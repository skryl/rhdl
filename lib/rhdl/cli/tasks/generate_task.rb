# frozen_string_literal: true

require_relative '../task'
require_relative '../config'
require 'set'

module RHDL
  module CLI
    module Tasks
      # Task for combined generate/clean/regenerate operations
      class GenerateTask < Task
        def run
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

          puts 'Cleaning native build artifacts...'
          NativeTask.new(clean: true).run
          puts

          clean_simulator_build_artifacts
          clean_web_artifacts
          clean_temp_artifacts

          puts
          puts "All generated files cleaned."
        end

        private

        def project_root
          @project_root ||= File.expand_path(options[:root] || Config.project_root)
        end

        def clean_simulator_build_artifacts
          puts 'Cleaning simulator build directories...'
          candidates = Set.new
          candidates.merge(Dir.glob(File.join(project_root, '.verilator_build*')))
          candidates.merge(Dir.glob(File.join(project_root, '.arcilator_build*')))
          candidates.merge(Dir.glob(File.join(project_root, '.hdl_build')))
          candidates.merge(Dir.glob(File.join(project_root, 'examples', '**', '.verilator_build*')))
          candidates.merge(Dir.glob(File.join(project_root, 'examples', '**', '.arcilator_build*')))
          candidates.merge(Dir.glob(File.join(project_root, 'examples', '**', '.hdl_build')))

          candidates.each do |path|
            next unless Dir.exist?(path)

            FileUtils.rm_rf(path)
            puts "  Cleaned: #{rel(path)}"
          end
        end

        def clean_web_artifacts
          puts 'Cleaning web artifacts...'

          %w[dist test-results].each do |child|
            path = File.join(project_root, 'web', child)
            next unless Dir.exist?(path)

            FileUtils.rm_rf(path)
            puts "  Cleaned: #{rel(path)}"
          end

          clean_web_build_dir(File.join(project_root, 'web', 'build'))
        end

        def clean_web_build_dir(build_root)
          return unless Dir.exist?(build_root)

          Dir.children(build_root).each do |entry|
            path = File.join(build_root, entry)
            if %w[arcilator verilator].include?(entry)
              clean_preserving_gitignore(path)
            else
              FileUtils.rm_rf(path)
              puts "  Cleaned: #{rel(path)}"
            end
          end
        end

        def clean_preserving_gitignore(dir)
          return unless Dir.exist?(dir)

          Dir.children(dir).each do |entry|
            next if entry == '.gitignore'

            path = File.join(dir, entry)
            FileUtils.rm_rf(path)
            puts "  Cleaned: #{rel(path)}"
          end
        end

        def clean_temp_artifacts
          puts 'Cleaning temporary directories...'
          %w[tmp .tmp].each do |name|
            path = File.join(project_root, name)
            next unless Dir.exist?(path)

            FileUtils.rm_rf(path)
            puts "  Cleaned: #{rel(path)}"
          end
        end

        def rel(path)
          path.delete_prefix("#{project_root}/")
        end
      end
    end
  end
end
