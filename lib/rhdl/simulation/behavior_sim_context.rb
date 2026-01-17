# frozen_string_literal: true

module RHDL
  module HDL
    # Context for evaluating behavior blocks in simulation mode
    class BehaviorSimContext
      def initialize(component)
        @component = component
        @assignments = []

        # Create accessor methods for all inputs and outputs
        component.inputs.each do |name, wire|
          define_singleton_method(name) { SimSignalProxy.new(name, wire, :input, self) }
        end
        component.outputs.each do |name, wire|
          define_singleton_method(name) { SimOutputProxy.new(name, wire, self) }
        end
        component.internal_signals.each do |name, wire|
          define_singleton_method(name) { SimOutputProxy.new(name, wire, self) }
        end
      end

      def evaluate(&block)
        @assignments.clear
        instance_eval(&block)

        # Apply all collected assignments
        @assignments.each do |assignment|
          assignment[:wire].set(assignment[:value])
        end
      end

      def record_assignment(wire, value)
        @assignments << { wire: wire, value: value }
      end

      # Helper for conditional expressions (mux)
      def mux(condition, when_true, when_false)
        cond_val = resolve_value(condition)
        cond_val != 0 ? resolve_value(when_true) : resolve_value(when_false)
      end

      # Helper for creating literal values with explicit width
      def lit(value, width:)
        value & ((1 << width) - 1)
      end

      # Helper for concatenation
      def cat(*signals)
        result = 0
        offset = 0
        signals.reverse.each do |sig|
          val, width = resolve_value_with_width(sig)
          result |= (val << offset)
          offset += width
        end
        result
      end

      private

      def resolve_value(sig)
        case sig
        when SimSignalProxy, SimOutputProxy
          sig.value
        when Integer
          sig
        else
          sig.respond_to?(:value) ? sig.value : sig.to_i
        end
      end

      def resolve_value_with_width(sig)
        case sig
        when SimSignalProxy, SimOutputProxy
          [sig.value, sig.width]
        when Integer
          [sig, sig == 0 ? 1 : sig.bit_length]
        else
          [sig.to_i, 8]
        end
      end
    end
  end
end
