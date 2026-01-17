# frozen_string_literal: true

module RHDL
  module HDL
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
  end
end
