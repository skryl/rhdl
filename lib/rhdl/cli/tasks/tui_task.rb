# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for launching TUI debugger
      class TuiTask < Task
        def run
          if options[:install]
            install_deps
          elsif options[:clean]
            clean
          elsif options[:list]
            list_components
          elsif options[:ink]
            run_ink_tui
          else
            run_ruby_tui
          end
        end

        # Install Ink TUI dependencies
        def install_deps
          puts "Installing Ink TUI dependencies..."
          puts '=' * 50

          ensure_node_available
          Dir.chdir(Config.tui_ink_dir) { system('npm install') }

          puts
          puts "Ink TUI dependencies installed."
        end

        # Clean Ink TUI build artifacts
        def clean
          dist_dir = File.join(Config.tui_ink_dir, 'dist')
          node_modules = File.join(Config.tui_ink_dir, 'node_modules')

          FileUtils.rm_rf(dist_dir) if Dir.exist?(dist_dir)
          puts "Cleaned: #{dist_dir}"

          if ENV['CLEAN_NODE_MODULES']
            FileUtils.rm_rf(node_modules) if Dir.exist?(node_modules)
            puts "Cleaned: #{node_modules}"
          end
        end

        # List available components
        def list_components
          puts "Available Components:"
          puts '=' * 50
          puts

          Config.hdl_components.keys.sort.each do |name|
            puts "  #{name}"
          end

          puts
          puts "Use component path (e.g., sequential/counter) or"
          puts "full class reference (e.g., RHDL::HDL::Counter)"
        end

        # Run Ink (React-based) TUI
        def run_ink_tui
          require 'rhdl/hdl'

          puts "Starting RHDL Ink TUI..."
          puts '=' * 50
          puts

          # Create a simple demo circuit
          not_gate = RHDL::HDL::NotGate.new('inverter')
          dff = RHDL::HDL::DFlipFlop.new('register')
          counter = RHDL::HDL::Counter.new('counter', width: 8)

          RHDL::HDL::SimComponent.connect(dff.outputs[:q], not_gate.inputs[:a])
          RHDL::HDL::SimComponent.connect(not_gate.outputs[:y], dff.inputs[:d])

          # Create debug simulator
          sim = RHDL::HDL::DebugSimulator.new
          sim.add_component(not_gate)
          sim.add_component(dff)
          sim.add_component(counter)

          # Set initial values
          dff.inputs[:rst].set(0)
          dff.inputs[:en].set(1)
          counter.inputs[:rst].set(0)
          counter.inputs[:en].set(1)

          # Create and run Ink adapter
          require 'rhdl/tui/ink_adapter'
          adapter = RHDL::TUI::InkAdapter.new(sim)
          adapter.add_component(not_gate)
          adapter.add_component(dff)
          adapter.add_component(counter)
          adapter.run
        end

        # Run standard Ruby TUI
        def run_ruby_tui
          component_ref = options[:component]
          raise ArgumentError, "Component reference required" unless component_ref

          require 'rhdl/hdl'
          require 'rhdl/tui'
          require 'rhdl/debug'

          # Try to find component by short name first
          component = if Config.hdl_components.key?(component_ref)
                        Config.hdl_components[component_ref].call
                      else
                        # Try as a class reference
                        begin
                          component_class = component_ref.split('::').inject(Object) { |mod, name| mod.const_get(name) }
                          component_class.new(component_ref.split('::').last.downcase)
                        rescue NameError
                          raise ArgumentError, "Component not found: #{component_ref}\nUse 'rhdl tui --list' to see available components"
                        end
                      end

          # Create debug simulator
          simulator = RHDL::HDL::DebugSimulator.new

          # Create TUI
          tui = RHDL::HDL::SimulatorTUI.new(simulator)

          # Add component with signal options
          tui.add_component(component, signals: options[:signals])

          puts "Starting TUI for #{component.name}..."
          puts "Press 'h' for help, 'q' to quit"
          sleep 0.5

          # Run the TUI
          tui.run
        end

        # Ensure TUI dependencies are installed
        def ensure_tui_deps
          ensure_node_available

          node_modules = File.join(Config.tui_ink_dir, 'node_modules')
          unless Dir.exist?(node_modules)
            puts "Installing TUI dependencies..."
            Dir.chdir(Config.tui_ink_dir) { system('npm install --silent') }
          end
        end

        private

        def ensure_node_available
          unless command_available?('node')
            raise "Node.js is required but not installed.\n" \
                  "Please install Node.js (v18+) first:\n" \
                  "  - macOS: brew install node\n" \
                  "  - Ubuntu: sudo apt-get install nodejs npm\n" \
                  "  - Or download from: https://nodejs.org/"
          end
        end
      end
    end
  end
end
