require_relative 'control_unit'
require_relative 'cpu_alu'

module RHDL
  module Components
    module CPU
      class CPU < RHDL::Component
        attr_reader :pc, :acc, :zero_flag, :halted, :sp
        attr_accessor :memory

        def initialize(memory)
          @memory = memory
          @control_unit = ControlUnit.new
          @alu = CpuALU.new
          reset
        end

        def reset
          @pc = 0
          @acc = 0
          @zero_flag = false
          @halted = false
          @sp = 0xFF  # Stack starts at the end of memory
          @control_unit.reset
          @alu.reset
        end

        def step
          # Add a line here to print CPU state before decoding:
          Debug.log("PC=0x#{@pc.to_s(16)}, ACC=0x#{@acc.to_s(16)}, ZERO=#{@zero_flag}, SP=0x#{@sp.to_s(16)}")

          # Fetch
          instruction = @memory.read(@pc)

          # Decode
          # For single-byte instructions, opcode is top nibble, operand is low nibble.
          # For multi-byte jump instructions, handle separately.
          opcode_byte = instruction & 0xF0
          operand_nibble = instruction & 0x0F

          case opcode_byte
          when 0xA0  # LDI
            opcode = :LDI
            operand = @memory.read(@pc + 1) & 0xFF
            pc_increment = 2
          when 0x20  # STA
            if instruction == 0x20  # Indirect STA (exactly 0x20)
              opcode = :STA
              # This is a 3-byte STA instruction with indirect addressing
              high_addr = @memory.read(@pc + 1)
              low_addr = @memory.read(@pc + 2)
              operand = [high_addr, low_addr]
              pc_increment = 3
            elsif instruction == 0x21  # 2-byte direct STA
              opcode = :STA
              operand = @memory.read(@pc + 1)
              pc_increment = 2
            else  # Direct STA (0x22-0x2F, nibble-encoded)
              opcode = :STA
              operand = operand_nibble
              pc_increment = 1
            end
          when 0xF0
            # Could be HLT (0xF0), MUL (0xF1), NOT (0xF2), JZ_LONG (0xF8), JMP_LONG (0xF9), JNZ_LONG (0xFA)
            case instruction
            when 0xF0 then opcode = :HLT;  operand = 0;   pc_increment = 1
            when 0xF1 then opcode = :MUL;  operand = @memory.read(@pc + 1) & 0xFF; pc_increment = 2
            when 0xF2 then opcode = :NOT;  operand = 0;   pc_increment = 1
            when 0xF3 then opcode = :CMP;  operand = @memory.read(@pc + 1) & 0xFF; pc_increment = 2
            when 0xF8 then opcode = :JZ_LONG; operand = (@memory.read(@pc + 1) << 8) | @memory.read(@pc + 2); pc_increment = 3
            when 0xF9 then opcode = :JMP_LONG; operand = (@memory.read(@pc + 1) << 8) | @memory.read(@pc + 2); pc_increment = 3
            when 0xFA then opcode = :JNZ_LONG; operand = (@memory.read(@pc + 1) << 8) | @memory.read(@pc + 2); pc_increment = 3
            else
              raise "Unknown F0-series opcode: #{instruction.to_s(16)}"
            end
          else
            # All other single-byte instructions
            opcode = case opcode_byte
                     when 0x00 then :NOP
                     when 0x10 then :LDA
                     when 0x30 then :ADD
                     when 0x40 then :SUB
                     when 0x50 then :AND
                     when 0x60 then :OR
                     when 0x70 then :XOR
                     when 0x80 then :JZ
                     when 0x90 then :JNZ
                     when 0xB0 then :JMP
                     when 0xC0 then :CALL
                     when 0xD0 then :RET
                     when 0xE0 then :DIV
                     else
                       raise "Unknown single-byte opcode: #{instruction.to_s(16)}"
                     end
            operand = operand_nibble
            pc_increment = 1
          end

          Debug.log("Decoded opcode: #{opcode}, operand: #{operand}")

          # Execute
          case opcode
          when :LDI
            @acc = operand & 0xFF
            @zero_flag = (@acc == 0)
            Debug.log("Executed LDI: Loaded 0x#{@acc.to_s(16)} into Accumulator")
            @pc += pc_increment

          when :MUL
            multiplicand = @memory.read(operand & 0xFF) & 0xFF
            @alu.a = @acc
            @alu.b = multiplicand
            @alu.op = :MUL
            @alu.operate
            @acc = @alu.result
            @zero_flag = @alu.zero_flag
            Debug.log("MUL: 0x#{@alu.a.to_s(16)} * 0x#{@alu.b.to_s(16)} = 0x#{@acc.to_s(16)}")
            @pc += pc_increment

          when :NOP
            @pc += 1

          when :LDA
            @acc = @memory.read(operand & 0xFF) & 0xFF
            @zero_flag = (@acc == 0)
            Debug.log("LDA: Loaded 0x#{@acc.to_s(16)} from memory[0x#{(operand & 0xFF).to_s(16)}]")
            @pc += pc_increment

          when :STA
            if operand.is_a?(Array)
              # Indirect addressing - operand contains memory addresses of high/low bytes
              high = @memory.read(operand[0]) & 0xFF
              low = @memory.read(operand[1]) & 0xFF
              addr = (high << 8) | low
              Debug.log("STA indirect: high_addr=0x#{operand[0].to_s(16)}, low_addr=0x#{operand[1].to_s(16)}, high=0x#{high.to_s(16)}, low=0x#{low.to_s(16)}, addr=0x#{addr.to_s(16)}")
              @memory.write(addr, @acc)
              Debug.log("STA: Stored 0x#{@acc.to_s(16)} to memory[0x#{addr.to_s(16)}] (indirect)")
            else
              # Direct addressing (nibble-encoded)
              @memory.write(operand, @acc)
              Debug.log("STA: Stored 0x#{@acc.to_s(16)} to memory[0x#{operand.to_s(16)}]")
            end
            @pc += pc_increment

          when :ADD, :SUB, :AND, :OR, :XOR, :DIV
            @alu.a = @acc
            @alu.b = @memory.read(operand & 0xFF) & 0xFF
            @alu.op = opcode
            Debug.log("ALU operation: #{opcode}, a=0x#{@alu.a.to_s(16)}, b=0x#{@alu.b.to_s(16)}")
            @alu.operate
            @acc = @alu.result
            @zero_flag = @alu.zero_flag
            Debug.log("ALU result=0x#{@acc.to_s(16)}")
            @pc += pc_increment

          when :NOT
            @alu.a = @acc
            @alu.op = :NOT
            @alu.operate
            @acc = @alu.result
            @zero_flag = @alu.zero_flag
            Debug.log("NOT: ~a=0x#{@acc.to_s(16)}")
            @pc += pc_increment

          when :JZ
            if @zero_flag
              Debug.log("JZ: zero_flag is true → PC=0x#{operand.to_s(16)}")
              @pc = operand & 0xFF
            else
              @pc += pc_increment
            end

          when :JNZ
            if !@zero_flag
              Debug.log("JNZ: zero_flag is false → PC=0x#{operand.to_s(16)}")
              @pc = operand & 0xFF
            else
              @pc += pc_increment
            end

          when :JMP
            Debug.log("JMP → PC=0x#{operand.to_s(16)}")
            @pc = operand & 0xFF

          when :CALL
            if @sp == 0x00
              @halted = true
              Debug.log("Stack Overflow (CALL). Halting CPU.")
            else
              @memory.write(@sp, (@pc + pc_increment) & 0xFF)
              @sp = (@sp - 1) & 0xFF
              @pc = operand & 0xFF
              Debug.log("CALL: Return addr=0x#{(@pc + pc_increment).to_s(16)}, SP=0x#{@sp.to_s(16)}, PC=0x#{@pc.to_s(16)}")
            end

          when :RET
            if @sp == 0xFF
              @halted = true
              Debug.log("Stack Underflow (RET). Halting CPU.")
            else
              @sp = (@sp + 1) & 0xFF
              @pc = @memory.read(@sp) & 0xFF
              Debug.log("RET: PC=0x#{@pc.to_s(16)}, SP=0x#{@sp.to_s(16)}")
            end

          when :HLT
            @halted = true
            Debug.log("HLT: Halting CPU.")

          when :JZ_LONG
            if @zero_flag
              Debug.log("JZ_LONG: zero_flag is true → PC=0x#{operand.to_s(16)}")
              @pc = operand & 0xFFFF  # 16-bit address
            else
              @pc += pc_increment
            end

          when :JMP_LONG
            Debug.log("JMP_LONG → PC=0x#{operand.to_s(16)}")
            @pc = operand & 0xFFFF  # 16-bit address

          when :JNZ_LONG
            if !@zero_flag
              Debug.log("JNZ_LONG: zero_flag is false → PC=0x#{operand.to_s(16)}")
              @pc = operand & 0xFFFF  # 16-bit address
            else
              @pc += pc_increment
            end

          when :CMP
            # CMP: Compare ACC with memory[operand].
            # Sets zero_flag if ACC == memory[operand].
            # Does not store the result back into ACC.
            addr = operand
            mem_val = @memory.read(addr) & 0xFF
            result = (@acc - mem_val) & 0xFF
            @zero_flag = (result == 0)
            Debug.log("CMP: ACC=0x#{@acc.to_s(16)}, mem[0x#{addr.to_s(16)}]=0x#{mem_val.to_s(16)}, zero_flag=#{@zero_flag}")
            @pc += pc_increment

          else
            raise "Unknown opcode symbol: #{opcode}"
          end
        end
      end
    end
  end
end
