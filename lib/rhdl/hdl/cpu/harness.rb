# CPU Harness - behavioral simulation wrapper
# Connects CPU to memory and provides simulation interface.
# Interacts with CPU ONLY through its ports - no direct access to internals.

require_relative 'cpu'

module RHDL
  module HDL
    module CPU
      # Memory interface for the CPU harness
      class Memory
        def initialize(ram)
          @ram = ram
        end

        def read(addr)
          @ram.read_mem(addr & 0xFFFF)
        end

        def write(addr, value)
          @ram.write_mem(addr & 0xFFFF, value & 0xFF)
        end

        def load(program, start_addr = 0)
          program.each_with_index do |byte, i|
            write(start_addr + i, byte)
          end
        end
      end

      # CPU Harness - connects CPU to memory for behavioral simulation
      # All interaction with CPU is through ports only
      class Harness
        attr_reader :memory, :halted, :cycle_count
        attr_reader :cpu, :ram

        def initialize(external_memory = nil, name: nil, memory_contents: [])
          @cycle_count = 0
          @halted = false

          # Create CPU and RAM
          @cpu = CPU.new(name || "cpu")
          @ram = RAM.new("mem", data_width: 8, addr_width: 16)
          @memory = Memory.new(@ram)

          # Load initial memory contents
          memory_contents.each_with_index do |byte, addr|
            @ram.write_mem(addr, byte)
          end

          # Copy external memory if provided
          if external_memory && !external_memory.is_a?(String)
            (0..0xFFFF).each do |addr|
              val = external_memory.read(addr)
              @memory.write(addr, val) if val != 0
            end
          end

          reset
        end

        # Read CPU state through output ports only
        def acc
          @cpu.get_output(:acc_out)
        end

        def pc
          @cpu.get_output(:pc_out)
        end

        def sp
          @cpu.get_output(:sp_out)
        end

        def zero_flag
          @cpu.get_output(:zero_flag_out) == 1
        end

        # Legacy accessors
        def acc_value
          acc
        end

        def pc_value
          pc
        end

        def sp_value
          sp
        end

        def zero_flag_value
          @cpu.get_output(:zero_flag_out)
        end

        # Simulation control
        def reset
          @halted = false
          @cycle_count = 0

          # Reset CPU through rst port
          @cpu.set_input(:rst, 1)
          @cpu.set_input(:zero_flag_load_en, 0)
          clock_cpu
          @cpu.set_input(:rst, 0)

          # Initialize PC to 0
          @cpu.set_input(:pc_load_data, 0)
          @cpu.set_input(:pc_load_en, 1)
          clock_cpu
          @cpu.set_input(:pc_load_en, 0)

          # Initialize ACC to 0 by providing 0 on mem_data_in and triggering load
          # The acc_mux will select based on is_lda, but we need to force a zero load
          # Set mem_data_in to 0 and enable acc_load to reset accumulator
          @cpu.set_input(:mem_data_in, 0)
          @cpu.set_input(:instruction, 0x10)  # LDA with operand 0 (is_lda=1)
          @cpu.propagate
          @cpu.set_input(:acc_load_en, 1)
          clock_cpu
          @cpu.set_input(:acc_load_en, 0)

          # SP initializes to 0xFF via StackPointer component
          @cpu.propagate
        end

        def step
          return if @halted
          execute_cycle
          @cycle_count += 1
        end

        def run(max_cycles = 10000)
          cycles = 0
          until @halted || cycles >= max_cycles
            step
            cycles += 1
          end
          cycles
        end

        def execute(max_cycles: 10000)
          reset
          run(max_cycles)
        end

        # Memory convenience methods
        def read_memory(addr)
          @memory.read(addr)
        end

        def write_memory(addr, value)
          @memory.write(addr, value)
        end

        def load_program(program, start_addr = 0)
          @memory.load(program, start_addr)
        end

        private

        def execute_cycle
          pc_val = pc

          # Fetch instruction from memory
          instruction = @ram.read_mem(pc_val)
          operand_nibble = instruction & 0x0F

          # Send instruction to CPU for decoding (zero flag is internal now)
          @cpu.set_input(:instruction, instruction)
          @cpu.propagate

          # Read decoded control signals from CPU ports
          instr_length = @cpu.get_output(:dec_instr_length)
          halt = @cpu.get_output(:dec_halt)
          call = @cpu.get_output(:dec_call)
          ret = @cpu.get_output(:dec_ret)
          reg_write = @cpu.get_output(:dec_reg_write)
          alu_src = @cpu.get_output(:dec_alu_src)
          mem_write = @cpu.get_output(:dec_mem_write)

          # Fetch operand bytes from memory
          operand = case instr_length
          when 2
            @ram.read_mem(pc_val + 1)
          when 3
            (@ram.read_mem(pc_val + 1) << 8) | @ram.read_mem(pc_val + 2)
          else
            operand_nibble
          end

          acc_val = acc

          # Check for halt
          if halt == 1
            @halted = true
            return
          end

          # Calculate new PC based on decoder signals
          pc_src = @cpu.get_output(:dec_pc_src)
          jump = @cpu.get_output(:dec_jump)
          branch = @cpu.get_output(:dec_branch)

          new_pc = pc_val + instr_length

          if jump == 1 || branch == 1
            case pc_src
            when 1 then new_pc = operand & 0xFF
            when 2 then new_pc = operand & 0xFFFF
            end
          end

          # Handle CALL - push return address to stack
          if call == 1
            sp_val = sp
            @ram.write_mem(sp_val, (pc_val + instr_length) & 0xFF)
            @cpu.set_input(:sp_push, 1)
            clock_cpu
            @cpu.set_input(:sp_push, 0)
            new_pc = operand & 0xFF
          end

          # Handle RET - pop return address from stack
          if ret == 1
            if @cpu.get_output(:sp_empty) == 1
              @halted = true
              return
            end
            @cpu.set_input(:sp_pop, 1)
            clock_cpu
            @cpu.set_input(:sp_pop, 0)
            sp_val = sp
            new_pc = @ram.read_mem(sp_val)
          end

          # ALU/Load operations - CPU handles muxing between ALU result and memory data
          if reg_write == 1
            if alu_src == 1
              # Immediate load (LDI) - provide operand as memory data
              @cpu.set_input(:mem_data_in, operand & 0xFF)
            else
              # Memory operand (LDA, ADD, SUB, AND, OR, XOR, etc.)
              mem_operand = @ram.read_mem(operand & 0xFF)
              @cpu.set_input(:mem_data_in, mem_operand)
            end
            @cpu.propagate

            # Load result into accumulator (CPU's acc_mux selects ALU vs mem_data_in)
            @cpu.set_input(:acc_load_en, 1)
            @cpu.set_input(:zero_flag_load_en, 1)
            clock_cpu
            @cpu.set_input(:acc_load_en, 0)
            @cpu.set_input(:zero_flag_load_en, 0)
          end

          # CMP - compare without storing (just updates zero flag)
          # CMP uses ALU SUB operation, so we need to provide operand and capture zero flag
          if instruction == 0xF3
            mem_val = @ram.read_mem(operand & 0xFF)
            @cpu.set_input(:mem_data_in, mem_val)
            @cpu.propagate
            # Update zero flag without writing to accumulator
            @cpu.set_input(:zero_flag_load_en, 1)
            clock_cpu
            @cpu.set_input(:zero_flag_load_en, 0)
          end

          # Memory write (STA)
          if mem_write == 1
            addr = get_store_address(instruction, operand)
            @ram.write_mem(addr, acc_val)
          end

          # Update PC
          @cpu.set_input(:pc_load_data, new_pc)
          @cpu.set_input(:pc_load_en, 1)
          clock_cpu
          @cpu.set_input(:pc_load_en, 0)
        end

        def get_store_address(instruction, operand)
          if instruction == 0x20  # Indirect STA
            high = @ram.read_mem((operand >> 8) & 0xFF)
            low = @ram.read_mem(operand & 0xFF)
            (high << 8) | low
          elsif instruction == 0x21  # Direct 2-byte STA
            operand & 0xFF
          else
            instruction & 0x0F
          end
        end

        def clock_cpu
          @cpu.set_input(:clk, 0)
          @cpu.propagate
          @cpu.set_input(:clk, 1)
          @cpu.propagate
        end
      end
    end
  end
end
