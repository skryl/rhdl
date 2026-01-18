require 'spec_helper'

RSpec.describe RHDL::HDL::Divider do
  describe 'simulation' do
    it 'divides 8-bit numbers' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 10)
      div.propagate
      expect(div.get_output(:quotient)).to eq(10)
      expect(div.get_output(:remainder)).to eq(0)
      expect(div.get_output(:div_by_zero)).to eq(0)
    end

    it 'computes remainder' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 30)
      div.propagate
      expect(div.get_output(:quotient)).to eq(3)
      expect(div.get_output(:remainder)).to eq(10)
    end

    it 'handles division by zero' do
      div = RHDL::HDL::Divider.new(nil, width: 8)

      div.set_input(:dividend, 100)
      div.set_input(:divisor, 0)
      div.propagate
      expect(div.get_output(:div_by_zero)).to eq(1)
    end
  end

  describe 'synthesis' do
    it 'has a behavior block defined' do
      expect(RHDL::HDL::Divider.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::Divider.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # dividend, divisor, quotient, remainder, div_by_zero
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::Divider.to_verilog
      expect(verilog).to include('module divider')
      expect(verilog).to include('input [7:0] dividend')
      expect(verilog).to include('output [7:0] quotient')
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::Divider.new('div', width: 8) }
    let(:ir) { RHDL::Gates::Lower.from_components([component], name: 'div') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('div.dividend', 'div.divisor')
      expect(ir.outputs.keys).to include('div.quotient', 'div.remainder', 'div.div_by_zero')
      # Divider has many gates for restoring division
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structural Verilog' do
      verilog = NetlistHelper.ir_to_structural_verilog(ir)
      expect(verilog).to include('module div')
      expect(verilog).to include('input [7:0] dividend')
      expect(verilog).to include('input [7:0] divisor')
      expect(verilog).to include('output [7:0] quotient')
      expect(verilog).to include('output [7:0] remainder')
      expect(verilog).to include('output div_by_zero')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavioral simulation' do
        test_vectors = []
        behavioral = RHDL::HDL::Divider.new(nil, width: 8)

        test_cases = [
          { dividend: 100, divisor: 10 },  # 10 r 0
          { dividend: 100, divisor: 30 },  # 3 r 10
          { dividend: 255, divisor: 16 },  # 15 r 15
          { dividend: 50, divisor: 7 },    # 7 r 1
          { dividend: 1, divisor: 1 },     # 1 r 0
          { dividend: 0, divisor: 5 },     # 0 r 0
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavioral.set_input(:dividend, tc[:dividend])
          behavioral.set_input(:divisor, tc[:divisor])
          behavioral.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            quotient: behavioral.get_output(:quotient),
            remainder: behavioral.get_output(:remainder),
            div_by_zero: behavioral.get_output(:div_by_zero)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'div')
        result = NetlistHelper.run_structural_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:quotient]).to eq(expected[:quotient]),
            "Cycle #{idx}: expected quotient=#{expected[:quotient]}, got #{result[:results][idx][:quotient]}"
          expect(result[:results][idx][:remainder]).to eq(expected[:remainder]),
            "Cycle #{idx}: expected remainder=#{expected[:remainder]}, got #{result[:results][idx][:remainder]}"
        end
      end
    end
  end
end
