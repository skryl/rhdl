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

        # Generate flattened IR for simulation (inlines all subcomponent logic)
        # This produces a single flat IR with no instances - suitable for RTL simulation
        def to_flat_ir(top_name: nil, prefix: '')
          name = top_name || verilog_module_name

          all_ports = []
          all_nets = []
          all_regs = []
          all_assigns = []
          all_processes = []
          all_memories = []

          # Get this component's IR
          ir = to_ir(top_name: name)

          # Add top-level ports (only for the root component, not prefixed subcomponents)
          if prefix.empty?
            all_ports = ir.ports
          end

          # Add this component's nets and regs with prefix
          ir.nets.each do |net|
            prefixed_name = prefix.empty? ? net.name : :"#{prefix}__#{net.name}"
            all_nets << RHDL::Export::IR::Net.new(name: prefixed_name, width: net.width)
          end

          ir.regs.each do |reg|
            prefixed_name = prefix.empty? ? reg.name : :"#{prefix}__#{reg.name}"
            all_regs << RHDL::Export::IR::Reg.new(name: prefixed_name, width: reg.width, reset_value: reg.reset_value)
          end

          # Add this component's assigns with prefixed signal names
          ir.assigns.each do |assign|
            prefixed_assign = prefix_assign(assign, prefix)
            all_assigns << prefixed_assign
          end

          # Add this component's processes with prefixed signal names
          ir.processes.each do |process|
            prefixed_process = prefix_process(process, prefix)
            all_processes << prefixed_process
          end

          # Add this component's memories with prefix
          ir.memories.each do |mem|
            prefixed_name = prefix.empty? ? mem.name : "#{prefix}__#{mem.name}"
            all_memories << RHDL::Export::IR::Memory.new(
              name: prefixed_name,
              depth: mem.depth,
              width: mem.width,
              read_ports: mem.read_ports,
              write_ports: mem.write_ports,
              initial_data: mem.initial_data
            )
          end

          # Recursively flatten each instance
          _instance_defs.each do |inst_def|
            inst_name = inst_def[:name]
            component_class = inst_def[:component_class]
            inst_prefix = prefix.empty? ? inst_name.to_s : "#{prefix}__#{inst_name}"

            # Get flattened IR from subcomponent
            if component_class.respond_to?(:to_flat_ir)
              sub_ir = component_class.to_flat_ir(prefix: inst_prefix)

              # Merge subcomponent's flattened IR
              all_nets.concat(sub_ir.nets)
              all_regs.concat(sub_ir.regs)
              all_assigns.concat(sub_ir.assigns)
              all_processes.concat(sub_ir.processes)
              all_memories.concat(sub_ir.memories) if sub_ir.memories

              # Create assignments for port connections
              inst_def[:connections].each do |port_name, parent_signal|
                # Find port direction
                port_def = component_class._port_defs.find { |p| p[:name] == port_name }
                direction = port_def ? port_def[:direction] : :in
                port_width = port_def ? port_def[:width] : 1

                child_signal = "#{inst_prefix}__#{port_name}"
                parent_sig = prefix.empty? ? parent_signal.to_s : "#{prefix}__#{parent_signal}"

                if direction == :in
                  # Input: parent drives child
                  all_assigns << RHDL::Export::IR::Assign.new(
                    target: child_signal,
                    expr: RHDL::Export::IR::Signal.new(name: parent_sig, width: port_width)
                  )
                else
                  # Output: child drives parent
                  all_assigns << RHDL::Export::IR::Assign.new(
                    target: parent_sig,
                    expr: RHDL::Export::IR::Signal.new(name: child_signal, width: port_width)
                  )
                end

                # Add net for child port signal if not already present
                unless all_nets.any? { |n| n.name.to_s == child_signal }
                  all_nets << RHDL::Export::IR::Net.new(name: child_signal.to_sym, width: port_width)
                end
              end
            end
          end

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: all_ports,
            nets: all_nets,
            regs: all_regs,
            assigns: all_assigns,
            processes: all_processes,
            instances: [],  # Flattened - no instances
            memories: all_memories,
            write_ports: ir.write_ports,
            parameters: ir.parameters
          )
        end

        # Prefix all signal references in an assign
        def prefix_assign(assign, prefix)
          return assign if prefix.empty?

          RHDL::Export::IR::Assign.new(
            target: "#{prefix}__#{assign.target}",
            expr: prefix_expr(assign.expr, prefix)
          )
        end

        # Prefix all signal references in an expression
        def prefix_expr(expr, prefix)
          return expr if prefix.empty?

          case expr
          when RHDL::Export::IR::Signal
            RHDL::Export::IR::Signal.new(name: "#{prefix}__#{expr.name}", width: expr.width)
          when RHDL::Export::IR::Literal
            expr
          when RHDL::Export::IR::BinaryOp
            RHDL::Export::IR::BinaryOp.new(
              op: expr.op,
              left: prefix_expr(expr.left, prefix),
              right: prefix_expr(expr.right, prefix),
              width: expr.width
            )
          when RHDL::Export::IR::UnaryOp
            RHDL::Export::IR::UnaryOp.new(
              op: expr.op,
              operand: prefix_expr(expr.operand, prefix),
              width: expr.width
            )
          when RHDL::Export::IR::Mux
            RHDL::Export::IR::Mux.new(
              condition: prefix_expr(expr.condition, prefix),
              when_true: prefix_expr(expr.when_true, prefix),
              when_false: prefix_expr(expr.when_false, prefix),
              width: expr.width
            )
          when RHDL::Export::IR::Slice
            RHDL::Export::IR::Slice.new(
              base: prefix_expr(expr.base, prefix),
              range: expr.range,
              width: expr.width
            )
          when RHDL::Export::IR::Concat
            RHDL::Export::IR::Concat.new(
              parts: expr.parts.map { |p| prefix_expr(p, prefix) },
              width: expr.width
            )
          when RHDL::Export::IR::Resize
            RHDL::Export::IR::Resize.new(
              expr: prefix_expr(expr.expr, prefix),
              width: expr.width
            )
          when RHDL::Export::IR::Case
            RHDL::Export::IR::Case.new(
              selector: prefix_expr(expr.selector, prefix),
              cases: expr.cases.transform_values { |v| prefix_expr(v, prefix) },
              default: expr.default ? prefix_expr(expr.default, prefix) : nil,
              width: expr.width
            )
          when RHDL::Export::IR::MemoryRead
            RHDL::Export::IR::MemoryRead.new(
              memory: "#{prefix}__#{expr.memory}",
              addr: prefix_expr(expr.addr, prefix),
              width: expr.width
            )
          else
            expr
          end
        end

        # Prefix all signal references in a process
        def prefix_process(process, prefix)
          return process if prefix.empty?

          RHDL::Export::IR::Process.new(
            name: :"#{prefix}__#{process.name}",
            statements: process.statements.map { |s| prefix_statement(s, prefix) },
            clocked: process.clocked,
            clock: process.clock ? "#{prefix}__#{process.clock}" : nil
          )
        end

        # Prefix all signal references in a statement
        def prefix_statement(stmt, prefix)
          case stmt
          when RHDL::Export::IR::SeqAssign
            RHDL::Export::IR::SeqAssign.new(
              target: "#{prefix}__#{stmt.target}",
              expr: prefix_expr(stmt.expr, prefix)
            )
          when RHDL::Export::IR::If
            RHDL::Export::IR::If.new(
              condition: prefix_expr(stmt.condition, prefix),
              then_statements: stmt.then_statements&.map { |s| prefix_statement(s, prefix) },
              else_statements: stmt.else_statements&.map { |s| prefix_statement(s, prefix) }
            )
          else
            stmt
          end
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
              write_ports: [],
              initial_data: mem_def.initial_values
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
              # For output ports, use intermediate wire name instead of parent signal
              # This prevents BLKANDNBLK errors where output is driven by both
              # instance port and assign statement
              signal_name = if direction == :out
                              "#{inst_def[:name]}__#{port_name}"
                            else
                              signal.to_s
                            end
              RHDL::Export::IR::PortConnection.new(
                port_name: port_name,
                signal: signal_name,
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
