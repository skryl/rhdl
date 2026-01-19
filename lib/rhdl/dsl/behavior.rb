# Behavior DSL for unified simulation and synthesis
#
# This module provides a `behavior` block that can be used for both:
# - Simulation: Execute as Ruby code to compute outputs from inputs
# - Synthesis: Build IR/AST for HDL export (Verilog)
#
# Example - Basic combinational logic:
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
# Example - ALU with case_of:
#   behavior do
#     # Local variables become wires
#     sum = local(:sum, a + b + c_in, width: 9)
#
#     # Case with multiple outputs
#     case_of op, width: 8 do |c|
#       c.when(OP_ADD) do
#         result <= sum[7..0]
#         c_out <= sum[8]
#       end
#       c.when(OP_AND) do
#         result <= a & b
#         c_out <= lit(0, width: 1)
#       end
#       c.default do
#         result <= a
#         c_out <= c_in
#       end
#     end
#   end
#
# The same behavior block is used for both simulation and synthesis.

require 'active_support/concern'
require 'set'

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
            # Handle both ascending (0..7) and descending (7..0) ranges
            high = [index.begin, index.end].max
            low = [index.begin, index.end].min
            slice_width = high - low + 1
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
          # Handle both ascending (0..7) and descending (7..0) ranges
          high = [range.begin, range.end].max
          low = [range.begin, range.end].min
          super(width: width || (high - low + 1))
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

      # Case select expression - maps selector to one of several values
      # Used for lookup-table style case statements
      class BehaviorCaseSelect < BehaviorExpr
        attr_reader :selector, :cases, :default_val

        def initialize(selector, cases, default_val: nil, width: 8)
          @selector = selector.is_a?(BehaviorExpr) ? selector : BehaviorLiteral.new(selector)
          @cases = cases.transform_values do |v|
            v.is_a?(BehaviorExpr) ? v : BehaviorLiteral.new(v, width: width)
          end
          @default_val = if default_val
            default_val.is_a?(BehaviorExpr) ? default_val : BehaviorLiteral.new(default_val, width: width)
          else
            BehaviorLiteral.new(0, width: width)
          end
          super(width: width)
        end

        def to_ir
          # Convert to nested muxes or case IR
          RHDL::Export::IR::Case.new(
            selector: @selector.to_ir,
            cases: @cases.transform_keys { |k| k.is_a?(Array) ? k : [k] }
                        .transform_values(&:to_ir),
            default: @default_val.to_ir,
            width: @width
          )
        end
      end

      # Local variable that becomes a wire in synthesis
      class BehaviorLocal < BehaviorExpr
        attr_reader :name, :expr

        def initialize(name, expr, width:)
          @name = name
          @expr = expr.is_a?(BehaviorExpr) ? expr : BehaviorLiteral.new(expr, width: width)
          super(width: width)
        end

        def to_ir
          # In synthesis, reference the wire
          RHDL::Export::IR::Signal.new(name: @name, width: @width)
        end

        # Return the assignment that creates this wire
        def wire_assign_ir
          RHDL::Export::IR::Assign.new(
            target: @name,
            expr: @expr.to_ir
          )
        end
      end

      # Case expression wrapper for synthesis
      class BehaviorCaseExpr < BehaviorExpr
        attr_reader :ir

        def initialize(ir, width:)
          @ir = ir
          super(width: width)
        end

        def to_ir
          @ir
        end
      end

      # Memory read expression for synthesis
      class BehaviorMemoryRead < BehaviorExpr
        attr_reader :memory_name, :addr

        def initialize(memory_name, addr, width:)
          @memory_name = memory_name
          @addr = addr.is_a?(BehaviorExpr) ? addr : BehaviorLiteral.new(addr)
          super(width: width)
        end

        def to_ir
          RHDL::Export::IR::MemoryRead.new(
            memory: @memory_name,
            addr: @addr.to_ir,
            width: @width
          )
        end
      end

      # Case statement builder for behavior blocks
      class BehaviorCaseBuilder
        attr_reader :selector, :branches, :default_branch

        def initialize(selector, context)
          @selector = selector
          @context = context
          @branches = {}   # { value => { output_name => expr } }
          @default_branch = {}
        end

        # Define a case branch
        def when(value, &block)
          @current_branch = {}
          branch_context = BehaviorCaseBranchContext.new(@context, @current_branch)
          branch_context.instance_eval(&block)
          @branches[value] = @current_branch
          self
        end

        # Define the default branch
        def default(&block)
          @default_branch = {}
          branch_context = BehaviorCaseBranchContext.new(@context, @default_branch)
          branch_context.instance_eval(&block)
          self
        end

        # Build case expressions for each output
        def build_assignments
          # Collect all outputs that are assigned in any branch
          all_outputs = Set.new
          @branches.each_value { |b| all_outputs.merge(b.keys) }
          all_outputs.merge(@default_branch.keys)

          # For each output, build a case expression
          all_outputs.map do |output_name|
            cases = @branches.transform_values { |b| b[output_name] }
                             .reject { |_, v| v.nil? }
            default = @default_branch[output_name]

            # Find output width
            output_proxy = @context.proxies[output_name]
            width = output_proxy&.width || 8

            # Create case IR for this output
            case_ir = build_case_ir(cases, default, width)
            BehaviorAssignment.new(output_proxy, BehaviorCaseExpr.new(case_ir, width: width))
          end
        end

        private

        def build_case_ir(cases, default, width)
          ir_cases = cases.transform_keys { |k| [k] }
                         .transform_values { |v| to_ir_expr(v, width) }

          RHDL::Export::IR::Case.new(
            selector: to_ir_expr(@selector, @selector.width),
            cases: ir_cases,
            default: default ? to_ir_expr(default, width) : nil,
            width: width
          )
        end

        def to_ir_expr(expr, width)
          return expr.to_ir if expr.respond_to?(:to_ir)
          RHDL::Export::IR::Literal.new(value: expr.to_i, width: width)
        end
      end

      # Context for inside a case branch
      class BehaviorCaseBranchContext
        def initialize(parent_context, assignments)
          @parent_context = parent_context
          @assignments = assignments
          @proxies = parent_context.proxies
        end

        def method_missing(name, *args)
          if @proxies.key?(name)
            CaseBranchProxy.new(name, @assignments, @proxies[name])
          else
            super
          end
        end

        def respond_to_missing?(name, include_private = false)
          @proxies.key?(name) || super
        end

        def lit(value, width:)
          BehaviorLiteral.new(value, width: width)
        end

        # Simple if-else for single expression
        def if_else(condition, then_expr, else_expr)
          cond = condition.is_a?(BehaviorExpr) ? condition : BehaviorLiteral.new(condition)
          then_val = then_expr.is_a?(BehaviorExpr) ? then_expr : BehaviorLiteral.new(then_expr)
          else_val = else_expr.is_a?(BehaviorExpr) ? else_expr : BehaviorLiteral.new(else_expr)
          BehaviorConditional.new(cond, when_true: then_val, when_false: else_val)
        end

        # Mux helper
        def mux(condition, when_true, when_false)
          if_else(condition, when_true, when_false)
        end
      end

      # Proxy for output in case branch that captures assignment
      class CaseBranchProxy < BehaviorSignalRef
        def initialize(name, assignments, original_proxy)
          super(name, width: original_proxy.width)
          @assignments = assignments
          @original_proxy = original_proxy
        end

        def <=(expr)
          wrapped = expr.is_a?(BehaviorExpr) ? expr : BehaviorLiteral.new(expr)
          @assignments[@name] = wrapped
        end
      end

      # If-elsif-else chain builder
      class BehaviorIfChain
        def initialize(context)
          @context = context
          @branches = []  # [ [condition, assignments], ... ]
          @else_branch = nil
        end

        def when_cond(condition, &block)
          assignments = {}
          branch_context = BehaviorCaseBranchContext.new(@context, assignments)
          branch_context.instance_eval(&block)
          cond = condition.is_a?(BehaviorExpr) ? condition : BehaviorLiteral.new(condition)
          @branches << [cond, assignments]
          self
        end

        def else_do(&block)
          @else_branch = {}
          branch_context = BehaviorCaseBranchContext.new(@context, @else_branch)
          branch_context.instance_eval(&block)
          self
        end

        # Build nested mux assignments for each output
        def build_assignments
          all_outputs = Set.new
          @branches.each { |_, assigns| all_outputs.merge(assigns.keys) }
          all_outputs.merge(@else_branch&.keys || [])

          all_outputs.map do |output_name|
            output_proxy = @context.proxies[output_name]
            width = output_proxy&.width || 8

            # Build nested mux from bottom up
            result = @else_branch&.dig(output_name) || BehaviorLiteral.new(0, width: width)

            @branches.reverse.each do |cond, assigns|
              if assigns[output_name]
                result = BehaviorConditional.new(
                  cond,
                  when_true: assigns[output_name],
                  when_false: result,
                  width: width
                )
              end
            end

            BehaviorAssignment.new(output_proxy, result)
          end
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
        attr_reader :mode, :input_values, :output_values, :assignments, :component_class, :locals, :proxies
        attr_accessor :component  # Reference to component instance for memory access

        def initialize(component_class)
          @component_class = component_class
          @component = nil
          @mode = SIM_MODE
          @input_values = {}
          @output_values = {}
          @assignments = []
          @locals = []
          @proxies = {}
        end

        def simulation_mode!
          @mode = SIM_MODE
          @assignments.clear
          @locals.clear
          self
        end

        def synthesis_mode!
          @mode = SYNTH_MODE
          @assignments.clear
          @locals.clear
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

        def record_local(local_var)
          @locals << local_var
        end

        # Create signal proxies for the behavior block
        def create_proxies
          @proxies = {}

          @component_class._ports.each do |port|
            if port.direction == :out
              @proxies[port.name] = BehaviorOutputProxy.new(port.name, width: port.width, context: self)
            else
              @proxies[port.name] = BehaviorSignalRef.new(port.name, width: port.width)
            end
          end

          @component_class._signals.each do |sig|
            @proxies[sig.name] = BehaviorOutputProxy.new(sig.name, width: sig.width, context: self)
          end

          @proxies
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

        # Evaluate for synthesis - returns hash with wires, wire_assigns, and output_assigns
        def evaluate_for_synthesis(&block)
          synthesis_mode!
          proxies = create_proxies

          # Execute the block to collect assignments
          BehaviorEvaluator.new(self, proxies).evaluate(&block)

          # Convert to IR with locals as wires
          {
            wires: @locals.map { |l| RHDL::Export::IR::Net.new(name: l.name, width: l.width) },
            wire_assigns: @locals.map(&:wire_assign_ir),
            output_assigns: @assignments.map do |assignment|
              RHDL::Export::IR::Assign.new(
                target: assignment.target.name,
                expr: resize_to_target(assignment.expr.to_ir, assignment.target.width)
              )
            end
          }
        end

        # Simple version for backwards compatibility - returns flat list of assigns
        def evaluate_for_synthesis_flat(&block)
          result = evaluate_for_synthesis(&block)
          result[:wire_assigns] + result[:output_assigns]
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
          when BehaviorLocal
            # Evaluate the underlying expression
            compute_value(expr.expr)
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
            low = [expr.range.begin, expr.range.end].min
            (base_val >> low) & mask
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
          when BehaviorCaseSelect
            selector_val = compute_value(expr.selector)
            if expr.cases.key?(selector_val)
              compute_value(expr.cases[selector_val])
            else
              compute_value(expr.default_val)
            end
          when BehaviorCaseExpr
            compute_case_value(expr.ir)
          when BehaviorMemoryRead
            # For simulation, need component reference with memory arrays
            if @component && @component.respond_to?(:mem_read)
              addr_val = compute_value(expr.addr)
              @component.mem_read(expr.memory_name, addr_val)
            else
              0  # No component reference or mem_read not available
            end
          when Integer
            expr
          else
            raise "Unknown expression type: #{expr.class}"
          end
        end

        # Compute case expression value during simulation
        def compute_case_value(case_ir)
          selector_val = compute_value_from_ir(case_ir.selector)

          case_ir.cases.each do |values, branch_ir|
            if values.include?(selector_val)
              return compute_value_from_ir(branch_ir)
            end
          end

          case_ir.default ? compute_value_from_ir(case_ir.default) : 0
        end

        # Compute IR expression value during simulation
        def compute_value_from_ir(ir)
          case ir
          when RHDL::Export::IR::Literal
            ir.value
          when RHDL::Export::IR::Signal
            @input_values[ir.name.to_sym] || @output_values[ir.name.to_sym] || 0
          when RHDL::Export::IR::BinaryOp
            left = compute_value_from_ir(ir.left)
            right = compute_value_from_ir(ir.right)
            compute_binary(ir.op, left, right, ir.width)
          when RHDL::Export::IR::UnaryOp
            operand = compute_value_from_ir(ir.operand)
            compute_unary(ir.op, operand, ir.width)
          when RHDL::Export::IR::Slice
            base = compute_value_from_ir(ir.base)
            low = [ir.range.begin, ir.range.end].min
            (base >> low) & ((1 << ir.width) - 1)
          when RHDL::Export::IR::Mux
            cond = compute_value_from_ir(ir.condition)
            if cond != 0
              compute_value_from_ir(ir.when_true)
            else
              compute_value_from_ir(ir.when_false)
            end
          when RHDL::Export::IR::Case
            compute_case_value(ir)
          when RHDL::Export::IR::Resize
            compute_value_from_ir(ir.expr)
          else
            0
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

      # Wrapper to provide proxies access to case builders
      class ContextWrapper
        attr_reader :proxies

        def initialize(context, proxies)
          @context = context
          @proxies = proxies
        end
      end

      # Evaluator that provides the DSL context for behavior blocks
      class BehaviorEvaluator
        def initialize(context, proxies)
          @context = context
          @proxies = proxies
          @locals = {}
          @context_wrapper = ContextWrapper.new(context, proxies)

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

        # Define a local variable (becomes a wire in synthesis)
        def local(name, expr, width: nil)
          wrapped = expr.is_a?(BehaviorExpr) ? expr : BehaviorLiteral.new(expr)
          w = width || wrapped.width
          local_var = BehaviorLocal.new(name, wrapped, width: w)
          @locals[name] = local_var

          # Make it available as a method
          define_singleton_method(name) { local_var }

          # Record the wire assignment
          @context.record_local(local_var)

          local_var
        end

        # Case statement with multiple outputs
        def case_of(selector, &block)
          builder = BehaviorCaseBuilder.new(selector, @context_wrapper)
          builder.instance_eval(&block)

          # Record all case assignments
          builder.build_assignments.each do |assignment|
            @context.record_assignment(assignment)
          end
        end

        # If-elsif-else chain with multiple outputs
        def if_chain(&block)
          builder = BehaviorIfChain.new(@context_wrapper)
          builder.instance_eval(&block)

          # Record all if-chain assignments
          builder.build_assignments.each do |assignment|
            @context.record_assignment(assignment)
          end
        end

        # Simple if-else for single expression
        def if_else(condition, then_expr, else_expr)
          cond = condition.is_a?(BehaviorExpr) ? condition : BehaviorLiteral.new(condition)
          then_val = then_expr.is_a?(BehaviorExpr) ? then_expr : BehaviorLiteral.new(then_expr)
          else_val = else_expr.is_a?(BehaviorExpr) ? else_expr : BehaviorLiteral.new(else_expr)
          BehaviorConditional.new(cond, when_true: then_val, when_false: else_val)
        end

        # Case select - lookup table style case statement
        # Returns a BehaviorCaseSelect expression for synthesis, or evaluates for simulation
        # Usage: case_select(op, { 0 => a + b, 1 => a - b, 2 => a & b }, default: 0)
        def case_select(selector, cases, default: 0)
          # Determine width from first case value
          first_val = cases.values.first
          width = first_val.is_a?(BehaviorExpr) ? first_val.width : 8

          BehaviorCaseSelect.new(selector, cases, default_val: default, width: width)
        end

        # Memory read expression for use in behavior blocks
        # Creates a BehaviorMemoryRead that generates IR::MemoryRead for synthesis
        # @param memory_name [Symbol] The memory array name
        # @param addr [BehaviorExpr, Integer] The address expression
        # @param width [Integer] Optional width override (default: 8)
        def mem_read_expr(memory_name, addr, width: 8)
          BehaviorMemoryRead.new(memory_name, addr, width: width)
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
          # BUT only if sequential is NOT defined (sequential handles its own propagate
          # and will call execute_behavior_for_simulation itself)
          sequential_block_defined = respond_to?(:_sequential_block) && !_sequential_block.nil?
          if ancestors.include?(RHDL::HDL::SimComponent) && !sequential_block_defined
            define_method(:propagate) do
              # Iterate until signals stabilize:
              # 1. Execute behavior FIRST (computes combinational signals from inputs)
              # 2. Propagate subcomponents (they use the fresh signal values)
              # 3. Repeat if any internal signals changed
              max_iterations = 10
              iterations = 0

              while iterations < max_iterations
                # Save current internal signal values
                old_values = {}
                @internal_signals&.each do |name, wire|
                  old_values[name] = wire.get
                end

                # Execute behavior block FIRST (computes combinational signals)
                self.class.execute_behavior_for_simulation(self)

                # Propagate subcomponents (use freshly computed signals)
                if @local_dependency_graph && !@subcomponents.empty?
                  propagate_subcomponents
                end

                # Check if any internal signals changed
                changed = false
                @internal_signals&.each do |name, wire|
                  if wire.get != old_values[name]
                    changed = true
                    break
                  end
                end

                iterations += 1
                break unless changed
              end
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
          # Also include current output values (for combinational outputs derived from sequential state)
          component.outputs.each do |name, wire|
            input_values[name] ||= wire.get
          end
          # Include internal signals (wires) that connect subcomponents
          if component.respond_to?(:internal_signals) && component.internal_signals
            component.internal_signals.each do |name, wire|
              input_values[name] ||= wire.get
            end
          end

          # Create context and evaluate
          context = BehaviorContext.new(self)
          context.component = component  # Pass component for memory access
          outputs = context.evaluate_for_simulation(input_values, &@_behavior_block.block)

          # Set output and internal signal values
          outputs.each do |name, value|
            if component.outputs[name]
              component.out_set(name, value)
            elsif component.internal_signals&.key?(name)
              component.internal_signals[name].set(value)
            end
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
