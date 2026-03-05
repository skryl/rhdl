# frozen_string_literal: true

# Try to load bundler, but don't fail if it's not available
begin
  require "bundler/gem_tasks"

  original_clean_task = Rake::Task.task_defined?('clean') ? Rake::Task['clean'] : nil
  original_clobber_task = Rake::Task.task_defined?('clobber') ? Rake::Task['clobber'] : nil
  original_release_task = Rake::Task.task_defined?('release') ? Rake::Task['release'] : nil

  namespace :gem do
    desc "Build the rhdl gem package"
    task :build do
      Bundler::GemHelper.instance.build_gem
    end

    desc "Install the rhdl gem locally"
    task :install do
      Bundler::GemHelper.instance.install_gem
    end

    namespace :build do
      desc "Generate SHA512 checksum of built gem artifact"
      task :checksum do
        Bundler::GemHelper.instance.build_checksum
      end
    end

    namespace :install do
      desc "Install the rhdl gem locally from built artifacts"
      task :local do
        Bundler::GemHelper.instance.install_gem(nil, true)
      end
    end

    desc "Release the rhdl gem"
    task :release do
      if original_release_task
        original_release_task.invoke
      else
        abort "Bundler release task is not available. Ensure bundler gem tasks are loaded."
      end
    end
  end

  namespace :build do
    if original_clean_task
      desc "Remove any temporary products"
      task :clean do
        original_clean_task.invoke
      end
    end

    if original_clobber_task
      desc "Remove any generated files"
      task :clobber do
        original_clobber_task.invoke
      end
    end

    # No custom dependency install task in build namespace
  end

  Rake.application.instance_variable_get(:@tasks).delete('build')
  Rake.application.instance_variable_get(:@tasks).delete('build:checksum')
  Rake.application.instance_variable_get(:@tasks).delete('install')
  Rake.application.instance_variable_get(:@tasks).delete('install:local')
  Rake.application.instance_variable_get(:@tasks).delete('release')
  Rake.application.instance_variable_get(:@tasks).delete('clean')
  Rake.application.instance_variable_get(:@tasks).delete('clobber')

  desc "Install test dependencies (alias for deps:install)"
  task deps: 'deps:install'
rescue LoadError
  # Bundler not available, skip gem tasks
end
require 'rbconfig'

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

namespace :build do
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
  task setup: ['build:setup:binstubs']
end

namespace :native do
  desc "Build the native ISA simulator Rust extension"
  task :build, [:target] do |_t, args|
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(build: true, target: args[:target]).run
  end

  desc "Clean native extension build artifacts"
  task :clean, [:target] do |_t, args|
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(clean: true, target: args[:target]).run
  end

  desc "Check if native extension is available"
  task :check, [:target] do |_t, args|
    load_cli_tasks
    RHDL::CLI::Tasks::NativeTask.new(check: true, target: args[:target]).run
  end
end

# =============================================================================
# Test Tasks (spec namespace)
# =============================================================================

# Test path definitions
SPEC_PATHS = {
  all: 'spec/',
  lib: 'spec/rhdl/',
  hdl: 'spec/rhdl/hdl/',
  mos6502: 'spec/examples/mos6502/',
  apple2: 'spec/examples/apple2/',
  riscv: 'spec/examples/riscv/'
}.freeze

# RSpec tasks
begin
  require "rspec/core/rake_task"

  desc "Run specs by scope (all, lib, hdl, mos6502, apple2, riscv)"
  task :spec, [:scope] => 'build:setup:binstubs' do |_, args|
    scope = (args[:scope] || 'all').to_sym

    patterns = {
      all: SPEC_PATHS[:all],
      lib: SPEC_PATHS[:lib],
      hdl: SPEC_PATHS[:hdl],
      mos6502: SPEC_PATHS[:mos6502],
      apple2: SPEC_PATHS[:apple2],
      riscv: SPEC_PATHS[:riscv]
    }
    pattern = patterns[scope]

    if pattern.nil?
      puts "Unknown spec scope '#{scope}'."
      puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
      exit 1
    end

    sh "bin/rspec #{pattern} --format progress"
  end
  
  namespace :spec do
    # Benchmark tasks
    desc "Benchmark specs by scope (all, lib, hdl, mos6502, apple2, riscv)"
    task :bench, [:scope, :count] => 'build:setup:binstubs' do |_, args|
      load_cli_tasks

      scope = (args[:scope] || 'all').to_sym
      count = args[:count]&.to_i || 20

      patterns = {
        all: SPEC_PATHS[:all],
        lib: SPEC_PATHS[:lib],
        hdl: SPEC_PATHS[:hdl],
        mos6502: SPEC_PATHS[:mos6502],
        apple2: SPEC_PATHS[:apple2],
        riscv: SPEC_PATHS[:riscv]
      }
      pattern = patterns[scope]

      if pattern.nil?
        puts "Unknown spec benchmark scope '#{scope}'."
        puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
        exit 1
      end

      RHDL::CLI::Tasks::BenchmarkTask.new(
        type: :tests,
        count: count,
        pattern: pattern
      ).run
    end

    namespace :bench do
      desc "Run full test timing analysis (detailed per-file timing)"
      task :timing => 'build:setup:binstubs' do
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(type: :timing).run
      end

      desc "Quick benchmark of test categories"
      task :quick => 'build:setup:binstubs' do
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(type: :quick).run
      end
    end
  end

rescue LoadError
  desc "Run specs by scope (all, lib, hdl, mos6502, apple2, riscv)"
  task :spec, [:scope] => 'build:setup:binstubs' do |_, args|
    scope = (args[:scope] || 'all').to_sym
    patterns = {
      all: SPEC_PATHS[:all],
      lib: SPEC_PATHS[:lib],
      hdl: SPEC_PATHS[:hdl],
      mos6502: SPEC_PATHS[:mos6502],
      apple2: SPEC_PATHS[:apple2],
      riscv: SPEC_PATHS[:riscv]
    }
    pattern = patterns[scope]

    if pattern.nil?
      puts "Unknown spec scope '#{scope}'."
      puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
      exit 1
    end

    sh "ruby -Ilib -S rspec #{pattern} --format progress"
  end

  namespace :spec do
    # Benchmark tasks
    desc "Benchmark specs by scope (all, lib, hdl, mos6502, apple2, riscv)"
    task :bench, [:scope, :count] do |_, args|
      load_cli_tasks

      scope = (args[:scope] || 'all').to_sym
      count = args[:count]&.to_i || 20

      patterns = {
        all: SPEC_PATHS[:all],
        lib: SPEC_PATHS[:lib],
        hdl: SPEC_PATHS[:hdl],
        mos6502: SPEC_PATHS[:mos6502],
        apple2: SPEC_PATHS[:apple2],
        riscv: SPEC_PATHS[:riscv]
      }
      pattern = patterns[scope]

      if pattern.nil?
        puts "Unknown spec benchmark scope '#{scope}'."
        puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
        exit 1
      end

      RHDL::CLI::Tasks::BenchmarkTask.new(
        type: :tests,
        count: count,
        pattern: pattern
      ).run
    end

    namespace :bench do
      desc "Run full test timing analysis (detailed per-file timing)"
      task :timing do
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(type: :timing).run
      end

      desc "Quick benchmark of test categories"
      task :quick do
        load_cli_tasks
        RHDL::CLI::Tasks::BenchmarkTask.new(type: :quick).run
      end
    end
  end
end

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

  # Force compact dot output for parallel runs, independent of .rspec defaults.
  def run_parallel_rspec(args)
    sh "RUBYOPT=-W0 #{parallel_rspec_cmd} --quiet --test-options '--format progress' #{args}"
  end

  desc "Run specs in parallel by scope (all, lib, hdl, mos6502, apple2, riscv)"
  task :pspec, [:scope] => 'build:setup:binstubs' do |_, args|
    scope = (args[:scope] || 'all').to_sym
    patterns = {
      all: SPEC_PATHS[:all],
      lib: SPEC_PATHS[:lib],
      hdl: SPEC_PATHS[:hdl],
      mos6502: SPEC_PATHS[:mos6502],
      apple2: SPEC_PATHS[:apple2],
      riscv: SPEC_PATHS[:riscv]
    }
    pattern = patterns[scope]

    if pattern.nil?
      puts "Unknown pspec scope '#{scope}'."
      puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
      exit 1
    end

    run_parallel_rspec(pattern)
  end

  namespace :pspec do
    desc "Run tests with specific number of processes"
    task :n, [:count] do |_, args|
      count = args[:count] || ENV['PARALLEL_TEST_PROCESSORS'] || Parallel.processor_count
      run_parallel_rspec("-n #{count} #{SPEC_PATHS[:all]}")
    end

    desc "Prepare parallel test database (record test file runtimes)"
    task :prepare do
      FileUtils.mkdir_p('tmp')
      run_parallel_rspec("--record-runtime #{SPEC_PATHS[:all]}")
    end

    desc "Run tests with runtime-based grouping for better balance"
    task :balanced do
      runtime_log = 'tmp/parallel_runtime_rspec.log'
      if File.exist?(runtime_log)
        run_parallel_rspec("--group-by runtime --runtime-log #{runtime_log} #{SPEC_PATHS[:all]}")
      else
        puts "No runtime log found. Run 'rake pspec:prepare' first for optimal balancing."
        puts "Falling back to file-count based grouping..."
        Rake::Task['pspec'].invoke
      end
    end
  end

rescue LoadError
  desc "Run tests in parallel (requires parallel_tests gem)"
  task :pspec, [:scope] => 'build:setup:binstubs' do |_, args|
    scope = (args[:scope] || 'all').to_sym
    patterns = {
      all: SPEC_PATHS[:all],
      lib: SPEC_PATHS[:lib],
      hdl: SPEC_PATHS[:hdl],
      mos6502: SPEC_PATHS[:mos6502],
      apple2: SPEC_PATHS[:apple2],
      riscv: SPEC_PATHS[:riscv]
    }

    if patterns[scope].nil?
      puts "Unknown pspec scope '#{scope}'."
      puts "Available scopes: all, lib, hdl, mos6502, apple2, riscv"
    end

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
  desc "Check and install test dependencies (iverilog, verilator, CIRCT tools)"
  task :install do
    load_cli_tasks
    RHDL::CLI::Tasks::DepsTask.new.run
  end

  desc "Check test dependencies status"
  task :check do
    load_cli_tasks
    RHDL::CLI::Tasks::DepsTask.new(check: true).run
  end

  desc "Fail-fast ArcToGPU toolchain check (arcilator_gpu prerequisites)"
  task :check_gpu do
    load_cli_tasks
    RHDL::CLI::Tasks::DepsTask.new(check_gpu: true, strict_gpu: true).run
  end
end

# Benchmarking
namespace :bench do
  desc "Benchmark by scope (gates, cpu8bit, gem_metal, gem_metal_cpu8bit, gem_metal_riscv, mos6502, apple2, gameboy, ir, riscv)"
  task :native, [:scope, :count] do |_, args|
    load_cli_tasks

    scope = (args[:scope] || 'gates').to_sym
    count = args[:count]&.to_i

    case scope
    when :gates
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gates).run
    when :cpu8bit
      cycles = count || 5_000_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :cpu8bit, cycles: cycles).run
    when :gem_metal
      cycles = count || 50_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gem_metal, cycles: cycles).run
    when :gem_metal_cpu8bit
      cycles = count || 5_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gem_metal_cpu8bit, cycles: cycles).run
    when :gem_metal_riscv
      cycles = count || 5_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gem_metal_riscv, cycles: cycles).run
    when :mos6502
      cycles = count || 5_000_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :mos6502, cycles: cycles).run
    when :apple2
      cycles = count || 5_000_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :apple2, cycles: cycles).run
    when :gameboy
      frames = count || 1_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :gameboy, frames: frames).run
    when :ir
      cycles = count || 5_000_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :ir, cycles: cycles).run
    when :riscv
      cycles = count || 100_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :riscv, cycles: cycles).run
    else
      puts "Unknown benchmark scope '#{scope}'."
      puts "Available scopes: gates, cpu8bit, gem_metal, gem_metal_cpu8bit, gem_metal_riscv, mos6502, apple2, gameboy, ir, riscv"
      exit 1
    end
  end

  desc "Run web benchmarks by scope (apple2, riscv)"
  task :web, [:scope, :count] do |_, args|
    load_cli_tasks

    scope = (args[:scope] || 'apple2').to_sym
    count = args[:count]&.to_i

    case scope
    when :apple2
      cycles = count || 5_000_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :web_apple2, cycles: cycles).run
    when :riscv
      cycles = count || 100_000
      RHDL::CLI::Tasks::BenchmarkTask.new(type: :web_riscv, cycles: cycles).run
    else
      puts "Unknown web benchmark scope '#{scope}'."
      puts "Available scopes: apple2, riscv"
      exit 1
    end
  end
end

# Default task
task default: :spec

# =============================================================================
# Native Extension Tasks
# =============================================================================

# =============================================================================
# Web Tasks
# =============================================================================

namespace :web do
  web_dir = File.expand_path('web', __dir__)
  web_node_modules_dir = File.join(web_dir, 'node_modules')

  install_web_dependencies = lambda do
    has_node_modules = if File.directory?(web_node_modules_dir)
      Dir.entries(web_node_modules_dir).size > 2
    else
      false
    end

    return if has_node_modules

    Dir.chdir(web_dir) do
      sh 'bun install --frozen-lockfile'
    end
  end

  desc "Start local web server for the web UI (builds dist first unless SKIP_WEB_BUNDLE=1)"
  task :start, [:port] do |_t, args|
    require 'webrick'

    host = (ENV['HOST'] || '127.0.0.1').to_s
    port = Integer(args[:port] || ENV['PORT'] || '8080')
    web_root = File.expand_path('web/dist', __dir__)
    watch_enabled = ENV.fetch('WEB_WATCH', '1') != '0' && ENV['SKIP_WEB_BUNDLE'] != '1'
    watch_interval = (Float(ENV.fetch('WEB_WATCH_INTERVAL', '0.75')) rescue 0.75)
    watch_interval = 0.75 unless watch_interval.positive?
    watch_targets = [
      File.join(web_dir, 'app'),
      File.join(web_dir, 'assets'),
      File.join(web_dir, 'index.html'),
      File.join(web_dir, 'coi-serviceworker.js'),
      File.join(web_dir, 'build.ts'),
      File.join(web_dir, 'package.json'),
      File.join(web_dir, 'tsconfig.json'),
      File.join(web_dir, 'bun.lock')
    ]

    inject_live_reload_client = lambda do
      index_path = File.join(web_root, 'index.html')
      next unless File.file?(index_path)

      html = File.read(index_path)
      marker = 'window.__RHDLLiveReloadPoll'
      next if html.include?(marker)

      snippet = <<~HTML
        <script>
          (() => {
            if (window.__RHDLLiveReloadPoll) return;
            window.__RHDLLiveReloadPoll = true;
            let knownVersion = null;
            const poll = async () => {
              try {
                const res = await fetch('./__rhdl_live_reload_version?ts=' + Date.now(), { cache: 'no-store' });
                if (!res.ok) return;
                const data = await res.json();
                const nextVersion = Number(data && data.version);
                if (!Number.isFinite(nextVersion)) return;
                if (knownVersion === null) {
                  knownVersion = nextVersion;
                  return;
                }
                if (nextVersion !== knownVersion) {
                  window.location.reload();
                }
              } catch (_err) {}
            };
            poll();
            setInterval(poll, 800);
          })();
        </script>
      HTML

      if html.include?('</body>')
        html.sub!('</body>', "#{snippet}\n  </body>")
      else
        html << "\n#{snippet}\n"
      end
      File.write(index_path, html)
    end

    snapshot_watch_inputs = lambda do
      snapshot = {}
      watch_targets.each do |target|
        if File.directory?(target)
          Dir.glob(File.join(target, '**', '*')).sort.each do |path|
            next if File.directory?(path)

            stat = File.stat(path) rescue nil
            next unless stat

            snapshot[path] = [stat.mtime.to_f, stat.size]
          end
          next
        end

        next unless File.file?(target)

        stat = File.stat(target) rescue nil
        next unless stat

        snapshot[target] = [stat.mtime.to_f, stat.size]
      end
      snapshot
    end

    live_reload_version = 0
    live_reload_mutex = Mutex.new
    watcher_stop = false
    watcher_thread = nil

    if ENV['SKIP_WEB_BUNDLE'] != '1'
      install_web_dependencies.call
      Dir.chdir(web_dir) do
        sh 'bun run build'
      end
      inject_live_reload_client.call if watch_enabled
    end

    unless File.directory?(web_root) && File.file?(File.join(web_root, 'index.html'))
      abort "[web] Missing built assets at #{web_root}. Run `bundle exec rake web:bundle` first."
    end
    puts "Starting web server at http://#{host}:#{port} (root: #{web_root})"
    puts '[web] Watching for changes with auto-reload enabled.' if watch_enabled

    headers_callback = proc do |_req, res|
      res['Cross-Origin-Opener-Policy'] = 'same-origin'
      res['Cross-Origin-Embedder-Policy'] = 'require-corp'
      res['Cross-Origin-Resource-Policy'] = 'same-origin'
    end

    server = WEBrick::HTTPServer.new(
      BindAddress: host,
      Port: port,
      DocumentRoot: web_root,
      AccessLog: [],
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN),
      RequestCallback: headers_callback
    )
    server.mount_proc('/__rhdl_live_reload_version') do |_req, res|
      version = live_reload_mutex.synchronize { live_reload_version }
      res.status = 200
      res['Content-Type'] = 'application/json'
      res['Cache-Control'] = 'no-store, max-age=0'
      res['Pragma'] = 'no-cache'
      res.body = "{\"version\":#{version}}"
    end
    server.mount('/', WEBrick::HTTPServlet::FileHandler, web_root)

    if watch_enabled
      watch_snapshot = snapshot_watch_inputs.call
      watcher_thread = Thread.new do
        while !watcher_stop
          sleep watch_interval
          next if watcher_stop

          latest_snapshot = snapshot_watch_inputs.call
          next if latest_snapshot == watch_snapshot

          changed_count = (watch_snapshot.keys | latest_snapshot.keys).count do |path|
            watch_snapshot[path] != latest_snapshot[path]
          end
          changed_count = 1 if changed_count < 1
          puts "[web] Detected #{changed_count} changed file(s); rebuilding..."
          build_ok = false
          Dir.chdir(web_dir) do
            build_ok = system('bun', 'run', 'build')
          end

          if build_ok
            inject_live_reload_client.call
            live_reload_mutex.synchronize { live_reload_version += 1 }
            version = live_reload_mutex.synchronize { live_reload_version }
            puts "[web] Rebuild complete (reload version #{version})."
          else
            warn '[web] Rebuild failed. Waiting for next change.'
          end
          watch_snapshot = latest_snapshot
        end
      end
    end

    trap_signals = %w[INT TERM]
    trap_signals.each do |signal|
      Kernel.trap(signal) do
        watcher_stop = true
        watcher_thread&.join(2)
        server.shutdown
      end
    end

    begin
      server.start
    ensure
      watcher_stop = true
      watcher_thread&.join(2)
    end
  end

  desc "Generate web artifacts, bundle, then start local web server"
  task :serve, [:port] do |_t, args|
    Rake::Task['web:generate'].invoke
    Rake::Task['web:start'].invoke(args[:port])
  end

  desc "Build web simulator WASM artifacts"
  task :build do
    load_cli_tasks
    RHDL::CLI::Tasks::WebGenerateTask.new.run_build
  end

  desc "Generate web simulator artifacts (IR, schematics, Ruby/Verilog source bundles)"
  task :generate do
    load_cli_tasks
    RHDL::CLI::Tasks::WebGenerateTask.new.run
  end

  desc "Bundle web simulator with Bun (output in web/dist/)"
  task :bundle do
    unless system('which bun > /dev/null 2>&1')
      abort "[web:bundle] Bun is required. Install from https://bun.sh"
    end

    install_web_dependencies.call

    Dir.chdir(web_dir) do
      sh 'bun run build'
    end
  end

  desc "Bundle web simulator for production"
  task 'bundle:prod' do
    unless system('which bun > /dev/null 2>&1')
      abort "[web:bundle:prod] Bun is required. Install from https://bun.sh"
    end

    install_web_dependencies.call

    Dir.chdir(web_dir) do
      sh 'bun run build:prod'
    end
  end
end

# =============================================================================
# Desktop (Electrobun) Tasks
# =============================================================================

namespace :desktop do
  desktop_dir = File.expand_path('web/desktop', __dir__)

  check_bun = -> {
    unless system('which bun > /dev/null 2>&1')
      abort <<~MSG
        [desktop] Bun is required but not found.
        Install it from https://bun.sh:
          curl -fsSL https://bun.sh/install | bash
      MSG
    end
  }

  check_electrobun = -> {
    unless File.exist?(File.join(desktop_dir, 'node_modules', 'electrobun'))
      abort <<~MSG
        [desktop] Electrobun not installed. Run:
          cd #{desktop_dir} && bun install
      MSG
    end
  }

  desc "Install desktop app dependencies (bun install)"
  task :install do
    check_bun.call
    Dir.chdir(desktop_dir) do
      sh 'bun install'
    end
  end

  desc "Build and launch desktop app in development mode"
  task :dev do
    check_bun.call
    check_electrobun.call
    Dir.chdir(desktop_dir) do
      sh 'bun run dev'
    end
  end

  desc "Build desktop app for development"
  task :build do
    check_bun.call
    check_electrobun.call
    Dir.chdir(desktop_dir) do
      sh 'bun run build:dev'
    end
  end

  desc "Build desktop app for stable release"
  task :release do
    check_bun.call
    check_electrobun.call
    Dir.chdir(desktop_dir) do
      sh 'bun run build:stable'
    end
  end

  desc "Clean desktop build artifacts"
  task :clean do
    rm_rf File.join(desktop_dir, 'build')
    rm_rf File.join(desktop_dir, 'artifacts')
    rm_rf File.join(desktop_dir, 'src', 'simulator')
    puts "[desktop] Cleaned build artifacts."
  end
end
