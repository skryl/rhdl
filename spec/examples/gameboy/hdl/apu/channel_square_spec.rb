# frozen_string_literal: true

require 'spec_helper'

# Game Boy Square Wave Channel Tests
# Tests the ChannelSquare component (channels 1 and 2)
#
# Features tested:
# - Component structure and ports
# - Duty cycle patterns (12.5%, 25%, 50%, 75%)
# - Trigger mechanism
# - DAC enable/disable logic
# - Output generation

RSpec.describe 'GameBoy::ChannelSquare' do
  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      @component_available = true
    rescue LoadError => e
      @component_available = false
    end
  end

  before(:each) do
    skip 'GameBoy components not available' unless @component_available
  end

  # Helper to create a clock cycle
  def clock_cycle(component, ce: 1)
    component.set_input(:ce, ce)
    component.set_input(:clk, 0)
    component.propagate
    component.set_input(:clk, 1)
    component.propagate
  end

  # Helper to run multiple clock cycles
  def run_cycles(component, n, ce: 1)
    n.times { clock_cycle(component, ce: ce) }
  end

  # Helper to reset and trigger the component with full initialization
  def reset_and_trigger(component, envelope: 0xF0, length_duty: 0x80)
    component.set_input(:reset, 1)
    clock_cycle(component)
    component.set_input(:reset, 0)
    component.set_input(:envelope, envelope)
    component.set_input(:length_duty, length_duty)
    component.set_input(:trigger, 1)
    clock_cycle(component)
    # Run a few more cycles to let state settle
    component.set_input(:trigger, 0)
    clock_cycle(component)
    component.propagate
  end

  describe 'ChannelSquare without sweep (channel 2)' do
    let(:channel) { GameBoy::ChannelSquare.new('ch2', has_sweep: false) }

    before do
      # Initialize default inputs
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:length_duty, 0x80)  # 50% duty cycle
      channel.set_input(:envelope, 0xF0)     # Max volume, no sweep
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    describe 'component structure' do
      it 'is a SequentialComponent' do
        expect(channel).to be_a(RHDL::HDL::SequentialComponent)
      end

      it 'has required input ports' do
        expect { channel.set_input(:clk, 0) }.not_to raise_error
        expect { channel.set_input(:ce, 0) }.not_to raise_error
        expect { channel.set_input(:reset, 0) }.not_to raise_error
        expect { channel.set_input(:sweep_reg, 0) }.not_to raise_error
        expect { channel.set_input(:length_duty, 0) }.not_to raise_error
        expect { channel.set_input(:envelope, 0) }.not_to raise_error
        expect { channel.set_input(:freq_lo, 0) }.not_to raise_error
        expect { channel.set_input(:freq_hi, 0) }.not_to raise_error
        expect { channel.set_input(:frame_seq, 0) }.not_to raise_error
        expect { channel.set_input(:trigger, 0) }.not_to raise_error
      end

      it 'has required output ports' do
        expect { channel.get_output(:output) }.not_to raise_error
        expect { channel.get_output(:enabled) }.not_to raise_error
      end
    end

    describe 'initialization' do
      it 'starts with output at 0 after reset' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        clock_cycle(channel)
        expect(channel.get_output(:output)).to eq(0)
      end

      it 'starts disabled after reset' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        clock_cycle(channel)
        expect(channel.get_output(:enabled)).to eq(0)
      end
    end

    describe 'DAC enable/disable' do
      it 'DAC is disabled when volume=0 and direction=0' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        channel.set_input(:envelope, 0x00)  # Volume=0, direction=0
        channel.set_input(:trigger, 1)
        clock_cycle(channel)
        channel.set_input(:trigger, 0)
        clock_cycle(channel)

        # DAC disabled means channel cannot be enabled
        expect(channel.get_output(:enabled)).to eq(0)
      end
    end

    describe 'output generation' do
      it 'outputs 0 when channel is disabled' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        clock_cycle(channel)
        # Don't trigger, leave disabled
        expect(channel.get_output(:output)).to eq(0)
      end

      it 'output is bounded to 4 bits (0-15)' do
        reset_and_trigger(channel, envelope: 0xF0)
        run_cycles(channel, 50)

        output = channel.get_output(:output)
        expect(output).to be >= 0
        expect(output).to be <= 15
      end
    end
  end

  describe 'ChannelSquare with sweep (channel 1)' do
    let(:channel) { GameBoy::ChannelSquare.new('ch1', has_sweep: true) }

    before do
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:length_duty, 0x80)
      channel.set_input(:envelope, 0xF0)
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    it 'creates channel with sweep capability' do
      expect(channel).to be_a(GameBoy::ChannelSquare)
    end

    it 'accepts sweep_reg input' do
      expect { channel.set_input(:sweep_reg, 0x77) }.not_to raise_error
    end
  end

  describe 'duty cycle input handling' do
    let(:channel) { GameBoy::ChannelSquare.new('ch_duty', has_sweep: false) }

    before do
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:envelope, 0xF0)
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    # Duty cycle patterns:
    # 0: 00000001 (12.5%) - 1 high, 7 low
    # 1: 10000001 (25%)   - 2 high, 6 low
    # 2: 10000111 (50%)   - 4 high, 4 low
    # 3: 01111110 (75%)   - 6 high, 2 low

    it 'accepts 12.5% duty cycle (pattern 0)' do
      expect { channel.set_input(:length_duty, 0x00) }.not_to raise_error
      channel.propagate
    end

    it 'accepts 25% duty cycle (pattern 1)' do
      expect { channel.set_input(:length_duty, 0x40) }.not_to raise_error
      channel.propagate
    end

    it 'accepts 50% duty cycle (pattern 2)' do
      expect { channel.set_input(:length_duty, 0x80) }.not_to raise_error
      channel.propagate
    end

    it 'accepts 75% duty cycle (pattern 3)' do
      expect { channel.set_input(:length_duty, 0xC0) }.not_to raise_error
      channel.propagate
    end
  end

  describe 'envelope input handling' do
    let(:channel) { GameBoy::ChannelSquare.new('ch_env', has_sweep: false) }

    before do
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:length_duty, 0x80)
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    it 'accepts envelope with max volume' do
      expect { channel.set_input(:envelope, 0xF0) }.not_to raise_error
      channel.propagate
    end

    it 'accepts envelope with volume increase direction' do
      expect { channel.set_input(:envelope, 0x08) }.not_to raise_error
      channel.propagate
    end

    it 'accepts envelope with period' do
      expect { channel.set_input(:envelope, 0xF7) }.not_to raise_error
      channel.propagate
    end
  end

  describe 'frequency input handling' do
    let(:channel) { GameBoy::ChannelSquare.new('ch_freq', has_sweep: false) }

    before do
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:length_duty, 0x80)
      channel.set_input(:envelope, 0xF0)
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    it 'accepts low frequency (slowest)' do
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      expect { channel.propagate }.not_to raise_error
    end

    it 'accepts high frequency (fastest)' do
      channel.set_input(:freq_lo, 0xFF)
      channel.set_input(:freq_hi, 0x07)
      expect { channel.propagate }.not_to raise_error
    end

    it 'accepts length enable bit in freq_hi' do
      channel.set_input(:freq_hi, 0x40)  # Length enable
      expect { channel.propagate }.not_to raise_error
    end
  end

  describe 'frame sequencer input handling' do
    let(:channel) { GameBoy::ChannelSquare.new('ch_frame', has_sweep: false) }

    before do
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:sweep_reg, 0x00)
      channel.set_input(:length_duty, 0x80)
      channel.set_input(:envelope, 0xF0)
      channel.set_input(:freq_lo, 0x00)
      channel.set_input(:freq_hi, 0x00)
      channel.set_input(:trigger, 0)
      channel.propagate
    end

    it 'accepts all frame sequencer steps (0-7)' do
      (0..7).each do |step|
        expect { channel.set_input(:frame_seq, step) }.not_to raise_error
        channel.propagate
      end
    end
  end
end
