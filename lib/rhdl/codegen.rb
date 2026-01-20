# Behavior codegen (RTL/Verilog)
require_relative "codegen/behavior/ir"
require_relative "codegen/behavior/lower"
require_relative "codegen/behavior/verilog"

# CIRCT codegen (FIRRTL)
require_relative "codegen/circt/firrtl"

# Structure codegen (gate-level synthesis)
require_relative "codegen/structure/ir"
require_relative "codegen/structure/primitives"
require_relative "codegen/structure/toposort"
require_relative "codegen/structure/lower"
require_relative "codegen/structure/sim_cpu"
require_relative "codegen/structure/sim_gpu"

require 'fileutils'

module RHDL
  module Codegen
    class << self
      # Behavior Verilog codegen
      def verilog(component, top_name: nil)
        module_def = Behavior::Lower.new(component, top_name: top_name).build
        Behavior::Verilog.generate(module_def)
      end
      alias_method :to_verilog, :verilog

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end

      # CIRCT FIRRTL codegen
      def circt(component, top_name: nil)
        module_def = Behavior::Lower.new(component, top_name: top_name).build
        CIRCT::FIRRTL.generate(module_def)
      end
      alias_method :to_circt, :circt
      alias_method :firrtl, :circt
      alias_method :to_firrtl, :circt

      def write_circt(component, path:, top_name: nil)
        File.write(path, circt(component, top_name: top_name))
      end
      alias_method :write_firrtl, :write_circt

      # Structure gate-level codegen
      def gate_level(components, backend: :cpu, lanes: 64, name: 'design')
        ir = Structure::Lower.from_components(components, name: name)
        case backend
        when :cpu
          Structure::SimCPU.new(ir, lanes: lanes)
        when :gpu
          Structure::SimGPU.new(ir, lanes: lanes)
        else
          raise ArgumentError, "Unknown backend: #{backend}"
        end
      end

      # Component discovery and batch codegen

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

      # Export all discovered components to Verilog
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
      def component_relative_path(component_class)
        parts = component_class.name.split('::')
        parts.shift if parts.first == 'RHDL'
        parts.shift if parts.first == 'HDL'
        parts.map(&:underscore).join('/')
      end
    end

    # Backwards compatibility aliases for old namespace
    IR = Behavior::IR
    Verilog = Behavior::Verilog
    Lower = Behavior::Lower
  end

  # Backwards compatibility alias
  Export = Codegen
end
