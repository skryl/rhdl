# frozen_string_literal: true

# HDL Sequential Component Base Class
# Base class for sequential (clocked) components
#
# Implements Verilog-style non-blocking assignment semantics:
# - On rising edge, all registers SAMPLE inputs first
# - Then all registers UPDATE outputs
# This ensures all registers see the "old" values, not values updated by other registers

module RHDL
  module Sim
    class SequentialComponent < Component
      # Include sequential codegen for to_ir override
      include RHDL::DSL::SequentialCodegen

      def initialize(name = nil, **kwargs)
        @prev_clk = 0
        @clk_sampled = false  # Track if we've sampled clock this cycle
        @state ||= 0  # Don't overwrite subclass initialization
        @sampled_inputs = {}  # For two-phase non-blocking semantics
        @pending_outputs = {}  # Outputs to be applied in update phase
        super
      end

      # Override input to not auto-propagate on any input changes
      # Sequential components should be propagated manually as part of clock cycles
      # This avoids race conditions where inputs change in wrong order during propagation
      def input(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @inputs[name] = wire
        # No on_change callbacks - sequential propagation must be explicit
        wire
      end

      def rising_edge?
        clk = in_val(:clk)
        result = @prev_clk == 0 && clk == 1
        # Update prev_clk after checking - this ensures the edge is detected once
        @prev_clk = clk
        result
      end

      def falling_edge?
        clk = in_val(:clk)
        result = @prev_clk == 1 && clk == 0
        @prev_clk = clk
        result
      end

      # Call this to sample the current clock value without detecting an edge
      # Useful when you need to update prev_clk outside of edge detection
      def sample_clock
        @prev_clk = in_val(:clk)
      end

      # Phase 1 of non-blocking assignment: Sample all inputs
      # Call this on all sequential components BEFORE any update their outputs
      def sample_inputs
        clk = in_val(:clk)
        is_rising = @prev_clk == 0 && clk == 1

        if is_rising
          # Sample all input values - these are the values we'll use
          @sampled_inputs = {}
          @inputs.each do |name, wire|
            @sampled_inputs[name] = wire.get
          end
        end

        @prev_clk = clk
        is_rising
      end

      # Phase 2 of non-blocking assignment: Update outputs
      # Call this on all sequential components AFTER all have sampled inputs
      def update_outputs
        # Subclasses should override to apply pending outputs
        @pending_outputs.each do |name, value|
          out_set(name, value)
        end
        @pending_outputs = {}
      end

      # Get a sampled input value (for use in sequential logic during update phase)
      def sampled_val(name)
        @sampled_inputs[name] || in_val(name)
      end

      # Schedule an output update (non-blocking assignment)
      def schedule_output(name, value)
        @pending_outputs[name] = value
      end

      class << self
        # Check if sequential block is defined
        def sequential_defined?
          respond_to?(:_sequential_block) && _sequential_block
        end
      end
    end
  end
end
