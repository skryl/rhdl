# HDL Sequential Component Base Class
# Base class for sequential (clocked) components

module RHDL
  module HDL
    class SequentialComponent < SimComponent
      def initialize(name = nil, **kwargs)
        @prev_clk = 0
        @clk_sampled = false  # Track if we've sampled clock this cycle
        @state ||= 0  # Don't overwrite subclass initialization
        super(name)
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
          name = top_name || self.name.split('::').last.underscore

          ports = _ports.map do |p|
            RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
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

          # Generate instances from structure definitions
          instances = structure_to_ir_instances

          # Get signal defs for internal wires
          regs = _signals.map do |s|
            RHDL::Export::IR::Reg.new(name: s.name, width: s.width)
          end

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: ports,
            nets: behavior_result[:wires],
            regs: regs,
            assigns: behavior_result[:assigns],
            processes: processes,
            instances: instances,
            reg_ports: reg_ports
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
