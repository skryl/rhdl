# HDL Simulation Engine
# Provides the core simulation infrastructure for gate-level and behavioral simulation

require 'active_support/concern'

module RHDL
  module HDL
    # Represents a signal value in the simulation
    # Supports multi-bit values and special states (X = unknown, Z = high-impedance)
    class SignalValue
      attr_reader :width, :value

      # Special values
      X = :unknown
      Z = :high_z

      def initialize(value, width: 1)
        @width = width
        @value = normalize(value)
      end

      def normalize(val)
        return val if val == X || val == Z
        val.is_a?(Integer) ? val & ((1 << @width) - 1) : val
      end

      def [](index)
        return X if @value == X
        return Z if @value == Z
        (@value >> index) & 1
      end

      def to_i
        @value.is_a?(Integer) ? @value : 0
      end

      def to_s
        return "X" * @width if @value == X
        return "Z" * @width if @value == Z
        @value.to_s(2).rjust(@width, '0')
      end

      def ==(other)
        other_val = other.is_a?(SignalValue) ? other.value : other
        @value == other_val
      end

      def zero?
        @value == 0
      end

      def high?
        @value != 0 && @value != X && @value != Z
      end
    end

    # A wire/signal in the circuit that can be connected and propagated
    class Wire
      attr_reader :name, :width, :sinks
      attr_accessor :value, :driver

      def initialize(name, width: 1)
        @name = name
        @width = width
        @value = SignalValue.new(0, width: width)
        @driver = nil
        @sinks = []
        @listeners = []
      end

      def set(val)
        new_val = val.is_a?(SignalValue) ? val : SignalValue.new(val, width: @width)
        if new_val.value != @value.value
          @value = new_val
          notify_listeners
        end
      end

      def get
        @value.to_i
      end

      def bit(index)
        @value[index]
      end

      def on_change(&block)
        @listeners << block
      end

      def add_sink(wire)
        @sinks << wire
      end

      def notify_listeners
        @listeners.each { |l| l.call(@value) }
      end

      def to_s
        "#{@name}[#{@width}]=#{@value}"
      end
    end

    # Clock signal with configurable period
    class Clock < Wire
      attr_reader :period, :cycle_count

      def initialize(name, period: 10)
        super(name, width: 1)
        @period = period
        @cycle_count = 0
        @high = false
      end

      def tick
        @high = !@high
        set(@high ? 1 : 0)
        @cycle_count += 1 if @high  # Count rising edges
      end

      def rising_edge?
        @high && @value.to_i == 1
      end

      def falling_edge?
        !@high && @value.to_i == 0
      end
    end

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

      # Behavior block definition
      class BehaviorBlockDef
        attr_reader :block, :options

        def initialize(block, **options)
          @block = block
          @options = options
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

    # Context for evaluating behavior blocks in simulation mode
    class BehaviorSimContext
      def initialize(component)
        @component = component
        @assignments = []

        # Create accessor methods for all inputs and outputs
        component.inputs.each do |name, wire|
          define_singleton_method(name) { SimSignalProxy.new(name, wire, :input, self) }
        end
        component.outputs.each do |name, wire|
          define_singleton_method(name) { SimOutputProxy.new(name, wire, self) }
        end
        component.internal_signals.each do |name, wire|
          define_singleton_method(name) { SimOutputProxy.new(name, wire, self) }
        end
      end

      def evaluate(&block)
        @assignments.clear
        instance_eval(&block)

        # Apply all collected assignments
        @assignments.each do |assignment|
          assignment[:wire].set(assignment[:value])
        end
      end

      def record_assignment(wire, value)
        @assignments << { wire: wire, value: value }
      end

      # Helper for conditional expressions (mux)
      def mux(condition, when_true, when_false)
        cond_val = resolve_value(condition)
        cond_val != 0 ? resolve_value(when_true) : resolve_value(when_false)
      end

      # Helper for creating literal values with explicit width
      def lit(value, width:)
        value & ((1 << width) - 1)
      end

      # Helper for concatenation
      def cat(*signals)
        result = 0
        offset = 0
        signals.reverse.each do |sig|
          val, width = resolve_value_with_width(sig)
          result |= (val << offset)
          offset += width
        end
        result
      end

      private

      def resolve_value(sig)
        case sig
        when SimSignalProxy, SimOutputProxy
          sig.value
        when Integer
          sig
        else
          sig.respond_to?(:value) ? sig.value : sig.to_i
        end
      end

      def resolve_value_with_width(sig)
        case sig
        when SimSignalProxy, SimOutputProxy
          [sig.value, sig.width]
        when Integer
          [sig, sig == 0 ? 1 : sig.bit_length]
        else
          [sig.to_i, 8]
        end
      end
    end

    # Proxy for input signals in simulation behavior blocks
    # Returns SimValueProxy objects for chained operations
    class SimSignalProxy
      attr_reader :name, :wire, :width

      def initialize(name, wire, direction, context)
        @name = name
        @wire = wire
        @width = wire.width
        @direction = direction
        @context = context
      end

      def value
        @wire.get
      end

      # Bitwise operators - return SimValueProxy for chaining
      def &(other)
        SimValueProxy.new(compute(:&, other), @width, @context)
      end

      def |(other)
        SimValueProxy.new(compute(:|, other), @width, @context)
      end

      def ^(other)
        SimValueProxy.new(compute(:^, other), @width, @context)
      end

      def ~
        mask = (1 << @width) - 1
        SimValueProxy.new((~value) & mask, @width, @context)
      end

      # Arithmetic operators
      def +(other)
        SimValueProxy.new(compute(:+, other), @width + 1, @context)
      end

      def -(other)
        SimValueProxy.new(compute(:-, other), @width, @context)
      end

      def *(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        SimValueProxy.new(compute(:*, other), @width + other_width, @context)
      end

      def /(other)
        other_val = resolve(other)
        result = other_val != 0 ? value / other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      def %(other)
        other_val = resolve(other)
        result = other_val != 0 ? value % other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      # Shift operators
      def <<(amount)
        mask = (1 << @width) - 1
        SimValueProxy.new((value << resolve(amount)) & mask, @width, @context)
      end

      def >>(amount)
        SimValueProxy.new(value >> resolve(amount), @width, @context)
      end

      # Comparison operators
      def ==(other)
        SimValueProxy.new((value == resolve(other)) ? 1 : 0, 1, @context)
      end

      def !=(other)
        SimValueProxy.new((value != resolve(other)) ? 1 : 0, 1, @context)
      end

      def <(other)
        SimValueProxy.new((value < resolve(other)) ? 1 : 0, 1, @context)
      end

      def >(other)
        SimValueProxy.new((value > resolve(other)) ? 1 : 0, 1, @context)
      end

      def <=(other)
        SimValueProxy.new((value <= resolve(other)) ? 1 : 0, 1, @context)
      end

      def >=(other)
        SimValueProxy.new((value >= resolve(other)) ? 1 : 0, 1, @context)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          # Handle both ascending (0..3) and descending (3..0) ranges
          # In HDL, bit slices are typically written high..low (e.g., 7..4)
          high = [index.begin, index.end].max
          low = [index.begin, index.end].min
          slice_width = high - low + 1
          mask = (1 << slice_width) - 1
          SimValueProxy.new((value >> low) & mask, slice_width, @context)
        else
          SimValueProxy.new((value >> index) & 1, 1, @context)
        end
      end

      # Concatenation
      def concat(*others)
        result = value
        offset = @width
        total_width = @width
        others.each do |other|
          other_val = resolve(other)
          other_width = other.respond_to?(:width) ? other.width : (other_val == 0 ? 1 : other_val.bit_length)
          result = (other_val << offset) | result
          offset += other_width
          total_width += other_width
        end
        SimValueProxy.new(result, total_width, @context)
      end

      # Replication
      def replicate(times)
        result = 0
        times.times do |i|
          result |= (value << (i * @width))
        end
        SimValueProxy.new(result, @width * times, @context)
      end

      def to_i
        value
      end

      # Coercion support for Integer operations (e.g., 1 & proxy)
      def coerce(other)
        [SimValueProxy.new(other, other == 0 ? 1 : other.bit_length, @context), self]
      end

      private

      def compute(op, other)
        other_val = resolve(other)
        result = value.send(op, other_val)
        mask = (1 << @width) - 1
        result & mask
      end

      def resolve(other)
        case other
        when SimSignalProxy, SimOutputProxy, SimValueProxy
          other.value
        when Integer
          other
        else
          other.respond_to?(:value) ? other.value : other.to_i
        end
      end
    end

    # Proxy for intermediate computed values in simulation behavior blocks
    # Allows operator chaining while tracking width
    class SimValueProxy
      attr_reader :width

      def initialize(value, width, context)
        @value = value
        @width = width
        @context = context
      end

      def value
        @value
      end

      # Bitwise operators
      def &(other)
        SimValueProxy.new(compute(:&, other), result_width(other), @context)
      end

      def |(other)
        SimValueProxy.new(compute(:|, other), result_width(other), @context)
      end

      def ^(other)
        SimValueProxy.new(compute(:^, other), result_width(other), @context)
      end

      def ~
        mask = (1 << @width) - 1
        SimValueProxy.new((~@value) & mask, @width, @context)
      end

      # Arithmetic operators
      def +(other)
        SimValueProxy.new(compute(:+, other), result_width(other) + 1, @context)
      end

      def -(other)
        SimValueProxy.new(compute(:-, other), result_width(other), @context)
      end

      def *(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        SimValueProxy.new(compute(:*, other), @width + other_width, @context)
      end

      def /(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value / other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      def %(other)
        other_val = resolve(other)
        result = other_val != 0 ? @value % other_val : 0
        SimValueProxy.new(result, @width, @context)
      end

      # Shift operators
      def <<(amount)
        mask = (1 << @width) - 1
        SimValueProxy.new((@value << resolve(amount)) & mask, @width, @context)
      end

      def >>(amount)
        SimValueProxy.new(@value >> resolve(amount), @width, @context)
      end

      # Comparison operators
      def ==(other)
        SimValueProxy.new((@value == resolve(other)) ? 1 : 0, 1, @context)
      end

      def !=(other)
        SimValueProxy.new((@value != resolve(other)) ? 1 : 0, 1, @context)
      end

      def <(other)
        SimValueProxy.new((@value < resolve(other)) ? 1 : 0, 1, @context)
      end

      def >(other)
        SimValueProxy.new((@value > resolve(other)) ? 1 : 0, 1, @context)
      end

      def <=(other)
        SimValueProxy.new((@value <= resolve(other)) ? 1 : 0, 1, @context)
      end

      def >=(other)
        SimValueProxy.new((@value >= resolve(other)) ? 1 : 0, 1, @context)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          slice_width = index.max - index.min + 1
          mask = (1 << slice_width) - 1
          SimValueProxy.new((@value >> index.min) & mask, slice_width, @context)
        else
          SimValueProxy.new((@value >> index) & 1, 1, @context)
        end
      end

      def to_i
        @value
      end

      # Coercion support
      def coerce(other)
        [SimValueProxy.new(other, other == 0 ? 1 : other.bit_length, @context), self]
      end

      private

      def compute(op, other)
        other_val = resolve(other)
        result = @value.send(op, other_val)
        mask = (1 << @width) - 1
        result & mask
      end

      def result_width(other)
        other_width = other.respond_to?(:width) ? other.width : 8
        [@width, other_width].max
      end

      def resolve(other)
        case other
        when SimSignalProxy, SimOutputProxy, SimValueProxy
          other.value
        when Integer
          other
        else
          other.respond_to?(:value) ? other.value : other.to_i
        end
      end
    end

    # Proxy for output signals that captures assignments
    class SimOutputProxy < SimSignalProxy
      def initialize(name, wire, context)
        super(name, wire, :output, context)
      end

      # The <= operator for assignments
      def <=(expr)
        val = resolve(expr)
        mask = (1 << @width) - 1
        @context.record_assignment(@wire, val & mask)
      end

      private

      def resolve(other)
        case other
        when SimSignalProxy, SimOutputProxy, SimValueProxy
          other.value
        when Integer
          other
        else
          other.respond_to?(:value) ? other.value : other.to_i
        end
      end
    end

    # Context for evaluating behavior blocks in synthesis mode
    # Generates IR expressions instead of computing values
    class BehaviorSynthContext
      attr_reader :assignments

      def initialize(component_class)
        @component_class = component_class
        @assignments = []
        @port_widths = {}

        # Build port width map
        component_class._port_defs.each do |pd|
          @port_widths[pd[:name]] = pd[:width]
        end
        component_class._signal_defs.each do |sd|
          @port_widths[sd[:name]] = sd[:width]
        end

        # Create accessor methods for all ports and signals
        component_class._port_defs.each do |pd|
          if pd[:direction] == :out
            define_singleton_method(pd[:name]) { SynthOutputProxy.new(pd[:name], pd[:width], self) }
          else
            define_singleton_method(pd[:name]) { SynthSignalProxy.new(pd[:name], pd[:width]) }
          end
        end
        component_class._signal_defs.each do |sd|
          define_singleton_method(sd[:name]) { SynthOutputProxy.new(sd[:name], sd[:width], self) }
        end
      end

      def evaluate(&block)
        @assignments.clear
        instance_eval(&block)
      end

      def record_assignment(target_name, target_width, expr)
        @assignments << { target: target_name, width: target_width, expr: expr }
      end

      # Convert collected assignments to IR
      def to_ir_assigns
        @assignments.map do |assignment|
          ir_expr = assignment[:expr].to_ir
          ir_expr = resize_ir(ir_expr, assignment[:width]) if ir_expr.width != assignment[:width]
          RHDL::Export::IR::Assign.new(target: assignment[:target], expr: ir_expr)
        end
      end

      # Helper for conditional expressions (mux)
      def mux(condition, when_true, when_false)
        cond = wrap_expr(condition)
        true_expr = wrap_expr(when_true)
        false_expr = wrap_expr(when_false)
        width = [true_expr.width, false_expr.width].max
        SynthMux.new(cond, true_expr, false_expr, width)
      end

      # Helper for creating literal values with explicit width
      def lit(value, width:)
        SynthLiteral.new(value, width)
      end

      # Helper for concatenation
      def cat(*signals)
        parts = signals.map { |s| wrap_expr(s) }
        total_width = parts.sum(&:width)
        SynthConcat.new(parts, total_width)
      end

      private

      def wrap_expr(expr)
        case expr
        when SynthExpr
          expr
        when Integer
          SynthLiteral.new(expr, expr == 0 ? 1 : expr.bit_length)
        else
          expr
        end
      end

      def resize_ir(ir_expr, target_width)
        RHDL::Export::IR::Resize.new(expr: ir_expr, width: target_width)
      end
    end

    # Base class for synthesis expressions
    class SynthExpr
      attr_reader :width

      def initialize(width)
        @width = width
      end

      # Bitwise operators
      def &(other)
        SynthBinaryOp.new(:&, self, wrap(other), result_width(other))
      end

      def |(other)
        SynthBinaryOp.new(:|, self, wrap(other), result_width(other))
      end

      def ^(other)
        SynthBinaryOp.new(:^, self, wrap(other), result_width(other))
      end

      def ~
        SynthUnaryOp.new(:~, self, @width)
      end

      # Arithmetic operators
      def +(other)
        SynthBinaryOp.new(:+, self, wrap(other), result_width(other) + 1)
      end

      def -(other)
        SynthBinaryOp.new(:-, self, wrap(other), result_width(other))
      end

      def *(other)
        other_width = other.is_a?(SynthExpr) ? other.width : bit_width(other)
        SynthBinaryOp.new(:*, self, wrap(other), @width + other_width)
      end

      def /(other)
        SynthBinaryOp.new(:/, self, wrap(other), @width)
      end

      def %(other)
        SynthBinaryOp.new(:%, self, wrap(other), @width)
      end

      # Shift operators
      def <<(amount)
        SynthBinaryOp.new(:<<, self, wrap(amount), @width)
      end

      def >>(amount)
        SynthBinaryOp.new(:>>, self, wrap(amount), @width)
      end

      # Comparison operators (result is 1 bit)
      def ==(other)
        SynthBinaryOp.new(:==, self, wrap(other), 1)
      end

      def !=(other)
        SynthBinaryOp.new(:!=, self, wrap(other), 1)
      end

      def <(other)
        SynthBinaryOp.new(:<, self, wrap(other), 1)
      end

      def >(other)
        SynthBinaryOp.new(:>, self, wrap(other), 1)
      end

      def <=(other)
        # Use different symbol to avoid conflict with assignment
        SynthBinaryOp.new(:le, self, wrap(other), 1)
      end

      def >=(other)
        SynthBinaryOp.new(:>=, self, wrap(other), 1)
      end

      # Bit selection
      def [](index)
        if index.is_a?(Range)
          slice_width = index.max - index.min + 1
          SynthSlice.new(self, index, slice_width)
        else
          SynthBitSelect.new(self, index)
        end
      end

      # Concatenation
      def concat(*others)
        parts = [self] + others.map { |o| wrap(o) }
        total_width = parts.sum(&:width)
        SynthConcat.new(parts, total_width)
      end

      # Replication
      def replicate(times)
        SynthReplicate.new(self, times, @width * times)
      end

      protected

      def wrap(other)
        return other if other.is_a?(SynthExpr)
        SynthLiteral.new(other, bit_width(other))
      end

      def result_width(other)
        other_width = other.is_a?(SynthExpr) ? other.width : bit_width(other)
        [@width, other_width].max
      end

      def bit_width(value)
        return 1 if value == 0 || value == 1
        value.is_a?(Integer) ? [value.bit_length, 1].max : 1
      end
    end

    # Synthesis signal reference
    class SynthSignalProxy < SynthExpr
      attr_reader :name

      def initialize(name, width)
        @name = name
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Signal.new(name: @name, width: @width)
      end
    end

    # Synthesis output proxy that captures assignments
    class SynthOutputProxy < SynthSignalProxy
      def initialize(name, width, context)
        super(name, width)
        @context = context
      end

      # The <= operator for assignments
      def <=(expr)
        synth_expr = expr.is_a?(SynthExpr) ? expr : SynthLiteral.new(expr, bit_width(expr))
        @context.record_assignment(@name, @width, synth_expr)
      end

      private

      def bit_width(value)
        return 1 if value == 0 || value == 1
        value.is_a?(Integer) ? [value.bit_length, 1].max : 1
      end
    end

    # Synthesis literal value
    class SynthLiteral < SynthExpr
      attr_reader :value

      def initialize(value, width)
        @value = value
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Literal.new(value: @value, width: @width)
      end
    end

    # Synthesis binary operation
    class SynthBinaryOp < SynthExpr
      attr_reader :op, :left, :right

      def initialize(op, left, right, width)
        @op = op
        @left = left
        @right = right
        super(width)
      end

      def to_ir
        # Handle the :le operator (<=) which we renamed to avoid conflict
        ir_op = @op == :le ? :<= : @op
        RHDL::Export::IR::BinaryOp.new(
          op: ir_op,
          left: @left.to_ir,
          right: resize_ir(@right.to_ir, @left.width),
          width: @width
        )
      end

      private

      def resize_ir(ir_expr, target_width)
        return ir_expr if ir_expr.width == target_width
        RHDL::Export::IR::Resize.new(expr: ir_expr, width: target_width)
      end
    end

    # Synthesis unary operation
    class SynthUnaryOp < SynthExpr
      attr_reader :op, :operand

      def initialize(op, operand, width)
        @op = op
        @operand = operand
        super(width)
      end

      def to_ir
        RHDL::Export::IR::UnaryOp.new(op: @op, operand: @operand.to_ir, width: @width)
      end
    end

    # Synthesis bit select
    class SynthBitSelect < SynthExpr
      attr_reader :base, :index

      def initialize(base, index)
        @base = base
        @index = index
        super(1)
      end

      def to_ir
        RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @index..@index, width: 1)
      end
    end

    # Synthesis slice
    class SynthSlice < SynthExpr
      attr_reader :base, :range

      def initialize(base, range, width)
        @base = base
        @range = range
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Slice.new(base: @base.to_ir, range: @range, width: @width)
      end
    end

    # Synthesis concatenation
    class SynthConcat < SynthExpr
      attr_reader :parts

      def initialize(parts, width)
        @parts = parts
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Concat.new(parts: @parts.map(&:to_ir), width: @width)
      end
    end

    # Synthesis replication
    class SynthReplicate < SynthExpr
      attr_reader :expr, :times

      def initialize(expr, times, width)
        @expr = expr
        @times = times
        super(width)
      end

      def to_ir
        parts = Array.new(@times) { @expr.to_ir }
        RHDL::Export::IR::Concat.new(parts: parts, width: @width)
      end
    end

    # Synthesis mux (conditional)
    class SynthMux < SynthExpr
      attr_reader :condition, :when_true, :when_false

      def initialize(condition, when_true, when_false, width)
        @condition = condition
        @when_true = when_true
        @when_false = when_false
        super(width)
      end

      def to_ir
        RHDL::Export::IR::Mux.new(
          condition: @condition.to_ir,
          when_true: @when_true.to_ir,
          when_false: @when_false.to_ir,
          width: @width
        )
      end
    end

    # Simulation scheduler for event-driven simulation
    class Simulator
      attr_reader :time, :components

      def initialize
        @time = 0
        @components = []
        @clocks = []
        @event_queue = []
      end

      def add_component(component)
        @components << component
        component
      end

      def add_clock(clock)
        @clocks << clock
        clock
      end

      # Run simulation for n clock cycles
      def run(cycles)
        cycles.times do
          @clocks.each(&:tick)
          propagate_all
          @clocks.each(&:tick)
          propagate_all
          @time += 1
        end
      end

      # Single step - propagate all signals
      def step
        propagate_all
      end

      def propagate_all
        # Keep propagating until stable
        max_iterations = 1000
        iterations = 0
        begin
          changed = false
          @components.each do |c|
            old_outputs = c.outputs.transform_values { |w| w.get }
            c.propagate
            new_outputs = c.outputs.transform_values { |w| w.get }
            changed ||= old_outputs != new_outputs
          end
          iterations += 1
        end while changed && iterations < max_iterations

        if iterations >= max_iterations
          warn "Simulation did not converge after #{max_iterations} iterations"
        end
      end

      def reset
        @time = 0
        @clocks.each { |c| c.set(0) }
      end
    end
  end
end
