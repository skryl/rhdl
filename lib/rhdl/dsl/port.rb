# frozen_string_literal: true

module RHDL
  module DSL
    # Port definition
    class Port
      attr_reader :name, :direction, :width, :default

      def initialize(name, direction, width, default: nil)
        @name = name
        @direction = direction
        @width = width
        @default = default
      end

      def to_verilog
        dir = case direction
              when :in then "input"
              when :out then "output"
              when :inOut then "inOut"
              end
        "#{dir} #{width_decl}#{name}".strip
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end

      private

      def width_decl
        return "" if scalar_width?

        msb, lsb = width_bounds
        "[#{msb}:#{lsb}] "
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
    end
  end
end
