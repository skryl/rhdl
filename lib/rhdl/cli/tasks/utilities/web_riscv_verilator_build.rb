# frozen_string_literal: true

require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Builds a Verilator-compiled RISC-V WASM module for web benchmarking.
      #
      # Pipeline:
      #   RHDL -> Verilog -> Verilator C++ -> em++ -> riscv_verilator.wasm
      #
      # The produced module exports the lightweight sim_* ABI used by
      # web/bench/riscv_wasm_bench.mjs.
      module WebRiscvVerilatorBuild
        PROJECT_ROOT = File.expand_path('../../../..', __dir__)
        BUILD_DIR = File.join(PROJECT_ROOT, 'web', 'verilator', 'riscv_build')
        VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
        OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')
        VERILOG_FILE = File.join(VERILOG_DIR, 'riscv_cpu.v')
        WRAPPER_SOURCE = File.join(BUILD_DIR, 'riscv_verilator_wasm_wrapper.cpp')
        COMPAT_SOURCE = File.join(BUILD_DIR, 'riscv_verilator_wasm_compat.cpp')
        WASM_OUTPUT = File.join(BUILD_DIR, 'riscv_verilator.wasm')

        PKG_DIR = File.join(PROJECT_ROOT, 'web', 'assets', 'pkg')
        PKG_OUTPUT = File.join(PKG_DIR, 'riscv_verilator.wasm')

        DEFAULT_VERILATOR_ROOT = '/opt/homebrew/Cellar/verilator/5.044/share/verilator'

        TOP_MODULE = 'riscv_cpu'
        VERILATOR_PREFIX = 'Vriscv'

        DEFAULT_MEM_SIZE = 16 * 1024 * 1024

        REQUIRED_TOOLS = %w[verilator em++].freeze
        LINK_EXPORTS = %w[
          sim_create sim_destroy sim_reset sim_eval sim_poke sim_peek
          sim_write_pc sim_load_mem sim_read_mem_word sim_run_cycles
          sim_uart_rx_push sim_uart_tx_len sim_uart_tx_copy sim_uart_tx_clear
          sim_disk_load sim_disk_read_byte sim_wasm_alloc sim_wasm_dealloc
        ].freeze

        module_function

        # Build the Verilator RISC-V WASM module.
        # Returns true if built, false if skipped.
        def build(dest_dir: PKG_DIR)
          missing = missing_tools
          unless missing.empty?
            warn "WARNING: RISC-V verilator WASM build skipped; missing tools: #{missing.join(', ')}"
            return false
          end

          verilated_cpp, verilated_threads_cpp = verilated_runtime_sources
          unless File.file?(verilated_cpp) && File.file?(verilated_threads_cpp)
            warn "WARNING: verilator runtime sources not found under #{resolved_verilator_root}"
            return false
          end

          FileUtils.mkdir_p(BUILD_DIR)
          FileUtils.mkdir_p(VERILOG_DIR)
          FileUtils.mkdir_p(OBJ_DIR)
          FileUtils.mkdir_p(dest_dir)

          puts 'Building verilator RISC-V WASM module...'

          export_verilog
          generate_cpp_wrapper
          generate_compat_source
          generate_verilator_cpp
          objects = compile_objects
          link_wasm(objects)
          install_wasm(dest_dir)

          puts "  Wrote #{File.join(dest_dir, 'riscv_verilator.wasm')}"
          true
        end

        def missing_tools
          REQUIRED_TOOLS.select { |tool| !tool_available?(tool) }
        end

        def tools_available?
          missing_tools.empty?
        end

        def export_verilog
          puts '  Exporting RISC-V CPU to Verilog...'
          require File.join(PROJECT_ROOT, 'examples/riscv/hdl/cpu')

          verilog_code = RHDL::Examples::RISCV::CPU.to_verilog_hierarchy
          File.write(VERILOG_FILE, verilog_code)
        end

        def load_runner_cycle_sources
          require File.join(PROJECT_ROOT, 'examples/riscv/utilities/runners/verilator_runner')

          runner = RHDL::Examples::RISCV::VerilogRunner.allocate
          [runner.send(:riscv_sim_common_types), runner.send(:riscv_sim_run_cycles_impl)]
        end

        def build_wrapper_source
          common_types, run_cycles_impl = load_runner_cycle_sources

          <<~CPP
            #include "Vriscv.h"
            #include "Vriscv___024root.h"
            #include "verilated.h"

            #include <cstdint>
            #include <cstdlib>
            #include <cstring>

            double sc_time_stamp() { return 0; }

            #{common_types}

            struct SimContext {
              Vriscv* dut;
              MemState mem;
            };

            #define CTX(c) (static_cast<SimContext*>(c))
            #define DUT_CLK(c)                (CTX(c)->dut->clk)
            #define DUT_RST(c)                (CTX(c)->dut->rst)
            #define DUT_IRQ_SOFTWARE(c)       (CTX(c)->dut->irq_software)
            #define DUT_IRQ_TIMER(c)          (CTX(c)->dut->irq_timer)
            #define DUT_IRQ_EXTERNAL(c)       (CTX(c)->dut->irq_external)
            #define DUT_INST_DATA(c)          (CTX(c)->dut->inst_data)
            #define DUT_DATA_RDATA(c)         (CTX(c)->dut->data_rdata)
            #define DUT_DEBUG_REG_ADDR(c)     (CTX(c)->dut->debug_reg_addr)
            #define DUT_INST_PTW_PTE0(c)      (CTX(c)->dut->inst_ptw_pte0)
            #define DUT_INST_PTW_PTE1(c)      (CTX(c)->dut->inst_ptw_pte1)
            #define DUT_DATA_PTW_PTE0(c)      (CTX(c)->dut->data_ptw_pte0)
            #define DUT_DATA_PTW_PTE1(c)      (CTX(c)->dut->data_ptw_pte1)
            #define DUT_INST_ADDR(c)          (CTX(c)->dut->inst_addr)
            #define DUT_INST_PTW_ADDR0(c)     (CTX(c)->dut->inst_ptw_addr0)
            #define DUT_INST_PTW_ADDR1(c)     (CTX(c)->dut->inst_ptw_addr1)
            #define DUT_DATA_ADDR(c)          (CTX(c)->dut->data_addr)
            #define DUT_DATA_WDATA(c)         (CTX(c)->dut->data_wdata)
            #define DUT_DATA_WE(c)            (CTX(c)->dut->data_we)
            #define DUT_DATA_RE(c)            (CTX(c)->dut->data_re)
            #define DUT_DATA_FUNCT3(c)        (CTX(c)->dut->data_funct3)
            #define DUT_DATA_PTW_ADDR0(c)     (CTX(c)->dut->data_ptw_addr0)
            #define DUT_DATA_PTW_ADDR1(c)     (CTX(c)->dut->data_ptw_addr1)
            #define DUT_DEBUG_PC(c)           (CTX(c)->dut->debug_pc)
            #define DUT_EVAL(c)               (CTX(c)->dut->eval())
            #define DUT_PC_REG(c)             (CTX(c)->dut->rootp->riscv_cpu__DOT__pc_reg___05Fpc)

            #{run_cycles_impl}

            extern "C" {
            __attribute__((export_name("sim_wasm_alloc")))
            void* sim_wasm_alloc(uint32_t size) {
              return std::malloc(size > 0 ? size : 1);
            }

            __attribute__((export_name("sim_wasm_dealloc")))
            void sim_wasm_dealloc(void* ptr, uint32_t size) {
              (void)size;
              std::free(ptr);
            }

            __attribute__((export_name("sim_create")))
            void* sim_create(uint32_t mem_size) {
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);

              auto* ctx = new SimContext();
              ctx->dut = new Vriscv();

              uint32_t actual_mem = mem_size;
              if (actual_mem == 0u || (actual_mem & (actual_mem - 1u)) != 0u) {
                actual_mem = #{DEFAULT_MEM_SIZE};
              }
              mem_init(&ctx->mem, actual_mem);

              ctx->dut->clk = 0;
              ctx->dut->rst = 1;
              ctx->dut->irq_software = 0;
              ctx->dut->irq_timer = 0;
              ctx->dut->irq_external = 0;
              ctx->dut->inst_data = 0;
              ctx->dut->data_rdata = 0;
              ctx->dut->debug_reg_addr = 0;
              ctx->dut->inst_ptw_pte0 = 0;
              ctx->dut->inst_ptw_pte1 = 0;
              ctx->dut->data_ptw_pte0 = 0;
              ctx->dut->data_ptw_pte1 = 0;
              ctx->dut->eval();
              return ctx;
            }

            __attribute__((export_name("sim_destroy")))
            void sim_destroy(void* sim) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              mem_free(&ctx->mem);
              delete ctx->dut;
              delete ctx;
            }

            __attribute__((export_name("sim_reset")))
            void sim_reset(void* sim) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !ctx->dut) return;
              ctx->dut->rst = 1;
              ctx->dut->clk = 0;
              ctx->dut->eval();
              ctx->dut->clk = 1;
              ctx->dut->eval();
              ctx->dut->clk = 0;
              ctx->dut->rst = 0;
              ctx->dut->eval();
            }

            __attribute__((export_name("sim_eval")))
            void sim_eval(void* sim) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !ctx->dut) return;
              ctx->dut->eval();
            }

            __attribute__((export_name("sim_poke")))
            void sim_poke(void* sim, const char* name, uint32_t value) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !ctx->dut || !name) return;
              if      (!std::strcmp(name, "clk"))             ctx->dut->clk = value;
              else if (!std::strcmp(name, "rst"))             ctx->dut->rst = value;
              else if (!std::strcmp(name, "irq_software"))    ctx->dut->irq_software = value;
              else if (!std::strcmp(name, "irq_timer"))       ctx->dut->irq_timer = value;
              else if (!std::strcmp(name, "irq_external"))    ctx->dut->irq_external = value;
              else if (!std::strcmp(name, "inst_data"))       ctx->dut->inst_data = value;
              else if (!std::strcmp(name, "data_rdata"))      ctx->dut->data_rdata = value;
              else if (!std::strcmp(name, "debug_reg_addr"))  ctx->dut->debug_reg_addr = value;
              else if (!std::strcmp(name, "inst_ptw_pte0"))   ctx->dut->inst_ptw_pte0 = value;
              else if (!std::strcmp(name, "inst_ptw_pte1"))   ctx->dut->inst_ptw_pte1 = value;
              else if (!std::strcmp(name, "data_ptw_pte0"))   ctx->dut->data_ptw_pte0 = value;
              else if (!std::strcmp(name, "data_ptw_pte1"))   ctx->dut->data_ptw_pte1 = value;
            }

            __attribute__((export_name("sim_peek")))
            uint32_t sim_peek(void* sim, const char* name) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !ctx->dut || !name) return 0;
              if      (!std::strcmp(name, "inst_addr"))       return ctx->dut->inst_addr;
              else if (!std::strcmp(name, "inst_ptw_addr0"))  return ctx->dut->inst_ptw_addr0;
              else if (!std::strcmp(name, "inst_ptw_addr1"))  return ctx->dut->inst_ptw_addr1;
              else if (!std::strcmp(name, "data_addr"))       return ctx->dut->data_addr;
              else if (!std::strcmp(name, "data_wdata"))      return ctx->dut->data_wdata;
              else if (!std::strcmp(name, "data_we"))         return ctx->dut->data_we;
              else if (!std::strcmp(name, "data_re"))         return ctx->dut->data_re;
              else if (!std::strcmp(name, "data_funct3"))     return ctx->dut->data_funct3;
              else if (!std::strcmp(name, "data_ptw_addr0"))  return ctx->dut->data_ptw_addr0;
              else if (!std::strcmp(name, "data_ptw_addr1"))  return ctx->dut->data_ptw_addr1;
              else if (!std::strcmp(name, "debug_pc"))        return ctx->dut->debug_pc;
              else if (!std::strcmp(name, "debug_inst"))      return ctx->dut->debug_inst;
              else if (!std::strcmp(name, "debug_x1"))        return ctx->dut->debug_x1;
              else if (!std::strcmp(name, "debug_x2"))        return ctx->dut->debug_x2;
              else if (!std::strcmp(name, "debug_x10"))       return ctx->dut->debug_x10;
              else if (!std::strcmp(name, "debug_x11"))       return ctx->dut->debug_x11;
              else if (!std::strcmp(name, "debug_reg_data"))  return ctx->dut->debug_reg_data;
              return 0;
            }

            __attribute__((export_name("sim_write_pc")))
            void sim_write_pc(void* sim, uint32_t value) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx || !ctx->dut) return;
              DUT_PC_REG(ctx) = value;
              ctx->dut->eval();
            }

            __attribute__((export_name("sim_load_mem")))
            void sim_load_mem(void* sim, int32_t mem_type, const uint8_t* data, uint32_t size, uint32_t base_addr) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              load_mem(&ctx->mem, mem_type, data, size, base_addr);
            }

            __attribute__((export_name("sim_read_mem_word")))
            uint32_t sim_read_mem_word(void* sim, int32_t mem_type, uint32_t addr) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              const uint8_t* mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
              return read_word_le(mem, ctx->mem.mem_mask, addr);
            }

            __attribute__((export_name("sim_run_cycles")))
            void sim_run_cycles(void* sim, uint32_t n_cycles) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              run_cycles_impl(ctx, &ctx->mem, n_cycles);
            }

            __attribute__((export_name("sim_uart_rx_push")))
            void sim_uart_rx_push(void* sim, const uint8_t* data, uint32_t len) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              uart_rx_queue_push_bytes(&ctx->mem, data, len);
            }

            __attribute__((export_name("sim_uart_tx_len")))
            uint32_t sim_uart_tx_len(void* sim) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              return uart_tx_len(&ctx->mem);
            }

            __attribute__((export_name("sim_uart_tx_copy")))
            uint32_t sim_uart_tx_copy(void* sim, uint8_t* out, uint32_t max_len) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              return uart_tx_copy(&ctx->mem, out, max_len);
            }

            __attribute__((export_name("sim_uart_tx_clear")))
            void sim_uart_tx_clear(void* sim) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return;
              uart_tx_clear(&ctx->mem);
            }

            __attribute__((export_name("sim_disk_load")))
            uint32_t sim_disk_load(void* sim, const uint8_t* data, uint32_t size, uint32_t base_addr) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              return static_cast<uint32_t>(disk_load(&ctx->mem, data, size, base_addr));
            }

            __attribute__((export_name("sim_disk_read_byte")))
            uint32_t sim_disk_read_byte(void* sim, uint32_t offset) {
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) return 0;
              return static_cast<uint32_t>(disk_read_byte(&ctx->mem, offset));
            }
            } // extern "C"
          CPP
        end

        def generate_cpp_wrapper
          File.write(WRAPPER_SOURCE, build_wrapper_source)
        end

        def generate_compat_source
          source = <<~CPP
            #include <pthread.h>
            #include <sched.h>
            #include <stddef.h>

            extern "C" int pthread_getaffinity_np(pthread_t thread, size_t cpusetsize, cpu_set_t* cpuset) {
              (void)thread;
              (void)cpusetsize;
              (void)cpuset;
              return 0;
            }

            extern "C" int pthread_setaffinity_np(pthread_t thread, size_t cpusetsize, const cpu_set_t* cpuset) {
              (void)thread;
              (void)cpusetsize;
              (void)cpuset;
              return 0;
            }

            extern "C" int sched_getcpu(void) {
              return 0;
            }
          CPP
          File.write(COMPAT_SOURCE, source)
        end

        def generate_verilator_cpp
          puts '  Generating Verilator C++ model...'
          run_tool!(
            'verilator',
            '--cc', VERILOG_FILE,
            '--top-module', TOP_MODULE,
            '--Mdir', OBJ_DIR,
            '--prefix', VERILATOR_PREFIX,
            '--x-assign', '0',
            '--x-initial', '0',
            '--noassert',
            '-O3',
            '-Wno-fatal'
          )
        end

        def compile_objects
          puts '  Compiling Verilator C++ to WASM objects...'
          generated_sources = Dir.glob(File.join(OBJ_DIR, "#{VERILATOR_PREFIX}*.cpp")).sort
          raise "No generated Verilator C++ files found in #{OBJ_DIR}" if generated_sources.empty?

          verilated_cpp, verilated_threads_cpp = verilated_runtime_sources
          sources = [WRAPPER_SOURCE, COMPAT_SOURCE, verilated_cpp, verilated_threads_cpp] + generated_sources
          sources.map do |source|
            object = source.sub(/\.cpp\z/, '.o')
            compile_cpp_to_obj(source, object)
            object
          end
        end

        def compile_cpp_to_obj(source, object)
          include_flags = [
            "-I#{OBJ_DIR}",
            "-I#{File.join(resolved_verilator_root, 'include')}",
            "-I#{File.join(resolved_verilator_root, 'include', 'vltstd')}"
          ]
          run_tool!(
            'em++',
            *include_flags,
            '-O2',
            '-frtti',
            '-DVL_IGNORE_UNKNOWN_ARCH',
            '-fno-stack-protector',
            '-c', source,
            '-o', object
          )
        end

        def link_wasm(objects)
          puts '  Linking WASM module...'
          export_flags = LINK_EXPORTS.flat_map { |name| ["-Wl,--export=#{name}"] }
          run_tool!(
            'em++',
            '-O2',
            '-Wl,--no-entry',
            '-Wl,--export-memory',
            '-Wl,--initial-memory=134217728',
            '-sALLOW_MEMORY_GROWTH=1',
            '-sASSERTIONS=0',
            *export_flags,
            '-o', WASM_OUTPUT,
            *objects
          )
        end

        def install_wasm(dest_dir)
          FileUtils.mkdir_p(dest_dir)
          FileUtils.cp(WASM_OUTPUT, File.join(dest_dir, 'riscv_verilator.wasm'))
        end

        def resolved_verilator_root
          @resolved_verilator_root ||= begin
            env_root = ENV.fetch('VERILATOR_ROOT', '').strip
            if env_root.empty?
              output = `verilator -V 2>&1`
              line = output.lines.find { |entry| entry.include?('VERILATOR_ROOT') && entry.include?('=') }
              parsed = line&.split('=', 2)&.last&.strip
              parsed.nil? || parsed.empty? ? DEFAULT_VERILATOR_ROOT : parsed
            else
              env_root
            end
          end
        end

        def verilated_runtime_sources
          root = resolved_verilator_root
          [File.join(root, 'include', 'verilated.cpp'), File.join(root, 'include', 'verilated_threads.cpp')]
        end

        def run_tool!(*args)
          ok = system(*args)
          return if ok

          raise "Command failed: #{args.join(' ')}"
        end

        def tool_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            File.executable?(File.join(dir, tool))
          end
        end
      end
    end
  end
end
