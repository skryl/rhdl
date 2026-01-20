# HDL Combinational Logic Components
# 2-to-4 Decoder

module RHDL
  module HDL
    # 2-to-4 Decoder
    class Decoder2to4 < Component
      # Class-level port definitions for synthesis
      input :a, width: 2
      input :en
      output :y0
      output :y1
      output :y2
      output :y3

      behavior do
        # Each output is active when enabled and address matches
        y0 <= en & (a == lit(0, width: 2))
        y1 <= en & (a == lit(1, width: 2))
        y2 <= en & (a == lit(2, width: 2))
        y3 <= en & (a == lit(3, width: 2))
      end
    end
  end
end
