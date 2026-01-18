# Synthesizable CPU Datapath - hierarchical component with instances
# Generates Verilog module instantiation and wiring

module RHDL
  module HDL
    module CPU
      class SynthDatapath < SimComponent
        # Clock and reset
        input :clk
        input :rst

        # Memory interface
        input :mem_data_in, width: 8
        output :mem_data_out, width: 8
        output :mem_addr, width: 16
        output :mem_write_en
        output :mem_read_en

        # Status outputs
        output :pc_out, width: 16
        output :acc_out, width: 8
        output :zero_flag
        output :halt

        # Internal wires
        wire :instruction, width: 8
        wire :operand, width: 8
        wire :alu_result, width: 8
        wire :alu_a, width: 8
        wire :alu_b, width: 8
        wire :alu_op, width: 4
        wire :alu_zero
        wire :reg_write
        wire :alu_src
        wire :decoder_mem_read
        wire :decoder_mem_write
        wire :branch
        wire :jump
        wire :pc_src, width: 2
        wire :halt_signal
        wire :call_signal
        wire :ret_signal
        wire :instr_length, width: 2

        # Instruction Decoder
        instance :decoder, InstructionDecoder
        port :instruction => [:decoder, :instruction]
        port :zero_flag => [:decoder, :zero_flag]
        port [:decoder, :alu_op] => :alu_op
        port [:decoder, :alu_src] => :alu_src
        port [:decoder, :reg_write] => :reg_write
        port [:decoder, :mem_read] => :decoder_mem_read
        port [:decoder, :mem_write] => :decoder_mem_write
        port [:decoder, :branch] => :branch
        port [:decoder, :jump] => :jump
        port [:decoder, :pc_src] => :pc_src
        port [:decoder, :halt] => :halt_signal
        port [:decoder, :call] => :call_signal
        port [:decoder, :ret] => :ret_signal
        port [:decoder, :instr_length] => :instr_length

        # ALU
        instance :alu, ALU, width: 8
        port :alu_a => [:alu, :a]
        port :alu_b => [:alu, :b]
        port :alu_op => [:alu, :op]
        port [:alu, :result] => :alu_result
        port [:alu, :zero] => :alu_zero

        # Program Counter (16-bit)
        instance :pc, ProgramCounter, width: 16
        port :clk => [:pc, :clk]
        port :rst => [:pc, :rst]
        port [:pc, :q] => :pc_out

        # Accumulator Register (8-bit)
        instance :acc, Register, width: 8
        port :clk => [:acc, :clk]
        port :rst => [:acc, :rst]
        port [:acc, :q] => :acc_out
      end
    end
  end
end
