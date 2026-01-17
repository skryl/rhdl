# frozen_string_literal: true

module RHDL
  module HDL
    # Context for evaluating behavior blocks in simulation mode
    class BehaviorSimContext
      def initialize(component)
        @component = component
        @assignments = []
        @locals = {}

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
        @locals.clear
        instance_eval(&block)

        # Apply all collected assignments
        @assignments.each do |assignment|
          assignment[:wire].set(assignment[:value])
        end
      end

      def record_assignment(wire, value)
        @assignments << { wire: wire, value: value }
      end

      # Define a local variable (becomes a wire in synthesis)
      def local(name, expr, width: nil)
        value = resolve_value(expr)
        w = width || (value == 0 ? 1 : [value.bit_length, 1].max)
        mask = (1 << w) - 1
        masked_value = value & mask

        # Store the local and make it accessible
        local_var = SimLocalProxy.new(name, masked_value, w, self)
        @locals[name] = local_var

        # Define accessor method for this local
        define_singleton_method(name) { @locals[name] }

        local_var
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

      # Simple if-else for single expression
      def if_else(condition, then_expr, else_expr)
        mux(condition, then_expr, else_expr)
      end

      private

      def resolve_value(sig)
        case sig
        when SimSignalProxy, SimOutputProxy, SimLocalProxy
          sig.value
        when Integer
          sig
        else
          sig.respond_to?(:value) ? sig.value : sig.to_i
        end
      end

      def resolve_value_with_width(sig)
        case sig
        when SimSignalProxy, SimOutputProxy, SimLocalProxy
          [sig.value, sig.width]
        when Integer
          [sig, sig == 0 ? 1 : sig.bit_length]
        else
          [sig.to_i, 8]
        end
      end
    end

    # Proxy for local variables in simulation
    class SimLocalProxy
      attr_reader :name, :value, :width

      def initialize(name, value, width, context)
        @name = name
        @value = value
        @width = width
        @context = context
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          high = [index.begin, index.end].max
          low = [index.begin, index.end].min
          slice_width = high - low + 1
          mask = (1 << slice_width) - 1
          SimLocalProxy.new("#{@name}[#{index}]", (@value >> low) & mask, slice_width, @context)
        else
          SimLocalProxy.new("#{@name}[#{index}]", (@value >> index) & 1, 1, @context)
        end
      end

      # Arithmetic operators
      def +(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value + other_val, @width + 1, @context)
      end

      def -(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value - other_val, @width, @context)
      end

      def *(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : 8
        SimLocalProxy.new(nil, @value * other_val, @width + other_width, @context)
      end

      # Bitwise operators
      def &(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        SimLocalProxy.new(nil, @value & other_val, [@width, other_width].max, @context)
      end

      def |(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        SimLocalProxy.new(nil, @value | other_val, [@width, other_width].max, @context)
      end

      def ^(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        SimLocalProxy.new(nil, @value ^ other_val, [@width, other_width].max, @context)
      end

      def ~
        mask = (1 << @width) - 1
        SimLocalProxy.new(nil, (~@value) & mask, @width, @context)
      end

      # Shift operators
      def <<(amount)
        amt = @context.send(:resolve_value, amount)
        SimLocalProxy.new(nil, @value << amt, @width, @context)
      end

      def >>(amount)
        amt = @context.send(:resolve_value, amount)
        SimLocalProxy.new(nil, @value >> amt, @width, @context)
      end

      # Comparison operators
      def ==(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value == other_val ? 1 : 0, 1, @context)
      end

      def !=(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value != other_val ? 1 : 0, 1, @context)
      end

      def <(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value < other_val ? 1 : 0, 1, @context)
      end

      def >(other)
        other_val = @context.send(:resolve_value, other)
        SimLocalProxy.new(nil, @value > other_val ? 1 : 0, 1, @context)
      end

      def to_i
        @value
      end
    end
  end
end
