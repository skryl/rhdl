# Self-Contained CPU with Internal Control Unit
# All instruction sequencing is handled internally.
# The harness only needs to connect memory and drive the clock.
#
# Architecture:
#   CPU outputs memory address and read/write enables
#   Harness reads/writes memory and provides data back to CPU
#   CPU sequences through states automatically

require_relative 'instruction_decoder'
require_relative 'control_unit'

module RHDL
  module HDL
    module CPU
      class CPUWithControl < Component
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        # Clock and reset
        input :clk
        input :rst

        # Memory interface - this is ALL the harness needs to connect
        input :mem_data_in, width: 8      # Data read from memory
        output :mem_data_out, width: 8    # Data to write to memory
        output :mem_addr, width: 16       # Memory address
        output :mem_write_en              # Memory write enable
        output :mem_read_en               # Memory read enable

        # Status outputs (for debugging/monitoring)
        output :pc_out, width: 16
        output :acc_out, width: 8
        output :sp_out, width: 8
        output :halted
        output :state_out, width: 8       # Current control state

        # Internal wires
        wire :instruction_reg, width: 8   # Latched instruction
        wire :operand_nibble, width: 4    # Embedded operand (instruction low nibble)
        wire :operand_lo, width: 8        # Operand low byte
        wire :operand_hi, width: 8        # Operand high byte
        wire :operand_16, width: 16       # Combined operand
        wire :effective_operand, width: 8 # Either embedded nibble or full operand byte
        wire :mem_data_latched, width: 8  # Latched memory data from S_READ_MEM

        wire :alu_result, width: 8
        wire :alu_zero
        wire :alu_b_input, width: 8       # ALU B operand (latched or immediate)
        wire :zero_flag_reg_out
        wire :zero_flag_next
        wire :acc_result, width: 8

        # Decoder outputs
        wire :dec_alu_op, width: 4
        wire :dec_alu_src
        wire :dec_reg_write
        wire :dec_mem_read
        wire :dec_mem_write
        wire :dec_branch
        wire :dec_jump
        wire :dec_pc_src, width: 2
        wire :dec_halt
        wire :dec_call
        wire :dec_ret
        wire :dec_instr_length, width: 2
        wire :dec_is_lda

        # Control unit outputs
        wire :ctrl_state, width: 8
        wire :ctrl_mem_addr_sel, width: 3
        wire :ctrl_mem_read_en
        wire :ctrl_mem_write_en
        wire :ctrl_instr_latch_en
        wire :ctrl_operand_lo_latch_en
        wire :ctrl_operand_hi_latch_en
        wire :ctrl_acc_load_en
        wire :ctrl_zero_flag_load_en
        wire :ctrl_pc_load_en
        wire :ctrl_pc_inc_en
        wire :ctrl_sp_push_en
        wire :ctrl_sp_pop_en
        wire :ctrl_data_out_sel, width: 2
        wire :ctrl_halted
        wire :ctrl_done
        wire :ctrl_mem_data_latch_en       # Latch memory data for ALU

        # PC control wires
        wire :pc_next, width: 16
        wire :pc_current, width: 16
        wire :return_addr, width: 8       # Return address for CALL

        # Address select values (must match ControlUnit)
        ADDR_PC      = 0
        ADDR_PC_1    = 1
        ADDR_PC_2    = 2
        ADDR_OPERAND = 3
        ADDR_OPERAND_16 = 4
        ADDR_SP      = 5
        ADDR_SP_PLUS_1 = 6  # For RET (pop reads from SP+1)

        # Sub-components
        instance :decoder, InstructionDecoder
        instance :ctrl, ControlUnit
        instance :alu, ALU, width: 8
        instance :pc_reg, ProgramCounter, width: 16
        instance :acc, Register, width: 8
        instance :sp, StackPointer, width: 8, initial: 0xFF
        instance :zero_flag_reg, DFlipFlop
        instance :acc_mux, Mux2, width: 8

        # Instruction register (latch instruction from memory)
        instance :instr_reg, Register, width: 8
        instance :op_lo_reg, Register, width: 8
        instance :op_hi_reg, Register, width: 8
        instance :mem_data_reg, Register, width: 8  # Latch memory data for ALU

        # Decoder connections
        port :instruction_reg => [:decoder, :instruction]
        port :zero_flag_reg_out => [:decoder, :zero_flag]
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
        port [:decoder, :is_lda] => :dec_is_lda

        # Control unit connections
        port :clk => [:ctrl, :clk]
        port :rst => [:ctrl, :rst]
        port :dec_instr_length => [:ctrl, :instr_length]
        port :dec_halt => [:ctrl, :is_halt]
        port :dec_call => [:ctrl, :is_call]
        port :dec_ret => [:ctrl, :is_ret]
        port :dec_branch => [:ctrl, :is_branch]
        port :dec_jump => [:ctrl, :is_jump]
        port :dec_is_lda => [:ctrl, :is_lda]
        port :dec_reg_write => [:ctrl, :is_reg_write]
        port :dec_mem_write => [:ctrl, :is_mem_write]
        port :dec_mem_read => [:ctrl, :is_mem_read]
        port :dec_pc_src => [:ctrl, :pc_src]
        port :dec_alu_src => [:ctrl, :alu_src]
        port [:sp, :empty] => [:ctrl, :sp_empty]
        port [:sp, :full] => [:ctrl, :sp_full]

        # Control unit outputs
        port [:ctrl, :state] => :ctrl_state
        port [:ctrl, :mem_addr_sel] => :ctrl_mem_addr_sel
        port [:ctrl, :mem_read_en] => :ctrl_mem_read_en
        port [:ctrl, :mem_write_en] => :ctrl_mem_write_en
        port [:ctrl, :instr_latch_en] => :ctrl_instr_latch_en
        port [:ctrl, :operand_lo_latch_en] => :ctrl_operand_lo_latch_en
        port [:ctrl, :operand_hi_latch_en] => :ctrl_operand_hi_latch_en
        port [:ctrl, :acc_load_en] => :ctrl_acc_load_en
        port [:ctrl, :zero_flag_load_en] => :ctrl_zero_flag_load_en
        port [:ctrl, :pc_load_en] => :ctrl_pc_load_en
        port [:ctrl, :pc_inc_en] => :ctrl_pc_inc_en
        port [:ctrl, :sp_push_en] => :ctrl_sp_push_en
        port [:ctrl, :sp_pop_en] => :ctrl_sp_pop_en
        port [:ctrl, :data_out_sel] => :ctrl_data_out_sel
        port [:ctrl, :halted] => :ctrl_halted
        port [:ctrl, :mem_data_latch_en] => :ctrl_mem_data_latch_en

        # Instruction register
        port :clk => [:instr_reg, :clk]
        port :rst => [:instr_reg, :rst]
        port :mem_data_in => [:instr_reg, :d]
        port :ctrl_instr_latch_en => [:instr_reg, :en]
        port [:instr_reg, :q] => :instruction_reg

        # Operand low register
        port :clk => [:op_lo_reg, :clk]
        port :rst => [:op_lo_reg, :rst]
        port :mem_data_in => [:op_lo_reg, :d]
        port :ctrl_operand_lo_latch_en => [:op_lo_reg, :en]
        port [:op_lo_reg, :q] => :operand_lo

        # Operand high register
        port :clk => [:op_hi_reg, :clk]
        port :rst => [:op_hi_reg, :rst]
        port :mem_data_in => [:op_hi_reg, :d]
        port :ctrl_operand_hi_latch_en => [:op_hi_reg, :en]
        port [:op_hi_reg, :q] => :operand_hi

        # Memory data latch (for ALU operand read during S_READ_MEM)
        port :clk => [:mem_data_reg, :clk]
        port :rst => [:mem_data_reg, :rst]
        port :mem_data_in => [:mem_data_reg, :d]
        port :ctrl_mem_data_latch_en => [:mem_data_reg, :en]
        port [:mem_data_reg, :q] => :mem_data_latched

        # Zero flag register
        port :clk => [:zero_flag_reg, :clk]
        port :rst => [:zero_flag_reg, :rst]
        port :ctrl_zero_flag_load_en => [:zero_flag_reg, :en]
        port :zero_flag_next => [:zero_flag_reg, :d]
        port [:zero_flag_reg, :q] => :zero_flag_reg_out

        # ACC result mux
        # For LDI: use latched operand (operand_lo)
        # For LDA: use live mem_data_in (from memory read in S_READ_MEM)
        # For ALU ops: use alu_result
        wire :acc_data_in, width: 8
        port :alu_result => [:acc_mux, :a]
        port :acc_data_in => [:acc_mux, :b]
        port :dec_is_lda => [:acc_mux, :sel]
        port [:acc_mux, :y] => :acc_result

        # ALU connections
        # B input uses latched memory data (read during S_READ_MEM)
        port :acc_out => [:alu, :a]
        port :alu_b_input => [:alu, :b]
        port :dec_alu_op => [:alu, :op]
        port [:alu, :result] => :alu_result
        port [:alu, :zero] => :alu_zero

        # Program counter
        # Load on either explicit load (branch/jump) or increment
        wire :pc_update_en
        port :clk => [:pc_reg, :clk]
        port :rst => [:pc_reg, :rst]
        port :pc_next => [:pc_reg, :d]
        port :pc_update_en => [:pc_reg, :load]
        port [:pc_reg, :q] => :pc_current

        # Accumulator
        port :clk => [:acc, :clk]
        port :rst => [:acc, :rst]
        port :acc_result => [:acc, :d]
        port :ctrl_acc_load_en => [:acc, :en]
        port [:acc, :q] => :acc_out

        # Stack pointer
        port :clk => [:sp, :clk]
        port :rst => [:sp, :rst]
        port :ctrl_sp_push_en => [:sp, :push]
        port :ctrl_sp_pop_en => [:sp, :pop]
        port [:sp, :q] => :sp_out

        # Outputs
        port :pc_current => :pc_out
        port :ctrl_halted => :halted
        port :ctrl_state => :state_out
        port :ctrl_mem_read_en => :mem_read_en
        port :ctrl_mem_write_en => :mem_write_en

        # Combinational logic
        behavior do
          # Extract embedded operand from instruction low nibble
          operand_nibble <= instruction_reg[3..0]

          # Effective operand: use embedded nibble for 1-byte instructions,
          # otherwise use the fetched operand byte
          effective_operand <= mux(dec_instr_length == lit(1, width: 2),
            operand_nibble,  # 1-byte: embedded in instruction
            operand_lo)      # 2+ byte: fetched operand

          # ALU B input: use latched memory data from S_READ_MEM
          alu_b_input <= mem_data_latched

          # Combine operand bytes into 16-bit value
          # operand_hi is MSB, operand_lo is LSB
          operand_16 <= (operand_hi[7..0] << lit(8, width: 4)) | operand_lo[7..0]

          # ACC data input - for LDI use latched operand, for LDA use latched memory data
          acc_data_in <= mux(dec_alu_src,
            operand_lo,        # LDI: use latched operand
            mem_data_latched)  # LDA: use latched memory data from S_READ_MEM

          # PC update enable - increment, load (branch/jump/call), or RET
          # RET needs special handling: load from mem_data_latched during EXECUTE
          pc_update_en <= ctrl_pc_inc_en | ctrl_pc_load_en |
            ((ctrl_state == lit(0x06, width: 8)) & dec_ret)  # EXECUTE state with RET

          # Zero flag next value - for LDI check if operand is zero
          zero_flag_next <= mux(dec_is_lda,
            mux(acc_data_in == lit(0, width: 8), 1, 0),
            alu_zero)

          # Memory address select
          mem_addr <= case_select(ctrl_mem_addr_sel, {
            ADDR_PC => pc_current,
            ADDR_PC_1 => pc_current + lit(1, width: 16),
            ADDR_PC_2 => pc_current + lit(2, width: 16),
            ADDR_OPERAND => effective_operand,  # 8-bit operand address
            ADDR_OPERAND_16 => operand_16,      # 16-bit operand address
            ADDR_SP => sp_out,                  # Stack pointer (8-bit, zero-extended)
            ADDR_SP_PLUS_1 => sp_out + lit(1, width: 8)  # SP+1 for RET pop
          }, default: pc_current)

          # Memory data out (for writes)
          mem_data_out <= mux(ctrl_data_out_sel == lit(0, width: 2),
            acc_out,      # Normal write: ACC value
            return_addr)  # CALL: return address

          # Return address for CALL (PC + instruction length)
          return_addr <= (pc_current + dec_instr_length)[7..0]

          # PC next value
          pc_next <= mux(ctrl_pc_inc_en,
            # Increment by instruction length
            pc_current + dec_instr_length,
            mux(ctrl_pc_load_en,
              # Load from branch/jump target
              case_select(dec_pc_src, {
                0 => pc_current + dec_instr_length,  # Sequential
                1 => effective_operand,              # Short jump (8-bit, may be embedded)
                2 => operand_16                      # Long jump (16-bit)
              }, default: pc_current),
              # For RET: load from memory data (popped from stack)
              mux(dec_ret, mem_data_latched, pc_current)))
        end
      end
    end
  end
end
