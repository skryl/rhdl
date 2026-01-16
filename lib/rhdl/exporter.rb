# RHDL Component Exporter
# Exports all registered components to VHDL and Verilog formats

require 'fileutils'

module RHDL
  module Exporter
    class << self
      # Registry of components that can be exported
      def components
        @components ||= []
      end

      # Register a component for export
      def register(component_class)
        components << component_class unless components.include?(component_class)
      end

      # Find all classes that include RHDL::DSL
      def discover_components
        ObjectSpace.each_object(Class).select do |klass|
          klass.included_modules.include?(RHDL::DSL) && klass != RHDL::Component
        end
      end

      # Export a single component to VHDL
      def to_vhdl(component_class)
        component_class.to_vhdl
      end

      # Export a single component to Verilog
      def to_verilog(component_class)
        component_class.to_verilog
      end

      # Export all registered components to VHDL
      def all_to_vhdl
        discover_components.map { |c| [c, c.to_vhdl] }.to_h
      end

      # Export all registered components to Verilog
      def all_to_verilog
        discover_components.map { |c| [c, c.to_verilog] }.to_h
      end

      # Export specific components to VHDL
      def export_vhdl(component_classes)
        Array(component_classes).map { |c| [c, c.to_vhdl] }.to_h
      end

      # Export specific components to Verilog
      def export_verilog(component_classes)
        Array(component_classes).map { |c| [c, c.to_verilog] }.to_h
      end

      # Export all discovered components to files in a directory
      def export_all_to_files(output_dir, format: :both)
        FileUtils.mkdir_p(output_dir)

        results = { vhdl: {}, verilog: {} }
        components = discover_components

        components.each do |component|
          component_name = component.name.split('::').last.underscore

          if format == :vhdl || format == :both
            vhdl_file = File.join(output_dir, "#{component_name}.vhd")
            File.write(vhdl_file, component.to_vhdl)
            results[:vhdl][component] = vhdl_file
          end

          if format == :verilog || format == :both
            verilog_file = File.join(output_dir, "#{component_name}.v")
            File.write(verilog_file, component.to_verilog)
            results[:verilog][component] = verilog_file
          end
        end

        results
      end

      # Export specific components to files in a directory
      def export_to_files(component_classes, output_dir, format: :both)
        FileUtils.mkdir_p(output_dir)

        results = { vhdl: {}, verilog: {} }

        Array(component_classes).each do |component|
          component_name = component.name.split('::').last.underscore

          if format == :vhdl || format == :both
            vhdl_file = File.join(output_dir, "#{component_name}.vhd")
            File.write(vhdl_file, component.to_vhdl)
            results[:vhdl][component] = vhdl_file
          end

          if format == :verilog || format == :both
            verilog_file = File.join(output_dir, "#{component_name}.v")
            File.write(verilog_file, component.to_verilog)
            results[:verilog][component] = verilog_file
          end
        end

        results
      end

      # List all exportable components with their names
      def list_components
        discover_components.map do |c|
          {
            class: c,
            name: c.name.split('::').last.underscore,
            ports: c._ports.size,
            signals: c._signals.size,
            generics: c._generics.size
          }
        end
      end
    end
  end
end
