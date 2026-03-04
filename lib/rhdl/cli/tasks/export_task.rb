# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for exporting HDL components to Verilog
      class ExportTask < Task
        CIRCT_TOOLING_BACKEND = 'circt_tooling'
        VALID_BACKENDS = [CIRCT_TOOLING_BACKEND].freeze

        def run
          if options[:clean]
            clean
          elsif options[:all]
            export_all
          else
            export_single
          end
        end

        # Export all components
        def export_all
          require 'rhdl'

          ensure_dir(Config.verilog_dir)
          exported_count = 0

          # Export lib components
          if %w[all lib].include?(options[:scope] || 'all')
            puts "Exporting lib/ components..."
            components = RHDL::Codegen.list_components

            components.each do |info|
              component = info[:class]
              relative_path = info[:relative_path]

              begin
                verilog_file = File.join(Config.verilog_dir, "#{relative_path}.v")
                write_component_verilog(component, verilog_file)
                puts_ok(component.name)
                exported_count += 1
              rescue => e
                puts_error("#{component.name}: #{e.message}")
              end
            end
          end

          # Export example components
          if %w[all examples].include?(options[:scope] || 'all')
            puts "\nExporting examples/ components..."

            Config::EXAMPLE_COMPONENTS.each do |relative_path, (require_path, class_name)|
              begin
                require File.join(Config.project_root, require_path)
                component = class_name.split('::').inject(Object) { |o, c| o.const_get(c) }

                verilog_file = File.join(Config.verilog_dir, "#{relative_path}.v")
                write_component_verilog(component, verilog_file)
                puts_ok(class_name)
                exported_count += 1
              rescue => e
                puts_error("#{class_name}: #{e.message}")
              end
            end
          end

          puts "\nExported #{exported_count} components to: #{Config.verilog_dir}"
        end

        # Export a single component
        def export_single
          component_ref = options[:component]
          lang = options[:lang]
          out_dir = options[:out]

          raise ArgumentError, "Component reference required" unless component_ref
          raise ArgumentError, "Language (--lang) required" unless lang
          raise ArgumentError, "Output directory (--out) required" unless out_dir

          require 'rhdl'

          component_class = component_ref.split("::").inject(Object) { |mod, name| mod.const_get(name) }
          ensure_dir(out_dir)

          unless lang == "verilog"
            raise ArgumentError, "Unknown language: #{lang}. Only 'verilog' is supported."
          end

          top_name = options[:top] || component_class.name.split("::").last.underscore
          output_path = File.join(out_dir, "#{top_name}.v")
          write_component_verilog(component_class, output_path, top_name: options[:top])

          puts "Wrote #{lang} to #{out_dir}"
        end

        # Clean all generated HDL files
        def clean
          Dir.glob(File.join(Config.verilog_dir, '**', '*.v')).each { |f| FileUtils.rm_f(f) }
          Dir.glob(File.join(Config.verilog_dir, '**', '*')).sort.reverse.each do |d|
            FileUtils.rmdir(d) if File.directory?(d) && Dir.empty?(d)
          end
          puts "Cleaned: #{Config.verilog_dir}"
        end

        private

        def write_component_verilog(component_class, path, top_name: nil)
          verilog = generate_component_verilog(component_class, top_name: top_name)
          ensure_dir(File.dirname(path))
          File.write(path, verilog)
        end

        def generate_component_verilog(component_class, top_name: nil)
          unless export_backend == CIRCT_TOOLING_BACKEND
            raise ArgumentError,
                  "Unknown export backend: #{export_backend.inspect}. Expected one of: #{VALID_BACKENDS.join(', ')}"
          end

          RHDL::Codegen.verilog_via_circt(
            component_class,
            top_name: top_name,
            tool: export_tool,
            extra_args: export_tool_args
          )
        end

        def export_backend
          value = options[:backend]
          value.nil? || value.to_s.strip.empty? ? CIRCT_TOOLING_BACKEND : value.to_s
        end

        def export_tool
          options[:tool] || RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL
        end

        def export_tool_args
          Array(options[:tool_args])
        end
      end
    end
  end
end
