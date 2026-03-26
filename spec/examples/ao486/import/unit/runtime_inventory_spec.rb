# frozen_string_literal: true

require 'spec_helper'

require_relative 'coverage_manifest'

RSpec.describe AO486UnitSupport::RuntimeImportSession do
  include AO486UnitSupport::RuntimeImportRequirements

  def eval_ir_expr(expr, env)
    case expr
    when RHDL::Codegen::CIRCT::IR::Signal
      env.fetch(expr.name.to_s, 0)
    when RHDL::Codegen::CIRCT::IR::Literal
      mask_width(expr.value, expr.width)
    when RHDL::Codegen::CIRCT::IR::BinaryOp
      left = eval_ir_expr(expr.left, env)
      right = eval_ir_expr(expr.right, env)
      mask = (1 << expr.width) - 1
      case expr.op
      when :|
        (left | right) & mask
      when :&
        (left & right) & mask
      when :^
        (left ^ right) & mask
      when :==
        left == right ? 1 : 0
      when :<
        left < right ? 1 : 0
      else
        raise "Unsupported IR binary op in test: #{expr.op.inspect}"
      end
    when RHDL::Codegen::CIRCT::IR::Mux
      cond = eval_ir_expr(expr.condition, env)
      branch = cond.zero? ? expr.when_false : expr.when_true
      eval_ir_expr(branch, env)
    else
      raise "Unsupported IR expr in test: #{expr.class}"
    end
  end

  def mask_width(value, width)
    return value if width.nil? || width <= 0

    value & ((1 << width) - 1)
  end

  def find_seq_assign(mod, target)
    Array(mod.processes).each do |process|
      Array(process.statements).each do |stmt|
        return stmt if stmt.is_a?(RHDL::Codegen::CIRCT::IR::SeqAssign) && stmt.target.to_s == target.to_s
      end
    end
    nil
  end

  def find_assign(mod, target)
    Array(mod.assigns).find { |assign| assign.target.to_s == target.to_s }
  end

  it 'builds a source-backed inventory from the default ao486 emitted import tree', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    inventory = session.inventory_records

    aggregate_failures do
      expect(inventory.length).to eq(RHDL::Examples::AO486::Unit::COVERED_MODULE_COUNT)
      expect(session.inventory_by_source_relative_path.length).to eq(RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILE_COUNT)
      expect(
        session.inventory_by_source_relative_path.transform_values { |records| records.map(&:module_name).sort }
      ).to eq(RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILES)
    end

    ao486 = session.module_record('ao486')
    l1_icache = session.module_record('l1_icache')

    aggregate_failures 'record metadata' do
      expect(ao486.source_relative_path).to eq('ao486/ao486.v')
      expect(ao486.generated_ruby_relative_path).to eq('ao486/ao486.rb')
      expect(File.file?(ao486.source_path)).to be(true)
      expect(File.file?(ao486.staged_source_path)).to be(true)
      expect(File.file?(ao486.generated_ruby_path)).to be(true)
      expect(ao486.component_class.verilog_module_name).to eq('ao486')

      expect(l1_icache.source_relative_path).to eq('cache/l1_icache.v')
      expect(l1_icache.generated_ruby_relative_path).to eq('cache/l1_icache.rb')
      expect(File.file?(l1_icache.source_path)).to be(true)
      expect(File.file?(l1_icache.staged_source_path)).to be(true)
      expect(File.file?(l1_icache.generated_ruby_path)).to be(true)
      expect(l1_icache.component_class.verilog_module_name).to eq('l1_icache')
    end
  end

  it 'preserves l1_icache startup state updates in the in-memory raised IR', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    mod = session.source_result.modules.find { |entry| entry.name == 'l1_icache' }
    expect(mod).not_to be_nil

    state_assign = find_seq_assign(mod, 'rt_tmp_4_3')
    update_tag_addr_assign = find_seq_assign(mod, 'rt_tmp_5_7')

    aggregate_failures do
      expect(state_assign).not_to be_nil
      expect(update_tag_addr_assign).not_to be_nil

      expect(state_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(update_tag_addr_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)

      expect(state_assign.expr.when_false).not_to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(update_tag_addr_assign.expr.when_false).not_to be_a(RHDL::Codegen::CIRCT::IR::Signal)
    end
  end

  it 'preserves l1_icache startup state updates in flattened imported IR for legacy runtime export', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    mod = session.module_record('l1_icache').component_class.to_flat_circt_nodes(top_name: 'l1_icache')

    state_assign = find_seq_assign(mod, 'rt_tmp_4_3')
    update_tag_addr_assign = find_seq_assign(mod, 'rt_tmp_5_7')

    aggregate_failures do
      expect(state_assign).not_to be_nil
      expect(update_tag_addr_assign).not_to be_nil

      expect(state_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
      expect(update_tag_addr_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)

      expect(state_assign.expr.when_false).not_to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(update_tag_addr_assign.expr.when_false).not_to be_a(RHDL::Codegen::CIRCT::IR::Signal)
    end
  end

  it 'preserves l1_icache CPU request hold startup logic in flattened imported IR for legacy runtime export', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    mod = session.module_record('l1_icache').component_class.to_flat_circt_nodes(top_name: 'l1_icache')
    cpu_req_hold_assign = find_seq_assign(mod, 'rt_tmp_9_1')

    expect(cpu_req_hold_assign).not_to be_nil

    value = eval_ir_expr(
      cpu_req_hold_assign.expr,
      {
        'RESET' => 0,
        'CPU_REQ' => 1,
        'rt_tmp_9_1' => 0,
        'rt_tmp_20_2' => 0,
        'rt_tmp_4_3' => 0
      }
    )

    expect(value).to eq(1)
  end

  it 'keeps flattened instance output links for the l1_icache snoop fifo in legacy runtime export', timeout: 480 do
    require_reference_tree!
    require_import_tool!

    session = described_class.current
    mod = session.module_record('l1_icache').component_class.to_flat_circt_nodes(top_name: 'l1_icache')
    empty_assign = find_assign(mod, 'isimple_fifo_empty_1')

    expect(empty_assign).not_to be_nil
    expect(empty_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
    expect(empty_assign.expr.name.to_s).to eq('isimple_fifo__empty')
  end
end
