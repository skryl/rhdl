# frozen_string_literal: true

module RHDL
  module Sim
    # Tracks dependencies between components for event-driven simulation
    # Components are only re-evaluated when their inputs change
    class DependencyGraph
      def initialize
        # Map from component to set of components that depend on it
        @dependents = Hash.new { |h, k| h[k] = Set.new }
        # Map from wire to the component that drives it
        @wire_drivers = {}
        # Map from wire to components that read from it
        @wire_readers = Hash.new { |h, k| h[k] = Set.new }
        # Set of components that need re-evaluation
        @dirty_queue = Set.new
        # All registered components
        @components = []
      end

      # Register a component and build its dependencies
      def register(component)
        @components << component

        # Track which wires this component drives (its outputs)
        component.outputs.each_value do |wire|
          @wire_drivers[wire] = component
        end

        # Track which wires this component reads (its inputs)
        component.inputs.each_value do |wire|
          @wire_readers[wire].add(component)
        end
      end

      # Build the dependency graph after all components are registered
      # Must be called after all components are added
      def build
        @dependents.clear

        @components.each do |component|
          # For each output wire of this component
          component.outputs.each_value do |output_wire|
            # Find all components that read from wires connected to this output
            # by following the wire's sinks
            find_dependent_components(output_wire).each do |dependent|
              @dependents[component].add(dependent) unless dependent == component
            end
          end
        end
      end

      # Mark a component as needing re-evaluation
      def mark_dirty(component)
        @dirty_queue.add(component)
      end

      # Mark all components that depend on a wire as dirty
      def mark_wire_dirty(wire)
        @wire_readers[wire].each do |component|
          @dirty_queue.add(component)
        end
      end

      # Get and clear the set of dirty components
      def consume_dirty
        result = @dirty_queue.to_a
        @dirty_queue.clear
        result
      end

      # Check if there are dirty components
      def dirty?
        !@dirty_queue.empty?
      end

      # Mark all components as dirty (for initial propagation)
      def mark_all_dirty
        @components.each { |c| @dirty_queue.add(c) }
      end

      # Get components that depend on a given component's outputs
      def dependents_of(component)
        @dependents[component].to_a
      end

      # Clear all state
      def clear
        @dependents.clear
        @wire_drivers.clear
        @wire_readers.clear
        @dirty_queue.clear
        @components.clear
      end

      private

      # Find all components that read from a wire or any wire connected to it
      def find_dependent_components(wire)
        result = Set.new

        # Direct readers of this wire
        result.merge(@wire_readers[wire])

        # Follow wire connections (sinks)
        wire.sinks.each do |sink_wire|
          result.merge(@wire_readers[sink_wire])
          # Recursively follow connections
          result.merge(find_dependent_components(sink_wire))
        end

        result
      end
    end
  end
end
