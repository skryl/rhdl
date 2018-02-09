require 'rspec'
require_relative 'spec_helper'


describe Alu8 do

  let(:alu) { Alu8.new }

  describe 'and' do

    let(:control) { { c: '00' } }

    it 'performs and op' do
      (0..255).multisample(100, 2) do |(v1,v2)|
        r = v1 & v2
        expect(alu.set!(a: v1.to_b, b: v2.to_b, **control).outputs).to \
          include(out: Wire(r.to_b))
      end
    end

  end


  describe 'or' do

    let(:control) { { c: '01' } }

    it 'performs and op' do
      (0..255).multisample(100, 2) do |(v1,v2)|
        r = v1 | v2
        expect(alu.set!(a: v1.to_b, b: v2.to_b, **control).outputs).to \
          include(out: Wire(r.to_b))
      end
    end

  end


  describe 'addition' do

    let(:control) { { c: '10' } }

    it 'performs 8 bit addition' do
      (0..127).multisample(100, 2) do |(v1,v2)|
        r      = v1 + v2
        r_bits = r.to_ba(9)
        carry  = r_bits[0]
        over   = r > 127 ? 1 : 0
        zero   = r == 0 ? 1 : 0

        expect(alu.set!(a: v1.to_b, b: v2.to_b, **control).outputs).to \
          match(out: r_bits[1..8], cout: carry, over: over, zero: zero)
      end
    end

  end

  describe 'subtraction' do

    let(:control) { { c: '10', bneg: 1 } }

    it 'performs 8 bit subtraction' do
      (0..127).multisample(100, 2) do |(v1,v2)|
        r      = v1 - v2
        r_bits = r.to_ba(9)
        carry  = r_bits[0]
        over   = r > 127 ? 1 : 0
        zero   = r == 0 ? 1 : 0

        expect(alu.set!(a: v1.to_b, b: v2.to_b, **control).outputs).to \
          match(out: r_bits[1..8], cout: carry, over: over, zero: zero)
      end
    end

  end



end
