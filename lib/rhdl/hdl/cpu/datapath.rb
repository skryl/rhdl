# CPU Datapath - HDL Implementation
# This implements the CPU datapath using gate-level HDL components

module RHDL
  module HDL
    module CPU
      # Instruction decoder - decodes opcode byte to control signals
      class InstructionDecoder < SimComponent
        # Opcodes matching the behavioral CPU
        OPCODES = {
          NOP: 0x00, LDA: 0x10, STA: 0x20, ADD: 0x30,
          SUB: 0x40, AND: 0x50, OR: 0x60, XOR: 0x70,
          JZ: 0x80, JNZ: 0x90, LDI: 0xA0, JMP: 0xB0,
          CALL: 0xC0, RET: 0xD0, DIV: 0xE0,
          HLT: 0xF0, MUL: 0xF1, NOT: 0xF2, CMP: 0xF3,
          JZ_LONG: 0xF8, JMP_LONG: 0xF9, JNZ_LONG: 0xFA
        }

        def setup_ports
          input :instruction, width: 8
          input :zero_flag

          # Control signals
          output :alu_op, width: 4       # ALU operation
          output :alu_src              # 0 = register, 1 = immediate
          output :reg_write            # Write to accumulator
          output :mem_read             # Read from memory
          output :mem_write            # Write to memory
          output :branch               # Branch instruction
          output :jump                 # Unconditional jump
          output :pc_src, width: 2     # PC source: 0=+1, 1=operand, 2=long addr
          output :halt                 # Halt CPU
          output :call                 # Call instruction
          output :ret                  # Return instruction
          output :instr_length, width: 2  # 1, 2, or 3 bytes
        end

        def propagate
          instr = in_val(:instruction)
          opcode = instr & 0xF0
          zero = in_val(:zero_flag)

          # Default all outputs to 0
          out_set(:alu_op, 0)
          out_set(:alu_src, 0)
          out_set(:reg_write, 0)
          out_set(:mem_read, 0)
          out_set(:mem_write, 0)
          out_set(:branch, 0)
          out_set(:jump, 0)
          out_set(:pc_src, 0)
          out_set(:halt, 0)
          out_set(:call, 0)
          out_set(:ret, 0)
          out_set(:instr_length, 1)

          case opcode
          when 0x00  # NOP
            # Do nothing

          when 0x10  # LDA
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x20  # STA
            out_set(:mem_write, 1)
            if instr == 0x20  # Indirect (3 bytes)
              out_set(:instr_length, 3)
            elsif instr == 0x21  # Direct 2-byte
              out_set(:instr_length, 2)
            end

          when 0x30  # ADD
            out_set(:alu_op, ALU::OP_ADD)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x40  # SUB
            out_set(:alu_op, ALU::OP_SUB)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x50  # AND
            out_set(:alu_op, ALU::OP_AND)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x60  # OR
            out_set(:alu_op, ALU::OP_OR)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x70  # XOR
            out_set(:alu_op, ALU::OP_XOR)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0x80  # JZ
            out_set(:branch, 1)
            out_set(:pc_src, zero == 1 ? 1 : 0)

          when 0x90  # JNZ
            out_set(:branch, 1)
            out_set(:pc_src, zero == 0 ? 1 : 0)

          when 0xA0  # LDI
            out_set(:alu_src, 1)  # Immediate
            out_set(:reg_write, 1)
            out_set(:instr_length, 2)

          when 0xB0  # JMP
            out_set(:jump, 1)
            out_set(:pc_src, 1)

          when 0xC0  # CALL
            out_set(:call, 1)
            out_set(:pc_src, 1)

          when 0xD0  # RET
            out_set(:ret, 1)

          when 0xE0  # DIV
            out_set(:alu_op, ALU::OP_DIV)
            out_set(:mem_read, 1)
            out_set(:reg_write, 1)

          when 0xF0
            case instr
            when 0xF0  # HLT
              out_set(:halt, 1)
            when 0xF1  # MUL
              out_set(:alu_op, ALU::OP_MUL)
              out_set(:mem_read, 1)
              out_set(:reg_write, 1)
              out_set(:instr_length, 2)
            when 0xF2  # NOT
              out_set(:alu_op, ALU::OP_NOT)
              out_set(:reg_write, 1)
            when 0xF3  # CMP
              out_set(:alu_op, ALU::OP_SUB)
              out_set(:mem_read, 1)
              # CMP sets flags but doesn't write result
              out_set(:instr_length, 2)
            when 0xF8  # JZ_LONG
              out_set(:branch, 1)
              out_set(:pc_src, zero == 1 ? 2 : 0)
              out_set(:instr_length, 3)
            when 0xF9  # JMP_LONG
              out_set(:jump, 1)
              out_set(:pc_src, 2)
              out_set(:instr_length, 3)
            when 0xFA  # JNZ_LONG
              out_set(:branch, 1)
              out_set(:pc_src, zero == 0 ? 2 : 0)
              out_set(:instr_length, 3)
            end
          end
        end
      end

      # Accumulator Register (8-bit)
      class Accumulator < Register
        def initialize(name = nil)
          super(name, width: 8)
        end
      end

      # CPU Datapath - connects all components
      class Datapath < SimComponent
        attr_reader :pc, :acc, :alu, :decoder, :memory
        attr_reader :halted, :cycle_count

        def initialize(name = nil, memory_contents: [])
          @cycle_count = 0
          @halted = false
          @prev_clk = 0
          super(name)

          # Create subcomponents
          @pc = ProgramCounter.new("pc", width: 16)
          @acc = Register.new("acc", width: 8)
          @alu = ALU.new("alu", width: 8)
          @decoder = InstructionDecoder.new("decoder")
          @memory = RAM.new("mem", data_width: 8, addr_width: 16)
          @sp = StackPointer.new("sp", width: 8, initial: 0xFF)

          # Internal state
          @zero_flag = 0
          @instruction = 0
          @operand = 0
          @operand_high = 0

          # Load initial memory contents
          memory_contents.each_with_index do |byte, addr|
            @memory.write_mem(addr, byte)
          end
        end

        def setup_ports
          input :clk
          input :rst
          output :pc_out, width: 16
          output :acc_out, width: 8
          output :zero_flag
          output :halted
        end

        def rising_edge?
          prev = @prev_clk
          @prev_clk = in_val(:clk)
          prev == 0 && @prev_clk == 1
        end

        def propagate
          # Handle reset
          if in_val(:rst) == 1
            reset_cpu
            return
          end

          return if @halted

          if rising_edge?
            execute_cycle
            @cycle_count += 1
          end

          # Update outputs
          out_set(:pc_out, @pc.get_output(:q))
          out_set(:acc_out, @acc.get_output(:q))
          out_set(:zero_flag, @zero_flag)
          out_set(:halted, @halted ? 1 : 0)
        end

        def reset_cpu
          @halted = false
          @cycle_count = 0
          @zero_flag = 0
          @instruction = 0
          @operand = 0
          @prev_clk = 0

          # Reset PC - set directly through internal state
          @pc.instance_variable_set(:@state, 0)
          @pc.set_input(:rst, 0)
          @pc.set_input(:en, 0)
          @pc.set_input(:load, 0)

          # Reset ACC - set directly
          @acc.instance_variable_set(:@state, 0)
          @acc.set_input(:rst, 0)
          @acc.set_input(:en, 0)

          # Reset SP - set directly to 0xFF
          @sp.instance_variable_set(:@state, 0xFF)
          @sp.set_input(:rst, 0)
          @sp.set_input(:push, 0)
          @sp.set_input(:pop, 0)

          # Propagate initial values
          @pc.propagate
          @acc.propagate
          @sp.propagate
        end

        def execute_cycle
          pc_val = @pc.get_output(:q)

          # Fetch instruction
          @instruction = @memory.read_mem(pc_val)
          opcode = @instruction & 0xF0
          operand_nibble = @instruction & 0x0F

          # Decode
          @decoder.set_input(:instruction, @instruction)
          @decoder.set_input(:zero_flag, @zero_flag)
          @decoder.propagate

          instr_length = @decoder.get_output(:instr_length)

          # Fetch additional bytes if needed
          @operand = case instr_length
          when 2
            @memory.read_mem(pc_val + 1)
          when 3
            (@memory.read_mem(pc_val + 1) << 8) | @memory.read_mem(pc_val + 2)
          else
            operand_nibble
          end

          acc_val = @acc.get_output(:q)

          # Execute based on decoded control signals
          if @decoder.get_output(:halt) == 1
            @halted = true
            return
          end

          # Calculate new PC
          new_pc = pc_val + instr_length
          pc_src = @decoder.get_output(:pc_src)

          if @decoder.get_output(:jump) == 1 || @decoder.get_output(:branch) == 1
            case pc_src
            when 1 then new_pc = @operand & 0xFF  # Short jump
            when 2 then new_pc = @operand & 0xFFFF  # Long jump
            end
          end

          # Handle CALL
          if @decoder.get_output(:call) == 1
            sp_val = @sp.get_output(:q)
            @memory.write_mem(sp_val, (pc_val + instr_length) & 0xFF)
            clock_sp(push: true)
            new_pc = @operand & 0xFF
          end

          # Handle RET
          if @decoder.get_output(:ret) == 1
            # Check for stack underflow (SP at max means empty stack)
            if @sp.get_output(:empty) == 1
              @halted = true
              return
            end
            clock_sp(pop: true)
            sp_val = @sp.get_output(:q)
            new_pc = @memory.read_mem(sp_val)
          end

          # ALU operations
          if @decoder.get_output(:reg_write) == 1
            if @decoder.get_output(:alu_src) == 1
              # Immediate load
              result = @operand & 0xFF
            else
              # Memory operand or ALU operation
              mem_operand = get_memory_operand
              @alu.set_input(:a, acc_val)
              @alu.set_input(:b, mem_operand)
              @alu.set_input(:op, @decoder.get_output(:alu_op))
              @alu.set_input(:cin, 0)
              @alu.propagate

              result = @alu.get_output(:result)
            end

            # Write to accumulator
            clock_register(@acc, result)
            @zero_flag = (result == 0) ? 1 : 0
          end

          # CMP - sets flags without writing
          if @instruction == 0xF3  # CMP
            mem_val = @memory.read_mem(@operand & 0xFF)
            result = (acc_val - mem_val) & 0xFF
            @zero_flag = (result == 0) ? 1 : 0
          end

          # Memory write (STA)
          if @decoder.get_output(:mem_write) == 1
            addr = get_store_address
            @memory.write_mem(addr, acc_val)
          end

          # Update PC
          clock_register(@pc, new_pc, load: true)
        end

        def get_memory_operand
          # For simple instructions, operand is in low nibble
          if @decoder.get_output(:instr_length) == 1
            @memory.read_mem(@operand & 0xFF)
          else
            @memory.read_mem(@operand & 0xFF)
          end
        end

        def get_store_address
          if @instruction == 0x20  # Indirect STA
            high = @memory.read_mem((@operand >> 8) & 0xFF)
            low = @memory.read_mem(@operand & 0xFF)
            (high << 8) | low
          elsif @instruction == 0x21  # Direct 2-byte STA
            @operand & 0xFF
          else  # Nibble-encoded STA
            @instruction & 0x0F
          end
        end

        def clock_register(reg, value, load: true)
          reg.set_input(:d, value)
          # For registers with load vs en (like ProgramCounter), use load
          if reg.inputs.key?(:load)
            reg.set_input(:load, load ? 1 : 0)
            reg.set_input(:en, 0)
          else
            reg.set_input(:en, 1)
          end
          reg.set_input(:clk, 0)
          reg.propagate
          reg.set_input(:clk, 1)
          reg.propagate
          # Clear the control signals
          if reg.inputs.key?(:load)
            reg.set_input(:load, 0)
          else
            reg.set_input(:en, 0)
          end
        end

        def clock_sp(push: false, pop: false)
          @sp.set_input(:push, push ? 1 : 0)
          @sp.set_input(:pop, pop ? 1 : 0)
          @sp.set_input(:clk, 0)
          @sp.propagate
          @sp.set_input(:clk, 1)
          @sp.propagate
          @sp.set_input(:push, 0)
          @sp.set_input(:pop, 0)
        end

        # Public interface for running
        def step
          set_input(:clk, 0)
          propagate
          set_input(:clk, 1)
          propagate
        end

        def run(max_cycles = 10000)
          set_input(:rst, 0)
          cycles = 0
          until @halted || cycles >= max_cycles
            step
            cycles += 1
          end
          cycles
        end

        def read_memory(addr)
          @memory.read_mem(addr)
        end

        def write_memory(addr, value)
          @memory.write_mem(addr, value)
        end

        def load_program(program, start_addr = 0)
          program.each_with_index do |byte, i|
            @memory.write_mem(start_addr + i, byte)
          end
        end

        def acc_value
          @acc.get_output(:q)
        end

        def pc_value
          @pc.get_output(:q)
        end

        def sp_value
          @sp.get_output(:q)
        end

        def zero_flag_value
          @zero_flag
        end
      end
    end
  end
end
