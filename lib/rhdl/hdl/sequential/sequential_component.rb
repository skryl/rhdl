# HDL Sequential Component Base Class
# Base class for sequential (clocked) components

module RHDL
  module HDL
    class SequentialComponent < SimComponent
      def initialize(name = nil)
        @prev_clk = 0
        @clk_sampled = false  # Track if we've sampled clock this cycle
        @state ||= 0  # Don't overwrite subclass initialization
        super(name)
      end

      # Override input to not auto-propagate on any input changes
      # Sequential components should be propagated manually as part of clock cycles
      # This avoids race conditions where inputs change in wrong order during propagation
      def input(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @inputs[name] = wire
        # No on_change callbacks - sequential propagation must be explicit
        wire
      end

      def rising_edge?
        clk = in_val(:clk)
        result = @prev_clk == 0 && clk == 1
        # Update prev_clk after checking - this ensures the edge is detected once
        @prev_clk = clk
        result
      end

      def falling_edge?
        clk = in_val(:clk)
        result = @prev_clk == 1 && clk == 0
        @prev_clk = clk
        result
      end

      # Call this to sample the current clock value without detecting an edge
      # Useful when you need to update prev_clk outside of edge detection
      def sample_clock
        @prev_clk = in_val(:clk)
      end
    end
  end
end
