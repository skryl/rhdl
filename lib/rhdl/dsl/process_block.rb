# frozen_string_literal: true

module RHDL
  module DSL
    # Process block (sequential or combinational)
    class ProcessBlock
      attr_reader :name, :sensitivity_list, :statements, :is_clocked, :is_initial

      def initialize(name, sensitivity_list: [], clocked: false, initial: false, &block)
        @name = name
        @sensitivity_list = sensitivity_list
        @statements = []
        @is_clocked = clocked
        @is_initial = initial
        @context = ProcessContext.new(self)
        @context.instance_eval(&block) if block_given?
      end

      def to_verilog
        sens = sensitivity_list.map { |s| render_sensitivity_item(s) }.compact
        lines = []
        if is_initial
          lines << "initial begin"
        elsif is_clocked
          # For clocked processes, default to posedge unless edge already specified.
          edge_list = sens.map { |s| clock_edge_item(s) }
          lines << "always @(#{edge_list.join(' or ')}) begin"
        else
          clause = sens.empty? ? "*" : sens.join(' or ')
          lines << "always @(#{clause}) begin"
        end
        statements.each { |s| lines << "  #{render_statement(s)}" }
        lines << "end"
        lines.join("\n")
      end

      def add_statement(stmt)
        @statements << stmt
      end

      private

      def render_sensitivity_item(item)
        case item
        when Hash
          edge = value_for(item, :edge).to_s.strip
          signal = value_for(item, :signal)
          rendered_signal = signal.respond_to?(:to_verilog) ? signal.to_verilog : signal.to_s
          return nil if rendered_signal.strip.empty?
          return rendered_signal if edge.empty? || edge == "any"

          "#{edge} #{rendered_signal}"
        else
          rendered = item.respond_to?(:to_verilog) ? item.to_verilog : item.to_s
          rendered = rendered.to_s.strip
          rendered.empty? ? nil : rendered
        end
      end

      def clock_edge_item(rendered_item)
        text = rendered_item.to_s.strip
        return text if text.start_with?("posedge ", "negedge ")

        "posedge #{text}"
      end

      def value_for(hash, key)
        return nil unless hash.is_a?(Hash)
        return hash[key] if hash.key?(key)

        text = key.to_s
        return hash[text] if hash.key?(text)

        symbol = key.to_sym
        return hash[symbol] if hash.key?(symbol)

        nil
      end

      def render_statement(statement)
        return statement.to_verilog(nonblocking: is_clocked) if accepts_nonblocking_kw?(statement)

        statement.to_verilog
      end

      def accepts_nonblocking_kw?(statement)
        return false unless statement.respond_to?(:to_verilog)

        params = statement.method(:to_verilog).parameters
        params.any? { |type, name| [:key, :keyreq].include?(type) && name == :nonblocking } ||
          params.any? { |type, _name| type == :keyrest }
      end
    end
  end
end
