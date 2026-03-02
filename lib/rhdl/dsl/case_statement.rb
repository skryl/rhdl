# frozen_string_literal: true

module RHDL
  module DSL
    # Case statement
    class CaseStatement
      attr_reader :selector, :when_blocks, :default_block

      def initialize(selector)
        @selector = selector
        @when_blocks = []
        @default_block = []
      end

      def add_when(value, statements)
        @when_blocks << [value, statements]
      end

      def add_default(statements)
        @default_block = statements
      end

      def to_verilog(nonblocking: nil)
        lines = []
        sel = selector.respond_to?(:to_verilog) ? selector.to_verilog : selector.to_s
        lines << "case (#{sel})"

        when_blocks.each do |val, stmts|
          v = val.respond_to?(:to_verilog) ? val.to_verilog : format_verilog_case_value(val)
          lines << "  #{v}: begin"
          stmts.each { |s| lines << "    #{render_statement(s, nonblocking: nonblocking)}" }
          lines << "  end"
        end

        unless default_block.empty?
          lines << "  default: begin"
          default_block.each { |s| lines << "    #{render_statement(s, nonblocking: nonblocking)}" }
          lines << "  end"
        end

        lines << "endcase"
        lines.join("\n")
      end

      private

      def format_verilog_case_value(val)
        val.is_a?(Integer) ? val.to_s : val.to_s
      end

      def render_statement(statement, nonblocking:)
        return statement.to_verilog(nonblocking: nonblocking) if accepts_nonblocking_kw?(statement)

        statement.to_verilog
      end

      def accepts_nonblocking_kw?(statement)
        params = statement.method(:to_verilog).parameters
        params.any? { |type, name| [:key, :keyreq].include?(type) && name == :nonblocking } ||
          params.any? { |type, _name| type == :keyrest }
      end
    end
  end
end
