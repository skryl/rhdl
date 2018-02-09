require 'rspec'
require_relative 'spec_helper'


describe Add32 do

  let(:add32) { Add32.new }

  it 'performs 32 bit addition' do
    (0..127).multisample(100, 2) do |(v1,v2)|
      r      = v1 + v2
      r_bits = r.to_ba(33)
      carry  = r_bits[0]
      over   = r > 127 ? 1 : 0

      expect(add32.set!(a: v1.to_b(32), b: v2.to_b(32)).outputs).to eq(s: r_bits[1..32], cout: carry, over: over)
    end
  end

end


describe And32 do

  let(:and32) { And32.new }

  it 'performs and op' do
    (0..255).multisample(100, 2) do |(v1,v2)|
      r = v1 & v2
      expect(and32.set!(a: v1.to_b(32), b: v2.to_b(32)).outputs).to eq(out: r.to_b(32))
    end
  end

end


describe Or32 do

  let(:or32) { Or32.new }

  it 'performs or op' do
    (0..255).multisample(100, 2) do |(v1,v2)|
      r = v1 | v2
      expect(or32.set!(a: v1.to_b(32), b: v2.to_b(32)).outputs).to eq(out: r.to_b(32))
    end
  end

end


describe Inv32 do

  let(:inv32) { Inv32.new }

  it 'performs or op' do
    (0..255).each do |(v)|
      r = ~v
      expect(inv32.set!(a: v.to_b(32)).outputs).to eq(out: r.to_b(32))
    end
  end

end


describe ZeroEq32 do

  let(:eqz32) { ZeroEq32.new }

  it 'performs comparisons with 0' do
    (0..255).each do |v|
      r = (v == 0 ? 1 : 0)
      expect(eqz32.set!(a: v.to_b(32)).outputs).to eq(out: r)
    end
  end

end
