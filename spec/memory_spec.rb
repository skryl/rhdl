require 'rspec'
require_relative 'spec_helper'

describe SRLatch do

  let(:latch) { SRLatch.new }

  it 'latches' do

    expect(latch.set!(s: 0, r: 1).outputs).to eq(q: 0, q_not: 1)
    expect(latch.set!(s: 0, r: 0).outputs).to eq(q: 0, q_not: 1)

    expect(latch.set!(s: 1, r: 0).outputs).to eq(q: 1, q_not: 0)
    expect(latch.set!(s: 0, r: 0).outputs).to eq(q: 1, q_not: 0)

  end

end

describe DLatch do

  let(:latch) { DLatch.new }

  it 'latches' do

    expect(latch.set!(clk: 1, d: 0).outputs).to eq(q: 0, q_not: 1)

    expect(latch.set!(clk: 1, d: 1).outputs).to eq(q: 1, q_not: 0)
    expect(latch.set!(clk: 1, d: 0).outputs).to eq(q: 0, q_not: 1)
    expect(latch.set!(clk: 1, d: 1).outputs).to eq(q: 1, q_not: 0)
    expect(latch.set!(clk: 1, d: 0).outputs).to eq(q: 0, q_not: 1)

    expect(latch.set!(clk: 0, d: 1).outputs).to eq(q: 0, q_not: 1)
    expect(latch.set!(clk: 0, d: 0).outputs).to eq(q: 0, q_not: 1)
    expect(latch.set!(clk: 0, d: 1).outputs).to eq(q: 0, q_not: 1)
    expect(latch.set!(clk: 0, d: 0).outputs).to eq(q: 0, q_not: 1)

  end

end

describe MSFlipFlop do

  let(:flop) { MSFlipFlop.new }

  it 'is edge triggered' do

    expect(flop.set!(clk: 1, d: 0).outputs).to eq(q: 1)
    expect(flop.set!(clk: 0, d: 0).outputs).to eq(q: 0)

    expect(flop.set!(clk: 1, d: 0).outputs).to eq(q: 0)
    expect(flop.set!(clk: 1, d: 1).outputs).to eq(q: 0)
    expect(flop.set!(clk: 0, d: 1).outputs).to eq(q: 1)

    expect(flop.set!(clk: 1, d: 1).outputs).to eq(q: 1)
    expect(flop.set!(clk: 1, d: 0).outputs).to eq(q: 1)
    expect(flop.set!(clk: 0, d: 0).outputs).to eq(q: 0)

  end

end


describe Register8 do

  let(:reg) { Register8.new }

  it 'is edge triggered' do

    expect(reg.set!(w: 1, clk: 1, d: 0).outputs).to eq(q: '11111111')
    expect(reg.set!(w: 0, clk: 0, d: 0).outputs).to eq(q: '00000000')

    expect(reg.set!(w: 1, clk: 1, d: '10101010').outputs).to eq(q: '00000000')
    expect(reg.set!(w: 0, clk: 0, d: 0).outputs).to eq(q: '10101010')

  end

end
