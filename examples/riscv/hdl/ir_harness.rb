# RV32I IR Harness - IR simulator + Ruby MMIO/memory harness
#
# Runs the single-cycle CPU core through RHDL IR simulation (jit/interpreter/compiler/ruby fallback)
# while keeping instruction/data memory and MMIO peripherals in Ruby for test ergonomics.

require 'rhdl/codegen'
require 'rhdl/codegen/ir/sim/ir_simulator'
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
      class IRHarness
        attr_reader :clock_count, :sim

        def initialize(mem_size: Memory::DEFAULT_SIZE, backend: :jit, allow_fallback: true)
          @mem_size = mem_size
          @backend = backend
          @allow_fallback = allow_fallback

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

          ir = CPU.to_flat_ir
          ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
          @sim = RHDL::Codegen::IR::IrSimulator.new(
            ir_json,
            backend: backend,
            allow_fallback: allow_fallback
          )
          @native_riscv = @sim.native? && @sim.runner_kind == :riscv

          @inst_mem = Memory.new('imem', size: mem_size)
          @data_mem = Memory.new('dmem', size: mem_size)
          @clint = Clint.new('clint')
          @plic = Plic.new('plic')
          @uart = Uart.new('uart')
          @virtio = VirtioBlk.new('virtio_blk')

          reset!
        end

        def native?
          @sim.native?
        end

        def simulator_type
          @sim.simulator_type
        end

        def backend
          @sim.backend
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

          @sim.reset

          if native_riscv?
            @sim.runner_riscv_set_interrupts(software: false, timer: false, external: false)
            @sim.runner_riscv_set_plic_sources(source1: false, source10: false)
            @sim.runner_riscv_clear_uart_tx_bytes
            return
          end

          set_clk_rst(0, 1)
          propagate_all(evaluate_cpu: true)
          set_clk_rst(1, 1)
          propagate_all(evaluate_cpu: false)
          tick_cpu
          set_clk_rst(0, 0)
          propagate_all(evaluate_cpu: true)
        end

        def clock_cycle
          if native_riscv?
            result = @sim.runner_run_cycles(1)
            @clock_count += result ? result[:cycles_run].to_i : 1
            return
          end

          set_clk_rst(0, 0)
          propagate_all(evaluate_cpu: true)

          set_clk_rst(1, 0)
          propagate_all(evaluate_cpu: false)
          tick_cpu

          set_clk_rst(0, 0)
          propagate_all(evaluate_cpu: true)

          @clock_count += 1
        end

        def run_cycles(n)
          if native_riscv?
            result = @sim.runner_run_cycles(n.to_i)
            @clock_count += result ? result[:cycles_run].to_i : n.to_i
          else
            n.times { clock_cycle }
          end
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
          raise NotImplementedError, 'IRHarness does not support direct register writes'
        end

        def read_pc
          peek_cpu(:debug_pc) & 0xFFFF_FFFF
        end

        def write_pc(_value)
          poke_internal_pc!(_value & 0xFFFF_FFFF)
        end

        def load_program(program, start_addr = 0)
          if native_riscv?
            @sim.runner_load_rom(program.pack('V*'), start_addr.to_i)
          else
            @inst_mem.load_program(program, start_addr)
          end
        end

        def load_data(data, start_addr = 0)
          if native_riscv?
            @sim.runner_write_memory(start_addr.to_i, data.pack('V*'), mapped: false)
          else
            @data_mem.load_program(data, start_addr)
          end
        end

        def read_inst_word(addr)
          if native_riscv?
            bytes = @sim.runner_read_rom(addr.to_i, 4)
            bytes.pack('C*').ljust(4, "\x00").unpack1('V')
          else
            @inst_mem.read_word(addr)
          end
        end

        def read_data_word(addr)
          if native_riscv?
            bytes = @sim.runner_read_memory(addr.to_i, 4, mapped: false)
            bytes.pack('C*').ljust(4, "\x00").unpack1('V')
          else
            @data_mem.read_word(addr)
          end
        end

        def write_data_word(addr, value)
          if native_riscv?
            @sim.runner_write_memory(addr.to_i, [value & 0xFFFF_FFFF].pack('V'), mapped: false)
          else
            @data_mem.write_word(addr, value)
          end
        end

        def set_interrupts(software: nil, timer: nil, external: nil)
          @irq_software = software.nil? ? @irq_software : (software ? 1 : 0)
          @irq_timer = timer.nil? ? @irq_timer : (timer ? 1 : 0)
          @irq_external = external.nil? ? @irq_external : (external ? 1 : 0)
          if native_riscv?
            @sim.runner_riscv_set_interrupts(
              software: @irq_software != 0,
              timer: @irq_timer != 0,
              external: @irq_external != 0
            )
          end
        end

        def set_plic_sources(source1: nil, source10: nil)
          @plic_source1 = source1.nil? ? @plic_source1 : (source1 ? 1 : 0)
          @plic_source10 = source10.nil? ? @plic_source10 : (source10 ? 1 : 0)
          if native_riscv?
            @sim.runner_riscv_set_plic_sources(
              source1: @plic_source1 != 0,
              source10: @plic_source10 != 0
            )
          end
        end

        def uart_receive_byte(byte)
          uart_receive_bytes([byte & 0xFF])
        end

        def uart_receive_bytes(bytes)
          if native_riscv?
            @sim.runner_riscv_uart_receive_bytes(bytes)
          else
            bytes.each { |byte| @uart_rx_queue << (byte & 0xFF) }
          end
        end

        def uart_receive_text(text)
          uart_receive_bytes(text.to_s.b.bytes)
        end

        def uart_tx_bytes
          if native_riscv?
            @sim.runner_riscv_uart_tx_bytes
          else
            @uart_tx_bytes.dup
          end
        end

        def clear_uart_tx_bytes
          if native_riscv?
            @sim.runner_riscv_clear_uart_tx_bytes
          else
            @uart_tx_bytes.clear
          end
        end

        def load_virtio_disk(bytes, offset: 0)
          if native_riscv?
            @sim.runner_riscv_load_disk(bytes, offset.to_i)
          else
            @virtio.load_disk_bytes(bytes, offset: offset)
          end
        end

        def read_virtio_disk_byte(offset)
          if native_riscv?
            @sim.runner_riscv_read_disk(offset.to_i, 1).first.to_i & 0xFF
          else
            @virtio.read_disk_byte(offset)
          end
        end

        def state
          {
            pc: read_pc,
            x1: read_reg(1),
            x2: read_reg(2),
            x10: read_reg(10),
            x11: read_reg(11),
            inst: peek_cpu(:debug_inst),
            cycles: @clock_count
          }
        end

        private

        def poke_cpu(name, value)
          @sim.poke(name.to_s, value)
        end

        def native_riscv?
          @native_riscv
        end

        def peek_cpu(name)
          @sim.peek(name.to_s)
        end

        def eval_cpu
          @sim.evaluate
        end

        def tick_cpu
          @sim.tick
        end

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

        def poke_internal_pc!(value)
          candidates = %w[pc_reg__pc pc current_pc]
          signal = candidates.find { |name| @sim.has_signal?(name) }
          raise NotImplementedError, 'Unable to locate internal PC signal in IR simulator' unless signal

          @sim.poke(signal, value & 0xFFFF_FFFF)
          @sim.evaluate
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
      end
    end
  end
end
