# frozen_string_literal: true

require 'json'
require 'set'

module RHDL
  module Codegen
    module CIRCT
      module RuntimeJSON
        module_function

        JSON_I64_MIN = -(1 << 63)
        JSON_I64_MAX = (1 << 63) - 1
        JSON_U64_MAX = (1 << 64) - 1
        MAX_RUNTIME_SIGNAL_WIDTH = 128
        EMPTY_SET = Set.new.freeze

        def dump(nodes_or_package, compact_exprs: false)
          JSON.generate(runtime_payload(nodes_or_package, compact_exprs: compact_exprs), max_nesting: false)
        end

        def dump_to_io(nodes_or_package, io, compact_exprs: false)
          if compact_exprs
            write_compact_runtime_payload(io, nodes_or_package)
          else
            JSON.dump(runtime_payload(nodes_or_package, compact_exprs: compact_exprs), io, false)
          end
          io
        end

        def runtime_payload(nodes_or_package, compact_exprs: false)
          modules = normalized_runtime_modules_from_input(nodes_or_package, compact_exprs: compact_exprs)
          expr_cache = {}
          payload = {
            circt_json_version: 1,
            dialects: %w[hw comb seq],
            modules: modules.map { |mod| serialize_module(mod, expr_cache: expr_cache, compact_exprs: compact_exprs) }
          }
          payload
        end

        def normalized_runtime_modules_from_input(nodes_or_package, compact_exprs: false)
          modules = case nodes_or_package
                    when IR::Package
                      nodes_or_package.modules
                    when Array
                      nodes_or_package
                    else
                      [nodes_or_package]
                    end

          Array(modules).map do |mod|
            assign_map = build_assign_map(mod.assigns)
            inlineable_names = Array(mod.nets).map { |net| net.name.to_s }.to_set
            signal_widths = build_signal_width_map(mod)
            runtime_sensitive_names = runtime_sensitive_signal_names(
              assign_map: assign_map,
              signal_widths: signal_widths
            )
            simplification_needed_cache = {}
            simplification_cache = {}
            live_assign_targets = runtime_live_assign_targets(
              mod,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              runtime_sensitive_names: runtime_sensitive_names,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache
            )

            normalize_module_for_runtime(
              mod,
              live_assign_targets: live_assign_targets,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              signal_widths: signal_widths,
              runtime_sensitive_names: runtime_sensitive_names,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache,
              # Keep shared-expression hoisting opt-in; on large real designs
              # like SPARC64 it makes export materially more expensive.
              hoist_shared_exprs: false
            )
          end
        end

        def normalize_modules_for_runtime(modules)
          Array(modules).map do |mod|
            mod = materialize_clocked_seq_targets(mod)
            assign_map = build_assign_map(mod.assigns)
            inlineable_names = Array(mod.nets).map { |net| net.name.to_s }.to_set
            signal_widths = build_signal_width_map(mod)
            runtime_sensitive_names = runtime_sensitive_signal_names(
              assign_map: assign_map,
              signal_widths: signal_widths
            )
            simplification_needed_cache = {}
            simplification_cache = {}
            live_assign_targets = runtime_live_assign_targets(
              mod,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              runtime_sensitive_names: runtime_sensitive_names,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache
            )

            normalize_module_for_runtime(
              mod,
              live_assign_targets: live_assign_targets,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              signal_widths: signal_widths,
              runtime_sensitive_names: runtime_sensitive_names,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache
            )
          end
        end

        def materialize_clocked_seq_targets(mod)
          reg_names = Array(mod.regs).map { |reg| reg.name.to_s }.to_set
          seq_targets = collect_runtime_seq_targets(Array(mod.processes))
          promoted_targets = seq_targets.reject { |target| reg_names.include?(target) }
          return mod if promoted_targets.empty?

          signal_widths = build_signal_width_map(mod)
          existing_names = Set.new
          Array(mod.ports).each { |port| existing_names << port.name.to_s }
          Array(mod.nets).each { |net| existing_names << net.name.to_s }
          Array(mod.regs).each { |reg| existing_names << reg.name.to_s }
          Array(mod.memories).each { |memory| existing_names << memory.name.to_s }

          backing_names = promoted_targets.each_with_object({}) do |target, acc|
            candidate = "#{target}__seq_reg"
            suffix = 0
            while existing_names.include?(candidate)
              suffix += 1
              candidate = "#{target}__seq_reg_#{suffix}"
            end
            existing_names << candidate
            acc[target] = candidate
          end

          promoted_regs = promoted_targets.map do |target|
            IR::Reg.new(
              name: backing_names.fetch(target),
              width: signal_widths.fetch(target, 1),
              reset_value: nil
            )
          end

          rewritten_assigns = Array(mod.assigns).reject do |assign|
            promoted_targets.include?(assign.target.to_s)
          end
          rewritten_assigns.concat(
            promoted_targets.map do |target|
              IR::Assign.new(
                target: target,
                expr: IR::Signal.new(name: backing_names.fetch(target), width: signal_widths.fetch(target, 1))
              )
            end
          )

          rewritten_processes = Array(mod.processes).map do |process|
            rewrite_runtime_process_seq_targets(process, backing_names)
          end

          IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: mod.nets,
            regs: Array(mod.regs) + promoted_regs,
            assigns: rewritten_assigns,
            processes: rewritten_processes,
            instances: mod.instances,
            memories: mod.memories,
            write_ports: mod.write_ports,
            sync_read_ports: mod.sync_read_ports,
            parameters: mod.parameters || {}
          )
        end

        def collect_runtime_seq_targets(processes, acc = Set.new)
          Array(processes).each do |process|
            collect_runtime_seq_targets_from_statements(Array(process.statements), acc)
          end

          acc
        end

        def collect_runtime_seq_targets_from_statements(statements, acc)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              acc << stmt.target.to_s
            when IR::If
              collect_runtime_seq_targets_from_statements(stmt.then_statements, acc)
              collect_runtime_seq_targets_from_statements(stmt.else_statements, acc)
            end
          end
        end

        def rewrite_runtime_process_seq_targets(process, backing_names)
          return process if backing_names.empty?

          reset_values = if process.reset_values
                           Array(process.reset_values).each_with_object({}) do |(target, value), acc|
                             rewritten_target = backing_names.fetch(target.to_s, target.to_s)
                             acc[rewritten_target.to_sym] = value
                           end
                         end

          IR::Process.new(
            name: process.name,
            statements: rewrite_runtime_seq_target_statements(process.statements, backing_names),
            clocked: process.clocked,
            clock: process.clock,
            sensitivity_list: process.sensitivity_list,
            reset: process.reset,
            reset_active_low: process.reset_active_low,
            reset_values: reset_values
          )
        end

        def rewrite_runtime_seq_target_statements(statements, backing_names)
          Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              target_name = stmt.target.to_s
              rewritten_target = backing_names.fetch(target_name, target_name)
              rewritten_target == target_name ? stmt : IR::SeqAssign.new(target: rewritten_target, expr: stmt.expr)
            when IR::If
              IR::If.new(
                condition: stmt.condition,
                then_statements: rewrite_runtime_seq_target_statements(stmt.then_statements, backing_names),
                else_statements: rewrite_runtime_seq_target_statements(stmt.else_statements, backing_names)
              )
            else
              stmt
            end
          end
        end

        def normalize_module_for_runtime(mod, live_assign_targets: nil, assign_map: nil, inlineable_names: nil,
                                         signal_widths: nil, runtime_sensitive_names: nil, needs_cache: nil,
                                         simplify_cache: nil, hoist_shared_exprs: false)
          mod = materialize_clocked_seq_targets(mod)
          temp_counter = 0
          extra_nets = []
          extra_assigns = []
          inlineable_names ||= Array(mod.nets).map { |net| net.name.to_s }.to_set
          simplification_needed_cache = needs_cache || {}
          simplification_cache = simplify_cache || {}
          assign_map ||= build_assign_map(mod.assigns)
          signal_widths ||= build_signal_width_map(mod)
          runtime_sensitive_names ||= runtime_sensitive_signal_names(
            assign_map: assign_map,
            signal_widths: signal_widths
          )

          assigns_to_normalize = if live_assign_targets
                                   dedupe_assigns_by_target(
                                     Array(mod.assigns).select do |assign|
                                       live_assign_targets.include?(assign.target.to_s)
                                     end
                                   )
                                 else
                                   Array(mod.assigns)
                                 end

          normalized_assigns = assigns_to_normalize.map do |assign|
            target_name = assign.target.to_s
            next assign unless runtime_sensitive_names.include?(target_name)
            next assign if signal_widths[target_name].to_i > MAX_RUNTIME_SIGNAL_WIDTH

            simplified_expr = simplify_runtime_expr_if_needed(
              assign.expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            expr, hoisted_assigns = if hoist_shared_exprs
                                      hoist_shared_exprs_to_assigns(
                                        simplified_expr,
                                        temp_counter: temp_counter,
                                        prefix: "#{target_name}_rt"
                                      )
                                    else
                                      [simplified_expr, []]
                                    end
            temp_counter += hoisted_assigns.length
            hoisted_assigns.each do |hoisted|
              extra_assigns << hoisted[:assign]
              extra_nets << hoisted[:net]
            end
            if hoisted_assigns.empty? && expr.equal?(assign.expr)
              assign
            else
              IR::Assign.new(target: assign.target, expr: expr)
            end
          end

          normalized_processes = mod.processes.map do |process|
            statements, hoisted_assigns, hoisted_nets = normalize_process_statements(
              process.statements,
              temp_counter: temp_counter,
              prefix: "#{process.name}_rt",
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              signal_widths: signal_widths,
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache,
              runtime_sensitive_names: runtime_sensitive_names,
              hoist_shared_exprs: hoist_shared_exprs
            )
            temp_counter += hoisted_assigns.length
            extra_assigns.concat(hoisted_assigns)
            extra_nets.concat(hoisted_nets)
            if hoisted_assigns.empty? && statements == Array(process.statements)
              process
            else
              IR::Process.new(
                name: process.name,
                statements: statements,
                clocked: process.clocked,
                clock: process.clock,
                sensitivity_list: process.sensitivity_list,
                reset: process.reset,
                reset_active_low: process.reset_active_low,
                reset_values: process.reset_values
              )
            end
          end

          normalized_module = IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: dedupe_by_name(mod.nets + extra_nets),
            regs: mod.regs,
            assigns: extra_assigns + normalized_assigns,
            processes: normalized_processes,
            instances: mod.instances,
            memories: mod.memories,
            write_ports: mod.write_ports,
            sync_read_ports: mod.sync_read_ports,
            parameters: mod.parameters || {}
          )

          pruned_module = prune_dead_runtime_assigns_and_signals(
            normalized_module,
            live_assign_targets: live_assign_targets,
            preserve_assign_targets: live_assign_targets
          )
          collapsed_module = collapse_runtime_alias_assigns(pruned_module)
          hoist_shared_exprs ? hoist_module_shared_exprs(collapsed_module) : collapsed_module
        end

        def recursion_cache_key(expr_or_id, expanding)
          expr_id = expr_or_id.is_a?(Integer) ? expr_or_id : expr_or_id.object_id
          return expr_id if expanding.empty?

          [expr_id, expanding]
        end

        def slice_recursion_cache_key(base_expr, low, high, expanding)
          base_key = [base_expr.object_id, low, high]
          return base_key if expanding.empty?

          [base_key, expanding]
        end

        def merge_signal_ref_sets(*sets)
          source_sets = sets.compact.reject(&:empty?)
          return EMPTY_SET if source_sets.empty?

          merged = source_sets.shift.dup
          source_sets.each { |set| merged.merge(set) }
          merged
        end

        def next_expanding_set(expanding, name)
          updated = expanding.dup
          updated << name
          updated.freeze
        end

        def normalize_process_statements(statements, temp_counter:, prefix:, assign_map:, inlineable_names:, needs_cache:,
                                         simplify_cache:, runtime_sensitive_names:, signal_widths: nil,
                                         hoist_shared_exprs: false)
          extra_assigns = []
          extra_nets = []
          signal_widths ||= {}
          normalized = Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              target_name = stmt.target.to_s
              next stmt unless runtime_sensitive_names.include?(target_name)
              next stmt if signal_widths[target_name].to_i > MAX_RUNTIME_SIGNAL_WIDTH

              expr = stmt.expr
              simplified_expr = simplify_runtime_expr_if_needed(
                expr,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )
              expr, hoisted_assigns = if hoist_shared_exprs
                                        hoist_shared_exprs_to_assigns(
                                          simplified_expr,
                                          temp_counter: temp_counter + extra_assigns.length,
                                          prefix: "#{prefix}_#{target_name}"
                                        )
                                      else
                                        [simplified_expr, []]
                                      end
              hoisted_assigns.each do |hoisted|
                extra_assigns << hoisted[:assign]
                extra_nets << hoisted[:net]
              end
              if hoisted_assigns.empty? && expr.equal?(stmt.expr)
                stmt
              else
                IR::SeqAssign.new(target: stmt.target, expr: expr)
              end
            when IR::If
              simplified_condition = simplify_runtime_expr_if_needed(
                stmt.condition,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )
              cond, hoisted_assigns = if simplified_condition.equal?(stmt.condition)
                                        [stmt.condition, []]
                                      elsif !hoist_shared_exprs
                                        [simplified_condition, []]
                                      else
                                        hoist_shared_exprs_to_assigns(
                                          simplified_condition,
                                          temp_counter: temp_counter + extra_assigns.length,
                                          prefix: "#{prefix}_if"
                                        )
                                      end
              hoisted_assigns.each do |hoisted|
                extra_assigns << hoisted[:assign]
                extra_nets << hoisted[:net]
              end
              then_stmts, then_assigns, then_nets = normalize_process_statements(
                stmt.then_statements,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_then",
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                signal_widths: signal_widths,
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names,
                hoist_shared_exprs: hoist_shared_exprs
              )
              else_stmts, else_assigns, else_nets = normalize_process_statements(
                stmt.else_statements,
                temp_counter: temp_counter + extra_assigns.length + then_assigns.length,
                prefix: "#{prefix}_else",
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                signal_widths: signal_widths,
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names,
                hoist_shared_exprs: hoist_shared_exprs
              )
              extra_assigns.concat(then_assigns)
              extra_assigns.concat(else_assigns)
              extra_nets.concat(then_nets)
              extra_nets.concat(else_nets)
              if hoisted_assigns.empty? &&
                 then_assigns.empty? &&
                 else_assigns.empty? &&
                 cond.equal?(stmt.condition) &&
                 then_stmts == Array(stmt.then_statements) &&
                 else_stmts == Array(stmt.else_statements)
                stmt
              else
                IR::If.new(condition: cond, then_statements: then_stmts, else_statements: else_stmts)
              end
            else
              stmt
            end
          end

          [normalized, extra_assigns, extra_nets]
        end

        def simplify_runtime_expr_if_needed(expr, assign_map:, inlineable_names:, needs_cache:, simplify_cache:,
                                            runtime_sensitive_names:)
          return expr unless needs_runtime_simplification?(
            expr,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )

          simplify_expr_for_runtime(
            expr,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            cache: simplify_cache,
            needs_cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )
        end

        def runtime_simplified_signal_refs(expr, assign_map:, inlineable_names:, runtime_sensitive_names:,
                                           needs_cache:, cache:, raw_cache:, expanding: EMPTY_SET)
          return EMPTY_SET if expr.nil? || expr.is_a?(IR::Literal)
          unless needs_runtime_simplification?(
            expr,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )
            return signal_refs_from_expr(expr, cache: raw_cache)
          end

          cache_key = recursion_cache_key(expr, expanding)
          return cache[cache_key] if cache_key && cache.key?(cache_key)

          refs = case expr
                 when IR::Signal
                   runtime_simplified_signal_refs_for_signal(
                     expr,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 when IR::UnaryOp
                   runtime_simplified_signal_refs(
                     expr.operand,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 when IR::BinaryOp
                   merge_signal_ref_sets(
                     runtime_simplified_signal_refs(
                       expr.left,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ),
                     runtime_simplified_signal_refs(
                       expr.right,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     )
                   )
                 when IR::Mux
                   merge_signal_ref_sets(
                     runtime_simplified_signal_refs(
                       expr.condition,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ),
                     runtime_simplified_signal_refs(
                       expr.when_true,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ),
                     runtime_simplified_signal_refs(
                       expr.when_false,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     )
                   )
                 when IR::Slice
                   low, high = normalized_slice_bounds(expr.range)
                   runtime_simplified_slice_signal_refs(
                     expr.base,
                     low: low,
                     high: high,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 when IR::Concat
                   Array(expr.parts).each_with_object(Set.new) do |part, acc|
                     acc.merge(
                       runtime_simplified_signal_refs(
                         part,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         runtime_sensitive_names: runtime_sensitive_names,
                         needs_cache: needs_cache,
                         cache: cache,
                         raw_cache: raw_cache,
                         expanding: expanding
                       )
                     )
                   end
                 when IR::Resize
                   runtime_simplified_signal_refs(
                     expr.expr,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 when IR::Case
                   refs = runtime_simplified_signal_refs(
                     expr.selector,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   ).dup
                   expr.cases.each_value do |value|
                     refs.merge(
                       runtime_simplified_signal_refs(
                         value,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         runtime_sensitive_names: runtime_sensitive_names,
                         needs_cache: needs_cache,
                         cache: cache,
                         raw_cache: raw_cache,
                         expanding: expanding
                       )
                     )
                   end
                   refs.merge(
                     runtime_simplified_signal_refs(
                       expr.default,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     )
                   )
                 when IR::MemoryRead
                   runtime_simplified_signal_refs(
                     expr.addr,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 else
                   signal_refs_from_expr(expr, cache: raw_cache)
                 end

          refs = refs.frozen? ? refs : refs.freeze
          cache[cache_key] = refs if cache_key
          refs
        end

        def runtime_simplified_signal_refs_for_signal(expr, assign_map:, inlineable_names:, runtime_sensitive_names:,
                                                      needs_cache:, cache:, raw_cache:, expanding:)
          name = expr.name.to_s
          unless runtime_signal_should_inline?(
            name,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            runtime_sensitive_names: runtime_sensitive_names,
            expanding: expanding
          )
            return Set[name].freeze
          end

          next_expanding = next_expanding_set(expanding, name)
          runtime_simplified_signal_refs(
            assign_map[name],
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            runtime_sensitive_names: runtime_sensitive_names,
            needs_cache: needs_cache,
            cache: cache,
            raw_cache: raw_cache,
            expanding: next_expanding
          )
        end

        def runtime_simplified_slice_signal_refs(base_expr, low:, high:, assign_map:, inlineable_names:,
                                                 runtime_sensitive_names:, needs_cache:, cache:, raw_cache:,
                                                 expanding:)
          return EMPTY_SET if base_expr.nil? || low > high

          slice_cache_key = slice_recursion_cache_key(base_expr, low, high, expanding)
          return cache[slice_cache_key] if slice_cache_key && cache.key?(slice_cache_key)

          refs = case base_expr
                 when IR::Literal
                   EMPTY_SET
                 when IR::Signal
                   name = base_expr.name.to_s
                   if runtime_signal_should_inline?(
                     name,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     expanding: expanding
                   )
                     next_expanding = next_expanding_set(expanding, name)
                     runtime_simplified_slice_signal_refs(
                       assign_map[name],
                       low: low,
                       high: high,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: next_expanding
                     )
                   else
                     Set[name].freeze
                   end
                 when IR::Slice
                   base_low, = normalized_slice_bounds(base_expr.range)
                   runtime_simplified_slice_signal_refs(
                     base_expr.base,
                     low: base_low + low,
                     high: base_low + high,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 when IR::Mux
                   merge_signal_ref_sets(
                     runtime_simplified_signal_refs(
                       base_expr.condition,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ),
                     runtime_simplified_slice_signal_refs(
                       base_expr.when_true,
                       low: low,
                       high: high,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ),
                     runtime_simplified_slice_signal_refs(
                       base_expr.when_false,
                       low: low,
                       high: high,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     )
                   )
                 when IR::Concat
                   total_width = Array(base_expr.parts).sum { |part| part.width.to_i }
                   cursor = total_width - 1
                   Array(base_expr.parts).each_with_object(Set.new) do |part, acc|
                     part_width = part.width.to_i
                     part_low = cursor - part_width + 1
                     part_high = cursor
                     overlap_low = [low, part_low].max
                     overlap_high = [high, part_high].min

                     if overlap_low <= overlap_high
                       inner_low = overlap_low - part_low
                       inner_high = overlap_high - part_low
                       part_refs = if inner_low.zero? && inner_high == (part_width - 1)
                                     runtime_simplified_signal_refs(
                                       part,
                                       assign_map: assign_map,
                                       inlineable_names: inlineable_names,
                                       runtime_sensitive_names: runtime_sensitive_names,
                                       needs_cache: needs_cache,
                                       cache: cache,
                                       raw_cache: raw_cache,
                                       expanding: expanding
                                     )
                                   else
                                     runtime_simplified_slice_signal_refs(
                                       part,
                                       low: inner_low,
                                       high: inner_high,
                                       assign_map: assign_map,
                                       inlineable_names: inlineable_names,
                                       runtime_sensitive_names: runtime_sensitive_names,
                                       needs_cache: needs_cache,
                                       cache: cache,
                                       raw_cache: raw_cache,
                                       expanding: expanding
                                     )
                                   end
                       acc.merge(part_refs)
                     end

                     cursor = part_low - 1
                   end
                 when IR::Resize
                   inner_width = base_expr.expr.width.to_i
                   if low >= inner_width
                     EMPTY_SET
                   else
                     runtime_simplified_slice_signal_refs(
                       base_expr.expr,
                       low: low,
                       high: [high, inner_width - 1].min,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     )
                   end
                 else
                   runtime_simplified_signal_refs(
                     base_expr,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   )
                 end

          refs = refs.frozen? ? refs : refs.freeze
          cache[slice_cache_key] = refs if slice_cache_key
          refs
        end

        def runtime_signal_should_inline?(name, assign_map:, inlineable_names:, runtime_sensitive_names:, expanding:)
          runtime_sensitive_names.include?(name) &&
            inlineable_names.include?(name) &&
            !expanding.include?(name) &&
            assign_map.key?(name)
        end

        def needs_runtime_simplification?(expr, assign_map:, inlineable_names:, expanding: EMPTY_SET, cache: {},
                                          runtime_sensitive_names:)
          expanding ||= EMPTY_SET
          return false if expr.nil?
          return false if expr.is_a?(IR::Literal)
          if expr.is_a?(IR::Signal)
            signal_name = expr.name.to_s
            return false if expr.width.to_i <= MAX_RUNTIME_SIGNAL_WIDTH && !runtime_sensitive_names.include?(signal_name)
          end

          cache_key = recursion_cache_key(expr, expanding)
          return cache[cache_key] if cache_key && cache.key?(cache_key)

          result = case expr
                   when IR::Signal
                     name = expr.name.to_s
                     if runtime_sensitive_names.include?(name) && inlineable_names.include?(name) &&
                        !expanding.include?(name)
                       assigned_expr = assign_map[name]
                       next_expanding = next_expanding_set(expanding, name)
                       expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || (
                         assigned_expr && needs_runtime_simplification?(
                           assigned_expr,
                           assign_map: assign_map,
                           inlineable_names: inlineable_names,
                           expanding: next_expanding,
                           cache: cache,
                           runtime_sensitive_names: runtime_sensitive_names
                         )
                       )
                     else
                       expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH
                     end
                   when IR::Slice
                     expr.base.respond_to?(:width) && expr.base.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH ||
                       needs_runtime_simplification?(
                         expr.base,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       )
                   when IR::Concat
                     expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || expr.parts.any? do |part|
                       needs_runtime_simplification?(
                         part,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       )
                     end
                   when IR::Mux
                     expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH ||
                       [expr.condition, expr.when_true, expr.when_false].compact.any? do |part|
                         needs_runtime_simplification?(
                           part,
                           assign_map: assign_map,
                           inlineable_names: inlineable_names,
                           expanding: expanding,
                           cache: cache,
                           runtime_sensitive_names: runtime_sensitive_names
                         )
                       end
                   when IR::Resize
                     expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH ||
                       needs_runtime_simplification?(
                         expr.expr,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       )
                   when IR::UnaryOp
                     needs_runtime_simplification?(
                       expr.operand,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       expanding: expanding,
                       cache: cache,
                       runtime_sensitive_names: runtime_sensitive_names
                     )
                   when IR::BinaryOp
                     needs_runtime_simplification?(
                       expr.left,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       expanding: expanding,
                       cache: cache,
                       runtime_sensitive_names: runtime_sensitive_names
                     ) ||
                       needs_runtime_simplification?(
                         expr.right,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       )
                   when IR::Case
                     needs_runtime_simplification?(
                       expr.selector,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       expanding: expanding,
                       cache: cache,
                       runtime_sensitive_names: runtime_sensitive_names
                     ) ||
                       needs_runtime_simplification?(
                         expr.default,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       ) ||
                       expr.cases.values.any? do |value|
                         needs_runtime_simplification?(
                           value,
                           assign_map: assign_map,
                           inlineable_names: inlineable_names,
                           expanding: expanding,
                           cache: cache,
                           runtime_sensitive_names: runtime_sensitive_names
                         )
                       end
                   when IR::MemoryRead
                     expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH ||
                       needs_runtime_simplification?(
                         expr.addr,
                         assign_map: assign_map,
                         inlineable_names: inlineable_names,
                         expanding: expanding,
                         cache: cache,
                         runtime_sensitive_names: runtime_sensitive_names
                       )
                   else
                     false
                   end

          cache[cache_key] = result if cache_key
          result
        end

        def simplify_expr_for_runtime(expr, assign_map:, inlineable_names:, expanding: EMPTY_SET, cache: nil,
                                      needs_cache: {}, runtime_sensitive_names:)
          expanding ||= EMPTY_SET
          return expr if expr.nil?
          if expr.is_a?(IR::Literal)
            return expr
          elsif expr.is_a?(IR::Signal)
            signal_name = expr.name.to_s
            return expr if expr.width.to_i <= MAX_RUNTIME_SIGNAL_WIDTH && !runtime_sensitive_names.include?(signal_name)
          end

          cache ||= {}
          slice_cache_key = nil
          if expr.is_a?(IR::Slice)
            low, high = normalized_slice_bounds(expr.range)
            slice_cache_key = slice_recursion_cache_key(expr.base, low, high, expanding)
            return cache[slice_cache_key] if slice_cache_key && cache.key?(slice_cache_key)
          end
          cache_key = recursion_cache_key(expr, expanding)
          return cache[cache_key] if cache_key && cache.key?(cache_key)

          result = case expr
          when IR::Signal
            inline_signal_expr(
              expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          when IR::Literal
            expr
          when IR::UnaryOp
            IR::UnaryOp.new(
              op: expr.op,
              operand: simplify_expr_for_runtime(
                expr.operand,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: expr.width.to_i
            )
          when IR::BinaryOp
            IR::BinaryOp.new(
              op: expr.op,
              left: simplify_expr_for_runtime(
                expr.left,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              right: simplify_expr_for_runtime(
                expr.right,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: expr.width.to_i
            )
          when IR::Mux
            IR::Mux.new(
              condition: simplify_expr_for_runtime(
                expr.condition,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_true: simplify_expr_for_runtime(
                expr.when_true,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_false: simplify_expr_for_runtime(
                expr.when_false,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: expr.width.to_i
            )
          when IR::Slice
            simplify_slice_expr_for_runtime(
              expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          when IR::Concat
            simplify_concat_expr_for_runtime(
              expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          when IR::Resize
            inner = simplify_expr_for_runtime(
                expr.expr,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )
            return inner if inner.respond_to?(:width) && inner.width.to_i == expr.width.to_i

            IR::Resize.new(expr: inner, width: expr.width.to_i)
          when IR::Case
            IR::Case.new(
              selector: simplify_expr_for_runtime(
                expr.selector,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              cases: expr.cases.transform_values do |value|
                simplify_expr_for_runtime(
                  value,
                  assign_map: assign_map,
                  inlineable_names: inlineable_names,
                  expanding: expanding,
                  cache: cache,
                  needs_cache: needs_cache,
                  runtime_sensitive_names: runtime_sensitive_names
                )
              end,
              default: expr.default && simplify_expr_for_runtime(
                expr.default,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: expr.width.to_i
            )
          when IR::MemoryRead
            IR::MemoryRead.new(
              memory: expr.memory,
              addr: simplify_expr_for_runtime(
                expr.addr,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: expr.width.to_i
            )
          else
            expr
          end

          cache[slice_cache_key] = result if slice_cache_key
          cache[cache_key] = result if cache_key
          result
        end

        def inline_signal_expr(expr, assign_map:, inlineable_names:, expanding:, cache:, needs_cache:,
                               runtime_sensitive_names:)
          name = expr.name.to_s
          return expr unless inlineable_names.include?(name)
          return expr unless runtime_sensitive_names.include?(name)
          return expr if expanding.include?(name)

          assigned_expr = assign_map[name]
          return expr unless assigned_expr

          next_expanding = next_expanding_set(expanding, name)

          simplified = simplify_expr_for_runtime(
            assigned_expr,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            expanding: next_expanding,
            cache: cache,
            needs_cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )
          return simplified if simplified.respond_to?(:width) && simplified.width.to_i == expr.width.to_i

          IR::Resize.new(expr: simplified, width: expr.width.to_i)
        end

        def simplify_slice_expr_for_runtime(expr, assign_map:, inlineable_names:, expanding:, cache:, needs_cache:,
                                            runtime_sensitive_names:)
          low, high = normalized_slice_bounds(expr.range)
          width = expr.width.to_i

          case expr.base
          when IR::Literal
            return IR::Literal.new(value: extract_literal_slice(expr.base.value, low, width), width: width)
          when IR::Signal
            name = expr.base.name.to_s
            if runtime_signal_should_inline?(
              name,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              runtime_sensitive_names: runtime_sensitive_names,
              expanding: expanding
            )
              next_expanding = next_expanding_set(expanding, name)
              assigned_expr = assign_map[name]
              return simplify_expr_for_runtime(
                IR::Slice.new(base: assigned_expr, range: low..high, width: width),
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: next_expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )
            end
          when IR::Slice
            base_low, = normalized_slice_bounds(expr.base.range)
            return simplify_expr_for_runtime(
              IR::Slice.new(base: expr.base.base, range: (base_low + low)..(base_low + high), width: width),
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          when IR::Mux
            return IR::Mux.new(
              condition: simplify_expr_for_runtime(
                expr.base.condition,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_true: simplify_expr_for_runtime(
                IR::Slice.new(base: expr.base.when_true, range: low..high, width: width),
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_false: simplify_expr_for_runtime(
                IR::Slice.new(base: expr.base.when_false, range: low..high, width: width),
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: width
            )
          when IR::Concat
            reduced = simplify_slice_over_concat_for_runtime(
              expr.base.parts,
              low: low,
              high: high,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            return reduced if reduced
          when IR::Resize
            return simplify_slice_of_resize_for_runtime(
              expr.base,
              low: low,
              high: high,
              width: width,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          end

          base = simplify_expr_for_runtime(
            expr.base,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            expanding: expanding,
            cache: cache,
            needs_cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )

          if base.is_a?(IR::Literal)
            return IR::Literal.new(value: extract_literal_slice(base.value, low, width), width: width)
          end

          if base.respond_to?(:width) && low.zero? && high == (base.width.to_i - 1) && width == base.width.to_i
            return base
          end

          case base
          when IR::Slice
            base_low, = normalized_slice_bounds(base.range)
            return simplify_expr_for_runtime(
              IR::Slice.new(base: base.base, range: (base_low + low)..(base_low + high), width: width),
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          when IR::Mux
            return IR::Mux.new(
              condition: simplify_expr_for_runtime(
                base.condition,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_true: simplify_expr_for_runtime(
                IR::Slice.new(base: base.when_true, range: low..high, width: width),
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              when_false: simplify_expr_for_runtime(
                IR::Slice.new(base: base.when_false, range: low..high, width: width),
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: cache,
                needs_cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              ),
              width: width
            )
          when IR::Concat
            reduced = simplify_slice_over_concat_for_runtime(
              base.parts,
              low: low,
              high: high,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            return reduced if reduced
          when IR::Resize
            return simplify_slice_of_resize_for_runtime(
              base,
              low: low,
              high: high,
              width: width,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          end

          IR::Slice.new(base: base, range: low..high, width: width)
        end

        def simplify_concat_expr_for_runtime(expr, assign_map:, inlineable_names:, expanding:, cache:, needs_cache:,
                                             runtime_sensitive_names:)
          changed = false
          parts = expr.parts.flat_map do |part|
            part_needs_simplification =
              part.is_a?(IR::Concat) || needs_runtime_simplification?(
                part,
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                expanding: expanding,
                cache: needs_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )

            simplified =
              if part_needs_simplification
                simplify_expr_for_runtime(
                  part,
                  assign_map: assign_map,
                  inlineable_names: inlineable_names,
                  expanding: expanding,
                  cache: cache,
                  needs_cache: needs_cache,
                  runtime_sensitive_names: runtime_sensitive_names
                )
              else
                part
              end

            if simplified.is_a?(IR::Concat)
              changed = true
              simplified.parts
            else
              changed ||= !simplified.equal?(part)
              [simplified]
            end
          end
          return expr unless changed
          return parts.first if parts.one? && parts.first.width.to_i == expr.width.to_i

          IR::Concat.new(parts: parts, width: expr.width.to_i)
        end

        def simplify_slice_over_concat_for_runtime(parts, low:, high:, assign_map:, inlineable_names:, expanding:,
                                                   cache:, needs_cache:, runtime_sensitive_names:)
          total_width = Array(parts).sum { |part| part.width.to_i }
          cursor = total_width - 1
          selected = []

          Array(parts).each do |part|
            part_width = part.width.to_i
            part_low = cursor - part_width + 1
            part_high = cursor
            overlap_low = [low, part_low].max
            overlap_high = [high, part_high].min

            if overlap_low <= overlap_high
              inner_low = overlap_low - part_low
              inner_high = overlap_high - part_low
              selected << if inner_low.zero? && inner_high == (part_width - 1)
                            part
                          else
                            simplify_expr_for_runtime(
                              IR::Slice.new(
                                base: part,
                                range: inner_low..inner_high,
                                width: inner_high - inner_low + 1
                              ),
                              assign_map: assign_map,
                              inlineable_names: inlineable_names,
                              expanding: expanding,
                              cache: cache,
                              needs_cache: needs_cache,
                              runtime_sensitive_names: runtime_sensitive_names
                            )
                          end
            end

            cursor = part_low - 1
          end

          return nil if selected.empty?
          return selected.first if selected.one? && selected.first.width.to_i == (high - low + 1)

          IR::Concat.new(parts: selected, width: high - low + 1)
        end

        def simplify_slice_of_resize_for_runtime(expr, low:, high:, width:, assign_map:, inlineable_names:, expanding:,
                                                 cache:, needs_cache:, runtime_sensitive_names:)
          inner = simplify_expr_for_runtime(
            expr.expr,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            expanding: expanding,
            cache: cache,
            needs_cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )
          inner_width = inner.width.to_i
          return literal_zero(width) if low >= inner_width

          if high < inner_width
            return simplify_expr_for_runtime(
              IR::Slice.new(base: inner, range: low..high, width: width),
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
          end

          overlap_high = inner_width - 1
          lower_width = overlap_high - low + 1
          lower_part = if lower_width == inner_width && low.zero?
                         inner
                       else
                         simplify_expr_for_runtime(
                           IR::Slice.new(base: inner, range: low..overlap_high, width: lower_width),
                           assign_map: assign_map,
                           inlineable_names: inlineable_names,
                           expanding: expanding,
                           cache: cache,
                           needs_cache: needs_cache,
                           runtime_sensitive_names: runtime_sensitive_names
                         )
                       end
          zero_width = width - lower_width
          return lower_part if zero_width <= 0

          IR::Concat.new(parts: [literal_zero(zero_width), lower_part], width: width)
        end

        # Build a mapping from signal name to its effective (chained) expression.
        #
        # When the behavior block contains multiple sequential assignments to the
        # same wire, e.g.:
        #
        #   read_to_reg <= lit(0)
        #   read_to_reg <= mux(is_ld_rr, lit(1), read_to_reg)
        #   read_to_reg <= mux(is_ld_r_n, lit(1), read_to_reg)
        #
        # each subsequent assignment's self-reference (Signal pointing to the
        # same target) denotes "the value produced by the previous assignment".
        # This helper folds those chains so that the map entry for the target is
        # a single composite expression that captures the full priority chain.
        def build_assign_map(assigns)
          Array(assigns).each_with_object({}) do |assign, mapping|
            target = assign.target.to_s
            prev_expr = mapping[target]
            if prev_expr.nil?
              mapping[target] = assign.expr
            else
              # Substitute self-references with the previous expression
              mapping[target] = substitute_self_ref(assign.expr, target, prev_expr)
            end
          end
        end

        # Recursively replace Signal nodes whose name matches +target+ with
        # +replacement+ inside +expr+.  Returns the original object when no
        # substitution is needed (to keep object sharing / caching intact).
        def substitute_self_ref(expr, target, replacement)
          case expr
          when IR::Signal
            return replacement if expr.name.to_s == target
            expr
          when IR::Mux
            c  = substitute_self_ref(expr.condition,  target, replacement)
            wt = substitute_self_ref(expr.when_true,  target, replacement)
            wf = substitute_self_ref(expr.when_false, target, replacement)
            return expr if c.equal?(expr.condition) && wt.equal?(expr.when_true) && wf.equal?(expr.when_false)
            IR::Mux.new(condition: c, when_true: wt, when_false: wf, width: expr.width.to_i)
          when IR::BinaryOp
            l = substitute_self_ref(expr.left,  target, replacement)
            r = substitute_self_ref(expr.right, target, replacement)
            return expr if l.equal?(expr.left) && r.equal?(expr.right)
            IR::BinaryOp.new(op: expr.op, left: l, right: r, width: expr.width.to_i)
          when IR::UnaryOp
            o = substitute_self_ref(expr.operand, target, replacement)
            return expr if o.equal?(expr.operand)
            IR::UnaryOp.new(op: expr.op, operand: o, width: expr.width.to_i)
          when IR::Slice
            b = substitute_self_ref(expr.base, target, replacement)
            return expr if b.equal?(expr.base)
            IR::Slice.new(base: b, range: expr.range, width: expr.width.to_i)
          when IR::Concat
            parts = expr.parts.map { |p| substitute_self_ref(p, target, replacement) }
            return expr if parts.each_with_index.all? { |p, i| p.equal?(expr.parts[i]) }
            IR::Concat.new(parts: parts, width: expr.width.to_i)
          when IR::Resize
            inner = substitute_self_ref(expr.expr, target, replacement)
            return expr if inner.equal?(expr.expr)
            IR::Resize.new(expr: inner, width: expr.width.to_i)
          when IR::Case
            sel = substitute_self_ref(expr.selector, target, replacement)
            cases = expr.cases.transform_values { |v| substitute_self_ref(v, target, replacement) }
            dflt = expr.default ? substitute_self_ref(expr.default, target, replacement) : expr.default
            return expr if sel.equal?(expr.selector) && dflt.equal?(expr.default) &&
                           cases.each_with_index.all? { |(k, v), _| v.equal?(expr.cases[k]) }
            IR::Case.new(selector: sel, cases: cases, default: dflt, width: expr.width.to_i)
          else
            expr
          end
        end

        def build_signal_width_map(mod)
          signal_widths = {}
          (Array(mod.ports) + Array(mod.nets) + Array(mod.regs)).each do |entry|
            signal_widths[entry.name.to_s] ||= entry.width.to_i
          end
          signal_widths
        end

        def runtime_sensitive_signal_names(assign_map:, signal_widths:)
          signal_cache = {}
          expr_cache = {}

          assign_map.each_key.each_with_object(Set.new) do |name, result|
            next unless signal_requires_runtime_simplification?(
              name,
              assign_map: assign_map,
              signal_widths: signal_widths,
              signal_cache: signal_cache,
              expr_cache: expr_cache,
              visiting: Set.new
            )

            result.add(name.to_s)
          end
        end

        def signal_requires_runtime_simplification?(name, assign_map:, signal_widths:, signal_cache:, expr_cache:, visiting:)
          signal_name = name.to_s
          return signal_cache[signal_name] if signal_cache.key?(signal_name)
          return signal_cache[signal_name] = true if signal_widths[signal_name].to_i > MAX_RUNTIME_SIGNAL_WIDTH

          assigned_expr = assign_map[signal_name]
          return signal_cache[signal_name] = false unless assigned_expr
          return false if visiting.include?(signal_name)

          visiting.add(signal_name)
          result = expr_requires_runtime_simplification?(
            assigned_expr,
            assign_map: assign_map,
            signal_widths: signal_widths,
            signal_cache: signal_cache,
            expr_cache: expr_cache,
            visiting: visiting
          )
          visiting.delete(signal_name)
          signal_cache[signal_name] = result
        end

        def expr_requires_runtime_simplification?(expr, assign_map:, signal_widths:, signal_cache:, expr_cache:, visiting:)
          return false if expr.nil?

          cache_key = expr.object_id
          return expr_cache[cache_key] if expr_cache.key?(cache_key)

          expr_cache[cache_key] = case expr
                                  when IR::Signal
                                    expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || signal_requires_runtime_simplification?(
                                      expr.name,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  when IR::Slice
                                    (expr.base.respond_to?(:width) && expr.base.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH) ||
                                      expr_requires_runtime_simplification?(
                                        expr.base,
                                        assign_map: assign_map,
                                        signal_widths: signal_widths,
                                        signal_cache: signal_cache,
                                        expr_cache: expr_cache,
                                        visiting: visiting
                                      )
                                  when IR::Concat
                                    expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || expr.parts.any? do |part|
                                      expr_requires_runtime_simplification?(
                                        part,
                                        assign_map: assign_map,
                                        signal_widths: signal_widths,
                                        signal_cache: signal_cache,
                                        expr_cache: expr_cache,
                                        visiting: visiting
                                      )
                                    end
                                  when IR::Mux
                                    expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || [expr.condition, expr.when_true, expr.when_false].compact.any? do |part|
                                      expr_requires_runtime_simplification?(
                                        part,
                                        assign_map: assign_map,
                                        signal_widths: signal_widths,
                                        signal_cache: signal_cache,
                                        expr_cache: expr_cache,
                                        visiting: visiting
                                      )
                                    end
                                  when IR::Resize
                                    expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || expr_requires_runtime_simplification?(
                                      expr.expr,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  when IR::UnaryOp
                                    expr_requires_runtime_simplification?(
                                      expr.operand,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  when IR::BinaryOp
                                    expr_requires_runtime_simplification?(
                                      expr.left,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    ) || expr_requires_runtime_simplification?(
                                      expr.right,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  when IR::Case
                                    expr_requires_runtime_simplification?(
                                      expr.selector,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    ) || expr_requires_runtime_simplification?(
                                      expr.default,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    ) || expr.cases.values.any? do |value|
                                      expr_requires_runtime_simplification?(
                                        value,
                                        assign_map: assign_map,
                                        signal_widths: signal_widths,
                                        signal_cache: signal_cache,
                                        expr_cache: expr_cache,
                                        visiting: visiting
                                      )
                                    end
                                  when IR::MemoryRead
                                    expr.width.to_i > MAX_RUNTIME_SIGNAL_WIDTH || expr_requires_runtime_simplification?(
                                      expr.addr,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  else
                                    false
                                  end
        end

        def normalized_slice_bounds(range)
          range_begin = range.begin.to_i
          range_end = range.end.to_i
          range_end -= 1 if range.exclude_end?
          [range_begin, range_end].minmax
        end

        def extract_literal_slice(value, low, width)
          return 0 if width.to_i <= 0

          mask = if width.to_i >= 128
                   (1 << 128) - 1
                 else
                   (1 << width.to_i) - 1
                 end
          (value.to_i >> low.to_i) & mask
        end

        def literal_zero(width)
          IR::Literal.new(value: 0, width: width.to_i)
        end

        def runtime_live_assign_targets_from_expr_graph(mod, seed_targets: nil)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          live_assign_targets = output_targets | runtime_non_assign_signal_refs(mod)
          live_assign_targets.merge(Array(seed_targets).map(&:to_s))
          assigns_by_target = Array(mod.assigns).group_by { |assign| assign.target.to_s }
          signal_refs_cache = {}
          worklist = live_assign_targets.to_a

          until worklist.empty?
            target = worklist.pop
            Array(assigns_by_target[target]).each do |assign|
              refs = signal_refs_from_expr(assign.expr, cache: signal_refs_cache)
              refs.each do |ref|
                next if live_assign_targets.include?(ref)

                live_assign_targets.add(ref)
                worklist << ref
              end
            end
          end

          live_assign_targets
        end

        def runtime_live_assign_targets(mod, assign_map: nil, inlineable_names: nil, runtime_sensitive_names: nil,
                                        needs_cache: nil, simplify_cache: nil)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          live_assign_targets = output_targets | runtime_non_assign_signal_refs(mod)
          processed_targets = Set.new
          assign_map ||= build_assign_map(mod.assigns)
          inlineable_names ||= Array(mod.nets).map { |net| net.name.to_s }.to_set
          signal_widths = build_signal_width_map(mod)
          if runtime_sensitive_names.nil?
            runtime_sensitive_names = runtime_sensitive_signal_names(
              assign_map: assign_map,
              signal_widths: signal_widths
            )
          end
          simplification_needed_cache = needs_cache || {}
          simplify_cache ||= {}
          signal_refs_cache = {}
          raw_signal_refs_cache = {}
          worklist = live_assign_targets.to_a

          until worklist.empty?
            target = worklist.pop
            next if processed_targets.include?(target)

            processed_targets.add(target)
            assigned_expr = assign_map[target.to_s]
            next unless assigned_expr

            target_width = signal_widths[target.to_s].to_i
            raw_refs = signal_refs_from_expr(assigned_expr, cache: raw_signal_refs_cache)
            refs = runtime_simplified_signal_refs(
              assigned_expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              needs_cache: simplification_needed_cache,
              cache: signal_refs_cache,
              raw_cache: raw_signal_refs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            refs =
              if target_width > MAX_RUNTIME_SIGNAL_WIDTH
                raw_refs
              else
                refs | raw_refs.select do |ref|
                  hierarchical_runtime_signal_name?(ref) || signal_widths[ref].to_i <= MAX_RUNTIME_SIGNAL_WIDTH
                end
              end
            refs.each do |ref|
              next if live_assign_targets.include?(ref)

              live_assign_targets.add(ref)
              worklist << ref
            end
          end

          live_assign_targets
        end

        def hierarchical_runtime_signal_name?(name)
          signal_name = name.to_s
          signal_name.include?('__') || signal_name.include?('.')
        end

        def prune_dead_runtime_assigns_and_signals(mod, live_assign_targets: nil, preserve_assign_targets: nil)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          live_assign_targets = runtime_live_assign_targets_from_expr_graph(mod, seed_targets: live_assign_targets)
          preserve_assign_targets = Set.new(Array(preserve_assign_targets).map(&:to_s))
          hierarchical_assign_targets = Array(mod.assigns)
                                        .map { |assign| assign.target.to_s }
                                        .select { |name| hierarchical_runtime_signal_name?(name) }
                                        .to_set

          filtered_assigns = mod.assigns.select do |assign|
            target = assign.target.to_s
            live_assign_targets.include?(target) ||
              hierarchical_assign_targets.include?(target) ||
              preserve_assign_targets.include?(target)
          end
          required_signal_names = output_targets | hierarchical_assign_targets | preserve_assign_targets
          sync_read_targets = Set.new

          filtered_assigns.each do |assign|
            required_signal_names.add(assign.target.to_s)
            collect_signal_refs_from_expr(assign.expr, required_signal_names)
          end

          Array(mod.processes).each do |process|
            collect_signal_usage_from_process(process, required_signal_names, Set.new)
          end
          Array(mod.instances).each do |instance|
            collect_signal_usage_from_instance(instance, required_signal_names)
          end
          Array(mod.write_ports).each do |write_port|
            collect_signal_usage_from_write_port(write_port, required_signal_names)
          end
          Array(mod.sync_read_ports).each do |sync_read_port|
            collect_signal_usage_from_sync_read_port(sync_read_port, required_signal_names, sync_read_targets)
          end

          required_signal_names.merge(sync_read_targets)

          filtered_nets = mod.nets.select { |net| required_signal_names.include?(net.name.to_s) }

          return mod if filtered_assigns.length == mod.assigns.length &&
                        filtered_nets.length == mod.nets.length

          IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: filtered_nets,
            regs: mod.regs,
            assigns: filtered_assigns,
            processes: mod.processes,
            instances: mod.instances,
            memories: mod.memories,
            write_ports: mod.write_ports,
            sync_read_ports: mod.sync_read_ports,
            parameters: mod.parameters || {}
          )
        end

        def collapse_runtime_alias_assigns(mod, preserve_assign_targets: nil)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          preserve_assign_targets = Set.new(Array(preserve_assign_targets).map(&:to_s))
          hierarchical_assign_targets = Array(mod.assigns)
                                        .map { |assign| assign.target.to_s }
                                        .select { |name| hierarchical_runtime_signal_name?(name) }
                                        .to_set
          preserved_targets = output_targets |
                              runtime_non_assign_signal_refs(mod) |
                              hierarchical_assign_targets |
                              preserve_assign_targets

          alias_targets = {}
          Array(mod.assigns).each do |assign|
            target_name = assign.target.to_s
            next if preserved_targets.include?(target_name)
            next unless assign.expr.is_a?(IR::Signal)

            source_name = assign.expr.name.to_s
            next if source_name == target_name

            alias_targets[target_name] = source_name
          end

          return mod if alias_targets.empty?

          signal_widths = build_signal_width_map(mod)
          resolution_cache = {}
          rewritten_assigns = Array(mod.assigns).map do |assign|
            expr = rewrite_runtime_expr_aliases(
              assign.expr,
              alias_targets: alias_targets,
              signal_widths: signal_widths,
              resolution_cache: resolution_cache
            )
            expr.equal?(assign.expr) ? assign : IR::Assign.new(target: assign.target, expr: expr)
          end.reject { |assign| alias_targets.key?(assign.target.to_s) }

          collapsed_module = IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: mod.nets,
            regs: mod.regs,
            assigns: rewritten_assigns,
            processes: mod.processes,
            instances: mod.instances,
            memories: mod.memories,
            write_ports: mod.write_ports,
            sync_read_ports: mod.sync_read_ports,
            parameters: mod.parameters || {}
          )

          prune_dead_runtime_assigns_and_signals(
            collapsed_module,
            preserve_assign_targets: preserved_targets
          )
        end

        def runtime_non_assign_signal_refs(mod)
          refs = Set.new
          process_writes = Set.new
          sync_read_targets = Set.new

          Array(mod.processes).each do |process|
            collect_signal_usage_from_process(process, refs, process_writes)
          end
          Array(mod.instances).each do |instance|
            collect_signal_usage_from_instance(instance, refs)
          end
          Array(mod.write_ports).each do |write_port|
            collect_signal_usage_from_write_port(write_port, refs)
          end
          Array(mod.sync_read_ports).each do |sync_read_port|
            collect_signal_usage_from_sync_read_port(sync_read_port, refs, sync_read_targets)
          end

          refs
        end

        def collect_signal_usage_from_process(process, refs, writes)
          return if process.nil?

          refs.add(process.clock.to_s) if process.clock
          Array(process.sensitivity_list).each { |signal| refs.add(signal.to_s) }
          collect_signal_usage_from_statements(Array(process.statements), refs, writes)
        end

        def collect_signal_usage_from_statements(statements, refs, writes)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              writes.add(stmt.target.to_s)
              collect_signal_refs_from_expr(stmt.expr, refs)
            when IR::If
              collect_signal_refs_from_expr(stmt.condition, refs)
              collect_signal_usage_from_statements(stmt.then_statements, refs, writes)
              collect_signal_usage_from_statements(stmt.else_statements, refs, writes)
            end
          end
        end

        def collect_signal_usage_from_instance(instance, refs)
          Array(instance&.connections).each do |connection|
            collect_runtime_signal_operand_refs(connection.signal, refs)
          end
        end

        def collect_signal_usage_from_write_port(write_port, refs)
          collect_runtime_signal_operand_refs(write_port&.clock, refs)
          collect_runtime_signal_operand_refs(write_port&.addr, refs)
          collect_runtime_signal_operand_refs(write_port&.data, refs)
          collect_runtime_signal_operand_refs(write_port&.enable, refs)
        end

        def collect_signal_usage_from_sync_read_port(sync_read_port, refs, targets)
          collect_runtime_signal_operand_refs(sync_read_port&.clock, refs)
          collect_runtime_signal_operand_refs(sync_read_port&.addr, refs)
          collect_runtime_signal_operand_refs(sync_read_port&.enable, refs)
          targets.add(sync_read_port.data.to_s) if sync_read_port&.data
        end

        def collect_runtime_signal_operand_refs(operand, refs)
          case operand
          when Symbol, String
            refs.add(operand.to_s)
          else
            collect_signal_refs_from_expr(operand, refs)
          end
        end

        def collect_signal_refs_from_expr(expr, refs, seen: nil)
          return refs if expr.nil?
          seen ||= Set.new
          oid = expr.object_id
          return refs if seen.include?(oid)

          seen.add(oid)

          case expr
          when IR::Signal
            refs.add(expr.name.to_s)
          when IR::UnaryOp
            collect_signal_refs_from_expr(expr.operand, refs, seen: seen)
          when IR::BinaryOp
            collect_signal_refs_from_expr(expr.left, refs, seen: seen)
            collect_signal_refs_from_expr(expr.right, refs, seen: seen)
          when IR::Mux
            collect_signal_refs_from_expr(expr.condition, refs, seen: seen)
            collect_signal_refs_from_expr(expr.when_true, refs, seen: seen)
            collect_signal_refs_from_expr(expr.when_false, refs, seen: seen)
          when IR::Slice
            collect_signal_refs_from_expr(expr.base, refs, seen: seen)
          when IR::Concat
            Array(expr.parts).each { |part| collect_signal_refs_from_expr(part, refs, seen: seen) }
          when IR::Resize
            collect_signal_refs_from_expr(expr.expr, refs, seen: seen)
          when IR::Case
            collect_signal_refs_from_expr(expr.selector, refs, seen: seen)
            expr.cases.each_value { |value| collect_signal_refs_from_expr(value, refs, seen: seen) }
            collect_signal_refs_from_expr(expr.default, refs, seen: seen)
          when IR::MemoryRead
            collect_signal_refs_from_expr(expr.addr, refs, seen: seen)
          end

          refs
        end

        def signal_refs_from_expr(expr, cache:, visiting: nil)
          return EMPTY_SET if expr.nil?

          visiting ||= Set.new
          oid = expr.object_id
          return cache[oid] if cache.key?(oid)
          return EMPTY_SET if visiting.include?(oid)

          visiting.add(oid)
          refs = case expr
                 when IR::Signal
                   Set[expr.name.to_s]
                 when IR::UnaryOp
                   signal_refs_from_expr(expr.operand, cache: cache, visiting: visiting)
                 when IR::BinaryOp
                   merge_signal_ref_sets(
                     signal_refs_from_expr(expr.left, cache: cache, visiting: visiting),
                     signal_refs_from_expr(expr.right, cache: cache, visiting: visiting)
                   )
                 when IR::Mux
                   merge_signal_ref_sets(
                     signal_refs_from_expr(expr.condition, cache: cache, visiting: visiting),
                     signal_refs_from_expr(expr.when_true, cache: cache, visiting: visiting),
                     signal_refs_from_expr(expr.when_false, cache: cache, visiting: visiting)
                   )
                 when IR::Slice
                   signal_refs_from_expr(expr.base, cache: cache, visiting: visiting)
                 when IR::Concat
                   Array(expr.parts).each_with_object(Set.new) do |part, acc|
                     acc.merge(signal_refs_from_expr(part, cache: cache, visiting: visiting))
                   end
                 when IR::Resize
                   signal_refs_from_expr(expr.expr, cache: cache, visiting: visiting)
                 when IR::Case
                   refs = signal_refs_from_expr(expr.selector, cache: cache, visiting: visiting).dup
                   expr.cases.each_value do |value|
                     refs.merge(signal_refs_from_expr(value, cache: cache, visiting: visiting))
                   end
                   refs.merge(signal_refs_from_expr(expr.default, cache: cache, visiting: visiting))
                 when IR::MemoryRead
                   signal_refs_from_expr(expr.addr, cache: cache, visiting: visiting)
                 else
                   EMPTY_SET
                 end
          visiting.delete(oid)
          cache[oid] = refs.frozen? ? refs : refs.freeze
        end

        def rewrite_runtime_expr_aliases(expr, alias_targets:, signal_widths:, resolution_cache:, visiting: nil)
          return expr if expr.nil?

          case expr
          when IR::Signal
            resolved_name = resolve_runtime_alias_name(
              expr.name.to_s,
              alias_targets: alias_targets,
              resolution_cache: resolution_cache,
              visiting: visiting
            )
            return expr if resolved_name == expr.name.to_s

            IR::Signal.new(name: resolved_name, width: signal_widths[resolved_name].to_i.nonzero? || expr.width.to_i)
          else
            children = expr_children(expr)
            return expr if children.empty?

            rewritten_children = children.map do |child|
              rewrite_runtime_expr_aliases(
                child,
                alias_targets: alias_targets,
                signal_widths: signal_widths,
                resolution_cache: resolution_cache,
                visiting: visiting
              )
            end
            return expr if rewritten_children.each_with_index.all? { |child, index| child.equal?(children[index]) }

            rebuild_expr(expr, rewritten_children)
          end
        end

        def resolve_runtime_alias_name(name, alias_targets:, resolution_cache:, visiting: nil)
          signal_name = name.to_s
          return resolution_cache[signal_name] if resolution_cache.key?(signal_name)

          visiting ||= Set.new
          return signal_name if visiting.include?(signal_name)

          target = alias_targets[signal_name]
          return resolution_cache[signal_name] = signal_name if target.nil?

          visiting.add(signal_name)
          resolved = resolve_runtime_alias_name(
            target,
            alias_targets: alias_targets,
            resolution_cache: resolution_cache,
            visiting: visiting
          )
          visiting.delete(signal_name)
          resolution_cache[signal_name] = resolved
        end

        def hoist_shared_exprs_to_assigns(expr, temp_counter:, prefix:)
          return [expr, []] if expr.nil? || expr.is_a?(IR::Literal) || expr.is_a?(IR::Signal)
          return [expr, []] unless expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat) || expr.is_a?(IR::Case)
          return [expr, []] unless shared_subexpressions?(expr)
          tree_width_cache = {}
          return [expr, []] unless runtime_expr_tree_fits_native_width?(expr, cache: tree_width_cache)

          counts = parent_counts(expr)

          hoisted = {}
          assigns = []
          counter_ref = { value: temp_counter.to_i }
          rewritten = rewrite_expr_for_runtime(
            expr,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: sanitize_runtime_name(prefix),
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          [rewritten, assigns]
        end

        def hoist_module_shared_exprs(mod)
          counts = module_expr_reference_counts(mod)
          hoisted_assigns = []
          hoisted = {}
          counter_ref = { value: 0 }
          prefix = sanitize_runtime_name("#{mod.name}_rt_shared")
          tree_width_cache = {}

          rewritten_assigns = Array(mod.assigns).map do |assign|
            expr = rewrite_expr_for_runtime(
              assign.expr,
              counts: counts,
              hoisted: hoisted,
              assigns: hoisted_assigns,
              prefix: prefix,
              counter_ref: counter_ref,
              tree_width_cache: tree_width_cache
            )
            expr.equal?(assign.expr) ? assign : IR::Assign.new(target: assign.target, expr: expr)
          end

          rewritten_processes = Array(mod.processes).map do |process|
            statements = rewrite_process_statements_with_shared_exprs(
              process.statements,
              counts: counts,
              hoisted: hoisted,
              assigns: hoisted_assigns,
              prefix: prefix,
              counter_ref: counter_ref,
              tree_width_cache: tree_width_cache
            )
            next process if statements == Array(process.statements)

            IR::Process.new(
              name: process.name,
              statements: statements,
              clocked: process.clocked,
              clock: process.clock,
              sensitivity_list: process.sensitivity_list,
              reset: process.reset,
              reset_active_low: process.reset_active_low,
              reset_values: process.reset_values
            )
          end

          rewritten_instances = Array(mod.instances).map do |instance|
            connections = Array(instance.connections).map do |connection|
              signal = rewrite_runtime_operand_with_shared_exprs(
                connection.signal,
                counts: counts,
                hoisted: hoisted,
                assigns: hoisted_assigns,
                prefix: prefix,
                counter_ref: counter_ref,
                tree_width_cache: tree_width_cache
              )
              next connection if signal.equal?(connection.signal)

              IR::PortConnection.new(
                port_name: connection.port_name,
                signal: signal,
                direction: connection.direction,
                width: connection.width
              )
            end
            next instance if connections == Array(instance.connections)

            IR::Instance.new(
              name: instance.name,
              module_name: instance.module_name,
              connections: connections,
              parameters: instance.parameters || {}
            )
          end

          rewritten_write_ports = Array(mod.write_ports).map do |write_port|
            rewrite_memory_write_port_with_shared_exprs(
              write_port,
              counts: counts,
              hoisted: hoisted,
              assigns: hoisted_assigns,
              prefix: prefix,
              counter_ref: counter_ref,
              tree_width_cache: tree_width_cache
            )
          end

          rewritten_sync_read_ports = Array(mod.sync_read_ports).map do |sync_read_port|
            rewrite_memory_sync_read_port_with_shared_exprs(
              sync_read_port,
              counts: counts,
              hoisted: hoisted,
              assigns: hoisted_assigns,
              prefix: prefix,
              counter_ref: counter_ref,
              tree_width_cache: tree_width_cache
            )
          end

          return mod if hoisted_assigns.empty?

          IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports,
            nets: dedupe_by_name(mod.nets + hoisted_assigns.map { |entry| entry[:net] }),
            regs: mod.regs,
            assigns: hoisted_assigns.map { |entry| entry[:assign] } + rewritten_assigns,
            processes: rewritten_processes,
            instances: rewritten_instances,
            memories: mod.memories,
            write_ports: rewritten_write_ports,
            sync_read_ports: rewritten_sync_read_ports,
            parameters: mod.parameters || {}
          )
        end

        def module_expr_reference_counts(mod)
          counts = Hash.new(0)
          seen = Set.new
          stack = collect_module_expr_roots(mod)

          stack.each { |root| counts[root.object_id] += 1 }

          until stack.empty?
            expr = stack.pop
            next if expr.nil?

            children = expr_children(expr)
            children.each { |child| counts[child.object_id] += 1 }

            oid = expr.object_id
            next if seen.include?(oid)

            seen << oid
            children.each { |child| stack << child }
          end

          counts
        end

        def collect_module_expr_roots(mod)
          roots = Array(mod.assigns).map(&:expr)
          Array(mod.processes).each do |process|
            collect_statement_expr_roots(process.statements, roots)
          end
          Array(mod.instances).each do |instance|
            Array(instance.connections).each do |connection|
              roots << connection.signal if runtime_expr_operand?(connection.signal)
            end
          end
          Array(mod.write_ports).each do |write_port|
            append_runtime_operand_root(roots, write_port.clock)
            append_runtime_operand_root(roots, write_port.addr)
            append_runtime_operand_root(roots, write_port.data)
            append_runtime_operand_root(roots, write_port.enable)
          end
          Array(mod.sync_read_ports).each do |sync_read_port|
            append_runtime_operand_root(roots, sync_read_port.clock)
            append_runtime_operand_root(roots, sync_read_port.addr)
            append_runtime_operand_root(roots, sync_read_port.enable)
          end
          roots.compact
        end

        def collect_statement_expr_roots(statements, roots)
          Array(statements).each do |stmt|
            case stmt
            when IR::SeqAssign
              roots << stmt.expr
            when IR::If
              roots << stmt.condition
              collect_statement_expr_roots(stmt.then_statements, roots)
              collect_statement_expr_roots(stmt.else_statements, roots)
            end
          end
        end

        def append_runtime_operand_root(roots, operand)
          roots << operand if runtime_expr_operand?(operand)
        end

        def runtime_expr_operand?(operand)
          operand.is_a?(IR::Expr)
        end

        def rewrite_process_statements_with_shared_exprs(statements, counts:, hoisted:, assigns:, prefix:,
                                                         counter_ref:, tree_width_cache:)
          Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              expr = rewrite_expr_for_runtime(
                stmt.expr,
                counts: counts,
                hoisted: hoisted,
                assigns: assigns,
                prefix: prefix,
                counter_ref: counter_ref,
                tree_width_cache: tree_width_cache
              )
              expr.equal?(stmt.expr) ? stmt : IR::SeqAssign.new(target: stmt.target, expr: expr)
            when IR::If
              condition = rewrite_expr_for_runtime(
                stmt.condition,
                counts: counts,
                hoisted: hoisted,
                assigns: assigns,
                prefix: prefix,
                counter_ref: counter_ref,
                tree_width_cache: tree_width_cache
              )
              then_statements = rewrite_process_statements_with_shared_exprs(
                stmt.then_statements,
                counts: counts,
                hoisted: hoisted,
                assigns: assigns,
                prefix: prefix,
                counter_ref: counter_ref,
                tree_width_cache: tree_width_cache
              )
              else_statements = rewrite_process_statements_with_shared_exprs(
                stmt.else_statements,
                counts: counts,
                hoisted: hoisted,
                assigns: assigns,
                prefix: prefix,
                counter_ref: counter_ref,
                tree_width_cache: tree_width_cache
              )
              if condition.equal?(stmt.condition) &&
                 then_statements == Array(stmt.then_statements) &&
                 else_statements == Array(stmt.else_statements)
                stmt
              else
                IR::If.new(
                  condition: condition,
                  then_statements: then_statements,
                  else_statements: else_statements
                )
              end
            else
              stmt
            end
          end
        end

        def rewrite_runtime_operand_with_shared_exprs(operand, counts:, hoisted:, assigns:, prefix:, counter_ref:,
                                                      tree_width_cache:)
          return operand unless runtime_expr_operand?(operand)

          rewrite_expr_for_runtime(
            operand,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
        end

        def rewrite_memory_write_port_with_shared_exprs(write_port, counts:, hoisted:, assigns:, prefix:, counter_ref:,
                                                        tree_width_cache:)
          clock = rewrite_runtime_operand_with_shared_exprs(
            write_port.clock,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          addr = rewrite_runtime_operand_with_shared_exprs(
            write_port.addr,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          data = rewrite_runtime_operand_with_shared_exprs(
            write_port.data,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          enable = rewrite_runtime_operand_with_shared_exprs(
            write_port.enable,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          return write_port if clock.equal?(write_port.clock) &&
                              addr.equal?(write_port.addr) &&
                              data.equal?(write_port.data) &&
                              enable.equal?(write_port.enable)

          IR::MemoryWritePort.new(
            memory: write_port.memory,
            clock: clock,
            addr: addr,
            data: data,
            enable: enable
          )
        end

        def rewrite_memory_sync_read_port_with_shared_exprs(sync_read_port, counts:, hoisted:, assigns:, prefix:,
                                                            counter_ref:, tree_width_cache:)
          clock = rewrite_runtime_operand_with_shared_exprs(
            sync_read_port.clock,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          addr = rewrite_runtime_operand_with_shared_exprs(
            sync_read_port.addr,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          enable = rewrite_runtime_operand_with_shared_exprs(
            sync_read_port.enable,
            counts: counts,
            hoisted: hoisted,
            assigns: assigns,
            prefix: prefix,
            counter_ref: counter_ref,
            tree_width_cache: tree_width_cache
          )
          return sync_read_port if clock.equal?(sync_read_port.clock) &&
                                  addr.equal?(sync_read_port.addr) &&
                                  enable.equal?(sync_read_port.enable)

          IR::MemorySyncReadPort.new(
            memory: sync_read_port.memory,
            clock: clock,
            addr: addr,
            data: sync_read_port.data,
            enable: enable
          )
        end

        def rewrite_expr_for_runtime(expr, counts:, hoisted:, assigns:, prefix:, counter_ref:, tree_width_cache:)
          return expr if expr.nil? || expr.is_a?(IR::Literal) || expr.is_a?(IR::Signal)

          oid = expr.object_id
          return hoisted[oid][:signal] if hoisted.key?(oid)

          rewritten_children = expr_children(expr).map do |child|
            rewrite_expr_for_runtime(
              child,
              counts: counts,
              hoisted: hoisted,
              assigns: assigns,
              prefix: prefix,
              counter_ref: counter_ref,
              tree_width_cache: tree_width_cache
            )
          end
          rewritten = rebuild_expr(expr, rewritten_children)

          if counts[oid].to_i > 1 &&
             expr.width.to_i <= MAX_RUNTIME_SIGNAL_WIDTH &&
             runtime_expr_tree_fits_native_width?(expr, cache: tree_width_cache)
            name = sanitize_runtime_name("#{prefix}_tmp_#{counter_ref[:value]}")
            counter_ref[:value] += 1
            signal = IR::Signal.new(name: name, width: expr.width.to_i)
            hoisted[oid] = { signal: signal }
            assigns << {
              net: IR::Net.new(name: name.to_sym, width: expr.width.to_i),
              assign: IR::Assign.new(target: name, expr: rewritten)
            }
            signal
          else
            rewritten
          end
        end

        def runtime_expr_tree_fits_native_width?(expr, cache: {})
          runtime_expr_tree_max_width(expr, cache: cache) <= MAX_RUNTIME_SIGNAL_WIDTH
        end

        def runtime_expr_tree_max_width(expr, cache: {})
          return 0 if expr.nil?
          return cache[expr.object_id] if cache.key?(expr.object_id)

          child_max = expr_children(expr).map { |child| runtime_expr_tree_max_width(child, cache: cache) }.max.to_i
          own_width = expr.respond_to?(:width) ? expr.width.to_i : 0
          cache[expr.object_id] = [own_width, child_max].max
        end

        def shared_subexpressions?(root)
          seen = Set.new
          stack = [root]

          until stack.empty?
            expr = stack.pop
            next if expr.nil?

            expr_children(expr).each do |child|
              child_id = child.object_id
              return true if seen.include?(child_id)

              seen.add(child_id)
              stack << child
            end
          end

          false
        end

        def parent_counts(root)
          counts = Hash.new(0)
          seen = Set.new
          stack = [root]

          until stack.empty?
            expr = stack.pop
            next if expr.nil?

            children = expr_children(expr)
            children.each { |child| counts[child.object_id] += 1 }

            oid = expr.object_id
            next if seen.include?(oid)

            seen << oid
            children.each { |child| stack << child }
          end

          counts
        end

        def expr_children(expr)
          case expr
          when IR::UnaryOp
            [expr.operand]
          when IR::BinaryOp
            [expr.left, expr.right]
          when IR::Mux
            [expr.condition, expr.when_true, expr.when_false]
          when IR::Slice
            [expr.base]
          when IR::Concat
            Array(expr.parts)
          when IR::Resize
            [expr.expr]
          when IR::Case
            [expr.selector, expr.default, *expr.cases.values]
          when IR::MemoryRead
            [expr.addr]
          else
            []
          end.compact
        end

        def rebuild_expr(expr, children)
          case expr
          when IR::UnaryOp
            IR::UnaryOp.new(op: expr.op, operand: children.fetch(0), width: expr.width.to_i)
          when IR::BinaryOp
            IR::BinaryOp.new(op: expr.op, left: children.fetch(0), right: children.fetch(1), width: expr.width.to_i)
          when IR::Mux
            IR::Mux.new(
              condition: children.fetch(0),
              when_true: children.fetch(1),
              when_false: children.fetch(2),
              width: expr.width.to_i
            )
          when IR::Slice
            IR::Slice.new(base: children.fetch(0), range: expr.range, width: expr.width.to_i)
          when IR::Concat
            IR::Concat.new(parts: children, width: expr.width.to_i)
          when IR::Resize
            IR::Resize.new(expr: children.fetch(0), width: expr.width.to_i)
          when IR::Case
            IR::Case.new(
              selector: children.fetch(0),
              cases: expr.cases.keys.zip(children.drop(2)).to_h,
              default: children.fetch(1),
              width: expr.width.to_i
            )
          when IR::MemoryRead
            IR::MemoryRead.new(memory: expr.memory, addr: children.fetch(0), width: expr.width.to_i)
          else
            expr
          end
        end

        def dedupe_by_name(entries)
          entries.uniq { |entry| entry.name.to_s }
        end

        def dedupe_assigns_by_target(assigns)
          # The behavior DSL produces ordered conditional chains such as:
          #   read_to_acc <= 0                             (default)
          #   read_to_acc <= mux(cond1, 1, read_to_acc)   (override)
          #   read_to_acc <= mux(cond2, 1, read_to_acc)   (override)
          #
          # Each subsequent assignment references the signal itself in the
          # else branch of the mux, creating a priority chain.  To emit a
          # single deterministic assignment we inline the chain:
          #
          #   read_to_acc <= mux(cond2, 1, mux(cond1, 1, 0))
          #
          # We detect self-referential mux patterns and fold them into one
          # expression per target.

          grouped = Array(assigns).group_by { |a| a.target.to_s }
          grouped.flat_map do |_target, group|
            next group if group.length == 1

            # Try to fold a self-referential mux chain.
            # Each element after the first should be mux(cond, val, <self>).
            first = group.first
            merged_expr = first.expr

            group[1..].each do |assign|
              expr = assign.expr
              if self_referential_mux?(expr, assign.target.to_s)
                merged_expr = substitute_self_ref(expr, assign.target.to_s, merged_expr)
              else
                # Not a self-referential mux; cannot fold further.
                # Emit what we have merged so far plus the rest as-is.
                # This is a conservative fallback.
                merged_expr = expr
              end
            end

            [first.class.new(target: first.target, expr: merged_expr)]
          end
        end

        # Check whether an expression is a mux whose false-branch is a
        # direct self-reference to +target_name+.
        def self_referential_mux?(expr, target_name)
          return false unless expr.respond_to?(:kind) || expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux)

          if expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
            false_branch = expr.when_false
            return signal_name_matches?(false_branch, target_name)
          end

          false
        end

        def signal_name_matches?(expr, target_name)
          return false unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Signal)

          expr.name.to_s == target_name
        end

        # Replace the self-reference in a mux expression with +replacement+.
        def substitute_self_ref(expr, target_name, replacement)
          return expr unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux)

          false_branch = expr.when_false
          if signal_name_matches?(false_branch, target_name)
            RHDL::Codegen::CIRCT::IR::Mux.new(
              condition: expr.condition,
              when_true: expr.when_true,
              when_false: replacement,
              width: expr.width
            )
          else
            expr
          end
        end

        def sanitize_runtime_name(name)
          value = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          value = "_#{value}" if value.empty? || value.match?(/\A\d/)
          value
        end

        def serialize_module(mod, expr_cache:, compact_exprs: false)
          compact_state = compact_exprs ? { cache: {}, exprs: [], repeat_key_cache: {} } : nil

          serialized = {
            name: mod.name.to_s,
            ports: mod.ports.map { |p| serialize_port(p) },
            nets: mod.nets.map { |n| { name: n.name.to_s, width: n.width.to_i } },
            regs: mod.regs.map do |r|
              {
                name: r.name.to_s,
                width: r.width.to_i,
                reset_value: serialize_runtime_integer(r.reset_value)
              }
            end,
            assigns: mod.assigns.map do |a|
              {
                target: a.target.to_s,
                expr: serialize_runtime_expr(a.expr, expr_cache: expr_cache, compact_state: compact_state)
              }
            end,
            processes: mod.processes.map do |p|
              serialize_process(p, expr_cache: expr_cache, compact_state: compact_state)
            end,
            instances: mod.instances.map do |i|
              serialize_instance(i, expr_cache: expr_cache, compact_state: compact_state)
            end,
            memories: mod.memories.map { |m| serialize_memory(m) },
            write_ports: mod.write_ports.map do |w|
              serialize_write_port(w, expr_cache: expr_cache, compact_state: compact_state)
            end,
            sync_read_ports: mod.sync_read_ports.map do |r|
              serialize_sync_read_port(r, expr_cache: expr_cache, compact_state: compact_state)
            end,
            parameters: mod.parameters || {}
          }

          serialized[:exprs] = compact_state[:exprs] unless compact_state.nil? || compact_state[:exprs].empty?
          serialized
        end

        def serialize_port(port)
          {
            name: port.name.to_s,
            direction: port.direction.to_s,
            width: port.width.to_i,
            default: serialize_runtime_integer(port.default)
          }
        end

        def serialize_process(process, expr_cache:, compact_state: nil)
          {
            name: process.name.to_s,
            clocked: !!process.clocked,
            clock: process.clock&.to_s,
            sensitivity_list: Array(process.sensitivity_list).map(&:to_s),
            statements: Array(process.statements).map do |s|
              serialize_stmt(s, expr_cache: expr_cache, compact_state: compact_state)
            end
          }
        end

        def serialize_stmt(stmt, expr_cache:, compact_state: nil)
          case stmt
          when IR::SeqAssign
            {
              kind: 'seq_assign',
              target: stmt.target.to_s,
              expr: serialize_runtime_expr(stmt.expr, expr_cache: expr_cache, compact_state: compact_state)
            }
          when IR::If
            {
              kind: 'if',
              condition: serialize_runtime_expr(stmt.condition, expr_cache: expr_cache, compact_state: compact_state),
              then_statements: Array(stmt.then_statements).map do |s|
                serialize_stmt(s, expr_cache: expr_cache, compact_state: compact_state)
              end,
              else_statements: Array(stmt.else_statements).map do |s|
                serialize_stmt(s, expr_cache: expr_cache, compact_state: compact_state)
              end
            }
          else
            {
              kind: 'unknown',
              class: stmt.class.to_s
            }
          end
        end

        def serialize_runtime_expr(expr, expr_cache:, compact_state: nil)
          if compact_state
            serialize_expr_compact(
              expr,
              cache: compact_state[:cache],
              exprs: compact_state[:exprs],
              repeat_key_cache: compact_state[:repeat_key_cache]
            )
          else
            serialize_expr(expr, cache: expr_cache)
          end
        end

        def serialize_expr(expr, cache:)
          return nil if expr.nil?

          key = expr.object_id
          return cache[key] if cache.key?(key)

          cache[key] = case expr
          when IR::Signal
            { kind: 'signal', name: expr.name.to_s, width: expr.width.to_i }
          when IR::Literal
            { kind: 'literal', value: serialize_runtime_integer(expr.value), width: expr.width.to_i }
          when IR::UnaryOp
            { kind: 'unary', op: expr.op.to_s, operand: serialize_expr(expr.operand, cache: cache), width: expr.width.to_i }
          when IR::BinaryOp
            {
              kind: 'binary',
              op: expr.op.to_s,
              left: serialize_expr(expr.left, cache: cache),
              right: serialize_expr(expr.right, cache: cache),
              width: expr.width.to_i
            }
          when IR::Mux
            {
              kind: 'mux',
              condition: serialize_expr(expr.condition, cache: cache),
              when_true: serialize_expr(expr.when_true, cache: cache),
              when_false: serialize_expr(expr.when_false, cache: cache),
              width: expr.width.to_i
            }
          when IR::Slice
            {
              kind: 'slice',
              base: serialize_expr(expr.base, cache: cache),
              range_begin: expr.range.begin,
              range_end: expr.range.end,
              width: expr.width.to_i
            }
          when IR::Concat
            {
              kind: 'concat',
              parts: expr.parts.map { |p| serialize_expr(p, cache: cache) },
              width: expr.width.to_i
            }
          when IR::Resize
            {
              kind: 'resize',
              expr: serialize_expr(expr.expr, cache: cache),
              width: expr.width.to_i
            }
          when IR::Case
            {
              kind: 'case',
              selector: serialize_expr(expr.selector, cache: cache),
              cases: expr.cases.transform_values { |v| serialize_expr(v, cache: cache) },
              default: expr.default ? serialize_expr(expr.default, cache: cache) : nil,
              width: expr.width.to_i
            }
          when IR::MemoryRead
            {
              kind: 'memory_read',
              memory: expr.memory.to_s,
              addr: serialize_expr(expr.addr, cache: cache),
              width: expr.width.to_i
            }
          else
            {
              kind: 'unknown',
              class: expr.class.to_s
            }
          end
        end

        def serialize_expr_compact(expr, cache:, exprs:, repeat_key_cache:, force_pool: false)
          return nil if expr.nil?

          key = [expr.object_id, force_pool]
          return cache[key] if cache.key?(key)
          structural_key = compact_structural_pool_key(expr, cache: repeat_key_cache)
          structural_cache_key = structural_key ? [:structural, structural_key] : nil
          return cache[structural_cache_key] if structural_cache_key && cache.key?(structural_cache_key)

          result = case expr
                   when IR::Signal
                     if force_pool
                       expr_id = exprs.length
                       ref = { kind: 'expr_ref', id: expr_id, width: expr.width.to_i }
                       cache[key] = ref
                       exprs << nil
                       exprs[expr_id] = serialize_expr_compact_node(
                         expr,
                         cache: cache,
                         exprs: exprs,
                         repeat_key_cache: repeat_key_cache
                       )
                       ref
                     else
                       cache[key] = { kind: 'signal', name: expr.name.to_s, width: expr.width.to_i }
                     end
                   when IR::Literal
                     if force_pool
                       expr_id = exprs.length
                       ref = { kind: 'expr_ref', id: expr_id, width: expr.width.to_i }
                       cache[key] = ref
                       exprs << nil
                       exprs[expr_id] = serialize_expr_compact_node(
                         expr,
                         cache: cache,
                         exprs: exprs,
                         repeat_key_cache: repeat_key_cache
                       )
                       ref
                     else
                       cache[key] = { kind: 'literal', value: serialize_runtime_integer(expr.value), width: expr.width.to_i }
                     end
                   else
                     expr_id = exprs.length
                     ref = { kind: 'expr_ref', id: expr_id, width: expr.width.to_i }
                     cache[key] = ref
                     # Reserve the index before recursing so nested children cannot shift
                     # the parent node away from the expr_ref id we just assigned.
                     exprs << nil
                     exprs[expr_id] = serialize_expr_compact_node(
                       expr,
                       cache: cache,
                       exprs: exprs,
                       repeat_key_cache: repeat_key_cache
                     )
                     ref
                   end
          cache[structural_cache_key] = result if structural_cache_key
          result
        end

        def serialize_expr_compact_node(expr, cache:, exprs:, repeat_key_cache:)
          case expr
          when IR::Signal
            { kind: 'signal', name: expr.name.to_s, width: expr.width.to_i }
          when IR::Literal
            { kind: 'literal', value: serialize_runtime_integer(expr.value), width: expr.width.to_i }
          when IR::UnaryOp
            {
              kind: 'unary',
              op: expr.op.to_s,
              operand: serialize_expr_compact(expr.operand, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              width: expr.width.to_i
            }
          when IR::BinaryOp
            {
              kind: 'binary',
              op: expr.op.to_s,
              left: serialize_expr_compact(expr.left, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              right: serialize_expr_compact(expr.right, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              width: expr.width.to_i
            }
          when IR::Mux
            {
              kind: 'mux',
              condition: serialize_expr_compact(expr.condition, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              when_true: serialize_expr_compact(expr.when_true, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              when_false: serialize_expr_compact(expr.when_false, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              width: expr.width.to_i
            }
          when IR::Slice
            {
              kind: 'slice',
              base: serialize_expr_compact(expr.base, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              range_begin: expr.range.begin,
              range_end: expr.range.end,
              width: expr.width.to_i
            }
          when IR::Concat
            repeated_part = repeated_compact_concat_part(expr.parts, cache: repeat_key_cache)
            {
              kind: 'concat',
              parts: if repeated_part
                       repeated_ref = serialize_expr_compact(
                         repeated_part,
                         cache: cache,
                         exprs: exprs,
                         repeat_key_cache: repeat_key_cache,
                         force_pool: true
                       )
                       Array.new(expr.parts.length) { repeated_ref.dup }
                     else
                       expr.parts.map do |part|
                         serialize_expr_compact(part, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache)
                       end
                     end,
              width: expr.width.to_i
            }
          when IR::Resize
            {
              kind: 'resize',
              expr: serialize_expr_compact(expr.expr, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              width: expr.width.to_i
            }
          when IR::Case
            {
              kind: 'case',
              selector: serialize_expr_compact(expr.selector, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              cases: expr.cases.transform_values do |value|
                serialize_expr_compact(value, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache)
              end,
              default: expr.default ? serialize_expr_compact(expr.default, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache) : nil,
              width: expr.width.to_i
            }
          when IR::MemoryRead
            {
              kind: 'memory_read',
              memory: expr.memory.to_s,
              addr: serialize_expr_compact(expr.addr, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache),
              width: expr.width.to_i
            }
          when IR::Signal, IR::Literal
            serialize_expr_compact(expr, cache: cache, exprs: exprs, repeat_key_cache: repeat_key_cache)
          else
            {
              kind: 'unknown',
              class: expr.class.to_s
            }
          end
        end

        def repeated_compact_concat_part(parts, cache:)
          first = Array(parts).first
          return nil if first.nil? || parts.length < 2

          first_key = compact_repeat_key(first, cache: cache)
          return nil unless parts.all? { |part| compact_repeat_key(part, cache: cache) == first_key }

          first
        end

        def compact_repeat_key(expr, cache:)
          return nil if expr.nil?

          key = expr.object_id
          return cache[key] if cache.key?(key)

          cache[key] = case expr
                       when IR::Signal
                         [:signal, expr.name.to_s, expr.width.to_i]
                       when IR::Literal
                         [:literal, serialize_runtime_integer(expr.value), expr.width.to_i]
                       when IR::UnaryOp
                         [:unary, expr.op.to_s, compact_repeat_key(expr.operand, cache: cache), expr.width.to_i]
                       when IR::BinaryOp
                         [:binary, expr.op.to_s, compact_repeat_key(expr.left, cache: cache), compact_repeat_key(expr.right, cache: cache), expr.width.to_i]
                       when IR::Mux
                         [:mux, compact_repeat_key(expr.condition, cache: cache), compact_repeat_key(expr.when_true, cache: cache), compact_repeat_key(expr.when_false, cache: cache), expr.width.to_i]
                       when IR::Slice
                         [:slice, compact_repeat_key(expr.base, cache: cache), expr.range.begin, expr.range.end, expr.width.to_i]
                       when IR::Concat
                         [:concat, expr.parts.map { |part| compact_repeat_key(part, cache: cache) }, expr.width.to_i]
                       when IR::Resize
                         [:resize, compact_repeat_key(expr.expr, cache: cache), expr.width.to_i]
                       when IR::Case
                         [:case, compact_repeat_key(expr.selector, cache: cache), expr.cases.transform_values { |value| compact_repeat_key(value, cache: cache) }, compact_repeat_key(expr.default, cache: cache), expr.width.to_i]
                       when IR::MemoryRead
                         [:memory_read, expr.memory.to_s, compact_repeat_key(expr.addr, cache: cache), expr.width.to_i]
                       else
                         [:unknown, expr.class.to_s]
                       end
        end

        def compact_structural_pool_key(expr, cache:)
          case expr
          when IR::Slice, IR::Resize, IR::BinaryOp, IR::Mux
            compact_repeat_key(expr, cache: cache)
          else
            nil
          end
        end

        def serialize_runtime_integer(value)
          return nil if value.nil?

          normalized = if value.is_a?(Float) && value.finite? && value == value.truncate
                         value.to_i
                       else
                         value
                       end

          return normalized unless normalized.is_a?(Integer)

          if normalized.negative?
            normalized < JSON_I64_MIN ? normalized.to_s : normalized
          else
            normalized > JSON_U64_MAX ? normalized.to_s : normalized
          end
        end

        def serialize_instance(instance, expr_cache:, compact_state: nil)
          {
            name: instance.name.to_s,
            module_name: instance.module_name.to_s,
            parameters: instance.parameters || {},
            connections: instance.connections.map do |c|
              {
                port_name: c.port_name.to_s,
                signal: if c.signal.respond_to?(:width)
                          serialize_runtime_expr(c.signal, expr_cache: expr_cache, compact_state: compact_state)
                        else
                          c.signal.to_s
                        end,
                direction: c.direction.to_s
              }
            end
          }
        end

        def serialize_memory(memory)
          {
            name: memory.name.to_s,
            depth: memory.depth.to_i,
            width: memory.width.to_i,
            initial_data: memory.initial_data
          }
        end

        def serialize_write_port(wp, expr_cache:, compact_state: nil)
          {
            memory: wp.memory.to_s,
            clock: wp.clock.to_s,
            addr: serialize_runtime_expr(wp.addr, expr_cache: expr_cache, compact_state: compact_state),
            data: serialize_runtime_expr(wp.data, expr_cache: expr_cache, compact_state: compact_state),
            enable: serialize_runtime_expr(wp.enable, expr_cache: expr_cache, compact_state: compact_state)
          }
        end

        def serialize_sync_read_port(rp, expr_cache:, compact_state: nil)
          {
            memory: rp.memory.to_s,
            clock: rp.clock.to_s,
            addr: serialize_runtime_expr(rp.addr, expr_cache: expr_cache, compact_state: compact_state),
            data: rp.data.to_s,
            enable: rp.enable ? serialize_runtime_expr(rp.enable, expr_cache: expr_cache, compact_state: compact_state) : nil
          }
        end

        def write_compact_runtime_payload(io, nodes_or_package)
          modules = normalized_runtime_modules_from_input(nodes_or_package, compact_exprs: true)
          io.write('{"circt_json_version":1,"dialects":["hw","comb","seq"],"modules":[')
          modules.each_with_index do |mod, index|
            io.write(',') if index.positive?
            write_compact_module_json(io, mod)
          end
          io.write(']}')
        end

        def write_compact_module_json(io, mod)
          expr_cache = {}
          compact_state = { cache: {}, exprs: [], repeat_key_cache: {} }

          write_json_object(io) do |field|
            field.call('name')
            JSON.dump(mod.name.to_s, io)

            field.call('ports')
            write_json_array(io, mod.ports) { |port| JSON.dump(serialize_port(port), io, false) }

            field.call('nets')
            write_json_array(io, mod.nets) do |net|
              JSON.dump({ name: net.name.to_s, width: net.width.to_i }, io, false)
            end

            field.call('regs')
            write_json_array(io, mod.regs) do |reg|
              JSON.dump(
                {
                  name: reg.name.to_s,
                  width: reg.width.to_i,
                  reset_value: serialize_runtime_integer(reg.reset_value)
                },
                io,
                false
              )
            end

            field.call('assigns')
            write_json_array(io, mod.assigns) do |assign|
              JSON.dump(
                {
                  target: assign.target.to_s,
                  expr: serialize_runtime_expr(assign.expr, expr_cache: expr_cache, compact_state: compact_state)
                },
                io,
                false
              )
            end

            field.call('processes')
            write_json_array(io, mod.processes) do |process|
              JSON.dump(
                serialize_process(process, expr_cache: expr_cache, compact_state: compact_state),
                io,
                false
              )
            end

            field.call('instances')
            write_json_array(io, mod.instances) do |instance|
              JSON.dump(
                serialize_instance(instance, expr_cache: expr_cache, compact_state: compact_state),
                io,
                false
              )
            end

            field.call('memories')
            write_json_array(io, mod.memories) { |memory| JSON.dump(serialize_memory(memory), io, false) }

            field.call('write_ports')
            write_json_array(io, mod.write_ports) do |write_port|
              JSON.dump(
                serialize_write_port(write_port, expr_cache: expr_cache, compact_state: compact_state),
                io,
                false
              )
            end

            field.call('sync_read_ports')
            write_json_array(io, mod.sync_read_ports) do |sync_read_port|
              JSON.dump(
                serialize_sync_read_port(sync_read_port, expr_cache: expr_cache, compact_state: compact_state),
                io,
                false
              )
            end

            field.call('parameters')
            JSON.dump(mod.parameters || {}, io, false)

            unless compact_state[:exprs].empty?
              field.call('exprs')
              write_json_array(io, compact_state[:exprs]) { |expr| JSON.dump(expr, io, false) }
            end
          end
        end

        def write_json_array(io, items)
          io.write('[')
          Array(items).each_with_index do |item, index|
            io.write(',') if index.positive?
            yield item
          end
          io.write(']')
        end

        def write_json_object(io)
          io.write('{')
          first = true
          emit_field = lambda do |key|
            io.write(',') unless first
            first = false
            JSON.dump(key, io)
            io.write(':')
          end
          yield emit_field
          io.write('}')
        end
      end
    end
  end
end
