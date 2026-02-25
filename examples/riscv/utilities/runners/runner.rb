# frozen_string_literal: true

# RV32I Runner - Shared infrastructure for Verilator and Arcilator runners
#
# Provides the common API, Fiddle FFI bindings, C++ MMIO code generation, and
# memory management. Subclasses implement the build pipeline for their specific
# HDL backend.

require 'fileutils'
require 'fiddle'
require_relative '../../hdl/constants'
require_relative '../../hdl/memory'

module RHDL
  module Examples
    module RISCV
      class Runner
        # Minimal stub for code that probes @cpu.sim for native runner capabilities.
        # HDL runners do not use the Rust native runner.
        class HdlSimStub
          def initialize(simulator_type)
            @simulator_type = simulator_type
          end

          def native?
            false
          end

          def runner_kind
            :hdl
          end

          def simulator_type
            @simulator_type
          end
        end

        attr_reader :clock_count

        def initialize(backend_sym:, simulator_type_sym:, mem_size:)
          @backend = backend_sym
          @simulator_type_sym = simulator_type_sym
          @mem_size = mem_size

          check_tools_available!

          puts "Initializing RISC-V #{@backend.to_s.capitalize} simulation..."
          start_time = Time.now

          build_simulation
          load_shared_library

          elapsed = Time.now - start_time
          puts "  #{@backend.to_s.capitalize} simulation built in #{elapsed.round(2)}s"

          @clock_count = 0
          @debug_reg_addr = 0

          @inst_mem = Memory.new('imem', size: mem_size)
          @data_mem = Memory.new('dmem', size: mem_size)
          @virtio_disk = nil
          @synced = false

          reset!
        end

        # Stub sim object for compatibility with HeadlessRunner checks.
        def sim
          @sim_stub ||= HdlSimStub.new(@simulator_type_sym)
        end

        def native?
          true
        end

        def simulator_type
          @simulator_type_sym
        end

        def backend
          @backend
        end

        def reset!
          @clock_count = 0
          @debug_reg_addr = 0
          @synced = false
          @sim_reset_fn.call(@sim_ctx)
        end

        def run_cycles(n)
          ensure_synced!
          @sim_run_cycles_fn.call(@sim_ctx, n)
          @clock_count += n
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
          raise NotImplementedError, "#{self.class.name} does not support direct register writes"
        end

        def read_pc
          peek_cpu(:debug_pc) & 0xFFFF_FFFF
        end

        def write_pc(value)
          v = value.to_i & 0xFFFF_FFFF
          v -= 0x1_0000_0000 if v > 0x7FFF_FFFF
          @sim_write_pc_fn.call(@sim_ctx, v)
          eval_cpu
        end

        def load_program(program, start_addr = 0)
          @inst_mem.load_program(program, start_addr)
          @synced = false
        end

        def load_data(data, start_addr = 0)
          @data_mem.load_program(data, start_addr)
          @synced = false
        end

        def read_inst_word(addr)
          @inst_mem.read_word(addr)
        end

        def read_data_word(addr)
          @data_mem.read_word(addr)
        end

        def write_data_word(addr, value)
          @data_mem.write_word(addr, value)
          @synced = false
        end

        def set_interrupts(software: nil, timer: nil, external: nil)
          # Managed by C++ batched loop via CLINT
        end

        def set_plic_sources(source1: nil, source10: nil)
          # Managed by C++ batched loop
        end

        def uart_receive_byte(byte)
          uart_receive_bytes([byte & 0xFF])
        end

        def uart_receive_bytes(bytes)
          # C++ batched loop does not support RX injection
        end

        def uart_receive_text(text)
          uart_receive_bytes(text.to_s.b.bytes)
        end

        def uart_tx_bytes
          # C++ batched loop does not buffer TX output
          []
        end

        def clear_uart_tx_bytes
          # No-op for batched HDL runners
        end

        def load_virtio_disk(bytes, offset: 0)
          @virtio_disk = Array.new(offset, 0).concat(bytes.is_a?(Array) ? bytes : bytes.bytes)
        end

        def read_virtio_disk_byte(offset)
          @virtio_disk ? (@virtio_disk[offset] || 0) : 0
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

        # ---- Subclass hooks ----

        def check_tools_available!
          raise NotImplementedError
        end

        def build_simulation
          raise NotImplementedError
        end

        def build_dir
          raise NotImplementedError
        end

        # Path to the compiled shared library (.so)
        def lib_path
          @lib_path
        end

        # ---- FFI ----

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
        end

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

        # ---- Memory sync ----

        def ensure_synced!
          return if @synced

          sync_mem_to_native(@inst_mem, 0) # MEM_TYPE_INST
          sync_mem_to_native(@data_mem, 1) # MEM_TYPE_DATA
          @synced = true
        end

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

        # ---- Utilities ----

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

        # ---- C++ code generation helpers ----

        # Common C types, memory helpers, and MMIO stubs shared by both wrappers.
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

        # C++ FFI function signatures for sim_poke / sim_peek (signal name dispatch).
        # Returns the poke and peek function bodies as a pair of strings.
        # Subclasses provide DUT macros that map signal names to DUT accesses.
        def sim_poke_peek_dispatch
          poke = <<~'CODE'
            void sim_poke(void* sim, const char* name, unsigned int value) {
                SimContext* ctx = CTX_CAST(sim);
                if      (!strcmp(name, "clk"))             DUT_CLK_POKE(ctx, value);
                else if (!strcmp(name, "rst"))             DUT_RST_POKE(ctx, value);
                else if (!strcmp(name, "irq_software"))    DUT_IRQ_SOFTWARE_POKE(ctx, value);
                else if (!strcmp(name, "irq_timer"))       DUT_IRQ_TIMER_POKE(ctx, value);
                else if (!strcmp(name, "irq_external"))    DUT_IRQ_EXTERNAL_POKE(ctx, value);
                else if (!strcmp(name, "inst_data"))       DUT_INST_DATA_POKE(ctx, value);
                else if (!strcmp(name, "data_rdata"))      DUT_DATA_RDATA_POKE(ctx, value);
                else if (!strcmp(name, "debug_reg_addr"))  DUT_DEBUG_REG_ADDR_POKE(ctx, value);
                else if (!strcmp(name, "inst_ptw_pte0"))   DUT_INST_PTW_PTE0_POKE(ctx, value);
                else if (!strcmp(name, "inst_ptw_pte1"))   DUT_INST_PTW_PTE1_POKE(ctx, value);
                else if (!strcmp(name, "data_ptw_pte0"))   DUT_DATA_PTW_PTE0_POKE(ctx, value);
                else if (!strcmp(name, "data_ptw_pte1"))   DUT_DATA_PTW_PTE1_POKE(ctx, value);
            }
          CODE

          peek = <<~'CODE'
            unsigned int sim_peek(void* sim, const char* name) {
                SimContext* ctx = CTX_CAST(sim);
                if      (!strcmp(name, "inst_addr"))       return DUT_INST_ADDR_PEEK(ctx);
                else if (!strcmp(name, "inst_ptw_addr0"))  return DUT_INST_PTW_ADDR0_PEEK(ctx);
                else if (!strcmp(name, "inst_ptw_addr1"))  return DUT_INST_PTW_ADDR1_PEEK(ctx);
                else if (!strcmp(name, "data_addr"))       return DUT_DATA_ADDR_PEEK(ctx);
                else if (!strcmp(name, "data_wdata"))      return DUT_DATA_WDATA_PEEK(ctx);
                else if (!strcmp(name, "data_we"))         return DUT_DATA_WE_PEEK(ctx);
                else if (!strcmp(name, "data_re"))         return DUT_DATA_RE_PEEK(ctx);
                else if (!strcmp(name, "data_funct3"))     return DUT_DATA_FUNCT3_PEEK(ctx);
                else if (!strcmp(name, "data_ptw_addr0"))  return DUT_DATA_PTW_ADDR0_PEEK(ctx);
                else if (!strcmp(name, "data_ptw_addr1"))  return DUT_DATA_PTW_ADDR1_PEEK(ctx);
                else if (!strcmp(name, "debug_pc"))        return DUT_DEBUG_PC_PEEK(ctx);
                else if (!strcmp(name, "debug_inst"))      return DUT_DEBUG_INST_PEEK(ctx);
                else if (!strcmp(name, "debug_x1"))        return DUT_DEBUG_X1_PEEK(ctx);
                else if (!strcmp(name, "debug_x2"))        return DUT_DEBUG_X2_PEEK(ctx);
                else if (!strcmp(name, "debug_x10"))       return DUT_DEBUG_X10_PEEK(ctx);
                else if (!strcmp(name, "debug_x11"))       return DUT_DEBUG_X11_PEEK(ctx);
                else if (!strcmp(name, "debug_reg_data"))  return DUT_DEBUG_REG_DATA_PEEK(ctx);
                return 0;
            }
          CODE
          [poke, peek]
        end
      end
    end
  end
end
