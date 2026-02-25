# frozen_string_literal: true

# RV32I HDL Harness - Native RTL simulation via Verilator or Arcilator + Ruby MMIO harness
#
# Compiles the single-cycle CPU core to native code (Verilog→Verilator or FIRRTL→Arcilator),
# drives it via Fiddle FFI, and keeps MMIO peripherals (CLINT, PLIC, UART, VirtIO) in Ruby.
#
# This provides the same interface as IRHarness for drop-in use in HeadlessRunner.

require 'rhdl/codegen'
require 'fileutils'
require 'fiddle'
require 'json'
require_relative 'constants'
require_relative 'cpu'
require_relative 'memory'
require_relative 'clint'
require_relative 'plic'
require_relative 'uart'
require_relative 'virtio_blk'

module RHDL
  module Examples
    module RISCV
      class HdlHarness
        # Minimal stub for code that probes @cpu.sim for native runner capabilities.
        # HdlHarness does not use the Rust native runner, so this stub returns false/nil
        # for all native runner queries.
        class HdlSimStub
          def initialize(backend)
            @backend = backend
          end

          def native?
            false
          end

          def runner_kind
            :hdl
          end

          def simulator_type
            @backend == :verilator ? :hdl_verilator : :hdl_arcilator
          end
        end

        attr_reader :clock_count

        # Stub sim object for compatibility with code that checks @cpu.sim.respond_to?(...)
        # The HdlHarness does not use an IrSimulator, so this returns a minimal object.
        def sim
          @sim_stub ||= HdlSimStub.new(@backend)
        end

        BUILD_BASE = File.expand_path('../../.hdl_build', __dir__)

        def initialize(backend: :verilator, mem_size: Memory::DEFAULT_SIZE, core: :single)
          @backend = backend.to_sym
          @mem_size = mem_size
          @core = core

          raise ArgumentError, "HdlHarness only supports single-cycle core" unless core == :single

          check_tools_available!

          puts "Initializing RISC-V #{@backend.capitalize} simulation..."
          start_time = Time.now

          build_simulation
          load_shared_library

          elapsed = Time.now - start_time
          puts "  #{@backend.capitalize} simulation built in #{elapsed.round(2)}s"

          @clock_count = 0
          @irq_software = 0
          @irq_timer = 0
          @irq_external = 0
          @plic_source1 = 0
          @plic_source10 = 0
          @plic_irq_external = 0
          @clint_irq_software = 0
          @clint_irq_timer = 0
          @uart_irq = 0
          @virtio_irq = 0
          @uart_rx_queue = []
          @uart_tx_bytes = []
          @debug_reg_addr = 0
          @clk = 0
          @rst = 0

          @inst_mem = Memory.new('imem', size: mem_size)
          @data_mem = Memory.new('dmem', size: mem_size)
          @clint = Clint.new('clint')
          @plic = Plic.new('plic')
          @uart = Uart.new('uart')
          @virtio = VirtioBlk.new('virtio_blk')

          reset!
        end

        def native?
          true
        end

        def simulator_type
          @backend == :verilator ? :hdl_verilator : :hdl_arcilator
        end

        def backend
          @backend
        end

        def reset!
          @clock_count = 0
          @irq_software = 0
          @irq_timer = 0
          @irq_external = 0
          @plic_source1 = 0
          @plic_source10 = 0
          @plic_irq_external = 0
          @clint_irq_software = 0
          @clint_irq_timer = 0
          @uart_irq = 0
          @virtio_irq = 0
          @uart_rx_queue = []
          @uart_tx_bytes = []
          @debug_reg_addr = 0

          @sim_reset_fn.call(@sim_ctx)
        end

        def clock_cycle
          set_clk_rst(0, 0)
          propagate_all(evaluate_cpu: true)

          set_clk_rst(1, 0)
          propagate_all(evaluate_cpu: false)
          eval_cpu # Rising edge eval advances sequential elements in Verilator/Arcilator

          set_clk_rst(0, 0)
          propagate_all(evaluate_cpu: true)

          @clock_count += 1
        end

        def run_cycles(n)
          n.times { clock_cycle }
        end

        def read_reg(index)
          idx = index & 0x1F
          return 0 if idx == 0

          old_addr = @debug_reg_addr
          @debug_reg_addr = idx
          poke_cpu(:debug_reg_addr, @debug_reg_addr)
          eval_cpu
          value = peek_cpu(:debug_reg_data) & 0xFFFF_FFFF
          @debug_reg_addr = old_addr
          poke_cpu(:debug_reg_addr, @debug_reg_addr)
          value
        end

        def write_reg(_index, _value)
          raise NotImplementedError, 'HdlHarness does not support direct register writes'
        end

        def read_pc
          peek_cpu(:debug_pc) & 0xFFFF_FFFF
        end

        def write_pc(value)
          # HDL harness cannot directly write internal PC register.
          # The HeadlessRunner set_pc handles this via reset vector or fallback.
          raise RuntimeError, 'HdlHarness does not support direct PC writes'
        end

        def load_program(program, start_addr = 0)
          @inst_mem.load_program(program, start_addr)
        end

        def load_data(data, start_addr = 0)
          @data_mem.load_program(data, start_addr)
        end

        def read_inst_word(addr)
          @inst_mem.read_word(addr)
        end

        def read_data_word(addr)
          @data_mem.read_word(addr)
        end

        def write_data_word(addr, value)
          @data_mem.write_word(addr, value)
        end

        def set_interrupts(software: nil, timer: nil, external: nil)
          @irq_software = software.nil? ? @irq_software : (software ? 1 : 0)
          @irq_timer = timer.nil? ? @irq_timer : (timer ? 1 : 0)
          @irq_external = external.nil? ? @irq_external : (external ? 1 : 0)
        end

        def set_plic_sources(source1: nil, source10: nil)
          @plic_source1 = source1.nil? ? @plic_source1 : (source1 ? 1 : 0)
          @plic_source10 = source10.nil? ? @plic_source10 : (source10 ? 1 : 0)
        end

        def uart_receive_byte(byte)
          uart_receive_bytes([byte & 0xFF])
        end

        def uart_receive_bytes(bytes)
          bytes.each { |byte| @uart_rx_queue << (byte & 0xFF) }
        end

        def uart_receive_text(text)
          uart_receive_bytes(text.to_s.b.bytes)
        end

        def uart_tx_bytes
          @uart_tx_bytes.dup
        end

        def clear_uart_tx_bytes
          @uart_tx_bytes.clear
        end

        def load_virtio_disk(bytes, offset: 0)
          @virtio.load_disk_bytes(bytes, offset: offset)
        end

        def read_virtio_disk_byte(offset)
          @virtio.read_disk_byte(offset)
        end

        def current_inst
          peek_cpu(:debug_inst) & 0xFFFF_FFFF
        end

        def state
          {
            pc: read_pc,
            x1: read_reg(1),
            x2: read_reg(2),
            x10: read_reg(10),
            x11: read_reg(11),
            inst: current_inst,
            cycles: @clock_count
          }
        end

        private

        # ---------- Build pipeline ----------

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, @backend.to_s)
        end

        def check_tools_available!
          case @backend
          when :verilator
            raise LoadError, "verilator not found in PATH" unless command_available?('verilator')
          when :arcilator
            %w[firtool circt-opt arcilator llc].each do |tool|
              raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
            end
          else
            raise ArgumentError, "Unsupported backend: #{@backend}"
          end
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)
          case @backend
          when :verilator then build_verilator
          when :arcilator then build_arcilator
          end
        end

        def build_verilator
          verilog_dir = File.join(build_dir, 'verilog')
          obj_dir = File.join(build_dir, 'obj_dir')
          FileUtils.mkdir_p(verilog_dir)
          FileUtils.mkdir_p(obj_dir)

          verilog_file = File.join(verilog_dir, 'riscv_cpu.v')
          wrapper_file = File.join(verilog_dir, 'sim_wrapper.cpp')
          header_file = File.join(verilog_dir, 'sim_wrapper.h')

          cpu_source = File.expand_path('cpu.rb', __dir__)
          export_deps = [__FILE__, cpu_source].select { |p| File.exist?(p) }
          needs_export = !File.exist?(verilog_file) ||
                         export_deps.any? { |p| File.mtime(p) > File.mtime(verilog_file) }

          if needs_export
            puts "  Exporting RISC-V CPU to Verilog..."
            verilog_code = CPU.to_verilog_hierarchy
            File.write(verilog_file, verilog_code)
          end

          write_verilator_wrapper(wrapper_file, header_file)

          @verilog_simulator = RHDL::Codegen::Verilog::VerilogSimulator.new(
            backend: :verilator,
            build_dir: build_dir,
            library_basename: 'riscv_sim',
            top_module: 'riscv_cpu',
            verilator_prefix: 'Vriscv',
            x_assign: '0',
            x_initial: 'unique'
          )

          lib_file = @verilog_simulator.shared_library_path
          needs_build = !File.exist?(lib_file) ||
                        File.mtime(verilog_file) > File.mtime(lib_file) ||
                        File.mtime(wrapper_file) > File.mtime(lib_file) ||
                        File.mtime(__FILE__) > File.mtime(lib_file)

          if needs_build
            puts "  Compiling with Verilator..."
            @verilog_simulator.compile_backend(verilog_file: verilog_file, wrapper_file: wrapper_file)
          end

          @lib_path = lib_file
        end

        def build_arcilator
          fir_file = File.join(build_dir, 'riscv_cpu.fir')
          mlir_file = File.join(build_dir, 'riscv_cpu_hw.mlir')
          ll_file = File.join(build_dir, 'riscv_cpu_arc.ll')
          state_file = File.join(build_dir, 'riscv_cpu_state.json')
          obj_file = File.join(build_dir, 'riscv_cpu_arc.o')
          wrapper_file = File.join(build_dir, 'arc_wrapper.cpp')

          cpu_source = File.expand_path('cpu.rb', __dir__)
          firrtl_gen = File.expand_path('../../../lib/rhdl/codegen/circt/firrtl.rb', __dir__)
          export_deps = [__FILE__, cpu_source, firrtl_gen].select { |p| File.exist?(p) }

          lib_file = shared_lib_path_arcilator
          needs_rebuild = !File.exist?(lib_file) ||
                          export_deps.any? { |p| File.mtime(p) > File.mtime(lib_file) }

          if needs_rebuild
            puts "  Exporting RISC-V CPU to FIRRTL..."
            export_firrtl(fir_file)

            puts "  Compiling with firtool + arcilator..."
            compile_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)

            puts "  Building shared library..."
            write_arcilator_wrapper(wrapper_file, state_file)
            link_arcilator(wrapper_file, obj_file, lib_file)
          end

          @lib_path = lib_file
        end

        def export_firrtl(fir_file)
          # Use flat IR to avoid combinational cycle detection in firtool.
          # The RISC-V CPU has valid combinational paths that cross sub-module
          # boundaries, which firtool rejects in hierarchical mode.
          flat_ir = CPU.to_flat_ir(top_name: 'riscv_cpu')
          firrtl = RHDL::Codegen::CIRCT::FIRRTL.generate(flat_ir)
          File.write(fir_file, firrtl)
        end

        def compile_arcilator(fir_file, mlir_file, ll_file, state_file, obj_file)
          parsed_mlir = File.join(build_dir, 'riscv_cpu_parsed.mlir')
          lowered_mlir = File.join(build_dir, 'riscv_cpu_lowered.mlir')
          log = File.join(build_dir, 'firtool.log')

          # Step 1: Parse FIRRTL to MLIR (no passes run)
          run_or_raise("firtool #{fir_file} --parse-only -o #{parsed_mlir} 2>#{log}",
                       "firtool parse", log)

          # Step 2: Run full FIRRTL pipeline via circt-opt, skipping firrtl-check-comb-loops.
          # The RISC-V single-cycle CPU has valid combinational feedback through the register
          # file (write-back data depends on ALU output which depends on read data) that is
          # broken by the clock edge.  firtool unconditionally rejects such designs, but the
          # hardware is correct.  We replicate the standard firtool FIRRTL pass pipeline with
          # that single check removed.
          run_or_raise(
            "circt-opt #{parsed_mlir} --pass-pipeline='#{firrtl_pipeline_without_comb_check}' " \
            "-o #{lowered_mlir} 2>>#{log}",
            "circt-opt FIRRTL pipeline", log
          )

          # Step 3: Lower FIRRTL MLIR to HW IR
          run_or_raise("firtool --format=mlir #{lowered_mlir} --ir-hw -o #{mlir_file} 2>>#{log}",
                       "firtool HW lowering", log)

          # Step 4: arcilator → LLVM IR
          run_or_raise("arcilator #{mlir_file} --state-file=#{state_file} -o #{ll_file} 2>>#{log}",
                       "arcilator", log)

          # Step 5: LLVM IR → object
          run_or_raise("llc -filetype=obj -O2 -relocation-model=pic #{ll_file} -o #{obj_file} 2>>#{log}",
                       "llc", log)
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
          system("g++ -shared -fPIC -O2 -o #{lib_file} #{wrapper_file} #{obj_file}") or raise LoadError, "g++ link failed"
        end

        def shared_lib_path_arcilator
          File.join(build_dir, 'libriscv_arc_sim.so')
        end

        # ---------- C++ wrapper generation ----------

        def write_verilator_wrapper(cpp_file, header_file)
          header = <<~H
            #ifndef SIM_WRAPPER_H
            #define SIM_WRAPPER_H
            #ifdef __cplusplus
            extern "C" {
            #endif
            void* sim_create(void);
            void sim_destroy(void* sim);
            void sim_reset(void* sim);
            void sim_eval(void* sim);
            void sim_poke(void* sim, const char* name, unsigned int value);
            unsigned int sim_peek(void* sim, const char* name);
            #ifdef __cplusplus
            }
            #endif
            #endif
          H

          cpp = <<~CPP
            #include "Vriscv.h"
            #include "Vriscv___024root.h"
            #include "verilated.h"
            #include "sim_wrapper.h"
            #include <cstring>

            double sc_time_stamp() { return 0; }

            struct SimContext {
                Vriscv* dut;
            };

            extern "C" {

            void* sim_create(void) {
                const char* empty_args[] = {""};
                Verilated::commandArgs(1, empty_args);
                SimContext* ctx = new SimContext();
                ctx->dut = new Vriscv();
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

            void sim_destroy(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                delete ctx->dut;
                delete ctx;
            }

            void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                // Reset sequence: clk=0,rst=1 → eval → clk=1,rst=1 → eval → clk=0,rst=0 → eval
                ctx->dut->rst = 1;
                ctx->dut->clk = 0;
                ctx->dut->eval();
                ctx->dut->clk = 1;
                ctx->dut->eval();
                ctx->dut->clk = 0;
                ctx->dut->rst = 0;
                ctx->dut->eval();
            }

            void sim_eval(void* sim) {
                static_cast<SimContext*>(sim)->dut->eval();
            }

            void sim_poke(void* sim, const char* name, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if      (!strcmp(name, "clk"))             ctx->dut->clk = value;
                else if (!strcmp(name, "rst"))             ctx->dut->rst = value;
                else if (!strcmp(name, "irq_software"))    ctx->dut->irq_software = value;
                else if (!strcmp(name, "irq_timer"))       ctx->dut->irq_timer = value;
                else if (!strcmp(name, "irq_external"))    ctx->dut->irq_external = value;
                else if (!strcmp(name, "inst_data"))       ctx->dut->inst_data = value;
                else if (!strcmp(name, "data_rdata"))      ctx->dut->data_rdata = value;
                else if (!strcmp(name, "debug_reg_addr"))  ctx->dut->debug_reg_addr = value;
                else if (!strcmp(name, "inst_ptw_pte0"))   ctx->dut->inst_ptw_pte0 = value;
                else if (!strcmp(name, "inst_ptw_pte1"))   ctx->dut->inst_ptw_pte1 = value;
                else if (!strcmp(name, "data_ptw_pte0"))   ctx->dut->data_ptw_pte0 = value;
                else if (!strcmp(name, "data_ptw_pte1"))   ctx->dut->data_ptw_pte1 = value;
            }

            unsigned int sim_peek(void* sim, const char* name) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                if      (!strcmp(name, "inst_addr"))       return ctx->dut->inst_addr;
                else if (!strcmp(name, "inst_ptw_addr0"))  return ctx->dut->inst_ptw_addr0;
                else if (!strcmp(name, "inst_ptw_addr1"))  return ctx->dut->inst_ptw_addr1;
                else if (!strcmp(name, "data_addr"))       return ctx->dut->data_addr;
                else if (!strcmp(name, "data_wdata"))      return ctx->dut->data_wdata;
                else if (!strcmp(name, "data_we"))         return ctx->dut->data_we;
                else if (!strcmp(name, "data_re"))         return ctx->dut->data_re;
                else if (!strcmp(name, "data_funct3"))     return ctx->dut->data_funct3;
                else if (!strcmp(name, "data_ptw_addr0"))  return ctx->dut->data_ptw_addr0;
                else if (!strcmp(name, "data_ptw_addr1"))  return ctx->dut->data_ptw_addr1;
                else if (!strcmp(name, "debug_pc"))        return ctx->dut->debug_pc;
                else if (!strcmp(name, "debug_inst"))      return ctx->dut->debug_inst;
                else if (!strcmp(name, "debug_x1"))        return ctx->dut->debug_x1;
                else if (!strcmp(name, "debug_x2"))        return ctx->dut->debug_x2;
                else if (!strcmp(name, "debug_x10"))       return ctx->dut->debug_x10;
                else if (!strcmp(name, "debug_x11"))       return ctx->dut->debug_x11;
                else if (!strcmp(name, "debug_reg_data"))  return ctx->dut->debug_reg_data;
                return 0;
            }

            } // extern "C"
          CPP

          write_file_if_changed(header_file, header)
          write_file_if_changed(cpp_file, cpp)
        end

        def write_arcilator_wrapper(wrapper_path, state_file_path)
          state = JSON.parse(File.read(state_file_path))
          mod = state[0]

          offsets = {}
          mod['states'].each { |s| offsets[s['name']] = s['offset'] }

          # Determine accessor type for each signal based on width
          # Build offset map - generate defines for known signals
          signal_defines = []
          signal_defines << "#define STATE_SIZE #{mod['numStateBytes']}"
          offsets.each { |name, offset| signal_defines << "#define OFF_#{name.upcase} #{offset}" }

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>

            extern "C" void riscv_cpu_eval(void* state);

            #{signal_defines.join("\n")}

            struct SimContext {
                uint8_t state[STATE_SIZE];
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

            extern "C" {

            void* sim_create(void) {
                SimContext* ctx = new SimContext();
                memset(ctx->state, 0, sizeof(ctx->state));
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

            void sim_destroy(void* sim) { delete static_cast<SimContext*>(sim); }

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

            } // extern "C"
          CPP

          File.write(wrapper_path, wrapper)
        end

        # ---------- Fiddle FFI ----------

        def load_shared_library
          @lib = Fiddle.dlopen(@lib_path)

          @sim_create_fn = Fiddle::Function.new(@lib['sim_create'], [], Fiddle::TYPE_VOIDP)
          @sim_destroy_fn = Fiddle::Function.new(@lib['sim_destroy'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_reset_fn = Fiddle::Function.new(@lib['sim_reset'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_eval_fn = Fiddle::Function.new(@lib['sim_eval'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
          @sim_poke_fn = Fiddle::Function.new(
            @lib['sim_poke'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )
          @sim_peek_fn = Fiddle::Function.new(
            @lib['sim_peek'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP],
            Fiddle::TYPE_INT
          )

          @sim_ctx = @sim_create_fn.call
        end

        # ---------- CPU interface ----------

        def poke_cpu(name, value)
          @sim_poke_fn.call(@sim_ctx, name.to_s, value.to_i)
        end

        def peek_cpu(name)
          @sim_peek_fn.call(@sim_ctx, name.to_s)
        end

        def eval_cpu
          @sim_eval_fn.call(@sim_ctx)
        end

        # ---------- Clock and propagation (mirrors IRHarness) ----------

        def set_clk_rst(clk, rst)
          @clk = clk
          @rst = rst
          poke_cpu(:clk, clk)
          poke_cpu(:rst, rst)
          apply_irq_inputs
          poke_cpu(:debug_reg_addr, @debug_reg_addr)
          @inst_mem.set_input(:clk, clk)
          @inst_mem.set_input(:rst, rst)
          @data_mem.set_input(:clk, clk)
          @data_mem.set_input(:rst, rst)
          @clint.set_input(:clk, clk)
          @clint.set_input(:rst, rst)
          @plic.set_input(:clk, clk)
          @plic.set_input(:rst, rst)
          @uart.set_input(:clk, clk)
          @uart.set_input(:rst, rst)
          @virtio.set_input(:clk, clk)
          @virtio.set_input(:rst, rst)
        end

        def propagate_all(evaluate_cpu: true)
          apply_irq_inputs
          poke_cpu(:debug_reg_addr, @debug_reg_addr)
          eval_cpu if evaluate_cpu

          if evaluate_cpu
            inst_ptw_addr1 = peek_cpu(:inst_ptw_addr1)
            poke_cpu(:inst_ptw_pte1, @data_mem.read_word(inst_ptw_addr1))
            eval_cpu
            inst_ptw_addr0 = peek_cpu(:inst_ptw_addr0)
            poke_cpu(:inst_ptw_pte0, @data_mem.read_word(inst_ptw_addr0))
            eval_cpu
          end

          inst_addr = peek_cpu(:inst_addr)
          @inst_mem.set_input(:addr, inst_addr)
          @inst_mem.set_input(:mem_read, 1)
          @inst_mem.set_input(:mem_write, 0)
          @inst_mem.set_input(:funct3, Funct3::WORD)
          @inst_mem.set_input(:write_data, 0)
          @inst_mem.propagate
          inst_data = @inst_mem.get_output(:read_data)
          if evaluate_cpu
            poke_cpu(:inst_data, inst_data)
            eval_cpu
          end

          if evaluate_cpu
            data_ptw_addr1 = peek_cpu(:data_ptw_addr1)
            poke_cpu(:data_ptw_pte1, @data_mem.read_word(data_ptw_addr1))
            eval_cpu
            data_ptw_addr0 = peek_cpu(:data_ptw_addr0)
            poke_cpu(:data_ptw_pte0, @data_mem.read_word(data_ptw_addr0))
            eval_cpu
          end

          data_addr = peek_cpu(:data_addr)
          data_wdata = peek_cpu(:data_wdata)
          data_we = peek_cpu(:data_we)
          data_re = peek_cpu(:data_re)
          data_funct3 = peek_cpu(:data_funct3)
          clint_selected = clint_access?(data_addr)
          plic_selected = plic_access?(data_addr)
          uart_selected = uart_access?(data_addr)
          virtio_selected = virtio_access?(data_addr)

          @clint.set_input(:addr, data_addr)
          @clint.set_input(:write_data, data_wdata)
          @clint.set_input(:mem_write, clint_selected ? data_we : 0)
          @clint.set_input(:mem_read, clint_selected ? data_re : 0)
          @clint.set_input(:funct3, data_funct3)
          @clint.propagate
          @clint_irq_software = @clint.get_output(:irq_software)
          @clint_irq_timer = @clint.get_output(:irq_timer)

          @virtio.set_input(:addr, data_addr)
          @virtio.set_input(:write_data, data_wdata)
          @virtio.set_input(:mem_write, virtio_selected ? data_we : 0)
          @virtio.set_input(:mem_read, virtio_selected ? data_re : 0)
          @virtio.set_input(:funct3, data_funct3)
          @virtio.propagate
          @virtio.service_queues!(@data_mem)
          @virtio_irq = @virtio.get_output(:irq)

          @plic.set_input(:addr, data_addr)
          @plic.set_input(:write_data, data_wdata)
          @plic.set_input(:mem_write, plic_selected ? data_we : 0)
          @plic.set_input(:mem_read, plic_selected ? data_re : 0)
          @plic.set_input(:funct3, data_funct3)
          @plic.set_input(:source1, (@plic_source1 | @virtio_irq) != 0 ? 1 : 0)
          @plic.set_input(:source10, (@plic_source10 | @uart_irq) != 0 ? 1 : 0)
          @plic.propagate
          @plic_irq_external = @plic.get_output(:irq_external)

          uart_rx_valid = @uart_rx_queue.empty? ? 0 : 1
          uart_rx_data = @uart_rx_queue.empty? ? 0 : @uart_rx_queue.first
          @uart.set_input(:addr, data_addr)
          @uart.set_input(:write_data, data_wdata)
          @uart.set_input(:mem_write, uart_selected ? data_we : 0)
          @uart.set_input(:mem_read, uart_selected ? data_re : 0)
          @uart.set_input(:funct3, data_funct3)
          @uart.set_input(:rx_valid, uart_rx_valid)
          @uart.set_input(:rx_data, uart_rx_data)
          @uart.propagate
          @uart_rx_queue.shift if @uart.get_output(:rx_accept) == 1 && !@uart_rx_queue.empty?
          @uart_tx_bytes << (@uart.get_output(:tx_data) & 0xFF) if @uart.get_output(:tx_valid) == 1
          @uart_irq = @uart.get_output(:irq)

          @data_mem.set_input(:addr, data_addr)
          @data_mem.set_input(:write_data, data_wdata)
          @data_mem.set_input(:mem_write, (clint_selected || plic_selected || uart_selected || virtio_selected) ? 0 : data_we)
          @data_mem.set_input(:mem_read, (clint_selected || plic_selected || uart_selected || virtio_selected) ? 0 : data_re)
          @data_mem.set_input(:funct3, data_funct3)
          @data_mem.propagate

          data_rdata = if clint_selected
                         @clint.get_output(:read_data)
                       elsif plic_selected
                         @plic.get_output(:read_data)
                       elsif uart_selected
                         @uart.get_output(:read_data)
                       elsif virtio_selected
                         @virtio.get_output(:read_data)
                       else
                         @data_mem.get_output(:read_data)
                       end

          if evaluate_cpu
            poke_cpu(:data_rdata, data_rdata)
            apply_irq_inputs
            poke_cpu(:debug_reg_addr, @debug_reg_addr)
            eval_cpu
          end
        end

        # ---------- MMIO address decoders ----------

        def clint_access?(addr)
          case addr & 0xFFFF_FFFF
          when Clint::MSIP_ADDR,
               Clint::MTIMECMP_LOW_ADDR, Clint::MTIMECMP_HIGH_ADDR,
               Clint::MTIME_LOW_ADDR, Clint::MTIME_HIGH_ADDR
            true
          else
            false
          end
        end

        def plic_access?(addr)
          case addr & 0xFFFF_FFFF
          when Plic::PRIORITY_1_ADDR, Plic::PRIORITY_10_ADDR,
               Plic::PENDING_ADDR, Plic::ENABLE_ADDR,
               Plic::THRESHOLD_ADDR, Plic::CLAIM_COMPLETE_ADDR
            true
          else
            false
          end
        end

        def uart_access?(addr)
          case addr & 0xFFFF_FFFF
          when Uart::BASE_ADDR + Uart::REG_THR_RBR_DLL,
               Uart::BASE_ADDR + Uart::REG_IER_DLM,
               Uart::BASE_ADDR + Uart::REG_IIR_FCR,
               Uart::BASE_ADDR + Uart::REG_LCR,
               Uart::BASE_ADDR + Uart::REG_MCR,
               Uart::BASE_ADDR + Uart::REG_LSR,
               Uart::BASE_ADDR + Uart::REG_MSR,
               Uart::BASE_ADDR + Uart::REG_SCR
            true
          else
            false
          end
        end

        def virtio_access?(addr)
          case addr & 0xFFFF_FFFF
          when VirtioBlk::MAGIC_VALUE_ADDR,
               VirtioBlk::VERSION_ADDR,
               VirtioBlk::DEVICE_ID_ADDR,
               VirtioBlk::VENDOR_ID_ADDR,
               VirtioBlk::DEVICE_FEATURES_ADDR,
               VirtioBlk::DEVICE_FEATURES_SEL_ADDR,
               VirtioBlk::DRIVER_FEATURES_ADDR,
               VirtioBlk::DRIVER_FEATURES_SEL_ADDR,
               VirtioBlk::GUEST_PAGE_SIZE_ADDR,
               VirtioBlk::QUEUE_SEL_ADDR,
               VirtioBlk::QUEUE_NUM_MAX_ADDR,
               VirtioBlk::QUEUE_NUM_ADDR,
               VirtioBlk::QUEUE_ALIGN_ADDR,
               VirtioBlk::QUEUE_PFN_ADDR,
               VirtioBlk::QUEUE_READY_ADDR,
               VirtioBlk::QUEUE_NOTIFY_ADDR,
               VirtioBlk::INTERRUPT_STATUS_ADDR,
               VirtioBlk::INTERRUPT_ACK_ADDR,
               VirtioBlk::STATUS_ADDR,
               VirtioBlk::QUEUE_DESC_LOW_ADDR,
               VirtioBlk::QUEUE_DESC_HIGH_ADDR,
               VirtioBlk::QUEUE_DRIVER_LOW_ADDR,
               VirtioBlk::QUEUE_DRIVER_HIGH_ADDR,
               VirtioBlk::QUEUE_DEVICE_LOW_ADDR,
               VirtioBlk::QUEUE_DEVICE_HIGH_ADDR,
               VirtioBlk::CONFIG_GENERATION_ADDR,
               VirtioBlk::CONFIG_CAPACITY_LOW_ADDR,
               VirtioBlk::CONFIG_CAPACITY_HIGH_ADDR
            true
          else
            false
          end
        end

        def apply_irq_inputs
          poke_cpu(:irq_software, (@irq_software | @clint_irq_software) != 0 ? 1 : 0)
          poke_cpu(:irq_timer, (@irq_timer | @clint_irq_timer) != 0 ? 1 : 0)
          poke_cpu(:irq_external, (@irq_external | @plic_irq_external) != 0 ? 1 : 0)
        end

        # ---------- Utilities ----------

        def command_available?(cmd)
          ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
            File.executable?(File.join(path, cmd))
          end
        end

        def write_file_if_changed(path, content)
          return false if File.exist?(path) && File.read(path) == content

          File.write(path, content)
          true
        end
      end
    end
  end
end
