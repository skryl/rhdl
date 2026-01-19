# frozen_string_literal: true

require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for exporting HDL components to Verilog/VHDL
      class ExportTask < Task
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
            components = RHDL::Export.list_components

            components.each do |info|
              component = info[:class]
              relative_path = info[:relative_path]

              begin
                verilog_file = File.join(Config.verilog_dir, "#{relative_path}.v")
                ensure_dir(File.dirname(verilog_file))
                File.write(verilog_file, component.to_verilog)
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
                ensure_dir(File.dirname(verilog_file))
                File.write(verilog_file, component.to_verilog)
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

          case lang
          when "verilog"
            top_name = options[:top] || component_class.name.split("::").last.underscore
            output_path = File.join(out_dir, "#{top_name}.v")
            RHDL::Export.write_verilog(component_class, path: output_path, top_name: options[:top])
          when "vhdl"
            top_name = options[:top] || component_class.name.split("::").last.underscore
            output_path = File.join(out_dir, "#{top_name}.vhd")
            RHDL::Export.write_vhdl(component_class, path: output_path, top_name: options[:top])
          else
            raise ArgumentError, "Unknown language: #{lang}"
          end

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
      end
    end
  end
end
