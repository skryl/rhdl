# HDL Combinational Logic Components
# 1-to-2 Demultiplexer

module RHDL
  module HDL
    # 1-to-2 Demultiplexer
    class Demux2 < Component
      parameter :width, default: 1

      input :a, width: :width
      input :sel
      output :y0, width: :width
      output :y1, width: :width

      behavior do
        w = port_width(:a)
        # When sel=0: y0=a, y1=0
        # When sel=1: y0=0, y1=a
        y0 <= mux(sel, lit(0, width: w), a)  # sel=0: a, sel=1: 0
        y1 <= mux(sel, a, lit(0, width: w))  # sel=0: 0, sel=1: a
      end
    end
  end
end
