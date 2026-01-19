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
        type_str = width > 1 ? "[#{width-1}:0]" : ""
        default_str = default ? " = #{format_verilog_value(default)}" : ""
        "reg #{type_str} #{name}#{default_str};".gsub(/\s+/, ' ').strip
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
