# Sequential Behavior DSL for synthesis
#
# This module extends the behavior DSL to support sequential logic patterns
# that can be synthesized to Verilog with proper clock domain handling.
#
# Example - D Flip-Flop:
#   class DFF < SequentialComponent
#     input :clk
#     input :rst
#     input :d
#     output :q
#
#     sequential clock: :clk, reset: :rst do
#       q <= d
#     end
#   end
#
# Example - Counter with case:
#   class Counter < SequentialComponent
#     input :clk
#     input :rst
#     input :mode, width: 2
#     output :count, width: 8
#
#     sequential clock: :clk, reset: :rst, reset_value: { count: 0 } do
#       case_of mode,
#         0 => count,           # Hold
#         1 => count + 1,       # Count up
#         2 => count - 1,       # Count down
#         default: 0            # Reset
#     end
#   end
#
# Example - ALU with case:
#   class ALU < Component
#     input :a, width: 8
#     input :b, width: 8
#     input :op, width: 4
#     output :result, width: 8
#
#     behavior do
#       result <= case_of(op,
#         0x00 => a + b,
#         0x01 => a - b,
#         0x02 => a & b,
#         0x03 => a | b,
#         0x04 => a ^ b,
#         0x05 => a << 1,
#         0x06 => a >> 1,
#         default: a
#       )
#     end
#   end

require 'active_support/concern'

module RHDL
  module DSL
    module Sequential
      extend ActiveSupport::Concern

      # Case expression for synthesis - maps to Verilog case
      class BehaviorCase < Behavior::BehaviorExpr
        attr_reader :selector, :cases, :default_case

        def initialize(selector, cases, default_case: nil, width: 8)
          @selector = selector.is_a?(Behavior::BehaviorExpr) ? selector : Behavior::BehaviorLiteral.new(selector)
          @cases = cases.transform_values do |v|
            v.is_a?(Behavior::BehaviorExpr) ? v : Behavior::BehaviorLiteral.new(v, width: width)
          end
          @default_case = if default_case
            default_case.is_a?(Behavior::BehaviorExpr) ? default_case : Behavior::BehaviorLiteral.new(default_case, width: width)
          end
          super(width: width)
        end

        def to_ir
          RHDL::Export::IR::Case.new(
            selector: @selector.to_ir,
            cases: @cases.transform_keys { |k| k.is_a?(Array) ? k : [k] }
                        .transform_values(&:to_ir),
            default: @default_case&.to_ir,
            width: @width
          )
        end
      end

      # If-elsif-else chain for synthesis
      class BehaviorIfChain < Behavior::BehaviorExpr
        attr_reader :conditions, :branches, :else_branch

        def initialize(width: 8)
          @conditions = []
          @branches = []
          @else_branch = nil
          super(width: width)
        end

        def when_cond(condition, value)
          cond = condition.is_a?(Behavior::BehaviorExpr) ? condition : Behavior::BehaviorLiteral.new(condition)
          val = value.is_a?(Behavior::BehaviorExpr) ? value : Behavior::BehaviorLiteral.new(value, width: @width)
          @conditions << cond
          @branches << val
          self
        end

        def else_val(value)
          @else_branch = value.is_a?(Behavior::BehaviorExpr) ? value : Behavior::BehaviorLiteral.new(value, width: @width)
          self
        end

        def to_ir
          # Convert to nested muxes for IR
          result = @else_branch&.to_ir || RHDL::Export::IR::Literal.new(value: 0, width: @width)
          @conditions.reverse.zip(@branches.reverse).each do |cond, branch|
            result = RHDL::Export::IR::Mux.new(
              condition: cond.to_ir,
              when_true: branch.to_ir,
              when_false: result,
              width: @width
            )
          end
          result
        end
      end

      # Sequential block definition
      class SequentialBlock
        attr_reader :clock, :reset, :reset_values, :block

        def initialize(clock:, reset: nil, reset_values: {}, &block)
          @clock = clock
          @reset = reset
          @reset_values = reset_values
          @block = block
        end
      end

      # Context for sequential evaluation
      class SequentialContext < Behavior::BehaviorContext
        attr_reader :registers

        def initialize(component_class, clock:, reset: nil, reset_values: {})
          super(component_class)
          @clock = clock
          @reset = reset
          @reset_values = reset_values
          @registers = {}
        end

        # Override to use SequentialEvaluator instead of BehaviorEvaluator
        def evaluate_for_simulation(input_values, &block)
          simulation_mode!
          @input_values = input_values.transform_keys(&:to_sym)
          @output_values = {}

          proxies = create_proxies

          # Use SequentialEvaluator which has local() and case_of support
          SequentialEvaluator.new(self, proxies).evaluate(&block)

          # Process assignments and compute output values
          @assignments.each do |assignment|
            target_name = assignment.target.name
            value = compute_value(assignment.expr)
            @output_values[target_name] = mask_value(value, assignment.target.width)
          end

          @output_values
        end

        # For synthesis: generate always @(posedge clk) block IR
        def to_sequential_ir(&block)
          synthesis_mode!
          proxies = create_proxies
          evaluator = SequentialEvaluator.new(self, proxies)
          evaluator.evaluate(&block)

          RHDL::Export::IR::Sequential.new(
            clock: @clock,
            reset: @reset,
            reset_values: @reset_values,
            assignments: @assignments.map do |a|
              RHDL::Export::IR::Assign.new(
                target: a.target.name,
                expr: a.expr.to_ir
              )
            end
          )
        end
      end

      # Evaluator with case_of support
      class SequentialEvaluator < Behavior::BehaviorEvaluator
        # Case expression helper
        # @example
        #   result <= case_of(op,
        #     0 => a + b,
        #     1 => a - b,
        #     default: a
        #   )
        def case_of(selector, cases_hash)
          # Extract default if present
          default_val = cases_hash.delete(:default)

          # Determine width from first case value
          first_val = cases_hash.values.first
          width = first_val.is_a?(Behavior::BehaviorExpr) ? first_val.width : 8

          BehaviorCase.new(selector, cases_hash, default_case: default_val, width: width)
        end

        # If-chain helper for complex conditionals
        # @example
        #   result <= if_chain(width: 8)
        #     .when_cond(a == 0, lit(0, width: 8))
        #     .when_cond(a < 10, a + 1)
        #     .else_val(a - 1)
        def if_chain(width: 8)
          BehaviorIfChain.new(width: width)
        end

        # Local variable for intermediate computation
        # In synthesis, these become wires
        # @param name [Symbol] The local variable name
        # @param expr [BehaviorExpr, Integer] The expression to assign
        # @param width [Integer] Optional width override
        def local(name, expr, width: nil)
          wrapped = if expr.is_a?(Behavior::BehaviorExpr)
            expr
          else
            Behavior::BehaviorLiteral.new(expr, width: width || 8)
          end
          # Store as a signal proxy for later reference
          @local_vars ||= {}
          @local_vars[name] = wrapped
          define_singleton_method(name) { @local_vars[name] }
          wrapped
        end
      end

      class_methods do
        # Define a sequential (clocked) behavior block
        #
        # @param clock [Symbol] The clock signal name
        # @param reset [Symbol, nil] Optional async reset signal
        # @param reset_values [Hash] Values to set on reset
        #
        # @example Simple register
        #   sequential clock: :clk do
        #     q <= d
        #   end
        #
        # @example With async reset
        #   sequential clock: :clk, reset: :rst, reset_values: { q: 0 } do
        #     q <= d
        #   end
        #
        def sequential(clock:, reset: nil, reset_values: {}, &block)
          @_sequential_block = SequentialBlock.new(
            clock: clock,
            reset: reset,
            reset_values: reset_values,
            &block
          )

          # Store reset values at class level for state initialization
          @_reset_values = reset_values

          # Define state initialization method
          define_method(:_init_seq_state) do
            return if @_seq_state
            @_seq_state = {}
            self.class._reset_values.each do |name, value|
              @_seq_state[name] = value
            end
          end

          # Two-phase non-blocking assignment semantics (Verilog-style):
          # - sample_inputs: Called on ALL sequential components first, samples inputs
          # - update_outputs: Called on ALL sequential components after, updates outputs
          # This ensures all registers see the "old" values, not values updated by other registers

          # Override sample_inputs for two-phase propagation
          # Returns true if this is a rising edge (outputs will need updating)
          # IMPORTANT: This ONLY samples inputs. Next state is computed in update phase.
          define_method(:sample_inputs) do
            _init_seq_state

            # Check for rising edge
            clk_val = in_val(clock)
            @_prev_clk ||= 0
            rising = (@_prev_clk == 0 && clk_val == 1)
            @_prev_clk = clk_val

            # Handle reset - sample but mark as needing reset
            @_needs_reset = reset && in_val(reset) == 1

            if @_needs_reset
              return true
            end

            # On rising edge, ONLY sample input values
            # Next state will be computed in update_outputs using these sampled values
            if rising
              # Sample ALL input wire values NOW, before any register updates
              @_sampled_inputs = {}
              @inputs.each do |name, wire|
                @_sampled_inputs[name] = wire.get
              end
            end

            rising
          end

          # Override update_outputs for two-phase propagation
          # Called AFTER all sequential components have sampled inputs
          define_method(:update_outputs) do
            _init_seq_state

            if @_needs_reset
              # Apply reset values
              reset_values.each do |name, value|
                @_seq_state[name] = value
                out_set(name, value)
              end
              @_needs_reset = false
              # Execute combinational parts
              process_memory_async_reads if respond_to?(:process_memory_async_reads)
              process_memory_lookup_tables if respond_to?(:process_memory_lookup_tables)
              self.class.execute_behavior_for_simulation(self) if self.class.respond_to?(:behavior_defined?) && self.class.behavior_defined?
              return
            end

            # If we have sampled inputs (from rising edge), compute next state NOW
            # using the sampled values (not current wire values)
            if @_sampled_inputs && !@_sampled_inputs.empty?
              # Process memory sync writes FIRST (using current register values)
              if respond_to?(:process_memory_sync_writes)
                rising_clocks = { clock => true }
                process_memory_sync_writes(rising_clocks)
              end

              # Compute next state using SAMPLED input values
              self.class.execute_sequential_with_sampled_inputs(self, @_sampled_inputs)
              @_sampled_inputs = nil  # Clear sampled inputs
            end

            # Output state values
            @_seq_state.each do |name, value|
              out_set(name, value)
            end

            # Process memory async reads (combinational, uses current values)
            process_memory_async_reads if respond_to?(:process_memory_async_reads)
            process_memory_lookup_tables if respond_to?(:process_memory_lookup_tables)

            # Execute behavior block (combinational logic based on current state)
            self.class.execute_behavior_for_simulation(self) if self.class.respond_to?(:behavior_defined?) && self.class.behavior_defined?
          end

          # Define propagate method - used when not doing two-phase propagation
          # (for backwards compatibility and when component is not a subcomponent)
          define_method(:propagate) do
            _init_seq_state

            # Propagate subcomponents first (if any)
            if @local_dependency_graph && !@subcomponents.empty?
              propagate_subcomponents
            end

            # Single-phase: sample and update together
            sample_inputs
            update_outputs
          end

          # Define read_reg for accessing internal state
          define_method(:read_reg) do |name|
            _init_seq_state
            @_seq_state[name]
          end

          # Define write_reg for modifying internal state (for test setup)
          define_method(:write_reg) do |name, value|
            _init_seq_state
            @_seq_state[name] = value
            out_set(name, value)
          end
        end

        def _reset_values
          @_reset_values || {}
        end

        def _sequential_block
          @_sequential_block
        end

        def sequential_defined?
          !@_sequential_block.nil?
        end

        # Execute sequential block for simulation
        def execute_sequential_for_simulation(component)
          return unless @_sequential_block

          # Gather input values from current wire values
          input_values = {}
          component.inputs.each do |name, wire|
            input_values[name] = wire.get
          end

          execute_sequential_with_inputs(component, input_values)
        end

        # Execute sequential block with pre-sampled input values
        # This is used for two-phase propagation where inputs were sampled earlier
        def execute_sequential_with_sampled_inputs(component, sampled_inputs)
          return unless @_sequential_block

          execute_sequential_with_inputs(component, sampled_inputs)
        end

        # Internal: execute sequential block with given input values
        def execute_sequential_with_inputs(component, input_values)
          return unless @_sequential_block

          # Also include current state values (for register feedback)
          component._init_seq_state
          component.instance_variable_get(:@_seq_state).each do |name, value|
            input_values[name] = value
          end

          context = SequentialContext.new(
            self,
            clock: @_sequential_block.clock,
            reset: @_sequential_block.reset,
            reset_values: @_sequential_block.reset_values
          )
          outputs = context.evaluate_for_simulation(input_values, &@_sequential_block.block)

          # Store outputs in component's internal state
          # DO NOT call out_set here - outputs are set at start of NEXT propagate cycle
          # This mimics how a real register updates on clock edge but outputs on next cycle
          outputs.each do |name, value|
            component.instance_variable_get(:@_seq_state)[name] = value
          end
        end

        # Execute sequential block for synthesis - returns IR
        def execute_sequential_for_synthesis
          return nil unless @_sequential_block

          context = SequentialContext.new(
            self,
            clock: @_sequential_block.clock,
            reset: @_sequential_block.reset,
            reset_values: @_sequential_block.reset_values
          )
          context.to_sequential_ir(&@_sequential_block.block)
        end
      end
    end
  end
end
