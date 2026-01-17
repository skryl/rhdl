# HDL Combinational Logic Components
# 4-to-1 Multiplexer

module RHDL
  module HDL
    # 4-to-1 Multiplexer
    class Mux4 < SimComponent
      # Class-level port definitions for synthesis (default 1-bit width)
      port_input :a
      port_input :b
      port_input :c
      port_input :d
      port_input :sel, width: 2
      port_output :y

      behavior do
        # 4-to-1 mux using nested 2-to-1 muxes
        # sel[0] selects between pairs, sel[1] selects which pair
        # When sel=0: a, sel=1: b, sel=2: c, sel=3: d
        low_mux = local(:low_mux, mux(sel[0], b, a), width: 1)   # sel[0]=0: a, sel[0]=1: b
        high_mux = local(:high_mux, mux(sel[0], d, c), width: 1) # sel[0]=0: c, sel[0]=1: d
        y <= mux(sel[1], high_mux, low_mux)  # sel[1]=0: low, sel[1]=1: high
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 1
        return if @width == 1
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @inputs[:c] = Wire.new("#{@name}.c", width: @width)
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
        @inputs[:c].on_change { |_| propagate }
        @inputs[:d].on_change { |_| propagate }
      end

      # Override propagate to handle multi-bit properly
      def propagate
        if @width == 1 && self.class.behavior_defined?
          execute_behavior
        else
          # Manual propagate for multi-bit
          case in_val(:sel) & 3
          when 0 then out_set(:y, in_val(:a))
          when 1 then out_set(:y, in_val(:b))
          when 2 then out_set(:y, in_val(:c))
          when 3 then out_set(:y, in_val(:d))
          end
        end
      end
    end
  end
end
