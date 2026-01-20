# frozen_string_literal: true

# Codegen DSL for HDL Components
#
# This module provides methods for generating IR and HDL output from components:
# - to_ir: Generate intermediate representation
# - to_verilog: Generate Verilog code
# - to_circt/to_firrtl: Generate CIRCT FIRRTL code
#
# These methods work with the behavior, structure, and sequential DSLs to produce
# synthesizable HDL output.

require 'active_support/concern'
require 'active_support/core_ext/string/inflections'
require 'set'

module RHDL
  module DSL
    module Codegen
      extend ActiveSupport::Concern

      class_methods do
        # Generate Verilog from the component
        def to_verilog(top_name: nil)
          RHDL::Export::Verilog.generate(to_ir(top_name: top_name))
        end

        # Generate CIRCT FIRRTL from the component
        def to_circt(top_name: nil)
          RHDL::Export::CIRCT::FIRRTL.generate(to_ir(top_name: top_name))
        end
        alias_method :to_firrtl, :to_circt

        # Generate CIRCT FIRRTL for this component and all its sub-modules
        # Returns a single FIRRTL circuit with all module definitions
        # @param top_name [String] Optional name override for top module
        # @return [String] Complete FIRRTL with all module definitions
        def to_circt_hierarchy(top_name: nil)
          module_defs = []

          # Generate sub-modules first (in dependency order - leaves first)
          submodules = collect_submodule_classes
          submodules.each do |submod|
            module_defs << submod.to_ir
          end

          # Generate top-level module last
          top_ir = to_ir(top_name: top_name)
          module_defs << top_ir

          RHDL::Export::CIRCT::FIRRTL.generate_hierarchy(module_defs, top_name: top_ir.name)
        end
        alias_method :to_firrtl_hierarchy, :to_circt_hierarchy

        # Returns the Verilog module name for this component
        # Derived from the class's full module path, filtering out RHDL/HDL namespaces
        # Examples:
        #   RHDL::HDL::RAM => "ram"
        #   MOS6502::ALU => "mos6502_alu"
        #   RISCV::Decoder => "riscv_decoder"
        # @return [String] The module name used in generated Verilog
        def verilog_module_name
          parts = self.name.split('::')
          # Filter out RHDL and HDL namespace modules
          filtered = parts.reject { |p| %w[RHDL HDL].include?(p) }
          # Convert each part to snake_case and join with underscore
          filtered.map { |p| p.underscore }.join('_')
        end

        # Collect all unique sub-module classes used by this component (recursively)
        # @return [Array<Class>] Array of component classes
        def collect_submodule_classes(collected = Set.new)
          _instance_defs.each do |inst_def|
            component_class = inst_def[:component_class]
            next if collected.include?(component_class)

            collected.add(component_class)
            # Recursively collect from sub-modules if they have instances
            if component_class.respond_to?(:_instance_defs)
              component_class.collect_submodule_classes(collected)
            end
          end
          collected.to_a
        end

        # Generate Verilog for this component and all its sub-modules
        # Returns a single string with all module definitions
        # @param top_name [String] Optional name override for top module
        # @return [String] Complete Verilog with all module definitions
        def to_verilog_hierarchy(top_name: nil)
          parts = []

          # Generate sub-modules first (in dependency order - leaves first)
          submodules = collect_submodule_classes
          submodules.each do |submod|
            parts << submod.to_verilog
          end

          # Generate top-level module last
          parts << to_verilog(top_name: top_name)

          parts.join("\n\n")
        end

        # Generate IR ModuleDef from the component
        def to_ir(top_name: nil)
          name = top_name || verilog_module_name

          ports = _ports.map do |p|
            RHDL::Export::IR::Port.new(
              name: p.name,
              direction: p.direction,
              width: p.width,
              default: p.default
            )
          end

          # Build parameters hash from class-level parameter definitions
          # Convert Procs to their evaluated values using default values
          parameters = {}
          _parameter_defs.each do |param_name, default_val|
            if default_val.is_a?(Proc)
              # For class-level evaluation, use default parameter values
              # Create context with parameter defaults and evaluate
              eval_context = Object.new
              _parameter_defs.each do |k, v|
                next if v.is_a?(Proc)
                eval_context.instance_variable_set(:"@#{k}", v)
              end
              parameters[param_name] = eval_context.instance_exec(&default_val)
            else
              parameters[param_name] = default_val
            end
          end

          # Get behavior assigns first so we can identify which signals are assign-driven
          behavior_result = behavior_to_ir_assigns
          assigns = behavior_result[:assigns]

          # Identify signals driven by instance outputs (these must be wires, not regs)
          # A signal is instance-driven if it's the destination of a connection from [inst, port]
          instance_driven_signals = Set.new
          # Also generate assign statements for signal-to-signal connections
          signal_assigns = []
          _connection_defs.each do |conn|
            source, dest = conn[:source], conn[:dest]
            # If source is [inst_name, port_name], then dest is driven by an instance output
            if source.is_a?(Array) && source.length == 2 && dest.is_a?(Symbol)
              instance_driven_signals.add(dest)
            # If both are symbols, generate an assign statement (signal-to-signal connection)
            # port :source_signal => :dest_signal means dest = source
            elsif source.is_a?(Symbol) && dest.is_a?(Symbol)
              # Get widths from ports and signals
              source_width = find_signal_width(source)
              signal_assigns << RHDL::Export::IR::Assign.new(
                target: dest.to_s,
                expr: RHDL::Export::IR::Signal.new(name: source.to_s, width: source_width)
              )
            end
          end
          assigns = assigns + signal_assigns

          # Identify signals driven by continuous assigns (these must be wires, not regs)
          # In Verilog, 'reg' cannot be driven by 'assign' statements
          assign_driven_signals = Set.new
          assigns.each do |assign|
            assign_driven_signals.add(assign.target.to_sym)
          end

          # Split signals into regs (procedural) and nets (continuous assignment or instance-driven)
          regs = []
          instance_nets = []
          _signals.each do |s|
            if instance_driven_signals.include?(s.name) || assign_driven_signals.include?(s.name)
              instance_nets << RHDL::Export::IR::Net.new(name: s.name, width: s.width)
            else
              regs << RHDL::Export::IR::Reg.new(name: s.name, width: s.width)
            end
          end

          nets = behavior_result[:wires] + instance_nets

          # Generate instances from structure definitions
          instances = structure_to_ir_instances

          # Generate memory IR from Memory DSL if included
          memories = []
          write_ports = []
          if respond_to?(:_memories) && !_memories.empty?
            memory_ir = memory_dsl_to_ir
            memories = memory_ir[:memories]
            write_ports = memory_ir[:write_ports]
            assigns = assigns + memory_ir[:assigns]
          end

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: ports,
            nets: nets,
            regs: regs,
            assigns: assigns,
            processes: [],
            instances: instances,
            memories: memories,
            write_ports: write_ports,
            parameters: parameters
          )
        end

        # Generate IR from Memory DSL definitions
        def memory_dsl_to_ir
          memories = []
          assigns = []
          write_ports = []

          mem_defs = _memories

          # Generate Memory IR nodes
          mem_defs.each do |mem_name, mem_def|
            memories << RHDL::Export::IR::Memory.new(
              name: mem_name.to_s,
              depth: mem_def.depth,
              width: mem_def.width,
              read_ports: [],
              write_ports: []
            )
          end

          # Generate async read assigns
          if respond_to?(:_async_reads)
            _async_reads.each do |read_def|
              mem_def = mem_defs[read_def.memory]
              addr_width = mem_def&.addr_width || 8
              data_width = mem_def&.width || 8

              read_expr = RHDL::Export::IR::MemoryRead.new(
                memory: read_def.memory,
                addr: RHDL::Export::IR::Signal.new(name: read_def.addr, width: addr_width),
                width: data_width
              )

              # Wrap in mux if enable is specified
              if read_def.enable
                read_expr = RHDL::Export::IR::Mux.new(
                  condition: RHDL::Export::IR::Signal.new(name: read_def.enable, width: 1),
                  when_true: read_expr,
                  when_false: RHDL::Export::IR::Literal.new(value: 0, width: data_width),
                  width: data_width
                )
              end

              assigns << RHDL::Export::IR::Assign.new(target: read_def.output, expr: read_expr)
            end
          end

          # Generate sync write ports
          if respond_to?(:_sync_writes)
            _sync_writes.each do |write_def|
              mem_def = mem_defs[write_def.memory]
              addr_width = mem_def&.addr_width || 8
              data_width = mem_def&.width || 8

              write_ports << RHDL::Export::IR::MemoryWritePort.new(
                memory: write_def.memory,
                clock: write_def.clock,
                addr: RHDL::Export::IR::Signal.new(name: write_def.addr, width: addr_width),
                data: RHDL::Export::IR::Signal.new(name: write_def.data, width: data_width),
                enable: RHDL::Export::IR::Signal.new(name: write_def.enable, width: 1)
              )
            end
          end

          { memories: memories, assigns: assigns, write_ports: write_ports }
        end

        # Generate IR instances from structure definitions
        def structure_to_ir_instances
          _instance_defs.map do |inst_def|
            component_class = inst_def[:component_class]
            # Build a map of port names to directions from the component class
            port_directions = {}
            if component_class.respond_to?(:_port_defs)
              component_class._port_defs.each do |port_def|
                port_directions[port_def[:name]] = port_def[:direction]
              end
            end

            connections = inst_def[:connections].map do |port_name, signal|
              direction = port_directions[port_name] || :in
              RHDL::Export::IR::PortConnection.new(
                port_name: port_name,
                signal: signal.to_s,
                direction: direction
              )
            end

            RHDL::Export::IR::Instance.new(
              name: inst_def[:name].to_s,
              module_name: inst_def[:module_name],
              connections: connections,
              parameters: inst_def[:parameters]
            )
          end
        end

        # Find the width of a signal by checking ports and internal signals
        def find_signal_width(signal_name)
          # Check ports first
          port = _ports.find { |p| p.name == signal_name }
          return port.width if port

          # Check internal signals
          sig = _signals.find { |s| s.name == signal_name }
          return sig.width if sig

          # Default to 1 if not found
          1
        end

        # Generate IR assigns and wire declarations from the behavior block
        # Used by the export/lowering system for HDL generation
        def behavior_to_ir_assigns
          return { assigns: [], wires: [] } unless behavior_defined?

          ctx = RHDL::Synth::Context.new(self)
          ctx.evaluate(&@_behavior_block.block)
          {
            assigns: ctx.to_ir_assigns,
            wires: ctx.wire_declarations
          }
        end
      end
    end
  end
end
