# frozen_string_literal: true

require 'open3'
require 'fileutils'

require 'rhdl/codegen'
require_relative 'cpu_parity_package'
require_relative 'cpu_parity_runtime'

module RHDL
  module Examples
    module AO486
      module Import
        # Verilator-side runtime helper for the parity-oriented imported AO486 CPU package.
        #
        # This runner intentionally mirrors the no-wait Avalon read-burst timing used by
        # CpuParityRuntime so the first reset-vector fetch words can be compared directly
        # between Verilator and IR JIT on the same canonical parity package.
        class CpuParityVerilatorRuntime
          RESET_VECTOR_PHYSICAL = CpuParityRuntime::RESET_VECTOR_PHYSICAL
          DEFAULT_MAX_CYCLES = CpuParityRuntime::DEFAULT_MAX_CYCLES

          attr_reader :binary_path, :memory

          def self.build_from_cleaned_mlir(mlir_text, work_dir:)
            parity = CpuParityPackage.from_cleaned_mlir(mlir_text)
            raise ArgumentError, Array(parity[:diagnostics]).join("\n") unless parity[:success]

            new(work_dir: work_dir).tap do |runner|
              runner.send(:build!, parity.fetch(:mlir))
            end
          end

          def initialize(work_dir:)
            @work_dir = File.expand_path(work_dir)
            @memory = Hash.new(0)
            @binary_path = nil
          end

          def load_bytes(base, bytes)
            Array(bytes).each_with_index do |byte, idx|
              @memory[base + idx] = byte.to_i & 0xFF
            end
          end

          def run_fetch_words(max_cycles: DEFAULT_MAX_CYCLES)
            raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
            raise "Verilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            parse_fetch_words(stdout)
          end

          private

          def build!(mlir_text)
            FileUtils.mkdir_p(@work_dir)

            mlir_path = File.join(@work_dir, 'cpu_parity.mlir')
            verilog_path = File.join(@work_dir, 'cpu_parity.v')
            cpp_path = File.join(@work_dir, 'cpu_parity_tb.cpp')
            obj_dir = File.join(@work_dir, 'obj_dir')

            File.write(mlir_path, mlir_text)

            firtool_stdout, firtool_stderr, firtool_status = Open3.capture3(
              'firtool',
              mlir_path,
              '--verilog',
              '-o',
              verilog_path
            )
            unless firtool_status.success?
              raise "firtool export failed:\n#{firtool_stdout}\n#{firtool_stderr}"
            end

            File.write(cpp_path, verilator_harness_cpp)

            verilator_cmd = [
              'verilator',
              '--cc',
              '--top-module', 'ao486',
              '--x-assign', '0',
              '--x-initial', '0',
              '-Wno-fatal',
              '-Wno-UNOPTFLAT',
              '-Wno-PINMISSING',
              '-Wno-WIDTHEXPAND',
              '-Wno-WIDTHTRUNC',
              '--Mdir', obj_dir,
              verilog_path,
              '--exe', cpp_path
            ]
            stdout, stderr, status = Open3.capture3(*verilator_cmd)
            raise "Verilator compile failed:\n#{stdout}\n#{stderr}" unless status.success?

            make_stdout, make_stderr, make_status = Open3.capture3('make', '-C', obj_dir, '-f', 'Vao486.mk')
            raise "Verilator make failed:\n#{make_stdout}\n#{make_stderr}" unless make_status.success?

            @binary_path = File.join(obj_dir, 'Vao486')
          end

          def write_memory_file(path)
            lines = @memory.keys.sort.map do |addr|
              format('%08X %02X', addr, @memory.fetch(addr))
            end
            File.write(path, lines.join("\n") + "\n")
          end

          def parse_fetch_words(stdout)
            stdout.lines.filter_map do |line|
              next unless (match = line.to_s.strip.match(/\Afetch_word 0x([0-9A-Fa-f]+)\z/))

              match[1].to_i(16)
            end
          end

          def verilator_harness_cpp
            <<~CPP
              #include "Vao486.h"
              #include "verilated.h"

              #include <cstdint>
              #include <cstdio>
              #include <cstdlib>
              #include <fstream>
              #include <string>
              #include <unordered_map>

              struct BurstState {
                bool active = false;
                bool started = false;
                uint32_t base = 0;
                int beat_index = 0;
                int beats_total = 8;
              };

              static std::unordered_map<uint32_t, uint8_t> load_memory(const char* path) {
                std::unordered_map<uint32_t, uint8_t> mem;
                std::ifstream in(path);
                if (!in) {
                  std::fprintf(stderr, "failed to open memory file: %s\\n", path);
                  std::exit(2);
                }

                uint32_t addr = 0;
                unsigned value = 0;
                while (in >> std::hex >> addr >> value) {
                  mem[addr] = static_cast<uint8_t>(value & 0xFFu);
                }
                return mem;
              }

              static uint32_t little_endian_word(const std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr) {
                uint32_t word = 0;
                for (int idx = 0; idx < 4; ++idx) {
                  auto it = mem.find(addr + static_cast<uint32_t>(idx));
                  uint32_t byte = (it == mem.end()) ? 0u : static_cast<uint32_t>(it->second);
                  word |= (byte << (idx * 8));
                }
                return word;
              }

              static void apply_defaults(Vao486* dut) {
                dut->a20_enable = 1;
                dut->cache_disable = 1;
                dut->interrupt_do = 0;
                dut->interrupt_vector = 0;
                dut->avm_waitrequest = 0;
                dut->avm_readdatavalid = 0;
                dut->avm_readdata = 0;
                dut->dma_address = 0;
                dut->dma_16bit = 0;
                dut->dma_write = 0;
                dut->dma_writedata = 0;
                dut->dma_read = 0;
                dut->io_read_data = 0;
                dut->io_read_done = 0;
                dut->io_write_done = 0;
              }

              int main(int argc, char** argv) {
                if (argc < 3) {
                  std::fprintf(stderr, "usage: %s <memory_init.txt> <max_cycles>\\n", argv[0]);
                  return 2;
                }

                Verilated::commandArgs(argc, argv);
                auto mem = load_memory(argv[1]);
                int max_cycles = std::atoi(argv[2]);

                Vao486* dut = new Vao486();
                apply_defaults(dut);

                dut->clk = 0;
                dut->rst_n = 0;
                dut->eval();
                dut->clk = 1;
                dut->eval();

                BurstState burst;

                for (int cycle = 0; cycle < max_cycles; ++cycle) {
                  if (burst.active && burst.started) {
                    uint32_t addr = burst.base + static_cast<uint32_t>(burst.beat_index * 4);
                    dut->avm_readdatavalid = 1;
                    dut->avm_readdata = little_endian_word(mem, addr);
                  } else {
                    dut->avm_readdatavalid = 0;
                    dut->avm_readdata = 0;
                  }

                  dut->clk = 0;
                  dut->rst_n = 1;
                  dut->eval();

                  dut->clk = 1;
                  dut->rst_n = 1;
                  dut->eval();

                  if (burst.active) {
                    if (burst.started) {
                      std::printf("fetch_word 0x%08X\\n", static_cast<uint32_t>(dut->avm_readdata));
                      burst.beat_index += 1;
                      if (burst.beat_index >= burst.beats_total) burst.active = false;
                    } else {
                      burst.started = true;
                    }
                  }

                  if (!burst.active && dut->avm_read) {
                    burst.active = true;
                    burst.started = false;
                    burst.base = static_cast<uint32_t>(dut->avm_address) << 2;
                    burst.beat_index = 0;
                    burst.beats_total = 8;
                  }
                }

                dut->final();
                delete dut;
                return 0;
              }
            CPP
          end
        end
      end
    end
  end
end
