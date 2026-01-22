# Behavior IR (intermediate representation for RTL codegen)
require_relative "codegen/ir/ir"
require_relative "codegen/ir/lower"
require_relative "codegen/ir/sim/ir_interpreter"
require_relative "codegen/ir/sim/ir_jit"
require_relative "codegen/ir/sim/ir_compiler"

# Verilog codegen
require_relative "codegen/verilog/verilog"

# CIRCT codegen (FIRRTL)
require_relative "codegen/circt/firrtl"

# Netlist codegen (gate-level synthesis)
require_relative "codegen/netlist/ir"
require_relative "codegen/netlist/primitives"
require_relative "codegen/netlist/toposort"
require_relative "codegen/netlist/lower"
require_relative "codegen/netlist/sim/netlist_interpreter"
require_relative "codegen/netlist/sim/netlist_jit"
require_relative "codegen/netlist/sim/netlist_compiler"

require 'fileutils'

module RHDL
  module Codegen
    class << self
      # Behavior Verilog codegen
      def verilog(component, top_name: nil)
        module_def = IR::Lower.new(component, top_name: top_name).build
        Verilog.generate(module_def)
      end
      alias_method :to_verilog, :verilog

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end

      # CIRCT FIRRTL codegen
      def circt(component, top_name: nil)
        module_def = IR::Lower.new(component, top_name: top_name).build
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
      def gate_level(components, backend: :interpreter, lanes: 64, name: 'design')
        ir = Netlist::Lower.from_components(components, name: name)
        case backend
        when :interpreter
          Netlist::NetlistInterpreterWrapper.new(ir, lanes: lanes)
        when :jit
          Netlist::NetlistJitWrapper.new(ir, lanes: lanes)
        when :compiler
          Netlist::NetlistCompilerWrapper.new(ir, lanes: lanes)
        else
          raise ArgumentError, "Unknown backend: #{backend}. Valid: :interpreter, :jit, :compiler"
        end
      end

      # Component discovery and batch codegen

      # Find all classes that are exportable (DSL or HDL with behavior blocks)
      def discover_components
        dsl_components = ObjectSpace.each_object(Class).select do |klass|
          klass.included_modules.include?(RHDL::DSL) && klass != RHDL::Component
        end

        # Also find HDL Component subclasses with behavior blocks
        hdl_components = ObjectSpace.each_object(Class).select do |klass|
          klass < RHDL::Sim::Component &&
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
    # IR module is now at top level in Codegen::IR, not nested in Verilog
    Lower = IR::Lower

    # Backwards compatibility: Behavior -> Verilog, Structure -> Netlist
    Behavior = Verilog
    Structure = Netlist
  end

  # Backwards compatibility alias
  Export = Codegen
end
