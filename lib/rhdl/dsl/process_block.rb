# frozen_string_literal: true

module RHDL
  module DSL
    # Process block (sequential or combinational)
    class ProcessBlock
      attr_reader :name, :sensitivity_list, :statements, :is_clocked

      def initialize(name, sensitivity_list: [], clocked: false, &block)
        @name = name
        @sensitivity_list = sensitivity_list
        @statements = []
        @is_clocked = clocked
        @context = ProcessContext.new(self)
        @context.instance_eval(&block) if block_given?
      end

      def to_verilog
        sens = sensitivity_list.map { |s| s.respond_to?(:to_verilog) ? s.to_verilog : s.to_s }
        lines = []
        if is_clocked
          # For clocked processes, use posedge/negedge
          edge_list = sens.map { |s| "posedge #{s}" }
          lines << "always @(#{edge_list.join(' or ')}) begin"
        else
          lines << "always @(#{sens.join(' or ')}) begin"
        end
        statements.each { |s| lines << "  #{s.to_verilog}" }
        lines << "end"
        lines.join("\n")
      end

      def add_statement(stmt)
        @statements << stmt
      end
    end
  end
end
