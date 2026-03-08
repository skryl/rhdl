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

        def dump(nodes_or_package)
          modules = case nodes_or_package
                    when IR::Package
                      nodes_or_package.modules
                    when Array
                      nodes_or_package
                    else
                      [nodes_or_package]
                    end

          modules = Array(modules).map do |mod|
            assign_map = Array(mod.assigns).each_with_object({}) do |assign, mapping|
              mapping[assign.target.to_s] ||= assign.expr
            end
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
          expr_cache = {}
          payload = {
            circt_json_version: 1,
            dialects: %w[hw comb seq],
            modules: modules.map { |mod| serialize_module(mod, expr_cache: expr_cache) }
          }

          JSON.generate(payload, max_nesting: false)
        end

        def normalize_modules_for_runtime(modules)
          Array(modules).map { |mod| normalize_module_for_runtime(mod) }
        end

        def normalize_module_for_runtime(mod, live_assign_targets: nil, assign_map: nil, inlineable_names: nil,
                                         signal_widths: nil, runtime_sensitive_names: nil, needs_cache: nil,
                                         simplify_cache: nil)
          temp_counter = 0
          extra_nets = []
          extra_assigns = []
          inlineable_names ||= Array(mod.nets).map { |net| net.name.to_s }.to_set
          simplification_needed_cache = needs_cache || {}
          simplification_cache = simplify_cache || {}
          assign_map ||= Array(mod.assigns).each_with_object({}) do |assign, mapping|
            mapping[assign.target.to_s] ||= assign.expr
          end
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
            expr = assign.expr
            target_runtime_sensitive = runtime_sensitive_names.include?(target_name)
            hoist_candidate = expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat) || expr.is_a?(IR::Case)

            unless target_runtime_sensitive || hoist_candidate
              next assign
            end

            simplified_expr = if target_runtime_sensitive
                                simplify_runtime_expr_if_needed(
                                  expr,
                                  assign_map: assign_map,
                                  inlineable_names: inlineable_names,
                                  needs_cache: simplification_needed_cache,
                                  simplify_cache: simplification_cache,
                                  runtime_sensitive_names: runtime_sensitive_names
                                )
                              else
                                expr
                              end
            expr, hoisted_assigns = hoist_shared_exprs_to_assigns(
              simplified_expr,
              temp_counter: temp_counter,
              prefix: "#{target_name}_rt"
            )
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
              needs_cache: simplification_needed_cache,
              simplify_cache: simplification_cache,
              runtime_sensitive_names: runtime_sensitive_names
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
                sensitivity_list: process.sensitivity_list
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

          prune_dead_runtime_assigns_and_signals(normalized_module)
        end

        def normalize_process_statements(statements, temp_counter:, prefix:, assign_map:, inlineable_names:, needs_cache:,
                                         simplify_cache:, runtime_sensitive_names:)
          extra_assigns = []
          extra_nets = []
          normalized = Array(statements).map do |stmt|
            case stmt
            when IR::SeqAssign
              target_name = stmt.target.to_s
              expr = stmt.expr
              target_runtime_sensitive = runtime_sensitive_names.include?(target_name)
              hoist_candidate = expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat) || expr.is_a?(IR::Case)
              unless target_runtime_sensitive || hoist_candidate
                next stmt
              end

              simplified_expr = if target_runtime_sensitive
                                  simplify_runtime_expr_if_needed(
                                    expr,
                                    assign_map: assign_map,
                                    inlineable_names: inlineable_names,
                                    needs_cache: needs_cache,
                                    simplify_cache: simplify_cache,
                                    runtime_sensitive_names: runtime_sensitive_names
                                  )
                                else
                                  expr
                                end
              expr, hoisted_assigns = hoist_shared_exprs_to_assigns(
                simplified_expr,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_#{target_name}"
              )
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
              cond, hoisted_assigns = hoist_shared_exprs_to_assigns(
                simplified_condition,
                temp_counter: temp_counter + extra_assigns.length,
                prefix: "#{prefix}_if"
              )
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
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names
              )
              else_stmts, else_assigns, else_nets = normalize_process_statements(
                stmt.else_statements,
                temp_counter: temp_counter + extra_assigns.length + then_assigns.length,
                prefix: "#{prefix}_else",
                assign_map: assign_map,
                inlineable_names: inlineable_names,
                needs_cache: needs_cache,
                simplify_cache: simplify_cache,
                runtime_sensitive_names: runtime_sensitive_names
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
                                           needs_cache:, cache:, raw_cache:, expanding: Set.new)
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

          cache_key = expanding.empty? ? expr.object_id : [expr.object_id, expanding.to_a.sort]
          return cache[cache_key] if cache.key?(cache_key)

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
                   runtime_simplified_signal_refs(
                     expr.left,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   ) |
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
                 when IR::Mux
                   runtime_simplified_signal_refs(
                     expr.condition,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   ) |
                     runtime_simplified_signal_refs(
                       expr.when_true,
                       assign_map: assign_map,
                       inlineable_names: inlineable_names,
                       runtime_sensitive_names: runtime_sensitive_names,
                       needs_cache: needs_cache,
                       cache: cache,
                       raw_cache: raw_cache,
                       expanding: expanding
                     ) |
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

          cache[cache_key] = refs.frozen? ? refs : refs.freeze
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

          next_expanding = expanding.dup
          next_expanding << name
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

          slice_cache_key = [base_expr.object_id, low, high, expanding.empty? ? nil : expanding.to_a.sort]
          return cache[slice_cache_key] if cache.key?(slice_cache_key)

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
                     next_expanding = expanding.dup
                     next_expanding << name
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
                   runtime_simplified_signal_refs(
                     base_expr.condition,
                     assign_map: assign_map,
                     inlineable_names: inlineable_names,
                     runtime_sensitive_names: runtime_sensitive_names,
                     needs_cache: needs_cache,
                     cache: cache,
                     raw_cache: raw_cache,
                     expanding: expanding
                   ) |
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
                     ) |
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

          cache[slice_cache_key] = refs.frozen? ? refs : refs.freeze
        end

        def runtime_signal_should_inline?(name, assign_map:, inlineable_names:, runtime_sensitive_names:, expanding:)
          runtime_sensitive_names.include?(name) &&
            inlineable_names.include?(name) &&
            !expanding.include?(name) &&
            assign_map.key?(name)
        end

        def needs_runtime_simplification?(expr, assign_map:, inlineable_names:, expanding: Set.new, cache: {},
                                          runtime_sensitive_names:)
          return false if expr.nil?
          return false if expr.is_a?(IR::Literal)
          if expr.is_a?(IR::Signal)
            signal_name = expr.name.to_s
            return false if expr.width.to_i <= 64 && !runtime_sensitive_names.include?(signal_name)
          end

          cache_key = expanding.empty? ? expr.object_id : [expr.object_id, expanding.to_a.sort]
          return cache[cache_key] if cache.key?(cache_key)

          cache[cache_key] = case expr
                             when IR::Signal
                               name = expr.name.to_s
                               if runtime_sensitive_names.include?(name) && inlineable_names.include?(name) &&
                                  !expanding.include?(name)
                                 assigned_expr = assign_map[name]
                                 next_expanding = expanding.dup
                                 next_expanding << name
                                 expr.width.to_i > 64 || (
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
                                 expr.width.to_i > 64
                               end
                             when IR::Slice
                               expr.base.respond_to?(:width) && expr.base.width.to_i > 64 ||
                                 needs_runtime_simplification?(
                                   expr.base,
                                   assign_map: assign_map,
                                   inlineable_names: inlineable_names,
                                   expanding: expanding,
                                   cache: cache,
                                   runtime_sensitive_names: runtime_sensitive_names
                                 )
                             when IR::Concat
                               expr.width.to_i > 64 || expr.parts.any? do |part|
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
                               expr.width.to_i > 64 ||
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
                               expr.width.to_i > 64 ||
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
                               expr.width.to_i > 64 ||
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
        end

        def simplify_expr_for_runtime(expr, assign_map:, inlineable_names:, expanding: Set.new, cache: nil,
                                      needs_cache: {}, runtime_sensitive_names:)
          return expr if expr.nil?
          if expr.is_a?(IR::Literal)
            return expr
          elsif expr.is_a?(IR::Signal)
            signal_name = expr.name.to_s
            return expr if expr.width.to_i <= 64 && !runtime_sensitive_names.include?(signal_name)
          end

          cache ||= {}
          cache_key = expanding.empty? ? expr.object_id : [expr.object_id, expanding.to_a.sort]
          return cache[cache_key] if cache.key?(cache_key)

          cache[cache_key] = case expr
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
        end

        def inline_signal_expr(expr, assign_map:, inlineable_names:, expanding:, cache:, needs_cache:,
                               runtime_sensitive_names:)
          name = expr.name.to_s
          return expr unless inlineable_names.include?(name)
          return expr unless runtime_sensitive_names.include?(name)
          return expr if expanding.include?(name)

          assigned_expr = assign_map[name]
          return expr unless assigned_expr

          next_expanding = expanding.dup
          next_expanding << name

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
          base = simplify_expr_for_runtime(
            expr.base,
            assign_map: assign_map,
            inlineable_names: inlineable_names,
            expanding: expanding,
            cache: cache,
            needs_cache: needs_cache,
            runtime_sensitive_names: runtime_sensitive_names
          )
          low, high = normalized_slice_bounds(expr.range)
          width = expr.width.to_i

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
          parts = expr.parts.flat_map do |part|
            simplified = simplify_expr_for_runtime(
              part,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              expanding: expanding,
              cache: cache,
              needs_cache: needs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            simplified.is_a?(IR::Concat) ? simplified.parts : [simplified]
          end
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
          return signal_cache[signal_name] = true if signal_widths[signal_name].to_i > 64

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
                                    expr.width.to_i > 64 || signal_requires_runtime_simplification?(
                                      expr.name,
                                      assign_map: assign_map,
                                      signal_widths: signal_widths,
                                      signal_cache: signal_cache,
                                      expr_cache: expr_cache,
                                      visiting: visiting
                                    )
                                  when IR::Slice
                                    (expr.base.respond_to?(:width) && expr.base.width.to_i > 64) ||
                                      expr_requires_runtime_simplification?(
                                        expr.base,
                                        assign_map: assign_map,
                                        signal_widths: signal_widths,
                                        signal_cache: signal_cache,
                                        expr_cache: expr_cache,
                                        visiting: visiting
                                      )
                                  when IR::Concat
                                    expr.width.to_i > 64 || expr.parts.any? do |part|
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
                                    expr.width.to_i > 64 || [expr.condition, expr.when_true, expr.when_false].compact.any? do |part|
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
                                    expr.width.to_i > 64 || expr_requires_runtime_simplification?(
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
                                    expr.width.to_i > 64 || expr_requires_runtime_simplification?(
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

        def runtime_live_assign_targets_from_expr_graph(mod)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          live_assign_targets = output_targets | runtime_non_assign_signal_refs(mod)
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
          assign_map ||= Array(mod.assigns).each_with_object({}) do |assign, mapping|
            mapping[assign.target.to_s] ||= assign.expr
          end
          inlineable_names ||= Array(mod.nets).map { |net| net.name.to_s }.to_set
          if runtime_sensitive_names.nil?
            runtime_sensitive_names = runtime_sensitive_signal_names(
              assign_map: assign_map,
              signal_widths: build_signal_width_map(mod)
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

            refs = runtime_simplified_signal_refs(
              assigned_expr,
              assign_map: assign_map,
              inlineable_names: inlineable_names,
              needs_cache: simplification_needed_cache,
              cache: signal_refs_cache,
              raw_cache: raw_signal_refs_cache,
              runtime_sensitive_names: runtime_sensitive_names
            )
            refs.each do |ref|
              next if live_assign_targets.include?(ref)

              live_assign_targets.add(ref)
              worklist << ref
            end
          end

          live_assign_targets
        end

        def prune_dead_runtime_assigns_and_signals(mod)
          output_targets = Array(mod.ports)
                           .select { |port| port.direction.to_sym == :out }
                           .map { |port| port.name.to_s }
                           .to_set
          live_assign_targets = runtime_live_assign_targets_from_expr_graph(mod)

          filtered_assigns = mod.assigns.select { |assign| live_assign_targets.include?(assign.target.to_s) }
          required_signal_names = output_targets.dup
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
                   signal_refs_from_expr(expr.left, cache: cache, visiting: visiting) |
                     signal_refs_from_expr(expr.right, cache: cache, visiting: visiting)
                 when IR::Mux
                   signal_refs_from_expr(expr.condition, cache: cache, visiting: visiting) |
                     signal_refs_from_expr(expr.when_true, cache: cache, visiting: visiting) |
                     signal_refs_from_expr(expr.when_false, cache: cache, visiting: visiting)
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

        def hoist_shared_exprs_to_assigns(expr, temp_counter:, prefix:)
          return [expr, []] if expr.nil? || expr.is_a?(IR::Literal) || expr.is_a?(IR::Signal)
          return [expr, []] unless expr.is_a?(IR::Mux) || expr.is_a?(IR::Concat) || expr.is_a?(IR::Case)
          return [expr, []] unless shared_subexpressions?(expr)

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
            counter_ref: counter_ref
          )
          [rewritten, assigns]
        end

        def rewrite_expr_for_runtime(expr, counts:, hoisted:, assigns:, prefix:, counter_ref:)
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
              counter_ref: counter_ref
            )
          end
          rewritten = rebuild_expr(expr, rewritten_children)

          if counts[oid].to_i > 1 && expr.width.to_i <= MAX_RUNTIME_SIGNAL_WIDTH
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
          seen_targets = Set.new
          Array(assigns).each_with_object([]) do |assign, deduped|
            target = assign.target.to_s
            next if seen_targets.include?(target)

            seen_targets.add(target)
            deduped << assign
          end
        end

        def sanitize_runtime_name(name)
          value = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
          value = "_#{value}" if value.empty? || value.match?(/\A\d/)
          value
        end

        def serialize_module(mod, expr_cache:)
          {
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
            assigns: mod.assigns.map { |a| { target: a.target.to_s, expr: serialize_expr(a.expr, cache: expr_cache) } },
            processes: mod.processes.map { |p| serialize_process(p, expr_cache: expr_cache) },
            instances: mod.instances.map { |i| serialize_instance(i, expr_cache: expr_cache) },
            memories: mod.memories.map { |m| serialize_memory(m) },
            write_ports: mod.write_ports.map { |w| serialize_write_port(w, expr_cache: expr_cache) },
            sync_read_ports: mod.sync_read_ports.map { |r| serialize_sync_read_port(r, expr_cache: expr_cache) },
            parameters: mod.parameters || {}
          }
        end

        def serialize_port(port)
          {
            name: port.name.to_s,
            direction: port.direction.to_s,
            width: port.width.to_i,
            default: serialize_runtime_integer(port.default)
          }
        end

        def serialize_process(process, expr_cache:)
          {
            name: process.name.to_s,
            clocked: !!process.clocked,
            clock: process.clock&.to_s,
            sensitivity_list: Array(process.sensitivity_list).map(&:to_s),
            statements: Array(process.statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) }
          }
        end

        def serialize_stmt(stmt, expr_cache:)
          case stmt
          when IR::SeqAssign
            {
              kind: 'seq_assign',
              target: stmt.target.to_s,
              expr: serialize_expr(stmt.expr, cache: expr_cache)
            }
          when IR::If
            {
              kind: 'if',
              condition: serialize_expr(stmt.condition, cache: expr_cache),
              then_statements: Array(stmt.then_statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) },
              else_statements: Array(stmt.else_statements).map { |s| serialize_stmt(s, expr_cache: expr_cache) }
            }
          else
            {
              kind: 'unknown',
              class: stmt.class.to_s
            }
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

        def serialize_instance(instance, expr_cache:)
          {
            name: instance.name.to_s,
            module_name: instance.module_name.to_s,
            parameters: instance.parameters || {},
            connections: instance.connections.map do |c|
              {
                port_name: c.port_name.to_s,
                signal: c.signal.respond_to?(:width) ? serialize_expr(c.signal, cache: expr_cache) : c.signal.to_s,
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

        def serialize_write_port(wp, expr_cache:)
          {
            memory: wp.memory.to_s,
            clock: wp.clock.to_s,
            addr: serialize_expr(wp.addr, cache: expr_cache),
            data: serialize_expr(wp.data, cache: expr_cache),
            enable: serialize_expr(wp.enable, cache: expr_cache)
          }
        end

        def serialize_sync_read_port(rp, expr_cache:)
          {
            memory: rp.memory.to_s,
            clock: rp.clock.to_s,
            addr: serialize_expr(rp.addr, cache: expr_cache),
            data: rp.data.to_s,
            enable: rp.enable ? serialize_expr(rp.enable, cache: expr_cache) : nil
          }
        end
      end
    end
  end
end
