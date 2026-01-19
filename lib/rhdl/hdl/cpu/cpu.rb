# Declarative CPU - combines all CPU components
# Purely synthesizable using only the declarative DSL.
# All logic is expressed through structure (instances + ports) and behavior blocks.
# No simulation-only methods - Harness interacts only through ports.

require_relative 'instruction_decoder'
require_relative 'accumulator'

module RHDL
  module HDL
    module CPU
      class CPU < SimComponent
        # Clock and reset
        input :clk
        input :rst

        # Memory interface
        input :mem_data_in, width: 8      # Data read from memory
        output :mem_data_out, width: 8    # Data to write to memory
        output :mem_addr, width: 16       # Memory address
        output :mem_write_en              # Memory write enable
        output :mem_read_en               # Memory read enable

        # Instruction input
        input :instruction, width: 8
        input :operand, width: 16         # Operand (1 or 2 bytes)
        input :zero_flag_in               # Zero flag input (computed by harness)

        # Control inputs for registers
        input :acc_load_en                # Load accumulator with acc_load_data
        input :acc_load_data, width: 8    # Data to load into accumulator
        input :pc_load_en                 # Load PC with pc_load_data
        input :pc_load_data, width: 16    # Data to load into PC
        input :sp_push                    # Push stack pointer
        input :sp_pop                     # Pop stack pointer

        # Status outputs
        output :pc_out, width: 16
        output :acc_out, width: 8
        output :sp_out, width: 8
        output :sp_empty
        output :halt_out

        # Decoder outputs (exposed for Harness to read control signals)
        output :dec_alu_op, width: 4
        output :dec_alu_src
        output :dec_reg_write
        output :dec_mem_read
        output :dec_mem_write
        output :dec_branch
        output :dec_jump
        output :dec_pc_src, width: 2
        output :dec_halt
        output :dec_call
        output :dec_ret
        output :dec_instr_length, width: 2

        # ALU output
        output :alu_result_out, width: 8
        output :alu_zero_out

        # Internal wires
        wire :alu_a, width: 8
        wire :alu_b, width: 8
        wire :alu_result, width: 8
        wire :alu_zero

        # Sub-components
        instance :decoder, InstructionDecoder
        instance :alu, ALU, width: 8
        instance :pc, ProgramCounter, width: 16
        instance :acc, Register, width: 8
        instance :sp, StackPointer, width: 8, initial: 0xFF

        # Decoder connections - zero flag comes from input port
        port :instruction => [:decoder, :instruction]
        port :zero_flag_in => [:decoder, :zero_flag]
        port [:decoder, :alu_op] => :dec_alu_op
        port [:decoder, :alu_src] => :dec_alu_src
        port [:decoder, :reg_write] => :dec_reg_write
        port [:decoder, :mem_read] => :dec_mem_read
        port [:decoder, :mem_write] => :dec_mem_write
        port [:decoder, :branch] => :dec_branch
        port [:decoder, :jump] => :dec_jump
        port [:decoder, :pc_src] => :dec_pc_src
        port [:decoder, :halt] => :dec_halt
        port [:decoder, :call] => :dec_call
        port [:decoder, :ret] => :dec_ret
        port [:decoder, :instr_length] => :dec_instr_length

        # ALU connections
        port :alu_a => [:alu, :a]
        port :alu_b => [:alu, :b]
        port :dec_alu_op => [:alu, :op]
        port [:alu, :result] => :alu_result
        port [:alu, :zero] => :alu_zero

        # ALU outputs exposed
        port :alu_result => :alu_result_out
        port :alu_zero => :alu_zero_out

        # Program counter connections
        port :clk => [:pc, :clk]
        port :rst => [:pc, :rst]
        port :pc_load_data => [:pc, :d]
        port :pc_load_en => [:pc, :load]
        port [:pc, :q] => :pc_out

        # Accumulator connections
        port :clk => [:acc, :clk]
        port :rst => [:acc, :rst]
        port :acc_load_data => [:acc, :d]
        port :acc_load_en => [:acc, :en]
        port [:acc, :q] => :acc_out

        # ALU input wiring (acc value to ALU input a, memory data to input b)
        port :acc_out => :alu_a
        port :mem_data_in => :alu_b

        # Stack pointer connections
        port :clk => [:sp, :clk]
        port :rst => [:sp, :rst]
        port :sp_push => [:sp, :push]
        port :sp_pop => [:sp, :pop]
        port [:sp, :q] => :sp_out
        port [:sp, :empty] => :sp_empty

        # Output routing
        port :dec_halt => :halt_out
        port :dec_mem_read => :mem_read_en
        port :dec_mem_write => :mem_write_en
        port :acc_out => :mem_data_out

        # Behavior for combinational control logic
        behavior do
          mem_addr <= pc_out
        end
      end
    end
  end
end
