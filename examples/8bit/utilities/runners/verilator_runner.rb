# frozen_string_literal: true

require 'fileutils'
require 'fiddle'
require 'open3'
require 'rbconfig'
require 'rhdl/codegen'
require 'rhdl/codegen/verilog/sim/verilog_simulator'
require_relative '../../hdl/cpu/cpu'

module RHDL
  module Examples
    module CPU8Bit
      # Native runner for 8-bit CPU using Verilator.
      #
      # Pipeline:
      #   RHDL CPU -> Verilog -> Verilator C++ -> shared library -> Fiddle
      class VerilatorRunner
        BUILD_DIR = File.expand_path('../../.verilator_build', __dir__)
        LIB_BASENAME = 'cpu8bit_verilator_sim'
        TOP_MODULE = 'cpu8bit'
        VERILATOR_PREFIX = 'Vcpu8bit'
        REQUIRED_TOOLS = %w[firtool verilator make].freeze

        attr_reader :backend

        def self.status
          missing_tools = REQUIRED_TOOLS.reject { |tool| command_available?(tool) }
          missing_tools << 'c++/clang++/g++' unless command_available?('c++') || command_available?('clang++') || command_available?('g++')
          {
            ready: missing_tools.empty?,
            missing_tools: missing_tools.uniq,
            missing_capabilities: []
          }
        end

        def self.ensure_available!
          info = status
          return info if info[:ready]

          details = []
          details << "missing tools: #{info[:missing_tools].join(', ')}" unless info[:missing_tools].empty?
          details << "missing capabilities: #{info[:missing_capabilities].join(', ')}" unless info[:missing_capabilities].empty?
          raise ArgumentError,
            "verilator backend unavailable (#{details.join('; ')}). " \
            "Install required verilator/make/C++ toolchain tools."
        end

        def initialize
          @backend = :verilator
          self.class.ensure_available!
          build_simulation
          load_library
          reset
        end

        def native?
          true
        end

        def runner_mode?
          true
        end

        def runner_kind
          :cpu8bit
        end

        def evaluate
          @fn_sim_eval.call(@ctx)
          nil
        end

        def reset
          @fn_sim_reset.call(@ctx)
          nil
        end

        def poke(name, value)
          @fn_sim_poke.call(@ctx, name.to_s, value.to_i & 0xFFFF_FFFF)
          true
        end

        def peek(name)
          @fn_sim_peek.call(@ctx, name.to_s) & 0xFFFF_FFFF
        end

        def runner_load_memory(data, offset = 0, _is_rom = false)
          payload = normalize_payload(data)
          return false if payload.empty?

          ptr = Fiddle::Pointer[payload]
          loaded = @fn_runner_load_memory.call(@ctx, ptr, payload.bytesize, offset.to_i & 0xFFFF)
          loaded.to_i.positive?
        end

        def runner_read_memory(offset, length, mapped: true)
          _ = mapped
          len = [length.to_i, 0].max
          return [] if len.zero?

          out = Fiddle::Pointer.malloc(len)
          read_len = @fn_runner_read_memory.call(@ctx, offset.to_i & 0xFFFF, len, out).to_i
          return [] if read_len <= 0

          out[0, read_len].unpack('C*')
        end

        def runner_write_memory(offset, data, mapped: true)
          _ = mapped
          payload = normalize_payload(data)
          return 0 if payload.empty?

          ptr = Fiddle::Pointer[payload]
          @fn_runner_write_memory.call(@ctx, offset.to_i & 0xFFFF, ptr, payload.bytesize).to_i
        end

        def runner_run_cycles(n, _key_data = 0, _key_ready = false)
          cycles = @fn_runner_run_cycles.call(@ctx, [n.to_i, 0].max).to_i
          {
            text_dirty: false,
            key_cleared: false,
            cycles_run: cycles,
            speaker_toggles: 0
          }
        end

        private

        def self.command_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, tool))
          end
        end

        def verilog_simulator
          @verilog_simulator ||= RHDL::Codegen::Verilog::VerilogSimulator.new(
            backend: :verilator,
            build_dir: BUILD_DIR,
            library_basename: LIB_BASENAME,
            top_module: TOP_MODULE,
            verilator_prefix: VERILATOR_PREFIX,
            x_assign: '0',
            x_initial: '0'
          )
        end

        def build_simulation
          verilog_simulator.ensure_backend_available!
          verilog_simulator.prepare_build_dirs!

          fir_file = File.join(BUILD_DIR, 'cpu8bit.fir')
          verilog_file = File.join(verilog_simulator.verilog_dir, 'cpu8bit.v')
          wrapper_file = File.join(verilog_simulator.verilog_dir, 'sim_wrapper.cpp')
          header_file = File.join(verilog_simulator.verilog_dir, 'sim_wrapper.h')
          lib_file = verilog_simulator.shared_library_path
          log_file = File.join(BUILD_DIR, 'cpu8bit_verilator.log')

          firrtl_changed = verilog_simulator.write_file_if_changed(
            fir_file,
            RHDL::Codegen::CIRCT::FIRRTL.generate(RHDL::HDL::CPU::CPU.to_flat_ir(top_name: TOP_MODULE))
          )
          verilog_regen_needed = firrtl_changed || !File.exist?(verilog_file)
          verilog_regen_needed ||= File.exist?(verilog_file) && File.mtime(fir_file) > File.mtime(verilog_file)
          if verilog_regen_needed
            run_or_raise(%W[firtool #{fir_file} --verilog -o #{verilog_file}], 'firtool Verilog lowering', log_file)
          end

          wrapper_changed = create_cpp_wrapper(wrapper_file, header_file)

          needs_build = !File.exist?(lib_file)
          if File.exist?(lib_file)
            needs_build ||= File.mtime(verilog_file) > File.mtime(lib_file)
            needs_build ||= File.mtime(wrapper_file) > File.mtime(lib_file)
            needs_build ||= File.mtime(__FILE__) > File.mtime(lib_file)
          end
          needs_build ||= verilog_regen_needed || wrapper_changed

          if needs_build
            verilog_simulator.compile_backend(
              verilog_file: verilog_file,
              wrapper_file: wrapper_file,
              log_file: log_file
            )
          end
        end

        def create_cpp_wrapper(cpp_file, header_file)
          header_content = <<~HEADER
            #ifndef SIM_WRAPPER_H
            #define SIM_WRAPPER_H

            #ifdef __cplusplus
            extern "C" {
            #endif

            void* sim_create(void);
            void sim_destroy(void* sim);
            void sim_eval(void* sim);
            void sim_reset(void* sim);
            void sim_poke(void* sim, const char* name, unsigned int value);
            unsigned int sim_peek(void* sim, const char* name);
            unsigned int sim_runner_load_memory(void* sim, const unsigned char* data, unsigned int len, unsigned int offset);
            unsigned int sim_runner_read_memory(void* sim, unsigned int offset, unsigned int len, unsigned char* out);
            unsigned int sim_runner_write_memory(void* sim, unsigned int offset, const unsigned char* data, unsigned int len);
            unsigned int sim_runner_run_cycles(void* sim, unsigned int n);

            #ifdef __cplusplus
            }
            #endif

            #endif
          HEADER

          cpp_content = <<~CPP
            #include "#{VERILATOR_PREFIX}.h"
            #include "verilated.h"
            #include "sim_wrapper.h"
            #include <cstdint>
            #include <cstring>

            double sc_time_stamp() { return 0; }

            struct SimContext {
              #{VERILATOR_PREFIX}* dut;
              std::uint8_t memory[65536];
            };

            static inline unsigned int run_cycles_internal(SimContext* ctx, unsigned int n) {
              for (unsigned int i = 0; i < n; ++i) {
                if (ctx->dut->halted) {
                  return i;
                }

                ctx->dut->clk = 0;
                ctx->dut->eval();

                unsigned int addr = ctx->dut->mem_addr & 0xFFFFu;
                if (ctx->dut->mem_write_en) {
                  ctx->memory[addr] = static_cast<std::uint8_t>(ctx->dut->mem_data_out & 0xFFu);
                }
                ctx->dut->mem_data_in = ctx->memory[addr];
                ctx->dut->eval();

                ctx->dut->clk = 1;
                ctx->dut->eval();
                if (ctx->dut->halted) {
                  return i + 1;
                }
              }
              return n;
            }

            extern "C" {

            void* sim_create(void) {
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);
              Verilated::randReset(0);
              SimContext* ctx = new SimContext();
              ctx->dut = new #{VERILATOR_PREFIX}();
              std::memset(ctx->memory, 0, sizeof(ctx->memory));
              ctx->dut->clk = 0;
              ctx->dut->rst = 1;
              ctx->dut->mem_data_in = 0;
              ctx->dut->eval();
              return ctx;
            }

            void sim_destroy(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              delete ctx->dut;
              delete ctx;
            }

            void sim_eval(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->eval();
            }

            void sim_reset(void* sim) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              ctx->dut->rst = 1;
              run_cycles_internal(ctx, 1);
              ctx->dut->rst = 0;
              ctx->dut->eval();
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (std::strcmp(name, "clk") == 0) ctx->dut->clk = value & 1u;
              else if (std::strcmp(name, "rst") == 0) ctx->dut->rst = value & 1u;
              else if (std::strcmp(name, "mem_data_in") == 0) ctx->dut->mem_data_in = value & 0xFFu;
            }

            unsigned int sim_peek(void* sim, const char* name) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              if (std::strcmp(name, "mem_addr") == 0) return ctx->dut->mem_addr;
              if (std::strcmp(name, "mem_data_out") == 0) return ctx->dut->mem_data_out;
              if (std::strcmp(name, "mem_write_en") == 0) return ctx->dut->mem_write_en;
              if (std::strcmp(name, "halted") == 0) return ctx->dut->halted;
              if (std::strcmp(name, "pc_out") == 0) return ctx->dut->pc_out;
              if (std::strcmp(name, "acc_out") == 0) return ctx->dut->acc_out;
              if (std::strcmp(name, "sp_out") == 0) return ctx->dut->sp_out;
              if (std::strcmp(name, "state_out") == 0) return ctx->dut->state_out;
              if (std::strcmp(name, "zero_flag_out") == 0) return ctx->dut->zero_flag_out;
              return 0;
            }

            unsigned int sim_runner_load_memory(void* sim, const unsigned char* data, unsigned int len, unsigned int offset) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              unsigned int loaded = 0;
              for (unsigned int i = 0; i < len; ++i) {
                unsigned int addr = (offset + i) & 0xFFFFu;
                ctx->memory[addr] = data[i];
                loaded++;
              }
              return loaded;
            }

            unsigned int sim_runner_read_memory(void* sim, unsigned int offset, unsigned int len, unsigned char* out) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                unsigned int addr = (offset + i) & 0xFFFFu;
                out[i] = ctx->memory[addr];
              }
              return len;
            }

            unsigned int sim_runner_write_memory(void* sim, unsigned int offset, const unsigned char* data, unsigned int len) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              for (unsigned int i = 0; i < len; ++i) {
                unsigned int addr = (offset + i) & 0xFFFFu;
                ctx->memory[addr] = data[i];
              }
              return len;
            }

            unsigned int sim_runner_run_cycles(void* sim, unsigned int n) {
              SimContext* ctx = static_cast<SimContext*>(sim);
              return run_cycles_internal(ctx, n);
            }

            }
          CPP

          header_changed = verilog_simulator.write_file_if_changed(header_file, header_content)
          cpp_changed = verilog_simulator.write_file_if_changed(cpp_file, cpp_content)
          header_changed || cpp_changed
        end

        def load_library
          @lib = verilog_simulator.load_library!(verilog_simulator.shared_library_path)
          @fn_sim_create = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
          @fn_sim_destroy = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_eval = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_reset = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @fn_sim_poke = Fiddle::Function.new(@lib['sim_poke'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT], Fiddle::TYPE_VOID)
          @fn_sim_peek = Fiddle::Function.new(@lib['sim_peek'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_UINT)
          @fn_runner_load_memory = Fiddle::Function.new(
            @lib['sim_runner_load_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )
          @fn_runner_read_memory = Fiddle::Function.new(
            @lib['sim_runner_read_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_UINT
          )
          @fn_runner_write_memory = Fiddle::Function.new(
            @lib['sim_runner_write_memory'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )
          @fn_runner_run_cycles = Fiddle::Function.new(
            @lib['sim_runner_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_UINT],
            Fiddle::TYPE_UINT
          )

          @ctx = @fn_sim_create.call
          ObjectSpace.define_finalizer(self, self.class.finalizer(@fn_sim_destroy, @ctx))
        end

        def run_or_raise(cmd, step_name, log_file)
          out, status = Open3.capture2e(*cmd)
          File.write(log_file, out, mode: 'a')
          return if status.success?

          raise LoadError, "#{step_name} failed"
        end

        def self.finalizer(destroy_fn, ctx)
          proc { destroy_fn.call(ctx) if ctx && !ctx.to_i.zero? }
        end

        def normalize_payload(data)
          case data
          when String
            data.b
          when Array
            data.pack('C*')
          else
            Array(data).pack('C*')
          end
        end
      end
    end
  end
end
