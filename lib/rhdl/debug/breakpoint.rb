# HDL Signal Probing - Breakpoint
# Breakpoint for simulation debugging

module RHDL
  module HDL
    # Breakpoint for simulation debugging
    class Breakpoint
      attr_reader :id, :condition, :hit_count, :enabled

      @@next_id = 1

      def initialize(condition:, &block)
        @id = @@next_id
        @@next_id += 1
        @condition = condition
        @callback = block
        @hit_count = 0
        @enabled = true
      end

      def check(context)
        return false unless @enabled
        result = @condition.call(context)
        if result
          @hit_count += 1
          @callback&.call(context)
        end
        result
      end

      def enable!
        @enabled = true
      end

      def disable!
        @enabled = false
      end

      def reset!
        @hit_count = 0
      end
    end
  end
end
