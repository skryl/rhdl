# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'digest'
require 'set'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe 'GameBoy mixed import Verilog roundtrip AST comparison', slow: true do
  MAX_STRICT_OUTPUT_EXPR_COMPLEXITY = 128
  MAX_STRICT_OUTPUT_MUX_NODES = 7
  EXPECTED_STRUCTURAL_MISMATCHES = %w[
  ].freeze

  def roundtrip_trace?
    ENV['RHDL_GAMEBOY_ROUNDTRIP_TRACE'] == '1'
  end

  def timed_roundtrip_step(label)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    puts "[gameboy roundtrip] #{label}: #{format('%.2fs', elapsed)}" if roundtrip_trace?
    result
  end


  def require_reference_tree!
    skip 'GameBoy reference tree not available' unless Dir.exist?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_REFERENCE_ROOT)
    skip 'GameBoy files.qip not available' unless File.file?(RHDL::Examples::GameBoy::Import::SystemImporter::DEFAULT_QIP_PATH)
  end

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def export_tool
    return 'firtool' if HdlToolchain.which('firtool')
    return 'circt-translate' if HdlToolchain.which('circt-translate')

    nil
  end

  def require_export_tool!
    skip 'firtool or circt-translate not available for MLIR export' unless export_tool
  end

  def diagnostic_summary(result)
    return '' unless result.respond_to?(:diagnostics)

    Array(result.diagnostics).map do |diag|
      if diag.respond_to?(:severity) && diag.respond_to?(:message)
        "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
      else
        diag.to_s
      end
    end.join("\n")
  end

  def convert_verilog_to_mlir(verilog_source, base_dir:, stem:)
    FileUtils.mkdir_p(base_dir)
    verilog_path = File.join(base_dir, "#{stem}.v")
    core_mlir_path = File.join(base_dir, "#{stem}.core.mlir")
    File.write(verilog_path, verilog_source)

    result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
      verilog_path: verilog_path,
      out_path: core_mlir_path,
      tool: 'circt-verilog'
    )
    expect(result[:success]).to be(true), "Verilog->CIRCT failed:\n#{result[:command]}\n#{result[:stderr]}"
    File.read(core_mlir_path)
  end

  def convert_mlir_to_verilog(mlir_source, base_dir:, stem:)
    mlir_path = File.join(base_dir, "#{stem}.mlir")
    verilog_path = File.join(base_dir, "#{stem}.v")
    File.write(mlir_path, mlir_source)
    tool = export_tool

    result = RHDL::Codegen::CIRCT::Tooling.circt_mlir_to_verilog(
      mlir_path: mlir_path,
      out_path: verilog_path,
      tool: tool
    )
    expect(result[:success]).to be(true), "CIRCT->Verilog failed:\n#{result[:command]}\n#{result[:stderr]}"
    File.read(verilog_path)
  end

  def normalized_module_signatures_from_verilog(verilog_source, base_dir:, stem:)
    mlir = convert_verilog_to_mlir(verilog_source, base_dir: base_dir, stem: stem)
    cleanup = RHDL::Codegen::CIRCT::ImportCleanup.cleanup_imported_core_mlir(
      mlir,
      strict: true
    )
    expect(cleanup.success?).to be(true), diagnostic_summary(cleanup.import_result)

    import_result = RHDL::Codegen.import_circt_mlir(cleanup.cleaned_text)
    expect(import_result.success?).to be(true), diagnostic_summary(import_result)

    import_result.modules.each_with_object({}) do |mod, acc|
      acc[mod.name.to_s] = semantic_signature_for_module(mod)
    end
  end

  def semantic_signature_for_module(mod)
    assigns_by_target = Hash.new { |h, k| h[k] = [] }
    mod.assigns.each { |assign| assigns_by_target[assign.target.to_s] << assign.expr }
    process_outputs = process_driver_exprs_by_target(mod)
    input_names = mod.ports.select { |p| p.direction.to_s == 'in' }.map { |p| p.name.to_s }.to_set
    output_names = mod.ports.select { |p| p.direction.to_s == 'out' }.map { |p| p.name.to_s }.to_set
    state_names = mod.regs.map { |r| r.name.to_s }.to_set
    Array(mod.processes).each do |process|
      next unless process&.clocked
      collect_clocked_targets(Array(process.statements)).each { |name| state_names << name }
    end
    outputs = mod.ports.select { |p| p.direction.to_s == 'out' }

    resolve_ctx = {
      assigns_by_target: assigns_by_target,
      process_outputs_by_target: process_outputs,
      input_names: input_names,
      output_names: output_names,
      state_names: state_names,
      resolving: Set.new,
      signal_cache: {}
    }
    resolve_memo = {}
    simplify_memo = {}
    signature_memo = {}
    complexity_memo = {}
    mux_count_memo = {}

    output_signatures = outputs.map do |port|
      expr = select_driver_expr(assigns_by_target[port.name.to_s], port.name.to_s)
      expr ||= process_outputs[port.name.to_s]
      expr ||= RHDL::Codegen::CIRCT::IR::Literal.new(value: 0, width: port.width.to_i)
      resolved = resolve_expr_signals(expr, resolve_ctx, resolve_memo)
      simplified = simplify_expr(resolved, simplify_memo)
      complexity = expr_complexity(simplified, complexity_memo)
      mux_nodes = mux_node_count_in_expr(simplified, mux_count_memo)
      signature =
        if complexity > MAX_STRICT_OUTPUT_EXPR_COMPLEXITY || mux_nodes >= MAX_STRICT_OUTPUT_MUX_NODES
          [:complex_output, port.width.to_i]
        else
          expr_signature(simplified, signature_memo)
        end
      [port.name.to_s, signature]
    end

    {
      parameter_values: stable_sort((mod.parameters || {}).values.map(&:to_s)),
      ports: stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
      outputs: output_signatures.sort_by(&:first)
    }
  end

  def collect_clocked_targets(statements, acc = Set.new)
    Array(statements).each do |stmt|
      case stmt
      when RHDL::Codegen::CIRCT::IR::SeqAssign
        acc << stmt.target.to_s
      when RHDL::Codegen::CIRCT::IR::If
        collect_clocked_targets(Array(stmt.then_statements), acc)
        collect_clocked_targets(Array(stmt.else_statements), acc)
      end
    end
    acc
  end

  def process_driver_exprs_by_target(mod)
    width_map = signal_width_map(mod)
    combined = {}
    Array(mod.processes).each do |process|
      next unless process
      next if process.clocked

      state = evaluate_process_statements(
        statements: Array(process.statements),
        incoming_state: {},
        width_map: width_map
      )
      state.each { |target, expr| combined[target.to_s] = expr }
    end
    combined
  end

  def signal_width_map(mod)
    map = {}
    Array(mod.ports).each { |port| map[port.name.to_s] = port.width.to_i }
    Array(mod.nets).each { |net| map[net.name.to_s] = net.width.to_i }
    Array(mod.regs).each { |reg| map[reg.name.to_s] = reg.width.to_i }
    map
  end

  def evaluate_process_statements(statements:, incoming_state:, width_map:)
    state = incoming_state.dup
    statements.each do |stmt|
      case stmt
      when RHDL::Codegen::CIRCT::IR::SeqAssign
        state[stmt.target.to_s] = stmt.expr
      when RHDL::Codegen::CIRCT::IR::If
        before = state.dup
        then_state = evaluate_process_statements(
          statements: Array(stmt.then_statements),
          incoming_state: before.dup,
          width_map: width_map
        )
        else_state = evaluate_process_statements(
          statements: Array(stmt.else_statements),
          incoming_state: before.dup,
          width_map: width_map
        )
        state = merge_if_states(
          condition: stmt.condition,
          before: before,
          then_state: then_state,
          else_state: else_state,
          width_map: width_map
        )
      end
    end
    state
  end

  def merge_if_states(condition:, before:, then_state:, else_state:, width_map:)
    merged = before.dup
    keys = before.keys | then_state.keys | else_state.keys
    keys.each do |key|
      then_expr = then_state[key] || before[key] || default_signal_expr(name: key, width_map: width_map)
      else_expr = else_state[key] || before[key] || default_signal_expr(name: key, width_map: width_map)
      if expr_signature(then_expr) == expr_signature(else_expr)
        merged[key] = then_expr
      else
        merged[key] = RHDL::Codegen::CIRCT::IR::Mux.new(
          condition: condition,
          when_true: then_expr,
          when_false: else_expr,
          width: [then_expr.width.to_i, else_expr.width.to_i].max
        )
      end
    end
    merged
  end

  def default_signal_expr(name:, width_map:)
    RHDL::Codegen::CIRCT::IR::Signal.new(name: name.to_s, width: [width_map[name.to_s].to_i, 1].max)
  end

  def select_driver_expr(exprs, target_name)
    all = Array(exprs)
    filtered = all.reject do |expr|
      expr.is_a?(RHDL::Codegen::CIRCT::IR::Signal) && expr.name.to_s == target_name.to_s
    end
    candidates = filtered.empty? ? all : filtered
    best_driver_expr(candidates)
  end

  def best_driver_expr(exprs)
    candidates = Array(exprs).compact
    return nil if candidates.empty?

    candidates.max_by do |expr|
      [
        expr.is_a?(RHDL::Codegen::CIRCT::IR::Literal) ? 0 : 1,
        expr_complexity(expr, {})
      ]
    end
  end

  def resolve_expr_signals(expr, ctx, memo)
    key = expr.object_id
    return memo[key] if memo.key?(key)

    resolved = case expr
              when RHDL::Codegen::CIRCT::IR::Signal
                name = expr.name.to_s
                if ctx[:input_names].include?(name) || ctx[:state_names].include?(name) || ctx[:resolving].include?(name)
                  expr
                elsif ctx[:signal_cache].key?(name)
                  ctx[:signal_cache][name]
                else
                  drivers = Array(ctx[:assigns_by_target][name])
                  drivers = drivers.reject do |driver|
                    driver.is_a?(RHDL::Codegen::CIRCT::IR::Signal) && driver.name.to_s == name
                  end
                  if drivers.empty? && ctx[:output_names].include?(name) && ctx[:process_outputs_by_target].key?(name)
                    drivers = [ctx[:process_outputs_by_target][name]]
                  end
                  if drivers.length != 1
                    expr
                  else
                    driver = select_driver_expr(drivers, name)
                    if driver
                      ctx[:resolving] << name
                      out = resolve_expr_signals(driver, ctx, memo)
                      ctx[:resolving].delete(name)
                      ctx[:signal_cache][name] = out
                    else
                      expr
                    end
                  end
                end
               when RHDL::Codegen::CIRCT::IR::UnaryOp
                 RHDL::Codegen::CIRCT::IR::UnaryOp.new(
                   op: expr.op,
                   operand: resolve_expr_signals(expr.operand, ctx, memo),
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::BinaryOp
                 RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                   op: expr.op,
                   left: resolve_expr_signals(expr.left, ctx, memo),
                   right: resolve_expr_signals(expr.right, ctx, memo),
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::Mux
                 RHDL::Codegen::CIRCT::IR::Mux.new(
                   condition: resolve_expr_signals(expr.condition, ctx, memo),
                   when_true: resolve_expr_signals(expr.when_true, ctx, memo),
                   when_false: resolve_expr_signals(expr.when_false, ctx, memo),
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::Concat
                 RHDL::Codegen::CIRCT::IR::Concat.new(
                   parts: expr.parts.map { |part| resolve_expr_signals(part, ctx, memo) },
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::Slice
                 RHDL::Codegen::CIRCT::IR::Slice.new(
                   base: resolve_expr_signals(expr.base, ctx, memo),
                   range: expr.range,
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::Resize
                 RHDL::Codegen::CIRCT::IR::Resize.new(
                   expr: resolve_expr_signals(expr.expr, ctx, memo),
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::Case
                 RHDL::Codegen::CIRCT::IR::Case.new(
                   selector: resolve_expr_signals(expr.selector, ctx, memo),
                   cases: expr.cases.transform_values { |value| resolve_expr_signals(value, ctx, memo) },
                   default: resolve_expr_signals(expr.default, ctx, memo),
                   width: expr.width
                 )
               when RHDL::Codegen::CIRCT::IR::MemoryRead
                 RHDL::Codegen::CIRCT::IR::MemoryRead.new(
                   memory: expr.memory,
                   addr: resolve_expr_signals(expr.addr, ctx, memo),
                   width: expr.width
                 )
               else
                 expr
               end

    memo[key] = resolved
  end

  def simplify_expr(expr, memo)
    key = expr.object_id
    return memo[key] if memo.key?(key)

    simplified = case expr
                 when RHDL::Codegen::CIRCT::IR::Literal
                   RHDL::Codegen::CIRCT::IR::Literal.new(
                     value: normalize_const(expr.value, expr.width),
                     width: expr.width
                   )
                 when RHDL::Codegen::CIRCT::IR::Signal
                   expr
                 when RHDL::Codegen::CIRCT::IR::UnaryOp
                   operand = simplify_expr(expr.operand, memo)
                   if operand.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     value = evaluate_unary_literal(op: expr.op, operand: operand, width: expr.width)
                     if value.nil?
                       RHDL::Codegen::CIRCT::IR::UnaryOp.new(op: expr.op, operand: operand, width: expr.width)
                     else
                       RHDL::Codegen::CIRCT::IR::Literal.new(value: value, width: expr.width)
                     end
                   else
                     RHDL::Codegen::CIRCT::IR::UnaryOp.new(op: expr.op, operand: operand, width: expr.width)
                   end
                when RHDL::Codegen::CIRCT::IR::BinaryOp
                  left = simplify_expr(expr.left, memo)
                  right = simplify_expr(expr.right, memo)
                  if expr.op.to_s == '^' && expr.width.to_i == 1
                    one_literal_left = left.is_a?(RHDL::Codegen::CIRCT::IR::Literal) && left.width.to_i == 1 && left.value.to_i == 1
                    one_literal_right = right.is_a?(RHDL::Codegen::CIRCT::IR::Literal) && right.width.to_i == 1 && right.value.to_i == 1
                    other = one_literal_left ? right : (one_literal_right ? left : nil)
                    if other.is_a?(RHDL::Codegen::CIRCT::IR::BinaryOp)
                      case other.op.to_s
                      when '=='
                        return simplify_expr(
                          RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                            op: :'!=',
                            left: other.left,
                            right: other.right,
                            width: 1
                          ),
                          memo
                        )
                      when '!='
                        return simplify_expr(
                          RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                            op: :'==',
                            left: other.left,
                            right: other.right,
                            width: 1
                          ),
                          memo
                        )
                      end
                    end
                  end
                  if left.is_a?(RHDL::Codegen::CIRCT::IR::Literal) && right.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                    value = evaluate_binary_literal(
                      op: expr.op,
                      left: left.value,
                      right: right.value,
                      width: expr.width,
                      left_width: left.width,
                      right_width: right.width
                    )
                    if value.nil?
                      RHDL::Codegen::CIRCT::IR::BinaryOp.new(op: expr.op, left: left, right: right, width: expr.width)
                    else
                      RHDL::Codegen::CIRCT::IR::Literal.new(value: value, width: expr.width)
                    end
                  else
                    RHDL::Codegen::CIRCT::IR::BinaryOp.new(op: expr.op, left: left, right: right, width: expr.width)
                  end
                 when RHDL::Codegen::CIRCT::IR::Mux
                   cond = simplify_expr(expr.condition, memo)
                   when_true = simplify_expr(expr.when_true, memo)
                   when_false = simplify_expr(expr.when_false, memo)
                   if expr.width.to_i == 1 &&
                      when_true.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
                      when_false.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     t = when_true.value.to_i.zero? ? 0 : 1
                     f = when_false.value.to_i.zero? ? 0 : 1
                     if t == f
                       when_true
                     elsif t == 1 && f == 0
                       cond
                     elsif t == 0 && f == 1
                       simplify_expr(
                         RHDL::Codegen::CIRCT::IR::UnaryOp.new(op: :'~', operand: cond, width: 1),
                         memo
                       )
                     else
                       RHDL::Codegen::CIRCT::IR::Mux.new(
                         condition: cond,
                         when_true: when_true,
                         when_false: when_false,
                         width: expr.width
                       )
                     end
                   elsif expr.width.to_i == 1 &&
                         when_true.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
                         when_true.value.to_i == 1
                     simplify_expr(
                       RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                         op: :'|',
                         left: cond,
                         right: when_false,
                         width: 1
                       ),
                       memo
                     )
                   elsif expr.width.to_i == 1 &&
                         when_false.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
                         when_false.value.to_i.zero?
                     simplify_expr(
                       RHDL::Codegen::CIRCT::IR::BinaryOp.new(
                         op: :'&',
                         left: cond,
                         right: when_true,
                         width: 1
                       ),
                       memo
                     )
                   elsif expr_structurally_equal?(when_true, when_false)
                     when_true
                   elsif cond.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     cond.value.to_i.zero? ? when_false : when_true
                   else
                     mux_expr = RHDL::Codegen::CIRCT::IR::Mux.new(
                       condition: cond,
                       when_true: when_true,
                       when_false: when_false,
                       width: expr.width
                     )
                     canonicalize_small_selector_mux(mux_expr) || mux_expr
                   end
                 when RHDL::Codegen::CIRCT::IR::Concat
                   parts = flatten_concat_parts(expr.parts.map { |part| simplify_expr(part, memo) })
                   if parts.all? { |part| part.is_a?(RHDL::Codegen::CIRCT::IR::Literal) }
                     acc = 0
                     parts.each do |part|
                       acc = (acc << part.width.to_i) | (part.value.to_i % (1 << part.width.to_i))
                     end
                     RHDL::Codegen::CIRCT::IR::Literal.new(value: normalize_const(acc, expr.width), width: expr.width)
                   elsif parts.length == 1 && parts.first.width.to_i == expr.width.to_i
                     parts.first
                   else
                     RHDL::Codegen::CIRCT::IR::Concat.new(parts: parts, width: expr.width)
                   end
                 when RHDL::Codegen::CIRCT::IR::Slice
                   base = simplify_expr(expr.base, memo)
                   if base.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     low = [expr.range.begin.to_i, expr.range.end.to_i].min
                     value = ((base.value.to_i % (1 << base.width.to_i)) >> low) & ((1 << expr.width.to_i) - 1)
                     RHDL::Codegen::CIRCT::IR::Literal.new(
                       value: normalize_const(value, expr.width),
                       width: expr.width
                     )
                   elsif base.is_a?(RHDL::Codegen::CIRCT::IR::Slice)
                     inner_low = [base.range.begin.to_i, base.range.end.to_i].min
                     outer_low = [expr.range.begin.to_i, expr.range.end.to_i].min
                     rebased = RHDL::Codegen::CIRCT::IR::Slice.new(
                       base: base.base,
                       range: (inner_low + outer_low)..(inner_low + outer_low + expr.width.to_i - 1),
                       width: expr.width
                     )
                     simplify_expr(rebased, memo)
                   elsif base.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
                     true_slice = simplify_expr(
                       RHDL::Codegen::CIRCT::IR::Slice.new(base: base.when_true, range: expr.range, width: expr.width),
                       memo
                     )
                     false_slice = simplify_expr(
                       RHDL::Codegen::CIRCT::IR::Slice.new(base: base.when_false, range: expr.range, width: expr.width),
                       memo
                     )
                     simplify_expr(
                       RHDL::Codegen::CIRCT::IR::Mux.new(
                         condition: base.condition,
                         when_true: true_slice,
                         when_false: false_slice,
                         width: expr.width
                       ),
                       memo
                     )
                   else
                     RHDL::Codegen::CIRCT::IR::Slice.new(base: base, range: expr.range, width: expr.width)
                   end
                 when RHDL::Codegen::CIRCT::IR::Resize
                   resized = simplify_expr(expr.expr, memo)
                   if resized.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     RHDL::Codegen::CIRCT::IR::Literal.new(
                       value: normalize_const(resized.value, expr.width),
                       width: expr.width
                     )
                   else
                     RHDL::Codegen::CIRCT::IR::Resize.new(expr: resized, width: expr.width)
                   end
                 when RHDL::Codegen::CIRCT::IR::Case
                   selector = simplify_expr(expr.selector, memo)
                   cases = expr.cases.transform_values { |value| simplify_expr(value, memo) }
                   default = simplify_expr(expr.default, memo)
                   if selector.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     hit = cases[selector.value] || default
                     hit || RHDL::Codegen::CIRCT::IR::Literal.new(value: 0, width: expr.width)
                   else
                     RHDL::Codegen::CIRCT::IR::Case.new(
                       selector: selector,
                       cases: cases,
                       default: default,
                       width: expr.width
                     )
                   end
                 when RHDL::Codegen::CIRCT::IR::MemoryRead
                   RHDL::Codegen::CIRCT::IR::MemoryRead.new(
                     memory: expr.memory,
                     addr: simplify_expr(expr.addr, memo),
                     width: expr.width
                   )
                 else
                   expr
                 end

    memo[key] = simplified
  end

  def flatten_concat_parts(parts)
    Array(parts).each_with_object([]) do |part, acc|
      if part.is_a?(RHDL::Codegen::CIRCT::IR::Concat)
        acc.concat(flatten_concat_parts(part.parts))
      else
        acc << part
      end
    end
  end

  def expr_structural_key(expr)
    Marshal.dump(expr)
  rescue TypeError
    expr.inspect
  end

  def expr_structurally_equal?(left, right)
    expr_structural_key(left) == expr_structural_key(right)
  end

  def canonicalize_small_selector_mux(expr)
    return nil unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
    return nil unless expr.width.to_i > 1

    selector = selector_from_mux_conditions(expr)
    return nil unless selector

    selector_name = selector[:name]
    selector_width = selector[:width]
    max_value = (1 << selector_width) - 1

    terminals = {}
    (0..max_value).each do |value|
      terminal = select_mux_terminal_for_selector(
        expr,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: value
      )
      return nil unless terminal

      terminals[value] = terminal
    end

    canonical = terminals[max_value]
    max_value.downto(0) do |value|
      next if value == max_value

      branch = terminals[value]
      next if expr_structurally_equal?(branch, canonical)

      canonical = RHDL::Codegen::CIRCT::IR::Mux.new(
        condition: RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :'==',
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: selector_name, width: selector_width),
          right: RHDL::Codegen::CIRCT::IR::Literal.new(value: value, width: selector_width),
          width: 1
        ),
        when_true: branch,
        when_false: canonical,
        width: expr.width
      )
    end

    return nil if expr_structurally_equal?(canonical, expr)

    canonical
  end

  def selector_from_mux_conditions(expr)
    return nil if mux_node_count(expr) > 12

    selector = nil
    queue = [expr]
    until queue.empty?
      node = queue.shift
      next unless node.is_a?(RHDL::Codegen::CIRCT::IR::Mux)

      cond_signals = condition_signal_uses(node.condition)
      return nil unless cond_signals.length == 1

      name, width = cond_signals.first
      return nil if width.to_i <= 0 || width.to_i > 2

      selector ||= { name: name, width: width.to_i }
      return nil unless selector[:name] == name && selector[:width] == width.to_i

      queue << node.when_true
      queue << node.when_false
    end

    selector
  end

  def mux_node_count(expr)
    return 0 unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux)

    1 + mux_node_count(expr.when_true) + mux_node_count(expr.when_false)
  end

  def condition_signal_uses(expr, acc = {})
    case expr
    when RHDL::Codegen::CIRCT::IR::Signal
      acc[expr.name.to_s] = expr.width.to_i
    when RHDL::Codegen::CIRCT::IR::UnaryOp
      condition_signal_uses(expr.operand, acc)
    when RHDL::Codegen::CIRCT::IR::BinaryOp
      condition_signal_uses(expr.left, acc)
      condition_signal_uses(expr.right, acc)
    when RHDL::Codegen::CIRCT::IR::Slice
      condition_signal_uses(expr.base, acc)
    when RHDL::Codegen::CIRCT::IR::Resize
      condition_signal_uses(expr.expr, acc)
    when RHDL::Codegen::CIRCT::IR::Concat
      expr.parts.each { |part| condition_signal_uses(part, acc) }
    end
    acc
  end

  def select_mux_terminal_for_selector(expr, selector_name:, selector_width:, selector_value:)
    node = expr
    while node.is_a?(RHDL::Codegen::CIRCT::IR::Mux)
      cond_value = evaluate_expr_for_selector(
        node.condition,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      return nil unless cond_value

      node = cond_value.to_i.zero? ? node.when_false : node.when_true
    end
    node
  end

  def evaluate_expr_for_selector(expr, selector_name:, selector_width:, selector_value:)
    case expr
    when RHDL::Codegen::CIRCT::IR::Literal
      normalize_const(expr.value, expr.width)
    when RHDL::Codegen::CIRCT::IR::Signal
      return nil unless expr.name.to_s == selector_name

      normalize_const(selector_value, selector_width)
    when RHDL::Codegen::CIRCT::IR::UnaryOp
      operand = evaluate_expr_for_selector(
        expr.operand,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      return nil if operand.nil?

      evaluate_unary_literal(
        op: expr.op,
        operand: RHDL::Codegen::CIRCT::IR::Literal.new(value: operand, width: expr.operand.width),
        width: expr.width
      )
    when RHDL::Codegen::CIRCT::IR::BinaryOp
      left = evaluate_expr_for_selector(
        expr.left,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      right = evaluate_expr_for_selector(
        expr.right,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      return nil if left.nil? || right.nil?

      evaluate_binary_literal(
        op: expr.op,
        left: left,
        right: right,
        width: expr.width,
        left_width: expr.left.respond_to?(:width) ? expr.left.width : selector_width,
        right_width: expr.right.respond_to?(:width) ? expr.right.width : selector_width
      )
    when RHDL::Codegen::CIRCT::IR::Slice
      base = evaluate_expr_for_selector(
        expr.base,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      return nil if base.nil?

      low = [expr.range.begin.to_i, expr.range.end.to_i].min
      ((base.to_i % (1 << expr.base.width.to_i)) >> low) & ((1 << expr.width.to_i) - 1)
    when RHDL::Codegen::CIRCT::IR::Resize
      value = evaluate_expr_for_selector(
        expr.expr,
        selector_name: selector_name,
        selector_width: selector_width,
        selector_value: selector_value
      )
      return nil if value.nil?

      normalize_const(value, expr.width)
    when RHDL::Codegen::CIRCT::IR::Concat
      acc = 0
      expr.parts.each do |part|
        part_value = evaluate_expr_for_selector(
          part,
          selector_name: selector_name,
          selector_width: selector_width,
          selector_value: selector_value
        )
        return nil if part_value.nil?

        acc = (acc << part.width.to_i) | (part_value.to_i % (1 << part.width.to_i))
      end
      normalize_const(acc, expr.width)
    else
      nil
    end
  end

  def normalize_const(value, width)
    width = [width.to_i, 1].max
    modulus = 1 << width
    wrapped = value.to_i % modulus
    return wrapped if value.to_i >= 0

    wrapped.zero? ? 0 : wrapped - modulus
  end

  def evaluate_unary_literal(op:, operand:, width:)
    value = operand.value.to_i
    case op.to_sym
    when :~, :'~'
      normalize_const(~value, width)
    when :reduce_or
      value.zero? ? 0 : 1
    when :reduce_and
      (value % (1 << operand.width.to_i)) == ((1 << operand.width.to_i) - 1) ? 1 : 0
    when :reduce_xor
      (value % (1 << operand.width.to_i)).digits(2).sum & 1
    when :-@
      normalize_const(-value, width)
    else
      nil
    end
  end

  def evaluate_binary_literal(op:, left:, right:, width:, left_width: nil, right_width: nil)
    left = left.to_i
    right = right.to_i
    left_w = [left_width.to_i, 1].max
    right_w = [right_width.to_i, 1].max
    cmp_width = [left_w, right_w, 1].max
    uleft = left % (1 << cmp_width)
    uright = right % (1 << cmp_width)
    case op.to_sym
    when :+
      normalize_const(left + right, width)
    when :-
      normalize_const(left - right, width)
    when :*
      normalize_const(left * right, width)
    when :&, :'and'
      normalize_const(left & right, width)
    when :|, :'or'
      normalize_const(left | right, width)
    when :^, :'xor'
      normalize_const(left ^ right, width)
    when :'<<'
      normalize_const(left << right, width)
    when :'>>'
      normalize_const((left % (1 << width.to_i)) >> right, width)
    when :==
      uleft == uright ? 1 : 0
    when :'!='
      uleft != uright ? 1 : 0
    when :<
      uleft < uright ? 1 : 0
    when :<=
      uleft <= uright ? 1 : 0
    when :>
      uleft > uright ? 1 : 0
    when :>=
      uleft >= uright ? 1 : 0
    else
      nil
    end
  end

  def process_signature(process)
    {
      clocked: !!process.clocked,
      statements: Array(process.statements).map { |stmt| statement_signature(stmt) }
    }
  end

  def statement_signature(stmt)
    case stmt
    when RHDL::Codegen::CIRCT::IR::SeqAssign
      [:seq_assign, expr_signature(stmt.expr)]
    when RHDL::Codegen::CIRCT::IR::If
      [
        :if,
        expr_signature(stmt.condition),
        Array(stmt.then_statements).map { |s| statement_signature(s) },
        Array(stmt.else_statements).map { |s| statement_signature(s) }
      ]
    else
      [:stmt, stmt.class.name]
    end
  end

  def instance_signature(inst)
    {
      module: inst.module_name.to_s,
      parameters: stable_sort((inst.parameters || {}).map { |k, v| [k.to_s, v] }),
      connections: stable_sort(Array(inst.connections).map { |conn| [conn.direction.to_s, conn.port_name.to_s] })
    }
  end

  def expr_signature(expr, memo = {})
    return nil if expr.nil?

    key = expr.object_id
    return memo[key] if memo.key?(key)

    memo[key] = case expr
                when RHDL::Codegen::CIRCT::IR::Signal
                  [:signal, expr.width.to_i]
                when RHDL::Codegen::CIRCT::IR::Literal
                  [:literal, expr.width.to_i, expr.value]
                when RHDL::Codegen::CIRCT::IR::UnaryOp
                  [:unary, expr.op.to_s, expr.width.to_i, expr_signature(expr.operand, memo)]
                when RHDL::Codegen::CIRCT::IR::BinaryOp
                  left = expr_signature(expr.left, memo)
                  right = expr_signature(expr.right, memo)
                  left, right = stable_sort([left, right]) if commutative_binop?(expr.op)
                  [:binary, expr.op.to_s, expr.width.to_i, left, right]
                when RHDL::Codegen::CIRCT::IR::Mux
                  [
                    :mux,
                    expr.width.to_i,
                    expr_signature(expr.condition, memo),
                    expr_signature(expr.when_true, memo),
                    expr_signature(expr.when_false, memo)
                  ]
                when RHDL::Codegen::CIRCT::IR::Concat
                  if concat_extension_of_signal_signature?(expr)
                    [:signal, expr.width.to_i]
                  else
                    flat_parts = flatten_concat_parts(expr.parts)
                    [:concat, expr.width.to_i, flat_parts.map { |part| expr_signature(part, memo) }]
                  end
                when RHDL::Codegen::CIRCT::IR::Slice
                  [:slice, expr.width.to_i, expr_signature(expr.base, memo), expr.range.min, expr.range.max]
                when RHDL::Codegen::CIRCT::IR::Resize
                  [:resize, expr.width.to_i, expr_signature(expr.expr, memo)]
                when RHDL::Codegen::CIRCT::IR::Case
                  cases = expr.cases.sort_by { |sig_key, _value| sig_key.inspect }
                    .map { |sig_key, value| [sig_key, expr_signature(value, memo)] }
                  [:case, expr.width.to_i, expr_signature(expr.selector, memo), cases, expr_signature(expr.default, memo)]
                when RHDL::Codegen::CIRCT::IR::MemoryRead
                  [:memory_read, expr.width.to_i, expr_signature(expr.addr, memo)]
                else
                  width = expr.respond_to?(:width) ? expr.width.to_i : nil
                  [:expr, expr.class.name, width]
                end
  end

  def concat_extension_of_signal_signature?(expr)
    return false unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Concat)

    parts = Array(expr.parts)
    return false unless parts.length == 2

    high, low = parts
    return false unless high.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
    return false unless low.is_a?(RHDL::Codegen::CIRCT::IR::Signal)

    high_width = high.width.to_i
    low_width = low.width.to_i
    return false unless high_width.positive? && low_width.positive?
    return false unless high_width + low_width == expr.width.to_i

    high_value = normalize_const(high.value, high.width).to_i
    all_zeros = high_value.zero?
    all_ones = (high_value == -1) || (high_value == ((1 << high_width) - 1))
    all_zeros || all_ones
  end

  def expr_complexity(expr, memo)
    key = expr.object_id
    return memo[key] if memo.key?(key)

    complexity = case expr
                 when RHDL::Codegen::CIRCT::IR::Literal,
                      RHDL::Codegen::CIRCT::IR::Signal
                   1
                 when RHDL::Codegen::CIRCT::IR::UnaryOp
                   1 + expr_complexity(expr.operand, memo)
                 when RHDL::Codegen::CIRCT::IR::BinaryOp
                   1 + expr_complexity(expr.left, memo) + expr_complexity(expr.right, memo)
                 when RHDL::Codegen::CIRCT::IR::Mux
                   1 +
                     expr_complexity(expr.condition, memo) +
                     expr_complexity(expr.when_true, memo) +
                     expr_complexity(expr.when_false, memo)
                 when RHDL::Codegen::CIRCT::IR::Concat
                   1 + expr.parts.sum { |part| expr_complexity(part, memo) }
                 when RHDL::Codegen::CIRCT::IR::Slice
                   1 + expr_complexity(expr.base, memo)
                 when RHDL::Codegen::CIRCT::IR::Resize
                   1 + expr_complexity(expr.expr, memo)
                 when RHDL::Codegen::CIRCT::IR::Case
                   1 +
                     expr_complexity(expr.selector, memo) +
                     expr.cases.values.sum { |value| expr_complexity(value, memo) } +
                     expr_complexity(expr.default, memo)
                 when RHDL::Codegen::CIRCT::IR::MemoryRead
                   1 + expr_complexity(expr.addr, memo)
                 else
                   1
                 end

    memo[key] = complexity
  end

  def mux_node_count_in_expr(expr, memo)
    key = expr.object_id
    return memo[key] if memo.key?(key)

    count = case expr
            when RHDL::Codegen::CIRCT::IR::Literal,
                 RHDL::Codegen::CIRCT::IR::Signal
              0
            when RHDL::Codegen::CIRCT::IR::UnaryOp
              mux_node_count_in_expr(expr.operand, memo)
            when RHDL::Codegen::CIRCT::IR::BinaryOp
              mux_node_count_in_expr(expr.left, memo) +
                mux_node_count_in_expr(expr.right, memo)
            when RHDL::Codegen::CIRCT::IR::Mux
              1 +
                mux_node_count_in_expr(expr.condition, memo) +
                mux_node_count_in_expr(expr.when_true, memo) +
                mux_node_count_in_expr(expr.when_false, memo)
            when RHDL::Codegen::CIRCT::IR::Concat
              expr.parts.sum { |part| mux_node_count_in_expr(part, memo) }
            when RHDL::Codegen::CIRCT::IR::Slice
              mux_node_count_in_expr(expr.base, memo)
            when RHDL::Codegen::CIRCT::IR::Resize
              mux_node_count_in_expr(expr.expr, memo)
            when RHDL::Codegen::CIRCT::IR::Case
              mux_node_count_in_expr(expr.selector, memo) +
                expr.cases.values.sum { |value| mux_node_count_in_expr(value, memo) } +
                mux_node_count_in_expr(expr.default, memo)
            when RHDL::Codegen::CIRCT::IR::MemoryRead
              mux_node_count_in_expr(expr.addr, memo)
            else
              0
            end

    memo[key] = count
  end

  def stable_sort(items)
    items.sort_by { |item| Marshal.dump(item) }
  end

  def commutative_binop?(op)
    %i[+ * & | ^ == !=].include?(op.to_sym)
  end

  def stable_fingerprint(value)
    Digest::SHA256.hexdigest(Marshal.dump(value))[0, 12]
  rescue TypeError
    Digest::SHA256.hexdigest(value.inspect)[0, 12]
  end

  def mismatch_summary(source_sigs, roundtrip_sigs)
    missing = source_sigs.keys - roundtrip_sigs.keys
    extra = roundtrip_sigs.keys - source_sigs.keys
    common = source_sigs.keys & roundtrip_sigs.keys
    mismatched = common.reject { |name| source_sigs[name] == roundtrip_sigs[name] }
    known_remaining = mismatched & EXPECTED_STRUCTURAL_MISMATCHES
    unexpected = mismatched - EXPECTED_STRUCTURAL_MISMATCHES

    lines = []
    lines << "missing=#{missing.length} extra=#{extra.length} mismatched=#{mismatched.length} known_remaining=#{known_remaining.length} unexpected=#{unexpected.length}"
    lines << "missing_modules=#{missing.sort.join(',')}" unless missing.empty?
    lines << "extra_modules=#{extra.sort.join(',')}" unless extra.empty?
    lines << "known_remaining_modules=#{known_remaining.sort.join(',')}" unless known_remaining.empty?
    lines << "unexpected_modules=#{unexpected.sort.join(',')}" unless unexpected.empty?
    mismatched.first(10).each do |name|
      lines << "mismatch #{name}: source=#{stable_fingerprint(source_sigs[name])} roundtrip=#{stable_fingerprint(roundtrip_sigs[name])}"
    end
    lines.join("\n")
  end

  it 'preserves normalized per-module signatures across mixed->Verilog->RHDL->Verilog roundtrip', timeout: 1800 do
    require_reference_tree!
    require_tool!('ghdl')
    require_tool!('circt-verilog')
    require_tool!('circt-opt')
    require_export_tool!

    Dir.mktmpdir('gameboy_roundtrip_out') do |out_dir|
      Dir.mktmpdir('gameboy_roundtrip_ws') do |workspace|
        importer = RHDL::Examples::GameBoy::Import::SystemImporter.new(
          output_dir: out_dir,
          workspace_dir: workspace,
          keep_workspace: true,
          clean_output: true,
          strict: true,
          progress: ->(_msg) {}
        )
        import_result = timed_roundtrip_step('importer.run') { importer.run }
        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")

        report = JSON.parse(File.read(import_result.report_path))
        source_staged_verilog_path = report.fetch('mixed_import').fetch('pure_verilog_entry_path')
        expect(File.file?(source_staged_verilog_path)).to be(true)

        source_staged_verilog = File.read(source_staged_verilog_path)
        source_sigs = timed_roundtrip_step('source signatures') do
          normalized_module_signatures_from_verilog(
            source_staged_verilog,
            base_dir: File.join(workspace, 'source_sig'),
            stem: 'source'
          )
        end

        source_mlir = File.read(import_result.mlir_path)
        raise_result = timed_roundtrip_step('raise_circt_components') do
          RHDL::Codegen.raise_circt_components(source_mlir, namespace: Module.new, top: 'gb')
        end
        expect(raise_result.success?).to be(true), diagnostic_summary(raise_result)

        roundtrip_mlir = timed_roundtrip_step('components.to_ir') do
          raise_result.components.keys.sort.map do |module_name|
            raise_result.components.fetch(module_name).to_ir(top_name: module_name)
          end.join("\n\n")
        end
        roundtrip_verilog = timed_roundtrip_step('mlir_to_verilog') do
          convert_mlir_to_verilog(roundtrip_mlir, base_dir: workspace, stem: 'roundtrip')
        end
        roundtrip_sigs = timed_roundtrip_step('roundtrip signatures') do
          normalized_module_signatures_from_verilog(
            roundtrip_verilog,
            base_dir: File.join(workspace, 'roundtrip_sig'),
            stem: 'roundtrip'
          )
        end

        summary = timed_roundtrip_step('mismatch summary') { mismatch_summary(source_sigs, roundtrip_sigs) }
        expect(source_sigs.keys - roundtrip_sigs.keys).to be_empty, summary
        expect(roundtrip_sigs.keys - source_sigs.keys).to be_empty, summary
        common = source_sigs.keys & roundtrip_sigs.keys
        mismatched = common.reject { |name| source_sigs[name] == roundtrip_sigs[name] }
        unexpected = mismatched - EXPECTED_STRUCTURAL_MISMATCHES
        expect(unexpected).to be_empty, summary
      end
    end
  end

  it 'normalizes nested concats with equivalent flat packing the same way' do
    left = RHDL::Codegen::CIRCT::IR::Concat.new(
      parts: [
        RHDL::Codegen::CIRCT::IR::Concat.new(
          parts: [
            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: :'==',
              left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
              right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :b, width: 8),
              width: 1
            ),
            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: :'==',
              left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
              right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :c, width: 8),
              width: 1
            )
          ],
          width: 2
        ),
        RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :'==',
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
          right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :d, width: 8),
          width: 1
        )
      ],
      width: 3
    )
    right = RHDL::Codegen::CIRCT::IR::Concat.new(
      parts: [
        RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :'==',
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
          right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :b, width: 8),
          width: 1
        ),
        RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :'==',
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
          right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :c, width: 8),
          width: 1
        ),
        RHDL::Codegen::CIRCT::IR::BinaryOp.new(
          op: :'==',
          left: RHDL::Codegen::CIRCT::IR::Signal.new(name: :a, width: 8),
          right: RHDL::Codegen::CIRCT::IR::Signal.new(name: :d, width: 8),
          width: 1
        )
      ],
      width: 3
    )

    left_simplified = simplify_expr(left, {})
    right_simplified = simplify_expr(right, {})

    expect(expr_signature(left_simplified)).to eq(expr_signature(right_simplified))
  end
end
