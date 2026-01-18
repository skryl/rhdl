# CPU adapter providing the same interface as behavioral CPU

module RHDL
  module HDL
    module CPU
      class CPUAdapter
        attr_reader :memory

        def initialize(external_memory = nil)
          @cpu = CPU.new("hdl_cpu")
          @memory = MemoryAdapter.new(@cpu.instance_variable_get(:@memory))

          # If external memory provided, copy its contents
          if external_memory
            # Copy any existing memory contents
            (0..0xFFFF).each do |addr|
              val = external_memory.read(addr)
              @memory.write(addr, val) if val != 0
            end
          end

          reset
        end

        def reset
          # Reset sequence: ensure clock is low when clearing reset
          # to avoid triggering an unintended cycle due to on_change callbacks
          @cpu.set_input(:clk, 0)
          @cpu.set_input(:rst, 1)
          @cpu.propagate
          @cpu.set_input(:clk, 1)
          @cpu.propagate
          @cpu.set_input(:clk, 0)  # Return clock to low before clearing reset
          @cpu.propagate
          @cpu.set_input(:rst, 0)
          @cpu.propagate
        end

        def step
          @cpu.step
        end

        def acc
          @cpu.acc_value
        end

        def pc
          @cpu.pc_value
        end

        def halted
          @cpu.halted
        end

        def zero_flag
          @cpu.zero_flag_value == 1
        end

        def sp
          @cpu.sp_value
        end

        # For direct CPU access if needed
        def cpu
          @cpu
        end
      end
    end
  end
end
