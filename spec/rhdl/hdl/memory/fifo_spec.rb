require 'spec_helper'

RSpec.describe RHDL::HDL::FIFO do
  def clock_cycle(component)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  let(:fifo) { RHDL::HDL::FIFO.new }

  before do
    fifo.set_input(:rst, 0)
    fifo.set_input(:wr_en, 0)
    fifo.set_input(:rd_en, 0)
    fifo.propagate  # Initialize outputs
  end

  describe 'simulation' do
    it 'maintains FIFO order' do
      # Write 1, 2, 3
      [1, 2, 3].each do |val|
        fifo.set_input(:din, val)
        fifo.set_input(:wr_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:wr_en, 0)
      end

      # Read should get 1, 2, 3 in order
      [1, 2, 3].each do |expected|
        expect(fifo.get_output(:dout)).to eq(expected)
        fifo.set_input(:rd_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:rd_en, 0)
      end
    end

    it 'indicates empty and full states' do
      expect(fifo.get_output(:empty)).to eq(1)
      expect(fifo.get_output(:full)).to eq(0)
      expect(fifo.get_output(:count)).to eq(0)

      # Fill FIFO (16 entries)
      16.times do |i|
        fifo.set_input(:din, i)
        fifo.set_input(:wr_en, 1)
        clock_cycle(fifo)
        fifo.set_input(:wr_en, 0)
      end

      expect(fifo.get_output(:empty)).to eq(0)
      expect(fifo.get_output(:full)).to eq(1)
      expect(fifo.get_output(:count)).to eq(16)
    end

    it 'resets to empty state' do
      # Write something
      fifo.set_input(:din, 0xFF)
      fifo.set_input(:wr_en, 1)
      clock_cycle(fifo)
      fifo.set_input(:wr_en, 0)

      expect(fifo.get_output(:empty)).to eq(0)

      # Reset
      fifo.set_input(:rst, 1)
      clock_cycle(fifo)

      expect(fifo.get_output(:empty)).to eq(1)
      expect(fifo.get_output(:count)).to eq(0)
    end
  end

  describe 'synthesis' do
    it 'has memory DSL defined' do
      expect(RHDL::HDL::FIFO.memory_dsl_defined?).to be_truthy
    end

    it 'generates valid IR' do
      ir = RHDL::HDL::FIFO.to_ir
      expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      expect(ir.ports.length).to eq(11)  # clk, rst, wr_en, rd_en, din, dout, empty, full, count, wr_ptr, rd_ptr
      expect(ir.memories.length).to eq(1)
    end

    it 'generates valid Verilog' do
      verilog = RHDL::HDL::FIFO.to_verilog
      expect(verilog).to include('module fifo')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to match(/output.*\[7:0\].*dout/)
    end

    it 'generates valid FIRRTL' do
      firrtl = RHDL::HDL::FIFO.to_circt
      expect(firrtl).to include('FIRRTL version')
      expect(firrtl).to include('circuit fifo')
      expect(firrtl).to include('input clk')
      expect(firrtl).to include('input din')
      expect(firrtl).to include('output dout')
    end

    context 'CIRCT firtool validation', if: HdlToolchain.firtool_available? do
      it 'firtool can compile FIRRTL to Verilog' do
        result = CirctHelper.validate_firrtl_syntax(
          RHDL::HDL::FIFO,
          base_dir: 'tmp/circt_test/fifo'
        )

        expect(result[:success]).to be(true), result[:error]
      end
    end
  end

  describe 'gate-level netlist' do
    let(:component) { RHDL::HDL::FIFO.new('fifo') }
    let(:ir) { RHDL::Export::Structure::Lower.from_components([component], name: 'fifo') }

    it 'generates correct IR structure' do
      expect(ir.inputs.keys).to include('fifo.clk', 'fifo.rst', 'fifo.wr_en', 'fifo.rd_en', 'fifo.din')
      expect(ir.outputs.keys).to include('fifo.dout', 'fifo.empty', 'fifo.full', 'fifo.count')
      # FIFO has DFFs for pointers and count
      expect(ir.dffs.length).to be >= 1
    end

    it 'generates valid structure Verilog' do
      verilog = NetlistHelper.ir_to_structure_verilog(ir)
      expect(verilog).to include('module fifo')
      expect(verilog).to include('input clk')
      expect(verilog).to include('input rst')
      expect(verilog).to include('input wr_en')
      expect(verilog).to include('input rd_en')
      expect(verilog).to include('input [7:0] din')
      expect(verilog).to include('output [7:0] dout')
      expect(verilog).to include('output empty')
      expect(verilog).to include('output full')
    end

    context 'iverilog simulation', if: HdlToolchain.iverilog_available? do
      it 'matches behavior simulation' do
        test_vectors = []
        behavior = RHDL::HDL::FIFO.new
        behavior.set_input(:rst, 0)
        behavior.set_input(:wr_en, 0)
        behavior.set_input(:rd_en, 0)
        behavior.propagate

        test_cases = [
          { din: 0x11, rst: 0, wr_en: 1, rd_en: 0 },  # write
          { din: 0x22, rst: 0, wr_en: 1, rd_en: 0 },  # write
          { din: 0, rst: 0, wr_en: 0, rd_en: 1 },     # read
          { din: 0, rst: 0, wr_en: 0, rd_en: 1 },     # read
        ]

        expected_outputs = []
        test_cases.each do |tc|
          behavior.set_input(:din, tc[:din])
          behavior.set_input(:rst, tc[:rst])
          behavior.set_input(:wr_en, tc[:wr_en])
          behavior.set_input(:rd_en, tc[:rd_en])
          behavior.set_input(:clk, 0)
          behavior.propagate
          behavior.set_input(:clk, 1)
          behavior.propagate

          test_vectors << { inputs: tc }
          expected_outputs << {
            dout: behavior.get_output(:dout),
            empty: behavior.get_output(:empty)
          }
        end

        base_dir = File.join('tmp', 'iverilog', 'fifo')
        result = NetlistHelper.run_structure_simulation(ir, test_vectors, base_dir: base_dir)

        expect(result[:success]).to be(true), result[:error]

        expected_outputs.each_with_index do |expected, idx|
          expect(result[:results][idx][:empty]).to eq(expected[:empty]),
            "Cycle #{idx}: expected empty=#{expected[:empty]}, got #{result[:results][idx][:empty]}"
        end
      end
    end

    describe 'simulator comparison' do
      it 'all simulators produce matching results', pending: 'FIFO has complex memory synthesis requirements' do
        test_cases = [
          { din: 0x11, rst: 0, wr_en: 1, rd_en: 0 },
          { din: 0x22, rst: 0, wr_en: 1, rd_en: 0 },
          { din: 0, rst: 0, wr_en: 0, rd_en: 1 },
          { din: 0, rst: 1, wr_en: 0, rd_en: 0 }
        ]

        NetlistHelper.compare_and_validate!(
          RHDL::HDL::FIFO,
          'fifo',
          test_cases,
          base_dir: 'tmp/netlist_comparison/fifo',
          has_clock: true
        )
      end
    end
  end
end
