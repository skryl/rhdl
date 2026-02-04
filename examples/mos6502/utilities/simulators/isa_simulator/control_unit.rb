module RHDL
  module Components
    module CPU
      class ControlUnit < RHDL::Component

        class << self
          def define_ports
            input :clk
            input :rst
            input :ir, width: 8
            input :zero_flag
            output :pc_inc
            output :pc_load
            output :acc_load
            output :mar_load
            output :ram_load
            output :alu_op, width: 4
            output :halted
            output :sp_dec
            output :sp_inc
            output :call_mode
            output :ret_mode
          end
        end

        attr_reader :opcode, :operand, :halted, :current_instruction

        def initialize
          @current_instruction = 0
          @opcode = 0
          @operand = 0
          @halted = false
          @call_mode = false
          @ret_mode = false
          reset
        end

        def reset
          @current_instruction = 0
          @opcode = :NOP
          @operand = 0
          @halted = false
          @call_mode = false
          @ret_mode = false
        end

        def decode(instruction, memory, pc)
          opcode = (instruction & 0xF0)
          operand = (instruction & 0x0F)

          case opcode
          when 0xA0
            [:LDI, memory.read(pc + 1)]
          when 0xF0
            case instruction
            when 0xF0 then [:HLT, 0]
            when 0xF1 then [:MUL, memory.read(pc + 1)]
            when 0xF2 then [:NOT, 0]
            when 0xF3 then [:CMP, memory.read(pc + 1)]
            when 0xF8 then [:JZ_LONG, memory.read(pc + 1)]
            when 0xF9 then [:JMP_LONG, memory.read(pc + 1)]
            when 0xFA then [:JNZ_LONG, memory.read(pc + 1)]
            else
              raise "Unknown F0-series opcode: #{instruction.to_s(16)}"
            end
          when 0x20
            if instruction == 0x20  # Indirect STA
              [:STA, [memory.read(pc + 1), memory.read(pc + 2)]]
            else  # Direct STA
              [:STA, memory.read(pc + 1)]
            end
          else
            # Handle other single-byte instructions
            single_byte_map = {
              0x00 => :NOP,
              0x10 => :LDA,
              0x30 => :ADD,
              0x40 => :SUB,
              0x50 => :AND,
              0x60 => :OR,
              0x70 => :XOR,
              0x80 => :JZ,
              0x90 => :JNZ,
              0xB0 => :JMP,
              0xC0 => :CALL,
              0xD0 => :RET,
              0xE0 => :DIV
            }
            opcode_symbol = single_byte_map[opcode]
            if opcode_symbol
              if [:LDI, :LDA, :ADD, :SUB, :AND, :OR, :XOR, :JZ, :JNZ, :JMP, :CALL, :MUL, :NOT, :DIV].include?(opcode_symbol)
                [:OP, opcode_symbol, operand]
              else
                [opcode_symbol, 0]
              end
            else
              raise "Unknown opcode: #{instruction.to_s(16)}"
            end
          end
        end

        def get_alu_op
          case @opcode
          when :ADD, :SUB, :AND, :OR, :XOR, :NOT, :MUL, :DIV
            @opcode
          else
            0x0  # default to ADD
          end
        end

        def is_memory_read?
          [:LDA, :ADD, :SUB, :AND, :OR, :XOR, :CMP].include?(@opcode)
        end

        def is_memory_write?
          [:STA, :STA_INDIRECT].include?(@opcode)
        end

        def is_jump?
          [:JMP, :JZ, :JNZ].include?(@opcode)
        end

        def is_call?
          @opcode == :CALL
        end

        def is_return?
          @opcode == :RET
        end

        def is_halt?
          @opcode == :HLT
        end

        def tick
          # Reset control signals
          @pc_inc = false
          @pc_load = false
          @acc_load = false
          @mar_load = false
          @ram_load = false
          @halted = false
          @sp_dec = false
          @sp_inc = false
          @call_mode = false
          @ret_mode = false

          # Set control signals based on current instruction
          case @opcode
          when :NOP
            @pc_inc = true
          when :LDA
            @mar_load = true
            @acc_load = true
            @pc_inc = true
          when :STA
            @mar_load = true
            @ram_load = true
            @pc_inc = true
          when :STA_INDIRECT
            @mar_load = true
            @ram_load = true
            @pc_inc = true
          when :ADD, :SUB, :AND, :OR, :XOR, :MUL, :DIV
            @mar_load = true
            @acc_load = true
            @pc_inc = true
          when :JZ
            if @zero_flag
              @pc_load = true
            else
              @pc_inc = true
            end
          when :JNZ
            if !@zero_flag
              @pc_load = true
            else
              @pc_inc = true
            end
          when :LDI
            @acc_load = true
            @pc_inc = true
          when :JMP
            @pc_load = true
          when :CALL
            @sp_dec = true
            @ram_load = true
            @pc_load = true
            @call_mode = true
          when :RET
            @sp_inc = true
            @pc_load = true
            @ret_mode = true
          when :NOT
            @acc_load = true
            @pc_inc = true
          when :HLT
            @halted = true
          end
        end
      end
    end
  end
end
