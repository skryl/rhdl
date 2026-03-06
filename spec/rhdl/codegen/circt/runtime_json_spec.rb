# frozen_string_literal: true

require 'spec_helper'
require 'timeout'
require 'json'

RSpec.describe RHDL::Codegen::CIRCT::RuntimeJSON do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  it 'dumps shared expression DAGs without timing out' do
    sel = ir::Signal.new(name: :sel, width: 1)
    shared = ir::Signal.new(name: :a, width: 8)
    100.times do |idx|
      shared = ir::Mux.new(
        condition: idx.even? ? sel : ir::UnaryOp.new(op: :'~', operand: sel, width: 1),
        when_true: shared,
        when_false: shared,
        width: 8
      )
    end

    mod = ir::ModuleOp.new(
      name: 'runtime_shared_dag',
      ports: [
        ir::Port.new(name: :sel, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y, direction: :out, width: 8)
      ],
      nets: [],
      regs: [],
      assigns: [ir::Assign.new(target: :y, expr: shared)],
      processes: [],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )

    json = nil
    expect do
      Timeout.timeout(2) do
        json = described_class.dump(mod)
      end
    end.not_to raise_error

    payload = JSON.parse(json)
    expect(payload.fetch('circt_json_version')).to eq(1)
    runtime_mod = payload.fetch('modules').fetch(0)
    expect(runtime_mod.fetch('nets')).not_to be_empty
    expect(runtime_mod.fetch('assigns').length).to be > 1
  end
end
