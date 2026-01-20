# State Machine DSL for synthesizable sequential controllers
#
# This module provides DSL constructs for finite state machines that can be
# synthesized to Verilog.
#
# Example - Simple FSM:
#   class TrafficLight < RHDL::Sim::SequentialComponent
#     include RHDL::DSL::StateMachine
#
#     input :clk
#     input :rst
#     input :sensor
#     output :red
#     output :yellow
#     output :green
#     output :state, width: 2
#
#     state_machine clock: :clk, reset: :rst do
#       state :RED, value: 0 do
#         output red: 1, yellow: 0, green: 0
#         transition to: :GREEN, when_cond: :sensor
#       end
#
#       state :YELLOW, value: 1 do
#         output red: 0, yellow: 1, green: 0
#         transition to: :RED, after: 3
#       end
#
#       state :GREEN, value: 2 do
#         output red: 0, yellow: 0, green: 1
#         transition to: :YELLOW, when_cond: proc { in_val(:sensor) == 0 }
#       end
#
#       initial_state :RED
#       output_state :state
#     end
#   end

require 'active_support/concern'

module RHDL
  module DSL
    module StateMachine
      extend ActiveSupport::Concern

      # State definition
      class StateDef
        attr_reader :name, :value, :outputs, :transitions

        def initialize(name, value:)
          @name = name
          @value = value
          @outputs = {}       # { output_name => value }
          @transitions = []   # [ TransitionDef, ... ]
        end

        def output(**outputs)
          @outputs.merge!(outputs)
        end

        def transition(to:, when_cond: nil, after: nil)
          @transitions << TransitionDef.new(
            target: to,
            condition: when_cond,
            delay: after
          )
        end
      end

      # Transition definition
      class TransitionDef
        attr_reader :target, :condition, :delay

        def initialize(target:, condition: nil, delay: nil)
          @target = target
          @condition = condition
          @delay = delay
        end
      end

      # State machine builder
      class StateMachineBuilder
        attr_reader :clock, :reset, :states, :initial, :state_output_name, :state_width

        def initialize(clock:, reset: nil)
          @clock = clock
          @reset = reset
          @states = {}
          @initial = nil
          @state_output_name = nil
          @state_width = nil
        end

        def state(name, value:, &block)
          state_def = StateDef.new(name, value: value)
          state_def.instance_eval(&block) if block_given?
          @states[name] = state_def
        end

        def initial_state(name)
          @initial = name
        end

        def output_state(name, width: nil)
          @state_output_name = name
          @state_width = width if width
        end

        # Calculate required state width
        def calculated_state_width
          return @state_width if @state_width
          max_value = @states.values.map(&:value).max || 0
          max_value == 0 ? 1 : Math.log2(max_value + 1).ceil
        end

        # Generate IR for synthesis
        def to_ir
          width = calculated_state_width

          # Build next-state logic as nested mux
          next_state_cases = @states.transform_values do |state_def|
            if state_def.transitions.empty?
              # Stay in current state
              RHDL::Export::IR::Literal.new(value: state_def.value, width: width)
            else
              # Build transition logic
              build_transition_ir(state_def.transitions, width)
            end
          end

          # Output assignments per state
          output_cases = {}
          first_state = @states.values.first
          return {} unless first_state

          first_state.outputs.keys.each do |output_name|
            output_cases[output_name] = @states.transform_values do |state_def|
              value = state_def.outputs[output_name] || 0
              RHDL::Export::IR::Literal.new(value: value, width: 1)
            end
          end

          {
            state_width: width,
            initial_value: @states[@initial]&.value || 0,
            next_state: next_state_cases,
            outputs: output_cases
          }
        end

        private

        def build_transition_ir(transitions, width)
          # Start with staying in current state
          result = nil

          transitions.reverse.each do |trans|
            target_value = @states[trans.target]&.value || 0
            target_ir = RHDL::Export::IR::Literal.new(value: target_value, width: width)

            if trans.condition
              # Conditional transition
              if result.nil?
                result = target_ir
              else
                cond_ir = if trans.condition.is_a?(Symbol)
                           RHDL::Export::IR::Signal.new(name: trans.condition, width: 1)
                         else
                           # For procs, we'll handle in simulation
                           RHDL::Export::IR::Literal.new(value: 1, width: 1)
                         end
                result = RHDL::Export::IR::Mux.new(
                  condition: cond_ir,
                  when_true: target_ir,
                  when_false: result,
                  width: width
                )
              end
            else
              # Unconditional transition (or delayed)
              result = target_ir
            end
          end

          result
        end
      end

      class_methods do
        # Define a state machine
        #
        # @param clock [Symbol] Clock signal
        # @param reset [Symbol, nil] Optional reset signal
        # @yield [StateMachineBuilder] Block to configure the FSM
        #
        def state_machine(clock:, reset: nil, &block)
          @_state_machine = StateMachineBuilder.new(clock: clock, reset: reset)
          @_state_machine.instance_eval(&block)

          # Define propagate for simulation
          define_fsm_propagate
        end

        def _state_machine
          @_state_machine
        end

        def state_machine_defined?
          !@_state_machine.nil?
        end

        private

        def define_fsm_propagate
          fsm = @_state_machine

          define_method(:propagate) do
            @_fsm_state ||= fsm.states[fsm.initial]&.value || 0
            @_prev_clk ||= 0
            @_delay_counters ||= {}

            clk_val = in_val(fsm.clock)
            rising = (@_prev_clk == 0 && clk_val == 1)
            @_prev_clk = clk_val

            # Handle reset
            if fsm.reset && in_val(fsm.reset) == 1
              @_fsm_state = fsm.states[fsm.initial]&.value || 0
              @_delay_counters = {}
            elsif rising
              # Find current state
              current_state_def = fsm.states.values.find { |s| s.value == @_fsm_state }

              if current_state_def
                # Evaluate transitions
                current_state_def.transitions.each do |trans|
                  should_transition = false

                  if trans.delay
                    # Delay-based transition
                    @_delay_counters[current_state_def.name] ||= 0
                    @_delay_counters[current_state_def.name] += 1
                    if @_delay_counters[current_state_def.name] >= trans.delay
                      should_transition = true
                      @_delay_counters[current_state_def.name] = 0
                    end
                  elsif trans.condition
                    # Conditional transition
                    if trans.condition.is_a?(Symbol)
                      should_transition = in_val(trans.condition) == 1
                    elsif trans.condition.is_a?(Proc)
                      should_transition = instance_eval(&trans.condition)
                    end
                  else
                    # Unconditional
                    should_transition = true
                  end

                  if should_transition
                    target_state = fsm.states[trans.target]
                    @_fsm_state = target_state.value if target_state
                    @_delay_counters.delete(current_state_def.name)
                    break
                  end
                end
              end
            end

            # Output current state value
            if fsm.state_output_name
              out_set(fsm.state_output_name, @_fsm_state)
            end

            # Set outputs based on current state
            current_state_def = fsm.states.values.find { |s| s.value == @_fsm_state }
            if current_state_def
              current_state_def.outputs.each do |output_name, value|
                out_set(output_name, value)
              end
            end
          end
        end
      end
    end
  end
end
