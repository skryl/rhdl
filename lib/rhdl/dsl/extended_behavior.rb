# Extended Behavior DSL for complex combinational logic
#
# This module extends the behavior DSL to handle patterns like:
# - Local variables (intermediate wires)
# - Case statements with multiple outputs
# - Nested conditionals
# - Helper functions that get inlined
#
# The key insight is that ALL Ruby propagate logic has a Verilog equivalent:
# - Local variables → wire declarations
# - case/when → case statement or nested ternary
# - if/else → nested mux or always @* procedural block
# - Method calls → inlined combinational logic
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

require 'active_support/concern'

module RHDL
  module DSL
    module ExtendedBehavior
      extend ActiveSupport::Concern

      # Local variable that becomes a wire in synthesis
      class BehaviorLocal < Behavior::BehaviorExpr
        attr_reader :name, :expr

        def initialize(name, expr, width:)
          @name = name
          @expr = expr.is_a?(Behavior::BehaviorExpr) ? expr : Behavior::BehaviorLiteral.new(expr, width: width)
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

      # Case statement builder for behavior blocks
      class BehaviorCaseBuilder
        attr_reader :selector, :branches, :default_branch, :outputs

        def initialize(selector, context, outputs: [])
          @selector = selector
          @context = context
          @branches = {}   # { value => { output_name => expr } }
          @default_branch = {}
          @outputs = outputs
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
            Behavior::BehaviorAssignment.new(output_proxy, BehaviorCaseExpr.new(case_ir, width: width))
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
          Behavior::BehaviorLiteral.new(value, width: width)
        end

        # Simple if-else for single expression
        def if_else(condition, then_expr, else_expr)
          cond = condition.is_a?(Behavior::BehaviorExpr) ? condition : Behavior::BehaviorLiteral.new(condition)
          then_val = then_expr.is_a?(Behavior::BehaviorExpr) ? then_expr : Behavior::BehaviorLiteral.new(then_expr)
          else_val = else_expr.is_a?(Behavior::BehaviorExpr) ? else_expr : Behavior::BehaviorLiteral.new(else_expr)
          Behavior::BehaviorConditional.new(cond, when_true: then_val, when_false: else_val)
        end

        # Mux helper
        def mux(condition, when_true, when_false)
          if_else(condition, when_true, when_false)
        end
      end

      # Proxy for output in case branch that captures assignment
      # Extends BehaviorSignalRef to work in expressions
      class CaseBranchProxy < Behavior::BehaviorSignalRef
        def initialize(name, assignments, original_proxy)
          super(name, width: original_proxy.width)
          @assignments = assignments
          @original_proxy = original_proxy
        end

        def <=(expr)
          wrapped = expr.is_a?(Behavior::BehaviorExpr) ? expr : Behavior::BehaviorLiteral.new(expr)
          @assignments[@name] = wrapped
        end
      end

      # Case expression wrapper
      class BehaviorCaseExpr < Behavior::BehaviorExpr
        attr_reader :ir

        def initialize(ir, width:)
          @ir = ir
          super(width: width)
        end

        def to_ir
          @ir
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
          cond = condition.is_a?(Behavior::BehaviorExpr) ? condition : Behavior::BehaviorLiteral.new(condition)
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
            result = @else_branch&.dig(output_name) || Behavior::BehaviorLiteral.new(0, width: width)

            @branches.reverse.each do |cond, assigns|
              if assigns[output_name]
                result = Behavior::BehaviorConditional.new(
                  cond,
                  when_true: assigns[output_name],
                  when_false: result,
                  width: width
                )
              end
            end

            Behavior::BehaviorAssignment.new(output_proxy, result)
          end
        end
      end

      # Extended evaluator with local, case_of, and if_chain
      class ExtendedBehaviorEvaluator < Behavior::BehaviorEvaluator
        def initialize(context, proxies)
          super
          @locals = {}
          @context_wrapper = ContextWrapper.new(context, proxies)
        end

        # Define a local variable (becomes a wire in synthesis)
        def local(name, expr, width: nil)
          wrapped = expr.is_a?(Behavior::BehaviorExpr) ? expr : Behavior::BehaviorLiteral.new(expr)
          w = width || wrapped.width
          local_var = BehaviorLocal.new(name, wrapped, width: w)
          @locals[name] = local_var

          # Make it available as a method
          define_singleton_method(name) { local_var }

          # Record the wire assignment
          @context.record_local(local_var) if @context.respond_to?(:record_local)

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
          cond = condition.is_a?(Behavior::BehaviorExpr) ? condition : Behavior::BehaviorLiteral.new(condition)
          then_val = then_expr.is_a?(Behavior::BehaviorExpr) ? then_expr : Behavior::BehaviorLiteral.new(then_expr)
          else_val = else_expr.is_a?(Behavior::BehaviorExpr) ? else_expr : Behavior::BehaviorLiteral.new(else_expr)
          Behavior::BehaviorConditional.new(cond, when_true: then_val, when_false: else_val)
        end

        # Inline helper - executes a block and returns the result expression
        # Used to inline helper method logic
        def inline(&block)
          instance_eval(&block)
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

      # Extended context that tracks locals
      class ExtendedBehaviorContext < Behavior::BehaviorContext
        attr_reader :locals

        def initialize(component_class)
          super
          @locals = []
        end

        def record_local(local_var)
          @locals << local_var
        end

        # Create extended proxies
        def create_extended_proxies
          proxies = create_proxies
          proxies
        end

        # Evaluate with extended features
        def evaluate_extended(&block)
          proxies = create_extended_proxies
          ExtendedBehaviorEvaluator.new(self, proxies).evaluate(&block)
        end

        # Convert to IR with locals as wires
        def to_ir_with_locals
          {
            wires: @locals.map { |l| RHDL::Export::IR::Net.new(name: l.name, width: l.width) },
            wire_assigns: @locals.map(&:wire_assign_ir),
            output_assigns: @assignments.map do |a|
              RHDL::Export::IR::Assign.new(
                target: a.target.name,
                expr: a.expr.to_ir
              )
            end
          }
        end
      end

      class_methods do
        # Extended behavior block with local variables and case support
        def extended_behavior(&block)
          @_extended_behavior_block = block

          # Define propagate for simulation
          if ancestors.include?(RHDL::HDL::SimComponent)
            define_method(:propagate) do
              self.class.execute_extended_behavior_for_simulation(self)
            end
          end
        end

        def _extended_behavior_block
          @_extended_behavior_block
        end

        def extended_behavior_defined?
          !@_extended_behavior_block.nil?
        end

        # Execute extended behavior for simulation
        def execute_extended_behavior_for_simulation(component)
          return unless @_extended_behavior_block

          input_values = {}
          component.inputs.each { |name, wire| input_values[name] = wire.get }
          component.outputs.each { |name, wire| input_values[name] = wire.get }

          context = ExtendedBehaviorContext.new(self)
          context.simulation_mode!
          context.instance_variable_set(:@input_values, input_values)

          # Create proxies and evaluate
          proxies = context.create_extended_proxies
          ExtendedBehaviorEvaluator.new(context, proxies).evaluate(&@_extended_behavior_block)

          # Compute simulation values from assignments
          context.assignments.each do |assignment|
            value = compute_extended_value(assignment.expr, context)
            component.out_set(assignment.target.name, value & ((1 << assignment.target.width) - 1))
          end
        end

        # Execute extended behavior for synthesis
        def execute_extended_behavior_for_synthesis
          return {} unless @_extended_behavior_block

          context = ExtendedBehaviorContext.new(self)
          context.synthesis_mode!
          context.evaluate_extended(&@_extended_behavior_block)
          context.to_ir_with_locals
        end

        private

        def compute_extended_value(expr, context)
          case expr
          when BehaviorLocal
            compute_extended_value(expr.expr, context)
          when BehaviorCaseExpr
            compute_case_value(expr.ir, context)
          when Behavior::BehaviorConditional
            cond = compute_extended_value(expr.condition, context)
            if cond != 0
              compute_extended_value(expr.when_true_expr, context)
            else
              expr.when_false_expr ? compute_extended_value(expr.when_false_expr, context) : 0
            end
          when Behavior::BehaviorLiteral
            expr.value
          when Behavior::BehaviorSignalRef
            context.input_values[expr.name] || 0
          when Behavior::BehaviorBinaryOp
            left = compute_extended_value(expr.left, context)
            right = compute_extended_value(expr.right, context)
            compute_binary_op(expr.op, left, right, expr.width)
          when Behavior::BehaviorUnaryOp
            operand = compute_extended_value(expr.operand, context)
            compute_unary_op(expr.op, operand, expr.width)
          when Behavior::BehaviorSlice
            base = compute_extended_value(expr.base, context)
            low = [expr.range.begin, expr.range.end].min
            (base >> low) & ((1 << expr.width) - 1)
          when Behavior::BehaviorBitSelect
            base = compute_extended_value(expr.base, context)
            (base >> expr.index) & 1
          when Behavior::BehaviorConcat
            result = 0
            offset = 0
            expr.parts.reverse.each do |part|
              result |= (compute_extended_value(part, context) << offset)
              offset += part.width
            end
            result
          when Integer
            expr
          else
            0
          end
        end

        def compute_case_value(case_ir, context)
          selector_val = compute_extended_value_from_ir(case_ir.selector, context)

          case_ir.cases.each do |values, branch_ir|
            if values.include?(selector_val)
              return compute_extended_value_from_ir(branch_ir, context)
            end
          end

          case_ir.default ? compute_extended_value_from_ir(case_ir.default, context) : 0
        end

        def compute_extended_value_from_ir(ir, context)
          case ir
          when RHDL::Export::IR::Literal
            ir.value
          when RHDL::Export::IR::Signal
            context.input_values[ir.name.to_sym] || 0
          when RHDL::Export::IR::BinaryOp
            left = compute_extended_value_from_ir(ir.left, context)
            right = compute_extended_value_from_ir(ir.right, context)
            compute_binary_op(ir.op, left, right, ir.width)
          when RHDL::Export::IR::UnaryOp
            operand = compute_extended_value_from_ir(ir.operand, context)
            compute_unary_op(ir.op, operand, ir.width)
          when RHDL::Export::IR::Slice
            base = compute_extended_value_from_ir(ir.base, context)
            low = [ir.range.begin, ir.range.end].min
            (base >> low) & ((1 << ir.width) - 1)
          when RHDL::Export::IR::Mux
            cond = compute_extended_value_from_ir(ir.condition, context)
            if cond != 0
              compute_extended_value_from_ir(ir.when_true, context)
            else
              compute_extended_value_from_ir(ir.when_false, context)
            end
          when RHDL::Export::IR::Case
            compute_case_value(ir, context)
          when RHDL::Export::IR::Resize
            compute_extended_value_from_ir(ir.expr, context)
          else
            0
          end
        end

        def compute_binary_op(op, left, right, width)
          # Ensure operands are integers
          left = left.to_i
          right = right.to_i
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
          else 0
          end
          result.to_i & mask
        end

        def compute_unary_op(op, operand, width)
          mask = (1 << width) - 1
          case op
          when :~ then (~operand) & mask
          when :- then (-operand) & mask
          else 0
          end
        end
      end
    end
  end
end
