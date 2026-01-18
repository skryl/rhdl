# CPU Harness - behavioral simulation wrapper
# Connects CPU to memory and provides simulation interface

require_relative 'instruction_decoder'
require_relative 'accumulator'
require_relative 'datapath'
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
      class Harness
        attr_reader :memory, :halted, :cycle_count
        attr_reader :cpu, :ram

        def initialize(external_memory = nil, name: nil, memory_contents: [])
          @cycle_count = 0
          @halted = false
          @zero_flag = 0

          # Create CPU and RAM - the only two components
          @cpu = CPU.new(name || "cpu")
          @ram = RAM.new("mem", data_width: 8, addr_width: 16)
          @memory = Memory.new(@ram)

          # Internal execution state
          @instruction = 0
          @operand = 0

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

        # Accessors - delegate to CPU components
        def acc
          @cpu.acc.get_output(:q)
        end

        def pc
          @cpu.pc.get_output(:q)
        end

        def sp
          @cpu.sp.get_output(:q)
        end

        def zero_flag
          @zero_flag == 1
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
          @zero_flag
        end

        # Simulation control
        def reset
          @halted = false
          @cycle_count = 0
          @zero_flag = 0
          @instruction = 0
          @operand = 0

          # Reset CPU components
          @cpu.pc.instance_variable_set(:@state, 0)
          @cpu.pc.set_input(:rst, 0)
          @cpu.pc.set_input(:en, 0)
          @cpu.pc.set_input(:load, 0)

          @cpu.acc.instance_variable_set(:@state, 0)
          @cpu.acc.set_input(:rst, 0)
          @cpu.acc.set_input(:en, 0)

          @cpu.sp.instance_variable_set(:@state, 0xFF)
          @cpu.sp.set_input(:rst, 0)
          @cpu.sp.set_input(:push, 0)
          @cpu.sp.set_input(:pop, 0)

          @cpu.pc.propagate
          @cpu.acc.propagate
          @cpu.sp.propagate
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
          @instruction = @ram.read_mem(pc_val)
          operand_nibble = @instruction & 0x0F

          # Decode instruction via CPU's decoder
          @cpu.decoder.set_input(:instruction, @instruction)
          @cpu.decoder.set_input(:zero_flag, @zero_flag)
          @cpu.decoder.propagate

          instr_length = @cpu.decoder.get_output(:instr_length)

          # Fetch operand bytes from memory
          @operand = case instr_length
          when 2
            @ram.read_mem(pc_val + 1)
          when 3
            (@ram.read_mem(pc_val + 1) << 8) | @ram.read_mem(pc_val + 2)
          else
            operand_nibble
          end

          acc_val = acc

          # Check for halt
          if @cpu.decoder.get_output(:halt) == 1
            @halted = true
            return
          end

          # Calculate new PC
          new_pc = pc_val + instr_length
          pc_src = @cpu.decoder.get_output(:pc_src)

          if @cpu.decoder.get_output(:jump) == 1 || @cpu.decoder.get_output(:branch) == 1
            case pc_src
            when 1 then new_pc = @operand & 0xFF
            when 2 then new_pc = @operand & 0xFFFF
            end
          end

          # Handle CALL - push return address to stack
          if @cpu.decoder.get_output(:call) == 1
            sp_val = sp
            @ram.write_mem(sp_val, (pc_val + instr_length) & 0xFF)
            clock_sp(push: true)
            new_pc = @operand & 0xFF
          end

          # Handle RET - pop return address from stack
          if @cpu.decoder.get_output(:ret) == 1
            if @cpu.sp.get_output(:empty) == 1
              @halted = true
              return
            end
            clock_sp(pop: true)
            sp_val = sp
            new_pc = @ram.read_mem(sp_val)
          end

          # ALU operations
          if @cpu.decoder.get_output(:reg_write) == 1
            if @cpu.decoder.get_output(:alu_src) == 1
              # Immediate load
              result = @operand & 0xFF
            else
              # Memory operand through CPU's ALU
              mem_operand = @ram.read_mem(@operand & 0xFF)
              @cpu.alu.set_input(:a, acc_val)
              @cpu.alu.set_input(:b, mem_operand)
              @cpu.alu.set_input(:op, @cpu.decoder.get_output(:alu_op))
              @cpu.alu.set_input(:cin, 0)
              @cpu.alu.propagate
              result = @cpu.alu.get_output(:result)
            end

            clock_register(@cpu.acc, result)
            @zero_flag = (result == 0) ? 1 : 0
          end

          # CMP - compare without storing
          if @instruction == 0xF3
            mem_val = @ram.read_mem(@operand & 0xFF)
            result = (acc_val - mem_val) & 0xFF
            @zero_flag = (result == 0) ? 1 : 0
          end

          # Memory write (STA)
          if @cpu.decoder.get_output(:mem_write) == 1
            addr = get_store_address
            @ram.write_mem(addr, acc_val)
          end

          # Update PC
          clock_register(@cpu.pc, new_pc, load: true)
        end

        def get_store_address
          if @instruction == 0x20  # Indirect STA
            high = @ram.read_mem((@operand >> 8) & 0xFF)
            low = @ram.read_mem(@operand & 0xFF)
            (high << 8) | low
          elsif @instruction == 0x21  # Direct 2-byte STA
            @operand & 0xFF
          else
            @instruction & 0x0F
          end
        end

        def clock_register(reg, value, load: true)
          reg.set_input(:d, value)
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
          if reg.inputs.key?(:load)
            reg.set_input(:load, 0)
          else
            reg.set_input(:en, 0)
          end
        end

        def clock_sp(push: false, pop: false)
          @cpu.sp.set_input(:push, push ? 1 : 0)
          @cpu.sp.set_input(:pop, pop ? 1 : 0)
          @cpu.sp.set_input(:clk, 0)
          @cpu.sp.propagate
          @cpu.sp.set_input(:clk, 1)
          @cpu.sp.propagate
          @cpu.sp.set_input(:push, 0)
          @cpu.sp.set_input(:pop, 0)
        end
      end
    end
  end
end
