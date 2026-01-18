# RHDL Component Exporter
# Exports all registered components to Verilog format

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

      # Find all classes that are exportable (DSL or HDL with behavior blocks)
      def discover_components
        dsl_components = ObjectSpace.each_object(Class).select do |klass|
          klass.included_modules.include?(RHDL::DSL) && klass != RHDL::Component
        end

        # Also find HDL SimComponent subclasses with behavior blocks
        hdl_components = ObjectSpace.each_object(Class).select do |klass|
          klass < RHDL::HDL::SimComponent &&
            klass.respond_to?(:behavior_defined?) &&
            klass.behavior_defined?
        end

        (dsl_components + hdl_components).uniq
      end

      # Export a single component to Verilog
      def to_verilog(component_class)
        component_class.to_verilog
      end

      # Export all registered components to Verilog
      def all_to_verilog
        discover_components.map { |c| [c, c.to_verilog] }.to_h
      end

      # Export specific components to Verilog
      def export_verilog(component_classes)
        Array(component_classes).map { |c| [c, c.to_verilog] }.to_h
      end

      # Export all discovered components to files in a directory
      def export_all_to_files(output_dir)
        FileUtils.mkdir_p(output_dir)

        results = { verilog: {} }
        components = discover_components

        components.each do |component|
          component_name = component.name.split('::').last.underscore

          verilog_file = File.join(output_dir, "#{component_name}.v")
          File.write(verilog_file, component.to_verilog)
          results[:verilog][component] = verilog_file
        end

        results
      end

      # Export specific components to files in a directory
      def export_to_files(component_classes, output_dir)
        FileUtils.mkdir_p(output_dir)

        results = { verilog: {} }

        Array(component_classes).each do |component|
          component_name = component.name.split('::').last.underscore

          verilog_file = File.join(output_dir, "#{component_name}.v")
          File.write(verilog_file, component.to_verilog)
          results[:verilog][component] = verilog_file
        end

        results
      end

      # List all exportable components with their names
      def list_components
        discover_components.map do |c|
          {
            class: c,
            name: c.name.split('::').last.underscore,
            relative_path: component_relative_path(c),
            ports: c._ports.size,
            signals: c._signals.size,
            generics: c.respond_to?(:_generics) ? c._generics.size : 0
          }
        end
      end

      # Compute relative path from component class name
      # e.g., RHDL::HDL::CPU::InstructionDecoder -> cpu/instruction_decoder
      def component_relative_path(component_class)
        parts = component_class.name.split('::')

        # Remove RHDL and HDL prefixes
        parts.shift if parts.first == 'RHDL'
        parts.shift if parts.first == 'HDL'

        # Convert all parts to snake_case and join with /
        parts.map(&:underscore).join('/')
      end
    end
  end
end
