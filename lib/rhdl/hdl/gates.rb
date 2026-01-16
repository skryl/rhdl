# HDL Gate Primitives
# Basic logic gates with simulation behavior

module RHDL
  module HDL
    # NOT gate - single input inverter
    class NotGate < SimComponent
      def setup_ports
        input :a
        output :y
      end

      def propagate
        out_set(:y, in_val(:a) == 0 ? 1 : 0)
      end
    end

    # Buffer - non-inverting driver
    class Buffer < SimComponent
      def setup_ports
        input :a
        output :y
      end

      def propagate
        out_set(:y, in_val(:a))
      end
    end

    # AND gate - 2 or more inputs
    class AndGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 1
        @input_count.times do |i|
          result &= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result)
      end
    end

    # OR gate - 2 or more inputs
    class OrGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 0
        @input_count.times do |i|
          result |= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result)
      end
    end

    # NAND gate - 2 or more inputs
    class NandGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 1
        @input_count.times do |i|
          result &= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result == 0 ? 1 : 0)
      end
    end

    # NOR gate - 2 or more inputs
    class NorGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 0
        @input_count.times do |i|
          result |= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result == 0 ? 1 : 0)
      end
    end

    # XOR gate - 2 inputs (extendable)
    class XorGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 0
        @input_count.times do |i|
          result ^= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result)
      end
    end

    # XNOR gate - 2 inputs (extendable)
    class XnorGate < SimComponent
      def initialize(name = nil, inputs: 2)
        @input_count = inputs
        super(name)
      end

      def setup_ports
        @input_count.times { |i| input :"a#{i}" }
        output :y
      end

      def propagate
        result = 0
        @input_count.times do |i|
          result ^= (in_val(:"a#{i}") & 1)
        end
        out_set(:y, result == 0 ? 1 : 0)
      end
    end

    # Tristate buffer with enable
    class TristateBuffer < SimComponent
      def setup_ports
        input :a
        input :en
        output :y
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
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        output :y, width: @width
      end

      def propagate
        out_set(:y, in_val(:a) & in_val(:b))
      end
    end

    # Multi-bit OR gate (bitwise OR)
    class BitwiseOr < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        output :y, width: @width
      end

      def propagate
        out_set(:y, in_val(:a) | in_val(:b))
      end
    end

    # Multi-bit XOR gate (bitwise XOR)
    class BitwiseXor < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        input :b, width: @width
        output :y, width: @width
      end

      def propagate
        out_set(:y, in_val(:a) ^ in_val(:b))
      end
    end

    # Multi-bit NOT gate (bitwise NOT)
    class BitwiseNot < SimComponent
      def initialize(name = nil, width: 8)
        @width = width
        super(name)
      end

      def setup_ports
        input :a, width: @width
        output :y, width: @width
      end

      def propagate
        mask = (1 << @width) - 1
        out_set(:y, (~in_val(:a)) & mask)
      end
    end
  end
end
