require 'spec_helper'
require 'json'
require 'fileutils'

module RHDL
  module SpecFixtures
    class CIRCTAdder < RHDL::Sim::Component
      input :a, width: 8
      input :b, width: 8
      output :y, width: 8

      behavior do
        y <= a + b
      end
    end

    class CIRCTWireChild < RHDL::Sim::Component
      input :a, width: 8
      output :y, width: 8

      behavior do
        y <= a
      end
    end

    class CIRCTHierTop < RHDL::Sim::Component
      input :a, width: 8
      output :y, width: 8

      instance :u, CIRCTWireChild
      port :a => [:u, :a]
      port [:u, :y] => :y
    end

    class CIRCTSharedChildTop < RHDL::Sim::Component
      input :a, width: 8
      output :y0, width: 8
      output :y1, width: 8

      instance :u0, CIRCTWireChild
      instance :u1, CIRCTWireChild
      port :a => [:u0, :a]
      port :a => [:u1, :a]
      port [:u0, :y] => :y0
      port [:u1, :y] => :y1
    end
  end
end

RSpec.describe 'CIRCT core IR pipeline' do
  describe 'DSL lowering contracts' do
    it 'emits CIRCT MLIR from to_ir' do
      mlir = RHDL::SpecFixtures::CIRCTAdder.to_ir
      expect(mlir).to be_a(String)
      expect(mlir).to include('hw.module @spec_fixtures_circt_adder')
      expect(mlir).to include('hw.output')
    end

    it 'keeps to_circt as an alias to to_ir' do
      expect(RHDL::SpecFixtures::CIRCTAdder.to_circt).to eq(RHDL::SpecFixtures::CIRCTAdder.to_ir)
    end

    it 'keeps hierarchy aliases for CIRCT and IR naming' do
      circt = RHDL::SpecFixtures::CIRCTHierTop.to_circt_hierarchy
      ir = RHDL::SpecFixtures::CIRCTHierTop.to_ir_hierarchy
      ir_misspelled = RHDL::SpecFixtures::CIRCTHierTop.to_ir_heirarchy

      expect(ir).to eq(circt)
      expect(ir_misspelled).to eq(circt)
      expect(circt).to include('hw.instance "u" @spec_fixtures_circt_wire_child')
    end

    it 'keeps RHDL::Codegen aliases for CIRCT and IR naming' do
      component = RHDL::SpecFixtures::CIRCTAdder
      expect(RHDL::Codegen.to_circt(component)).to eq(RHDL::Codegen.to_ir(component))
      expect(RHDL::Codegen.to_ir(component)).to include('hw.module @spec_fixtures_circt_adder')
    end

    it 'exposes CIRCT nodes and flattened CIRCT nodes explicitly' do
      circt_nodes = RHDL::SpecFixtures::CIRCTAdder.to_circt_nodes
      flat_circt_nodes = RHDL::SpecFixtures::CIRCTAdder.to_flat_circt_nodes

      expect(circt_nodes).to be_a(RHDL::Codegen::CIRCT::IR::ModuleOp)
      expect(flat_circt_nodes).to be_a(RHDL::Codegen::CIRCT::IR::ModuleOp)
    end

    it 'does not expose legacy DSL IR entry points' do
      expect(RHDL::SpecFixtures::CIRCTAdder).not_to respond_to(:to_flat_ir)
      expect(RHDL::SpecFixtures::CIRCTAdder).not_to respond_to(:to_legacy_ir)
    end

    it 'serializes flattened CIRCT nodes for runtime JSON' do
      json = RHDL::SpecFixtures::CIRCTAdder.to_circt_runtime_json
      parsed = JSON.parse(json)
      expect(parsed['circt_json_version']).to eq(1)
      expect(parsed['modules']).to be_an(Array)
      expect(parsed['modules'].first['name']).to eq('spec_fixtures_circt_adder')
    end

    it 'reuses the same child flatten template for repeated identical instances' do
      allow(RHDL::SpecFixtures::CIRCTWireChild).to receive(:build_flat_circt_module).and_call_original

      flat = RHDL::SpecFixtures::CIRCTSharedChildTop.to_flat_circt_nodes
      assign_targets = flat.assigns.map { |assign| assign.target.to_s }
      net_names = flat.nets.map { |net| net.name.to_s }

      expect(RHDL::SpecFixtures::CIRCTWireChild).to have_received(:build_flat_circt_module)
        .with(parameters: {})
        .once
      expect(assign_targets).to include('u0__a', 'u1__a', 'y0', 'y1')
      expect(net_names).to include('u0__y', 'u1__y')
    end

    it 'serializes instance connections with structured expression payloads' do
      ir = RHDL::Codegen::CIRCT::IR
      mod = ir::ModuleOp.new(
        name: 'top',
        ports: [
          ir::Port.new(name: :a, direction: :in, width: 8),
          ir::Port.new(name: :y, direction: :out, width: 8)
        ],
        nets: [ir::Net.new(name: 'u__y', width: 8)],
        regs: [],
        assigns: [ir::Assign.new(target: :y, expr: ir::Signal.new(name: 'u__y', width: 8))],
        processes: [],
        instances: [
          ir::Instance.new(
            name: 'u',
            module_name: 'child',
            connections: [
              ir::PortConnection.new(
                port_name: :a,
                signal: ir::Signal.new(name: :a, width: 8),
                direction: :in
              ),
              ir::PortConnection.new(
                port_name: :y,
                signal: 'u__y',
                direction: :out
              )
            ],
            parameters: { width: 8 }
          )
        ],
        memories: [],
        write_ports: [],
        sync_read_ports: [],
        parameters: {}
      )

      parsed = JSON.parse(RHDL::Codegen::CIRCT::RuntimeJSON.dump(mod))
      inst = parsed['modules'].first['instances'].first
      expect(inst['module_name']).to eq('child')
      expect(inst['parameters']).to eq({ 'width' => 8 })
      expect(inst['connections'].first['signal']['kind']).to eq('signal')
      expect(inst['connections'].first['signal']['name']).to eq('a')
      expect(inst['connections'].last['signal']).to eq('u__y')
    end

    it 'provides class-level verilog export via circt tooling path' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |kwargs|
        File.write(kwargs[:out_path], "module spec_fixtures_circt_adder;\nendmodule\n")
        {
          success: true,
          command: "#{RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL} input.mlir --verilog -o output.v",
          stdout: '',
          stderr: ''
        }
      end

      verilog = RHDL::SpecFixtures::CIRCTAdder.to_verilog_via_circt
      expect(verilog).to include('module spec_fixtures_circt_adder')
    end

    it 'emits hw.instance for hierarchical components' do
      mlir = RHDL::SpecFixtures::CIRCTHierTop.to_ir
      expect(mlir).to include('hw.instance "u" @spec_fixtures_circt_wire_child')
    end
  end

  describe 'CIRCT import and raise' do
    let(:mlir) do
      <<~MLIR
        hw.module @simple_adder(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8
          hw.output %sum : i8
        }
      MLIR
    end

    it 'imports MLIR into CIRCT nodes' do
      result = RHDL::Codegen::CIRCT::Import.from_mlir(mlir)
      expect(result.success?).to be(true)
      expect(result.modules.length).to eq(1)
      expect(result.modules.first.name).to eq('simple_adder')
    end

    it 'raises CIRCT MLIR to Ruby DSL source files' do
      out_dir = File.join('tmp', 'circt_raise_spec')
      FileUtils.rm_rf(out_dir)

      result = RHDL::Codegen::CIRCT::Raise.to_dsl(mlir, out_dir: out_dir, top: 'simple_adder')
      expect(result.files_written).not_to be_empty
      expect(result.success?).to be(true)

      generated = File.read(result.files_written.first)
      expect(generated).to include('class SimpleAdder')
      expect(generated).to include('behavior do')
    end

    it 'raises module parameters into DSL parameter declarations' do
      mlir = <<~MLIR
        hw.module @param_adder<WIDTH: i32 = 8>(%a: i8, %b: i8) -> (y: i8) {
          %sum = comb.add %a, %b : i8
          hw.output %sum : i8
        }
      MLIR

      result = RHDL::Codegen.raise_circt_sources(mlir, top: 'param_adder')
      expect(result.success?).to be(true)
      expect(result.sources['param_adder']).to include('parameter :WIDTH, default: 8')
      expect(result.diagnostics.any? { |d| d.op == 'raise.module_params' }).to be(false)
    end

    it 'round-trips hierarchical MLIR into loaded component classes' do
      mlir = RHDL::SpecFixtures::CIRCTHierTop.to_mlir_hierarchy
      namespace = Module.new

      result = RHDL::Codegen.raise_circt_components(mlir, namespace: namespace, top: 'spec_fixtures_circt_hier_top')
      expect(result.success?).to be(true)
      expect(result.components.keys).to include('spec_fixtures_circt_wire_child', 'spec_fixtures_circt_hier_top')
      expect(namespace.const_defined?(:SpecFixturesCirctWireChild, false)).to be(true)
      expect(namespace.const_defined?(:SpecFixturesCirctHierTop, false)).to be(true)
      top_class = namespace.const_get(:SpecFixturesCirctHierTop, false)
      expect(top_class.respond_to?(:_instance_defs)).to be(true)
      expect(top_class._instance_defs.map { |d| d[:name] }).to include(:u)
    end
  end
end
