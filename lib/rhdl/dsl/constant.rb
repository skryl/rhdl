# frozen_string_literal: true

module RHDL
  module DSL
    # Constant definition
    class Constant
      attr_reader :name, :width, :value

      def initialize(name, width, value)
        @name = name
        @width = width
        @value = value
      end

      def to_verilog
        type_str = width > 1 ? "[#{width-1}:0]" : ""
        "localparam #{type_str} #{name} = #{format_verilog_value(value)};".gsub(/\s+/, ' ').strip
      end

      def to_signal_ref
        SignalRef.new(name, width: width)
      end

      private

      def format_verilog_value(val)
        if width == 1
          val == 0 ? "1'b0" : "1'b1"
        else
          "#{width}'b#{val.to_s(2).rjust(width, '0')}"
        end
      end
    end
  end
end
