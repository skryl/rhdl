# frozen_string_literal: true

require 'json'
require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Builds an arcilator-compiled Apple II WASM module for the web simulator.
      #
      # Pipeline: RHDL → FIRRTL → firtool (HW MLIR) → arcilator (LLVM IR) →
      #           clang --target=wasm32 + wasm-ld → apple2_arcilator.wasm
      #
      # The generated WASM module implements the WasmIrSimulator API and Apple II
      # runner extensions, with the circuit evaluation function compiled directly
      # from MLIR rather than going through the IR simulator layer.
      module WebApple2ArcilatorBuild
        PROJECT_ROOT = File.expand_path('../../../../..', __dir__)
        BUILD_DIR = File.join(PROJECT_ROOT, 'web', 'build', 'arcilator', 'build')
        WRAPPER_SOURCE = File.join(BUILD_DIR, 'arc_wasm_wrapper.c')
        FIRRTL_FILE = File.join(BUILD_DIR, 'apple2.fir')
        MLIR_FILE = File.join(BUILD_DIR, 'apple2_hw.mlir')
        LL_FILE = File.join(BUILD_DIR, 'apple2_arc.ll')
        STATE_FILE = File.join(BUILD_DIR, 'apple2_state.json')
        OBJ_ARC = File.join(BUILD_DIR, 'apple2_arc.o')
        OBJ_WRAPPER = File.join(BUILD_DIR, 'arc_wasm_wrapper.o')
        WASM_OUTPUT = File.join(BUILD_DIR, 'apple2_arcilator.wasm')
        PKG_DIR = File.join(PROJECT_ROOT, 'web', 'assets', 'pkg')
        PKG_OUTPUT = File.join(PKG_DIR, 'apple2_arcilator.wasm')

        REQUIRED_TOOLS = %w[firtool arcilator clang wasm-ld].freeze

        # State buffer size — generous allocation for Apple II design.
        # Arcilator packs all registers into a flat byte array; typical Apple II
        # designs use ~2-4 KB. We allocate 16 KB to be safe.
        STATE_SIZE = 16_384

        # Apple II memory sizes
        RAM_SIZE = 48 * 1024   # 48 KB main RAM ($0000-$BFFF)
        ROM_SIZE = 12 * 1024   # 12 KB ROM ($D000-$FFFF)

        module_function

        # Build the arcilator Apple II WASM module.
        # Returns true if the WASM was built, false if skipped.
        def build(dest_dir: PKG_DIR)
          missing = missing_tools
          unless missing.empty?
            warn "WARNING: arcilator WASM build skipped; missing tools: #{missing.join(', ')}"
            return false
          end

          FileUtils.mkdir_p(BUILD_DIR)
          FileUtils.mkdir_p(dest_dir)

          puts 'Building arcilator Apple II WASM module...'

          export_firrtl
          compile_firrtl_to_mlir
          compile_mlir_to_llvm_ir
          state = parse_state_json
          generate_c_wrapper(state)
          compile_llvm_ir_to_wasm_obj
          compile_wrapper_to_wasm_obj
          link_wasm
          install_wasm(dest_dir)

          puts "  Wrote #{File.join(dest_dir, 'apple2_arcilator.wasm')}"
          true
        end

        # Check which required tools are missing from PATH.
        def missing_tools
          REQUIRED_TOOLS.select { |tool| !tool_available?(tool) }
        end

        # Check if all required tools are available.
        def tools_available?
          missing_tools.empty?
        end

        # Export Apple II HDL to FIRRTL format.
        def export_firrtl
          puts '  Exporting Apple2 to FIRRTL...'
          require File.join(PROJECT_ROOT, 'examples/apple2/hdl/apple2')
          require 'rhdl/codegen'

          components = [
            RHDL::Examples::Apple2::TimingGenerator,
            RHDL::Examples::Apple2::VideoGenerator,
            RHDL::Examples::Apple2::CharacterROM,
            RHDL::Examples::Apple2::SpeakerToggle,
            RHDL::Examples::Apple2::CPU6502,
            RHDL::Examples::Apple2::DiskII,
            RHDL::Examples::Apple2::DiskIIROM,
            RHDL::Examples::Apple2::Keyboard,
            RHDL::Examples::Apple2::PS2Controller,
            RHDL::Examples::Apple2::Apple2
          ]
          module_defs = components.map(&:to_ir)
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate_hierarchy(module_defs, top_name: 'apple2_apple2')
          File.write(FIRRTL_FILE, firrtl)
        end

        # FIRRTL → HW+Comb+Seq MLIR via firtool.
        def compile_firrtl_to_mlir
          puts '  Compiling FIRRTL → MLIR (firtool)...'
          run_tool!('firtool', FIRRTL_FILE, '--ir-hw', '-o', MLIR_FILE)
        end

        # MLIR → LLVM IR via arcilator.
        def compile_mlir_to_llvm_ir
          puts '  Compiling MLIR → LLVM IR (arcilator)...'
          run_tool!('arcilator', MLIR_FILE, "--state-file=#{STATE_FILE}", '-o', LL_FILE)
        end

        # Parse arcilator state JSON to extract signal name→offset mappings.
        def parse_state_json
          puts '  Parsing arcilator state layout...'
          raw = JSON.parse(File.read(STATE_FILE))
          mod = raw[0]
          offsets = {}
          mod['states'].each { |s| offsets[s['name']] = { offset: s['offset'], num_bits: s['numBits'] || 1 } }

          actual_size = mod['states'].map { |s| s['offset'] + ((s['numBits'] || 1) + 7) / 8 }.max || 0
          puts "  State buffer: #{offsets.size} signals, #{actual_size} bytes used"

          { offsets: offsets, actual_size: actual_size }
        end

        # Generate the C wrapper source that implements the WasmIrSimulator API.
        def generate_c_wrapper(state)
          puts '  Generating WASM C wrapper...'
          offsets = state[:offsets]
          actual_size = state[:actual_size]
          buf_size = [STATE_SIZE, actual_size + 256].max

          source = build_wrapper_source(offsets, buf_size)
          File.write(WRAPPER_SOURCE, source)
        end

        # Compile arcilator LLVM IR to wasm32 object.
        def compile_llvm_ir_to_wasm_obj
          puts '  Compiling LLVM IR → wasm32 object...'
          # Rewrite target triple in the .ll file for wasm32
          ll_content = File.read(LL_FILE)
          ll_content = rewrite_llvm_ir_for_wasm32(ll_content)
          wasm_ll = File.join(BUILD_DIR, 'apple2_arc_wasm.ll')
          File.write(wasm_ll, ll_content)

          run_tool!(
            'clang', '--target=wasm32-unknown-unknown',
            '-O2', '-c', '-fPIC',
            '-Wno-override-module',
            wasm_ll, '-o', OBJ_ARC
          )
        end

        # Compile C wrapper to wasm32 object.
        def compile_wrapper_to_wasm_obj
          puts '  Compiling C wrapper → wasm32 object...'
          run_tool!(
            'clang', '--target=wasm32-unknown-unknown',
            '-O2', '-c', '-fPIC', '-ffreestanding',
            '-Wno-incompatible-library-redeclaration',
            WRAPPER_SOURCE, '-o', OBJ_WRAPPER
          )
        end

        # Link objects into final WASM module.
        def link_wasm
          puts '  Linking WASM module...'
          run_tool!(
            'wasm-ld',
            '--no-entry',
            '--export-dynamic',
            '--allow-undefined',
            '--initial-memory=16777216',   # 16 MB initial WASM memory
            '--max-memory=67108864',       # 64 MB max
            '-o', WASM_OUTPUT,
            OBJ_WRAPPER, OBJ_ARC
          )
        end

        # Copy built WASM to web assets directory.
        def install_wasm(dest_dir)
          dest = File.join(dest_dir, 'apple2_arcilator.wasm')
          FileUtils.cp(WASM_OUTPUT, dest)
        end

        # Rewrite LLVM IR target triple and data layout for wasm32.
        def rewrite_llvm_ir_for_wasm32(ll_content)
          lines = ll_content.lines.map do |line|
            if line.start_with?('target datalayout')
              "target datalayout = \"e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20\"\n"
            elsif line.start_with?('target triple')
              "target triple = \"wasm32-unknown-unknown\"\n"
            elsif line.include?('i64') && line.include?('ptrtoint')
              # Convert i64 ptrtoint to i32 for wasm32 pointer size
              line.gsub(/ptrtoint\s+([^)]+)\s+to\s+i64/, 'ptrtoint \\1 to i32')
            else
              line
            end
          end
          lines.join
        end

        # ---- C Wrapper Source Generator ----

        # Build the complete C wrapper source implementing the WasmIrSimulator API.
        def build_wrapper_source(offsets, state_size)
          signal_table = build_signal_table(offsets)
          <<~C
            /* Auto-generated arcilator WASM wrapper for Apple II web simulator.
             * Implements the WasmIrSimulator C ABI for browser-based simulation.
             * Generated by: lib/rhdl/cli/tasks/utilities/web_apple2_arcilator_build.rb
             */

            typedef unsigned char uint8_t;
            typedef unsigned short uint16_t;
            typedef unsigned int uint32_t;
            typedef unsigned long long uint64_t;
            typedef int int32_t;

            #define NULL ((void*)0)
            #define STATE_SIZE #{state_size}
            #define RAM_SIZE #{RAM_SIZE}
            #define ROM_SIZE #{ROM_SIZE}

            /* ---- Minimal libc replacements for freestanding WASM ---- */

            static void *arc_memset(void *s, int c, unsigned int n) {
                uint8_t *p = (uint8_t *)s;
                while (n--) *p++ = (uint8_t)c;
                return s;
            }

            static void *arc_memcpy(void *d, const void *s, unsigned int n) {
                uint8_t *dp = (uint8_t *)d;
                const uint8_t *sp = (const uint8_t *)s;
                while (n--) *dp++ = *sp++;
                return d;
            }

            static int arc_strcmp(const char *a, const char *b) {
                while (*a && *a == *b) { a++; b++; }
                return (unsigned char)*a - (unsigned char)*b;
            }

            static unsigned int arc_strlen(const char *s) {
                unsigned int n = 0;
                while (*s++) n++;
                return n;
            }

            /* Provide libc symbols that LLVM-generated code may reference */
            void *memset(void *s, int c, unsigned int n) { return arc_memset(s, c, n); }
            void *memcpy(void *d, const void *s, unsigned int n) { return arc_memcpy(d, s, n); }
            void *memmove(void *d, const void *s, unsigned int n) {
                uint8_t *dp = (uint8_t *)d;
                const uint8_t *sp = (const uint8_t *)s;
                if (dp < sp || dp >= sp + n) return arc_memcpy(d, s, n);
                dp += n; sp += n;
                while (n--) *--dp = *--sp;
                return d;
            }

            /* ---- Simple bump allocator for WASM ---- */

            /* Heap region for temporary allocations (IR JSON + staging buffers) */
            #define HEAP_SIZE (8 * 1024 * 1024)
            static uint8_t g_heap[HEAP_SIZE];
            static uint32_t g_heap_offset = 0;

            __attribute__((export_name("sim_wasm_alloc")))
            void *sim_wasm_alloc(uint32_t size) {
                uint32_t aligned = (g_heap_offset + 7u) & ~7u;
                if (aligned + size > HEAP_SIZE) return NULL;
                void *ptr = &g_heap[aligned];
                g_heap_offset = aligned + size;
                return ptr;
            }

            __attribute__((export_name("sim_wasm_dealloc")))
            void sim_wasm_dealloc(void *ptr, uint32_t size) {
                /* Bump allocator: reclaim if this was the last allocation */
                if (ptr && (uint8_t *)ptr + size == &g_heap[g_heap_offset]) {
                    g_heap_offset = (uint32_t)((uint8_t *)ptr - g_heap);
                }
            }

            /* ---- Arcilator eval function (linked from arcilator LLVM IR) ---- */

            extern void apple2_apple2_eval(void *state);

            /* ---- Signal offset definitions ---- */

            #{generate_offset_defines(offsets)}

            /* ---- Signal table for name-based lookup ---- */

            #define SIG_BIT  0
            #define SIG_U8   1
            #define SIG_U16  2
            #define SIG_U32  3

            typedef struct {
                const char *name;
                uint32_t offset;
                uint8_t width;    /* SIG_BIT, SIG_U8, SIG_U16, SIG_U32 */
                uint8_t is_input; /* 1 = input, 0 = output */
            } SignalEntry;

            #{generate_signal_table(signal_table)}

            /* ---- Simulation context ---- */

            typedef struct {
                uint8_t state[STATE_SIZE];
                uint8_t ram[RAM_SIZE];
                uint8_t rom[ROM_SIZE];
                uint8_t prev_speaker;
                uint32_t speaker_toggles;
                uint32_t text_dirty;
                uint32_t sub_cycles;
                uint32_t cycle_count;
            } SimContext;

            static SimContext g_ctx;
            static int g_ctx_initialized = 0;

            /* ---- State access helpers ---- */

            static void set_bit(uint8_t *s, uint32_t o, uint8_t v) { s[o] = v & 1; }
            static uint8_t get_bit(uint8_t *s, uint32_t o) { return s[o] & 1; }
            static void set_u8(uint8_t *s, uint32_t o, uint8_t v) { s[o] = v; }
            static uint8_t get_u8(uint8_t *s, uint32_t o) { return s[o]; }
            static void set_u16(uint8_t *s, uint32_t o, uint16_t v) { arc_memcpy(&s[o], &v, 2); }
            static uint16_t get_u16(uint8_t *s, uint32_t o) { uint16_t v; arc_memcpy(&v, &s[o], 2); return v; }

            /* ---- Signal lookup ---- */

            static const SignalEntry *find_signal(const char *name) {
                if (!name) return NULL;
                for (uint32_t i = 0; i < SIGNAL_COUNT; i++) {
                    if (arc_strcmp(g_signal_table[i].name, name) == 0)
                        return &g_signal_table[i];
                }
                return NULL;
            }

            static uint32_t signal_peek(const SignalEntry *sig, const uint8_t *state) {
                switch (sig->width) {
                    case SIG_BIT: return get_bit((uint8_t*)state, sig->offset);
                    case SIG_U8:  return get_u8((uint8_t*)state, sig->offset);
                    case SIG_U16: return get_u16((uint8_t*)state, sig->offset);
                    default: return 0;
                }
            }

            static void signal_poke(const SignalEntry *sig, uint8_t *state, uint32_t value) {
                switch (sig->width) {
                    case SIG_BIT: set_bit(state, sig->offset, (uint8_t)value); break;
                    case SIG_U8:  set_u8(state, sig->offset, (uint8_t)value); break;
                    case SIG_U16: set_u16(state, sig->offset, (uint16_t)value); break;
                }
            }

            /* ---- 14 MHz cycle with memory bridge ---- */

            static void run_14m_cycle(SimContext *ctx) {
                set_bit(ctx->state, OFF_CLK_14M, 0);
                apple2_apple2_eval(ctx->state);

                uint16_t a = get_u16(ctx->state, OFF_RAM_ADDR) & 0xFFFF;
                if (a >= 0xD000)
                    set_u8(ctx->state, OFF_RAM_DO, (a - 0xD000 < ROM_SIZE) ? ctx->rom[a - 0xD000] : 0);
                else if (a >= 0xC000)
                    set_u8(ctx->state, OFF_RAM_DO, 0);
                else
                    set_u8(ctx->state, OFF_RAM_DO, ctx->ram[a]);
                apple2_apple2_eval(ctx->state);

                set_bit(ctx->state, OFF_CLK_14M, 1);
                apple2_apple2_eval(ctx->state);
                apple2_apple2_eval(ctx->state);

                if (get_bit(ctx->state, OFF_RAM_WE)) {
                    uint16_t wa = get_u16(ctx->state, OFF_RAM_ADDR) & 0xFFFF;
                    if (wa < 0xC000) {
                        ctx->ram[wa] = get_u8(ctx->state, OFF_D) & 0xFF;
                        if ((wa >= 0x0400 && wa <= 0x07FF) || (wa >= 0x2000 && wa <= 0x5FFF))
                            ctx->text_dirty = 1;
                    }
                }

                uint8_t spk = get_bit(ctx->state, OFF_SPEAKER);
                if (spk != ctx->prev_speaker) {
                    ctx->speaker_toggles++;
                    ctx->prev_speaker = spk;
                }
            }

            /* ---- Core WasmIrSimulator API ---- */

            /* Capability flags (must match wasm_ir_simulator.mjs constants) */
            #define SIM_CAP_SIGNAL_INDEX       (1u << 0)
            #define SIM_CAP_FORCED_CLOCK       (1u << 1)
            #define SIM_CAP_TRACE              (1u << 2)
            #define SIM_CAP_RUNNER_INTERP_JIT  (1u << 4)
            #define SIM_CAP_RUNNER             (1u << 6)

            /* Signal ops */
            #define SIM_SIGNAL_HAS        0
            #define SIM_SIGNAL_GET_INDEX  1
            #define SIM_SIGNAL_PEEK       2
            #define SIM_SIGNAL_POKE       3
            #define SIM_SIGNAL_PEEK_INDEX 4
            #define SIM_SIGNAL_POKE_INDEX 5

            /* Exec ops */
            #define SIM_EXEC_EVALUATE      0
            #define SIM_EXEC_TICK          1
            #define SIM_EXEC_TICK_FORCED   2
            #define SIM_EXEC_RESET         5
            #define SIM_EXEC_RUN_TICKS     6
            #define SIM_EXEC_SIGNAL_COUNT  7
            #define SIM_EXEC_REG_COUNT     8

            /* Blob ops */
            #define SIM_BLOB_INPUT_NAMES   0
            #define SIM_BLOB_OUTPUT_NAMES  1
            #define SIM_BLOB_TRACE_TO_VCD  2

            /* Runner constants */
            #define RUNNER_KIND_APPLE2     1
            #define RUNNER_MEM_OP_LOAD     0
            #define RUNNER_MEM_OP_READ     1
            #define RUNNER_MEM_OP_WRITE    2
            #define RUNNER_MEM_SPACE_MAIN  0
            #define RUNNER_MEM_SPACE_ROM   1
            #define RUNNER_MEM_FLAG_MAPPED 1

            #define RUNNER_CONTROL_SET_RESET_VECTOR     0
            #define RUNNER_CONTROL_RESET_SPEAKER        1

            #define RUNNER_PROBE_KIND              0
            #define RUNNER_PROBE_IS_MODE           1
            #define RUNNER_PROBE_SPEAKER_TOGGLES   2
            #define RUNNER_PROBE_SIGNAL            9

            #define RUNNER_RUN_MODE_BASIC  0

            typedef struct {
                int32_t text_dirty;
                int32_t key_cleared;
                uint32_t cycles_run;
                uint32_t speaker_toggles;
                uint32_t frames_completed;
            } RunnerRunResult;

            static uint32_t normalize_rom_offset(uint32_t offset) {
                if (offset >= 0xD000u && offset <= 0xFFFFu) {
                    return offset - 0xD000u;
                }
                return offset;
            }

            __attribute__((export_name("sim_create")))
            void *sim_create(const char *json, uint32_t json_len, uint32_t sub_cycles, uint32_t *err_out) {
                (void)json; (void)json_len;
                if (err_out) *err_out = 0;

                SimContext *ctx = &g_ctx;
                arc_memset(ctx->state, 0, STATE_SIZE);
                arc_memset(ctx->ram, 0, RAM_SIZE);
                arc_memset(ctx->rom, 0, ROM_SIZE);
                ctx->prev_speaker = 0;
                ctx->speaker_toggles = 0;
                ctx->text_dirty = 0;
                ctx->sub_cycles = (sub_cycles > 0 && sub_cycles <= 14) ? sub_cycles : 14;
                ctx->cycle_count = 0;

                /* Initial state */
                set_bit(ctx->state, OFF_CLK_14M, 0);
                set_bit(ctx->state, OFF_RESET, 1);
                set_bit(ctx->state, OFF_PS2_CLK, 1);
                set_bit(ctx->state, OFF_PS2_DATA, 1);
                apple2_apple2_eval(ctx->state);

                g_ctx_initialized = 1;
                return ctx;
            }

            __attribute__((export_name("sim_destroy")))
            void sim_destroy(void *ctx) {
                (void)ctx;
                g_ctx_initialized = 0;
            }

            __attribute__((export_name("sim_free_error")))
            void sim_free_error(void *err) {
                (void)err;
            }

            __attribute__((export_name("sim_get_caps")))
            int32_t sim_get_caps(const void *ctx, uint32_t *caps_out) {
                if (!ctx || !caps_out) return 0;
                *caps_out = SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER_INTERP_JIT | SIM_CAP_RUNNER;
                return 1;
            }

            __attribute__((export_name("sim_signal")))
            int32_t sim_signal(void *ctx_ptr, uint32_t op, const char *name,
                               uint32_t idx, uint32_t value, uint32_t *out_value) {
                SimContext *ctx = (SimContext *)ctx_ptr;
                if (!ctx) return 0;

                switch (op) {
                case SIM_SIGNAL_HAS: {
                    const SignalEntry *sig = find_signal(name);
                    if (out_value) *out_value = sig ? 1 : 0;
                    return sig ? 1 : 0;
                }
                case SIM_SIGNAL_GET_INDEX: {
                    for (uint32_t i = 0; i < SIGNAL_COUNT; i++) {
                        if (arc_strcmp(g_signal_table[i].name, name) == 0) {
                            if (out_value) *out_value = i;
                            return 1;
                        }
                    }
                    return 0;
                }
                case SIM_SIGNAL_PEEK: {
                    const SignalEntry *sig = find_signal(name);
                    if (!sig) return 0;
                    if (out_value) *out_value = signal_peek(sig, ctx->state);
                    return 1;
                }
                case SIM_SIGNAL_POKE: {
                    const SignalEntry *sig = find_signal(name);
                    if (!sig) return 0;
                    signal_poke(sig, ctx->state, value);
                    if (out_value) *out_value = value;
                    return 1;
                }
                case SIM_SIGNAL_PEEK_INDEX: {
                    if (idx >= SIGNAL_COUNT) return 0;
                    if (out_value) *out_value = signal_peek(&g_signal_table[idx], ctx->state);
                    return 1;
                }
                case SIM_SIGNAL_POKE_INDEX: {
                    if (idx >= SIGNAL_COUNT) return 0;
                    signal_poke(&g_signal_table[idx], ctx->state, value);
                    if (out_value) *out_value = value;
                    return 1;
                }
                default:
                    return 0;
                }
            }

            __attribute__((export_name("sim_exec")))
            int32_t sim_exec(void *ctx_ptr, uint32_t op, uint32_t arg0, uint32_t arg1,
                             uint32_t *out_value, uint32_t *err_out) {
                SimContext *ctx = (SimContext *)ctx_ptr;
                if (!ctx) return 0;
                (void)arg1;

                switch (op) {
                case SIM_EXEC_EVALUATE:
                    apple2_apple2_eval(ctx->state);
                    if (out_value) *out_value = 1;
                    return 1;

                case SIM_EXEC_TICK:
                case SIM_EXEC_TICK_FORCED:
                    run_14m_cycle(ctx);
                    if (out_value) *out_value = 1;
                    return 1;

                case SIM_EXEC_RESET: {
                    ctx->speaker_toggles = 0;
                    set_bit(ctx->state, OFF_RESET, 1);
                    for (int i = 0; i < 14; i++) run_14m_cycle(ctx);
                    set_bit(ctx->state, OFF_RESET, 0);
                    for (int i = 0; i < 140; i++) run_14m_cycle(ctx);
                    ctx->cycle_count = 0;
                    if (out_value) *out_value = 1;
                    return 1;
                }

                case SIM_EXEC_RUN_TICKS: {
                    uint32_t ticks = arg0;
                    for (uint32_t i = 0; i < ticks; i++) run_14m_cycle(ctx);
                    if (out_value) *out_value = ticks;
                    return 1;
                }

                case SIM_EXEC_SIGNAL_COUNT:
                    if (out_value) *out_value = SIGNAL_COUNT;
                    return 1;

                case SIM_EXEC_REG_COUNT:
                    if (out_value) *out_value = 0;
                    return 1;

                default:
                    return 0;
                }
            }

            __attribute__((export_name("sim_trace")))
            int32_t sim_trace(void *ctx, uint32_t op, const char *str_arg, uint32_t *out_value) {
                (void)ctx; (void)str_arg;
                /* Tracing not supported in arcilator WASM backend */
                if (out_value) *out_value = 0;
                return (op == 3) ? 1 : 0; /* op 3 = ENABLED → return ok but value=0 (disabled) */
            }

            /* Build input/output name CSV strings */
            #{generate_name_csv_strings(signal_table)}

            __attribute__((export_name("sim_blob")))
            uint32_t sim_blob(void *ctx, uint32_t op, uint8_t *out_ptr, uint32_t out_len) {
                (void)ctx;
                const char *data = NULL;
                uint32_t data_len = 0;

                switch (op) {
                case SIM_BLOB_INPUT_NAMES:
                    data = g_input_names_csv;
                    data_len = g_input_names_csv_len;
                    break;
                case SIM_BLOB_OUTPUT_NAMES:
                    data = g_output_names_csv;
                    data_len = g_output_names_csv_len;
                    break;
                default:
                    return 0;
                }

                if (!out_ptr || out_len == 0) return data_len;
                uint32_t copy = data_len < out_len ? data_len : out_len;
                arc_memcpy(out_ptr, data, copy);
                return copy;
            }

            /* ---- Runner extension API (Apple II specific) ---- */

            __attribute__((export_name("runner_get_caps")))
            int32_t runner_get_caps(const void *ctx, uint32_t *caps_out) {
                if (!ctx || !caps_out) return 0;
                /* RunnerCaps: { kind, mem_spaces, control_ops, probe_ops } */
                caps_out[0] = RUNNER_KIND_APPLE2;  /* kind */
                caps_out[1] = (1u << RUNNER_MEM_SPACE_MAIN) | (1u << RUNNER_MEM_SPACE_ROM); /* mem_spaces */
                caps_out[2] = (1u << RUNNER_CONTROL_SET_RESET_VECTOR) | (1u << RUNNER_CONTROL_RESET_SPEAKER); /* control_ops */
                caps_out[3] = (1u << RUNNER_PROBE_KIND) | (1u << RUNNER_PROBE_IS_MODE)
                            | (1u << RUNNER_PROBE_SPEAKER_TOGGLES) | (1u << RUNNER_PROBE_SIGNAL); /* probe_ops */
                return 1;
            }

            __attribute__((export_name("runner_mem")))
            uint32_t runner_mem(void *ctx_ptr, uint32_t op, uint32_t space,
                                uint32_t offset, uint8_t *data, uint32_t len, uint32_t flags) {
                SimContext *ctx = (SimContext *)ctx_ptr;
                if (!ctx || !data) return 0;
                (void)flags;

                uint8_t *mem = NULL;
                uint32_t mem_size = 0;
                uint32_t mem_offset = offset;

                switch (space) {
                case RUNNER_MEM_SPACE_MAIN:
                    mem = ctx->ram;
                    mem_size = RAM_SIZE;
                    break;
                case RUNNER_MEM_SPACE_ROM:
                    mem = ctx->rom;
                    mem_size = ROM_SIZE;
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
                    /* For mapped reads on MAIN, route through the full address space */
                    if (space == RUNNER_MEM_SPACE_MAIN && (flags & RUNNER_MEM_FLAG_MAPPED)) {
                        uint32_t count = 0;
                        for (uint32_t i = 0; i < len; i++) {
                            uint32_t addr = (offset + i) & 0xFFFF;
                            if (addr >= 0xD000)
                                data[i] = (addr - 0xD000 < ROM_SIZE) ? ctx->rom[addr - 0xD000] : 0;
                            else if (addr >= 0xC000)
                                data[i] = 0;
                            else if (addr < RAM_SIZE)
                                data[i] = ctx->ram[addr];
                            else
                                data[i] = 0;
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
            int32_t runner_run(void *ctx_ptr, uint32_t cycles, uint8_t key_data,
                               int32_t key_ready, uint32_t mode, RunnerRunResult *result) {
                SimContext *ctx = (SimContext *)ctx_ptr;
                if (!ctx) return 0;
                (void)key_data; (void)key_ready; (void)mode;

                ctx->text_dirty = 0;
                ctx->speaker_toggles = 0;

                uint32_t n_14m = cycles * ctx->sub_cycles;
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
            int32_t runner_control(void *ctx_ptr, uint32_t op, uint32_t arg0, uint32_t arg1) {
                SimContext *ctx = (SimContext *)ctx_ptr;
                if (!ctx) return 0;
                (void)arg1;

                switch (op) {
                case RUNNER_CONTROL_SET_RESET_VECTOR:
                    /* Write reset vector to ROM ($FFFC/$FFFD → rom offset $2FFC/$2FFD) */
                    if (0x2FFC < ROM_SIZE && 0x2FFD < ROM_SIZE) {
                        ctx->rom[0x2FFC] = (uint8_t)(arg0 & 0xFF);
                        ctx->rom[0x2FFD] = (uint8_t)((arg0 >> 8) & 0xFF);
                    }
                    return 1;

                case RUNNER_CONTROL_RESET_SPEAKER:
                    ctx->speaker_toggles = 0;
                    return 1;

                default:
                    return 0;
                }
            }

            __attribute__((export_name("runner_probe")))
            uint32_t runner_probe(const void *ctx_ptr, uint32_t op, uint32_t arg0) {
                const SimContext *ctx = (const SimContext *)ctx_ptr;
                if (!ctx) return 0;

                switch (op) {
                case RUNNER_PROBE_KIND:
                    return RUNNER_KIND_APPLE2;
                case RUNNER_PROBE_IS_MODE:
                    return 1;
                case RUNNER_PROBE_SPEAKER_TOGGLES:
                    return ctx->speaker_toggles;
                case RUNNER_PROBE_SIGNAL:
                    if (arg0 < SIGNAL_COUNT)
                        return signal_peek(&g_signal_table[arg0], ctx->state);
                    return 0;
                default:
                    return 0;
                }
            }
          C
        end

        # Map signal bit width to C type constant.
        def signal_width_type(num_bits)
          case num_bits
          when 1 then 'SIG_BIT'
          when 2..8 then 'SIG_U8'
          when 9..16 then 'SIG_U16'
          else 'SIG_U32'
          end
        end

        # Known Apple II input signal names.
        INPUT_SIGNALS = %w[
          clk_14m reset ram_do ps2_clk ps2_data pause gameport pd flash_clk
        ].freeze

        # Known Apple II output signal names.
        OUTPUT_SIGNALS = %w[
          ram_addr ram_we d speaker video color_line hbl vbl
          pc_debug a_debug x_debug y_debug s_debug p_debug opcode_debug
          io_select device_select pdl_strobe stb read_key
          an clk_2m pre_phase_zero
        ].freeze

        # Build the signal table entries from offsets map.
        def build_signal_table(offsets)
          entries = []

          # Add all known signals that exist in the state
          (INPUT_SIGNALS + OUTPUT_SIGNALS).each do |name|
            info = offsets[name]
            next unless info

            entries << {
              name: name,
              offset: info[:offset],
              width: signal_width_type(info[:num_bits]),
              is_input: INPUT_SIGNALS.include?(name) ? 1 : 0
            }
          end

          entries
        end

        # Generate #define lines for signal offsets.
        def generate_offset_defines(offsets)
          # Only define offsets for signals we actually use
          used = INPUT_SIGNALS + OUTPUT_SIGNALS
          lines = used.filter_map do |name|
            info = offsets[name]
            next unless info

            "#define OFF_#{name.upcase} #{info[:offset]}"
          end
          lines.join("\n")
        end

        # Generate the C signal table array.
        def generate_signal_table(entries)
          lines = ["#define SIGNAL_COUNT #{entries.size}"]
          lines << ''
          lines << 'static const SignalEntry g_signal_table[SIGNAL_COUNT] = {'

          entries.each_with_index do |e, i|
            comma = i < entries.size - 1 ? ',' : ''
            lines << "    { \"#{e[:name]}\", #{e[:offset]}, #{e[:width]}, #{e[:is_input]} }#{comma}"
          end

          lines << '};'
          lines.join("\n")
        end

        # Generate CSV name strings for sim_blob INPUT_NAMES / OUTPUT_NAMES.
        def generate_name_csv_strings(entries)
          inputs = entries.select { |e| e[:is_input] == 1 }.map { |e| e[:name] }
          outputs = entries.select { |e| e[:is_input] == 0 }.map { |e| e[:name] }

          input_csv = inputs.join(',')
          output_csv = outputs.join(',')

          <<~C
            static const char g_input_names_csv[] = "#{input_csv}";
            static const uint32_t g_input_names_csv_len = #{input_csv.length};
            static const char g_output_names_csv[] = "#{output_csv}";
            static const uint32_t g_output_names_csv_len = #{output_csv.length};
          C
        end

        # Check if a tool is available in PATH.
        def tool_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            candidate = File.join(dir, tool)
            File.file?(candidate) && File.executable?(candidate)
          end
        end

        # Run a tool and raise on failure.
        def run_tool!(*cmd)
          unless system(*cmd)
            raise "Command failed: #{cmd.join(' ')}"
          end
        end
      end
    end
  end
end
