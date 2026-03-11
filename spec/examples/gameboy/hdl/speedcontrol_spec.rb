# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/hdl/gameboy'
require_relative '../../../../examples/gameboy/utilities/clock_enable_waveform'

# Game Boy Speed Control Unit Tests
# Tests the SpeedControl component for clock enable generation
#
# The SpeedControl uses the SequentialComponent DSL for IR compilation.
# Tests verify the component structure via IR.
#
# The SpeedControl component generates clock enable signals from clk_sys:
# - ce:    4MHz clock enable
# - ce_n:  4MHz inverted clock enable (180 degrees out of phase)
# - ce_2x: 8MHz clock enable for GBC double speed mode
#
# In IR simulation, ce is always ~pause (no clock division).

RSpec.describe 'GameBoy SpeedControl' do
  def clock_cycle(component)
    component.set_input(:clk_sys, 0)
    component.propagate
    component.set_input(:clk_sys, 1)
    component.propagate
  end

  describe 'Module Loading' do
    it 'defines the SpeedControl class' do
      expect(defined?(RHDL::Examples::GameBoy::SpeedControl)).to eq('constant')
    end

    it 'inherits from SequentialComponent' do
      expect(RHDL::Examples::GameBoy::SpeedControl.superclass).to eq(RHDL::HDL::SequentialComponent)
    end
  end

  describe 'SpeedControl Component Structure' do
    let(:speed_ctrl) { RHDL::Examples::GameBoy::SpeedControl.new('speedcontrol') }
    let(:ir) { speed_ctrl.class.to_flat_circt_nodes }
    let(:port_names) { ir.ports.map { |p| p.name.to_sym } }

    describe 'Input Ports (via IR)' do
      it 'has clk_sys input' do
        expect(port_names).to include(:clk_sys)
      end

      it 'has reset input' do
        expect(port_names).to include(:reset)
      end

      it 'has pause input' do
        expect(port_names).to include(:pause)
      end

      it 'has speedup input' do
        expect(port_names).to include(:speedup)
      end

      it 'has cart_act input (cartridge activity)' do
        expect(port_names).to include(:cart_act)
      end

      it 'has dma_on input' do
        expect(port_names).to include(:dma_on)
      end
    end

    describe 'Output Ports (via IR)' do
      it 'has ce output (4MHz clock enable)' do
        expect(port_names).to include(:ce)
      end

      it 'has ce_n output (inverted clock enable)' do
        expect(port_names).to include(:ce_n)
      end

      it 'has ce_2x output (8MHz for GBC double speed)' do
        expect(port_names).to include(:ce_2x)
      end
    end

    describe 'IR Generation' do
      it 'can generate IR representation' do
        expect(ir).not_to be_nil
        expect(ir.ports.length).to be > 0
      end

      it 'can generate flattened IR' do
        flat_ir = speed_ctrl.class.to_flat_circt_nodes
        expect(flat_ir).not_to be_nil
      end

      it 'has the correct number of ports' do
        # 6 inputs + 3 outputs = 9 ports
        expect(ir.ports.length).to be >= 9
      end
    end
  end

  describe 'SpeedControl Behavior' do
    let(:speed_ctrl) { RHDL::Examples::GameBoy::SpeedControl.new }

    before do
      speed_ctrl.set_input(:reset, 0)
      speed_ctrl.set_input(:clk_sys, 0)
      speed_ctrl.set_input(:pause, 0)
      speed_ctrl.set_input(:speedup, 0)
      speed_ctrl.set_input(:cart_act, 0)
      speed_ctrl.set_input(:dma_on, 0)
      speed_ctrl.propagate
    end

    describe 'Clock Enable Logic' do
      it 'starts on the reference phase-0 waveform after reset' do
        speed_ctrl.set_input(:reset, 1)
        clock_cycle(speed_ctrl)
        speed_ctrl.set_input(:reset, 0)
        speed_ctrl.propagate

        expect(speed_ctrl.get_output(:ce)).to eq(1)
        expect(speed_ctrl.get_output(:ce_n)).to eq(0)
        expect(speed_ctrl.get_output(:ce_2x)).to eq(1)
      end

      it 'matches the shared 8-phase clock-enable waveform' do
        speed_ctrl.set_input(:reset, 1)
        clock_cycle(speed_ctrl)
        speed_ctrl.set_input(:reset, 0)
        speed_ctrl.propagate

        sequence = []
        8.times do
          sequence << {
            ce: speed_ctrl.get_output(:ce),
            ce_n: speed_ctrl.get_output(:ce_n),
            ce_2x: speed_ctrl.get_output(:ce_2x)
          }
          clock_cycle(speed_ctrl)
        end

        expect(sequence).to eq(
          8.times.map { |phase| RHDL::Examples::GameBoy::ClockEnableWaveform.values_for_phase(phase) }
        )
      end

      it 'suppresses all clock enables while paused' do
        speed_ctrl.set_input(:pause, 1)
        speed_ctrl.propagate

        expect(speed_ctrl.get_output(:ce)).to eq(0)
        expect(speed_ctrl.get_output(:ce_n)).to eq(0)
        expect(speed_ctrl.get_output(:ce_2x)).to eq(0)
      end
    end
  end

  describe 'SpeedControl Integration' do
    # SpeedControl is instantiated inside the Gameboy component
    # and its outputs drive all other components' clock enables

    it 'is part of the full Gameboy system' do
      # The Gameboy component uses SpeedControl to generate clock enables
      expect(defined?(RHDL::Examples::GameBoy::Gameboy)).to eq('constant')
    end
  end

  # ============================================================================
  # Missing functionality tests (from reference comparison)
  # These tests verify features that should be implemented to match the
  # MiSTer reference implementation (reference/rtl/speedcontrol.vhd)
  # ============================================================================

  describe 'Clock Divider' do
    it 'uses 3-bit divider (0-7) for 8x clock division' do
      # Reference: Proper clkdiv counter creates 8x division from system clock
      pending 'Clock divider implementation'
      fail
    end

    it 'generates ce at clkdiv=0' do
      speed_ctrl = RHDL::Examples::GameBoy::SpeedControl.new
      speed_ctrl.set_input(:reset, 1)
      clock_cycle(speed_ctrl)
      speed_ctrl.set_input(:reset, 0)
      speed_ctrl.set_input(:pause, 0)
      speed_ctrl.set_input(:speedup, 0)
      speed_ctrl.set_input(:cart_act, 0)
      speed_ctrl.set_input(:dma_on, 0)
      speed_ctrl.propagate

      expect(speed_ctrl.get_output(:ce)).to eq(1)
    end

    it 'generates ce_n at clkdiv=4 (180 degrees out of phase)' do
      speed_ctrl = RHDL::Examples::GameBoy::SpeedControl.new
      speed_ctrl.set_input(:reset, 1)
      clock_cycle(speed_ctrl)
      speed_ctrl.set_input(:reset, 0)
      speed_ctrl.set_input(:pause, 0)
      speed_ctrl.set_input(:speedup, 0)
      speed_ctrl.set_input(:cart_act, 0)
      speed_ctrl.set_input(:dma_on, 0)
      speed_ctrl.propagate

      4.times { clock_cycle(speed_ctrl) }

      expect(speed_ctrl.get_output(:ce)).to eq(0)
      expect(speed_ctrl.get_output(:ce_n)).to eq(1)
    end
  end

  describe 'State Machine' do
    it 'has 6 states: NORMAL, PAUSED, FASTFORWARDSTART, FASTFORWARD, FASTFORWARDEND, RAMACCESS' do
      # Reference: Full FSM with 6 states for different operating modes
      pending 'Complete 6-state FSM implementation'
      fail
    end

    it 'transitions to PAUSED state when pause=1' do
      # Reference: Pause transitions to PAUSED state
      pending 'Pause state transition'
      fail
    end

    it 'uses unpause_cnt for gradual pause exit (0-15)' do
      # Reference: unpause_cnt counter for debouncing/gradual exit
      pending 'Unpause counter implementation'
      fail
    end

    it 'transitions to FASTFORWARD state when speedup=1' do
      # Reference: Fast-forward mode with entry/exit delays
      pending 'Fast-forward state transition'
      fail
    end

    it 'uses fastforward_cnt for fast-forward timing' do
      # Reference: fastforward_cnt counter for mode delays
      pending 'Fast-forward counter implementation'
      fail
    end

    it 'transitions to RAMACCESS state during SDRAM operations' do
      # Reference: RAMACCESS state with sdram_busy counter
      pending 'RAM access state implementation'
      fail
    end
  end

  describe 'RAM Access Handling' do
    it 'tracks SDRAM busy with sdram_busy counter' do
      # Reference: sdram_busy counter for memory access timing
      pending 'SDRAM busy counter'
      fail
    end

    it 'generates refresh signal for SDRAM' do
      # Reference: refreshcnt for SDRAM refresh timing
      pending 'SDRAM refresh signal generation'
      fail
    end

    it 'outputs refresh signal' do
      # Reference: refresh output for SDRAM controller
      pending 'Refresh output signal'
      fail
    end
  end

  describe 'Fast-Forward Mode' do
    it 'outputs ff_on signal when in fast-forward mode' do
      # Reference: ff_on output indicates fast-forward active
      pending 'ff_on output signal'
      fail
    end

    it 'uses FASTFORWARDSTART state for entry delay' do
      # Reference: Entry delay before full fast-forward
      pending 'Fast-forward start delay'
      fail
    end

    it 'uses FASTFORWARDEND state for exit delay' do
      # Reference: Exit delay before returning to normal
      pending 'Fast-forward end delay'
      fail
    end
  end

  describe 'ce_2x Behavior' do
    it 'generates ce_2x at specific clkdiv phases for double-speed' do
      speed_ctrl = RHDL::Examples::GameBoy::SpeedControl.new
      speed_ctrl.set_input(:reset, 1)
      clock_cycle(speed_ctrl)
      speed_ctrl.set_input(:reset, 0)
      speed_ctrl.set_input(:pause, 0)
      speed_ctrl.set_input(:speedup, 0)
      speed_ctrl.set_input(:cart_act, 0)
      speed_ctrl.set_input(:dma_on, 0)
      speed_ctrl.propagate

      phases = []
      8.times do
        phases << speed_ctrl.get_output(:ce_2x)
        clock_cycle(speed_ctrl)
      end

      expect(phases).to eq([1, 0, 0, 0, 1, 0, 0, 0])
    end

    it 'ce_2x has different timing than ce' do
      speed_ctrl = RHDL::Examples::GameBoy::SpeedControl.new
      speed_ctrl.set_input(:reset, 1)
      clock_cycle(speed_ctrl)
      speed_ctrl.set_input(:reset, 0)
      speed_ctrl.set_input(:pause, 0)
      speed_ctrl.set_input(:speedup, 0)
      speed_ctrl.set_input(:cart_act, 0)
      speed_ctrl.set_input(:dma_on, 0)
      speed_ctrl.propagate

      values = []
      8.times do
        values << [speed_ctrl.get_output(:ce), speed_ctrl.get_output(:ce_n), speed_ctrl.get_output(:ce_2x)]
        clock_cycle(speed_ctrl)
      end

      expect(values.uniq).to include([0, 1, 1])
    end
  end

  describe 'Savestate Support' do
    it 'has savestate interface' do
      # Reference: SaveState bus signals for MiSTer
      pending 'Savestate interface'
      fail
    end
  end
end
