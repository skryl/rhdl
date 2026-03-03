# frozen_string_literal: true

require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Builds a Verilator-compiled Apple II WASM module for web benchmarking.
      #
      # Pipeline:
      #   RHDL -> Verilog -> Verilator C++ -> em++ -> apple2_verilator.wasm
      #
      # The produced module exports the same sim_/runner_ ABI surface used by
      # the web benchmark harness.
      module WebApple2VerilatorBuild
        PROJECT_ROOT = File.expand_path('../../../../..', __dir__)
        BUILD_DIR = File.join(PROJECT_ROOT, 'web', 'build', 'verilator', 'build')
        VERILOG_DIR = File.join(BUILD_DIR, 'verilog')
        OBJ_DIR = File.join(BUILD_DIR, 'obj_dir')
        VERILOG_FILE = File.join(VERILOG_DIR, 'apple2.v')
        WRAPPER_SOURCE = File.join(BUILD_DIR, 'verilator_wasm_wrapper.cpp')
        COMPAT_SOURCE = File.join(BUILD_DIR, 'verilator_wasm_compat.cpp')
        WASM_OUTPUT = File.join(BUILD_DIR, 'apple2_verilator.wasm')
        PKG_DIR = File.join(PROJECT_ROOT, 'web', 'assets', 'pkg')
        PKG_OUTPUT = File.join(PKG_DIR, 'apple2_verilator.wasm')
        DEFAULT_VERILATOR_ROOT = '/opt/homebrew/Cellar/verilator/5.044/share/verilator'

        TOP_MODULE = 'apple2_apple2'
        VERILATOR_PREFIX = 'Vapple2'

        RAM_SIZE = 48 * 1024
        ROM_SIZE = 12 * 1024

        REQUIRED_TOOLS = %w[verilator em++].freeze
        INPUT_SIGNALS = %w[
          clk_14m flash_clk reset ram_do pd ps2_clk ps2_data gameport pause
        ].freeze
        OUTPUT_SIGNALS = %w[
          ram_addr ram_we d speaker pc_debug opcode_debug a_debug x_debug y_debug s_debug p_debug
        ].freeze
        SIGNAL_WIDTHS = {
          'clk_14m' => 'SIG_BIT',
          'flash_clk' => 'SIG_BIT',
          'reset' => 'SIG_BIT',
          'ram_do' => 'SIG_U8',
          'pd' => 'SIG_U8',
          'ps2_clk' => 'SIG_BIT',
          'ps2_data' => 'SIG_BIT',
          'gameport' => 'SIG_U8',
          'pause' => 'SIG_BIT',
          'ram_addr' => 'SIG_U16',
          'ram_we' => 'SIG_BIT',
          'd' => 'SIG_U8',
          'speaker' => 'SIG_BIT',
          'pc_debug' => 'SIG_U16',
          'opcode_debug' => 'SIG_U8',
          'a_debug' => 'SIG_U8',
          'x_debug' => 'SIG_U8',
          'y_debug' => 'SIG_U8',
          's_debug' => 'SIG_U8',
          'p_debug' => 'SIG_U8'
        }.freeze
        LINK_EXPORTS = %w[
          sim_create sim_destroy sim_free_error sim_wasm_alloc sim_wasm_dealloc
          sim_get_caps sim_signal sim_exec sim_trace sim_blob
          runner_get_caps runner_mem runner_run runner_control runner_probe
        ].freeze

        module_function

        # Build the Verilator Apple II WASM module.
        # Returns true if the WASM was built, false if skipped.
        def build(dest_dir: PKG_DIR)
          missing = missing_tools
          unless missing.empty?
            warn "WARNING: verilator WASM build skipped; missing tools: #{missing.join(', ')}"
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

          puts 'Building verilator Apple II WASM module...'

          export_verilog
          generate_cpp_wrapper
          generate_compat_source
          generate_verilator_cpp
          objects = compile_objects
          link_wasm(objects)
          install_wasm(dest_dir)

          puts "  Wrote #{File.join(dest_dir, 'apple2_verilator.wasm')}"
          true
        end

        def missing_tools
          REQUIRED_TOOLS.select { |tool| !tool_available?(tool) }
        end

        def tools_available?
          missing_tools.empty?
        end

        def build_signal_entries
          (INPUT_SIGNALS + OUTPUT_SIGNALS).map do |name|
            {
              name: name,
              enum_name: signal_enum_name(name),
              field_name: name,
              width: SIGNAL_WIDTHS.fetch(name, 'SIG_U32'),
              is_input: INPUT_SIGNALS.include?(name) ? 1 : 0
            }
          end
        end

        def build_wrapper_source
          signal_entries = build_signal_entries
          enum_lines = signal_entries.each_with_index.map do |entry, index|
            "  #{entry[:enum_name]} = #{index},"
          end.join("\n")
          table_lines = signal_entries.map do |entry|
            "  { \"#{entry[:name]}\", #{entry[:enum_name]}, #{entry[:width]}, #{entry[:is_input]} },"
          end.join("\n")
          lookup_cases = signal_entries.map do |entry|
            "  if (std::strcmp(name, \"#{entry[:name]}\") == 0) return #{entry[:enum_name]};"
          end.join("\n")
          input_names = signal_entries.select { |entry| entry[:is_input] == 1 }.map { |entry| entry[:name] }.join(',')
          output_names = signal_entries.select { |entry| entry[:is_input] == 0 }.map { |entry| entry[:name] }.join(',')
          peek_cases = signal_entries.map do |entry|
            field = entry[:field_name]
            "  case #{entry[:enum_name]}: return static_cast<uint32_t>(ctx->dut->#{field});"
          end.join("\n")
          poke_cases = signal_entries.select { |entry| entry[:is_input] == 1 }.map do |entry|
            field = entry[:field_name]
            "  case #{entry[:enum_name]}: ctx->dut->#{field} = value; return;"
          end.join("\n")

          <<~CPP
            #include "Vapple2.h"
            #include "verilated.h"

            #include <cstdint>
            #include <cstdlib>
            #include <cstring>

            // Verilator runtime hook.
            double sc_time_stamp() { return 0; }

            namespace {
            constexpr uint32_t kRamSize = #{RAM_SIZE};
            constexpr uint32_t kRomSize = #{ROM_SIZE};

            struct SimContext {
              Vapple2* dut;
              uint8_t ram[kRamSize];
              uint8_t rom[kRomSize];
              uint8_t prev_speaker;
              uint32_t speaker_toggles;
              uint32_t text_dirty;
              uint32_t sub_cycles;
              uint32_t cycle_count;
            };

            static SimContext g_ctx{};
            static bool g_ctx_initialized = false;

            enum SignalWidth : uint8_t {
              SIG_BIT = 0,
              SIG_U8 = 1,
              SIG_U16 = 2,
              SIG_U32 = 3
            };

            enum SignalId : uint32_t {
            #{enum_lines}
              SIGNAL_COUNT
            };

            struct SignalEntry {
              const char* name;
              SignalId id;
              SignalWidth width;
              uint8_t is_input;
            };

            static const SignalEntry kSignalTable[] = {
            #{table_lines}
            };

            static SignalId signal_id_from_name(const char* name) {
              if (!name) return SIGNAL_COUNT;
            #{lookup_cases}
              return SIGNAL_COUNT;
            }

            static uint32_t signal_peek_by_id(SimContext* ctx, SignalId id) {
              switch (id) {
            #{peek_cases}
              default:
                return 0;
              }
            }

            static void signal_poke_by_id(SimContext* ctx, SignalId id, uint32_t value) {
              switch (id) {
            #{poke_cases}
              default:
                return;
              }
            }

            static void run_14m_cycle(SimContext* ctx) {
              ctx->dut->clk_14m = 0;
              ctx->dut->eval();

              const uint32_t ram_addr = static_cast<uint32_t>(ctx->dut->ram_addr) & 0xFFFFu;
              if (ram_addr >= 0xD000u && ram_addr <= 0xFFFFu) {
                const uint32_t rom_offset = ram_addr - 0xD000u;
                ctx->dut->ram_do = (rom_offset < kRomSize) ? ctx->rom[rom_offset] : 0;
              } else if (ram_addr >= 0xC000u) {
                ctx->dut->ram_do = 0;
              } else if (ram_addr < kRamSize) {
                ctx->dut->ram_do = ctx->ram[ram_addr];
              } else {
                ctx->dut->ram_do = 0;
              }
              ctx->dut->eval();

              ctx->dut->clk_14m = 1;
              ctx->dut->eval();
              // Keep derived-clock behavior consistent with the native runner.
              ctx->dut->eval();

              if (ctx->dut->ram_we) {
                const uint32_t write_addr = static_cast<uint32_t>(ctx->dut->ram_addr) & 0xFFFFu;
                if (write_addr < 0xC000u && write_addr < kRamSize) {
                  ctx->ram[write_addr] = static_cast<uint8_t>(ctx->dut->d) & 0xFFu;
                  if ((write_addr >= 0x0400u && write_addr <= 0x07FFu)
                      || (write_addr >= 0x2000u && write_addr <= 0x5FFFu)) {
                    ctx->text_dirty = 1;
                  }
                }
              }

              const uint8_t speaker = static_cast<uint8_t>(ctx->dut->speaker) & 0x1u;
              if (speaker != ctx->prev_speaker) {
                ctx->speaker_toggles++;
                ctx->prev_speaker = speaker;
              }
            }
            }  // namespace

            extern "C" {
            // Capability flags mirrored from web/app/components/sim/runtime/wasm_ir_simulator.mjs
            #define SIM_CAP_SIGNAL_INDEX       (1u << 0)
            #define SIM_CAP_RUNNER_INTERP_JIT  (1u << 4)
            #define SIM_CAP_RUNNER             (1u << 6)

            // Signal ops
            #define SIM_SIGNAL_HAS        0
            #define SIM_SIGNAL_GET_INDEX  1
            #define SIM_SIGNAL_PEEK       2
            #define SIM_SIGNAL_POKE       3
            #define SIM_SIGNAL_PEEK_INDEX 4
            #define SIM_SIGNAL_POKE_INDEX 5

            // Exec ops
            #define SIM_EXEC_EVALUATE      0
            #define SIM_EXEC_TICK          1
            #define SIM_EXEC_TICK_FORCED   2
            #define SIM_EXEC_RESET         5
            #define SIM_EXEC_RUN_TICKS     6
            #define SIM_EXEC_SIGNAL_COUNT  7
            #define SIM_EXEC_REG_COUNT     8

            // Blob ops
            #define SIM_BLOB_INPUT_NAMES   0
            #define SIM_BLOB_OUTPUT_NAMES  1

            // Runner constants
            #define RUNNER_KIND_APPLE2      1
            #define RUNNER_MEM_OP_LOAD      0
            #define RUNNER_MEM_OP_READ      1
            #define RUNNER_MEM_OP_WRITE     2
            #define RUNNER_MEM_SPACE_MAIN   0
            #define RUNNER_MEM_SPACE_ROM    1
            #define RUNNER_MEM_FLAG_MAPPED  1

            #define RUNNER_CONTROL_SET_RESET_VECTOR 0
            #define RUNNER_CONTROL_RESET_SPEAKER    1

            #define RUNNER_PROBE_KIND            0
            #define RUNNER_PROBE_IS_MODE         1
            #define RUNNER_PROBE_SPEAKER_TOGGLES 2
            #define RUNNER_PROBE_SIGNAL          9

            struct RunnerRunResult {
              int32_t text_dirty;
              int32_t key_cleared;
              uint32_t cycles_run;
              uint32_t speaker_toggles;
              uint32_t frames_completed;
            };

            static uint32_t normalize_rom_offset(uint32_t offset) {
              if (offset >= 0xD000u && offset <= 0xFFFFu) {
                return offset - 0xD000u;
              }
              return offset;
            }

            __attribute__((export_name("sim_create")))
            void* sim_create(const char* json, uint32_t json_len, uint32_t sub_cycles, uint32_t* err_out) {
              (void)json;
              (void)json_len;
              if (err_out) *err_out = 0;

              if (!g_ctx_initialized) {
                const char* empty_args[] = {""};
                Verilated::commandArgs(1, empty_args);
                g_ctx.dut = new Vapple2();
                g_ctx_initialized = true;
              }

              std::memset(g_ctx.ram, 0, sizeof(g_ctx.ram));
              std::memset(g_ctx.rom, 0, sizeof(g_ctx.rom));
              g_ctx.prev_speaker = 0;
              g_ctx.speaker_toggles = 0;
              g_ctx.text_dirty = 0;
              g_ctx.sub_cycles = (sub_cycles > 0 && sub_cycles <= 14) ? sub_cycles : 14;
              g_ctx.cycle_count = 0;

              g_ctx.dut->clk_14m = 0;
              g_ctx.dut->flash_clk = 0;
              g_ctx.dut->reset = 1;
              g_ctx.dut->ram_do = 0;
              g_ctx.dut->pd = 0;
              g_ctx.dut->ps2_clk = 1;
              g_ctx.dut->ps2_data = 1;
              g_ctx.dut->gameport = 0;
              g_ctx.dut->pause = 0;
              g_ctx.dut->eval();

              return &g_ctx;
            }

            __attribute__((export_name("sim_destroy")))
            void sim_destroy(void* ctx_ptr) {
              (void)ctx_ptr;
              if (!g_ctx_initialized) return;
              delete g_ctx.dut;
              g_ctx.dut = nullptr;
              g_ctx_initialized = false;
            }

            __attribute__((export_name("sim_free_error")))
            void sim_free_error(void* err) {
              (void)err;
            }

            __attribute__((export_name("sim_wasm_alloc")))
            void* sim_wasm_alloc(uint32_t size) {
              return std::malloc(size > 0 ? size : 1);
            }

            __attribute__((export_name("sim_wasm_dealloc")))
            void sim_wasm_dealloc(void* ptr, uint32_t size) {
              (void)size;
              std::free(ptr);
            }

            __attribute__((export_name("sim_get_caps")))
            int32_t sim_get_caps(const void* ctx_ptr, uint32_t* caps_out) {
              if (!ctx_ptr || !caps_out) return 0;
              *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER_INTERP_JIT | SIM_CAP_RUNNER;
              return 1;
            }

            __attribute__((export_name("sim_signal")))
            int32_t sim_signal(void* ctx_ptr, uint32_t op, const char* name,
                               uint32_t idx, uint32_t value, uint32_t* out_value) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              if (!ctx || !ctx->dut) return 0;

              switch (op) {
              case SIM_SIGNAL_HAS: {
                const auto id = signal_id_from_name(name);
                if (out_value) *out_value = (id != SIGNAL_COUNT) ? 1u : 0u;
                return (id != SIGNAL_COUNT) ? 1 : 0;
              }
              case SIM_SIGNAL_GET_INDEX: {
                const auto id = signal_id_from_name(name);
                if (id == SIGNAL_COUNT) return 0;
                if (out_value) *out_value = static_cast<uint32_t>(id);
                return 1;
              }
              case SIM_SIGNAL_PEEK: {
                const auto id = signal_id_from_name(name);
                if (id == SIGNAL_COUNT) return 0;
                if (out_value) *out_value = signal_peek_by_id(ctx, id);
                return 1;
              }
              case SIM_SIGNAL_POKE: {
                const auto id = signal_id_from_name(name);
                if (id == SIGNAL_COUNT) return 0;
                signal_poke_by_id(ctx, id, value);
                if (out_value) *out_value = value;
                return 1;
              }
              case SIM_SIGNAL_PEEK_INDEX: {
                if (idx >= static_cast<uint32_t>(SIGNAL_COUNT)) return 0;
                if (out_value) *out_value = signal_peek_by_id(ctx, static_cast<SignalId>(idx));
                return 1;
              }
              case SIM_SIGNAL_POKE_INDEX: {
                if (idx >= static_cast<uint32_t>(SIGNAL_COUNT)) return 0;
                signal_poke_by_id(ctx, static_cast<SignalId>(idx), value);
                if (out_value) *out_value = value;
                return 1;
              }
              default:
                return 0;
              }
            }

            __attribute__((export_name("sim_exec")))
            int32_t sim_exec(void* ctx_ptr, uint32_t op, uint32_t arg0, uint32_t arg1,
                             uint32_t* out_value, uint32_t* err_out) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              (void)arg1;
              (void)err_out;
              if (!ctx || !ctx->dut) return 0;

              switch (op) {
              case SIM_EXEC_EVALUATE:
                ctx->dut->eval();
                if (out_value) *out_value = 1;
                return 1;
              case SIM_EXEC_TICK:
              case SIM_EXEC_TICK_FORCED:
                run_14m_cycle(ctx);
                if (out_value) *out_value = 1;
                return 1;
              case SIM_EXEC_RESET:
                ctx->speaker_toggles = 0;
                ctx->dut->reset = 1;
                for (int i = 0; i < 14; i++) run_14m_cycle(ctx);
                ctx->dut->reset = 0;
                for (int i = 0; i < 140; i++) run_14m_cycle(ctx);
                ctx->cycle_count = 0;
                if (out_value) *out_value = 1;
                return 1;
              case SIM_EXEC_RUN_TICKS:
                for (uint32_t i = 0; i < arg0; i++) run_14m_cycle(ctx);
                if (out_value) *out_value = arg0;
                return 1;
              case SIM_EXEC_SIGNAL_COUNT:
                if (out_value) *out_value = static_cast<uint32_t>(SIGNAL_COUNT);
                return 1;
              case SIM_EXEC_REG_COUNT:
                if (out_value) *out_value = 0;
                return 1;
              default:
                return 0;
              }
            }

            __attribute__((export_name("sim_trace")))
            int32_t sim_trace(void* ctx_ptr, uint32_t op, const char* str_arg, uint32_t* out_value) {
              (void)ctx_ptr;
              (void)str_arg;
              if (out_value) *out_value = 0;
              return (op == 3) ? 1 : 0;
            }

            static const char kInputNamesCsv[] = "#{input_names}";
            static const char kOutputNamesCsv[] = "#{output_names}";

            __attribute__((export_name("sim_blob")))
            uint32_t sim_blob(void* ctx_ptr, uint32_t op, uint8_t* out_ptr, uint32_t out_len) {
              (void)ctx_ptr;
              const char* data = nullptr;
              uint32_t len = 0;
              switch (op) {
              case SIM_BLOB_INPUT_NAMES:
                data = kInputNamesCsv;
                len = static_cast<uint32_t>(sizeof(kInputNamesCsv) - 1);
                break;
              case SIM_BLOB_OUTPUT_NAMES:
                data = kOutputNamesCsv;
                len = static_cast<uint32_t>(sizeof(kOutputNamesCsv) - 1);
                break;
              default:
                return 0;
              }
              if (!out_ptr || out_len == 0) return len;
              const uint32_t copy_len = (len < out_len) ? len : out_len;
              std::memcpy(out_ptr, data, copy_len);
              return copy_len;
            }

            __attribute__((export_name("runner_get_caps")))
            int32_t runner_get_caps(const void* ctx_ptr, uint32_t* caps_out) {
              if (!ctx_ptr || !caps_out) return 0;
              caps_out[0] = RUNNER_KIND_APPLE2;
              caps_out[1] = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM);
              caps_out[2] = (1u << RUNNER_CONTROL_SET_RESET_VECTOR) | (1u << RUNNER_CONTROL_RESET_SPEAKER);
              caps_out[3] = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE)
                          | (1u << RUNNER_PROBE_SPEAKER_TOGGLES) | (1u << RUNNER_PROBE_SIGNAL);
              return 1;
            }

            __attribute__((export_name("runner_mem")))
            uint32_t runner_mem(void* ctx_ptr, uint32_t op, uint32_t space,
                                uint32_t offset, uint8_t* data, uint32_t len, uint32_t flags) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              if (!ctx || !data) return 0;

              uint8_t* mem = nullptr;
              uint32_t mem_size = 0;
              uint32_t mem_offset = offset;
              switch (space) {
              case RUNNER_MEM_SPACE_MAIN:
                mem = ctx->ram;
                mem_size = kRamSize;
                break;
              case RUNNER_MEM_SPACE_ROM:
                mem = ctx->rom;
                mem_size = kRomSize;
                mem_offset = normalize_rom_offset(offset);
                break;
              default:
                return 0;
              }

              switch (op) {
              case RUNNER_MEM_OP_LOAD:
              case RUNNER_MEM_OP_WRITE: {
                uint32_t count = 0;
                for (uint32_t i = 0; i < len && (mem_offset + i) < mem_size; i++) {
                  mem[mem_offset + i] = data[i];
                  count++;
                }
                return count;
              }
              case RUNNER_MEM_OP_READ: {
                if (space == RUNNER_MEM_SPACE_MAIN && (flags & RUNNER_MEM_FLAG_MAPPED)) {
                  uint32_t count = 0;
                  for (uint32_t i = 0; i < len; i++) {
                    const uint32_t addr = (offset + i) & 0xFFFFu;
                    if (addr >= 0xD000u) {
                      const uint32_t ro = addr - 0xD000u;
                      data[i] = (ro < kRomSize) ? ctx->rom[ro] : 0;
                    } else if (addr >= 0xC000u) {
                      data[i] = 0;
                    } else {
                      data[i] = (addr < kRamSize) ? ctx->ram[addr] : 0;
                    }
                    count++;
                  }
                  return count;
                }

                uint32_t count = 0;
                for (uint32_t i = 0; i < len && (mem_offset + i) < mem_size; i++) {
                  data[i] = mem[mem_offset + i];
                  count++;
                }
                return count;
              }
              default:
                return 0;
              }
            }

            __attribute__((export_name("runner_run")))
            int32_t runner_run(void* ctx_ptr, uint32_t cycles, uint8_t key_data,
                               int32_t key_ready, uint32_t mode, RunnerRunResult* result) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              if (!ctx || !ctx->dut) return 0;
              (void)key_data;
              (void)key_ready;
              (void)mode;

              ctx->text_dirty = 0;
              ctx->speaker_toggles = 0;

              const uint32_t n_14m = cycles * ctx->sub_cycles;
              for (uint32_t i = 0; i < n_14m; i++) {
                run_14m_cycle(ctx);
              }
              ctx->cycle_count += cycles;

              if (result) {
                result->text_dirty = ctx->text_dirty ? 1 : 0;
                result->key_cleared = 0;
                result->cycles_run = cycles;
                result->speaker_toggles = ctx->speaker_toggles;
                result->frames_completed = 0;
              }
              return 1;
            }

            __attribute__((export_name("runner_control")))
            int32_t runner_control(void* ctx_ptr, uint32_t op, uint32_t arg0, uint32_t arg1) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              if (!ctx || !ctx->dut) return 0;
              (void)arg1;

              switch (op) {
              case RUNNER_CONTROL_SET_RESET_VECTOR:
                if (0x2FFDu < kRomSize) {
                  ctx->rom[0x2FFCu] = static_cast<uint8_t>(arg0 & 0xFFu);
                  ctx->rom[0x2FFDu] = static_cast<uint8_t>((arg0 >> 8) & 0xFFu);
                }
                return 1;
              case RUNNER_CONTROL_RESET_SPEAKER:
                ctx->speaker_toggles = 0;
                ctx->prev_speaker = static_cast<uint8_t>(ctx->dut->speaker) & 0x1u;
                return 1;
              default:
                return 0;
              }
            }

            __attribute__((export_name("runner_probe")))
            uint32_t runner_probe(void* ctx_ptr, uint32_t op, uint32_t arg0) {
              auto* ctx = static_cast<SimContext*>(ctx_ptr);
              if (!ctx || !ctx->dut) return 0;

              switch (op) {
              case RUNNER_PROBE_KIND:
                return RUNNER_KIND_APPLE2;
              case RUNNER_PROBE_IS_MODE:
                return 0;
              case RUNNER_PROBE_SPEAKER_TOGGLES:
                return ctx->speaker_toggles;
              case RUNNER_PROBE_SIGNAL:
                if (arg0 >= static_cast<uint32_t>(SIGNAL_COUNT)) return 0;
                return signal_peek_by_id(ctx, static_cast<SignalId>(arg0));
              default:
                return 0;
              }
            }
            }  // extern "C"
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

        def export_verilog
          puts '  Exporting Apple2 to Verilog...'
          require File.join(PROJECT_ROOT, 'examples/apple2/hdl/apple2')

          main_verilog = RHDL::Examples::Apple2::Apple2.to_verilog
          subcomponents = []
          [
            RHDL::Examples::Apple2::TimingGenerator,
            RHDL::Examples::Apple2::VideoGenerator,
            RHDL::Examples::Apple2::CharacterROM,
            RHDL::Examples::Apple2::SpeakerToggle,
            RHDL::Examples::Apple2::CPU6502,
            RHDL::Examples::Apple2::DiskII,
            RHDL::Examples::Apple2::DiskIIROM,
            RHDL::Examples::Apple2::Keyboard,
            RHDL::Examples::Apple2::PS2Controller
          ].each do |component_class|
            begin
              subcomponents << component_class.to_verilog
            rescue StandardError => e
              warn "  Warning: could not export #{component_class}: #{e.message}"
            end
          end

          File.write(VERILOG_FILE, ([main_verilog] + subcomponents).join("\n\n"))
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
            '--x-initial', 'unique',
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
            '-Wl,--initial-memory=67108864',
            '-sALLOW_MEMORY_GROWTH=1',
            '-sASSERTIONS=0',
            *export_flags,
            '-o', WASM_OUTPUT,
            *objects
          )
        end

        def install_wasm(dest_dir)
          FileUtils.mkdir_p(dest_dir)
          FileUtils.cp(WASM_OUTPUT, File.join(dest_dir, 'apple2_verilator.wasm'))
        end

        def run_tool!(*args)
          ok = system(*args)
          return if ok

          raise "Command failed: #{args.join(' ')}"
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

        def signal_enum_name(name)
          "SIG_#{name.upcase.gsub(/[^A-Z0-9]+/, '_')}"
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
