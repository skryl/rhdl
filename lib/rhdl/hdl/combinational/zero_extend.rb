# HDL Combinational Logic Components
# Zero Extender

module RHDL
  module HDL
    # Zero Extender - extends a narrower value with zeros
    class ZeroExtend < SimComponent
      parameter :in_width, default: 8
      parameter :out_width, default: 16

      input :a, width: :in_width
      output :y, width: :out_width

      # Zero extension is just assignment - output width is larger than input
      behavior do
        y <= a
      end

      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end
    end
  end
end
