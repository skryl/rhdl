# frozen_string_literal: true

# Structure DSL for HDL Components
#
# This module provides class-level DSL methods for defining component structure:
# - instance: Instantiate sub-components
# - port: Connect signals to sub-component ports
#
# @example Hierarchical component
#   class MyDatapath < Component
#     include RHDL::DSL::Structure
#
#     input :a, width: 8
#     output :result, width: 8
#
#     instance :alu, ALU, width: 8
#     instance :reg, Register, width: 8
#
#     port :a => [:alu, :a]
#     port [:alu, :result] => [:reg, :d]
#     port [:reg, :q] => :result
#   end

require 'rhdl/support/concern'
require 'rhdl/support/inflections'

module RHDL
  module DSL
    module Structure
      extend RHDL::Support::Concern

      class_methods do
        def inherited(subclass)
          super
          # Copy definitions to subclass
          subclass.instance_variable_set(:@_instance_defs, (@_instance_defs || []).dup)
          subclass.instance_variable_set(:@_connection_defs, (@_connection_defs || []).dup)
        end

        def _instance_defs
          @_instance_defs ||= []
        end

        def _connection_defs
          @_connection_defs ||= []
        end

        # Check if structure is defined (has instances)
        def structure_defined?
          !_instance_defs.empty?
        end

        # Define a sub-component instance (class-level)
        #
        # @param name [Symbol] Instance name
        # @param component_class [Class] Component class to instantiate
        # @param params [Hash] Parameters to pass to the component
        #
        # @example
        #   class MyDatapath < Component
        #     input :a, width: 8
        #     output :result, width: 8
        #
        #     instance :alu, ALU, width: 8
        #     instance :reg, Register, width: 8
        #
        #     port :a => [:alu, :a]
        #     port [:alu, :result] => [:reg, :d]
        #     port [:reg, :q] => :result
        #   end
        #
        def instance(name, component_class, **params)
          module_name = if component_class.respond_to?(:verilog_module_name)
                          component_class.verilog_module_name
                        else
                          component_class.name.split('::').last.underscore
                        end
          _instance_defs << {
            name: name,
            component_class: component_class,
            module_name: module_name,
            parameters: params,
            connections: {}
          }
        end

        # Define connections between signals and instance ports (class-level)
        #
        # @param mappings [Hash] Signal to port mappings
        #   Formats:
        #   - port :clk => [:pc, :clk]              # Signal to instance port
        #   - port :clk => [[:pc, :clk], [:acc, :clk]]  # Signal to multiple ports
        #   - port [:alu, :result] => :result      # Instance output to signal
        #   - port [:alu, :result] => [:reg, :d]   # Instance to instance
        #
        def port(mappings)
          mappings.each do |source, dest|
            _connection_defs << { source: source, dest: dest }

            if dest.is_a?(Array) && dest.first.is_a?(Array)
              # Multiple destinations: port :clk => [[:pc, :clk], [:acc, :clk]]
              dest.each { |d| add_port_connection(source, d) }
            elsif dest.is_a?(Array) && dest.length == 2
              # Single destination: port :clk => [:pc, :clk]
              add_port_connection(source, dest)
            elsif source.is_a?(Array) && source.length == 2
              # Instance output to signal: port [:alu, :result] => :result
              add_output_connection(source, dest)
            end
          end
        end

        private

        def add_port_connection(signal, dest)
          inst_name, port_name = dest
          inst_def = _instance_defs.find { |i| i[:name] == inst_name }
          return unless inst_def

          inst_def[:connections][port_name] = signal
        end

        def add_output_connection(source, signal)
          inst_name, port_name = source
          inst_def = _instance_defs.find { |i| i[:name] == inst_name }
          return unless inst_def

          inst_def[:connections][port_name] = signal
        end
      end

      # Instance methods

      # Automatically instantiate and wire sub-components from structure DSL
      def setup_structure_instances
        return if self.class._instance_defs.empty?

        # Instantiate all sub-components
        self.class._instance_defs.each do |inst_def|
          component_class = inst_def[:component_class]
          inst_name = inst_def[:name]
          params = inst_def[:parameters] || {}

          # Create the sub-component instance
          component = component_class.new("#{@name}.#{inst_name}", **params)
          @subcomponents[inst_name] = component

          # Make it accessible as an instance variable for convenience
          instance_variable_set(:"@#{inst_name}", component)
        end

        # Wire connections based on _connection_defs
        self.class._connection_defs.each do |conn_def|
          source = conn_def[:source]
          dest = conn_def[:dest]
          wire_connection(source, dest)
        end

        # Build local dependency graph for optimized propagation
        setup_local_dependency_graph
      end

      # Wire a connection between source and destination
      # Handles fan-out where dest can be an array of destinations
      def wire_connection(source, dest)
        source_wire = resolve_wire(source)
        return unless source_wire

        # Check if dest is a fan-out (array of arrays)
        # e.g., [[:registers, :clk], [:pc, :clk], ...]
        if dest.is_a?(Array) && dest.first.is_a?(Array)
          # Fan-out: connect source to each destination
          dest.each do |single_dest|
            dest_wire = resolve_wire(single_dest)
            self.class.connect(source_wire, dest_wire) if dest_wire
          end
        else
          # Single destination
          dest_wire = resolve_wire(dest)
          self.class.connect(source_wire, dest_wire) if dest_wire
        end
      end

      # Resolve a wire reference to an actual Wire object
      def resolve_wire(ref)
        if ref.is_a?(Symbol)
          # Reference to this component's port or signal
          @inputs[ref] || @outputs[ref] || @internal_signals[ref]
        elsif ref.is_a?(Array) && ref.length == 2
          # Reference to sub-component port: [:inst_name, :port_name]
          inst_name, port_name = ref
          component = @subcomponents[inst_name]
          return nil unless component

          component.inputs[port_name] || component.outputs[port_name]
        end
      end
    end
  end
end
