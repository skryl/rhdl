# HDL Combinational Logic Components
# Zero Detector

module RHDL
  module HDL
    # Zero Detector
    class ZeroDetect < SimComponent
      # Class-level port definitions for synthesis (default 8-bit width)
      port_input :a, width: 8
      port_output :zero

      behavior do
        zero <= (a == lit(0, width: 8))
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different from 8
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end
    end
  end
end
