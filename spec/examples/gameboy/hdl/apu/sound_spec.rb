# frozen_string_literal: true

require 'spec_helper'

# Game Boy APU (Audio Processing Unit) Tests
# Tests the main Sound component that combines all 4 channels
#
# Features tested:
# - Component structure and ports
# - Register addressing
# - Audio output generation
# - CPU interface

RSpec.describe 'GameBoy::Sound' do
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

  describe 'Sound (APU)' do
    let(:apu) { GameBoy::Sound.new('apu') }

    before do
      # Initialize default inputs
      apu.set_input(:ce, 1)
      apu.set_input(:reset, 0)
      apu.set_input(:is_gbc, 0)
      apu.set_input(:remove_pops, 0)
      apu.set_input(:s1_read, 0)
      apu.set_input(:s1_write, 0)
      apu.set_input(:s1_addr, 0)
      apu.set_input(:s1_writedata, 0)
      apu.propagate
    end

    describe 'component structure' do
      it 'is a SequentialComponent' do
        expect(apu).to be_a(RHDL::HDL::SequentialComponent)
      end

      it 'has required input ports' do
        expect { apu.set_input(:clk, 0) }.not_to raise_error
        expect { apu.set_input(:ce, 0) }.not_to raise_error
        expect { apu.set_input(:reset, 0) }.not_to raise_error
        expect { apu.set_input(:is_gbc, 0) }.not_to raise_error
        expect { apu.set_input(:remove_pops, 0) }.not_to raise_error
        expect { apu.set_input(:s1_read, 0) }.not_to raise_error
        expect { apu.set_input(:s1_write, 0) }.not_to raise_error
        expect { apu.set_input(:s1_addr, 0) }.not_to raise_error
        expect { apu.set_input(:s1_writedata, 0) }.not_to raise_error
      end

      it 'has required output ports' do
        expect { apu.get_output(:s1_readdata) }.not_to raise_error
        expect { apu.get_output(:snd_left) }.not_to raise_error
        expect { apu.get_output(:snd_right) }.not_to raise_error
      end
    end

    describe 'initialization' do
      it 'has audio outputs after reset' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        # Audio outputs should exist and be integers
        expect(apu.get_output(:snd_left)).to be_a(Integer)
        expect(apu.get_output(:snd_right)).to be_a(Integer)
      end

      it 's1_readdata is an integer' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        expect(apu.get_output(:s1_readdata)).to be_a(Integer)
      end
    end

    describe 'CPU interface addressing' do
      # Audio registers map: address offset from FF10
      # 0x00: NR10 (Channel 1 Sweep)
      # 0x01: NR11 (Channel 1 Length/Duty)
      # 0x02: NR12 (Channel 1 Envelope)
      # 0x03: NR13 (Channel 1 Frequency Low) - Write only
      # 0x04: NR14 (Channel 1 Frequency High/Control)
      # 0x06: NR21 (Channel 2 Length/Duty)
      # 0x07: NR22 (Channel 2 Envelope)
      # 0x08: NR23 (Channel 2 Frequency Low) - Write only
      # 0x09: NR24 (Channel 2 Frequency High/Control)
      # 0x0A: NR30 (Channel 3 DAC Enable)
      # 0x0B: NR31 (Channel 3 Length) - Write only
      # 0x0C: NR32 (Channel 3 Volume)
      # 0x0D: NR33 (Channel 3 Frequency Low) - Write only
      # 0x0E: NR34 (Channel 3 Frequency High/Control)
      # 0x10: NR41 (Channel 4 Length) - Write only
      # 0x11: NR42 (Channel 4 Envelope)
      # 0x12: NR43 (Channel 4 Polynomial)
      # 0x13: NR44 (Channel 4 Control)
      # 0x14: NR50 (Master Volume)
      # 0x15: NR51 (Channel Panning)
      # 0x16: NR52 (Sound On/Off)

      it 'accepts address input for all register addresses' do
        # Test all valid register addresses (0x00-0x16)
        (0x00..0x16).each do |addr|
          expect { apu.set_input(:s1_addr, addr) }.not_to raise_error
          apu.propagate
        end
      end

      it 'accepts write data input' do
        (0..255).step(0x55) do |value|
          expect { apu.set_input(:s1_writedata, value) }.not_to raise_error
          apu.propagate
        end
      end

      it 'accepts read control input' do
        expect { apu.set_input(:s1_read, 0) }.not_to raise_error
        expect { apu.set_input(:s1_read, 1) }.not_to raise_error
        apu.propagate
      end

      it 'accepts write control input' do
        expect { apu.set_input(:s1_write, 0) }.not_to raise_error
        expect { apu.set_input(:s1_write, 1) }.not_to raise_error
        apu.propagate
      end
    end

    describe 'audio output' do
      it 'outputs 16-bit stereo audio' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        left = apu.get_output(:snd_left)
        right = apu.get_output(:snd_right)

        # Outputs should be 16-bit values
        expect(left).to be >= 0
        expect(left).to be < 65536

        expect(right).to be >= 0
        expect(right).to be < 65536
      end

      it 'audio outputs are integers' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        run_cycles(apu, 10)

        expect(apu.get_output(:snd_left)).to be_a(Integer)
        expect(apu.get_output(:snd_right)).to be_a(Integer)
      end
    end

    describe 'configuration inputs' do
      it 'accepts is_gbc input (Game Boy Color mode)' do
        expect { apu.set_input(:is_gbc, 0) }.not_to raise_error
        expect { apu.set_input(:is_gbc, 1) }.not_to raise_error
        apu.propagate
      end

      it 'accepts remove_pops input (anti-pop filter)' do
        expect { apu.set_input(:remove_pops, 0) }.not_to raise_error
        expect { apu.set_input(:remove_pops, 1) }.not_to raise_error
        apu.propagate
      end
    end

    describe 'clock and reset' do
      it 'accepts clock input' do
        expect { apu.set_input(:clk, 0) }.not_to raise_error
        expect { apu.set_input(:clk, 1) }.not_to raise_error
        apu.propagate
      end

      it 'accepts clock enable input' do
        expect { apu.set_input(:ce, 0) }.not_to raise_error
        expect { apu.set_input(:ce, 1) }.not_to raise_error
        apu.propagate
      end

      it 'accepts reset input' do
        expect { apu.set_input(:reset, 0) }.not_to raise_error
        expect { apu.set_input(:reset, 1) }.not_to raise_error
        apu.propagate
      end
    end

    describe 's1_readdata output' do
      it 'returns integer value' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        apu.set_input(:s1_addr, 0x16)  # NR52
        apu.set_input(:s1_read, 1)
        apu.propagate

        expect(apu.get_output(:s1_readdata)).to be_a(Integer)
      end

      it 'readdata is bounded to 8 bits (0-255)' do
        apu.set_input(:reset, 1)
        clock_cycle(apu)
        apu.set_input(:reset, 0)
        clock_cycle(apu)

        apu.set_input(:s1_read, 1)
        apu.propagate

        readdata = apu.get_output(:s1_readdata)
        expect(readdata).to be >= 0
        expect(readdata).to be <= 255
      end
    end
  end
end
