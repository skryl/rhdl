# ao486 Instruction Decode (Real Mode Subset)
# Ported from: rtl/ao486/pipeline/decode.v, decode_prefix.v, decode_ready.v,
#              decode_commands.v, autogen/decode_commands.v
#
# Unified combinational decoder for x86 real-mode instruction subset.
# Parses prefix bytes, opcode, ModR/M, SIB, and immediates.
# Outputs: CMD_* type, consumed byte count, operand sizes, register indices.

require_relative '../../../../lib/rhdl'
require_relative '../../../../lib/rhdl/dsl/behavior'
require_relative '../constants'

module RHDL
  module Examples
    module AO486
      class Decode < RHDL::HDL::Component
        include RHDL::DSL::Behavior

        # From fetch stage
        input :fetch_valid, width: 4
        input :fetch, width: 64

        # From write-back (current mode)
        input :operand_32bit  # CS.D bit (0=16-bit default, 1=32-bit default)
        input :address_32bit  # CS.D bit for addressing

        # Decoded outputs
        output :dec_cmd, width: 7
        output :dec_cmdex, width: 4
        output :dec_consumed, width: 4
        output :dec_ready
        output :dec_is_8bit
        output :dec_operand_32bit
        output :dec_address_32bit
        output :dec_prefix_group_1_rep, width: 2
        output :dec_prefix_group_1_lock
        output :dec_prefix_group_2_seg, width: 3
        output :dec_modregrm_mod, width: 2
        output :dec_modregrm_reg, width: 3
        output :dec_modregrm_rm, width: 3

        def propagate
          valid = in_val(:fetch_valid)
          fetch = in_val(:fetch)

          # Extract up to 8 bytes from fetch window
          bytes = Array.new(8) { |i| (fetch >> (i * 8)) & 0xFF }

          # --- Phase 1: Parse prefixes ---
          prefix_count = 0
          prefix_2byte = false
          prefix_66 = false
          prefix_67 = false
          seg_override = 3  # default DS
          has_seg_override = false
          rep_prefix = 0
          lock_prefix = false

          while prefix_count < valid && prefix_count < 4
            b = bytes[prefix_count]
            case b
            when 0x66
              prefix_66 = true
              prefix_count += 1
            when 0x67
              prefix_67 = true
              prefix_count += 1
            when 0x26 then has_seg_override = true; seg_override = Constants::SEGMENT_ES; prefix_count += 1
            when 0x2E then has_seg_override = true; seg_override = Constants::SEGMENT_CS; prefix_count += 1
            when 0x36 then has_seg_override = true; seg_override = Constants::SEGMENT_SS; prefix_count += 1
            when 0x3E then has_seg_override = true; seg_override = Constants::SEGMENT_DS; prefix_count += 1
            when 0x64 then has_seg_override = true; seg_override = Constants::SEGMENT_FS; prefix_count += 1
            when 0x65 then has_seg_override = true; seg_override = Constants::SEGMENT_GS; prefix_count += 1
            when 0xF0 then lock_prefix = true; prefix_count += 1
            when 0xF2 then rep_prefix = 1; prefix_count += 1
            when 0xF3 then rep_prefix = 2; prefix_count += 1
            when 0x0F then prefix_2byte = true; prefix_count += 1; break
            else break
            end
          end

          # Operand/address size after prefix toggle
          op32 = in_val(:operand_32bit) != 0
          op32 = !op32 if prefix_66
          addr32 = in_val(:address_32bit) != 0
          addr32 = !addr32 if prefix_67

          # --- Phase 2: Decode opcode ---
          if prefix_count >= valid
            set_not_ready
            return
          end

          opcode = bytes[prefix_count]
          modregrm_offset = prefix_count + 1

          # Default output values
          cmd = Constants::CMD_NULL
          cmdex = 0
          is_8bit = false
          consumed = 0
          ready = false

          # --- Phase 3: Instruction classification ---
          if prefix_2byte
            # 2-byte opcodes (0x0F xx)
            cmd, cmdex, consumed, is_8bit, ready = decode_2byte(opcode, bytes, modregrm_offset, prefix_count, valid, op32, addr32)
          else
            cmd, cmdex, consumed, is_8bit, ready = decode_1byte(opcode, bytes, modregrm_offset, prefix_count, valid, op32, addr32)
          end

          # --- Phase 4: Drive outputs ---
          # consumed from decode_*byte is instruction-only; add prefix bytes
          total_consumed = prefix_count + consumed
          out_set(:dec_cmd, cmd & 0x7F)
          out_set(:dec_cmdex, cmdex & 0xF)
          out_set(:dec_consumed, total_consumed & 0xF)
          out_set(:dec_ready, ready ? 1 : 0)
          out_set(:dec_is_8bit, is_8bit ? 1 : 0)
          out_set(:dec_operand_32bit, op32 ? 1 : 0)
          out_set(:dec_address_32bit, addr32 ? 1 : 0)
          out_set(:dec_prefix_group_1_rep, rep_prefix & 0x3)
          out_set(:dec_prefix_group_1_lock, lock_prefix ? 1 : 0)
          out_set(:dec_prefix_group_2_seg, (has_seg_override ? seg_override : 3) & 0x7)

          # ModR/M fields (if present)
          if modregrm_offset < valid
            mrm = bytes[modregrm_offset]
            out_set(:dec_modregrm_mod, (mrm >> 6) & 0x3)
            out_set(:dec_modregrm_reg, (mrm >> 3) & 0x7)
            out_set(:dec_modregrm_rm, mrm & 0x7)
          else
            out_set(:dec_modregrm_mod, 0)
            out_set(:dec_modregrm_reg, 0)
            out_set(:dec_modregrm_rm, 0)
          end
        end

        private

        def set_not_ready
          out_set(:dec_cmd, Constants::CMD_NULL)
          out_set(:dec_cmdex, 0)
          out_set(:dec_consumed, 0)
          out_set(:dec_ready, 0)
          out_set(:dec_is_8bit, 0)
          out_set(:dec_operand_32bit, 0)
          out_set(:dec_address_32bit, 0)
          out_set(:dec_prefix_group_1_rep, 0)
          out_set(:dec_prefix_group_1_lock, 0)
          out_set(:dec_prefix_group_2_seg, 3)
          out_set(:dec_modregrm_mod, 0)
          out_set(:dec_modregrm_reg, 0)
          out_set(:dec_modregrm_rm, 0)
        end

        # Compute ModR/M+displacement byte count for 16-bit addressing
        # Returns: number of bytes for ModR/M portion (ModR/M byte + displacement)
        def modregrm_len_16(bytes, offset, valid)
          return 0 if offset >= valid
          mrm = bytes[offset]
          mod = (mrm >> 6) & 3
          rm = mrm & 7
          case mod
          when 0 then rm == 6 ? 3 : 1  # ModR/M + disp16, or just ModR/M
          when 1 then 2                  # ModR/M + disp8
          when 2 then 3                  # ModR/M + disp16
          when 3 then 1                  # ModR/M only (register)
          end
        end

        # Compute ModR/M+displacement byte count for 32-bit addressing
        # Returns: number of bytes for ModR/M portion (ModR/M + SIB + displacement)
        def modregrm_len_32(bytes, offset, valid)
          return 0 if offset >= valid
          mrm = bytes[offset]
          mod = (mrm >> 6) & 3
          rm = mrm & 7
          has_sib = (rm == 4 && mod != 3)
          sib_base = has_sib && (offset + 1) < valid ? bytes[offset + 1] & 7 : 0

          case mod
          when 0
            if rm == 5 then 5            # ModR/M + disp32
            elsif has_sib && sib_base == 5 then 6  # ModR/M + SIB + disp32
            elsif has_sib then 2          # ModR/M + SIB
            else 1                        # ModR/M only
            end
          when 1
            has_sib ? 3 : 2              # ModR/M + (SIB) + disp8
          when 2
            has_sib ? 6 : 5              # ModR/M + (SIB) + disp32
          when 3 then 1                  # ModR/M only (register)
          end
        end

        def modregrm_len(bytes, offset, valid, addr32)
          addr32 ? modregrm_len_32(bytes, offset, valid) : modregrm_len_16(bytes, offset, valid)
        end

        # Check if we have enough bytes
        def has_bytes?(prefix_count, needed, valid)
          (prefix_count + needed) <= valid
        end

        # Decode 1-byte opcodes
        def decode_1byte(opcode, bytes, mrm_off, pfx_cnt, valid, op32, addr32)
          # Arithmetic with accumulator: ADD/OR/ADC/SBB/AND/SUB/XOR/CMP AL/AX, imm
          # Pattern: 0000_0r0w (r=reg_index[2:1], w=0 for 8bit, 1 for 16/32)
          if (opcode & 0xC6) == 0x04  # 0x04,0x05,0x0C,0x0D,...,0x3C,0x3D
            arith_op = (opcode >> 3) & 7
            cmd = Constants::CMD_Arith + arith_op
            is_8bit = (opcode & 1) == 0
            if is_8bit
              needed = 2  # opcode + imm8
            else
              needed = op32 ? 5 : 3  # opcode + imm16/32
            end
            return [cmd, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # Arithmetic ModR/M: 0x00-0x03, 0x08-0x0B, ..., 0x38-0x3B
          if (opcode & 0xC4) == 0x00 && (opcode & 0x07) <= 3
            arith_op = (opcode >> 3) & 7
            cmd = Constants::CMD_Arith + arith_op
            is_8bit = (opcode & 1) == 0
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [cmd, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # Immediate group 0x80-0x83
          if opcode >= 0x80 && opcode <= 0x83
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            reg_field = mrm_off < valid ? (bytes[mrm_off] >> 3) & 7 : 0
            cmd = Constants::CMD_Arith + reg_field
            is_8bit = (opcode == 0x80 || opcode == 0x82)
            imm_size = if opcode == 0x80 || opcode == 0x82 || opcode == 0x83
                         1  # imm8 or sign-extended imm8
                       else
                         op32 ? 4 : 2
                       end
            needed = 1 + mlen + imm_size
            return [cmd, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # INC/DEC register short form (0x40-0x4F)
          if opcode >= 0x40 && opcode <= 0x4F
            return [Constants::CMD_INC_DEC, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # PUSH register (0x50-0x57)
          if opcode >= 0x50 && opcode <= 0x57
            return [Constants::CMD_PUSH, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # POP register (0x58-0x5F)
          if opcode >= 0x58 && opcode <= 0x5F
            return [Constants::CMD_POP, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # PUSH imm (0x68 imm16/32, 0x6A imm8)
          if opcode == 0x68
            needed = op32 ? 5 : 3
            return [Constants::CMD_PUSH, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end
          if opcode == 0x6A
            return [Constants::CMD_PUSH, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # Jcc short (0x70-0x7F)
          if opcode >= 0x70 && opcode <= 0x7F
            return [Constants::CMD_Jcc, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # TEST r/m, r (0x84/0x85)
          if opcode == 0x84 || opcode == 0x85
            is_8bit = (opcode == 0x84)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_TEST, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # XCHG (0x86/0x87)
          if opcode == 0x86 || opcode == 0x87
            is_8bit = (opcode == 0x86)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_XCHG, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # MOV r/m, r (0x88/0x89) and MOV r, r/m (0x8A/0x8B)
          if opcode >= 0x88 && opcode <= 0x8B
            is_8bit = (opcode & 1) == 0
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_MOV, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # LEA (0x8D)
          if opcode == 0x8D
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_LEA, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # NOP/XCHG reg, EAX (0x90-0x97)
          if (opcode & 0xF8) == 0x90
            return [Constants::CMD_XCHG, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # PUSHF (0x9C), POPF (0x9D)
          if opcode == 0x9C
            return [Constants::CMD_PUSHF, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end
          if opcode == 0x9D
            return [Constants::CMD_POPF, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # SAHF (0x9E), LAHF (0x9F)
          if opcode == 0x9E
            return [Constants::CMD_SAHF, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end
          if opcode == 0x9F
            return [Constants::CMD_LAHF, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # MOV moffs (0xA0-0xA3)
          if opcode >= 0xA0 && opcode <= 0xA3
            is_8bit = (opcode & 1) == 0
            addr_sz = addr32 ? 4 : 2
            needed = 1 + addr_sz
            return [Constants::CMD_MOV, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # TEST AL/AX, imm (0xA8/0xA9)
          if opcode == 0xA8
            return [Constants::CMD_TEST, 0, 2, true, has_bytes?(pfx_cnt, 2, valid)]
          end
          if opcode == 0xA9
            needed = op32 ? 5 : 3
            return [Constants::CMD_TEST, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # MOV reg, imm8 (0xB0-0xB7)
          if opcode >= 0xB0 && opcode <= 0xB7
            return [Constants::CMD_MOV, 0, 2, true, has_bytes?(pfx_cnt, 2, valid)]
          end

          # MOV reg, imm16/32 (0xB8-0xBF)
          if opcode >= 0xB8 && opcode <= 0xBF
            needed = op32 ? 5 : 3
            return [Constants::CMD_MOV, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # Shift group (0xC0/0xC1 imm8)
          if opcode == 0xC0 || opcode == 0xC1
            is_8bit = (opcode == 0xC0)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen + 1  # +1 for imm8 shift count
            return [Constants::CMD_Shift, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # RET near (0xC3), RET near imm16 (0xC2)
          if opcode == 0xC3
            return [Constants::CMD_RET_near, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end
          if opcode == 0xC2
            return [Constants::CMD_RET_near, 0, 3, false, has_bytes?(pfx_cnt, 3, valid)]
          end

          # MOV r/m, imm (0xC6/0xC7)
          if opcode == 0xC6 || opcode == 0xC7
            is_8bit = (opcode == 0xC6)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            imm_sz = is_8bit ? 1 : (op32 ? 4 : 2)
            needed = 1 + mlen + imm_sz
            return [Constants::CMD_MOV, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # RET far (0xCB), RET far imm16 (0xCA)
          if opcode == 0xCB
            return [Constants::CMD_RET_far, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end
          if opcode == 0xCA
            return [Constants::CMD_RET_far, 0, 3, false, has_bytes?(pfx_cnt, 3, valid)]
          end

          # INT3 (0xCC)
          if opcode == 0xCC
            return [Constants::CMD_INT_INTO, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # INT imm8 (0xCD)
          if opcode == 0xCD
            return [Constants::CMD_INT_INTO, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # INTO (0xCE)
          if opcode == 0xCE
            return [Constants::CMD_INT_INTO, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # IRET (0xCF)
          if opcode == 0xCF
            return [Constants::CMD_IRET, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # Shift group (0xD0-0xD3)
          if opcode >= 0xD0 && opcode <= 0xD3
            is_8bit = (opcode & 1) == 0
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_Shift, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # CALL near (0xE8)
          if opcode == 0xE8
            needed = op32 ? 5 : 3
            return [Constants::CMD_CALL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # JMP near (0xE9)
          if opcode == 0xE9
            needed = op32 ? 5 : 3
            return [Constants::CMD_JMP, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # JMP far (0xEA)
          if opcode == 0xEA
            needed = op32 ? 7 : 5
            return [Constants::CMD_JMP, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # JMP short (0xEB)
          if opcode == 0xEB
            return [Constants::CMD_JMP, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # JCXZ (0xE3)
          if opcode == 0xE3
            return [Constants::CMD_JCXZ, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # LOOP/LOOPcc (0xE0-0xE2)
          if opcode >= 0xE0 && opcode <= 0xE2
            return [Constants::CMD_LOOP, 0, 2, false, has_bytes?(pfx_cnt, 2, valid)]
          end

          # CALL far (0x9A)
          if opcode == 0x9A
            needed = op32 ? 7 : 5
            return [Constants::CMD_CALL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # PUSHA (0x60), POPA (0x61)
          if opcode == 0x60
            return [Constants::CMD_PUSHA, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end
          if opcode == 0x61
            return [Constants::CMD_POPA, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # TEST/NOT/NEG/MUL/IMUL/DIV/IDIV ModR/M (0xF6/0xF7)
          if opcode == 0xF6 || opcode == 0xF7
            is_8bit = (opcode == 0xF6)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            reg_field = mrm_off < valid ? (bytes[mrm_off] >> 3) & 7 : 0
            if reg_field == 0  # TEST r/m, imm
              imm_sz = is_8bit ? 1 : (op32 ? 4 : 2)
              needed = 1 + mlen + imm_sz
              return [Constants::CMD_TEST, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 2  # NOT
              needed = 1 + mlen
              return [Constants::CMD_NOT, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 3  # NEG
              needed = 1 + mlen
              return [Constants::CMD_NEG, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 4  # MUL
              needed = 1 + mlen
              return [Constants::CMD_MUL, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 5  # IMUL
              needed = 1 + mlen
              return [Constants::CMD_IMUL, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 6  # DIV
              needed = 1 + mlen
              return [Constants::CMD_DIV, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            elsif reg_field == 7  # IDIV
              needed = 1 + mlen
              return [Constants::CMD_IDIV, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            end
          end

          # CLC (0xF8), STC (0xF9), CLI (0xFA), STI (0xFB)
          # CLD (0xFC), STD (0xFD), CMC (0xF5)
          case opcode
          when 0xF5 then return [Constants::CMD_CMC, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xF8 then return [Constants::CMD_CLC, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xF9 then return [Constants::CMD_STC, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xFA then return [Constants::CMD_CLI, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xFB then return [Constants::CMD_STI, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xFC then return [Constants::CMD_CLD, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          when 0xFD then return [Constants::CMD_STD, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # HLT (0xF4)
          if opcode == 0xF4
            return [Constants::CMD_HLT, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
          end

          # INC/DEC/CALL/JMP/PUSH ModR/M (0xFE/0xFF)
          if opcode == 0xFE || opcode == 0xFF
            is_8bit = (opcode == 0xFE)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            reg_field = mrm_off < valid ? (bytes[mrm_off] >> 3) & 7 : 0
            case reg_field
            when 0, 1  # INC/DEC
              return [Constants::CMD_INC_DEC, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
            when 2     # CALL near indirect
              return [Constants::CMD_CALL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
            when 4     # JMP near indirect
              return [Constants::CMD_JMP, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
            when 6     # PUSH r/m
              return [Constants::CMD_PUSH, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
            end
          end

          # String ops (0xA4-0xAF)
          case opcode
          when 0xA4, 0xA5  # MOVS
            return [Constants::CMD_MOVS, 0, 1, opcode == 0xA4, has_bytes?(pfx_cnt, 1, valid)]
          when 0xA6, 0xA7  # CMPS
            return [Constants::CMD_CMPS, 0, 1, opcode == 0xA6, has_bytes?(pfx_cnt, 1, valid)]
          when 0xAA, 0xAB  # STOS
            return [Constants::CMD_STOS, 0, 1, opcode == 0xAA, has_bytes?(pfx_cnt, 1, valid)]
          when 0xAC, 0xAD  # LODS
            return [Constants::CMD_LODS, 0, 1, opcode == 0xAC, has_bytes?(pfx_cnt, 1, valid)]
          when 0xAE, 0xAF  # SCAS
            return [Constants::CMD_SCAS, 0, 1, opcode == 0xAE, has_bytes?(pfx_cnt, 1, valid)]
          end

          # IMUL r, r/m, imm (0x69/0x6B)
          if opcode == 0x69
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            imm_sz = op32 ? 4 : 2
            needed = 1 + mlen + imm_sz
            return [Constants::CMD_IMUL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end
          if opcode == 0x6B
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen + 1
            return [Constants::CMD_IMUL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # Fallthrough: unknown opcode
          [Constants::CMD_NULL, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
        end

        # Decode 2-byte opcodes (0x0F xx)
        def decode_2byte(opcode, bytes, mrm_off, pfx_cnt, valid, op32, addr32)
          # Jcc near (0x0F 0x80-0x8F)
          if opcode >= 0x80 && opcode <= 0x8F
            needed = op32 ? 5 : 3  # opcode (already consumed 0F) + disp16/32
            return [Constants::CMD_Jcc, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # MOVZX (0x0F 0xB6/0xB7)
          if opcode == 0xB6 || opcode == 0xB7
            is_8bit = (opcode == 0xB6)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen  # 0F already consumed in prefix
            return [Constants::CMD_MOVZX, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # MOVSX (0x0F 0xBE/0xBF)
          if opcode == 0xBE || opcode == 0xBF
            is_8bit = (opcode == 0xBE)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_MOVSX, 0, needed, is_8bit, has_bytes?(pfx_cnt, needed, valid)]
          end

          # SETcc (0x0F 0x90-0x9F)
          if opcode >= 0x90 && opcode <= 0x9F
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_SETcc, 0, needed, true, has_bytes?(pfx_cnt, needed, valid)]
          end

          # IMUL r, r/m (0x0F 0xAF)
          if opcode == 0xAF
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_IMUL, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # BT/BTS/BTR/BTC (0x0F 0xA3, 0xAB, 0xB3, 0xBB)
          if [0xA3, 0xAB, 0xB3, 0xBB].include?(opcode)
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_BT, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # SHLD/SHRD (0x0F 0xA4/0xA5/0xAC/0xAD)
          if [0xA4, 0xAC].include?(opcode)  # imm8
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen + 1
            return [Constants::CMD_SHLD, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end
          if [0xA5, 0xAD].include?(opcode)  # CL
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_SHLD, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # BSF/BSR (0x0F 0xBC/0xBD)
          if opcode == 0xBC || opcode == 0xBD
            mlen = modregrm_len(bytes, mrm_off, valid, addr32)
            needed = 1 + mlen
            return [Constants::CMD_BSF, 0, needed, false, has_bytes?(pfx_cnt, needed, valid)]
          end

          # Unknown 2-byte opcode
          [Constants::CMD_NULL, 0, 1, false, has_bytes?(pfx_cnt, 1, valid)]
        end
      end
    end
  end
end
