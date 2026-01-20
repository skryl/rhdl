# frozen_string_literal: true

# Try to load bundler, but don't fail if it's not available
begin
  require "bundler/gem_tasks"
rescue LoadError
  # Bundler not available, skip gem tasks
end

# =============================================================================
# CLI Task Loading
# =============================================================================

# Load CLI tasks for shared functionality
def load_cli_tasks
  require_relative 'lib/rhdl/cli'
end

# =============================================================================
# Development Tasks (not prefixed - internal use)
# =============================================================================

namespace :dev do
  namespace :setup do
    desc "Generate binstubs for all gem executables"
    task :binstubs do
      binstubs_needed = {
        'rake' => 'rake',
        'rspec-core' => 'rspec',
        'parallel_tests' => 'parallel_rspec'
      }

      binstubs_needed.each do |gem_name, executable|
        binstub_path = File.expand_path("bin/#{executable}", __dir__)
        unless File.executable?(binstub_path)
          puts "Generating binstub for #{executable}..."
          system("bundle binstubs #{gem_name} --force")
        end
      end
    end
  end

  desc "Setup development environment (install deps + binstubs)"
  task setup: ['dev:setup:binstubs']

  # RSpec tasks
  begin
    require "rspec/core/rake_task"

    RSpec::Core::RakeTask.new(:spec) do |t|
      t.rspec_opts = "--format progress"
    end

    RSpec::Core::RakeTask.new(:spec_6502) do |t|
      t.pattern = "spec/examples/mos6502/**/*_spec.rb"
      t.rspec_opts = "--format progress"
    end

    RSpec::Core::RakeTask.new(:spec_doc) do |t|
      t.rspec_opts = "--format documentation"
    end
  rescue LoadError
    desc "Run RSpec tests"
    task :spec do
      sh "ruby -Ilib -S rspec"
    end

    desc "Run 6502 CPU tests"
    task :spec_6502 do
      sh "ruby -Ilib -S rspec spec/examples/mos6502/ --format progress"
    end

    desc "Run all tests with documentation format"
    task :spec_doc do
      sh "ruby -Ilib -S rspec --format documentation"
    end
  end

  # Ensure binstubs exist before running tests
  task spec: 'dev:setup:binstubs'
  task pspec: 'dev:setup:binstubs'

  # Parallel Test Tasks
  begin
    require 'parallel_tests'

    # Helper to find the parallel_rspec command
    def parallel_rspec_cmd
      binstub = File.expand_path('bin/parallel_rspec', __dir__)
      if File.executable?(binstub)
        binstub
      else
        'bundle exec parallel_rspec'
      end
    end

    namespace :parallel do
      desc "Run all tests in parallel (auto-detect CPU count)"
      task :spec do
        sh "#{parallel_rspec_cmd} spec/"
      end

      desc "Run all tests in parallel with specific number of processes"
      task :spec_n, [:count] do |_, args|
        count = args[:count] || ENV['PARALLEL_TEST_PROCESSORS'] || Parallel.processor_count
        sh "#{parallel_rspec_cmd} -n #{count} spec/"
      end

      desc "Run 6502 CPU tests in parallel"
      task :spec_6502 do
        sh "#{parallel_rspec_cmd} spec/examples/mos6502/"
      end

      desc "Run HDL tests in parallel"
      task :spec_hdl do
        sh "#{parallel_rspec_cmd} spec/rhdl/hdl/"
      end

      desc "Prepare parallel test database (record test file runtimes)"
      task :prepare do
        FileUtils.mkdir_p('tmp')
        sh "#{parallel_rspec_cmd} --record-runtime spec/"
      end

      desc "Run tests in parallel using runtime-based grouping for better balance"
      task :spec_balanced do
        runtime_log = 'tmp/parallel_runtime_rspec.log'
        if File.exist?(runtime_log)
          sh "#{parallel_rspec_cmd} --group-by runtime --runtime-log #{runtime_log} spec/"
        else
          puts "No runtime log found. Run 'rake dev:parallel:prepare' first for optimal balancing."
          puts "Falling back to file-count based grouping..."
          Rake::Task['dev:parallel:spec'].invoke
        end
      end
    end

    desc "Run all tests in parallel (alias for dev:parallel:spec)"
    task pspec: 'dev:parallel:spec'

  rescue LoadError
    desc "Run tests in parallel (requires parallel_tests gem)"
    task :pspec do
      abort "parallel_tests gem not installed. Run: bundle install"
    end
  end

  # RuboCop tasks (optional)
  begin
    require "rubocop/rake_task"
    RuboCop::RakeTask.new(:rubocop)
  rescue LoadError
    # RuboCop not available
  end

  # Dependency Management
  namespace :deps do
    desc "Check and install test dependencies (iverilog)"
    task :install do
      load_cli_tasks
      RHDL::CLI::Tasks::DepsTask.new.run
    end

    desc "Check test dependencies status"
    task :check do
      load_cli_tasks
      RHDL::CLI::Tasks::DepsTask.new(check: true).run
    end
  end

  desc "Install test dependencies (alias for dev:deps:install)"
  task deps: 'dev:deps:install'

  # Benchmarking
  namespace :bench do
    desc "Benchmark gate-level simulation"
    task :gates do
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gates).run
    end
  end

  desc "Run gate benchmark (alias for dev:bench:gates)"
  task bench: 'dev:bench:gates'

  namespace :benchmark do
    desc "Profile RSpec tests and show slowest 20 tests"
    task :tests, [:count] => 'dev:setup:binstubs' do |_, args|
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(
        type: :tests,
        count: args[:count]&.to_i || 20,
        pattern: 'spec/'
      ).run
    end

    desc "Profile 6502 tests and show slowest tests"
    task :tests_6502, [:count] => 'dev:setup:binstubs' do |_, args|
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(
        type: :tests,
        count: args[:count]&.to_i || 20,
        pattern: 'spec/examples/mos6502/'
      ).run
    end

    desc "Profile HDL tests and show slowest tests"
    task :tests_hdl, [:count] => 'dev:setup:binstubs' do |_, args|
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(
        type: :tests,
        count: args[:count]&.to_i || 20,
        pattern: 'spec/rhdl/hdl/'
      ).run
    end

    desc "Run full test timing analysis (detailed per-file timing)"
    task timing: 'dev:setup:binstubs' do
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :timing).run
    end

    desc "Quick benchmark of test categories"
    task quick: 'dev:setup:binstubs' do
      load_cli_tasks
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :quick).run
    end
  end

  desc "Benchmark tests showing 20 slowest (alias for dev:benchmark:tests)"
  task benchmark: 'dev:benchmark:tests'
end

# Default task
task default: 'dev:spec'

# =============================================================================
# CLI Tasks (prefixed with cli: - shared with CLI binary)
# =============================================================================

namespace :cli do
  # ---------------------------------------------------------------------------
  # Diagram Generation
  # ---------------------------------------------------------------------------
  namespace :diagrams do
    desc "[CLI] Generate component-level diagrams (simple block view)"
    task :component do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'component').run
    end

    desc "[CLI] Generate hierarchical diagrams (with subcomponents)"
    task :hierarchical do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'hierarchical').run
    end

    desc "[CLI] Generate gate-level diagrams (primitive gates and flip-flops)"
    task :gate do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'gate').run
    end

    desc "[CLI] Generate all circuit diagrams (component, hierarchical, gate)"
    task generate: [:component, :hierarchical, :gate] do
      load_cli_tasks
      # Generate README after all modes are done
      task = RHDL::CLI::Tasks::DiagramTask.new(all: true)
      task.send(:generate_readme)
      puts
      puts "=" * 60
      puts "Done! Diagrams generated in: #{RHDL::CLI::Config.diagrams_dir}"
      puts "=" * 60
    end

    desc "[CLI] Clean all generated diagrams"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(clean: true).run
    end
  end

  desc "[CLI] Generate all diagrams (alias for cli:diagrams:generate)"
  task diagrams: 'cli:diagrams:generate'

  # ---------------------------------------------------------------------------
  # HDL Export
  # ---------------------------------------------------------------------------
  namespace :hdl do
    desc "[CLI] Export all DSL components to Verilog (lib/ and examples/)"
    task export: [:export_lib, :export_examples] do
      puts
      puts "=" * 50
      puts "HDL export complete!"
      load_cli_tasks
      puts "Verilog files: #{RHDL::CLI::Config.verilog_dir}"
    end

    desc "[CLI] Export lib/ DSL components to Verilog"
    task :export_lib do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'lib').run
    end

    desc "[CLI] Export examples/ components to Verilog"
    task :export_examples do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'examples').run
    end

    desc "[CLI] Export Verilog files"
    task :verilog do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'lib').run
    end

    desc "[CLI] Clean all generated HDL files"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(clean: true).run
    end
  end

  desc "[CLI] Export all HDL (alias for cli:hdl:export)"
  task hdl: 'cli:hdl:export'

  # ---------------------------------------------------------------------------
  # Gate-Level Synthesis
  # ---------------------------------------------------------------------------
  namespace :gates do
    desc "[CLI] Export all components to gate-level IR (JSON netlists)"
    task :export do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(export: true).run
    end

    desc "[CLI] Export simcpu datapath to gate-level"
    task :simcpu do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(simcpu: true).run
    end

    desc "[CLI] Clean gate-level synthesis output"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(clean: true).run
    end

    desc "[CLI] Show gate-level synthesis statistics"
    task :stats do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(stats: true).run
    end
  end

  desc "[CLI] Export gate-level synthesis (alias for cli:gates:export)"
  task gates: 'cli:gates:export'

  # ---------------------------------------------------------------------------
  # TUI Debugger
  # ---------------------------------------------------------------------------
  namespace :tui do
    desc "[CLI] Install Ink TUI dependencies"
    task :install do
      load_cli_tasks
      RHDL::CLI::Tasks::TuiTask.new(install: true).run
    end

    desc "[CLI] Build Ink TUI (compile TypeScript)"
    task :build do
      load_cli_tasks
      # Ensure deps are installed first
      RHDL::CLI::Tasks::TuiTask.new.send(:ensure_tui_deps)
      puts "Building Ink TUI..."
      puts "=" * 50
      Dir.chdir(RHDL::CLI::Config.tui_ink_dir) do
        sh 'npm run build'
      end
      puts
      puts "Ink TUI built successfully."
    end

    desc "[CLI] Run the Ink TUI with a demo simulation"
    task :run do
      load_cli_tasks
      RHDL::CLI::Tasks::TuiTask.new(ink: true).run
    end

    desc "[CLI] Run the Ink TUI with an ALU demo"
    task alu: :build do
      require_relative 'lib/rhdl'

      puts "Starting RHDL Ink TUI with ALU demo..."
      puts "=" * 50
      puts

      # Create ALU and supporting components
      alu = RHDL::HDL::ALU.new('alu', width: 8)
      acc = RHDL::HDL::Register.new('acc', width: 8)

      # Connect ALU output to accumulator input
      RHDL::HDL::SimComponent.connect(alu.outputs[:result], acc.inputs[:d])

      # Create debug simulator
      sim = RHDL::HDL::DebugSimulator.new
      sim.add_component(alu)
      sim.add_component(acc)

      # Set initial values
      alu.inputs[:a].set(0x42)
      alu.inputs[:b].set(0x10)
      alu.inputs[:op].set(0)  # ADD
      acc.inputs[:rst].set(0)
      acc.inputs[:en].set(1)

      # Create and run Ink adapter
      adapter = RHDL::HDL::InkAdapter.new(sim)
      adapter.add_component(alu, signals: :all)
      adapter.add_component(acc, signals: :all)
      adapter.run
    end

    desc "[CLI] List available components for TUI"
    task :list do
      load_cli_tasks
      RHDL::CLI::Tasks::TuiTask.new(list: true).run
    end

    desc "[CLI] Clean Ink TUI build artifacts"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::TuiTask.new(clean: true).run
    end
  end

  desc "[CLI] Run Ink TUI (alias for cli:tui:run)"
  task tui: 'cli:tui:run'

  # ---------------------------------------------------------------------------
  # Apple II Emulator
  # ---------------------------------------------------------------------------
  namespace :apple2 do
    desc "[CLI] Assemble the mini monitor ROM"
    task :build do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(build: true).run
    end

    desc "[CLI] Run the Apple II emulator with the mini monitor"
    task run: :build do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(build: true, run: true).run
    end

    desc "[CLI] Run with AppleIIGo public domain ROM"
    task :run_appleiigo do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(appleiigo: true).run
    end

    desc "[CLI] Run the Apple II emulator demo (no ROM needed)"
    task :demo do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(demo: true).run
    end

    desc "[CLI] Run Apple II emulator with Ink TUI"
    task :ink do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true).run
    end

    desc "[CLI] Run Apple II emulator with Ink TUI (HDL mode)"
    task :ink_hdl do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true, hdl: true).run
    end

    desc "[CLI] Run Apple II with program file using Ink TUI"
    task :ink_run, [:program] do |_, args|
      unless args[:program]
        puts "Usage: rake cli:apple2:ink_run[path/to/program.bin]"
        exit 1
      end
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(ink: true, program: args[:program]).run
    end

    desc "[CLI] Clean ROM output files"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::Apple2Task.new(clean: true).run
    end
  end

  desc "[CLI] Build Apple II ROM (alias for cli:apple2:build)"
  task apple2: 'cli:apple2:build'

  # ---------------------------------------------------------------------------
  # Combined Tasks
  # ---------------------------------------------------------------------------
  desc "[CLI] Generate all output files (diagrams + HDL exports)"
  task generate_all: ['cli:diagrams:generate', 'cli:hdl:export']

  desc "[CLI] Clean all generated files"
  task clean_all: ['cli:diagrams:clean', 'cli:hdl:clean', 'cli:gates:clean']

  desc "[CLI] Regenerate all output files (clean + generate)"
  task regenerate: ['cli:clean_all', 'cli:generate_all']
end

# =============================================================================
# Top-level Aliases (for convenience)
# =============================================================================

desc "Run tests (alias for dev:spec)"
task spec: 'dev:spec'

desc "Run tests in parallel (alias for dev:pspec)"
task pspec: 'dev:pspec'
