# Lower RHDL DSL component definitions into export IR

require 'rhdl/support/inflections'
require 'set'
require_relative "ir"

module RHDL
  module Codegen
    module IR
      class Lower
      def initialize(component_class, top_name: nil, mode: :lir)
        @component_class = component_class
        @top_name = top_name
        @mode = mode.to_sym
        @widths = {}
        @hir_memory_candidates = {}
        @parameters = {}
        @ports = []
        @regs = []
        @nets = []
        @assigns = []
        @processes = []
        @reg_ports = []
        @memories = []
        @instances = []
        @loop_bindings = {}
      end

      def build
        collect_parameters
        collect_ports
        collect_signals
        infer_hir_memory_candidates if hir_mode?
        collect_memories
        collect_assignments
        collect_processes
        collect_instances

        IR::ModuleDef.new(
          name: module_name,
          parameters: @parameters,
          ports: @ports,
          nets: @nets,
          regs: @regs,
          assigns: @assigns,
          processes: @processes,
          reg_ports: @reg_ports,
          memories: @memories,
          instances: @instances,
          declaration_kinds: imported_declaration_kinds
        )
      end

      private

      def hir_mode?
        @mode == :hir
      end

      def module_name
        @top_name || @component_class.name.split("::").last.underscore
      end

      def collect_parameters
        if @component_class.respond_to?(:_parameter_defs)
          @component_class._parameter_defs.each do |name, default|
            @parameters[name] = parameter_default_value(default)
          end
        end

        if @component_class.respond_to?(:_generics)
          @component_class._generics.each do |entry|
            hash = entry.is_a?(Hash) ? entry : {}
            name = (hash[:name] || hash["name"])
            next if name.nil?

            default = hash[:default]
            default = hash["default"] if default.nil? && hash.key?("default")
            @parameters[name] = parameter_default_value(default)
          end
        end
      end

      def parameter_default_value(value)
        case value
        when Proc
          # Keep lowering deterministic for codegen-only components.
          # Runtime parameterized codegen uses _parameter_defs directly.
          0
        when Symbol
          value.to_s
        when TrueClass
          1
        when FalseClass
          0
        else
          value
        end
      end

      def collect_ports
        @component_class._ports.each do |port|
          @ports << IR::Port.new(name: port.name, direction: port.direction, width: port.width, default: port.default)
          @widths[port.name.to_sym] = port.width
        end
      end

      def collect_signals
        # Get reset values from sequential block if present
        reset_values = if @component_class.respond_to?(:_reset_values)
          @component_class._reset_values
        elsif @component_class.respond_to?(:_sequential_block) && @component_class._sequential_block
          @component_class._sequential_block.reset_values
        else
          {}
        end
        assign_driven_targets = @component_class._assignments.map { |assignment| signal_name(assignment.target).to_sym }.to_set
        instance_driven_targets = instance_driven_signal_targets
        process_driven_targets = process_driven_signal_targets
        import_decl_kinds = imported_declaration_kinds

        @component_class._signals.each do |signal|
          reset_val = reset_values[signal.name.to_sym]
          if reset_val.nil? && !signal.default.nil? &&
             !assign_driven_targets.include?(signal.name.to_sym) &&
             !instance_driven_targets.include?(signal.name.to_sym)
            reset_val = signal.default
          end

          declared_kind = import_decl_kinds[signal.name.to_sym]
          case declared_kind
          when :wire
            if process_driven_targets.include?(signal.name.to_sym)
              @regs << IR::Reg.new(name: signal.name, width: signal.width, reset_value: reset_val)
            else
              @nets << IR::Net.new(name: signal.name, width: signal.width)
            end
          when :reg, :logic, :integer, :int
            @regs << IR::Reg.new(name: signal.name, width: signal.width, reset_value: reset_val)
          else
            if assign_driven_targets.include?(signal.name.to_sym) || instance_driven_targets.include?(signal.name.to_sym)
              @nets << IR::Net.new(name: signal.name, width: signal.width)
            else
              @regs << IR::Reg.new(name: signal.name, width: signal.width, reset_value: reset_val)
            end
          end
          @widths[signal.name.to_sym] = signal.width
        end

        # Also create registers for sequential block targets defined in reset_values
        # that aren't already defined as explicit signals
        reset_values.each do |name, value|
          next if @widths.key?(name.to_sym)

          # Infer width from reset value, or use a reasonable default
          width = infer_width_from_value(value)
          @regs << IR::Reg.new(name: name, width: width, reset_value: value)
          @widths[name.to_sym] = width
        end

        @component_class._constants.each do |const|
          @widths[const.name.to_sym] = const.width
        end
      end

      def process_driven_signal_targets
        targets = Set.new
        Array(@component_class._processes).each do |process|
          collect_dsl_statement_targets(Array(process.statements), targets)
        end
        targets
      end

      def collect_dsl_statement_targets(statements, targets)
        Array(statements).each do |stmt|
          case stmt
          when RHDL::DSL::SequentialAssignment
            target_name = signal_name(stmt.target)
            targets.add(target_name.to_sym) unless target_name.nil?
          when RHDL::DSL::IfStatement
            collect_dsl_statement_targets(stmt.then_block, targets)
            stmt.elsif_blocks.each do |_condition, block|
              collect_dsl_statement_targets(block, targets)
            end
            collect_dsl_statement_targets(stmt.else_block, targets)
          when RHDL::DSL::CaseStatement
            stmt.when_blocks.each do |_value, block|
              collect_dsl_statement_targets(block, targets)
            end
            collect_dsl_statement_targets(stmt.default_block, targets)
          when RHDL::DSL::ForLoop
            collect_dsl_statement_targets(stmt.statements, targets)
          end
        end
      end

      def infer_width_from_value(value)
        # For sequential block registers, the reset value doesn't tell us the max value.
        # Use a reasonable default that covers most state machines and counters.
        # 8 bits covers states 0-255, good for most state machines.
        # Can be overridden by defining the signal explicitly with `wire :name, width: N`
        8
      end

      def collect_memories
        return unless @component_class.respond_to?(:_memories)

        @component_class._memories.each do |name, mem_def|
          @memories << IR::Memory.new(
            name: name,
            depth: mem_def.depth,
            width: mem_def.width,
            initial_data: mem_def.initial_values
          )
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
        lowered_processes = @component_class._processes.map do |process|
          default_nonblocking = process.is_clocked
          initial_process = process.respond_to?(:is_initial) && process.is_initial
          statements = process.statements.flat_map do |stmt|
            lowered = lower_statement(stmt, nonblocking: default_nonblocking)
            lowered.nil? ? [] : Array(lowered)
          end
          sensitivity = process.sensitivity_list.filter_map { |sig| sensitivity_signal_name(sig) }
          if !imported_component? && !process.is_clocked && !initial_process && sensitivity.empty?
            sensitivity = infer_process_sensitivity(statements)
          end

          {
            process: process,
            statements: statements,
            sensitivity: sensitivity,
            initial: initial_process
          }
        end
        target_counts = process_target_writer_counts(lowered_processes)

        lowered_processes.each do |entry|
          process = entry.fetch(:process)
          statements = entry.fetch(:statements)
          sensitivity = entry.fetch(:sensitivity)
          initial_process = entry.fetch(:initial, false)

          if !imported_component? &&
             !process.is_clocked &&
             !initial_process &&
             sensitivity.empty? &&
             materialize_constant_process_as_assigns?(
               statements,
               target_counts: target_counts
             )
            emit_constant_process_assigns(statements)
            next
          end

          statements.each { |stmt| collect_sequential_targets(stmt, sequential_targets) }

          if process.is_clocked
            clock = sensitivity.first
            @processes << IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: true,
              clock: clock,
              sensitivity_list: sensitivity,
              initial: false
            )
          else
            @processes << IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: false,
              sensitivity_list: sensitivity,
              initial: initial_process
            )
          end
        end

        mark_reg_ports(sequential_targets)
      end

      def infer_process_sensitivity(statements)
        assigned_targets = Set.new
        Array(statements).each do |stmt|
          collect_statement_targets(stmt, targets: assigned_targets)
        end

        seen = {}
        inferred = []

        Array(statements).each do |stmt|
          collect_statement_read_signals(stmt, seen: seen, signals: inferred)
        end

        inferred.reject { |signal| assigned_targets.include?(signal.to_sym) }
      end

      def collect_statement_read_signals(stmt, seen:, signals:)
        case stmt
        when IR::SeqAssign
          collect_expr_read_signals(stmt.expr, seen: seen, signals: signals)
        when IR::If
          collect_expr_read_signals(stmt.condition, seen: seen, signals: signals)
          Array(stmt.then_statements).each do |inner|
            collect_statement_read_signals(inner, seen: seen, signals: signals)
          end
          Array(stmt.else_statements).each do |inner|
            collect_statement_read_signals(inner, seen: seen, signals: signals)
          end
        when IR::CaseStmt
          collect_expr_read_signals(stmt.selector, seen: seen, signals: signals)
          Array(stmt.branches).each do |branch|
            Array(branch.values).each do |value|
              collect_expr_read_signals(value, seen: seen, signals: signals)
            end
            Array(branch.statements).each do |inner|
              collect_statement_read_signals(inner, seen: seen, signals: signals)
            end
          end
          Array(stmt.default_statements).each do |inner|
            collect_statement_read_signals(inner, seen: seen, signals: signals)
          end
        end
      end

      def collect_expr_read_signals(expr, seen:, signals:)
        case expr
        when IR::Signal
          register_sensitivity_signal(expr.name, seen: seen, signals: signals)
        when IR::UnaryOp
          collect_expr_read_signals(expr.operand, seen: seen, signals: signals)
        when IR::BinaryOp
          collect_expr_read_signals(expr.left, seen: seen, signals: signals)
          collect_expr_read_signals(expr.right, seen: seen, signals: signals)
        when IR::Mux
          collect_expr_read_signals(expr.condition, seen: seen, signals: signals)
          collect_expr_read_signals(expr.when_true, seen: seen, signals: signals)
          collect_expr_read_signals(expr.when_false, seen: seen, signals: signals)
        when IR::Concat
          Array(expr.parts).each do |part|
            collect_expr_read_signals(part, seen: seen, signals: signals)
          end
        when IR::Slice
          collect_expr_read_signals(expr.base, seen: seen, signals: signals)
        when IR::DynamicSlice
          collect_expr_read_signals(expr.base, seen: seen, signals: signals)
          collect_expr_read_signals(expr.msb, seen: seen, signals: signals)
          collect_expr_read_signals(expr.lsb, seen: seen, signals: signals)
        when IR::Resize
          collect_expr_read_signals(expr.expr, seen: seen, signals: signals)
        when IR::MemoryRead
          collect_expr_read_signals(expr.addr, seen: seen, signals: signals)
        end
      end

      def collect_statement_targets(stmt, targets:)
        case stmt
        when IR::SeqAssign
          target_name = seqassign_target_name(stmt.target)
          targets << target_name unless target_name.nil?
        when IR::If
          Array(stmt.then_statements).each do |inner|
            collect_statement_targets(inner, targets: targets)
          end
          Array(stmt.else_statements).each do |inner|
            collect_statement_targets(inner, targets: targets)
          end
        when IR::CaseStmt
          Array(stmt.branches).each do |branch|
            Array(branch.statements).each do |inner|
              collect_statement_targets(inner, targets: targets)
            end
          end
          Array(stmt.default_statements).each do |inner|
            collect_statement_targets(inner, targets: targets)
          end
        end

        targets
      end

      def process_target_writer_counts(lowered_processes)
        counts = Hash.new(0)

        Array(lowered_processes).each do |entry|
          Array(entry.fetch(:statements, [])).each do |stmt|
            collect_statement_targets(stmt, targets: Set.new).each do |target|
              counts[target.to_sym] += 1
            end
          end
        end

        counts
      end

      def materialize_constant_process_as_assigns?(statements, target_counts:)
        return false if Array(statements).empty?

        assign_targets = @assigns.map { |entry| entry.target.to_sym }.to_set
        port_targets = @ports.map { |entry| entry.name.to_sym }.to_set
        Array(statements).all? do |stmt|
          next false unless stmt.is_a?(IR::SeqAssign)
          next false if stmt.nonblocking
          next false unless literal_like_expr?(stmt.expr)

          target = seqassign_target_name(stmt.target)
          next false if target.nil?
          port_targets.include?(target) &&
            !assign_targets.include?(target) &&
            target_counts[target] == 1
        end
      end

      def emit_constant_process_assigns(statements)
        Array(statements).each do |stmt|
          next unless stmt.is_a?(IR::SeqAssign)
          target_name = seqassign_target_name(stmt.target)
          next if target_name.nil?

          width = @widths.fetch(target_name.to_sym, stmt.expr.width)
          @assigns << IR::Assign.new(target: target_name, expr: resize(stmt.expr, width))
        end
      end

      def literal_like_expr?(expr)
        case expr
        when IR::Literal
          true
        when IR::Resize
          literal_like_expr?(expr.expr)
        else
          false
        end
      end

      def register_sensitivity_signal(name, seen:, signals:)
        token = name.to_sym
        return if seen[token]

        seen[token] = true
        signals << token
      end

      def collect_instances
        return unless @component_class.respond_to?(:_instances)

        @component_class._instances.each do |instance|
          port_directions = instance_port_directions(instance)
          port_map = resolved_instance_port_map(instance, port_directions: port_directions)
          connections = port_map.map do |port_name, signal|
            IR::PortConnection.new(
              port_name: port_name,
              signal: normalize_instance_signal(signal),
              direction: port_directions.fetch(port_name.to_sym, :in)
            )
          end

          @instances << IR::Instance.new(
            name: instance.name.to_s,
            module_name: instance.component_type.to_s,
            connections: connections,
            parameters: instance.generic_map || {}
          )
        end
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
          target_name = seqassign_target_name(stmt.target)
          targets << target_name unless target_name.nil?
        when IR::If
          stmt.then_statements.each { |s| collect_sequential_targets(s, targets) }
          stmt.else_statements.each { |s| collect_sequential_targets(s, targets) }
        when IR::CaseStmt
          Array(stmt.branches).each do |branch|
            Array(branch.statements).each { |s| collect_sequential_targets(s, targets) }
          end
          Array(stmt.default_statements).each { |s| collect_sequential_targets(s, targets) }
        end
      end

      def lower_statement(stmt, nonblocking:)
        case stmt
        when RHDL::DSL::SequentialAssignment
          assignment_mode = assignment_mode_for(stmt, default: nonblocking)

          if indexed_target?(stmt.target)
            return lower_indexed_assignment(stmt, nonblocking: assignment_mode) unless hir_mode?
            return lower_hir_indexed_assignment(stmt, nonblocking: assignment_mode)
          end

          target_name = signal_name(stmt.target)
          target_width = width_for(stmt.target)
          expr = lower_expr(stmt.value, context_width: target_width)
          expr = resize(expr, target_width)
          IR::SeqAssign.new(target: target_name, expr: expr, nonblocking: assignment_mode)
        when RHDL::DSL::IfStatement
          lower_if(stmt, nonblocking: nonblocking)
        when RHDL::DSL::CaseStatement
          lower_case_statement(stmt, nonblocking: nonblocking)
        when RHDL::DSL::ForLoop
          lower_for_loop(stmt, nonblocking: nonblocking)
        else
          nil
        end
      end

      def lower_hir_indexed_assignment(stmt, nonblocking:)
        if hir_memory_write_target?(stmt.target, value: stmt.value)
          return lower_hir_memory_like_indexed_assignment(stmt, nonblocking: nonblocking)
        end

        target_expr = hir_lvalue_target(stmt.target)
        return lower_indexed_assignment(stmt, nonblocking: nonblocking) if target_expr.nil?

        target_width = width_for(stmt.target)
        expr = lower_expr(stmt.value, context_width: target_width)
        expr = resize(expr, target_width)
        IR::SeqAssign.new(target: target_expr, expr: expr, nonblocking: nonblocking)
      end

      def hir_lvalue_target(target)
        return nil if target_uses_loop_binding?(target)

        case target
        when RHDL::DSL::BitSelect
          return nil unless simple_hir_lvalue_base?(target.signal)
          base_width = hir_lvalue_base_width(target.signal)
          return target if hir_memory_candidate_name?(signal_name(target.signal))
          return nil unless base_width.is_a?(Integer) && base_width > 1
          return target
        when RHDL::DSL::BitSlice
          if target.signal.is_a?(RHDL::DSL::BitSelect) &&
             hir_memory_bitselect_candidate?(target.signal) &&
             bit_slice_static?(target.range)
            return target
          end

          return nil unless simple_hir_lvalue_base?(target.signal)
          return nil unless bit_slice_static?(target.range)
          base_width = hir_lvalue_base_width(target.signal)
          return nil unless base_width.is_a?(Integer) && base_width > 1

          bounds = static_range_bounds(target.range)
          return nil if bounds.nil?

          high, low = bounds
          return nil if low.negative?
          return nil if high >= base_width

          return target
        else
          nil
        end
      end

      def infer_hir_memory_candidates
        @component_class._assignments.each do |assignment|
          target_width = width_for(assignment.target)
          collect_hir_memory_candidates_from_expression(assignment.value, context_width: target_width)
        end

        Array(@component_class._processes).each do |process|
          collect_hir_memory_candidates_from_statements(Array(process.statements))
        end
      rescue StandardError
        nil
      end

      def collect_hir_memory_candidates_from_statements(statements)
        Array(statements).each do |stmt|
          case stmt
          when RHDL::DSL::SequentialAssignment
            if hir_dynamic_bitselect?(stmt.target)
              base_name = signal_name(stmt.target.signal)
              value_width = width_for(stmt.value)
              addr_width = width_for(stmt.target.index)
              if value_width.is_a?(Integer) && value_width > 1
                register_hir_memory_candidate(
                  name: base_name,
                  word_width: value_width,
                  addr_width: addr_width
                )
              end
              target_width = [width_for(stmt.target), value_width].compact.max
            else
              target_width = width_for(stmt.target)
            end

            collect_hir_memory_candidates_from_expression(stmt.value, context_width: target_width)
          when RHDL::DSL::IfStatement
            collect_hir_memory_candidates_from_expression(stmt.condition, context_width: 1)
            collect_hir_memory_candidates_from_statements(stmt.then_block)
            stmt.elsif_blocks.each do |condition, block|
              collect_hir_memory_candidates_from_expression(condition, context_width: 1)
              collect_hir_memory_candidates_from_statements(block)
            end
            collect_hir_memory_candidates_from_statements(stmt.else_block)
          when RHDL::DSL::CaseStatement
            collect_hir_memory_candidates_from_expression(stmt.selector, context_width: nil)
            stmt.when_blocks.each do |values, block|
              Array(values).each do |value|
                collect_hir_memory_candidates_from_expression(value, context_width: nil)
              end
              collect_hir_memory_candidates_from_statements(block)
            end
            collect_hir_memory_candidates_from_statements(stmt.default_block)
          when RHDL::DSL::ForLoop
            collect_hir_memory_candidates_from_statements(stmt.statements)
          end
        end
      end

      def collect_hir_memory_candidates_from_expression(expr, context_width:)
        return if expr.nil?

        case expr
        when RHDL::DSL::BitSelect
          if hir_dynamic_bitselect?(expr)
            base_name = signal_name(expr.signal)
            register_hir_memory_candidate(
              name: base_name,
              word_width: context_width,
              addr_width: width_for(expr.index)
            )
          end
          collect_hir_memory_candidates_from_expression(expr.signal, context_width: nil)
          collect_hir_memory_candidates_from_expression(expr.index, context_width: nil)
        when RHDL::DSL::BitSlice
          collect_hir_memory_candidates_from_expression(expr.signal, context_width: nil)
          if expr.range.is_a?(Range)
            collect_hir_memory_candidates_from_expression(expr.range.begin, context_width: nil)
            collect_hir_memory_candidates_from_expression(expr.range.end, context_width: nil)
          end
        when RHDL::DSL::BinaryOp
          left_width = normalize_positive_integer(width_for(expr.left))
          right_width = normalize_positive_integer(width_for(expr.right))
          shared_context = [
            normalize_positive_integer(context_width),
            left_width,
            right_width
          ].compact.max
          collect_hir_memory_candidates_from_expression(expr.left, context_width: shared_context)
          collect_hir_memory_candidates_from_expression(expr.right, context_width: shared_context)
        when RHDL::DSL::UnaryOp
          collect_hir_memory_candidates_from_expression(expr.operand, context_width: nil)
        when RHDL::DSL::TernaryOp
          collect_hir_memory_candidates_from_expression(expr.condition, context_width: 1)
          collect_hir_memory_candidates_from_expression(expr.when_true, context_width: context_width)
          collect_hir_memory_candidates_from_expression(expr.when_false, context_width: context_width)
        when RHDL::DSL::Concatenation
          expr.signals.each { |part| collect_hir_memory_candidates_from_expression(part, context_width: nil) }
        when RHDL::DSL::Replication
          collect_hir_memory_candidates_from_expression(expr.signal, context_width: nil)
          collect_hir_memory_candidates_from_expression(expr.times, context_width: nil)
        when RHDL::DSL::CaseSelect
          collect_hir_memory_candidates_from_expression(expr.selector, context_width: nil)
          expr.cases.each_value do |branch_expr|
            collect_hir_memory_candidates_from_expression(branch_expr, context_width: context_width)
          end
          collect_hir_memory_candidates_from_expression(expr.default_expr, context_width: context_width)
        when Hash
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :signal), context_width: nil)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :value), context_width: context_width)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :left), context_width: nil)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :right), context_width: nil)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :condition), context_width: 1)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :true_expr), context_width: context_width)
          collect_hir_memory_candidates_from_expression(value_for_hash(expr, :false_expr), context_width: context_width)
        when Array
          expr.each { |entry| collect_hir_memory_candidates_from_expression(entry, context_width: nil) }
        end
      end

      def value_for_hash(hash, key)
        return nil unless hash.is_a?(Hash)
        return hash[key] if hash.key?(key)
        return hash[key.to_s] if hash.key?(key.to_s)

        hash[key.to_sym]
      end

      def hir_dynamic_bitselect?(target)
        return false unless target.is_a?(RHDL::DSL::BitSelect)
        return false if target.index.is_a?(Integer)
        return false unless simple_hir_lvalue_base?(target.signal)

        !signal_name(target.signal).nil?
      rescue StandardError
        false
      end

      def hir_memory_bitselect_candidate?(target)
        return false unless hir_dynamic_bitselect?(target)

        base_width = hir_lvalue_base_width(target.signal)
        return false unless base_width.is_a?(Integer) && base_width <= 1

        true
      rescue StandardError
        false
      end

      def register_hir_memory_candidate(name:, word_width:, addr_width:)
        token = name.to_sym
        width = normalize_positive_integer(word_width)
        return if width.nil? || width <= 1

        addr = normalize_positive_integer(addr_width) || 1
        current = (@hir_memory_candidates[token] ||= { word_width: 0, addr_width: 0 })
        current[:word_width] = [current[:word_width], width].max
        current[:addr_width] = [current[:addr_width], addr].max
      rescue StandardError
        nil
      end

      def normalize_positive_integer(value)
        return nil if value.nil?

        integer =
          case value
          when Integer
            value
          when Range
            range_width(value)
          else
            Integer(value.to_s)
          end

        integer.positive? ? integer : nil
      rescue ArgumentError, TypeError
        nil
      end

      def hir_memory_candidate_name?(name)
        return false if name.nil?

        entry = @hir_memory_candidates[name.to_sym]
        entry.is_a?(Hash) && entry.fetch(:word_width, 0) > 1
      end

      def hir_memory_word_width_for(name, fallback: nil)
        entry = @hir_memory_candidates[name.to_sym]
        width = entry.is_a?(Hash) ? normalize_positive_integer(entry[:word_width]) : nil
        width ||= normalize_positive_integer(fallback)
        width ||= 1
        width
      end

      def hir_memory_addr_width_for(name, fallback: nil)
        entry = @hir_memory_candidates[name.to_sym]
        width = entry.is_a?(Hash) ? normalize_positive_integer(entry[:addr_width]) : nil
        width ||= normalize_positive_integer(fallback)
        width ||= 1
        width
      end

      def hir_memory_write_target?(target, value:)
        return false unless hir_dynamic_bitselect?(target)

        base_name = signal_name(target.signal)
        return false if base_name.nil?
        return true if hir_memory_candidate_name?(base_name)
        return false unless hir_memory_bitselect_candidate?(target)

        value_width = normalize_positive_integer(width_for(value))
        value_width.is_a?(Integer) && value_width > 1
      end

      def lower_hir_memory_like_indexed_assignment(stmt, nonblocking:)
        target = stmt.target
        base_name = signal_name(target.signal)
        return lower_indexed_assignment(stmt, nonblocking: nonblocking) if base_name.nil?

        inferred_width = hir_memory_word_width_for(base_name, fallback: width_for(stmt.value))
        inferred_addr_width = hir_memory_addr_width_for(base_name, fallback: width_for(target.index))
        register_hir_memory_candidate(name: base_name, word_width: inferred_width, addr_width: inferred_addr_width)

        addr_expr = lower_expr(target.index, context_width: inferred_addr_width)
        addr_expr = resize(addr_expr, inferred_addr_width)

        data_expr = lower_expr(stmt.value, context_width: inferred_width)
        data_expr = resize(data_expr, inferred_width)

        IR::MemoryWrite.new(memory: base_name, addr: addr_expr, data: data_expr)
      end

      def target_uses_loop_binding?(target)
        return false if @loop_bindings.empty?
        return false unless target.respond_to?(:to_verilog)

        rendered = target.to_verilog.to_s
        return false if rendered.empty?

        @loop_bindings.keys.any? do |binding_name|
          rendered.match?(/\b#{Regexp.escape(binding_name.to_s)}\b/)
        end
      rescue StandardError
        false
      end

      def simple_hir_lvalue_base?(base)
        case base
        when Symbol
          true
        when String
          !base.strip.empty?
        when RHDL::DSL::SignalRef
          true
        else
          false
        end
      end

      def hir_lvalue_base_width(base)
        base_name = signal_name(base)
        return nil if base_name.nil?

        width_value_to_integer(@widths[base_name.to_sym])
      rescue StandardError
        nil
      end

      def lower_if(if_stmt, nonblocking:)
        condition = lower_expr(if_stmt.condition)
        then_statements = if_stmt.then_block.flat_map do |stmt|
          lowered = lower_statement(stmt, nonblocking: nonblocking)
          lowered.nil? ? [] : Array(lowered)
        end
        else_statements = []

        if if_stmt.elsif_blocks.any?
          nested = build_elsif_chain(if_stmt.elsif_blocks, if_stmt.else_block, nonblocking: nonblocking)
          else_statements << nested if nested
        else
          else_statements = if_stmt.else_block.flat_map do |stmt|
            lowered = lower_statement(stmt, nonblocking: nonblocking)
            lowered.nil? ? [] : Array(lowered)
          end
        end

        IR::If.new(condition: condition, then_statements: then_statements, else_statements: else_statements)
      end

      def build_elsif_chain(elsif_blocks, else_block, nonblocking:)
        first = elsif_blocks.first
        return nil unless first

        condition = lower_expr(first[0])
        then_statements = first[1].flat_map do |stmt|
          lowered = lower_statement(stmt, nonblocking: nonblocking)
          lowered.nil? ? [] : Array(lowered)
        end
        remaining = elsif_blocks.drop(1)
        else_statements = []
        if remaining.any?
          nested = build_elsif_chain(remaining, else_block, nonblocking: nonblocking)
          else_statements << nested if nested
        else
          else_statements = else_block.flat_map do |stmt|
            lowered = lower_statement(stmt, nonblocking: nonblocking)
            lowered.nil? ? [] : Array(lowered)
          end
        end

        IR::If.new(condition: condition, then_statements: then_statements, else_statements: else_statements)
      end

      def lower_case_statement(case_stmt, nonblocking:)
        selector = case_stmt.selector
        selector_width = width_for(selector)
        default_statements = case_stmt.default_block.flat_map do |stmt|
          lowered = lower_statement(stmt, nonblocking: nonblocking)
          lowered.nil? ? [] : Array(lowered)
        end

        branches = []
        case_stmt.when_blocks.each do |raw_value, statements|
          values = Array(raw_value).flatten
          next if values.empty?

          lowered_values = values.map do |value|
            value_expr = lower_expr(value, context_width: selector_width)
            resize(value_expr, selector_width)
          end
          then_statements = statements.flat_map do |stmt|
            lowered = lower_statement(stmt, nonblocking: nonblocking)
            lowered.nil? ? [] : Array(lowered)
          end
          branches << IR::CaseBranch.new(values: lowered_values, statements: then_statements)
        end

        IR::CaseStmt.new(
          selector: lower_expr(selector),
          branches: branches,
          default_statements: default_statements
        )
      end

      def lower_for_loop(for_loop, nonblocking:)
        range = for_loop.range
        return [] unless range.is_a?(Range)
        return [] unless range.begin.is_a?(Integer) && range.end.is_a?(Integer)

        values =
          if range.begin <= range.end
            (range.begin..range.end).to_a
          else
            range.begin.downto(range.end).to_a
          end

        values.flat_map do |value|
          with_loop_binding(for_loop.variable.to_sym, value) do
            for_loop.statements.flat_map do |stmt|
              lowered = lower_statement(stmt, nonblocking: nonblocking)
              lowered.nil? ? [] : Array(lowered)
            end
          end
        end
      end

      def with_loop_binding(name, value)
        previous = @loop_bindings[name]
        @loop_bindings[name] = value
        yield
      ensure
        if previous.nil?
          @loop_bindings.delete(name)
        else
          @loop_bindings[name] = previous
        end
      end

      def lower_expr(expr, context_width: nil)
        case expr
        when RHDL::DSL::SignalRef
          binding_value = @loop_bindings[expr.name.to_sym]
          unless binding_value.nil?
            width = expr.width
            width = [binding_value.to_i.bit_length, 1].max unless width.is_a?(Integer)
            return IR::Literal.new(value: binding_value, width: width)
          end
          IR::Signal.new(name: expr.name, width: width_for(expr))
        when RHDL::DSL::BitSelect
          if hir_mode?
            memory_read = lower_hir_memory_read_expr(expr, context_width: context_width)
            return memory_read unless memory_read.nil?
          end

          base = lower_expr(expr.signal)
          index_offset = import_signal_lsb_offset(expr.signal)
          if expr.index.is_a?(Integer)
            adjusted_index = expr.index + index_offset
            IR::Slice.new(base: base, range: adjusted_index..adjusted_index, width: 1)
          else
            lowered_index = lower_expr(expr.index)
            lowered_index = add_import_index_offset(
              lowered_index,
              index_offset,
              context_width: base.width
            )
            shifted = IR::BinaryOp.new(
              op: :>>,
              left: base,
              right: resize(lowered_index, base.width),
              width: base.width
            )
            IR::Slice.new(base: shifted, range: 0..0, width: 1)
          end
        when RHDL::DSL::BitSlice
          base = lower_expr(expr.signal)
          if bit_slice_static?(expr.range)
            bounds = static_range_bounds(expr.range)
            raise ArgumentError, "Invalid static bit slice range: #{expr.range.inspect}" if bounds.nil?

            high, low = bounds
            index_offset = import_signal_lsb_offset(expr.signal)
            high += index_offset
            low += index_offset
            width = high - low + 1
            IR::Slice.new(base: base, range: high..low, width: width)
          elsif hir_mode?
            msb = lower_expr(expr.range.begin)
            lsb = lower_expr(expr.range.end)
            width = context_width || dynamic_range_width(expr.range) || width_for(expr)
            IR::DynamicSlice.new(base: base, msb: msb, lsb: lsb, width: width)
          else
            lower_dynamic_bit_slice(base: base, range: expr.range)
          end
        when RHDL::DSL::BinaryOp
          lower_binary(expr)
        when RHDL::DSL::UnaryOp
          operand = lower_expr(expr.operand)
          op = expr.op
          IR::UnaryOp.new(op: op, operand: operand, width: unary_result_width(op: op, operand_width: operand.width))
        when RHDL::DSL::TernaryOp
          condition = lower_expr(expr.condition)
          true_expr = lower_expr(expr.when_true, context_width: context_width)
          false_expr = lower_expr(expr.when_false, context_width: true_expr.width)
          width = [true_expr.width, false_expr.width].max
          IR::Mux.new(
            condition: condition,
            when_true: resize(true_expr, width),
            when_false: resize(false_expr, width),
            width: width
          )
        when RHDL::DSL::CaseSelect
          lower_case_select(expr, context_width: context_width)
        when RHDL::DSL::Concatenation
          parts = expr.signals.map { |part| lower_expr(part) }
          width = parts.sum(&:width)
          IR::Concat.new(parts: parts, width: width)
        when RHDL::DSL::Replication
          part = lower_expr(expr.signal)
          times = literal_integer(expr.times)
          parts = Array.new(times) { part }
          IR::Concat.new(parts: parts, width: part.width * times)
        when RHDL::DSL::Literal
          width = expr.width
          width = context_width if width.nil? && !import_hir_preserve_literal_widths?
          width ||= [expr.value.to_i.bit_length, 1].max
          IR::Literal.new(
            value: expr.value,
            width: width,
            base: expr.base,
            signed: expr.signed
          )
        when Integer
          width = if import_hir_preserve_literal_widths?
            [expr.bit_length, 1].max
          else
            context_width || [expr.bit_length, 1].max
          end
          IR::Literal.new(value: expr, width: width)
        when Symbol
          binding_value = @loop_bindings[expr.to_sym]
          unless binding_value.nil?
            width = if import_hir_preserve_literal_widths?
              [binding_value.to_i.bit_length, 1].max
            else
              context_width || [binding_value.to_i.bit_length, 1].max
            end
            return IR::Literal.new(value: binding_value, width: width)
          end
          width = @widths.fetch(expr, 1)
          IR::Signal.new(name: expr, width: width)
        when RHDL::DSL::Behavior::BehaviorMemoryRead
          addr = lower_expr(expr.addr)
          IR::MemoryRead.new(memory: expr.memory_name, addr: addr, width: expr.width)
        else
          raise ArgumentError, "Unsupported expression: #{expr.inspect}"
        end
      end

      def lower_hir_memory_read_expr(expr, context_width:)
        return nil unless hir_dynamic_bitselect?(expr)

        base_name = signal_name(expr.signal)
        return nil if base_name.nil?
        return nil unless hir_memory_candidate_name?(base_name) || hir_memory_bitselect_candidate?(expr)

        candidate_width = hir_memory_word_width_for(base_name, fallback: context_width)
        return nil unless candidate_width.is_a?(Integer) && candidate_width > 1

        addr_expr = lower_expr(expr.index)
        register_hir_memory_candidate(
          name: base_name,
          word_width: candidate_width,
          addr_width: addr_expr.width
        )
        IR::MemoryRead.new(memory: base_name, addr: addr_expr, width: candidate_width)
      end

      def lower_case_select(expr, context_width:)
        selector = lower_expr(expr.selector)
        lowered_cases = {}
        candidate_widths = []

        expr.cases.each do |raw_values, branch_expr|
          values = normalize_case_values(raw_values)
          next if values.empty?

          lowered_branch = lower_expr(branch_expr, context_width: context_width)
          lowered_cases[values] = lowered_branch
          candidate_widths << lowered_branch.width
        end

        lowered_default = lower_expr(expr.default_expr, context_width: context_width)
        candidate_widths << lowered_default.width
        width = candidate_widths.max || selector.width

        widened_cases = lowered_cases.each_with_object({}) do |(values, branch_expr), memo|
          memo[values] = resize(branch_expr, width)
        end

        IR::Case.new(
          selector: selector,
          cases: widened_cases,
          default: resize(lowered_default, width),
          width: width
        )
      end

      def normalize_case_values(raw_values)
        Array(raw_values).filter_map do |value|
          case value
          when Integer
            value
          when RHDL::DSL::Literal
            value.value.to_i
          else
            if value.respond_to?(:to_i) && value.to_s.match?(/\A-?\d+\z/)
              value.to_i
            else
              nil
            end
          end
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
        when :-, :&, :|, :^
          aligned = align_operands(left, right)
          width = aligned.map(&:width).max
          left = resize(aligned[0], width)
          right = resize(aligned[1], width)
          IR::BinaryOp.new(op: op, left: left, right: right, width: width)
        when :<<, :>>
          # Preserve shift shape by keeping the data operand width as the result width.
          # Widening the left side to match a wide shift amount literal introduces
          # synthetic zero-extension concat trees that break structural AST parity.
          width = left.width
          IR::BinaryOp.new(op: op, left: left, right: right, width: width)
        else
          raise ArgumentError, "Unsupported binary operator: #{op}"
        end
      end

      def comparison_op?(op)
        %i[== != < > <= >=].include?(op)
      end

      def unary_result_width(op:, operand_width:)
        return 1 if op == :! || reduction_unary_operator?(op)

        operand_width
      end

      def reduction_unary_operator?(op)
        %i[& | ^ ~& ~| ~^ ^~ reduce_and reduce_or reduce_xor].include?(op)
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
        width = width_value_to_integer(explicit_width_for(obj))
        return width unless width.nil?

        name = signal_name(obj)
        return 1 if name.nil?

        fallback = @widths.fetch(name.to_sym, 1)
        width_value_to_integer(fallback) || 1
      rescue StandardError
        1
      end

      def explicit_width_for(obj)
        case obj
        when nil
          nil
        when Hash
          width = obj[:width] || obj["width"]
          return width if width.is_a?(Integer)

          signal = obj[:signal] || obj["signal"]
          signal.nil? ? nil : explicit_width_for(signal)
        when Integer
          [obj.bit_length, 1].max
        when Range
          range_width(obj)
        when Symbol, String
          nil
        when RHDL::DSL::SignalRef
          width = obj.width
          return width if width.is_a?(Integer)
          return nil if width.nil?

          explicit_width_for(width)
        when RHDL::DSL::BitSelect
          1
        when RHDL::DSL::BitSlice
          if bit_slice_static?(obj.range)
            bounds = static_range_bounds(obj.range)
            return width_for(obj.signal) if bounds.nil?

            high, low = bounds
            high - low + 1
          else
            dynamic_width = dynamic_range_width(obj.range)
            return dynamic_width unless dynamic_width.nil?

            width_for(obj.signal)
          end
        when RHDL::DSL::Literal
          obj.width || [obj.value.to_i.bit_length, 1].max
        when RHDL::DSL::UnaryOp
          operand_width = width_for(obj.operand)
          unary_result_width(op: obj.op, operand_width: operand_width)
        when RHDL::DSL::BinaryOp
          left_width = width_for(obj.left)
          right_width = width_for(obj.right)
          op = obj.op
          return 1 if comparison_op?(op)

          case op
          when :+
            [left_width, right_width].max + 1
          when :-, :&, :|, :^
            [left_width, right_width].max
          when :<<, :>>
            left_width
          else
            [left_width, right_width].max
          end
        when RHDL::DSL::TernaryOp
          [width_for(obj.when_true), width_for(obj.when_false)].max
        when RHDL::DSL::Concatenation
          obj.signals.map { |part| width_for(part) }.sum
        when RHDL::DSL::Replication
          width_for(obj.signal) * literal_integer(obj.times)
        when RHDL::DSL::CaseSelect
          branch_widths = obj.cases.values.map { |expr| width_for(expr) }
          branch_widths << width_for(obj.default_expr)
          branch_widths.max || 1
        when RHDL::DSL::Behavior::BehaviorMemoryRead
          obj.width
        else
          obj.respond_to?(:width) ? obj.width : nil
        end
      end

      def width_value_to_integer(value)
        case value
        when Integer
          value
        when Range
          range_width(value)
        else
          nil
        end
      end

      def range_width(range)
        return nil unless range.begin.is_a?(Integer) && range.end.is_a?(Integer)

        (range.begin - range.end).abs + 1
      end

      def sensitivity_signal_name(entry)
        case entry
        when Hash
          signal = entry[:signal] || entry["signal"]
          return nil if signal.nil?
          signal_token = signal_name(signal)
          return nil if signal_token.nil?

          edge = (entry[:edge] || entry["edge"]).to_s.strip
          return signal_token if edge.empty? || edge == "level" || edge == "any"

          "#{edge} #{signal_token}"
        else
          signal_name(entry)
        end
      rescue StandardError
        nil
      end

      def imported_declaration_kinds
        @imported_declaration_kinds ||= begin
          unless @component_class.respond_to?(:_import_decl_kinds)
            {}
          else
            raw = @component_class._import_decl_kinds
            hash = raw.is_a?(Hash) ? raw : {}
            hash.each_with_object({}) do |(name, kind), memo|
              next if name.nil? || kind.nil?

              memo[name.to_sym] = kind.to_sym
            end
          end
        end
      end

      def imported_component?
        @component_class.respond_to?(:_import_decl_kinds)
      end

      def import_hir_preserve_literal_widths?
        hir_mode? && imported_component?
      end

      def assignment_mode_for(stmt, default:)
        return default unless stmt.respond_to?(:kind)

        case stmt.kind
        when :nonblocking then true
        when :blocking then false
        else default
        end
      end

      def indexed_target?(target)
        target.is_a?(RHDL::DSL::BitSelect) || target.is_a?(RHDL::DSL::BitSlice)
      end

      def lower_indexed_assignment(stmt, nonblocking:)
        target = stmt.target
        case target
        when RHDL::DSL::BitSelect
          lower_bit_select_assignment(target: target, value: stmt.value, nonblocking: nonblocking)
        when RHDL::DSL::BitSlice
          lower_bit_slice_assignment(target: target, value: stmt.value, nonblocking: nonblocking)
        else
          nil
        end
      end

      def lower_bit_select_assignment(target:, value:, nonblocking:)
        base = target.signal
        base_name = signal_name(base)
        base_width = width_for(base)

        index_expr = lower_expr(target.index)
        index_expr = resize(index_expr, base_width)

        value_expr = lower_expr(value, context_width: 1)
        value_expr = resize(value_expr, base_width)

        base_signal = IR::Signal.new(name: base_name, width: base_width)
        one = IR::Literal.new(value: 1, width: base_width)
        bit_mask = IR::BinaryOp.new(op: :<<, left: one, right: index_expr, width: base_width)
        clear_mask = IR::UnaryOp.new(op: :~, operand: bit_mask, width: base_width)
        cleared = IR::BinaryOp.new(op: :&, left: base_signal, right: clear_mask, width: base_width)

        value_bit = IR::BinaryOp.new(
          op: :&,
          left: value_expr,
          right: one,
          width: base_width
        )
        shifted_value = IR::BinaryOp.new(op: :<<, left: value_bit, right: index_expr, width: base_width)
        merged = IR::BinaryOp.new(op: :|, left: cleared, right: shifted_value, width: base_width)

        IR::SeqAssign.new(target: base_name, expr: merged, nonblocking: nonblocking)
      end

      def lower_bit_slice_assignment(target:, value:, nonblocking:)
        range = target.range
        base = target.signal
        base_name = signal_name(base)
        base_width = width_for(base)
        if memory_like_word_slice_target?(base: base, range: range)
          return lower_memory_word_slice_assignment(
            base_select: base,
            range: range,
            value: value,
            nonblocking: nonblocking
          )
        end

        if bit_slice_static?(range)
          bounds = static_range_bounds(range)
          return lower_dynamic_bit_slice_assignment(
            base_name: base_name,
            base_width: base_width,
            range: range,
            value: value,
            nonblocking: nonblocking
          ) if bounds.nil?

          high, low = bounds
          slice_width = high - low + 1

          base_signal = IR::Signal.new(name: base_name, width: base_width)
          shift_amount = IR::Literal.new(value: low, width: base_width)
          slice_mask_value = ((1 << slice_width) - 1) << low
          full_mask_value = (1 << base_width) - 1
          keep_mask = IR::Literal.new(value: full_mask_value ^ slice_mask_value, width: base_width)
          update_mask = IR::Literal.new(value: slice_mask_value, width: base_width)

          cleared = IR::BinaryOp.new(op: :&, left: base_signal, right: keep_mask, width: base_width)
          value_expr = lower_expr(value, context_width: slice_width)
          value_expr = resize(value_expr, base_width)
          shifted = IR::BinaryOp.new(op: :<<, left: value_expr, right: shift_amount, width: base_width)
          masked = IR::BinaryOp.new(op: :&, left: shifted, right: update_mask, width: base_width)
          merged = IR::BinaryOp.new(op: :|, left: cleared, right: masked, width: base_width)

          return IR::SeqAssign.new(target: base_name, expr: merged, nonblocking: nonblocking)
        end

        lower_dynamic_bit_slice_assignment(
          base_name: base_name,
          base_width: base_width,
          range: range,
          value: value,
          nonblocking: nonblocking
        )
      end

      def memory_like_word_slice_target?(base:, range:)
        return false unless base.is_a?(RHDL::DSL::BitSelect)
        return false unless bit_slice_static?(range)

        memory_name = signal_name(base.signal)
        return false if memory_name.nil?

        word_width = width_for(base.signal)
        return false unless word_width.is_a?(Integer) && word_width > 1

        true
      rescue StandardError
        false
      end

      def lower_memory_word_slice_assignment(base_select:, range:, value:, nonblocking:)
        memory_name = signal_name(base_select.signal)
        word_width = width_for(base_select.signal)
        bounds = static_range_bounds(range)
        if memory_name.nil? || !word_width.is_a?(Integer) || word_width <= 1 || bounds.nil?
          return lower_bit_select_assignment(target: base_select, value: value, nonblocking: nonblocking)
        end

        addr_width = width_for(base_select.index)
        addr_width = 1 unless addr_width.is_a?(Integer) && addr_width.positive?

        addr_expr = lower_expr(base_select.index, context_width: addr_width)
        addr_expr = resize(addr_expr, addr_width)
        current_word = IR::MemoryRead.new(memory: memory_name, addr: addr_expr, width: word_width)

        high, low = bounds
        slice_width = high - low + 1
        shift_amount = IR::Literal.new(value: low, width: word_width)
        slice_mask_value = ((1 << slice_width) - 1) << low
        full_mask_value = (1 << word_width) - 1
        keep_mask = IR::Literal.new(value: full_mask_value ^ slice_mask_value, width: word_width)
        update_mask = IR::Literal.new(value: slice_mask_value, width: word_width)

        cleared = IR::BinaryOp.new(op: :&, left: current_word, right: keep_mask, width: word_width)
        value_expr = lower_expr(value, context_width: slice_width)
        value_expr = resize(value_expr, word_width)
        shifted = IR::BinaryOp.new(op: :<<, left: value_expr, right: shift_amount, width: word_width)
        masked = IR::BinaryOp.new(op: :&, left: shifted, right: update_mask, width: word_width)
        merged = IR::BinaryOp.new(op: :|, left: cleared, right: masked, width: word_width)

        IR::MemoryWrite.new(memory: memory_name, addr: addr_expr, data: merged)
      end

      def seqassign_target_name(target)
        case target
        when Symbol
          target
        when String
          text = target.strip
          text.empty? ? nil : text.to_sym
        when RHDL::DSL::BitSelect, RHDL::DSL::BitSlice
          signal_name(target.signal)&.to_sym
        when RHDL::DSL::SignalRef
          target.name.to_sym
        when IR::Signal
          target.name.to_sym
        else
          name = signal_name(target)
          name.nil? ? nil : name.to_sym
        end
      rescue StandardError
        nil
      end

      def bit_slice_static?(range)
        !static_range_bounds(range).nil?
      end

      def import_signal_lsb_offset(signal_ref)
        return 0 unless imported_component?

        name = signal_name(signal_ref)
        return 0 if name.nil?

        width = @widths[name.to_sym]
        return 0 unless width.is_a?(Range)
        return 0 unless width.begin.is_a?(Integer) && width.end.is_a?(Integer)

        [width.begin, width.end].min
      rescue StandardError
        0
      end

      def add_import_index_offset(index_expr, offset, context_width:)
        return index_expr if offset.zero?

        if index_expr.is_a?(IR::Literal)
          adjusted_value = index_expr.value.to_i + offset
          return IR::Literal.new(
            value: adjusted_value,
            width: index_expr.width,
            base: index_expr.base,
            signed: index_expr.signed
          )
        end

        add_width = [index_expr.width, context_width, [offset.bit_length, 1].max].compact.max
        IR::BinaryOp.new(
          op: :+,
          left: resize(index_expr, add_width),
          right: IR::Literal.new(value: offset, width: add_width),
          width: add_width
        )
      end

      def static_range_bounds(range)
        return nil unless range.is_a?(Range)

        first = constant_integer(range.begin)
        last = constant_integer(range.end)
        return nil if first.nil? || last.nil?

        [[first, last].max, [first, last].min]
      end

      def dynamic_range_width(range)
        return nil unless range.is_a?(Range)

        static_bounds = static_range_bounds(range)
        unless static_bounds.nil?
          high, low = static_bounds
          return high - low + 1
        end

        up_delta = expression_constant_offset(upper: range.begin, lower: range.end)
        return up_delta + 1 if up_delta && up_delta >= 0

        down_delta = expression_constant_offset(upper: range.end, lower: range.begin)
        return down_delta + 1 if down_delta && down_delta >= 0

        nil
      end

      def expression_constant_offset(upper:, lower:)
        return 0 if dsl_expr_equal?(upper, lower)

        upper_hash = expression_hash(upper)
        if upper_hash && expression_hash_value(upper_hash, :kind).to_s == "binary"
          op = expression_hash_value(upper_hash, :op) || expression_hash_value(upper_hash, :operator)
          left = expression_hash_value(upper_hash, :left)
          right = expression_hash_value(upper_hash, :right)

          case op&.to_s
          when "+"
            right_literal = constant_integer(right)
            return right_literal if right_literal && dsl_expr_equal?(left, lower)

            left_literal = constant_integer(left)
            return left_literal if left_literal && dsl_expr_equal?(right, lower)
          when "-"
            right_literal = constant_integer(right)
            return right_literal if right_literal && dsl_expr_equal?(left, lower)
          end
        elsif upper.is_a?(RHDL::DSL::BinaryOp)
          case upper.op
          when :+
            right_literal = constant_integer(upper.right)
            return right_literal if right_literal && dsl_expr_equal?(upper.left, lower)

            left_literal = constant_integer(upper.left)
            return left_literal if left_literal && dsl_expr_equal?(upper.right, lower)
          when :-
            right_literal = constant_integer(upper.right)
            return right_literal if right_literal && dsl_expr_equal?(upper.left, lower)
          end
        end

        nil
      end

      def dsl_expr_equal?(left, right)
        left_hash = expression_hash(left)
        right_hash = expression_hash(right)
        if left_hash && right_hash
          return normalize_expression_hash(left_hash) == normalize_expression_hash(right_hash)
        end

        case left
        when Integer
          right.is_a?(Integer) && left == right
        when Symbol
          right.is_a?(Symbol) && left == right
        when String
          right.is_a?(String) && left == right
        when RHDL::DSL::SignalRef
          right.is_a?(RHDL::DSL::SignalRef) && left.name.to_s == right.name.to_s
        when RHDL::DSL::Literal
          right.is_a?(RHDL::DSL::Literal) &&
            left.value == right.value &&
            left.width == right.width &&
            left.base == right.base &&
            left.signed == right.signed
        when RHDL::DSL::UnaryOp
          right.is_a?(RHDL::DSL::UnaryOp) &&
            left.op == right.op &&
            dsl_expr_equal?(left.operand, right.operand)
        when RHDL::DSL::BinaryOp
          right.is_a?(RHDL::DSL::BinaryOp) &&
            left.op == right.op &&
            dsl_expr_equal?(left.left, right.left) &&
            dsl_expr_equal?(left.right, right.right)
        when RHDL::DSL::BitSelect
          right.is_a?(RHDL::DSL::BitSelect) &&
            dsl_expr_equal?(left.signal, right.signal) &&
            dsl_expr_equal?(left.index, right.index)
        when RHDL::DSL::BitSlice
          right.is_a?(RHDL::DSL::BitSlice) &&
            dsl_expr_equal?(left.signal, right.signal) &&
            left.range.is_a?(Range) &&
            right.range.is_a?(Range) &&
            dsl_expr_equal?(left.range.begin, right.range.begin) &&
            dsl_expr_equal?(left.range.end, right.range.end)
        when RHDL::DSL::Concatenation
          right.is_a?(RHDL::DSL::Concatenation) &&
            left.signals.length == right.signals.length &&
            left.signals.zip(right.signals).all? { |l_part, r_part| dsl_expr_equal?(l_part, r_part) }
        when RHDL::DSL::Replication
          right.is_a?(RHDL::DSL::Replication) &&
            dsl_expr_equal?(left.signal, right.signal) &&
            dsl_expr_equal?(left.times, right.times)
        else
          left == right
        end
      end

      def normalize_expression_hash(hash)
        hash.keys.map(&:to_sym).sort_by(&:to_s).each_with_object({}) do |key, memo|
          memo[key] = normalize_expression_value(expression_hash_value(hash, key))
        end
      end

      def normalize_expression_value(value)
        if value.is_a?(Hash)
          normalize_expression_hash(value)
        elsif value.is_a?(Array)
          value.map { |entry| normalize_expression_value(entry) }
        else
          value
        end
      end

      def expression_hash(value)
        value.is_a?(Hash) ? value : nil
      end

      def expression_hash_value(hash, key)
        return nil unless hash.is_a?(Hash)

        return hash[key] if hash.key?(key)

        key_string = key.to_s
        return hash[key_string] if hash.key?(key_string)

        key_symbol = key.to_sym
        return hash[key_symbol] if hash.key?(key_symbol)

        nil
      end

      def lower_dynamic_bit_slice_assignment(base_name:, base_width:, range:, value:, nonblocking:)
        base_signal = IR::Signal.new(name: base_name, width: base_width)

        left = lower_expr(range.begin)
        right = lower_expr(range.end)
        compare_width = [left.width, right.width].max
        left_cmp = resize(left, compare_width)
        right_cmp = resize(right, compare_width)
        left_ge_right = IR::BinaryOp.new(op: :>=, left: left_cmp, right: right_cmp, width: 1)

        lower_bound = IR::Mux.new(
          condition: left_ge_right,
          when_true: right_cmp,
          when_false: left_cmp,
          width: compare_width
        )
        upper_bound = IR::Mux.new(
          condition: left_ge_right,
          when_true: left_cmp,
          when_false: right_cmp,
          width: compare_width
        )

        span_width = compare_width + 1
        dynamic_width = IR::BinaryOp.new(
          op: :+,
          left: IR::BinaryOp.new(
            op: :-,
            left: resize(upper_bound, span_width),
            right: resize(lower_bound, span_width),
            width: span_width
          ),
          right: IR::Literal.new(value: 1, width: span_width),
          width: span_width
        )

        one = IR::Literal.new(value: 1, width: base_width)
        all_ones = IR::Literal.new(value: (1 << base_width) - 1, width: base_width)
        lower_bound_base = resize(lower_bound, base_width)
        dynamic_width_base = resize(dynamic_width, base_width)

        width_mask = IR::BinaryOp.new(
          op: :-,
          left: IR::BinaryOp.new(
            op: :<<,
            left: one,
            right: dynamic_width_base,
            width: base_width
          ),
          right: one,
          width: base_width
        )
        update_mask = IR::BinaryOp.new(
          op: :&,
          left: IR::BinaryOp.new(
            op: :<<,
            left: width_mask,
            right: lower_bound_base,
            width: base_width
          ),
          right: all_ones,
          width: base_width
        )
        keep_mask = IR::UnaryOp.new(op: :~, operand: update_mask, width: base_width)

        cleared = IR::BinaryOp.new(op: :&, left: base_signal, right: keep_mask, width: base_width)
        value_expr = lower_expr(value, context_width: base_width)
        value_expr = resize(value_expr, base_width)
        shifted = IR::BinaryOp.new(op: :<<, left: value_expr, right: lower_bound_base, width: base_width)
        masked = IR::BinaryOp.new(op: :&, left: shifted, right: update_mask, width: base_width)
        merged = IR::BinaryOp.new(op: :|, left: cleared, right: masked, width: base_width)

        IR::SeqAssign.new(target: base_name, expr: merged, nonblocking: nonblocking)
      end

      def lower_dynamic_bit_slice(base:, range:)
        left = lower_expr(range.begin)
        right = lower_expr(range.end)
        compare_width = [left.width, right.width].max
        left_cmp = resize(left, compare_width)
        right_cmp = resize(right, compare_width)
        left_ge_right = IR::BinaryOp.new(op: :>=, left: left_cmp, right: right_cmp, width: 1)

        lower_bound = IR::Mux.new(
          condition: left_ge_right,
          when_true: right_cmp,
          when_false: left_cmp,
          width: compare_width
        )
        upper_bound = IR::Mux.new(
          condition: left_ge_right,
          when_true: left_cmp,
          when_false: right_cmp,
          width: compare_width
        )

        span_width = compare_width + 1
        width_expr = IR::BinaryOp.new(
          op: :+,
          left: IR::BinaryOp.new(
            op: :-,
            left: resize(upper_bound, span_width),
            right: resize(lower_bound, span_width),
            width: span_width
          ),
          right: IR::Literal.new(value: 1, width: span_width),
          width: span_width
        )
        mask_expr = IR::BinaryOp.new(
          op: :-,
          left: IR::BinaryOp.new(
            op: :<<,
            left: IR::Literal.new(value: 1, width: base.width),
            right: resize(width_expr, base.width),
            width: base.width
          ),
          right: IR::Literal.new(value: 1, width: base.width),
          width: base.width
        )
        shifted = IR::BinaryOp.new(op: :>>, left: base, right: resize(lower_bound, base.width), width: base.width)
        IR::BinaryOp.new(op: :&, left: shifted, right: mask_expr, width: base.width)
      end

      def instance_driven_signal_targets
        targets = Set.new
        return targets unless @component_class.respond_to?(:_instances)

        @component_class._instances.each do |instance|
          port_directions = instance_port_directions(instance)
          next if port_directions.empty?

          port_map = resolved_instance_port_map(instance, port_directions: port_directions)
          port_map.each do |port_name, signal|
            direction = port_directions.fetch(port_name.to_sym, :in)
            next unless direction == :out || direction == :inout

            target_name = instance_connection_target_name(signal)
            targets << target_name unless target_name.nil?
          end
        end

        targets
      end

      def resolved_instance_port_map(instance, port_directions:)
        explicit = normalize_instance_port_map(instance.port_map)
        return explicit if port_directions.empty?

        available = implicit_instance_connection_names
        port_directions.each_key do |port_name|
          next if explicit.key?(port_name)
          next unless available.include?(port_name.to_sym)

          explicit[port_name] = port_name.to_sym
        end

        explicit
      end

      def normalize_instance_port_map(port_map)
        case port_map
        when Hash
          port_map.each_with_object({}) do |(port_name, signal), memo|
            next if port_name.to_s.strip.empty?

            normalized_signal = case signal
                               when nil
                                 nil
                               when String
                                 signal.strip
                               else
                                 signal
                               end
            next if normalized_signal.nil?

            memo[port_name.to_sym] = normalized_signal
          end
        else
          {}
        end
      end

      def implicit_instance_connection_names
        @implicit_instance_connection_names ||= begin
          names = []
          names.concat(Array(@component_class._ports).map(&:name)) if @component_class.respond_to?(:_ports)
          names.concat(Array(@component_class._signals).map(&:name)) if @component_class.respond_to?(:_signals)
          names.each_with_object(Set.new) { |name, memo| memo << name.to_sym }
        end
      end

      def instance_connection_target_name(signal)
        return nil if signal == :__rhdl_unconnected
        case signal
        when Symbol
          signal.to_sym
        when String
          token = signal.strip
          token.empty? ? nil : token.to_sym
        when RHDL::DSL::SignalRef
          signal.name.to_sym
        else
          nil
        end
      end

      def instance_port_directions(instance)
        component_class = resolve_instance_component_class(instance.component_type)
        return {} unless component_class&.respond_to?(:_ports)

        Array(component_class._ports).each_with_object({}) do |port, memo|
          memo[port.name.to_sym] = normalize_port_direction(port.direction)
        end
      end

      def normalize_port_direction(direction)
        case direction.to_s
        when "in", "input"
          :in
        when "out", "output"
          :out
        when "inout"
          :inout
        else
          :in
        end
      end

      def resolve_instance_component_class(component_type)
        return component_type if component_type.is_a?(Class) && component_type.respond_to?(:_ports)

        module_name = component_type.to_s.strip
        return nil if module_name.empty?

        lookup_candidates_for_module_name(module_name).each do |candidate|
          klass = constant_lookup(candidate)
          return klass if klass&.respond_to?(:_ports)
        end

        normalized_candidates = instance_component_name_candidates(module_name).to_set
        ObjectSpace.each_object(Class) do |klass|
          next unless klass.respond_to?(:_ports)
          next if klass.name.to_s.empty?

          next if normalized_candidates.none? { |candidate| component_module_name_matches?(klass, candidate) }

          return klass
        end

        nil
      end

      def lookup_candidates_for_module_name(module_name)
        candidates = [module_name]

        simple_token = module_name.split("::").last
        camelized = simple_token.to_s.split("_").reject(&:empty?).map { |segment| segment[0].to_s.upcase + segment[1..].to_s }.join
        unless camelized.to_s.empty?
          candidates << camelized
          candidates << "Imported#{camelized}"
        end

        candidates.uniq
      end

      def instance_component_name_candidates(module_name)
        simple_token = module_name.to_s.split("::").last.to_s
        underscored = simple_token.gsub(/-/, "_").underscore
        camelized = simple_token.to_s.split("_").reject(&:empty?).map { |segment| segment[0].to_s.upcase + segment[1..].to_s }.join

        candidates = [simple_token, underscored, camelized]
        unless underscored.start_with?("imported_")
          candidates << "imported_#{underscored}"
        end
        unless camelized.start_with?("Imported")
          candidates << "Imported#{camelized}"
          candidates << "imported#{camelized}"
        end

        candidates.compact.map(&:to_s).map(&:strip).map(&:downcase).reject(&:empty?).uniq
      end

      def component_module_name_matches?(klass, candidate)
        candidate_token = candidate.to_s.downcase
        class_name = klass.name.to_s.split("::").last.to_s
        class_names = Set.new
        class_names << class_name
        class_names << class_name.underscore
        class_names << class_name.sub(/^Imported/, "")
        class_names << class_name.sub(/^Imported/, "").underscore
        class_names << class_name.sub(/^imported_/, "")
        class_names.compact
          .map(&:to_s)
          .map(&:strip)
          .map(&:downcase)
          .select { |value| !value.empty? }
          .any? { |name| name == candidate_token }
      end

      def constant_lookup(name)
        tokens = name.to_s.split("::").reject(&:empty?)
        return nil if tokens.empty?

        tokens.inject(Object) { |scope, token| scope.const_get(token) }
      rescue NameError
        nil
      end

      def component_module_name(klass)
        if klass.respond_to?(:source_module_name)
          source_name = klass.source_module_name.to_s
          return source_name unless source_name.empty?
        end

        if klass.respond_to?(:verilog_module_name)
          verilog_name = klass.verilog_module_name.to_s
          return verilog_name unless verilog_name.empty?
        end

        klass.name.to_s.split("::").last.to_s.underscore
      end

      def normalize_instance_signal(signal)
        return :__rhdl_unconnected if signal.to_s.empty?

        case signal
        when Symbol
          signal.to_s
        when String
          signal
        when RHDL::DSL::SignalRef,
             RHDL::DSL::BitSelect,
             RHDL::DSL::BitSlice,
             RHDL::DSL::BinaryOp,
             RHDL::DSL::UnaryOp,
             RHDL::DSL::TernaryOp,
             RHDL::DSL::Concatenation,
             RHDL::DSL::Replication,
             RHDL::DSL::Literal,
             Integer
          lower_expr(signal)
        else
          signal.to_s
        end
      end

      def literal_integer(value)
        folded = constant_integer(value)
        return folded unless folded.nil?

        Integer(value.to_s)
      rescue ArgumentError, TypeError
        1
      end

      def constant_integer(value)
        case value
        when Integer
          value
        when String
          Integer(value.strip)
        when RHDL::DSL::Literal
          value.value.to_i
        when RHDL::DSL::UnaryOp
          operand = constant_integer(value.operand)
          return nil if operand.nil?

          case value.op
          when :+ then operand
          when :- then -operand
          when :~ then ~operand
          else nil
          end
        when RHDL::DSL::BinaryOp
          left = constant_integer(value.left)
          right = constant_integer(value.right)
          return nil if left.nil? || right.nil?

          case value.op
          when :+ then left + right
          when :- then left - right
          when :* then left * right
          when :/ then right.zero? ? nil : (left / right)
          when :% then right.zero? ? nil : (left % right)
          when :<< then left << right
          when :>> then left >> right
          when :& then left & right
          when :| then left | right
          when :^ then left ^ right
          else nil
          end
        else
          nil
        end
      rescue ArgumentError, TypeError
        nil
      end

      def signal_name(obj)
        if obj.is_a?(Hash)
          signal = obj[:signal] || obj["signal"]
          return signal_name(signal) unless signal.nil?
        end

        case obj
        when nil
          nil
        when Symbol
          obj
        when String
          token = obj.strip
          token.empty? ? nil : token.to_sym
        when RHDL::DSL::SignalRef
          obj.name.to_sym
        when RHDL::DSL::BitSelect, RHDL::DSL::BitSlice
          signal_name(obj.signal)
        else
          extracted = extract_signal_name_from_expression(obj)
          return extracted unless extracted.nil?

          return obj.name.to_sym if obj.respond_to?(:name) && !obj.name.nil?
          return obj.to_sym if obj.respond_to?(:to_sym)

          raise ArgumentError, "Unable to resolve signal name for #{obj.inspect}"
        end
      end

      def extract_signal_name_from_expression(obj)
        case obj
        when Hash
          signal = obj[:signal] || obj["signal"]
          return extract_signal_name_from_expression(signal) unless signal.nil?

          name = obj[:name] || obj["name"]
          return name.to_sym unless name.nil?
          nil
        when Symbol
          obj
        when String
          token = obj.strip
          token.empty? ? nil : token.to_sym
        when RHDL::DSL::SignalRef
          obj.name.to_sym
        when RHDL::DSL::BitSelect, RHDL::DSL::BitSlice
          extract_signal_name_from_expression(obj.signal)
        when RHDL::DSL::UnaryOp
          extract_signal_name_from_expression(obj.operand)
        when RHDL::DSL::BinaryOp
          extract_signal_name_from_expression(obj.left) ||
            extract_signal_name_from_expression(obj.right)
        when RHDL::DSL::TernaryOp
          extract_signal_name_from_expression(obj.when_true) ||
            extract_signal_name_from_expression(obj.when_false) ||
            extract_signal_name_from_expression(obj.condition)
        when RHDL::DSL::Concatenation
          Array(obj.signals).each do |part|
            name = extract_signal_name_from_expression(part)
            return name unless name.nil?
          end
          nil
        when RHDL::DSL::Replication
          extract_signal_name_from_expression(obj.signal)
        else
          nil
        end
      end
    end
  end
  end
end
