# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for combined generate/clean/regenerate operations
      class GenerateTask < Task
        def run
          if dry_run?
            return dry_run_describe
          end

          case options[:action]
          when :clean
            clean_all
          when :regenerate
            clean_all
            puts
            generate_all
          else
            generate_all
          end
        end

        def dry_run_describe
          case options[:action]
          when :clean
            would :clean_all, description: "Clean all generated files (diagrams, verilog, gates)"
          when :regenerate
            would :regenerate_all, description: "Clean and regenerate all output files"
          else
            would :generate_all, description: "Generate all output files (diagrams, verilog)"
          end
          dry_run_output
        end

        # Generate all output files
        def generate_all
          puts "Generating all output files..."
          puts '=' * 50
          puts

          puts "Generating diagrams..."
          DiagramTask.new(all: true).run

          puts
          puts "Exporting HDL..."
          ExportTask.new(all: true).run

          puts
          puts '=' * 50
          puts "All output files generated."
        end

        # Clean all generated files
        def clean_all
          puts "Cleaning all generated files..."
          puts '=' * 50
          puts

          DiagramTask.new(clean: true).run
          puts

          ExportTask.new(clean: true).run
          puts

          GatesTask.new(clean: true).run

          puts
          puts "All generated files cleaned."
        end
      end
    end
  end
end
