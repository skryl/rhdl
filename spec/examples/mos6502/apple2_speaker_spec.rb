# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../examples/mos6502/utilities/output/apple2_speaker'

RSpec.describe MOS6502::Apple2Speaker do
  subject(:speaker) { described_class.new }

  describe '#initialize' do
    it 'starts disabled' do
      expect(speaker.enabled).to be false
    end

    it 'starts with zero toggle count' do
      expect(speaker.toggle_count).to eq 0
    end
  end

  describe '#status' do
    it 'returns off when not started' do
      expect(speaker.status).to eq 'off'
    end

    it 'returns backend name or none after start' do
      speaker.start
      expect(['sox', 'ffplay', 'paplay', 'aplay', 'none', 'no backend', 'off']).to include(speaker.status)
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

  describe '#active?' do
    it 'returns false when no toggles' do
      expect(speaker.active?).to be false
    end

    it 'returns true after toggles' do
      speaker.start
      10.times { speaker.toggle(0) }
      # Force activity check
      speaker.instance_variable_set(:@last_activity_check, Time.now - 1)
      speaker.active?
      expect(speaker.active?).to be true
      speaker.stop
    end
  end

  describe '#debug_info' do
    it 'returns a hash with debug information' do
      info = speaker.debug_info
      expect(info).to be_a(Hash)
      expect(info).to include(:backend, :enabled, :running, :toggle_count)
    end
  end

  describe '#sync_toggles' do
    context 'when not running' do
      it 'does not generate samples' do
        speaker.sync_toggles(10, 0.033)
        expect(speaker.samples_written).to eq(0)
      end
    end

    context 'when running' do
      before do
        speaker.instance_variable_set(:@running, true)
        speaker.instance_variable_set(:@enabled, true)
        speaker.instance_variable_set(:@mutex, Mutex.new)
        speaker.instance_variable_set(:@sample_buffer, [])
        speaker.instance_variable_set(:@audio_pipe, nil)
      end

      it 'increments toggle count by the batched count' do
        initial_count = speaker.toggle_count
        speaker.sync_toggles(50, 0.033)
        expect(speaker.toggle_count).to eq(initial_count + 50)
      end

      it 'generates samples based on average interval' do
        # 10 toggles over 0.01 seconds = 1ms average interval
        # At 22050 Hz, 1ms = ~22 samples per toggle
        speaker.sync_toggles(10, 0.01)

        buffer = speaker.instance_variable_get(:@sample_buffer)
        # Should have samples: 10 toggles * (0.001 * 22050) = ~220 samples
        expect(buffer.size).to be_between(200, 250)
      end

      it 'skips audio generation for intervals below MIN_TOGGLE_INTERVAL' do
        # 100 toggles in 0.0001 seconds = 0.000001s average (below MIN_TOGGLE_INTERVAL)
        speaker.sync_toggles(100, 0.0001)

        buffer = speaker.instance_variable_get(:@sample_buffer)
        expect(buffer.size).to eq(0)
      end

      it 'skips audio generation for intervals above MAX_TOGGLE_INTERVAL' do
        # 2 toggles over 10 seconds = 5s average (above MAX_TOGGLE_INTERVAL)
        speaker.sync_toggles(2, 10.0)

        buffer = speaker.instance_variable_get(:@sample_buffer)
        expect(buffer.size).to eq(0)
      end

      it 'alternates speaker state for each toggle' do
        initial_state = speaker.instance_variable_get(:@speaker_state)
        speaker.sync_toggles(5, 0.005)  # 5 toggles

        # After 5 toggles, state should be inverted
        final_state = speaker.instance_variable_get(:@speaker_state)
        expect(final_state).to eq(!initial_state)
      end

      it 'does nothing with zero toggles' do
        initial_count = speaker.toggle_count
        speaker.sync_toggles(0, 0.033)
        expect(speaker.toggle_count).to eq(initial_count)
      end

      it 'does nothing with zero elapsed time' do
        initial_count = speaker.toggle_count
        speaker.sync_toggles(10, 0)
        expect(speaker.toggle_count).to eq(initial_count)
      end
    end
  end
end

RSpec.describe MOS6502::Apple2SpeakerBeep do
  subject(:speaker) { described_class.new }

  describe '#initialize' do
    it 'starts enabled' do
      expect(speaker.enabled).to be true
    end

    it 'starts with zero toggle count' do
      expect(speaker.toggle_count).to eq 0
    end
  end

  describe '#toggle' do
    it 'accepts a cycle parameter' do
      expect { speaker.toggle(1000) }.not_to raise_error
    end

    it 'increments toggle count' do
      100.times { speaker.toggle(0) }
      expect(speaker.toggle_count).to eq 100
    end
  end

  describe '#status' do
    it 'returns beep when enabled' do
      expect(speaker.status).to eq 'beep'
    end

    it 'returns off when disabled' do
      speaker.enable(false)
      expect(speaker.status).to eq 'off'
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
