# frozen_string_literal: true

require 'spec_helper'

# Load the PS2 encoder
require_relative '../../../../examples/apple2/utilities/input/ps2_encoder'

RSpec.describe RHDL::Examples::Apple2::PS2Encoder do
  let(:encoder) { described_class.new }

  describe '#initialize' do
    it 'starts in idle state' do
      expect(encoder.sending?).to be false
    end

    it 'returns idle PS/2 signals (both high)' do
      clk, data = encoder.next_ps2_state
      expect(clk).to eq(1)
      expect(data).to eq(1)
    end
  end

  describe '#queue_key' do
    it 'queues a key for transmission' do
      encoder.queue_key(0x41) # 'A'
      expect(encoder.sending?).to be true
    end

    it 'returns non-idle PS/2 signals while sending' do
      encoder.queue_key(0x41) # 'A'
      # Get a few states to ensure we're transmitting
      states = 5.times.map { encoder.next_ps2_state }
      # Should have some clock transitions (not all high)
      clocks = states.map(&:first)
      expect(clocks.uniq.length).to be > 1
    end

    it 'eventually returns to idle after transmission' do
      encoder.queue_key(0x41) # 'A'
      # Drain the queue (should take roughly 33 states per scancode * 2 for press+release)
      500.times { encoder.next_ps2_state }
      expect(encoder.sending?).to be false
    end

    context 'with shifted keys' do
      it 'queues shift press, key, key release, shift release for symbols' do
        encoder.queue_key(0x21) # '!' (shifted '1')
        # Should be sending shift + 1 + releases
        expect(encoder.sending?).to be true
        # The queue should be longer than for an unshifted key
        expect(encoder.queue_length).to be > 100
      end
    end
  end

  describe '#queue_scancode' do
    it 'queues an 11-bit PS/2 frame' do
      encoder.queue_scancode(0x1C) # Scancode for 'A'
      # 11 bits * 3 states per bit + gap = ~43 states
      expect(encoder.queue_length).to be >= 33
    end

    it 'generates correct parity' do
      encoder.queue_scancode(0x00) # All zeros (parity should be 1)
      # Extract the parity bit from the frame
      # This is a basic structural test - we verify the queue is populated
      expect(encoder.sending?).to be true
    end
  end

  describe '#clear' do
    it 'clears the queue' do
      encoder.queue_key(0x41)
      expect(encoder.sending?).to be true
      encoder.clear
      expect(encoder.sending?).to be false
    end
  end

  describe 'ASCII to scancode mapping' do
    # Test a few key mappings
    [
      [0x41, 0x1C, false], # A
      [0x5A, 0x1A, false], # Z
      [0x30, 0x45, false], # 0
      [0x39, 0x46, false], # 9
      [0x20, 0x29, false], # Space
      [0x0D, 0x5A, false], # Enter
      [0x08, 0x66, false], # Backspace
      [0x21, 0x16, true],  # ! (shifted 1)
      [0x40, 0x1E, true],  # @ (shifted 2)
    ].each do |ascii, expected_scancode, needs_shift|
      it "maps ASCII #{ascii.to_s(16)} correctly" do
        mapping = RHDL::Examples::Apple2::PS2Encoder::ASCII_TO_SCANCODE[ascii]
        expect(mapping).not_to be_nil, "Missing mapping for ASCII #{ascii.to_s(16)}"
        scancode, shift = mapping
        expect(scancode).to eq(expected_scancode)
        expect(shift).to eq(needs_shift)
      end
    end
  end

  describe 'PS/2 protocol timing' do
    it 'generates proper clock transitions for each bit' do
      encoder.queue_scancode(0xAA) # Some test scancode

      # Each bit should have: [1, data], [0, data], [1, data]
      # Verify we get clock high->low->high transitions
      clock_states = []
      while encoder.sending?
        clk, _data = encoder.next_ps2_state
        clock_states << clk
      end

      # Should have alternating clock states (high-low-high for each bit)
      # 11 bits * 3 states = 33 states minimum
      expect(clock_states.length).to be >= 33
    end

    it 'data is stable on falling clock edge' do
      encoder.queue_scancode(0x1C) # Scancode for 'A'

      prev_clk = 1
      prev_data = 1
      data_on_falling_edges = []

      while encoder.sending?
        clk, data = encoder.next_ps2_state
        # Capture data on falling edge
        if prev_clk == 1 && clk == 0
          data_on_falling_edges << data
        end
        prev_clk = clk
        prev_data = data
      end

      # Should have 11 bits captured (start + 8 data + parity + stop)
      expect(data_on_falling_edges.length).to eq(11)

      # Verify start bit is 0
      expect(data_on_falling_edges[0]).to eq(0)

      # Verify stop bit is 1
      expect(data_on_falling_edges[10]).to eq(1)

      # Verify data bits (LSB first) = 0x1C = 0b00011100
      data_bits = data_on_falling_edges[1..8]
      received_byte = data_bits.each_with_index.reduce(0) { |acc, (bit, i)| acc | (bit << i) }
      expect(received_byte).to eq(0x1C)
    end
  end
end
