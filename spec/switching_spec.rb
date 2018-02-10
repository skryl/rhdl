require 'rspec'
require_relative 'spec_helper'

describe Decoder4 do

  let(:decoder) { described_class.new }

  it 'decodes' do
    (0..3).each do |idx|
      data = [0,0,0,0]
      data[idx] = 1
      expect(decoder.set!(s: idx.to_b(2)).outputs).to eq(d: data)
    end
  end

end


describe Decoder8 do

  let(:decoder) { described_class.new }

  it 'decodes' do
    (0..7).each do |idx|
      data = [0,0,0,0,0,0,0,0]
      data[idx] = 1
      expect(decoder.set!(s: idx.to_b(3)).outputs).to eq(d: data)
    end
  end

end


describe Mux2 do

  let(:mux) { described_class.new }

  it 'muxes' do
    (0..1).each do |idx|
      d = [0,1]

      expect(mux.set!(s: idx, a: d[0], b: d[1]).outputs).to eq(out: d[idx])
    end
  end

end


describe Mux2x8 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = ['00001111','11110000']

    (0..1).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], s: idx).outputs).to eq(out: data[idx].to_a)
    end
  end

end

describe Mux2x32 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = ['01'*16,'10'*16]

    (0..1).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], s: idx).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux4 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = [0,1,0,1]

    (0..3).each do |idx|
      expect(mux.set!(s: idx.to_b(2), d: data).outputs).to eq(out: data[idx])
    end
  end

end


describe Mux4x8 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = ['00001111','11110000', '1100110011', '0011001100']

    (0..3).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], c: data[2], d: data[3], s: idx.to_b(2)).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux4x8 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = ['00001111','11110000', '1100110011', '0011001100'].map { |b| b*4 }

    (0..3).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], c: data[2], d: data[3], s: idx.to_b(2)).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux8 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = [0,1,0,1,0,1,0,1]

    (0..7).each do |idx|
      expect(mux.set!(s: idx.to_b(3), d: data).outputs).to eq(out: data[idx])
    end
  end

end


describe Mux8x8 do

  let(:mux) { described_class.new }

  it 'muxes' do
     data = ['00110011','00001111', '1100110011', '11110000', '10101010', '01010101', '00000000', '11111111']

    (0..7).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], c: data[2], d: data[3],
                      e: data[4], f: data[5], g: data[6], h: data[7],
                      s: idx.to_b(3)).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux8x32 do

  let(:mux) { described_class.new }

  it 'muxes' do
    data = ['00110011','00001111', '1100110011', '11110000', '10101010', '01010101', '00000000', '11111111'].map { |b| b*4 }

    (0..7).each do |idx|
      expect(mux.set!(a: data[0], b: data[1], c: data[2], d: data[3],
                      e: data[4], f: data[5], g: data[6], h: data[7],
                      s: idx.to_b(3)).outputs).to eq(out: data[idx].to_a)
    end
  end

end
