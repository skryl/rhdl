# frozen_string_literal: true

require 'active_support/concern'

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
        wire.on_change { |_| propagate }
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
        # Separate combinational and sequential components
        combinational = []
        sequential = []

        @subcomponents.each_value do |comp|
          if comp.is_a?(SequentialComponent)
            sequential << comp
          else
            combinational << comp
          end
        end

        # Check if any sequential component will see a rising edge
        # This determines if behavior should run to set up latch wires
        # We only want to run behavior ONCE when there's a rising edge
        has_pending_edge = sequential.any? do |comp|
          clk_wire = comp.inputs[:clk]
          prev_clk = comp.instance_variable_get(:@prev_clk) || 0
          clk_wire && prev_clk == 0 && clk_wire.get == 1
        end

        # Track whether we've already executed behavior while clk=1
        # This prevents multiple propagate calls from overwriting latch wire values
        # Once we've run behavior on a rising edge, don't run again until clk goes low
        @_last_behavior_clk ||= nil
        current_clk = @inputs[:clk]&.get

        # If clk went 0->1 (rising edge), we need to run behavior
        # If clk is still 1 and we already ran behavior, don't run again
        # If clk went back to 0, reset tracking
        if current_clk == 0
          @_behavior_ran_this_high = false
        end
        behavior_already_ran = current_clk == 1 && @_behavior_ran_this_high

        max_iterations = 100
        iterations = 0

        loop do
          changed = false

          # Phase 1: Propagate all combinational components until stable
          comb_iterations = 0
          loop do
            comb_changed = false

            combinational.each do |component|
              old_outputs = component.outputs.transform_values(&:get)
              component.propagate

              component.outputs.each do |_port_name, wire|
                if wire.get != old_outputs[_port_name]
                  comb_changed = true
                  changed = true
                end
              end
            end

            comb_iterations += 1
            break unless comb_changed && comb_iterations < max_iterations
          end

          # Phase 2: Execute parent's behavior block
          # Only run on first iteration when there's a pending rising edge
          # This ensures latch wires are set based on values BEFORE registers update
          # On subsequent propagates (same clock value), behavior doesn't run
          # to prevent overwriting latch wires with post-update values
          should_run_behavior = self.class.behavior_defined? &&
                                !behavior_already_ran &&
                                (has_pending_edge ? iterations == 0 : true)
          if should_run_behavior
            execute_behavior
            @_behavior_ran_this_high = true if current_clk == 1

            # Phase 2b: Re-propagate combinational components after behavior
            # This is critical for components like hazard_unit that depend on
            # behavior outputs (e.g., take_branch). Without this, hazard_unit
            # would see stale values and generate wrong flush signals.
            comb_iterations = 0
            loop do
              comb_changed = false

              combinational.each do |component|
                old_outputs = component.outputs.transform_values(&:get)
                component.propagate

                component.outputs.each do |port_name, wire|
                  if wire.get != old_outputs[port_name]
                    comb_changed = true
                    changed = true
                  end
                end
              end

              comb_iterations += 1
              break unless comb_changed && comb_iterations < max_iterations
            end
          end

          # Phase 3: All sequential components SAMPLE inputs (don't update outputs yet)
          rising_edges = []
          # DEBUG: Show phase start
          puts "  [PHASE 3] iter=#{iterations} Sequential SAMPLE start" if ENV['DEBUG_PHASES']
          sequential.each do |component|
            if component.respond_to?(:sample_inputs)
              puts "    [PHASE 3] Calling sample_inputs on #{component.name}" if ENV['DEBUG_PHASES']
              is_rising = component.sample_inputs
              rising_edges << component if is_rising
            end
          end
          puts "  [PHASE 3] iter=#{iterations} done, rising_edges=#{rising_edges.map(&:name)}" if ENV['DEBUG_PHASES']

          # Phase 4: All sequential components UPDATE outputs (for those with rising edge)
          puts "  [PHASE 4] iter=#{iterations} Sequential UPDATE start" if ENV['DEBUG_PHASES']
          rising_edges.each do |component|
            puts "    [PHASE 4] Calling update_outputs on #{component.name}" if ENV['DEBUG_PHASES']
            old_outputs = component.outputs.transform_values(&:get)
            component.update_outputs

            component.outputs.each do |_port_name, wire|
              if wire.get != old_outputs[_port_name]
                changed = true
              end
            end
          end

          # For sequential components that didn't have a rising edge, we still need
          # to give them a chance to run combinational logic (behavior blocks).
          # BUT we must NOT call their propagate() method because that would call
          # sample_inputs and update_outputs together, violating two-phase semantics.
          # Instead, just call execute_behavior if they have one.
          (sequential - rising_edges).each do |component|
            if component.class.respond_to?(:behavior_defined?) && component.class.behavior_defined?
              puts "    [NO-EDGE] Executing behavior for #{component.name}" if ENV['DEBUG_PHASES']
              old_outputs = component.outputs.transform_values(&:get)
              component.execute_behavior if component.respond_to?(:execute_behavior)

              component.outputs.each do |_port_name, wire|
                if wire.get != old_outputs[_port_name]
                  changed = true
                end
              end
            end
          end

          iterations += 1
          break unless changed && iterations < max_iterations
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
