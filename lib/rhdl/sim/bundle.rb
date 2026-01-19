# frozen_string_literal: true

module RHDL
  module Sim
    # Base class for defining Bundle types (aggregate interface types)
    #
    # Bundles group named fields into reusable interface definitions,
    # similar to Chisel's Bundle or SystemVerilog structs/interfaces.
    #
    # @example Define a simple bundle
    #   class AxiLite < Bundle
    #     field :awaddr, width: 32, direction: :output
    #     field :awvalid, width: 1, direction: :output
    #     field :awready, width: 1, direction: :input
    #     field :wdata, width: 32, direction: :output
    #     field :wvalid, width: 1, direction: :output
    #     field :wready, width: 1, direction: :input
    #   end
    #
    # @example Use bundle as port type
    #   class MyModule < Component
    #     input_bundle :axi, AxiLite
    #     output_bundle :response, ResponseBundle
    #   end
    #
    # @example Flipped bundle (reverse all directions)
    #   class Consumer < Component
    #     input_bundle :port, AxiLite, flipped: true
    #   end
    #
    class Bundle
      class << self
        def inherited(subclass)
          super
          subclass.instance_variable_set(:@_field_defs, (@_field_defs || []).dup)
        end

        def _field_defs
          @_field_defs ||= []
        end

        # Define a field in the bundle
        #
        # @param name [Symbol] Field name
        # @param width [Integer] Bit width (default: 1)
        # @param direction [Symbol] :input or :output (default: :output)
        #
        # @example
        #   field :data, width: 8, direction: :output
        #   field :ready, direction: :input  # 1-bit input
        #
        def field(name, width: 1, direction: :output)
          _field_defs << FieldDef.new(name, width, direction)
        end

        # Get all field definitions
        def fields
          _field_defs
        end

        # Calculate total width of all fields
        def total_width
          _field_defs.sum(&:width)
        end

        # Get field names
        def field_names
          _field_defs.map(&:name)
        end

        # Get a specific field definition
        def field_def(name)
          _field_defs.find { |f| f.name == name }
        end

        # Create a flipped version of this bundle (all directions reversed)
        def flipped
          FlippedBundle.new(self)
        end
      end

      # Represents a field definition within a bundle
      FieldDef = Struct.new(:name, :width, :direction) do
        def flipped_direction
          direction == :input ? :output : :input
        end
      end

      attr_reader :name, :bundle_class, :flipped, :prefix

      def initialize(name, bundle_class, flipped: false, prefix: nil)
        @name = name
        @bundle_class = bundle_class
        @flipped = flipped
        @prefix = prefix || name.to_s
        @field_wires = {}
      end

      # Get the effective direction for a field (accounting for flipped)
      def field_direction(field_name)
        field = @bundle_class.field_def(field_name)
        return nil unless field
        @flipped ? field.flipped_direction : field.direction
      end

      # Get all fields with their effective directions
      def fields_with_directions
        @bundle_class.fields.map do |field|
          [field.name, field.width, field_direction(field.name)]
        end
      end

      # Generate flattened port names for this bundle instance
      # Returns array of [port_name, width, direction]
      def flattened_ports
        fields_with_directions.map do |name, width, direction|
          ["#{@prefix}_#{name}".to_sym, width, direction]
        end
      end

      # Access a field wire
      def [](field_name)
        @field_wires[field_name]
      end

      # Set a field wire
      def []=(field_name, wire)
        @field_wires[field_name] = wire
      end

      # Get all field wires
      def wires
        @field_wires
      end

      # Iterate over fields with their wires
      def each_field
        @bundle_class.fields.each do |field|
          yield field.name, @field_wires[field.name], field_direction(field.name)
        end
      end
    end

    # Wrapper for creating flipped bundle types
    class FlippedBundle
      attr_reader :bundle_class

      def initialize(bundle_class)
        @bundle_class = bundle_class
      end

      def fields
        @bundle_class.fields
      end

      def total_width
        @bundle_class.total_width
      end

      def field_names
        @bundle_class.field_names
      end

      def field_def(name)
        @bundle_class.field_def(name)
      end

      # When instantiated, create a flipped Bundle instance
      def new(name, prefix: nil)
        Bundle.new(name, @bundle_class, flipped: true, prefix: prefix)
      end
    end

    # Bundle instance for simulation - wraps field wires and provides access
    class BundleInstance
      attr_reader :name, :bundle_class, :flipped, :fields

      def initialize(name, bundle_class, component, flipped: false)
        @name = name
        @bundle_class = bundle_class
        @component = component
        @flipped = flipped
        @fields = {}

        # Create wires for each field
        setup_field_wires
      end

      # Access a field by name
      def method_missing(method_name, *args, &block)
        if @fields.key?(method_name)
          @fields[method_name]
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @fields.key?(method_name) || super
      end

      # Get all field wires as a hash
      def to_h
        @fields.dup
      end

      # Get field direction (accounting for flip)
      def field_direction(field_name)
        field = @bundle_class.field_def(field_name)
        return nil unless field
        @flipped ? field.flipped_direction : field.direction
      end

      # Get the wire name prefix
      def prefix
        @name.to_s
      end

      # Bulk connect to another bundle instance
      # Connects fields with matching names
      def connect_to(other_bundle)
        @fields.each do |field_name, wire|
          other_wire = other_bundle.fields[field_name]
          next unless other_wire

          my_dir = field_direction(field_name)
          other_dir = other_bundle.field_direction(field_name)

          # Connect based on direction
          if my_dir == :output && other_dir == :input
            Component.connect(wire, other_wire)
          elsif my_dir == :input && other_dir == :output
            Component.connect(other_wire, wire)
          end
        end
      end

      private

      def setup_field_wires
        @bundle_class.fields.each do |field|
          wire_name = "#{@component.name}.#{@name}_#{field.name}"
          wire = Wire.new(wire_name, width: field.width)
          @fields[field.name] = wire

          # Register with component based on effective direction
          effective_dir = field_direction(field.name)
          port_name = "#{@name}_#{field.name}".to_sym

          if effective_dir == :input
            @component.inputs[port_name] = wire
            wire.on_change { |_| @component.propagate }
          else
            @component.outputs[port_name] = wire
          end
        end
      end
    end
  end
end
