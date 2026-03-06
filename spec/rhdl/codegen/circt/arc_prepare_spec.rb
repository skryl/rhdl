# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'open3'

RSpec.describe RHDL::Codegen::CIRCT::ArcPrepare do
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
          ^bb1(%5: i1, %6: i1, %7: i1):  // 3 preds: ^bb0, ^bb2, ^bb2
            llhd.drv %q, %6 after %0 if %7 : i1
            llhd.wait (%2 : i1), ^bb2(%5 : i1)
          ^bb2(%8: i1):  // pred: ^bb1
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

  it 'lowers a minimal normalized LLHD edge-register module into hw/seq' do
    result = described_class.transform_normalized_llhd(simple_dff_llhd)

    expect(result.fetch(:success)).to be(true)
    expect(result.fetch(:unsupported_modules)).to be_empty
    expect(result.fetch(:transformed_modules)).to eq(['dff'])
    expect(result.fetch(:output_text)).to include('seq.to_clock')
    expect(result.fetch(:output_text)).to include('seq.compreg')
    expect(result.fetch(:output_text)).to include('hw.output')
    expect(result.fetch(:output_text)).not_to include('llhd.')
  end

  it 'reports unsupported LLHD module shapes without rewriting them' do
    input = <<~MLIR
      module {
        hw.module @bad(in %a : i1, out y : i1) {
          %0 = llhd.constant_time <0ns, 0d, 1e>
          %sig = llhd.sig %a : i1
          llhd.combinational {
            llhd.yield
          }
          %1 = llhd.prb %sig : i1
          hw.output %1 : i1
        }
      }
    MLIR

    result = described_class.transform_normalized_llhd(input)

    expect(result.fetch(:success)).to be(false)
    expect(result.fetch(:unsupported_modules)).to include(
      'module' => 'bad',
      'reason' => 'unsupported normalized LLHD process shape'
    )
    expect(result.fetch(:output_text)).to include('llhd.combinational')
  end

  it 'emits hw/seq that convert-to-arcs accepts for the minimal fixture' do
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')

    result = described_class.transform_normalized_llhd(simple_dff_llhd)
    expect(result.fetch(:success)).to be(true)

    Dir.mktmpdir('arc_prepare_spec') do |dir|
      input_path = File.join(dir, 'dff.hwseq.mlir')
      output_path = File.join(dir, 'dff.arc.mlir')
      File.write(input_path, result.fetch(:output_text))

      stdout, stderr, status = Open3.capture3('circt-opt', '--convert-to-arcs', input_path, '-o', output_path)
      expect(status.success?).to be(true), "#{stdout}\n#{stderr}"
      expect(File.read(output_path)).to include('arc.')
      expect(File.read(output_path)).not_to include('llhd.')
    end
  end
end
