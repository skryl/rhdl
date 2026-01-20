# HDL Combinational Logic Components
# Sign Extender

module RHDL
  module HDL
    # Sign Extender
    class SignExtend < Component
      parameter :in_width, default: 8
      parameter :out_width, default: 16

      input :a, width: :in_width
      output :y, width: :out_width

      behavior do
        # Sign bit from input
        sign = local(:sign, a[7], width: 1)

        # Extension: if sign=1, extend with 0xFF; if sign=0, extend with 0x00
        extension = local(:extension, mux(sign, lit(0xFF, width: 8), lit(0x00, width: 8)), width: 8)

        # Combine: upper byte is extension, lower byte is original
        y <= cat(extension, a)
      end
    end
  end
end
