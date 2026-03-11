# frozen_string_literal: true

require 'rhdl/support/concern'

module RHDL
  module Sim
    # Base class for all HDL components with simulation support
    #
    # Components are defined using class-level declarations:
    # - input/output: Define I/O ports
    # - wire: Define internal wires (signals)
    # - instance: Instantiate sub-components
    # - port: Connect signals to sub-component ports
    # - behavior: Define combinational logic
    #
    # @example Simple combinational component
    #   class MyAnd < Component
    #     input :a
    #     input :b
    #     output :y
    #
    #     behavior do
    #       y <= a & b
    #     end
    #   end
    #
    # @example Hierarchical component with sub-components
    #   class MyDatapath < Component
    #     input :a, width: 8
    #     input :b, width: 8
    #     output :result, width: 8
    #
    #     wire :alu_out, width: 8
    #
    #     instance :alu, ALU, width: 8
    #     instance :reg, Register, width: 8
    #
    #     port :a => [:alu, :a]
    #     port :b => [:alu, :b]
    #     port [:alu, :result] => :alu_out
    #     port :alu_out => [:reg, :d]
    #     port [:reg, :q] => :result
    #   end
    #
    class Component
      # Include DSL modules for defining component structure
      include RHDL::DSL::Ports
      include RHDL::DSL::Structure
      include RHDL::DSL::Vec
      include RHDL::DSL::Bundle
      include RHDL::DSL::Codegen

      attr_reader :name, :inputs, :outputs, :internal_signals

      class << self
        def inherited(subclass)
          super
        end

        # Check if behavior block is defined
        def behavior_defined?
          instance_variable_defined?(:@_behavior_block) && @_behavior_block
        end

        def _behavior_block
          @_behavior_block
        end

        # Define a behavior block for unified simulation and synthesis
        #
        # @example Basic combinational logic
        #   class MyAnd < Component
        #     input :a
        #     input :b
        #     output :y
        #
        #     behavior do
        #       y <= a & b
        #     end
        #   end
        #
        def behavior(**options, &block)
          @_behavior_block = BehaviorBlockDef.new(block, **options)
        end

        # Simple value object to hold behavior block definition
        class BehaviorBlockDef
          attr_reader :block, :options

          def initialize(block, **options)
            @block = block
            @options = options
          end
        end

        # Connect an output of one component to an input of another
        def connect(source_wire, dest_wire)
          source_wire.on_change { |val| dest_wire.set(val) }
          dest_wire.set(source_wire.value)
          dest_wire.driver = source_wire
          source_wire.add_sink(dest_wire)
        end
      end

      def initialize(name = nil, **kwargs)
        @name = name || self.class.name.split('::').last.downcase
        @inputs = {}
        @outputs = {}
        @internal_signals = {}
        @subcomponents = {}
        @propagation_delay = 0
        @local_dependency_graph = nil
        setup_parameters(kwargs)
        setup_ports_from_class_defs
        setup_ports
        setup_vecs_from_class_defs
        setup_bundles_from_class_defs
        setup_structure_instances
      end

      # Override in subclasses to define ports
      def setup_ports
      end

      # Build dependency graph for sub-components
      def setup_local_dependency_graph
        return if @subcomponents.empty?

        @local_dependency_graph = DependencyGraph.new

        # Register all sub-components
        @subcomponents.each_value do |component|
          @local_dependency_graph.register(component)
        end

        # Build the graph
        @local_dependency_graph.build
      end

      def input(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @inputs[name] = wire
        wire.on_change do |_|
          next if self.class.respond_to?(:sequential_defined?) && self.class.sequential_defined?
          next if @subcomponents && !@subcomponents.empty?

          propagate
        end
        wire
      end

      def output(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @outputs[name] = wire
        wire
      end

      def signal(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @internal_signals[name] = wire
        wire
      end

      def add_subcomponent(name, component)
        @subcomponents[name] = component
        component
      end

      # Main simulation method - compute outputs from inputs
      # Override in subclasses, or use a behavior block
      def propagate
        # If we have sub-components, propagate them using two-phase semantics
        if @local_dependency_graph && !@subcomponents.empty?
          propagate_subcomponents
        elsif self.class.behavior_defined?
          # No subcomponents, just execute behavior
          execute_behavior
        end
      end

      # Propagate sub-components using Verilog-style two-phase semantics
      # This ensures proper non-blocking assignment behavior for sequential components:
      # 1. Propagate combinational components until stable
      # 2. Execute parent's behavior block (sets combinational outputs like latch wires)
      # 3. All sequential components sample their inputs simultaneously
      # 4. All sequential components update their outputs
      # 5. Repeat until stable (but behavior only runs when there's a rising edge)
      def propagate_subcomponents
        max_iterations = 100

        stabilize_component_hierarchy(self, max_iterations: max_iterations)

        rising_edges = []
        collect_component_rising_edges(self, rising_edges)
        rising_edges.each(&:update_outputs)

        stabilize_component_hierarchy(self, max_iterations: max_iterations)
      end

      def sequential_component_node?(component)
        component.respond_to?(:sample_inputs) &&
          component.class.respond_to?(:sequential_defined?) &&
          component.class.sequential_defined?
      end

      def component_state_snapshot(component)
        snapshot = {}

        component.outputs.each do |name, wire|
          snapshot[[:out, name]] = wire.get
        end

        component.internal_signals.each do |name, wire|
          snapshot[[:sig, name]] = wire.get
        end

        snapshot
      end

      def stabilize_component_hierarchy(component, max_iterations:)
        iterations = 0

        while iterations < max_iterations
          old_values = component_state_snapshot(component)

          component.execute_behavior if component.class.respond_to?(:behavior_defined?) && component.class.behavior_defined?

          component.instance_variable_get(:@subcomponents)&.each_value do |sub|
            if sequential_component_node?(sub)
              # Sequential descendants hold their current state during the
              # settle phase. If they also expose combinational behavior,
              # refresh that behavior without advancing the clocked state.
              sub.execute_behavior if sub.class.respond_to?(:behavior_defined?) && sub.class.behavior_defined?
            elsif sub.instance_variable_defined?(:@subcomponents) &&
                  sub.instance_variable_get(:@subcomponents)&.any?
              stabilize_component_hierarchy(sub, max_iterations: max_iterations)
            else
              sub.propagate
            end
          end

          component.execute_behavior if component.class.respond_to?(:behavior_defined?) && component.class.behavior_defined?

          iterations += 1
          break if component_state_snapshot(component) == old_values
        end
      end

      def collect_component_rising_edges(component, rising_edges)
        component.instance_variable_get(:@subcomponents)&.each_value do |sub|
          if sequential_component_node?(sub)
            rising_edges << sub if sub.sample_inputs
          elsif sub.instance_variable_defined?(:@subcomponents) &&
                sub.instance_variable_get(:@subcomponents)&.any?
            collect_component_rising_edges(sub, rising_edges)
          end
        end
      end

      # Execute the behavior block for simulation
      def execute_behavior
        return unless self.class._behavior_block

        block = self.class._behavior_block
        ctx = BehaviorContext.new(self)
        ctx.evaluate(&block.block)
      end

      # Get input value by name
      def in_val(name)
        @inputs[name]&.get || 0
      end

      # Set output or internal signal value by name
      def out_set(name, val)
        if @outputs[name]
          @outputs[name].set(val)
        elsif @internal_signals && @internal_signals[name]
          @internal_signals[name].set(val)
        end
      end

      # Convenience method to set an input
      def set_input(name, value)
        @inputs[name]&.set(value)
      end

      # Convenience method to get an output
      def get_output(name)
        @outputs[name]&.get
      end

      def inspect
        ins = @inputs.map { |k, v| "#{k}=#{v.get}" }.join(', ')
        outs = @outputs.map { |k, v| "#{k}=#{v.get}" }.join(', ')
        "#<#{self.class.name} #{@name} in:(#{ins}) out:(#{outs})>"
      end
    end
  end
end
