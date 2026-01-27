# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for gate-level synthesis
      class GatesTask < Task
        def run
          if options[:clean]
            clean
          elsif options[:stats]
            show_stats
          elsif options[:simcpu]
            export_simcpu
          else
            export_all
          end
        end

        # Export all components to gate-level IR
        def export_all
          require 'rhdl/hdl'
          require 'rhdl/export'

          puts_header("RHDL Gate-Level Synthesis Export")

          ensure_dir(Config.gates_dir)
          exported_count = 0
          error_count = 0

          Config.gate_synth_components.each do |name, creator|
            begin
              component = creator.call

              subdir = File.dirname(name)
              ensure_dir(File.join(Config.gates_dir, subdir))

              ir = RHDL::Export::Structure::Lower.from_components([component], name: component.name)

              # Export to JSON
              json_file = File.join(Config.gates_dir, "#{name}.json")
              File.write(json_file, ir.to_json)

              # Create summary text file
              txt_file = File.join(Config.gates_dir, "#{name}.txt")
              File.write(txt_file, generate_summary(component, ir))

              puts "  [OK] #{name} (#{ir.gates.length} gates, #{ir.dffs.length} DFFs)"
              exported_count += 1
            rescue => e
              puts_error("#{name}: #{e.message}")
              error_count += 1
            end
          end

          puts
          puts '=' * 50
          puts "Exported: #{exported_count}/#{Config.gate_synth_components.size} components"
          puts "Errors: #{error_count}"
          puts "Output: #{Config.gates_dir}"
        end

        # Export SimCPU datapath components
        def export_simcpu
          require 'rhdl/hdl'
          require 'rhdl/export'

          puts_header("RHDL SimCPU Gate-Level Export")

          ensure_dir(File.join(Config.gates_dir, 'cpu'))

          begin
            pc = RHDL::HDL::ProgramCounter.new('pc', width: 16)
            acc = RHDL::HDL::Register.new('acc', width: 8)
            alu = RHDL::HDL::ALU.new('alu', width: 8)
            decoder = RHDL::HDL::CPU::InstructionDecoder.new('decoder')

            components = [
              ['cpu/pc', pc],
              ['cpu/acc', acc],
              ['cpu/alu', alu],
              ['cpu/decoder', decoder]
            ]

            total_gates = 0
            total_dffs = 0

            components.each do |name, component|
              ir = RHDL::Export::Structure::Lower.from_components([component], name: component.name)
              json_file = File.join(Config.gates_dir, "#{name}.json")
              File.write(json_file, ir.to_json)
              puts "  [OK] #{name}: #{ir.gates.length} gates, #{ir.dffs.length} DFFs"
              total_gates += ir.gates.length
              total_dffs += ir.dffs.length
            end

            puts
            puts "SimCPU Totals:"
            puts "  Total Gates: #{total_gates}"
            puts "  Total DFFs: #{total_dffs}"
            puts "  Output: #{File.join(Config.gates_dir, 'cpu')}"
          rescue => e
            puts_error(e.message)
          end
        end

        # Show gate-level synthesis statistics
        def show_stats
          require 'rhdl/hdl'
          require 'rhdl/export'

          puts_header("RHDL Gate-Level Synthesis Statistics")

          total_gates = 0
          total_dffs = 0
          component_stats = []

          Config.gate_synth_components.each do |name, creator|
            begin
              component = creator.call
              ir = RHDL::Export::Structure::Lower.from_components([component], name: component.name)
              component_stats << {
                name: name,
                gates: ir.gates.length,
                dffs: ir.dffs.length,
                nets: ir.net_count
              }
              total_gates += ir.gates.length
              total_dffs += ir.dffs.length
            rescue => e
              component_stats << { name: name, error: e.message }
            end
          end

          component_stats.sort_by! { |s| -(s[:gates] || 0) }

          puts "Components by Gate Count:"
          puts_separator
          component_stats.each do |s|
            if s[:error]
              puts "  #{s[:name]}: ERROR - #{s[:error]}"
            else
              puts "  #{s[:name]}: #{s[:gates]} gates, #{s[:dffs]} DFFs, #{s[:nets]} nets"
            end
          end

          puts
          puts '=' * 50
          puts "Total Components: #{Config.gate_synth_components.size}"
          puts "Total Gates: #{total_gates}"
          puts "Total DFFs: #{total_dffs}"
        end

        # Clean gate-level output
        def clean
          if Dir.exist?(Config.gates_dir)
            FileUtils.rm_rf(Config.gates_dir)
            puts "Cleaned: #{Config.gates_dir}"
          end
          puts "Gate-level files cleaned."
        end

        private

        def generate_summary(component, ir)
          summary = []
          summary << "Component: #{component.name}"
          summary << "Type: #{component.class.name}"
          summary << "Gates: #{ir.gates.length}"
          summary << "DFFs: #{ir.dffs.length}"
          summary << "Nets: #{ir.net_count}"
          summary << ""
          summary << "Inputs:"
          ir.inputs.each { |n, nets| summary << "  #{n}: #{nets.length} bits" }
          summary << ""
          summary << "Outputs:"
          ir.outputs.each { |n, nets| summary << "  #{n}: #{nets.length} bits" }
          summary << ""
          summary << "Gate Types:"
          gate_counts = ir.gates.group_by(&:type).transform_values(&:length)
          gate_counts.each { |type, count| summary << "  #{type}: #{count}" }
          summary.join("\n")
        end
      end
    end
  end
end
