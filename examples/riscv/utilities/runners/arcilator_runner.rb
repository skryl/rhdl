# frozen_string_literal: true

# RV32I Arcilator Runner - Native RTL simulation via CIRCT arcilator
#
# Exports the single-cycle CPU to FIRRTL, compiles through firtool + arcilator
# to LLVM IR, then to a shared library. Driven via Fiddle FFI with batched C++
# cycle execution.

require 'rhdl/codegen'
require 'json'
require_relative 'hdl_runner_base'
require_relative '../../hdl/cpu'

module RHDL
  module Examples
    module RISCV
      class ArcilatorRunner < HdlRunnerBase
        BUILD_BASE = File.expand_path('../../.hdl_build', __dir__)

        def initialize(mem_size: Memory::DEFAULT_SIZE)
          super(backend_sym: :arcilator, simulator_type_sym: :hdl_arcilator, mem_size: mem_size)
        end

        private

        def check_tools_available!
          %w[firtool circt-opt arcilator llc].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, 'arcilator')
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          fir_file = File.join(build_dir, 'riscv_cpu.fir')
          mlir_file = File.join(build_dir, 'riscv_cpu_hw.mlir')
          ll_file = File.join(build_dir, 'riscv_cpu_arc.ll')
          state_file = File.join(build_dir, 'riscv_cpu_state.json')
          obj_file = File.join(build_dir, 'riscv_cpu_arc.o')
          wrapper_file = File.join(build_dir, 'arc_wrapper.cpp')
          lib_file = shared_lib_path

          cpu_source = File.expand_path('../../hdl/cpu.rb', __dir__)
          firrtl_gen = File.expand_path('../../../../lib/rhdl/codegen/circt/firrtl.rb', __dir__)
          export_deps = [__FILE__, cpu_source, firrtl_gen].select { |p| File.exist?(p) }

          needs_rebuild = !File.exist?(lib_file) ||
                          export_deps.any? { |p| File.mtime(p) > File.mtime(lib_file) }

          if needs_rebuild
            puts '  Exporting RISC-V CPU to FIRRTL...'
            export_firrtl(fir_file)

            puts '  Compiling with firtool + arcilator...'
            compile_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)

            puts '  Building shared library...'
            write_arcilator_wrapper(wrapper_file, state_file)
            link_arcilator(wrapper_file, obj_file, lib_file)
          end

          @lib_path = lib_file
        end

        def shared_lib_path
          File.join(build_dir, 'libriscv_arc_sim.so')
        end

        def export_firrtl(fir_file)
          flat_ir = CPU.to_flat_ir(top_name: 'riscv_cpu')
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(flat_ir)
          File.write(fir_file, firrtl)
        end

        def compile_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)
          parsed_mlir = File.join(build_dir, 'riscv_cpu_parsed.mlir')
          lowered_mlir = File.join(build_dir, 'riscv_cpu_lowered.mlir')
          log = File.join(build_dir, 'firtool.log')

          run_or_raise("firtool #{fir_file} --parse-only -o #{parsed_mlir} 2>#{log}",
                       'firtool parse', log)

          run_or_raise(
            "circt-opt #{parsed_mlir} --pass-pipeline='#{firrtl_pipeline_without_comb_check}' " \
            "-o #{lowered_mlir} 2>>#{log}",
            'circt-opt FIRRTL pipeline', log
          )

          run_or_raise("firtool --format=mlir #{lowered_mlir} --ir-hw -o #{mlir_file} 2>>#{log}",
                       'firtool HW lowering', log)

          run_or_raise("arcilator #{mlir_file} --observe-registers --state-file=#{state_file} -o #{ll_file} 2>>#{log}",
                       'arcilator', log)

          run_or_raise("llc -filetype=obj -O2 -relocation-model=pic #{ll_file} -o #{obj_file} 2>>#{log}",
                       'llc', log)
        end

        def run_or_raise(cmd, step_name, log_path)
          return if system(cmd)

          error_msg = File.exist?(log_path) ? File.read(log_path).lines.last(3).join.strip : 'unknown error'
          raise LoadError, "#{step_name} failed for RISC-V CPU: #{error_msg}"
        end

        # Replicate the standard firtool FIRRTL pass pipeline, omitting firrtl-check-comb-loops.
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

        def link_arcilator(wrapper_file, obj_file, lib_file)
          system("g++ -shared -fPIC -O2 -o #{lib_file} #{wrapper_file} #{obj_file}") or raise LoadError, 'g++ link failed'
        end

        def write_arcilator_wrapper(wrapper_path, state_file_path)
          state = JSON.parse(File.read(state_file_path))
          mod = state[0]

          offsets = {}
          mod['states'].each { |s| offsets[s['name']] = s['offset'] }

          signal_defines = []
          signal_defines << "#define STATE_SIZE #{mod['numStateBytes']}"
          offsets.each { |name, offset| signal_defines << "#define OFF_#{name.upcase} #{offset}" }

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>

            extern "C" void riscv_cpu_eval(void* state);

            #{signal_defines.join("\n")}

            #{riscv_sim_common_types}

            struct SimContext {
                uint8_t state[STATE_SIZE];
                MemState mem;
            };

            static inline void set_u8(uint8_t* s, int o, uint8_t v) { s[o] = v; }
            static inline uint8_t get_u8(uint8_t* s, int o) { return s[o]; }
            static inline void set_u32(uint8_t* s, int o, uint32_t v) { memcpy(&s[o], &v, 4); }
            static inline uint32_t get_u32(uint8_t* s, int o) { uint32_t v; memcpy(&v, &s[o], 4); return v; }
            static inline void set_bit(uint8_t* s, int o, uint8_t v) { s[o] = v & 1; }
            static inline uint8_t get_bit(uint8_t* s, int o) { return s[o] & 1; }
            static inline void set_u3(uint8_t* s, int o, uint8_t v) { s[o] = v & 0x7; }
            static inline uint8_t get_u3(uint8_t* s, int o) { return s[o] & 0x7; }
            static inline void set_u5(uint8_t* s, int o, uint8_t v) { s[o] = v & 0x1F; }
            static inline uint8_t get_u5(uint8_t* s, int o) { return s[o] & 0x1F; }

            // Arcilator DUT port access macros (lvalue-capable via state buffer casts)
            #define CTX(c)                    (static_cast<SimContext*>(c))
            #define DUT_CLK(c)                (CTX(c)->state[OFF_CLK])
            #define DUT_RST(c)                (CTX(c)->state[OFF_RST])
            #define DUT_IRQ_SOFTWARE(c)       (CTX(c)->state[OFF_IRQ_SOFTWARE])
            #define DUT_IRQ_TIMER(c)          (CTX(c)->state[OFF_IRQ_TIMER])
            #define DUT_IRQ_EXTERNAL(c)       (CTX(c)->state[OFF_IRQ_EXTERNAL])
            #define DUT_INST_DATA(c)          (*(uint32_t*)(&CTX(c)->state[OFF_INST_DATA]))
            #define DUT_DATA_RDATA(c)         (*(uint32_t*)(&CTX(c)->state[OFF_DATA_RDATA]))
            #define DUT_DEBUG_REG_ADDR(c)     (CTX(c)->state[OFF_DEBUG_REG_ADDR])
            #define DUT_INST_PTW_PTE0(c)      (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_PTE0]))
            #define DUT_INST_PTW_PTE1(c)      (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_PTE1]))
            #define DUT_DATA_PTW_PTE0(c)      (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_PTE0]))
            #define DUT_DATA_PTW_PTE1(c)      (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_PTE1]))
            #define DUT_INST_ADDR(c)          (*(uint32_t*)(&CTX(c)->state[OFF_INST_ADDR]))
            #define DUT_INST_PTW_ADDR0(c)     (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_ADDR0]))
            #define DUT_INST_PTW_ADDR1(c)     (*(uint32_t*)(&CTX(c)->state[OFF_INST_PTW_ADDR1]))
            #define DUT_DATA_ADDR(c)          (*(uint32_t*)(&CTX(c)->state[OFF_DATA_ADDR]))
            #define DUT_DATA_WDATA(c)         (*(uint32_t*)(&CTX(c)->state[OFF_DATA_WDATA]))
            #define DUT_DATA_WE(c)            (CTX(c)->state[OFF_DATA_WE])
            #define DUT_DATA_RE(c)            (CTX(c)->state[OFF_DATA_RE])
            #define DUT_DATA_FUNCT3(c)        (CTX(c)->state[OFF_DATA_FUNCT3])
            #define DUT_DATA_PTW_ADDR0(c)     (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_ADDR0]))
            #define DUT_DATA_PTW_ADDR1(c)     (*(uint32_t*)(&CTX(c)->state[OFF_DATA_PTW_ADDR1]))
            #define DUT_DEBUG_PC(c)           (*(uint32_t*)(&CTX(c)->state[OFF_DEBUG_PC]))
            #define DUT_EVAL(c)               riscv_cpu_eval(CTX(c)->state)

            #{riscv_sim_run_cycles_impl}

            extern "C" {

            void* sim_create(unsigned int mem_size) {
                SimContext* ctx = new SimContext();
                memset(ctx->state, 0, sizeof(ctx->state));
                mem_init(&ctx->mem, mem_size);
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

            void sim_destroy(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                mem_free(&ctx->mem);
                delete ctx;
            }

            void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                set_bit(ctx->state, OFF_RST, 1);
                set_bit(ctx->state, OFF_CLK, 0);
                riscv_cpu_eval(ctx->state);
                set_bit(ctx->state, OFF_CLK, 1);
                riscv_cpu_eval(ctx->state);
                set_bit(ctx->state, OFF_CLK, 0);
                set_bit(ctx->state, OFF_RST, 0);
                riscv_cpu_eval(ctx->state);
            }

            void sim_eval(void* sim) {
                riscv_cpu_eval(static_cast<SimContext*>(sim)->state);
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
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

            unsigned int sim_peek(void* sim, const char* name) {
                SimContext* ctx = static_cast<SimContext*>(sim);
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

            void sim_write_pc(void* sim, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                #ifdef OFF_PC_REG__PC
                set_u32(ctx->state, OFF_PC_REG__PC, value);
                #endif
                riscv_cpu_eval(ctx->state);
            }

            void sim_load_mem(void* sim, int mem_type, const unsigned char* data, unsigned int size, unsigned int base_addr) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                load_mem(&ctx->mem, mem_type, data, size, base_addr);
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                run_cycles_impl(ctx, &ctx->mem, n_cycles);
            }

            } // extern "C"
          CPP

          File.write(wrapper_path, wrapper)
        end
      end
    end
  end
end
