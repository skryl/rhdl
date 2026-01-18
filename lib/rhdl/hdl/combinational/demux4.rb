# HDL Combinational Logic Components
# 1-to-4 Demultiplexer

module RHDL
  module HDL
    # 1-to-4 Demultiplexer - routes input to one of 4 outputs
    class Demux4 < SimComponent
      parameter :width, default: 1

      input :a, width: :width
      input :sel, width: 2
      output :y0, width: :width
      output :y1, width: :width
      output :y2, width: :width
      output :y3, width: :width

      behavior do
        w = port_width(:a)
        # Decode selector
        sel_0 = local(:sel_0, ~sel[1] & ~sel[0], width: 1)  # sel == 0
        sel_1 = local(:sel_1, ~sel[1] & sel[0], width: 1)   # sel == 1
        sel_2 = local(:sel_2, sel[1] & ~sel[0], width: 1)   # sel == 2
        sel_3 = local(:sel_3, sel[1] & sel[0], width: 1)    # sel == 3

        # Route input to selected output, others get 0
        y0 <= mux(sel_0, a, lit(0, width: w))
        y1 <= mux(sel_1, a, lit(0, width: w))
        y2 <= mux(sel_2, a, lit(0, width: w))
        y3 <= mux(sel_3, a, lit(0, width: w))
      end
    end
  end
end
