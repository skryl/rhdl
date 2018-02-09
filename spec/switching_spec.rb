require 'rspec'
require_relative 'spec_helper'

describe Decoder4 do

  it 'decodes' do
    (0..3).each do |idx|
      data = [0,0,0,0]
      data[idx] = 1

      expect(Decoder4.new(s: idx.to_b(2)).outputs).to eq(d: data)
    end
  end

end


describe Decoder8 do

  it 'decodes' do
    (0..7).each do |idx|
      data = [0,0,0,0,0,0,0,0]
      data[idx] = 1

      expect(Decoder8.new(s: idx.to_b(3)).outputs).to eq(d: data)
    end
  end

end


describe Mux2 do

  it 'muxes' do
    (0..1).each do |idx|
      d = [0,1]

      expect(Mux2.new(s: idx, a: d[0], b: d[1]).outputs).to eq(out: d[idx])
    end
  end

end


describe Mux2x8 do

  it 'muxes' do
    (0..1).each do |idx|
      data = ['00001111','11110000']

      expect(Mux2x8.new(a: data[0], b: data[1], s: idx).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux4 do

  it 'muxes' do
    (0..3).each do |idx|
      data = [0,1,0,1]

      expect(Mux4.new(s: idx.to_b(2), d: data).outputs).to eq(out: data[idx])
    end
  end

end


describe Mux8 do

  it 'muxes' do
    (0..7).each do |idx|
      data = [0,1,0,1,0,1,0,1]

      expect(Mux8.new(s: idx.to_b(3), d: data).outputs).to eq(out: data[idx])
    end
  end

end


describe Mux4x8 do

  it 'muxes' do
    (0..3).each do |idx|
      data = ['00001111','11110000', '1100110011', '0011001100']

      expect(Mux4x8.new(a: data[0], b: data[1], c: data[2], d: data[3], s: idx.to_b(2)).outputs).to eq(out: data[idx].to_a)
    end
  end

end


describe Mux8x8 do

  it 'muxes' do
    (0..7).each do |idx|
      data = ['00110011','00001111', '1100110011', '11110000', '10101010', '01010101', '00000000', '11111111']

      expect(Mux8x8.new(a: data[0], b: data[1], c: data[2], d: data[3],
                        e: data[4], f: data[5], g: data[6], h: data[7],
                        s: idx.to_b(3)).outputs).to eq(out: data[idx].to_a)
    end
  end

end
