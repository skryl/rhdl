# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::HDL::BarrelShifter do
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
