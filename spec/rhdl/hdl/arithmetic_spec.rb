require 'spec_helper'

RSpec.describe 'HDL Arithmetic Components' do
  describe RHDL::HDL::HalfAdder do
    describe 'simulation' do
      it 'adds two bits' do
        adder = RHDL::HDL::HalfAdder.new

        # 0 + 0 = 0
        adder.set_input(:a, 0)
        adder.set_input(:b, 0)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(0)
        expect(adder.get_output(:cout)).to eq(0)

        # 1 + 0 = 1
        adder.set_input(:a, 1)
        adder.set_input(:b, 0)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(1)
        expect(adder.get_output(:cout)).to eq(0)

        # 1 + 1 = 10
        adder.set_input(:a, 1)
        adder.set_input(:b, 1)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(0)
        expect(adder.get_output(:cout)).to eq(1)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::HalfAdder.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::HalfAdder.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
        expect(ir.ports.length).to eq(4)  # a, b, sum, cout
        expect(ir.assigns.length).to be >= 2
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::HalfAdder.to_verilog
        expect(verilog).to include('module half_adder')
        expect(verilog).to include('input a')
        expect(verilog).to include('input b')
        expect(verilog).to include('output sum')
        expect(verilog).to include('output cout')
        expect(verilog).to include('assign sum')
        expect(verilog).to include('assign cout')
      end
    end
  end

  describe RHDL::HDL::FullAdder do
    describe 'simulation' do
      it 'adds two bits with carry in' do
        adder = RHDL::HDL::FullAdder.new

        # 1 + 1 + 1 = 11
        adder.set_input(:a, 1)
        adder.set_input(:b, 1)
        adder.set_input(:cin, 1)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(1)
        expect(adder.get_output(:cout)).to eq(1)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::FullAdder.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::FullAdder.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
        expect(ir.ports.length).to eq(5)  # a, b, cin, sum, cout
        expect(ir.assigns.length).to be >= 2
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::FullAdder.to_verilog
        expect(verilog).to include('module full_adder')
        expect(verilog).to include('input a')
        expect(verilog).to include('input b')
        expect(verilog).to include('input cin')
        expect(verilog).to include('output sum')
        expect(verilog).to include('output cout')
        expect(verilog).to include('assign sum')
        expect(verilog).to include('assign cout')
      end
    end
  end

  describe RHDL::HDL::RippleCarryAdder do
    describe 'simulation' do
      it 'adds 8-bit numbers' do
        adder = RHDL::HDL::RippleCarryAdder.new(nil, width: 8)

        # 100 + 50 = 150
        adder.set_input(:a, 100)
        adder.set_input(:b, 50)
        adder.set_input(:cin, 0)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(150)
        expect(adder.get_output(:cout)).to eq(0)

        # 200 + 100 = 300 (overflow)
        adder.set_input(:a, 200)
        adder.set_input(:b, 100)
        adder.propagate
        expect(adder.get_output(:sum)).to eq(44)  # 300 & 0xFF
        expect(adder.get_output(:cout)).to eq(1)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::RippleCarryAdder.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::RippleCarryAdder.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
        expect(ir.ports.length).to eq(6)  # a, b, cin, sum, cout, overflow
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::RippleCarryAdder.to_verilog
        expect(verilog).to include('module ripple_carry_adder')
        expect(verilog).to include('input [7:0] a')
        expect(verilog).to include('input [7:0] b')
        expect(verilog).to include('output [7:0] sum')
        expect(verilog).to include('assign sum')
      end
    end
  end

  describe RHDL::HDL::Multiplier do
    describe 'simulation' do
      it 'multiplies 8-bit numbers' do
        mult = RHDL::HDL::Multiplier.new(nil, width: 8)

        mult.set_input(:a, 10)
        mult.set_input(:b, 20)
        mult.propagate
        expect(mult.get_output(:product)).to eq(200)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::Multiplier.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::Multiplier.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
        expect(ir.ports.length).to eq(3)  # a, b, product
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::Multiplier.to_verilog
        expect(verilog).to include('module multiplier')
        expect(verilog).to include('input [7:0] a')
        expect(verilog).to include('input [7:0] b')
        expect(verilog).to include('output [15:0] product')
        expect(verilog).to include('assign product')
      end
    end
  end

  describe RHDL::HDL::ALU do
    let(:alu) { RHDL::HDL::ALU.new(nil, width: 8) }

    describe 'simulation' do
      it 'performs ADD' do
        alu.set_input(:a, 10)
        alu.set_input(:b, 5)
        alu.set_input(:op, RHDL::HDL::ALU::OP_ADD)
        alu.set_input(:cin, 0)
        alu.propagate

        expect(alu.get_output(:result)).to eq(15)
        expect(alu.get_output(:zero)).to eq(0)
      end

      it 'performs SUB' do
        alu.set_input(:a, 10)
        alu.set_input(:b, 5)
        alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
        alu.set_input(:cin, 0)
        alu.propagate

        expect(alu.get_output(:result)).to eq(5)
      end

      it 'performs AND' do
        alu.set_input(:a, 0b11110000)
        alu.set_input(:b, 0b10101010)
        alu.set_input(:op, RHDL::HDL::ALU::OP_AND)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0b10100000)
      end

      it 'performs OR' do
        alu.set_input(:a, 0b11110000)
        alu.set_input(:b, 0b00001111)
        alu.set_input(:op, RHDL::HDL::ALU::OP_OR)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0b11111111)
      end

      it 'performs XOR' do
        alu.set_input(:a, 0b11110000)
        alu.set_input(:b, 0b10101010)
        alu.set_input(:op, RHDL::HDL::ALU::OP_XOR)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0b01011010)
      end

      it 'performs NOT' do
        alu.set_input(:a, 0b11110000)
        alu.set_input(:op, RHDL::HDL::ALU::OP_NOT)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0b00001111)
      end

      it 'performs MUL' do
        alu.set_input(:a, 10)
        alu.set_input(:b, 5)
        alu.set_input(:op, RHDL::HDL::ALU::OP_MUL)
        alu.propagate

        expect(alu.get_output(:result)).to eq(50)
      end

      it 'performs DIV' do
        alu.set_input(:a, 20)
        alu.set_input(:b, 4)
        alu.set_input(:op, RHDL::HDL::ALU::OP_DIV)
        alu.propagate

        expect(alu.get_output(:result)).to eq(5)
      end

      it 'sets zero flag' do
        alu.set_input(:a, 5)
        alu.set_input(:b, 5)
        alu.set_input(:op, RHDL::HDL::ALU::OP_SUB)
        alu.set_input(:cin, 0)
        alu.propagate

        expect(alu.get_output(:result)).to eq(0)
        expect(alu.get_output(:zero)).to eq(1)
      end
    end

    # Note: ALU uses manual propagate for complex case logic
    # Synthesis tests are omitted since the behavior DSL doesn't support case statements yet
  end

  describe RHDL::HDL::Comparator do
    let(:cmp) { RHDL::HDL::Comparator.new(nil, width: 8) }

    describe 'simulation' do
      it 'compares equal values' do
        cmp.set_input(:a, 42)
        cmp.set_input(:b, 42)
        cmp.set_input(:signed, 0)
        cmp.propagate

        expect(cmp.get_output(:eq)).to eq(1)
        expect(cmp.get_output(:gt)).to eq(0)
        expect(cmp.get_output(:lt)).to eq(0)
      end

      it 'compares greater than' do
        cmp.set_input(:a, 50)
        cmp.set_input(:b, 30)
        cmp.set_input(:signed, 0)
        cmp.propagate

        expect(cmp.get_output(:eq)).to eq(0)
        expect(cmp.get_output(:gt)).to eq(1)
        expect(cmp.get_output(:lt)).to eq(0)
      end

      it 'compares less than' do
        cmp.set_input(:a, 20)
        cmp.set_input(:b, 40)
        cmp.set_input(:signed, 0)
        cmp.propagate

        expect(cmp.get_output(:eq)).to eq(0)
        expect(cmp.get_output(:gt)).to eq(0)
        expect(cmp.get_output(:lt)).to eq(1)
      end
    end

    # Note: Comparator uses complex signed/unsigned conditional logic
    # Synthesis tests are omitted since the behavior DSL doesn't support conditionals yet
  end
end
