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

  describe '.verilog_to_circt_mlir' do
    it 'invokes circt-verilog import command with expected args and writes stdout to the target file' do
      Dir.mktmpdir('tooling_spec_import') do |dir|
        status = instance_double(Process::Status, success?: true)
        out_path = File.join(dir, 'out.mlir')
        expect(Open3).to receive(:capture3).with(
          'circt-verilog', '--ir-hw', 'in.v'
        ).and_return(["hw.module @in() {\n  hw.output\n}\n", '', status])

        result = described_class.verilog_to_circt_mlir(verilog_path: 'in.v', out_path: out_path)
        expect(result[:success]).to be(true)
        expect(result[:command]).to eq('circt-verilog --ir-hw in.v')
        expect(result[:output_path]).to eq(out_path)
        expect(File.read(out_path)).to include('hw.module @in')
      end
    end

    it 'preserves an explicit circt-verilog IR mode override' do
      Dir.mktmpdir('tooling_spec_import_override') do |dir|
        status = instance_double(Process::Status, success?: true)
        out_path = File.join(dir, 'out.mlir')
        expect(Open3).to receive(:capture3).with(
          'circt-verilog', '--ir-moore', 'in.v'
        ).and_return(["module {\n}\n", '', status])

        result = described_class.verilog_to_circt_mlir(
          verilog_path: 'in.v',
          out_path: out_path,
          extra_args: ['--ir-moore']
        )
        expect(result[:success]).to be(true)
        expect(result[:command]).to eq('circt-verilog --ir-moore in.v')
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

    it 'invokes circt-translate export command when explicitly requested' do
      status = instance_double(Process::Status, success?: true)
      expect(Open3).to receive(:capture3).with(
        'circt-translate', '--export-verilog', 'in.mlir', '-o', 'out.v'
      ).and_return(['', '', status])

      result = described_class.circt_mlir_to_verilog(
        mlir_path: 'in.mlir',
        out_path: 'out.v',
        tool: 'circt-translate'
      )
      expect(result[:success]).to be(true)
      expect(result[:command]).to include('--export-verilog')
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
        expect(File.basename(result.fetch(:hwseq_mlir_path))).to eq('dff.hwseq.mlir')
        expect(File.read(result.fetch(:hwseq_mlir_path))).not_to include('llhd.')
        expect(File.exist?(result.fetch(:arc_mlir_path))).to be(true)
        expect(File.read(result.fetch(:arc_mlir_path))).not_to include('llhd.')
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
end
