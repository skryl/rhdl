# frozen_string_literal: true

module RHDL
  module DSL
    # For loop
    class ForLoop
      attr_reader :variable, :range, :statements

      def initialize(variable, range)
        @variable = variable
        @range = range
        @statements = []
      end

      def add_statement(stmt)
        @statements << stmt
      end

      def to_vhdl
        lines = []
        lines << "for #{variable} in #{range.min} to #{range.max} loop"
        statements.each { |s| lines << "  #{s.to_vhdl}" }
        lines << "end loop;"
        lines.join("\n")
      end

      def to_verilog
        lines = []
        lines << "for (#{variable} = #{range.min}; #{variable} <= #{range.max}; #{variable} = #{variable} + 1) begin"
        statements.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"
        lines.join("\n")
      end
    end
  end
end
