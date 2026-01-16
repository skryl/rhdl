require 'spec_helper'

RSpec.describe RHDL::HDL do
  describe 'Logic Gates' do
    describe RHDL::HDL::NotGate do
      let(:gate) { RHDL::HDL::NotGate.new }

      describe 'simulation' do
        it 'inverts the input' do
          gate.set_input(:a, 0)
          gate.propagate
          expect(gate.get_output(:y)).to eq(1)

          gate.set_input(:a, 1)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::NotGate.behavior_defined?).to be_truthy
        end

        it 'generates valid IR' do
          ir = RHDL::HDL::NotGate.to_ir
          expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
          expect(ir.ports.length).to eq(2)
          expect(ir.assigns.length).to be >= 1
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::NotGate.to_verilog
          expect(verilog).to include('module not_gate')
          expect(verilog).to include('input a')
          expect(verilog).to include('output y')
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::Buffer do
      let(:gate) { RHDL::HDL::Buffer.new }

      describe 'simulation' do
        it 'passes input to output' do
          gate.set_input(:a, 0)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0)

          gate.set_input(:a, 1)
          gate.propagate
          expect(gate.get_output(:y)).to eq(1)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::Buffer.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::Buffer.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::AndGate do
      describe 'simulation' do
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

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::AndGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::AndGate.to_verilog
          expect(verilog).to include('module and_gate')
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::OrGate do
      describe 'simulation' do
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

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::OrGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::OrGate.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::XorGate do
      describe 'simulation' do
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

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::XorGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::XorGate.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::NandGate do
      describe 'simulation' do
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

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::NandGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::NandGate.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::NorGate do
      describe 'simulation' do
        it 'performs NOR operation' do
          gate = RHDL::HDL::NorGate.new

          gate.set_input(:a0, 0)
          gate.set_input(:a1, 0)
          gate.propagate
          expect(gate.get_output(:y)).to eq(1)

          gate.set_input(:a0, 1)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::NorGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::NorGate.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::XnorGate do
      describe 'simulation' do
        it 'performs XNOR operation' do
          gate = RHDL::HDL::XnorGate.new

          gate.set_input(:a0, 0)
          gate.set_input(:a1, 0)
          gate.propagate
          expect(gate.get_output(:y)).to eq(1)

          gate.set_input(:a0, 1)
          gate.set_input(:a1, 0)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0)

          gate.set_input(:a0, 1)
          gate.set_input(:a1, 1)
          gate.propagate
          expect(gate.get_output(:y)).to eq(1)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::XnorGate.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::XnorGate.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end
  end

  describe 'Bitwise Operations' do
    describe RHDL::HDL::BitwiseAnd do
      describe 'simulation' do
        it 'performs 8-bit AND' do
          gate = RHDL::HDL::BitwiseAnd.new(nil, width: 8)
          gate.set_input(:a, 0b11110000)
          gate.set_input(:b, 0b10101010)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0b10100000)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::BitwiseAnd.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog with correct width' do
          verilog = RHDL::HDL::BitwiseAnd.to_verilog
          expect(verilog).to include('[7:0]')  # 8-bit signals
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::BitwiseOr do
      describe 'simulation' do
        it 'performs 8-bit OR' do
          gate = RHDL::HDL::BitwiseOr.new(nil, width: 8)
          gate.set_input(:a, 0b11110000)
          gate.set_input(:b, 0b00001111)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0b11111111)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::BitwiseOr.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::BitwiseOr.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::BitwiseXor do
      describe 'simulation' do
        it 'performs 8-bit XOR' do
          gate = RHDL::HDL::BitwiseXor.new(nil, width: 8)
          gate.set_input(:a, 0b11110000)
          gate.set_input(:b, 0b10101010)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0b01011010)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::BitwiseXor.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::BitwiseXor.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end

    describe RHDL::HDL::BitwiseNot do
      describe 'simulation' do
        it 'performs 8-bit NOT' do
          gate = RHDL::HDL::BitwiseNot.new(nil, width: 8)
          gate.set_input(:a, 0b11110000)
          gate.propagate
          expect(gate.get_output(:y)).to eq(0b00001111)
        end
      end

      describe 'synthesis' do
        it 'has a behavior block defined' do
          expect(RHDL::HDL::BitwiseNot.behavior_defined?).to be_truthy
        end

        it 'generates valid Verilog' do
          verilog = RHDL::HDL::BitwiseNot.to_verilog
          expect(verilog).to include('assign y')
        end
      end
    end
  end
end
