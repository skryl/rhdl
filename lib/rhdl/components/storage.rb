module RHDL
  module Components
    class DFlipFlop < Component
      input :d
      input :clk
      input :rst
      input :en
      output :q
      output :qn
    end

    class TFlipFlop < Component
      input :t
      input :clk
      input :rst
      input :en
      output :q
      output :qn
    end

    class JKFlipFlop < Component
      input :j
      input :k
      input :clk
      input :rst
      input :en
      output :q
      output :qn
    end

    class SRFlipFlop < Component
      input :s
      input :r
      input :clk
      input :rst
      input :en
      output :q
      output :qn
    end

    class Register < Component
      def initialize(width = 8)
        @width = width
        input :d, width: width
        input :clk
        input :rst
        input :en
        output :q, width: width
      end
    end

    class ShiftRegister < Component
      def initialize(width = 8)
        @width = width
        input :d
        input :clk
        input :rst
        input :en
        input :direction  # 0 for right, 1 for left
        output :q, width: width
        
        # Internal signals for shift stages
        (@width - 1).times do |i|
          signal :"stage#{i}"
        end
      end
    end

    class Counter < Component
      def initialize(width = 8)
        @width = width
        input :clk
        input :rst
        input :en
        input :up_down  # 0 for down, 1 for up
        input :load
        input :data, width: width
        output :q, width: width
        output :max
        output :min
      end
    end

    class RAM < Component
      def initialize(data_width = 8, addr_width = 8)
        @data_width = data_width
        @addr_width = addr_width

        input :clk
        input :we         # Write enable
        input :addr, width: addr_width
        input :data_in, width: data_width
        output :data_out, width: data_width
      end
    end

    class FIFO < Component
      def initialize(data_width = 8, depth = 16)
        @data_width = data_width
        @addr_width = Math.log2(depth).ceil
        @depth = depth

        input :clk
        input :rst
        input :wr_en     # Write enable
        input :rd_en     # Read enable
        input :data_in, width: data_width
        output :data_out, width: data_width
        output :full
        output :empty
        output :almost_full
        output :almost_empty
        
        # Internal signals
        signal :wr_ptr, width: @addr_width
        signal :rd_ptr, width: @addr_width
        signal :count, width: @addr_width + 1
      end
    end
  end
end
