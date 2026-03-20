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

require 'rhdl/support/concern'

module RHDL
  module DSL
    module Sequential
      extend RHDL::Support::Concern

      class << self
        def active_low_reset_name?(name)
          reset_name = name.to_s
          reset_name.end_with?('_n', '_l')
        end
      end

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
          RHDL::Codegen::CIRCT::IR::Case.new(
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
          result = @else_branch&.to_ir || RHDL::Codegen::CIRCT::IR::Literal.new(value: 0, width: @width)
          @conditions.reverse.zip(@branches.reverse).each do |cond, branch|
            result = RHDL::Codegen::CIRCT::IR::Mux.new(
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

      SequentialAssign = Struct.new(:target, :expr, keyword_init: true)
      SequentialIR = Struct.new(:clock, :reset, :reset_values, :assignments, keyword_init: true)

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
        # IMPORTANT: Uses non-blocking assignment semantics where all RHS values
        # are computed using OLD state values before any updates occur.
        def evaluate_for_simulation(input_values, &block)
          simulation_mode!
          @input_values = input_values.transform_keys(&:to_sym)
          @output_values = {}

          proxies = create_proxies

          # Use SequentialEvaluator which has local() and case_of support
          SequentialEvaluator.new(self, proxies).evaluate(&block)

          # Non-blocking assignment semantics: compute ALL values first using
          # only input_values (old state), then store all results at once.
          # This prevents earlier assignments from affecting later ones.
          computed_values = {}
          @assignments.each do |assignment|
            target_name = assignment.target.name
            # compute_value will only see @input_values since @output_values is empty
            value = compute_value(assignment.expr)
            computed_values[target_name] = mask_value(value, assignment.target.width)
          end

          # Now store all computed values
          @output_values = computed_values
          @output_values
        end

        # For synthesis: generate always @(posedge clk) block IR
        def to_sequential_ir(&block)
          synthesis_mode!
          proxies = create_proxies
          evaluator = SequentialEvaluator.new(self, proxies)
          evaluator.evaluate(&block)
          ir_cache = {}

          SequentialIR.new(
            clock: @clock,
            reset: @reset,
            reset_values: @reset_values,
            assignments: @assignments.map do |a|
              SequentialAssign.new(
                target: a.target.name,
                expr: a.expr.to_ir(ir_cache)
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
          wrapped = Behavior::BehaviorResize.new(wrapped, width: width) if width && wrapped.width != width
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
          @_sequential_blocks ||= []
          @_sequential_blocks << SequentialBlock.new(
            clock: clock,
            reset: reset,
            reset_values: reset_values,
            &block
          )

          # Store reset values at class level for state initialization
          @_reset_values = _reset_values.merge(
            reset_values.each_with_object({}) { |(name, value), acc| acc[name.to_sym] = value }
          )

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
            blocks = self.class._sequential_blocks
            return false if blocks.empty?

            @_prev_clk_by_name ||= {}
            rising_by_clock = {}
            blocks.map(&:clock).compact.map(&:to_sym).uniq.each do |clock_name|
              clk_val = in_val(clock_name)
              prev_clk = @_prev_clk_by_name.fetch(clock_name, 0)
              rising_by_clock[clock_name] = (prev_clk == 0 && clk_val == 1)
              @_prev_clk_by_name[clock_name] = clk_val
            end

            @_pending_sequential_blocks = []
            @_pending_rising_clocks = {}

            blocks.each do |seq_block|
              needs_reset =
                if seq_block.reset
                  reset_value = in_val(seq_block.reset)
                  if RHDL::DSL::Sequential.active_low_reset_name?(seq_block.reset)
                    reset_value == 0
                  else
                    reset_value == 1
                  end
                else
                  false
                end

              clock_name = seq_block.clock.to_sym
              rising = rising_by_clock.fetch(clock_name, false)
              next unless needs_reset || rising

              @_pending_sequential_blocks << {
                block: seq_block,
                reset: needs_reset
              }
              @_pending_rising_clocks[clock_name] = true if rising
            end

            # On any rising edge, ONLY sample input values. Next state will be
            # computed in update_outputs using these sampled values.
            if @_pending_rising_clocks.any?
              # Sample ALL input wire values NOW, before any register updates
              @_sampled_inputs = {}
              @inputs.each do |name, wire|
                @_sampled_inputs[name] = wire.get
              end
              # Also sample internal signals (wires from subcomponents, etc.)
              @internal_signals.each do |name, wire|
                @_sampled_inputs[name] = wire.get
              end
            else
              @_sampled_inputs = nil
            end

            @_pending_sequential_blocks.any?
          end

          # Helper to set state value on outputs OR internal signals
          define_method(:_set_state_value) do |name, value|
            if @outputs[name]
              @outputs[name].set(value)
            elsif @internal_signals[name]
              @internal_signals[name].set(value)
            end
          end

          # Override update_outputs for two-phase propagation
          # Called AFTER all sequential components have sampled inputs
          define_method(:update_outputs) do
            _init_seq_state

            pending_blocks = Array(@_pending_sequential_blocks)
            if pending_blocks.any?
              # Process memory sync writes FIRST (using current register values)
              if respond_to?(:process_memory_sync_writes) && @_pending_rising_clocks&.any?
                process_memory_sync_writes(@_pending_rising_clocks)
              end

              next_state_updates = {}
              pending_blocks.each do |entry|
                seq_block = entry.fetch(:block)
                block_updates =
                  if entry[:reset]
                    seq_block.reset_values.each_with_object({}) do |(name, value), acc|
                      acc[name.to_sym] = value
                    end
                  else
                    self.class.evaluate_sequential_blocks_with_inputs(
                      component: self,
                      input_values: @_sampled_inputs || {},
                      sequential_blocks: [seq_block]
                    )
                  end

                block_updates.each do |name, value|
                  next_state_updates[name.to_sym] = value
                end
              end

              next_state_updates.each do |name, value|
                @_seq_state[name.to_sym] = value
              end
            end

            @_pending_sequential_blocks = []
            @_pending_rising_clocks = {}
            @_sampled_inputs = nil

            # Output state values (to both outputs and internal signals)
            @_seq_state.each do |name, value|
              _set_state_value(name, value)
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

        def _sequential_blocks
          @_sequential_blocks || []
        end

        def _sequential_block
          _sequential_blocks.last
        end

        def sequential_defined?
          _sequential_blocks.any?
        end

        # Execute sequential block for simulation
        def execute_sequential_for_simulation(component)
          return unless sequential_defined?

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
          return unless sequential_defined?

          execute_sequential_with_inputs(component, sampled_inputs)
        end

        # Internal: execute sequential block with given input values
        def execute_sequential_with_inputs(component, input_values)
          return unless sequential_defined?

          outputs = evaluate_sequential_blocks_with_inputs(
            component: component,
            input_values: input_values,
            sequential_blocks: _sequential_blocks
          )

          outputs.each do |name, value|
            component.instance_variable_get(:@_seq_state)[name.to_sym] = value
          end
          outputs
        end

        def evaluate_sequential_blocks_with_inputs(component:, input_values:, sequential_blocks:)
          return {} if Array(sequential_blocks).empty?

          Array(sequential_blocks).each_with_object({}) do |sequential_block, merged_outputs|
            block_outputs = evaluate_single_sequential_block_with_inputs(
              component: component,
              input_values: input_values,
              sequential_block: sequential_block
            )
            block_outputs.each do |name, value|
              merged_outputs[name.to_sym] = value
            end
          end
        end

        def evaluate_single_sequential_block_with_inputs(component:, input_values:, sequential_block:)
          # Also include current state values (for register feedback)
          component._init_seq_state
          eval_inputs = input_values.each_with_object({}) { |(name, value), acc| acc[name.to_sym] = value }
          component.instance_variable_get(:@_seq_state).each do |name, value|
            eval_inputs[name.to_sym] = value
          end

          context = SequentialContext.new(
            self,
            clock: sequential_block.clock,
            reset: sequential_block.reset,
            reset_values: sequential_block.reset_values
          )
          # Set component reference for memory access in mem_read_expr
          context.component = component
          context.evaluate_for_simulation(eval_inputs, &sequential_block.block)
        end

        # Execute sequential block for synthesis - returns IR
        def execute_sequential_for_synthesis
          return nil unless sequential_defined?

          _sequential_blocks.map do |sequential_block|
            context = SequentialContext.new(
              self,
              clock: sequential_block.clock,
              reset: sequential_block.reset,
              reset_values: sequential_block.reset_values
            )
            context.to_sequential_ir(&sequential_block.block)
          end
        end
      end
    end
  end
end
