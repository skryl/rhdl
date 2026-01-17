# CPU Datapath - HDL Implementation
# This implements the CPU datapath using gate-level HDL components

module RHDL
  module HDL
    module CPU
      # Instruction decoder - decodes opcode byte to control signals
      class InstructionDecoder < SimComponent
        # ALU operation codes (must match ALU constants)
        OP_ADD = 0
        OP_SUB = 1
        OP_AND = 2
        OP_OR  = 3
        OP_XOR = 4
        OP_NOT = 5
        OP_MUL = 11
        OP_DIV = 12

        port_input :instruction, width: 8
        port_input :zero_flag

        # Control signals
        port_output :alu_op, width: 4       # ALU operation
        port_output :alu_src                # 0 = register, 1 = immediate
        port_output :reg_write              # Write to accumulator
        port_output :mem_read               # Read from memory
        port_output :mem_write              # Write to memory
        port_output :branch                 # Branch instruction
        port_output :jump                   # Unconditional jump
        port_output :pc_src, width: 2       # PC source: 0=+1, 1=operand, 2=long addr
        port_output :halt                   # Halt CPU
        port_output :call                   # Call instruction
        port_output :ret                    # Return instruction
        port_output :instr_length, width: 2 # 1, 2, or 3 bytes

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

      # Accumulator Register (8-bit)
      class Accumulator < Register
        def initialize(name = nil)
          super(name, width: 8)
        end
      end

      # Synthesizable CPU Datapath - structural component with instances
      # Generates Verilog/VHDL module instantiation and wiring
      class SynthDatapath < SimComponent
        # Clock and reset
        port_input :clk
        port_input :rst

        # Memory interface
        port_input :mem_data_in, width: 8
        port_output :mem_data_out, width: 8
        port_output :mem_addr, width: 16
        port_output :mem_write_en
        port_output :mem_read_en

        # Status outputs
        port_output :pc_out, width: 16
        port_output :acc_out, width: 8
        port_output :zero_flag
        port_output :halt

        # Internal signals
        port_signal :instruction, width: 8
        port_signal :operand, width: 8
        port_signal :alu_result, width: 8
        port_signal :alu_a, width: 8
        port_signal :alu_b, width: 8
        port_signal :alu_op, width: 4
        port_signal :alu_zero
        port_signal :reg_write
        port_signal :alu_src
        port_signal :decoder_mem_read
        port_signal :decoder_mem_write
        port_signal :branch
        port_signal :jump
        port_signal :pc_src, width: 2
        port_signal :halt_signal
        port_signal :call_signal
        port_signal :ret_signal
        port_signal :instr_length, width: 2

        structure do
          # Instruction Decoder
          instance :decoder, InstructionDecoder
          connect :instruction => [:decoder, :instruction]
          connect :zero_flag => [:decoder, :zero_flag]
          connect [:decoder, :alu_op] => :alu_op
          connect [:decoder, :alu_src] => :alu_src
          connect [:decoder, :reg_write] => :reg_write
          connect [:decoder, :mem_read] => :decoder_mem_read
          connect [:decoder, :mem_write] => :decoder_mem_write
          connect [:decoder, :branch] => :branch
          connect [:decoder, :jump] => :jump
          connect [:decoder, :pc_src] => :pc_src
          connect [:decoder, :halt] => :halt_signal
          connect [:decoder, :call] => :call_signal
          connect [:decoder, :ret] => :ret_signal
          connect [:decoder, :instr_length] => :instr_length

          # ALU
          instance :alu, ALU, width: 8
          connect :alu_a => [:alu, :a]
          connect :alu_b => [:alu, :b]
          connect :alu_op => [:alu, :op]
          connect [:alu, :result] => :alu_result
          connect [:alu, :zero] => :alu_zero

          # Program Counter (16-bit)
          instance :pc, ProgramCounter, width: 16
          connect :clk => [:pc, :clk]
          connect :rst => [:pc, :rst]
          connect [:pc, :q] => :pc_out

          # Accumulator Register (8-bit)
          instance :acc, Register, width: 8
          connect :clk => [:acc, :clk]
          connect :rst => [:acc, :rst]
          connect [:acc, :q] => :acc_out
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
