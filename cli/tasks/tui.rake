# frozen_string_literal: true

# TUI debugger tasks

namespace :cli do
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
      require_relative "#{RHDL_ROOT}/lib/rhdl"

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
end
