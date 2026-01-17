# frozen_string_literal: true

module RHDL
  module HDL
    # Context for evaluating behavior blocks in synthesis mode
    # Generates IR expressions instead of computing values
    class BehaviorSynthContext
      attr_reader :assignments

      def initialize(component_class)
        @component_class = component_class
        @assignments = []
        @port_widths = {}

        # Build port width map
        component_class._port_defs.each do |pd|
          @port_widths[pd[:name]] = pd[:width]
        end
        component_class._signal_defs.each do |sd|
          @port_widths[sd[:name]] = sd[:width]
        end

        # Create accessor methods for all ports and signals
        component_class._port_defs.each do |pd|
          if pd[:direction] == :out
            define_singleton_method(pd[:name]) { SynthOutputProxy.new(pd[:name], pd[:width], self) }
          else
            define_singleton_method(pd[:name]) { SynthSignalProxy.new(pd[:name], pd[:width]) }
          end
        end
        component_class._signal_defs.each do |sd|
          define_singleton_method(sd[:name]) { SynthOutputProxy.new(sd[:name], sd[:width], self) }
        end
      end

      def evaluate(&block)
        @assignments.clear
        instance_eval(&block)
      end

      def record_assignment(target_name, target_width, expr)
        @assignments << { target: target_name, width: target_width, expr: expr }
      end

      # Convert collected assignments to IR
      def to_ir_assigns
        @assignments.map do |assignment|
          ir_expr = assignment[:expr].to_ir
          ir_expr = resize_ir(ir_expr, assignment[:width]) if ir_expr.width != assignment[:width]
          RHDL::Export::IR::Assign.new(target: assignment[:target], expr: ir_expr)
        end
      end

      # Helper for conditional expressions (mux)
      def mux(condition, when_true, when_false)
        cond = wrap_expr(condition)
        true_expr = wrap_expr(when_true)
        false_expr = wrap_expr(when_false)
        width = [true_expr.width, false_expr.width].max
        SynthMux.new(cond, true_expr, false_expr, width)
      end

      # Helper for creating literal values with explicit width
      def lit(value, width:)
        SynthLiteral.new(value, width)
      end

      # Helper for concatenation
      def cat(*signals)
        parts = signals.map { |s| wrap_expr(s) }
        total_width = parts.sum(&:width)
        SynthConcat.new(parts, total_width)
      end

      private

      def wrap_expr(expr)
        case expr
        when SynthExpr
          expr
        when Integer
          SynthLiteral.new(expr, expr == 0 ? 1 : expr.bit_length)
        else
          expr
        end
      end

      def resize_ir(ir_expr, target_width)
        RHDL::Export::IR::Resize.new(expr: ir_expr, width: target_width)
      end
    end
  end
end
