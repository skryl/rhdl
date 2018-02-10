require 'rspec'
require_relative 'spec_helper'


describe Add8 do

  let(:add8) { Add8.new }

  it 'performs 8 bit addition' do
    max = 2**8
    max_int = (max/2-1)
    (0...max).multisample(100, 2) do |(v1,v2)|
      r      = v1 + v2
      r_bits = r.to_ba(9)
      carry  = r_bits[0]
      over   = (v1 > max_int && v2 > max_int && r_bits[1] == 0) ||
               (v1 <= max_int && v2 <= max_int && r_bits[1] == 1) ? 1 : 0

      expect(add8.set!(a: v1.to_b(8), b: v2.to_b(8)).outputs).to eq(s: r_bits[1..8], cout: carry, over: over)
    end
  end

end


describe And8 do

  let(:and8) { And8.new }

  it 'performs and op' do
    (0..255).multisample(100, 2) do |(v1,v2)|
      r = v1 & v2
      expect(and8.set!(a: v1.to_b(8), b: v2.to_b(8)).outputs).to eq(out: r.to_b(8))
    end
  end

end


describe Or8 do

  let(:or8) { Or8.new }

  it 'performs or op' do
    (0..255).multisample(100, 2) do |(v1,v2)|
      r = v1 | v2
      expect(or8.set!(a: v1.to_b(8), b: v2.to_b(8)).outputs).to eq(out: r.to_b(8))
    end
  end

end


describe Inv8 do

  let(:inv8) { Inv8.new }

  it 'performs or op' do
    (0..255).each do |(v)|
      r = ~v
      expect(inv8.set!(a: v.to_b(8)).outputs).to eq(out: r.to_b(8))
    end
  end

end


describe ZeroEq8 do

  let(:eqz8) { ZeroEq8.new }

  it 'performs comparisons with 0' do
    (0..255).each do |v|
      r = (v == 0 ? 1 : 0)
      expect(eqz8.set!(a: v.to_b(8)).outputs).to eq(out: r)
    end
  end

end
