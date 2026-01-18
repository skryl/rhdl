# HDL Combinational Logic Components
# 4-to-1 Multiplexer

module RHDL
  module HDL
    # 4-to-1 Multiplexer
    class Mux4 < SimComponent
      parameter :width, default: 1

      input :a, width: :width
      input :b, width: :width
      input :c, width: :width
      input :d, width: :width
      input :sel, width: 2
      output :y, width: :width

      behavior do
        # 4-to-1 mux using nested 2-to-1 muxes
        # sel[0] selects between pairs, sel[1] selects which pair
        # When sel=0: a, sel=1: b, sel=2: c, sel=3: d
        w = port_width(:y)
        low_mux = local(:low_mux, mux(sel[0], b, a), width: w)   # sel[0]=0: a, sel[0]=1: b
        high_mux = local(:high_mux, mux(sel[0], d, c), width: w) # sel[0]=0: c, sel[0]=1: d
        y <= mux(sel[1], high_mux, low_mux)  # sel[1]=0: low, sel[1]=1: high
      end
    end
  end
end
