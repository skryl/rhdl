# frozen_string_literal: true

module RHDL
  module HDL
    # Simulation scheduler for event-driven simulation
    class Simulator
      attr_reader :time, :components

      def initialize
        @time = 0
        @components = []
        @clocks = []
        @event_queue = []
      end

      def add_component(component)
        @components << component
        component
      end

      def add_clock(clock)
        @clocks << clock
        clock
      end

      # Run simulation for n clock cycles
      def run(cycles)
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
        propagate_all
      end

      def propagate_all
        # Keep propagating until stable
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

      def reset
        @time = 0
        @clocks.each { |c| c.set(0) }
      end
    end
  end
end
