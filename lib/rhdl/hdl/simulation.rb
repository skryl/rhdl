# HDL Simulation Engine
# Provides the core simulation infrastructure for gate-level and behavioral simulation

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
      attr_reader :name, :width
      attr_accessor :value, :driver

      def initialize(name, width: 1)
        @name = name
        @width = width
        @value = SignalValue.new(0, width: width)
        @driver = nil
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
    class SimComponent
      attr_reader :name, :inputs, :outputs, :internal_signals

      def initialize(name = nil)
        @name = name || self.class.name.split('::').last.downcase
        @inputs = {}
        @outputs = {}
        @internal_signals = {}
        @subcomponents = {}
        @propagation_delay = 0
        setup_ports
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
      end

      # Main simulation method - compute outputs from inputs
      # Override in subclasses
      def propagate
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
