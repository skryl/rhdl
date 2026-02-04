# file: rhdl/spec/support/assembler.rb
module Assembler
    class Program
      attr_reader :instructions
  
      # Initialize an empty list of instructions and empty label table.
      def initialize
        @instructions = []
        @labels = {}
        @unresolved = []
      end
  
      # Label the next instruction's address with +name+
      def label(name)
        @labels[name] = @instructions.size
      end
  
      # Add an instruction that may have an operand, which can be an integer or a symbol (label).
      #
      # e.g., instr(:JZ_LONG, :my_label)
      #       instr(:LDI, 0x40)
      def instr(opcode, operand = 0)
        if operand.is_a?(Array) && operand.size == 2
          # Indirect addressing: operand is [high_byte, low_byte]
          @instructions << [opcode, operand[0], operand[1]]
        else
          @instructions << [opcode, operand]
        end
      end
  
      # Once we have added all instructions (and labels), run finalize to convert label operands into addresses.
      def finalize(base_address = 0)
        # First pass: figure out how many bytes each instruction occupies to compute addresses.
        # nibble-based CPU typically uses 1 byte for single instructions plus 2 bytes for "long" instructions.
        # We'll build a "byte_offset" array that says where each instruction starts in memory.
  
        offsets = []
        current_address = 0
        @instructions.each_with_index do |instr, index|
          offsets << current_address
          opcode = instr[0]
          operand = instr[1]
          # Calculate instruction size based on opcode and operand
          if instr.size == 3
            # 3-element instruction (indirect addressing)
            current_address += 3
          elsif needs_four_bytes?(opcode)
            current_address += 3  # opcode + high byte + low byte
          elsif is_single_byte?(opcode)
            current_address += 1  # just opcode
          elsif opcode == :STA && !operand.is_a?(Symbol)
            # STA has special encoding: indirect (3 bytes), extended (2 bytes), or nibble (1 byte)
            if sta_can_use_nibble?(operand)
              current_address += 1  # Nibble-encoded (0x22-0x2F)
            else
              current_address += 2  # 2-byte direct (0x21 + operand)
            end
          elsif opcode == :LDA && !operand.is_a?(Symbol)
            # LDA has special encoding: indirect (3 bytes), direct (2 bytes), or nibble (1 byte)
            # 0x10 = indirect, 0x11 = direct, 0x12-0x1F = nibble
            if lda_can_use_nibble?(operand)
              current_address += 1  # Nibble-encoded (0x12-0x1F)
            else
              current_address += 2  # 2-byte direct (0x11 + operand)
            end
          elsif opcode == :CALL
            # CALL always uses 2-byte encoding to ensure correct label resolution
            current_address += 2
          elsif is_nibble_encoded?(opcode) && (!operand.is_a?(Symbol) && operand <= 0x0F)
            # Nibble-encoded with operand that fits in nibble
            current_address += 1
          elsif needs_two_bytes?(opcode) || (is_nibble_encoded?(opcode) && (!operand.is_a?(Symbol) && operand > 0x0F))
            # 2-byte instruction or nibble-encoded with operand > 0x0F
            current_address += 2
          else
            # Default: assume 1 byte for symbols that will be resolved
            current_address += 1
          end
        end
  
        # Now convert any label references into the correct offset from the "offsets" array.
        @instructions.each_with_index do |instr, index|
          opcode = instr[0]
          operand = instr[1]
          # Verify opcode is valid
          raise ArgumentError, "Unknown instruction: #{opcode}" unless valid_opcode?(opcode)

          if operand.is_a?(Symbol)
            # The instruction wants to jump to a label. Let's see which instruction that label is on:
            label_index = @labels[operand]
            raise "Unknown label #{operand.inspect}" unless label_index
            # Then the numeric address is base_address + offsets[label_index].
            absolute_address = base_address + offsets[label_index]
            @instructions[index][1] = absolute_address & 0xFF  # For 8-bit jumps

            # Handle 16-bit operands for opcodes that require them
            if needs_four_bytes?(opcode)
              high_byte = (absolute_address >> 8) & 0xFF
              low_byte = absolute_address & 0xFF
              @instructions[index] = [opcode, high_byte, low_byte]
            end
         end
       end
  
       # Convert instructions into flat byte array, splitting high and low bytes where necessary
       flat_instructions = []
       @instructions.each do |instr|
         case instr.size
         when 2
           opcode, operand = instr
           # Handle STA specially due to reserved opcodes (0x20=indirect, 0x21=extended)
           if opcode == :STA
             if sta_can_use_nibble?(operand)
               # Nibble-encoded: 0x22-0x2F
               flat_instructions << (0x20 | (operand & 0x0F))
             else
               # 2-byte direct STA: 0x21 + operand
               flat_instructions << 0x21
               flat_instructions << operand
             end
           # Handle LDA specially due to reserved opcodes (0x10=indirect, 0x11=direct)
           elsif opcode == :LDA
             if lda_can_use_nibble?(operand)
               # Nibble-encoded: 0x12-0x1F
               flat_instructions << (0x10 | (operand & 0x0F))
             else
               # 2-byte direct LDA: 0x11 + operand
               flat_instructions << 0x11
               flat_instructions << operand
             end
           # CALL always uses 2-byte encoding for consistent label resolution
           elsif opcode == :CALL
             flat_instructions << 0xC0  # CALL opcode
             flat_instructions << operand
           # Check if this is a nibble-encoded instruction (1 byte) AND operand fits in nibble
           elsif is_nibble_encoded?(opcode) && operand <= 0x0F
             # Encode as single byte: high nibble = opcode, low nibble = operand
             flat_instructions << (encode_opcode(opcode) | (operand & 0x0F))
           elsif is_single_byte?(opcode)
             # Single-byte instruction with no operand (e.g., HLT, NOT)
             flat_instructions << encode_opcode(opcode)
           elsif needs_four_bytes?(opcode)
             # Three-byte instruction: opcode + high byte + low byte
             high_byte = (operand >> 8) & 0xFF
             low_byte = operand & 0xFF
             flat_instructions << encode_opcode(opcode)
             flat_instructions << high_byte
             flat_instructions << low_byte
           else
             # Two-byte instruction: opcode + operand
             flat_instructions << encode_opcode(opcode)
             flat_instructions << operand
           end
         when 3
           opcode, high, low = instr
           if opcode == :STA
             # For indirect STA, encode as 0x20 followed by high and low bytes
             flat_instructions << 0x20  # STA opcode
             flat_instructions << high  # high byte address
             flat_instructions << low   # low byte address
           else
             flat_instructions << encode_opcode(opcode)
             flat_instructions << high
             flat_instructions << low
           end
         else
           raise "Unsupported instruction format: #{instr.inspect}"
         end
       end
  
       @instructions = flat_instructions
  
       @instructions
     end
  
    
    # Return true if this opcode occupies four bytes in memory (for 16-bit operands)
    def needs_four_bytes?(opcode)
      [:JMP_LONG, :JZ_LONG, :JNZ_LONG].include?(opcode)  # All long jump variants
    end
  
      private

      # Return true if this is a nibble-encoded instruction (1 byte total)
      # Note: STA is handled specially since 0x20 and 0x21 are reserved for indirect/extended
      def is_nibble_encoded?(opcode)
        [:NOP, :LDA, :ADD, :SUB, :AND, :OR, :XOR, :JZ, :JNZ, :JMP, :CALL, :RET, :DIV].include?(opcode)
      end

      # Check if STA operand can use nibble encoding
      # Only operands 2-15 (0x02-0x0F) can use nibble encoding
      # 0x20 = indirect STA, 0x21 = 2-byte direct STA
      def sta_can_use_nibble?(operand)
        operand.is_a?(Integer) && operand >= 2 && operand <= 0x0F
      end

      # Check if LDA operand can use nibble encoding
      # Only operands 2-15 (0x02-0x0F) can use nibble encoding
      # 0x10 = indirect LDA (3 bytes), 0x11 = 2-byte direct LDA
      def lda_can_use_nibble?(operand)
        operand.is_a?(Integer) && operand >= 2 && operand <= 0x0F
      end

      # Return true if this is a single-byte instruction with no operand
      def is_single_byte?(opcode)
        [:HLT, :NOT].include?(opcode)
      end

      # Return true if this opcode occupies two or more bytes in memory
      def needs_two_bytes?(opcode)
        # All non-nibble-encoded and non-single-byte instructions are multi-byte
        !is_nibble_encoded?(opcode) && !is_single_byte?(opcode)
      end
  
      def valid_opcode?(opcode)
        [
          :NOP, :LDA, :STA, :ADD, :SUB, :AND, :OR, :XOR,
          :JZ, :JNZ, :LDI, :JMP, :CALL, :RET, :DIV, :HLT,
          :MUL, :NOT, :JZ_LONG, :JMP_LONG, :JNZ_LONG, :CMP
        ].include?(opcode)
      end
  
      def encode_opcode(opcode)
        case opcode
        when :NOP  then 0x00
        when :LDA  then 0x10
        when :STA  then 0x20
        when :ADD  then 0x30
        when :SUB  then 0x40
        when :AND  then 0x50
        when :OR   then 0x60
        when :XOR  then 0x70
        when :JZ   then 0x80
        when :JNZ  then 0x90
        when :LDI  then 0xA0
        when :JMP  then 0xB0
        when :CALL then 0xC0
        when :RET  then 0xD0
        when :DIV  then 0xE0
        when :HLT  then 0xF0
        when :MUL  then 0xF1
        when :NOT  then 0xF2
        when :CMP  then 0xF3
        when :JZ_LONG  then 0xF8
        when :JMP_LONG then 0xF9
        when :JNZ_LONG then 0xFA
        else
          raise ArgumentError, "Unknown opcode: #{opcode}"
        end
      end
    end
  
    # Helper method so we can do something like:
    #
    #   program = Assembler.build do |p|
    #     p.label :start
    #     p.instr :LDA, 0xE
    #     p.instr :JZ_LONG, :halt
    #     p.label :loop
    #     ...
    #     p.label :halt
    #     p.instr :HLT
    #   end
    #
    #   program.finalize
    #
    def self.build(base_address = 0)
      prog = Program.new
      yield prog
      prog.finalize(base_address)
      prog.instructions
    end
  end