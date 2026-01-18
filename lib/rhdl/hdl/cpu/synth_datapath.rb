# Synthesizable CPU Datapath - structural component with instances
# Generates Verilog module instantiation and wiring

module RHDL
  module HDL
    module CPU
      class SynthDatapath < SimComponent
        # Clock and reset
        port_input :clk
        port_input :rst

        # Memory interface
        port_input :mem_data_in, width: 8
        port_output :mem_data_out, width: 8
        port_output :mem_addr, width: 16
        port_output :mem_write_en
        port_output :mem_read_en

        # Status outputs
        port_output :pc_out, width: 16
        port_output :acc_out, width: 8
        port_output :zero_flag
        port_output :halt

        # Internal signals
        port_signal :instruction, width: 8
        port_signal :operand, width: 8
        port_signal :alu_result, width: 8
        port_signal :alu_a, width: 8
        port_signal :alu_b, width: 8
        port_signal :alu_op, width: 4
        port_signal :alu_zero
        port_signal :reg_write
        port_signal :alu_src
        port_signal :decoder_mem_read
        port_signal :decoder_mem_write
        port_signal :branch
        port_signal :jump
        port_signal :pc_src, width: 2
        port_signal :halt_signal
        port_signal :call_signal
        port_signal :ret_signal
        port_signal :instr_length, width: 2

        structure do
          # Instruction Decoder
          instance :decoder, InstructionDecoder
          connect :instruction => [:decoder, :instruction]
          connect :zero_flag => [:decoder, :zero_flag]
          connect [:decoder, :alu_op] => :alu_op
          connect [:decoder, :alu_src] => :alu_src
          connect [:decoder, :reg_write] => :reg_write
          connect [:decoder, :mem_read] => :decoder_mem_read
          connect [:decoder, :mem_write] => :decoder_mem_write
          connect [:decoder, :branch] => :branch
          connect [:decoder, :jump] => :jump
          connect [:decoder, :pc_src] => :pc_src
          connect [:decoder, :halt] => :halt_signal
          connect [:decoder, :call] => :call_signal
          connect [:decoder, :ret] => :ret_signal
          connect [:decoder, :instr_length] => :instr_length

          # ALU
          instance :alu, ALU, width: 8
          connect :alu_a => [:alu, :a]
          connect :alu_b => [:alu, :b]
          connect :alu_op => [:alu, :op]
          connect [:alu, :result] => :alu_result
          connect [:alu, :zero] => :alu_zero

          # Program Counter (16-bit)
          instance :pc, ProgramCounter, width: 16
          connect :clk => [:pc, :clk]
          connect :rst => [:pc, :rst]
          connect [:pc, :q] => :pc_out

          # Accumulator Register (8-bit)
          instance :acc, Register, width: 8
          connect :clk => [:acc, :clk]
          connect :rst => [:acc, :rst]
          connect [:acc, :q] => :acc_out
        end
      end
    end
  end
end
