# frozen_string_literal: true

module RHDL
  module Sim
    # Simulation scheduler for event-driven simulation
    class Simulator
      attr_reader :time, :components, :dependency_graph

      def initialize
        @time = 0
        @components = []
        @clocks = []
        @event_queue = []
        @dependency_graph = DependencyGraph.new
        @initialized = false
      end

      def add_component(component)
        @components << component
        @dependency_graph.register(component)
        # Attach dependency graph to all wires for change notification
        attach_graph_to_wires(component)
        component
      end

      def add_clock(clock)
        @clocks << clock
        clock
      end

      # Initialize the dependency graph (call after all components are added)
      def initialize_graph
        return if @initialized

        @dependency_graph.build
        @dependency_graph.mark_all_dirty
        @initialized = true
      end

      # Run simulation for n clock cycles
      def run(cycles)
        initialize_graph
        cycles.times do
          @clocks.each(&:tick)
          propagate_all
          @clocks.each(&:tick)
          propagate_all
          @time += 1
        end
      end

      # Single step - propagate all signals
      def step
        initialize_graph
        propagate_all
      end

      def propagate_all
        # Use event-driven propagation if graph is initialized
        if @initialized
          propagate_event_driven
        else
          propagate_polling
        end
      end

      private

      # Attach dependency graph to all wires in a component
      def attach_graph_to_wires(component)
        component.inputs.each_value { |wire| wire.dependency_graph = @dependency_graph }
        component.outputs.each_value { |wire| wire.dependency_graph = @dependency_graph }
        component.internal_signals.each_value { |wire| wire.dependency_graph = @dependency_graph }
      end

      # Event-driven propagation - only evaluate dirty components
      def propagate_event_driven
        max_iterations = 1000
        iterations = 0

        while @dependency_graph.dirty? && iterations < max_iterations
          # Get components that need evaluation
          dirty_components = @dependency_graph.consume_dirty

          dirty_components.each do |component|
            # Capture old output values
            old_outputs = component.outputs.transform_values(&:get)

            # Propagate
            component.propagate

            # Check if outputs changed and mark dependents
            component.outputs.each do |name, wire|
              if wire.get != old_outputs[name]
                # Mark components that depend on this output as dirty
                @dependency_graph.dependents_of(component).each do |dep|
                  @dependency_graph.mark_dirty(dep)
                end
              end
            end
          end

          iterations += 1
        end

        if iterations >= max_iterations
          warn "Simulation did not converge after #{max_iterations} iterations"
        end
      end

      # Original polling-based propagation (fallback)
      def propagate_polling
        max_iterations = 1000
        iterations = 0
        begin
          changed = false
          @components.each do |c|
            old_outputs = c.outputs.transform_values { |w| w.get }
            c.propagate
            new_outputs = c.outputs.transform_values { |w| w.get }
            changed ||= old_outputs != new_outputs
          end
          iterations += 1
        end while changed && iterations < max_iterations

        if iterations >= max_iterations
          warn "Simulation did not converge after #{max_iterations} iterations"
        end
      end

      public

      def reset
        @time = 0
        @clocks.each { |c| c.set(0) }
        @dependency_graph.mark_all_dirty if @initialized
      end
    end
  end
end
