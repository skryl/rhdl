# HDL Sequential Component Base Class
# Base class for sequential (clocked) components

module RHDL
  module HDL
    class SequentialComponent < SimComponent
      def initialize(name = nil, **kwargs)
        @prev_clk = 0
        @clk_sampled = false  # Track if we've sampled clock this cycle
        @state ||= 0  # Don't overwrite subclass initialization
        super
      end

      # Override input to not auto-propagate on any input changes
      # Sequential components should be propagated manually as part of clock cycles
      # This avoids race conditions where inputs change in wrong order during propagation
      def input(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @inputs[name] = wire
        # No on_change callbacks - sequential propagation must be explicit
        wire
      end

      def rising_edge?
        clk = in_val(:clk)
        result = @prev_clk == 0 && clk == 1
        # Update prev_clk after checking - this ensures the edge is detected once
        @prev_clk = clk
        result
      end

      def falling_edge?
        clk = in_val(:clk)
        result = @prev_clk == 1 && clk == 0
        @prev_clk = clk
        result
      end

      # Call this to sample the current clock value without detecting an edge
      # Useful when you need to update prev_clk outside of edge detection
      def sample_clock
        @prev_clk = in_val(:clk)
      end

      class << self
        # Check if sequential block is defined
        def sequential_defined?
          respond_to?(:_sequential_block) && _sequential_block
        end

        # Override to_ir to include sequential processes
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
          reg_ports = _ports.select { |p| p.direction == :out && sequential_targets.include?(p.name) }.map(&:name)

          # Also check for behavior blocks (for combinational parts)
          behavior_result = behavior_to_ir_assigns
          assigns = behavior_result[:assigns]

          # Generate instances from structure definitions
          instances = structure_to_ir_instances

          # Identify signals driven by instance outputs (these must be wires, not regs)
          # Also generate assign statements for signal-to-signal connections
          instance_driven_signals = Set.new
          signal_assigns = []
          _connection_defs.each do |conn|
            source, dest = conn[:source], conn[:dest]
            # If source is [inst_name, port_name], then dest is driven by an instance output
            if source.is_a?(Array) && source.length == 2 && dest.is_a?(Symbol)
              instance_driven_signals.add(dest)
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
          regs = []
          instance_nets = []
          _signals.each do |s|
            if instance_driven_signals.include?(s.name) || assign_driven_signals.include?(s.name)
              instance_nets << RHDL::Export::IR::Net.new(name: s.name, width: s.width)
            else
              regs << RHDL::Export::IR::Reg.new(name: s.name, width: s.width)
            end
          end

          # Generate memory IR from MemoryDSL if included
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
            nets: behavior_result[:wires] + instance_nets,
            regs: regs,
            assigns: assigns,
            processes: processes,
            instances: instances,
            reg_ports: reg_ports,
            memories: memories,
            write_ports: write_ports,
            parameters: parameters
          )
        end

        # Convert IR::Sequential to IR::Process
        def sequential_ir_to_process(seq_ir)
          statements = []

          # Build if-else structure: if (reset) ... else ...
          if seq_ir.reset
            # Reset branch: assign reset values
            reset_stmts = seq_ir.reset_values.map do |name, value|
              port = _ports.find { |p| p.name == name }
              width = port ? port.width : 8
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
            statements << RHDL::Export::IR::If.new(
              condition: RHDL::Export::IR::Signal.new(name: seq_ir.reset, width: 1),
              then_statements: reset_stmts,
              else_statements: normal_stmts
            )
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
