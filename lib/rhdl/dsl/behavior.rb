# Behavior DSL for unified simulation and synthesis
#
# This module provides a `behavior` block that can be used for both:
# - Simulation: Execute as Ruby code to compute outputs from inputs
# - Synthesis: Build IR/AST for HDL export (VHDL/Verilog)
#
# Example:
#   class MyAnd
#     include RHDL::DSL
#     include RHDL::DSL::Behavior
#
#     input :a
#     input :b
#     output :y
#
#     behavior do
#       y <= a & b
#     end
#   end
#
# The same behavior block is used for both simulation and synthesis.

require 'active_support/concern'

module RHDL
  module DSL
    module Behavior
      extend ActiveSupport::Concern

      # Execution modes
      SIM_MODE = :simulation
      SYNTH_MODE = :synthesis

      # Base class for behavior expressions in synthesis mode
      class BehaviorExpr
        attr_reader :width

        def initialize(width: 1)
          @width = width
        end

        # Bitwise operators
        def &(other)
          BehaviorBinaryOp.new(:&, self, wrap(other), width: result_width(other))
        end

        def |(other)
          BehaviorBinaryOp.new(:|, self, wrap(other), width: result_width(other))
        end

        def ^(other)
          BehaviorBinaryOp.new(:^, self, wrap(other), width: result_width(other))
        end

        def ~
          BehaviorUnaryOp.new(:~, self, width: @width)
        end

        # Arithmetic operators
        def +(other)
          BehaviorBinaryOp.new(:+, self, wrap(other), width: result_width(other) + 1)
        end

        def -(other)
          BehaviorBinaryOp.new(:-, self, wrap(other), width: result_width(other))
        end

        def *(other)
          other_width = other.is_a?(BehaviorExpr) ? other.width : bit_width(other)
          BehaviorBinaryOp.new(:*, self, wrap(other), width: @width + other_width)
        end

        def /(other)
          BehaviorBinaryOp.new(:/, self, wrap(other), width: @width)
        end

        def %(other)
          BehaviorBinaryOp.new(:%, self, wrap(other), width: @width)
        end

        # Shift operators
        def <<(amount)
          BehaviorBinaryOp.new(:<<, self, wrap(amount), width: @width)
        end

        def >>(amount)
          BehaviorBinaryOp.new(:>>, self, wrap(amount), width: @width)
        end

        # Comparison operators (result is 1 bit)
        def ==(other)
          BehaviorBinaryOp.new(:==, self, wrap(other), width: 1)
        end

        def !=(other)
          BehaviorBinaryOp.new(:!=, self, wrap(other), width: 1)
        end

        def <(other)
          BehaviorBinaryOp.new(:<, self, wrap(other), width: 1)
        end

        def >(other)
          BehaviorBinaryOp.new(:>, self, wrap(other), width: 1)
        end

        def <=(other)
          BehaviorBinaryOp.new(:<=, self, wrap(other), width: 1)
        end

        def >=(other)
          BehaviorBinaryOp.new(:>=, self, wrap(other), width: 1)
        end

        # Bit selection and slicing
        def [](index)
          if index.is_a?(Range)
            slice_width = index.max - index.min + 1
            BehaviorSlice.new(self, index, width: slice_width)
          else
            BehaviorBitSelect.new(self, index)
          end
        end

        # Concatenation
        def concat(*others)
          parts = [self] + others.map { |o| wrap(o) }
          total_width = parts.sum(&:width)
          BehaviorConcat.new(parts, width: total_width)
        end

        # Replication
        def replicate(times)
          BehaviorReplicate.new(self, times, width: @width * times)
        end

        # Conditional (ternary) - enables mux-like expressions
        def when_true(condition)
          BehaviorConditional.new(condition, when_true: self)
        end

        protected

        def wrap(other)
          return other if other.is_a?(BehaviorExpr)
          BehaviorLiteral.new(other, width: bit_width(other))
        end

        def result_width(other)
          other_width = other.is_a?(BehaviorExpr) ? other.width : bit_width(other)
          [@width, other_width].max
        end

        def bit_width(value)
          return 1 if value == 0 || value == 1
          value.is_a?(Integer) ? [value.bit_length, 1].max : 1
        end
      end

      # Literal value in synthesis mode
      class BehaviorLiteral < BehaviorExpr
        attr_reader :value

        def initialize(value, width: nil)
          @value = value
          super(width: width || bit_width(value))
        end

        def to_ir
          RHDL::Export::IR::Literal.new(value: @value, width: @width)
        end

        def to_dsl_expr
          @value
        end

        private

        def bit_width(value)
          return 1 if value == 0 || value == 1
          value.is_a?(Integer) ? [value.bit_length, 1].max : 1
        end
      end

      # Signal reference in synthesis mode
      class BehaviorSignalRef < BehaviorExpr
        attr_reader :name

        def initialize(name, width: 1)
          @name = name
          super(width: width)
        end

        def to_ir
          RHDL::Export::IR::Signal.new(name: @name, width: @width)
        end

        def to_dsl_expr
          RHDL::DSL::SignalRef.new(@name, width: @width)
        end
      end

      # Binary operation in synthesis mode
      class BehaviorBinaryOp < BehaviorExpr
        attr_reader :op, :left, :right

        def initialize(op, left, right, width: 1)
          @op = op
          @left = left
          @right = right
          super(width: width)
        end

        def to_ir
          RHDL::Export::IR::BinaryOp.new(
            op: @op,
            left: @left.to_ir,
            right: resize_ir(@right.to_ir, @left.width),
            width: @width
          )
        end

        def to_dsl_expr
          RHDL::DSL::BinaryOp.new(@op, @left.to_dsl_expr, @right.to_dsl_expr)
        end

        private

        def resize_ir(expr, target_width)
          return expr if expr.width == target_width
          RHDL::Export::IR::Resize.new(expr: expr, width: target_width)
        end
      end

      # Unary operation in synthesis mode
      class BehaviorUnaryOp < BehaviorExpr
        attr_reader :op, :operand

        def initialize(op, operand, width: 1)
          @op = op
          @operand = operand
          super(width: width)
        end

        def to_ir
          RHDL::Export::IR::UnaryOp.new(op: @op, operand: @operand.to_ir, width: @width)
        end

        def to_dsl_expr
          RHDL::DSL::UnaryOp.new(@op, @operand.to_dsl_expr)
        end
      end

      # Bit selection in synthesis mode
      class BehaviorBitSelect < BehaviorExpr
        attr_reader :base, :index

        def initialize(base, index)
          @base = base
          @index = index
          super(width: 1)
        end

        def to_ir
          RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @index..@index, width: 1)
        end

        def to_dsl_expr
          RHDL::DSL::BitSelect.new(@base.to_dsl_expr, @index)
        end
      end

      # Bit slice in synthesis mode
      class BehaviorSlice < BehaviorExpr
        attr_reader :base, :range

        def initialize(base, range, width: nil)
          @base = base
          @range = range
          super(width: width || (range.max - range.min + 1))
        end

        def to_ir
          RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @range, width: @width)
        end

        def to_dsl_expr
          RHDL::DSL::BitSlice.new(@base.to_dsl_expr, @range)
        end
      end

      # Concatenation in synthesis mode
      class BehaviorConcat < BehaviorExpr
        attr_reader :parts

        def initialize(parts, width: nil)
          @parts = parts
          super(width: width || parts.sum(&:width))
        end

        def to_ir
          RHDL::Export::IR::Concat.new(parts: @parts.map(&:to_ir), width: @width)
        end

        def to_dsl_expr
          RHDL::DSL::Concatenation.new(@parts.map(&:to_dsl_expr))
        end
      end

      # Replication in synthesis mode
      class BehaviorReplicate < BehaviorExpr
        attr_reader :expr, :times

        def initialize(expr, times, width: nil)
          @expr = expr
          @times = times
          super(width: width || (expr.width * times))
        end

        def to_ir
          parts = Array.new(@times) { @expr.to_ir }
          RHDL::Export::IR::Concat.new(parts: parts, width: @width)
        end

        def to_dsl_expr
          RHDL::DSL::Replication.new(@expr.to_dsl_expr, @times)
        end
      end

      # Conditional/Mux expression in synthesis mode
      class BehaviorConditional < BehaviorExpr
        attr_reader :condition, :when_true_expr, :when_false_expr

        def initialize(condition, when_true: nil, when_false: nil, width: nil)
          @condition = condition.is_a?(BehaviorExpr) ? condition : BehaviorLiteral.new(condition)
          @when_true_expr = when_true
          @when_false_expr = when_false
          super(width: width || when_true&.width || 1)
        end

        def otherwise(value)
          @when_false_expr = value.is_a?(BehaviorExpr) ? value : BehaviorLiteral.new(value)
          @width = [@when_true_expr&.width || 1, @when_false_expr.width].max
          self
        end

        def to_ir
          RHDL::Export::IR::Mux.new(
            condition: @condition.to_ir,
            when_true: @when_true_expr.to_ir,
            when_false: @when_false_expr&.to_ir || RHDL::Export::IR::Literal.new(value: 0, width: @width),
            width: @width
          )
        end
      end

      # Assignment collector for behavior blocks
      class BehaviorAssignment
        attr_reader :target, :expr

        def initialize(target, expr)
          @target = target
          @expr = expr
        end
      end

      # Proxy for output signals that captures assignments
      class BehaviorOutputProxy < BehaviorSignalRef
        attr_reader :assignments

        def initialize(name, width: 1, context: nil)
          super(name, width: width)
          @context = context
          @assignments = []
        end

        # The <= operator for assignments
        def <=(expr)
          assignment = BehaviorAssignment.new(self, expr.is_a?(BehaviorExpr) ? expr : BehaviorLiteral.new(expr))
          @context&.record_assignment(assignment)
          assignment
        end
      end

      # Context for evaluating behavior blocks
      class BehaviorContext
        attr_reader :mode, :input_values, :output_values, :assignments, :component_class

        def initialize(component_class)
          @component_class = component_class
          @mode = SIM_MODE
          @input_values = {}
          @output_values = {}
          @assignments = []
          @signal_proxies = {}
        end

        def simulation_mode!
          @mode = SIM_MODE
          @assignments.clear
          self
        end

        def synthesis_mode!
          @mode = SYNTH_MODE
          @assignments.clear
          self
        end

        def simulation?
          @mode == SIM_MODE
        end

        def synthesis?
          @mode == SYNTH_MODE
        end

        def record_assignment(assignment)
          @assignments << assignment
        end

        # Create signal proxies for the behavior block
        def create_proxies
          @signal_proxies = {}

          @component_class._ports.each do |port|
            if port.direction == :out
              @signal_proxies[port.name] = BehaviorOutputProxy.new(port.name, width: port.width, context: self)
            else
              @signal_proxies[port.name] = BehaviorSignalRef.new(port.name, width: port.width)
            end
          end

          @component_class._signals.each do |sig|
            @signal_proxies[sig.name] = BehaviorOutputProxy.new(sig.name, width: sig.width, context: self)
          end

          @signal_proxies
        end

        # Evaluate for simulation - returns hash of output values
        def evaluate_for_simulation(input_values, &block)
          simulation_mode!
          @input_values = input_values.transform_keys(&:to_sym)
          @output_values = {}

          proxies = create_proxies

          # Execute the block
          BehaviorEvaluator.new(self, proxies).evaluate(&block)

          # Process assignments and compute output values
          @assignments.each do |assignment|
            target_name = assignment.target.name
            value = compute_value(assignment.expr)
            @output_values[target_name] = mask_value(value, assignment.target.width)
          end

          @output_values
        end

        # Evaluate for synthesis - returns list of IR assignments
        def evaluate_for_synthesis(&block)
          synthesis_mode!
          proxies = create_proxies

          # Execute the block to collect assignments
          BehaviorEvaluator.new(self, proxies).evaluate(&block)

          # Convert assignments to IR
          @assignments.map do |assignment|
            RHDL::Export::IR::Assign.new(
              target: assignment.target.name,
              expr: resize_to_target(assignment.expr.to_ir, assignment.target.width)
            )
          end
        end

        private

        def resize_to_target(ir_expr, target_width)
          return ir_expr if ir_expr.width == target_width
          RHDL::Export::IR::Resize.new(expr: ir_expr, width: target_width)
        end

        # Compute the actual value of an expression during simulation
        def compute_value(expr)
          case expr
          when BehaviorLiteral
            expr.value
          when BehaviorSignalRef
            @input_values[expr.name] || @output_values[expr.name] || 0
          when BehaviorBinaryOp
            compute_binary(expr.op, compute_value(expr.left), compute_value(expr.right), expr.width)
          when BehaviorUnaryOp
            compute_unary(expr.op, compute_value(expr.operand), expr.width)
          when BehaviorBitSelect
            (compute_value(expr.base) >> expr.index) & 1
          when BehaviorSlice
            base_val = compute_value(expr.base)
            mask = (1 << expr.width) - 1
            (base_val >> expr.range.min) & mask
          when BehaviorConcat
            result = 0
            offset = 0
            expr.parts.reverse.each do |part|
              result |= (compute_value(part) << offset)
              offset += part.width
            end
            result
          when BehaviorReplicate
            base_val = compute_value(expr.expr)
            result = 0
            offset = 0
            expr.times.times do
              result |= (base_val << offset)
              offset += expr.expr.width
            end
            result
          when BehaviorConditional
            cond_val = compute_value(expr.condition)
            if cond_val != 0
              compute_value(expr.when_true_expr)
            else
              expr.when_false_expr ? compute_value(expr.when_false_expr) : 0
            end
          when Integer
            expr
          else
            raise "Unknown expression type: #{expr.class}"
          end
        end

        def compute_binary(op, left, right, width)
          mask = (1 << width) - 1
          result = case op
          when :& then left & right
          when :| then left | right
          when :^ then left ^ right
          when :+ then left + right
          when :- then left - right
          when :* then left * right
          when :/ then right != 0 ? left / right : 0
          when :% then right != 0 ? left % right : 0
          when :<< then left << right
          when :>> then left >> right
          when :== then (left == right) ? 1 : 0
          when :!= then (left != right) ? 1 : 0
          when :< then (left < right) ? 1 : 0
          when :> then (left > right) ? 1 : 0
          when :<= then (left <= right) ? 1 : 0
          when :>= then (left >= right) ? 1 : 0
          else
            raise "Unknown binary operator: #{op}"
          end
          result & mask
        end

        def compute_unary(op, operand, width)
          mask = (1 << width) - 1
          case op
          when :~ then (~operand) & mask
          when :- then (-operand) & mask
          else
            raise "Unknown unary operator: #{op}"
          end
        end

        def mask_value(value, width)
          value & ((1 << width) - 1)
        end
      end

      # Evaluator that provides the DSL context for behavior blocks
      class BehaviorEvaluator
        def initialize(context, proxies)
          @context = context
          @proxies = proxies

          # Define methods for each signal
          @proxies.each do |name, proxy|
            define_singleton_method(name) { proxy }
          end
        end

        def evaluate(&block)
          instance_eval(&block)
        end

        # Helper for conditional expressions
        def mux(condition, when_true, when_false)
          cond = condition.is_a?(BehaviorExpr) ? condition : BehaviorLiteral.new(condition)
          true_expr = when_true.is_a?(BehaviorExpr) ? when_true : BehaviorLiteral.new(when_true)
          false_expr = when_false.is_a?(BehaviorExpr) ? when_false : BehaviorLiteral.new(when_false)
          BehaviorConditional.new(cond, when_true: true_expr, when_false: false_expr)
        end

        # Helper for creating literal values with explicit width
        def lit(value, width:)
          BehaviorLiteral.new(value, width: width)
        end

        # Helper for concatenation
        def cat(*signals)
          parts = signals.map { |s| s.is_a?(BehaviorExpr) ? s : BehaviorLiteral.new(s) }
          BehaviorConcat.new(parts)
        end
      end

      # Behavior block definition stored at class level
      class BehaviorBlock
        attr_reader :block, :options

        def initialize(block, **options)
          @block = block
          @options = options
        end
      end

      class_methods do
        # Define a behavior block for the component
        #
        # @example Basic combinational logic
        #   behavior do
        #     y <= a & b
        #   end
        #
        # @example Multiple outputs
        #   behavior do
        #     sum <= a + b
        #     carry <= (a & b) | (a & cin) | (b & cin)
        #   end
        #
        def behavior(**options, &block)
          @_behavior_block = BehaviorBlock.new(block, **options)

          # Define propagate method if this is a SimComponent
          if ancestors.include?(RHDL::HDL::SimComponent)
            define_method(:propagate) do
              self.class.execute_behavior_for_simulation(self)
            end
          end
        end

        def _behavior_block
          @_behavior_block
        end

        # Check if a behavior block is defined
        def behavior_defined?
          !@_behavior_block.nil?
        end

        # Execute behavior block for simulation
        def execute_behavior_for_simulation(component)
          return unless @_behavior_block

          # Gather input values
          input_values = {}
          component.inputs.each do |name, wire|
            input_values[name] = wire.get
          end

          # Create context and evaluate
          context = BehaviorContext.new(self)
          outputs = context.evaluate_for_simulation(input_values, &@_behavior_block.block)

          # Set output values
          outputs.each do |name, value|
            component.out_set(name, value)
          end
        end

        # Execute behavior block for synthesis - returns IR assigns
        def execute_behavior_for_synthesis
          return [] unless @_behavior_block

          context = BehaviorContext.new(self)
          context.evaluate_for_synthesis(&@_behavior_block.block)
        end

        # Get the behavior block as DSL expressions (for existing export pipeline)
        def behavior_to_dsl_assignments
          return [] unless @_behavior_block

          context = BehaviorContext.new(self)
          context.synthesis_mode!
          proxies = context.create_proxies

          # Execute the block to collect assignments
          evaluator = BehaviorEvaluator.new(context, proxies)
          evaluator.evaluate(&@_behavior_block.block)

          # Convert to DSL Assignment objects
          context.assignments.map do |assignment|
            RHDL::DSL::Assignment.new(
              assignment.target.to_dsl_expr,
              assignment.expr.to_dsl_expr
            )
          end
        end
      end

      # Instance methods
      included do
        # Override propagate if behavior is defined
        def propagate
          if self.class.behavior_defined?
            self.class.execute_behavior_for_simulation(self)
          else
            super if defined?(super)
          end
        end
      end
    end
  end
end
