# Behavior DSL Specification
#
# Tests the unified behavior block that works for both simulation and synthesis

require 'rhdl'

RSpec.describe 'Behavior DSL' do
  describe 'Basic combinational logic' do
    # Simple AND gate using behavior block
    class BehaviorAndGate < RHDL::HDL::SimComponent
      port_input :a
      port_input :b
      port_output :y

      behavior do
        y <= a & b
      end
    end

    it 'simulates AND gate correctly' do
      gate = BehaviorAndGate.new('and')

      # Test all input combinations
      [[0, 0, 0], [0, 1, 0], [1, 0, 0], [1, 1, 1]].each do |a, b, expected|
        gate.set_input(:a, a)
        gate.set_input(:b, b)
        gate.propagate
        expect(gate.get_output(:y)).to eq(expected), "AND(#{a}, #{b}) should be #{expected}"
      end
    end

    it 'generates correct Verilog' do
      verilog = BehaviorAndGate.to_verilog
      expect(verilog).to include('assign y = (a & b)')
    end
  end

  describe 'OR gate' do
    class BehaviorOrGate < RHDL::HDL::SimComponent
      port_input :a
      port_input :b
      port_output :y

      behavior do
        y <= a | b
      end
    end

    it 'simulates OR gate correctly' do
      gate = BehaviorOrGate.new('or')

      [[0, 0, 0], [0, 1, 1], [1, 0, 1], [1, 1, 1]].each do |a, b, expected|
        gate.set_input(:a, a)
        gate.set_input(:b, b)
        gate.propagate
        expect(gate.get_output(:y)).to eq(expected)
      end
    end
  end

  describe 'XOR gate' do
    class BehaviorXorGate < RHDL::HDL::SimComponent
      port_input :a
      port_input :b
      port_output :y

      behavior do
        y <= a ^ b
      end
    end

    it 'simulates XOR gate correctly' do
      gate = BehaviorXorGate.new('xor')

      [[0, 0, 0], [0, 1, 1], [1, 0, 1], [1, 1, 0]].each do |a, b, expected|
        gate.set_input(:a, a)
        gate.set_input(:b, b)
        gate.propagate
        expect(gate.get_output(:y)).to eq(expected)
      end
    end
  end

  describe 'NOT gate' do
    class BehaviorNotGate < RHDL::HDL::SimComponent
      port_input :a
      port_output :y

      behavior do
        y <= ~a
      end
    end

    it 'simulates NOT gate correctly' do
      gate = BehaviorNotGate.new('not')

      gate.set_input(:a, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'Full adder' do
    class BehaviorFullAdder < RHDL::HDL::SimComponent
      port_input :a
      port_input :b
      port_input :cin
      port_output :sum
      port_output :cout

      behavior do
        sum <= a ^ b ^ cin
        cout <= (a & b) | (a & cin) | (b & cin)
      end
    end

    it 'simulates full adder correctly' do
      adder = BehaviorFullAdder.new('fa')

      # Test all 8 input combinations
      expected_results = [
        [0, 0, 0, 0, 0],  # 0+0+0 = 0
        [0, 0, 1, 1, 0],  # 0+0+1 = 1
        [0, 1, 0, 1, 0],  # 0+1+0 = 1
        [0, 1, 1, 0, 1],  # 0+1+1 = 2
        [1, 0, 0, 1, 0],  # 1+0+0 = 1
        [1, 0, 1, 0, 1],  # 1+0+1 = 2
        [1, 1, 0, 0, 1],  # 1+1+0 = 2
        [1, 1, 1, 1, 1],  # 1+1+1 = 3
      ]

      expected_results.each do |a, b, cin, exp_sum, exp_cout|
        adder.set_input(:a, a)
        adder.set_input(:b, b)
        adder.set_input(:cin, cin)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(exp_sum), "sum(#{a}+#{b}+#{cin}) should be #{exp_sum}"
        expect(adder.get_output(:cout)).to eq(exp_cout), "cout(#{a}+#{b}+#{cin}) should be #{exp_cout}"
      end
    end

    it 'generates correct Verilog' do
      verilog = BehaviorFullAdder.to_verilog
      expect(verilog).to include('assign sum = ((a ^ b) ^ cin)')
      expect(verilog).to include('assign cout = (((a & b) | (a & cin)) | (b & cin))')
    end
  end

  describe 'Multi-bit operations' do
    class Behavior8BitAdder < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :sum, width: 8

      behavior do
        sum <= a + b
      end
    end

    it 'simulates 8-bit addition correctly' do
      adder = Behavior8BitAdder.new('add8')

      test_cases = [
        [0x00, 0x00, 0x00],
        [0x01, 0x01, 0x02],
        [0x0F, 0x01, 0x10],
        [0x7F, 0x01, 0x80],
        [0xFF, 0x01, 0x00],  # Overflow wraps
        [0x55, 0xAA, 0xFF],
      ]

      test_cases.each do |a, b, expected|
        adder.set_input(:a, a)
        adder.set_input(:b, b)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(expected),
          "#{a.to_s(16)} + #{b.to_s(16)} should be #{expected.to_s(16)}"
      end
    end

    it 'generates correct Verilog for multi-bit signals' do
      verilog = Behavior8BitAdder.to_verilog
      expect(verilog).to include('input [7:0] a')
      expect(verilog).to include('input [7:0] b')
      expect(verilog).to include('output [7:0] sum')
    end
  end

  describe 'Bitwise operations on multi-bit values' do
    class Behavior8BitAnd < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a & b
      end
    end

    it 'simulates 8-bit AND correctly' do
      gate = Behavior8BitAnd.new('and8')

      gate.set_input(:a, 0x0F)
      gate.set_input(:b, 0xF0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0x00)

      gate.set_input(:a, 0xFF)
      gate.set_input(:b, 0xF0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0xF0)
    end
  end

  describe 'Comparison operations' do
    class BehaviorZeroDetect < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_output :is_zero

      behavior do
        is_zero <= (a == 0)
      end
    end

    it 'detects zero correctly' do
      detect = BehaviorZeroDetect.new('zero')

      detect.set_input(:a, 0)
      detect.propagate
      expect(detect.get_output(:is_zero)).to eq(1)

      detect.set_input(:a, 1)
      detect.propagate
      expect(detect.get_output(:is_zero)).to eq(0)

      detect.set_input(:a, 0xFF)
      detect.propagate
      expect(detect.get_output(:is_zero)).to eq(0)
    end
  end

  describe 'Shift operations' do
    class BehaviorShifter < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_input :amount, width: 3
      port_output :left, width: 8
      port_output :right, width: 8

      behavior do
        left <= a << amount
        right <= a >> amount
      end
    end

    it 'shifts correctly' do
      shifter = BehaviorShifter.new('shift')

      shifter.set_input(:a, 0x01)
      shifter.set_input(:amount, 4)
      shifter.propagate
      expect(shifter.get_output(:left)).to eq(0x10)
      expect(shifter.get_output(:right)).to eq(0x00)

      shifter.set_input(:a, 0x80)
      shifter.set_input(:amount, 4)
      shifter.propagate
      expect(shifter.get_output(:left)).to eq(0x00)  # Shifted out
      expect(shifter.get_output(:right)).to eq(0x08)
    end
  end

  describe 'Mux helper' do
    class BehaviorMux < RHDL::HDL::SimComponent
      port_input :sel
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= mux(sel, a, b)  # sel ? a : b
      end
    end

    it 'selects correct input' do
      mux_comp = BehaviorMux.new('mux')

      mux_comp.set_input(:a, 0xAA)
      mux_comp.set_input(:b, 0x55)

      mux_comp.set_input(:sel, 1)
      mux_comp.propagate
      expect(mux_comp.get_output(:y)).to eq(0xAA)

      mux_comp.set_input(:sel, 0)
      mux_comp.propagate
      expect(mux_comp.get_output(:y)).to eq(0x55)
    end

    it 'generates mux in Verilog' do
      verilog = BehaviorMux.to_verilog
      expect(verilog).to include('?')  # Ternary operator in mux
    end
  end

  describe 'Bit selection' do
    class BehaviorBitSelect < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_output :bit0
      port_output :bit7

      behavior do
        bit0 <= a[0]
        bit7 <= a[7]
      end
    end

    it 'selects individual bits' do
      sel = BehaviorBitSelect.new('bitsel')

      sel.set_input(:a, 0b10000001)
      sel.propagate
      expect(sel.get_output(:bit0)).to eq(1)
      expect(sel.get_output(:bit7)).to eq(1)

      sel.set_input(:a, 0b01111110)
      sel.propagate
      expect(sel.get_output(:bit0)).to eq(0)
      expect(sel.get_output(:bit7)).to eq(0)
    end
  end

  describe 'Bit slice' do
    class BehaviorBitSlice < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_output :low, width: 4
      port_output :high, width: 4

      behavior do
        low <= a[3..0]
        high <= a[7..4]
      end
    end

    it 'extracts bit slices' do
      slice = BehaviorBitSlice.new('slice')

      slice.set_input(:a, 0xAB)
      slice.propagate
      expect(slice.get_output(:low)).to eq(0x0B)
      expect(slice.get_output(:high)).to eq(0x0A)
    end
  end

  describe 'Backwards compatibility' do
    # Test that existing components with propagate() still work
    class TraditionalGate < RHDL::HDL::SimComponent
      def setup_ports
        input :a
        input :b
        output :y
      end

      def propagate
        out_set(:y, in_val(:a) & in_val(:b))
      end
    end

    it 'traditional propagate still works' do
      gate = TraditionalGate.new('trad')

      gate.set_input(:a, 1)
      gate.set_input(:b, 1)
      gate.propagate
      expect(gate.get_output(:y)).to eq(1)

      gate.set_input(:a, 1)
      gate.set_input(:b, 0)
      gate.propagate
      expect(gate.get_output(:y)).to eq(0)
    end
  end

  describe 'Mixed port definitions' do
    # Test that class-level port_* and instance-level input/output work together
    class MixedPortComponent < RHDL::HDL::SimComponent
      port_input :a, width: 8
      port_input :b, width: 8
      port_output :y, width: 8

      behavior do
        y <= a + b
      end
    end

    it 'supports both port definition styles' do
      comp = MixedPortComponent.new('mixed')
      expect(comp.inputs.keys).to include(:a, :b)
      expect(comp.outputs.keys).to include(:y)

      comp.set_input(:a, 10)
      comp.set_input(:b, 20)
      comp.propagate
      expect(comp.get_output(:y)).to eq(30)
    end
  end

  describe 'IR generation' do
    it 'generates IR assigns from behavior block' do
      result = BehaviorAndGate.send(:behavior_to_ir_assigns)
      ir_assigns = result[:assigns]
      expect(ir_assigns.length).to eq(1)
      expect(ir_assigns[0].target).to eq(:y)
      expect(ir_assigns[0].expr).to be_a(RHDL::Export::IR::BinaryOp)
      expect(ir_assigns[0].expr.op).to eq(:&)
    end

    it 'generates complete IR module definition' do
      ir = BehaviorFullAdder.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)
      expect(ir.assigns.length).to eq(2)
    end
  end
end
