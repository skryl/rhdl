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
task spec: 'setup:binstubs'
task pspec: 'setup:binstubs'

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
        puts "No runtime log found. Run 'rake parallel:prepare' first for optimal balancing."
        puts "Falling back to file-count based grouping..."
        Rake::Task['parallel:spec'].invoke
      end
    end
  end

  desc "Run all tests in parallel (alias for parallel:spec)"
  task pspec: 'parallel:spec'

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
end

desc "Run gate benchmark (alias for bench:gates)"
task bench: 'bench:gates'

namespace :benchmark do
  desc "Profile RSpec tests and show slowest 20 tests"
  task :tests, [:count] => 'setup:binstubs' do |_, args|
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(
      type: :tests,
      count: args[:count]&.to_i || 20,
      pattern: 'spec/'
    ).run
  end

  desc "Profile 6502 tests and show slowest tests"
  task :tests_6502, [:count] => 'setup:binstubs' do |_, args|
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(
      type: :tests,
      count: args[:count]&.to_i || 20,
      pattern: 'spec/examples/mos6502/'
    ).run
  end

  desc "Profile HDL tests and show slowest tests"
  task :tests_hdl, [:count] => 'setup:binstubs' do |_, args|
    load_cli_tasks
    RHDL::CLI::Tasks::BenchmarkTask.new(
      type: :tests,
      count: args[:count]&.to_i || 20,
      pattern: 'spec/rhdl/hdl/'
    ).run
  end

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

desc "Benchmark tests showing 20 slowest (alias for benchmark:tests)"
task benchmark: 'benchmark:tests'

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
