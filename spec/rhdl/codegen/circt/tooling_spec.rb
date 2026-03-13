# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Codegen::CIRCT::Tooling do
  let(:simple_dff_llhd) do
    <<~MLIR
      module {
        hw.module @dff(in %clk : i1, in %d : i1, out q : i1) {
          %0 = llhd.constant_time <0ns, 1d, 0e>
          %1 = llhd.constant_time <0ns, 0d, 1e>
          %true = hw.constant true
          %false = hw.constant false
          %clk_0 = llhd.sig name "clk" %false : i1
          %2 = llhd.prb %clk_0 : i1
          %d_1 = llhd.sig name "d" %false : i1
          %q = llhd.sig %false : i1
          llhd.process {
            %4 = llhd.prb %clk_0 : i1
            cf.br ^bb1(%4, %false, %false : i1, i1, i1)
          ^bb1(%5: i1, %6: i1, %7: i1):
            llhd.drv %q, %6 after %0 if %7 : i1
            llhd.wait (%2 : i1), ^bb2(%5 : i1)
          ^bb2(%8: i1):
            %9 = llhd.prb %clk_0 : i1
            %10 = llhd.prb %d_1 : i1
            %11 = comb.xor bin %8, %true : i1
            %12 = comb.and bin %11, %2 : i1
            cf.cond_br %12, ^bb1(%9, %10, %true : i1, i1, i1), ^bb1(%9, %false, %false : i1, i1, i1)
          }
          llhd.drv %clk_0, %clk after %1 : i1
          llhd.drv %d_1, %d after %1 : i1
          %3 = llhd.prb %q : i1
          hw.output %3 : i1
        }
      }
    MLIR
  end

  describe '.circt_verilog_import_command' do
    it 'builds the canonical circt-verilog import command with memory detection by default' do
      expect(described_class.circt_verilog_import_command(verilog_path: 'in.v')).to eq(
        ['circt-verilog', '--detect-memories', '--ir-hw', 'in.v']
      )
      expect(described_class.circt_verilog_import_command_string(verilog_path: 'in.v')).to eq(
        'circt-verilog --detect-memories --ir-hw in.v'
      )
    end

    it 'preserves an explicit circt-verilog IR mode override' do
      expect(
        described_class.circt_verilog_import_command(
          verilog_path: 'in.v',
          extra_args: ['--ir-moore']
        )
      ).to eq(['circt-verilog', '--detect-memories', '--ir-moore', 'in.v'])
    end

    it 'does not duplicate detect-memories when explicitly requested' do
      expect(
        described_class.circt_verilog_import_command(
          verilog_path: 'in.v',
          extra_args: ['--detect-memories', '--ir-moore']
        )
      ).to eq(['circt-verilog', '--detect-memories', '--ir-moore', 'in.v'])
    end
  end

  describe '.arcilator_command' do
    it 'adds the shared split-functions threshold by default' do
      expect(
        described_class.arcilator_command(
          mlir_path: 'in.mlir',
          state_file: 'state.json',
          out_path: 'out.ll'
        )
      ).to eq(
        ['arcilator', 'in.mlir', '--split-funcs-threshold=100', '--state-file=state.json', '-o', 'out.ll']
      )
    end

    it 'preserves an explicit split-functions threshold override' do
      expect(
        described_class.arcilator_command(
          mlir_path: 'in.mlir',
          state_file: 'state.json',
          out_path: 'out.ll',
          extra_args: ['--observe-registers', '--split-funcs-threshold=250']
        )
      ).to eq(
        ['arcilator', 'in.mlir', '--observe-registers', '--split-funcs-threshold=250', '--state-file=state.json', '-o', 'out.ll']
      )
    end
  end

  describe '.verilog_to_circt_mlir' do
    it 'invokes circt-verilog import command with expected args and writes stdout to the target file' do
      Dir.mktmpdir('tooling_spec_import') do |dir|
        status = instance_double(Process::Status, success?: true)
        out_path = File.join(dir, 'out.mlir')
        expected_cmd = described_class.circt_verilog_import_command(verilog_path: 'in.v')
        expect(Open3).to receive(:capture3).with(*expected_cmd)
                                             .and_return(["hw.module @in() {\n  hw.output\n}\n", '', status])

        result = described_class.verilog_to_circt_mlir(verilog_path: 'in.v', out_path: out_path)
        expect(result[:success]).to be(true)
        expect(result[:command]).to eq(described_class.circt_verilog_import_command_string(verilog_path: 'in.v'))
        expect(result[:output_path]).to eq(out_path)
        expect(File.read(out_path)).to include('hw.module @in')
      end
    end

    it 'preserves an explicit circt-verilog IR mode override' do
      Dir.mktmpdir('tooling_spec_import_override') do |dir|
        status = instance_double(Process::Status, success?: true)
        out_path = File.join(dir, 'out.mlir')
        expected_cmd = described_class.circt_verilog_import_command(
          verilog_path: 'in.v',
          extra_args: ['--ir-moore']
        )
        expect(Open3).to receive(:capture3).with(*expected_cmd)
                                             .and_return(["module {\n}\n", '', status])

        result = described_class.verilog_to_circt_mlir(
          verilog_path: 'in.v',
          out_path: out_path,
          extra_args: ['--ir-moore']
        )
        expect(result[:success]).to be(true)
        expect(result[:command]).to eq(
          described_class.circt_verilog_import_command_string(
            verilog_path: 'in.v',
            extra_args: ['--ir-moore']
          )
        )
      end
    end

    it 'returns a descriptive failure for unsupported verilog import tools' do
      expect(Open3).not_to receive(:capture3)

      result = described_class.verilog_to_circt_mlir(
        verilog_path: 'in.v',
        out_path: 'out.mlir',
        tool: 'firtool'
      )
      expect(result[:success]).to be(false)
      expect(result[:stderr]).to include('requires circt-verilog')
      expect(result[:tool]).to eq('firtool')
    end
  end

  describe '.circt_mlir_to_verilog' do
    it 'invokes firtool export command with expected args by default' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'firtool',
        'in.mlir',
        '--verilog',
        '-o',
        'out.v',
        "--lowering-options=#{described_class::DEFAULT_FIRTOOL_LOWERING_OPTIONS}",
        '--format=mlir'
      ).and_return(['', '', status])

      result = described_class.circt_mlir_to_verilog(mlir_path: 'in.mlir', out_path: 'out.v')
      expect(result[:success]).to be(true)
      expect(result[:tool]).to eq('firtool')
      expect(result[:command]).to match(/--format\\?=mlir/)
      expect(result[:command]).to include('--verilog')
      expect(result[:command]).to match(/--lowering-options\\?=/)
      expect(result[:output_path]).to eq('out.v')
    end

    it 'invokes the canonical export tool when explicitly requested' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        described_class::DEFAULT_VERILOG_EXPORT_TOOL,
        'in.mlir',
        '--verilog',
        '-o',
        'out.v',
        "--lowering-options=#{described_class::DEFAULT_FIRTOOL_LOWERING_OPTIONS}",
        '--format=mlir',
        '--split-verilog'
      ).and_return(['', '', status])

      result = described_class.circt_mlir_to_verilog(
        mlir_path: 'in.mlir',
        out_path: 'out.v',
        tool: described_class::DEFAULT_VERILOG_EXPORT_TOOL,
        extra_args: ['--split-verilog']
      )
      expect(result[:success]).to be(true)
      expect(result[:command]).to include('--verilog')
      expect(result[:command]).to include('--split-verilog')
    end

    it 'returns a failure result when tool is missing' do
      allow(Open3).to receive(:capture3).and_raise(Errno::ENOENT)

      result = described_class.circt_mlir_to_verilog(mlir_path: 'in.mlir', out_path: 'out.v')
      expect(result[:success]).to be(false)
      expect(result[:stderr]).to include('Tool not found')
    end
  end

  describe '.ghdl_analyze' do
    it 'invokes ghdl analyze command with expected args' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'ghdl', '-a', '--std=08', '--workdir=/tmp/ghdl_work', '--work=work', '-P/tmp/ghdl_work', 'leaf.vhd'
      ).and_return(['', '', status])

      result = described_class.ghdl_analyze(
        vhdl_path: 'leaf.vhd',
        workdir: '/tmp/ghdl_work'
      )
      expect(result[:success]).to be(true)
      expect(result[:command]).to include('ghdl')
      expect(result[:command]).to match(/--workdir\\?=\/tmp\/ghdl_work/)
    end
  end

  describe '.ghdl_synth_to_verilog' do
    it 'invokes ghdl synth command and writes stdout to output file' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'ghdl', '--synth', '--std=08', '--workdir=/tmp/ghdl_work', '--work=work', '-P/tmp/ghdl_work', '--out=verilog', 'leaf'
      ).and_return(["module leaf; endmodule\n", '', status])

      Dir.mktmpdir('tooling_spec_ghdl') do |dir|
        out = File.join(dir, 'leaf.v')
        result = described_class.ghdl_synth_to_verilog(
          entity: 'leaf',
          out_path: out,
          workdir: '/tmp/ghdl_work'
        )
        expect(result[:success]).to be(true)
        expect(File.exist?(out)).to be(true)
        expect(File.read(out)).to include('module leaf')
      end
    end
  end

  describe '.prepare_arc_mlir_from_verilog' do
    it 'builds arc-ready MLIR from a simple Verilog register without LLHD time ops' do
      skip 'circt-verilog or circt-opt not available' unless HdlToolchain.which('circt-verilog') && HdlToolchain.which('circt-opt')

      Dir.mktmpdir('tooling_prepare_arc') do |dir|
        verilog_path = File.join(dir, 'dff.v')
        File.write(verilog_path, <<~VERILOG)
          module dff(input clk, input d, output reg q);
            always @(posedge clk) q <= d;
          endmodule
        VERILOG

        result = described_class.prepare_arc_mlir_from_verilog(
          verilog_path: verilog_path,
          work_dir: File.join(dir, 'work')
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s
        expect(result.fetch(:unsupported_modules)).to be_empty
        expect(result.fetch(:transformed_modules)).to include('dff')
        hwseq = File.read(result.fetch(:hwseq_mlir_path))
        expect(hwseq).not_to include('llhd.')
        expect(hwseq).to include('seq.firreg').or include('seq.compreg')
        expect(File.read(result.fetch(:arc_mlir_path))).to include('arc.')
      end
    end
  end

  describe '.prepare_arc_mlir_from_circt_mlir' do
    it 'builds shared hwseq and arc artifacts from canonical LLHD MLIR' do
      skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

      Dir.mktmpdir('tooling_prepare_arc_circt') do |dir|
        mlir_path = File.join(dir, 'dff.normalized.llhd.mlir')
        File.write(mlir_path, simple_dff_llhd)

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: File.join(dir, 'work'),
          base_name: 'dff'
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s
        expect(result.fetch(:unsupported_modules)).to be_empty
        expect(result.fetch(:transformed_modules)).to eq(['dff'])
        expect(result.dig(:flatten, :success)).to be(true), result.dig(:flatten, :stderr).to_s
        expect(File.basename(result.fetch(:hwseq_mlir_path))).to eq('dff.hwseq.mlir')
        expect(File.basename(result.fetch(:flattened_hwseq_mlir_path))).to eq('dff.flattened.hwseq.mlir')
        expect(File.read(result.fetch(:hwseq_mlir_path))).not_to include('llhd.')
        expect(File.read(result.fetch(:flattened_hwseq_mlir_path))).not_to include('llhd.')
        expect(File.exist?(result.fetch(:arc_mlir_path))).to be(true)
        expect(File.read(result.fetch(:arc_mlir_path))).not_to include('llhd.')
      end
    end

    it 'supports syntax-only ARC cleanup without the importer cleanup round-trip' do
      skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

      Dir.mktmpdir('tooling_prepare_arc_circt_syntax_only') do |dir|
        mlir_path = File.join(dir, 'dff.normalized.llhd.mlir')
        File.write(mlir_path, simple_dff_llhd)

        allow(RHDL::Codegen::CIRCT::ImportCleanup).to receive(:cleanup_imported_core_mlir).and_call_original

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: File.join(dir, 'work'),
          base_name: 'dff',
          cleanup_mode: :syntax_only
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s
        expect(RHDL::Codegen::CIRCT::ImportCleanup).not_to have_received(:cleanup_imported_core_mlir)
        expect(File.read(result.fetch(:hwseq_mlir_path))).not_to include('llhd.')
      end
    end

    it 'applies requested module stubs before ARC preparation' do
      skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

      Dir.mktmpdir('tooling_prepare_arc_circt_stubbed') do |dir|
        mlir_path = File.join(dir, 'stubbed.mlir')
        File.write(mlir_path, <<~MLIR)
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

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: File.join(dir, 'work'),
          base_name: 'stubbed',
          top: 'top',
          strict: true,
          stub_modules: [
            {
              name: 'child',
              outputs: {
                'reset_out' => { signal: 'reset_in' },
                'dout' => 9
              }
            }
          ]
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s
        hwseq_result = RHDL::Codegen.import_circt_mlir(
          File.read(result.fetch(:hwseq_mlir_path)),
          strict: true,
          top: 'top',
          resolve_forward_refs: true
        )
        expect(hwseq_result.success?).to be(true), hwseq_result.diagnostics.map(&:message).join("\n")
        child = hwseq_result.modules.find { |mod| mod.name.to_s == 'child' }
        expect(child).not_to be_nil
        expect(child.assigns.find { |assign| assign.target.to_s == 'reset_out' }&.expr).to be_a(RHDL::Codegen::CIRCT::IR::Signal)
        expect(child.assigns.find { |assign| assign.target.to_s == 'reset_out' }&.expr&.name).to eq('reset_in')
        expect(child.assigns.find { |assign| assign.target.to_s == 'dout' }&.expr).to be_a(RHDL::Codegen::CIRCT::IR::Literal)
        expect(child.assigns.find { |assign| assign.target.to_s == 'dout' }&.expr&.value).to eq(9)
      end
    end

    it 'runs a cleanup opt pass on flattened hwseq before ARC conversion' do
      status = instance_double(Process::Status, success?: true)

      Dir.mktmpdir('tooling_prepare_arc_circt_cleanup') do |dir|
        mlir_path = File.join(dir, 'top.mlir')
        work_dir = File.join(dir, 'work')
        File.write(mlir_path, <<~MLIR)
          hw.module @top(out out : i1) {
            %false = hw.constant false
            hw.output %false : i1
          }
        MLIR

        hwseq_path = File.join(work_dir, 'top.hwseq.mlir')
        flattened_path = File.join(work_dir, 'top.flattened.hwseq.mlir')
        cleaned_path = File.join(work_dir, 'top.flattened.cleaned.hwseq.mlir')
        arc_path = File.join(work_dir, 'top.arc.mlir')

        expect(Open3).to receive(:capture3).with(
          'circt-opt',
          hwseq_path,
          "--pass-pipeline=#{described_class::DEFAULT_ARC_FLATTEN_PIPELINE}",
          '-o',
          flattened_path
        ).ordered.and_return(['', '', status])

        expect(Open3).to receive(:capture3).with(
          'circt-opt',
          flattened_path,
          '--canonicalize',
          '--cse',
          '-o',
          cleaned_path
        ).ordered.and_return(['', '', status])

        expect(Open3).to receive(:capture3).with(
          'circt-opt',
          flattened_path,
          '--convert-to-arcs',
          '-o',
          arc_path
        ).ordered.and_return(['', '', status])

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: work_dir,
          base_name: 'top'
        )

        expect(result[:success]).to be(true)
        expect(result.dig(:flatten_cleanup, :success)).to be(true)
      end
    end

    it 'emits ARC MLIR that arcilator can lower on a simple design' do
      skip 'circt-opt or arcilator not available' unless HdlToolchain.which('circt-opt') && HdlToolchain.which('arcilator')

      Dir.mktmpdir('tooling_prepare_arc_circt_arcilator') do |dir|
        mlir_path = File.join(dir, 'dff.normalized.llhd.mlir')
        File.write(mlir_path, simple_dff_llhd)

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: File.join(dir, 'work'),
          base_name: 'dff'
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s

        ll_path = File.join(dir, 'work', 'dff.ll')
        state_path = File.join(dir, 'work', 'dff.state.json')
        command = ['arcilator', result.fetch(:arc_mlir_path), '--state-file=' + state_path, '-o', ll_path]
        expect(system(*command)).to be(true), "arcilator failed for #{result.fetch(:arc_mlir_path)}"
        expect(File.exist?(ll_path)).to be(true)
        expect(File.exist?(state_path)).to be(true)
      end
    end

    it 'emits hwseq MLIR that firtool accepts for Verilog export' do
      skip 'circt-opt or firtool not available' unless HdlToolchain.which('circt-opt') && HdlToolchain.which('firtool')

      Dir.mktmpdir('tooling_prepare_arc_circt_firtool') do |dir|
        mlir_path = File.join(dir, 'dff.normalized.llhd.mlir')
        File.write(mlir_path, simple_dff_llhd)

        result = described_class.prepare_arc_mlir_from_circt_mlir(
          mlir_path: mlir_path,
          work_dir: File.join(dir, 'work'),
          base_name: 'dff'
        )

        expect(result[:success]).to be(true), result.dig(:arc, :stderr).to_s

        verilog_path = File.join(dir, 'dff.v')
        export = described_class.circt_mlir_to_verilog(
          mlir_path: result.fetch(:hwseq_mlir_path),
          out_path: verilog_path
        )

        expect(export[:success]).to be(true), export[:stderr].to_s
        expect(File.read(verilog_path)).to include('module dff')
      end
    end
  end

  describe '.preferred_arcilator_input_mlir_path' do
    it 'prefers flattened hwseq output when available' do
      Dir.mktmpdir('tooling_arcilator_input') do |dir|
        flattened = File.join(dir, 'design.flattened.hwseq.mlir')
        hwseq = File.join(dir, 'design.hwseq.mlir')
        arc = File.join(dir, 'design.arc.mlir')
        [flattened, hwseq, arc].each { |path| File.write(path, "module {}\n") }

        expect(
          described_class.preferred_arcilator_input_mlir_path(
            flattened_hwseq_mlir_path: flattened,
            hwseq_mlir_path: hwseq,
            arc_mlir_path: arc
          )
        ).to eq(flattened)
      end
    end

    it 'falls back to the first existing artifact when flattened hwseq is unavailable' do
      Dir.mktmpdir('tooling_arcilator_input_fallback') do |dir|
        hwseq = File.join(dir, 'design.hwseq.mlir')
        arc = File.join(dir, 'design.arc.mlir')
        [hwseq, arc].each { |path| File.write(path, "module {}\n") }

        expect(
          described_class.preferred_arcilator_input_mlir_path(
            flattened_hwseq_mlir_path: File.join(dir, 'missing.flattened.hwseq.mlir'),
            hwseq_mlir_path: hwseq,
            arc_mlir_path: arc
          )
        ).to eq(hwseq)
      end
    end
  end
end
