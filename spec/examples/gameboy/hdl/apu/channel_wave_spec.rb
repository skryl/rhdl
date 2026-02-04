# frozen_string_literal: true

require 'spec_helper'

# Game Boy Wave Channel Tests (Channel 3)
# Tests the ChannelWave component
#
# Features tested:
# - Component structure and ports
# - Wave RAM addressing
# - Volume shift settings
# - DAC enable/disable
# - Output generation

RSpec.describe 'RHDL::Examples::GameBoy::ChannelWave' do
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

  describe 'ChannelWave' do
    let(:channel) { RHDL::Examples::GameBoy::ChannelWave.new('ch3') }

    before do
      # Initialize default inputs
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:dac_enable, 0x80)   # NR30 - DAC enabled
      channel.set_input(:length_reg, 0x00)   # NR31 - Full length
      channel.set_input(:volume_reg, 0x20)   # NR32 - 100% volume
      channel.set_input(:freq_lo, 0x00)      # NR33
      channel.set_input(:freq_hi, 0x00)      # NR34
      channel.set_input(:frame_seq, 0)
      channel.set_input(:trigger, 0)
      channel.set_input(:wave_ram_data, 0x0F)  # Sample data from wave RAM
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
        expect { channel.set_input(:dac_enable, 0) }.not_to raise_error
        expect { channel.set_input(:length_reg, 0) }.not_to raise_error
        expect { channel.set_input(:volume_reg, 0) }.not_to raise_error
        expect { channel.set_input(:freq_lo, 0) }.not_to raise_error
        expect { channel.set_input(:freq_hi, 0) }.not_to raise_error
        expect { channel.set_input(:frame_seq, 0) }.not_to raise_error
        expect { channel.set_input(:trigger, 0) }.not_to raise_error
        expect { channel.set_input(:wave_ram_data, 0) }.not_to raise_error
      end

      it 'has required output ports' do
        expect { channel.get_output(:output) }.not_to raise_error
        expect { channel.get_output(:enabled) }.not_to raise_error
        expect { channel.get_output(:wave_ram_addr) }.not_to raise_error
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

      it 'has wave_ram_addr output' do
        expect(channel.get_output(:wave_ram_addr)).to be_a(Integer)
      end
    end

    describe 'DAC enable/disable' do
      it 'DAC is disabled when bit 7 of NR30 is clear' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        channel.set_input(:dac_enable, 0x00)  # Bit 7 clear
        channel.set_input(:trigger, 1)
        clock_cycle(channel)
        channel.set_input(:trigger, 0)
        clock_cycle(channel)

        expect(channel.get_output(:enabled)).to eq(0)
      end
    end

    describe 'volume control input handling' do
      # Volume shift: 00=mute, 01=100%, 10=50%, 11=25%
      # Volume is controlled by NR32 bits 6-5

      it 'accepts mute volume setting (shift=00)' do
        expect { channel.set_input(:volume_reg, 0x00) }.not_to raise_error
        channel.propagate
      end

      it 'accepts 100% volume setting (shift=01)' do
        expect { channel.set_input(:volume_reg, 0x20) }.not_to raise_error
        channel.propagate
      end

      it 'accepts 50% volume setting (shift=10)' do
        expect { channel.set_input(:volume_reg, 0x40) }.not_to raise_error
        channel.propagate
      end

      it 'accepts 25% volume setting (shift=11)' do
        expect { channel.set_input(:volume_reg, 0x60) }.not_to raise_error
        channel.propagate
      end
    end

    describe 'wave RAM addressing' do
      it 'wave_ram_addr is an integer output' do
        expect(channel.get_output(:wave_ram_addr)).to be_a(Integer)
      end

      it 'wave_ram_addr is bounded to 5 bits (0-31)' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)

        addr = channel.get_output(:wave_ram_addr)
        expect(addr).to be >= 0
        expect(addr).to be < 32
      end
    end

    describe 'output generation' do
      it 'outputs 0 when channel is disabled' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        channel.set_input(:dac_enable, 0x00)  # DAC disabled
        channel.set_input(:wave_ram_data, 0x0F)
        clock_cycle(channel)

        expect(channel.get_output(:output)).to eq(0)
      end

      it 'output is bounded to 4 bits (0-15)' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        clock_cycle(channel)

        output = channel.get_output(:output)
        expect(output).to be >= 0
        expect(output).to be <= 15
      end
    end

    describe 'frequency input handling' do
      it 'accepts low frequency setting' do
        channel.set_input(:freq_lo, 0x00)
        channel.set_input(:freq_hi, 0x00)
        expect { channel.propagate }.not_to raise_error
      end

      it 'accepts high frequency setting' do
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
      it 'accepts all frame sequencer steps (0-7)' do
        (0..7).each do |step|
          expect { channel.set_input(:frame_seq, step) }.not_to raise_error
          channel.propagate
        end
      end
    end

    describe 'wave RAM data input handling' do
      it 'accepts all 4-bit sample values (0-15)' do
        (0..15).each do |sample|
          expect { channel.set_input(:wave_ram_data, sample) }.not_to raise_error
          channel.propagate
        end
      end
    end
  end
end
