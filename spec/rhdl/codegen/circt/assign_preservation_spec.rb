# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'CIRCT assign-preservation roundtrip' do
  FIXTURES = {
    'decode' => <<~MLIR,
      hw.module @decode(%a: i8, %b: i8) -> (y: i8) {
        %t = llhd.constant_time <0s, 1e>
        %decode_res = llhd.sig name "decode_res" 0 : i8
        %anded = comb.and %a, %b : i8
        llhd.drv %decode_res, %anded after %t : i8
        hw.output %decode_res : i8
      }
    MLIR
    'execute' => <<~MLIR,
      hw.module @execute(%a: i8, %b: i8) -> (y: i8) {
        %t = llhd.constant_time <0s, 1e>
        %execute_res = llhd.sig name "execute_res" 0 : i8
        %xor = comb.xor %a, %b : i8
        llhd.drv %execute_res, %xor after %t : i8
        hw.output %execute_res : i8
      }
    MLIR
    'l1_icache' => <<~MLIR,
      hw.module @l1_icache(%a: i8, %b: i8) -> (y: i8) {
        %t = llhd.constant_time <0s, 1e>
        %cache_res = llhd.sig name "cache_res" 0 : i8
        %anded = comb.and %a, %b : i8
        %slice = comb.extract %anded from 0 : (i8) -> i4
        %widen = comb.concat %slice, %slice : i4, i4
        llhd.drv %cache_res, %widen after %t : i8
        hw.output %cache_res : i8
      }
    MLIR
    'execute_divide' => <<~MLIR,
      hw.module @execute_divide(%a: i8, %b: i8) -> (y: i8) {
        %t = llhd.constant_time <0s, 1e>
        %execute_divide_res = llhd.sig name "execute_divide_res" 0 : i8
        %div = comb.divu %a, %b : i8
        llhd.drv %execute_divide_res, %div after %t : i8
        hw.output %execute_divide_res : i8
      }
    MLIR
    'memory' => <<~MLIR,
      hw.module @memory(%a: i8, %b: i8) -> (y: i8) {
        %t = llhd.constant_time <0s, 1e>
        %memory_res = llhd.sig name "memory_res" 0 : i8
        %low = comb.extract %a from 0 : (i8) -> i4
        %high = comb.extract %b from 0 : (i8) -> i4
        %packed = comb.concat %high, %low : i4, i4
        llhd.drv %memory_res, %packed after %t : i8
        hw.output %memory_res : i8
      }
    MLIR
    'multi_drive_output' => <<~MLIR,
      hw.module @multi_drive_output(%a: i1) -> (y: i1) {
        %t = llhd.constant_time <0s, 1e>
        %y_sig = llhd.sig name "y" 0 : i1
        %zero = hw.constant 0 : i1
        %one = hw.constant 1 : i1
        llhd.drv %y_sig, %zero after %t : i1
        llhd.drv %y_sig, %one after %t : i1
        hw.output %y_sig : i1
      }
    MLIR
    'input_target_drive' => <<~MLIR
      hw.module @input_target_drive(%clk: i1, %a: i1) -> (y: i1) {
        %t = llhd.constant_time <0s, 1e>
        %clk_sig = llhd.sig name "clk" 0 : i1
        %one = hw.constant 1 : i1
        llhd.drv %clk_sig, %one after %t : i1
        hw.output %a : i1
      }
    MLIR
  }.freeze

  def diag_lines(result)
    Array(result.diagnostics).map { |diag| "[#{diag.severity}] #{diag.op}: #{diag.message}" }.join("\n")
  end

  def stable_sort(items)
    items.sort_by { |item| Marshal.dump(item) }
  end

  def commutative_binop?(op)
    %i[+ * & | ^ == !=].include?(op.to_sym)
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
      [:slice, expr.width.to_i, expr_signature(expr.base), expr.range.min, expr.range.max]
    when RHDL::Codegen::CIRCT::IR::Resize
      [:resize, expr.width.to_i, expr_signature(expr.expr)]
    else
      [:expr, expr.class.name, expr.respond_to?(:width) ? expr.width.to_i : nil]
    end
  end

  def assign_signatures(mod)
    stable_sort(mod.assigns.map { |assign| expr_signature(assign.expr) })
  end

  def find_module(modules, name)
    modules.find { |mod| mod.name.to_s == name.to_s }
  end

  def roundtrip_assign_signatures(mlir, top:)
    source_import = RHDL::Codegen.import_circt_mlir(mlir, strict: true)
    expect(source_import.success?).to be(true), diag_lines(source_import)

    raised = RHDL::Codegen.raise_circt_components(mlir, namespace: Module.new, top: top, strict: true)
    expect(raised.success?).to be(true), diag_lines(raised)

    roundtrip_mlir = raised.components.fetch(top).to_ir(top_name: top)
    roundtrip_import = RHDL::Codegen.import_circt_mlir(roundtrip_mlir, strict: true)
    expect(roundtrip_import.success?).to be(true), diag_lines(roundtrip_import)

    source_mod = find_module(source_import.modules, top)
    roundtrip_mod = find_module(roundtrip_import.modules, top)

    [assign_signatures(source_mod), assign_signatures(roundtrip_mod)]
  end

  it 'emits non-output assign statements in raised behavior' do
    result = RHDL::Codegen::CIRCT::Raise.to_sources(FIXTURES.fetch('decode'), top: 'decode', strict: true)
    expect(result.success?).to be(true), diag_lines(result)

    source = result.sources.fetch('decode')
    expect(source).to include('decode_res <= (a & b)')
    expect(source).to include('y <= decode_res')
  end

  ROUNDTRIP_PARITY_FIXTURES = FIXTURES.except('multi_drive_output', 'input_target_drive').freeze

  ROUNDTRIP_PARITY_FIXTURES.each do |name, fixture_mlir|
    it "preserves assign-expression multiset for #{name}" do
      source_assigns, roundtrip_assigns = roundtrip_assign_signatures(fixture_mlir, top: name)
      # MLIR export intentionally normalizes away LLHD relay/signal assigns.
      expected = source_assigns.reject { |signature| signature[0] == :signal }
      expect(roundtrip_assigns).to eq(expected)
    end
  end

  it 'preserves multi-drive output assign-expression multiset' do
    _source_assigns, roundtrip_assigns = roundtrip_assign_signatures(FIXTURES.fetch('multi_drive_output'), top: 'multi_drive_output')
    # Multi-drive LLHD targets collapse to the final driver in normalized hw/comb export.
    expect(roundtrip_assigns).to eq([[:literal, 1, 1]])
  end

  it 'preserves input-target llhd.drv assign-expression multiset' do
    _source_assigns, roundtrip_assigns = roundtrip_assign_signatures(FIXTURES.fetch('input_target_drive'), top: 'input_target_drive')
    expect(roundtrip_assigns).to eq([[:signal, 1]])
  end
end
