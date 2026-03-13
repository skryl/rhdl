# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'open3'

RSpec.describe 'RHDL import path coverage' do
  RAISE_DEGRADE_OPS = %w[
    raise.behavior
    raise.expr
    raise.memory_read
    raise.case
    raise.sequential
  ].freeze

  let(:verilog_fixture) do
    <<~VERILOG
      module import_comb(
        input [7:0] a,
        input [7:0] b,
        output [7:0] y
      );
        assign y = a + b;
      endmodule
    VERILOG
  end

  let(:circt_comb_mlir) do
    <<~MLIR
      hw.module @circt_roundtrip(in %a: i8, in %b: i8, out y: i8) {
        %sum = comb.add %a, %b : i8
        hw.output %sum : i8
      }
    MLIR
  end

  let(:circt_mixed_mlir) do
    <<~MLIR
      hw.module @import_comb(in %a: i8, in %b: i8, out y: i8) {
        %sum = comb.add %a, %b : i8
        hw.output %sum : i8
      }

      hw.module @import_seq(in %d: i8, in %clk: i1, out q: i8) {
        %q = seq.compreg %d, %clk : i8
        hw.output %q : i8
      }
    MLIR
  end

  let(:comb_inputs) { { a: 8, b: 8 } }
  let(:comb_outputs) { { y: 8 } }
  let(:comb_vectors) do
    [
      { inputs: { a: 0, b: 0 } },
      { inputs: { a: 1, b: 2 } },
      { inputs: { a: 3, b: 9 } },
      { inputs: { a: 11, b: 13 } },
      { inputs: { a: 255, b: 1 } }
    ]
  end

  it 'covers Verilog -> CIRCT' do
    require_tool!('circt-verilog')

    Dir.mktmpdir('rhdl_import_path_v2c') do |dir|
      mlir = convert_verilog_to_mlir(verilog_fixture, base_dir: dir, stem: 'import_comb')
      import_result = RHDL::Codegen.import_circt_mlir(mlir)

      expect(import_result.success?).to be(true), diagnostic_summary(import_result.diagnostics)
      expect(import_result.modules.map(&:name)).to include('import_comb')
      expect(mlir).to include('hw.module @import_comb')
    end
  end

  it 'covers CIRCT -> RHDL at highest available DSL level' do
    raise_result = RHDL::Codegen.raise_circt_sources(circt_mixed_mlir, top: 'import_comb')

    expect(raise_result.success?).to be(true), diagnostic_summary(raise_result.diagnostics)
    expect_no_raise_degrade!(raise_result.diagnostics)

    comb_source = raise_result.sources.fetch('import_comb')
    seq_source = raise_result.sources.fetch('import_seq')

    expect(comb_source).to include('behavior do')
    expect(comb_source).to include('y <=')
    expect(seq_source).to include('sequential clock: :clk do')
  end

  it 'covers Verilog -> CIRCT -> RHDL at highest available DSL level' do
    require_tool!('circt-verilog')

    Dir.mktmpdir('rhdl_import_path_v2c2r') do |dir|
      mlir = convert_verilog_to_mlir(verilog_fixture, base_dir: dir, stem: 'import_comb')
      raise_result = RHDL::Codegen.raise_circt_sources(mlir, top: 'import_comb')

      expect(raise_result.success?).to be(true), diagnostic_summary(raise_result.diagnostics)
      expect_no_raise_degrade!(raise_result.diagnostics)

      source = raise_result.sources.fetch('import_comb')
      expect(source).to include('behavior do')
      expect(source).to include('y <=')
    end
  end

  it 'covers CIRCT -> RHDL -> CIRCT with semantic retention' do
    require_behavior_tools!
    require_export_tool!

    Dir.mktmpdir('rhdl_import_path_c2r2c') do |dir|
      components = RHDL::Codegen.raise_circt_components(circt_comb_mlir, top: 'circt_roundtrip')
      expect(components.success?).to be(true), diagnostic_summary(components.diagnostics)
      expect_no_raise_degrade!(components.diagnostics)

      roundtrip_component = components.components.fetch('circt_roundtrip')
      roundtrip_mlir = roundtrip_component.to_ir(top_name: 'circt_roundtrip')

      source_sig = normalized_semantic_signature_from_mlir(circt_comb_mlir)
      roundtrip_sig = normalized_semantic_signature_from_mlir(roundtrip_mlir)
      expect(roundtrip_sig).to eq(source_sig)

      source_verilog = convert_mlir_to_verilog(circt_comb_mlir, base_dir: dir, stem: 'source_roundtrip')
      roundtrip_verilog = convert_mlir_to_verilog(roundtrip_mlir, base_dir: dir, stem: 'raised_roundtrip')

      source_outputs = simulate_verilog(
        source_verilog,
        module_name: 'circt_roundtrip',
        inputs: comb_inputs,
        outputs: comb_outputs,
        test_vectors: comb_vectors,
        base_dir: File.join(dir, 'sim_source')
      )
      roundtrip_outputs = simulate_verilog(
        roundtrip_verilog,
        module_name: 'circt_roundtrip',
        inputs: comb_inputs,
        outputs: comb_outputs,
        test_vectors: comb_vectors,
        base_dir: File.join(dir, 'sim_roundtrip')
      )

      expect(roundtrip_outputs).to eq(source_outputs)
    end
  end

  it 'covers Verilog -> CIRCT -> RHDL -> CIRCT -> Verilog with semantic retention' do
    require_tool!('circt-verilog')
    require_behavior_tools!
    require_export_tool!

    Dir.mktmpdir('rhdl_import_path_v2c2r2c2v') do |dir|
      source_mlir = convert_verilog_to_mlir(verilog_fixture, base_dir: dir, stem: 'source_input')
      raise_components = RHDL::Codegen.raise_circt_components(source_mlir, top: 'import_comb')
      expect(raise_components.success?).to be(true), diagnostic_summary(raise_components.diagnostics)
      expect_no_raise_degrade!(raise_components.diagnostics)

      roundtrip_component = raise_components.components.fetch('import_comb')
      roundtrip_mlir = roundtrip_component.to_ir(top_name: 'import_comb')
      roundtrip_verilog = convert_mlir_to_verilog(roundtrip_mlir, base_dir: dir, stem: 'roundtrip_output')

      source_sig = normalized_semantic_signature_from_verilog(
        verilog_fixture,
        base_dir: File.join(dir, 'sig_source'),
        stem: 'source'
      )
      roundtrip_sig = normalized_semantic_signature_from_verilog(
        roundtrip_verilog,
        base_dir: File.join(dir, 'sig_roundtrip'),
        stem: 'roundtrip'
      )
      expect(roundtrip_sig).to eq(source_sig)

      source_outputs = simulate_verilog(
        verilog_fixture,
        module_name: 'import_comb',
        inputs: comb_inputs,
        outputs: comb_outputs,
        test_vectors: comb_vectors,
        base_dir: File.join(dir, 'sim_source')
      )
      roundtrip_outputs = simulate_verilog(
        roundtrip_verilog,
        module_name: 'import_comb',
        inputs: comb_inputs,
        outputs: comb_outputs,
        test_vectors: comb_vectors,
        base_dir: File.join(dir, 'sim_roundtrip')
      )

      expect(roundtrip_outputs).to eq(source_outputs)
    end
  end

  private

  def require_tool!(cmd)
    skip "#{cmd} not available" unless HdlToolchain.which(cmd)
  end

  def require_behavior_tools!
    skip 'iverilog/vvp not available' unless HdlToolchain.iverilog_available?
  end

  def require_export_tool!
    skip "#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL} not available for MLIR export" unless export_tool
  end

  def export_tool
    tool = RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL
    return tool if HdlToolchain.which(tool)

    nil
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
    expect(File.exist?(core_mlir_path)).to be(true)

    File.read(core_mlir_path)
  end

  def convert_mlir_to_verilog(mlir_source, base_dir:, stem:)
    mlir_path = File.join(base_dir, "#{stem}.mlir")
    verilog_path = File.join(base_dir, "#{stem}.v")
    File.write(mlir_path, mlir_source)

    result = RHDL::Codegen::CIRCT::Tooling.circt_mlir_to_verilog(
      mlir_path: mlir_path,
      out_path: verilog_path,
      tool: export_tool
    )
    expect(result[:success]).to be(true), "CIRCT->Verilog failed:\n#{result[:command]}\n#{result[:stderr]}"
    expect(File.exist?(verilog_path)).to be(true)

    File.read(verilog_path)
  end

  def simulate_verilog(verilog_source, module_name:, inputs:, outputs:, test_vectors:, base_dir:)
    result = NetlistHelper.run_behavior_simulation(
      verilog_source,
      module_name: module_name,
      inputs: inputs,
      outputs: outputs,
      test_vectors: test_vectors,
      base_dir: base_dir
    )
    expect(result[:success]).to be(true), "Simulation failed: #{result[:error]}"

    result[:results]
  end

  def expect_no_raise_degrade!(diagnostics)
    degrade = diagnostics.select { |diag| RAISE_DEGRADE_OPS.include?(diag.op.to_s) }
    expect(degrade).to be_empty, diagnostic_summary(degrade)
  end

  def normalized_semantic_signature_from_verilog(verilog_source, base_dir:, stem:)
    mlir = convert_verilog_to_mlir(verilog_source, base_dir: base_dir, stem: stem)
    normalized_semantic_signature_from_mlir(mlir)
  end

  def normalized_semantic_signature_from_mlir(mlir)
    import_result = RHDL::Codegen.import_circt_mlir(mlir)
    expect(import_result.success?).to be(true), diagnostic_summary(import_result.diagnostics)

    stable_sort(import_result.modules.map { |mod| semantic_signature_for_module(mod) })
  end

  def semantic_signature_for_module(mod)
    {
      parameters: stable_sort((mod.parameters || {}).map { |k, v| [k.to_s, v] }),
      ports: stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
      regs: stable_sort(mod.regs.map { |reg| [reg.width.to_i, reg.reset_value] }),
      assigns: stable_sort(mod.assigns.map { |assign| expr_signature(assign.expr) }),
      processes: stable_sort(mod.processes.map { |process| process_signature(process) }),
      instances: stable_sort(mod.instances.map { |inst| instance_signature(inst) })
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

  def diagnostic_summary(diagnostics)
    return '' if diagnostics.nil? || diagnostics.empty?

    diagnostics.map do |diag|
      "[#{diag.severity}]#{diag.op ? " #{diag.op}:" : ''} #{diag.message}"
    end.join("\n")
  end
end
