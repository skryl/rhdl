# frozen_string_literal: true

module RHDL
  module DSL
    # Sequential assignment (inside process)
    class SequentialAssignment
      VALID_KINDS = %i[auto nonblocking blocking].freeze

      attr_reader :target, :value, :kind

      def initialize(target, value, kind: :auto, nonblocking: nil)
        kind = nonblocking ? :nonblocking : :blocking unless nonblocking.nil?
        unless VALID_KINDS.include?(kind)
          raise ArgumentError, "Invalid assignment kind: #{kind.inspect}. Valid: #{VALID_KINDS.join(', ')}"
        end

        @target = target
        @value = value
        @kind = kind
      end

      def nonblocking?(default: true)
        case kind
        when :nonblocking then true
        when :blocking then false
        else default
        end
      end

      def to_verilog(nonblocking: nil)
        t = target.respond_to?(:to_verilog) ? target.to_verilog : target.to_s
        v = value.respond_to?(:to_verilog) ? value.to_verilog : value.to_s
        op = if nonblocking.nil?
          nonblocking?(default: true) ? "<=" : "="
        else
          nonblocking ? "<=" : "="
        end
        "#{t} #{op} #{v};"
      end
    end
  end
end
