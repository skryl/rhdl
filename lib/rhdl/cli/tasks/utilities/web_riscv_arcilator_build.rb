# frozen_string_literal: true

require 'json'
require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Builds an arcilator-compiled RISC-V WASM module for web benchmarking.
      #
      # Pipeline:
      #   RHDL -> CIRCT MLIR -> arcilator -> LLVM IR
      #   -> clang --target=wasm32 -> wasm-ld -> riscv_arcilator.wasm
      module WebRiscvArcilatorBuild
        PROJECT_ROOT = File.expand_path('../../../../..', __dir__)
        BUILD_DIR = File.join(PROJECT_ROOT, 'web', 'build', 'arcilator', 'riscv_build')

        FIRRTL_FILE = File.join(BUILD_DIR, 'riscv_cpu.fir')
        PARSED_MLIR_FILE = File.join(BUILD_DIR, 'riscv_cpu_parsed.mlir')
        LOWERED_MLIR_FILE = File.join(BUILD_DIR, 'riscv_cpu_lowered.mlir')
        MLIR_FILE = File.join(BUILD_DIR, 'riscv_cpu_hw.mlir')
        LL_FILE = File.join(BUILD_DIR, 'riscv_cpu_arc.ll')
        WASM_LL_FILE = File.join(BUILD_DIR, 'riscv_cpu_arc_wasm.ll')
        STATE_FILE = File.join(BUILD_DIR, 'riscv_cpu_state.json')
        WRAPPER_SOURCE = File.join(BUILD_DIR, 'riscv_arc_wasm_wrapper.cpp')
        OBJ_ARC = File.join(BUILD_DIR, 'riscv_cpu_arc.o')
        OBJ_WRAPPER = File.join(BUILD_DIR, 'riscv_arc_wasm_wrapper.o')
        WASM_OUTPUT = File.join(BUILD_DIR, 'riscv_arcilator.wasm')

        PKG_DIR = File.join(PROJECT_ROOT, 'web', 'assets', 'pkg')
        PKG_OUTPUT = File.join(PKG_DIR, 'riscv_arcilator.wasm')

        REQUIRED_TOOLS = %w[arcilator clang wasm-ld].freeze
        DEFAULT_MEM_SIZE = 128 * 1024 * 1024
        # Arcilator wrapper uses a fixed bump heap for malloc/calloc.
        # Keep enough room for inst+data memories, disk image buffer, and runtime state.
        HEAP_SIZE = 320 * 1024 * 1024
        INITIAL_MEMORY = 384 * 1024 * 1024
        MAX_MEMORY = 768 * 1024 * 1024

        REQUIRED_SIGNALS = %w[
          clk rst irq_software irq_timer irq_external
          inst_data data_rdata debug_reg_addr
          inst_ptw_pte0 inst_ptw_pte1 data_ptw_pte0 data_ptw_pte1
          inst_addr inst_ptw_addr0 inst_ptw_addr1
          data_addr data_wdata data_we data_re data_funct3
          data_ptw_addr0 data_ptw_addr1
          debug_pc debug_inst debug_x1 debug_x2 debug_x10 debug_x11 debug_reg_data
        ].freeze

        module_function

        # Build the arcilator RISC-V WASM module.
        # Returns true if built, false if skipped.
        def build(dest_dir: PKG_DIR)
          missing = missing_tools
          unless missing.empty?
            warn "WARNING: RISC-V arcilator WASM build skipped; missing tools: #{missing.join(', ')}"
            return false
          end

          FileUtils.mkdir_p(BUILD_DIR)
          FileUtils.mkdir_p(dest_dir)

          puts 'Building arcilator RISC-V WASM module...'

          export_firrtl
          compile_firrtl_to_mlir
          compile_mlir_to_llvm_ir
          state = parse_state_json
          generate_c_wrapper(state)
          compile_llvm_ir_to_wasm_obj
          compile_wrapper_to_wasm_obj
          link_wasm
          install_wasm(dest_dir)

          puts "  Wrote #{File.join(dest_dir, 'riscv_arcilator.wasm')}"
          true
        end

        def missing_tools
          REQUIRED_TOOLS.select { |tool| !tool_available?(tool) }
        end

        def tools_available?
          missing_tools.empty?
        end

        def export_firrtl
          puts '  Exporting RISC-V CPU to CIRCT MLIR...'
          require File.join(PROJECT_ROOT, 'examples/riscv/hdl/cpu')
          require 'rhdl/codegen'

          flat_nodes = RHDL::Examples::RISCV::CPU.to_flat_circt_nodes(top_name: 'riscv_cpu')
          mlir = RHDL::Codegen::CIRCT::MLIR.generate(flat_nodes)
          File.write(MLIR_FILE, mlir)
        end

        def compile_firrtl_to_mlir
          puts '  CIRCT MLIR already emitted; skipping FIRRTL lowering step.'
        end

        def compile_mlir_to_llvm_ir
          puts '  Compiling MLIR -> LLVM IR (arcilator)...'
          run_tool!('arcilator', MLIR_FILE, '--observe-registers', "--state-file=#{STATE_FILE}", '-o', LL_FILE)
        end

        def parse_state_json
          puts '  Parsing arcilator state layout...'
          raw = JSON.parse(File.read(STATE_FILE))
          mod = raw[0] || {}
          states = mod['states'] || []
          offsets = {}
          states.each { |s| offsets[s['name']] = { offset: s['offset'], num_bits: s['numBits'] || 1 } }

          ensure_required_offsets!(offsets)

          actual_size = states.map { |s| s['offset'] + ((s['numBits'] || 1) + 7) / 8 }.max || 0
          state_size = [mod['numStateBytes'].to_i, actual_size].max
          puts "  State buffer: #{offsets.size} signals, #{state_size} bytes used"

          { offsets: offsets, state_size: state_size }
        end

        def generate_c_wrapper(state)
          puts '  Generating WASM C wrapper...'
          source = build_wrapper_source(offsets: state[:offsets], state_size: state[:state_size])
          File.write(WRAPPER_SOURCE, source)
        end

        def compile_llvm_ir_to_wasm_obj
          puts '  Compiling LLVM IR -> wasm32 object...'
          ll_content = File.read(LL_FILE)
          File.write(WASM_LL_FILE, rewrite_llvm_ir_for_wasm32(ll_content))

          run_tool!(
            'clang', '--target=wasm32-unknown-unknown',
            '-O2', '-c', '-fPIC',
            '-Wno-override-module',
            WASM_LL_FILE, '-o', OBJ_ARC
          )
        end

        def compile_wrapper_to_wasm_obj
          puts '  Compiling C wrapper -> wasm32 object...'
          run_tool!(
            'clang', '--target=wasm32-unknown-unknown',
            '-O2', '-c', '-fPIC', '-ffreestanding',
            '-Wno-incompatible-library-redeclaration',
            WRAPPER_SOURCE, '-o', OBJ_WRAPPER
          )
        end

        def link_wasm
          puts '  Linking WASM module...'
          run_tool!(
            'wasm-ld',
            '--no-entry',
            '--export-dynamic',
            '--export-memory',
            "--initial-memory=#{INITIAL_MEMORY}",
            "--max-memory=#{MAX_MEMORY}",
            '-o', WASM_OUTPUT,
            OBJ_WRAPPER, OBJ_ARC
          )
        end

        def install_wasm(dest_dir)
          FileUtils.cp(WASM_OUTPUT, File.join(dest_dir, 'riscv_arcilator.wasm'))
        end

        def rewrite_llvm_ir_for_wasm32(ll_content)
          ll_content.lines.map do |line|
            if line.start_with?('target datalayout')
              "target datalayout = \"e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20\"\n"
            elsif line.start_with?('target triple')
              "target triple = \"wasm32-unknown-unknown\"\n"
            elsif line.include?('i64') && line.include?('ptrtoint')
              line.gsub(/ptrtoint\s+([^)]+)\s+to\s+i64/, 'ptrtoint \\1 to i32')
            else
              line
            end
          end.join
        end

        def ensure_required_offsets!(offsets)
          missing = REQUIRED_SIGNALS.reject { |name| offsets.key?(name) }
          return if missing.empty?

          raise "Missing required RISC-V signals in arcilator state: #{missing.join(', ')}"
        end

        def required_offset_defines(offsets)
          defines = REQUIRED_SIGNALS.map do |name|
            "#define OFF_#{name.upcase} #{offsets.fetch(name)[:offset]}"
          end
          if offsets.key?('pc_reg__pc')
            defines << "#define OFF_PC_REG__PC #{offsets.fetch('pc_reg__pc')[:offset]}"
          end
          defines.join("\n")
        end

        def load_runner_cycle_sources
          require File.join(PROJECT_ROOT, 'examples/riscv/utilities/runners/arcilator_runner')

          runner = RHDL::Examples::RISCV::ArcilatorRunner.allocate
          [runner.send(:riscv_sim_common_types), runner.send(:riscv_sim_run_cycles_impl)]
        end

        def build_wrapper_source(offsets:, state_size:)
          common_types, run_cycles_impl = load_runner_cycle_sources
          offset_defines = required_offset_defines(offsets)

          <<~C
            /* Auto-generated arcilator WASM wrapper for RISC-V web benchmark. */

            typedef unsigned char uint8_t;
            typedef unsigned short uint16_t;
            typedef unsigned int uint32_t;
            typedef unsigned long long uint64_t;
            typedef signed char int8_t;
            typedef short int16_t;
            typedef int int32_t;
            typedef long long int64_t;
            typedef unsigned int size_t;

            #define NULL ((void*)0)
            #define STATE_SIZE #{state_size}
            #define DEFAULT_MEM_SIZE #{DEFAULT_MEM_SIZE}
            #define HEAP_SIZE #{HEAP_SIZE}

            static void *arc_memset(void *s, int c, size_t n) {
                uint8_t *p = (uint8_t *)s;
                while (n--) *p++ = (uint8_t)c;
                return s;
            }

            static void *arc_memcpy(void *d, const void *s, size_t n) {
                uint8_t *dp = (uint8_t *)d;
                const uint8_t *sp = (const uint8_t *)s;
                while (n--) *dp++ = *sp++;
                return d;
            }

            static void *arc_memmove(void *d, const void *s, size_t n) {
                uint8_t *dp = (uint8_t *)d;
                const uint8_t *sp = (const uint8_t *)s;
                if (dp < sp || dp >= sp + n) return arc_memcpy(d, s, n);
                dp += n; sp += n;
                while (n--) *--dp = *--sp;
                return d;
            }

            static int arc_memcmp(const void *a, const void *b, size_t n) {
                const uint8_t *ap = (const uint8_t *)a;
                const uint8_t *bp = (const uint8_t *)b;
                while (n--) {
                    if (*ap != *bp) return (int)(*ap) - (int)(*bp);
                    ap++;
                    bp++;
                }
                return 0;
            }

            static int arc_strcmp(const char *a, const char *b) {
                while (*a && *a == *b) {
                    a++;
                    b++;
                }
                return (unsigned char)*a - (unsigned char)*b;
            }

            void *memset(void *s, int c, size_t n) { return arc_memset(s, c, n); }
            void *memcpy(void *d, const void *s, size_t n) { return arc_memcpy(d, s, n); }
            void *memmove(void *d, const void *s, size_t n) { return arc_memmove(d, s, n); }
            int memcmp(const void *a, const void *b, size_t n) { return arc_memcmp(a, b, n); }
            int strcmp(const char *a, const char *b) { return arc_strcmp(a, b); }

            typedef struct {
                uint32_t offset;
                uint32_t size;
                uint8_t used;
            } AllocRec;

            static uint8_t g_heap[HEAP_SIZE];
            static uint32_t g_heap_offset = 0;
            static AllocRec g_allocs[4096];

            static int alloc_find_index(void *ptr) {
                if (!ptr) return -1;
                uint8_t *bp = (uint8_t *)ptr;
                if (bp < g_heap || bp >= (g_heap + HEAP_SIZE)) return -1;
                uint32_t off = (uint32_t)(bp - g_heap);
                for (uint32_t i = 0; i < 4096; i++) {
                    if (g_allocs[i].used && g_allocs[i].offset == off) return (int)i;
                }
                return -1;
            }

            static void alloc_mark(void *ptr, uint32_t size) {
                if (!ptr || size == 0) return;
                uint8_t *bp = (uint8_t *)ptr;
                uint32_t off = (uint32_t)(bp - g_heap);
                for (uint32_t i = 0; i < 4096; i++) {
                    if (!g_allocs[i].used) {
                        g_allocs[i].used = 1;
                        g_allocs[i].offset = off;
                        g_allocs[i].size = size;
                        return;
                    }
                }
            }

            void *malloc(size_t size) {
                if (size == 0) size = 1;
                uint32_t aligned = (g_heap_offset + 7u) & ~7u;
                if ((uint64_t)aligned + (uint64_t)size > (uint64_t)HEAP_SIZE) return NULL;
                void *ptr = &g_heap[aligned];
                g_heap_offset = aligned + (uint32_t)size;
                alloc_mark(ptr, (uint32_t)size);
                return ptr;
            }

            void free(void *ptr) {
                int idx = alloc_find_index(ptr);
                if (idx >= 0) g_allocs[(uint32_t)idx].used = 0;
            }

            void *calloc(size_t nmemb, size_t size) {
                uint64_t total64 = (uint64_t)nmemb * (uint64_t)size;
                if (total64 == 0) total64 = 1;
                if (total64 > 0xFFFFFFFFull) return NULL;
                void *ptr = malloc((size_t)total64);
                if (!ptr) return NULL;
                arc_memset(ptr, 0, (size_t)total64);
                return ptr;
            }

            void *realloc(void *ptr, size_t size) {
                if (!ptr) return malloc(size);
                if (size == 0) {
                    free(ptr);
                    return NULL;
                }

                int idx = alloc_find_index(ptr);
                uint32_t old_size = 0;
                if (idx >= 0) old_size = g_allocs[(uint32_t)idx].size;

                void *next = malloc(size);
                if (!next) return NULL;

                uint32_t copy_size = old_size < (uint32_t)size ? old_size : (uint32_t)size;
                if (copy_size > 0) arc_memcpy(next, ptr, copy_size);
                free(ptr);
                return next;
            }

            __attribute__((export_name("sim_wasm_alloc")))
            void *sim_wasm_alloc(uint32_t size) {
                return malloc(size);
            }

            __attribute__((export_name("sim_wasm_dealloc")))
            void sim_wasm_dealloc(void *ptr, uint32_t size) {
                (void)size;
                free(ptr);
            }

            extern "C" void riscv_cpu_eval(void *state);

            #{offset_defines}

            #{common_types}

            typedef struct {
                uint8_t state[STATE_SIZE];
                MemState mem;
                uint8_t trace_enabled;
            } SimContext;

            static inline void set_u8(uint8_t *s, int o, uint8_t v) { s[o] = v; }
            static inline uint8_t get_u8(uint8_t *s, int o) { return s[o]; }
            static inline void set_u32(uint8_t *s, int o, uint32_t v) { memcpy(&s[o], &v, 4); }
            static inline uint32_t get_u32(uint8_t *s, int o) { uint32_t v; memcpy(&v, &s[o], 4); return v; }
            static inline void set_bit(uint8_t *s, int o, uint8_t v) { s[o] = v & 1; }
            static inline uint8_t get_bit(uint8_t *s, int o) { return s[o] & 1; }
            static inline void set_u3(uint8_t *s, int o, uint8_t v) { s[o] = v & 0x7; }
            static inline uint8_t get_u3(uint8_t *s, int o) { return s[o] & 0x7; }
            static inline void set_u5(uint8_t *s, int o, uint8_t v) { s[o] = v & 0x1F; }

            #define CTX(c)                ((SimContext*)(c))
            #define DUT_CLK(c)            (CTX(c)->state[OFF_CLK])
            #define DUT_RST(c)            (CTX(c)->state[OFF_RST])
            #define DUT_IRQ_SOFTWARE(c)   (CTX(c)->state[OFF_IRQ_SOFTWARE])
            #define DUT_IRQ_TIMER(c)      (CTX(c)->state[OFF_IRQ_TIMER])
            #define DUT_IRQ_EXTERNAL(c)   (CTX(c)->state[OFF_IRQ_EXTERNAL])
            #define DUT_INST_DATA(c)      (*(uint32_t*)(&CTX(c)->state[OFF_INST_DATA]))
            #define DUT_DATA_RDATA(c)     (*(uint32_t*)(&CTX(c)->state[OFF_DATA_RDATA]))
            #define DUT_DEBUG_REG_ADDR(c) (CTX(c)->state[OFF_DEBUG_REG_ADDR])
            #define DUT_INST_PTW_PTE0(c)  (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_PTE0]))
            #define DUT_INST_PTW_PTE1(c)  (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_PTE1]))
            #define DUT_DATA_PTW_PTE0(c)  (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_PTE0]))
            #define DUT_DATA_PTW_PTE1(c)  (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_PTE1]))
            #define DUT_INST_ADDR(c)      (*(uint32_t*)(&CTX(c)->state[OFF_INST_ADDR]))
            #define DUT_INST_PTW_ADDR0(c) (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_ADDR0]))
            #define DUT_INST_PTW_ADDR1(c) (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_ADDR1]))
            #define DUT_DATA_ADDR(c)      (*(uint32_t*)(&CTX(c)->state[OFF_DATA_ADDR]))
            #define DUT_DATA_WDATA(c)     (*(uint32_t*)(&CTX(c)->state[OFF_DATA_WDATA]))
            #define DUT_DATA_WE(c)        (CTX(c)->state[OFF_DATA_WE])
            #define DUT_DATA_RE(c)        (CTX(c)->state[OFF_DATA_RE])
            #define DUT_DATA_FUNCT3(c)    (CTX(c)->state[OFF_DATA_FUNCT3])
            #define DUT_DATA_PTW_ADDR0(c) (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_ADDR0]))
            #define DUT_DATA_PTW_ADDR1(c) (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_ADDR1]))
            #define DUT_DEBUG_PC(c)       (*(uint32_t*)(&CTX(c)->state[OFF_DEBUG_PC]))
            #define DUT_EVAL(c)           riscv_cpu_eval(CTX(c)->state)

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

            static const char *k_input_signal_names[] = {
                "clk", "rst", "irq_software", "irq_timer", "irq_external",
                "inst_data", "data_rdata", "debug_reg_addr",
                "inst_ptw_pte0", "inst_ptw_pte1", "data_ptw_pte0", "data_ptw_pte1"
            };
            static const char *k_output_signal_names[] = {
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
            static const uint32_t k_input_signal_count = (uint32_t)(sizeof(k_input_signal_names) / sizeof(k_input_signal_names[0]));
            static const uint32_t k_output_signal_count = (uint32_t)(sizeof(k_output_signal_names) / sizeof(k_output_signal_names[0]));

            static uint32_t cstr_len(const char *text) {
                uint32_t n = 0;
                if (!text) return 0;
                while (text[n]) n++;
                return n;
            }

            static uint32_t total_signal_count(void) {
                return k_input_signal_count + k_output_signal_count;
            }

            static const char *signal_name_from_index(uint32_t idx) {
                if (idx < k_input_signal_count) return k_input_signal_names[idx];
                idx -= k_input_signal_count;
                if (idx < k_output_signal_count) return k_output_signal_names[idx];
                return (const char *)0;
            }

            static int32_t signal_index_from_name(const char *name) {
                if (!name) return -1;
                for (uint32_t i = 0; i < k_input_signal_count; i++) {
                    if (!strcmp(name, k_input_signal_names[i])) return (int32_t)i;
                }
                for (uint32_t i = 0; i < k_output_signal_count; i++) {
                    if (!strcmp(name, k_output_signal_names[i])) return (int32_t)(k_input_signal_count + i);
                }
                return -1;
            }

            static void write_out_u32(uint32_t *out, uint32_t value) {
                if (out) *out = value;
            }

            static uint32_t blob_write_text(const char *text, uint8_t *ptr, uint32_t max_bytes) {
                uint32_t len = cstr_len(text);
                if (!ptr || max_bytes == 0) return len;
                uint32_t n = len < max_bytes ? len : max_bytes;
                if (n > 0) memcpy(ptr, text, n);
                return n;
            }

            static uint32_t read_mem_bytes(SimContext *ctx, int32_t mem_type, uint32_t offset, uint8_t *out, uint32_t len) {
                if (!ctx || !out || len == 0) return 0;
                const uint8_t *mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
                for (uint32_t i = 0; i < len; i++) {
                    uint32_t byte_addr = offset + i;
                    uint32_t aligned = byte_addr & ~3u;
                    uint32_t shift = (byte_addr & 3u) * 8u;
                    uint32_t word = read_word_le(mem, ctx->mem.mem_mask, aligned);
                    out[i] = (uint8_t)((word >> shift) & 0xFFu);
                }
                return len;
            }

            static uint32_t read_uart_tx_bytes(SimContext *ctx, uint32_t offset, uint8_t *out, uint32_t len) {
                if (!ctx || !out || len == 0) return 0;
                uint32_t available = uart_tx_len(&ctx->mem);
                if (offset >= available) return 0;
                uint32_t n = available - offset;
                if (n > len) n = len;
                memcpy(out, ctx->mem.uart_tx_bytes + offset, n);
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

            __attribute__((export_name("sim_create")))
            void *sim_create(const char *json, uint32_t json_len, uint32_t sub_cycles, uint32_t *err_out) {
                (void)json;
                (void)json_len;
                (void)sub_cycles;
                write_out_u32(err_out, 0);
                SimContext *ctx = (SimContext *)calloc(1, sizeof(SimContext));
                if (!ctx) return NULL;

                mem_init(&ctx->mem, DEFAULT_MEM_SIZE);
                set_bit(ctx->state, OFF_CLK, 0);
                set_bit(ctx->state, OFF_RST, 1);
                set_bit(ctx->state, OFF_IRQ_SOFTWARE, 0);
                set_bit(ctx->state, OFF_IRQ_TIMER, 0);
                set_bit(ctx->state, OFF_IRQ_EXTERNAL, 0);
                set_u32(ctx->state, OFF_INST_DATA, 0);
                set_u32(ctx->state, OFF_DATA_RDATA, 0);
                set_u5(ctx->state, OFF_DEBUG_REG_ADDR, 0);
                set_u32(ctx->state, OFF_INST_PTW_PTE0, 0);
                set_u32(ctx->state, OFF_INST_PTW_PTE1, 0);
                set_u32(ctx->state, OFF_DATA_PTW_PTE0, 0);
                set_u32(ctx->state, OFF_DATA_PTW_PTE1, 0);
                ctx->trace_enabled = 0;
                riscv_cpu_eval(ctx->state);
                return ctx;
            }

            __attribute__((export_name("sim_destroy")))
            void sim_destroy(void *sim) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                mem_free(&ctx->mem);
                free(ctx);
            }

            __attribute__((export_name("sim_reset")))
            void sim_reset(void *sim) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                set_bit(ctx->state, OFF_RST, 1);
                set_bit(ctx->state, OFF_CLK, 0);
                riscv_cpu_eval(ctx->state);
                set_bit(ctx->state, OFF_CLK, 1);
                riscv_cpu_eval(ctx->state);
                set_bit(ctx->state, OFF_CLK, 0);
                set_bit(ctx->state, OFF_RST, 0);
                riscv_cpu_eval(ctx->state);
            }

            __attribute__((export_name("sim_eval")))
            void sim_eval(void *sim) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                riscv_cpu_eval(ctx->state);
            }

            __attribute__((export_name("sim_poke")))
            void sim_poke(void *sim, const char *name, uint32_t value) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx || !name) return;
                if      (!strcmp(name, "clk"))             set_bit(ctx->state, OFF_CLK, value);
                else if (!strcmp(name, "rst"))             set_bit(ctx->state, OFF_RST, value);
                else if (!strcmp(name, "irq_software"))    set_bit(ctx->state, OFF_IRQ_SOFTWARE, value);
                else if (!strcmp(name, "irq_timer"))       set_bit(ctx->state, OFF_IRQ_TIMER, value);
                else if (!strcmp(name, "irq_external"))    set_bit(ctx->state, OFF_IRQ_EXTERNAL, value);
                else if (!strcmp(name, "inst_data"))       set_u32(ctx->state, OFF_INST_DATA, value);
                else if (!strcmp(name, "data_rdata"))      set_u32(ctx->state, OFF_DATA_RDATA, value);
                else if (!strcmp(name, "debug_reg_addr"))  set_u5(ctx->state, OFF_DEBUG_REG_ADDR, value);
                else if (!strcmp(name, "inst_ptw_pte0"))   set_u32(ctx->state, OFF_INST_PTW_PTE0, value);
                else if (!strcmp(name, "inst_ptw_pte1"))   set_u32(ctx->state, OFF_INST_PTW_PTE1, value);
                else if (!strcmp(name, "data_ptw_pte0"))   set_u32(ctx->state, OFF_DATA_PTW_PTE0, value);
                else if (!strcmp(name, "data_ptw_pte1"))   set_u32(ctx->state, OFF_DATA_PTW_PTE1, value);
            }

            __attribute__((export_name("sim_peek")))
            uint32_t sim_peek(void *sim, const char *name) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx || !name) return 0;
                if      (!strcmp(name, "inst_addr"))       return get_u32(ctx->state, OFF_INST_ADDR);
                else if (!strcmp(name, "inst_ptw_addr0"))  return get_u32(ctx->state, OFF_INST_PTW_ADDR0);
                else if (!strcmp(name, "inst_ptw_addr1"))  return get_u32(ctx->state, OFF_INST_PTW_ADDR1);
                else if (!strcmp(name, "data_addr"))       return get_u32(ctx->state, OFF_DATA_ADDR);
                else if (!strcmp(name, "data_wdata"))      return get_u32(ctx->state, OFF_DATA_WDATA);
                else if (!strcmp(name, "data_we"))         return get_bit(ctx->state, OFF_DATA_WE);
                else if (!strcmp(name, "data_re"))         return get_bit(ctx->state, OFF_DATA_RE);
                else if (!strcmp(name, "data_funct3"))     return get_u3(ctx->state, OFF_DATA_FUNCT3);
                else if (!strcmp(name, "data_ptw_addr0"))  return get_u32(ctx->state, OFF_DATA_PTW_ADDR0);
                else if (!strcmp(name, "data_ptw_addr1"))  return get_u32(ctx->state, OFF_DATA_PTW_ADDR1);
                else if (!strcmp(name, "debug_pc"))        return get_u32(ctx->state, OFF_DEBUG_PC);
                else if (!strcmp(name, "debug_inst"))      return get_u32(ctx->state, OFF_DEBUG_INST);
                else if (!strcmp(name, "debug_x1"))        return get_u32(ctx->state, OFF_DEBUG_X1);
                else if (!strcmp(name, "debug_x2"))        return get_u32(ctx->state, OFF_DEBUG_X2);
                else if (!strcmp(name, "debug_x10"))       return get_u32(ctx->state, OFF_DEBUG_X10);
                else if (!strcmp(name, "debug_x11"))       return get_u32(ctx->state, OFF_DEBUG_X11);
                else if (!strcmp(name, "debug_reg_data"))  return get_u32(ctx->state, OFF_DEBUG_REG_DATA);
                return 0;
            }

            __attribute__((export_name("sim_write_pc")))
            void sim_write_pc(void *sim, uint32_t value) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                #ifdef OFF_PC_REG__PC
                set_u32(ctx->state, OFF_PC_REG__PC, value);
                #endif
                riscv_cpu_eval(ctx->state);
            }

            __attribute__((export_name("sim_load_mem")))
            void sim_load_mem(void *sim, int32_t mem_type, const uint8_t *data, uint32_t size, uint32_t base_addr) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                load_mem(&ctx->mem, mem_type, data, size, base_addr);
            }

            __attribute__((export_name("sim_read_mem_word")))
            uint32_t sim_read_mem_word(void *sim, int32_t mem_type, uint32_t addr) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return 0;
                const uint8_t *mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
                return read_word_le(mem, ctx->mem.mem_mask, addr);
            }

            __attribute__((export_name("sim_run_cycles")))
            void sim_run_cycles(void *sim, uint32_t n_cycles) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                run_cycles_impl(ctx, &ctx->mem, n_cycles);
            }

            __attribute__((export_name("sim_uart_rx_push")))
            void sim_uart_rx_push(void *sim, const uint8_t *data, uint32_t len) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                uart_rx_queue_push_bytes(&ctx->mem, data, len);
            }

            __attribute__((export_name("sim_uart_tx_len")))
            uint32_t sim_uart_tx_len(void *sim) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return 0;
                return uart_tx_len(&ctx->mem);
            }

            __attribute__((export_name("sim_uart_tx_copy")))
            uint32_t sim_uart_tx_copy(void *sim, uint8_t *out, uint32_t max_len) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return 0;
                return uart_tx_copy(&ctx->mem, out, max_len);
            }

            __attribute__((export_name("sim_uart_tx_clear")))
            void sim_uart_tx_clear(void *sim) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return;
                uart_tx_clear(&ctx->mem);
            }

            __attribute__((export_name("sim_disk_load")))
            uint32_t sim_disk_load(void *sim, const uint8_t *data, uint32_t size, uint32_t base_addr) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return 0;
                return (uint32_t)disk_load(&ctx->mem, data, size, base_addr);
            }

            __attribute__((export_name("sim_disk_read_byte")))
            uint32_t sim_disk_read_byte(void *sim, uint32_t offset) {
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) return 0;
                return (uint32_t)disk_read_byte(&ctx->mem, offset);
            }

            __attribute__((export_name("sim_get_caps")))
            uint32_t sim_get_caps(void *sim, uint32_t *out_caps) {
                (void)sim;
                write_out_u32(out_caps, SIM_CAP_SIGNAL_INDEX | SIM_CAP_TRACE | SIM_CAP_RUNNER_INTERP_JIT);
                return 1;
            }

            __attribute__((export_name("sim_signal")))
            uint32_t sim_signal(void *sim, uint32_t op, const char *name, uint32_t idx, uint32_t value, uint32_t *out_value) {
                int32_t resolved_idx = -1;
                const char *resolved_name = 0;
                if (name && name[0]) {
                    resolved_idx = signal_index_from_name(name);
                    resolved_name = name;
                } else {
                    resolved_name = signal_name_from_index(idx);
                    resolved_idx = (resolved_name ? (int32_t)idx : -1);
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
                        write_out_u32(out_value, (uint32_t)resolved_idx);
                        return 1;
                    case SIM_SIGNAL_PEEK:
                    case SIM_SIGNAL_PEEK_INDEX:
                        if (resolved_idx < 0 || !resolved_name) {
                            write_out_u32(out_value, 0);
                            return 0;
                        }
                        write_out_u32(out_value, sim_peek(sim, resolved_name));
                        return 1;
                    case SIM_SIGNAL_POKE:
                    case SIM_SIGNAL_POKE_INDEX:
                        if (resolved_idx < 0 || !resolved_name) {
                            write_out_u32(out_value, 0);
                            return 0;
                        }
                        sim_poke(sim, resolved_name, value);
                        write_out_u32(out_value, 1);
                        return 1;
                    default:
                        write_out_u32(out_value, 0);
                        return 0;
                }
            }

            __attribute__((export_name("sim_exec")))
            uint32_t sim_exec(void *sim, uint32_t op, uint32_t arg0, uint32_t arg1, uint32_t *out_value, uint32_t *err_out) {
                (void)arg1;
                write_out_u32(err_out, 0);
                switch (op) {
                    case SIM_EXEC_EVALUATE:
                        sim_eval(sim);
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_TICK:
                    case SIM_EXEC_TICK_FORCED:
                        sim_run_cycles(sim, 1);
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_SET_PREV_CLOCK:
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_GET_CLOCK_LIST_IDX:
                        write_out_u32(out_value, 0xFFFFFFFFu);
                        return 1;
                    case SIM_EXEC_RESET:
                        sim_reset(sim);
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_RUN_TICKS:
                        sim_run_cycles(sim, arg0);
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_SIGNAL_COUNT:
                        write_out_u32(out_value, total_signal_count());
                        return 1;
                    case SIM_EXEC_REG_COUNT:
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_EXEC_COMPILE:
                    case SIM_EXEC_IS_COMPILED:
                        write_out_u32(out_value, 1);
                        return 1;
                    default:
                        write_out_u32(out_value, 0);
                        return 0;
                }
            }

            __attribute__((export_name("sim_trace")))
            uint32_t sim_trace(void *sim, uint32_t op, const char *arg, uint32_t *out_value) {
                (void)arg;
                SimContext *ctx = (SimContext *)sim;
                if (!ctx) {
                    write_out_u32(out_value, 0);
                    return 0;
                }
                switch (op) {
                    case SIM_TRACE_START:
                    case SIM_TRACE_START_STREAMING:
                        ctx->trace_enabled = 1;
                        write_out_u32(out_value, 1);
                        return 1;
                    case SIM_TRACE_STOP:
                        ctx->trace_enabled = 0;
                        write_out_u32(out_value, 0);
                        return 1;
                    case SIM_TRACE_ENABLED:
                        write_out_u32(out_value, ctx->trace_enabled ? 1u : 0u);
                        return 1;
                    case SIM_TRACE_CHANGE_COUNT:
                        write_out_u32(out_value, 0);
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
                        write_out_u32(out_value, 0);
                        return 1;
                    default:
                        write_out_u32(out_value, 0);
                        return 0;
                }
            }

            __attribute__((export_name("sim_blob")))
            uint32_t sim_blob(void *sim, uint32_t op, uint8_t *ptr, uint32_t max_bytes) {
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
            uint32_t runner_get_caps(void *sim, uint32_t *caps_ptr) {
                (void)sim;
                if (!caps_ptr) return 0;
                caps_ptr[0] = (uint32_t)RUNNER_KIND_RISCV;
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
                void *sim,
                uint32_t op,
                uint32_t space,
                uint32_t offset,
                uint8_t *ptr,
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
                    SimContext *ctx = (SimContext *)sim;
                    if (space == RUNNER_MEM_SPACE_MAIN) {
                        uint32_t resolved = runner_main_resolve_offset(offset, flags);
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
                        uint32_t resolved = runner_main_resolve_offset(offset, flags);
                        sim_load_mem(sim, MEM_TYPE_DATA, ptr, len, resolved);
                        return len;
                    }
                    return 0;
                }

                return 0;
            }

            __attribute__((export_name("runner_run")))
            uint32_t runner_run(void *sim, uint32_t cycles, uint32_t key_data, uint32_t key_ready, uint32_t mode, uint32_t *result_ptr) {
                (void)mode;
                if (!sim) return 0;
                if (key_ready) {
                    uint8_t key = (uint8_t)(key_data & 0xFFu);
                    sim_uart_rx_push(sim, &key, 1);
                }
                sim_run_cycles(sim, cycles);
                if (result_ptr) {
                    result_ptr[0] = 0u;                        /* text_dirty */
                    result_ptr[1] = key_ready ? 1u : 0u;      /* key_cleared */
                    result_ptr[2] = cycles;                   /* cycles_run */
                    result_ptr[3] = 0u;                       /* speaker_toggles */
                    result_ptr[4] = 0u;                       /* frames_completed */
                }
                return 1;
            }

            __attribute__((export_name("runner_control")))
            uint32_t runner_control(void *sim, uint32_t op, uint32_t arg0, uint32_t arg1) {
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
            uint32_t runner_probe(void *sim, uint32_t op, uint32_t arg0) {
                if (!sim) return 0;
                if (op == RUNNER_PROBE_KIND) return (uint32_t)RUNNER_KIND_RISCV;
                if (op == RUNNER_PROBE_IS_MODE) return 1u;
                if (op == RUNNER_PROBE_RISCV_UART_TX_LEN) return sim_uart_tx_len(sim);
                if (op == RUNNER_PROBE_SIGNAL) {
                    if (arg0 < k_output_signal_count) {
                        return sim_peek(sim, k_output_signal_names[arg0]);
                    }
                    return 0;
                }
                return 0;
            }
          C
        end

        # Replicates the standard firtool FIRRTL pass pipeline, omitting comb loop checks.
        def firrtl_pipeline_without_comb_check
          'builtin.module(firrtl.circuit(' \
            'firrtl-check-recursive-instantiation,' \
            'firrtl-check-layers,' \
            'firrtl-lower-open-aggs,' \
            'firrtl-resolve-paths,' \
            'firrtl-lower-annotations{disable-annotation-classless=false disable-annotation-unknown=false no-ref-type-ports=false},' \
            'firrtl-lower-intmodules{fixup-eicg-wrapper=false},' \
            'firrtl.module(firrtl-lower-intrinsics),' \
            'firrtl-specialize-option{select-default-for-unspecified-instance-choice=false},' \
            'firrtl-lower-signatures,' \
            'firrtl-inject-dut-hier,' \
            'any(cse),' \
            'firrtl.module(firrtl-passive-wires,firrtl-drop-names{preserve-values=none},firrtl-lower-chirrtl,firrtl-lower-matches),' \
            'firrtl-infer-widths,' \
            'firrtl-mem-to-reg-of-vec{ignore-read-enable-mem=false repl-seq-mem=false},' \
            'firrtl-infer-resets,' \
            'firrtl-drop-const,' \
            'firrtl-dedup{dedup-classes=true},' \
            'firrtl.module(firrtl-flatten-memory),' \
            'firrtl-lower-types{preserve-aggregate=none preserve-memories=none},' \
            'firrtl.module(firrtl-expand-whens,firrtl-sfc-compat),' \
            'firrtl-specialize-layers,' \
            'firrtl-inliner,' \
            'firrtl.module(firrtl-layer-merge,firrtl-randomize-register-init,' \
            'canonicalize{max-iterations=10 max-num-rewrites=-1 region-simplify=disabled test-convergence=false top-down=true},' \
            'firrtl-infer-rw),' \
            'firrtl-imconstprop,' \
            'firrtl-add-seqmem-ports))'
        end

        def tool_available?(tool)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |dir|
            candidate = File.join(dir, tool)
            File.file?(candidate) && File.executable?(candidate)
          end
        end

        def run_tool!(*cmd)
          return if system(*cmd)

          raise "Command failed: #{cmd.join(' ')}"
        end
      end
    end
  end
end
