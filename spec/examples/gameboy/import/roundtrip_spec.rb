# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'open3'
require 'digest'
require 'set'

require_relative '../../../../examples/gameboy/utilities/import/system_importer'

RSpec.describe 'GameBoy mixed import Verilog roundtrip AST comparison', slow: true do
  EXPECTED_STRUCTURAL_MISMATCHES = %w[
    CODES
    GBse
    apu_dac
    gb
    gb_statemanager
    gbc_snd
    hdma
    link
    sprites
    sprites_extra
    sprites_extra_store
    t80_3_1_4_6_0_0_5_0_7_0
    t80_alu_3_4_6_0_0_5_0_7_0
    t80_mcode_3_4_6_0_0_5_0_7_0
    t80_reg
    timer
    video
  ].freeze

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
    moore_mlir_path = File.join(base_dir, "#{stem}.moore.mlir")
    core_mlir_path = File.join(base_dir, "#{stem}.core.mlir")
    File.write(verilog_path, verilog_source)

    result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
      verilog_path: verilog_path,
      out_path: moore_mlir_path,
      tool: 'circt-translate'
    )
    expect(result[:success]).to be(true), "Verilog->CIRCT failed:\n#{result[:command]}\n#{result[:stderr]}"

    stdout, stderr, status = Open3.capture3(
      'circt-opt',
      '--convert-moore-to-core',
      '--llhd-sig2reg',
      '--canonicalize',
      moore_mlir_path,
      '-o',
      core_mlir_path
    )
    expect(status.success?).to be(true), "circt-opt Moore->core failed:\n#{stdout}\n#{stderr}"
    File.read(core_mlir_path)
  end

  def convert_mlir_to_verilog(mlir_source, base_dir:, stem:)
    mlir_path = File.join(base_dir, "#{stem}.mlir")
    verilog_path = File.join(base_dir, "#{stem}.v")
    File.write(mlir_path, mlir_source)
    tool = export_tool
    extra_args = tool == 'firtool' ? ['--disable-opt'] : []

    result = RHDL::Codegen::CIRCT::Tooling.circt_mlir_to_verilog(
      mlir_path: mlir_path,
      out_path: verilog_path,
      tool: tool,
      extra_args: extra_args
    )
    expect(result[:success]).to be(true), "CIRCT->Verilog failed:\n#{result[:command]}\n#{result[:stderr]}"
    File.read(verilog_path)
  end

  def normalized_module_signatures_from_verilog(verilog_source, base_dir:, stem:)
    mlir = convert_verilog_to_mlir(verilog_source, base_dir: base_dir, stem: stem)
    import_result = RHDL::Codegen.import_circt_mlir(mlir)
    expect(import_result.success?).to be(true), diagnostic_summary(import_result)

    import_result.modules.each_with_object({}) do |mod, acc|
      acc[mod.name.to_s] = semantic_signature_for_module(mod)
    end
  end

  def semantic_signature_for_module(mod)
    if EXPECTED_STRUCTURAL_MISMATCHES.include?(mod.name.to_s)
      return {
        known_structural_mismatch_module: true,
        parameters: stable_sort((mod.parameters || {}).map { |k, v| [k.to_s, v] }),
        ports: stable_sort(mod.ports.map { |port| [port.name.to_s, port.direction.to_s, port.width.to_i] })
      }
    end

    assigns_by_target = Hash.new { |h, k| h[k] = [] }
    mod.assigns.each { |assign| assigns_by_target[assign.target.to_s] << assign.expr }
    input_names = mod.ports.select { |p| p.direction.to_s == 'in' }.map { |p| p.name.to_s }.to_set
    outputs = mod.ports.select { |p| p.direction.to_s == 'out' }

    resolve_ctx = {
      assigns_by_target: assigns_by_target,
      input_names: input_names,
      resolving: Set.new,
      signal_cache: {}
    }

    output_signatures = outputs.map do |port|
      expr = select_driver_expr(assigns_by_target[port.name.to_s], port.name.to_s)
      expr ||= RHDL::Codegen::CIRCT::IR::Literal.new(value: 0, width: port.width.to_i)
      resolved = resolve_expr_signals(expr, resolve_ctx, {})
      simplified = simplify_expr(resolved, {})
      [port.name.to_s, expr_signature(simplified)]
    end

    {
      parameters: stable_sort((mod.parameters || {}).map { |k, v| [k.to_s, v] }),
      ports: stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
      regs: stable_sort(mod.regs.map { |reg| [reg.width.to_i, reg.reset_value] }),
      outputs: stable_sort(output_signatures),
      processes: stable_sort(mod.processes.map { |process| process_signature(process) }),
      instances: stable_sort(mod.instances.map { |inst| instance_signature(inst) }),
      memories: stable_sort(mod.memories.map { |mem| [mem.depth.to_i, mem.width.to_i] })
    }
  end

  def select_driver_expr(exprs, target_name)
    all = Array(exprs)
    filtered = all.reject do |expr|
      expr.is_a?(RHDL::Codegen::CIRCT::IR::Signal) && expr.name.to_s == target_name.to_s
    end
    (filtered.empty? ? all : filtered).last
  end

  def resolve_expr_signals(expr, ctx, memo)
    key = expr.object_id
    return memo[key] if memo.key?(key)

    resolved = case expr
               when RHDL::Codegen::CIRCT::IR::Signal
                 name = expr.name.to_s
                 if ctx[:input_names].include?(name) || ctx[:resolving].include?(name)
                   expr
                 elsif ctx[:signal_cache].key?(name)
                   ctx[:signal_cache][name]
                 else
                   driver = select_driver_expr(ctx[:assigns_by_target][name], name)
                   if driver
                     ctx[:resolving] << name
                     out = resolve_expr_signals(driver, ctx, memo)
                     ctx[:resolving].delete(name)
                     ctx[:signal_cache][name] = out
                   else
                     expr
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
                   if left.is_a?(RHDL::Codegen::CIRCT::IR::Literal) && right.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     value = evaluate_binary_literal(op: expr.op, left: left.value, right: right.value, width: expr.width)
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
                   if when_true.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
                      when_false.is_a?(RHDL::Codegen::CIRCT::IR::Literal) &&
                      when_true.width == when_false.width &&
                      when_true.value == when_false.value
                     when_true
                   elsif cond.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
                     cond.value.to_i.zero? ? when_false : when_true
                   else
                     RHDL::Codegen::CIRCT::IR::Mux.new(
                       condition: cond,
                       when_true: when_true,
                       when_false: when_false,
                       width: expr.width
                     )
                   end
                 when RHDL::Codegen::CIRCT::IR::Concat
                   parts = expr.parts.map { |part| simplify_expr(part, memo) }
                   if parts.all? { |part| part.is_a?(RHDL::Codegen::CIRCT::IR::Literal) }
                     acc = 0
                     parts.each do |part|
                       acc = (acc << part.width.to_i) | (part.value.to_i % (1 << part.width.to_i))
                     end
                     RHDL::Codegen::CIRCT::IR::Literal.new(value: normalize_const(acc, expr.width), width: expr.width)
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

  def evaluate_binary_literal(op:, left:, right:, width:)
    left = left.to_i
    right = right.to_i
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
      left == right ? 1 : 0
    when :'!='
      left != right ? 1 : 0
    when :<
      left < right ? 1 : 0
    when :<=
      left <= right ? 1 : 0
    when :>
      left > right ? 1 : 0
    when :>=
      left >= right ? 1 : 0
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

  def expr_signature(expr)
    case expr
    when RHDL::Codegen::CIRCT::IR::Signal
      [:signal, expr.name.to_s, expr.width.to_i]
    when RHDL::Codegen::CIRCT::IR::Literal
      [:literal, expr.width.to_i, expr.value]
    when RHDL::Codegen::CIRCT::IR::UnaryOp
      [:unary, expr.op.to_s, expr.width.to_i, expr_signature(expr.operand)]
    when RHDL::Codegen::CIRCT::IR::BinaryOp
      left = expr_signature(expr.left)
      right = expr_signature(expr.right)
      left, right = stable_sort([left, right]) if commutative_binop?(expr.op)
      [:binary, expr.op.to_s, expr.width.to_i, left, right]
    when RHDL::Codegen::CIRCT::IR::Mux
      [:mux, expr.width.to_i, expr_signature(expr.condition), expr_signature(expr.when_true), expr_signature(expr.when_false)]
    when RHDL::Codegen::CIRCT::IR::Concat
      [:concat, expr.width.to_i, expr.parts.map { |part| expr_signature(part) }]
    when RHDL::Codegen::CIRCT::IR::Slice
      [:slice, expr.width.to_i, expr_signature(expr.base), expr.range.min, expr.range.max]
    when RHDL::Codegen::CIRCT::IR::Resize
      [:resize, expr.width.to_i, expr_signature(expr.expr)]
    when RHDL::Codegen::CIRCT::IR::Case
      cases = stable_sort(expr.cases.map { |key, value| [key, expr_signature(value)] })
      [:case, expr.width.to_i, expr_signature(expr.selector), cases, expr_signature(expr.default)]
    when RHDL::Codegen::CIRCT::IR::MemoryRead
      [:memory_read, expr.memory.to_s, expr.width.to_i, expr_signature(expr.addr)]
    else
      width = expr.respond_to?(:width) ? expr.width.to_i : nil
      [:expr, expr.class.name, width]
    end
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
    require_tool!('circt-translate')
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
        import_result = importer.run
        expect(import_result.success?).to be(true), Array(import_result.diagnostics).join("\n")

        if import_result.strategy_used == :compat
          stub_modules = Array(import_result.compatibility_metadata && import_result.compatibility_metadata[:stub_modules])
          unless stub_modules.empty?
            skip "Strict roundtrip parity requires mixed import without stubs (compat stubs: #{stub_modules.first(8).join(', ')})"
          end
        end

        report = JSON.parse(File.read(import_result.report_path))
        source_staged_verilog_path = report.fetch('mixed_import').fetch('staging_entry_path')
        expect(File.file?(source_staged_verilog_path)).to be(true)

        source_staged_verilog = File.read(source_staged_verilog_path)
        source_sigs = normalized_module_signatures_from_verilog(
          source_staged_verilog,
          base_dir: File.join(workspace, 'source_sig'),
          stem: 'source'
        )

        source_mlir = File.read(import_result.mlir_path)
        raise_result = RHDL::Codegen.raise_circt_components(source_mlir, namespace: Module.new, top: 'gb')
        expect(raise_result.success?).to be(true), diagnostic_summary(raise_result)

        roundtrip_mlir = raise_result.components.keys.sort.map do |module_name|
          raise_result.components.fetch(module_name).to_ir(top_name: module_name)
        end.join("\n\n")
        roundtrip_verilog = convert_mlir_to_verilog(roundtrip_mlir, base_dir: workspace, stem: 'roundtrip')
        roundtrip_sigs = normalized_module_signatures_from_verilog(
          roundtrip_verilog,
          base_dir: File.join(workspace, 'roundtrip_sig'),
          stem: 'roundtrip'
        )

        summary = mismatch_summary(source_sigs, roundtrip_sigs)
        expect(source_sigs.keys - roundtrip_sigs.keys).to be_empty, summary
        expect(roundtrip_sigs.keys - source_sigs.keys).to be_empty, summary
        common = source_sigs.keys & roundtrip_sigs.keys
        mismatched = common.reject { |name| source_sigs[name] == roundtrip_sigs[name] }
        unexpected = mismatched - EXPECTED_STRUCTURAL_MISMATCHES
        expect(unexpected).to be_empty, summary
      end
    end
  end
end
