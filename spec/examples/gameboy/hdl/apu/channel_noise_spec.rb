# frozen_string_literal: true

require 'spec_helper'

# Game Boy Noise Channel Tests (Channel 4)
# Tests the ChannelNoise component
#
# Features tested:
# - Component structure and ports
# - LFSR width modes (7-bit vs 15-bit)
# - Divisor selection
# - Clock shift settings
# - DAC enable/disable
# - Output generation

RSpec.describe 'RHDL::Examples::GameBoy::ChannelNoise' do
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

  describe 'ChannelNoise' do
    let(:channel) { RHDL::Examples::GameBoy::ChannelNoise.new('ch4') }

    before do
      # Initialize default inputs
      channel.set_input(:ce, 1)
      channel.set_input(:reset, 0)
      channel.set_input(:length_reg, 0x00)    # NR41 - Full length
      channel.set_input(:envelope, 0xF0)      # NR42 - Max volume, no sweep
      channel.set_input(:poly_reg, 0x00)      # NR43 - LFSR parameters
      channel.set_input(:control, 0x00)       # NR44 - Control
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
        expect { channel.set_input(:length_reg, 0) }.not_to raise_error
        expect { channel.set_input(:envelope, 0) }.not_to raise_error
        expect { channel.set_input(:poly_reg, 0) }.not_to raise_error
        expect { channel.set_input(:control, 0) }.not_to raise_error
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

        expect(channel.get_output(:enabled)).to eq(0)
      end
    end

    describe 'LFSR width mode input handling' do
      # Bit 3 of NR43 controls LFSR width:
      # 0 = 15-bit LFSR
      # 1 = 7-bit LFSR (more metallic sound)

      it 'accepts 15-bit LFSR mode (width mode = 0)' do
        expect { channel.set_input(:poly_reg, 0x00) }.not_to raise_error
        channel.propagate
      end

      it 'accepts 7-bit LFSR mode (width mode = 1)' do
        expect { channel.set_input(:poly_reg, 0x08) }.not_to raise_error
        channel.propagate
      end
    end

    describe 'divisor selection input handling' do
      # NR43 bits 2-0 select divisor:
      # 0: 8, 1: 16, 2: 32, 3: 48, 4: 64, 5: 80, 6: 96, 7: 112

      it 'accepts all divisor codes (0-7)' do
        (0..7).each do |divisor_code|
          expect { channel.set_input(:poly_reg, divisor_code) }.not_to raise_error
          channel.propagate
        end
      end
    end

    describe 'clock shift input handling' do
      # NR43 bits 7-4 control clock shift (0-15)

      it 'accepts all clock shift values (0-15)' do
        (0..15).each do |shift|
          value = shift << 4
          expect { channel.set_input(:poly_reg, value) }.not_to raise_error
          channel.propagate
        end
      end
    end

    describe 'envelope input handling' do
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

    describe 'control input handling' do
      it 'accepts length enable bit' do
        expect { channel.set_input(:control, 0x40) }.not_to raise_error
        channel.propagate
      end

      it 'accepts trigger bit' do
        expect { channel.set_input(:control, 0x80) }.not_to raise_error
        channel.propagate
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

    describe 'output generation' do
      it 'outputs 0 when channel is disabled' do
        channel.set_input(:reset, 1)
        clock_cycle(channel)
        channel.set_input(:reset, 0)
        channel.set_input(:envelope, 0x00)  # DAC disabled
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

    describe 'length register input handling' do
      it 'accepts length values (6 bits used)' do
        (0..63).each do |length|
          expect { channel.set_input(:length_reg, length) }.not_to raise_error
          channel.propagate
        end
      end
    end
  end
end
