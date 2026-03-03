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
        PROJECT_ROOT = File.expand_path('../../../../..', __dir__)
        BUILD_DIR = File.join(PROJECT_ROOT, 'web', 'build', 'verilator', 'riscv_build')
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

        # Match the canonical RISC-V headless runner RAM size so linux_kernel +
        # initramfs + dtb/bootstrap load addresses fit without aliasing.
        DEFAULT_MEM_SIZE = 128 * 1024 * 1024

        REQUIRED_TOOLS = %w[verilator em++].freeze
        LINK_EXPORTS = %w[
          sim_create sim_destroy sim_reset sim_eval sim_poke sim_peek
          sim_write_pc sim_load_mem sim_read_mem_word sim_run_cycles
          sim_uart_rx_push sim_uart_tx_len sim_uart_tx_copy sim_uart_tx_clear
          sim_disk_load sim_disk_read_byte sim_wasm_alloc sim_wasm_dealloc
          sim_get_caps sim_signal sim_exec sim_trace sim_blob
          runner_get_caps runner_mem runner_run runner_control runner_probe
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
              uint8_t trace_enabled;
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

            #define SIM_CAP_SIGNAL_INDEX      (1u << 0)
            #define SIM_CAP_TRACE             (1u << 2)
            #define SIM_CAP_RUNNER_INTERP_JIT (1u << 4)

            #define SIM_SIGNAL_HAS        0u
            #define SIM_SIGNAL_GET_INDEX  1u
            #define SIM_SIGNAL_PEEK       2u
            #define SIM_SIGNAL_POKE       3u
            #define SIM_SIGNAL_PEEK_INDEX 4u
            #define SIM_SIGNAL_POKE_INDEX 5u

            #define SIM_EXEC_EVALUATE       0u
            #define SIM_EXEC_TICK           1u
            #define SIM_EXEC_TICK_FORCED    2u
            #define SIM_EXEC_SET_PREV_CLOCK 3u
            #define SIM_EXEC_GET_CLOCK_LIST_IDX 4u
            #define SIM_EXEC_RESET          5u
            #define SIM_EXEC_RUN_TICKS      6u
            #define SIM_EXEC_SIGNAL_COUNT   7u
            #define SIM_EXEC_REG_COUNT      8u
            #define SIM_EXEC_COMPILE        9u
            #define SIM_EXEC_IS_COMPILED    10u

            #define SIM_TRACE_START             0u
            #define SIM_TRACE_START_STREAMING   1u
            #define SIM_TRACE_STOP              2u
            #define SIM_TRACE_ENABLED           3u
            #define SIM_TRACE_CAPTURE           4u
            #define SIM_TRACE_ADD_SIGNAL        5u
            #define SIM_TRACE_ADD_SIGNALS_MATCHING 6u
            #define SIM_TRACE_ALL_SIGNALS       7u
            #define SIM_TRACE_CLEAR_SIGNALS     8u
            #define SIM_TRACE_CLEAR             9u
            #define SIM_TRACE_CHANGE_COUNT      10u
            #define SIM_TRACE_SIGNAL_COUNT      11u
            #define SIM_TRACE_SET_TIMESCALE     12u
            #define SIM_TRACE_SET_MODULE_NAME   13u
            #define SIM_TRACE_SAVE_VCD          14u

            #define SIM_BLOB_INPUT_NAMES       0u
            #define SIM_BLOB_OUTPUT_NAMES      1u
            #define SIM_BLOB_TRACE_TO_VCD      2u
            #define SIM_BLOB_TRACE_TAKE_LIVE_VCD 3u
            #define SIM_BLOB_GENERATED_CODE    4u

            #define RUNNER_KIND_RISCV          5

            #define RUNNER_MEM_OP_LOAD         0u
            #define RUNNER_MEM_OP_READ         1u
            #define RUNNER_MEM_OP_WRITE        2u

            #define RUNNER_MEM_SPACE_MAIN      0u
            #define RUNNER_MEM_SPACE_ROM       1u
            #define RUNNER_MEM_SPACE_DISK      7u
            #define RUNNER_MEM_SPACE_UART_TX   8u
            #define RUNNER_MEM_SPACE_UART_RX   9u
            #define RUNNER_MEM_FLAG_MAPPED     1u

            #define RUNNER_CONTROL_SET_RESET_VECTOR 0u
            #define RUNNER_CONTROL_CLEAR_UART_TX    6u

            #define RUNNER_PROBE_KIND              0u
            #define RUNNER_PROBE_IS_MODE           1u
            #define RUNNER_PROBE_SIGNAL            9u
            #define RUNNER_PROBE_RISCV_UART_TX_LEN 17u

            static const char* k_input_signal_names[] = {
              "clk", "rst", "irq_software", "irq_timer", "irq_external",
              "inst_data", "data_rdata", "debug_reg_addr",
              "inst_ptw_pte0", "inst_ptw_pte1", "data_ptw_pte0", "data_ptw_pte1"
            };
            static const char* k_output_signal_names[] = {
              "inst_addr", "inst_ptw_addr0", "inst_ptw_addr1",
              "data_addr", "data_wdata", "data_we", "data_re", "data_funct3",
              "data_ptw_addr0", "data_ptw_addr1",
              "debug_pc", "debug_inst", "debug_x1", "debug_x2", "debug_x10", "debug_x11", "debug_reg_data"
            };
            static const char k_input_names_csv[] =
              "clk,rst,irq_software,irq_timer,irq_external,inst_data,data_rdata,debug_reg_addr,"
              "inst_ptw_pte0,inst_ptw_pte1,data_ptw_pte0,data_ptw_pte1";
            static const char k_output_names_csv[] =
              "inst_addr,inst_ptw_addr0,inst_ptw_addr1,data_addr,data_wdata,data_we,data_re,data_funct3,"
              "data_ptw_addr0,data_ptw_addr1,debug_pc,debug_inst,debug_x1,debug_x2,debug_x10,debug_x11,debug_reg_data";
            static const uint32_t k_input_signal_count = static_cast<uint32_t>(sizeof(k_input_signal_names) / sizeof(k_input_signal_names[0]));
            static const uint32_t k_output_signal_count = static_cast<uint32_t>(sizeof(k_output_signal_names) / sizeof(k_output_signal_names[0]));

            static uint32_t total_signal_count() {
              return k_input_signal_count + k_output_signal_count;
            }

            static const char* signal_name_from_index(uint32_t idx) {
              if (idx < k_input_signal_count) return k_input_signal_names[idx];
              idx -= k_input_signal_count;
              if (idx < k_output_signal_count) return k_output_signal_names[idx];
              return nullptr;
            }

            static int32_t signal_index_from_name(const char* name) {
              if (!name) return -1;
              for (uint32_t i = 0; i < k_input_signal_count; i++) {
                if (!std::strcmp(name, k_input_signal_names[i])) return static_cast<int32_t>(i);
              }
              for (uint32_t i = 0; i < k_output_signal_count; i++) {
                if (!std::strcmp(name, k_output_signal_names[i])) return static_cast<int32_t>(k_input_signal_count + i);
              }
              return -1;
            }

            static void write_out_u32(uint32_t* out, uint32_t value) {
              if (out) *out = value;
            }

            static uint32_t blob_write_text(const char* text, uint8_t* ptr, uint32_t max_bytes) {
              const auto len = static_cast<uint32_t>(std::strlen(text));
              if (!ptr || max_bytes == 0) return len;
              const uint32_t n = len < max_bytes ? len : max_bytes;
              if (n > 0) std::memcpy(ptr, text, n);
              return n;
            }

            static uint32_t read_mem_bytes(SimContext* ctx, int32_t mem_type, uint32_t offset, uint8_t* out, uint32_t len) {
              if (!ctx || !out || len == 0) return 0;
              const uint8_t* mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
              for (uint32_t i = 0; i < len; i++) {
                const uint32_t byte_addr = offset + i;
                const uint32_t aligned = byte_addr & ~3u;
                const uint32_t shift = (byte_addr & 3u) * 8u;
                const uint32_t word = read_word_le(mem, ctx->mem.mem_mask, aligned);
                out[i] = static_cast<uint8_t>((word >> shift) & 0xFFu);
              }
              return len;
            }

            static uint32_t read_uart_tx_bytes(SimContext* ctx, uint32_t offset, uint8_t* out, uint32_t len) {
              if (!ctx || !out || len == 0) return 0;
              const uint32_t available = uart_tx_len(&ctx->mem);
              if (offset >= available) return 0;
              uint32_t n = available - offset;
              if (n > len) n = len;
              std::memcpy(out, ctx->mem.uart_tx_bytes + offset, n);
              return n;
            }

            static inline uint32_t runner_main_resolve_offset(uint32_t offset, uint32_t flags) {
              if ((flags & RUNNER_MEM_FLAG_MAPPED) == 0u) {
                return offset;
              }
              // Linux kernel direct-map on RV32:
              // virtual 0xC0000000.. maps to physical 0x80000000..
              if (offset >= 0xC0000000u) {
                return offset - 0x40000000u;
              }
              return offset;
            }

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
            void* sim_create(const char* json, uint32_t json_len, uint32_t sub_cycles, uint32_t* err_out) {
              (void)json;
              (void)json_len;
              (void)sub_cycles;
              write_out_u32(err_out, 0);
              const char* empty_args[] = {""};
              Verilated::commandArgs(1, empty_args);

              auto* ctx = new SimContext();
              ctx->dut = new Vriscv();

              mem_init(&ctx->mem, #{DEFAULT_MEM_SIZE});

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
              ctx->trace_enabled = 0;
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

            __attribute__((export_name("sim_get_caps")))
            uint32_t sim_get_caps(void* sim, uint32_t* out_caps) {
              (void)sim;
              write_out_u32(out_caps, SIM_CAP_SIGNAL_INDEX | SIM_CAP_TRACE | SIM_CAP_RUNNER_INTERP_JIT);
              return 1;
            }

            __attribute__((export_name("sim_signal")))
            uint32_t sim_signal(void* sim, uint32_t op, const char* name, uint32_t idx, uint32_t value, uint32_t* out_value) {
              int32_t resolved_idx = -1;
              const char* resolved_name = nullptr;
              if (name && name[0]) {
                resolved_idx = signal_index_from_name(name);
                resolved_name = name;
              } else {
                resolved_name = signal_name_from_index(idx);
                resolved_idx = resolved_name ? static_cast<int32_t>(idx) : -1;
              }

              switch (op) {
                case SIM_SIGNAL_HAS:
                  write_out_u32(out_value, resolved_idx >= 0 ? 1u : 0u);
                  return resolved_idx >= 0 ? 1u : 0u;
                case SIM_SIGNAL_GET_INDEX:
                  if (resolved_idx < 0) {
                    write_out_u32(out_value, 0xFFFFFFFFu);
                    return 0;
                  }
                  write_out_u32(out_value, static_cast<uint32_t>(resolved_idx));
                  return 1;
                case SIM_SIGNAL_PEEK:
                case SIM_SIGNAL_PEEK_INDEX:
                  if (resolved_idx < 0 || !resolved_name) {
                    write_out_u32(out_value, 0u);
                    return 0;
                  }
                  write_out_u32(out_value, sim_peek(sim, resolved_name));
                  return 1;
                case SIM_SIGNAL_POKE:
                case SIM_SIGNAL_POKE_INDEX:
                  if (resolved_idx < 0 || !resolved_name) {
                    write_out_u32(out_value, 0u);
                    return 0;
                  }
                  sim_poke(sim, resolved_name, value);
                  write_out_u32(out_value, 1u);
                  return 1;
                default:
                  write_out_u32(out_value, 0u);
                  return 0;
              }
            }

            __attribute__((export_name("sim_exec")))
            uint32_t sim_exec(void* sim, uint32_t op, uint32_t arg0, uint32_t arg1, uint32_t* out_value, uint32_t* err_out) {
              (void)arg1;
              write_out_u32(err_out, 0u);
              switch (op) {
                case SIM_EXEC_EVALUATE:
                  sim_eval(sim);
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_TICK:
                case SIM_EXEC_TICK_FORCED:
                  sim_run_cycles(sim, 1u);
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_SET_PREV_CLOCK:
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_GET_CLOCK_LIST_IDX:
                  write_out_u32(out_value, 0xFFFFFFFFu);
                  return 1;
                case SIM_EXEC_RESET:
                  sim_reset(sim);
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_RUN_TICKS:
                  sim_run_cycles(sim, arg0);
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_SIGNAL_COUNT:
                  write_out_u32(out_value, total_signal_count());
                  return 1;
                case SIM_EXEC_REG_COUNT:
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_EXEC_COMPILE:
                case SIM_EXEC_IS_COMPILED:
                  write_out_u32(out_value, 1u);
                  return 1;
                default:
                  write_out_u32(out_value, 0u);
                  return 0;
              }
            }

            __attribute__((export_name("sim_trace")))
            uint32_t sim_trace(void* sim, uint32_t op, const char* arg, uint32_t* out_value) {
              (void)arg;
              auto* ctx = static_cast<SimContext*>(sim);
              if (!ctx) {
                write_out_u32(out_value, 0u);
                return 0;
              }

              switch (op) {
                case SIM_TRACE_START:
                case SIM_TRACE_START_STREAMING:
                  ctx->trace_enabled = 1;
                  write_out_u32(out_value, 1u);
                  return 1;
                case SIM_TRACE_STOP:
                  ctx->trace_enabled = 0;
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_TRACE_ENABLED:
                  write_out_u32(out_value, ctx->trace_enabled ? 1u : 0u);
                  return 1;
                case SIM_TRACE_CHANGE_COUNT:
                  write_out_u32(out_value, 0u);
                  return 1;
                case SIM_TRACE_SIGNAL_COUNT:
                  write_out_u32(out_value, total_signal_count());
                  return 1;
                case SIM_TRACE_CAPTURE:
                case SIM_TRACE_ADD_SIGNAL:
                case SIM_TRACE_ADD_SIGNALS_MATCHING:
                case SIM_TRACE_ALL_SIGNALS:
                case SIM_TRACE_CLEAR_SIGNALS:
                case SIM_TRACE_CLEAR:
                case SIM_TRACE_SET_TIMESCALE:
                case SIM_TRACE_SET_MODULE_NAME:
                case SIM_TRACE_SAVE_VCD:
                  write_out_u32(out_value, 0u);
                  return 1;
                default:
                  write_out_u32(out_value, 0u);
                  return 0;
              }
            }

            __attribute__((export_name("sim_blob")))
            uint32_t sim_blob(void* sim, uint32_t op, uint8_t* ptr, uint32_t max_bytes) {
              (void)sim;
              if (op == SIM_BLOB_INPUT_NAMES) {
                return blob_write_text(k_input_names_csv, ptr, max_bytes);
              }
              if (op == SIM_BLOB_OUTPUT_NAMES) {
                return blob_write_text(k_output_names_csv, ptr, max_bytes);
              }
              return blob_write_text("", ptr, max_bytes);
            }

            __attribute__((export_name("runner_get_caps")))
            uint32_t runner_get_caps(void* sim, uint32_t* caps_ptr) {
              (void)sim;
              if (!caps_ptr) return 0;
              caps_ptr[0] = static_cast<uint32_t>(RUNNER_KIND_RISCV);
              caps_ptr[1] =
                (1u << RUNNER_MEM_SPACE_MAIN)
                | (1u << RUNNER_MEM_SPACE_ROM)
                | (1u << RUNNER_MEM_SPACE_DISK)
                | (1u << RUNNER_MEM_SPACE_UART_TX)
                | (1u << RUNNER_MEM_SPACE_UART_RX);
              caps_ptr[2] =
                (1u << RUNNER_CONTROL_SET_RESET_VECTOR)
                | (1u << RUNNER_CONTROL_CLEAR_UART_TX);
              caps_ptr[3] =
                (1u << RUNNER_PROBE_KIND)
                | (1u << RUNNER_PROBE_IS_MODE)
                | (1u << RUNNER_PROBE_SIGNAL)
                | (1u << RUNNER_PROBE_RISCV_UART_TX_LEN);
              return 1;
            }

            __attribute__((export_name("runner_mem")))
            uint32_t runner_mem(
              void* sim,
              uint32_t op,
              uint32_t space,
              uint32_t offset,
              uint8_t* ptr,
              uint32_t len,
              uint32_t flags
            ) {
              if (!sim || !ptr || len == 0) return 0;

              if (op == RUNNER_MEM_OP_LOAD) {
                if (space == RUNNER_MEM_SPACE_MAIN || space == RUNNER_MEM_SPACE_ROM) {
                  sim_load_mem(sim, MEM_TYPE_INST, ptr, len, offset);
                  sim_load_mem(sim, MEM_TYPE_DATA, ptr, len, offset);
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_DISK) {
                  return sim_disk_load(sim, ptr, len, offset);
                }
                return 0;
              }

              if (op == RUNNER_MEM_OP_READ) {
                auto* ctx = static_cast<SimContext*>(sim);
                if (space == RUNNER_MEM_SPACE_MAIN) {
                  const uint32_t resolved = runner_main_resolve_offset(offset, flags);
                  return read_mem_bytes(ctx, MEM_TYPE_DATA, resolved, ptr, len);
                }
                if (space == RUNNER_MEM_SPACE_ROM) {
                  return read_mem_bytes(ctx, MEM_TYPE_INST, offset, ptr, len);
                }
                if (space == RUNNER_MEM_SPACE_UART_TX) {
                  return read_uart_tx_bytes(ctx, offset, ptr, len);
                }
                return 0;
              }

              if (op == RUNNER_MEM_OP_WRITE) {
                if (space == RUNNER_MEM_SPACE_UART_RX) {
                  sim_uart_rx_push(sim, ptr, len);
                  return len;
                }
                if (space == RUNNER_MEM_SPACE_MAIN) {
                  const uint32_t resolved = runner_main_resolve_offset(offset, flags);
                  sim_load_mem(sim, MEM_TYPE_DATA, ptr, len, resolved);
                  return len;
                }
                return 0;
              }

              return 0;
            }

            __attribute__((export_name("runner_run")))
            uint32_t runner_run(void* sim, uint32_t cycles, uint32_t key_data, uint32_t key_ready, uint32_t mode, uint32_t* result_ptr) {
              (void)mode;
              if (!sim) return 0;
              if (key_ready) {
                uint8_t key = static_cast<uint8_t>(key_data & 0xFFu);
                sim_uart_rx_push(sim, &key, 1u);
              }
              sim_run_cycles(sim, cycles);
              if (result_ptr) {
                result_ptr[0] = 0u;                    /* text_dirty */
                result_ptr[1] = key_ready ? 1u : 0u;  /* key_cleared */
                result_ptr[2] = cycles;               /* cycles_run */
                result_ptr[3] = 0u;                   /* speaker_toggles */
                result_ptr[4] = 0u;                   /* frames_completed */
              }
              return 1;
            }

            __attribute__((export_name("runner_control")))
            uint32_t runner_control(void* sim, uint32_t op, uint32_t arg0, uint32_t arg1) {
              (void)arg1;
              if (!sim) return 0;
              if (op == RUNNER_CONTROL_SET_RESET_VECTOR) {
                sim_write_pc(sim, arg0);
                return 1;
              }
              if (op == RUNNER_CONTROL_CLEAR_UART_TX) {
                sim_uart_tx_clear(sim);
                return 1;
              }
              return 0;
            }

            __attribute__((export_name("runner_probe")))
            uint32_t runner_probe(void* sim, uint32_t op, uint32_t arg0) {
              if (!sim) return 0;
              if (op == RUNNER_PROBE_KIND) return static_cast<uint32_t>(RUNNER_KIND_RISCV);
              if (op == RUNNER_PROBE_IS_MODE) return 1u;
              if (op == RUNNER_PROBE_RISCV_UART_TX_LEN) return sim_uart_tx_len(sim);
              if (op == RUNNER_PROBE_SIGNAL) {
                if (arg0 < k_output_signal_count) {
                  return sim_peek(sim, k_output_signal_names[arg0]);
                }
                return 0u;
              }
              return 0u;
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
            object = File.join(OBJ_DIR, "#{File.basename(source, '.cpp')}.o")
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
