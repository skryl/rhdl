# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../examples/apple2/utilities/speaker'

RSpec.describe RHDL::Apple2::Speaker do
  let(:speaker) { described_class.new }

  describe '#initialize' do
    it 'starts disabled' do
      expect(speaker.enabled).to be false
    end

    it 'has zero toggle count initially' do
      expect(speaker.toggle_count).to eq(0)
    end

    it 'has no audio backend initially' do
      expect(speaker.audio_backend).to be_nil
    end
  end

  describe '#toggle' do
    context 'when not running' do
      it 'increments toggle count' do
        expect { speaker.toggle }.to change { speaker.toggle_count }.by(1)
      end

      it 'does not generate samples' do
        speaker.toggle
        expect(speaker.samples_written).to eq(0)
      end
    end
  end

  describe '#update_state' do
    it 'toggles on state change from 0 to 1' do
      speaker.update_state(0)
      expect { speaker.update_state(1) }.to change { speaker.toggle_count }.by(1)
    end

    it 'toggles on state change from 1 to 0' do
      speaker.update_state(1)
      expect { speaker.update_state(0) }.to change { speaker.toggle_count }.by(1)
    end

    it 'does not toggle when state unchanged' do
      speaker.update_state(0)
      expect { speaker.update_state(0) }.not_to change { speaker.toggle_count }
    end
  end

  describe '#status' do
    it 'returns "OFF" when not running' do
      expect(speaker.status).to eq("OFF")
    end

    it 'returns "no backend" when started but no audio available' do
      # Mock no audio backend available
      allow(speaker).to receive(:find_audio_command).and_return([nil, nil])
      speaker.start
      expect(speaker.status).to eq("no backend")
    end
  end

  describe '#active?' do
    it 'returns false when no toggles' do
      expect(speaker.active?).to be false
    end

    it 'returns true when speaker has been toggled recently' do
      # First check sets the baseline
      speaker.active?
      # Toggle the speaker
      10.times { speaker.toggle }
      # Force activity check by sleeping
      speaker.instance_variable_set(:@last_activity_check, Time.now - 0.2)
      expect(speaker.active?).to be true
    end
  end

  describe '#debug_info' do
    it 'returns a hash with status information' do
      info = speaker.debug_info
      expect(info).to be_a(Hash)
      expect(info).to include(
        :backend,
        :enabled,
        :running,
        :toggle_count,
        :samples_generated,
        :samples_written,
        :buffer_size,
        :last_error,
        :pipe_open
      )
    end
  end

  describe '.available?' do
    it 'returns a boolean' do
      result = described_class.available?
      expect([true, false]).to include(result)
    end
  end

  describe '.find_available_backend' do
    it 'returns nil or a valid backend name' do
      result = described_class.find_available_backend
      expect([nil, 'sox', 'ffplay', 'paplay', 'aplay']).to include(result)
    end
  end

  describe '#start and #stop' do
    context 'when no audio backend available' do
      before do
        allow(speaker).to receive(:find_audio_command).and_return([nil, nil])
      end

      it 'sets backend to none on start' do
        speaker.start
        expect(speaker.audio_backend).to eq('none')
      end
    end

    it 'can be stopped without starting' do
      expect { speaker.stop }.not_to raise_error
    end
  end

  describe '#enable' do
    it 'enables the speaker' do
      speaker.enable(true)
      expect(speaker.enabled).to be true
    end

    it 'disables the speaker' do
      speaker.enable(true)
      speaker.enable(false)
      expect(speaker.enabled).to be false
    end
  end

  describe 'sample generation' do
    it 'calculates correct sample count for interval' do
      # At 22050 Hz, 0.001 seconds = ~22 samples
      interval = 0.001
      expected_samples = (interval * described_class::SAMPLE_RATE).to_i

      # Enable generation path
      speaker.instance_variable_set(:@running, true)
      speaker.instance_variable_set(:@enabled, true)
      speaker.instance_variable_set(:@last_toggle_time, Time.now - interval)
      speaker.instance_variable_set(:@speaker_state, true)

      # Create a mock mutex to allow sample generation
      speaker.instance_variable_set(:@mutex, Mutex.new)
      speaker.instance_variable_set(:@sample_buffer, [])
      speaker.instance_variable_set(:@audio_pipe, nil)  # Prevent flush

      speaker.send(:generate_samples, interval)

      buffer = speaker.instance_variable_get(:@sample_buffer)
      expect(buffer.size).to eq(expected_samples)
    end

    it 'generates positive amplitude when speaker state is true' do
      speaker.instance_variable_set(:@running, true)
      speaker.instance_variable_set(:@enabled, true)
      speaker.instance_variable_set(:@speaker_state, true)
      speaker.instance_variable_set(:@mutex, Mutex.new)
      speaker.instance_variable_set(:@sample_buffer, [])
      speaker.instance_variable_set(:@audio_pipe, nil)

      speaker.send(:generate_samples, 0.001)

      buffer = speaker.instance_variable_get(:@sample_buffer)
      expect(buffer.first).to eq(described_class::AMPLITUDE)
    end

    it 'generates negative amplitude when speaker state is false' do
      speaker.instance_variable_set(:@running, true)
      speaker.instance_variable_set(:@enabled, true)
      speaker.instance_variable_set(:@speaker_state, false)
      speaker.instance_variable_set(:@mutex, Mutex.new)
      speaker.instance_variable_set(:@sample_buffer, [])
      speaker.instance_variable_set(:@audio_pipe, nil)

      speaker.send(:generate_samples, 0.001)

      buffer = speaker.instance_variable_get(:@sample_buffer)
      expect(buffer.first).to eq(-described_class::AMPLITUDE)
    end
  end

  describe 'constants' do
    it 'has a reasonable sample rate' do
      expect(described_class::SAMPLE_RATE).to eq(22050)
    end

    it 'has a reasonable buffer size' do
      expect(described_class::BUFFER_SIZE).to eq(512)
    end

    it 'has amplitude within 16-bit signed range' do
      expect(described_class::AMPLITUDE).to be_between(0, 32767)
    end
  end
end
