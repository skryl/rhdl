# HDL Gate Primitives
# Basic logic gates with simulation behavior and synthesis support

module RHDL
  module HDL
    # NOT gate - single input inverter
    class NotGate < SimComponent
      port_input :a
      port_output :y

      behavior do
        y <= ~a
      end
    end

    # Buffer - non-inverting driver
    class Buffer < SimComponent
      port_input :a
      port_output :y

      behavior do
        y <= a
      end
    end

    # AND gate - 2 or more inputs
    # For 2-input case, uses behavior block for synthesis
    # For N-input case, uses dynamic port setup
    class AndGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= a0 & a1
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        # Add additional inputs beyond the default 2 if needed
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          # Fall back to manual computation for N-input case
          result = 1
          @input_count.times do |i|
            result &= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result)
        end
      end
    end

    # OR gate - 2 or more inputs
    class OrGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= a0 | a1
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 0
          @input_count.times do |i|
            result |= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result)
        end
      end
    end

    # NAND gate - 2 or more inputs
    class NandGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= ~(a0 & a1)
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 1
          @input_count.times do |i|
            result &= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result == 0 ? 1 : 0)
        end
      end
    end

    # NOR gate - 2 or more inputs
    class NorGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= ~(a0 | a1)
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 0
          @input_count.times do |i|
            result |= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result == 0 ? 1 : 0)
        end
      end
    end

    # XOR gate - 2 inputs (extendable)
    class XorGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= a0 ^ a1
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 0
          @input_count.times do |i|
            result ^= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result)
        end
      end
    end

    # XNOR gate - 2 inputs (extendable)
    class XnorGate < SimComponent
      port_input :a0
      port_input :a1
      port_output :y

      behavior do
        y <= ~(a0 ^ a1)
      end

      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        (@input_count - 2).times { |i| input :"a#{i + 2}" }
      end

      def propagate
        if @input_count == 2 && self.class.behavior_defined?
          execute_behavior
        else
          result = 0
          @input_count.times do |i|
            result ^= (in_val(:"a#{i}") & 1)
          end
          out_set(:y, result == 0 ? 1 : 0)
        end
      end
    end

    # Tristate buffer with enable
    # Note: High-Z state not yet supported in behavior DSL
    class TristateBuffer < SimComponent
      port_input :a
      port_input :en
      port_output :y

      behavior do
        # Simplified: always output a when enabled, 0 when disabled
        # Full tristate support would require Z state in synthesis
        y <= mux(en, a, 0)
      end

      def propagate
        if in_val(:en) == 1
          out_set(:y, in_val(:a))
        else
          @outputs[:y].set(SignalValue::Z)
        end
      end
    end

    # Multi-bit AND gate (bitwise AND)
    class BitwiseAnd < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a & b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        # Override default width if different
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        out_set(:y, in_val(:a) & in_val(:b))
      end
    end

    # Multi-bit OR gate (bitwise OR)
    class BitwiseOr < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a | b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        out_set(:y, in_val(:a) | in_val(:b))
      end
    end

    # Multi-bit XOR gate (bitwise XOR)
    class BitwiseXor < SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a ^ b
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @inputs[:b] = Wire.new("#{@name}.b", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
        @inputs[:b].on_change { |_| propagate }
      end

      def propagate
        out_set(:y, in_val(:a) ^ in_val(:b))
      end
    end

    # Multi-bit NOT gate (bitwise NOT)
    class BitwiseNot < SimComponent
      port_input :a, width: 8
      port_output :y, width: 8

      behavior do
        y <= ~a
      end

      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        return if @width == 8
        @inputs[:a] = Wire.new("#{@name}.a", width: @width)
        @outputs[:y] = Wire.new("#{@name}.y", width: @width)
        @inputs[:a].on_change { |_| propagate }
      end

      def propagate
        mask = (1 << @width) - 1
        out_set(:y, (~in_val(:a)) & mask)
      end
    end
  end
end
