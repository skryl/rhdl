# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/rhdl/cli/tasks/ao486_task'
require 'json'
require 'tmpdir'

RSpec.describe RHDL::CLI::Tasks::AO486Task do
  FakeDiag = Struct.new(:severity, :op, :message, :line, :column, keyword_init: true)

  FakeImportResult = Struct.new(
    :success,
    :files_written,
    :output_dir,
    :workspace,
    :diagnostics,
    :raise_diagnostics,
    :strategy_requested,
    :strategy_used,
    :fallback_used,
    :attempted_strategies,
    :stub_modules,
    keyword_init: true
  ) do
    def success?
      !!success
    end
  end

  class FakeImporter
    DEFAULT_SOURCE_PATH = '/tmp/source.v'
    DEFAULT_TOP = 'system'
    DEFAULT_IMPORT_STRATEGY = :stubbed

    class << self
      attr_accessor :last_init_kwargs, :next_result
    end

    def initialize(**kwargs)
      self.class.last_init_kwargs = kwargs
    end

    def run
      self.class.next_result
    end
  end

  class FakeHeadlessRunner
    class << self
      attr_accessor :last_init_kwargs, :instance
    end

    attr_reader :calls

    def initialize(**kwargs)
      self.class.last_init_kwargs = kwargs
      @calls = []
      self.class.instance = self
    end

    def load_bios
      @calls << :load_bios
    end

    def load_dos(**kwargs)
      @calls << [:load_dos, kwargs]
    end

    def dos_disk2_path
      '/fake/dos_disk2.img'
    end

    def hdd_path
      '/fake/hdd.img'
    end

    def load_hdd(**kwargs)
      @calls << [:load_hdd, kwargs]
    end

    def swap_dos(slot)
      @calls << [:swap_dos, slot]
    end

    def run
      @calls << :run
      :runner_state
    end
  end

  before do
    FakeImporter.last_init_kwargs = nil
    FakeImporter.next_result = nil
    FakeHeadlessRunner.last_init_kwargs = nil
    FakeHeadlessRunner.instance = nil
  end

  it 'runs default action through the AO486 headless runner surface' do
    task = described_class.new(
      action: :run,
      mode: :verilator,
      sim: :compile,
      bios: true,
      dos: true,
      debug: true,
      speed: 12_345,
      headless: true,
      cycles: 678,
      headless_runner_class: FakeHeadlessRunner
    )

    expect(task.run).to eq(:runner_state)
    expect(FakeHeadlessRunner.last_init_kwargs).to include(
      mode: :verilator,
      sim: :compile,
      debug: true,
      speed: 12_345,
      headless: true,
      cycles: 678
    )
    expect(FakeHeadlessRunner.instance.calls).to eq([
      :load_bios,
      [:load_dos, {}],
      [:load_dos, { path: '/fake/dos_disk2.img', slot: 1, activate: false }],
      [:load_hdd, { path: '/fake/hdd.img' }],
      :run
    ])
  end

  it 'does not load optional software artifacts unless requested' do
    task = described_class.new(
      action: :run,
      headless_runner_class: FakeHeadlessRunner
    )

    task.run
    expect(FakeHeadlessRunner.last_init_kwargs).to include(
      mode: described_class::DEFAULT_RUN_MODE,
      sim: described_class::DEFAULT_RUN_SIM,
      debug: false,
      headless: false
    )
    expect(FakeHeadlessRunner.instance.calls).to eq([:run])
  end

  it 'loads custom DOS disk1 and disk2 paths into separate runner slots for default run mode' do
    task = described_class.new(
      action: :run,
      dos_disk1: '/tmp/msdos4_disk1.img',
      dos_disk2: '/tmp/msdos4_disk2.img',
      headless_runner_class: FakeHeadlessRunner
    )

    task.run

    expect(FakeHeadlessRunner.instance.calls).to eq(
      [
        [:load_dos, { path: '/tmp/msdos4_disk1.img', slot: 0, activate: true }],
        [:load_dos, { path: '/tmp/msdos4_disk2.img', slot: 1, activate: false }],
        :run
      ]
    )
  end

  it 'runs import action and prints summary on success' do
    FakeImporter.next_result = FakeImportResult.new(
      success: true,
      files_written: %w[a.rb b.rb],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: ['warn line'],
      raise_diagnostics: [],
      strategy_requested: :tree,
      strategy_used: :tree,
      fallback_used: false,
      attempted_strategies: %i[tree],
      stub_modules: %w[foo bar]
    )

    task = described_class.new(
      action: :import,
      output_dir: '/tmp/out',
      importer_class: FakeImporter
    )

    expect { task.run }.to output(/AO486 import success=true files=2/).to_stdout
    expect(FakeImporter.last_init_kwargs[:source_path]).to eq(FakeImporter::DEFAULT_SOURCE_PATH)
    expect(FakeImporter.last_init_kwargs[:output_dir]).to eq('/tmp/out')
    expect(FakeImporter.last_init_kwargs[:top]).to eq(FakeImporter::DEFAULT_TOP)
    expect(FakeImporter.last_init_kwargs[:clean_output]).to eq(true)
    expect(FakeImporter.last_init_kwargs[:import_strategy]).to eq(:tree)
    expect(FakeImporter.last_init_kwargs[:fallback_to_stubbed]).to eq(false)
    expect(FakeImporter.last_init_kwargs[:maintain_directory_structure]).to eq(true)
    expect(FakeImporter.last_init_kwargs[:format_output]).to eq(false)
    expect(FakeImporter.last_init_kwargs[:strict]).to eq(false)
    expect(FakeImporter.last_init_kwargs[:progress]).to respond_to(:call)
  end

  it 'uses the CLI default import strategy instead of inheriting the importer default' do
    FakeImporter.next_result = FakeImportResult.new(
      success: true,
      files_written: [],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: [],
      raise_diagnostics: [],
      strategy_requested: :tree,
      strategy_used: :tree,
      fallback_used: false,
      attempted_strategies: %i[tree],
      stub_modules: []
    )

    task = described_class.new(
      action: :import,
      output_dir: '/tmp/out',
      importer_class: FakeImporter
    )

    task.run
    expect(FakeImporter::DEFAULT_IMPORT_STRATEGY).to eq(:stubbed)
    expect(FakeImporter.last_init_kwargs[:import_strategy]).to eq(described_class::DEFAULT_CLI_IMPORT_STRATEGY)
  end

  it 'passes clean_output=false through to importer' do
    FakeImporter.next_result = FakeImportResult.new(
      success: true,
      files_written: [],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: [],
      raise_diagnostics: [],
      strategy_requested: :tree,
      strategy_used: :tree,
      fallback_used: false,
      attempted_strategies: %i[tree],
      stub_modules: []
    )

    task = described_class.new(
      action: :import,
      output_dir: '/tmp/out',
      clean_output: false,
      importer_class: FakeImporter
    )

    expect { task.run }.to output(/AO486 import success=true files=0/).to_stdout
    expect(FakeImporter.last_init_kwargs[:clean_output]).to eq(false)
  end

  it 'requires output_dir for import action' do
    FakeImporter.next_result = FakeImportResult.new(success: true, files_written: [])

    task = described_class.new(
      action: :import,
      importer_class: FakeImporter
    )

    expect { task.run }.to raise_error(ArgumentError, /AO486 import requires output_dir/)
  end

  it 'writes import report JSON when report path is provided' do
    FakeImporter.next_result = FakeImportResult.new(
      success: true,
      files_written: ['/tmp/generated/system.rb'],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: ['warn line'],
      raise_diagnostics: [],
      strategy_requested: :stubbed,
      strategy_used: :stubbed,
      fallback_used: false,
      attempted_strategies: %i[stubbed],
      stub_modules: %w[foo bar]
    )

    Dir.mktmpdir('ao486_task_report_spec') do |dir|
      report_path = File.join(dir, 'import_report.json')
      task = described_class.new(
        action: :import,
        output_dir: '/tmp/out',
        report: report_path,
        importer_class: FakeImporter
      )

      expect { task.run }.to output(/AO486 import report=#{Regexp.escape(report_path)}/).to_stdout
      expect(File.exist?(report_path)).to be(true)

      report = JSON.parse(File.read(report_path))
      expect(report['success']).to eq(true)
      expect(report['strategy_used']).to eq('stubbed')
      expect(report['files_written']).to include('/tmp/generated/system.rb')
      expect(report['diagnostics']).to include('warn line')
    end
  end

  it 'adds missing-ops summary and strict gate status to import report and fails strict gate' do
    FakeImporter.next_result = FakeImportResult.new(
      success: true,
      files_written: ['/tmp/generated/system.rb'],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: ['warn line'],
      raise_diagnostics: [
        FakeDiag.new(severity: :warning, op: 'parser', message: 'Unsupported MLIR line, skipped: %a = hw.array_get %x[%i] : !hw.array<2xi8>, i1'),
        FakeDiag.new(severity: :warning, op: 'comb.icmp', message: "Unsupported comb.icmp predicate 'ceq', defaulting to eq"),
        FakeDiag.new(severity: :warning, op: 'raise.structure', message: 'Unsupported instance input connection for u.a')
      ],
      strategy_requested: :tree,
      strategy_used: :tree,
      fallback_used: false,
      attempted_strategies: %i[tree],
      stub_modules: %w[foo]
    )

    Dir.mktmpdir('ao486_task_report_summary_spec') do |dir|
      report_path = File.join(dir, 'import_report.json')
      task = described_class.new(
        action: :import,
        output_dir: '/tmp/out',
        report: report_path,
        importer_class: FakeImporter
      )
      expect { task.run }.to raise_error(RuntimeError, /AO486 import failed/)

      report = JSON.parse(File.read(report_path))
      expect(report['missing_ops_summary']['parser:hw.array_get']).to eq(1)
      expect(report['missing_ops_summary']['comb.icmp:predicate_fallback']).to eq(1)
      expect(report['missing_ops_summary']['raise.structure:unsupported_instance_input_connection']).to eq(1)
      expect(report['strict_gate']).to include('passed' => false)
      expect(report['strict_gate']['blocking_categories']).to include('parser:hw.array_get')
    end
  end

  it 'raises on import failure' do
    FakeImporter.next_result = FakeImportResult.new(
      success: false,
      files_written: [],
      output_dir: '/tmp/generated',
      workspace: '/tmp/ws',
      diagnostics: ['import failed'],
      raise_diagnostics: [],
      strategy_requested: :tree,
      strategy_used: :tree,
      fallback_used: true,
      attempted_strategies: %i[tree stubbed],
      stub_modules: []
    )

    task = described_class.new(
      action: :import,
      output_dir: '/tmp/out',
      importer_class: FakeImporter
    )

    expect { task.run }.to raise_error(RuntimeError, /AO486 import failed/)
  end

  it 'runs parity action with parity spec' do
    captured = nil
    task = described_class.new(
      action: :parity,
      spec_runner: lambda { |cmd|
        captured = cmd
        true
      }
    )

    task.run
    joined = captured.join(' ')
    expect(joined).to include('spec/examples/ao486/import/parity_spec.rb')
  end

  it 'runs verify action with importer/parity/import-path specs' do
    captured = nil
    task = described_class.new(
      action: :verify,
      spec_runner: lambda { |cmd|
        captured = cmd
        true
      }
    )

    task.run
    joined = captured.join(' ')
    expect(joined).to include('spec/examples/ao486/import/cpu_importer_spec.rb')
    expect(joined).to include('spec/examples/ao486/import/parity_spec.rb')
    expect(joined).to include('spec/rhdl/import/import_paths_spec.rb')
  end

  it 'raises for unknown action' do
    task = described_class.new(action: :unknown)
    expect { task.run }.to raise_error(ArgumentError, /Unknown AO486 action/)
  end
end
