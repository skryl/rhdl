# frozen_string_literal: true

# Sequential Codegen DSL for HDL Components
#
# This module extends the base Codegen module with sequential-specific IR generation.
# It overrides to_ir to include sequential processes (always @(posedge clk) blocks).

require 'rhdl/support/concern'
require 'set'

module RHDL
  module DSL
    module SequentialCodegen
      extend RHDL::Support::Concern

      class_methods do
        # Override to_ir to include sequential processes
        # @param top_name [String] Optional name override for module
        # @param parameters [Hash] Instance parameters to override defaults
        def to_ir(top_name: nil, parameters: {})
          name = top_name || verilog_module_name

          # Build parameters hash from class-level parameter definitions
          # then merge in any instance-specific parameters
          resolved_params = {}
          _parameter_defs.each do |param_name, default_val|
            if default_val.is_a?(Proc)
              # For class-level evaluation, use default parameter values
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
          # Override with instance parameters
          resolved_params.merge!(parameters)

          # Resolve port widths using the resolved parameters
          ports = _port_defs.map do |p|
            raw_width = p[:width]
            resolved_width = raw_width.is_a?(Symbol) ? (resolved_params[raw_width] || 1) : raw_width
            RHDL::Export::IR::Port.new(
              name: p[:name],
              direction: p[:direction],
              width: resolved_width,
              default: p[:default]
            )
          end

          # Get sequential IR if defined
          processes = []
          sequential_targets = []
          if sequential_defined?
            seq_ir = execute_sequential_for_synthesis
            if seq_ir
              process = sequential_ir_to_process(seq_ir)
              processes << process
              # Collect targets assigned in sequential block
              sequential_targets = seq_ir.assignments.map { |a| a.target.to_sym }
              # Also include reset values as they're sequential targets too
              sequential_targets += seq_ir.reset_values.keys
            end
          end

          # Only mark outputs as registers if they are assigned in the sequential block
          reg_ports = _port_defs.select { |p| p[:direction] == :out && sequential_targets.include?(p[:name]) }.map { |p| p[:name] }

          # Also check for behavior blocks (for combinational parts)
          # Pass resolved parameters for parameterized width resolution
          behavior_result = behavior_to_ir_assigns(parameters: resolved_params)
          assigns = behavior_result[:assigns]

          # Generate instances from structure definitions
          instances = structure_to_ir_instances

          # Identify signals driven by instance outputs (these must be wires, not regs)
          # Also generate assign statements for signal-to-signal connections
          instance_driven_signals = Set.new
          signal_assigns = []
          instance_output_nets = []
          _connection_defs.each do |conn|
            source, dest = conn[:source], conn[:dest]
            # If source is [inst_name, port_name], then dest is driven by an instance output
            if source.is_a?(Array) && source.length == 2 && dest.is_a?(Symbol)
              instance_driven_signals.add(dest)
              # Generate a flattened signal name and assign statement for RTL simulation
              # This allows behavior-level simulators to trace these connections
              inst_name, port_name = source
              flat_signal_name = "#{inst_name}__#{port_name}"
              dest_width = find_signal_width(dest)
              # Add net for the flattened instance output signal
              instance_output_nets << RHDL::Export::IR::Net.new(name: flat_signal_name.to_sym, width: dest_width)
              # Add assign from flattened signal to destination
              signal_assigns << RHDL::Export::IR::Assign.new(
                target: dest.to_s,
                expr: RHDL::Export::IR::Signal.new(name: flat_signal_name, width: dest_width)
              )
            # If both are symbols, generate an assign statement (signal-to-signal connection)
            elsif source.is_a?(Symbol) && dest.is_a?(Symbol)
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
          # Get reset values from sequential block if available
          reset_vals = {}
          if sequential_defined?
            seq_ir_for_reset = execute_sequential_for_synthesis
            reset_vals = seq_ir_for_reset&.reset_values || {}
          end

          regs = []
          instance_nets = []
          signal_names = Set.new

          _signals.each do |s|
            signal_names.add(s.name)
            if instance_driven_signals.include?(s.name) || assign_driven_signals.include?(s.name)
              instance_nets << RHDL::Export::IR::Net.new(name: s.name, width: s.width)
            else
              reset_val = reset_vals[s.name]
              regs << RHDL::Export::IR::Reg.new(name: s.name, width: s.width, reset_value: reset_val)
            end
          end

          # Also create registers for sequential targets defined in reset_values
          # that aren't already defined as explicit signals
          reset_vals.each do |reg_name, reset_val|
            next if signal_names.include?(reg_name)
            # Look up width from ports if it's an output port, otherwise default to 8 bits
            port = _ports.find { |p| p.name == reg_name }
            width = port ? port.width : 8
            regs << RHDL::Export::IR::Reg.new(name: reg_name, width: width, reset_value: reset_val)
          end

          # Generate memory IR from Memory DSL if included
          memories = []
          write_ports = []
          sync_read_ports = []
          if respond_to?(:_memories) && !_memories.empty?
            memory_ir = memory_dsl_to_ir
            memories = memory_ir[:memories]
            write_ports = memory_ir[:write_ports]
            sync_read_ports = memory_ir[:sync_read_ports] || []
            assigns = assigns + memory_ir[:assigns]
          end

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: ports,
            nets: behavior_result[:wires] + instance_nets + instance_output_nets,
            regs: regs,
            assigns: assigns,
            processes: processes,
            instances: instances,
            reg_ports: reg_ports,
            memories: memories,
            write_ports: write_ports,
            sync_read_ports: sync_read_ports,
            parameters: resolved_params
          )
        end

        # Convert IR::Sequential to IR::Process
        def sequential_ir_to_process(seq_ir)
          statements = []

          # Build if-else structure: if (reset) ... else ...
          if seq_ir.reset
            # Reset branch: assign reset values
            reset_stmts = seq_ir.reset_values.map do |name, value|
              # Look up width from ports first, then signals
              port = _ports.find { |p| p.name == name }
              signal = _signals.find { |s| s.name == name }
              width = if port
                        port.width
                      elsif signal
                        signal.width
                      else
                        8  # Default fallback
                      end
              RHDL::Export::IR::SeqAssign.new(
                target: name,
                expr: RHDL::Export::IR::Literal.new(value: value, width: width)
              )
            end

            # Normal operation branch
            normal_stmts = seq_ir.assignments.map do |assign|
              RHDL::Export::IR::SeqAssign.new(
                target: assign.target,
                expr: assign.expr
              )
            end

            # Wrap in if-else
            # Determine if reset is active-low (ends with _n) or active-high
            reset_name = seq_ir.reset.to_s
            active_low = reset_name.end_with?('_n')

            # For active-low reset (reset_n):
            #   - when reset_n=1 (not in reset): run normal logic
            #   - when reset_n=0 (in reset): apply reset values
            # For active-high reset:
            #   - when reset=1 (in reset): apply reset values
            #   - when reset=0 (not in reset): run normal logic
            if active_low
              statements << RHDL::Export::IR::If.new(
                condition: RHDL::Export::IR::Signal.new(name: seq_ir.reset, width: 1),
                then_statements: normal_stmts,
                else_statements: reset_stmts
              )
            else
              statements << RHDL::Export::IR::If.new(
                condition: RHDL::Export::IR::Signal.new(name: seq_ir.reset, width: 1),
                then_statements: reset_stmts,
                else_statements: normal_stmts
              )
            end
          else
            # No reset - just the assignments
            statements = seq_ir.assignments.map do |assign|
              RHDL::Export::IR::SeqAssign.new(
                target: assign.target,
                expr: assign.expr
              )
            end
          end

          RHDL::Export::IR::Process.new(
            name: :seq_logic,
            statements: statements,
            clocked: true,
            clock: seq_ir.clock
          )
        end
      end
    end
  end
end
