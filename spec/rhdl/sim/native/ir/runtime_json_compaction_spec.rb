# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'stringio'

RSpec.describe RHDL::Codegen::CIRCT::RuntimeJSON do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def build_alias_chain_runtime_module
    src = ir::Signal.new(name: :src, width: 8)
    alias_a = ir::Signal.new(name: :alias_a, width: 8)
    alias_b = ir::Signal.new(name: :alias_b, width: 8)

    ir::ModuleOp.new(
      name: 'runtime_alias_chain',
      ports: [
        ir::Port.new(name: :src, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [
        ir::Net.new(name: :alias_a, width: 8),
        ir::Net.new(name: :alias_b, width: 8)
      ],
      regs: [],
      assigns: [
        ir::Assign.new(target: :alias_a, expr: src),
        ir::Assign.new(target: :alias_b, expr: alias_a),
        ir::Assign.new(target: :y, expr: alias_b)
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_repeated_concat_runtime_module
    bit = ir::Signal.new(name: :bit, width: 1)

    ir::ModuleOp.new(
      name: 'runtime_repeated_concat',
      ports: [
        ir::Port.new(name: :bit, direction: :in, width: 1),
        ir::Port.new(name: :packed, direction: :out, width: 34)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :packed,
          expr: ir::Concat.new(parts: Array.new(34) { bit }, width: 34)
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  def build_structural_pool_runtime_module
    bus = ir::Signal.new(name: :bus, width: 16)
    a = ir::Signal.new(name: :a, width: 8)
    b = ir::Signal.new(name: :b, width: 8)
    sel = ir::Signal.new(name: :sel, width: 1)

    ir::ModuleOp.new(
      name: 'runtime_structural_pool',
      ports: [
        ir::Port.new(name: :bus, direction: :in, width: 16),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :b, direction: :in, width: 8),
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :slice0, direction: :out, width: 8),
        ir::Port.new(name: :slice1, direction: :out, width: 8),
        ir::Port.new(name: :and0, direction: :out, width: 8),
        ir::Port.new(name: :and1, direction: :out, width: 8),
        ir::Port.new(name: :mux0, direction: :out, width: 8),
        ir::Port.new(name: :mux1, direction: :out, width: 8),
        ir::Port.new(name: :resize0, direction: :out, width: 12),
        ir::Port.new(name: :resize1, direction: :out, width: 12)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(target: :slice0, expr: ir::Slice.new(base: bus, range: 7..0, width: 8)),
        ir::Assign.new(target: :slice1, expr: ir::Slice.new(base: bus, range: 7..0, width: 8)),
        ir::Assign.new(target: :and0, expr: ir::BinaryOp.new(op: '&', left: a, right: b, width: 8)),
        ir::Assign.new(target: :and1, expr: ir::BinaryOp.new(op: '&', left: a, right: b, width: 8)),
        ir::Assign.new(target: :mux0, expr: ir::Mux.new(condition: sel, when_true: a, when_false: b, width: 8)),
        ir::Assign.new(target: :mux1, expr: ir::Mux.new(condition: sel, when_true: a, when_false: b, width: 8)),
        ir::Assign.new(
          target: :resize0,
          expr: ir::Resize.new(expr: ir::Slice.new(base: bus, range: 7..0, width: 8), width: 12)
        ),
        ir::Assign.new(
          target: :resize1,
          expr: ir::Resize.new(expr: ir::Slice.new(base: bus, range: 7..0, width: 8), width: 12)
        )
      ],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  it 'collapses non-hierarchical alias chains during compact dump export' do
    runtime_mod = JSON.parse(described_class.dump(build_alias_chain_runtime_module, compact_exprs: true)).fetch('modules').fetch(0)

    expect(runtime_mod.fetch('assigns')).to eq(
      [
        {
          'target' => 'y',
          'expr' => { 'kind' => 'signal', 'name' => 'src', 'width' => 8 }
        }
      ]
    )
    expect(runtime_mod.fetch('nets')).to eq([])
  end

  it 'pools repeated concat parts through expr_ref in compact dump export' do
    runtime_mod = JSON.parse(described_class.dump(build_repeated_concat_runtime_module, compact_exprs: true)).fetch('modules').fetch(0)

    assign_expr = runtime_mod.fetch('assigns').fetch(0).fetch('expr')
    concat_expr = runtime_mod.fetch('exprs').fetch(assign_expr.fetch('id'))
    part_refs = concat_expr.fetch('parts')

    expect(part_refs).to all(include('kind' => 'expr_ref'))
    expect(part_refs.map { |part| part.fetch('id') }.uniq.length).to eq(1)
    expect(runtime_mod.fetch('exprs').fetch(part_refs.fetch(0).fetch('id'))).to include(
      'kind' => 'signal',
      'name' => 'bit',
      'width' => 1
    )
  end

  it 'streams the same repeated-concat compact payload through dump_to_io' do
    expected = JSON.parse(described_class.dump(build_repeated_concat_runtime_module, compact_exprs: true))
    io = StringIO.new

    described_class.dump_to_io(build_repeated_concat_runtime_module, io, compact_exprs: true)

    expect(JSON.parse(io.string)).to eq(expected)
  end

  it 'pools repeated slice, binary, mux, and resize trees through shared expr_ref ids in compact dump export' do
    runtime_mod = JSON.parse(described_class.dump(build_structural_pool_runtime_module, compact_exprs: true)).fetch('modules').fetch(0)

    assign_ids = runtime_mod.fetch('assigns').to_h do |assign|
      [assign.fetch('target'), assign.fetch('expr').fetch('id')]
    end

    aggregate_failures do
      expect(assign_ids.fetch('slice0')).to eq(assign_ids.fetch('slice1'))
      expect(assign_ids.fetch('and0')).to eq(assign_ids.fetch('and1'))
      expect(assign_ids.fetch('mux0')).to eq(assign_ids.fetch('mux1'))
      expect(assign_ids.fetch('resize0')).to eq(assign_ids.fetch('resize1'))
    end
  end
end
