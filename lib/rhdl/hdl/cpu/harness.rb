# CPU HDL Module
# Gate-level CPU implementation

require_relative 'instruction_decoder'
require_relative 'accumulator'
require_relative 'datapath'

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

      # CPU Harness with behavioral simulation logic
      # Provides unified interface for running CPU simulations
      class Harness < SimComponent
        attr_reader :memory, :halted, :cycle_count

        def initialize(external_memory = nil, name: nil, memory_contents: [])
          @cycle_count = 0
          @halted = false
          @prev_clk = 0

          # Handle name parameter (can be first positional arg for backward compat)
          name = external_memory if external_memory.is_a?(String)
          super(name)

          # Create internal components
          @pc_reg = ProgramCounter.new("pc", width: 16)
          @acc_reg = Register.new("acc", width: 8)
          @alu = ALU.new("alu", width: 8)
          @decoder = InstructionDecoder.new("decoder")
          @ram = RAM.new("mem", data_width: 8, addr_width: 16)
          @sp_reg = StackPointer.new("sp", width: 8, initial: 0xFF)

          # Memory interface
          @memory = Memory.new(@ram)

          # Internal state
          @zero_flag = 0
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

        def setup_ports
          input :clk
          input :rst
          output :pc_out, width: 16
          output :acc_out, width: 8
          output :zero_flag
          output :halted
        end

        # Simple accessors matching expected interface
        def acc
          @acc_reg.get_output(:q)
        end

        def pc
          @pc_reg.get_output(:q)
        end

        def sp
          @sp_reg.get_output(:q)
        end

        def zero_flag
          @zero_flag == 1
        end

        # Legacy accessors (for backward compatibility)
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

        def rising_edge?
          prev = @prev_clk
          @prev_clk = in_val(:clk)
          prev == 0 && @prev_clk == 1
        end

        def propagate
          if in_val(:rst) == 1
            reset_cpu
            return
          end

          return if @halted

          if rising_edge?
            execute_cycle
            @cycle_count += 1
          end

          out_set(:pc_out, pc)
          out_set(:acc_out, acc)
          out_set(:zero_flag, @zero_flag)
          out_set(:halted, @halted ? 1 : 0)
        end

        def reset
          set_input(:clk, 0)
          set_input(:rst, 1)
          propagate
          set_input(:clk, 1)
          propagate
          set_input(:clk, 0)
          propagate
          set_input(:rst, 0)
          propagate
        end

        def reset_cpu
          @halted = false
          @cycle_count = 0
          @zero_flag = 0
          @instruction = 0
          @operand = 0
          @prev_clk = 0

          @pc_reg.instance_variable_set(:@state, 0)
          @pc_reg.set_input(:rst, 0)
          @pc_reg.set_input(:en, 0)
          @pc_reg.set_input(:load, 0)

          @acc_reg.instance_variable_set(:@state, 0)
          @acc_reg.set_input(:rst, 0)
          @acc_reg.set_input(:en, 0)

          @sp_reg.instance_variable_set(:@state, 0xFF)
          @sp_reg.set_input(:rst, 0)
          @sp_reg.set_input(:push, 0)
          @sp_reg.set_input(:pop, 0)

          @pc_reg.propagate
          @acc_reg.propagate
          @sp_reg.propagate
        end

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

          @instruction = @ram.read_mem(pc_val)
          operand_nibble = @instruction & 0x0F

          @decoder.set_input(:instruction, @instruction)
          @decoder.set_input(:zero_flag, @zero_flag)
          @decoder.propagate

          instr_length = @decoder.get_output(:instr_length)

          @operand = case instr_length
          when 2
            @ram.read_mem(pc_val + 1)
          when 3
            (@ram.read_mem(pc_val + 1) << 8) | @ram.read_mem(pc_val + 2)
          else
            operand_nibble
          end

          acc_val = acc

          if @decoder.get_output(:halt) == 1
            @halted = true
            return
          end

          new_pc = pc_val + instr_length
          pc_src = @decoder.get_output(:pc_src)

          if @decoder.get_output(:jump) == 1 || @decoder.get_output(:branch) == 1
            case pc_src
            when 1 then new_pc = @operand & 0xFF
            when 2 then new_pc = @operand & 0xFFFF
            end
          end

          if @decoder.get_output(:call) == 1
            sp_val = sp
            @ram.write_mem(sp_val, (pc_val + instr_length) & 0xFF)
            clock_sp(push: true)
            new_pc = @operand & 0xFF
          end

          if @decoder.get_output(:ret) == 1
            if @sp_reg.get_output(:empty) == 1
              @halted = true
              return
            end
            clock_sp(pop: true)
            sp_val = sp
            new_pc = @ram.read_mem(sp_val)
          end

          if @decoder.get_output(:reg_write) == 1
            if @decoder.get_output(:alu_src) == 1
              result = @operand & 0xFF
            else
              mem_operand = @ram.read_mem(@operand & 0xFF)
              @alu.set_input(:a, acc_val)
              @alu.set_input(:b, mem_operand)
              @alu.set_input(:op, @decoder.get_output(:alu_op))
              @alu.set_input(:cin, 0)
              @alu.propagate
              result = @alu.get_output(:result)
            end

            clock_register(@acc_reg, result)
            @zero_flag = (result == 0) ? 1 : 0
          end

          if @instruction == 0xF3  # CMP
            mem_val = @ram.read_mem(@operand & 0xFF)
            result = (acc_val - mem_val) & 0xFF
            @zero_flag = (result == 0) ? 1 : 0
          end

          if @decoder.get_output(:mem_write) == 1
            addr = get_store_address
            @ram.write_mem(addr, acc_val)
          end

          clock_register(@pc_reg, new_pc, load: true)
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
          @sp_reg.set_input(:push, push ? 1 : 0)
          @sp_reg.set_input(:pop, pop ? 1 : 0)
          @sp_reg.set_input(:clk, 0)
          @sp_reg.propagate
          @sp_reg.set_input(:clk, 1)
          @sp_reg.propagate
          @sp_reg.set_input(:push, 0)
          @sp_reg.set_input(:pop, 0)
        end
      end
    end
  end
end
