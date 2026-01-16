require 'spec_helper'

RSpec.describe RHDL::HDL do
  describe 'Logic Gates' do
    describe RHDL::HDL::NotGate do
      it 'inverts the input' do
        gate = RHDL::HDL::NotGate.new
        gate.set_input(:a, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)

        gate.set_input(:a, 1)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)
      end
    end

    describe RHDL::HDL::AndGate do
      it 'performs AND operation' do
        gate = RHDL::HDL::AndGate.new

        gate.set_input(:a0, 0)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 1)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)
      end

      it 'supports multiple inputs' do
        gate = RHDL::HDL::AndGate.new(nil, inputs: 3)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 1)
        gate.set_input(:a2, 1)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)

        gate.set_input(:a2, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)
      end
    end

    describe RHDL::HDL::OrGate do
      it 'performs OR operation' do
        gate = RHDL::HDL::OrGate.new

        gate.set_input(:a0, 0)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)
      end
    end

    describe RHDL::HDL::XorGate do
      it 'performs XOR operation' do
        gate = RHDL::HDL::XorGate.new

        gate.set_input(:a0, 0)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 1)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)
      end
    end

    describe RHDL::HDL::NandGate do
      it 'performs NAND operation' do
        gate = RHDL::HDL::NandGate.new

        gate.set_input(:a0, 1)
        gate.set_input(:a1, 1)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0)

        gate.set_input(:a0, 0)
        gate.propagate
        expect(gate.get_output(:y)).to eq(1)
      end
    end
  end

  describe 'Bitwise Operations' do
    describe RHDL::HDL::BitwiseAnd do
      it 'performs 8-bit AND' do
        gate = RHDL::HDL::BitwiseAnd.new(nil, width: 8)
        gate.set_input(:a, 0b11110000)
        gate.set_input(:b, 0b10101010)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0b10100000)
      end
    end

    describe RHDL::HDL::BitwiseNot do
      it 'performs 8-bit NOT' do
        gate = RHDL::HDL::BitwiseNot.new(nil, width: 8)
        gate.set_input(:a, 0b11110000)
        gate.propagate
        expect(gate.get_output(:y)).to eq(0b00001111)
      end
    end
  end
end
