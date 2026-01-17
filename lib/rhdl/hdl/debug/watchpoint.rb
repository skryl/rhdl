# HDL Signal Probing - Watchpoint
# Watchpoint - break when a signal changes or matches a value

module RHDL
  module HDL
    # Watchpoint - break when a signal changes or matches a value
    class Watchpoint < Breakpoint
      attr_reader :wire, :watch_type, :watch_value

      def initialize(wire, type: :change, value: nil, &block)
        @wire = wire
        @watch_type = type
        @watch_value = value
        @last_value = wire.get

        condition = case type
        when :change
          -> (_) { check_change }
        when :equals
          -> (_) { wire.get == value }
        when :not_equals
          -> (_) { wire.get != value }
        when :greater
          -> (_) { wire.get > value }
        when :less
          -> (_) { wire.get < value }
        when :rising_edge
          -> (_) { check_rising_edge }
        when :falling_edge
          -> (_) { check_falling_edge }
        else
          -> (_) { false }
        end

        super(condition: condition, &block)
      end

      def check_change
        current = @wire.get
        changed = current != @last_value
        @last_value = current
        changed
      end

      def check_rising_edge
        current = @wire.get
        rising = @last_value == 0 && current == 1
        @last_value = current
        rising
      end

      def check_falling_edge
        current = @wire.get
        falling = @last_value == 1 && current == 0
        @last_value = current
        falling
      end

      def description
        case @watch_type
        when :change then "#{@wire.name} changes"
        when :equals then "#{@wire.name} == #{@watch_value}"
        when :not_equals then "#{@wire.name} != #{@watch_value}"
        when :greater then "#{@wire.name} > #{@watch_value}"
        when :less then "#{@wire.name} < #{@watch_value}"
        when :rising_edge then "#{@wire.name} ↑"
        when :falling_edge then "#{@wire.name} ↓"
        else "unknown"
        end
      end
    end
  end
end
