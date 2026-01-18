# HDL Combinational Logic Components
# 2-to-1 Multiplexer

module RHDL
  module HDL
    # 2-to-1 Multiplexer
    class Mux2 < SimComponent
      parameter :width, default: 1

      input :a, width: :width   # Selected when sel = 0
      input :b, width: :width   # Selected when sel = 1
      input :sel
      output :y, width: :width

      # mux(sel, if_true, if_false) - sel ? if_true : if_false
      # Note: sel=0 selects a (first arg), sel=1 selects b (second arg)
      behavior do
        y <= mux(sel, b, a)
      end
    end
  end
end
