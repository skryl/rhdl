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
    it 'bench:native invokes BenchmarkTask with type: :gates' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :gates)
      Rake::Task['bench:native'].invoke
    end

    it 'bench:native :ir scope invokes BenchmarkTask with type: :ir and cycles' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:ir)
        expect(opts[:cycles]).to be_a(Integer)
        task_instance
      end

      Rake::Task['bench:native'].invoke('ir')
    end

    it 'bench:web scope riscv invokes BenchmarkTask with type: :web_riscv and cycles' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:web_riscv)
        expect(opts[:cycles]).to be_a(Integer)
        task_instance
      end

      Rake::Task['bench:web'].invoke('riscv')
    end
  end

  describe 'benchmark tasks' do
    it 'spec:bench:timing invokes BenchmarkTask with type: :timing' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :timing)
      Rake::Task['spec:bench:timing'].invoke
    end

    it 'spec:bench:quick invokes BenchmarkTask with type: :quick' do
      expect_task_class(RHDL::CLI::Tasks::BenchmarkTask, type: :quick)
      Rake::Task['spec:bench:quick'].invoke
    end
  end

  describe 'spec:bench tasks' do
    it 'spec:bench scope all invokes BenchmarkTask with type: :tests for all specs' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/')
        expect(opts[:count]).to eq(20)
        task_instance
      end

      Rake::Task['spec:bench'].invoke('all')
    end

    it 'spec:bench scope lib invokes BenchmarkTask with lib pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/rhdl/')
        task_instance
      end

      Rake::Task['spec:bench'].invoke('lib')
    end

    it 'spec:bench scope hdl invokes BenchmarkTask with hdl pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/rhdl/hdl/')
        task_instance
      end

      Rake::Task['spec:bench'].invoke('hdl')
    end

    it 'spec:bench scope mos6502 invokes BenchmarkTask with mos6502 pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/examples/mos6502/')
        task_instance
      end

      Rake::Task['spec:bench'].invoke('mos6502')
    end

    it 'spec:bench scope apple2 invokes BenchmarkTask with apple2 pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/examples/apple2/')
        task_instance
      end

      Rake::Task['spec:bench'].invoke('apple2')
    end

    it 'spec:bench scope riscv invokes BenchmarkTask with riscv pattern' do
      task_instance = instance_double(RHDL::CLI::Tasks::BenchmarkTask)
      allow(task_instance).to receive(:run)

      expect(RHDL::CLI::Tasks::BenchmarkTask).to receive(:new) do |opts|
        expect(opts[:type]).to eq(:tests)
        expect(opts[:pattern]).to eq('spec/examples/riscv/')
        task_instance
      end

      Rake::Task['spec:bench'].invoke('riscv')
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

  describe 'web tasks' do
    it 'web:start launches WEBrick static server with COOP/COEP headers' do
      require 'webrick'
      server = instance_double(WEBrick::HTTPServer)

      expect(WEBrick::HTTPServer).to receive(:new) do |opts|
        expect(opts[:BindAddress]).to eq('127.0.0.1')
        expect(opts[:Port]).to eq(8080)
        expect(opts[:DocumentRoot]).to end_with('/web/dist')
        expect(opts[:RequestCallback]).to be_a(Proc)

        response = {}
        opts[:RequestCallback].call(nil, response)
        expect(response['Cross-Origin-Opener-Policy']).to eq('same-origin')
        expect(response['Cross-Origin-Embedder-Policy']).to eq('require-corp')
        expect(response['Cross-Origin-Resource-Policy']).to eq('same-origin')
        server
      end
      expect(server).to receive(:mount).with(
        '/',
        WEBrick::HTTPServlet::FileHandler,
        a_string_ending_with('/web/dist')
      )
      expect(server).to receive(:mount_proc).with('/__rhdl_live_reload_version')
      expect(Kernel).to receive(:trap).with('INT')
      expect(Kernel).to receive(:trap).with('TERM')
      expect(server).to receive(:start)

      Rake::Task['web:start'].invoke
    end

    it 'web:build invokes WebGenerateTask#run_build' do
      task_instance = instance_double(RHDL::CLI::Tasks::WebGenerateTask)
      allow(task_instance).to receive(:run_build)

      expect(RHDL::CLI::Tasks::WebGenerateTask).to receive(:new).and_return(task_instance)
      expect(task_instance).to receive(:run_build)

      Rake::Task['web:build'].invoke
    end

    it 'web:generate invokes WebGenerateTask with no options' do
      expect_task_class(RHDL::CLI::Tasks::WebGenerateTask, {})
      Rake::Task['web:generate'].invoke
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
      expect(defined?(RHDL::CLI::Tasks::WebGenerateTask)).to eq('constant')
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
        RHDL::CLI::Tasks::TuiTask,
        RHDL::CLI::Tasks::WebGenerateTask
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
        RHDL::CLI::Tasks::TuiTask,
        RHDL::CLI::Tasks::WebGenerateTask
      ]

      task_classes.each do |klass|
        expect(klass.instance_methods(false)).to include(:run),
          "Expected #{klass} to define its own run method"
      end
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
        spec pspec
        spec:bench spec:bench:timing spec:bench:quick
        pspec:n pspec:prepare pspec:balanced
        deps deps:install deps:check
        bench:native bench:web
        gem:build gem:build:checksum gem:install gem:install:local gem:release
        native:build native:clean native:check
        web:start web:build web:generate
        build:setup build:setup:binstubs
        build:clean build:clobber
      ].each do |task_name|
      it "defines #{task_name} task" do
        expect(Rake::Task.task_defined?(task_name)).to be(true),
          "Expected rake task '#{task_name}' to be defined"
      end
    end
  end
end
