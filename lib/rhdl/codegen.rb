# Native IR simulation backends
require_relative "sim/native/ir/simulator"

# Verilog simulation backend utilities
require_relative "codegen/verilog/sim/verilog_simulator"
require_relative "codegen/source/source"
require_relative "codegen/schematic/schematic"

# CIRCT codegen (HW/Comb/Seq MLIR + compatibility aliases)
require_relative "codegen/circt/ir"
require_relative "codegen/circt/mlir"
require_relative "codegen/circt/import"
require_relative "codegen/circt/raise"
require_relative "codegen/circt/runtime_json"
require_relative "codegen/circt/tooling"
require_relative "codegen/circt/firrtl"

# Netlist codegen (gate-level synthesis)
require_relative "codegen/netlist/ir"
require_relative "codegen/netlist/primitives"
require_relative "codegen/netlist/toposort"
require_relative "codegen/netlist/lower"
require_relative "sim/native/netlist/simulator"

require 'fileutils'
require 'tmpdir'

module RHDL
  module Codegen
    class << self
      # Behavior Verilog codegen
      def verilog(component, top_name: nil)
        verilog_via_circt(component, top_name: top_name)
      end
      alias_method :to_verilog, :verilog

      def write_verilog(component, path:, top_name: nil)
        File.write(path, verilog(component, top_name: top_name))
      end

      def write_verilog_via_circt(component, path:, top_name: nil,
                                  tool: CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL, extra_args: [])
        File.write(
          path,
          verilog_via_circt(component, top_name: top_name, tool: tool, extra_args: extra_args)
        )
      end

      # Compatibility aliases that now return CIRCT MLIR.
      def circt(component, top_name: nil)
        mlir(component, top_name: top_name)
      end
      alias_method :to_circt, :circt

      # Compatibility aliases that now return CIRCT MLIR.
      def firrtl(component, top_name: nil)
        mlir(component, top_name: top_name)
      end
      alias_method :to_firrtl, :firrtl

      # CIRCT MLIR codegen (HW/Comb/Seq).
      def mlir(component, top_name: nil)
        component.to_ir(top_name: top_name)
      end
      alias_method :to_mlir, :mlir

      # Export CIRCT MLIR text to Verilog using external CIRCT tooling.
      def verilog_from_mlir(mlir_text, tool: CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL, extra_args: [])
        tmpdir = Dir.mktmpdir('rhdl_circt_verilog')
        mlir_path = File.join(tmpdir, 'input.mlir')
        out_path = File.join(tmpdir, 'output.v')
        File.write(mlir_path, mlir_text)

        result = CIRCT::Tooling.circt_mlir_to_verilog(
          mlir_path: mlir_path,
          out_path: out_path,
          tool: tool,
          extra_args: extra_args
        )

        unless result[:success]
          raise RuntimeError,
                "CIRCT MLIR->Verilog conversion failed with '#{tool}'.\nCommand: #{result[:command]}\n#{result[:stderr]}"
        end

        normalize_verilog_text(File.read(out_path))
      ensure
        FileUtils.rm_rf(tmpdir) if tmpdir && Dir.exist?(tmpdir)
      end
      alias_method :to_verilog_from_mlir, :verilog_from_mlir

      # Export component via CIRCT path (RHDL DSL -> CIRCT MLIR -> external Verilog).
      def verilog_via_circt(component, top_name: nil, tool: CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL, extra_args: [])
        verilog_from_mlir(mlir_for_verilog(component, top_name: top_name), tool: tool, extra_args: extra_args)
      end
      alias_method :to_verilog_via_circt, :verilog_via_circt

      def mlir_for_verilog(component, top_name:)
        if component.respond_to?(:to_mlir_hierarchy)
          component.to_mlir_hierarchy(top_name: top_name)
        elsif component.respond_to?(:to_ir)
          component.to_ir(top_name: top_name)
        elsif component.respond_to?(:to_circt_nodes)
          CIRCT::MLIR.generate(component.to_circt_nodes(top_name: top_name))
        else
          raise ArgumentError, "Component #{component.inspect} does not support CIRCT MLIR generation"
        end
      end

      def normalize_verilog_text(text)
        trailing_newline = text.end_with?("\n")
        normalized = text.lines.map do |line|
          line
            .tr("\t", ' ')
            .gsub(/ +/, ' ')
            .rstrip
        end.join("\n")
        trailing_newline ? "#{normalized}\n" : normalized
      end

      # Parse CIRCT MLIR into CIRCT node IR.
      def import_circt_mlir(text, strict: false, top: nil, extern_modules: [])
        CIRCT::Import.from_mlir(text, strict: strict, top: top, extern_modules: extern_modules)
      end

      # Raise CIRCT nodes/MLIR into in-memory Ruby DSL source strings.
      def raise_circt_sources(nodes_or_mlir, top: nil, strict: false)
        CIRCT::Raise.to_sources(nodes_or_mlir, top: top, strict: strict)
      end

      # Raise CIRCT nodes/MLIR into Ruby DSL source files.
      def raise_circt(nodes_or_mlir, out_dir:, top: nil, strict: false, format: false)
        CIRCT::Raise.to_dsl(nodes_or_mlir, out_dir: out_dir, top: top, strict: strict, format: format)
      end

      # Raise CIRCT nodes/MLIR into loaded Ruby DSL component classes.
      def raise_circt_components(nodes_or_mlir, namespace: Module.new, top: nil, strict: false)
        CIRCT::Raise.to_components(nodes_or_mlir, namespace: namespace, top: top, strict: strict)
      end

      def write_circt(component, path:, top_name: nil)
        File.write(path, circt(component, top_name: top_name))
      end

      def write_firrtl(component, path:, top_name: nil)
        File.write(path, firrtl(component, top_name: top_name))
      end

      # Structure gate-level codegen
      def gate_level(components, backend: :interpreter, lanes: 64, name: 'design')
        ir = Netlist::Lower.from_components(components, name: name)
        simulator_backend = case backend
                            when :interpreter, :interpret then :interpreter
                            when :jit then :jit
                            when :compiler, :compile then :compiler
                            else
                              raise ArgumentError, "Unknown backend: #{backend}. Valid: :interpreter, :jit, :compiler"
                            end
        Sim::Native::Netlist::Simulator.new(
          ir,
          backend: simulator_backend,
          lanes: lanes
        )
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

    # Backwards compatibility: Behavior -> Verilog, Structure -> Netlist
    Behavior = Verilog
    Structure = Netlist
  end

  # Backwards compatibility alias
  Export = Codegen
  CIRCT = Codegen::CIRCT unless const_defined?(:CIRCT)
end
