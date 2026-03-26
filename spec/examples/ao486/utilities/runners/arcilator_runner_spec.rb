# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

require_relative '../../../../../examples/ao486/utilities/runners/arcilator_runner'

RSpec.describe RHDL::Examples::AO486::ArcilatorRunner do
  it 'uses flattening plus direct ARC conversion when building imported parity runtimes from cleaned MLIR' do
    status = instance_double(Process::Status, success?: true)

    Dir.mktmpdir('ao486_arcilator_runner_spec') do |dir|
      arc_dir = File.join(File.expand_path(dir), 'arc')
      arc_mlir_path = File.join(arc_dir, '07.cpu_parity.arc.mlir')
      runner = described_class.new(headless: true)

      allow(RHDL::Codegen::CIRCT::Tooling).to receive(:arcilator_command).and_return(['true'])
      expect(RHDL::Codegen::CIRCT::Tooling).to receive(:prepare_arc_mlir_from_circt_mlir).with(
        mlir_path: File.join(File.expand_path(dir), 'cpu_parity.mlir'),
        work_dir: arc_dir,
        base_name: 'cpu_parity',
        top: 'ao486',
        include: %i[flatten to_arc]
      ).and_return(
        success: true,
        arc: { stderr: '' },
        arc_mlir_path: arc_mlir_path
      )
      allow(Open3).to receive(:capture3).with('true').and_return(['', '', status])
      allow(runner).to receive(:parse_state_file!).and_return(module_name: 'ao486', state_size: 1, offsets: {})
      allow(runner).to receive(:write_arcilator_trace_harness)
      allow(runner).to receive(:prepare_harness_executable!)

      runner.send(:build_imported_parity!, "hw.module @ao486() { hw.output }\n", work_dir: dir)
    end
  end
end
