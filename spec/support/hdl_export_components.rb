module RHDL
  module ExportFixtures
    class Mux2 < RHDL::Component
      self._ports = []
      self._signals = []
      self._constants = []
      self._processes = []
      self._assignments = []
      self._instances = []
      self._generics = []

      input :a, width: 4
      input :b, width: 4
      input :sel
      output :y, width: 4

      sel_ref = RHDL::DSL::SignalRef.new(:sel, width: 1)
      a_ref = RHDL::DSL::SignalRef.new(:a, width: 4)
      b_ref = RHDL::DSL::SignalRef.new(:b, width: 4)
      y_ref = RHDL::DSL::SignalRef.new(:y, width: 4)

      combinational :mux_logic do
        if_stmt(sel_ref == 1) do
          assign(y_ref, b_ref)
          else_block do
            assign(y_ref, a_ref)
          end
        end
      end
    end

    class Adder8 < RHDL::Component
      self._ports = []
      self._signals = []
      self._constants = []
      self._processes = []
      self._assignments = []
      self._instances = []
      self._generics = []

      input :a, width: 8
      input :b, width: 8
      output :sum, width: 8

      a_ref = RHDL::DSL::SignalRef.new(:a, width: 8)
      b_ref = RHDL::DSL::SignalRef.new(:b, width: 8)
      sum_ref = RHDL::DSL::SignalRef.new(:sum, width: 8)

      assign sum_ref, a_ref + b_ref
    end

    class Reg8 < RHDL::Component
      self._ports = []
      self._signals = []
      self._constants = []
      self._processes = []
      self._assignments = []
      self._instances = []
      self._generics = []

      input :clk
      input :reset
      input :d, width: 8
      output :q, width: 8

      reset_ref = RHDL::DSL::SignalRef.new(:reset, width: 1)
      d_ref = RHDL::DSL::SignalRef.new(:d, width: 8)
      q_ref = RHDL::DSL::SignalRef.new(:q, width: 8)

      clocked :reg_logic, clock: :clk do
        if_stmt(reset_ref == 1) do
          assign(q_ref, 0)
          else_block do
            assign(q_ref, d_ref)
          end
        end
      end
    end

    class Mux2Ref < RHDL::HDL::Component
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

    class Adder8Ref < RHDL::HDL::Component
      def setup_ports
        input :a, width: 8
        input :b, width: 8
        output :sum, width: 8
      end

      def propagate
        out_set(:sum, (in_val(:a) + in_val(:b)) & 0xFF)
      end
    end

    class Reg8Ref < RHDL::HDL::Component
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
