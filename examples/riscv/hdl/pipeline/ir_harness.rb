# IR harness for the pipelined RISC-V CPU
# Runs the core in IR simulation and keeps memories/MMIO in Ruby.

require 'rhdl/codegen'
require 'rhdl/codegen/ir/sim/ir_simulator'
require_relative 'cpu'
require_relative '../memory'
require_relative '../clint'
require_relative '../plic'
require_relative '../uart'

module RHDL
  module Examples
    module RISCV
      module Pipeline
        class IRHarness
          attr_reader :clock_count, :sim

          def initialize(name = nil, backend: :jit, allow_fallback: true)
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
            @debug_reg_addr = 0
            @clk = 0
            @rst = 0

            ir = CPU.to_flat_ir(top_name: name || 'riscv_pipeline_ir')
            ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)
            @sim = RHDL::Codegen::IR::IrSimulator.new(
              ir_json,
              backend: backend,
              allow_fallback: allow_fallback
            )

            @inst_mem = Memory.new('inst_mem')
            @data_mem = Memory.new('data_mem')
            @clint = Clint.new('clint')
            @plic = Plic.new('plic')
            @uart = Uart.new('uart')
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
            @uart_rx_queue = []
            @uart_tx_bytes = []
            @debug_reg_addr = 0

            @sim.reset

            set_clk_rst(0, 1)
            propagate_all(evaluate_cpu: true)
            set_clk_rst(1, 1)
            propagate_all(evaluate_cpu: false)
            tick_cpu
            set_clk_rst(0, 1)
            propagate_all(evaluate_cpu: true)
            set_clk_rst(0, 0)
            propagate_all(evaluate_cpu: true)
          end

          def clock_cycle
            # Low phase - settle full combinational path
            set_clk_rst(0, 0)
            propagate_all(evaluate_cpu: true)

            # Rising edge - latch pipeline state
            set_clk_rst(1, 0)
            propagate_all(evaluate_cpu: false)
            tick_cpu

            # Low phase - settle combinational paths
            set_clk_rst(0, 0)
            propagate_all(evaluate_cpu: true)

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
            peek_cpu(:debug_pc) & 0xFFFF_FFFF
          end

          def current_inst
            peek_cpu(:debug_inst)
          end

          private

          def poke_cpu(name, value)
            @sim.poke(name.to_s, value)
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
          end

          # Fetch instruction for current PC and feed to CPU without clock edge.
          def propagate_fetch_only(evaluate_cpu: true)
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

            @inst_mem.set_input(:clk, @clk)
            @inst_mem.set_input(:rst, @rst)
            @inst_mem.set_input(:addr, inst_addr)
            @inst_mem.set_input(:write_data, 0)
            @inst_mem.set_input(:mem_write, 0)
            @inst_mem.set_input(:mem_read, 1)
            @inst_mem.set_input(:funct3, 0b010)
            @inst_mem.propagate
            inst_data = @inst_mem.get_output(:read_data)

            poke_cpu(:inst_data, inst_data)
            eval_cpu if evaluate_cpu
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

            @inst_mem.set_input(:clk, @clk)
            @inst_mem.set_input(:rst, @rst)
            @inst_mem.set_input(:addr, inst_addr)
            @inst_mem.set_input(:write_data, 0)
            @inst_mem.set_input(:mem_write, 0)
            @inst_mem.set_input(:mem_read, 1)
            @inst_mem.set_input(:funct3, 0b010)
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

            @clint.set_input(:clk, @clk)
            @clint.set_input(:rst, @rst)
            @clint.set_input(:addr, data_addr)
            @clint.set_input(:write_data, data_wdata)
            @clint.set_input(:mem_write, clint_selected ? data_we : 0)
            @clint.set_input(:mem_read, clint_selected ? data_re : 0)
            @clint.set_input(:funct3, data_funct3)
            @clint.propagate
            @clint_irq_software = @clint.get_output(:irq_software)
            @clint_irq_timer = @clint.get_output(:irq_timer)

            @plic.set_input(:clk, @clk)
            @plic.set_input(:rst, @rst)
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
            @uart.set_input(:clk, @clk)
            @uart.set_input(:rst, @rst)
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

            @data_mem.set_input(:clk, @clk)
            @data_mem.set_input(:rst, @rst)
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

          def apply_irq_inputs
            poke_cpu(:irq_software, (@irq_software | @clint_irq_software) != 0 ? 1 : 0)
            poke_cpu(:irq_timer, (@irq_timer | @clint_irq_timer) != 0 ? 1 : 0)
            poke_cpu(:irq_external, (@irq_external | @plic_irq_external) != 0 ? 1 : 0)
          end
        end

        IRPipelinedCPU = IRHarness
      end
    end
  end
end
