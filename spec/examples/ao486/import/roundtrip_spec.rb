# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'digest'

require_relative '../../../../examples/ao486/utilities/import/system_importer'

RSpec.describe 'AO486 import AST roundtrip (full tree baseline)', slow: true do
  def diagnostic_summary(result)
    lines = []
    diagnostics = result.respond_to?(:diagnostics) ? Array(result.diagnostics) : []
    lines.concat(diagnostics.map { |diag| diagnostic_line(diag) })
    extra_raise = result.respond_to?(:raise_diagnostics) ? Array(result.raise_diagnostics) : []
    lines.concat(extra_raise.map { |diag| diagnostic_line(diag) })
    lines.join("\n")
  end

  def diagnostic_line(diag)
    return diag.to_s unless diag.respond_to?(:severity) && diag.respond_to?(:message)

    "[#{diag.severity}]#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
  end

  def run_importer(out_dir:, workspace:)
    RHDL::Examples::AO486::Import::SystemImporter.new(
      output_dir: out_dir,
      workspace_dir: workspace,
      keep_workspace: true,
      import_strategy: :tree,
      fallback_to_stubbed: false,
      maintain_directory_structure: true
    ).run
  end

  def normalized_module_signatures(modules)
    modules.each_with_object({}) do |mod, acc|
      acc[mod.name.to_s] = semantic_signature_for_module(mod)
    end
  end

  def module_preview(module_names, limit: 10)
    sorted = Array(module_names).map(&:to_s).sort
    return 'none' if sorted.empty?

    preview = sorted.first(limit)
    omitted = sorted.length - preview.length
    suffix = omitted.positive? ? ", ... (+#{omitted} more)" : ''
    "#{preview.join(', ')}#{suffix}"
  end

  def collection_count(value)
    return 0 if value.nil?
    return value.length if value.respond_to?(:length)

    1
  end

  def stable_fingerprint(value)
    Digest::SHA256.hexdigest(Marshal.dump(value))[0, 12]
  rescue TypeError
    Digest::SHA256.hexdigest(value.inspect)[0, 12]
  end

  def module_field_diffs(source_sig, roundtrip_sig)
    fields = (source_sig.keys | roundtrip_sig.keys).sort_by(&:to_s)
    fields.each_with_object({}) do |field, acc|
      source_value = source_sig[field]
      roundtrip_value = roundtrip_sig[field]
      next if source_value == roundtrip_value

      acc[field] = {
        source_count: collection_count(source_value),
        roundtrip_count: collection_count(roundtrip_value),
        source_fingerprint: stable_fingerprint(source_value),
        roundtrip_fingerprint: stable_fingerprint(roundtrip_value)
      }
    end
  end

  def format_field_mismatch_counts(field_counts)
    return 'none' if field_counts.empty?

    field_counts.sort_by { |field, count| [-count, field.to_s] }
      .map { |field, count| "#{field}:#{count}" }
      .join(', ')
  end

  def format_top_modules(module_diffs, limit: 10)
    top_modules = module_diffs.sort_by { |name, fields| [-fields.size, name] }.first(limit)
    return 'none' if top_modules.empty?

    top_modules
      .map { |name, fields| "#{name}(#{fields.size} fields)" }
      .join(', ')
  end

  def diff_excerpt_limit
    limit = ENV.fetch('AO486_ROUNDTRIP_DIFF_EXCERPT', '0').to_i
    limit.positive? ? limit : 0
  end

  def format_module_diff_excerpt(module_diffs)
    limit = diff_excerpt_limit
    return [] unless limit.positive?

    top_modules = module_diffs.sort_by { |name, fields| [-fields.size, name] }.first(limit)
    lines = ["module_diff_excerpt(limit=#{limit})"]
    top_modules.each do |module_name, field_diffs|
      changed_fields = field_diffs.keys.map(&:to_s).sort.join(', ')
      lines << "  #{module_name}: #{changed_fields}"
      field_diffs.sort_by { |field, _detail| field.to_s }.each do |field, detail|
        lines << "    #{field}: source_count=#{detail[:source_count]} roundtrip_count=#{detail[:roundtrip_count]} " \
                 "source_fp=#{detail[:source_fingerprint]} roundtrip_fp=#{detail[:roundtrip_fingerprint]}"
      end
    end
    lines
  end

  def build_mismatch_summary(source_sigs:, roundtrip_sigs:, missing_modules:, extra_modules:, mismatched_modules:)
    lines = []
    lines << "missing=#{missing_modules.size} (#{module_preview(missing_modules)})"
    lines << "extra=#{extra_modules.size} (#{module_preview(extra_modules)})"
    lines << "mismatched=#{mismatched_modules.size} (#{module_preview(mismatched_modules)})"

    return lines.join("\n") if mismatched_modules.empty?

    module_diffs = mismatched_modules.sort.each_with_object({}) do |module_name, acc|
      acc[module_name] = module_field_diffs(
        source_sigs.fetch(module_name),
        roundtrip_sigs.fetch(module_name)
      )
    end

    field_counts = Hash.new(0)
    module_diffs.each_value do |field_diffs|
      field_diffs.each_key { |field| field_counts[field] += 1 }
    end

    lines << "field_mismatch_counts=#{format_field_mismatch_counts(field_counts)}"
    lines << "top_mismatched_modules=#{format_top_modules(module_diffs)}"
    lines << "set AO486_ROUNDTRIP_DIFF_EXCERPT=<n> for per-module field excerpt" if diff_excerpt_limit.zero?
    lines.concat(format_module_diff_excerpt(module_diffs))
    lines.join("\n")
  end

  def semantic_signature_for_module(mod)
    {
      parameters: stable_sort((mod.parameters || {}).map { |k, v| [k.to_s, v] }),
      ports: stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
      regs: stable_sort(mod.regs.map { |reg| [reg.width.to_i, reg.reset_value] }),
      assigns: stable_sort(mod.assigns.map { |assign| expr_signature(assign.expr) }),
      processes: stable_sort(mod.processes.map { |process| process_signature(process) }),
      instances: stable_sort(mod.instances.map { |inst| instance_signature(inst) }),
      memories: stable_sort(mod.memories.map { |mem| memory_signature(mem) }),
      write_ports: stable_sort(mod.write_ports.map { |port| write_port_signature(port) }),
      sync_read_ports: stable_sort(mod.sync_read_ports.map { |port| sync_read_port_signature(port) })
    }
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
      connections: stable_sort(
        Array(inst.connections).map do |conn|
          [conn.direction.to_s, conn.port_name.to_s]
        end
      )
    }
  end

  def memory_signature(mem)
    {
      depth: mem.depth.to_i,
      width: mem.width.to_i
    }
  end

  def write_port_signature(port)
    {
      memory: port.memory.to_s,
      clock: port.clock.to_s,
      addr: expr_signature(port.addr),
      data: expr_signature(port.data),
      enable: expr_signature(port.enable)
    }
  end

  def sync_read_port_signature(port)
    {
      memory: port.memory.to_s,
      clock: port.clock.to_s,
      addr: expr_signature(port.addr),
      data: port.data.to_s,
      enable: port.enable ? expr_signature(port.enable) : nil
    }
  end

  def expr_signature(expr)
    case expr
    when RHDL::Codegen::CIRCT::IR::Signal
      [:signal, expr.width.to_i]
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
      reduced = reduced_slice_signature(expr)
      return reduced if reduced

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

  def commutative_binop?(op)
    %i[+ * & | ^ == !=].include?(op.to_sym)
  end

  def reduced_slice_signature(expr)
    return nil unless expr.range.min == 0
    return nil unless expr.range.max == (expr.width.to_i - 1)
    return nil unless expr.base.is_a?(RHDL::Codegen::CIRCT::IR::BinaryOp)

    bin = expr.base
    left = maybe_unpadded_operand_signature(bin.left, expr.width.to_i)
    right = maybe_unpadded_operand_signature(bin.right, expr.width.to_i)
    return nil unless left && right

    left, right = stable_sort([left, right]) if commutative_binop?(bin.op)
    [:binary, bin.op.to_s, expr.width.to_i, left, right]
  end

  def maybe_unpadded_operand_signature(expr, width)
    return expr_signature(expr) if expr.respond_to?(:width) && expr.width.to_i == width

    return nil unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Concat)
    return nil unless expr.width.to_i == width + 1
    return nil unless expr.parts.length == 2

    high, low = expr.parts
    return nil unless high.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
    return nil unless high.width.to_i == 1 && high.value.to_i.zero?
    return nil unless low.respond_to?(:width) && low.width.to_i == width

    expr_signature(low)
  end

  def stable_sort(items)
    items.sort_by { |item| Marshal.dump(item) }
  end

  it 'preserves normalized per-module AST signatures across CIRCT -> RHDL -> CIRCT for full import', timeout: 1800 do
    skip 'circt-translate not available' unless HdlToolchain.which('circt-translate')
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    Dir.mktmpdir('ao486_roundtrip_out') do |out_dir|
      Dir.mktmpdir('ao486_roundtrip_ws') do |workspace|
        import_result = run_importer(out_dir: out_dir, workspace: workspace)
        expect(import_result.success?).to be(true), diagnostic_summary(import_result)
        expect(import_result.strategy_used).to eq(:tree)

        source_mlir = File.read(import_result.normalized_core_mlir_path)
        source_import = RHDL::Codegen.import_circt_mlir(source_mlir)
        expect(source_import.success?).to be(true), diagnostic_summary(source_import)

        raised = RHDL::Codegen.raise_circt_components(source_mlir, namespace: Module.new, top: 'system')
        expect(raised.success?).to be(true), diagnostic_summary(raised)

        roundtrip_mlir = raised.components.keys.sort.map do |module_name|
          raised.components.fetch(module_name).to_ir(top_name: module_name)
        end.join("\n\n")

        roundtrip_import = RHDL::Codegen.import_circt_mlir(roundtrip_mlir)
        expect(roundtrip_import.success?).to be(true), diagnostic_summary(roundtrip_import)

        source_sigs = normalized_module_signatures(source_import.modules)
        roundtrip_sigs = normalized_module_signatures(roundtrip_import.modules)

        missing_modules = source_sigs.keys - roundtrip_sigs.keys
        extra_modules = roundtrip_sigs.keys - source_sigs.keys
        common = source_sigs.keys & roundtrip_sigs.keys
        mismatched = common.reject { |name| source_sigs[name] == roundtrip_sigs[name] }

        mismatch_summary = build_mismatch_summary(
          source_sigs: source_sigs,
          roundtrip_sigs: roundtrip_sigs,
          missing_modules: missing_modules,
          extra_modules: extra_modules,
          mismatched_modules: mismatched
        )

        expect(missing_modules).to be_empty, mismatch_summary
        expect(extra_modules).to be_empty, mismatch_summary
        expect(mismatched).to be_empty, mismatch_summary
      end
    end
  end
end
