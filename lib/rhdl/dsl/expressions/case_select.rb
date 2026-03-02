# frozen_string_literal: true

module RHDL
  module DSL
    # Expression-level case selection.
    # This keeps multi-way selects readable at the DSL layer while remaining
    # usable in assignment expressions.
    class CaseSelect
      include ExpressionOperators

      attr_reader :selector, :cases, :default_expr

      def initialize(selector, cases:, default:)
        @selector = selector
        @cases = normalize_cases(cases)
        @default_expr = default
      end

      def to_verilog
        selector_code = render(selector)
        result = render(default_expr)

        cases.to_a.reverse_each do |values, branch_expr|
          branch_code = render(branch_expr)
          conditions = values.map do |value|
            "(#{selector_code} == #{render(value)})"
          end
          cond_code = conditions.join(" || ")
          result = "(#{cond_code}) ? #{branch_code} : #{result}"
        end

        result
      end

      private

      def normalize_cases(raw_cases)
        source = raw_cases.is_a?(Hash) ? raw_cases : {}

        source.each_with_object({}) do |(raw_values, expr), memo|
          values = Array(raw_values).flatten
          values = values.reject(&:nil?)
          next if values.empty?

          memo[values] = expr
        end
      end

      def render(value)
        if value.respond_to?(:to_verilog)
          value.to_verilog
        elsif value.is_a?(String)
          value
        else
          value.to_s
        end
      end
    end
  end
end
