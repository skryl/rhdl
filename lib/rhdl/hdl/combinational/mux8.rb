# HDL Combinational Logic Components
# 8-to-1 Multiplexer

module RHDL
  module HDL
    # 8-to-1 Multiplexer - selects one of 8 inputs
    class Mux8 < Component
      parameter :width, default: 1

      input :in0, width: :width
      input :in1, width: :width
      input :in2, width: :width
      input :in3, width: :width
      input :in4, width: :width
      input :in5, width: :width
      input :in6, width: :width
      input :in7, width: :width
      input :sel, width: 3
      output :y, width: :width

      behavior do
        # 8-to-1 mux using case_select
        w = port_width(:y)
        y <= case_select(sel, {
          0 => in0,
          1 => in1,
          2 => in2,
          3 => in3,
          4 => in4,
          5 => in5,
          6 => in6,
          7 => in7
        }, default: lit(0, width: w))
      end
    end
  end
end
