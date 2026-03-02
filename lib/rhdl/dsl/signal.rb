# frozen_string_literal: true

module RHDL
  module DSL
    # Internal signal definition
    class Signal
      attr_reader :name, :width, :default

      def initialize(name, width, default: nil)
        @name = name
        @width = width
        @default = default
      end

      def to_verilog
        type_str = width_decl
        default_str = default ? " = #{format_verilog_value(default)}" : ""
        "reg #{type_str} #{name}#{default_str};".gsub(/\s+/, ' ').strip
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end

      private

      def width_decl
        return "" if scalar_width?

        msb, lsb = width_bounds
        "[#{msb}:#{lsb}]"
      end

      def scalar_width?
        case width
        when Integer
          width <= 1
        when Range
          width.begin == width.end
        else
          width.to_s == "1"
        end
      end

      def width_bounds
        case width
        when Integer
          [width - 1, 0]
        when Range
          if width.begin.is_a?(Integer) && width.end.is_a?(Integer)
            [[width.begin, width.end].max, [width.begin, width.end].min]
          else
            [width.begin, width.end]
          end
        else
          ["#{width}-1", 0]
        end
      end

      def literal_size
        case width
        when Integer
          width
        when Range
          if width.begin.is_a?(Integer) && width.end.is_a?(Integer)
            high = [width.begin, width.end].max
            low = [width.begin, width.end].min
            high - low + 1
          end
        else
          width
        end
      end

      def format_verilog_value(val)
        size = literal_size
        if size == 1
          val == 0 ? "1'b0" : "1'b1"
        elsif size.is_a?(Integer)
          "#{size}'b#{val.to_s(2).rjust(size, '0')}"
        elsif size
          "#{size}'d#{val}"
        else
          val.to_s
        end
      end
    end
  end
end
