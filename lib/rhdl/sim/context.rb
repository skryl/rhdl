# frozen_string_literal: true

module RHDL
  module Sim
    # Context for evaluating behavior blocks in simulation mode
    class BehaviorContext
      attr_reader :proxy_pool

      def initialize(component)
        @component = component
        @assignments = []
        @locals = {}
        @proxy_pool = ProxyPoolAccessor.pool

        # Create accessor methods for all inputs and outputs
        component.inputs.each do |name, wire|
          define_singleton_method(name) { SignalProxy.new(name, wire, :input, self) }
        end
        component.outputs.each do |name, wire|
          define_singleton_method(name) { OutputProxy.new(name, wire, self) }
        end
        component.internal_signals.each do |name, wire|
          define_singleton_method(name) { OutputProxy.new(name, wire, self) }
        end

        # Create accessor methods for Vecs
        if component.instance_variable_defined?(:@vecs) && component.instance_variable_get(:@vecs)
          component.instance_variable_get(:@vecs).each do |name, vec_inst|
            define_singleton_method(name) { VecProxy.new(vec_inst, self) }
          end
        end

        # Create accessor methods for Bundles
        if component.instance_variable_defined?(:@bundles) && component.instance_variable_get(:@bundles)
          component.instance_variable_get(:@bundles).each do |name, bundle_inst|
            define_singleton_method(name) { BundleProxy.new(bundle_inst, self) }
          end
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

        # Release pooled proxies back to pool
        @proxy_pool.release_all
      end

      def record_assignment(wire, value)
        @assignments << { wire: wire, value: value }
      end

      # Access component instance variables (e.g., @width, @input_count)
      def param(name)
        @component.instance_variable_get(:"@#{name}")
      end

      # Get the actual runtime width of a port
      def port_width(name)
        wire = @component.inputs[name] || @component.outputs[name]
        wire&.width || 1
      end

      # Sequential component support: access state variable
      def state
        @component.instance_variable_get(:@state) || 0
      end

      # Sequential component support: set state variable
      def set_state(value)
        @component.instance_variable_set(:@state, value)
      end

      # Sequential component support: check for rising clock edge
      def rising_edge?(clock_name = :clk)
        return false unless @component.respond_to?(:rising_edge?)
        @component.rising_edge?
      end

      # Memory component support: read from memory array
      def mem_read(index, array_name = :memory)
        mem = @component.instance_variable_get(:"@#{array_name}")
        return 0 unless mem
        idx = resolve_value(index)
        mem[idx] || 0
      end

      # Memory component support: write to memory array
      def mem_write(index, value, array_name = :memory)
        mem = @component.instance_variable_get(:"@#{array_name}")
        return unless mem
        idx = resolve_value(index)
        val = resolve_value(value)
        mem[idx] = val
      end

      # Set stack pointer (for Stack component)
      def set_sp(value)
        @component.instance_variable_set(:@sp, resolve_value(value))
      end

      # Generic state variable access (for components with multiple state vars like FIFO)
      def get_var(name)
        @component.instance_variable_get(:"@#{name}") || 0
      end

      def set_var(name, value)
        @component.instance_variable_set(:"@#{name}", resolve_value(value))
      end

      # Dynamic input access by name
      def input_val(name)
        wire = @component.inputs[name.to_sym]
        return 0 unless wire
        wire.value
      end

      # Dynamic output assignment by name
      def output_set(name, value)
        wire = @component.outputs[name.to_sym]
        return unless wire
        record_assignment(wire, resolve_value(value))
      end

      # Get memory array size
      def mem_size(array_name = :memory)
        mem = @component.instance_variable_get(:"@#{array_name}")
        mem&.size || 0
      end

      # Create a range-based iteration for synthesis-friendly loops
      # Usage: each_bit(a) { |bit, i| ... }
      def each_bit(signal, &block)
        val = resolve_value(signal)
        w = signal.respond_to?(:width) ? signal.width : port_width(signal)
        w.times { |i| yield((val >> i) & 1, i) }
      end

      # Reduction operations
      def reduce_or(signal)
        val = resolve_value(signal)
        val != 0 ? 1 : 0
      end

      def reduce_and(signal)
        w = signal.respond_to?(:width) ? signal.width : 8
        mask = MaskCache.mask(w)
        val = resolve_value(signal)
        (val & mask) == mask ? 1 : 0
      end

      def reduce_xor(signal)
        val = resolve_value(signal)
        count = 0
        while val > 0
          count += val & 1
          val >>= 1
        end
        count & 1
      end

      # Define a local variable (becomes a wire in synthesis)
      def local(name, expr, width: nil)
        value = resolve_value(expr)
        w = width || (value == 0 ? 1 : [value.bit_length, 1].max)
        masked_value = value & MaskCache.mask(w)

        # Store the local and make it accessible
        local_var = LocalProxy.new(name, masked_value, w, self)
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
      # Returns a LocalProxy so operators work with other proxies
      def lit(value, width:)
        masked_value = value & MaskCache.mask(width)
        LocalProxy.new(nil, masked_value, width, self)
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

      # Case select - lookup table style case statement
      # Usage: case_select(op, { 0 => a + b, 1 => a - b, 2 => a & b }, default: 0)
      def case_select(selector, cases, default: 0)
        sel_val = resolve_value(selector)
        if cases.key?(sel_val)
          resolve_value(cases[sel_val])
        else
          resolve_value(default)
        end
      end

      # Memory read expression - reads from memory array using address expression
      # For simulation, this directly reads from the component's memory array
      # @param memory_name [Symbol] The memory array name
      # @param addr [Object] The address expression
      # @param width [Integer] The data width (unused in simulation but needed for consistency)
      def mem_read_expr(memory_name, addr, width: 8)
        addr_val = resolve_value(addr)
        if @component.respond_to?(:mem_read)
          @component.mem_read(memory_name, addr_val)
        else
          # Fallback: try to read from _memory_arrays
          arrays = @component.instance_variable_get(:@_memory_arrays)
          if arrays && arrays[memory_name]
            arrays[memory_name][addr_val] || 0
          else
            0
          end
        end
      end

      private

      def resolve_value(sig)
        case sig
        when SignalProxy, OutputProxy, LocalProxy
          sig.value
        when Integer
          sig
        else
          sig.respond_to?(:value) ? sig.value : sig.to_i
        end
      end

      def resolve_value_with_width(sig)
        case sig
        when SignalProxy, OutputProxy, LocalProxy, ValueProxy
          [sig.value, sig.width]
        when Integer
          [sig, sig == 0 ? 1 : sig.bit_length]
        else
          # Fallback: check if it has value and width methods
          if sig.respond_to?(:value) && sig.respond_to?(:width)
            [sig.value, sig.width]
          else
            [sig.to_i, 8]
          end
        end
      end
    end

    # Proxy for local variables in simulation
    class LocalProxy
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
          LocalProxy.new("#{@name}[#{index}]", (@value >> low) & MaskCache.mask(slice_width), slice_width, @context)
        else
          LocalProxy.new("#{@name}[#{index}]", (@value >> index) & 1, 1, @context)
        end
      end

      # Arithmetic operators
      def +(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value + other_val, @width + 1, @context)
      end

      def -(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value - other_val, @width, @context)
      end

      def *(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : 8
        LocalProxy.new(nil, @value * other_val, @width + other_width, @context)
      end

      # Bitwise operators
      def &(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        LocalProxy.new(nil, @value & other_val, [@width, other_width].max, @context)
      end

      def |(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        LocalProxy.new(nil, @value | other_val, [@width, other_width].max, @context)
      end

      def ^(other)
        other_val = @context.send(:resolve_value, other)
        other_width = other.respond_to?(:width) ? other.width : @width
        LocalProxy.new(nil, @value ^ other_val, [@width, other_width].max, @context)
      end

      def ~
        LocalProxy.new(nil, (~@value) & MaskCache.mask(@width), @width, @context)
      end

      # Shift operators
      def <<(amount)
        amt = @context.send(:resolve_value, amount)
        LocalProxy.new(nil, @value << amt, @width, @context)
      end

      def >>(amount)
        amt = @context.send(:resolve_value, amount)
        LocalProxy.new(nil, @value >> amt, @width, @context)
      end

      # Comparison operators
      def ==(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value == other_val ? 1 : 0, 1, @context)
      end

      def !=(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value != other_val ? 1 : 0, 1, @context)
      end

      def <(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value < other_val ? 1 : 0, 1, @context)
      end

      def >(other)
        other_val = @context.send(:resolve_value, other)
        LocalProxy.new(nil, @value > other_val ? 1 : 0, 1, @context)
      end

      def to_i
        @value
      end
    end

    # Proxy for Vec access in behavior blocks (simulation mode)
    class VecProxy
      attr_reader :vec_inst, :context

      def initialize(vec_inst, context)
        @vec_inst = vec_inst
        @context = context
      end

      # Access element by index (constant or hardware)
      def [](index)
        resolved_idx = resolve_value(index)
        clamped_idx = resolved_idx.clamp(0, @vec_inst.count - 1)
        wire = @vec_inst.elements[clamped_idx]
        SignalProxy.new("#{@vec_inst.name}[#{clamped_idx}]", wire, :internal, @context)
      end

      # Set element at constant index
      def []=(index, value)
        resolved_idx = resolve_value(index)
        clamped_idx = resolved_idx.clamp(0, @vec_inst.count - 1)
        wire = @vec_inst.elements[clamped_idx]
        val = resolve_value(value)
        @context.record_assignment(wire, val)
      end

      # Iterate over elements
      def each(&block)
        @vec_inst.elements.each_with_index do |wire, i|
          proxy = SignalProxy.new("#{@vec_inst.name}[#{i}]", wire, :internal, @context)
          block.call(proxy)
        end
      end

      def each_with_index(&block)
        @vec_inst.elements.each_with_index do |wire, i|
          proxy = SignalProxy.new("#{@vec_inst.name}[#{i}]", wire, :internal, @context)
          block.call(proxy, i)
        end
      end

      # Get count of elements
      def count
        @vec_inst.count
      end

      def length
        @vec_inst.count
      end

      # Get width of each element
      def element_width
        @vec_inst.element_width
      end

      private

      def resolve_value(val)
        case val
        when Integer
          val
        when SignalProxy, OutputProxy, LocalProxy
          val.value
        else
          val.respond_to?(:value) ? val.value : val.to_i
        end
      end
    end

    # Proxy for Bundle access in behavior blocks (simulation mode)
    class BundleProxy
      attr_reader :bundle_inst, :context

      def initialize(bundle_inst, context)
        @bundle_inst = bundle_inst
        @context = context
      end

      # Access field by name
      def method_missing(method_name, *args, &block)
        if @bundle_inst.fields.key?(method_name)
          wire = @bundle_inst.fields[method_name]
          direction = @bundle_inst.field_direction(method_name)
          if direction == :output
            OutputProxy.new("#{@bundle_inst.name}.#{method_name}", wire, @context)
          else
            SignalProxy.new("#{@bundle_inst.name}.#{method_name}", wire, :input, @context)
          end
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @bundle_inst.fields.key?(method_name) || super
      end

      # Get all field values as hash
      def to_h
        @bundle_inst.fields.transform_values(&:get)
      end

      # Check if field exists
      def field?(name)
        @bundle_inst.fields.key?(name)
      end

      # Get field direction
      def field_direction(name)
        @bundle_inst.field_direction(name)
      end
    end
  end
end
