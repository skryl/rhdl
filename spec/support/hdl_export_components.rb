module RHDL
  module ExportFixtures
    class Mux2 < RHDL::Component
      input :a, width: 4
      input :b, width: 4
      input :sel
      output :y, width: 4

      combinational :mux_logic do
        if_stmt(sel == 1) do
          assign(y, b)
          else_block do
            assign(y, a)
          end
        end
      end
    end

    class Adder8 < RHDL::Component
      input :a, width: 8
      input :b, width: 8
      output :sum, width: 8

      assign sum, a + b
    end

    class Reg8 < RHDL::Component
      input :clk
      input :reset
      input :d, width: 8
      output :q, width: 8

      clocked :reg_logic, clock: :clk do
        if_stmt(reset == 1) do
          assign(q, 0)
          else_block do
            assign(q, d)
          end
        end
      end
    end

    class Mux2Ref < RHDL::HDL::SimComponent
      def setup_ports
        input :a, width: 4
        input :b, width: 4
        input :sel
        output :y, width: 4
      end

      def propagate
        out_set(:y, in_val(:sel) == 1 ? in_val(:b) : in_val(:a))
      end
    end

    class Adder8Ref < RHDL::HDL::SimComponent
      def setup_ports
        input :a, width: 8
        input :b, width: 8
        output :sum, width: 8
      end

      def propagate
        out_set(:sum, (in_val(:a) + in_val(:b)) & 0xFF)
      end
    end

    class Reg8Ref < RHDL::HDL::SimComponent
      def initialize(name = nil)
        @state = 0
        @last_clk = 0
        super(name)
      end

      def setup_ports
        input :clk
        input :reset
        input :d, width: 8
        output :q, width: 8
      end

      def propagate
        clk_val = in_val(:clk)
        if @last_clk == 0 && clk_val == 1
          @state = in_val(:reset) == 1 ? 0 : in_val(:d)
        end
        @last_clk = clk_val
        out_set(:q, @state)
      end
    end
  end
end
