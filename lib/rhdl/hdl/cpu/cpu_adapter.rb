# CPU adapter providing the same interface as behavioral CPU

module RHDL
  module HDL
    module CPU
      class CPUAdapter
        attr_reader :memory

        def initialize(external_memory = nil)
          @datapath = Datapath.new("hdl_cpu")
          @memory = MemoryAdapter.new(@datapath.instance_variable_get(:@memory))

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
          @datapath.set_input(:clk, 0)
          @datapath.set_input(:rst, 1)
          @datapath.propagate
          @datapath.set_input(:clk, 1)
          @datapath.propagate
          @datapath.set_input(:clk, 0)  # Return clock to low before clearing reset
          @datapath.propagate
          @datapath.set_input(:rst, 0)
          @datapath.propagate
        end

        def step
          @datapath.step
        end

        def acc
          @datapath.acc_value
        end

        def pc
          @datapath.pc_value
        end

        def halted
          @datapath.halted
        end

        def zero_flag
          @datapath.zero_flag_value == 1
        end

        def sp
          @datapath.sp_value
        end

        # For direct datapath access if needed
        def datapath
          @datapath
        end
      end
    end
  end
end
