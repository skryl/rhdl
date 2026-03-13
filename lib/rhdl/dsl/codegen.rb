# frozen_string_literal: true

# Codegen DSL for HDL Components
#
# This module provides methods for generating CIRCT/HDL output from components:
# - to_ir: Generate CIRCT MLIR (hw/comb/seq)
# - to_verilog: Generate Verilog via CIRCT MLIR tooling
# - to_circt: Generate CIRCT MLIR (hw/comb/seq)
# - to_firrtl: Generate FIRRTL text from CIRCT IR
#
# These methods work with the behavior, structure, and sequential DSLs to produce
# synthesizable HDL output.

require 'rhdl/support/concern'
require 'rhdl/support/inflections'
require 'set'

module RHDL
  module DSL
    module Codegen
      extend RHDL::Support::Concern

      class_methods do
        # Generate Verilog from the component via CIRCT tooling.
        def to_verilog(top_name: nil)
          to_verilog_via_circt(top_name: top_name)
        end

        # Generate Verilog through CIRCT tooling (DSL -> MLIR -> external export).
        def to_verilog_via_circt(top_name: nil, tool: RHDL::Codegen::CIRCT::Tooling::DEFAULT_VERILOG_EXPORT_TOOL, extra_args: [])
          RHDL::Codegen.verilog_via_circt(
            self,
            top_name: top_name,
            tool: tool,
            extra_args: extra_args
          )
        end

        # Export this component's Ruby source metadata/content
        def to_source(relative_to: nil)
          RHDL::Codegen::Source.component_entry(self, relative_to: relative_to)
        end

        # Export schematic bundle for this component hierarchy
        def to_schematic(sim_ir: nil, runner: nil)
          RHDL::Codegen::Schematic.bundle(
            top_class: self,
            sim_ir: (sim_ir || to_flat_circt_nodes),
            runner: runner
          )
        end

        # Compatibility alias that returns CIRCT MLIR.
        def to_circt(top_name: nil)
          to_ir(top_name: top_name)
        end

        # Explicit MLIR alias that resolves after to_ir definition.
        def to_mlir(top_name: nil, parameters: {})
          to_ir(top_name: top_name, parameters: parameters)
        end

        # Generate FIRRTL text from CIRCT IR for a single module.
        def to_firrtl(top_name: nil)
          RHDL::Codegen::CIRCT::FIRRTL.generate(
            to_circt_nodes(top_name: top_name)
          )
        end

        # Generate CIRCT MLIR for this component hierarchy.
        def to_circt_hierarchy(top_name: nil)
          to_mlir_hierarchy(top_name: top_name)
        end

        # IR-named hierarchy alias to match CIRCT hierarchy export.
        def to_ir_hierarchy(top_name: nil)
          to_circt_hierarchy(top_name: top_name)
        end

        # Backward-compatible misspelling retained by request.
        alias_method :to_ir_heirarchy, :to_ir_hierarchy

        # Generate FIRRTL text for this component hierarchy.
        def to_firrtl_hierarchy(top_name: nil)
          modules = collect_submodule_specs.map do |component_class, parameters|
            component_class.to_circt_nodes(parameters: parameters || {})
          end
          modules << to_circt_nodes(top_name: top_name)
          circuit_name = top_name || verilog_module_name
          RHDL::Codegen::CIRCT::FIRRTL.generate_hierarchy(modules, top_name: circuit_name)
        end

        # Generate CIRCT MLIR for this component hierarchy.
        def to_mlir_hierarchy(top_name: nil)
          modules = collect_submodule_specs.map do |component_class, parameters|
            component_class.to_circt_nodes(parameters: parameters || {})
          end
          modules << to_circt_nodes(top_name: top_name)
          RHDL::Codegen::CIRCT::MLIR.generate(RHDL::Codegen::CIRCT::IR::Package.new(modules: modules))
        end

        # Returns the Verilog module name for this component
        # Derived from the class's full module path, filtering out RHDL/HDL/Examples namespaces
        # Examples:
        #   RHDL::HDL::RAM => "ram"
        #   RHDL::Examples::MOS6502::ALU => "mos6502_alu"
        #   RHDL::Examples::RISCV::Decoder => "riscv_decoder"
        # @return [String] The module name used in generated Verilog
        def verilog_module_name
          parts = self.name.split('::')
          # Filter out RHDL, HDL, and Examples namespace modules
          filtered = parts.reject { |p| %w[RHDL HDL Examples].include?(p) }
          # Convert each part to snake_case and join with underscore
          filtered.map { |p| p.underscore }.join('_')
        end

        # Collect all unique sub-module classes used by this component (recursively)
        # @return [Array<Class>] Array of component classes
        def collect_submodule_classes(collected = Set.new)
          return collected.to_a unless respond_to?(:_instance_defs)

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

        # Collect unique sub-module classes with representative parameter overrides.
        # If a submodule is instantiated multiple times, first-seen parameters win.
        def collect_submodule_specs(collected = {})
          return collected unless respond_to?(:_instance_defs)

          _instance_defs.each do |inst_def|
            component_class = inst_def[:component_class]
            collected[component_class] ||= (inst_def[:parameters] || {})

            if component_class.respond_to?(:collect_submodule_specs)
              component_class.collect_submodule_specs(collected)
            end
          end

          collected
        end

        # Generate Verilog for this component and all its sub-modules
        # Returns a single string with all module definitions
        # @param top_name [String] Optional name override for top module
        # @return [String] Complete Verilog with all module definitions
        def to_verilog_hierarchy(top_name: nil)
          # `to_verilog` already exports hierarchical MLIR through CIRCT tooling.
          # Re-invoking `to_verilog` on each submodule duplicates module definitions.
          to_verilog(top_name: top_name)
        end

        # Generate flattened CIRCT nodes for simulation/runtime export.
        def to_flat_circt_nodes(top_name: nil, prefix: '', parameters: {})
          build_flat_circt_module(top_name: top_name, prefix: prefix, parameters: parameters)
        end

        def to_circt_runtime_json(top_name: nil, prefix: '', parameters: {})
          RHDL::Codegen::CIRCT::RuntimeJSON.dump(
            to_flat_circt_nodes(top_name: top_name, prefix: prefix, parameters: parameters)
          )
        end

        # Build CIRCT node graph from the component.
        # This is the canonical in-memory IR for DSL lowering.
        def to_circt_nodes(top_name: nil, parameters: {})
          if (cached = cached_imported_circt_module(top_name: top_name, parameters: parameters))
            return cached
          end

          build_circt_module(top_name: top_name, parameters: parameters)
        end

        def build_circt_module(top_name: nil, parameters: {})
          name = top_name || verilog_module_name
          resolved_params = resolve_codegen_parameters(parameters)

          # Imported/generated DSL can occasionally contain duplicated port
          # declarations with identical name/direction pairs. Keep the first
          # declaration to produce valid CIRCT module signatures.
          deduped_port_defs = []
          seen_port_keys = {}
          _port_defs.each do |p|
            key = [p[:name].to_s, p[:direction].to_s]
            next if seen_port_keys[key]

            seen_port_keys[key] = true
            deduped_port_defs << p
          end

          ports = deduped_port_defs.map do |p|
            raw_width = p[:width]
            resolved_width = raw_width.is_a?(Symbol) ? (resolved_params[raw_width] || 1) : raw_width
            RHDL::Codegen::CIRCT::IR::Port.new(
              name: p[:name],
              direction: p[:direction],
              width: resolved_width,
              default: p[:default]
            )
          end

          behavior_result = behavior_to_circt_assigns(parameters: resolved_params)
          assigns = behavior_result[:assigns].dup

          seq_state = circt_sequential_state
          processes = seq_state[:processes]
          reset_vals = seq_state[:reset_values]

          instance_port_info = build_instance_port_info

          instance_driven_signals = Set.new
          signal_assigns = []
          _connection_defs.each do |conn|
            source, dest = conn[:source], conn[:dest]
            if source.is_a?(Array) && source.length == 2 && dest.is_a?(Symbol)
              instance_driven_signals.add(dest)
              src_inst, src_port = source
              src_wire = "#{src_inst}__#{src_port}"
              src_width = instance_port_info[[src_inst, src_port]]&.dig(:width) || find_signal_width(dest)
              signal_assigns << RHDL::Codegen::CIRCT::IR::Assign.new(
                target: dest.to_s,
                expr: RHDL::Codegen::CIRCT::IR::Signal.new(name: src_wire, width: src_width)
              )
            elsif source.is_a?(Symbol) && dest.is_a?(Symbol)
              source_width = find_signal_width(source)
              signal_assigns << RHDL::Codegen::CIRCT::IR::Assign.new(
                target: dest.to_s,
                expr: RHDL::Codegen::CIRCT::IR::Signal.new(name: source.to_s, width: source_width)
              )
            end
          end
          assigns.concat(signal_assigns)

          instance_output_nets = []
          _instance_defs.each do |inst_def|
            inst_def[:connections].each_key do |port_name|
              info = instance_port_info[[inst_def[:name], port_name]]
              next unless info && info[:direction] == :out

              instance_output_nets << RHDL::Codegen::CIRCT::IR::Net.new(
                name: "#{inst_def[:name]}__#{port_name}",
                width: info[:width]
              )
            end
          end

          assign_driven_signals = Set.new
          assigns.each do |assign|
            assign_driven_signals.add(assign.target.to_sym)
          end

          regs = []
          instance_nets = []
          signal_names = Set.new
          _signals.each do |signal|
            signal_names.add(signal.name)
            should_be_net = instance_driven_signals.include?(signal.name) || assign_driven_signals.include?(signal.name)

            if should_be_net
              instance_nets << RHDL::Codegen::CIRCT::IR::Net.new(name: signal.name, width: signal.width)
            else
              reset_value = reset_vals[signal.name]
              regs << RHDL::Codegen::CIRCT::IR::Reg.new(name: signal.name, width: signal.width, reset_value: reset_value)
            end
          end

          reset_vals.each do |reg_name, reset_value|
            next if signal_names.include?(reg_name)

            port = _ports.find { |p| p.name == reg_name }
            width = port ? port.width : 8
            regs << RHDL::Codegen::CIRCT::IR::Reg.new(name: reg_name, width: width, reset_value: reset_value)
          end

          wires = behavior_result[:wires]
          nets = (wires + instance_nets + instance_output_nets).uniq { |net| net.name.to_s }

          instances = structure_to_circt_instances

          memories = []
          write_ports = []
          sync_read_ports = []
          if respond_to?(:_memories) && !_memories.empty?
            memory_ir = memory_dsl_to_circt
            memories = memory_ir[:memories]
            write_ports = memory_ir[:write_ports]
            sync_read_ports = Array(memory_ir[:sync_read_ports])
            assigns.concat(memory_ir[:assigns])
          end

          RHDL::Codegen::CIRCT::IR::ModuleOp.new(
            name: name,
            ports: ports,
            nets: nets,
            regs: regs,
            assigns: assigns,
            processes: processes,
            instances: instances,
            memories: memories,
            write_ports: write_ports,
            sync_read_ports: sync_read_ports,
            parameters: resolved_params
          )
        end

        def build_flat_circt_module(top_name: nil, prefix: '', parameters: {})
          name = top_name || verilog_module_name

          all_ports = []
          all_nets = []
          all_regs = []
          all_assigns = []
          all_processes = []
          all_memories = []
          all_write_ports = []
          all_sync_read_ports = []
          net_names = Set.new
          reg_names = Set.new

          ir = build_circt_module(top_name: name, parameters: parameters)

          all_ports = ir.ports if prefix.empty?

          ir.nets.each do |net|
            prefixed_name = prefix.empty? ? net.name : :"#{prefix}__#{net.name}"
            append_flat_net!(all_nets, net_names, name: prefixed_name, width: net.width)
          end

          unless prefix.empty?
            ir.ports.each do |port|
              next unless port.direction.to_s == 'out'
              prefixed_name = :"#{prefix}__#{port.name}"
              append_flat_net!(all_nets, net_names, reg_names: reg_names, name: prefixed_name, width: port.width)
            end
          end

          ir.regs.each do |reg|
            prefixed_name = prefix.empty? ? reg.name : :"#{prefix}__#{reg.name}"
            append_flat_reg!(all_regs, reg_names, name: prefixed_name, width: reg.width, reset_value: reg.reset_value)
          end

          ir.assigns.each do |assign|
            all_assigns << prefix_circt_assign(assign, prefix)
          end

          ir.processes.each do |process|
            all_processes << prefix_circt_process(process, prefix)
          end

          ir.memories.each do |mem|
            prefixed_name = prefix.empty? ? mem.name : "#{prefix}__#{mem.name}"
            all_memories << RHDL::Codegen::CIRCT::IR::Memory.new(
              name: prefixed_name,
              depth: mem.depth,
              width: mem.width,
              read_ports: mem.read_ports,
              write_ports: mem.write_ports,
              initial_data: mem.initial_data
            )
          end

          ir.write_ports.each do |write_port|
            all_write_ports << prefix_circt_write_port(write_port, prefix)
          end

          ir.sync_read_ports.each do |read_port|
            all_sync_read_ports << prefix_circt_sync_read_port(read_port, prefix)
          end

          _instance_defs.each do |inst_def|
            inst_name = inst_def[:name]
            component_class = inst_def[:component_class]
            inst_prefix = prefix.empty? ? inst_name.to_s : "#{prefix}__#{inst_name}"
            inst_params = inst_def[:parameters] || {}

            if component_class.respond_to?(:to_flat_circt_nodes)
              sub_ir = component_class.flat_circt_template(parameters: inst_params)
              append_prefixed_flat_module!(
                module_ir: sub_ir,
                prefix: inst_prefix,
                nets: all_nets,
                net_names: net_names,
                regs: all_regs,
                reg_names: reg_names,
                assigns: all_assigns,
                processes: all_processes,
                memories: all_memories,
                write_ports: all_write_ports,
                sync_read_ports: all_sync_read_ports
              )

              connected_ports = Set.new
              port_defs_by_name = component_class.port_defs_by_name
              inst_def[:connections].each do |port_name, parent_signal|
                connected_ports.add(port_name)
                port_def = port_defs_by_name[port_name]
                direction = port_def ? port_def[:direction] : :in
                raw_width = port_def ? port_def[:width] : 1
                port_width = if raw_width.is_a?(Symbol)
                  inst_params[raw_width] || component_class._parameter_defs[raw_width] || 1
                else
                  raw_width
                end

                child_signal = "#{inst_prefix}__#{port_name}"
                parent_sig = if parent_signal.is_a?(Array) && parent_signal.length == 2
                  src_inst, src_port = parent_signal
                  prefix.empty? ? "#{src_inst}__#{src_port}" : "#{prefix}__#{src_inst}__#{src_port}"
                else
                  prefix.empty? ? parent_signal.to_s : "#{prefix}__#{parent_signal}"
                end

                if direction == :in
                  all_assigns << RHDL::Codegen::CIRCT::IR::Assign.new(
                    target: child_signal,
                    expr: RHDL::Codegen::CIRCT::IR::Signal.new(name: parent_sig, width: port_width)
                  )
                end

                append_flat_net!(all_nets, net_names, reg_names: reg_names, name: child_signal.to_sym, width: port_width)
              end

              component_class._port_defs.each do |port_def|
                next if connected_ports.include?(port_def[:name])
                next unless port_def[:direction] == :in
                next if port_def[:default].nil?

                child_signal = "#{inst_prefix}__#{port_def[:name]}"
                default_value = port_def[:default].is_a?(Proc) ? port_def[:default].call : port_def[:default].to_i

                raw_width = port_def[:width]
                resolved_width = if raw_width.is_a?(Symbol)
                  inst_params[raw_width] || component_class._parameter_defs[raw_width] || 1
                else
                  raw_width
                end

                all_assigns << RHDL::Codegen::CIRCT::IR::Assign.new(
                  target: child_signal,
                  expr: RHDL::Codegen::CIRCT::IR::Literal.new(value: default_value, width: resolved_width)
                )

                append_flat_net!(all_nets, net_names, reg_names: reg_names, name: child_signal.to_sym, width: resolved_width)
              end
            end
          end

          RHDL::Codegen::CIRCT::IR::ModuleOp.new(
            name: name,
            ports: all_ports,
            nets: all_nets,
            regs: all_regs,
            assigns: all_assigns,
            processes: all_processes,
            instances: [],
            memories: all_memories,
            write_ports: all_write_ports,
            sync_read_ports: all_sync_read_ports,
            parameters: ir.parameters
          )
        end

        def circt_sequential_state
          return { processes: [], sequential_targets: Set.new, reset_values: {} } unless respond_to?(:execute_sequential_for_synthesis)

          sequential_irs = Array(execute_sequential_for_synthesis).compact
          return { processes: [], sequential_targets: Set.new, reset_values: {} } if sequential_irs.empty?

          processes = sequential_irs.each_with_index.map do |seq_ir, index|
            circt_process_from_sequential_ir(seq_ir, index: index)
          end
          sequential_targets = Set.new(
            sequential_irs.flat_map do |seq_ir|
              seq_ir.assignments.map { |assignment| assignment.target.to_sym } + Array(seq_ir.reset_values).map { |name, _| name.to_sym }
            end
          )
          reset_values = sequential_irs.each_with_object({}) do |seq_ir, acc|
            Array(seq_ir.reset_values).each do |name, value|
              acc[name.to_sym] = value
            end
          end

          {
            processes: processes,
            sequential_targets: sequential_targets,
            reset_values: reset_values
          }
        end

        def circt_process_from_sequential_ir(seq_ir, index: 0)
          normal_statements = seq_ir.assignments.map do |assign|
            RHDL::Codegen::CIRCT::IR::SeqAssign.new(
              target: assign.target,
              expr: assign.expr
            )
          end

          statements = if seq_ir.reset
            reset_signal = RHDL::Codegen::CIRCT::IR::Signal.new(name: seq_ir.reset, width: 1)
            reset_statements = Array(seq_ir.reset_values).map do |name, value|
              RHDL::Codegen::CIRCT::IR::SeqAssign.new(
                target: name,
                expr: RHDL::Codegen::CIRCT::IR::Literal.new(
                  value: value,
                  width: sequential_target_width(name)
                )
              )
            end

            if RHDL::DSL::Sequential.active_low_reset_name?(seq_ir.reset)
              [RHDL::Codegen::CIRCT::IR::If.new(
                condition: reset_signal,
                then_statements: normal_statements,
                else_statements: reset_statements
              )]
            else
              [RHDL::Codegen::CIRCT::IR::If.new(
                condition: reset_signal,
                then_statements: reset_statements,
                else_statements: normal_statements
              )]
            end
          else
            normal_statements
          end

          RHDL::Codegen::CIRCT::IR::Process.new(
            name: (index.zero? ? :seq_logic : :"seq_logic_#{index}"),
            statements: statements,
            clocked: true,
            clock: seq_ir.clock,
            reset: seq_ir.reset,
            reset_active_low: !!(seq_ir.reset && RHDL::DSL::Sequential.active_low_reset_name?(seq_ir.reset)),
            reset_values: seq_ir.reset_values
          )
        end

        def sequential_target_width(target_name)
          target = target_name.to_sym

          port = _ports.find { |entry| entry.name.to_sym == target }
          return port.width if port

          signal = _signals.find { |entry| entry.name.to_sym == target }
          return signal.width if signal

          8
        end

        def build_instance_port_info
          instance_port_info = {}
          _instance_defs.each do |inst_def|
            component_class = inst_def[:component_class]
            next unless component_class.respond_to?(:_port_defs)

            inst_params = inst_def[:parameters] || {}
            parameter_defaults = component_class.respond_to?(:_parameter_defs) ? component_class._parameter_defs : {}

            component_class._port_defs.each do |port_def|
              raw_width = port_def[:width]
              resolved_width = if raw_width.is_a?(Symbol)
                inst_params[raw_width] || parameter_defaults[raw_width] || 1
              else
                raw_width
              end

              instance_port_info[[inst_def[:name], port_def[:name]]] = {
                direction: port_def[:direction],
                width: resolved_width
              }
            end
          end
          instance_port_info
        end

        def resolve_codegen_parameters(parameters)
          resolved_params = {}
          _parameter_defs.each do |param_name, default_val|
            if default_val.is_a?(Proc)
              eval_context = Object.new
              _parameter_defs.each do |k, v|
                next if v.is_a?(Proc)
                eval_context.instance_variable_set(:"@#{k}", v)
              end
              resolved_params[param_name] = eval_context.instance_exec(&default_val)
            else
              resolved_params[param_name] = default_val
            end
          end
          resolved_params.merge(parameters)
        end

        def flat_circt_template(parameters: {})
          cache = instance_variable_get(:@_flat_circt_template_cache) || {}
          key = flat_circt_template_cache_key(parameters)
          return cache[key] if cache.key?(key)

          template = build_flat_circt_module(parameters: parameters)
          cache[key] = template
          instance_variable_set(:@_flat_circt_template_cache, cache)
          template
        end

        def port_defs_by_name
          instance_variable_get(:@_port_defs_by_name) || begin
            mapping = _port_defs.each_with_object({}) do |port_def, result|
              result[port_def[:name]] = port_def
            end
            instance_variable_set(:@_port_defs_by_name, mapping)
          end
        end

        def append_prefixed_flat_module!(module_ir:, prefix:, nets:, net_names:, regs:, reg_names:, assigns:, processes:, memories:, write_ports:, sync_read_ports:)
          module_ir.nets.each do |net|
            append_flat_net!(
              nets,
              net_names,
              name: :"#{prefix}__#{net.name}",
              width: net.width
            )
          end

          module_ir.ports.each do |port|
            next unless port.direction.to_s == 'out'

            append_flat_net!(
              nets,
              net_names,
              reg_names: reg_names,
              name: :"#{prefix}__#{port.name}",
              width: port.width
            )
          end

          module_ir.regs.each do |reg|
            append_flat_reg!(
              regs,
              reg_names,
              name: :"#{prefix}__#{reg.name}",
              width: reg.width,
              reset_value: reg.reset_value
            )
          end

          module_ir.assigns.each do |assign|
            assigns << prefix_circt_assign(assign, prefix)
          end

          module_ir.processes.each do |process|
            processes << prefix_circt_process(process, prefix)
          end

          module_ir.memories.each do |mem|
            memories << prefix_circt_memory(mem, prefix)
          end

          module_ir.write_ports.each do |write_port|
            write_ports << prefix_circt_write_port(write_port, prefix)
          end

          module_ir.sync_read_ports.each do |read_port|
            sync_read_ports << prefix_circt_sync_read_port(read_port, prefix)
          end
        end

        def append_flat_net!(nets, net_names, name:, width:, reg_names: nil)
          net_key = name.to_s
          return if net_names.include?(net_key)
          return if reg_names && reg_names.include?(net_key)

          nets << RHDL::Codegen::CIRCT::IR::Net.new(name: name, width: width)
          net_names.add(net_key)
        end

        def append_flat_reg!(regs, reg_names, name:, width:, reset_value:)
          reg_key = name.to_s
          return if reg_names.include?(reg_key)

          regs << RHDL::Codegen::CIRCT::IR::Reg.new(name: name, width: width, reset_value: reset_value)
          reg_names.add(reg_key)
        end

        def prefix_circt_memory(memory, prefix)
          return memory if prefix.empty?

          RHDL::Codegen::CIRCT::IR::Memory.new(
            name: "#{prefix}__#{memory.name}",
            depth: memory.depth,
            width: memory.width,
            read_ports: memory.read_ports,
            write_ports: memory.write_ports,
            initial_data: memory.initial_data
          )
        end

        def flat_circt_template_cache_key(parameters)
          case parameters
          when Hash
            parameters.keys.sort_by(&:to_s).map do |key|
              [key.to_s, flat_circt_template_cache_key(parameters[key])]
            end
          when Array
            parameters.map { |value| flat_circt_template_cache_key(value) }
          else
            parameters
          end
        end

        def prefix_circt_assign(assign, prefix)
          return assign if prefix.empty?

          RHDL::Codegen::CIRCT::IR::Assign.new(
            target: "#{prefix}__#{assign.target}",
            expr: prefix_circt_expr(assign.expr, prefix)
          )
        end

        def prefix_circt_expr(expr, prefix)
          return expr if prefix.empty?

          case expr
          when RHDL::Codegen::CIRCT::IR::Signal
            RHDL::Codegen::CIRCT::IR::Signal.new(name: "#{prefix}__#{expr.name}", width: expr.width)
          when RHDL::Codegen::CIRCT::IR::Literal
            expr
          when RHDL::Codegen::CIRCT::IR::BinaryOp
            RHDL::Codegen::CIRCT::IR::BinaryOp.new(
              op: expr.op,
              left: prefix_circt_expr(expr.left, prefix),
              right: prefix_circt_expr(expr.right, prefix),
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::UnaryOp
            RHDL::Codegen::CIRCT::IR::UnaryOp.new(
              op: expr.op,
              operand: prefix_circt_expr(expr.operand, prefix),
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::Mux
            RHDL::Codegen::CIRCT::IR::Mux.new(
              condition: prefix_circt_expr(expr.condition, prefix),
              when_true: prefix_circt_expr(expr.when_true, prefix),
              when_false: prefix_circt_expr(expr.when_false, prefix),
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::Slice
            RHDL::Codegen::CIRCT::IR::Slice.new(
              base: prefix_circt_expr(expr.base, prefix),
              range: expr.range,
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::Concat
            RHDL::Codegen::CIRCT::IR::Concat.new(
              parts: expr.parts.map { |part| prefix_circt_expr(part, prefix) },
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::Resize
            RHDL::Codegen::CIRCT::IR::Resize.new(
              expr: prefix_circt_expr(expr.expr, prefix),
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::Case
            RHDL::Codegen::CIRCT::IR::Case.new(
              selector: prefix_circt_expr(expr.selector, prefix),
              cases: expr.cases.transform_values { |value| prefix_circt_expr(value, prefix) },
              default: expr.default ? prefix_circt_expr(expr.default, prefix) : nil,
              width: expr.width
            )
          when RHDL::Codegen::CIRCT::IR::MemoryRead
            RHDL::Codegen::CIRCT::IR::MemoryRead.new(
              memory: "#{prefix}__#{expr.memory}",
              addr: prefix_circt_expr(expr.addr, prefix),
              width: expr.width
            )
          else
            expr
          end
        end

        def prefix_circt_process(process, prefix)
          return process if prefix.empty?

          RHDL::Codegen::CIRCT::IR::Process.new(
            name: :"#{prefix}__#{process.name}",
            statements: process.statements.map { |stmt| prefix_circt_statement(stmt, prefix) },
            clocked: process.clocked,
            clock: process.clock ? "#{prefix}__#{process.clock}" : nil,
            sensitivity_list: Array(process.sensitivity_list).map { |entry| "#{prefix}__#{entry}" },
            reset: process.reset ? "#{prefix}__#{process.reset}" : nil,
            reset_active_low: process.reset_active_low,
            reset_values: process.reset_values
          )
        end

        def prefix_circt_statement(stmt, prefix)
          case stmt
          when RHDL::Codegen::CIRCT::IR::SeqAssign
            RHDL::Codegen::CIRCT::IR::SeqAssign.new(
              target: "#{prefix}__#{stmt.target}",
              expr: prefix_circt_expr(stmt.expr, prefix)
            )
          when RHDL::Codegen::CIRCT::IR::If
            RHDL::Codegen::CIRCT::IR::If.new(
              condition: prefix_circt_expr(stmt.condition, prefix),
              then_statements: stmt.then_statements&.map { |sub_stmt| prefix_circt_statement(sub_stmt, prefix) },
              else_statements: stmt.else_statements&.map { |sub_stmt| prefix_circt_statement(sub_stmt, prefix) }
            )
          else
            stmt
          end
        end

        def prefix_circt_write_port(write_port, prefix)
          return write_port if prefix.empty?

          RHDL::Codegen::CIRCT::IR::MemoryWritePort.new(
            memory: "#{prefix}__#{write_port.memory}",
            clock: "#{prefix}__#{write_port.clock}",
            addr: prefix_circt_expr(write_port.addr, prefix),
            data: prefix_circt_expr(write_port.data, prefix),
            enable: prefix_circt_expr(write_port.enable, prefix)
          )
        end

        def prefix_circt_sync_read_port(read_port, prefix)
          return read_port if prefix.empty?

          RHDL::Codegen::CIRCT::IR::MemorySyncReadPort.new(
            memory: "#{prefix}__#{read_port.memory}",
            clock: "#{prefix}__#{read_port.clock}",
            addr: prefix_circt_expr(read_port.addr, prefix),
            data: "#{prefix}__#{read_port.data}",
            enable: read_port.enable ? prefix_circt_expr(read_port.enable, prefix) : nil
          )
        end

        # Generate CIRCT MLIR text from the component.
        def to_ir(top_name: nil, parameters: {})
          if (cached_text = cached_imported_circt_module_text(top_name: top_name, parameters: parameters))
            return cached_text
          end

          RHDL::Codegen::CIRCT::MLIR.generate(to_circt_nodes(top_name: top_name, parameters: parameters))
        end

        def cached_imported_circt_module(top_name:, parameters:)
          return nil unless (parameters.nil? || parameters.empty?)

          base = instance_variable_get(:@_imported_circt_module)
          return nil unless base

          desired_name = top_name ? top_name.to_s : base.name.to_s
          return base if desired_name == base.name.to_s

          cached_by_name = instance_variable_get(:@_imported_circt_module_by_name) || {}
          return cached_by_name[desired_name] if cached_by_name.key?(desired_name)

          renamed = RHDL::Codegen::CIRCT::IR::ModuleOp.new(
            name: desired_name,
            ports: base.ports,
            nets: base.nets,
            regs: base.regs,
            assigns: base.assigns,
            processes: base.processes,
            instances: base.instances,
            memories: base.memories,
            write_ports: base.write_ports,
            sync_read_ports: base.sync_read_ports,
            parameters: base.parameters
          )
          cached_by_name[desired_name] = renamed
          instance_variable_set(:@_imported_circt_module_by_name, cached_by_name)
          renamed
        end

        def cached_imported_circt_module_text(top_name:, parameters:)
          return nil unless (parameters.nil? || parameters.empty?)

          base = instance_variable_get(:@_imported_circt_module_text)
          mod = instance_variable_get(:@_imported_circt_module)
          return nil unless base && mod

          desired_name = top_name ? top_name.to_s : mod.name.to_s
          return base if desired_name == mod.name.to_s

          cached_by_name = instance_variable_get(:@_imported_circt_module_text_by_name) || {}
          return cached_by_name[desired_name] if cached_by_name.key?(desired_name)

          header = /
            ^
            (?<prefix>\s*(?:hw|sv)\.module(?:\s+\w+)*\s+)
            @#{Regexp.escape(mod.name.to_s)}
            (?=[(<\s])
          /x
          renamed = base.sub(header, "\\k<prefix>@#{desired_name}")
          cached_by_name[desired_name] = renamed
          instance_variable_set(:@_imported_circt_module_text_by_name, cached_by_name)
          renamed
        end

        # Generate CIRCT IR from Memory DSL definitions
        def memory_dsl_to_circt
          memories = []
          assigns = []
          write_ports = []

          mem_defs = _memories

          # Generate Memory IR nodes
          mem_defs.each do |mem_name, mem_def|
            memories << RHDL::Codegen::CIRCT::IR::Memory.new(
              name: mem_name,
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

              read_expr = RHDL::Codegen::CIRCT::IR::MemoryRead.new(
                memory: read_def.memory,
                addr: RHDL::Codegen::CIRCT::IR::Signal.new(name: read_def.addr, width: addr_width),
                width: data_width
              )

              # Wrap in mux if enable is specified
              if read_def.enable
                read_expr = RHDL::Codegen::CIRCT::IR::Mux.new(
                  condition: RHDL::Codegen::CIRCT::IR::Signal.new(name: read_def.enable, width: 1),
                  when_true: read_expr,
                  when_false: RHDL::Codegen::CIRCT::IR::Literal.new(value: 0, width: data_width),
                  width: data_width
                )
              end

              assigns << RHDL::Codegen::CIRCT::IR::Assign.new(target: read_def.output, expr: read_expr)
            end
          end

          # Generate sync write ports
          if respond_to?(:_sync_writes)
            _sync_writes.each do |write_def|
              mem_def = mem_defs[write_def.memory]
              addr_width = mem_def&.addr_width || 8
              data_width = mem_def&.width || 8

              # Handle enable as expression or simple signal
              enable_ir = if write_def.enable_is_expression?
                           write_def.enable_to_ir({})
                         else
                           RHDL::Codegen::CIRCT::IR::Signal.new(name: write_def.enable, width: 1)
                         end

              write_ports << RHDL::Codegen::CIRCT::IR::MemoryWritePort.new(
                memory: write_def.memory,
                clock: write_def.clock,
                addr: RHDL::Codegen::CIRCT::IR::Signal.new(name: write_def.addr, width: addr_width),
                data: RHDL::Codegen::CIRCT::IR::Signal.new(name: write_def.data, width: data_width),
                enable: enable_ir
              )
            end
          end

          # Generate sync read ports
          sync_read_ports = []
          if respond_to?(:_sync_reads)
            _sync_reads.each do |read_def|
              mem_def = mem_defs[read_def.memory]
              addr_width = mem_def&.addr_width || 8

              # Handle enable as expression or simple signal
              enable_ir = if read_def.enable_is_expression?
                           read_def.enable_to_ir({})
                         elsif read_def.enable
                           RHDL::Codegen::CIRCT::IR::Signal.new(name: read_def.enable, width: 1)
                         else
                           nil
                         end

              sync_read_ports << RHDL::Codegen::CIRCT::IR::MemorySyncReadPort.new(
                memory: read_def.memory,
                clock: read_def.clock,
                addr: RHDL::Codegen::CIRCT::IR::Signal.new(name: read_def.addr, width: addr_width),
                data: read_def.output.to_s,
                enable: enable_ir
              )
            end
          end

          { memories: memories, assigns: assigns, write_ports: write_ports, sync_read_ports: sync_read_ports }
        end

        # Generate CIRCT instances from structure definitions
        def structure_to_circt_instances
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
                            elsif signal.is_a?(Array) && signal.length == 2
                              # Instance-to-instance connection: [:src_inst, :src_port]
                              "#{signal[0]}__#{signal[1]}"
                            else
                              signal.to_s
                            end
              RHDL::Codegen::CIRCT::IR::PortConnection.new(
                port_name: port_name,
                signal: signal_name,
                direction: direction
              )
            end

            RHDL::Codegen::CIRCT::IR::Instance.new(
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

        # Generate CIRCT assigns and wire declarations from the behavior block.
        # @param parameters [Hash] Instance parameters for parameterized widths
        def behavior_to_circt_assigns(parameters: {})
          return { assigns: [], wires: [] } unless behavior_defined?

          ctx = RHDL::Synth::Context.new(self, parameters: parameters)
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
