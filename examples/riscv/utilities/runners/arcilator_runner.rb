# frozen_string_literal: true

# RV32I Arcilator Runner - Native RTL simulation via CIRCT arcilator
#
# Self-contained implementation: shared HDL runner logic is in this file.

require 'fileutils'
require 'fiddle'
require 'rhdl/codegen'
require 'rhdl/codegen/circt/tooling'
require 'json'
require 'open3'
require 'rbconfig'
require 'rhdl/sim/native/mlir/arcilator/runtime'
require 'etc'
require_relative '../../hdl/constants'
require_relative '../../hdl/memory'
require_relative '../../hdl/cpu'
require_relative 'verilator_runner'

module RHDL
  module Examples
    module RISCV
      class ArcilatorRunner
        SIGNAL_WIDTHS = VerilogRunner::SIGNAL_WIDTHS

        attr_reader :clock_count

        def initialize(backend_sym:, simulator_type_sym:, mem_size:, jit: false)
          @backend = backend_sym
          @simulator_type_sym = simulator_type_sym
          @mem_size = mem_size
          @jit = !!jit

          check_tools_available!

          puts "Initializing RISC-V #{@backend.to_s.capitalize} simulation..."
          start_time = Time.now

          build_simulation
          jit? ? start_jit_process : load_shared_library

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

        def sim
          @sim
        end

        def jit?
          @jit
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
          if jit?
            send_jit_command('RESET')
          else
            @sim.reset
          end
          self
        end

        def run_cycles(n)
          ensure_synced!
          if jit?
            response = send_jit_command("RUN #{n.to_i}")
            _tag, cycles_run, _uart_tx_len = response.split(' ', 3)
            ran = cycles_run.to_i
            @clock_count += ran
            ran
          else
            result = @sim.runner_run_cycles(n)
            @clock_count += (result && result[:cycles_run]) || n
          end
        end

        def read_reg(index)
          idx = index & 0x1F
          return 0 if idx == 0

          if jit?
            _tag, value = send_jit_command("GET_REG #{idx}").split(' ', 2)
            return value.to_i & 0xFFFF_FFFF
          end

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
          if jit?
            _tag, value = send_jit_command('GET_PC').split(' ', 2)
            return value.to_i & 0xFFFF_FFFF
          end

          peek_cpu(:debug_pc) & 0xFFFF_FFFF
        end

        def write_pc(value)
          v = value.to_i & 0xFFFF_FFFF
          v -= 0x1_0000_0000 if v > 0x7FFF_FFFF
          if jit?
            send_jit_command("SET_PC #{v & 0xFFFF_FFFF}")
            return
          end

          if @sim_write_pc_fn
            @sim_write_pc_fn.call(@sim.raw_context, v)
            eval_cpu
          elsif @sim.runner_set_reset_vector(v)
            reset!
          else
            raise NotImplementedError, "#{self.class.name} cannot write the PC on this runtime"
          end
        end

        def load_program(program, start_addr = 0)
          @inst_mem.load_program(program, start_addr)
          # Keep instruction/data views coherent for unified-memory software
          # images (xv6 kernel, Linux), matching IR runner ROM load behavior.
          @data_mem.load_program(program, start_addr)
          @synced = false
        end

        def load_data(data, start_addr = 0)
          @data_mem.load_program(data, start_addr)
          @synced = false
        end

        def read_inst_word(addr)
          ensure_synced!
          if jit?
            _tag, value = send_jit_command("READ_INST_WORD #{addr.to_i & 0xFFFF_FFFF}").split(' ', 2)
            return value.to_i & 0xFFFF_FFFF
          end

          a = addr.to_i & 0xFFFF_FFFF
          bytes = @sim.runner_read_rom(a, 4)
          return @inst_mem.read_word(addr) if bytes.empty?

          little_endian_word(bytes)
        end

        def read_data_word(addr)
          ensure_synced!
          if jit?
            _tag, value = send_jit_command("READ_DATA_WORD #{addr.to_i & 0xFFFF_FFFF}").split(' ', 2)
            return value.to_i & 0xFFFF_FFFF
          end

          a = addr.to_i & 0xFFFF_FFFF
          bytes = @sim.runner_read_memory(a, 4, mapped: false)
          return @data_mem.read_word(addr) if bytes.empty?

          little_endian_word(bytes)
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
          if jit?
            send_jit_payload_command('UART_RX', bytes)
          else
            @sim.runner_riscv_uart_receive_bytes(bytes)
          end
        end

        def uart_receive_text(text)
          uart_receive_bytes(text.to_s.b.bytes)
        end

        def uart_tx_bytes
          if jit?
            _tag, hex = send_jit_command('GET_UART_TX').split(' ', 2)
            parse_jit_hex_bytes(hex)
          else
            @sim.runner_riscv_uart_tx_bytes
          end
        end

        def clear_uart_tx_bytes
          jit? ? send_jit_command('CLEAR_UART_TX') : @sim.runner_riscv_clear_uart_tx_bytes
        end

        def load_virtio_disk(bytes, offset: 0)
          payload = bytes.is_a?(String) ? bytes.b.bytes : Array(bytes)
          if jit?
            send_jit_payload_command_with_addr('LOAD_DISK', offset.to_i, payload)
          else
            @sim.runner_load_disk(payload.pack('C*'), offset.to_i)
          end
        end

        def read_virtio_disk_byte(offset)
          if jit?
            _tag, value = send_jit_command("READ_DISK_BYTE #{offset.to_i}").split(' ', 2)
            value.to_i & 0xFF
          else
            @sim.runner_read_disk(offset.to_i, 1).first.to_i & 0xFF
          end
        end

        def current_inst
          if jit?
            _tag, value = send_jit_command('GET_INST').split(' ', 2)
            return value.to_i & 0xFFFF_FFFF
          end

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
          @sim = RHDL::Sim::Native::MLIR::Arcilator::Runtime.open(
            lib_path: @lib_path,
            config: runtime_config,
            signal_widths_by_name: SIGNAL_WIDTHS,
            signal_widths_by_idx: SIGNAL_WIDTHS.values,
            backend_label: 'RISC-V Arcilator'
          )
          ensure_runner_abi!(@sim, expected_kind: :riscv, backend_label: 'RISC-V Arcilator')
          @sim_write_pc_fn = @sim.bind_optional_function(
            'sim_write_pc',
            [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT],
            Fiddle::TYPE_VOID
          )
        end

        def start_jit_process
          raise "Linked JIT bitcode not found: #{@jit_bitcode_path}" unless @jit_bitcode_path && File.file?(@jit_bitcode_path)

          cmd = ['lli', '--jit-kind=orc-lazy', "--compile-threads=#{jit_compile_threads}", '-O0', @jit_bitcode_path]
          @jit_stdin, @jit_stdout, @jit_stderr, @jit_wait_thr = Open3.popen3(*cmd)
          @jit_stdin.sync = true
          @jit_stdout.sync = true
          @jit_stderr.sync = true
          @jit_log_thread = Thread.new do
            begin
              File.open(log_path, 'a') do |file|
                @jit_stderr.each_line do |line|
                  file.write(line)
                  file.flush
                end
              end
            rescue IOError
              nil
            end
          end

          ready = @jit_stdout.gets
          return if ready&.strip == 'READY'

          close_jit_process
          raise "RISC-V Arcilator JIT runtime failed to start#{ready ? ": #{ready.strip}" : ''}"
        end

        def ensure_runner_abi!(sim, expected_kind:, backend_label:)
          unless sim.runner_supported?
            sim.close
            raise RuntimeError, "#{backend_label} shared library does not expose runner ABI"
          end

          actual_kind = sim.runner_kind
          return if actual_kind == expected_kind

          sim.close
          raise RuntimeError, "#{backend_label} shared library exposes runner kind #{actual_kind.inspect}, expected #{expected_kind.inspect}"
        end

        def send_jit_command(command)
          raise 'RISC-V Arcilator JIT runner is not active' unless @jit_stdin && @jit_stdout

          @jit_stdin.puts(command)
          response = @jit_stdout.gets
          raise 'RISC-V Arcilator JIT runner exited unexpectedly' unless response

          response = response.strip
          raise "RISC-V Arcilator JIT command failed: #{response}" if response.start_with?('ERR')

          response
        end

        def send_jit_payload_command(prefix, bytes)
          payload = Array(bytes).pack('C*').unpack1('H*')
          send_jit_command("#{prefix} #{payload}")
        end

        def send_jit_payload_command_with_addr(prefix, addr, bytes)
          payload = Array(bytes).pack('C*').unpack1('H*')
          send_jit_command("#{prefix} #{addr.to_i & 0xFFFF_FFFF} #{payload}")
        end

        def parse_jit_hex_bytes(hex)
          return [] if hex.nil? || hex.empty?

          [hex].pack('H*').bytes
        end

        def close_jit_process
          return false unless @jit_wait_thr

          begin
            send_jit_command('QUIT') if @jit_stdin && !@jit_stdin.closed?
          rescue StandardError
            nil
          end

          @jit_stdin&.close unless @jit_stdin&.closed?
          @jit_stdout&.close unless @jit_stdout&.closed?
          @jit_stderr&.close unless @jit_stderr&.closed?
          @jit_wait_thr.value
          @jit_log_thread&.join(1)
          @jit_stdin = nil
          @jit_stdout = nil
          @jit_stderr = nil
          @jit_wait_thr = nil
          @jit_log_thread = nil
          true
        end

        def poke_cpu(name, value)
          v = value.to_i & 0xFFFF_FFFF
          v -= 0x1_0000_0000 if v > 0x7FFF_FFFF
          @sim.poke(name.to_s, v)
        end

        def peek_cpu(name)
          @sim.peek(name.to_s) & 0xFFFF_FFFF
        end

        def eval_cpu
          @sim.evaluate
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
            sync_runtime_memory(mem_type, buf, min_addr)
          else
            buf = backing.pack('C*')
            sync_runtime_memory(mem_type, buf, 0)
          end
        end

        def sync_runtime_memory(mem_type, payload, base_addr)
          if jit?
            if mem_type == 0
              send_jit_payload_command_with_addr('LOAD_ROM', base_addr, payload.bytes)
            else
              send_jit_payload_command_with_addr('LOAD_MAIN', base_addr, payload.bytes)
            end
          elsif mem_type == 0
            @sim.runner_load_rom(payload, base_addr)
          else
            @sim.runner_load_memory(payload, base_addr, false)
          end
        end

        def little_endian_word(bytes)
          Array(bytes).first(4).each_with_index.reduce(0) do |acc, (byte, idx)|
            acc | ((byte.to_i & 0xFF) << (idx * 8))
          end
        end

        def runtime_config
          { 'mem_size' => @mem_size }
        end

        def jit_compile_threads
          [Etc.nprocessors, 8].compact.min
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
            #define FUNCT3_BYTE 0u
            #define FUNCT3_HALF 1u
            #define FUNCT3_WORD 2u
            #define FUNCT3_BYTE_U 4u
            #define FUNCT3_HALF_U 5u

            // CLINT addresses
            #define CLINT_BASE        0x02000000u
            #define CLINT_MSIP        (CLINT_BASE + 0x0000u)
            #define CLINT_MTIMECMP_LO (CLINT_BASE + 0x4000u)
            #define CLINT_MTIMECMP_HI (CLINT_BASE + 0x4004u)
            #define CLINT_MTIME_LO    (CLINT_BASE + 0xBFF8u)
            #define CLINT_MTIME_HI    (CLINT_BASE + 0xBFFCu)

            // PLIC addresses
            #define PLIC_BASE               0x0C000000u
            #define PLIC_PRIORITY_1         (PLIC_BASE + 0x0004u)
            #define PLIC_PRIORITY_10        (PLIC_BASE + 0x0028u)
            #define PLIC_PENDING            (PLIC_BASE + 0x1000u)
            #define PLIC_ENABLE             (PLIC_BASE + 0x2000u)
            #define PLIC_SENABLE            (PLIC_BASE + 0x2080u)
            #define PLIC_THRESHOLD          (PLIC_BASE + 0x200000u)
            #define PLIC_STHRESHOLD         (PLIC_BASE + 0x201000u)
            #define PLIC_CLAIM_COMPLETE     (PLIC_BASE + 0x200004u)
            #define PLIC_SCLAIM_COMPLETE    (PLIC_BASE + 0x201004u)

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

            // VirtIO block MMIO addresses
            #define VIRTIO_BASE                  0x10001000u
            #define VIRTIO_MAGIC_VALUE           (VIRTIO_BASE + 0x000u)
            #define VIRTIO_VERSION               (VIRTIO_BASE + 0x004u)
            #define VIRTIO_DEVICE_ID             (VIRTIO_BASE + 0x008u)
            #define VIRTIO_VENDOR_ID_ADDR        (VIRTIO_BASE + 0x00Cu)
            #define VIRTIO_DEVICE_FEATURES       (VIRTIO_BASE + 0x010u)
            #define VIRTIO_DEVICE_FEATURES_SEL   (VIRTIO_BASE + 0x014u)
            #define VIRTIO_DRIVER_FEATURES       (VIRTIO_BASE + 0x020u)
            #define VIRTIO_DRIVER_FEATURES_SEL   (VIRTIO_BASE + 0x024u)
            #define VIRTIO_GUEST_PAGE_SIZE       (VIRTIO_BASE + 0x028u)
            #define VIRTIO_QUEUE_SEL             (VIRTIO_BASE + 0x030u)
            #define VIRTIO_QUEUE_NUM_MAX_ADDR    (VIRTIO_BASE + 0x034u)
            #define VIRTIO_QUEUE_NUM             (VIRTIO_BASE + 0x038u)
            #define VIRTIO_QUEUE_ALIGN           (VIRTIO_BASE + 0x03Cu)
            #define VIRTIO_QUEUE_PFN             (VIRTIO_BASE + 0x040u)
            #define VIRTIO_QUEUE_READY           (VIRTIO_BASE + 0x044u)
            #define VIRTIO_QUEUE_NOTIFY          (VIRTIO_BASE + 0x050u)
            #define VIRTIO_INTERRUPT_STATUS      (VIRTIO_BASE + 0x060u)
            #define VIRTIO_INTERRUPT_ACK         (VIRTIO_BASE + 0x064u)
            #define VIRTIO_STATUS                (VIRTIO_BASE + 0x070u)
            #define VIRTIO_QUEUE_DESC_LOW        (VIRTIO_BASE + 0x080u)
            #define VIRTIO_QUEUE_DESC_HIGH       (VIRTIO_BASE + 0x084u)
            #define VIRTIO_QUEUE_DRIVER_LOW      (VIRTIO_BASE + 0x090u)
            #define VIRTIO_QUEUE_DRIVER_HIGH     (VIRTIO_BASE + 0x094u)
            #define VIRTIO_QUEUE_DEVICE_LOW      (VIRTIO_BASE + 0x0A0u)
            #define VIRTIO_QUEUE_DEVICE_HIGH     (VIRTIO_BASE + 0x0A4u)
            #define VIRTIO_CONFIG_GENERATION     (VIRTIO_BASE + 0x0FCu)
            #define VIRTIO_CONFIG_CAPACITY_LOW   (VIRTIO_BASE + 0x100u)
            #define VIRTIO_CONFIG_CAPACITY_HIGH  (VIRTIO_BASE + 0x104u)
            #define VIRTIO_MMIO_END              (VIRTIO_BASE + 0x1104u)

            #define VIRTIO_MAGIC_CONST 0x74726976u
            #define VIRTIO_VENDOR_CONST 0x554D4551u
            #define VIRTIO_STATUS_DRIVER_OK 0x04u
            #define VIRTIO_INTERRUPT_USED_BUFFER 0x01u
            #define VIRTIO_DESC_F_NEXT 0x0001u
            #define VIRTIO_REQ_T_IN 0u
            #define VIRTIO_REQ_T_OUT 1u
            #define VIRTIO_SECTOR_BYTES 512ull
            #define VIRTIO_QUEUE_NUM_MAX 8u
            #define DEFAULT_DISK_BYTES (8u * 1024u * 1024u)
            #define UART_RX_QUEUE_CAPACITY 65536u
            #define MASK64 0xFFFFFFFFFFFFFFFFull

            struct VirtioDesc {
                uint64_t addr;
                uint32_t len;
                uint16_t flags;
                uint16_t next;
            };

            struct MemState {
                uint8_t* inst_mem;
                uint8_t* data_mem;
                uint8_t* disk;
                uint32_t mem_size;
                uint32_t mem_mask;
                uint32_t disk_size;
                // CLINT
                uint64_t mtime;
                uint64_t mtimecmp;
                uint32_t msip;
                // IRQ outputs to DUT
                uint8_t irq_timer;
                uint8_t irq_software;
                uint8_t irq_external;
                // PLIC
                uint32_t plic_priority1;
                uint32_t plic_priority10;
                uint32_t plic_pending1;
                uint32_t plic_pending10;
                uint32_t plic_enable1;
                uint32_t plic_enable10;
                uint32_t plic_threshold;
                uint32_t plic_in_service_id;
                uint8_t plic_prev_source1;
                uint8_t plic_prev_source10;
                // UART
                uint8_t uart_rbr;
                uint8_t uart_ier;
                uint8_t uart_lcr;
                uint8_t uart_mcr;
                uint8_t uart_dll;
                uint8_t uart_dlm;
                uint8_t uart_scr;
                uint8_t uart_rx_ready;
                uint8_t uart_tx_data_reg;
                uint8_t uart_tx_irq_pending;
                uint8_t uart_rx_queue[UART_RX_QUEUE_CAPACITY];
                uint32_t uart_rx_head;
                uint32_t uart_rx_tail;
                uint32_t uart_rx_count;
                uint8_t* uart_tx_bytes;
                uint32_t uart_tx_len;
                uint32_t uart_tx_cap;
                // VirtIO block
                uint32_t virtio_device_features_sel;
                uint32_t virtio_driver_features_sel;
                uint32_t virtio_driver_features_0;
                uint32_t virtio_driver_features_1;
                uint32_t virtio_guest_page_size;
                uint32_t virtio_queue_sel;
                uint16_t virtio_queue_num;
                uint32_t virtio_queue_ready;
                uint64_t virtio_queue_desc;
                uint64_t virtio_queue_driver;
                uint64_t virtio_queue_device;
                uint32_t virtio_queue_pfn;
                uint32_t virtio_queue_align;
                uint32_t virtio_status;
                uint32_t virtio_interrupt_status;
                uint8_t virtio_notify_pending;
                uint16_t virtio_last_avail_idx;
                uint8_t virtio_irq;
            };

            static void virtio_reset_state(MemState* m) {
                m->virtio_device_features_sel = 0;
                m->virtio_driver_features_sel = 0;
                m->virtio_driver_features_0 = 0;
                m->virtio_driver_features_1 = 0;
                m->virtio_guest_page_size = 0;
                m->virtio_queue_sel = 0;
                m->virtio_queue_num = 0;
                m->virtio_queue_ready = 0;
                m->virtio_queue_desc = 0;
                m->virtio_queue_driver = 0;
                m->virtio_queue_device = 0;
                m->virtio_queue_pfn = 0;
                m->virtio_queue_align = 0;
                m->virtio_status = 0;
                m->virtio_interrupt_status = 0;
                m->virtio_notify_pending = 0;
                m->virtio_last_avail_idx = 0;
                m->virtio_irq = 0;
            }

            static void mem_init(MemState* m, uint32_t size) {
                m->inst_mem = (uint8_t*)calloc(size, 1);
                m->data_mem = (uint8_t*)calloc(size, 1);
                m->disk = (uint8_t*)calloc(DEFAULT_DISK_BYTES, 1);
                m->mem_size = size;
                m->mem_mask = size - 1;
                m->disk_size = DEFAULT_DISK_BYTES;
                m->mtime = 0;
                m->mtimecmp = MASK64;
                m->msip = 0;
                m->irq_timer = 0;
                m->irq_software = 0;
                m->irq_external = 0;
                m->plic_priority1 = 0;
                m->plic_priority10 = 0;
                m->plic_pending1 = 0;
                m->plic_pending10 = 0;
                m->plic_enable1 = 0;
                m->plic_enable10 = 0;
                m->plic_threshold = 0;
                m->plic_in_service_id = 0;
                m->plic_prev_source1 = 0;
                m->plic_prev_source10 = 0;
                m->uart_rbr = 0;
                m->uart_ier = 0;
                m->uart_lcr = 0;
                m->uart_mcr = 0;
                m->uart_dll = 0;
                m->uart_dlm = 0;
                m->uart_scr = 0;
                m->uart_rx_ready = 0;
                m->uart_tx_data_reg = 0;
                m->uart_tx_irq_pending = 0;
                m->uart_rx_head = 0;
                m->uart_rx_tail = 0;
                m->uart_rx_count = 0;
                m->uart_tx_cap = 1024;
                m->uart_tx_len = 0;
                m->uart_tx_bytes = (uint8_t*)malloc(m->uart_tx_cap);
                virtio_reset_state(m);
            }

            static void mem_free(MemState* m) {
                free(m->inst_mem);
                free(m->data_mem);
                free(m->disk);
                free(m->uart_tx_bytes);
            }

            static void load_mem(MemState* m, int mem_type, const uint8_t* data, uint32_t size, uint32_t base) {
                uint8_t* target = (mem_type == MEM_TYPE_INST) ? m->inst_mem : m->data_mem;
                for (uint32_t i = 0; i < size; i++) {
                    target[(base + i) & m->mem_mask] = data[i];
                }
            }

            static int disk_load(MemState* m, const uint8_t* data, uint32_t size, uint32_t base) {
                if (!data || size == 0) return 0;
                if (base >= m->disk_size) return 0;
                uint32_t limit = m->disk_size - base;
                uint32_t count = size < limit ? size : limit;
                memcpy(m->disk + base, data, count);
                return (int)count;
            }

            static uint8_t disk_read_byte(MemState* m, uint32_t offset) {
                if (offset >= m->disk_size) return 0;
                return m->disk[offset];
            }

            static inline uint32_t read_word_le(const uint8_t* mem, uint32_t mask, uint32_t addr) {
                uint32_t a = addr & mask;
                return (uint32_t)mem[a] | ((uint32_t)mem[(a+1)&mask] << 8) |
                       ((uint32_t)mem[(a+2)&mask] << 16) | ((uint32_t)mem[(a+3)&mask] << 24);
            }

            static inline uint16_t read_half_le(const uint8_t* mem, uint32_t mask, uint32_t addr) {
                uint32_t a = addr & mask;
                return (uint16_t)mem[a] | ((uint16_t)mem[(a+1)&mask] << 8);
            }

            static inline void write_word_le(uint8_t* mem, uint32_t mask, uint32_t addr, uint32_t val) {
                uint32_t a = addr & mask;
                mem[a] = (uint8_t)val;
                mem[(a+1)&mask] = (uint8_t)(val >> 8);
                mem[(a+2)&mask] = (uint8_t)(val >> 16);
                mem[(a+3)&mask] = (uint8_t)(val >> 24);
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
                switch (a) {
                case PLIC_PRIORITY_1:
                case PLIC_PRIORITY_10:
                case PLIC_PENDING:
                case PLIC_ENABLE:
                case PLIC_SENABLE:
                case PLIC_THRESHOLD:
                case PLIC_STHRESHOLD:
                case PLIC_CLAIM_COMPLETE:
                case PLIC_SCLAIM_COMPLETE:
                    return 1;
                default:
                    return 0;
                }
            }

            static inline int is_virtio(uint32_t a) {
                switch (a) {
                case VIRTIO_MAGIC_VALUE:
                case VIRTIO_VERSION:
                case VIRTIO_DEVICE_ID:
                case VIRTIO_VENDOR_ID_ADDR:
                case VIRTIO_DEVICE_FEATURES:
                case VIRTIO_DEVICE_FEATURES_SEL:
                case VIRTIO_DRIVER_FEATURES:
                case VIRTIO_DRIVER_FEATURES_SEL:
                case VIRTIO_GUEST_PAGE_SIZE:
                case VIRTIO_QUEUE_SEL:
                case VIRTIO_QUEUE_NUM_MAX_ADDR:
                case VIRTIO_QUEUE_NUM:
                case VIRTIO_QUEUE_ALIGN:
                case VIRTIO_QUEUE_PFN:
                case VIRTIO_QUEUE_READY:
                case VIRTIO_QUEUE_NOTIFY:
                case VIRTIO_INTERRUPT_STATUS:
                case VIRTIO_INTERRUPT_ACK:
                case VIRTIO_STATUS:
                case VIRTIO_QUEUE_DESC_LOW:
                case VIRTIO_QUEUE_DESC_HIGH:
                case VIRTIO_QUEUE_DRIVER_LOW:
                case VIRTIO_QUEUE_DRIVER_HIGH:
                case VIRTIO_QUEUE_DEVICE_LOW:
                case VIRTIO_QUEUE_DEVICE_HIGH:
                case VIRTIO_CONFIG_GENERATION:
                case VIRTIO_CONFIG_CAPACITY_LOW:
                case VIRTIO_CONFIG_CAPACITY_HIGH:
                    return 1;
                default:
                    return 0;
                }
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

            static inline int uart_access_ok(uint32_t funct3) {
                return funct3 == FUNCT3_WORD || funct3 == FUNCT3_BYTE || funct3 == FUNCT3_BYTE_U;
            }

            static inline int uart_rx_queue_push_byte(MemState* m, uint8_t byte) {
                if (m->uart_rx_count >= UART_RX_QUEUE_CAPACITY) return 0;
                m->uart_rx_queue[m->uart_rx_tail] = byte;
                m->uart_rx_tail = (m->uart_rx_tail + 1) % UART_RX_QUEUE_CAPACITY;
                m->uart_rx_count++;
                return 1;
            }

            static void uart_rx_queue_push_bytes(MemState* m, const uint8_t* data, uint32_t len) {
                if (!data || len == 0) return;
                for (uint32_t i = 0; i < len; i++) {
                    if (!uart_rx_queue_push_byte(m, data[i])) break;
                }
            }

            static inline int uart_rx_queue_pop_byte(MemState* m, uint8_t* out) {
                if (m->uart_rx_count == 0) return 0;
                if (out) *out = m->uart_rx_queue[m->uart_rx_head];
                m->uart_rx_head = (m->uart_rx_head + 1) % UART_RX_QUEUE_CAPACITY;
                m->uart_rx_count--;
                return 1;
            }

            static inline void uart_feed_rx_slot(MemState* m) {
                if (m->uart_rx_ready) return;
                uint8_t next = 0;
                if (uart_rx_queue_pop_byte(m, &next)) {
                    m->uart_rbr = next;
                    m->uart_rx_ready = 1;
                }
            }

            static inline int uart_tx_append(MemState* m, uint8_t byte) {
                if (m->uart_tx_len >= m->uart_tx_cap) {
                    uint32_t next_cap = m->uart_tx_cap < 1024 ? 1024 : m->uart_tx_cap * 2;
                    uint8_t* resized = (uint8_t*)realloc(m->uart_tx_bytes, next_cap);
                    if (!resized) return 0;
                    m->uart_tx_bytes = resized;
                    m->uart_tx_cap = next_cap;
                }
                m->uart_tx_bytes[m->uart_tx_len++] = byte;
                return 1;
            }

            static inline int uart_rx_irq_pending(MemState* m) {
                return ((m->uart_ier & 0x1u) != 0u) && m->uart_rx_ready;
            }

            static inline int uart_tx_irq_pending(MemState* m) {
                return m->uart_tx_irq_pending != 0;
            }

            static inline int uart_irq_pending(MemState* m) {
                return uart_rx_irq_pending(m) || uart_tx_irq_pending(m);
            }

            static inline uint8_t uart_iir(MemState* m) {
                if (uart_rx_irq_pending(m)) return 0x04;
                if (uart_tx_irq_pending(m)) return 0x02;
                return 0x01;
            }

            static inline uint8_t uart_lsr(MemState* m) {
                return (uint8_t)(0x60u | (m->uart_rx_ready ? 0x01u : 0x00u));
            }

            static uint32_t handle_uart_read(MemState* m, uint32_t addr, uint32_t funct3) {
                if (!uart_access_ok(funct3)) return 0;

                uint32_t reg_offset = addr & 0x7u;
                int dlab = (m->uart_lcr & 0x80u) != 0;
                uint8_t iir = uart_iir(m);
                uint8_t read_byte = 0;

                switch (reg_offset) {
                case 0: // THR/RBR/DLL
                    if (dlab) {
                        read_byte = m->uart_dll;
                    } else {
                        read_byte = m->uart_rbr;
                    }
                    break;
                case 1: // IER/DLM
                    read_byte = dlab ? m->uart_dlm : m->uart_ier;
                    break;
                case 2: // IIR/FCR
                    read_byte = iir;
                    break;
                case 3:
                    read_byte = m->uart_lcr;
                    break;
                case 4:
                    read_byte = m->uart_mcr;
                    break;
                case 5:
                    read_byte = uart_lsr(m);
                    break;
                case 6:
                    read_byte = 0;
                    break;
                case 7:
                    read_byte = m->uart_scr;
                    break;
                default:
                    read_byte = 0;
                    break;
                }

                if (funct3 == FUNCT3_BYTE) {
                    int8_t s = (int8_t)read_byte;
                    return (uint32_t)(int32_t)s;
                }
                return (uint32_t)read_byte;
            }

            static void handle_uart_write(MemState* m, uint32_t addr, uint32_t val, uint32_t funct3) {
                if (!uart_access_ok(funct3)) return;

                uint32_t reg_offset = addr & 0x7u;
                uint8_t write_byte = (uint8_t)(val & 0xFFu);
                int dlab = (m->uart_lcr & 0x80u) != 0;

                switch (reg_offset) {
                case 0: // THR/RBR/DLL
                    if (dlab) {
                        m->uart_dll = write_byte;
                    } else {
                        m->uart_tx_data_reg = write_byte;
                        uart_tx_append(m, write_byte);
                        m->uart_tx_irq_pending = ((m->uart_ier & 0x2u) != 0u) ? 1 : 0;
                    }
                    break;
                case 1: // IER/DLM
                    if (dlab) {
                        m->uart_dlm = write_byte;
                    } else {
                        m->uart_ier = write_byte & 0x0Fu;
                        if ((m->uart_ier & 0x2u) == 0u) m->uart_tx_irq_pending = 0;
                    }
                    break;
                case 2: // IIR/FCR
                    if ((write_byte & 0x2u) != 0u) m->uart_rx_ready = 0;
                    break;
                case 3:
                    m->uart_lcr = write_byte;
                    break;
                case 4:
                    m->uart_mcr = write_byte;
                    break;
                case 7:
                    m->uart_scr = write_byte;
                    break;
                default:
                    break;
                }
            }

            static void handle_uart_read_commit(MemState* m, uint32_t addr, uint32_t funct3) {
                if (!uart_access_ok(funct3)) return;

                uint32_t reg_offset = addr & 0x7u;
                int dlab = (m->uart_lcr & 0x80u) != 0;
                uint8_t iir = uart_iir(m);

                if (reg_offset == 0u && !dlab && m->uart_rx_ready) {
                    m->uart_rx_ready = 0;
                }
                if (reg_offset == 2u && iir == 0x02u) {
                    m->uart_tx_irq_pending = 0;
                }
            }

            static uint32_t uart_tx_len(MemState* m) {
                return m->uart_tx_len;
            }

            static uint32_t uart_tx_copy(MemState* m, uint8_t* out, uint32_t max_len) {
                if (!out || max_len == 0 || m->uart_tx_len == 0) return 0;
                uint32_t n = m->uart_tx_len < max_len ? m->uart_tx_len : max_len;
                memcpy(out, m->uart_tx_bytes, n);
                return n;
            }

            static void uart_tx_clear(MemState* m) {
                m->uart_tx_len = 0;
            }

            static inline uint8_t virtio_irq_asserted(MemState* m) {
                return (m->virtio_interrupt_status & 0x3u) != 0u ? 1u : 0u;
            }

            static inline uint64_t virtio_capacity_sectors(MemState* m) {
                return ((uint64_t)m->disk_size) / VIRTIO_SECTOR_BYTES;
            }

            static inline uint32_t virtio_device_features_for_sel(MemState* m, uint32_t sel) {
                (void)m;
                (void)sel;
                return 0;
            }

            static inline uint64_t virtio_legacy_page_size(MemState* m) {
                return m->virtio_guest_page_size == 0 ? 4096ull : (uint64_t)m->virtio_guest_page_size;
            }

            static inline uint64_t virtio_align_up(uint64_t value, uint64_t align) {
                if (align <= 1ull) return value;
                if ((align & (align - 1ull)) == 0ull) {
                    uint64_t mask = align - 1ull;
                    return (value + mask) & ~mask;
                }
                uint64_t rem = value % align;
                return rem == 0ull ? value : (value + (align - rem));
            }

            static inline uint64_t virtio_legacy_queue_desc(MemState* m) {
                return ((uint64_t)m->virtio_queue_pfn) * virtio_legacy_page_size(m);
            }

            static inline uint64_t virtio_legacy_queue_driver(MemState* m) {
                return virtio_legacy_queue_desc(m) + ((uint64_t)m->virtio_queue_num * 16ull);
            }

            static inline uint64_t virtio_legacy_queue_device(MemState* m) {
                uint64_t avail_base = virtio_legacy_queue_driver(m);
                uint64_t avail_bytes = 6ull + ((uint64_t)m->virtio_queue_num * 2ull);
                uint64_t align = m->virtio_queue_align == 0 ? 4096ull : (uint64_t)m->virtio_queue_align;
                return virtio_align_up(avail_base + avail_bytes, align);
            }

            static inline uint64_t virtio_queue_desc_addr(MemState* m) {
                if (m->virtio_queue_desc != 0ull) return m->virtio_queue_desc;
                if (m->virtio_queue_pfn != 0u) return virtio_legacy_queue_desc(m);
                return 0ull;
            }

            static inline uint64_t virtio_queue_driver_addr(MemState* m) {
                if (m->virtio_queue_driver != 0ull) return m->virtio_queue_driver;
                if (m->virtio_queue_pfn != 0u) return virtio_legacy_queue_driver(m);
                return 0ull;
            }

            static inline uint64_t virtio_queue_device_addr(MemState* m) {
                if (m->virtio_queue_device != 0ull) return m->virtio_queue_device;
                if (m->virtio_queue_pfn != 0u) return virtio_legacy_queue_device(m);
                return 0ull;
            }

            static inline uint8_t virtio_mem_read_u8(MemState* m, uint64_t addr) {
                return m->data_mem[((uint32_t)addr) & m->mem_mask];
            }

            static inline void virtio_mem_write_u8(MemState* m, uint64_t addr, uint8_t value) {
                uint32_t idx = ((uint32_t)addr) & m->mem_mask;
                m->data_mem[idx] = value;
                m->inst_mem[idx] = value;
            }

            static inline uint16_t virtio_mem_read_u16(MemState* m, uint64_t addr) {
                uint16_t lo = virtio_mem_read_u8(m, addr);
                uint16_t hi = virtio_mem_read_u8(m, addr + 1ull);
                return (uint16_t)((hi << 8) | lo);
            }

            static inline void virtio_mem_write_u16(MemState* m, uint64_t addr, uint16_t value) {
                virtio_mem_write_u8(m, addr, (uint8_t)(value & 0xFFu));
                virtio_mem_write_u8(m, addr + 1ull, (uint8_t)((value >> 8) & 0xFFu));
            }

            static inline uint32_t virtio_mem_read_u32(MemState* m, uint64_t addr) {
                uint32_t b0 = virtio_mem_read_u8(m, addr);
                uint32_t b1 = virtio_mem_read_u8(m, addr + 1ull);
                uint32_t b2 = virtio_mem_read_u8(m, addr + 2ull);
                uint32_t b3 = virtio_mem_read_u8(m, addr + 3ull);
                return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
            }

            static inline void virtio_mem_write_u32(MemState* m, uint64_t addr, uint32_t value) {
                virtio_mem_write_u8(m, addr, (uint8_t)(value & 0xFFu));
                virtio_mem_write_u8(m, addr + 1ull, (uint8_t)((value >> 8) & 0xFFu));
                virtio_mem_write_u8(m, addr + 2ull, (uint8_t)((value >> 16) & 0xFFu));
                virtio_mem_write_u8(m, addr + 3ull, (uint8_t)((value >> 24) & 0xFFu));
            }

            static inline uint64_t virtio_mem_read_u64(MemState* m, uint64_t addr) {
                uint64_t lo = virtio_mem_read_u32(m, addr);
                uint64_t hi = virtio_mem_read_u32(m, addr + 4ull);
                return lo | (hi << 32);
            }

            static int virtio_queue_operational(MemState* m) {
                int modern_ready = m->virtio_queue_ready == 1u &&
                                   m->virtio_queue_desc != 0ull &&
                                   m->virtio_queue_driver != 0ull &&
                                   m->virtio_queue_device != 0ull;
                int legacy_ready = m->virtio_queue_pfn != 0u;
                return m->virtio_queue_sel == 0u &&
                       m->virtio_queue_num > 0u &&
                       (m->virtio_status & VIRTIO_STATUS_DRIVER_OK) != 0u &&
                       (modern_ready || legacy_ready);
            }

            static uint32_t virtio_read_register(MemState* m, uint32_t addr) {
                switch (addr) {
                case VIRTIO_MAGIC_VALUE: return VIRTIO_MAGIC_CONST;
                case VIRTIO_VERSION: return 1u;
                case VIRTIO_DEVICE_ID: return 2u;
                case VIRTIO_VENDOR_ID_ADDR: return VIRTIO_VENDOR_CONST;
                case VIRTIO_DEVICE_FEATURES: return virtio_device_features_for_sel(m, m->virtio_device_features_sel);
                case VIRTIO_DEVICE_FEATURES_SEL: return m->virtio_device_features_sel;
                case VIRTIO_DRIVER_FEATURES:
                    return m->virtio_driver_features_sel == 0u ? m->virtio_driver_features_0 : m->virtio_driver_features_1;
                case VIRTIO_DRIVER_FEATURES_SEL: return m->virtio_driver_features_sel;
                case VIRTIO_GUEST_PAGE_SIZE: return m->virtio_guest_page_size;
                case VIRTIO_QUEUE_SEL: return m->virtio_queue_sel;
                case VIRTIO_QUEUE_NUM_MAX_ADDR: return m->virtio_queue_sel == 0u ? VIRTIO_QUEUE_NUM_MAX : 0u;
                case VIRTIO_QUEUE_NUM: return m->virtio_queue_sel == 0u ? (uint32_t)m->virtio_queue_num : 0u;
                case VIRTIO_QUEUE_ALIGN: return m->virtio_queue_align;
                case VIRTIO_QUEUE_PFN: return m->virtio_queue_pfn;
                case VIRTIO_QUEUE_READY: return m->virtio_queue_sel == 0u ? m->virtio_queue_ready : 0u;
                case VIRTIO_INTERRUPT_STATUS: return m->virtio_interrupt_status & 0x3u;
                case VIRTIO_STATUS: return m->virtio_status & 0xFFu;
                case VIRTIO_QUEUE_DESC_LOW: return (uint32_t)m->virtio_queue_desc;
                case VIRTIO_QUEUE_DESC_HIGH: return (uint32_t)(m->virtio_queue_desc >> 32);
                case VIRTIO_QUEUE_DRIVER_LOW: return (uint32_t)m->virtio_queue_driver;
                case VIRTIO_QUEUE_DRIVER_HIGH: return (uint32_t)(m->virtio_queue_driver >> 32);
                case VIRTIO_QUEUE_DEVICE_LOW: return (uint32_t)m->virtio_queue_device;
                case VIRTIO_QUEUE_DEVICE_HIGH: return (uint32_t)(m->virtio_queue_device >> 32);
                case VIRTIO_CONFIG_GENERATION: return 0u;
                case VIRTIO_CONFIG_CAPACITY_LOW: return (uint32_t)virtio_capacity_sectors(m);
                case VIRTIO_CONFIG_CAPACITY_HIGH: return (uint32_t)(virtio_capacity_sectors(m) >> 32);
                default: return 0u;
                }
            }

            static void virtio_write_register(MemState* m, uint32_t addr, uint32_t value) {
                switch (addr) {
                case VIRTIO_DEVICE_FEATURES_SEL:
                    m->virtio_device_features_sel = value & 0x1u;
                    break;
                case VIRTIO_DRIVER_FEATURES_SEL:
                    m->virtio_driver_features_sel = value & 0x1u;
                    break;
                case VIRTIO_DRIVER_FEATURES:
                    if (m->virtio_driver_features_sel == 0u) m->virtio_driver_features_0 = value;
                    else m->virtio_driver_features_1 = value;
                    break;
                case VIRTIO_GUEST_PAGE_SIZE:
                    m->virtio_guest_page_size = value;
                    break;
                case VIRTIO_QUEUE_SEL:
                    m->virtio_queue_sel = value;
                    if (m->virtio_queue_sel != 0u) m->virtio_last_avail_idx = 0u;
                    break;
                case VIRTIO_QUEUE_NUM:
                    if (m->virtio_queue_sel == 0u) {
                        uint16_t num = (uint16_t)(value & 0xFFFFu);
                        if (num < 1u) num = 1u;
                        if (num > VIRTIO_QUEUE_NUM_MAX) num = VIRTIO_QUEUE_NUM_MAX;
                        m->virtio_queue_num = num;
                    } else {
                        m->virtio_queue_num = 0u;
                    }
                    break;
                case VIRTIO_QUEUE_ALIGN:
                    m->virtio_queue_align = value;
                    break;
                case VIRTIO_QUEUE_PFN:
                    m->virtio_queue_pfn = value;
                    break;
                case VIRTIO_QUEUE_READY:
                    m->virtio_queue_ready = m->virtio_queue_sel == 0u ? (value & 0x1u) : 0u;
                    if (m->virtio_queue_ready == 0u) m->virtio_last_avail_idx = 0u;
                    break;
                case VIRTIO_QUEUE_NOTIFY:
                    if ((value & 0xFFFFu) == 0u) m->virtio_notify_pending = 1u;
                    break;
                case VIRTIO_INTERRUPT_ACK:
                    m->virtio_interrupt_status &= ~(value & 0x3u);
                    break;
                case VIRTIO_STATUS:
                    if ((value & 0xFFu) == 0u) virtio_reset_state(m);
                    else m->virtio_status = value & 0xFFu;
                    break;
                case VIRTIO_QUEUE_DESC_LOW:
                    m->virtio_queue_desc = (m->virtio_queue_desc & 0xFFFFFFFF00000000ull) | (uint64_t)value;
                    break;
                case VIRTIO_QUEUE_DESC_HIGH:
                    m->virtio_queue_desc = ((uint64_t)value << 32) | (m->virtio_queue_desc & 0xFFFFFFFFull);
                    break;
                case VIRTIO_QUEUE_DRIVER_LOW:
                    m->virtio_queue_driver = (m->virtio_queue_driver & 0xFFFFFFFF00000000ull) | (uint64_t)value;
                    break;
                case VIRTIO_QUEUE_DRIVER_HIGH:
                    m->virtio_queue_driver = ((uint64_t)value << 32) | (m->virtio_queue_driver & 0xFFFFFFFFull);
                    break;
                case VIRTIO_QUEUE_DEVICE_LOW:
                    m->virtio_queue_device = (m->virtio_queue_device & 0xFFFFFFFF00000000ull) | (uint64_t)value;
                    break;
                case VIRTIO_QUEUE_DEVICE_HIGH:
                    m->virtio_queue_device = ((uint64_t)value << 32) | (m->virtio_queue_device & 0xFFFFFFFFull);
                    break;
                default:
                    break;
                }
            }

            static int virtio_read_desc(MemState* m, uint16_t desc_idx, struct VirtioDesc* out) {
                if (!out) return 0;
                if (m->virtio_queue_num == 0u || desc_idx >= m->virtio_queue_num) return 0;
                uint64_t queue_desc = virtio_queue_desc_addr(m);
                if (queue_desc == 0ull) return 0;
                uint64_t base = queue_desc + ((uint64_t)desc_idx * 16ull);
                out->addr = virtio_mem_read_u64(m, base);
                out->len = virtio_mem_read_u32(m, base + 8ull);
                out->flags = virtio_mem_read_u16(m, base + 12ull);
                out->next = virtio_mem_read_u16(m, base + 14ull);
                return 1;
            }

            static int virtio_transfer_data(MemState* m, uint32_t req_type, uint64_t sector, uint64_t data_addr, uint32_t data_len) {
                uint64_t disk_offset = sector * VIRTIO_SECTOR_BYTES;
                if (disk_offset >= (uint64_t)m->disk_size) return 0;

                uint32_t len = data_len;
                switch (req_type) {
                case VIRTIO_REQ_T_IN:
                    for (uint32_t idx = 0; idx < len; idx++) {
                        uint64_t src64 = disk_offset + (uint64_t)idx;
                        uint8_t byte = src64 < (uint64_t)m->disk_size ? m->disk[(uint32_t)src64] : 0u;
                        virtio_mem_write_u8(m, data_addr + (uint64_t)idx, byte);
                    }
                    return 1;
                case VIRTIO_REQ_T_OUT:
                    for (uint32_t idx = 0; idx < len; idx++) {
                        uint64_t dst64 = disk_offset + (uint64_t)idx;
                        if (dst64 >= (uint64_t)m->disk_size) break;
                        m->disk[(uint32_t)dst64] = virtio_mem_read_u8(m, data_addr + (uint64_t)idx);
                    }
                    return 1;
                default:
                    return 0;
                }
            }

            static void virtio_push_used(MemState* m, uint16_t head_idx, uint32_t used_len) {
                if (m->virtio_queue_num == 0u) return;
                uint64_t queue_device = virtio_queue_device_addr(m);
                if (queue_device == 0ull) return;
                uint16_t used_idx = virtio_mem_read_u16(m, queue_device + 2ull);
                uint64_t slot = (uint64_t)(used_idx % m->virtio_queue_num);
                uint64_t elem_addr = queue_device + 4ull + (slot * 8ull);
                virtio_mem_write_u32(m, elem_addr, (uint32_t)head_idx);
                virtio_mem_write_u32(m, elem_addr + 4ull, used_len);
                virtio_mem_write_u16(m, queue_device + 2ull, (uint16_t)(used_idx + 1u));
            }

            static void virtio_process_one_request(MemState* m, uint16_t head_idx) {
                struct VirtioDesc d0, d1, d2;
                if (!virtio_read_desc(m, head_idx, &d0)) return;
                if ((d0.flags & VIRTIO_DESC_F_NEXT) == 0u) return;
                if (!virtio_read_desc(m, d0.next, &d1)) return;
                if ((d1.flags & VIRTIO_DESC_F_NEXT) == 0u) return;
                if (!virtio_read_desc(m, d1.next, &d2)) return;

                uint64_t req_addr = d0.addr;
                uint32_t req_type = virtio_mem_read_u32(m, req_addr);
                uint64_t sector = virtio_mem_read_u64(m, req_addr + 8ull);
                int success = virtio_transfer_data(m, req_type, sector, d1.addr, d1.len);
                virtio_mem_write_u8(m, d2.addr, success ? 0u : 1u);
                virtio_push_used(m, head_idx, success ? d1.len : 0u);
                m->virtio_interrupt_status |= VIRTIO_INTERRUPT_USED_BUFFER;
            }

            static int virtio_process_available(MemState* m) {
                if (m->virtio_queue_num == 0u) return 0;
                uint64_t queue_driver = virtio_queue_driver_addr(m);
                if (queue_driver == 0ull) return 0;

                int processed_any = 0;
                uint32_t guard = 0u;
                uint32_t max_guard = (uint32_t)m->virtio_queue_num * 4u;
                if (max_guard < 16u) max_guard = 16u;

                uint16_t avail_idx = virtio_mem_read_u16(m, queue_driver + 2ull);
                while (m->virtio_last_avail_idx != avail_idx && guard < max_guard) {
                    uint64_t ring_slot = (uint64_t)(m->virtio_last_avail_idx % m->virtio_queue_num);
                    uint16_t head_idx = virtio_mem_read_u16(m, queue_driver + 4ull + (ring_slot * 2ull));
                    virtio_process_one_request(m, head_idx);
                    m->virtio_last_avail_idx = (uint16_t)(m->virtio_last_avail_idx + 1u);
                    processed_any = 1;
                    guard++;
                    avail_idx = virtio_mem_read_u16(m, queue_driver + 2ull);
                }
                return processed_any;
            }

            static void virtio_service_queues(MemState* m) {
                if (!m->virtio_notify_pending) {
                    m->virtio_irq = virtio_irq_asserted(m);
                    return;
                }
                m->virtio_notify_pending = 0;
                if (!virtio_queue_operational(m)) {
                    m->virtio_irq = virtio_irq_asserted(m);
                    return;
                }
                virtio_process_available(m);
                m->virtio_irq = virtio_irq_asserted(m);
            }

            static inline void plic_clear_pending(MemState* m, uint32_t id) {
                if (id == 1u) m->plic_pending1 = 0u;
                if (id == 10u) m->plic_pending10 = 0u;
            }

            static inline uint32_t plic_select_claim_id(MemState* m) {
                if (m->plic_in_service_id != 0u) return 0u;
                int source1 = m->plic_pending1 == 1u && m->plic_enable1 == 1u && m->plic_priority1 > m->plic_threshold;
                int source10 = m->plic_pending10 == 1u && m->plic_enable10 == 1u && m->plic_priority10 > m->plic_threshold;
                if (!source1 && !source10) return 0u;
                if (source1 && !source10) return 1u;
                if (source10 && !source1) return 10u;
                return (m->plic_priority10 > m->plic_priority1) ? 10u : 1u;
            }

            static inline void plic_latch_sources(MemState* m, uint8_t source1, uint8_t source10) {
                // Match IR runner PLIC gateway behavior: edge-gated pending latch
                // with one outstanding notification per source while in-service.
                if (source1 && !m->plic_prev_source1 && m->plic_pending1 == 0u && m->plic_in_service_id != 1u) {
                    m->plic_pending1 = 1u;
                }
                if (source10 && !m->plic_prev_source10 && m->plic_pending10 == 0u && m->plic_in_service_id != 10u) {
                    m->plic_pending10 = 1u;
                }
                m->plic_prev_source1 = source1 ? 1u : 0u;
                m->plic_prev_source10 = source10 ? 1u : 0u;
            }

            static inline void plic_refresh_irq_external(MemState* m) {
                m->irq_external = plic_select_claim_id(m) != 0u ? 1u : 0u;
            }

            static uint32_t handle_plic_read(MemState* m, uint32_t addr, uint32_t funct3) {
                if (funct3 != FUNCT3_WORD) return 0u;
                uint32_t claim_id = plic_select_claim_id(m);
                switch (addr) {
                case PLIC_PRIORITY_1: return m->plic_priority1;
                case PLIC_PRIORITY_10: return m->plic_priority10;
                case PLIC_PENDING: return (m->plic_pending1 << 1) | (m->plic_pending10 << 10);
                case PLIC_ENABLE:
                case PLIC_SENABLE:
                    return (m->plic_enable1 << 1) | (m->plic_enable10 << 10);
                case PLIC_THRESHOLD:
                case PLIC_STHRESHOLD:
                    return m->plic_threshold;
                case PLIC_CLAIM_COMPLETE:
                case PLIC_SCLAIM_COMPLETE:
                    return claim_id;
                default:
                    return 0u;
                }
            }

            static void handle_plic_read_commit(MemState* m, uint32_t addr, uint32_t funct3) {
                if (funct3 != FUNCT3_WORD) return;
                if (addr != PLIC_CLAIM_COMPLETE && addr != PLIC_SCLAIM_COMPLETE) return;

                uint32_t claim_id = plic_select_claim_id(m);
                if (claim_id != 0u) {
                    plic_clear_pending(m, claim_id);
                    m->plic_in_service_id = claim_id;
                    if (claim_id == 1u) {
                        m->virtio_interrupt_status &= ~VIRTIO_INTERRUPT_USED_BUFFER;
                        m->virtio_irq = virtio_irq_asserted(m);
                    }
                }
                plic_refresh_irq_external(m);
            }

            static void handle_plic_write(MemState* m, uint32_t addr, uint32_t value, uint32_t funct3) {
                if (funct3 != FUNCT3_WORD) return;
                switch (addr) {
                case PLIC_PRIORITY_1:
                    m->plic_priority1 = value & 0x7u;
                    break;
                case PLIC_PRIORITY_10:
                    m->plic_priority10 = value & 0x7u;
                    break;
                case PLIC_ENABLE:
                case PLIC_SENABLE:
                    m->plic_enable1 = (value >> 1) & 0x1u;
                    m->plic_enable10 = (value >> 10) & 0x1u;
                    break;
                case PLIC_THRESHOLD:
                case PLIC_STHRESHOLD:
                    m->plic_threshold = value & 0x7u;
                    break;
                case PLIC_CLAIM_COMPLETE:
                case PLIC_SCLAIM_COMPLETE: {
                    uint32_t complete_id = value & 0x3FFu;
                    if (complete_id == m->plic_in_service_id) {
                        m->plic_in_service_id = 0u;
                        if (complete_id == 1u) m->plic_prev_source1 = 0u;
                        if (complete_id == 10u) m->plic_prev_source10 = 0u;
                    }
                    break;
                }
                default:
                    break;
                }
                plic_refresh_irq_external(m);
            }

            static uint32_t handle_virtio_read(MemState* m, uint32_t addr, uint32_t funct3) {
                if (funct3 != FUNCT3_WORD) return 0u;
                m->virtio_irq = virtio_irq_asserted(m);
                return virtio_read_register(m, addr);
            }

            static void handle_virtio_write(MemState* m, uint32_t addr, uint32_t value, uint32_t funct3) {
                if (funct3 != FUNCT3_WORD) return;
                virtio_write_register(m, addr, value);
                m->virtio_irq = virtio_irq_asserted(m);
            }

            static uint32_t handle_mmio_read(MemState* m, uint32_t addr, uint32_t funct3) {
                if (is_clint(addr)) return handle_clint_read(m, addr);
                if (is_uart(addr)) return handle_uart_read(m, addr, funct3);
                if (is_plic(addr)) return handle_plic_read(m, addr, funct3);
                if (is_virtio(addr)) return handle_virtio_read(m, addr, funct3);
                return 0u;
            }

            static void handle_mmio_write(MemState* m, uint32_t addr, uint32_t val, uint32_t funct3) {
                if (is_clint(addr)) {
                    handle_clint_write(m, addr, val);
                    return;
                }
                if (is_uart(addr)) {
                    handle_uart_write(m, addr, val, funct3);
                    return;
                }
                if (is_plic(addr)) {
                    handle_plic_write(m, addr, val, funct3);
                    return;
                }
                if (is_virtio(addr)) {
                    handle_virtio_write(m, addr, val, funct3);
                }
            }
          CODE
        end

        # Batched cycle execution loop. Must appear AFTER DUT_* macros are defined.
        def riscv_sim_run_cycles_impl
          <<~'CODE'
            static void run_cycles_impl(void* raw_ctx, MemState* m, uint32_t n_cycles) {
                for (uint32_t i = 0; i < n_cycles; i++) {
                    uart_feed_rx_slot(m);
                    virtio_service_queues(m);
                    plic_latch_sources(m, m->virtio_irq, uart_irq_pending(m) ? 1 : 0);
                    plic_refresh_irq_external(m);

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
                    uint32_t write_addr = data_addr;
                    uint32_t write_wdata = data_wdata;
                    uint32_t write_we = data_we;
                    uint32_t write_funct3 = data_funct3;
                    uint32_t read_addr = data_addr;
                    uint32_t read_re = data_re;
                    uint32_t read_funct3 = data_funct3;

                    uint32_t rdata = 0;
                    if (is_mmio(data_addr)) {
                        if (data_re) rdata = handle_mmio_read(m, data_addr, data_funct3);
                    } else {
                        if (data_re) rdata = read_mem_funct3(m->data_mem, m->mem_mask, data_addr, data_funct3);
                    }

                    DUT_DATA_RDATA(raw_ctx) = rdata;
                    DUT_IRQ_SOFTWARE(raw_ctx) = m->irq_software;
                    DUT_IRQ_TIMER(raw_ctx) = m->irq_timer;
                    DUT_IRQ_EXTERNAL(raw_ctx) = m->irq_external;
                    DUT_EVAL(raw_ctx);

                    // --- Phase 2: CLK high (rising edge) ---
                    DUT_CLK(raw_ctx) = 1;
                    if (write_we) {
                        if (is_mmio(write_addr)) {
                            handle_mmio_write(m, write_addr, write_wdata, write_funct3);
                            virtio_service_queues(m);
                            plic_latch_sources(m, m->virtio_irq, uart_irq_pending(m) ? 1 : 0);
                            plic_refresh_irq_external(m);
                        } else {
                            write_mem_funct3(m->data_mem, m->mem_mask, write_addr, write_wdata, write_funct3);
                            write_mem_funct3(m->inst_mem, m->mem_mask, write_addr, write_wdata, write_funct3);
                        }
                    }
                    if (read_re) {
                        if (is_uart(read_addr)) {
                            handle_uart_read_commit(m, read_addr, read_funct3);
                        } else if (is_plic(read_addr)) {
                            handle_plic_read_commit(m, read_addr, read_funct3);
                        }
                    }
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
                    data_funct3 = DUT_DATA_FUNCT3(raw_ctx);
                    if (is_mmio(data_addr)) {
                        rdata = data_re ? handle_mmio_read(m, data_addr, data_funct3) : 0;
                    } else {
                        rdata = data_re ? read_mem_funct3(m->data_mem, m->mem_mask, data_addr, data_funct3) : 0;
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
                    virtio_service_queues(m);
                    plic_latch_sources(m, m->virtio_irq, uart_irq_pending(m) ? 1 : 0);
                    plic_refresh_irq_external(m);
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
        BUILD_BASE = File.expand_path('../../.hdl_build', __dir__)
        alias_method :initialize_backend_runner, :initialize

        def initialize(mem_size: Memory::DEFAULT_SIZE, jit: false)
          initialize_backend_runner(backend_sym: :arcilator, simulator_type_sym: :hdl_arcilator, mem_size: mem_size, jit: jit)
        end

        private :initialize_backend_runner

        private

        def check_tools_available!
          %w[arcilator circt-opt].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end

          %w[clang++ llvm-link].each do |tool|
            raise LoadError, "#{tool} not found in PATH" unless command_available?(tool)
          end
          raise LoadError, 'Neither clang nor llc found in PATH' unless command_available?('clang') || command_available?('llc')
          raise LoadError, 'lli not found in PATH' if jit? && !command_available?('lli')
        end

        def build_dir
          @build_dir ||= File.join(BUILD_BASE, jit? ? 'arcilator_jit' : 'arcilator')
        end

        def build_simulation
          FileUtils.mkdir_p(build_dir)

          mlir_file = File.join(build_dir, 'riscv_cpu_hw.mlir')
          ll_file = File.join(build_dir, 'riscv_cpu_arc.ll')
          state_file = File.join(build_dir, 'riscv_cpu_state.json')
          obj_file = File.join(build_dir, 'riscv_cpu_arc.o')
          wrapper_file = File.join(build_dir, 'arc_wrapper.cpp')
          wrapper_ll_file = File.join(build_dir, 'arc_wrapper.ll')
          runtime_bc_file = File.join(build_dir, 'riscv_cpu_arc_runtime.bc')
          jit_wrapper_ll_file = File.join(build_dir, 'arc_jit_main.ll')
          jit_bc_file = File.join(build_dir, 'riscv_cpu_arc_jit.bc')
          lib_file = shared_lib_path
          arc_dir = File.join(build_dir, 'arc')

          cpu_source = File.expand_path('../../hdl/cpu.rb', __dir__)
          mlir_gen = File.expand_path('../../../../lib/rhdl/codegen/circt/mlir.rb', __dir__)
          tooling_file = File.expand_path('../../../../lib/rhdl/codegen/circt/tooling.rb', __dir__)
          export_deps = [__FILE__, cpu_source, mlir_gen, tooling_file].select { |p| File.exist?(p) }

          primary_output = jit? ? jit_bc_file : lib_file
          needs_rebuild = !File.exist?(primary_output) ||
                          export_deps.any? { |p| File.mtime(p) > File.mtime(primary_output) }

          if needs_rebuild
            puts '  Exporting RISC-V CPU to CIRCT MLIR...'
            export_mlir(mlir_file)

            puts '  Preparing ARC MLIR...'
            prepared = RHDL::Codegen::CIRCT::Tooling.prepare_arc_mlir_from_circt_mlir(
              mlir_path: mlir_file,
              work_dir: arc_dir,
              base_name: 'riscv_cpu',
              top: 'riscv_cpu'
            )
            raise LoadError, "ARC preparation failed for RISC-V CPU: #{prepared.dig(:arc, :stderr)}" unless prepared[:success]
            arcilator_mlir_path = RHDL::Codegen::CIRCT::Tooling.finalize_arc_mlir_for_arcilator!(
              arc_mlir_path: prepared.fetch(:arc_mlir_path),
              check_paths: [
                prepared[:normalized_llhd_mlir_path],
                prepared[:hwseq_mlir_path],
                prepared[:flattened_hwseq_mlir_path],
                prepared[:flattened_cleaned_hwseq_mlir_path],
                prepared[:arc_mlir_path]
              ]
            )

            puts '  Compiling with arcilator...'
            compile_arcilator(arcilator_mlir_path, ll_file, state_file)

            puts '  Building shared library...'
            write_arcilator_wrapper(wrapper_file, state_file)
            FileUtils.rm_f(wrapper_ll_file)
            FileUtils.rm_f(runtime_bc_file)
            compile_wrapper_llvm_ir(wrapper_path: wrapper_file, wrapper_ll_path: wrapper_ll_file, jit_main: false)
            link_jit_bitcode(ll_path: ll_file, wrapper_ll_path: wrapper_ll_file, jit_bc_path: runtime_bc_file)
            if jit?
              FileUtils.rm_f(jit_wrapper_ll_file)
              FileUtils.rm_f(jit_bc_file)
              compile_wrapper_llvm_ir(wrapper_path: wrapper_file, wrapper_ll_path: jit_wrapper_ll_file, jit_main: true)
              link_jit_bitcode(ll_path: ll_file, wrapper_ll_path: jit_wrapper_ll_file, jit_bc_path: jit_bc_file)
            else
              compile_llvm_ir_object(ll_path: runtime_bc_file, obj_path: obj_file)
              link_arcilator(obj_file, lib_file)
            end
          end

          @lib_path = lib_file
          @jit_bitcode_path = jit_bc_file
        end

        def shared_lib_path
          File.join(build_dir, 'libriscv_arc_sim.so')
        end

        def export_mlir(mlir_file)
          flat_nodes = CPU.to_flat_circt_nodes(top_name: 'riscv_cpu')
          mlir = RHDL::Codegen::CIRCT::MLIR.generate(flat_nodes)
          File.write(mlir_file, mlir)
        end

        def compile_arcilator(mlir_file, ll_file, state_file)
          log = log_path
          FileUtils.rm_f(state_file)
          FileUtils.rm_f(ll_file)
          cmd = RHDL::Codegen::CIRCT::Tooling.arcilator_command(
            mlir_path: mlir_file,
            state_file: state_file,
            out_path: ll_file
          )
          run_or_raise(cmd, 'arcilator', log)
        end

        def run_or_raise(cmd, step_name, log_path)
          if cmd.is_a?(Array)
            return if system(*cmd, out: [log_path, 'a'], err: [log_path, 'a'])
          else
            return if system(cmd)
          end

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

        def link_arcilator(obj_file, lib_file)
          cxx = if darwin_host? && command_available?('clang++')
                  'clang++'
                elsif command_available?('g++')
                  'g++'
                else
                  'c++'
                end

          link_cmd = String.new("#{cxx} -shared -fPIC -O2")
          if (arch = build_target_arch)
            link_cmd << " -arch #{arch}"
          end
          link_cmd << " -o #{lib_file} #{obj_file}"

          system(link_cmd) or raise LoadError, "#{cxx} link failed"
        end

        def darwin_host?(host_os: RbConfig::CONFIG['host_os'])
          host_os.to_s.downcase.include?('darwin')
        end

        def build_target_arch(host_os: RbConfig::CONFIG['host_os'], host_cpu: RbConfig::CONFIG['host_cpu'])
          return nil unless darwin_host?(host_os: host_os)

          cpu = host_cpu.to_s.downcase
          return 'arm64' if cpu.include?('arm64') || cpu.include?('aarch64')
          return 'x86_64' if cpu.include?('x86_64') || cpu.include?('amd64')

          nil
        end

        def log_path
          File.join(build_dir, 'arcilator.log')
        end

        def compile_wrapper_llvm_ir(wrapper_path:, wrapper_ll_path:, jit_main: false)
          cmd = ['clang++', '-std=c++17', '-O0', '-S', '-emit-llvm']
          cmd << '-DARCI_JIT_MAIN' if jit_main
          cmd += [wrapper_path, '-o', wrapper_ll_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, "#{stdout}#{stderr}", mode: 'a')
          raise "RISC-V Arcilator wrapper LLVM IR compilation failed:\n#{stdout}\n#{stderr}" unless status.success?
        end

        def link_jit_bitcode(ll_path:, wrapper_ll_path:, jit_bc_path:)
          cmd = ['llvm-link', ll_path, wrapper_ll_path, '-o', jit_bc_path]
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, "#{stdout}#{stderr}", mode: 'a')
          raise "RISC-V Arcilator bitcode link failed:\n#{stdout}\n#{stderr}" unless status.success?
        end

        def compile_llvm_ir_object(ll_path:, obj_path:)
          cmd = if command_available?('llc')
                  ['llc', '-filetype=obj', '-O0', '-relocation-model=pic', ll_path, '-o', obj_path]
                else
                  ['clang', '-c', '-O0', '-fPIC', ll_path, '-o', obj_path]
                end
          stdout, stderr, status = Open3.capture3(*cmd)
          File.write(log_path, "#{stdout}#{stderr}", mode: 'a')
          raise "RISC-V Arcilator object compilation failed:\n#{stdout}\n#{stderr}" unless status.success?
        end

        def write_arcilator_wrapper(wrapper_path, state_file_path)
          state = JSON.parse(File.read(state_file_path))
          mod = state.find { |entry| entry['name'].to_s == 'riscv_cpu' } || state[0]

          offsets = {}
          mod['states'].each { |s| offsets[s['name']] = s['offset'] }

          signal_defines = []
          signal_defines << "#define STATE_SIZE #{mod['numStateBytes']}"
          offsets.each { |name, offset| signal_defines << "#define OFF_#{name.to_s.upcase.gsub(/[^A-Z0-9]+/, '_')} #{offset}" }

          wrapper = <<~CPP
            #include <cstdint>
            #include <cstring>
            #include <cstdlib>
            #include <stdio.h>

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

            static unsigned int parse_mem_size_config(const char* json, size_t json_len, unsigned int default_mem_size) {
                if (!json || json_len == 0) return default_mem_size;
                const char* key = "\\\"mem_size\\\"";
                const char* match = std::strstr(json, key);
                if (!match) return default_mem_size;
                match += std::strlen(key);
                while (*match == ' ' || *match == '\\t' || *match == '\\n' || *match == '\\r' || *match == ':') match++;
                char* end_ptr = nullptr;
                unsigned long value = std::strtoul(match, &end_ptr, 10);
                if (end_ptr == match || value == 0ul) return default_mem_size;
                return static_cast<unsigned int>(value & 0xFFFF'FFFFu);
            }

            enum {
                SIM_CAP_SIGNAL_INDEX = 1u << 0,
                SIM_CAP_FORCED_CLOCK = 1u << 1,
                SIM_CAP_TRACE = 1u << 2,
                SIM_CAP_TRACE_STREAMING = 1u << 3,
                SIM_CAP_COMPILE = 1u << 4,
                SIM_CAP_GENERATED_CODE = 1u << 5,
                SIM_CAP_RUNNER = 1u << 6
            };

            enum {
                SIM_SIGNAL_HAS = 0u,
                SIM_SIGNAL_GET_INDEX = 1u,
                SIM_SIGNAL_PEEK = 2u,
                SIM_SIGNAL_POKE = 3u,
                SIM_SIGNAL_PEEK_INDEX = 4u,
                SIM_SIGNAL_POKE_INDEX = 5u
            };

            enum {
                SIM_EXEC_EVALUATE = 0u,
                SIM_EXEC_TICK = 1u,
                SIM_EXEC_TICK_FORCED = 2u,
                SIM_EXEC_SET_PREV_CLOCK = 3u,
                SIM_EXEC_GET_CLOCK_LIST_IDX = 4u,
                SIM_EXEC_RESET = 5u,
                SIM_EXEC_RUN_TICKS = 6u,
                SIM_EXEC_SIGNAL_COUNT = 7u,
                SIM_EXEC_REG_COUNT = 8u,
                SIM_EXEC_COMPILE = 9u,
                SIM_EXEC_IS_COMPILED = 10u
            };

            enum {
                SIM_TRACE_START = 0u,
                SIM_TRACE_START_STREAMING = 1u,
                SIM_TRACE_STOP = 2u,
                SIM_TRACE_ENABLED = 3u,
                SIM_TRACE_CAPTURE = 4u,
                SIM_TRACE_ADD_SIGNAL = 5u,
                SIM_TRACE_ADD_SIGNALS_MATCHING = 6u,
                SIM_TRACE_ALL_SIGNALS = 7u,
                SIM_TRACE_CLEAR_SIGNALS = 8u,
                SIM_TRACE_CLEAR = 9u,
                SIM_TRACE_CHANGE_COUNT = 10u,
                SIM_TRACE_SIGNAL_COUNT = 11u,
                SIM_TRACE_SET_TIMESCALE = 12u,
                SIM_TRACE_SET_MODULE_NAME = 13u,
                SIM_TRACE_SAVE_VCD = 14u
            };

            enum {
                SIM_BLOB_INPUT_NAMES = 0u,
                SIM_BLOB_OUTPUT_NAMES = 1u,
                SIM_BLOB_TRACE_TO_VCD = 2u,
                SIM_BLOB_TRACE_TAKE_LIVE_VCD = 3u,
                SIM_BLOB_GENERATED_CODE = 4u,
                SIM_BLOB_SPARC64_WISHBONE_TRACE = 5u,
                SIM_BLOB_SPARC64_UNMAPPED_ACCESSES = 6u
            };

            enum {
                RUNNER_KIND_NONE = 0,
                RUNNER_KIND_APPLE2 = 1,
                RUNNER_KIND_MOS6502 = 2,
                RUNNER_KIND_GAMEBOY = 3,
                RUNNER_KIND_CPU8BIT = 4,
                RUNNER_KIND_RISCV = 5
            };

            enum {
                RUNNER_MEM_OP_LOAD = 0u,
                RUNNER_MEM_OP_READ = 1u,
                RUNNER_MEM_OP_WRITE = 2u
            };

            enum {
                RUNNER_MEM_SPACE_MAIN = 0u,
                RUNNER_MEM_SPACE_ROM = 1u,
                RUNNER_MEM_SPACE_DISK = 7u,
                RUNNER_MEM_SPACE_UART_TX = 8u,
                RUNNER_MEM_SPACE_UART_RX = 9u
            };

            enum {
                RUNNER_MEM_FLAG_MAPPED = 1u
            };

            enum {
                RUNNER_RUN_MODE_BASIC = 0u
            };

            enum {
                RUNNER_CONTROL_SET_RESET_VECTOR = 0u,
                RUNNER_CONTROL_RESET_SPEAKER_TOGGLES = 1u,
                RUNNER_CONTROL_RESET_LCD = 2u,
                RUNNER_CONTROL_RISCV_SET_IRQS = 3u,
                RUNNER_CONTROL_RISCV_SET_PLIC_SOURCES = 4u,
                RUNNER_CONTROL_RISCV_UART_PUSH_RX = 5u,
                RUNNER_CONTROL_RISCV_CLEAR_UART_TX = 6u
            };

            enum {
                RUNNER_PROBE_KIND = 0u,
                RUNNER_PROBE_IS_MODE = 1u,
                RUNNER_PROBE_SIGNAL = 9u,
                RUNNER_PROBE_RISCV_UART_TX_LEN = 17u
            };

            struct RunnerCaps {
                int kind;
                unsigned int mem_spaces;
                unsigned int control_ops;
                unsigned int probe_ops;
            };

            struct RunnerRunResult {
                int text_dirty;
                int key_cleared;
                unsigned int cycles_run;
                unsigned int speaker_toggles;
                unsigned int frames_completed;
            };

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

            static const unsigned int k_input_signal_count = static_cast<unsigned int>(sizeof(k_input_signal_names) / sizeof(k_input_signal_names[0]));
            static const unsigned int k_output_signal_count = static_cast<unsigned int>(sizeof(k_output_signal_names) / sizeof(k_output_signal_names[0]));

            static inline void write_out_u32(unsigned int* out, unsigned int value) {
                if (out) *out = value;
            }

            static inline void write_out_ulong(unsigned long* out, unsigned long value) {
                if (out) *out = value;
            }

            static inline size_t total_signal_count() {
                return static_cast<size_t>(k_input_signal_count + k_output_signal_count);
            }

            static inline const char* signal_name_from_index(unsigned int idx) {
                if (idx < k_input_signal_count) return k_input_signal_names[idx];
                idx -= k_input_signal_count;
                return idx < k_output_signal_count ? k_output_signal_names[idx] : nullptr;
            }

            static inline int signal_index_from_name(const char* name) {
                if (!name) return -1;
                for (unsigned int i = 0; i < k_input_signal_count; i++) {
                    if (!std::strcmp(name, k_input_signal_names[i])) return static_cast<int>(i);
                }
                for (unsigned int i = 0; i < k_output_signal_count; i++) {
                    if (!std::strcmp(name, k_output_signal_names[i])) {
                        return static_cast<int>(k_input_signal_count + i);
                    }
                }
                return -1;
            }

            static inline size_t copy_blob(unsigned char* out_ptr, size_t out_len, const char* text) {
                const size_t required = text ? std::strlen(text) : 0u;
                if (out_ptr && out_len && required) {
                    const size_t copy_len = required < out_len ? required : out_len;
                    std::memcpy(out_ptr, text, copy_len);
                }
                return required;
            }

            static inline unsigned int runner_main_resolve_offset(unsigned int offset, unsigned int flags) {
                if ((flags & RUNNER_MEM_FLAG_MAPPED) == 0u) {
                    return offset;
                }
                if (offset >= 0xC0000000u) {
                    return offset - 0x40000000u;
                }
                return offset;
            }

            static inline size_t read_mem_bytes(SimContext* ctx, int mem_type, unsigned int offset, unsigned char* out, size_t len) {
                const uint8_t* mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
                if (!mem || !out) return 0u;
                for (size_t i = 0; i < len; i++) {
                    out[i] = mem[(offset + static_cast<unsigned int>(i)) & ctx->mem.mem_mask];
                }
                return len;
            }

            static inline size_t read_uart_tx_bytes(SimContext* ctx, unsigned int offset, unsigned char* out, size_t len) {
                if (!out || offset >= ctx->mem.uart_tx_len) return 0u;
                const size_t available = ctx->mem.uart_tx_len - offset;
                const size_t copy_len = available < len ? available : len;
                std::memcpy(out, ctx->mem.uart_tx_bytes + offset, copy_len);
                return copy_len;
            }

            extern "C" {

            void* sim_create(const char* json, size_t json_len, unsigned int sub_cycles, char** err_out) {
                (void)sub_cycles;
                if (err_out) *err_out = nullptr;
                SimContext* ctx = new SimContext();
                memset(ctx->state, 0, sizeof(ctx->state));
                mem_init(&ctx->mem, parse_mem_size_config(json, json_len, #{@mem_size}));
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

            void sim_free_error(char* error) {
                if (error) {
                    std::free(error);
                }
            }

            void sim_free_string(char* str) {
                if (str) {
                    std::free(str);
                }
            }

            void* sim_wasm_alloc(size_t size) {
                return std::malloc(size > 0 ? size : 1);
            }

            void sim_wasm_dealloc(void* ptr, size_t size) {
                (void)size;
                std::free(ptr);
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

            unsigned int sim_read_mem_word(void* sim, int mem_type, unsigned int addr) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                const uint8_t* mem = mem_type == MEM_TYPE_INST ? ctx->mem.inst_mem : ctx->mem.data_mem;
                return read_word_le(mem, ctx->mem.mem_mask, addr);
            }

            void sim_run_cycles(void* sim, unsigned int n_cycles) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                run_cycles_impl(ctx, &ctx->mem, n_cycles);
            }

            void sim_uart_rx_push(void* sim, const unsigned char* data, unsigned int len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                uart_rx_queue_push_bytes(&ctx->mem, data, len);
            }

            unsigned int sim_uart_tx_len(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return uart_tx_len(&ctx->mem);
            }

            unsigned int sim_uart_tx_copy(void* sim, unsigned char* out, unsigned int max_len) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return uart_tx_copy(&ctx->mem, out, max_len);
            }

            void sim_uart_tx_clear(void* sim) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                uart_tx_clear(&ctx->mem);
            }

            unsigned int sim_disk_load(void* sim, const unsigned char* data, unsigned int size, unsigned int base_addr) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return (unsigned int)disk_load(&ctx->mem, data, size, base_addr);
            }

            unsigned int sim_disk_read_byte(void* sim, unsigned int offset) {
                SimContext* ctx = static_cast<SimContext*>(sim);
                return (unsigned int)disk_read_byte(&ctx->mem, offset);
            }

            int sim_get_caps(void* sim, unsigned int* caps_out) {
                (void)sim;
                write_out_u32(caps_out, SIM_CAP_SIGNAL_INDEX | SIM_CAP_RUNNER);
                return 1;
            }

            int sim_signal(void* sim, unsigned int op, const char* name, unsigned int idx, unsigned long value, unsigned long* out_value) {
                int resolved_idx = -1;
                const char* resolved_name = nullptr;
                if (name && name[0]) {
                    resolved_idx = signal_index_from_name(name);
                    resolved_name = name;
                } else {
                    resolved_name = signal_name_from_index(idx);
                    resolved_idx = resolved_name ? static_cast<int>(idx) : -1;
                }

                switch (op) {
                case SIM_SIGNAL_HAS:
                    write_out_ulong(out_value, resolved_idx >= 0 ? 1ul : 0ul);
                    return resolved_idx >= 0 ? 1 : 0;
                case SIM_SIGNAL_GET_INDEX:
                    if (resolved_idx < 0) {
                        write_out_ulong(out_value, 0ul);
                        return 0;
                    }
                    write_out_ulong(out_value, static_cast<unsigned long>(resolved_idx));
                    return 1;
                case SIM_SIGNAL_PEEK:
                case SIM_SIGNAL_PEEK_INDEX:
                    if (resolved_idx < 0 || !resolved_name) {
                        write_out_ulong(out_value, 0ul);
                        return 0;
                    }
                    write_out_ulong(out_value, static_cast<unsigned long>(sim_peek(sim, resolved_name)));
                    return 1;
                case SIM_SIGNAL_POKE:
                case SIM_SIGNAL_POKE_INDEX:
                    if (resolved_idx < 0 || !resolved_name) {
                        write_out_ulong(out_value, 0ul);
                        return 0;
                    }
                    sim_poke(sim, resolved_name, static_cast<unsigned int>(value));
                    write_out_ulong(out_value, 1ul);
                    return 1;
                default:
                    write_out_ulong(out_value, 0ul);
                    return 0;
                }
            }

            int sim_exec(void* sim, unsigned int op, unsigned long arg0, unsigned long arg1, unsigned long* out_value, char** err_out) {
                (void)arg1;
                if (err_out) *err_out = nullptr;
                switch (op) {
                case SIM_EXEC_EVALUATE:
                    sim_eval(sim);
                    write_out_ulong(out_value, 0ul);
                    return 1;
                case SIM_EXEC_TICK:
                    sim_run_cycles(sim, 1u);
                    write_out_ulong(out_value, 0ul);
                    return 1;
                case SIM_EXEC_RESET:
                    sim_reset(sim);
                    write_out_ulong(out_value, 0ul);
                    return 1;
                case SIM_EXEC_RUN_TICKS:
                    sim_run_cycles(sim, static_cast<unsigned int>(arg0));
                    write_out_ulong(out_value, 0ul);
                    return 1;
                case SIM_EXEC_SIGNAL_COUNT:
                    write_out_ulong(out_value, static_cast<unsigned long>(total_signal_count()));
                    return 1;
                case SIM_EXEC_REG_COUNT:
                    write_out_ulong(out_value, 0ul);
                    return 1;
                default:
                    write_out_ulong(out_value, 0ul);
                    return 0;
                }
            }

            int sim_trace(void* sim, unsigned int op, const char* str_arg, unsigned long* out_value) {
                (void)sim;
                (void)str_arg;
                write_out_ulong(out_value, 0ul);
                return (op == SIM_TRACE_ENABLED) ? 1 : 0;
            }

            size_t sim_blob(void* sim, unsigned int op, unsigned char* out_ptr, size_t out_len) {
                (void)sim;
                switch (op) {
                case SIM_BLOB_INPUT_NAMES:
                    return copy_blob(out_ptr, out_len, k_input_names_csv);
                case SIM_BLOB_OUTPUT_NAMES:
                    return copy_blob(out_ptr, out_len, k_output_names_csv);
                default:
                    return 0u;
                }
            }

            int runner_get_caps(void* sim, RunnerCaps* caps_out) {
                (void)sim;
                if (!caps_out) return 0;
                caps_out->kind = RUNNER_KIND_RISCV;
                caps_out->mem_spaces =
                    (1u << RUNNER_MEM_SPACE_MAIN) |
                    (1u << RUNNER_MEM_SPACE_ROM) |
                    (1u << RUNNER_MEM_SPACE_DISK) |
                    (1u << RUNNER_MEM_SPACE_UART_TX) |
                    (1u << RUNNER_MEM_SPACE_UART_RX);
                caps_out->control_ops =
                    (1u << RUNNER_CONTROL_SET_RESET_VECTOR) |
                    (1u << RUNNER_CONTROL_RISCV_CLEAR_UART_TX);
                caps_out->probe_ops =
                    (1u << RUNNER_PROBE_KIND) |
                    (1u << RUNNER_PROBE_IS_MODE) |
                    (1u << RUNNER_PROBE_SIGNAL) |
                    (1u << RUNNER_PROBE_RISCV_UART_TX_LEN);
                return 1;
            }

            size_t runner_mem(void* sim, unsigned int op, unsigned int space, size_t offset, unsigned char* ptr, size_t len, unsigned int flags) {
                if (!sim || !ptr || len == 0u) return 0u;
                if (op == RUNNER_MEM_OP_LOAD) {
                    if (space == RUNNER_MEM_SPACE_MAIN) {
                        sim_load_mem(sim, MEM_TYPE_DATA, ptr, static_cast<unsigned int>(len), static_cast<unsigned int>(offset));
                        return len;
                    }
                    if (space == RUNNER_MEM_SPACE_ROM) {
                        sim_load_mem(sim, MEM_TYPE_INST, ptr, static_cast<unsigned int>(len), static_cast<unsigned int>(offset));
                        return len;
                    }
                    if (space == RUNNER_MEM_SPACE_DISK) {
                        return static_cast<size_t>(sim_disk_load(sim, ptr, static_cast<unsigned int>(len), static_cast<unsigned int>(offset)));
                    }
                    return 0u;
                }
                if (op == RUNNER_MEM_OP_READ) {
                    SimContext* ctx = static_cast<SimContext*>(sim);
                    if (space == RUNNER_MEM_SPACE_MAIN) {
                        return read_mem_bytes(ctx, MEM_TYPE_DATA, runner_main_resolve_offset(static_cast<unsigned int>(offset), flags), ptr, len);
                    }
                    if (space == RUNNER_MEM_SPACE_ROM) {
                        return read_mem_bytes(ctx, MEM_TYPE_INST, static_cast<unsigned int>(offset), ptr, len);
                    }
                    if (space == RUNNER_MEM_SPACE_UART_TX) {
                        return read_uart_tx_bytes(ctx, static_cast<unsigned int>(offset), ptr, len);
                    }
                    if (space == RUNNER_MEM_SPACE_DISK) {
                        size_t copied = 0u;
                        for (; copied < len; copied++) {
                            ptr[copied] = static_cast<unsigned char>(sim_disk_read_byte(sim, static_cast<unsigned int>(offset + copied)) & 0xFFu);
                        }
                        return copied;
                    }
                    return 0u;
                }
                if (op == RUNNER_MEM_OP_WRITE) {
                    if (space == RUNNER_MEM_SPACE_UART_RX) {
                        sim_uart_rx_push(sim, ptr, static_cast<unsigned int>(len));
                        return len;
                    }
                    if (space == RUNNER_MEM_SPACE_MAIN) {
                        sim_load_mem(sim, MEM_TYPE_DATA, ptr, static_cast<unsigned int>(len), runner_main_resolve_offset(static_cast<unsigned int>(offset), flags));
                        return len;
                    }
                    return 0u;
                }
                return 0u;
            }

            int runner_run(void* sim, unsigned int cycles, unsigned char key_data, int key_ready, unsigned int mode, RunnerRunResult* result_out) {
                (void)mode;
                if (!sim) return 0;
                if (key_ready) {
                    unsigned char key = static_cast<unsigned char>(key_data & 0xFFu);
                    sim_uart_rx_push(sim, &key, 1u);
                }
                sim_run_cycles(sim, cycles);
                if (result_out) {
                    result_out->text_dirty = 0;
                    result_out->key_cleared = key_ready ? 1 : 0;
                    result_out->cycles_run = cycles;
                    result_out->speaker_toggles = 0u;
                    result_out->frames_completed = 0u;
                }
                return 1;
            }

            int runner_control(void* sim, unsigned int op, unsigned int arg0, unsigned int arg1) {
                (void)arg1;
                if (!sim) return 0;
                if (op == RUNNER_CONTROL_SET_RESET_VECTOR) {
                    sim_write_pc(sim, arg0);
                    return 1;
                }
                if (op == RUNNER_CONTROL_RISCV_CLEAR_UART_TX) {
                    sim_uart_tx_clear(sim);
                    return 1;
                }
                return 0;
            }

            unsigned long long runner_probe(void* sim, unsigned int op, unsigned int arg0) {
                if (!sim) return 0ull;
                if (op == RUNNER_PROBE_KIND) return static_cast<unsigned long long>(RUNNER_KIND_RISCV);
                if (op == RUNNER_PROBE_IS_MODE) return 1ull;
                if (op == RUNNER_PROBE_RISCV_UART_TX_LEN) return static_cast<unsigned long long>(sim_uart_tx_len(sim));
                if (op == RUNNER_PROBE_SIGNAL) {
                    const char* signal_name = signal_name_from_index(arg0);
                    return signal_name ? static_cast<unsigned long long>(sim_peek(sim, signal_name)) : 0ull;
                }
                return 0ull;
            }

            } // extern "C"

            #{riscv_jit_main}
          CPP

          File.write(wrapper_path, wrapper)
        end

        def riscv_jit_main
          <<~'CPP'
            #ifdef ARCI_JIT_MAIN
            static int hex_nibble(char ch) {
                if (ch >= '0' && ch <= '9') return ch - '0';
                if (ch >= 'a' && ch <= 'f') return 10 + (ch - 'a');
                if (ch >= 'A' && ch <= 'F') return 10 + (ch - 'A');
                return -1;
            }

            static bool decode_hex_payload(const char* hex, unsigned char* out, size_t out_cap, size_t* out_len) {
                const size_t hex_len = std::strlen(hex);
                if ((hex_len & 1u) != 0u) return false;
                const size_t byte_len = hex_len / 2u;
                if (byte_len > out_cap) return false;
                std::memset(out, 0, out_cap);
                for (size_t i = 0; i < byte_len; ++i) {
                    const int hi = hex_nibble(hex[i * 2u]);
                    const int lo = hex_nibble(hex[(i * 2u) + 1u]);
                    if (hi < 0 || lo < 0) return false;
                    out[i] = static_cast<unsigned char>((hi << 4) | lo);
                }
                if (out_len) *out_len = byte_len;
                return true;
            }

            static void write_hex_bytes(FILE* out, const unsigned char* bytes, size_t len) {
                static const char* digits = "0123456789abcdef";
                for (size_t i = 0; i < len; ++i) {
                    const unsigned int value = bytes[i];
                    fputc(digits[(value >> 4) & 0xFu], out);
                    fputc(digits[value & 0xFu], out);
                }
            }

            static char* skip_spaces(char* text) {
                while (text && (*text == ' ' || *text == '\t')) ++text;
                return text;
            }

            static bool parse_u32_token(const char* token, unsigned int* out_value) {
                if (!token || !out_value) return false;
                char* end_ptr = nullptr;
                const unsigned long value = std::strtoul(token, &end_ptr, 0);
                if (end_ptr == token) return false;
                while (end_ptr && (*end_ptr == ' ' || *end_ptr == '\t')) ++end_ptr;
                if (end_ptr && *end_ptr != '\0') return false;
                *out_value = static_cast<unsigned int>(value & 0xFFFF'FFFFu);
                return true;
            }

            static bool parse_addr_and_hex(char* args, unsigned int* out_addr, char** out_hex) {
                if (!args || !out_addr || !out_hex) return false;
                char* addr_token = skip_spaces(args);
                if (!addr_token || *addr_token == '\0') return false;
                char* sep = addr_token;
                while (*sep && *sep != ' ' && *sep != '\t') ++sep;
                if (*sep == '\0') return false;
                const char saved = *sep;
                *sep = '\0';
                const bool parsed = parse_u32_token(addr_token, out_addr);
                *sep = saved;
                if (!parsed) return false;
                char* hex = skip_spaces(sep);
                if (!hex || *hex == '\0') return false;
                *out_hex = hex;
                return true;
            }

            static unsigned int jit_read_reg(SimContext* ctx, unsigned int idx) {
                set_u5(ctx->state, OFF_DEBUG_REG_ADDR, static_cast<uint8_t>(idx & 0x1Fu));
                riscv_cpu_eval(ctx->state);
                return get_u32(ctx->state, OFF_DEBUG_REG_DATA);
            }

            int main(int argc, char** argv) {
                (void)argc;
                (void)argv;
                SimContext* ctx = nullptr;

                fprintf(stdout, "READY\n");
                fflush(stdout);

                char* line = nullptr;
                size_t cap = 0u;
                while (getline(&line, &cap, stdin) != -1) {
                    size_t len = std::strlen(line);
                    while (len > 0u && (line[len - 1u] == '\n' || line[len - 1u] == '\r')) {
                        line[--len] = '\0';
                    }

                    if (std::strcmp(line, "QUIT") != 0 && !ctx) {
                        ctx = static_cast<SimContext*>(sim_create(nullptr, 0u, 0u, nullptr));
                        if (!ctx) {
                            fprintf(stdout, "ERR INIT\n");
                            fflush(stdout);
                            continue;
                        }
                    }

                    if (std::strcmp(line, "RESET") == 0) {
                        sim_reset(ctx);
                        fprintf(stdout, "OK\n");
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "LOAD_PROGRAM ", 13) == 0 ||
                        std::strncmp(line, "LOAD_ROM ", 9) == 0 ||
                        std::strncmp(line, "LOAD_MAIN ", 10) == 0 ||
                        std::strncmp(line, "LOAD_DISK ", 10) == 0 ||
                        std::strncmp(line, "UART_RX ", 8) == 0) {
                        char* payload = line;
                        unsigned int base_addr = 0u;
                        char* hex = nullptr;
                        const bool is_program = std::strncmp(line, "LOAD_PROGRAM ", 13) == 0;
                        const bool is_rom = std::strncmp(line, "LOAD_ROM ", 9) == 0;
                        const bool is_main = std::strncmp(line, "LOAD_MAIN ", 10) == 0;
                        const bool is_disk = std::strncmp(line, "LOAD_DISK ", 10) == 0;
                        const bool is_uart_rx = std::strncmp(line, "UART_RX ", 8) == 0;

                        if (is_program) {
                            payload += 13;
                        } else if (is_rom) {
                            payload += 9;
                        } else if (is_main || is_disk) {
                            payload += 10;
                        } else {
                            payload += 8;
                        }

                        if (is_uart_rx) {
                            hex = skip_spaces(payload);
                            if (!hex || *hex == '\0') {
                                fprintf(stdout, "ERR UART_RX\n");
                                fflush(stdout);
                                continue;
                            }
                        } else if (!parse_addr_and_hex(payload, &base_addr, &hex)) {
                            fprintf(stdout, "ERR LOAD\n");
                            fflush(stdout);
                            continue;
                        }

                        const size_t hex_len = std::strlen(hex);
                        const size_t byte_cap = (hex_len / 2u) + 1u;
                        unsigned char* bytes = static_cast<unsigned char*>(std::malloc(byte_cap > 0u ? byte_cap : 1u));
                        size_t payload_len = 0u;
                        const bool decoded = bytes && decode_hex_payload(hex, bytes, byte_cap, &payload_len);
                        if (!decoded) {
                            std::free(bytes);
                            fprintf(stdout, "%s\n", is_uart_rx ? "ERR UART_RX" : "ERR LOAD");
                            fflush(stdout);
                            continue;
                        }

                        if (is_uart_rx) {
                            sim_uart_rx_push(ctx, bytes, static_cast<unsigned int>(payload_len));
                        } else {
                            if (is_program || is_rom) {
                                runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, base_addr, bytes, payload_len, 0u);
                            }
                            if (is_program || is_main) {
                                runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_MAIN, base_addr, bytes, payload_len, 0u);
                            }
                            if (is_disk) {
                                runner_mem(ctx, RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_DISK, base_addr, bytes, payload_len, 0u);
                            }
                        }
                        std::free(bytes);
                        fprintf(stdout, "OK %zu\n", payload_len);
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "RUN ", 4) == 0) {
                        unsigned int cycles = 0u;
                        if (!parse_u32_token(line + 4, &cycles)) {
                            fprintf(stdout, "ERR RUN\n");
                            fflush(stdout);
                            continue;
                        }
                        RunnerRunResult result;
                        std::memset(&result, 0, sizeof(result));
                        if (!runner_run(ctx, cycles, 0u, 0, RUNNER_RUN_MODE_BASIC, &result)) {
                            fprintf(stdout, "ERR RUN\n");
                            fflush(stdout);
                            continue;
                        }
                        fprintf(stdout, "RUN %u %u\n", result.cycles_run, sim_uart_tx_len(ctx));
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "GET_REG ", 8) == 0) {
                        unsigned int idx = 0u;
                        if (!parse_u32_token(line + 8, &idx)) {
                            fprintf(stdout, "ERR GET_REG\n");
                            fflush(stdout);
                            continue;
                        }
                        fprintf(stdout, "REG %u\n", jit_read_reg(ctx, idx));
                        fflush(stdout);
                        continue;
                    }

                    if (std::strcmp(line, "GET_PC") == 0) {
                        fprintf(stdout, "PC %u\n", sim_peek(ctx, "debug_pc"));
                        fflush(stdout);
                        continue;
                    }

                    if (std::strcmp(line, "GET_INST") == 0) {
                        fprintf(stdout, "INST %u\n", sim_peek(ctx, "debug_inst"));
                        fflush(stdout);
                        continue;
                    }

                    if (std::strcmp(line, "GET_UART_TX") == 0) {
                        const unsigned int tx_len = sim_uart_tx_len(ctx);
                        unsigned char* bytes = static_cast<unsigned char*>(std::malloc(tx_len > 0u ? tx_len : 1u));
                        const unsigned int copied = (bytes && tx_len > 0u) ? sim_uart_tx_copy(ctx, bytes, tx_len) : 0u;
                        fputs("UART_TX ", stdout);
                        if (bytes && copied > 0u) write_hex_bytes(stdout, bytes, copied);
                        fputc('\n', stdout);
                        fflush(stdout);
                        std::free(bytes);
                        continue;
                    }

                    if (std::strcmp(line, "CLEAR_UART_TX") == 0) {
                        sim_uart_tx_clear(ctx);
                        fprintf(stdout, "OK\n");
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "READ_INST_WORD ", 15) == 0 ||
                        std::strncmp(line, "READ_DATA_WORD ", 15) == 0) {
                        unsigned int addr = 0u;
                        if (!parse_u32_token(line + 15, &addr)) {
                            fprintf(stdout, "ERR READ_WORD\n");
                            fflush(stdout);
                            continue;
                        }
                        const int mem_type = (std::strncmp(line, "READ_INST_WORD ", 15) == 0) ? MEM_TYPE_INST : MEM_TYPE_DATA;
                        fprintf(stdout, "WORD %u\n", sim_read_mem_word(ctx, mem_type, addr));
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "READ_DISK_BYTE ", 15) == 0) {
                        unsigned int addr = 0u;
                        if (!parse_u32_token(line + 15, &addr)) {
                            fprintf(stdout, "ERR READ_DISK_BYTE\n");
                            fflush(stdout);
                            continue;
                        }
                        fprintf(stdout, "BYTE %u\n", sim_disk_read_byte(ctx, addr) & 0xFFu);
                        fflush(stdout);
                        continue;
                    }

                    if (std::strncmp(line, "SET_PC ", 7) == 0) {
                        unsigned int value = 0u;
                        if (!parse_u32_token(line + 7, &value)) {
                            fprintf(stdout, "ERR SET_PC\n");
                            fflush(stdout);
                            continue;
                        }
                        sim_write_pc(ctx, value);
                        fprintf(stdout, "OK\n");
                        fflush(stdout);
                        continue;
                    }

                    if (std::strcmp(line, "QUIT") == 0) {
                        fprintf(stdout, "OK\n");
                        fflush(stdout);
                        break;
                    }

                    fprintf(stdout, "ERR UNKNOWN\n");
                    fflush(stdout);
                }

                std::free(line);
                if (ctx) sim_destroy(ctx);
                return 0;
            }
            #endif
          CPP
        end
      end
    end
  end
end
