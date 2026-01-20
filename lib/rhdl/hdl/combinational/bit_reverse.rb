# HDL Combinational Logic Components
# Bit Reverser

module RHDL
  module HDL
    # Bit Reverser
    class BitReverse < Component
      parameter :width, default: 8

      input :a, width: :width
      output :y, width: :width

      behavior do
        # Reverse bit order: y = {a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]}
        y <= cat(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
      end
    end
  end
end
