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
          if @batched_mode
            @sim_run_cycles_fn.call(@sim_ctx, n)
            @clock_count += n
          else
            n.times { clock_cycle }
          end
        end

        # Copy Ruby-side memory to C++ and enable batched cycle execution.
        # After this call, run_cycles uses the C++ loop with embedded MMIO.
        def enable_batched_mode!
          sync_mem_to_native(@inst_mem, 0) # MEM_TYPE_INST
          sync_mem_to_native(@data_mem, 1) # MEM_TYPE_DATA
          @batched_mode = true
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
          v = value.to_i & 0xFFFF_FFFF
          # Convert to signed 32-bit for Fiddle TYPE_INT compatibility
          v -= 0x1_0000_0000 if v > 0x7FFF_FFFF
          @sim_write_pc_fn.call(@sim_ctx, v)
          eval_cpu
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

          # Step 4: arcilator → LLVM IR (observe registers so internal PC is accessible)
          run_or_raise("arcilator #{mlir_file} --observe-registers --state-file=#{state_file} -o #{ll_file} 2>>#{log}",
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

        # Common C types and helpers used by both Verilator and Arcilator wrappers.
        # This must appear BEFORE the DUT_* macros and run_cycles_impl.
        def riscv_sim_common_types
          <<~'CODE'
            // ---- Memory & MMIO state ----
            #define MEM_TYPE_INST 0
            #define MEM_TYPE_DATA 1

            // CLINT addresses
            #define CLINT_BASE        0x02000000u
            #define CLINT_MSIP        (CLINT_BASE + 0x0000u)
            #define CLINT_MTIMECMP_LO (CLINT_BASE + 0x4000u)
            #define CLINT_MTIMECMP_HI (CLINT_BASE + 0x4004u)
            #define CLINT_MTIME_LO    (CLINT_BASE + 0xBFF8u)
            #define CLINT_MTIME_HI    (CLINT_BASE + 0xBFFCu)

            // UART 16550 addresses
            #define UART_BASE         0x10000000u
            #define UART_THR          (UART_BASE + 0)
            #define UART_IER          (UART_BASE + 1)
            #define UART_IIR          (UART_BASE + 2)
            #define UART_LCR          (UART_BASE + 3)
            #define UART_MCR          (UART_BASE + 4)
            #define UART_LSR          (UART_BASE + 5)
            #define UART_MSR          (UART_BASE + 6)
            #define UART_SCR          (UART_BASE + 7)

            // PLIC addresses (simplified)
            #define PLIC_BASE         0x0C000000u

            // VirtIO address range (read-only stubs for benchmark)
            #define VIRTIO_BASE       0x10001000u
            #define VIRTIO_END        0x10002000u

            struct MemState {
                uint8_t* inst_mem;
                uint8_t* data_mem;
                uint32_t mem_size;
                uint32_t mem_mask;
                // CLINT
                uint64_t mtime;
                uint64_t mtimecmp;
                uint32_t msip;
                // IRQ outputs
                uint8_t irq_timer;
                uint8_t irq_software;
                uint8_t irq_external;
                // UART (simple model for benchmark)
                uint8_t uart_lsr;  // Line Status: always TX empty + data ready when RX available
            };

            static void mem_init(MemState* m, uint32_t size) {
                m->inst_mem = (uint8_t*)calloc(size, 1);
                m->data_mem = (uint8_t*)calloc(size, 1);
                m->mem_size = size;
                m->mem_mask = size - 1;
                m->mtime = 0;
                m->mtimecmp = 0xFFFFFFFFFFFFFFFFull;
                m->msip = 0;
                m->irq_timer = 0;
                m->irq_software = 0;
                m->irq_external = 0;
                m->uart_lsr = 0x60; // THR empty + THRE
            }

            static void mem_free(MemState* m) {
                free(m->inst_mem);
                free(m->data_mem);
            }

            static void load_mem(MemState* m, int mem_type, const uint8_t* data, uint32_t size, uint32_t base) {
                uint8_t* target = (mem_type == MEM_TYPE_INST) ? m->inst_mem : m->data_mem;
                for (uint32_t i = 0; i < size; i++) {
                    target[(base + i) & m->mem_mask] = data[i];
                }
            }

            static inline uint32_t read_word_le(const uint8_t* mem, uint32_t mask, uint32_t addr) {
                uint32_t a = addr & mask;
                return (uint32_t)mem[a] | ((uint32_t)mem[(a+1)&mask] << 8) |
                       ((uint32_t)mem[(a+2)&mask] << 16) | ((uint32_t)mem[(a+3)&mask] << 24);
            }

            static inline uint32_t read_mem_funct3(const uint8_t* mem, uint32_t mask, uint32_t addr, uint32_t funct3) {
                uint32_t a = addr & mask;
                switch (funct3) {
                case 0: { uint8_t v = mem[a]; return (v & 0x80) ? (v | 0xFFFFFF00u) : v; }
                case 1: { uint16_t v = (uint16_t)mem[a] | ((uint16_t)mem[(a+1)&mask] << 8);
                          return (v & 0x8000) ? (v | 0xFFFF0000u) : v; }
                case 2: return read_word_le(mem, mask, addr);
                case 4: return mem[a];
                case 5: return (uint32_t)mem[a] | ((uint32_t)mem[(a+1)&mask] << 8);
                default: return 0;
                }
            }

            static inline void write_mem_funct3(uint8_t* mem, uint32_t mask, uint32_t addr, uint32_t val, uint32_t funct3) {
                uint32_t a = addr & mask;
                switch (funct3) {
                case 0: case 4: mem[a] = (uint8_t)val; break;
                case 1: case 5: mem[a] = (uint8_t)val; mem[(a+1)&mask] = (uint8_t)(val >> 8); break;
                case 2: mem[a]=(uint8_t)val; mem[(a+1)&mask]=(uint8_t)(val>>8);
                        mem[(a+2)&mask]=(uint8_t)(val>>16); mem[(a+3)&mask]=(uint8_t)(val>>24); break;
                }
            }

            static inline int is_clint(uint32_t a) {
                return a == CLINT_MSIP || a == CLINT_MTIMECMP_LO || a == CLINT_MTIMECMP_HI ||
                       a == CLINT_MTIME_LO || a == CLINT_MTIME_HI;
            }

            static inline int is_uart(uint32_t a) {
                return a >= UART_BASE && a <= UART_SCR;
            }

            static inline int is_plic(uint32_t a) {
                return (a >= PLIC_BASE && a < PLIC_BASE + 0x400000u);
            }

            static inline int is_virtio(uint32_t a) {
                return (a >= VIRTIO_BASE && a < VIRTIO_END);
            }

            static inline int is_mmio(uint32_t a) {
                return is_clint(a) || is_uart(a) || is_plic(a) || is_virtio(a);
            }

            static uint32_t handle_clint_read(MemState* m, uint32_t addr) {
                switch (addr) {
                case CLINT_MSIP:        return m->msip;
                case CLINT_MTIMECMP_LO: return (uint32_t)(m->mtimecmp);
                case CLINT_MTIMECMP_HI: return (uint32_t)(m->mtimecmp >> 32);
                case CLINT_MTIME_LO:    return (uint32_t)(m->mtime);
                case CLINT_MTIME_HI:    return (uint32_t)(m->mtime >> 32);
                default: return 0;
                }
            }

            static void handle_clint_write(MemState* m, uint32_t addr, uint32_t val) {
                switch (addr) {
                case CLINT_MSIP:        m->msip = val & 1; break;
                case CLINT_MTIMECMP_LO: m->mtimecmp = (m->mtimecmp & 0xFFFFFFFF00000000ull) | val; break;
                case CLINT_MTIMECMP_HI: m->mtimecmp = (m->mtimecmp & 0x00000000FFFFFFFFull) | ((uint64_t)val << 32); break;
                case CLINT_MTIME_LO:    m->mtime = (m->mtime & 0xFFFFFFFF00000000ull) | val; break;
                case CLINT_MTIME_HI:    m->mtime = (m->mtime & 0x00000000FFFFFFFFull) | ((uint64_t)val << 32); break;
                }
            }

            static uint32_t handle_uart_read(MemState* m, uint32_t addr) {
                switch (addr) {
                case UART_LSR: return m->uart_lsr;
                default: return 0;
                }
            }

            static uint32_t handle_mmio_read(MemState* m, uint32_t addr) {
                if (is_clint(addr)) return handle_clint_read(m, addr);
                if (is_uart(addr))  return handle_uart_read(m, addr);
                return 0;  // PLIC/VirtIO return 0 for benchmark
            }

            static void handle_mmio_write(MemState* m, uint32_t addr, uint32_t val) {
                if (is_clint(addr)) handle_clint_write(m, addr, val);
                // UART/PLIC/VirtIO writes are no-ops for benchmark
            }
          CODE
        end

        # Batched cycle execution loop. Must appear AFTER DUT_* macros are defined.
        def riscv_sim_run_cycles_impl
          <<~'CODE'
            static void run_cycles_impl(void* raw_ctx, MemState* m, uint32_t n_cycles) {
                for (uint32_t i = 0; i < n_cycles; i++) {
                    // --- Phase 1: CLK low, evaluate combinational ---
                    DUT_CLK(raw_ctx) = 0;
                    DUT_RST(raw_ctx) = 0;
                    DUT_IRQ_SOFTWARE(raw_ctx) = m->irq_software;
                    DUT_IRQ_TIMER(raw_ctx) = m->irq_timer;
                    DUT_IRQ_EXTERNAL(raw_ctx) = m->irq_external;
                    DUT_EVAL(raw_ctx);

                    // Instruction page table walk
                    DUT_INST_PTW_PTE1(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_INST_PTW_ADDR1(raw_ctx));
                    DUT_EVAL(raw_ctx);
                    DUT_INST_PTW_PTE0(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_INST_PTW_ADDR0(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Instruction fetch
                    DUT_INST_DATA(raw_ctx) = read_word_le(m->inst_mem, m->mem_mask, DUT_INST_ADDR(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Data page table walk
                    DUT_DATA_PTW_PTE1(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_DATA_PTW_ADDR1(raw_ctx));
                    DUT_EVAL(raw_ctx);
                    DUT_DATA_PTW_PTE0(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_DATA_PTW_ADDR0(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Data memory / MMIO access
                    uint32_t data_addr = DUT_DATA_ADDR(raw_ctx);
                    uint32_t data_wdata = DUT_DATA_WDATA(raw_ctx);
                    uint32_t data_we = DUT_DATA_WE(raw_ctx);
                    uint32_t data_re = DUT_DATA_RE(raw_ctx);
                    uint32_t data_funct3 = DUT_DATA_FUNCT3(raw_ctx);

                    uint32_t rdata = 0;
                    if (is_mmio(data_addr)) {
                        if (data_re) rdata = handle_mmio_read(m, data_addr);
                        if (data_we) handle_mmio_write(m, data_addr, data_wdata);
                    } else {
                        if (data_re) rdata = read_mem_funct3(m->data_mem, m->mem_mask, data_addr, data_funct3);
                        if (data_we) write_mem_funct3(m->data_mem, m->mem_mask, data_addr, data_wdata, data_funct3);
                    }

                    DUT_DATA_RDATA(raw_ctx) = rdata;
                    DUT_IRQ_SOFTWARE(raw_ctx) = m->irq_software;
                    DUT_IRQ_TIMER(raw_ctx) = m->irq_timer;
                    DUT_IRQ_EXTERNAL(raw_ctx) = m->irq_external;
                    DUT_EVAL(raw_ctx);

                    // --- Phase 2: CLK high (rising edge) ---
                    DUT_CLK(raw_ctx) = 1;
                    DUT_EVAL(raw_ctx);

                    // --- Phase 3: CLK low, post-edge settle ---
                    DUT_CLK(raw_ctx) = 0;
                    DUT_IRQ_SOFTWARE(raw_ctx) = m->irq_software;
                    DUT_IRQ_TIMER(raw_ctx) = m->irq_timer;
                    DUT_IRQ_EXTERNAL(raw_ctx) = m->irq_external;
                    DUT_EVAL(raw_ctx);

                    // Post-edge instruction page table walk
                    DUT_INST_PTW_PTE1(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_INST_PTW_ADDR1(raw_ctx));
                    DUT_EVAL(raw_ctx);
                    DUT_INST_PTW_PTE0(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_INST_PTW_ADDR0(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Post-edge instruction fetch
                    DUT_INST_DATA(raw_ctx) = read_word_le(m->inst_mem, m->mem_mask, DUT_INST_ADDR(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Post-edge data page table walk
                    DUT_DATA_PTW_PTE1(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_DATA_PTW_ADDR1(raw_ctx));
                    DUT_EVAL(raw_ctx);
                    DUT_DATA_PTW_PTE0(raw_ctx) = read_word_le(m->data_mem, m->mem_mask, DUT_DATA_PTW_ADDR0(raw_ctx));
                    DUT_EVAL(raw_ctx);

                    // Post-edge data read
                    data_addr = DUT_DATA_ADDR(raw_ctx);
                    data_re = DUT_DATA_RE(raw_ctx);
                    if (is_mmio(data_addr)) {
                        rdata = data_re ? handle_mmio_read(m, data_addr) : 0;
                    } else {
                        rdata = data_re ? read_mem_funct3(m->data_mem, m->mem_mask, data_addr, DUT_DATA_FUNCT3(raw_ctx)) : 0;
                    }
                    DUT_DATA_RDATA(raw_ctx) = rdata;
                    DUT_IRQ_SOFTWARE(raw_ctx) = m->irq_software;
                    DUT_IRQ_TIMER(raw_ctx) = m->irq_timer;
                    DUT_IRQ_EXTERNAL(raw_ctx) = m->irq_external;
                    DUT_EVAL(raw_ctx);

                    // CLINT tick
                    m->mtime++;
                    m->irq_timer = (m->mtime >= m->mtimecmp) ? 1 : 0;
                    m->irq_software = (m->msip & 1) ? 1 : 0;
                }
            }
          CODE
        end

        def write_verilator_wrapper(cpp_file, header_file)
          header = <<~H
            #ifndef SIM_WRAPPER_H
            #define SIM_WRAPPER_H
            #ifdef __cplusplus
            extern "C" {
            #endif
            void* sim_create(unsigned int mem_size);
            void sim_destroy(void* sim);
            void sim_reset(void* sim);
            void sim_eval(void* sim);
            void sim_poke(void* sim, const char* name, unsigned int value);
            unsigned int sim_peek(void* sim, const char* name);
            void sim_write_pc(void* sim, unsigned int value);
            void sim_load_mem(void* sim, int mem_type, const unsigned char* data, unsigned int size, unsigned int base_addr);
            void sim_run_cycles(void* sim, unsigned int n_cycles);
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
            #include <cstdlib>

            double sc_time_stamp() { return 0; }

            #{riscv_sim_common_types}

            struct SimContext {
                Vriscv* dut;
                MemState mem;
            };

            // Verilator DUT port access macros (lvalue-capable via struct members)
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

            #{riscv_sim_run_cycles_impl}

            extern "C" {

            void* sim_create(unsigned int mem_size) {
                const char* empty_args[] = {""};
                Verilated::commandArgs(1, empty_args);
                SimContext* ctx = new SimContext();
                ctx->dut = new Vriscv();
                mem_init(&ctx->mem, mem_size);
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
                mem_free(&ctx->mem);
                delete ctx->dut;
                delete ctx;
            }

            void sim_reset(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
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

            void sim_write_pc(void* sim, unsigned int value) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                ctx->dut->rootp->riscv_cpu__DOT__pc_reg___05Fpc = value;
                ctx->dut->eval();
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

          write_file_if_changed(header_file, header)
          write_file_if_changed(cpp_file, cpp)
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

        # ---------- Fiddle FFI ----------

        def load_shared_library
          @lib = Fiddle.dlopen(@lib_path)

          @sim_create_fn = Fiddle::Function.new(
            @lib['sim_create'], [Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP
          )
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
          @sim_write_pc_fn = Fiddle::Function.new(
            @lib['sim_write_pc'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )
          @sim_load_mem_fn = Fiddle::Function.new(
            @lib['sim_load_mem'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )
          @sim_run_cycles_fn = Fiddle::Function.new(
            @lib['sim_run_cycles'],
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )

          @sim_ctx = @sim_create_fn.call(@mem_size)
          @batched_mode = false
        end

        # ---------- CPU interface ----------

        def poke_cpu(name, value)
          v = value.to_i & 0xFFFF_FFFF
          v -= 0x1_0000_0000 if v > 0x7FFF_FFFF
          @sim_poke_fn.call(@sim_ctx, name.to_s, v)
        end

        def peek_cpu(name)
          @sim_peek_fn.call(@sim_ctx, name.to_s) & 0xFFFF_FFFF
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

        # ---------- Memory sync ----------

        def sync_mem_to_native(mem, mem_type)
          backing = mem.instance_variable_get(:@mem)
          if backing.is_a?(Hash)
            return if backing.empty?

            min_addr = backing.keys.min
            max_addr = backing.keys.max
            length = max_addr - min_addr + 1
            buf = "\0".b * length
            backing.each { |addr, byte| buf.setbyte(addr - min_addr, byte) }
            ptr = Fiddle::Pointer.to_ptr(buf)
            @sim_load_mem_fn.call(@sim_ctx, mem_type, ptr, length, min_addr)
          else
            buf = backing.pack('C*')
            ptr = Fiddle::Pointer.to_ptr(buf)
            @sim_load_mem_fn.call(@sim_ctx, mem_type, ptr, buf.size, 0)
          end
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
