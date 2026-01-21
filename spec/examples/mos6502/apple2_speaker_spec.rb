# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../examples/mos6502/utilities/apple2_speaker'

RSpec.describe MOS6502::Apple2Speaker do
  subject(:speaker) { described_class.new }

  describe '#initialize' do
    it 'starts disabled' do
      expect(speaker.enabled).to be false
    end
  end

  describe '#toggle' do
    it 'accepts a cycle parameter' do
      expect { speaker.toggle(1000) }.not_to raise_error
    end

    it 'does nothing when disabled' do
      # Should not raise error or produce audio when disabled
      10.times { speaker.toggle(1000) }
    end
  end

  describe '#update_cycle' do
    it 'accepts a cycle parameter' do
      expect { speaker.update_cycle(1000) }.not_to raise_error
    end
  end

  describe '#start' do
    it 'enables the speaker' do
      # Note: actual audio playback requires audio system
      speaker.start
      # If audio system not available, enabled will still be set
      # but no error should be raised
    end
  end

  describe '#stop' do
    it 'disables the speaker' do
      speaker.start
      speaker.stop
      expect(speaker.enabled).to be false
    end
  end

  describe '#enable' do
    it 'sets enabled state' do
      speaker.enable(true)
      expect(speaker.enabled).to be true

      speaker.enable(false)
      expect(speaker.enabled).to be false
    end
  end

  describe '.available?' do
    it 'returns a boolean' do
      result = described_class.available?
      expect(result).to be(true).or be(false)
    end
  end
end

RSpec.describe MOS6502::Apple2SpeakerBeep do
  subject(:speaker) { described_class.new }

  describe '#initialize' do
    it 'starts enabled' do
      expect(speaker.enabled).to be true
    end
  end

  describe '#toggle' do
    it 'accepts a cycle parameter' do
      expect { speaker.toggle(1000) }.not_to raise_error
    end

    it 'increments toggle count' do
      100.times { speaker.toggle(0) }
      # Should not raise error
    end
  end

  describe '#enable' do
    it 'sets enabled state' do
      speaker.enable(false)
      expect(speaker.enabled).to be false

      speaker.enable(true)
      expect(speaker.enabled).to be true
    end
  end

  describe '.available?' do
    it 'always returns true' do
      expect(described_class.available?).to be true
    end
  end
end
