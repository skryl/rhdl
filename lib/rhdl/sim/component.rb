# frozen_string_literal: true

require 'active_support/concern'

module RHDL
  module Sim
    # Base class for all HDL components with simulation support
    #
    # Components are defined using class-level declarations:
    # - input/output: Define I/O ports
    # - wire: Define internal wires (signals)
    # - instance: Instantiate sub-components
    # - port: Connect signals to sub-component ports
    # - behavior: Define combinational logic
    #
    # @example Simple combinational component
    #   class MyAnd < Component
    #     input :a
    #     input :b
    #     output :y
    #
    #     behavior do
    #       y <= a & b
    #     end
    #   end
    #
    # @example Hierarchical component with sub-components
    #   class MyDatapath < Component
    #     input :a, width: 8
    #     input :b, width: 8
    #     output :result, width: 8
    #
    #     wire :alu_out, width: 8
    #
    #     instance :alu, ALU, width: 8
    #     instance :reg, Register, width: 8
    #
    #     port :a => [:alu, :a]
    #     port :b => [:alu, :b]
    #     port [:alu, :result] => :alu_out
    #     port :alu_out => [:reg, :d]
    #     port [:reg, :q] => :result
    #   end
    #
    class Component
      extend ActiveSupport::Concern
      attr_reader :name, :inputs, :outputs, :internal_signals

      # Class-level port definitions for behavior blocks
      class << self
        def inherited(subclass)
          super
          # Copy definitions to subclass
          subclass.instance_variable_set(:@_port_defs, (@_port_defs || []).dup)
          subclass.instance_variable_set(:@_signal_defs, (@_signal_defs || []).dup)
          subclass.instance_variable_set(:@_instance_defs, (@_instance_defs || []).dup)
          subclass.instance_variable_set(:@_connection_defs, (@_connection_defs || []).dup)
          subclass.instance_variable_set(:@_parameter_defs, (@_parameter_defs || {}).dup)
          subclass.instance_variable_set(:@_bundle_defs, (@_bundle_defs || []).dup)
          subclass.instance_variable_set(:@_vec_defs, (@_vec_defs || []).dup)
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

        def _parameter_defs
          @_parameter_defs ||= {}
        end

        def _bundle_defs
          @_bundle_defs ||= []
        end

        def _vec_defs
          @_vec_defs ||= []
        end

        # Define a component parameter with default value
        # Parameters can be referenced by symbol in width declarations
        # Supports computed defaults via Proc/lambda
        #
        # @param name [Symbol] Parameter name (becomes @name instance variable)
        # @param default [Integer, Proc] Default value or lambda for computed value
        #
        # @example Simple parameter
        #   parameter :width, default: 8
        #
        # @example Computed parameter (evaluated after other params are set)
        #   parameter :width, default: 8
        #   parameter :product_width, default: -> { @width * 2 }
        #
        def parameter(name, default:)
          _parameter_defs[name] = default
        end

        # Resolve a width value at class level using default parameter values
        # For computed (Proc) defaults, evaluates them using other defaults
        def resolve_class_width(width)
          case width
          when Integer
            width
          when Symbol
            val = _parameter_defs[width]
            case val
            when Proc
              # For class-level resolution, evaluate proc with defaults
              eval_context = Object.new
              _parameter_defs.each do |k, v|
                next if v.is_a?(Proc)
                eval_context.instance_variable_set(:"@#{k}", v)
              end
              eval_context.instance_exec(&val)
            when Integer
              val
            else
              1
            end
          else
            1
          end
        end

        # DSL-compatible _ports accessor for behavior module
        def _ports
          _port_defs.map do |pd|
            PortDef.new(pd[:name], pd[:direction], resolve_class_width(pd[:width]), pd[:default])
          end
        end

        # DSL-compatible _signals accessor for behavior module
        def _signals
          _signal_defs.map do |sd|
            SignalDef.new(sd[:name], resolve_class_width(sd[:width]))
          end
        end

        # Class-level input port definition
        # @param name [Symbol] Port name
        # @param width [Integer] Bit width (default: 1)
        # @param default [Integer, nil] Default value for unconnected ports (Verilog only)
        def input(name, width: 1, default: nil)
          _port_defs << { name: name, direction: :in, width: width, default: default }
        end

        # Class-level output port definition
        def output(name, width: 1)
          _port_defs << { name: name, direction: :out, width: width }
        end

        # Define an internal wire (signal)
        # Also handles backwards-compatible connection syntax when called with a Hash
        #
        # @param name [Symbol] Wire name (for signal definition)
        # @param width [Integer] Bit width (default: 1, only for signal definition)
        # @param mappings [Hash] Connection mappings (backwards compatible)
        #
        # @example Define internal wire
        #   wire :alu_out, width: 8
        #
        # @example Connection (backwards compatible, prefer 'port' instead)
        #   wire :a => [:alu, :a]
        #
        def wire(name = nil, width: 1, **mappings)
          if name.nil? && !mappings.empty?
            # Backwards compatibility: wire :a => [:alu, :a]
            # Ruby parses :a => [...] as keyword argument, so it ends up in mappings
            port(mappings)
          elsif name.is_a?(Hash)
            # Explicit hash argument: wire({:a => [:alu, :a]})
            port(name)
          else
            # New syntax: wire :signal_name, width: 8
            _signal_defs << { name: name, width: width }
          end
        end

        # Define a Bundle port (aggregate interface type)
        #
        # Bundles group multiple related signals into a single interface.
        # Fields are flattened to individual ports in the generated Verilog.
        #
        # @param name [Symbol] Bundle instance name
        # @param bundle_class [Class] Bundle class (must inherit from Bundle)
        # @param direction [Symbol] :input or :output (default: :input)
        # @param flipped [Boolean] Reverse all field directions (default: false)
        #
        # @example Define a bundle
        #   class AxiLite < Bundle
        #     field :awaddr, width: 32, direction: :output
        #     field :awvalid, width: 1, direction: :output
        #     field :awready, width: 1, direction: :input
        #   end
        #
        # @example Use as input (producer interface)
        #   input_bundle :axi, AxiLite
        #
        # @example Use as output (consumer interface - flipped)
        #   output_bundle :axi, AxiLite  # equivalent to flipped: true
        #
        def input_bundle(name, bundle_class, flipped: false)
          _bundle_defs << {
            name: name,
            bundle_class: bundle_class,
            direction: :input,
            flipped: flipped
          }

          # Add flattened ports
          bundle_class.fields.each do |field|
            effective_dir = flipped ? field.flipped_direction : field.direction
            port_name = "#{name}_#{field.name}".to_sym

            if effective_dir == :input
              _port_defs << { name: port_name, direction: :in, width: field.width, default: nil }
            else
              _port_defs << { name: port_name, direction: :out, width: field.width }
            end
          end
        end

        # Define an output Bundle port (flipped by default for consumer interface)
        #
        # @param name [Symbol] Bundle instance name
        # @param bundle_class [Class] Bundle class
        # @param flipped [Boolean] Reverse field directions (default: true for output)
        #
        def output_bundle(name, bundle_class, flipped: true)
          _bundle_defs << {
            name: name,
            bundle_class: bundle_class,
            direction: :output,
            flipped: flipped
          }

          # Add flattened ports
          bundle_class.fields.each do |field|
            effective_dir = flipped ? field.flipped_direction : field.direction
            port_name = "#{name}_#{field.name}".to_sym

            if effective_dir == :input
              _port_defs << { name: port_name, direction: :in, width: field.width, default: nil }
            else
              _port_defs << { name: port_name, direction: :out, width: field.width }
            end
          end
        end

        # Define a Vec (hardware array) port or signal
        #
        # Vec creates an array of signals that can be indexed at runtime
        # (generates mux/demux logic) or at elaboration time (constant index).
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements (can reference parameter)
        # @param width [Integer, Symbol] Width of each element (default: 1)
        # @param direction [Symbol] :input, :output, or nil for internal (default: nil)
        #
        # @example Internal Vec (array of wires)
        #   vec :regs, count: 32, width: 64
        #
        # @example Input Vec (array of input ports)
        #   input_vec :data_in, count: 4, width: 8
        #
        # @example Output Vec (array of output ports)
        #   output_vec :data_out, count: 4, width: 8
        #
        # @example Parameterized Vec
        #   parameter :depth, default: 32
        #   vec :registers, count: :depth, width: 64
        #
        def vec(name, count:, width: 1, direction: nil)
          _vec_defs << {
            name: name,
            count: count,
            width: width,
            direction: direction
          }

          # For ports, add flattened individual ports
          resolved_count = resolve_class_width(count)
          if direction == :input || direction == :output
            resolved_count.times do |i|
              port_name = "#{name}_#{i}".to_sym
              if direction == :input
                _port_defs << { name: port_name, direction: :in, width: width, default: nil }
              else
                _port_defs << { name: port_name, direction: :out, width: width }
              end
            end
          end
        end

        # Define an input Vec (array of input ports)
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements
        # @param width [Integer, Symbol] Width of each element
        #
        # @example
        #   input_vec :data_in, count: 4, width: 8
        #   # Creates: data_in_0, data_in_1, data_in_2, data_in_3 (all 8-bit inputs)
        #
        def input_vec(name, count:, width: 1)
          vec(name, count: count, width: width, direction: :input)
        end

        # Define an output Vec (array of output ports)
        #
        # @param name [Symbol] Vec instance name
        # @param count [Integer, Symbol] Number of elements
        # @param width [Integer, Symbol] Width of each element
        #
        # @example
        #   output_vec :data_out, count: 4, width: 8
        #   # Creates: data_out_0, data_out_1, data_out_2, data_out_3 (all 8-bit outputs)
        #
        def output_vec(name, count:, width: 1)
          vec(name, count: count, width: width, direction: :output)
        end

        # Define a sub-component instance (class-level)
        #
        # @param name [Symbol] Instance name
        # @param component_class [Class] Component class to instantiate
        # @param params [Hash] Parameters to pass to the component
        #
        # @example
        #   class MyDatapath < Component
        #     input :a, width: 8
        #     output :result, width: 8
        #
        #     instance :alu, ALU, width: 8
        #     instance :reg, Register, width: 8
        #
        #     port :a => [:alu, :a]
        #     port [:alu, :result] => [:reg, :d]
        #     port [:reg, :q] => :result
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
        #   - port :clk => [:pc, :clk]              # Signal to instance port
        #   - port :clk => [[:pc, :clk], [:acc, :clk]]  # Signal to multiple ports
        #   - port [:alu, :result] => :result      # Instance output to signal
        #   - port [:alu, :result] => [:reg, :d]   # Instance to instance
        #
        def port(mappings)
          mappings.each do |source, dest|
            _connection_defs << { source: source, dest: dest }

            if dest.is_a?(Array) && dest.first.is_a?(Array)
              # Multiple destinations: port :clk => [[:pc, :clk], [:acc, :clk]]
              dest.each { |d| add_port_connection(source, d) }
            elsif dest.is_a?(Array) && dest.length == 2
              # Single destination: port :clk => [:pc, :clk]
              add_port_connection(source, dest)
            elsif source.is_a?(Array) && source.length == 2
              # Instance output to signal: port [:alu, :result] => :result
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
        #   class MyAnd < Component
        #     input :a
        #     input :b
        #     output :y
        #
        #     behavior do
        #       y <= a & b
        #     end
        #   end
        #
        def behavior(**options, &block)
          @_behavior_block = BehaviorBlockDef.new(block, **options)
        end

        # Simple value object to hold behavior block definition
        class BehaviorBlockDef
          attr_reader :block, :options

          def initialize(block, **options)
            @block = block
            @options = options
          end
        end

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

        # Generate VHDL from the component
        def to_vhdl(top_name: nil)
          RHDL::Export::VHDL.generate(to_ir(top_name: top_name))
        end

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

        # Generate IR from MemoryDSL definitions
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

      # Simple structs for port/signal definitions
      PortDef = Struct.new(:name, :direction, :width, :default)
      SignalDef = Struct.new(:name, :width)

      def initialize(name = nil, **kwargs)
        @name = name || self.class.name.split('::').last.downcase
        @inputs = {}
        @outputs = {}
        @internal_signals = {}
        @subcomponents = {}
        @propagation_delay = 0
        @local_dependency_graph = nil
        setup_parameters(kwargs)
        setup_ports_from_class_defs
        setup_ports
        setup_structure_instances
      end

      # Set parameter values from kwargs or use defaults from class definition
      # Handles computed defaults (Procs) by evaluating them after simple params are set
      def setup_parameters(kwargs)
        # First pass: set non-computed parameters
        self.class._parameter_defs.each do |name, default|
          next if default.is_a?(Proc)
          ivar = :"@#{name}"
          value = kwargs.fetch(name, default)
          instance_variable_set(ivar, value)
        end

        # Second pass: evaluate computed parameters
        self.class._parameter_defs.each do |name, default|
          next unless default.is_a?(Proc)
          ivar = :"@#{name}"
          # Use kwarg value if provided, otherwise compute from proc
          value = kwargs.key?(name) ? kwargs[name] : instance_exec(&default)
          instance_variable_set(ivar, value)
        end
      end

      # Resolve a width value - either an Integer or a Symbol referencing a parameter
      def resolve_width(width)
        case width
        when Integer
          width
        when Symbol
          instance_variable_get(:"@#{width}") || 1
        else
          1
        end
      end

      # Create ports from class-level definitions
      def setup_ports_from_class_defs
        self.class._port_defs.each do |pd|
          w = resolve_width(pd[:width])
          case pd[:direction]
          when :in
            input(pd[:name], width: w)
          when :out
            output(pd[:name], width: w)
          end
        end
        self.class._signal_defs.each do |sd|
          w = resolve_width(sd[:width])
          signal(sd[:name], width: w)
        end

        # Setup Vec instances
        setup_vecs_from_class_defs

        # Setup Bundle instances
        setup_bundles_from_class_defs
      end

      # Setup Vec instances from class-level definitions
      def setup_vecs_from_class_defs
        @vecs = {}

        self.class._vec_defs.each do |vd|
          count = resolve_width(vd[:count])
          width = resolve_width(vd[:width])
          direction = vd[:direction]

          vec_inst = VecInstance.new(
            vd[:name],
            count: count,
            width: width,
            component: self,
            direction: direction
          )

          @vecs[vd[:name]] = vec_inst
          instance_variable_set(:"@#{vd[:name]}", vec_inst)
        end
      end

      # Setup Bundle instances from class-level definitions
      def setup_bundles_from_class_defs
        @bundles = {}

        self.class._bundle_defs.each do |bd|
          bundle_inst = BundleInstance.new(
            bd[:name],
            bd[:bundle_class],
            self,
            flipped: bd[:flipped]
          )

          @bundles[bd[:name]] = bundle_inst
          instance_variable_set(:"@#{bd[:name]}", bundle_inst)
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
      # Handles fan-out where dest can be an array of destinations
      def wire_connection(source, dest)
        source_wire = resolve_wire(source)
        return unless source_wire

        # Check if dest is a fan-out (array of arrays)
        # e.g., [[:registers, :clk], [:pc, :clk], ...]
        if dest.is_a?(Array) && dest.first.is_a?(Array)
          # Fan-out: connect source to each destination
          dest.each do |single_dest|
            dest_wire = resolve_wire(single_dest)
            self.class.connect(source_wire, dest_wire) if dest_wire
          end
        else
          # Single destination
          dest_wire = resolve_wire(dest)
          self.class.connect(source_wire, dest_wire) if dest_wire
        end
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
        # If we have sub-components, propagate them using two-phase semantics
        if @local_dependency_graph && !@subcomponents.empty?
          propagate_subcomponents
        elsif self.class.behavior_defined?
          # No subcomponents, just execute behavior
          execute_behavior
        end
      end

      # Propagate sub-components using Verilog-style two-phase semantics
      # This ensures proper non-blocking assignment behavior for sequential components:
      # 1. Propagate combinational components until stable
      # 2. Execute parent's behavior block (sets combinational outputs like latch wires)
      # 3. All sequential components sample their inputs simultaneously
      # 4. All sequential components update their outputs
      # 5. Repeat until stable (but behavior only runs when there's a rising edge)
      def propagate_subcomponents
        # Separate combinational and sequential components
        combinational = []
        sequential = []

        @subcomponents.each_value do |comp|
          if comp.is_a?(SequentialComponent)
            sequential << comp
          else
            combinational << comp
          end
        end

        # Check if any sequential component will see a rising edge
        # This determines if behavior should run to set up latch wires
        # We only want to run behavior ONCE when there's a rising edge
        has_pending_edge = sequential.any? do |comp|
          clk_wire = comp.inputs[:clk]
          prev_clk = comp.instance_variable_get(:@prev_clk) || 0
          clk_wire && prev_clk == 0 && clk_wire.get == 1
        end

        # Track whether we've already executed behavior while clk=1
        # This prevents multiple propagate calls from overwriting latch wire values
        # Once we've run behavior on a rising edge, don't run again until clk goes low
        @_last_behavior_clk ||= nil
        current_clk = @inputs[:clk]&.get

        # If clk went 0->1 (rising edge), we need to run behavior
        # If clk is still 1 and we already ran behavior, don't run again
        # If clk went back to 0, reset tracking
        if current_clk == 0
          @_behavior_ran_this_high = false
        end
        behavior_already_ran = current_clk == 1 && @_behavior_ran_this_high

        max_iterations = 100
        iterations = 0

        loop do
          changed = false

          # Phase 1: Propagate all combinational components until stable
          comb_iterations = 0
          loop do
            comb_changed = false

            combinational.each do |component|
              old_outputs = component.outputs.transform_values(&:get)
              component.propagate

              component.outputs.each do |_port_name, wire|
                if wire.get != old_outputs[_port_name]
                  comb_changed = true
                  changed = true
                end
              end
            end

            comb_iterations += 1
            break unless comb_changed && comb_iterations < max_iterations
          end

          # Phase 2: Execute parent's behavior block
          # Only run on first iteration when there's a pending rising edge
          # This ensures latch wires are set based on values BEFORE registers update
          # On subsequent propagates (same clock value), behavior doesn't run
          # to prevent overwriting latch wires with post-update values
          should_run_behavior = self.class.behavior_defined? &&
                                !behavior_already_ran &&
                                (has_pending_edge ? iterations == 0 : true)
          if should_run_behavior
            execute_behavior
            @_behavior_ran_this_high = true if current_clk == 1

            # Phase 2b: Re-propagate combinational components after behavior
            # This is critical for components like hazard_unit that depend on
            # behavior outputs (e.g., take_branch). Without this, hazard_unit
            # would see stale values and generate wrong flush signals.
            comb_iterations = 0
            loop do
              comb_changed = false

              combinational.each do |component|
                old_outputs = component.outputs.transform_values(&:get)
                component.propagate

                component.outputs.each do |port_name, wire|
                  if wire.get != old_outputs[port_name]
                    comb_changed = true
                    changed = true
                  end
                end
              end

              comb_iterations += 1
              break unless comb_changed && comb_iterations < max_iterations
            end
          end

          # Phase 3: All sequential components SAMPLE inputs (don't update outputs yet)
          rising_edges = []
          # DEBUG: Show phase start
          puts "  [PHASE 3] iter=#{iterations} Sequential SAMPLE start" if ENV['DEBUG_PHASES']
          sequential.each do |component|
            if component.respond_to?(:sample_inputs)
              puts "    [PHASE 3] Calling sample_inputs on #{component.name}" if ENV['DEBUG_PHASES']
              is_rising = component.sample_inputs
              rising_edges << component if is_rising
            end
          end
          puts "  [PHASE 3] iter=#{iterations} done, rising_edges=#{rising_edges.map(&:name)}" if ENV['DEBUG_PHASES']

          # Phase 4: All sequential components UPDATE outputs (for those with rising edge)
          puts "  [PHASE 4] iter=#{iterations} Sequential UPDATE start" if ENV['DEBUG_PHASES']
          rising_edges.each do |component|
            puts "    [PHASE 4] Calling update_outputs on #{component.name}" if ENV['DEBUG_PHASES']
            old_outputs = component.outputs.transform_values(&:get)
            component.update_outputs

            component.outputs.each do |_port_name, wire|
              if wire.get != old_outputs[_port_name]
                changed = true
              end
            end
          end

          # For sequential components that didn't have a rising edge, we still need
          # to give them a chance to run combinational logic (behavior blocks).
          # BUT we must NOT call their propagate() method because that would call
          # sample_inputs and update_outputs together, violating two-phase semantics.
          # Instead, just call execute_behavior if they have one.
          (sequential - rising_edges).each do |component|
            if component.class.respond_to?(:behavior_defined?) && component.class.behavior_defined?
              puts "    [NO-EDGE] Executing behavior for #{component.name}" if ENV['DEBUG_PHASES']
              old_outputs = component.outputs.transform_values(&:get)
              component.execute_behavior if component.respond_to?(:execute_behavior)

              component.outputs.each do |_port_name, wire|
                if wire.get != old_outputs[_port_name]
                  changed = true
                end
              end
            end
          end

          iterations += 1
          break unless changed && iterations < max_iterations
        end
      end

      # Execute the behavior block for simulation
      def execute_behavior
        return unless self.class._behavior_block

        block = self.class._behavior_block
        ctx = BehaviorContext.new(self)
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
