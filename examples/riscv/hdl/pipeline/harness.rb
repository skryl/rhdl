# Harness class for testing the pipelined RISC-V CPU
# Provides memory and test helper methods

require_relative 'cpu'
require_relative '../memory'
require_relative '../clint'
require_relative '../plic'
require_relative '../uart'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class Harness
      attr_reader :clock_count

      def initialize(name = nil)
        @cpu = CPU.new(name || 'cpu')
        @inst_mem = Memory.new('inst_mem')
        @data_mem = Memory.new('data_mem')
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
        @uart_rx_queue = []
        @uart_tx_bytes = []
        @clint = Clint.new('clint')
        @plic = Plic.new('plic')
        @uart = Uart.new('uart')
        reset!
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
        @uart_rx_queue = []
        @uart_tx_bytes = []
        @cpu.set_input(:rst, 1)
        @cpu.set_input(:clk, 0)
        propagate_all
        @cpu.set_input(:clk, 1)
        propagate_all
        @cpu.set_input(:clk, 0)
        propagate_all
        @cpu.set_input(:rst, 0)
        propagate_all
      end

      def clock_cycle
        # Low phase - fetch instruction for current PC
        @cpu.set_input(:clk, 0)
        propagate_fetch_only  # Fetch instruction without clock edge

        # Rising edge - latch values including fetched instruction
        @cpu.set_input(:clk, 1)
        propagate_all

        # Low phase - let combinational logic settle
        @cpu.set_input(:clk, 0)
        propagate_all
        @clock_count += 1
      end

      def run_cycles(n)
        n.times { clock_cycle }
      end

      def load_program(instructions, start_addr = 0)
        instructions.each_with_index do |inst, i|
          @inst_mem.write_word(start_addr + i * 4, inst)
        end
      end

      def write_data(addr, value)
        @data_mem.write_word(addr, value)
      end

      def read_data(addr)
        @data_mem.read_word(addr)
      end

      def read_reg(index)
        @cpu.read_reg(index)
      end

      def write_reg(index, value)
        @cpu.write_reg(index, value)
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
        @uart_rx_queue << (byte & 0xFF)
      end

      def uart_tx_bytes
        @uart_tx_bytes.dup
      end

      def clear_uart_tx_bytes
        @uart_tx_bytes.clear
      end

      def pc
        @cpu.get_output(:debug_pc)
      end

      def current_inst
        @cpu.get_output(:debug_inst)
      end

      private

      # Fetch instruction for current PC and feed to CPU (without triggering clock edge)
      def propagate_fetch_only
        clk = @cpu.inputs[:clk].get
        rst = @cpu.inputs[:rst].get
        apply_irq_inputs

        # Propagate CPU to get current instruction address
        @cpu.propagate
        inst_addr = @cpu.get_output(:inst_addr)

        # Fetch instruction from memory
        @inst_mem.set_input(:clk, clk)
        @inst_mem.set_input(:rst, rst)
        @inst_mem.set_input(:addr, inst_addr)
        @inst_mem.set_input(:write_data, 0)
        @inst_mem.set_input(:mem_write, 0)
        @inst_mem.set_input(:mem_read, 1)
        @inst_mem.set_input(:funct3, 0b010)
        @inst_mem.propagate
        inst_data = @inst_mem.get_output(:read_data)

        # Feed instruction to CPU (so it's available for the rising edge)
        @cpu.set_input(:inst_data, inst_data)
        @cpu.propagate  # Propagate to update wires, but clk=0 so no edge
      end

      def propagate_all
        clk = @cpu.inputs[:clk].get
        rst = @cpu.inputs[:rst].get
        apply_irq_inputs

        # First propagate CPU to get instruction address
        @cpu.propagate
        inst_addr = @cpu.get_output(:inst_addr)

        # Instruction memory fetch
        @inst_mem.set_input(:clk, clk)
        @inst_mem.set_input(:rst, rst)
        @inst_mem.set_input(:addr, inst_addr)
        @inst_mem.set_input(:write_data, 0)
        @inst_mem.set_input(:mem_write, 0)
        @inst_mem.set_input(:mem_read, 1)
        @inst_mem.set_input(:funct3, 0b010)
        @inst_mem.propagate
        inst_data = @inst_mem.get_output(:read_data)

        # Feed instruction to CPU
        @cpu.set_input(:inst_data, inst_data)
        @cpu.propagate

        # Data memory access
        data_addr = @cpu.get_output(:data_addr)
        data_wdata = @cpu.get_output(:data_wdata)
        data_we = @cpu.get_output(:data_we)
        data_re = @cpu.get_output(:data_re)
        data_funct3 = @cpu.get_output(:data_funct3)
        clint_selected = clint_access?(data_addr)
        plic_selected = plic_access?(data_addr)
        uart_selected = uart_access?(data_addr)

        # CLINT access and timer interrupt generation
        @clint.set_input(:clk, clk)
        @clint.set_input(:rst, rst)
        @clint.set_input(:addr, data_addr)
        @clint.set_input(:write_data, data_wdata)
        @clint.set_input(:mem_write, clint_selected ? data_we : 0)
        @clint.set_input(:mem_read, clint_selected ? data_re : 0)
        @clint.set_input(:funct3, data_funct3)
        @clint.propagate
        @clint_irq_software = @clint.get_output(:irq_software)
        @clint_irq_timer = @clint.get_output(:irq_timer)

        @plic.set_input(:clk, clk)
        @plic.set_input(:rst, rst)
        @plic.set_input(:addr, data_addr)
        @plic.set_input(:write_data, data_wdata)
        @plic.set_input(:mem_write, plic_selected ? data_we : 0)
        @plic.set_input(:mem_read, plic_selected ? data_re : 0)
        @plic.set_input(:funct3, data_funct3)
        @plic.set_input(:source1, @plic_source1)
        @plic.set_input(:source10, (@plic_source10 | @uart_irq) != 0 ? 1 : 0)
        @plic.propagate
        @plic_irq_external = @plic.get_output(:irq_external)

        uart_rx_valid = @uart_rx_queue.empty? ? 0 : 1
        uart_rx_data = @uart_rx_queue.empty? ? 0 : @uart_rx_queue.first
        @uart.set_input(:clk, clk)
        @uart.set_input(:rst, rst)
        @uart.set_input(:addr, data_addr)
        @uart.set_input(:write_data, data_wdata)
        @uart.set_input(:mem_write, uart_selected ? data_we : 0)
        @uart.set_input(:mem_read, uart_selected ? data_re : 0)
        @uart.set_input(:funct3, data_funct3)
        @uart.set_input(:rx_valid, uart_rx_valid)
        @uart.set_input(:rx_data, uart_rx_data)
        @uart.propagate
        @uart_rx_queue.shift if @uart.get_output(:rx_accept) == 1 && !@uart_rx_queue.empty?
        if @uart.get_output(:tx_valid) == 1
          @uart_tx_bytes << (@uart.get_output(:tx_data) & 0xFF)
        end
        @uart_irq = @uart.get_output(:irq)

        @data_mem.set_input(:clk, clk)
        @data_mem.set_input(:rst, rst)
        @data_mem.set_input(:addr, data_addr)
        @data_mem.set_input(:write_data, data_wdata)
        @data_mem.set_input(:mem_write, (clint_selected || plic_selected || uart_selected) ? 0 : data_we)
        @data_mem.set_input(:mem_read, (clint_selected || plic_selected || uart_selected) ? 0 : data_re)
        @data_mem.set_input(:funct3, data_funct3)
        @data_mem.propagate
        data_rdata = if clint_selected
                       @clint.get_output(:read_data)
                     elsif plic_selected
                       @plic.get_output(:read_data)
                     elsif uart_selected
                       @uart.get_output(:read_data)
                     else
                       @data_mem.get_output(:read_data)
                     end

        # Feed memory data back to CPU
        @cpu.set_input(:data_rdata, data_rdata)
        apply_irq_inputs
        @cpu.propagate
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

      def apply_irq_inputs
        @cpu.set_input(:irq_software, (@irq_software | @clint_irq_software) != 0 ? 1 : 0)
        @cpu.set_input(:irq_timer, (@irq_timer | @clint_irq_timer) != 0 ? 1 : 0)
        @cpu.set_input(:irq_external, (@irq_external | @plic_irq_external) != 0 ? 1 : 0)
      end
        end

        # Keep the old class name for backwards compatibility with tests
        PipelinedCPU = Harness
      end
    end
  end
end
