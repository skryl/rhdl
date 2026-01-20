# frozen_string_literal: true

module RHDL
  module Sim
    # Vec represents a hardware array of signals with hardware-indexable access
    #
    # Similar to Chisel's Vec, this allows creating arrays of signals that can
    # be indexed at both elaboration time (constant index) and runtime (hardware index).
    #
    # @example Create a Vec in a component
    #   class RegisterFile < Component
    #     parameter :depth, default: 32
    #     parameter :width, default: 64
    #
    #     input :read_addr, width: 5
    #     input :write_addr, width: 5
    #     input :write_data, width: :width
    #     input :write_enable
    #     input :clk
    #     output :read_data, width: :width
    #
    #     vec :regs, count: :depth, width: :width  # Creates Vec of 32 64-bit wires
    #
    #     behavior do
    #       # Hardware-indexed read (creates mux tree)
    #       read_data <= regs[read_addr]
    #     end
    #   end
    #
    # @example Vec of bundles
    #   vec :ports, count: 4, type: AxiLite
    #
    class Vec
      attr_reader :name, :count, :element_width, :elements

      def initialize(name, count:, width: 1, component: nil)
        @name = name
        @count = count
        @element_width = width
        @component = component
        @elements = []

        setup_elements if component
      end

      # Access element by constant index (elaboration time)
      def [](index)
        if index.is_a?(Integer)
          @elements[index]
        else
          # Hardware index - return a VecAccess expression for synthesis
          VecAccess.new(self, index)
        end
      end

      # Set element at constant index
      def []=(index, value)
        raise ArgumentError, "Vec index must be constant integer for assignment" unless index.is_a?(Integer)
        @elements[index]&.set(value)
      end

      # Iterate over all elements
      def each(&block)
        @elements.each(&block)
      end

      def each_with_index(&block)
        @elements.each_with_index(&block)
      end

      # Map over elements
      def map(&block)
        @elements.map(&block)
      end

      # Get all values as array
      def values
        @elements.map(&:get)
      end

      # Set all values from array
      def set_values(arr)
        arr.each_with_index do |val, i|
          @elements[i]&.set(val)
        end
      end

      # Total width (all elements combined)
      def total_width
        @count * @element_width
      end

      # Number of bits needed to index this Vec
      def index_width
        (@count - 1).bit_length.clamp(1, 32)
      end

      private

      def setup_elements
        @count.times do |i|
          wire_name = "#{@component.name}.#{@name}[#{i}]"
          wire = Wire.new(wire_name, width: @element_width)
          @elements << wire
        end
      end
    end

    # Represents a hardware-indexed access to a Vec
    # Used in behavior blocks to generate mux trees for synthesis
    class VecAccess
      attr_reader :vec, :index

      def initialize(vec, index)
        @vec = vec
        @index = index
      end

      # Get the width of the accessed element
      def width
        @vec.element_width
      end

      # In simulation, resolve the index and return the value
      def value
        idx = resolve_index(@index)
        idx = idx.clamp(0, @vec.count - 1)
        @vec.elements[idx]&.get || 0
      end

      # Allow comparison operations
      def ==(other)
        value == resolve_value(other)
      end

      def to_i
        value
      end

      private

      def resolve_index(idx)
        case idx
        when Integer
          idx
        when Wire
          idx.get
        when SignalProxy, OutputProxy, LocalProxy
          idx.value
        else
          idx.respond_to?(:value) ? idx.value : idx.to_i
        end
      end

      def resolve_value(val)
        case val
        when Integer
          val
        when Wire
          val.get
        else
          val.respond_to?(:value) ? val.value : val.to_i
        end
      end
    end

    # Vec instance for simulation with full wire integration
    class VecInstance
      attr_reader :name, :count, :element_width, :elements, :component

      def initialize(name, count:, width:, component:, direction: nil)
        @name = name
        @count = count
        @element_width = width
        @component = component
        @direction = direction
        @elements = []

        setup_elements
      end

      # Access element by index
      def [](index)
        if index.is_a?(Integer)
          # Constant index - direct access
          @elements[index]
        else
          # Hardware index - return proxy for behavior block
          VecAccessProxy.new(self, index, @component)
        end
      end

      # Set element at constant index
      def []=(index, value)
        raise ArgumentError, "Vec index must be constant for assignment" unless index.is_a?(Integer)
        @elements[index]&.set(value.respond_to?(:value) ? value.value : value)
      end

      # Iterate over elements
      def each(&block)
        @elements.each(&block)
      end

      def each_with_index(&block)
        @elements.each_with_index(&block)
      end

      # Map over elements
      def map(&block)
        @elements.map(&block)
      end

      # Get all values
      def values
        @elements.map(&:get)
      end

      # Set all values
      def set_values(arr)
        arr.each_with_index do |val, i|
          @elements[i]&.set(val)
        end
      end

      # Number of bits needed to index
      def index_width
        (@count - 1).bit_length.clamp(1, 32)
      end

      # Total width
      def total_width
        @count * @element_width
      end

      # Generate flattened port names for Verilog
      def flattened_ports
        @elements.map.with_index do |_, i|
          ["#{@name}_#{i}".to_sym, @element_width, @direction]
        end
      end

      private

      def setup_elements
        @count.times do |i|
          wire_name = "#{@component.name}.#{@name}[#{i}]"
          wire = Wire.new(wire_name, width: @element_width)
          @elements << wire

          # Register with component if direction specified
          port_name = "#{@name}_#{i}".to_sym
          if @direction == :input
            @component.inputs[port_name] = wire
            wire.on_change { |_| @component.propagate }
          elsif @direction == :output
            @component.outputs[port_name] = wire
          else
            # Internal signal
            @component.internal_signals[port_name] = wire
          end
        end
      end
    end

    # Proxy for hardware-indexed Vec access in behavior blocks
    class VecAccessProxy
      attr_reader :vec, :index, :width

      def initialize(vec, index, component)
        @vec = vec
        @index = index
        @component = component
        @width = vec.element_width
      end

      # Get the value (for simulation)
      def value
        idx = resolve_value(@index)
        idx = idx.clamp(0, @vec.count - 1)
        @vec.elements[idx]&.get || 0
      end

      def to_i
        value
      end

      # Arithmetic operators
      def +(other)
        ValueProxy.new(nil, value + resolve_value(other), @width + 1, nil)
      end

      def -(other)
        ValueProxy.new(nil, value - resolve_value(other), @width, nil)
      end

      def &(other)
        ValueProxy.new(nil, value & resolve_value(other), @width, nil)
      end

      def |(other)
        ValueProxy.new(nil, value | resolve_value(other), @width, nil)
      end

      def ^(other)
        ValueProxy.new(nil, value ^ resolve_value(other), @width, nil)
      end

      def ==(other)
        value == resolve_value(other) ? 1 : 0
      end

      def !=(other)
        value != resolve_value(other) ? 1 : 0
      end

      private

      def resolve_value(val)
        case val
        when Integer
          val
        when Wire
          val.get
        when SignalProxy, OutputProxy, LocalProxy, VecAccessProxy
          val.value
        else
          val.respond_to?(:value) ? val.value : val.to_i
        end
      end
    end
  end
end
