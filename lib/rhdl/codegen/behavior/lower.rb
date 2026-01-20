# Lower RHDL DSL component definitions into export IR

require "active_support/core_ext/string/inflections"
require_relative "ir"

module RHDL
  module Codegen
    module Behavior
      class Lower
      def initialize(component_class, top_name: nil)
        @component_class = component_class
        @top_name = top_name
        @widths = {}
        @ports = []
        @regs = []
        @nets = []
        @assigns = []
        @processes = []
        @reg_ports = []
      end

      def build
        collect_ports
        collect_signals
        collect_assignments
        collect_processes

        IR::ModuleDef.new(
          name: module_name,
          ports: @ports,
          nets: @nets,
          regs: @regs,
          assigns: @assigns,
          processes: @processes,
          reg_ports: @reg_ports
        )
      end

      private

      def module_name
        @top_name || @component_class.name.split("::").last.underscore
      end

      def collect_ports
        @component_class._ports.each do |port|
          @ports << IR::Port.new(name: port.name, direction: port.direction, width: port.width)
          @widths[port.name.to_sym] = port.width
        end
      end

      def collect_signals
        @component_class._signals.each do |signal|
          @regs << IR::Reg.new(name: signal.name, width: signal.width)
          @widths[signal.name.to_sym] = signal.width
        end
        @component_class._constants.each do |const|
          @widths[const.name.to_sym] = const.width
        end
      end

      def collect_assignments
        @component_class._assignments.each do |assignment|
          target = assignment.target
          target_name = signal_name(target)
          target_width = width_for(target)
          expr = lower_expr(assignment.value, context_width: target_width)

          if assignment.condition
            cond = lower_expr(assignment.condition)
            expr = IR::Mux.new(
              condition: cond,
              when_true: expr,
              when_false: IR::Signal.new(name: target_name, width: target_width),
              width: target_width
            )
          end

          expr = resize(expr, target_width)
          @assigns << IR::Assign.new(target: target_name, expr: expr)
        end
      end

      def collect_processes
        sequential_targets = []

        @component_class._processes.each do |process|
          statements = process.statements.map { |stmt| lower_statement(stmt) }.compact
          statements.each { |stmt| collect_sequential_targets(stmt, sequential_targets) }

          if process.is_clocked
            clock = signal_name(process.sensitivity_list.first)
            @processes << IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: true,
              clock: clock
            )
          else
            sensitivity = process.sensitivity_list.map { |sig| signal_name(sig) }
            @processes << IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: false,
              sensitivity_list: sensitivity
            )
          end
        end

        mark_reg_ports(sequential_targets)
      end

      def mark_reg_ports(sequential_targets)
        return if sequential_targets.empty?

        port_names = @ports.map(&:name)
        sequential_targets.uniq.each do |name|
          @reg_ports << name if port_names.include?(name)
        end
      end

      def collect_sequential_targets(stmt, targets)
        case stmt
        when IR::SeqAssign
          targets << stmt.target
        when IR::If
          stmt.then_statements.each { |s| collect_sequential_targets(s, targets) }
          stmt.else_statements.each { |s| collect_sequential_targets(s, targets) }
        end
      end

      def lower_statement(stmt)
        case stmt
        when RHDL::DSL::SequentialAssignment
          target_name = signal_name(stmt.target)
          target_width = width_for(stmt.target)
          expr = lower_expr(stmt.value, context_width: target_width)
          expr = resize(expr, target_width)
          IR::SeqAssign.new(target: target_name, expr: expr)
        when RHDL::DSL::IfStatement
          lower_if(stmt)
        else
          nil
        end
      end

      def lower_if(if_stmt)
        condition = lower_expr(if_stmt.condition)
        then_statements = if_stmt.then_block.map { |stmt| lower_statement(stmt) }.compact
        else_statements = []

        if if_stmt.elsif_blocks.any?
          nested = build_elsif_chain(if_stmt.elsif_blocks, if_stmt.else_block)
          else_statements << nested if nested
        else
          else_statements = if_stmt.else_block.map { |stmt| lower_statement(stmt) }.compact
        end

        IR::If.new(condition: condition, then_statements: then_statements, else_statements: else_statements)
      end

      def build_elsif_chain(elsif_blocks, else_block)
        first = elsif_blocks.first
        return nil unless first

        condition = lower_expr(first[0])
        then_statements = first[1].map { |stmt| lower_statement(stmt) }.compact
        remaining = elsif_blocks.drop(1)
        else_statements = []
        if remaining.any?
          nested = build_elsif_chain(remaining, else_block)
          else_statements << nested if nested
        else
          else_statements = else_block.map { |stmt| lower_statement(stmt) }.compact
        end

        IR::If.new(condition: condition, then_statements: then_statements, else_statements: else_statements)
      end

      def lower_expr(expr, context_width: nil)
        case expr
        when RHDL::DSL::SignalRef
          IR::Signal.new(name: expr.name, width: width_for(expr))
        when RHDL::DSL::BitSelect
          base = lower_expr(expr.signal)
          IR::Slice.new(base: base, range: expr.index..expr.index, width: 1)
        when RHDL::DSL::BitSlice
          base = lower_expr(expr.signal)
          width = expr.range.max - expr.range.min + 1
          IR::Slice.new(base: base, range: expr.range, width: width)
        when RHDL::DSL::BinaryOp
          lower_binary(expr)
        when RHDL::DSL::UnaryOp
          operand = lower_expr(expr.operand)
          IR::UnaryOp.new(op: expr.op, operand: operand, width: operand.width)
        when RHDL::DSL::Concatenation
          parts = expr.signals.map { |part| lower_expr(part) }
          width = parts.sum(&:width)
          IR::Concat.new(parts: parts, width: width)
        when RHDL::DSL::Replication
          part = lower_expr(expr.signal)
          parts = Array.new(expr.times) { part }
          IR::Concat.new(parts: parts, width: part.width * expr.times)
        when Integer
          width = context_width || [expr.bit_length, 1].max
          IR::Literal.new(value: expr, width: width)
        when Symbol
          width = @widths.fetch(expr, 1)
          IR::Signal.new(name: expr, width: width)
        else
          raise ArgumentError, "Unsupported expression: #{expr.inspect}"
        end
      end

      def lower_binary(expr)
        left = lower_expr(expr.left)
        right = lower_expr(expr.right, context_width: left.width)
        op = expr.op

        if comparison_op?(op)
          aligned = align_operands(left, right)
          return IR::BinaryOp.new(op: op, left: aligned[0], right: aligned[1], width: 1)
        end

        case op
        when :+
          aligned = align_operands(left, right)
          width = aligned.map(&:width).max + 1
          left = resize(aligned[0], width)
          right = resize(aligned[1], width)
          IR::BinaryOp.new(op: op, left: left, right: right, width: width)
        when :-, :&, :|, :^, :<<, :>>
          aligned = align_operands(left, right)
          width = aligned.map(&:width).max
          left = resize(aligned[0], width)
          right = resize(aligned[1], width)
          IR::BinaryOp.new(op: op, left: left, right: right, width: width)
        else
          raise ArgumentError, "Unsupported binary operator: #{op}"
        end
      end

      def comparison_op?(op)
        %i[== != < > <= >=].include?(op)
      end

      def align_operands(left, right)
        width = [left.width, right.width].max
        [resize(left, width), resize(right, width)]
      end

      def resize(expr, width)
        return expr if expr.width == width

        IR::Resize.new(expr: expr, width: width)
      end

      def width_for(obj)
        name = signal_name(obj)
        @widths.fetch(name.to_sym, 1)
      end

      def signal_name(obj)
        if obj.respond_to?(:name)
          obj.name.to_sym
        else
          obj.to_sym
        end
      end
    end
  end
  end
end
