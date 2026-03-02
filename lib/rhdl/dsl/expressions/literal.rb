# frozen_string_literal: true

module RHDL
  module DSL
    # Numeric literal that preserves optional Verilog base/width formatting.
    class Literal
      include ExpressionOperators

      attr_reader :value, :width, :base, :signed

      def initialize(value, width: nil, base: nil, signed: false)
        @base = normalize_base(base)
        @signed = !!signed
        @value = normalize_value(value, @base)
        @width = normalize_width(width)
      end

      def to_verilog
        return value.to_s if base.nil?

        digits = render_digits
        return digits if base == "d" && width.nil?

        prefix = width.nil? ? "" : width.to_s
        sign = signed ? "s" : ""
        "#{prefix}'#{sign}#{base}#{digits}"
      end

      private

      def normalize_width(width)
        return nil if width.nil?
        return width if width.is_a?(Integer)

        text = width.to_s.strip
        return nil if text.empty?
        return Integer(text) if text.match?(/\A-?\d+\z/)

        text
      end

      def normalize_base(base)
        token = base.to_s.strip.downcase
        return nil if token.empty?

        case token
        when "2", "b", "bin", "binary"
          "b"
        when "8", "o", "oct", "octal"
          "o"
        when "10", "d", "dec", "decimal"
          "d"
        when "16", "h", "hex", "hexadecimal"
          "h"
        else
          token
        end
      end

      def normalize_value(value, normalized_base)
        return value if value.is_a?(Integer)

        text = value.to_s.strip
        return 0 if text.empty?
        return Integer(text) if text.match?(/\A-?\d+\z/)

        radix = case normalized_base
        when "b" then 2
        when "o" then 8
        when "d" then 10
        when "h" then 16
        else 10
        end
        Integer(text, radix)
      rescue ArgumentError
        0
      end

      def render_digits
        case base
        when "b" then value.to_s(2)
        when "o" then value.to_s(8)
        when "d" then value.to_s(10)
        when "h" then value.to_s(16)
        else value.to_s
        end
      end
    end
  end
end
