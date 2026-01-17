# frozen_string_literal: true

module RHDL
  module HDL
    # Context for evaluating behavior blocks in synthesis mode
    # Generates IR expressions instead of computing values
    class BehaviorSynthContext
      attr_reader :assignments, :locals

      def initialize(component_class)
        @component_class = component_class
        @assignments = []
        @locals = []
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
        @locals.clear
        instance_eval(&block)
      end

      def record_assignment(target_name, target_width, expr)
        @assignments << { target: target_name, width: target_width, expr: expr }
      end

      # Define a local variable (becomes a wire in synthesis)
      def local(name, expr, width: nil)
        wrapped = wrap_expr(expr)
        w = width || wrapped.width
        local_var = SynthLocal.new(name, wrapped, w)
        @locals << local_var

        # Define accessor method for this local
        define_singleton_method(name) { local_var }

        local_var
      end

      # Convert collected assignments to IR with local wires
      def to_ir_assigns
        # First, create wire assignments for locals
        wire_assigns = @locals.map do |local_var|
          ir_expr = local_var.expr.to_ir
          ir_expr = resize_ir(ir_expr, local_var.width) if ir_expr.width != local_var.width
          RHDL::Export::IR::Assign.new(target: local_var.name, expr: ir_expr)
        end

        # Then, create output assignments
        output_assigns = @assignments.map do |assignment|
          ir_expr = assignment[:expr].to_ir
          ir_expr = resize_ir(ir_expr, assignment[:width]) if ir_expr.width != assignment[:width]
          RHDL::Export::IR::Assign.new(target: assignment[:target], expr: ir_expr)
        end

        wire_assigns + output_assigns
      end

      # Get wire declarations for locals
      def wire_declarations
        @locals.map do |local_var|
          RHDL::Export::IR::Net.new(name: local_var.name, width: local_var.width)
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

      # Simple if-else for single expression
      def if_else(condition, then_expr, else_expr)
        mux(condition, then_expr, else_expr)
      end

      # Access component class-level parameters (for synthesis, uses defaults)
      # In synthesis, this returns the default width from port definitions
      def param(name)
        case name
        when :width
          # Look for common width parameter from output ports
          out_port = @component_class._port_defs.find { |p| p[:direction] == :out && p[:width] > 1 }
          out_port ? out_port[:width] : 1
        when :input_count
          @component_class._port_defs.count { |p| p[:direction] == :in && p[:name].to_s.start_with?('in') }
        else
          nil
        end
      end

      # Get the width of a port (uses class-level definitions)
      def port_width(name)
        @port_widths[name] || 1
      end

      # Reduction OR - any bit set
      def reduce_or(signal)
        wrapped = wrap_expr(signal)
        SynthUnaryOp.new(:reduce_or, wrapped, 1)
      end

      # Reduction AND - all bits set
      def reduce_and(signal)
        wrapped = wrap_expr(signal)
        SynthUnaryOp.new(:reduce_and, wrapped, 1)
      end

      # Reduction XOR - parity
      def reduce_xor(signal)
        wrapped = wrap_expr(signal)
        SynthUnaryOp.new(:reduce_xor, wrapped, 1)
      end

      # Case select - generates nested mux chain for synthesis
      # Usage: case_select(op, { 0 => a + b, 1 => a - b }, default: 0)
      def case_select(selector, cases, default: 0)
        sel = wrap_expr(selector)
        default_expr = wrap_expr(default)

        # Build nested mux chain: mux(sel == n, case_n, mux(sel == n-1, ...))
        result = default_expr
        cases.reverse_each do |value, expr|
          wrapped = wrap_expr(expr)
          cond = SynthBinaryOp.new(:==, sel, SynthLiteral.new(value, sel.width), 1)
          result = SynthMux.new(cond, wrapped, result, [wrapped.width, result.width].max)
        end
        result
      end

      # Memory read expression for use in behavior blocks
      # Creates a SynthMemoryRead that generates IR::MemoryRead for synthesis
      # @param memory_name [Symbol] The memory array name
      # @param addr [SynthExpr, Integer] The address expression
      # @param width [Integer] Optional width override (default: 8)
      def mem_read_expr(memory_name, addr, width: 8)
        addr_expr = wrap_expr(addr)
        SynthMemoryRead.new(memory_name, addr_expr, width)
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

    # Local variable expression for synthesis
    class SynthLocal < SynthExpr
      attr_reader :name, :expr

      def initialize(name, expr, width)
        super(width)
        @name = name
        @expr = expr
      end

      def to_ir
        # Reference the wire by name
        RHDL::Export::IR::Signal.new(name: @name, width: @width)
      end
    end
  end
end
