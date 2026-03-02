# frozen_string_literal: true

require 'json'
require 'fileutils'

module RHDL
  module CLI
    module Tasks
      # Builds an arcilator-compiled RISC-V WASM module for web benchmarking.
      #
      # Pipeline:
      #   RHDL -> FIRRTL -> firtool/circt-opt -> arcilator -> LLVM IR
      #   -> clang --target=wasm32 -> wasm-ld -> riscv_arcilator.wasm
      module WebRiscvArcilatorBuild
        PROJECT_ROOT = File.expand_path('../../../..', __dir__)
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

        REQUIRED_TOOLS = %w[firtool circt-opt arcilator clang wasm-ld].freeze
        DEFAULT_MEM_SIZE = 16 * 1024 * 1024
        HEAP_SIZE = 48 * 1024 * 1024
        INITIAL_MEMORY = 128 * 1024 * 1024
        MAX_MEMORY = 512 * 1024 * 1024

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
          puts '  Exporting RISC-V CPU to FIRRTL...'
          require File.join(PROJECT_ROOT, 'examples/riscv/hdl/cpu')
          require 'rhdl/codegen'

          flat_ir = RHDL::Examples::RISCV::CPU.to_flat_ir(top_name: 'riscv_cpu')
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(flat_ir)
          File.write(FIRRTL_FILE, firrtl)
        end

        def compile_firrtl_to_mlir
          puts '  Compiling FIRRTL -> HW MLIR...'
          run_tool!('firtool', FIRRTL_FILE, '--parse-only', '-o', PARSED_MLIR_FILE)
          run_tool!('circt-opt', PARSED_MLIR_FILE, "--pass-pipeline=#{firrtl_pipeline_without_comb_check}", '-o',
                    LOWERED_MLIR_FILE)
          run_tool!('firtool', '--format=mlir', LOWERED_MLIR_FILE, '--ir-hw', '-o', MLIR_FILE)
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
          REQUIRED_SIGNALS.map do |name|
            "#define OFF_#{name.upcase} #{offsets.fetch(name)[:offset]}"
          end.join("\n")
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

            __attribute__((export_name("sim_create")))
            void *sim_create(uint32_t mem_size) {
                SimContext *ctx = (SimContext *)calloc(1, sizeof(SimContext));
                if (!ctx) return NULL;

                uint32_t actual_mem = mem_size;
                if (actual_mem == 0u || (actual_mem & (actual_mem - 1u)) != 0u) {
                    actual_mem = DEFAULT_MEM_SIZE;
                }

                mem_init(&ctx->mem, actual_mem);
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
