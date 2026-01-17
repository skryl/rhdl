# HDL Combinational Logic Components
# Zero Detector

module RHDL
  module HDL
    # Zero Detector
    class ZeroDetect < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :zero
      end

      def propagate
        out_set(:zero, in_val(:a) == 0 ? 1 : 0)
      end
    end
  end
end
