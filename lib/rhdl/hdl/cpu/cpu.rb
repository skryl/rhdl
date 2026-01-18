# Declarative CPU - combines all CPU components
# Generates Verilog module with full CPU structure
#
# This component uses only the declarative DSL (input, output, wire, instance, port).
# The SimComponent base class automatically instantiates sub-components and creates
# instance variables (@decoder, @alu, @pc, @acc, @sp) from the instance declarations.

module RHDL
  module HDL
    module CPU
      class CPU < SimComponent
        # Expose sub-components (automatically instantiated from 'instance' declarations)
        attr_reader :decoder, :alu, :pc, :acc, :sp

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
        output :sp_out, width: 8
        output :zero_flag
        output :halt

        # Internal wires - control signals
        wire :instruction, width: 8
        wire :operand, width: 8
        wire :alu_result, width: 8
        wire :alu_op, width: 4
        wire :alu_zero
        wire :reg_write
        wire :alu_src
        wire :mem_read
        wire :mem_write
        wire :branch
        wire :jump
        wire :pc_src, width: 2
        wire :halt_signal
        wire :call_signal
        wire :ret_signal
        wire :instr_length, width: 2
        wire :sp_empty

        # Sub-components - automatically instantiated by SimComponent
        instance :decoder, InstructionDecoder
        instance :alu, ALU, width: 8
        instance :pc, ProgramCounter, width: 16
        instance :acc, Register, width: 8
        instance :sp, StackPointer, width: 8, initial: 0xFF

        # Decoder connections
        port :instruction => [:decoder, :instruction]
        port :zero_flag => [:decoder, :zero_flag]
        port [:decoder, :alu_op] => :alu_op
        port [:decoder, :alu_src] => :alu_src
        port [:decoder, :reg_write] => :reg_write
        port [:decoder, :mem_read] => :mem_read
        port [:decoder, :mem_write] => :mem_write
        port [:decoder, :branch] => :branch
        port [:decoder, :jump] => :jump
        port [:decoder, :pc_src] => :pc_src
        port [:decoder, :halt] => :halt_signal
        port [:decoder, :call] => :call_signal
        port [:decoder, :ret] => :ret_signal
        port [:decoder, :instr_length] => :instr_length

        # ALU connections
        port :acc_out => [:alu, :a]
        port :mem_data_in => [:alu, :b]
        port :alu_op => [:alu, :op]
        port [:alu, :result] => :alu_result
        port [:alu, :zero] => :alu_zero

        # Program counter connections
        port :clk => [:pc, :clk]
        port :rst => [:pc, :rst]
        port [:pc, :q] => :pc_out

        # Accumulator connections
        port :clk => [:acc, :clk]
        port :rst => [:acc, :rst]
        port :alu_result => [:acc, :d]
        port [:acc, :q] => :acc_out

        # Stack pointer connections
        port :clk => [:sp, :clk]
        port :rst => [:sp, :rst]
        port [:sp, :q] => :sp_out
        port [:sp, :empty] => :sp_empty

        # Output routing
        port :halt_signal => :halt
        port :mem_read => :mem_read_en
        port :mem_write => :mem_write_en
      end
    end
  end
end
