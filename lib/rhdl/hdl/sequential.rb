# HDL Sequential Logic Components
# Flip-flops, registers, and other clock-triggered elements
#
# Note: Sequential components use manual propagate methods because the current
# behavior DSL only supports combinational logic (assign statements). Sequential
# synthesis requires always @(posedge clk) blocks which are not yet implemented.

module RHDL
  module HDL
    # Base class for sequential (clocked) components
    class SequentialComponent < SimComponent
      def initialize(name = nil)
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
    end

    # D Flip-Flop with synchronous reset and enable
    # Sequential - requires always @(posedge clk) for synthesis
    class DFlipFlop < SequentialComponent
      port_input :d
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            @state = in_val(:d) & 1
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # D Flip-Flop with asynchronous reset
    # Sequential - requires always @(posedge clk or posedge rst) for synthesis
    class DFlipFlopAsync < SequentialComponent
      port_input :d
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      def propagate
        if in_val(:rst) == 1
          @state = 0
        elsif rising_edge? && in_val(:en) == 1
          @state = in_val(:d) & 1
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # T Flip-Flop (Toggle)
    # Sequential - requires always @(posedge clk) for synthesis
    class TFlipFlop < SequentialComponent
      port_input :t
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1 && in_val(:t) == 1
            @state = @state == 0 ? 1 : 0
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # JK Flip-Flop
    # Sequential - requires always @(posedge clk) for synthesis
    class JKFlipFlop < SequentialComponent
      port_input :j
      port_input :k
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            j = in_val(:j) & 1
            k = in_val(:k) & 1
            case [j, k]
            when [0, 0] then # Hold
            when [0, 1] then @state = 0
            when [1, 0] then @state = 1
            when [1, 1] then @state = @state == 0 ? 1 : 0
            end
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # SR Flip-Flop (Set-Reset)
    # Sequential - requires always @(posedge clk) for synthesis
    class SRFlipFlop < SequentialComponent
      port_input :s
      port_input :r
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q
      port_output :qn

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            s = in_val(:s) & 1
            r = in_val(:r) & 1
            case [s, r]
            when [0, 0] then # Hold
            when [0, 1] then @state = 0
            when [1, 0] then @state = 1
            when [1, 1] then @state = 0  # Invalid, but we default to 0
            end
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # SR Latch (level-sensitive, not edge-triggered)
    # Combinational with feedback - requires special synthesis handling
    class SRLatch < SimComponent
      port_input :s
      port_input :r
      port_input :en
      port_output :q
      port_output :qn

      def initialize(name = nil)
        @state = 0
        super(name)
      end

      def propagate
        if in_val(:en) == 1
          s = in_val(:s) & 1
          r = in_val(:r) & 1
          case [s, r]
          when [0, 0] then # Hold
          when [0, 1] then @state = 0
          when [1, 0] then @state = 1
          when [1, 1] then @state = 0  # Invalid
          end
        end
        out_set(:q, @state)
        out_set(:qn, @state == 0 ? 1 : 0)
      end
    end

    # Multi-bit Register with synchronous reset and enable
    # Sequential - requires always @(posedge clk) for synthesis
    class Register < SequentialComponent
      port_input :d, width: 8
      port_input :clk
      port_input :rst
      port_input :en
      port_output :q, width: 8

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:en) == 1
            @state = in_val(:d)
          end
        end
        out_set(:q, @state)
      end
    end

    # Register with load capability
    # Sequential - requires always @(posedge clk) for synthesis
    class RegisterLoad < SequentialComponent
      port_input :d, width: 8
      port_input :clk
      port_input :rst
      port_input :load
      port_output :q, width: 8

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d)
          end
        end
        out_set(:q, @state)
      end
    end

    # Shift Register
    # Sequential - requires always @(posedge clk) for synthesis
    class ShiftRegister < SequentialComponent
      port_input :d_in       # Serial input
      port_input :clk
      port_input :rst
      port_input :en
      port_input :dir        # 0 = right, 1 = left
      port_input :load       # Parallel load enable
      port_input :d, width: 8  # Parallel load data
      port_output :q, width: 8
      port_output :d_out     # Serial output

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d)
          elsif in_val(:en) == 1
            if in_val(:dir) == 0  # Shift right
              @state = (@state >> 1) | ((in_val(:d_in) & 1) << (@width - 1))
            else  # Shift left
              @state = ((@state << 1) | (in_val(:d_in) & 1)) & ((1 << @width) - 1)
            end
          end
        end
        out_set(:q, @state)
        # Serial out is LSB when shifting right, MSB when shifting left
        serial_out = in_val(:dir) == 0 ? @state & 1 : (@state >> (@width - 1)) & 1
        out_set(:d_out, serial_out)
      end
    end

    # Binary Counter with up/down, load, and wrap
    # Sequential - requires always @(posedge clk) for synthesis
    class Counter < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :en
      port_input :up        # 1 = count up, 0 = count down
      port_input :load
      port_input :d, width: 8
      port_output :q, width: 8
      port_output :tc       # Terminal count (max when up, 0 when down)
      port_output :zero     # Zero flag

      def initialize(name = nil, width: 8)
        @width = width
        @state = 0
        @max = (1 << width) - 1
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d) & @max
          elsif in_val(:en) == 1
            if in_val(:up) == 1
              @state = (@state + 1) & @max
            else
              @state = (@state - 1) & @max
            end
          end
        end
        out_set(:q, @state)
        tc = in_val(:up) == 1 ? (@state == @max ? 1 : 0) : (@state == 0 ? 1 : 0)
        out_set(:tc, tc)
        out_set(:zero, @state == 0 ? 1 : 0)
      end
    end

    # Program Counter (16-bit, for CPU)
    # Sequential - requires always @(posedge clk) for synthesis
    class ProgramCounter < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :en          # Increment enable
      port_input :load        # Load new address
      port_input :d, width: 16
      port_input :inc, width: 16  # Increment amount (usually 1, 2, or 3)
      port_output :q, width: 16

      def initialize(name = nil, width: 16)
        @width = width
        @state = 0
        @max = (1 << width) - 1
        super(name)
      end

      def setup_ports
        return if @width == 16
        @inputs[:d] = Wire.new("#{@name}.d", width: @width)
        @inputs[:inc] = Wire.new("#{@name}.inc", width: @width)
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = 0
          elsif in_val(:load) == 1
            @state = in_val(:d) & @max
          elsif in_val(:en) == 1
            inc_val = in_val(:inc)
            inc_val = 1 if inc_val == 0  # Default increment
            @state = (@state + inc_val) & @max
          end
        end
        out_set(:q, @state)
      end
    end

    # Stack Pointer Register
    # Sequential - requires always @(posedge clk) for synthesis
    class StackPointer < SequentialComponent
      port_input :clk
      port_input :rst
      port_input :push     # Decrement SP
      port_input :pop      # Increment SP
      port_output :q, width: 8
      port_output :empty   # SP at max (empty stack)
      port_output :full    # SP at 0 (full stack)

      def initialize(name = nil, width: 8, initial: 0xFF)
        @width = width
        @initial = initial
        @state = initial
        @max = (1 << width) - 1
        super(name)
      end

      def setup_ports
        return if @width == 8
        @outputs[:q] = Wire.new("#{@name}.q", width: @width)
      end

      def propagate
        if rising_edge?
          if in_val(:rst) == 1
            @state = @initial
          elsif in_val(:push) == 1
            @state = (@state - 1) & @max
          elsif in_val(:pop) == 1
            @state = (@state + 1) & @max
          end
        end
        out_set(:q, @state)
        out_set(:empty, @state == @max ? 1 : 0)
        out_set(:full, @state == 0 ? 1 : 0)
      end
    end
  end
end
