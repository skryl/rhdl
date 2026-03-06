# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

module RHDL
  module SpecFixtures
    class CIRCTToolingAdder < RHDL::Sim::Component
      input :a, width: 8
      input :b, width: 8
      output :y, width: 8

      behavior do
        y <= a + b
      end
    end
  end
end

RSpec.describe 'RHDL::Codegen CIRCT APIs' do
  let(:mlir) do
    <<~MLIR
      hw.module @top(%a: i8, %b: i8) -> (y: i8) {
        %sum = comb.add %a, %b : i8
        hw.output %sum : i8
      }
    MLIR
  end

  describe '.import_circt_mlir' do
    it 'imports MLIR into CIRCT modules with diagnostics' do
      result = RHDL::Codegen.import_circt_mlir(mlir)
      expect(result).to be_a(RHDL::Codegen::CIRCT::ImportResult)
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to eq(['top'])
    end

    it 'accepts hw.module private headers produced by moore-to-core lowering' do
      private_mlir = <<~MLIR
        hw.module @top(%a: i1) -> (y: i1) {
          %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
          hw.output %child_y : i1
        }

        hw.module private @child(%a: i1) -> (y: i1) {
          hw.output %a : i1
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(private_mlir, strict: true, top: 'top')
      expect(result.success?).to be(true)
      expect(result.modules.map(&:name)).to include('top', 'child')
    end

    it 'supports strict mode for no-skip import contracts' do
      strict_mlir = <<~MLIR
        hw.module @strict_top(%a: i8) -> (y: i8) {
          comb.unknown %a : i8
          hw.output %a : i8
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(strict_mlir, strict: true)
      expect(result.success?).to be(false)
      expect(result.diagnostics.any? { |d| d.op == 'parser' && d.severity.to_s == 'error' }).to be(true)
    end

    it 'supports closure checks with top and extern module allowlist options' do
      closure_mlir = <<~MLIR
        hw.module @top(%a: i1) -> (y: i1) {
          %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
          hw.output %child_y : i1
        }
      MLIR

      fail_result = RHDL::Codegen.import_circt_mlir(closure_mlir, strict: true, top: 'top')
      expect(fail_result.success?).to be(false)
      expect(fail_result.diagnostics.any? { |d| d.op == 'import.closure' && d.severity.to_s == 'error' }).to be(true)

      pass_result = RHDL::Codegen.import_circt_mlir(
        closure_mlir,
        strict: true,
        top: 'top',
        extern_modules: ['child']
      )
      expect(pass_result.success?).to be(true)
      expect(pass_result.diagnostics.any? { |d| d.op == 'import.closure' }).to be(false)
    end

    it 'parses scf.if plus bit_reverse func.call as a mux expression' do
      mlir_with_scf = <<~MLIR
        hw.module @top(%a: i8, %sel: i1) -> (y: i8) {
          %x = scf.if %sel -> (i8) {
            %r = func.call @bit_reverse(%a) : (i8) -> i8
            scf.yield %r : i8
          } else {
            scf.yield %a : i8
          }
          hw.output %x : i8
        }

        func.func private @bit_reverse(%arg0: i8) -> i8 {
          return %arg0 : i8
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(mlir_with_scf, strict: true, top: 'top')
      expect(result.success?).to be(true)
      top_mod = result.modules.find { |m| m.name == 'top' }
      expect(top_mod).not_to be_nil
      expect(top_mod.assigns.length).to eq(1)
      expect(top_mod.assigns.first.expr).to be_a(RHDL::Codegen::CIRCT::IR::Mux)
    end

    it 'treats non-clocked llhd.process control flow as combinational assignments' do
      llhd_process_mlir = <<~MLIR
        hw.module @top(in %a: i1, in %sel: i1) -> (y: i1) {
          %t0 = llhd.constant_time <0ns, 0d, 1e>
          %false = hw.constant false
          %y_0 = llhd.sig %false : i1
          llhd.process {
            %a_0 = llhd.sig %a : i1
            %sel_0 = llhd.sig %sel : i1
            cf.br ^bb0
          ^bb0:
            %sel_v = llhd.prb %sel_0 : i1
            cf.cond_br %sel_v, ^bb1, ^bb2
          ^bb1:
            %a_v = llhd.prb %a_0 : i1
            llhd.drv %y_0, %a_v after %t0 : i1
            cf.br ^bb3
          ^bb2:
            llhd.drv %y_0, %false after %t0 : i1
            cf.br ^bb3
          ^bb3:
            llhd.halt
          }
          %y_v = llhd.prb %y_0 : i1
          hw.output %y_v : i1
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(llhd_process_mlir, strict: true, top: 'top')
      expect(result.success?).to be(true)
      top_mod = result.modules.find { |m| m.name == 'top' }
      expect(top_mod).not_to be_nil

      mux_assigns = top_mod.assigns.select { |assign| assign.expr.is_a?(RHDL::Codegen::CIRCT::IR::Mux) }
      expect(mux_assigns).not_to be_empty
      y0_assigns = top_mod.assigns.select { |assign| assign.target.to_s == 'y_0' }
      expect(y0_assigns.length).to eq(1)
    end

    it 'rewrites llhd.sig.array_get drive targets back to their parent array signal' do
      array_write_mlir = <<~MLIR
        hw.module @arrw(in %clk : i1, in %in_data : i8) -> (out_data : i8) {
          %false = hw.constant false : i1
          %true = hw.constant true : i1
          %c0_i8 = hw.constant 0 : i8
          %c1_i1 = hw.constant 1 : i1
          %t0 = llhd.constant_time <0s, 0d, 0e>
          %t1 = llhd.constant_time <0s, 1d, 0e>
          %clk_0 = llhd.sig name "clk" %false : i1
          %clk_probe = llhd.prb %clk_0 : i1
          %in_data_0 = llhd.sig name "in_data" %c0_i8 : i8
          %arr_init = hw.array_create %c0_i8, %c0_i8 : i8
          %arr = llhd.sig %arr_init : !hw.array<2xi8>
          llhd.process {
            cf.br ^bb1
          ^bb1:
            %pclk = llhd.prb %clk_0 : i1
            llhd.wait (%clk_probe : i1), ^bb2
          ^bb2:
            %nclk = llhd.prb %clk_0 : i1
            %inv = comb.xor bin %pclk, %true : i1
            %edge = comb.and bin %inv, %nclk : i1
            cf.cond_br %edge, ^bb3, ^bb1
          ^bb3:
            %slot = llhd.sig.array_get %arr[%c1_i1] : <!hw.array<2xi8>>
            %din = llhd.prb %in_data_0 : i8
            llhd.drv %slot, %din after %t0 : i8
            cf.br ^bb1
          }
          llhd.drv %clk_0, %clk after %t1 : i1
          llhd.drv %in_data_0, %in_data after %t1 : i8
          %arr_probe = llhd.prb %arr : !hw.array<2xi8>
          %outv = comb.extract %arr_probe from 8 : (i16) -> i8
          hw.output %outv : i8
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(array_write_mlir, strict: true, top: 'arrw')
      expect(result.success?).to be(true)
      mod = result.modules.find { |m| m.name == 'arrw' }
      expect(mod).not_to be_nil
      expect(mod.processes.length).to eq(1)

      targets = []
      walk = lambda do |stmts|
        Array(stmts).each do |stmt|
          case stmt
          when RHDL::Codegen::CIRCT::IR::SeqAssign
            targets << stmt.target.to_s
          when RHDL::Codegen::CIRCT::IR::If
            walk.call(stmt.then_statements)
            walk.call(stmt.else_statements)
          end
        end
      end
      walk.call(mod.processes.first.statements)

      expect(targets).to include('arr')
      expect(targets).not_to include('slot')
      expect(targets).not_to include('46')
      expect(targets).not_to include('63')
    end

    it 'treats llhd array signal reads as live signal slices (not initializer literals)' do
      array_read_mlir = <<~MLIR
        hw.module @arrread() -> (out_data : i8) {
          %c0_i8 = hw.constant 0 : i8
          %c1_i1 = hw.constant 1 : i1
          %arr_init = hw.array_create %c0_i8, %c0_i8 : i8
          %arr = llhd.sig %arr_init : !hw.array<2xi8>
          %slot = llhd.sig.array_get %arr[%c1_i1] : <!hw.array<2xi8>>
          %slot_v = llhd.prb %slot : i8
          hw.output %slot_v : i8
        }
      MLIR

      result = RHDL::Codegen.import_circt_mlir(array_read_mlir, strict: true, top: 'arrread')
      expect(result.success?).to be(true)

      mod = result.modules.find { |m| m.name == 'arrread' }
      expect(mod).not_to be_nil

      out_assign = mod.assigns.find { |a| a.target.to_s == 'out_data' }
      expect(out_assign).not_to be_nil
      expect(out_assign.expr).to be_a(RHDL::Codegen::CIRCT::IR::Slice)
      expect(out_assign.expr.base).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
      expect(out_assign.expr.base.name.to_s).to eq('arr')
    end
  end

  describe '.raise_circt_sources' do
    it 'raises nodes/MLIR into in-memory ruby sources' do
      result = RHDL::Codegen.raise_circt_sources(mlir, top: 'top')
      expect(result).to be_a(RHDL::Codegen::CIRCT::SourceResult)
      expect(result.success?).to be(true)
      expect(result.sources.keys).to include('top')
      expect(result.sources['top']).to include('class Top')
    end

    it 'lowers sequential if trees into mux assignments in raised DSL' do
      llhd_clocked = <<~MLIR
        hw.module @top(in %clk : i1, in %sel : i1) -> (y: i1) {
          %t0 = llhd.constant_time <0ns, 0d, 1e>
          %false = hw.constant false
          %y_r = llhd.sig %false : i1
          llhd.process {
            %clk_ref = llhd.sig %clk : i1
            cf.br ^bb0
          ^bb0:
            llhd.wait (%clk_ref : !llhd.sig<i1>), ^bb1
          ^bb1:
            %clk_v = llhd.prb %clk_ref : i1
            cf.cond_br %clk_v, ^bb2, ^bb0
          ^bb2:
            %sel_ref = llhd.sig %sel : i1
            %sel_v = llhd.prb %sel_ref : i1
            cf.cond_br %sel_v, ^bb3, ^bb4
          ^bb3:
            llhd.drv %y_r, %sel_v after %t0 : i1
            cf.br ^bb0
          ^bb4:
            llhd.drv %y_r, %false after %t0 : i1
            cf.br ^bb0
          }
          %y_v = llhd.prb %y_r : i1
          hw.output %y_v : i1
        }
      MLIR

      result = RHDL::Codegen.raise_circt_sources(llhd_clocked, top: 'top')
      expect(result.success?).to be(true)
      source = result.sources.fetch('top')
      expect(source).to include('sequential clock:')
      expect(source).to include('<= mux(')
      expect(source).not_to include("\n    if ")
    end
  end

  describe '.raise_circt' do
    it 'writes raised DSL files to disk' do
      Dir.mktmpdir('rhdl_codegen_api_spec') do |dir|
        result = RHDL::Codegen.raise_circt(mlir, out_dir: dir, top: 'top')
        expect(result.success?).to be(true)
        expect(result.files_written).to include(File.join(dir, 'top.rb'))
        expect(File.read(File.join(dir, 'top.rb'))).to include('behavior do')
      end
    end
  end

  describe '.raise_circt_components' do
    it 'loads raised DSL classes into a namespace module' do
      namespace = Module.new
      result = RHDL::Codegen.raise_circt_components(mlir, namespace: namespace, top: 'top')
      expect(result.success?).to be(true)
      expect(result.components.keys).to include('top')
      expect(result.components['top']).to be < RHDL::Sim::Component
      expect(namespace.const_defined?(:Top, false)).to be(true)
    end
  end

  describe '.verilog_from_mlir' do
    it 'exports MLIR to Verilog through external tooling wrapper' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |kwargs|
        File.write(kwargs[:out_path], "module top(input [7:0] a, input [7:0] b, output [7:0] y);\nendmodule\n")
        { success: true, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: '' }
      end

      verilog = RHDL::Codegen.verilog_from_mlir(mlir)
      expect(verilog).to include('module top')
      expect(verilog).to include('output [7:0] y')
    end

    it 'raises a descriptive error when tooling export fails' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog).and_return(
        { success: false, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: 'export failed' }
      )

      expect { RHDL::Codegen.verilog_from_mlir(mlir) }.to raise_error(RuntimeError, /CIRCT MLIR->Verilog conversion failed/)
    end
  end

  describe '.verilog_via_circt' do
    it 'exports a component via MLIR + external tooling path' do
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |kwargs|
        File.write(kwargs[:out_path], "module spec_fixtures_circt_tooling_adder;\nendmodule\n")
        { success: true, command: 'circt-translate --export-verilog input.mlir -o output.v', stdout: '', stderr: '' }
      end

      verilog = RHDL::Codegen.verilog_via_circt(RHDL::SpecFixtures::CIRCTToolingAdder)
      expect(verilog).to include('module spec_fixtures_circt_tooling_adder')
    end
  end
end
