require 'spec_helper'

RSpec.describe RHDL::HDL::SRLatch do
  let(:latch) { RHDL::HDL::SRLatch.new }

  before do
    latch.set_input(:en, 1)
  end

  describe 'simulation' do
    it 'holds state when S=0 and R=0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 0)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)  # Hold
    end

    it 'resets when S=0 and R=1' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)
      expect(latch.get_output(:qn)).to eq(1)
    end

    it 'sets when S=1 and R=0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)
      expect(latch.get_output(:qn)).to eq(0)
    end

    it 'handles invalid state S=1 R=1 by defaulting to 0' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:s, 1)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)  # Invalid defaults to 0
    end

    it 'is level-sensitive (no clock needed)' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      # Change S immediately and propagate
      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(0)
    end

    it 'does not change when enable is low' do
      latch.set_input(:s, 1)
      latch.set_input(:r, 0)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)

      latch.set_input(:en, 0)
      latch.set_input(:s, 0)
      latch.set_input(:r, 1)
      latch.propagate
      expect(latch.get_output(:q)).to eq(1)  # Still 1 because enable is low
    end
  end

  describe 'synthesis' do
    it 'has synthesis support defined' do
      expect(RHDL::HDL::SRLatch.behavior_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::SRLatch.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(5)  # s, r, en, q, qn
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::SRLatch.to_verilog
      expect(verilog).to include('module sr_latch')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to match(/output.*q/)
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::SRLatch.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit sr_latch')
      expect(firrtl).to include('input s')
      expect(firrtl).to include('input r')
      expect(firrtl).to include('output q')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        pending 'FIRRTL memory port syntax not yet implemented'
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::SRLatch,
          base_dir: 'tmp/circt_test/sr_latch'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::SRLatch.new('sr_latch') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'sr_latch') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('sr_latch.s', 'sr_latch.r', 'sr_latch.en')
      expect(ir.outputs.keys).to include('sr_latch.q', 'sr_latch.qn')
      expect(ir.gates.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module sr_latch')
      expect(verilog).to include('input s')
      expect(verilog).to include('input r')
      expect(verilog).to include('input en')
      expect(verilog).to include('output q')
      expect(verilog).to include('output qn')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::SRLatch.new
        behavior.set_input(:en, 1)

        test_cases = [
          { s: 1, r: 0, en: 1 },  # set
          { s: 0, r: 0, en: 1 },  # hold
          { s: 0, r: 1, en: 1 },  # reset
          { s: 1, r: 0, en: 1 },  # set again
          { s: 0, r: 1, en: 0 },  # hold (en=0)
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:s, tc[:s])
          behavior.set_input(:r, tc[:r])
          behavior.set_input(:en, tc[:en])
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << { q: behavior.get_output(:q) }
        end

        base_dir = File.join('tmp', 'iverilog', 'sr_latch')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:q]).to eq(expected[:q]),
            "Cycle #{idx}: expected q=#{expected[:q]}, got #{result[:results][idx][:q]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results', pending: 'SR Latch synthesized as combinational logic without memory hold state' do
        test_cases = [
          { s: 1, r: 0, en: 1 },
          { s: 0, r: 0, en: 1 },
          { s: 0, r: 1, en: 1 },
          { s: 1, r: 0, en: 0 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::SRLatch,
          'sr_latch',
          test_cases,
          base_dir: 'tmp/netlist_comparison/sr_latch',
          has_clock: false
        )
      end
    end
  end
end
