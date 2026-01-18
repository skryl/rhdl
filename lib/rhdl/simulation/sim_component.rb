# frozen_string_literal: true

require 'active_support/concern'

module RHDL
  module HDL
    # Base class for all HDL components with simulation support
    #
    # Components are defined using class-level declarations:
    # - port_input/port_output: Define I/O ports
    # - port_signal: Define internal signals
    # - instance: Instantiate sub-components
    # - wire: Connect signals to sub-component ports
    # - behavior: Define combinational logic
    #
    # @example Simple combinational component
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
    # @example Hierarchical component with sub-components
    #   class MyDatapath < SimComponent
    #     port_input :a, width: 8
    #     port_input :b, width: 8
    #     port_output :result, width: 8
    #
    #     instance :alu, ALU, width: 8
    #     instance :reg, Register, width: 8
    #
    #     wire :a => [:alu, :a]
    #     wire :b => [:alu, :b]
    #     wire [:alu, :result] => [:reg, :d]
    #     wire [:reg, :q] => :result
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
          subclass.instance_variable_set(:@_instance_defs, (@_instance_defs || []).dup)
          subclass.instance_variable_set(:@_connection_defs, (@_connection_defs || []).dup)
        end

        def _port_defs
          @_port_defs ||= []
        end

        def _signal_defs
          @_signal_defs ||= []
        end

        def _instance_defs
          @_instance_defs ||= []
        end

        def _connection_defs
          @_connection_defs ||= []
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

        # Define a sub-component instance (class-level)
        #
        # @param name [Symbol] Instance name
        # @param component_class [Class] Component class to instantiate
        # @param params [Hash] Parameters to pass to the component
        #
        # @example
        #   class MyDatapath < SimComponent
        #     port_input :a, width: 8
        #     port_output :result, width: 8
        #
        #     instance :alu, ALU, width: 8
        #     instance :reg, Register, width: 8
        #
        #     wire :a => [:alu, :a]
        #     wire [:alu, :result] => [:reg, :d]
        #     wire [:reg, :q] => :result
        #   end
        #
        def instance(name, component_class, **params)
          module_name = if component_class.respond_to?(:verilog_module_name)
                          component_class.verilog_module_name
                        else
                          component_class.name.split('::').last.underscore
                        end
          _instance_defs << {
            name: name,
            component_class: component_class,
            module_name: module_name,
            parameters: params,
            connections: {}
          }
        end

        # Define connections between signals and instance ports (class-level)
        #
        # @param mappings [Hash] Signal to port mappings
        #   Formats:
        #   - wire :clk => [:pc, :clk]              # Signal to instance port
        #   - wire :clk => [[:pc, :clk], [:acc, :clk]]  # Signal to multiple ports
        #   - wire [:alu, :result] => :result      # Instance output to signal
        #   - wire [:alu, :result] => [:reg, :d]   # Instance to instance
        #
        def wire(mappings)
          mappings.each do |source, dest|
            _connection_defs << { source: source, dest: dest }

            if dest.is_a?(Array) && dest.first.is_a?(Array)
              # Multiple destinations: connect :clk => [[:pc, :clk], [:acc, :clk]]
              dest.each { |d| add_port_connection(source, d) }
            elsif dest.is_a?(Array) && dest.length == 2
              # Single destination: connect :clk => [:pc, :clk]
              add_port_connection(source, dest)
            elsif source.is_a?(Array) && source.length == 2
              # Instance output to signal: connect [:alu, :result] => :result
              add_output_connection(source, dest)
            end
          end
        end

        # Check if behavior block is defined
        def behavior_defined?
          instance_variable_defined?(:@_behavior_block) && @_behavior_block
        end

        def _behavior_block
          @_behavior_block
        end

        # Check if structure is defined (has instances)
        def structure_defined?
          !_instance_defs.empty?
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
        def behavior(**options, &block)
          @_behavior_block = BehaviorBlockDef.new(block, **options)
        end

        private

        def add_port_connection(signal, dest)
          inst_name, port_name = dest
          inst_def = _instance_defs.find { |i| i[:name] == inst_name }
          return unless inst_def

          inst_def[:connections][port_name] = signal
        end

        def add_output_connection(source, signal)
          inst_name, port_name = source
          inst_def = _instance_defs.find { |i| i[:name] == inst_name }
          return unless inst_def

          inst_def[:connections][port_name] = signal
        end

        # Generate IR assigns and wire declarations from the behavior block
        # Used by the export/lowering system for HDL generation
        def behavior_to_ir_assigns
          return { assigns: [], wires: [] } unless behavior_defined?

          ctx = BehaviorSynthContext.new(self)
          ctx.evaluate(&@_behavior_block.block)
          {
            assigns: ctx.to_ir_assigns,
            wires: ctx.wire_declarations
          }
        end

        # Generate IR ModuleDef from the component
        def to_ir(top_name: nil)
          name = top_name || self.name.split('::').last.underscore

          ports = _ports.map do |p|
            RHDL::Export::IR::Port.new(name: p.name, direction: p.direction, width: p.width)
          end

          # Identify signals driven by instance outputs (these must be wires, not regs)
          # A signal is instance-driven if it's the destination of a connection from [inst, port]
          instance_driven_signals = Set.new
          _connection_defs.each do |conn|
            source, dest = conn[:source], conn[:dest]
            # If source is [inst_name, port_name], then dest is driven by an instance output
            if source.is_a?(Array) && source.length == 2 && dest.is_a?(Symbol)
              instance_driven_signals.add(dest)
            end
          end

          # Split signals into regs (not instance-driven) and nets (instance-driven)
          regs = []
          instance_nets = []
          _signals.each do |s|
            if instance_driven_signals.include?(s.name)
              instance_nets << RHDL::Export::IR::Net.new(name: s.name, width: s.width)
            else
              regs << RHDL::Export::IR::Reg.new(name: s.name, width: s.width)
            end
          end

          behavior_result = behavior_to_ir_assigns
          assigns = behavior_result[:assigns]
          nets = behavior_result[:wires] + instance_nets

          # Generate instances from structure definitions
          instances = structure_to_ir_instances

          RHDL::Export::IR::ModuleDef.new(
            name: name,
            ports: ports,
            nets: nets,
            regs: regs,
            assigns: assigns,
            processes: [],
            instances: instances
          )
        end

        # Generate IR instances from structure definitions
        def structure_to_ir_instances
          _instance_defs.map do |inst_def|
            connections = inst_def[:connections].map do |port_name, signal|
              RHDL::Export::IR::PortConnection.new(
                port_name: port_name,
                signal: signal.to_s
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

        # Generate Verilog from the component
        def to_verilog(top_name: nil)
          RHDL::Export::Verilog.generate(to_ir(top_name: top_name))
        end

        # Generate VHDL from the component
        def to_vhdl(top_name: nil)
          RHDL::Export::VHDL.generate(to_ir(top_name: top_name))
        end

        # Returns the Verilog module name for this component
        # Override in subclasses that use custom module names
        # @return [String] The module name used in generated Verilog
        def verilog_module_name
          self.name.split('::').last.underscore
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

        # Generate VHDL for this component and all its sub-modules
        # @param top_name [String] Optional name override for top module
        # @return [String] Complete VHDL with all module definitions
        def to_vhdl_hierarchy(top_name: nil)
          parts = []

          submodules = collect_submodule_classes
          submodules.each do |submod|
            parts << submod.to_vhdl
          end

          parts << to_vhdl(top_name: top_name)

          parts.join("\n\n")
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
        @local_dependency_graph = nil
        setup_ports_from_class_defs
        setup_ports
        setup_structure_instances
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

      # Automatically instantiate and wire sub-components from structure DSL
      def setup_structure_instances
        return if self.class._instance_defs.empty?

        # Instantiate all sub-components
        self.class._instance_defs.each do |inst_def|
          component_class = inst_def[:component_class]
          inst_name = inst_def[:name]
          params = inst_def[:parameters] || {}

          # Create the sub-component instance
          component = component_class.new("#{@name}.#{inst_name}", **params)
          @subcomponents[inst_name] = component

          # Make it accessible as an instance variable for convenience
          instance_variable_set(:"@#{inst_name}", component)
        end

        # Wire connections based on _connection_defs
        self.class._connection_defs.each do |conn_def|
          source = conn_def[:source]
          dest = conn_def[:dest]
          wire_connection(source, dest)
        end

        # Build local dependency graph for optimized propagation
        setup_local_dependency_graph
      end

      # Wire a connection between source and destination
      def wire_connection(source, dest)
        source_wire = resolve_wire(source)
        dest_wire = resolve_wire(dest)

        return unless source_wire && dest_wire

        # Connect source to destination
        self.class.connect(source_wire, dest_wire)
      end

      # Resolve a wire reference to an actual Wire object
      def resolve_wire(ref)
        if ref.is_a?(Symbol)
          # Reference to this component's port or signal
          @inputs[ref] || @outputs[ref] || @internal_signals[ref]
        elsif ref.is_a?(Array) && ref.length == 2
          # Reference to sub-component port: [:inst_name, :port_name]
          inst_name, port_name = ref
          component = @subcomponents[inst_name]
          return nil unless component

          component.inputs[port_name] || component.outputs[port_name]
        end
      end

      # Build dependency graph for sub-components
      def setup_local_dependency_graph
        return if @subcomponents.empty?

        @local_dependency_graph = DependencyGraph.new

        # Register all sub-components
        @subcomponents.each_value do |component|
          @local_dependency_graph.register(component)
        end

        # Build the graph
        @local_dependency_graph.build
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
        # If we have sub-components, propagate them using dependency graph
        if @local_dependency_graph && !@subcomponents.empty?
          propagate_subcomponents
        end

        # Execute behavior block if defined
        if self.class.behavior_defined?
          execute_behavior
        end
      end

      # Propagate sub-components using event-driven dependency graph
      def propagate_subcomponents
        # Mark all sub-components as dirty initially
        @local_dependency_graph.mark_all_dirty

        max_iterations = 100
        iterations = 0

        while @local_dependency_graph.dirty? && iterations < max_iterations
          dirty_components = @local_dependency_graph.consume_dirty

          dirty_components.each do |component|
            old_outputs = component.outputs.transform_values(&:get)
            component.propagate

            # Check if outputs changed and mark dependents
            component.outputs.each do |port_name, wire|
              if wire.get != old_outputs[port_name]
                @local_dependency_graph.dependents_of(component).each do |dep|
                  @local_dependency_graph.mark_dirty(dep)
                end
              end
            end
          end

          iterations += 1
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
