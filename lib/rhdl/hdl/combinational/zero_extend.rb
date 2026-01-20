# HDL Combinational Logic Components
# Zero Extender

module RHDL
  module HDL
    # Zero Extender - extends a narrower value with zeros
    class ZeroExtend < Component
      parameter :in_width, default: 8
      parameter :out_width, default: 16

      input :a, width: :in_width
      output :y, width: :out_width

      # Zero extension is just assignment - output width is larger than input
      behavior do
        y <= a
      end
    end
  end
end
