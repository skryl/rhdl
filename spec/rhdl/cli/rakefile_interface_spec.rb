# frozen_string_literal: true

require 'spec_helper'
require 'rake'
require 'rhdl/cli'

RSpec.describe 'Rakefile interface' do
  # Load the Rakefile once for all tests
  before(:all) do
    @rake = Rake::Application.new
    Rake.application = @rake
    # Silence rake output during tests
    @rake.options.silent = true
    # Load the Rakefile
    load File.expand_path('../../../Rakefile', __dir__)
  end

  after(:all) do
    Rake.application.clear
  end

  # Reset task invocation state before each test
  before(:each) do
    Rake.application.tasks.each(&:reenable)
  end

  # Helper to capture task instantiation
  def expect_task_class(task_class, expected_options = {})
    task_instance = instance_double(task_class)
    allow(task_instance).to receive(:run)

    expect(task_class).to receive(:new) do |actual_options|
      expected_options.each do |key, value|
        expect(actual_options[key]).to eq(value),
          "Expected #{task_class}.new to receive #{key}: #{value.inspect}, got #{actual_options[key].inspect}"
      end
      task_instance
    end

    task_instance
  end

  describe 'deps tasks' do
    it 'deps:install invokes DepsTask with no options' do
      expect_task_class(RHDL::CLI::Tasks::DepsTask, {})
      Rake::Task['deps:install'].invoke
    end

    it 'deps:check invokes DepsTask with check: true' do
      expect_task_class(RHDL::CLI::Tasks::DepsTask, check: true)
      Rake::Task['deps:check'].invoke
    end
  end

  describe 'bench tasks' do
    it 'bench:gates invokes BenchmarkTask with type: :gates' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :gates)
      Rake::Task['bench:gates'].invoke
    end

    it 'bench:ir invokes BenchmarkTask with type: :ir and cycles' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:ir)
        expect(opts[:cycles]).to be_a(Integer)
        task_instance
      end

      Rake::Task['bench:ir'].invoke
    end
  end

  describe 'benchmark tasks' do
    it 'benchmark:timing invokes BenchmarkTask with type: :timing' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :timing)
      Rake::Task['benchmark:timing'].invoke
    end

    it 'benchmark:quick invokes BenchmarkTask with type: :quick' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :quick)
      Rake::Task['benchmark:quick'].invoke
    end
  end

  describe 'spec:bench tasks' do
    it 'spec:bench:all invokes BenchmarkTask with type: :tests for all specs' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/')
        expect(opts[:count]).to eq(20)
        task_instance
      end

      Rake::Task['spec:bench:all'].invoke
    end

    it 'spec:bench:lib invokes BenchmarkTask with lib pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/rhdl/')
        task_instance
      end

      Rake::Task['spec:bench:lib'].invoke
    end

    it 'spec:bench:hdl invokes BenchmarkTask with hdl pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/rhdl/hdl/')
        task_instance
      end

      Rake::Task['spec:bench:hdl'].invoke
    end

    it 'spec:bench:mos6502 invokes BenchmarkTask with mos6502 pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/examples/mos6502/')
        task_instance
      end

      Rake::Task['spec:bench:mos6502'].invoke
    end

    it 'spec:bench:apple2 invokes BenchmarkTask with apple2 pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/examples/apple2/')
        task_instance
      end

      Rake::Task['spec:bench:apple2'].invoke
    end
  end

  describe 'native tasks' do
    it 'native:build invokes NativeTask with build: true' do
      expect_task_class(RHDL::CLI::Tasks::NativeTask, build: true)
      Rake::Task['native:build'].invoke
    end

    it 'native:clean invokes NativeTask with clean: true' do
      expect_task_class(RHDL::CLI::Tasks::NativeTask, clean: true)
      Rake::Task['native:clean'].invoke
    end

    it 'native:check invokes NativeTask with check: true' do
      expect_task_class(RHDL::CLI::Tasks::NativeTask, check: true)
      Rake::Task['native:check'].invoke
    end
  end

  describe 'task class loading' do
    it 'loads all task classes via load_cli_tasks' do
      # Verify the CLI module and all task classes are loadable
      require 'rhdl/cli'

      expect(defined?(RHDL::CLI::Tasks::Apple2Task)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::BenchmarkTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::DepsTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::DiagramTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::DiskConvertTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::ExportTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::GatesTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::GenerateTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::MOS6502Task)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::NativeTask)).to eq('constant')
      expect(defined?(RHDL::CLI::Tasks::TuiTask)).to eq('constant')
    end

    it 'all task classes inherit from Task base class' do
      require 'rhdl/cli'

      task_classes = [
        RHDL::CLI::Tasks::Apple2Task,
        RHDL::CLI::Tasks::BenchmarkTask,
        RHDL::CLI::Tasks::DepsTask,
        RHDL::CLI::Tasks::DiagramTask,
        RHDL::CLI::Tasks::DiskConvertTask,
        RHDL::CLI::Tasks::ExportTask,
        RHDL::CLI::Tasks::GatesTask,
        RHDL::CLI::Tasks::GenerateTask,
        RHDL::CLI::Tasks::MOS6502Task,
        RHDL::CLI::Tasks::NativeTask,
        RHDL::CLI::Tasks::TuiTask
      ]

      task_classes.each do |klass|
        expect(klass.ancestors).to include(RHDL::CLI::Task),
          "Expected #{klass} to inherit from RHDL::CLI::Task"
      end
    end

    it 'all task classes implement run method' do
      require 'rhdl/cli'

      task_classes = [
        RHDL::CLI::Tasks::Apple2Task,
        RHDL::CLI::Tasks::BenchmarkTask,
        RHDL::CLI::Tasks::DepsTask,
        RHDL::CLI::Tasks::DiagramTask,
        RHDL::CLI::Tasks::DiskConvertTask,
        RHDL::CLI::Tasks::ExportTask,
        RHDL::CLI::Tasks::GatesTask,
        RHDL::CLI::Tasks::GenerateTask,
        RHDL::CLI::Tasks::MOS6502Task,
        RHDL::CLI::Tasks::NativeTask,
        RHDL::CLI::Tasks::TuiTask
      ]

      task_classes.each do |klass|
        expect(klass.instance_methods(false)).to include(:run),
          "Expected #{klass} to define its own run method"
      end
    end

    it 'all task classes implement dry_run_describe method' do
      require 'rhdl/cli'

      task_classes = [
        RHDL::CLI::Tasks::Apple2Task,
        RHDL::CLI::Tasks::BenchmarkTask,
        RHDL::CLI::Tasks::DepsTask,
        RHDL::CLI::Tasks::DiagramTask,
        RHDL::CLI::Tasks::DiskConvertTask,
        RHDL::CLI::Tasks::ExportTask,
        RHDL::CLI::Tasks::GatesTask,
        RHDL::CLI::Tasks::GenerateTask,
        RHDL::CLI::Tasks::MOS6502Task,
        RHDL::CLI::Tasks::NativeTask,
        RHDL::CLI::Tasks::TuiTask
      ]

      task_classes.each do |klass|
        expect(klass.instance_methods(false)).to include(:dry_run_describe),
          "Expected #{klass} to define dry_run_describe method"
      end
    end
  end

  describe 'dry_run functionality' do
    it 'Task base class provides dry_run? method' do
      task = RHDL::CLI::Task.new(dry_run: true)
      expect(task.dry_run?).to be true

      task = RHDL::CLI::Task.new
      expect(task.dry_run?).to be false
    end

    it 'Task base class provides would method for recording actions' do
      task = RHDL::CLI::Task.new(dry_run: true)
      task.would(:test_action, foo: 'bar')
      expect(task.dry_run_output).to eq([{ action: :test_action, foo: 'bar' }])
    end

    it 'dry_run mode returns action descriptions instead of executing' do
      # Test a few representative task classes
      deps_task = RHDL::CLI::Tasks::DepsTask.new(dry_run: true)
      result = deps_task.run
      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:install_deps)

      benchmark_task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :gates, dry_run: true)
      result = benchmark_task.run
      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:benchmark_gates)

      native_task = RHDL::CLI::Tasks::NativeTask.new(build: true, dry_run: true)
      result = native_task.run
      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:cargo_build)
    end
  end

  describe 'SPEC_PATHS constant' do
    it 'defines correct spec paths' do
      expect(SPEC_PATHS[:all]).to eq('spec/')
      expect(SPEC_PATHS[:lib]).to eq('spec/rhdl/')
      expect(SPEC_PATHS[:hdl]).to eq('spec/rhdl/hdl/')
      expect(SPEC_PATHS[:mos6502]).to eq('spec/examples/mos6502/')
      expect(SPEC_PATHS[:apple2]).to eq('spec/examples/apple2/')
    end
  end

  describe 'rake task existence' do
    # Verify all custom rake tasks exist
    %w[
      spec spec:lib spec:hdl spec:mos6502 spec:apple2
      spec:bench spec:bench:all spec:bench:lib spec:bench:hdl spec:bench:mos6502 spec:bench:apple2
      pspec pspec:lib pspec:hdl pspec:mos6502 pspec:apple2 pspec:n pspec:prepare pspec:balanced
      deps deps:install deps:check
      bench bench:gates bench:ir
      benchmark benchmark:timing benchmark:quick
      native native:build native:clean native:check
      setup setup:binstubs
    ].each do |task_name|
      it "defines #{task_name} task" do
        expect(Rake::Task.task_defined?(task_name)).to be(true),
          "Expected rake task '#{task_name}' to be defined"
      end
    end
  end
end
