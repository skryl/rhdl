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
# Development Tasks
# =============================================================================

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
task setup: ['setup:binstubs']

# =============================================================================
# Test Tasks (spec namespace)
# =============================================================================

# Test path definitions
SPEC_PATHS = {
  all: 'spec/',
  lib: 'spec/rhdl/',
  hdl: 'spec/rhdl/hdl/',
  mos6502: 'spec/examples/mos6502/',
  apple2: 'spec/examples/apple2/'
}.freeze

# RSpec tasks
begin
  require "rspec/core/rake_task"

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.rspec_opts = "--format progress"
  end

  namespace :spec do
    desc "Run lib/rhdl specs"
    RSpec::Core::RakeTask.new(:lib) do |t|
      t.pattern = "#{SPEC_PATHS[:lib]}**/*_spec.rb"
      t.rspec_opts = "--format progress"
    end

    desc "Run HDL component specs"
    RSpec::Core::RakeTask.new(:hdl) do |t|
      t.pattern = "#{SPEC_PATHS[:hdl]}**/*_spec.rb"
      t.rspec_opts = "--format progress"
    end

    desc "Run MOS 6502 specs"
    RSpec::Core::RakeTask.new(:mos6502) do |t|
      t.pattern = "#{SPEC_PATHS[:mos6502]}**/*_spec.rb"
      t.rspec_opts = "--format progress"
    end

    desc "Run Apple II specs"
    RSpec::Core::RakeTask.new(:apple2) do |t|
      t.pattern = "#{SPEC_PATHS[:apple2]}**/*_spec.rb"
      t.rspec_opts = "--format progress"
    end

    # Benchmark tasks
    namespace :bench do
      desc "Benchmark all specs"
      task :all, [:count] => 'setup:binstubs' do |_, args|
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(
          type: :tests,
          count: args[:count]&.to_i || 20,
          pattern: SPEC_PATHS[:all]
        ).run
      end

      desc "Benchmark lib/rhdl specs"
      task :lib, [:count] => 'setup:binstubs' do |_, args|
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(
          type: :tests,
          count: args[:count]&.to_i || 20,
          pattern: SPEC_PATHS[:lib]
        ).run
      end

      desc "Benchmark HDL specs"
      task :hdl, [:count] => 'setup:binstubs' do |_, args|
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(
          type: :tests,
          count: args[:count]&.to_i || 20,
          pattern: SPEC_PATHS[:hdl]
        ).run
      end

      desc "Benchmark MOS 6502 specs"
      task :mos6502, [:count] => 'setup:binstubs' do |_, args|
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(
          type: :tests,
          count: args[:count]&.to_i || 20,
          pattern: SPEC_PATHS[:mos6502]
        ).run
      end

      desc "Benchmark Apple II specs"
      task :apple2, [:count] => 'setup:binstubs' do |_, args|
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(
          type: :tests,
          count: args[:count]&.to_i || 20,
          pattern: SPEC_PATHS[:apple2]
        ).run
      end
    end

    desc "Benchmark all specs (alias for spec:bench:all)"
    task bench: 'spec:bench:all'
  end

rescue LoadError
  desc "Run RSpec tests"
  task :spec do
    sh "ruby -Ilib -S rspec"
  end

  namespace :spec do
    desc "Run lib/rhdl specs"
    task :lib do
      sh "ruby -Ilib -S rspec #{SPEC_PATHS[:lib]} --format progress"
    end

    desc "Run HDL component specs"
    task :hdl do
      sh "ruby -Ilib -S rspec #{SPEC_PATHS[:hdl]} --format progress"
    end

    desc "Run MOS 6502 specs"
    task :mos6502 do
      sh "ruby -Ilib -S rspec #{SPEC_PATHS[:mos6502]} --format progress"
    end

    desc "Run Apple II specs"
    task :apple2 do
      sh "ruby -Ilib -S rspec #{SPEC_PATHS[:apple2]} --format progress"
    end
  end
end

# Ensure binstubs exist before running tests
task spec: 'setup:binstubs'
task pspec: 'setup:binstubs'

# =============================================================================
# Parallel Test Tasks (pspec namespace)
# =============================================================================

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

  desc "Run all tests in parallel"
  task :pspec do
    sh "#{parallel_rspec_cmd} #{SPEC_PATHS[:all]}"
  end

  namespace :pspec do
    desc "Run lib/rhdl specs in parallel"
    task :lib do
      sh "#{parallel_rspec_cmd} #{SPEC_PATHS[:lib]}"
    end

    desc "Run HDL specs in parallel"
    task :hdl do
      sh "#{parallel_rspec_cmd} #{SPEC_PATHS[:hdl]}"
    end

    desc "Run MOS 6502 specs in parallel"
    task :mos6502 do
      sh "#{parallel_rspec_cmd} #{SPEC_PATHS[:mos6502]}"
    end

    desc "Run Apple II specs in parallel"
    task :apple2 do
      sh "#{parallel_rspec_cmd} #{SPEC_PATHS[:apple2]}"
    end

    desc "Run tests with specific number of processes"
    task :n, [:count] do |_, args|
      count = args[:count] || ENV['PARALLEL_TEST_PROCESSORS'] || Parallel.processor_count
      sh "#{parallel_rspec_cmd} -n #{count} #{SPEC_PATHS[:all]}"
    end

    desc "Prepare parallel test database (record test file runtimes)"
    task :prepare do
      FileUtils.mkdir_p('tmp')
      sh "#{parallel_rspec_cmd} --record-runtime #{SPEC_PATHS[:all]}"
    end

    desc "Run tests with runtime-based grouping for better balance"
    task :balanced do
      runtime_log = 'tmp/parallel_runtime_rspec.log'
      if File.exist?(runtime_log)
        sh "#{parallel_rspec_cmd} --group-by runtime --runtime-log #{runtime_log} #{SPEC_PATHS[:all]}"
      else
        puts "No runtime log found. Run 'rake pspec:prepare' first for optimal balancing."
        puts "Falling back to file-count based grouping..."
        Rake::Task['pspec'].invoke
      end
    end
  end

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

desc "Install test dependencies (alias for deps:install)"
task deps: 'deps:install'

# Benchmarking
namespace :bench do
  desc "Benchmark gate-level simulation"
  task :gates do
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :gates).run
  end

  desc "Benchmark MOS6502 CPU IR with memory bridging"
  task :mos6502, [:cycles] do |_, args|
    load_cli_tasks
    cycles = args[:cycles]&.to_i || 5_000_000
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :mos6502, cycles: cycles).run
  end

  desc "Benchmark Apple2 full system IR"
  task :apple2, [:cycles] do |_, args|
    load_cli_tasks
    cycles = args[:cycles]&.to_i || 5_000_000
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :apple2, cycles: cycles).run
  end

  desc "Benchmark GameBoy with Prince of Persia ROM"
  task :gameboy, [:frames] do |_, args|
    load_cli_tasks
    frames = args[:frames]&.to_i || 1000
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :gameboy, frames: frames).run
  end

  desc "Benchmark IR runners"
  task :ir, [:cycles] do |_, args|
    load_cli_tasks
    cycles = args[:cycles]&.to_i || 5_000_000
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :ir, cycles: cycles).run
  end
end

desc "Run gate benchmark (alias for bench:gates)"
task bench: 'bench:gates'

namespace :benchmark do
  desc "Run full test timing analysis (detailed per-file timing)"
  task timing: 'setup:binstubs' do
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :timing).run
  end

  desc "Quick benchmark of test categories"
  task quick: 'setup:binstubs' do
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(type: :quick).run
  end
end

desc "Benchmark tests showing 20 slowest (alias for spec:bench)"
task benchmark: 'spec:bench'

# Default task
task default: :spec

# =============================================================================
# Native Extension Tasks
# =============================================================================

namespace :native do
  desc "Build the native ISA simulator Rust extension"
  task :build do
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(build: true).run
  end

  desc "Clean native extension build artifacts"
  task :clean do
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(clean: true).run
  end

  desc "Check if native extension is available"
  task :check do
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(check: true).run
  end
end

desc "Build native ISA simulator (alias for native:build)"
task native: 'native:build'

# =============================================================================
# Debug Tasks
# =============================================================================

namespace :debug do
  desc "Debug Game Boy interrupt handling with VCD tracing"
  task :interrupt do
    load_cli_tasks
    require_relative 'lib/rhdl/cli/tasks/debug_interrupt_task'
    RHDL::CLI::Tasks::DebugInterruptTask.new.run
  end
end
