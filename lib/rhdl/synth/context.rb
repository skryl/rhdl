# frozen_string_literal: true

module RHDL
  module Synth
    # Context for evaluating behavior blocks in synthesis mode
    # Generates IR expressions instead of computing values
    class Context
      attr_reader :assignments, :locals

      def initialize(component_class)
        @component_class = component_class
        @assignments = []
        @locals = []
        @port_widths = {}
        @vec_defs = {}

        # Build port width map (use _ports/_signals which resolve parameterized widths)
        component_class._ports.each do |p|
          @port_widths[p.name] = p.width
        end
        component_class._signals.each do |s|
          @port_widths[s.name] = s.width
        end

        # Create accessor methods for all ports and signals
        component_class._ports.each do |p|
          if p.direction == :out
            define_singleton_method(p.name) { OutputProxy.new(p.name, p.width, self) }
          else
            define_singleton_method(p.name) { SignalProxy.new(p.name, p.width) }
          end
        end
        component_class._signals.each do |s|
          define_singleton_method(s.name) { OutputProxy.new(s.name, s.width, self) }
        end

        # Create accessor methods for Vecs
        component_class._vec_defs.each do |vd|
          count = component_class.resolve_class_width(vd[:count])
          width = component_class.resolve_class_width(vd[:width])
          @vec_defs[vd[:name]] = { count: count, width: width, direction: vd[:direction] }

          vec_name = vd[:name]
          define_singleton_method(vec_name) { VecProxy.new(vec_name, @vec_defs[vec_name], self) }
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
        local_var = Local.new(name, wrapped, w)
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
          RHDL::Codegen::IR::Assign.new(target: local_var.name, expr: ir_expr)
        end

        # Then, create output assignments
        output_assigns = @assignments.map do |assignment|
          ir_expr = assignment[:expr].to_ir
          ir_expr = resize_ir(ir_expr, assignment[:width]) if ir_expr.width != assignment[:width]
          RHDL::Codegen::IR::Assign.new(target: assignment[:target], expr: ir_expr)
        end

        wire_assigns + output_assigns
      end

      # Get wire declarations for locals
      def wire_declarations
        @locals.map do |local_var|
          RHDL::Codegen::IR::Net.new(name: local_var.name, width: local_var.width)
        end
      end

      # Helper for conditional expressions (mux)
      def mux(condition, when_true, when_false)
        cond = wrap_expr(condition)
        true_expr = wrap_expr(when_true)
        false_expr = wrap_expr(when_false)
        width = [true_expr.width, false_expr.width].max
        Mux.new(cond, true_expr, false_expr, width)
      end

      # Helper for creating literal values with explicit width
      def lit(value, width:)
        Literal.new(value, width)
      end

      # Helper for concatenation
      def cat(*signals)
        parts = signals.map { |s| wrap_expr(s) }
        total_width = parts.sum(&:width)
        Concat.new(parts, total_width)
      end

      # Simple if-else for single expression
      def if_else(condition, then_expr, else_expr)
        mux(condition, then_expr, else_expr)
      end

      # Access component class-level parameters (for synthesis, uses defaults)
      # In synthesis, this returns the default value from parameter definitions
      def param(name)
        # First check explicit parameter definitions
        if @component_class._parameter_defs.key?(name)
          return @component_class._parameter_defs[name]
        end

        # Fall back to legacy inference for backwards compatibility
        case name
        when :width
          # Look for common width parameter from resolved ports
          out_port = @component_class._ports.find { |p| p.direction == :out && p.width > 1 }
          out_port ? out_port.width : 1
        when :input_count
          @component_class._ports.count { |p| p.direction == :in && p.name.to_s.start_with?('in') }
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
        UnaryOp.new(:reduce_or, wrapped, 1)
      end

      # Reduction AND - all bits set
      def reduce_and(signal)
        wrapped = wrap_expr(signal)
        UnaryOp.new(:reduce_and, wrapped, 1)
      end

      # Reduction XOR - parity
      def reduce_xor(signal)
        wrapped = wrap_expr(signal)
        UnaryOp.new(:reduce_xor, wrapped, 1)
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
          cond = BinaryOp.new(:==, sel, Literal.new(value, sel.width), 1)
          result = Mux.new(cond, wrapped, result, [wrapped.width, result.width].max)
        end
        result
      end

      # Memory read expression for use in behavior blocks
      # Creates a MemoryRead that generates IR::MemoryRead for synthesis
      # @param memory_name [Symbol] The memory array name
      # @param addr [Expr, Integer] The address expression
      # @param width [Integer] Optional width override (default: 8)
      def mem_read_expr(memory_name, addr, width: 8)
        addr_expr = wrap_expr(addr)
        MemoryRead.new(memory_name, addr_expr, width)
      end

      private

      def wrap_expr(expr)
        case expr
        when Expr
          expr
        when Integer
          Literal.new(expr, expr == 0 ? 1 : expr.bit_length)
        else
          expr
        end
      end

      def resize_ir(ir_expr, target_width)
        RHDL::Codegen::IR::Resize.new(expr: ir_expr, width: target_width)
      end
    end

    # Local variable expression for synthesis
    class Local < Expr
      attr_reader :name, :expr

      def initialize(name, expr, width)
        super(width)
        @name = name
        @expr = expr
      end

      def to_ir
        # Reference the wire by name
        RHDL::Codegen::IR::Signal.new(name: @name, width: @width)
      end
    end

    # Proxy for Vec access in behavior blocks (synthesis mode)
    # Generates mux trees for hardware-indexed access
    class VecProxy
      attr_reader :name, :vec_def, :context

      def initialize(name, vec_def, context)
        @name = name
        @vec_def = vec_def
        @context = context
      end

      # Access element by index
      # Constant index: returns reference to flattened port
      # Hardware index: generates mux tree
      def [](index)
        if index.is_a?(Integer)
          # Constant index - reference the flattened port directly
          port_name = "#{@name}_#{index}"
          SignalProxy.new(port_name, @vec_def[:width])
        else
          # Hardware index - generate mux expression
          VecAccess.new(@name, @vec_def, index, @context)
        end
      end

      def count
        @vec_def[:count]
      end

      def element_width
        @vec_def[:width]
      end
    end

    # Represents a hardware-indexed Vec access for synthesis
    # Generates a mux tree selecting from all elements
    class VecAccess < Expr
      attr_reader :vec_name, :vec_def, :index

      def initialize(vec_name, vec_def, index, context)
        super(vec_def[:width])
        @vec_name = vec_name
        @vec_def = vec_def
        @index = index
        @context = context
      end

      def to_ir
        # Generate a mux tree for selecting from Vec elements
        # case_select(index, { 0 => vec_0, 1 => vec_1, ... })
        count = @vec_def[:count]
        element_width = @vec_def[:width]

        # Build cases for each element
        # Start with last element as default, then build mux chain backwards
        result = RHDL::Codegen::IR::Signal.new(
          name: "#{@vec_name}_#{count - 1}",
          width: element_width
        )

        # Build mux chain from second-to-last down to first
        (count - 2).downto(0) do |i|
          element_signal = RHDL::Codegen::IR::Signal.new(
            name: "#{@vec_name}_#{i}",
            width: element_width
          )

          # Condition: index == i
          index_ir = @index.respond_to?(:to_ir) ? @index.to_ir : RHDL::Codegen::IR::Signal.new(name: @index.to_s, width: index_width)
          condition = RHDL::Codegen::IR::BinaryOp.new(
            op: :==,
            left: index_ir,
            right: RHDL::Codegen::IR::Literal.new(value: i, width: index_width),
            width: 1
          )

          result = RHDL::Codegen::IR::Mux.new(
            condition: condition,
            when_true: element_signal,
            when_false: result,
            width: element_width
          )
        end

        result
      end

      private

      def index_width
        (@vec_def[:count] - 1).bit_length.clamp(1, 32)
      end
    end
  end
end
