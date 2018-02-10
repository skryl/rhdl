require 'rspec'
require_relative 'spec_helper'


describe Alu32 do

  let(:alu) { described_class.new }

  describe 'and' do

    let(:control) { { c: '00' } }

    it 'performs and op' do
      (0..255).multisample(100, 2) do |(v1,v2)|
        r = v1 & v2
        expect(alu.set!(a: v1.to_b(32), b: v2.to_b(32), **control).outputs).to \
          include(out: Wire(r.to_b(32)))
      end
    end

  end


  describe 'or' do

    let(:control) { { c: '01' } }

    it 'performs and op' do
      (0..255).multisample(100, 2) do |(v1,v2)|
        r = v1 | v2
        expect(alu.set!(a: v1.to_b(32), b: v2.to_b(32), **control).outputs).to \
          include(out: Wire(r.to_b(32)))
      end
    end

  end


  describe 'addition' do

    let(:control) { { c: '10' } }

    it 'performs 32 bit addition' do
      max = 2**32
      max_int = (max/2-1)
      (0...max).multisample(100, 2) do |(v1,v2)|
        r      = v1 + v2
        r_bits = r.to_ba(33)
        carry  = r_bits[0]
        zero   = r_bits[1..-1].all? { |b| b == 0 } ? 1 : 0
        over   = (v1 > max_int && v2 > max_int && r_bits[1] == 0) ||
                 (v1 <= max_int && v2 <= max_int && r_bits[1] == 1) ? 1 : 0

        expect(alu.set!(a: v1.to_b(32), b: v2.to_b(32), **control).outputs).to \
          eq(out: r_bits[1..32], cout: carry, over: over, zero: zero)
      end
    end

  end

  describe 'subtraction' do

    let(:control) { { c: '10', bneg: 1 } }

    it 'performs 32 bit subtraction' do
      max = 2**32
      max_int = (max/2-1)
      (0...max).multisample(100, 2) do |(v1,v2)|
        r      = v1 - v2
        r_bits = r.to_ba(33)
        carry  = r_bits[0]
        zero   = r_bits[1..-1].all? { |b| b == 0 } ? 1 : 0
        over   = (v1 > max_int && v2 <= max_int && r_bits[1] == 0) ||
                 (v1 <= max_int && v2 > max_int && r_bits[1] == 1) ? 1 : 0

        expect(alu.set!(a: v1.to_b(32), b: v2.to_b(32), **control).outputs).to \
          eq(out: r_bits[1..32], cout: carry, over: over, zero: zero)
      end
    end

  end

end
