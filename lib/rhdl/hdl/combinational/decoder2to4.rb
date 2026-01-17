# HDL Combinational Logic Components
# 2-to-4 Decoder

module RHDL
  module HDL
    # 2-to-4 Decoder
    class Decoder2to4 < SimComponent
      # Class-level port definitions for synthesis
      port_input :a, width: 2
      port_input :en
      port_output :y0
      port_output :y1
      port_output :y2
      port_output :y3

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
