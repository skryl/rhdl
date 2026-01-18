# HDL Combinational Logic Components
# Leading Zero Count

module RHDL
  module HDL
    # Leading Zero Count - counts leading zeros in input
    class LZCount < SimComponent
      parameter :width, default: 8
      parameter :out_width, default: -> { Math.log2(@width + 1).ceil }

      input :a, width: :width
      output :count, width: :out_width
      output :all_zero

      behavior do
        w = param(:width)
        val = a.value

        # Count leading zeros from MSB
        lz_count = 0
        (w - 1).downto(0) do |i|
          if (val >> i) & 1 == 0
            lz_count += 1
          else
            break
          end
        end

        count <= lz_count
        all_zero <= (val == 0 ? 1 : 0)
      end
    end
  end
end
