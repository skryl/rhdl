# HDL Combinational Logic Components
# 3-to-8 Decoder

module RHDL
  module HDL
    # 3-to-8 Decoder
    class Decoder3to8 < SimComponent
      # Class-level port definitions for synthesis
      input :a, width: 3
      input :en
      output :y0
      output :y1
      output :y2
      output :y3
      output :y4
      output :y5
      output :y6
      output :y7

      behavior do
        # Each output is active when enabled and address matches
        y0 <= en & (a == lit(0, width: 3))
        y1 <= en & (a == lit(1, width: 3))
        y2 <= en & (a == lit(2, width: 3))
        y3 <= en & (a == lit(3, width: 3))
        y4 <= en & (a == lit(4, width: 3))
        y5 <= en & (a == lit(5, width: 3))
        y6 <= en & (a == lit(6, width: 3))
        y7 <= en & (a == lit(7, width: 3))
      end
    end
  end
end
