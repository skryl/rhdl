# frozen_string_literal: true

require 'active_support/concern'

module RHDL
  module HDL
    # Base class for all HDL components with simulation support
    #
    # Components can define their behavior in two ways:
    # 1. Override the `propagate` method (traditional approach)
    # 2. Use the `behavior` class method (unified simulation/synthesis)
    #
    # Example with behavior block:
    #   class MyAnd < SimComponent
    #     port_input :a
    #     port_input :b
    #     port_output :y
    #
    #     behavior do
    #       y <= a & b
    #     end
    #   end
    #
    class SimComponent
      extend ActiveSupport::Concern
      attr_reader :name, :inputs, :outputs, :internal_signals

      # Class-level port definitions for behavior blocks
      class << self
        def inherited(subclass)
          super
          # Copy port definitions to subclass
          subclass.instance_variable_set(:@_port_defs, (@_port_defs || []).dup)
          subclass.instance_variable_set(:@_signal_defs, (@_signal_defs || []).dup)
        end

        def _port_defs
          @_port_defs ||= []
        end

        def _signal_defs
          @_signal_defs ||= []
        end

        # DSL-compatible _ports accessor for behavior module
        def _ports
          _port_defs.map do |pd|
            PortDef.new(pd[:name], pd[:direction], pd[:width])
          end
        end

        # DSL-compatible _signals accessor for behavior module
        def _signals
          _signal_defs.map do |sd|
            SignalDef.new(sd[:name], sd[:width])
          end
        end

        # Class-level port definition (for behavior blocks)
        def port_input(name, width: 1)
          _port_defs << { name: name, direction: :in, width: width }
        end

        def port_output(name, width: 1)
          _port_defs << { name: name, direction: :out, width: width }
        end

        def port_signal(name, width: 1)
          _signal_defs << { name: name, width: width }
        end

        # Check if behavior block is defined
        def behavior_defined?
          instance_variable_defined?(:@_behavior_block) && @_behavior_block
        end

        def _behavior_block
          @_behavior_block
        end

        # Define a behavior block for unified simulation and synthesis
        #
        # @example Basic combinational logic
        #   class MyAnd < SimComponent
        #     port_input :a
        #     port_input :b
        #     port_output :y
        #
        #     behavior do
        #       y <= a & b
        #     end
        #   end
        #
        # @example Multiple outputs with arithmetic
        #   class FullAdder < SimComponent
        #     port_input :a
        #     port_input :b
        #     port_input :cin
        #     port_output :sum
        #     port_output :cout
        #
        #     behavior do
        #       sum <= a ^ b ^ cin
        #       cout <= (a & b) | (a & cin) | (b & cin)
        #     end
        #   end
        #
        def behavior(**options, &block)
          @_behavior_block = BehaviorBlockDef.new(block, **options)
        end

        # Generate IR assigns from the behavior block
        # Used by the export/lowering system for HDL generation
        def behavior_to_ir_assigns
          return [] unless behavior_defined?

          ctx = BehaviorSynthContext.new(self)
          ctx.evaluate(&@_behavior_block.block)
          ctx.to_ir_assigns
        end

        # Generate IR ModuleDef from the component
        def to_ir(top_name: nil)
          name = top_name || self.name.split('::').last.underscore

          ports = _ports.map do |p|
            RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
          end

          regs = _signals.map do |s|
            RHDL::Export::IR::Reg.new(name: s.name, width: s.width)
          end

          assigns = behavior_to_ir_assigns

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: ports,
            nets: [],
            regs: regs,
            assigns: assigns,
            processes: []
          )
        end

        # Generate Verilog from the component
        def to_verilog(top_name: nil)
          RHDL::Export::Verilog.generate(to_ir(top_name: top_name))
        end

        # Generate VHDL from the component
        def to_vhdl(top_name: nil)
          RHDL::Export::VHDL.generate(to_ir(top_name: top_name))
        end
      end

      # Simple structs for port/signal definitions
      PortDef = Struct.new(:name, :direction, :width)
      SignalDef = Struct.new(:name, :width)

      def initialize(name = nil)
        @name = name || self.class.name.split('::').last.downcase
        @inputs = {}
        @outputs = {}
        @internal_signals = {}
        @subcomponents = {}
        @propagation_delay = 0
        setup_ports_from_class_defs
        setup_ports
      end

      # Create ports from class-level definitions
      def setup_ports_from_class_defs
        self.class._port_defs.each do |pd|
          case pd[:direction]
          when :in
            input(pd[:name], width: pd[:width])
          when :out
            output(pd[:name], width: pd[:width])
          end
        end
        self.class._signal_defs.each do |sd|
          signal(sd[:name], width: sd[:width])
        end
      end

      # Override in subclasses to define ports
      def setup_ports
      end

      def input(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @inputs[name] = wire
        wire.on_change { |_| propagate }
        wire
      end

      def output(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @outputs[name] = wire
        wire
      end

      def signal(name, width: 1)
        wire = Wire.new("#{@name}.#{name}", width: width)
        @internal_signals[name] = wire
        wire
      end

      def add_subcomponent(name, component)
        @subcomponents[name] = component
        component
      end

      # Connect an output of one component to an input of another
      def self.connect(source_wire, dest_wire)
        source_wire.on_change { |val| dest_wire.set(val) }
        dest_wire.set(source_wire.value)
        dest_wire.driver = source_wire
        source_wire.add_sink(dest_wire)
      end

      # Main simulation method - compute outputs from inputs
      # Override in subclasses, or use a behavior block
      def propagate
        if self.class.behavior_defined?
          execute_behavior
        end
      end

      # Execute the behavior block for simulation
      def execute_behavior
        return unless self.class._behavior_block

        block = self.class._behavior_block
        ctx = BehaviorSimContext.new(self)
        ctx.evaluate(&block.block)
      end

      # Get input value by name
      def in_val(name)
        @inputs[name]&.get || 0
      end

      # Set output value by name
      def out_set(name, val)
        @outputs[name]&.set(val)
      end

      # Convenience method to set an input
      def set_input(name, value)
        @inputs[name]&.set(value)
      end

      # Convenience method to get an output
      def get_output(name)
        @outputs[name]&.get
      end

      def inspect
        ins = @inputs.map { |k, v| "#{k}=#{v.get}" }.join(', ')
        outs = @outputs.map { |k, v| "#{k}=#{v.get}" }.join(', ')
        "#<#{self.class.name} #{@name} in:(#{ins}) out:(#{outs})>"
      end
    end
  end
end
