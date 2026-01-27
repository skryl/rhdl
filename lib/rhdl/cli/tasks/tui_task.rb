# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for launching TUI debugger
      class TuiTask < Task
        def run
          if options[:list]
            list_components
          else
            run_ruby_tui
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
          simulator = RHDL::Debug::DebugSimulator.new

          # Create TUI
          tui = RHDL::TUI::SimulatorTUI.new(simulator)

          # Add component with signal options
          tui.add_component(component, signals: options[:signals])

          puts "Starting TUI for #{component.name}..."
          puts "Press 'h' for help, 'q' to quit"
          sleep 0.5

          # Run the TUI
          tui.run
        end
      end
    end
  end
end
