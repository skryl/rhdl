# frozen_string_literal: true

module RHDL
  module HDL
    # A wire/signal in the circuit that can be connected and propagated
    class Wire
      attr_reader :name, :width, :sinks
      attr_accessor :value, :driver, :dependency_graph

      def initialize(name, width: 1)
        @name = name
        @width = width
        @value = SignalValue.new(0, width: width)
        @driver = nil
        @sinks = []
        @listeners = []
        @dependency_graph = nil
      end

      def set(val)
        new_val = val.is_a?(SignalValue) ? val : SignalValue.new(val, width: @width)
        if new_val.value != @value.value
          @value = new_val
          notify_listeners
          # Notify dependency graph if attached
          @dependency_graph&.mark_wire_dirty(self)
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
  end
end
