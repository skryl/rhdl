# frozen_string_literal: true

module RHDL
  module DSL
    # If statement
    class IfStatement
      attr_reader :condition, :then_block, :elsif_blocks, :else_block

      def initialize(condition)
        @condition = condition
        @then_block = []
        @elsif_blocks = []
        @else_block = []
      end

      def add_then(stmt)
        @then_block << stmt
      end

      def add_elsif(condition, statements)
        @elsif_blocks << [condition, statements]
      end

      def add_else(stmt)
        @else_block << stmt
      end

      def to_verilog
        lines = []
        cond = condition.respond_to?(:to_verilog) ? condition.to_verilog : condition.to_s
        lines << "if (#{cond}) begin"
        then_block.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"

        elsif_blocks.each do |cond, stmts|
          c = cond.respond_to?(:to_verilog) ? cond.to_verilog : cond.to_s
          lines << "else if (#{c}) begin"
          stmts.each { |s| lines << "  #{s.to_verilog}" }
          lines << "end"
        end

        unless else_block.empty?
          lines << "else begin"
          else_block.each { |s| lines << "  #{s.to_verilog}" }
          lines << "end"
        end

        lines.join("\n")
      end
    end
  end
end
