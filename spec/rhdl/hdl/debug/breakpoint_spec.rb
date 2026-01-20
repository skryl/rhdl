# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RHDL::Debug::Breakpoint do
  it 'checks condition and triggers' do
    counter = 0
    bp = RHDL::Debug::Breakpoint.new(condition: -> (ctx) { ctx[:value] > 5 }) do
      counter += 1
    end

    expect(bp.check({ value: 3 })).to be false
    expect(bp.check({ value: 10 })).to be true
    expect(counter).to eq(1)
    expect(bp.hit_count).to eq(1)
  end

  it 'can be enabled and disabled' do
    bp = RHDL::Debug::Breakpoint.new(condition: -> (ctx) { true })

    expect(bp.check({})).to be true

    bp.disable!
    expect(bp.check({})).to be false

    bp.enable!
    expect(bp.check({})).to be true
  end

  it 'resets hit count' do
    bp = RHDL::Debug::Breakpoint.new(condition: -> (ctx) { true })
    bp.check({})
    bp.check({})
    expect(bp.hit_count).to eq(2)

    bp.reset!
    expect(bp.hit_count).to eq(0)
  end
end
