# frozen_string_literal: true

require 'spec_helper'

module RHDL
  module SpecFixtures
    class ToMlirHierarchySharedSlice < RHDL::Sim::Component
      input :a, width: 8
      output :y, width: 8

      behavior do
        y <= a[7..4].concat(a[7..4])
      end
    end

    class ToMlirHierarchySharedSequentialSlice < RHDL::Sim::SequentialComponent
      include RHDL::DSL::Sequential

      input :clk
      input :a, width: 8
      output :q0, width: 4
      output :q1, width: 4

      sequential clock: :clk do
        q0 <= a[7..4]
        q1 <= a[7..4]
      end
    end
  end
end

RSpec.describe 'RHDL::Codegen CIRCT fresh export performance' do
  let(:ir) { RHDL::Codegen::CIRCT::IR }

  def capture_ir_ctor_counts
    counts = {
      slice: 0,
      signal: Hash.new(0)
    }

    allow(RHDL::Codegen::CIRCT::IR::Slice).to receive(:new).and_wrap_original do |orig, **kwargs|
      counts[:slice] += 1
      orig.call(**kwargs)
    end

    allow(RHDL::Codegen::CIRCT::IR::Signal).to receive(:new).and_wrap_original do |orig, **kwargs|
      name = kwargs[:name]
      counts[:signal][name.to_s] += 1 unless name.nil?
      orig.call(**kwargs)
    end

    yield counts
  end

  def shared_slice_outputs_module
    ir::ModuleOp.new(
      name: 'shared_slice_outputs',
      ports: [
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :y0, direction: :out, width: 4),
        ir::Port.new(name: :y1, direction: :out, width: 4)
      ],
      nets: [],
      regs: [],
      assigns: [
        ir::Assign.new(
          target: :y0,
          expr: ir::Slice.new(
            base: ir::Signal.new(name: :a, width: 8),
            range: 7..4,
            width: 4
          )
        ),
        ir::Assign.new(
          target: :y1,
          expr: ir::Slice.new(
            base: ir::Signal.new(name: :a, width: 8),
            range: 7..4,
            width: 4
          )
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

  def shared_slice_sequential_module
    ir::ModuleOp.new(
      name: 'shared_slice_seq',
      ports: [
        ir::Port.new(name: :clk, direction: :in, width: 1),
        ir::Port.new(name: :a, direction: :in, width: 8),
        ir::Port.new(name: :q0, direction: :out, width: 4),
        ir::Port.new(name: :q1, direction: :out, width: 4)
      ],
      nets: [],
      regs: [
        ir::Reg.new(name: :q0, width: 4),
        ir::Reg.new(name: :q1, width: 4)
      ],
      assigns: [
        ir::Assign.new(target: :q0, expr: ir::Signal.new(name: :q0, width: 4)),
        ir::Assign.new(target: :q1, expr: ir::Signal.new(name: :q1, width: 4))
      ],
      processes: [
        ir::Process.new(
          name: :shared_slice_seq,
          clocked: true,
          clock: :clk,
          statements: [
            ir::SeqAssign.new(
              target: :q0,
              expr: ir::Slice.new(
                base: ir::Signal.new(name: :a, width: 8),
                range: 7..4,
                width: 4
              )
            ),
            ir::SeqAssign.new(
              target: :q1,
              expr: ir::Slice.new(
                base: ir::Signal.new(name: :a, width: 8),
                range: 7..4,
                width: 4
              )
            )
          ]
        )
      ],
      instances: [],
      memories: [],
      write_ports: [],
      sync_read_ports: [],
      parameters: {}
    )
  end

  it 'memoizes repeated behavior expression lowering within one export-pass cache' do
    capture_ir_ctor_counts do |counts|
      signal = RHDL::DSL::Behavior::BehaviorSignalRef.new(:a, width: 8)
      slice_a = RHDL::DSL::Behavior::BehaviorSlice.new(signal, 7..4)
      slice_b = RHDL::DSL::Behavior::BehaviorSlice.new(signal, 7..4)
      concat = RHDL::DSL::Behavior::BehaviorConcat.new([slice_a, slice_b], width: 8)

      ir = concat.to_ir({})

      expect(ir).to be_a(RHDL::Codegen::CIRCT::IR::Concat)
      expect(counts[:slice]).to eq(1)
      expect(counts[:signal].fetch('a')).to eq(1)
    end
  end

  it 'memoizes repeated synth expression lowering within one export-pass cache' do
    capture_ir_ctor_counts do |counts|
      signal = RHDL::Synth::SignalProxy.new(:a, 8)
      concat = signal[7..4].concat(signal[7..4])

      ir = concat.to_ir({})

      expect(ir).to be_a(RHDL::Codegen::CIRCT::IR::Concat)
      expect(counts[:slice]).to eq(1)
      expect(counts[:signal].fetch('a')).to eq(1)
    end
  end

  it 'uses the fresh export-pass cache during to_mlir_hierarchy' do
    capture_ir_ctor_counts do |counts|
      mlir = RHDL::SpecFixtures::ToMlirHierarchySharedSlice.to_mlir_hierarchy(
        top_name: 'spec_fixtures_to_mlir_hierarchy_shared_slice'
      )

      expect(mlir).to include('hw.module @spec_fixtures_to_mlir_hierarchy_shared_slice')
      expect(mlir).to include('comb.concat')
      expect(counts[:slice]).to eq(1)
      expect(counts[:signal].fetch('a')).to eq(1)
    end
  end

  it 'uses the fresh export-pass cache during sequential to_mlir_hierarchy export' do
    capture_ir_ctor_counts do |counts|
      mlir = RHDL::SpecFixtures::ToMlirHierarchySharedSequentialSlice.to_mlir_hierarchy(
        top_name: 'spec_fixtures_to_mlir_hierarchy_shared_sequential_slice'
      )

      expect(mlir).to include('hw.module @spec_fixtures_to_mlir_hierarchy_shared_sequential_slice')
      expect(mlir).to include('seq.firreg')
      expect(counts[:slice]).to eq(1)
      expect(counts[:signal].fetch('a')).to eq(1)
    end
  end

  it 'shares structurally identical raised expressions across behavior assignments' do
    result = RHDL::Codegen::CIRCT::Raise.to_sources(
      shared_slice_outputs_module,
      top: 'shared_slice_outputs',
      strict: true
    )

    expect(result.success?).to be(true)
    source = result.sources.fetch('shared_slice_outputs')
    shared_local_match = source.match(
      /^\s+(\w+)\s*=\s*local\(\s*:?\1,\s*a\[(?:4\.\.7|7\.\.4)\],\s*width: 4\s*\)$/m
    )

    expect(shared_local_match).not_to be_nil
    shared_local = shared_local_match[1]
    expect(source.scan(/a\[(?:4\.\.7|7\.\.4)\]/).length).to eq(1)
    expect(source.scan(/<= #{Regexp.escape(shared_local)}\b/).length).to eq(2)
  end

  it 'shares structurally identical raised expressions across sequential targets' do
    result = RHDL::Codegen::CIRCT::Raise.to_sources(
      shared_slice_sequential_module,
      top: 'shared_slice_seq',
      strict: true
    )

    expect(result.success?).to be(true)
    source = result.sources.fetch('shared_slice_seq')
    shared_local_match = source.match(
      /^\s+(\w+)\s*=\s*local\(\s*:?\1,\s*a\[(?:4\.\.7|7\.\.4)\],\s*width: 4\s*\)$/m
    )

    expect(shared_local_match).not_to be_nil
    shared_local = shared_local_match[1]
    expect(source.scan(/a\[(?:4\.\.7|7\.\.4)\]/).length).to eq(1)
    expect(source.scan(/q[01] <= #{Regexp.escape(shared_local)}\b/).length).to eq(2)
  end

  it 'reuses raised shared locals during fresh hierarchy export across assignments' do
    mod = shared_slice_outputs_module

    capture_ir_ctor_counts do |counts|
      result = RHDL::Codegen::CIRCT::Raise.to_components(
        mod,
        namespace: Module.new,
        top: 'shared_slice_outputs',
        strict: true
      )

      expect(result.success?).to be(true)
      component_class = result.components.fetch('shared_slice_outputs')

      mlir = component_class.to_mlir_hierarchy(top_name: 'shared_slice_outputs')

      expect(mlir).to include('hw.module @shared_slice_outputs')
      expect(counts[:slice]).to eq(2)
      expect(counts[:signal].fetch('a')).to eq(1)
    end
  end
end
