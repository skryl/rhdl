# Instruction Decoder - decodes opcode byte to control signals

module RHDL
  module HDL
    module CPU
      class InstructionDecoder < Component
        # ALU operation codes (must match ALU constants)
        OP_ADD = 0
        OP_SUB = 1
        OP_AND = 2
        OP_OR  = 3
        OP_XOR = 4
        OP_NOT = 5
        OP_MUL = 11
        OP_DIV = 12

        input :instruction, width: 8
        input :zero_flag

        # Control signals
        output :alu_op, width: 4       # ALU operation
        output :alu_src                # 0 = register, 1 = immediate
        output :reg_write              # Write to accumulator
        output :mem_read               # Read from memory
        output :mem_write              # Write to memory
        output :branch                 # Branch instruction
        output :jump                   # Unconditional jump
        output :pc_src, width: 2       # PC source: 0=+1, 1=operand, 2=long addr
        output :halt                   # Halt CPU
        output :call                   # Call instruction
        output :ret                    # Return instruction
        output :instr_length, width: 2 # 1, 2, or 3 bytes

        behavior do
          # Extract opcode nibble (high 4 bits: values 0-15)
          # 0=NOP, 1=LDA, 2=STA, 3=ADD, 4=SUB, 5=AND, 6=OR, 7=XOR,
          # 8=JZ, 9=JNZ, 10=LDI, 11=JMP, 12=CALL, 13=RET, 14=DIV, 15=special
          opcode = instruction[7..4]

          # alu_op: which ALU operation to perform
          # ADD=0, SUB=1, AND=2, OR=3, XOR=4, NOT=5, MUL=11, DIV=12
          alu_op <= case_select(opcode, {
            3 => 0,   # ADD
            4 => 1,   # SUB
            5 => 2,   # AND
            6 => 3,   # OR
            7 => 4,   # XOR
            14 => 12, # DIV
            15 => case_select(instruction, {
              0xF1 => 11, # MUL
              0xF2 => 5,  # NOT
              0xF3 => 1   # CMP (uses SUB)
            }, default: 0)
          }, default: 0)

          # alu_src: 0=register, 1=immediate
          # Only LDI (opcode 10) uses immediate
          alu_src <= mux(opcode == 10, 1, 0)

          # reg_write: write to accumulator
          # LDA(1), ADD(3), SUB(4), AND(5), OR(6), XOR(7), LDI(10), DIV(14)
          # For 0xF: MUL(0xF1), NOT(0xF2)
          reg_write <= case_select(opcode, {
            1 => 1,   # LDA
            3 => 1,   # ADD
            4 => 1,   # SUB
            5 => 1,   # AND
            6 => 1,   # OR
            7 => 1,   # XOR
            10 => 1,  # LDI
            14 => 1,  # DIV
            15 => mux((instruction == 0xF1) | (instruction == 0xF2), 1, 0)
          }, default: 0)

          # mem_read: read from memory
          # LDA(1), ADD(3), SUB(4), AND(5), OR(6), XOR(7), DIV(14)
          # For 0xF: MUL(0xF1), CMP(0xF3)
          mem_read <= case_select(opcode, {
            1 => 1,   # LDA
            3 => 1,   # ADD
            4 => 1,   # SUB
            5 => 1,   # AND
            6 => 1,   # OR
            7 => 1,   # XOR
            14 => 1,  # DIV
            15 => mux((instruction == 0xF1) | (instruction == 0xF3), 1, 0)
          }, default: 0)

          # mem_write: write to memory (STA = opcode 2)
          mem_write <= mux(opcode == 2, 1, 0)

          # branch: conditional branch
          # JZ(8), JNZ(9), JZ_LONG(0xF8), JNZ_LONG(0xFA)
          branch <= case_select(opcode, {
            8 => 1,   # JZ
            9 => 1,   # JNZ
            15 => mux((instruction == 0xF8) | (instruction == 0xFA), 1, 0)
          }, default: 0)

          # jump: unconditional jump
          # JMP(11), JMP_LONG(0xF9)
          jump <= case_select(opcode, {
            11 => 1,  # JMP
            15 => mux(instruction == 0xF9, 1, 0)
          }, default: 0)

          # pc_src: PC source selection (0=+1, 1=short operand, 2=long addr)
          # JZ: if zero then 1 else 0
          # JNZ: if not zero then 1 else 0
          # JMP: always 1
          # CALL: always 1
          # JZ_LONG: if zero then 2 else 0
          # JMP_LONG: always 2
          # JNZ_LONG: if not zero then 2 else 0
          pc_src <= case_select(opcode, {
            8 => mux(zero_flag, 1, 0),   # JZ
            9 => mux(zero_flag, 0, 1),   # JNZ (if NOT zero)
            11 => 1,                      # JMP
            12 => 1,                      # CALL
            15 => case_select(instruction, {
              0xF8 => mux(zero_flag, 2, 0),  # JZ_LONG
              0xF9 => 2,                      # JMP_LONG
              0xFA => mux(zero_flag, 0, 2)   # JNZ_LONG
            }, default: 0)
          }, default: 0)

          # halt: halt CPU (HLT = 0xF0)
          halt <= mux(instruction == 0xF0, 1, 0)

          # call: call instruction (CALL = opcode 12)
          call <= mux(opcode == 12, 1, 0)

          # ret: return instruction (RET = opcode 13)
          ret <= mux(opcode == 13, 1, 0)

          # instr_length: 1, 2, or 3 bytes
          # Most are 1 byte
          # LDI(10): 2 bytes
          # STA variants: 0x20=3 bytes, 0x21=2 bytes
          # For 0xF: MUL(0xF1)=2, CMP(0xF3)=2,
          #          JZ_LONG(0xF8)=3, JMP_LONG(0xF9)=3, JNZ_LONG(0xFA)=3
          instr_length <= case_select(opcode, {
            2 => case_select(instruction, {
              0x20 => 3,  # STA Indirect
              0x21 => 2   # STA Direct
            }, default: 1),
            10 => 2,      # LDI
            15 => case_select(instruction, {
              0xF1 => 2,  # MUL
              0xF3 => 2,  # CMP
              0xF8 => 3,  # JZ_LONG
              0xF9 => 3,  # JMP_LONG
              0xFA => 3   # JNZ_LONG
            }, default: 1)
          }, default: 1)
        end
      end
    end
  end
end
