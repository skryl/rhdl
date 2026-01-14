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
      def finalize
        # First pass: figure out how many bytes each instruction occupies to compute addresses.
        # nibble-based CPU typically uses 1 byte for single instructions plus 2 bytes for "long" instructions.
        # We'll build a "byte_offset" array that says where each instruction starts in memory.
  
        offsets = []
        current_address = 0
        @instructions.each_with_index do |(opcode, operand), index|
          offsets << current_address
          if needs_two_bytes?(opcode)
            if needs_four_bytes?(opcode)
              current_address += 3  # opcode + high byte + low byte
            else
              current_address += 2  # opcode + operand
            end
          else
            current_address += 1
          end
        end
  
        # Now convert any label references into the correct offset from the "offsets" array.
        @instructions.each_with_index do |(opcode, operand), index|
          # Verify opcode is valid
          raise ArgumentError, "Unknown instruction: #{opcode}" unless valid_opcode?(opcode)
          
          if operand.is_a?(Symbol)
            # The instruction wants to jump to a label. Let's see which instruction that label is on:
            label_index = @labels[operand]
            raise "Unknown label #{operand.inspect}" unless label_index
            # Then the numeric address is offsets[label_index].
            @instructions[index][1] = offsets[label_index] & 0xFF  # your CPU is 8-bit, so mask it
           
            # Handle 16-bit operands for opcodes that require them
            if needs_four_bytes?(opcode)
              high_byte = (offsets[label_index] >> 8) & 0xFF
              low_byte = offsets[label_index] & 0xFF
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
           # Check if this is a nibble-encoded instruction (1 byte)
           if is_nibble_encoded?(opcode)
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
      def is_nibble_encoded?(opcode)
        [:NOP, :LDA, :STA, :ADD, :SUB, :AND, :OR, :XOR, :JZ, :JNZ, :JMP, :CALL, :RET, :DIV].include?(opcode)
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
    def self.build
      prog = Program.new
      yield prog
      prog.finalize
      prog.instructions
    end
  end