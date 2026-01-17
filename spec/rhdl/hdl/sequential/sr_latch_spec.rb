require 'spec_helper'

RSpec.describe RHDL::HDL::SRLatch do
  let(:latch) { RHDL::HDL::SRLatch.new }

  before do
    latch.set_input(:en, 1)
  end

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
