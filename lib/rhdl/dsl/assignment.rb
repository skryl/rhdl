# frozen_string_literal: true

module RHDL
  module DSL
    # Signal assignment
    class Assignment
      attr_reader :target, :value, :condition

      def initialize(target, value, condition: nil)
        @target = target
        @value = value
        @condition = condition
      end

      def to_verilog
        t = target.respond_to?(:to_verilog) ? target.to_verilog : target.to_s
        v = value.respond_to?(:to_verilog) ? value.to_verilog : format_verilog_literal(value)

        if condition
          c = condition.respond_to?(:to_verilog) ? condition.to_verilog : condition.to_s
          "assign #{t} = #{c} ? #{v} : #{t};"
        else
          "assign #{t} = #{v};"
        end
      end

      private

      def format_verilog_literal(val)
        if val.is_a?(Integer)
          if target.respond_to?(:width) && target.width > 1
            "#{target.width}'b#{val.to_s(2).rjust(target.width, '0')}"
          else
            val == 0 ? "1'b0" : "1'b1"
          end
        else
          val.to_s
        end
      end
    end
  end
end
