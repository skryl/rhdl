# frozen_string_literal: true

module RHDL
  module DSL
    # Sequential assignment (inside process)
    class SequentialAssignment
      attr_reader :target, :value

      def initialize(target, value)
        @target = target
        @value = value
      end

      def to_verilog
        t = target.respond_to?(:to_verilog) ? target.to_verilog : target.to_s
        v = value.respond_to?(:to_verilog) ? value.to_verilog : value.to_s
        "#{t} <= #{v};"
      end
    end
  end
end
