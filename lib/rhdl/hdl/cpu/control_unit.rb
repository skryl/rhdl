# Control Unit - State machine that sequences instruction execution
# Synthesizable using Sequential DSL
# All instruction timing/sequencing is handled here, making the harness
# a simple memory interface with no control logic.

module RHDL
  module HDL
    module CPU
      class ControlUnit < SequentialComponent
        include RHDL::DSL::Behavior
        include RHDL::DSL::Sequential

        # CPU States
        S_RESET      = 0x00  # Reset sequence
        S_FETCH      = 0x01  # Fetch opcode from memory[PC]
        S_DECODE     = 0x02  # Decode instruction, determine next state
        S_FETCH_OP1  = 0x03  # Fetch first operand byte from memory[PC+1]
        S_FETCH_OP2  = 0x04  # Fetch second operand byte from memory[PC+2]
        S_READ_MEM   = 0x05  # Read memory operand (LDA, ADD, SUB, etc.)
        S_EXECUTE    = 0x06  # Execute ALU operation, update registers
        S_WRITE_MEM  = 0x07  # Write ACC to memory (STA direct)
        S_CALL_PUSH  = 0x08  # Push return address for CALL
        S_RET_POP    = 0x09  # Pop return address for RET
        S_READ_PTR_HI = 0x0A # Read indirect pointer high byte
        S_READ_PTR_LO = 0x0B # Read indirect pointer low byte
        S_WRITE_INDIRECT = 0x0C # Write ACC to indirect address
        S_HALT       = 0xFF  # CPU halted

        # Address select values
        ADDR_PC      = 0  # Program counter
        ADDR_PC_1    = 1  # PC + 1
        ADDR_PC_2    = 2  # PC + 2
        ADDR_OPERAND = 3  # Operand address (8-bit)
        ADDR_OPERAND_16 = 4  # Operand address (16-bit for indirect)
        ADDR_SP      = 5  # Stack pointer
        ADDR_SP_PLUS_1 = 6  # Stack pointer + 1 (for RET pop)
        ADDR_PTR_HI  = 7  # Address from operand_lo (pointer to high byte)
        ADDR_PTR_LO  = 8  # Address from operand_hi (pointer to low byte)
        ADDR_INDIRECT = 9 # Indirect 16-bit address

        input :clk
        input :rst

        # Decoded instruction signals from InstructionDecoder
        input :instr_length, width: 2    # 1, 2, or 3 bytes
        input :is_halt                   # HLT instruction
        input :is_call                   # CALL instruction
        input :is_ret                    # RET instruction
        input :is_branch                 # Branch instruction (JZ, JNZ)
        input :is_jump                   # Unconditional jump (JMP)
        input :is_lda                    # LDA/LDI instruction
        input :is_reg_write              # Writes to accumulator
        input :is_mem_write              # Writes to memory (STA)
        input :is_mem_read               # Reads from memory
        input :is_sta_indirect           # STA indirect addressing mode
        input :pc_src, width: 2          # PC source: 0=+len, 1=short, 2=long
        input :alu_src                   # 0=memory, 1=immediate

        # Stack status
        input :sp_empty                  # Stack is empty (can't pop)
        input :sp_full                   # Stack is full (can't push)

        # Control outputs
        output :state, width: 8          # Current state (for debugging)
        output :mem_addr_sel, width: 4   # Memory address source select (expanded for indirect)
        output :mem_read_en              # Memory read enable
        output :mem_write_en             # Memory write enable
        output :instr_latch_en           # Latch instruction register
        output :operand_lo_latch_en      # Latch operand low byte
        output :operand_hi_latch_en      # Latch operand high byte
        output :acc_load_en              # Load accumulator
        output :zero_flag_load_en        # Load zero flag
        output :pc_load_en               # Load program counter
        output :pc_inc_en                # Increment PC by instruction length
        output :sp_push_en               # Push stack pointer (decrement)
        output :sp_pop_en                # Pop stack pointer (increment)
        output :data_out_sel, width: 2   # Data output select: 0=ACC, 1=return_addr
        output :halted                   # CPU is halted
        output :done                     # Instruction complete (ready for next)
        output :mem_data_latch_en        # Latch memory data for ALU operations
        output :indirect_hi_latch_en     # Latch indirect address high byte
        output :indirect_lo_latch_en     # Latch indirect address low byte

        # State register
        sequential clock: :clk, reset: :rst, reset_values: { state: S_RESET } do
          # Decode next state
          decode_next = local(:decode_next,
            mux(is_halt,
              lit(S_HALT, width: 8),
              mux(instr_length == lit(1, width: 2),
                # 1-byte instruction
                mux(is_call,
                  mux(sp_full, lit(S_HALT, width: 8), lit(S_CALL_PUSH, width: 8)),
                  mux(is_ret,
                    mux(sp_empty, lit(S_HALT, width: 8), lit(S_RET_POP, width: 8)),
                    mux(is_mem_read,
                      lit(S_READ_MEM, width: 8),
                      mux(is_mem_write,
                        lit(S_WRITE_MEM, width: 8),
                        lit(S_EXECUTE, width: 8))))),
                # Multi-byte instruction: fetch operand(s)
                lit(S_FETCH_OP1, width: 8))),
            width: 8)

          # Fetch operand 1 next state
          fetch_op1_next = local(:fetch_op1_next,
            mux(instr_length == lit(3, width: 2),
              lit(S_FETCH_OP2, width: 8),
              mux(is_call,
                mux(sp_full, lit(S_HALT, width: 8), lit(S_CALL_PUSH, width: 8)),
                mux(is_mem_read,
                  lit(S_READ_MEM, width: 8),
                  mux(is_mem_write,
                    lit(S_WRITE_MEM, width: 8),
                    mux(alu_src, lit(S_EXECUTE, width: 8), lit(S_READ_MEM, width: 8)))))),
            width: 8)

          # Fetch operand 2 next state
          # For indirect STA, go to read pointer states; otherwise direct write or execute
          fetch_op2_next = local(:fetch_op2_next,
            mux(is_sta_indirect,
              lit(S_READ_PTR_HI, width: 8),  # Indirect STA: read pointer bytes first
              mux(is_mem_write,
                lit(S_WRITE_MEM, width: 8),
                lit(S_EXECUTE, width: 8))),
            width: 8)

          # State transition
          state <= case_select(state, {
            S_RESET => lit(S_FETCH, width: 8),
            S_FETCH => lit(S_DECODE, width: 8),
            S_DECODE => decode_next,
            S_FETCH_OP1 => fetch_op1_next,
            S_FETCH_OP2 => fetch_op2_next,
            S_READ_MEM => lit(S_EXECUTE, width: 8),
            S_EXECUTE => lit(S_FETCH, width: 8),
            S_WRITE_MEM => lit(S_FETCH, width: 8),
            S_CALL_PUSH => lit(S_EXECUTE, width: 8),
            S_RET_POP => lit(S_EXECUTE, width: 8),
            S_READ_PTR_HI => lit(S_READ_PTR_LO, width: 8),  # After reading hi byte, read lo
            S_READ_PTR_LO => lit(S_WRITE_INDIRECT, width: 8), # After reading lo, write
            S_WRITE_INDIRECT => lit(S_FETCH, width: 8),    # After indirect write, fetch next
            S_HALT => lit(S_HALT, width: 8)
          }, default: S_FETCH)
        end

        # Control signal behavior - combinational outputs based on state
        behavior do
          # mem_addr_sel: Memory address source
          mem_addr_sel <= case_select(state, {
            S_FETCH => lit(ADDR_PC, width: 4),
            S_FETCH_OP1 => lit(ADDR_PC_1, width: 4),
            S_FETCH_OP2 => lit(ADDR_PC_2, width: 4),
            S_READ_MEM => lit(ADDR_OPERAND, width: 4),
            S_WRITE_MEM => lit(ADDR_OPERAND, width: 4),
            S_CALL_PUSH => lit(ADDR_SP, width: 4),
            S_RET_POP => lit(ADDR_SP_PLUS_1, width: 4),
            S_READ_PTR_HI => lit(ADDR_PTR_HI, width: 4),  # Read from operand_lo address
            S_READ_PTR_LO => lit(ADDR_PTR_LO, width: 4),  # Read from operand_hi address
            S_WRITE_INDIRECT => lit(ADDR_INDIRECT, width: 4)  # Write to indirect address
          }, default: ADDR_PC)

          # mem_read_en: Read from memory
          mem_read_en <= case_select(state, {
            S_FETCH => lit(1, width: 1),
            S_FETCH_OP1 => lit(1, width: 1),
            S_FETCH_OP2 => lit(1, width: 1),
            S_READ_MEM => lit(1, width: 1),
            S_RET_POP => lit(1, width: 1),
            S_READ_PTR_HI => lit(1, width: 1),
            S_READ_PTR_LO => lit(1, width: 1)
          }, default: 0)

          # mem_write_en: Write to memory
          mem_write_en <= case_select(state, {
            S_WRITE_MEM => lit(1, width: 1),
            S_CALL_PUSH => lit(1, width: 1),
            S_WRITE_INDIRECT => lit(1, width: 1)
          }, default: 0)

          # instr_latch_en: Latch instruction register
          instr_latch_en <= (state == lit(S_FETCH, width: 8))

          # operand_lo_latch_en: Latch operand low byte
          operand_lo_latch_en <= (state == lit(S_FETCH_OP1, width: 8))

          # operand_hi_latch_en: Latch operand high byte
          operand_hi_latch_en <= (state == lit(S_FETCH_OP2, width: 8))

          # acc_load_en: Load accumulator (in EXECUTE state with reg_write)
          acc_load_en <= mux(state == lit(S_EXECUTE, width: 8), is_reg_write, 0)

          # zero_flag_load_en: Load zero flag (in EXECUTE state with reg_write)
          zero_flag_load_en <= mux(state == lit(S_EXECUTE, width: 8), is_reg_write, 0)

          # pc_inc_en: Increment PC after instruction fetch/decode
          # Don't increment for CALL (return addr calc), branches/jumps (pc_load handles),
          # or instructions that will halt
          no_inc = is_call | is_branch | is_jump | is_halt | (is_ret & sp_empty)
          pc_inc_en <= case_select(state, {
            S_DECODE => mux((instr_length == lit(1, width: 2)) & ~no_inc, 1, 0),
            S_FETCH_OP1 => mux((instr_length == lit(2, width: 2)) & ~no_inc, 1, 0),
            S_FETCH_OP2 => mux(~no_inc, 1, 0)
          }, default: 0)

          # pc_load_en: Load PC for branches/jumps (NOT for RET - handled separately)
          pc_load_en <= mux(state == lit(S_EXECUTE, width: 8),
            is_branch | is_jump | is_call,
            0)

          # sp_push_en: Push (decrement) stack pointer
          sp_push_en <= (state == lit(S_CALL_PUSH, width: 8))

          # sp_pop_en: Pop (increment) stack pointer
          sp_pop_en <= (state == lit(S_RET_POP, width: 8))

          # data_out_sel: Data output select (0=ACC, 1=return_addr)
          data_out_sel <= mux(state == lit(S_CALL_PUSH, width: 8), 1, 0)

          # halted: CPU is halted
          halted <= (state == lit(S_HALT, width: 8))

          # done: Instruction complete
          done <= case_select(state, {
            S_EXECUTE => lit(1, width: 1),
            S_WRITE_MEM => lit(1, width: 1)
          }, default: 0)

          # mem_data_latch_en: Latch memory data during READ_MEM or RET_POP
          mem_data_latch_en <= (state == lit(S_READ_MEM, width: 8)) | (state == lit(S_RET_POP, width: 8))

          # indirect_hi_latch_en: Latch indirect address high byte during S_READ_PTR_HI
          indirect_hi_latch_en <= (state == lit(S_READ_PTR_HI, width: 8))

          # indirect_lo_latch_en: Latch indirect address low byte during S_READ_PTR_LO
          indirect_lo_latch_en <= (state == lit(S_READ_PTR_LO, width: 8))
        end
      end
    end
  end
end
