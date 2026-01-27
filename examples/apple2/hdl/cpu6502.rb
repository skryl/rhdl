# frozen_string_literal: true

# MOS 6502 CPU - HDL Implementation
# Based on Peter Wendrich's table-driven, cycle-exact 6502/6510 core
# Ported from cpu6502.vhd (FPGA-64 project, Stephen Edwards' neoapple2)
#
# This is a cycle-accurate implementation of the 6502 processor,
# using a table-driven approach for opcode decoding.

require 'rhdl/hdl'

module RHDL
  module Apple2
    class CPU6502 < RHDL::HDL::SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential
      include RHDL::DSL::Memory

      # Clock and control
      input :clk
      input :enable
      input :reset

      # Interrupt inputs (active low)
      input :nmi_n
      input :irq_n
      input :so_n                              # Set overflow

      # Data bus
      input :di, width: 8                      # Data in from memory
      output :do_out, width: 8                 # Data out to memory
      output :addr, width: 16                  # Address bus
      output :we                               # Write enable

      # Debug outputs
      output :debug_opcode, width: 8
      output :debug_pc, width: 16
      output :debug_a, width: 8
      output :debug_x, width: 8
      output :debug_y, width: 8
      output :debug_s, width: 8
      output :debug_p, width: 8
      output :debug_second_byte
      output :debug_cycle2
      output :debug_addr_c2, width: 16
      output :debug_opc_info, width: 48

      # CPU state machine states
      STATE_OPCODE_FETCH   = 0
      STATE_CYCLE2         = 1
      STATE_CYCLE3         = 2
      STATE_PRE_INDIRECT   = 3
      STATE_INDIRECT       = 4
      STATE_BRANCH_TAKEN   = 5
      STATE_BRANCH_PAGE    = 6
      STATE_PRE_READ       = 7
      STATE_READ           = 8
      STATE_READ2          = 9
      STATE_RMW            = 10
      STATE_PRE_WRITE      = 11
      STATE_WRITE          = 12
      STATE_STACK1         = 13
      STATE_STACK2         = 14
      STATE_STACK3         = 15
      STATE_STACK4         = 16
      STATE_JUMP           = 17
      STATE_END            = 18

      # Opcode decode flags (bit positions in opcInfo)
      OPC_UPDATE_A    = 0
      OPC_UPDATE_X    = 1
      OPC_UPDATE_Y    = 2
      OPC_UPDATE_S    = 3
      OPC_UPDATE_N    = 4
      OPC_UPDATE_V    = 5
      OPC_UPDATE_D    = 6
      OPC_UPDATE_I    = 7
      OPC_UPDATE_Z    = 8
      OPC_UPDATE_C    = 9
      OPC_SECOND_BYTE = 10
      OPC_ABSOLUTE    = 11
      OPC_ZEROPAGE    = 12
      OPC_INDIRECT    = 13
      OPC_STACK_ADDR  = 14
      OPC_STACK_DATA  = 15
      OPC_JUMP        = 16
      OPC_BRANCH      = 17
      OPC_INDEX_X     = 18
      OPC_INDEX_Y     = 19
      OPC_STACK_UP    = 20
      OPC_WRITE       = 21
      OPC_RMW         = 22
      OPC_INCR_AFTER  = 23
      OPC_RTI         = 24
      OPC_IRQ         = 25
      OPC_IN_A        = 26
      OPC_IN_E        = 27
      OPC_IN_X        = 28
      OPC_IN_Y        = 29
      OPC_IN_S        = 30
      OPC_IN_T        = 31
      OPC_IN_H        = 32
      OPC_IN_CLEAR    = 33
      ALU_MODE1_START = 34
      ALU_MODE1_END   = 37
      ALU_MODE2_START = 38
      ALU_MODE2_END   = 40
      OPC_IN_CMP      = 41
      OPC_IN_CPX      = 42
      OPC_IN_CPY      = 43

      # ALU Mode 1 (shift/logic unit)
      ALU1_INP = 0b0000
      ALU1_P   = 0b0001
      ALU1_INC = 0b0010
      ALU1_DEC = 0b0011
      ALU1_FLG = 0b0100
      ALU1_BIT = 0b0101
      ALU1_LSR = 0b1000
      ALU1_ROR = 0b1001
      ALU1_ASL = 0b1010
      ALU1_ROL = 0b1011
      ALU1_ANC = 0b1111

      # ALU Mode 2 (arithmetic unit)
      ALU2_PSS = 0b000
      ALU2_CMP = 0b001
      ALU2_ADC = 0b010
      ALU2_SBC = 0b011
      ALU2_AND = 0b100
      ALU2_ORA = 0b101
      ALU2_EOR = 0b110
      ALU2_ARR = 0b111

      # Address modes (encoded)
      ADDR_IMPLIED    = 0b0000_0000_0000_0000
      ADDR_IMMEDIATE  = 0b1000_0000_0000_0000
      ADDR_READ_ZP    = 0b1010_0000_0000_0000
      ADDR_WRITE_ZP   = 0b1010_0000_0001_0000
      ADDR_RMW_ZP     = 0b1010_0000_0000_1000
      ADDR_READ_ZPX   = 0b1010_0000_1000_0000
      ADDR_WRITE_ZPX  = 0b1010_0000_1001_0000
      ADDR_RMW_ZPX    = 0b1010_0000_1000_1000
      ADDR_READ_ZPY   = 0b1010_0000_0100_0000
      ADDR_WRITE_ZPY  = 0b1010_0000_0101_0000
      ADDR_READ_INDX  = 0b1001_0000_1000_0000
      ADDR_WRITE_INDX = 0b1001_0000_1001_0000
      ADDR_RMW_INDX   = 0b1001_0000_1000_1000
      ADDR_READ_INDY  = 0b1001_0000_0100_0000
      ADDR_WRITE_INDY = 0b1001_0000_0101_0000
      ADDR_RMW_INDY   = 0b1001_0000_0100_1000
      ADDR_READ_ABS   = 0b1100_0000_0000_0000
      ADDR_WRITE_ABS  = 0b1100_0000_0001_0000
      ADDR_RMW_ABS    = 0b1100_0000_0000_1000
      ADDR_READ_ABSX  = 0b1100_0000_1000_0000
      ADDR_WRITE_ABSX = 0b1100_0000_1001_0000
      ADDR_RMW_ABSX   = 0b1100_0000_1000_1000
      ADDR_READ_ABSY  = 0b1100_0000_0100_0000
      ADDR_WRITE_ABSY = 0b1100_0000_0101_0000
      ADDR_RMW_ABSY   = 0b1100_0000_0100_1000
      ADDR_PUSH       = 0b0000_0100_0000_0000
      ADDR_POP        = 0b0000_0100_0010_0000
      ADDR_JSR        = 0b1000_1010_0000_0000
      ADDR_JUMP_ABS   = 0b1000_0010_0000_0000
      ADDR_JUMP_IND   = 0b1100_0010_0000_0000
      ADDR_RELATIVE   = 0b1000_0001_0000_0000
      ADDR_RTS        = 0b0000_1010_0010_0100
      ADDR_RTI        = 0b0000_1110_0010_0010
      ADDR_BRK        = 0b1000_1110_0000_0001

      # ALU input selections
      ALU_IN_A     = 0b1000_0000
      ALU_IN_E     = 0b0100_0000
      ALU_IN_EXT   = 0b0110_0100
      ALU_IN_ET    = 0b0100_0100
      ALU_IN_X     = 0b0010_0000
      ALU_IN_XH    = 0b0010_0010
      ALU_IN_Y     = 0b0001_0000
      ALU_IN_YH    = 0b0001_0010
      ALU_IN_S     = 0b0000_1000
      ALU_IN_T     = 0b0000_0100
      ALU_IN_AX    = 0b1010_0000
      ALU_IN_AXH   = 0b1010_0010
      ALU_IN_AT    = 0b1000_0100
      ALU_IN_XT    = 0b0010_0100
      ALU_IN_ST    = 0b0000_1100
      ALU_IN_SET   = 0b0000_0000
      ALU_IN_CLR   = 0b0000_0001

      # Build the opcode decode table (256 entries)
      # Each entry encodes: reg updates, flag updates, addressing mode, alu input, alu mode
      def self.build_opcode_table
        table = Array.new(256) { 0 }

        # Helper to encode an opcode entry
        # regs: AXYS (4 bits), flags: NVDIZC (6 bits), addr: 16 bits, aluIn: 8 bits, aluMode: 10 bits
        encode = lambda do |regs, flags, addr, alu_in, alu1, alu2, cmp_flags = 0|
          entry = 0
          entry |= ((regs >> 3) & 1) << OPC_UPDATE_A
          entry |= ((regs >> 2) & 1) << OPC_UPDATE_X
          entry |= ((regs >> 1) & 1) << OPC_UPDATE_Y
          entry |= (regs & 1) << OPC_UPDATE_S
          entry |= ((flags >> 5) & 1) << OPC_UPDATE_N
          entry |= ((flags >> 4) & 1) << OPC_UPDATE_V
          entry |= ((flags >> 3) & 1) << OPC_UPDATE_D
          entry |= ((flags >> 2) & 1) << OPC_UPDATE_I
          entry |= ((flags >> 1) & 1) << OPC_UPDATE_Z
          entry |= (flags & 1) << OPC_UPDATE_C

          # Address mode bits
          entry |= ((addr >> 15) & 1) << OPC_SECOND_BYTE
          entry |= ((addr >> 14) & 1) << OPC_ABSOLUTE
          entry |= ((addr >> 13) & 1) << OPC_ZEROPAGE
          entry |= ((addr >> 12) & 1) << OPC_INDIRECT
          entry |= ((addr >> 11) & 1) << OPC_STACK_ADDR
          entry |= ((addr >> 10) & 1) << OPC_STACK_DATA
          entry |= ((addr >> 9) & 1) << OPC_JUMP
          entry |= ((addr >> 8) & 1) << OPC_BRANCH
          entry |= ((addr >> 7) & 1) << OPC_INDEX_X
          entry |= ((addr >> 6) & 1) << OPC_INDEX_Y
          entry |= ((addr >> 5) & 1) << OPC_STACK_UP
          entry |= ((addr >> 4) & 1) << OPC_WRITE
          entry |= ((addr >> 3) & 1) << OPC_RMW
          entry |= ((addr >> 2) & 1) << OPC_INCR_AFTER
          entry |= ((addr >> 1) & 1) << OPC_RTI
          entry |= (addr & 1) << OPC_IRQ

          # ALU input selection
          entry |= ((alu_in >> 7) & 1) << OPC_IN_A
          entry |= ((alu_in >> 6) & 1) << OPC_IN_E
          entry |= ((alu_in >> 5) & 1) << OPC_IN_X
          entry |= ((alu_in >> 4) & 1) << OPC_IN_Y
          entry |= ((alu_in >> 3) & 1) << OPC_IN_S
          entry |= ((alu_in >> 2) & 1) << OPC_IN_T
          entry |= ((alu_in >> 1) & 1) << OPC_IN_H
          entry |= (alu_in & 1) << OPC_IN_CLEAR

          # ALU mode
          entry |= (alu1 & 0xF) << ALU_MODE1_START
          entry |= (alu2 & 0x7) << ALU_MODE2_START

          # CMP input flags
          entry |= ((cmp_flags >> 2) & 1) << OPC_IN_CMP
          entry |= ((cmp_flags >> 1) & 1) << OPC_IN_CPX
          entry |= (cmp_flags & 1) << OPC_IN_CPY

          entry
        end

        # Shorthand for common patterns
        nop = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)

        # 0x00 - 0x0F
        table[0x00] = encode.call(0b0000, 0b000100, ADDR_BRK, 0, ALU1_P, ALU2_PSS)           # BRK
        table[0x01] = encode.call(0b1000, 0b100010, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_ORA)  # ORA (zp,x)
        table[0x02] = nop  # JAM
        table[0x03] = nop  # iSLO (zp,x) - illegal
        table[0x04] = encode.call(0, 0, ADDR_READ_ZP, 0, ALU1_INP, ALU2_PSS)  # iNOP zp
        table[0x05] = encode.call(0b1000, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_ORA)    # ORA zp
        table[0x06] = encode.call(0b0000, 0b100011, ADDR_RMW_ZP, ALU_IN_T, ALU1_ASL, ALU2_PSS)     # ASL zp
        table[0x07] = nop  # iSLO zp - illegal
        table[0x08] = encode.call(0, 0, ADDR_PUSH, 0, ALU1_P, ALU2_PSS)                           # PHP
        table[0x09] = encode.call(0b1000, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_ORA)  # ORA imm
        table[0x0A] = encode.call(0b1000, 0b100011, ADDR_IMPLIED, ALU_IN_A, ALU1_ASL, ALU2_PSS)    # ASL A
        table[0x0B] = nop  # iANC imm - illegal
        table[0x0C] = encode.call(0, 0, ADDR_READ_ABS, 0, ALU1_INP, ALU2_PSS)  # iNOP abs
        table[0x0D] = encode.call(0b1000, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_ORA)   # ORA abs
        table[0x0E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABS, ALU_IN_T, ALU1_ASL, ALU2_PSS)    # ASL abs
        table[0x0F] = nop  # iSLO abs - illegal

        # 0x10 - 0x1F
        table[0x10] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BPL
        table[0x11] = encode.call(0b1000, 0b100010, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_ORA)  # ORA (zp),y
        table[0x12] = nop  # JAM
        table[0x13] = nop  # iSLO (zp),y - illegal
        table[0x14] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0x15] = encode.call(0b1000, 0b100010, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_ORA)   # ORA zp,x
        table[0x16] = encode.call(0b0000, 0b100011, ADDR_RMW_ZPX, ALU_IN_T, ALU1_ASL, ALU2_PSS)    # ASL zp,x
        table[0x17] = nop  # iSLO zp,x - illegal
        table[0x18] = encode.call(0, 0b000001, ADDR_IMPLIED, ALU_IN_CLR, ALU1_FLG, ALU2_PSS)       # CLC
        table[0x19] = encode.call(0b1000, 0b100010, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_ORA)  # ORA abs,y
        table[0x1A] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0x1B] = nop  # iSLO abs,y - illegal
        table[0x1C] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0x1D] = encode.call(0b1000, 0b100010, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_ORA)  # ORA abs,x
        table[0x1E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABSX, ALU_IN_T, ALU1_ASL, ALU2_PSS)   # ASL abs,x
        table[0x1F] = nop  # iSLO abs,x - illegal

        # 0x20 - 0x2F
        table[0x20] = encode.call(0, 0, ADDR_JSR, 0, ALU1_INP, ALU2_PSS)                           # JSR
        table[0x21] = encode.call(0b1000, 0b100010, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_AND)  # AND (zp,x)
        table[0x22] = nop  # JAM
        table[0x23] = nop  # iRLA (zp,x) - illegal
        table[0x24] = encode.call(0, 0b110010, ADDR_READ_ZP, ALU_IN_T, ALU1_BIT, ALU2_AND)         # BIT zp
        table[0x25] = encode.call(0b1000, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_AND)    # AND zp
        table[0x26] = encode.call(0b0000, 0b100011, ADDR_RMW_ZP, ALU_IN_T, ALU1_ROL, ALU2_PSS)     # ROL zp
        table[0x27] = nop  # iRLA zp - illegal
        table[0x28] = encode.call(0, 0b111111, ADDR_POP, ALU_IN_T, ALU1_FLG, ALU2_PSS)             # PLP
        table[0x29] = encode.call(0b1000, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_AND)  # AND imm
        table[0x2A] = encode.call(0b1000, 0b100011, ADDR_IMPLIED, ALU_IN_A, ALU1_ROL, ALU2_PSS)    # ROL A
        table[0x2B] = nop  # iANC imm - illegal
        table[0x2C] = encode.call(0, 0b110010, ADDR_READ_ABS, ALU_IN_T, ALU1_BIT, ALU2_AND)        # BIT abs
        table[0x2D] = encode.call(0b1000, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_AND)   # AND abs
        table[0x2E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABS, ALU_IN_T, ALU1_ROL, ALU2_PSS)    # ROL abs
        table[0x2F] = nop  # iRLA abs - illegal

        # 0x30 - 0x3F
        table[0x30] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BMI
        table[0x31] = encode.call(0b1000, 0b100010, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_AND)  # AND (zp),y
        table[0x32] = nop  # JAM
        table[0x33] = nop  # iRLA (zp),y - illegal
        table[0x34] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0x35] = encode.call(0b1000, 0b100010, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_AND)   # AND zp,x
        table[0x36] = encode.call(0b0000, 0b100011, ADDR_RMW_ZPX, ALU_IN_T, ALU1_ROL, ALU2_PSS)    # ROL zp,x
        table[0x37] = nop  # iRLA zp,x - illegal
        table[0x38] = encode.call(0, 0b000001, ADDR_IMPLIED, ALU_IN_SET, ALU1_FLG, ALU2_PSS)       # SEC
        table[0x39] = encode.call(0b1000, 0b100010, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_AND)  # AND abs,y
        table[0x3A] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0x3B] = nop  # iRLA abs,y - illegal
        table[0x3C] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0x3D] = encode.call(0b1000, 0b100010, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_AND)  # AND abs,x
        table[0x3E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABSX, ALU_IN_T, ALU1_ROL, ALU2_PSS)   # ROL abs,x
        table[0x3F] = nop  # iRLA abs,x - illegal

        # 0x40 - 0x4F
        table[0x40] = encode.call(0, 0b111111, ADDR_RTI, ALU_IN_T, ALU1_FLG, ALU2_PSS)             # RTI
        table[0x41] = encode.call(0b1000, 0b100010, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_EOR)  # EOR (zp,x)
        table[0x42] = nop  # JAM
        table[0x43] = nop  # iSRE (zp,x) - illegal
        table[0x44] = encode.call(0, 0, ADDR_READ_ZP, 0, ALU1_INP, ALU2_PSS)  # iNOP zp
        table[0x45] = encode.call(0b1000, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_EOR)    # EOR zp
        table[0x46] = encode.call(0b0000, 0b100011, ADDR_RMW_ZP, ALU_IN_T, ALU1_LSR, ALU2_PSS)     # LSR zp
        table[0x47] = nop  # iSRE zp - illegal
        table[0x48] = encode.call(0, 0, ADDR_PUSH, ALU_IN_A, ALU1_INP, ALU2_PSS)                   # PHA
        table[0x49] = encode.call(0b1000, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_EOR)  # EOR imm
        table[0x4A] = encode.call(0b1000, 0b100011, ADDR_IMPLIED, ALU_IN_A, ALU1_LSR, ALU2_PSS)    # LSR A
        table[0x4B] = nop  # iALR imm - illegal
        table[0x4C] = encode.call(0, 0, ADDR_JUMP_ABS, 0, ALU1_INP, ALU2_PSS)                      # JMP abs
        table[0x4D] = encode.call(0b1000, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_EOR)   # EOR abs
        table[0x4E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABS, ALU_IN_T, ALU1_LSR, ALU2_PSS)    # LSR abs
        table[0x4F] = nop  # iSRE abs - illegal

        # 0x50 - 0x5F
        table[0x50] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BVC
        table[0x51] = encode.call(0b1000, 0b100010, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_EOR)  # EOR (zp),y
        table[0x52] = nop  # JAM
        table[0x53] = nop  # iSRE (zp),y - illegal
        table[0x54] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0x55] = encode.call(0b1000, 0b100010, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_EOR)   # EOR zp,x
        table[0x56] = encode.call(0b0000, 0b100011, ADDR_RMW_ZPX, ALU_IN_T, ALU1_LSR, ALU2_PSS)    # LSR zp,x
        table[0x57] = nop  # iSRE zp,x - illegal
        table[0x58] = encode.call(0, 0b000100, ADDR_IMPLIED, ALU_IN_CLR, ALU1_INP, ALU2_PSS)       # CLI
        table[0x59] = encode.call(0b1000, 0b100010, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_EOR)  # EOR abs,y
        table[0x5A] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0x5B] = nop  # iSRE abs,y - illegal
        table[0x5C] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0x5D] = encode.call(0b1000, 0b100010, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_EOR)  # EOR abs,x
        table[0x5E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABSX, ALU_IN_T, ALU1_LSR, ALU2_PSS)   # LSR abs,x
        table[0x5F] = nop  # iSRE abs,x - illegal

        # 0x60 - 0x6F
        table[0x60] = encode.call(0, 0, ADDR_RTS, 0, ALU1_INP, ALU2_PSS)                           # RTS
        table[0x61] = encode.call(0b1000, 0b110011, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_ADC)  # ADC (zp,x)
        table[0x62] = nop  # JAM
        table[0x63] = nop  # iRRA (zp,x) - illegal
        table[0x64] = encode.call(0, 0, ADDR_READ_ZP, 0, ALU1_INP, ALU2_PSS)  # iNOP zp
        table[0x65] = encode.call(0b1000, 0b110011, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_ADC)    # ADC zp
        table[0x66] = encode.call(0b0000, 0b100011, ADDR_RMW_ZP, ALU_IN_T, ALU1_ROR, ALU2_PSS)     # ROR zp
        table[0x67] = nop  # iRRA zp - illegal
        table[0x68] = encode.call(0b1000, 0b100010, ADDR_POP, ALU_IN_T, ALU1_INP, ALU2_PSS)        # PLA
        table[0x69] = encode.call(0b1000, 0b110011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_ADC)  # ADC imm
        table[0x6A] = encode.call(0b1000, 0b100011, ADDR_IMPLIED, ALU_IN_A, ALU1_ROR, ALU2_PSS)    # ROR A
        table[0x6B] = nop  # iARR imm - illegal
        table[0x6C] = encode.call(0, 0, ADDR_JUMP_IND, 0, ALU1_INP, ALU2_PSS)                      # JMP (ind)
        table[0x6D] = encode.call(0b1000, 0b110011, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_ADC)   # ADC abs
        table[0x6E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABS, ALU_IN_T, ALU1_ROR, ALU2_PSS)    # ROR abs
        table[0x6F] = nop  # iRRA abs - illegal

        # 0x70 - 0x7F
        table[0x70] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BVS
        table[0x71] = encode.call(0b1000, 0b110011, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_ADC)  # ADC (zp),y
        table[0x72] = nop  # JAM
        table[0x73] = nop  # iRRA (zp),y - illegal
        table[0x74] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0x75] = encode.call(0b1000, 0b110011, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_ADC)   # ADC zp,x
        table[0x76] = encode.call(0b0000, 0b100011, ADDR_RMW_ZPX, ALU_IN_T, ALU1_ROR, ALU2_PSS)    # ROR zp,x
        table[0x77] = nop  # iRRA zp,x - illegal
        table[0x78] = encode.call(0, 0b000100, ADDR_IMPLIED, ALU_IN_SET, ALU1_INP, ALU2_PSS)       # SEI
        table[0x79] = encode.call(0b1000, 0b110011, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_ADC)  # ADC abs,y
        table[0x7A] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0x7B] = nop  # iRRA abs,y - illegal
        table[0x7C] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0x7D] = encode.call(0b1000, 0b110011, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_ADC)  # ADC abs,x
        table[0x7E] = encode.call(0b0000, 0b100011, ADDR_RMW_ABSX, ALU_IN_T, ALU1_ROR, ALU2_PSS)   # ROR abs,x
        table[0x7F] = nop  # iRRA abs,x - illegal

        # 0x80 - 0x8F
        table[0x80] = encode.call(0, 0, ADDR_IMMEDIATE, 0, ALU1_INP, ALU2_PSS)  # iNOP imm
        table[0x81] = encode.call(0, 0, ADDR_WRITE_INDX, ALU_IN_A, ALU1_INP, ALU2_PSS)             # STA (zp,x)
        table[0x82] = encode.call(0, 0, ADDR_IMMEDIATE, 0, ALU1_INP, ALU2_PSS)  # iNOP imm
        table[0x83] = nop  # iSAX (zp,x) - illegal
        table[0x84] = encode.call(0, 0, ADDR_WRITE_ZP, ALU_IN_Y, ALU1_INP, ALU2_PSS)               # STY zp
        table[0x85] = encode.call(0, 0, ADDR_WRITE_ZP, ALU_IN_A, ALU1_INP, ALU2_PSS)               # STA zp
        table[0x86] = encode.call(0, 0, ADDR_WRITE_ZP, ALU_IN_X, ALU1_INP, ALU2_PSS)               # STX zp
        table[0x87] = nop  # iSAX zp - illegal
        table[0x88] = encode.call(0b0010, 0b100010, ADDR_IMPLIED, ALU_IN_Y, ALU1_DEC, ALU2_PSS)    # DEY
        table[0x89] = encode.call(0, 0, ADDR_IMMEDIATE, 0, ALU1_INP, ALU2_PSS)  # iNOP imm
        table[0x8A] = encode.call(0b1000, 0b100010, ADDR_IMPLIED, ALU_IN_X, ALU1_INP, ALU2_PSS)    # TXA
        table[0x8B] = nop  # iANE imm - illegal
        table[0x8C] = encode.call(0, 0, ADDR_WRITE_ABS, ALU_IN_Y, ALU1_INP, ALU2_PSS)              # STY abs
        table[0x8D] = encode.call(0, 0, ADDR_WRITE_ABS, ALU_IN_A, ALU1_INP, ALU2_PSS)              # STA abs
        table[0x8E] = encode.call(0, 0, ADDR_WRITE_ABS, ALU_IN_X, ALU1_INP, ALU2_PSS)              # STX abs
        table[0x8F] = nop  # iSAX abs - illegal

        # 0x90 - 0x9F
        table[0x90] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BCC
        table[0x91] = encode.call(0, 0, ADDR_WRITE_INDY, ALU_IN_A, ALU1_INP, ALU2_PSS)             # STA (zp),y
        table[0x92] = nop  # JAM
        table[0x93] = nop  # iAHX (zp),y - illegal
        table[0x94] = encode.call(0, 0, ADDR_WRITE_ZPX, ALU_IN_Y, ALU1_INP, ALU2_PSS)              # STY zp,x
        table[0x95] = encode.call(0, 0, ADDR_WRITE_ZPX, ALU_IN_A, ALU1_INP, ALU2_PSS)              # STA zp,x
        table[0x96] = encode.call(0, 0, ADDR_WRITE_ZPY, ALU_IN_X, ALU1_INP, ALU2_PSS)              # STX zp,y
        table[0x97] = nop  # iSAX zp,y - illegal
        table[0x98] = encode.call(0b1000, 0b100010, ADDR_IMPLIED, ALU_IN_Y, ALU1_INP, ALU2_PSS)    # TYA
        table[0x99] = encode.call(0, 0, ADDR_WRITE_ABSY, ALU_IN_A, ALU1_INP, ALU2_PSS)             # STA abs,y
        table[0x9A] = encode.call(0b0001, 0, ADDR_IMPLIED, ALU_IN_X, ALU1_INP, ALU2_PSS)           # TXS
        table[0x9B] = nop  # iSHS abs,y - illegal
        table[0x9C] = nop  # iSHY abs,x - illegal
        table[0x9D] = encode.call(0, 0, ADDR_WRITE_ABSX, ALU_IN_A, ALU1_INP, ALU2_PSS)             # STA abs,x
        table[0x9E] = nop  # iSHX abs,y - illegal
        table[0x9F] = nop  # iAHX abs,y - illegal

        # 0xA0 - 0xAF
        table[0xA0] = encode.call(0b0010, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDY imm
        table[0xA1] = encode.call(0b1000, 0b100010, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDA (zp,x)
        table[0xA2] = encode.call(0b0100, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDX imm
        table[0xA3] = nop  # iLAX (zp,x) - illegal
        table[0xA4] = encode.call(0b0010, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_PSS)    # LDY zp
        table[0xA5] = encode.call(0b1000, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_PSS)    # LDA zp
        table[0xA6] = encode.call(0b0100, 0b100010, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_PSS)    # LDX zp
        table[0xA7] = nop  # iLAX zp - illegal
        table[0xA8] = encode.call(0b0010, 0b100010, ADDR_IMPLIED, ALU_IN_A, ALU1_INP, ALU2_PSS)    # TAY
        table[0xA9] = encode.call(0b1000, 0b100010, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDA imm
        table[0xAA] = encode.call(0b0100, 0b100010, ADDR_IMPLIED, ALU_IN_A, ALU1_INP, ALU2_PSS)    # TAX
        table[0xAB] = nop  # iLXA imm - illegal
        table[0xAC] = encode.call(0b0010, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDY abs
        table[0xAD] = encode.call(0b1000, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDA abs
        table[0xAE] = encode.call(0b0100, 0b100010, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDX abs
        table[0xAF] = nop  # iLAX abs - illegal

        # 0xB0 - 0xBF
        table[0xB0] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BCS
        table[0xB1] = encode.call(0b1000, 0b100010, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDA (zp),y
        table[0xB2] = nop  # JAM
        table[0xB3] = nop  # iLAX (zp),y - illegal
        table[0xB4] = encode.call(0b0010, 0b100010, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDY zp,x
        table[0xB5] = encode.call(0b1000, 0b100010, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDA zp,x
        table[0xB6] = encode.call(0b0100, 0b100010, ADDR_READ_ZPY, ALU_IN_T, ALU1_INP, ALU2_PSS)   # LDX zp,y
        table[0xB7] = nop  # iLAX zp,y - illegal
        table[0xB8] = encode.call(0, 0b010000, ADDR_IMPLIED, ALU_IN_CLR, ALU1_FLG, ALU2_PSS)       # CLV
        table[0xB9] = encode.call(0b1000, 0b100010, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDA abs,y
        table[0xBA] = encode.call(0b0100, 0b100010, ADDR_IMPLIED, ALU_IN_S, ALU1_INP, ALU2_PSS)    # TSX
        table[0xBB] = nop  # iLAS abs,y - illegal
        table[0xBC] = encode.call(0b0010, 0b100010, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDY abs,x
        table[0xBD] = encode.call(0b1000, 0b100010, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDA abs,x
        table[0xBE] = encode.call(0b0100, 0b100010, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_PSS)  # LDX abs,y
        table[0xBF] = nop  # iLAX abs,y - illegal

        # 0xC0 - 0xCF
        table[0xC0] = encode.call(0, 0b100011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b001)  # CPY imm
        table[0xC1] = encode.call(0, 0b100011, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)  # CMP (zp,x)
        table[0xC2] = encode.call(0, 0, ADDR_IMMEDIATE, 0, ALU1_INP, ALU2_PSS)  # iNOP imm
        table[0xC3] = nop  # iDCP (zp,x) - illegal
        table[0xC4] = encode.call(0, 0b100011, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b001)    # CPY zp
        table[0xC5] = encode.call(0, 0b100011, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)    # CMP zp
        table[0xC6] = encode.call(0, 0b100010, ADDR_RMW_ZP, ALU_IN_T, ALU1_DEC, ALU2_PSS)            # DEC zp
        table[0xC7] = nop  # iDCP zp - illegal
        table[0xC8] = encode.call(0b0010, 0b100010, ADDR_IMPLIED, ALU_IN_Y, ALU1_INC, ALU2_PSS)      # INY
        table[0xC9] = encode.call(0, 0b100011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)  # CMP imm
        table[0xCA] = encode.call(0b0100, 0b100010, ADDR_IMPLIED, ALU_IN_X, ALU1_DEC, ALU2_PSS)      # DEX
        table[0xCB] = nop  # iSBX imm - illegal
        table[0xCC] = encode.call(0, 0b100011, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b001)   # CPY abs
        table[0xCD] = encode.call(0, 0b100011, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)   # CMP abs
        table[0xCE] = encode.call(0, 0b100010, ADDR_RMW_ABS, ALU_IN_T, ALU1_DEC, ALU2_PSS)           # DEC abs
        table[0xCF] = nop  # iDCP abs - illegal

        # 0xD0 - 0xDF
        table[0xD0] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BNE
        table[0xD1] = encode.call(0, 0b100011, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)  # CMP (zp),y
        table[0xD2] = nop  # JAM
        table[0xD3] = nop  # iDCP (zp),y - illegal
        table[0xD4] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0xD5] = encode.call(0, 0b100011, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)   # CMP zp,x
        table[0xD6] = encode.call(0, 0b100010, ADDR_RMW_ZPX, ALU_IN_T, ALU1_DEC, ALU2_PSS)           # DEC zp,x
        table[0xD7] = nop  # iDCP zp,x - illegal
        table[0xD8] = encode.call(0, 0b001000, ADDR_IMPLIED, ALU_IN_CLR, ALU1_INP, ALU2_PSS)         # CLD
        table[0xD9] = encode.call(0, 0b100011, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)  # CMP abs,y
        table[0xDA] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0xDB] = nop  # iDCP abs,y - illegal
        table[0xDC] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0xDD] = encode.call(0, 0b100011, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b100)  # CMP abs,x
        table[0xDE] = encode.call(0, 0b100010, ADDR_RMW_ABSX, ALU_IN_T, ALU1_DEC, ALU2_PSS)          # DEC abs,x
        table[0xDF] = nop  # iDCP abs,x - illegal

        # 0xE0 - 0xEF
        table[0xE0] = encode.call(0, 0b100011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b010)  # CPX imm
        table[0xE1] = encode.call(0b1000, 0b110011, ADDR_READ_INDX, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC (zp,x)
        table[0xE2] = encode.call(0, 0, ADDR_IMMEDIATE, 0, ALU1_INP, ALU2_PSS)  # iNOP imm
        table[0xE3] = nop  # iISC (zp,x) - illegal
        table[0xE4] = encode.call(0, 0b100011, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b010)    # CPX zp
        table[0xE5] = encode.call(0b1000, 0b110011, ADDR_READ_ZP, ALU_IN_T, ALU1_INP, ALU2_SBC)      # SBC zp
        table[0xE6] = encode.call(0, 0b100010, ADDR_RMW_ZP, ALU_IN_T, ALU1_INC, ALU2_PSS)            # INC zp
        table[0xE7] = nop  # iISC zp - illegal
        table[0xE8] = encode.call(0b0100, 0b100010, ADDR_IMPLIED, ALU_IN_X, ALU1_INC, ALU2_PSS)      # INX
        table[0xE9] = encode.call(0b1000, 0b110011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC imm
        table[0xEA] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)                         # NOP
        table[0xEB] = encode.call(0b1000, 0b110011, ADDR_IMMEDIATE, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC imm (illegal)
        table[0xEC] = encode.call(0, 0b100011, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_CMP, 0b010)   # CPX abs
        table[0xED] = encode.call(0b1000, 0b110011, ADDR_READ_ABS, ALU_IN_T, ALU1_INP, ALU2_SBC)     # SBC abs
        table[0xEE] = encode.call(0, 0b100010, ADDR_RMW_ABS, ALU_IN_T, ALU1_INC, ALU2_PSS)           # INC abs
        table[0xEF] = nop  # iISC abs - illegal

        # 0xF0 - 0xFF
        table[0xF0] = encode.call(0, 0, ADDR_RELATIVE, 0, ALU1_INP, ALU2_PSS)  # BEQ
        table[0xF1] = encode.call(0b1000, 0b110011, ADDR_READ_INDY, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC (zp),y
        table[0xF2] = nop  # JAM
        table[0xF3] = nop  # iISC (zp),y - illegal
        table[0xF4] = encode.call(0, 0, ADDR_READ_ZPX, 0, ALU1_INP, ALU2_PSS)  # iNOP zp,x
        table[0xF5] = encode.call(0b1000, 0b110011, ADDR_READ_ZPX, ALU_IN_T, ALU1_INP, ALU2_SBC)     # SBC zp,x
        table[0xF6] = encode.call(0, 0b100010, ADDR_RMW_ZPX, ALU_IN_T, ALU1_INC, ALU2_PSS)           # INC zp,x
        table[0xF7] = nop  # iISC zp,x - illegal
        table[0xF8] = encode.call(0, 0b001000, ADDR_IMPLIED, ALU_IN_SET, ALU1_INP, ALU2_PSS)         # SED
        table[0xF9] = encode.call(0b1000, 0b110011, ADDR_READ_ABSY, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC abs,y
        table[0xFA] = encode.call(0, 0, ADDR_IMPLIED, 0, ALU1_INP, ALU2_PSS)  # iNOP implied
        table[0xFB] = nop  # iISC abs,y - illegal
        table[0xFC] = encode.call(0, 0, ADDR_READ_ABSX, 0, ALU1_INP, ALU2_PSS)  # iNOP abs,x
        table[0xFD] = encode.call(0b1000, 0b110011, ADDR_READ_ABSX, ALU_IN_T, ALU1_INP, ALU2_SBC)    # SBC abs,x
        table[0xFE] = encode.call(0, 0b100010, ADDR_RMW_ABSX, ALU_IN_T, ALU1_INC, ALU2_PSS)          # INC abs,x
        table[0xFF] = nop  # iISC abs,x - illegal

        table
      end

      OPCODE_TABLE = build_opcode_table.freeze

      # Opcode decode ROM
      memory :opcode_rom, depth: 256, width: 48, initial: OPCODE_TABLE

      # Internal state registers
      wire :cpu_state, width: 5
      wire :next_state, width: 5
      wire :opcode, width: 8
      wire :opc_info, width: 48
      wire :t_reg, width: 8           # Temporary data register
      wire :pc_reg, width: 16         # Program counter
      wire :addr_reg, width: 16       # Address register
      wire :a_reg, width: 8           # Accumulator
      wire :x_reg, width: 8           # X index
      wire :y_reg, width: 8           # Y index
      wire :s_reg, width: 8           # Stack pointer
      wire :flag_c                    # Carry
      wire :flag_z                    # Zero
      wire :flag_i                    # Interrupt disable
      wire :flag_d                    # Decimal mode
      wire :flag_v                    # Overflow
      wire :flag_n                    # Negative
      wire :irq_active
      wire :nmi_reg
      wire :nmi_edge
      wire :irq_reg
      wire :so_reg
      wire :process_irq
      wire :we_reg
      wire :do_reg, width: 8
      wire :index_out, width: 9       # Index calculation result with carry
      wire :update_regs

      # ALU signals
      wire :alu_input, width: 8
      wire :alu_cmp_input, width: 8
      wire :alu_rmw_out, width: 8
      wire :alu_reg_out, width: 8
      wire :alu_c
      wire :alu_z
      wire :alu_v
      wire :alu_n

      # Reset opcode is JMP absolute ($4C) - this causes CPU to jump to reset vector
      JMP_OPCODE = 0x4C
      JMP_OPC_INFO = OPCODE_TABLE[JMP_OPCODE]

      # Main sequential logic
      sequential clock: :clk, reset: :reset, reset_values: {
        cpu_state: STATE_CYCLE2,
        opcode: JMP_OPCODE,
        opc_info: JMP_OPC_INFO,
        t_reg: 0,
        pc_reg: 0,
        addr_reg: 0xFFFC,
        a_reg: 0,
        x_reg: 0,
        y_reg: 0,
        s_reg: 0xFD,  # 6502 reset decrements SP 3 times (dummy pushes)
        flag_c: 0,
        flag_z: 0,
        flag_i: 1,
        flag_d: 0,
        flag_v: 0,
        flag_n: 0,
        irq_active: 0,
        nmi_reg: 1,
        nmi_edge: 1,
        irq_reg: 1,
        so_reg: 1,
        process_irq: 0,
        we_reg: 0,
        do_reg: 0
      } do
        # State machine advance
        cpu_state <= mux(enable, next_state, cpu_state)

        # Latch opcode on fetch
        fetch_cycle = (cpu_state == lit(STATE_OPCODE_FETCH, width: 5))
        opcode <= mux(enable & fetch_cycle,
          mux(process_irq, lit(0x00, width: 8), di),
          opcode
        )

        # Latch opcode info
        opc_info <= mux(enable & fetch_cycle,
          mem_read_expr(:opcode_rom, mux(process_irq, lit(0x00, width: 8), di), width: 48),
          opc_info
        )

        # IRQ detection
        in_branch_or_fetch = (next_state == lit(STATE_BRANCH_TAKEN, width: 5)) |
                            (next_state == lit(STATE_OPCODE_FETCH, width: 5))
        irq_reg <= mux(enable & ~in_branch_or_fetch, irq_n, irq_reg)
        nmi_edge <= mux(enable & ~in_branch_or_fetch, nmi_n, nmi_edge)
        nmi_falling = nmi_edge & ~nmi_n
        nmi_reg <= mux(enable & (cpu_state == lit(STATE_STACK4, width: 5)),
          lit(1, width: 1),
          mux(enable & ~in_branch_or_fetch & nmi_falling, lit(0, width: 1), nmi_reg)
        )

        irq_bit = opc_info[OPC_IRQ]
        process_irq <= mux(enable,
          ~((nmi_reg & (irq_reg | flag_i)) | irq_bit),
          process_irq
        )

        irq_active <= mux(enable & fetch_cycle,
          mux(process_irq, lit(1, width: 1), lit(0, width: 1)),
          irq_active
        )

        # T register update
        cycle2 = (cpu_state == lit(STATE_CYCLE2, width: 5))
        stack1 = (cpu_state == lit(STATE_STACK1, width: 5))
        stack2 = (cpu_state == lit(STATE_STACK2, width: 5))
        indirect = (cpu_state == lit(STATE_INDIRECT, width: 5))
        read_cycle = (cpu_state == lit(STATE_READ, width: 5))
        read2 = (cpu_state == lit(STATE_READ2, width: 5))
        stack_up = opc_info[OPC_STACK_UP]

        t_latch = cycle2 |
                  ((stack1 | stack2) & stack_up) |
                  indirect | read_cycle | read2

        t_reg <= mux(enable & t_latch, di, t_reg)

        # Register updates - triggered when instruction completes (transitioning to OPCODE_FETCH)
        rti_bit = opc_info[OPC_RTI]
        completing = (next_state == lit(STATE_OPCODE_FETCH, width: 5))
        update_regs <= mux(rti_bit,
          read_cycle,
          completing
        )

        a_update = opc_info[OPC_UPDATE_A] & update_regs & enable
        x_update = opc_info[OPC_UPDATE_X] & update_regs & enable
        y_update = opc_info[OPC_UPDATE_Y] & update_regs & enable
        s_update_reg = opc_info[OPC_UPDATE_S] & update_regs & enable

        a_reg <= mux(a_update, alu_reg_out, a_reg)
        x_reg <= mux(x_update, alu_reg_out, x_reg)
        y_reg <= mux(y_update, alu_reg_out, y_reg)

        # Stack pointer updates
        stack3 = (cpu_state == lit(STATE_STACK3, width: 5))
        stack4 = (cpu_state == lit(STATE_STACK4, width: 5))
        stack_data = opc_info[OPC_STACK_DATA]
        write_cycle = (cpu_state == lit(STATE_WRITE, width: 5))

        s_inc = s_reg + lit(1, width: 8)
        s_dec = s_reg - lit(1, width: 8)
        s_adj = mux(stack_up, s_inc, s_dec)

        s_update_stack1 = (next_state == lit(STATE_STACK1, width: 5)) & (stack_up | stack_data)
        s_update_stack2 = (next_state == lit(STATE_STACK2, width: 5))
        s_update_stack3 = (next_state == lit(STATE_STACK3, width: 5))
        s_update_stack4 = (next_state == lit(STATE_STACK4, width: 5))
        s_update_read = (next_state == lit(STATE_READ, width: 5)) & rti_bit
        s_update_write = (next_state == lit(STATE_WRITE, width: 5)) & stack_data

        s_stack_update = s_update_stack1 | s_update_stack2 | s_update_stack3 |
                        s_update_stack4 | s_update_read | s_update_write

        s_reg <= mux(s_update_reg, alu_reg_out,
          mux(enable & s_stack_update, s_adj, s_reg)
        )

        # Flag updates
        c_update = opc_info[OPC_UPDATE_C] & update_regs & enable
        z_update = opc_info[OPC_UPDATE_Z] & update_regs & enable
        i_update = opc_info[OPC_UPDATE_I] & update_regs & enable
        d_update = opc_info[OPC_UPDATE_D] & update_regs & enable
        v_update = opc_info[OPC_UPDATE_V] & update_regs & enable
        n_update = opc_info[OPC_UPDATE_N] & update_regs & enable

        flag_c <= mux(c_update, alu_c, flag_c)
        flag_z <= mux(z_update, alu_z, flag_z)
        flag_i <= mux(i_update, alu_input[2], flag_i)
        flag_d <= mux(d_update, alu_input[3], flag_d)

        # V flag with SO pin detection
        so_falling = so_reg & ~so_n
        flag_v <= mux(v_update, alu_v,
          mux(enable & so_falling, lit(1, width: 1), flag_v)
        )
        so_reg <= mux(enable, so_n, so_reg)

        flag_n <= mux(n_update, alu_n, flag_n)

        # PC updates
        cycle3 = (cpu_state == lit(STATE_CYCLE3, width: 5))
        second_byte = opc_info[OPC_SECOND_BYTE]
        absolute = opc_info[OPC_ABSOLUTE]

        pc_incr = addr_reg + lit(1, width: 16)
        pc_reg <= mux(enable,
          mux(fetch_cycle, addr_reg,
            mux(cycle2 & ~irq_active & second_byte, pc_incr,
              mux(cycle2 & ~irq_active & ~second_byte, addr_reg,
                mux(cycle3 & absolute, pc_incr, pc_reg)
              )
            )
          ),
          pc_reg
        )

        # Write enable
        rmw_cycle = (cpu_state == lit(STATE_RMW, width: 5))
        stack_addr = opc_info[OPC_STACK_ADDR]
        rmw_bit = opc_info[OPC_RMW]
        write_bit = opc_info[OPC_WRITE]

        we_stack1 = (next_state == lit(STATE_STACK1, width: 5)) &
                   ~stack_up & (~stack_addr | stack_data)
        we_stack234 = ((next_state == lit(STATE_STACK2, width: 5)) |
                      (next_state == lit(STATE_STACK3, width: 5)) |
                      (next_state == lit(STATE_STACK4, width: 5))) & ~stack_up
        we_rmw = (next_state == lit(STATE_RMW, width: 5))
        we_write = (next_state == lit(STATE_WRITE, width: 5))

        we_reg <= mux(enable,
          we_stack1 | we_stack234 | we_rmw | we_write,
          we_reg
        )

        # Data out register
        irq_bit_val = opc_info[OPC_IRQ]
        in_h = opc_info[OPC_IN_H]

        do_stack2 = (next_state == lit(STATE_STACK2, width: 5))
        do_stack3 = (next_state == lit(STATE_STACK3, width: 5))
        do_rmw = (next_state == lit(STATE_RMW, width: 5))

        addr_incr_h = addr_reg[15..8] + lit(1, width: 8)

        do_val = mux(in_h, alu_rmw_out & addr_incr_h, alu_rmw_out)

        do_reg <= mux(enable,
          mux(do_stack2,
            mux(irq_bit_val & ~irq_active, pc_incr[15..8], pc_reg[15..8]),
            mux(do_stack3, pc_reg[7..0],
              mux(do_rmw, di, do_val)
            )
          ),
          do_reg
        )

        # Address register updates (complex state machine)
        pre_indirect = (cpu_state == lit(STATE_PRE_INDIRECT, width: 5))
        branch_taken = (cpu_state == lit(STATE_BRANCH_TAKEN, width: 5))
        branch_page = (cpu_state == lit(STATE_BRANCH_PAGE, width: 5))
        pre_read = (cpu_state == lit(STATE_PRE_READ, width: 5))
        pre_write = (cpu_state == lit(STATE_PRE_WRITE, width: 5))
        jump_cycle = (cpu_state == lit(STATE_JUMP, width: 5))

        zeropage = opc_info[OPC_ZEROPAGE]
        indirect_bit = opc_info[OPC_INDIRECT]
        index_x = opc_info[OPC_INDEX_X]
        index_y = opc_info[OPC_INDEX_Y]
        jump_bit = opc_info[OPC_JUMP]
        branch_bit = opc_info[OPC_BRANCH]

        addr_incr = addr_reg + lit(1, width: 16)
        addr_incr_l = cat(addr_reg[15..8], addr_reg[7..0] + lit(1, width: 8))
        addr_decr_h = cat(addr_reg[15..8] - lit(1, width: 8), addr_reg[7..0])

        # Index calculation
        idx_val = mux(index_x, x_reg, mux(index_y, y_reg, lit(0, width: 8)))
        idx_sum = cat(lit(0, width: 1), t_reg) + cat(lit(0, width: 1), idx_val)
        branch_sum = cat(lit(0, width: 1), t_reg) + cat(lit(0, width: 1), addr_reg[7..0])
        index_out <= mux(branch_bit, branch_sum, idx_sum)

        # Next address calculation based on state
        addr_next = addr_reg  # Default: hold

        # cycle2 address
        addr_c2 = mux(stack_addr | stack_data, cat(lit(0x01, width: 8), s_reg),
          mux(absolute, addr_incr,
            mux(zeropage | indirect_bit, cat(lit(0x00, width: 8), di),
              mux(second_byte, addr_incr, addr_reg)
            )
          )
        )

        # cycle3 address
        # For indexed addressing, use index_out (t_reg + index register)
        # For non-indexed, use t_reg directly (index_out has stale values)
        indexed = index_x | index_y
        addr_c3 = mux(indirect_bit & index_x,
          cat(di, t_reg),
          mux(indexed,
            cat(di, (t_reg + idx_val)[7..0]),  # Use fresh index calculation
            cat(di, t_reg)                      # Non-indexed: use t_reg directly
          )
        )

        # branch address - compute fresh using current t_reg and addr_reg
        # (index_out has stale values from previous cycle)
        branch_low = (t_reg + addr_reg[7..0])[7..0]
        addr_branch = cat(addr_reg[15..8], branch_low)
        addr_branch_page = mux(t_reg[7],
          cat(addr_reg[15..8] - lit(1, width: 8), branch_low),
          cat(addr_reg[15..8] + lit(1, width: 8), branch_low)
        )

        # stack address - use current S register
        addr_stack = cat(lit(0x01, width: 8), s_reg)

        # irq/nmi vector
        addr_irq = mux(nmi_reg, lit(0xFFFE, width: 16), lit(0xFFFA, width: 16))

        # jump address
        addr_jump = cat(di, t_reg)

        # For indexed zero page addressing (pre_read state), compute indexed address fresh
        # (index_out has stale values from previous cycle)
        index_x_bit = opc_info[OPC_INDEX_X]
        index_y_bit = opc_info[OPC_INDEX_Y]
        zp_index_val = mux(index_x_bit, x_reg, mux(index_y_bit, y_reg, lit(0, width: 8)))
        zp_indexed_addr = cat(lit(0x00, width: 8), (t_reg + zp_index_val)[7..0])

        addr_reg <= mux(enable,
          mux(cycle2, addr_c2,
            mux(cycle3, addr_c3,
              mux(pre_indirect, cat(lit(0x00, width: 8), index_out[7..0]),
                mux(indirect, addr_incr_l,
                  mux(branch_taken, addr_branch,
                    mux(branch_page, addr_branch_page,
                      mux(pre_read, zp_indexed_addr,
                        mux(read_cycle,
                          mux(jump_bit, addr_incr_l,
                            mux(index_out[8], cat(addr_reg[15..8] + lit(1, width: 8), addr_reg[7..0]),
                              mux(rmw_bit, addr_reg, pc_reg)
                            )
                          ),
                          mux(read2, mux(rmw_bit, addr_reg, pc_reg),
                            mux(rmw_cycle,
                              # For RMW cycle, hold address constant (don't use t_reg which now contains data)
                              addr_reg,
                              mux(pre_write,
                                mux(zeropage, zp_indexed_addr,
                                  mux(index_out[8], cat(addr_reg[15..8] + lit(1, width: 8), addr_reg[7..0]), addr_reg)
                                ),
                                mux(write_cycle, pc_reg,
                                  mux(stack1 | stack2, addr_stack,
                                    mux(stack3,
                                      # For JSR (jump_bit), use pc_reg to read high byte
                                      # For other stack ops, use addr_stack
                                      mux(jump_bit, pc_reg, addr_stack),
                                      mux(stack4, addr_irq,
                                        mux(jump_cycle, addr_jump, addr_incr)
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          ),
          addr_reg
        )
      end

      # Combinational logic for ALU and next state
      behavior do
        # Output assignments
        addr <= addr_reg
        we <= we_reg
        do_out <= do_reg
        debug_opcode <= opcode
        debug_pc <= pc_reg
        debug_a <= a_reg
        debug_x <= x_reg
        debug_y <= y_reg
        debug_s <= s_reg

        # Debug: address calculation signals
        dbg_cycle2 = (cpu_state == lit(STATE_CYCLE2, width: 5))
        dbg_second_byte = opc_info[OPC_SECOND_BYTE]
        dbg_addr_incr = addr_reg + lit(1, width: 16)
        dbg_addr_c2 = mux(dbg_second_byte, dbg_addr_incr, addr_reg)
        debug_cycle2 <= dbg_cycle2
        debug_second_byte <= dbg_second_byte
        debug_addr_c2 <= dbg_addr_c2
        debug_opc_info <= opc_info

        # ALU input selection
        in_a = opc_info[OPC_IN_A]
        in_e = opc_info[OPC_IN_E]
        in_x = opc_info[OPC_IN_X]
        in_y = opc_info[OPC_IN_Y]
        in_s = opc_info[OPC_IN_S]
        in_t = opc_info[OPC_IN_T]
        in_clr = opc_info[OPC_IN_CLEAR]
        in_cmp = opc_info[OPC_IN_CMP]
        in_cpx = opc_info[OPC_IN_CPX]
        in_cpy = opc_info[OPC_IN_CPY]

        # Compute t_latch condition for bypass (same as in sequential block)
        # When t_latch is true, di is about to be latched into t_reg.
        # Use di directly (bypass) to match reference VHDL combinational behavior.
        b_cycle2 = (cpu_state == lit(STATE_CYCLE2, width: 5))
        b_stack1 = (cpu_state == lit(STATE_STACK1, width: 5))
        b_stack2 = (cpu_state == lit(STATE_STACK2, width: 5))
        b_indirect = (cpu_state == lit(STATE_INDIRECT, width: 5))
        b_read_cycle = (cpu_state == lit(STATE_READ, width: 5))
        b_read2 = (cpu_state == lit(STATE_READ2, width: 5))
        b_stack_up = opc_info[OPC_STACK_UP]
        b_t_latch = b_cycle2 | ((b_stack1 | b_stack2) & b_stack_up) | b_indirect | b_read_cycle | b_read2

        # Use di directly when t_latch is true (bypassing old t_reg)
        t_val = mux(enable & b_t_latch, di, t_reg)

        # ALU input (ANDed together like reference)
        alu_tmp = lit(0xFF, width: 8)
        alu_tmp = mux(in_a, alu_tmp & a_reg, alu_tmp)
        alu_tmp = mux(in_e, alu_tmp & (a_reg | lit(0xEE, width: 8)), alu_tmp)
        alu_tmp = mux(in_x, alu_tmp & x_reg, alu_tmp)
        alu_tmp = mux(in_y, alu_tmp & y_reg, alu_tmp)
        alu_tmp = mux(in_s, alu_tmp & s_reg, alu_tmp)
        alu_tmp = mux(in_t, alu_tmp & t_val, alu_tmp)
        alu_tmp = mux(in_clr, lit(0x00, width: 8), alu_tmp)
        alu_input <= alu_tmp

        # Compare input
        cmp_tmp = lit(0xFF, width: 8)
        cmp_tmp = mux(in_cmp, cmp_tmp & a_reg, cmp_tmp)
        cmp_tmp = mux(in_cpx, cmp_tmp & x_reg, cmp_tmp)
        cmp_tmp = mux(in_cpy, cmp_tmp & y_reg, cmp_tmp)
        alu_cmp_input <= cmp_tmp

        # ALU mode extraction
        alu_mode1 = opc_info[ALU_MODE1_END..ALU_MODE1_START]
        alu_mode2 = opc_info[ALU_MODE2_END..ALU_MODE2_START]

        # Shift/RMW unit
        rmw_c = flag_c
        rmw_in = alu_input
        rmw_out = rmw_in
        rmw_c_out = flag_c

        # Status register pack for PHP
        status_reg = cat(flag_n, flag_v, lit(1, width: 1), ~irq_active, flag_d, flag_i, flag_z, flag_c)
        debug_p <= status_reg

        rmw_out = mux(alu_mode1 == lit(ALU1_INP, width: 4), rmw_in,
          mux(alu_mode1 == lit(ALU1_P, width: 4), status_reg,
            mux(alu_mode1 == lit(ALU1_INC, width: 4), (rmw_in + lit(1, width: 8))[7..0],
              mux(alu_mode1 == lit(ALU1_DEC, width: 4), (rmw_in - lit(1, width: 8))[7..0],
                mux(alu_mode1 == lit(ALU1_FLG, width: 4), rmw_in,
                  mux(alu_mode1 == lit(ALU1_BIT, width: 4), rmw_in,
                    mux(alu_mode1 == lit(ALU1_LSR, width: 4), cat(lit(0, width: 1), rmw_in[7..1]),
                      mux(alu_mode1 == lit(ALU1_ROR, width: 4), cat(flag_c, rmw_in[7..1]),
                        mux(alu_mode1 == lit(ALU1_ASL, width: 4), cat(rmw_in[6..0], lit(0, width: 1)),
                          mux(alu_mode1 == lit(ALU1_ROL, width: 4), cat(rmw_in[6..0], flag_c),
                            rmw_in
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )

        # Carry output from shift/RMW unit
        # For ALU1_FLG (SEC/CLC), use bit 0 of input: SEC has 0xFF (bit0=1), CLC has 0x00 (bit0=0)
        rmw_c_out = mux(alu_mode1 == lit(ALU1_FLG, width: 4), rmw_in[0],
          mux(alu_mode1 == lit(ALU1_LSR, width: 4), rmw_in[0],
            mux(alu_mode1 == lit(ALU1_ROR, width: 4), rmw_in[0],
              mux(alu_mode1 == lit(ALU1_ASL, width: 4), rmw_in[7],
                mux(alu_mode1 == lit(ALU1_ROL, width: 4), rmw_in[7],
                  mux(alu_mode1 == lit(ALU1_ANC, width: 4), rmw_in[7] & a_reg[7],
                    flag_c
                  )
                )
              )
            )
          )
        )

        alu_rmw_out <= rmw_out

        # Arithmetic ALU
        arith_a = a_reg
        arith_b = rmw_out
        arith_c_in = mux((alu_mode1 == lit(ALU1_FLG, width: 4)) |
                        (alu_mode1 == lit(ALU1_LSR, width: 4)) |
                        (alu_mode1 == lit(ALU1_ROR, width: 4)) |
                        (alu_mode1 == lit(ALU1_ASL, width: 4)) |
                        (alu_mode1 == lit(ALU1_ROL, width: 4)),
                        rmw_c_out, flag_c)

        # 9-bit result for carry detection
        add_result = cat(lit(0, width: 1), arith_a) + cat(lit(0, width: 1), arith_b) + cat(lit(0, width: 8), arith_c_in)
        sub_result = cat(lit(0, width: 1), arith_a) + cat(lit(0, width: 1), ~arith_b) + cat(lit(0, width: 8), arith_c_in)
        cmp_result = cat(lit(0, width: 1), alu_cmp_input) + cat(lit(0, width: 1), ~arith_b) + lit(1, width: 9)

        arith_out = mux(alu_mode2 == lit(ALU2_ADC, width: 3), add_result[7..0],
          mux(alu_mode2 == lit(ALU2_SBC, width: 3), sub_result[7..0],
            mux(alu_mode2 == lit(ALU2_CMP, width: 3), cmp_result[7..0],
              mux(alu_mode2 == lit(ALU2_AND, width: 3), arith_a & arith_b,
                mux(alu_mode2 == lit(ALU2_ORA, width: 3), arith_a | arith_b,
                  mux(alu_mode2 == lit(ALU2_EOR, width: 3), arith_a ^ arith_b,
                    rmw_out  # PSS - pass through
                  )
                )
              )
            )
          )
        )

        alu_reg_out <= arith_out

        # Flag calculations
        alu_z <= mux(alu_mode1 == lit(ALU1_FLG, width: 4), rmw_out[1],
          mux(arith_out == lit(0, width: 8), lit(1, width: 1), lit(0, width: 1))
        )

        alu_n <= mux((alu_mode1 == lit(ALU1_BIT, width: 4)) | (alu_mode1 == lit(ALU1_FLG, width: 4)),
          rmw_out[7], arith_out[7])

        alu_c <= mux(alu_mode2 == lit(ALU2_ADC, width: 3), add_result[8],
          mux(alu_mode2 == lit(ALU2_SBC, width: 3), sub_result[8],
            mux(alu_mode2 == lit(ALU2_CMP, width: 3), cmp_result[8],
              rmw_c_out
            )
          )
        )

        # Overflow: (A[7] ^ result[7]) & (B[7] ^ result[7]) for ADC
        #           (A[7] ^ result[7]) & (~B[7] ^ result[7]) for SBC
        alu_v <= mux(alu_mode2 == lit(ALU2_ADC, width: 3),
          (arith_a[7] ^ arith_out[7]) & (arith_b[7] ^ arith_out[7]),
          mux(alu_mode2 == lit(ALU2_SBC, width: 3),
            (arith_a[7] ^ arith_out[7]) & (~arith_b[7] ^ arith_out[7]),
            mux(alu_mode1 == lit(ALU1_BIT, width: 4), rmw_out[6], alu_input[6])
          )
        )

        # Next state calculation
        cur_state = cpu_state
        second_byte = opc_info[OPC_SECOND_BYTE]
        branch_bit = opc_info[OPC_BRANCH]
        stack_up = opc_info[OPC_STACK_UP]
        stack_addr = opc_info[OPC_STACK_ADDR]
        stack_data = opc_info[OPC_STACK_DATA]
        absolute = opc_info[OPC_ABSOLUTE]
        indirect_bit = opc_info[OPC_INDIRECT]
        zeropage = opc_info[OPC_ZEROPAGE]
        write_bit = opc_info[OPC_WRITE]
        index_x = opc_info[OPC_INDEX_X]
        index_y = opc_info[OPC_INDEX_Y]
        jump_bit = opc_info[OPC_JUMP]
        rmw_bit = opc_info[OPC_RMW]
        incr_after = opc_info[OPC_INCR_AFTER]
        rti_bit = opc_info[OPC_RTI]

        # Branch condition check
        branch_cond = mux((opcode[7..6] == lit(0b00, width: 2)), flag_n == opcode[5],
          mux((opcode[7..6] == lit(0b01, width: 2)), flag_v == opcode[5],
            mux((opcode[7..6] == lit(0b10, width: 2)), flag_c == opcode[5],
              flag_z == opcode[5]
            )
          )
        )

        # Index calculation for page crossing
        idx_val = mux(index_x, x_reg, mux(index_y, y_reg, lit(0, width: 8)))
        idx_sum = cat(lit(0, width: 1), t_reg) + cat(lit(0, width: 1), idx_val)
        branch_sum = cat(lit(0, width: 1), t_reg) + cat(lit(0, width: 1), addr_reg[7..0])
        page_cross = mux(branch_bit, branch_sum[8] ^ t_reg[7], idx_sum[8])

        # State machine
        ns = lit(STATE_OPCODE_FETCH, width: 5)  # Default

        ns = mux(cur_state == lit(STATE_OPCODE_FETCH, width: 5), lit(STATE_CYCLE2, width: 5), ns)

        # cycle2 next state
        c2_branch = branch_bit & branch_cond
        c2_stack_up = stack_up
        c2_stack_both = stack_addr & stack_data
        c2_stack_addr_only = stack_addr & ~stack_data
        c2_stack_data_only = ~stack_addr & stack_data
        c2_abs = absolute
        c2_ind_x = indirect_bit & index_x
        c2_ind_y = indirect_bit & ~index_x
        c2_zp_write = zeropage & write_bit
        c2_zp_read = zeropage & ~write_bit
        c2_zp_indexed = index_x | index_y
        c2_jump = jump_bit

        c2_ns = mux(c2_branch, lit(STATE_BRANCH_TAKEN, width: 5),
          mux(c2_stack_up, lit(STATE_STACK1, width: 5),
            mux(c2_stack_both, lit(STATE_STACK2, width: 5),
              mux(c2_stack_addr_only, lit(STATE_STACK1, width: 5),
                mux(c2_stack_data_only, lit(STATE_WRITE, width: 5),
                  mux(c2_abs, lit(STATE_CYCLE3, width: 5),
                    mux(c2_ind_x, lit(STATE_PRE_INDIRECT, width: 5),
                      mux(c2_ind_y, lit(STATE_INDIRECT, width: 5),
                        mux(c2_zp_write & c2_zp_indexed, lit(STATE_PRE_WRITE, width: 5),
                          mux(c2_zp_write & ~c2_zp_indexed, lit(STATE_WRITE, width: 5),
                            mux(c2_zp_read & c2_zp_indexed, lit(STATE_PRE_READ, width: 5),
                              mux(c2_zp_read & ~c2_zp_indexed, lit(STATE_READ2, width: 5),
                                mux(c2_jump, lit(STATE_JUMP, width: 5),
                                  lit(STATE_OPCODE_FETCH, width: 5)
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
        ns = mux(cur_state == lit(STATE_CYCLE2, width: 5), c2_ns, ns)

        # cycle3 next state
        c3_ind_x = indirect_bit & index_x
        c3_write = write_bit
        c3_indexed = index_x | index_y

        c3_ns = mux(c3_ind_x & c3_write, lit(STATE_WRITE, width: 5),
          mux(c3_ind_x & ~c3_write, lit(STATE_READ2, width: 5),
            mux(c3_write & c3_indexed, lit(STATE_PRE_WRITE, width: 5),
              mux(c3_write & ~c3_indexed, lit(STATE_WRITE, width: 5),
                lit(STATE_READ, width: 5)
              )
            )
          )
        )
        ns = mux(cur_state == lit(STATE_CYCLE3, width: 5), c3_ns, ns)

        ns = mux(cur_state == lit(STATE_PRE_INDIRECT, width: 5), lit(STATE_INDIRECT, width: 5), ns)
        ns = mux(cur_state == lit(STATE_INDIRECT, width: 5), lit(STATE_CYCLE3, width: 5), ns)

        # branch_taken next state
        bt_ns = mux(page_cross, lit(STATE_BRANCH_PAGE, width: 5), lit(STATE_OPCODE_FETCH, width: 5))
        ns = mux(cur_state == lit(STATE_BRANCH_TAKEN, width: 5), bt_ns, ns)

        ns = mux(cur_state == lit(STATE_BRANCH_PAGE, width: 5), lit(STATE_OPCODE_FETCH, width: 5), ns)
        ns = mux(cur_state == lit(STATE_PRE_READ, width: 5),
          mux(zeropage, lit(STATE_READ2, width: 5), lit(STATE_OPCODE_FETCH, width: 5)), ns)

        # read next state
        rd_ns = mux(jump_bit, lit(STATE_JUMP, width: 5),
          mux(page_cross, lit(STATE_READ2, width: 5),
            mux(rmw_bit,
              mux(index_x | index_y, lit(STATE_READ2, width: 5), lit(STATE_RMW, width: 5)),
              lit(STATE_OPCODE_FETCH, width: 5)
            )
          )
        )
        ns = mux(cur_state == lit(STATE_READ, width: 5), rd_ns, ns)

        rd2_ns = mux(rmw_bit, lit(STATE_RMW, width: 5), lit(STATE_OPCODE_FETCH, width: 5))
        ns = mux(cur_state == lit(STATE_READ2, width: 5), rd2_ns, ns)

        ns = mux(cur_state == lit(STATE_RMW, width: 5), lit(STATE_WRITE, width: 5), ns)
        ns = mux(cur_state == lit(STATE_PRE_WRITE, width: 5), lit(STATE_WRITE, width: 5), ns)
        ns = mux(cur_state == lit(STATE_WRITE, width: 5), lit(STATE_OPCODE_FETCH, width: 5), ns)

        # stack states
        st1_ns = mux(stack_addr, lit(STATE_STACK2, width: 5), lit(STATE_READ, width: 5))
        ns = mux(cur_state == lit(STATE_STACK1, width: 5), st1_ns, ns)

        st2_ns = mux(rti_bit, lit(STATE_READ, width: 5),
          mux(~stack_data & stack_up, lit(STATE_JUMP, width: 5), lit(STATE_STACK3, width: 5))
        )
        ns = mux(cur_state == lit(STATE_STACK2, width: 5), st2_ns, ns)

        st3_ns = mux(~stack_data | stack_up, lit(STATE_JUMP, width: 5),
          mux(stack_addr, lit(STATE_STACK4, width: 5), lit(STATE_READ, width: 5))
        )
        ns = mux(cur_state == lit(STATE_STACK3, width: 5), st3_ns, ns)

        ns = mux(cur_state == lit(STATE_STACK4, width: 5), lit(STATE_READ, width: 5), ns)

        jmp_ns = mux(incr_after, lit(STATE_END, width: 5), lit(STATE_OPCODE_FETCH, width: 5))
        ns = mux(cur_state == lit(STATE_JUMP, width: 5), jmp_ns, ns)

        ns = mux(cur_state == lit(STATE_END, width: 5), lit(STATE_OPCODE_FETCH, width: 5), ns)

        next_state <= ns
      end
    end
  end
end
