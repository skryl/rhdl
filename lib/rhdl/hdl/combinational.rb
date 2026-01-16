# HDL Combinational Logic Components
# Multiplexers, decoders, encoders, and other combinational circuits

module RHDL
  module HDL
    # 2-to-1 Multiplexer
    class Mux2 < SimComponent
      port_input :a   # Selected when sel = 0
      port_input :b   # Selected when sel = 1
      port_input :sel
      port_output :y

      # mux(sel, if_true, if_false) - sel ? if_true : if_false
      # Note: sel=0 selects a (first arg), sel=1 selects b (second arg)
      behavior do
        y <= mux(sel, b, a)
      end

      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 1
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        if @width == 1 && self.class.behavior_defined?
          execute_behavior
        else
          if in_val(:sel) == 0
            out_set(:y, in_val(:a))
          else
            out_set(:y, in_val(:b))
          end
        end
      end
    end

    # 4-to-1 Multiplexer
    class Mux4 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        input :c, width: @width
        input :d, width: @width
        input :sel, width: 2
        output :y, width: @width
      end

      def propagate
        case in_val(:sel) & 3
        when 0 then out_set(:y, in_val(:a))
        when 1 then out_set(:y, in_val(:b))
        when 2 then out_set(:y, in_val(:c))
        when 3 then out_set(:y, in_val(:d))
        end
      end
    end

    # 8-to-1 Multiplexer
    class Mux8 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        8.times { |i| input :"in#{i}", width: @width }
        input :sel, width: 3
        output :y, width: @width
      end

      def propagate
        sel = in_val(:sel) & 7
        out_set(:y, in_val(:"in#{sel}"))
      end
    end

    # N-to-1 Multiplexer (generic)
    class MuxN < SimComponent
      def initialize(name = nil, inputs: 2, width: 1)
        @input_count = inputs
        @sel_width = Math.log2(inputs).ceil
        @width = width
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"in#{i}", width: @width }
        input :sel, width: @sel_width
        output :y, width: @width
      end

      def propagate
        sel = in_val(:sel) & ((1 << @sel_width) - 1)
        if sel < @input_count
          out_set(:y, in_val(:"in#{sel}"))
        else
          out_set(:y, 0)
        end
      end
    end

    # 1-to-2 Demultiplexer
    class Demux2 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :sel
        output :y0, width: @width
        output :y1, width: @width
      end

      def propagate
        val = in_val(:a)
        if in_val(:sel) == 0
          out_set(:y0, val)
          out_set(:y1, 0)
        else
          out_set(:y0, 0)
          out_set(:y1, val)
        end
      end
    end

    # 1-to-4 Demultiplexer
    class Demux4 < SimComponent
      def initialize(name = nil, width: 1)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :sel, width: 2
        4.times { |i| output :"y#{i}", width: @width }
      end

      def propagate
        val = in_val(:a)
        sel = in_val(:sel) & 3
        4.times { |i| out_set(:"y#{i}", i == sel ? val : 0) }
      end
    end

    # 2-to-4 Decoder
    class Decoder2to4 < SimComponent
      def setup_ports
        input :a, width: 2
        input :en
        output :y0
        output :y1
        output :y2
        output :y3
      end

      def propagate
        if in_val(:en) == 0
          4.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & 3
          4.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end

    # 3-to-8 Decoder
    class Decoder3to8 < SimComponent
      def setup_ports
        input :a, width: 3
        input :en
        8.times { |i| output :"y#{i}" }
      end

      def propagate
        if in_val(:en) == 0
          8.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & 7
          8.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end

    # Generic N-bit Decoder
    class DecoderN < SimComponent
      def initialize(name = nil, width: 3)
        @width = width
        @output_count = 1 << width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :en
        @output_count.times { |i| output :"y#{i}" }
      end

      def propagate
        if in_val(:en) == 0
          @output_count.times { |i| out_set(:"y#{i}", 0) }
        else
          val = in_val(:a) & ((1 << @width) - 1)
          @output_count.times { |i| out_set(:"y#{i}", i == val ? 1 : 0) }
        end
      end
    end

    # 4-to-2 Priority Encoder
    class Encoder4to2 < SimComponent
      def setup_ports
        input :a, width: 4
        output :y, width: 2
        output :valid
      end

      def propagate
        val = in_val(:a) & 0xF
        if val == 0
          out_set(:y, 0)
          out_set(:valid, 0)
        elsif (val & 8) != 0
          out_set(:y, 3)
          out_set(:valid, 1)
        elsif (val & 4) != 0
          out_set(:y, 2)
          out_set(:valid, 1)
        elsif (val & 2) != 0
          out_set(:y, 1)
          out_set(:valid, 1)
        else
          out_set(:y, 0)
          out_set(:valid, 1)
        end
      end
    end

    # 8-to-3 Priority Encoder
    class Encoder8to3 < SimComponent
      def setup_ports
        input :a, width: 8
        output :y, width: 3
        output :valid
      end

      def propagate
        val = in_val(:a) & 0xFF
        if val == 0
          out_set(:y, 0)
          out_set(:valid, 0)
        else
          # Find highest set bit
          result = 0
          7.downto(0) do |i|
            if (val & (1 << i)) != 0
              result = i
              break
            end
          end
          out_set(:y, result)
          out_set(:valid, 1)
        end
      end
    end

    # Zero Detector
    class ZeroDetect < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :zero
      end

      def propagate
        out_set(:zero, in_val(:a) == 0 ? 1 : 0)
      end
    end

    # Sign Extender
    class SignExtend < SimComponent
      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end

      def setup_ports
        input :a, width: @in_width
        output :y, width: @out_width
      end

      def propagate
        val = in_val(:a)
        sign = (val >> (@in_width - 1)) & 1
        if sign == 1
          # Extend with 1s
          extension = ((1 << (@out_width - @in_width)) - 1) << @in_width
          out_set(:y, val | extension)
        else
          out_set(:y, val)
        end
      end
    end

    # Zero Extender
    class ZeroExtend < SimComponent
      port_input :a, width: 8
      port_output :y, width: 16

      behavior do
        y <= a
      end

      def initialize(name = nil, in_width: 8, out_width: 16)
        @in_width = in_width
        @out_width = out_width
        super(name)
      end

      def setup_ports
        return if @in_width == 8 && @out_width == 16
        @inputs[:a] = Wire.new("#{@name}.a", width: @in_width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @out_width)
        @inputs[:a].on_change { |_| propagate }
      end

      def propagate
        out_set(:y, in_val(:a))
      end
    end

    # Barrel Shifter
    class BarrelShifter < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @shift_width = Math.log2(width).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :shift, width: @shift_width
        input :dir      # 0 = left, 1 = right
        input :arith    # 1 = arithmetic right shift
        input :rotate   # 1 = rotate instead of shift
        output :y, width: @width
      end

      def propagate
        val = in_val(:a)
        shift = in_val(:shift) & ((1 << @shift_width) - 1)
        dir = in_val(:dir) & 1
        arith = in_val(:arith) & 1
        rotate = in_val(:rotate) & 1
        mask = (1 << @width) - 1

        result = if dir == 0  # Left
          if rotate == 1
            ((val << shift) | (val >> (@width - shift))) & mask
          else
            (val << shift) & mask
          end
        else  # Right
          if rotate == 1
            ((val >> shift) | (val << (@width - shift))) & mask
          elsif arith == 1
            sign = (val >> (@width - 1)) & 1
            shifted = val >> shift
            if sign == 1
              fill = ((1 << shift) - 1) << (@width - shift)
              (shifted | fill) & mask
            else
              shifted
            end
          else
            val >> shift
          end
        end

        out_set(:y, result)
      end
    end

    # Bit Reverser
    class BitReverse < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :y, width: @width
      end

      def propagate
        val = in_val(:a)
        result = 0
        @width.times do |i|
          result |= ((val >> i) & 1) << (@width - 1 - i)
        end
        out_set(:y, result)
      end
    end

    # Population Count (count 1 bits)
    class PopCount < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :count, width: @out_width
      end

      def propagate
        val = in_val(:a)
        count = 0
        @width.times do |i|
          count += (val >> i) & 1
        end
        out_set(:count, count)
      end
    end

    # Leading Zero Count
    class LZCount < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        @out_width = Math.log2(width + 1).ceil
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :count, width: @out_width
        output :all_zero
      end

      def propagate
        val = in_val(:a)
        count = 0
        (@width - 1).downto(0) do |i|
          if (val >> i) & 1 == 0
            count += 1
          else
            break
          end
        end
        out_set(:count, count)
        out_set(:all_zero, val == 0 ? 1 : 0)
      end
    end
  end
end
