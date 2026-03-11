# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'
require 'json'

RSpec.describe RHDL::CLI::Tasks::ImportTask do
  let(:tmp_dir) { Dir.mktmpdir('rhdl_import_task_spec') }

  def circt_verilog_import_command(verilog_path, extra_args: [])
    RHDL::Codegen::CIRCT::Tooling.circt_verilog_import_command_string(
      verilog_path: verilog_path,
      extra_args: extra_args
    )
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'imports verilog through external tooling without raise step' do
    input = File.join(tmp_dir, 'design.v')
    File.write(input, 'module design(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      raise_to_dsl: false
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
      {
        success: true,
        command: circt_verilog_import_command(input),
        stdout: '',
        stderr: ''
      }
    )

    expect { task.run }.to output(/Wrote CIRCT MLIR/).to_stdout
  end

  it 'passes the requested top through to circt-verilog imports' do
    input = File.join(tmp_dir, 'design.v')
    File.write(input, 'module design(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      top: 'design',
      raise_to_dsl: false
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
      {
        success: true,
        command: circt_verilog_import_command(input, extra_args: ['--top=design']),
        stdout: '',
        stderr: ''
      }
    )

    task.run

    expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:verilog_to_circt_mlir).with(
      hash_including(
        verilog_path: input,
        extra_args: array_including('--top=design')
      )
    )
  end

  it 'raises when a system import requires circt-verilog --top and none is available' do
    input = File.join(tmp_dir, 'design.v')
    File.write(input, 'module design(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      require_verilog_import_top: true,
      raise_to_dsl: false
    )

    expect(RHDL::Codegen::CIRCT::Tooling).not_to receive(:verilog_to_circt_mlir)
    expect { task.run }.to raise_error(ArgumentError, /requires --top to be passed to circt-verilog/)
  end

  it 'cleans imported core MLIR after circt-verilog import' do
    input = File.join(tmp_dir, 'design.v')
    core_mlir = File.join(tmp_dir, 'design.core.mlir')
    File.write(input, 'module design(input logic clk, input logic d, output logic q); always_ff @(posedge clk) q <= d; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      top: 'eReg_SavestateV__vhdl_c2a6c3cbd0d4',
      raise_to_dsl: false
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
      File.write(args.fetch(:out_path), <<~MLIR)
        hw.module private @eReg_SavestateV__vhdl_c2a6c3cbd0d4(in %clk : i1, in %BUS_Din : i64, in %BUS_Adr : i10, in %BUS_wren : i1, in %BUS_rst : i1, in %Din : i61, out BUS_Dout : i64, out Dout : i61) {
          %c0_i3 = hw.constant 0 : i3
          %0 = llhd.constant_time <0ns, 0d, 1e>
          %c9_i10 = hw.constant 9 : i10
          %c0_i61 = hw.constant 0 : i61
          %dout_buffer = llhd.sig %c0_i61 : i61
          %n324 = llhd.sig %c0_i61 : i61
          %1 = llhd.prb %dout_buffer : i61
          %2 = llhd.prb %n324 : i61
          llhd.drv %dout_buffer, %2 after %0 : i61
          llhd.drv %dout_buffer, %c0_i61 after %0 : i61
          %3 = comb.icmp eq %BUS_Adr, %c9_i10 : i10
          %4 = comb.and %BUS_wren, %3 : i1
          %5 = comb.extract %BUS_Din from 0 : (i64) -> i61
          %6 = comb.mux %4, %5, %1 : i61
          %7 = comb.mux %BUS_rst, %c0_i61, %6 : i61
          %8 = seq.to_clock %clk
          %n324_0 = seq.firreg %7 clock %8 : i61
          llhd.drv %n324, %n324_0 after %0 : i61
          llhd.drv %n324, %c0_i61 after %0 : i61
          %9 = comb.concat %c0_i3, %1 : i3, i61
          hw.output %9, %1 : i64, i61
        }
      MLIR
      {
        success: true,
        command: circt_verilog_import_command(input),
        stdout: '',
        stderr: ''
      }
    end

    expect { task.run }.to output(/Cleanup imported CIRCT core MLIR/).to_stdout
    expect(File.read(core_mlir)).not_to include('llhd.')
    expect(File.read(core_mlir)).to include('seq.compreg')
  end

  it 'skips imported core cleanup when circt-verilog already emitted pure core MLIR' do
    input = File.join(tmp_dir, 'simple.v')
    core_mlir = File.join(tmp_dir, 'simple.core.mlir')
    File.write(input, 'module simple(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      raise_to_dsl: false
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
      File.write(args.fetch(:out_path), <<~MLIR)
        hw.module @simple(%a: i1) -> (y: i1) {
          hw.output %a : i1
        }
      MLIR
      {
        success: true,
        command: circt_verilog_import_command(input),
        stdout: '',
        stderr: ''
      }
    end

    expect { task.run }.to output(/Skip imported CIRCT core cleanup \(no cleanup markers or stub modules requested\)/).to_stdout
    expect(File.read(core_mlir)).not_to include('llhd.')
  end

  it 'raises a descriptive error when verilog tooling fails' do
    input = File.join(tmp_dir, 'broken.v')
    File.write(input, 'module broken(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(
      mode: :verilog,
      input: input,
      out: tmp_dir,
      raise_to_dsl: false
    )

    allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
      {
        success: false,
        command: circt_verilog_import_command(input),
        stdout: '',
        stderr: 'parse failed'
      }
    )

    expect { task.run }.to raise_error(RuntimeError, /Verilog->CIRCT conversion failed/)
  end

  it 'raises CIRCT MLIR into DSL files in circt mode' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect { task.run }.to output(/Raised 1 DSL file/).to_stdout
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(true)
  end

  it 'prints import progress steps during circt raise flow' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect do
      task.run
    end.to output(
      /Import step: Parse\/import CIRCT MLIR.*Import step: Raise CIRCT -> RHDL files.*Import step: Skip formatting RHDL output directory.*Import step: Write import report/m
    ).to_stdout
  end

  it 'skips formatted raised output during import raise flow by default' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple'
    )

    expect(RHDL::Codegen).to receive(:raise_circt).with(
      anything,
      out_dir: tmp_dir,
      top: 'simple',
      strict: true,
      format: false
    ).and_call_original
    expect(RHDL::Codegen).not_to receive(:format_raised_dsl)

    task.run
  end

  it 'formats raised output when format_output is true' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple',
      format_output: true
    )

    expect(RHDL::Codegen).to receive(:format_raised_dsl).with(tmp_dir).and_call_original

    expect { task.run }.to output(/Import step: Format RHDL output directory/).to_stdout
  end

  it 'skips raise flow in circt mode when raise_to_dsl is false' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      raise_to_dsl: false
    )

    expect { task.run }.to output(/CIRCT MLIR ready/).to_stdout
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(false)
  end

  it 'writes an import report JSON for circt mode raise flow' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    report_file = File.join(tmp_dir, 'report.json')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'simple',
      report: report_file,
      strict: true
    )

    expect { task.run }.to output(/Wrote import report/).to_stdout
    expect(File.exist?(report_file)).to be(true)

    report = JSON.parse(File.read(report_file))
    expect(report.fetch('success')).to be(true)
    expect(report.fetch('strict')).to be(true)
    expect(report.fetch('module_count')).to eq(1)
    expect(report.fetch('modules').first.fetch('name')).to eq('simple')
    expect(report).not_to have_key('arc_remove_llhd')
  end

  it 'fails when top is missing but still writes partial output files' do
    mlir_file = File.join(tmp_dir, 'simple.mlir')
    File.write(mlir_file, <<~MLIR)
      hw.module @simple(%a: i1) -> (y: i1) {
        hw.output %a : i1
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'missing_top'
    )

    expect { task.run }.to raise_error(RuntimeError, /partial output written/)
    expect(File.exist?(File.join(tmp_dir, 'simple.rb'))).to be(true)
  end

  it 'enforces strict top-closure checks unless unresolved targets are allowlisted as extern' do
    mlir_file = File.join(tmp_dir, 'closure.mlir')
    failing_report = File.join(tmp_dir, 'closure_failing_report.json')
    passing_report = File.join(tmp_dir, 'closure_passing_report.json')
    File.write(mlir_file, <<~MLIR)
      hw.module @top(%a: i1) -> (y: i1) {
        %child_y = hw.instance "u_child" @child(a: %a: i1) -> (y: i1)
        hw.output %child_y : i1
      }
    MLIR

    failing_task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'top',
      strict: true,
      report: failing_report
    )
    expect { failing_task.run }.to raise_error(RuntimeError, /partial output written/)
    expect(File.exist?(failing_report)).to be(true)
    failing = JSON.parse(File.read(failing_report))
    expect(failing.fetch('success')).to be(false)
    expect(
      failing.fetch('import_diagnostics').any? do |diag|
        diag.fetch('op') == 'import.closure' && diag.fetch('message').include?('Unresolved instance target @child')
      end
    ).to be(true)

    passing_task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'top',
      strict: true,
      extern_modules: ['child'],
      report: passing_report
    )
    expect { passing_task.run }.not_to raise_error
    passing = JSON.parse(File.read(passing_report))
    expect(passing.fetch('success')).to be(true)
    expect(File.exist?(File.join(tmp_dir, 'top.rb'))).to be(true)
  end

  it 'stubs selected CIRCT modules before raise and records them in the report' do
    mlir_file = File.join(tmp_dir, 'stubbed.mlir')
    report_path = File.join(tmp_dir, 'stubbed_report.json')
    File.write(mlir_file, <<~MLIR)
      hw.module @child(in %reset_in : i1, in %din : i8, out reset_out : i1, out dout : i8) {
        %false = hw.constant false
        %c1_i8 = hw.constant 1 : i8
        hw.output %false, %c1_i8 : i1, i8
      }

      hw.module @top(in %reset_in : i1, in %din : i8, out reset_out : i1, out dout : i8) {
        %child_reset, %child_dout = hw.instance "u_child" @child(reset_in: %reset_in : i1, din: %din : i8) -> (reset_out: i1, dout: i8)
        hw.output %child_reset, %child_dout : i1, i8
      }
    MLIR

    task = described_class.new(
      mode: :circt,
      input: mlir_file,
      out: tmp_dir,
      top: 'top',
      strict: true,
      report: report_path,
      stub_modules: [
        {
          name: 'child',
          outputs: {
            'reset_out' => { signal: 'reset_in' },
            'dout' => 7
          }
        }
      ]
    )

    expect { task.run }.not_to raise_error
    report = JSON.parse(File.read(report_path))
    expect(report.fetch('success')).to be(true)
    expect(report.fetch('stub_modules')).to eq(['child'])
    child_entry = report.fetch('modules').find { |entry| entry.fetch('name') == 'child' }
    expect(child_entry.fetch('stubbed')).to be(true)
    expect(File.exist?(File.join(tmp_dir, 'child.rb'))).to be(true)
    expect(File.exist?(File.join(tmp_dir, 'top.rb'))).to be(true)
  end

  it 'raises for unsupported mode' do
    task = described_class.new(mode: :unknown, input: 'x', out: tmp_dir)
    expect { task.run }.to raise_error(ArgumentError, /Unknown import mode/)
  end

  it 'postprocesses generated VHDL Verilog for known positional-parameter modules' do
    out_path = File.join(tmp_dir, 'eReg_SavestateV.v')
    File.write(out_path, "module eReg_SavestateV (\n  input clk\n);\nendmodule\n")
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'eReg_SavestateV', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('module eReg_SavestateV')
    expect(text).to include('parameter P4 = 0')
  end

  it 'postprocesses generated VHDL Verilog by renaming reserved do token for GBse' do
    out_path = File.join(tmp_dir, 'GBse.v')
    File.write(out_path, "module GBse(input do, output do); assign do = do; endmodule\n")
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'GBse', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('do_o')
    expect(text).not_to match(/\bdo\b/)
  end

  it 'restores the missing DI_Reg alias in generated T80 Verilog' do
    out_path = File.join(tmp_dir, 'T80.v')
    File.write(out_path, <<~VERILOG)
      module T80(
        input [7:0] DI,
        output [15:0] A
      );
        wire [7:0] di_reg;
        assign A = {8'hFF, di_reg};
      endmodule
    VERILOG
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'T80', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('assign di_reg = DI;')
  end

  it 'restores the missing DI_Reg alias inside GBse embedded T80 modules' do
    out_path = File.join(tmp_dir, 'GBse.v')
    File.write(out_path, <<~VERILOG)
      module t80_specialized(
        input [7:0] di,
        output [15:0] a
      );
        wire [7:0] di_reg;
        assign a = {8'hFF, di_reg};
      endmodule

      module GBse(
        input clk,
        output done
      );
        assign done = clk;
      endmodule
    VERILOG
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(:postprocess_generated_vhdl_verilog!, entity: 'GBse', out_path: out_path)

    text = File.read(out_path)
    expect(text).to include('assign di_reg = di;')
  end

  it 'renames synthesized VHDL modules when a specialized module name is requested' do
    out_path = File.join(tmp_dir, 'dpram.v')
    File.write(out_path, "module dpram (\n  input clk\n);\nendmodule\n")
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(
      :postprocess_generated_vhdl_verilog!,
      entity: 'dpram',
      out_path: out_path,
      module_name: 'dpram__vhdl_deadbeef'
    )

    text = File.read(out_path)
    expect(text).to include('module dpram__vhdl_deadbeef')
    expect(text).not_to include('module dpram (')
  end

  it 'namespaces generated helper modules to avoid duplicate definitions across specialized files' do
    out_path = File.join(tmp_dir, 'dpram.v')
    File.write(out_path, <<~VERILOG)
      module altsyncram_hash(input clk);
      endmodule

      module dpram(input clk);
        altsyncram_hash ram(.clk(clk));
      endmodule
    VERILOG
    task = described_class.new(mode: :mixed, out: tmp_dir)

    task.send(
      :postprocess_generated_vhdl_verilog!,
      entity: 'dpram',
      out_path: out_path,
      module_name: 'dpram__vhdl_deadbeef'
    )

    text = File.read(out_path)
    expect(text).to include('module dpram__vhdl_deadbeef')
    expect(text).to include('module altsyncram_hash__')
    expect(text).to include('altsyncram_hash__')
    expect(text).not_to include("module altsyncram_hash\n")
  end

  it 'expands VHDL synth targets for parameterized Verilog callsites and rewrites them' do
    vhdl_path = File.join(tmp_dir, 'dpram.vhd')
    File.write(vhdl_path, <<~VHDL)
      entity dpram is
        generic (
          addr_width : integer := 8;
          data_width : integer := 8
        );
        port (
          clock_a : in bit
        );
      end dpram;
    VHDL

    verilog_path = File.join(tmp_dir, 'top.v')
    File.write(verilog_path, <<~VERILOG)
      module top;
        dpram #(13, 8) vram0 (.clock_a(clk));
        dpram #(7, 8) zpram (.clock_a(clk));
      endmodule
    VERILOG

    task = described_class.new(mode: :mixed, out: tmp_dir)
    expansion = task.send(
      :expand_vhdl_synth_targets_for_specializations,
      synth_targets: [{ entity: 'dpram', library: nil }],
      verilog_files: [{ path: verilog_path, language: 'verilog', library: nil }],
      vhdl_files: [{ path: vhdl_path, language: 'vhdl', library: nil }]
    )

    targets = expansion.fetch(:targets)
    expect(targets.length).to eq(2)
    expect(targets.map { |target| target.fetch(:module_name) }.uniq.length).to eq(2)
    expect(targets.map { |target| target.fetch(:extra_args) }).to contain_exactly(
      ['-gaddr_width=13', '-gdata_width=8'],
      ['-gaddr_width=7', '-gdata_width=8']
    )

    rewritten = task.send(
      :rewrite_vhdl_specialized_instantiations,
      File.read(verilog_path),
      rewrite_plan: expansion.fetch(:rewrite_plan)
    )
    expect(rewritten).not_to include('dpram #(')
    expect(rewritten.scan(/dpram__vhdl_[0-9a-f]{12}\s+vram0/).length).to eq(1)
    expect(rewritten.scan(/dpram__vhdl_[0-9a-f]{12}\s+zpram/).length).to eq(1)
  end

  it 'normalizes Verilog based literals for VHDL generic overrides' do
    task = described_class.new(mode: :mixed, out: tmp_dir)

    expect(task.send(:normalize_vhdl_generic_override_value, "64'h0000E00001FFFFF0")).to eq('X"0000E00001FFFFF0"')
    expect(task.send(:normalize_vhdl_generic_override_value, "8'd42")).to eq('42')
    expect(task.send(:normalize_vhdl_generic_override_value, '"BootROMs/cgb_boot.mif"')).to eq('BootROMs/cgb_boot.mif')
  end

  it 'uses circt-verilog as the fixed verilog import frontend' do
    input = File.join(tmp_dir, 'design.v')
    File.write(input, 'module design(input logic a, output logic y); assign y = a; endmodule')

    task = described_class.new(mode: :verilog, input: input, out: tmp_dir, raise_to_dsl: false, tool: 'custom-import-tool')

    expect(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).with(
      verilog_path: input,
      out_path: File.join(tmp_dir, 'design.core.mlir'),
      tool: 'circt-verilog',
      extra_args: []
    ).and_return(
      success: true,
      command: circt_verilog_import_command(input),
      stdout: '',
      stderr: ''
    )

    task.run
  end

  it 'overlays generated memory-backed VHDL modules onto canonical normalized Verilog and keeps raw firtool output' do
    normalized_path = File.join(tmp_dir, 'design.normalized.v')
    pure_root = File.join(tmp_dir, 'pure_verilog')
    generated_dir = File.join(pure_root, 'generated_vhdl')
    firtool_path = File.join(tmp_dir, 'design.firtool.v')
    FileUtils.mkdir_p(generated_dir)

    File.write(
      File.join(generated_dir, 'dpram__vhdl_deadbeef.v'),
      <<~VERILOG
        module altsyncram_deadbeef(
          input clock0,
          input [14:0] address_a,
          output [7:0] q_a
        );
          reg [7:0] q_a_reg;
          reg [7:0] mem[32767:0] ; // memory
          assign q_a = q_a_reg;
          always @(posedge clock0)
            q_a_reg <= mem[address_a];
        endmodule

        module dpram__vhdl_deadbeef(
          input clock0,
          input [14:0] address_a,
          output [7:0] q_a
        );
          altsyncram_deadbeef altsyncram_component (
            .clock0(clock0),
            .address_a(address_a),
            .q_a(q_a)
          );
        endmodule
      VERILOG
    )

    File.write(
      firtool_path,
      <<~VERILOG
        module altsyncram_deadbeef(
          input clock0,
          input [14:0] address_a,
          output [7:0] q_a
        );
          reg [262143:0] v3_262144;
          assign q_a = v3_262144[7:0];
        endmodule

        module dpram__vhdl_deadbeef(
          input clock0,
          input [14:0] address_a,
          output [7:0] q_a
        );
          altsyncram_deadbeef altsyncram_component (
            .clock0(clock0),
            .address_a(address_a),
            .q_a(q_a)
          );
        endmodule
      VERILOG
    )
    FileUtils.cp(firtool_path, normalized_path)

    task = described_class.new(mode: :mixed, out: tmp_dir)
    replaced = task.send(
      :overlay_generated_memory_modules!,
      normalized_verilog_path: normalized_path,
      pure_verilog_root: pure_root
    )

    expect(replaced).to contain_exactly('altsyncram_deadbeef', 'dpram__vhdl_deadbeef')
    expect(File.read(firtool_path)).to include('reg [262143:0] v3_262144;')
    expect(File.read(normalized_path)).to include('reg [7:0] mem[32767:0] ; // memory')
    expect(File.read(normalized_path)).not_to include('reg [262143:0] v3_262144;')
  end

  it 'also overlays non-memory generated VHDL modules into canonical normalized Verilog' do
    normalized_path = File.join(tmp_dir, 'design.normalized.v')
    pure_root = File.join(tmp_dir, 'pure_verilog')
    generated_dir = File.join(pure_root, 'generated_vhdl')
    FileUtils.mkdir_p(generated_dir)

    File.write(
      File.join(generated_dir, 'eReg_SavestateV__vhdl_deadbeef.v'),
      <<~VERILOG
        module eReg_SavestateV__vhdl_deadbeef(
          input clk,
          output [7:0] Dout
        );
          assign Dout = 8'hAA;
        endmodule
      VERILOG
    )

    File.write(
      normalized_path,
      <<~VERILOG
        module eReg_SavestateV__vhdl_deadbeef(
          input clk,
          output [7:0] Dout
        );
          assign Dout = 8'h55;
        endmodule
      VERILOG
    )

    task = described_class.new(mode: :mixed, out: tmp_dir)
    replaced = task.send(
      :overlay_generated_memory_modules!,
      normalized_verilog_path: normalized_path,
      pure_verilog_root: pure_root
    )

    expect(replaced).to include('eReg_SavestateV__vhdl_deadbeef')
    expect(File.read(normalized_path)).to include("assign Dout = 8'hAA;")
    expect(File.read(normalized_path)).not_to include("assign Dout = 8'h55;")
  end

  it 'materializes VHDL defaulted memory control ports in staged Verilog instances' do
    task = described_class.new(mode: :mixed, out: tmp_dir)
    source = <<~VERILOG
      module top;
        dpram__vhdl_deadbeef vram0(
          .clock_a(clk_cpu),
          .address_a(vram_addr),
          .wren_a(vram_wren),
          .data_a(vram_di),
          .q_a(vram_do)
        );

        dpram_dif__vhdl_deadbeef boot_rom(
          .clock(clk_sys),
          .address_a(boot_addr),
          .q_a(boot_q),
          .address_b(boot_wr_addr),
          .wren_b(ioctl_wr && boot_download),
          .data_b(ioctl_dout)
        );
      endmodule
    VERILOG

    rewritten = task.send(:materialize_vhdl_default_memory_ports, source)

    expect(rewritten).to include(".clken_a(1'b1)")
    expect(rewritten).to include(".clken_b(1'b1)")
    expect(rewritten).to include(".enable_a(1'b1)")
    expect(rewritten).to include(".cs_a(1'b1)")
    expect(rewritten).to include(".enable_b(1'b1)")
    expect(rewritten).to include(".cs_b(1'b1)")
  end

  it 'builds a byte-addressed runtime overlay for generated dpram_dif modules' do
    task = described_class.new(mode: :mixed, out: tmp_dir)
    rewritten = task.send(:runtime_dpram_dif_module_block, 'dpram_dif__vhdl_test')

    expect(rewritten).to include('module dpram_dif__vhdl_test')
    expect(rewritten).to include('wire enable_a_active = (enable_a !== 1\'b0);')
    expect(rewritten).to include('wire cs_b_active = (cs_b !== 1\'b0);')
    expect(rewritten).to include('wire wren_b_active = (wren_b === 1\'b1);')
    expect(rewritten).to include('wire [10:0] word_addr_a = address_a[11:1];')
    expect(rewritten).to include('wire [7:0]  read_byte_a = byte_sel_a ? word_data_a[15:8] : word_data_a[7:0];')
    expect(rewritten).to include('if (wren_b_active & cs_b_active)')
  end

  it 'overlays staged generated dpram_dif modules with the byte-addressed runtime model after import' do
    task = described_class.new(mode: :mixed, out: tmp_dir)
    pure_root = File.join(tmp_dir, '.mixed_import', 'pure_verilog')
    generated_dir = File.join(pure_root, 'generated_vhdl')
    FileUtils.mkdir_p(generated_dir)
    out_path = File.join(generated_dir, 'dpram_dif__vhdl_deadbeef.v')
    File.write(out_path, <<~VERILOG)
      module altsyncram_hash(input clk);
      endmodule

      module dpram_dif__vhdl_deadbeef(
        input clock,
        input [11:0] address_a,
        output [7:0] q_a
      );
        altsyncram_hash ram(.clk(clock));
      endmodule
    VERILOG

    replaced = task.send(:overlay_runtime_generated_vhdl_modules!, pure_verilog_root: pure_root)
    text = File.read(out_path)

    expect(replaced).to eq(['dpram_dif__vhdl_deadbeef'])
    expect(text).to include('module dpram_dif__vhdl_deadbeef')
    expect(text).to include('wire enable_b_active = (enable_b !== 1\'b0);')
    expect(text).to include('wire [10:0] word_addr_a = address_a[11:1];')
    expect(text).to include('wire [7:0]  read_byte_a = byte_sel_a ? word_data_a[15:8] : word_data_a[7:0];')
    expect(text).not_to include('altsyncram_hash')
  end

  describe 'mixed mode' do
    it 'requires either --manifest or a top source file --input' do
      task = described_class.new(
        mode: :mixed,
        out: tmp_dir,
        raise_to_dsl: false
      )

      expect { task.run }.to raise_error(ArgumentError, /Mixed mode requires --manifest or --input/)
    end

    it 'requires --input to be a file path when manifest is omitted' do
      task = described_class.new(
        mode: :mixed,
        input: tmp_dir,
        out: tmp_dir,
        raise_to_dsl: false
      )

      expect { task.run }.to raise_error(ArgumentError, /Mixed mode autoscan requires --input to be a file path/)
    end

    it 'imports mixed sources through staging without raise step' do
      manifest_path = File.join(tmp_dir, 'mixed_import.yml')
      File.write(
        manifest_path,
        <<~YAML
          version: 1
          top:
            name: mixed_top
            language: verilog
            file: top.sv
          files:
            - path: top.sv
              language: verilog
            - path: leaf.vhd
              language: vhdl
        YAML
      )

      staged_verilog = File.join(tmp_dir, 'staged.v')
      task = described_class.new(
        mode: :mixed,
        manifest: manifest_path,
        out: tmp_dir,
        raise_to_dsl: false
      )

      allow(task).to receive(:build_mixed_import_staging).and_return(
        {
          staged_verilog_path: staged_verilog,
          pure_verilog_root: File.join(tmp_dir, '.mixed_import', 'pure_verilog'),
          pure_verilog_entry_path: staged_verilog,
          provenance: { source_files: [] }
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
        {
          success: true,
          command: circt_verilog_import_command(staged_verilog),
          stdout: '',
          stderr: ''
        }
      )

      expect { task.run }.to output(/Wrote CIRCT MLIR/).to_stdout
      expect(task).to have_received(:build_mixed_import_staging)
    end

    it 'passes the resolved mixed top through to circt-verilog imports' do
      manifest_path = File.join(tmp_dir, 'mixed_import.yml')
      File.write(
        manifest_path,
        <<~YAML
          version: 1
          top:
            name: mixed_top
            language: verilog
            file: top.sv
          files:
            - path: top.sv
              language: verilog
        YAML
      )

      staged_verilog = File.join(tmp_dir, 'staged.v')
      task = described_class.new(
        mode: :mixed,
        manifest: manifest_path,
        out: tmp_dir,
        raise_to_dsl: false
      )

      allow(task).to receive(:build_mixed_import_staging).and_return(
        {
          staged_verilog_path: staged_verilog,
          pure_verilog_root: File.join(tmp_dir, '.mixed_import', 'pure_verilog'),
          pure_verilog_entry_path: staged_verilog,
          top_name: 'mixed_top',
          tool_args: [],
          provenance: { source_files: [] }
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir).and_return(
        {
          success: true,
          command: circt_verilog_import_command(staged_verilog, extra_args: ['--top=mixed_top']),
          stdout: '',
          stderr: ''
        }
      )

      task.run

      expect(RHDL::Codegen::CIRCT::Tooling).to have_received(:verilog_to_circt_mlir).with(
        hash_including(
          verilog_path: staged_verilog,
          extra_args: array_including('--top=mixed_top')
        )
      )
    end

    it 'writes mixed import provenance into report when raise flow is enabled' do
      manifest_path = File.join(tmp_dir, 'mixed_import.yml')
      report_path = File.join(tmp_dir, 'mixed_report.json')
      File.write(
        manifest_path,
        <<~YAML
          version: 1
          top:
            name: mixed_top
            language: verilog
            file: top.sv
          files:
            - path: top.sv
              language: verilog
        YAML
      )

      staged_verilog = File.join(tmp_dir, 'staged.v')
      File.write(staged_verilog, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")

      task = described_class.new(
        mode: :mixed,
        manifest: manifest_path,
        out: tmp_dir,
        strict: true,
        report: report_path
      )

      allow(task).to receive(:build_mixed_import_staging).and_return(
        {
          staged_verilog_path: staged_verilog,
          pure_verilog_root: File.join(tmp_dir, '.mixed_import', 'pure_verilog'),
          pure_verilog_entry_path: File.join(tmp_dir, '.mixed_import', 'pure_verilog_entry.v'),
          top_name: 'mixed_top',
          tool_args: [],
          provenance: {
            top_name: 'mixed_top',
            top_language: 'verilog',
            top_file: staged_verilog,
            source_files: [{ path: staged_verilog, language: 'verilog' }],
            pure_verilog_files: [
              {
                path: staged_verilog,
                language: 'verilog',
                generated: false,
                origin_kind: 'source_verilog',
                original_source_path: staged_verilog
              }
            ]
          }
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
        File.write(
          args.fetch(:out_path),
          <<~MLIR
            hw.module @mixed_top(%a: i1) -> (y: i1) {
              hw.output %a : i1
            }
          MLIR
        )
        {
          success: true,
          command: circt_verilog_import_command(staged_verilog),
          stdout: '',
          stderr: ''
        }
      end
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |**args|
        FileUtils.mkdir_p(File.dirname(args.fetch(:out_path)))
        File.write(args.fetch(:out_path), "module mixed_top(input a, output y); assign y = a; endmodule\n")
        {
          success: true,
          command: 'firtool mixed_top.core.mlir --verilog',
          stdout: '',
          stderr: ''
        }
      end

      expect { task.run }.to output(/Wrote import report/).to_stdout
      expect(File.exist?(File.join(tmp_dir, 'mixed_top.rb'))).to be(true)
      report = JSON.parse(File.read(report_path))
      expect(report.fetch('success')).to be(true)
      expect(report.fetch('top')).to eq('mixed_top')
      mixed = report.fetch('mixed_import')
      artifacts = report.fetch('artifacts')
      mixed_top_module = report.fetch('modules').find { |entry| entry.fetch('name') == 'mixed_top' }
      expect(mixed.fetch('top_name')).to eq('mixed_top')
      expect(mixed.fetch('source_files').first.fetch('language')).to eq('verilog')
      expect(mixed.fetch('pure_verilog_files').first).to include(
        'path',
        'language',
        'generated',
        'origin_kind'
      )
      expect(mixed.fetch('pure_verilog_root')).to eq(File.join(tmp_dir, '.mixed_import', 'pure_verilog'))
      expect(mixed.fetch('pure_verilog_entry_path')).to eq(File.join(tmp_dir, '.mixed_import', 'pure_verilog_entry.v'))
      expect(mixed.fetch('core_mlir_path')).to eq(File.join(tmp_dir, 'mixed_top.core.mlir'))
      expect(mixed.fetch('runtime_json_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.runtime.json'))
      expect(mixed.fetch('normalized_verilog_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.normalized.v'))
      expect(mixed.fetch('firtool_verilog_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.firtool.v'))
      expect(report.fetch('raised_files')).to include(File.join(tmp_dir, 'mixed_top.rb'))
      expect(mixed_top_module).to include(
        'verilog_module_name' => 'mixed_top',
        'ruby_class_name' => 'MixedTop',
        'raised_rhdl_path' => File.join(tmp_dir, 'mixed_top.rb'),
        'staged_verilog_path' => staged_verilog,
        'staged_verilog_module_name' => 'mixed_top',
        'origin_kind' => 'source_verilog',
        'source_kind' => 'verilog',
        'original_source_path' => staged_verilog
      )
      expect(mixed_top_module.fetch('emitted_dsl_features')).to be_a(Array)
      expect(mixed_top_module.fetch('emitted_base_class')).to be_a(String)
      expect(mixed_top_module).not_to have_key('vhdl_synth')
      expect(artifacts.fetch('pure_verilog_root')).to eq(mixed.fetch('pure_verilog_root'))
      expect(artifacts.fetch('pure_verilog_entry_path')).to eq(mixed.fetch('pure_verilog_entry_path'))
      expect(artifacts.fetch('core_mlir_path')).to eq(mixed.fetch('core_mlir_path'))
      expect(artifacts.fetch('runtime_json_path')).to eq(mixed.fetch('runtime_json_path'))
      expect(artifacts.fetch('normalized_verilog_path')).to eq(mixed.fetch('normalized_verilog_path'))
      expect(artifacts.fetch('firtool_verilog_path')).to eq(mixed.fetch('firtool_verilog_path'))
    end

    it 'runs mixed autoscan end-to-end through raise flow and writes report provenance' do
      rtl_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(rtl_dir)
      top_path = File.join(rtl_dir, 'mixed_top.sv')
      leaf_vhdl = File.join(rtl_dir, 'leaf.vhd')
      report_path = File.join(tmp_dir, 'mixed_autoscan_report.json')
      File.write(top_path, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf_vhdl, <<~VHDL)
        entity leaf is
        end entity;
        architecture rtl of leaf is
        begin
        end architecture;
      VHDL

      task = described_class.new(
        mode: :mixed,
        input: top_path,
        out: tmp_dir,
        top: 'mixed_top',
        strict: true,
        report: report_path
      )

      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_analyze).and_return(
        {
          success: true,
          command: 'ghdl -a --std=08 leaf.vhd',
          stdout: '',
          stderr: ''
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_synth_to_verilog) do |**args|
        FileUtils.mkdir_p(File.dirname(args.fetch(:out_path)))
        File.write(args.fetch(:out_path), "module leaf; endmodule\n")
        {
          success: true,
          command: 'ghdl --synth --out=verilog leaf',
          stdout: '',
          stderr: ''
        }
      end
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
        File.write(
          args.fetch(:out_path),
          <<~MLIR
            hw.module @leaf() {
              hw.output
            }

            hw.module @mixed_top(%a: i1) -> (y: i1) {
              hw.output %a : i1
            }
          MLIR
        )
        {
          success: true,
          command: circt_verilog_import_command(args.fetch(:verilog_path)),
          stdout: '',
          stderr: ''
        }
      end
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |**args|
        FileUtils.mkdir_p(File.dirname(args.fetch(:out_path)))
        File.write(args.fetch(:out_path), "module mixed_top(input a, output y); assign y = a; endmodule\n")
        {
          success: true,
          command: 'firtool mixed_top.core.mlir --verilog',
          stdout: '',
          stderr: ''
        }
      end

      expect { task.run }.to output(/Wrote import report/).to_stdout
      expect(File.exist?(File.join(tmp_dir, 'mixed_top.rb'))).to be(true)
      expect(File.exist?(report_path)).to be(true)

      report = JSON.parse(File.read(report_path))
      expect(report.fetch('success')).to be(true)
      expect(report.fetch('top')).to eq('mixed_top')
      mixed = report.fetch('mixed_import')
      artifacts = report.fetch('artifacts')
      leaf_module = report.fetch('modules').find { |entry| entry.fetch('name') == 'leaf' }
      expect(mixed.fetch('autoscan_root')).to eq(File.expand_path(rtl_dir))
      expect(mixed.fetch('top_file')).to eq(File.join(tmp_dir, '.mixed_import', 'pure_verilog', 'mixed_top.sv'))
      expect(mixed.fetch('top_language')).to eq('verilog')
      expect(mixed.fetch('vhdl_analysis_commands')).not_to be_empty
      expect(mixed.fetch('vhdl_synth_outputs')).not_to be_empty
      expect(mixed.fetch('vhdl_synth_outputs').first).to include(
        'source_path' => File.expand_path(leaf_vhdl),
        'standard' => '08',
        'workdir' => File.join(tmp_dir, '.mixed_import', 'ghdl_work')
      )
      expect(mixed.fetch('pure_verilog_files').first).to include('origin_kind')
      expect(mixed.fetch('pure_verilog_root')).to eq(File.join(tmp_dir, '.mixed_import', 'pure_verilog'))
      expect(mixed.fetch('pure_verilog_entry_path')).to eq(File.join(tmp_dir, '.mixed_import', 'pure_verilog_entry.v'))
      expect(mixed.fetch('core_mlir_path')).to eq(File.join(tmp_dir, 'mixed_top.core.mlir'))
      expect(mixed.fetch('runtime_json_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.runtime.json'))
      expect(mixed.fetch('normalized_verilog_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.normalized.v'))
      expect(mixed.fetch('firtool_verilog_path')).to eq(File.join(tmp_dir, '.mixed_import', 'mixed_top.firtool.v'))
      expect(report.fetch('raised_files')).to include(File.join(tmp_dir, 'mixed_top.rb'), File.join(tmp_dir, 'leaf.rb'))
      expect(leaf_module).to include(
        'verilog_module_name' => 'leaf',
        'ruby_class_name' => 'Leaf',
        'raised_rhdl_path' => File.join(tmp_dir, 'leaf.rb'),
        'staged_verilog_path' => File.join(tmp_dir, '.mixed_import', 'pure_verilog', 'generated_vhdl', 'leaf.v'),
        'staged_verilog_module_name' => 'leaf',
        'origin_kind' => 'source_vhdl_generated',
        'source_kind' => 'generated_vhdl',
        'original_source_path' => File.expand_path(leaf_vhdl),
        'vhdl_synth' => include(
          'entity' => 'leaf',
          'module_name' => 'leaf',
          'standard' => '08',
          'workdir' => File.join(tmp_dir, '.mixed_import', 'ghdl_work'),
          'source_path' => File.expand_path(leaf_vhdl)
        )
      )
      expect(artifacts.fetch('core_mlir_path')).to eq(mixed.fetch('core_mlir_path'))
      expect(artifacts.fetch('runtime_json_path')).to eq(mixed.fetch('runtime_json_path'))
      expect(artifacts.fetch('firtool_verilog_path')).to eq(mixed.fetch('firtool_verilog_path'))
    end

    it 'skips mixed runtime JSON emission when emit_runtime_json is false' do
      staged_verilog = File.join(tmp_dir, 'mixed_top.sv')
      report_path = File.join(tmp_dir, 'mixed_report.json')
      File.write(staged_verilog, "module mixed_top(input a, output y); assign y = a; endmodule\n")

      task = described_class.new(
        mode: :mixed,
        input: staged_verilog,
        out: tmp_dir,
        top: 'mixed_top',
        strict: true,
        report: report_path,
        emit_runtime_json: false
      )

      allow(task).to receive(:discover_rtl_files).and_return([staged_verilog])
      allow(task).to receive(:discover_source_files) do |input, no_autoscan:, source_paths:|
        [described_class::MixedImportSource.new(path: input, language: :verilog, generated: false, origin: :source)]
      end
      allow(task).to receive(:build_mixed_pure_verilog_entry!) do |sources:, pure_verilog_root:, top_name:|
        FileUtils.mkdir_p(pure_verilog_root)
        copied = File.join(pure_verilog_root, File.basename(staged_verilog))
        FileUtils.cp(staged_verilog, copied)
        entry_path = File.join(tmp_dir, '.mixed_import', 'pure_verilog_entry.v')
        File.write(entry_path, "module mixed_top(input a, output y); assign y = a; endmodule\n")
        {
          top_file: copied,
          top_language: :verilog,
          entry_path: entry_path,
          copied_sources: [
            {
              source: described_class::MixedImportSource.new(
                path: staged_verilog,
                language: :verilog,
                generated: false,
                origin: :source
              ),
              copied_path: copied
            }
          ]
        }
      end
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:verilog_to_circt_mlir) do |**args|
        File.write(
          args.fetch(:out_path),
          <<~MLIR
            hw.module @mixed_top(%a: i1) -> (y: i1) {
              hw.output %a : i1
            }
          MLIR
        )
        {
          success: true,
          command: circt_verilog_import_command(staged_verilog),
          stdout: '',
          stderr: ''
        }
      end
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:circt_mlir_to_verilog) do |**args|
        FileUtils.mkdir_p(File.dirname(args.fetch(:out_path)))
        File.write(args.fetch(:out_path), "module mixed_top(input a, output y); assign y = a; endmodule\n")
        {
          success: true,
          command: 'firtool mixed_top.core.mlir --verilog',
          stdout: '',
          stderr: ''
        }
      end

      expect { task.run }.to output(/Wrote import report/).to_stdout

      report = JSON.parse(File.read(report_path))
      mixed = report.fetch('mixed_import')
      artifacts = report.fetch('artifacts')
      runtime_json_path = File.join(tmp_dir, '.mixed_import', 'mixed_top.runtime.json')

      expect(mixed).not_to have_key('runtime_json_path')
      expect(artifacts).not_to have_key('runtime_json_path')
      expect(File.exist?(runtime_json_path)).to be(false)
    end

    it 'fails fast when VHDL synth fails during mixed import run' do
      rtl_dir = File.join(tmp_dir, 'rtl')
      FileUtils.mkdir_p(rtl_dir)
      top_path = File.join(rtl_dir, 'mixed_top.sv')
      leaf_vhdl = File.join(rtl_dir, 'leaf.vhd')
      File.write(top_path, "module mixed_top(input logic a, output logic y); assign y = a; endmodule\n")
      File.write(leaf_vhdl, "entity leaf is end entity;\narchitecture rtl of leaf is begin end architecture;\n")

      task = described_class.new(
        mode: :mixed,
        input: top_path,
        out: tmp_dir,
        strict: true
      )

      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_analyze).and_return(
        {
          success: true,
          command: 'ghdl -a --std=08 leaf.vhd',
          stdout: '',
          stderr: ''
        }
      )
      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:ghdl_synth_to_verilog).and_return(
        {
          success: false,
          command: 'ghdl --synth --out=verilog leaf',
          stdout: '',
          stderr: 'synth failed'
        }
      )
      expect(RHDL::Codegen::CIRCT::Tooling).not_to receive(:verilog_to_circt_mlir)

      expect { task.run }.to raise_error(RuntimeError, /VHDL synth->Verilog failed/)
    end
  end
end
