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

          FetchWordEvent = Struct.new(:address, :word, keyword_init: true)
          FetchGroupEvent = Struct.new(:address, :bytes, keyword_init: true)
          FetchPcGroupEvent = Struct.new(:pc, :bytes, keyword_init: true)
          StepEvent = Struct.new(:eip, :consumed, :bytes, keyword_init: true)

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

          def clear_memory!
            @memory.clear
          end

          def load_bytes(base, bytes)
            Array(bytes).each_with_index do |byte, idx|
              @memory[base + idx] = byte.to_i & 0xFF
            end
          end

          def read_bytes(base, length)
            Array.new(length) { |idx| @memory[base + idx] || 0 }
          end

          def run_fetch_words(max_cycles: DEFAULT_MAX_CYCLES)
            raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
            raise "Verilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            @memory = read_memory_file(memory_path)
            parse_fetch_trace(stdout).map(&:word)
          end

          def run_fetch_trace(max_cycles: DEFAULT_MAX_CYCLES)
            raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
            raise "Verilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            @memory = read_memory_file(memory_path)
            parse_fetch_trace(stdout)
          end

          def run_fetch_groups(max_cycles: DEFAULT_MAX_CYCLES)
            run_fetch_trace(max_cycles: max_cycles).map do |event|
              FetchGroupEvent.new(
                address: event.address,
                bytes: word_to_bytes(event.word)
              )
            end
          end

          def run_fetch_pc_groups(max_cycles: DEFAULT_MAX_CYCLES)
            run_fetch_groups(max_cycles: max_cycles).map do |event|
              next if event.address < CpuParityRuntime::STARTUP_CS_BASE

              FetchPcGroupEvent.new(
                pc: event.address - CpuParityRuntime::STARTUP_CS_BASE,
                bytes: event.bytes
              )
            end.compact
          end

          def run_step_trace(max_cycles: DEFAULT_MAX_CYCLES)
            raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
            raise "Verilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            @memory = read_memory_file(memory_path)
            parse_step_trace(stdout)
          end

          def run_final_state(max_cycles: DEFAULT_MAX_CYCLES)
            raise 'Verilator binary not built' unless @binary_path && File.exist?(@binary_path)

            memory_path = File.join(@work_dir, 'memory_init.txt')
            write_memory_file(memory_path)

            stdout, stderr, status = Open3.capture3(@binary_path, memory_path, max_cycles.to_i.to_s)
            raise "Verilator parity runtime failed:\n#{stdout}\n#{stderr}" unless status.success?

            @memory = read_memory_file(memory_path)
            parse_final_state(stdout)
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

          def read_memory_file(path)
            mem = Hash.new(0)
            File.readlines(path, chomp: true).each do |line|
              next if line.empty?

              addr_hex, byte_hex = line.split(/\s+/, 2)
              next unless addr_hex && byte_hex

              mem[addr_hex.to_i(16)] = byte_hex.to_i(16) & 0xFF
            end
            mem
          end

          def parse_fetch_trace(stdout)
            stdout.lines.filter_map do |line|
              match = line.to_s.strip.match(/\Afetch_word 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              FetchWordEvent.new(
                address: match[1].to_i(16),
                word: match[2].to_i(16)
              )
            end
          end

          def parse_step_trace(stdout)
            stdout.lines.filter_map do |line|
              match = line.to_s.strip.match(/\Astep_trace 0x([0-9A-Fa-f]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              wr_eip = match[1].to_i(16)
              consumed = match[2].to_i(16)
              start_eip = wr_eip - consumed

              StepEvent.new(
                eip: start_eip,
                consumed: consumed,
                bytes: read_bytes(CpuParityRuntime::STARTUP_CS_BASE + start_eip, consumed)
              )
            end
          end

          def parse_final_state(stdout)
            stdout.lines.each_with_object({}) do |line, state|
              match = line.to_s.strip.match(/\Afinal_state ([A-Za-z0-9_]+) 0x([0-9A-Fa-f]+)\z/)
              next unless match

              state[match[1]] = match[2].to_i(16)
            end
          end

          def word_to_bytes(word)
            Array.new(4) { |idx| (word >> (idx * 8)) & 0xFF }
          end

          def verilator_harness_cpp
            <<~CPP
              #include "Vao486.h"
              #include "verilated.h"

              #include <cstdint>
              #include <cstdio>
              #include <cstdlib>
              #include <fstream>
              #include <iomanip>
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

              static void write_word(std::unordered_map<uint32_t, uint8_t>& mem, uint32_t addr, uint32_t word, uint32_t byteenable) {
                for (int idx = 0; idx < 4; ++idx) {
                  if (((byteenable >> idx) & 1u) == 0u) continue;
                  mem[addr + static_cast<uint32_t>(idx)] = static_cast<uint8_t>((word >> (idx * 8)) & 0xFFu);
                }
              }

              static void save_memory(const char* path, const std::unordered_map<uint32_t, uint8_t>& mem) {
                std::ofstream out(path, std::ios::trunc);
                if (!out) {
                  std::fprintf(stderr, "failed to write memory file: %s\\n", path);
                  std::exit(3);
                }

                out << std::uppercase << std::hex << std::setfill('0');
                for (const auto& entry : mem) {
                  out << std::setw(8) << static_cast<unsigned>(entry.first)
                      << ' '
                      << std::setw(2) << static_cast<unsigned>(entry.second)
                      << "\\n";
                }
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
                uint32_t prev_trace_wr_eip = 0;
                uint32_t prev_trace_wr_consumed = 0;

                auto emit_step_trace = [&]() {
                  if (dut->trace_retired &&
                      !(dut->trace_wr_eip == 0 && dut->trace_wr_consumed == 0) &&
                      !(dut->trace_wr_eip == prev_trace_wr_eip &&
                        dut->trace_wr_consumed == prev_trace_wr_consumed)) {
                    std::printf("step_trace 0x%08X 0x%08X\\n",
                                static_cast<uint32_t>(dut->trace_wr_eip),
                                static_cast<uint32_t>(dut->trace_wr_consumed));
                    prev_trace_wr_eip = static_cast<uint32_t>(dut->trace_wr_eip);
                    prev_trace_wr_consumed = static_cast<uint32_t>(dut->trace_wr_consumed);
                  }
                };

                for (int cycle = 0; cycle < max_cycles; ++cycle) {
                  bool deliver_read_beat =
                    burst.active &&
                    burst.started;
                  if (deliver_read_beat) {
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

                  if (!burst.active && dut->avm_read) {
                    burst.active = true;
                    burst.started = false;
                    burst.base = static_cast<uint32_t>(dut->avm_address) << 2;
                    burst.beat_index = 0;
                    burst.beats_total = dut->avm_burstcount > 0 ? dut->avm_burstcount : 1;
                  }

                  dut->clk = 1;
                  dut->rst_n = 1;
                  dut->eval();
                  emit_step_trace();

                  if (dut->avm_write) {
                    uint32_t addr = static_cast<uint32_t>(dut->avm_address) << 2;
                    write_word(mem, addr, static_cast<uint32_t>(dut->avm_writedata), static_cast<uint32_t>(dut->avm_byteenable));
                  }

                  if (burst.active) {
                    if (deliver_read_beat) {
                      uint32_t addr = burst.base + static_cast<uint32_t>(burst.beat_index * 4);
                      std::printf("fetch_word 0x%08X 0x%08X\\n", addr, static_cast<uint32_t>(dut->avm_readdata));
                      burst.beat_index += 1;
                      if (burst.beat_index >= burst.beats_total) burst.active = false;
                    } else {
                      burst.started = true;
                    }
                  }

                }

                save_memory(argv[1], mem);
                std::printf("final_state trace_arch_new_export 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_new_export));
                std::printf("final_state trace_arch_eax 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_eax));
                std::printf("final_state trace_arch_ebx 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_ebx));
                std::printf("final_state trace_arch_ecx 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_ecx));
                std::printf("final_state trace_arch_edx 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_edx));
                std::printf("final_state trace_arch_esi 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_esi));
                std::printf("final_state trace_arch_edi 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_edi));
                std::printf("final_state trace_arch_esp 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_esp));
                std::printf("final_state trace_arch_ebp 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_ebp));
                std::printf("final_state trace_arch_eip 0x%08X\\n", static_cast<uint32_t>(dut->trace_arch_eip));
                std::printf("final_state trace_wr_eip 0x%08X\\n", static_cast<uint32_t>(dut->trace_wr_eip));
                std::printf("final_state trace_wr_consumed 0x%08X\\n", static_cast<uint32_t>(dut->trace_wr_consumed));
                std::printf("final_state trace_wr_hlt_in_progress 0x%08X\\n", static_cast<uint32_t>(dut->trace_wr_hlt_in_progress));
                std::printf("final_state trace_wr_finished 0x%08X\\n", static_cast<uint32_t>(dut->trace_wr_finished));
                std::printf("final_state trace_wr_ready 0x%08X\\n", static_cast<uint32_t>(dut->trace_wr_ready));
                std::printf("final_state trace_retired 0x%08X\\n", static_cast<uint32_t>(dut->trace_retired));
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
