# MOS 6502 Assembler
# Simple two-pass assembler for 6502 assembly language

module MOS6502
  class Assembler
    # Instruction definitions: mnemonic => { mode => [opcode, size] }
    INSTRUCTIONS = {
      'ADC' => { imm: [0x69, 2], zp: [0x65, 2], zpx: [0x75, 2], abs: [0x6D, 3],
                 absx: [0x7D, 3], absy: [0x79, 3], indx: [0x61, 2], indy: [0x71, 2] },
      'AND' => { imm: [0x29, 2], zp: [0x25, 2], zpx: [0x35, 2], abs: [0x2D, 3],
                 absx: [0x3D, 3], absy: [0x39, 3], indx: [0x21, 2], indy: [0x31, 2] },
      'ASL' => { acc: [0x0A, 1], zp: [0x06, 2], zpx: [0x16, 2], abs: [0x0E, 3], absx: [0x1E, 3] },
      'BCC' => { rel: [0x90, 2] },
      'BCS' => { rel: [0xB0, 2] },
      'BEQ' => { rel: [0xF0, 2] },
      'BIT' => { zp: [0x24, 2], abs: [0x2C, 3] },
      'BMI' => { rel: [0x30, 2] },
      'BNE' => { rel: [0xD0, 2] },
      'BPL' => { rel: [0x10, 2] },
      'BRK' => { imp: [0x00, 1] },
      'BVC' => { rel: [0x50, 2] },
      'BVS' => { rel: [0x70, 2] },
      'CLC' => { imp: [0x18, 1] },
      'CLD' => { imp: [0xD8, 1] },
      'CLI' => { imp: [0x58, 1] },
      'CLV' => { imp: [0xB8, 1] },
      'CMP' => { imm: [0xC9, 2], zp: [0xC5, 2], zpx: [0xD5, 2], abs: [0xCD, 3],
                 absx: [0xDD, 3], absy: [0xD9, 3], indx: [0xC1, 2], indy: [0xD1, 2] },
      'CPX' => { imm: [0xE0, 2], zp: [0xE4, 2], abs: [0xEC, 3] },
      'CPY' => { imm: [0xC0, 2], zp: [0xC4, 2], abs: [0xCC, 3] },
      'DEC' => { zp: [0xC6, 2], zpx: [0xD6, 2], abs: [0xCE, 3], absx: [0xDE, 3] },
      'DEX' => { imp: [0xCA, 1] },
      'DEY' => { imp: [0x88, 1] },
      'EOR' => { imm: [0x49, 2], zp: [0x45, 2], zpx: [0x55, 2], abs: [0x4D, 3],
                 absx: [0x5D, 3], absy: [0x59, 3], indx: [0x41, 2], indy: [0x51, 2] },
      'INC' => { zp: [0xE6, 2], zpx: [0xF6, 2], abs: [0xEE, 3], absx: [0xFE, 3] },
      'INX' => { imp: [0xE8, 1] },
      'INY' => { imp: [0xC8, 1] },
      'JMP' => { abs: [0x4C, 3], ind: [0x6C, 3] },
      'JSR' => { abs: [0x20, 3] },
      'LDA' => { imm: [0xA9, 2], zp: [0xA5, 2], zpx: [0xB5, 2], abs: [0xAD, 3],
                 absx: [0xBD, 3], absy: [0xB9, 3], indx: [0xA1, 2], indy: [0xB1, 2] },
      'LDX' => { imm: [0xA2, 2], zp: [0xA6, 2], zpy: [0xB6, 2], abs: [0xAE, 3], absy: [0xBE, 3] },
      'LDY' => { imm: [0xA0, 2], zp: [0xA4, 2], zpx: [0xB4, 2], abs: [0xAC, 3], absx: [0xBC, 3] },
      'LSR' => { acc: [0x4A, 1], zp: [0x46, 2], zpx: [0x56, 2], abs: [0x4E, 3], absx: [0x5E, 3] },
      'NOP' => { imp: [0xEA, 1] },
      'ORA' => { imm: [0x09, 2], zp: [0x05, 2], zpx: [0x15, 2], abs: [0x0D, 3],
                 absx: [0x1D, 3], absy: [0x19, 3], indx: [0x01, 2], indy: [0x11, 2] },
      'PHA' => { imp: [0x48, 1] },
      'PHP' => { imp: [0x08, 1] },
      'PLA' => { imp: [0x68, 1] },
      'PLP' => { imp: [0x28, 1] },
      'ROL' => { acc: [0x2A, 1], zp: [0x26, 2], zpx: [0x36, 2], abs: [0x2E, 3], absx: [0x3E, 3] },
      'ROR' => { acc: [0x6A, 1], zp: [0x66, 2], zpx: [0x76, 2], abs: [0x6E, 3], absx: [0x7E, 3] },
      'RTI' => { imp: [0x40, 1] },
      'RTS' => { imp: [0x60, 1] },
      'SBC' => { imm: [0xE9, 2], zp: [0xE5, 2], zpx: [0xF5, 2], abs: [0xED, 3],
                 absx: [0xFD, 3], absy: [0xF9, 3], indx: [0xE1, 2], indy: [0xF1, 2] },
      'SEC' => { imp: [0x38, 1] },
      'SED' => { imp: [0xF8, 1] },
      'SEI' => { imp: [0x78, 1] },
      'STA' => { zp: [0x85, 2], zpx: [0x95, 2], abs: [0x8D, 3],
                 absx: [0x9D, 3], absy: [0x99, 3], indx: [0x81, 2], indy: [0x91, 2] },
      'STX' => { zp: [0x86, 2], zpy: [0x96, 2], abs: [0x8E, 3] },
      'STY' => { zp: [0x84, 2], zpx: [0x94, 2], abs: [0x8C, 3] },
      'TAX' => { imp: [0xAA, 1] },
      'TAY' => { imp: [0xA8, 1] },
      'TSX' => { imp: [0xBA, 1] },
      'TXA' => { imp: [0x8A, 1] },
      'TXS' => { imp: [0x9A, 1] },
      'TYA' => { imp: [0x98, 1] }
    }

    # Branch instructions for relative addressing
    BRANCH_INSTRUCTIONS = %w[BCC BCS BEQ BMI BNE BPL BVC BVS]

    def initialize
      @labels = {}
      @origin = 0x8000
    end

    def assemble(source, origin = 0x8000)
      @origin = origin
      @labels = {}

      lines = preprocess(source)

      # Pass 1: Collect labels
      pass1(lines)

      # Pass 2: Generate code
      pass2(lines)
    end

    private

    def preprocess(source)
      source.lines.map do |line|
        # Remove comments
        line = line.split(';').first || ''
        line.strip
      end.reject(&:empty?)
    end

    def pass1(lines)
      pc = @origin

      lines.each do |line|
        # Handle equates
        if line =~ /^([A-Za-z_]\w*)\s*=\s*(.+)$/
          label = $1.upcase
          @labels[label] = resolve_value($2, pc)
          next
        end

        # Check for label
        if line =~ /^(\w+):(.*)$/
          label = $1.upcase
          @labels[label] = pc
          line = $2.strip
        end

        # Check for directives
        if line =~ /^\*\s*=\s*(.+)$/
          pc = resolve_value($1, pc)
          next
        end

        if line =~ /^\.ORG\s+(.+)/i
          pc = resolve_value($1, pc)
          next
        end

        if line =~ /^\.BYTE\s+(.+)/i
          bytes = parse_byte_list($1, pc)
          pc += bytes.length
          next
        end

        if line =~ /^\.WORD\s+(.+)/i
          words = parse_word_list($1)
          pc += words.length * 2
          next
        end

        if line =~ /^\.END/i
          break
        end

        # Skip empty lines after label extraction
        next if line.empty?

        # Parse instruction
        mnemonic, operand = parse_instruction(line)
        next unless mnemonic

        mode, _ = determine_mode(mnemonic, operand, pc)
        info = INSTRUCTIONS[mnemonic]&.[](mode)
        if info
          pc += info[1]
        else
          raise "Unknown instruction: #{line}"
        end
      end
    end

    def pass2(lines)
      bytes = []
      pc = @origin

      lines.each do |line|
        # Handle equates
        if line =~ /^([A-Za-z_]\w*)\s*=\s*(.+)$/
          next
        end

        # Remove label
        if line =~ /^(\w+):(.*)$/
          line = $2.strip
        end

        # Handle directives
        if line =~ /^\*\s*=\s*(.+)$/
          pc = resolve_value($1, pc)
          next
        end

        if line =~ /^\.ORG\s+(.+)/i
          pc = resolve_value($1, pc)
          next
        end

        if line =~ /^\.BYTE\s+(.+)/i
          data = parse_byte_list($1, pc)
          bytes.concat(data)
          pc += data.length
          next
        end

        if line =~ /^\.WORD\s+(.+)/i
          words = parse_word_list($1)
          words.each do |w|
            resolved = resolve_value(w, pc)
            bytes << (resolved & 0xFF)
            bytes << ((resolved >> 8) & 0xFF)
            pc += 2
          end
          next
        end

        if line =~ /^\.END/i
          next
        end

        next if line.empty?

        # Parse and encode instruction
        mnemonic, operand = parse_instruction(line)
        next unless mnemonic

        mode, value = determine_mode(mnemonic, operand, pc)
        info = INSTRUCTIONS[mnemonic]&.[](mode)

        unless info
          raise "Invalid addressing mode for #{mnemonic}: #{operand}"
        end

        opcode, size = info

        # Handle relative addressing for branches
        if mode == :rel
          target = resolve_value(value, pc)
          offset = target - (pc + 2)
          if offset < -128 || offset > 127
            raise "Branch target out of range: #{line}"
          end
          bytes << opcode
          bytes << (offset & 0xFF)
        elsif size == 1
          bytes << opcode
        elsif size == 2
          resolved = resolve_value(value, pc)
          bytes << opcode
          bytes << (resolved & 0xFF)
        elsif size == 3
          resolved = resolve_value(value, pc)
          bytes << opcode
          bytes << (resolved & 0xFF)
          bytes << ((resolved >> 8) & 0xFF)
        end

        pc += size
      end

      bytes
    end

    def parse_instruction(line)
      return nil, nil if line.empty?

      parts = line.split(/\s+/, 2)
      mnemonic = parts[0].upcase
      operand = parts[1]&.strip || ''

      [mnemonic, operand]
    end

    def determine_mode(mnemonic, operand, pc)
      return [:imp, nil] if operand.empty? || operand.nil?

      # Accumulator
      if operand.upcase == 'A'
        return [:acc, nil]
      end

      # Immediate: #$xx or #xx
      if operand =~ /^#(.+)$/
        return [:imm, $1]
      end

      # Indexed indirect: ($xx,X)
      if operand =~ /^\((.+),\s*X\)$/i
        return [:indx, $1]
      end

      # Indirect indexed: ($xx),Y
      if operand =~ /^\((.+)\),\s*Y$/i
        return [:indy, $1]
      end

      # Indirect: ($xxxx)
      if operand =~ /^\((.+)\)$/
        return [:ind, $1]
      end

      # Absolute,X or Zero Page,X
      if operand =~ /^(.+),\s*X$/i
        value_str = $1
        value = resolve_value(value_str, pc)
        if value <= 0xFF && !INSTRUCTIONS[mnemonic][:absx]
          return [:zpx, value_str]
        elsif value <= 0xFF && INSTRUCTIONS[mnemonic][:zpx]
          return [:zpx, value_str]
        else
          return [:absx, value_str]
        end
      end

      # Absolute,Y or Zero Page,Y
      if operand =~ /^(.+),\s*Y$/i
        value_str = $1
        value = resolve_value(value_str, pc)
        if value <= 0xFF && INSTRUCTIONS[mnemonic][:zpy]
          return [:zpy, value_str]
        else
          return [:absy, value_str]
        end
      end

      # Branch (relative)
      if BRANCH_INSTRUCTIONS.include?(mnemonic)
        return [:rel, operand]
      end

      # Zero page or Absolute
      value = resolve_value(operand, pc)
      if value <= 0xFF && INSTRUCTIONS[mnemonic][:zp]
        return [:zp, operand]
      else
        return [:abs, operand]
      end
    end

    def resolve_value(str, pc = @origin)
      return 0 if str.nil? || str.empty?

      str = str.strip

      # Expression with < (low byte) or > (high byte)
      if str =~ /^<(.+)$/
        value = resolve_value($1, pc)
        return value & 0xFF
      end

      if str =~ /^>(.+)$/
        value = resolve_value($1, pc)
        return (value >> 8) & 0xFF
      end

      # Expression with +/-
      if str =~ /[+\-]/
        return evaluate_expression(str, pc)
      end

      # Label reference
      if str =~ /^[A-Za-z_]\w*$/
        label = str.upcase
        return @labels[label] if @labels[label]
        return 0  # Will be resolved in pass 2
      end

      # Current location counter
      if str == '*'
        return pc
      end

      # Hex: $xx or $xxxx
      if str =~ /^\$([0-9A-Fa-f]+)$/
        return $1.to_i(16)
      end

      # Binary: %xxxxxxxx
      if str =~ /^%([01]+)$/
        return $1.to_i(2)
      end

      # Decimal
      if str =~ /^(\d+)$/
        return $1.to_i
      end

      0
    end

    def evaluate_expression(str, pc)
      tokens = str.delete(' ').scan(/[+\-]?[^+\-]+/)
      total = 0

      tokens.each do |token|
        sign = 1
        if token.start_with?('+', '-')
          sign = token[0] == '-' ? -1 : 1
          token = token[1..]
        end

        value = resolve_value(token, pc)
        total += sign * value
      end

      total
    end

    def parse_byte_list(str, pc)
      str.split(',').map do |item|
        item = item.strip
        if item =~ /^"(.+)"$/
          $1.bytes
        else
          [resolve_value(item, pc) & 0xFF]
        end
      end.flatten
    end

    def parse_word_list(str)
      str.split(',').map(&:strip)
    end
  end
end
