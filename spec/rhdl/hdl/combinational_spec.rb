require 'spec_helper'

RSpec.describe 'HDL Combinational Components' do
  describe RHDL::HDL::Mux2 do
    let(:mux) { RHDL::HDL::Mux2.new(nil, width: 8) }

    describe 'simulation' do
      it 'selects input a when sel=0' do
        mux.set_input(:a, 0x11)
        mux.set_input(:b, 0x22)
        mux.set_input(:sel, 0)
        mux.propagate

        expect(mux.get_output(:y)).to eq(0x11)
      end

      it 'selects input b when sel=1' do
        mux.set_input(:a, 0x11)
        mux.set_input(:b, 0x22)
        mux.set_input(:sel, 1)
        mux.propagate

        expect(mux.get_output(:y)).to eq(0x22)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::Mux2.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::Mux2.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
        expect(ir.ports.length).to eq(4)  # a, b, sel, y
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::Mux2.to_verilog
        expect(verilog).to include('module mux2')
        expect(verilog).to include('assign y')
      end
    end
  end

  describe RHDL::HDL::Mux4 do
    let(:mux) { RHDL::HDL::Mux4.new(nil, width: 8) }

    before do
      mux.set_input(:a, 0x10)
      mux.set_input(:b, 0x20)
      mux.set_input(:c, 0x30)
      mux.set_input(:d, 0x40)
    end

    it 'selects correct input based on sel' do
      mux.set_input(:sel, 0)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x10)

      mux.set_input(:sel, 1)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x20)

      mux.set_input(:sel, 2)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x30)

      mux.set_input(:sel, 3)
      mux.propagate
      expect(mux.get_output(:y)).to eq(0x40)
    end
  end

  describe RHDL::HDL::Mux8 do
    let(:mux) { RHDL::HDL::Mux8.new(nil, width: 8) }

    it 'selects from 8 inputs' do
      8.times { |i| mux.set_input("in#{i}".to_sym, (i + 1) * 10) }

      mux.set_input(:sel, 5)
      mux.propagate
      expect(mux.get_output(:y)).to eq(60)

      mux.set_input(:sel, 7)
      mux.propagate
      expect(mux.get_output(:y)).to eq(80)
    end
  end

  describe RHDL::HDL::MuxN do
    let(:mux) { RHDL::HDL::MuxN.new(nil, width: 8, inputs: 6) }

    it 'handles arbitrary number of inputs' do
      6.times { |i| mux.set_input("in#{i}".to_sym, 100 + i) }

      mux.set_input(:sel, 3)
      mux.propagate
      expect(mux.get_output(:y)).to eq(103)
    end
  end

  describe RHDL::HDL::Demux2 do
    let(:demux) { RHDL::HDL::Demux2.new(nil, width: 8) }

    it 'routes to output a when sel=0' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 0)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0x42)
      expect(demux.get_output(:y1)).to eq(0)
    end

    it 'routes to output b when sel=1' do
      demux.set_input(:a, 0x42)
      demux.set_input(:sel, 1)
      demux.propagate

      expect(demux.get_output(:y0)).to eq(0)
      expect(demux.get_output(:y1)).to eq(0x42)
    end
  end

  describe RHDL::HDL::Demux4 do
    let(:demux) { RHDL::HDL::Demux4.new(nil, width: 8) }

    it 'routes to correct output' do
      demux.set_input(:a, 0xFF)

      4.times do |sel|
        demux.set_input(:sel, sel)
        demux.propagate

        4.times do |out|
          expected = (out == sel) ? 0xFF : 0
          expect(demux.get_output("y#{out}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe RHDL::HDL::Decoder2to4 do
    let(:dec) { RHDL::HDL::Decoder2to4.new }

    it 'produces one-hot output' do
      dec.set_input(:en, 1)

      dec.set_input(:a, 0)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(1)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)

      dec.set_input(:a, 2)
      dec.propagate
      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y2)).to eq(1)
    end

    it 'outputs all zeros when disabled' do
      dec.set_input(:en, 0)
      dec.set_input(:a, 1)
      dec.propagate

      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y1)).to eq(0)
      expect(dec.get_output(:y2)).to eq(0)
      expect(dec.get_output(:y3)).to eq(0)
    end
  end

  describe RHDL::HDL::Decoder3to8 do
    let(:dec) { RHDL::HDL::Decoder3to8.new }

    it 'decodes all 8 values' do
      dec.set_input(:en, 1)

      8.times do |i|
        dec.set_input(:a, i)
        dec.propagate

        8.times do |j|
          expected = (i == j) ? 1 : 0
          expect(dec.get_output("y#{j}".to_sym)).to eq(expected)
        end
      end
    end
  end

  describe RHDL::HDL::DecoderN do
    let(:dec) { RHDL::HDL::DecoderN.new(nil, width: 4) }

    it 'decodes N-bit input to 2^N outputs' do
      dec.set_input(:en, 1)

      dec.set_input(:a, 10)
      dec.propagate
      expect(dec.get_output(:y10)).to eq(1)
      expect(dec.get_output(:y0)).to eq(0)
      expect(dec.get_output(:y15)).to eq(0)
    end
  end

  describe RHDL::HDL::Encoder4to2 do
    let(:enc) { RHDL::HDL::Encoder4to2.new }

    it 'encodes one-hot input' do
      # Input :a is a 4-bit value where bit 2 is set (0b0100)
      enc.set_input(:a, 0b0100)
      enc.propagate

      expect(enc.get_output(:y)).to eq(2)
      expect(enc.get_output(:valid)).to eq(1)
    end

    it 'indicates invalid when no input' do
      enc.set_input(:a, 0b0000)
      enc.propagate

      expect(enc.get_output(:valid)).to eq(0)
    end

    it 'prioritizes higher input' do
      # Bits 0, 1, and 3 are set - highest is bit 3
      enc.set_input(:a, 0b1011)
      enc.propagate

      expect(enc.get_output(:y)).to eq(3)
    end
  end

  describe RHDL::HDL::Encoder8to3 do
    let(:enc) { RHDL::HDL::Encoder8to3.new }

    it 'encodes 8-bit one-hot to 3-bit binary' do
      # Bit 5 is set (0b00100000)
      enc.set_input(:a, 0b00100000)
      enc.propagate

      expect(enc.get_output(:y)).to eq(5)
      expect(enc.get_output(:valid)).to eq(1)
    end
  end

  describe RHDL::HDL::BarrelShifter do
    let(:shifter) { RHDL::HDL::BarrelShifter.new(nil, width: 8) }

    it 'shifts left' do
      shifter.set_input(:a, 0b00001111)
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 0)  # left
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00111100)
    end

    it 'shifts right logical' do
      shifter.set_input(:a, 0b11110000)
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00111100)
    end

    it 'shifts right arithmetic (sign extends)' do
      shifter.set_input(:a, 0b10000000)  # -128 in signed 8-bit
      shifter.set_input(:shift, 2)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 1)
      shifter.set_input(:rotate, 0)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b11100000)
    end

    it 'rotates left' do
      shifter.set_input(:a, 0b10000001)
      shifter.set_input(:shift, 1)
      shifter.set_input(:dir, 0)  # left
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 1)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b00000011)
    end

    it 'rotates right' do
      shifter.set_input(:a, 0b10000001)
      shifter.set_input(:shift, 1)
      shifter.set_input(:dir, 1)  # right
      shifter.set_input(:arith, 0)
      shifter.set_input(:rotate, 1)
      shifter.propagate

      expect(shifter.get_output(:y)).to eq(0b11000000)
    end
  end

  describe RHDL::HDL::SignExtend do
    let(:ext) { RHDL::HDL::SignExtend.new(nil, in_width: 8, out_width: 16) }

    it 'extends positive values with zeros' do
      ext.set_input(:a, 0x7F)  # Positive (MSB = 0)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0x007F)
    end

    it 'extends negative values with ones' do
      ext.set_input(:a, 0x80)  # Negative (MSB = 1)
      ext.propagate
      expect(ext.get_output(:y)).to eq(0xFF80)
    end
  end

  describe RHDL::HDL::ZeroExtend do
    let(:ext) { RHDL::HDL::ZeroExtend.new(nil, in_width: 8, out_width: 16) }

    describe 'simulation' do
      it 'extends with zeros' do
        ext.set_input(:a, 0xFF)
        ext.propagate
        expect(ext.get_output(:y)).to eq(0x00FF)
      end
    end

    describe 'synthesis' do
      it 'has a behavior block defined' do
        expect(RHDL::HDL::ZeroExtend.behavior_defined?).to be_truthy
      end

      it 'generates valid IR' do
        ir = RHDL::HDL::ZeroExtend.to_ir
        expect(ir).to be_a(RHDL::Export::IR::ModuleDef)
      end

      it 'generates valid Verilog' do
        verilog = RHDL::HDL::ZeroExtend.to_verilog
        expect(verilog).to include('module zero_extend')
        expect(verilog).to include('assign y')
      end
    end
  end

  describe RHDL::HDL::PopCount do
    let(:pop) { RHDL::HDL::PopCount.new(nil, width: 8) }

    it 'counts set bits' do
      pop.set_input(:a, 0b10101010)
      pop.propagate
      expect(pop.get_output(:count)).to eq(4)

      pop.set_input(:a, 0b11111111)
      pop.propagate
      expect(pop.get_output(:count)).to eq(8)

      pop.set_input(:a, 0b00000000)
      pop.propagate
      expect(pop.get_output(:count)).to eq(0)
    end
  end

  describe RHDL::HDL::LZCount do
    let(:lzc) { RHDL::HDL::LZCount.new(nil, width: 8) }

    it 'counts leading zeros' do
      lzc.set_input(:a, 0b10000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(0)

      lzc.set_input(:a, 0b00001000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(4)

      lzc.set_input(:a, 0b00000001)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(7)

      lzc.set_input(:a, 0b00000000)
      lzc.propagate
      expect(lzc.get_output(:count)).to eq(8)
    end
  end
end
