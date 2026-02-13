# RV32I/RV32M RISC-V Constants and Encoding
# Based on RISC-V ISA specification

module RHDL
  module Examples
    module RISCV
  # Opcodes (7-bit field at bits [6:0])
  module Opcode
    LUI     = 0b0110111  # Load Upper Immediate
    AUIPC   = 0b0010111  # Add Upper Immediate to PC
    JAL     = 0b1101111  # Jump and Link
    JALR    = 0b1100111  # Jump and Link Register
    BRANCH  = 0b1100011  # Branch instructions
    LOAD    = 0b0000011  # Load instructions
    STORE   = 0b0100011  # Store instructions
    OP_IMM  = 0b0010011  # Immediate arithmetic
    OP      = 0b0110011  # Register-register arithmetic
    AMO     = 0b0101111  # Atomic memory operations (RV32A)
    MISC_MEM = 0b0001111 # FENCE instructions
    SYSTEM  = 0b1110011  # ECALL, EBREAK
  end

  # Funct3 values for ALU operations
  module Funct3
    # Arithmetic/Logic (OP and OP_IMM)
    ADD_SUB = 0b000
    SLL     = 0b001
    SLT     = 0b010
    SLTU    = 0b011
    XOR     = 0b100
    SRL_SRA = 0b101
    OR      = 0b110
    AND     = 0b111

    # Branch conditions
    BEQ     = 0b000
    BNE     = 0b001
    BLT     = 0b100
    BGE     = 0b101
    BLTU    = 0b110
    BGEU    = 0b111

    # Load/Store sizes
    BYTE    = 0b000
    HALF    = 0b001
    WORD    = 0b010
    BYTE_U  = 0b100
    HALF_U  = 0b101
  end

  # Funct7 values
  module Funct7
    NORMAL  = 0b0000000
    ALT     = 0b0100000  # SUB, SRA
    M_EXT   = 0b0000001  # MUL/DIV/REM family
  end

  # ALU operation codes (internal)
  module AluOp
    ADD   = 0
    SUB   = 1
    SLL   = 2
    SLT   = 3
    SLTU  = 4
    XOR   = 5
    SRL   = 6
    SRA   = 7
    OR    = 8
    AND   = 9
    PASS_A = 10  # Pass through A (for LUI)
    PASS_B = 11  # Pass through B (for AUIPC)
    MUL    = 12
    MULH   = 13
    MULHSU = 14
    MULHU  = 15
    DIV    = 16
    DIVU   = 17
    REM    = 18
    REMU   = 19
  end

  # Instruction format types
  module InstType
    R_TYPE = 0
    I_TYPE = 1
    S_TYPE = 2
    B_TYPE = 3
    U_TYPE = 4
    J_TYPE = 5
  end

  # Control signals for register write source
  module WBSrc
    ALU    = 0  # ALU result
    MEM    = 1  # Memory read data
    PC4    = 2  # PC + 4 (for JAL/JALR)
    IMM    = 3  # Immediate (for LUI)
  end

  # PC source selection
  module PCSrc
    PC4    = 0  # PC + 4 (normal)
    BRANCH = 1  # Branch target
    JAL    = 2  # JAL target
    JALR   = 3  # JALR target
  end

  # Privilege modes
  module PrivMode
    USER       = 0b00
    SUPERVISOR = 0b01
    MACHINE    = 0b11
  end
    end
  end
end
