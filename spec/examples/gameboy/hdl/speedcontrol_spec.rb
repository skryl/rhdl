# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/gameboy'

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
    let(:ir) { speed_ctrl.class.to_ir }
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
        flat_ir = speed_ctrl.class.to_flat_ir
        expect(flat_ir).not_to be_nil
      end

      it 'has the correct number of ports' do
        # 6 inputs + 3 outputs = 9 ports
        expect(ir.ports.length).to be >= 9
      end
    end
  end

  def build_speed_ctrl
    ctrl = RHDL::Examples::GameBoy::SpeedControl.new
    {
      clk_sys: 0,
      reset: 0,
      pause: 0,
      speedup: 0,
      cart_act: 0,
      dma_on: 0
    }.each { |k, v| ctrl.set_input(k, v) }
    ctrl.propagate
    ctrl
  end

  def speed_clock(ctrl, cycles: 1)
    cycles.times do
      ctrl.set_input(:clk_sys, 0)
      ctrl.propagate
      ctrl.set_input(:clk_sys, 1)
      ctrl.propagate
    end
  end

  def speed_reset(ctrl)
    ctrl.set_input(:reset, 1)
    speed_clock(ctrl)
    ctrl.set_input(:reset, 0)
    speed_clock(ctrl)
  end

  def wait_for_state(ctrl, target, max_cycles: 256)
    max_cycles.times do
      return true if ctrl.read_reg(:state) == target
      speed_clock(ctrl)
    end
    false
  end

  describe 'SpeedControl Behavior' do
    describe 'Clock Enable Logic' do
      it 'produces phased ce/ce_n pulses in normal mode' do
        ctrl = build_speed_ctrl
        speed_reset(ctrl)

        ce_pulses = 0
        ce_n_pulses = 0
        16.times do
          ctrl.set_input(:clk_sys, 0)
          ctrl.propagate
          ce_pulses += 1 if ctrl.get_output(:ce) == 1
          ce_n_pulses += 1 if ctrl.get_output(:ce_n) == 1
          ctrl.set_input(:clk_sys, 1)
          ctrl.propagate
        end

        expect(ce_pulses).to be > 0
        expect(ce_n_pulses).to be > 0
      end

      it 'does not keep all clock enables tied together' do
        ctrl = build_speed_ctrl
        speed_reset(ctrl)

        differing_cycle_seen = false
        16.times do
          ctrl.set_input(:clk_sys, 0)
          ctrl.propagate
          vals = [ctrl.get_output(:ce), ctrl.get_output(:ce_n), ctrl.get_output(:ce_2x)]
          differing_cycle_seen ||= vals.uniq.length > 1
          ctrl.set_input(:clk_sys, 1)
          ctrl.propagate
        end

        expect(differing_cycle_seen).to eq(true)
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

  describe 'Clock Divider' do
    it 'uses 3-bit divider (0-7) for 8x clock division' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      seen = []
      16.times do
        speed_clock(ctrl)
        seen << ctrl.read_reg(:clkdiv)
      end

      expect(seen.min).to be >= 0
      expect(seen.max).to be <= 7
      expect(seen).to include(0)
      expect(seen).to include(7)
    end

    it 'generates ce at clkdiv=0' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      saw_ce_at_zero = false
      32.times do
        ctrl.set_input(:clk_sys, 0)
        ctrl.propagate
        saw_ce_at_zero ||= (ctrl.get_output(:ce) == 1 && ctrl.read_reg(:clkdiv) == 0)
        ctrl.set_input(:clk_sys, 1)
        ctrl.propagate
      end

      expect(saw_ce_at_zero).to eq(true)
    end

    it 'generates ce_n at clkdiv=4 (180 degrees out of phase)' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      saw_ce_n_at_four = false
      overlap = false
      32.times do
        ctrl.set_input(:clk_sys, 0)
        ctrl.propagate
        saw_ce_n_at_four ||= (ctrl.get_output(:ce_n) == 1 && ctrl.read_reg(:clkdiv) == 4)
        overlap ||= (ctrl.get_output(:ce) == 1 && ctrl.get_output(:ce_n) == 1)
        ctrl.set_input(:clk_sys, 1)
        ctrl.propagate
      end

      expect(saw_ce_n_at_four).to eq(true)
      expect(overlap).to eq(false)
    end
  end

  describe 'State Machine' do
    it 'has 6 states: NORMAL, PAUSED, FASTFORWARDSTART, FASTFORWARD, FASTFORWARDEND, RAMACCESS' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      reached = [ctrl.read_reg(:state)]

      ctrl.set_input(:pause, 1)
      wait_for_state(ctrl, 1)
      reached << ctrl.read_reg(:state)

      ctrl.set_input(:pause, 0)
      wait_for_state(ctrl, 0)
      reached << ctrl.read_reg(:state)

      ctrl.set_input(:speedup, 1)
      wait_for_state(ctrl, 2)
      reached << ctrl.read_reg(:state)
      wait_for_state(ctrl, 3)
      reached << ctrl.read_reg(:state)

      ctrl.set_input(:cart_act, 1)
      speed_clock(ctrl)
      reached << ctrl.read_reg(:state)
      ctrl.set_input(:cart_act, 0)
      wait_for_state(ctrl, 3)

      ctrl.set_input(:speedup, 0)
      wait_for_state(ctrl, 4)
      reached << ctrl.read_reg(:state)
      wait_for_state(ctrl, 0)
      reached << ctrl.read_reg(:state)

      expect(reached.uniq.sort).to include(0, 1, 2, 3, 4, 5)
    end

    it 'transitions to PAUSED state when pause=1' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:pause, 1)
      expect(wait_for_state(ctrl, 1)).to eq(true)
    end

    it 'uses unpause_cnt for gradual pause exit (0-15)' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:pause, 1)
      expect(wait_for_state(ctrl, 1)).to eq(true)
      ctrl.set_input(:pause, 0)
      speed_clock(ctrl, cycles: 4)
      expect(ctrl.read_reg(:unpause_cnt)).to be > 0
      expect(ctrl.read_reg(:unpause_cnt)).to be <= 15
    end

    it 'transitions to FASTFORWARD state when speedup=1' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)
    end

    it 'uses fastforward_cnt for fast-forward timing' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 2)).to eq(true)
      speed_clock(ctrl, cycles: 4)
      expect(ctrl.read_reg(:fastforward_cnt)).to be > 0
      expect(ctrl.read_reg(:fastforward_cnt)).to be <= 15
    end

    it 'transitions to RAMACCESS state during SDRAM operations' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)
      ctrl.set_input(:cart_act, 1)
      speed_clock(ctrl)
      expect(ctrl.read_reg(:state)).to eq(5)
    end
  end

  describe 'RAM Access Handling' do
    it 'tracks SDRAM busy with sdram_busy counter' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)
      ctrl.set_input(:cart_act, 1)
      speed_clock(ctrl)
      expect(ctrl.read_reg(:sdram_busy)).to eq(1)
      speed_clock(ctrl)
      expect(ctrl.read_reg(:sdram_busy)).to eq(0)
    end

    it 'generates refresh signal for SDRAM' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)

      ctrl.set_input(:clk_sys, 0)
      ctrl.propagate
      expect(ctrl.get_output(:refresh)).to eq(1)
    end

    it 'outputs refresh signal' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:pause, 1)
      expect(wait_for_state(ctrl, 1)).to eq(true)

      ctrl.set_input(:clk_sys, 0)
      ctrl.propagate
      expect(ctrl.get_output(:refresh)).to eq(1)
    end
  end

  describe 'Fast-Forward Mode' do
    it 'outputs ff_on signal when in fast-forward mode' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)
      expect(ctrl.get_output(:ff_on)).to eq(1)
    end

    it 'uses FASTFORWARDSTART state for entry delay' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 2)).to eq(true)
    end

    it 'uses FASTFORWARDEND state for exit delay' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)
      ctrl.set_input(:speedup, 1)
      expect(wait_for_state(ctrl, 3)).to eq(true)
      ctrl.set_input(:speedup, 0)
      expect(wait_for_state(ctrl, 4)).to eq(true)
    end
  end

  describe 'ce_2x Behavior' do
    it 'generates ce_2x at specific clkdiv phases for double-speed' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      ce2x_pulses = 0
      16.times do
        ctrl.set_input(:clk_sys, 0)
        ctrl.propagate
        ce2x_pulses += 1 if ctrl.get_output(:ce_2x) == 1
        ctrl.set_input(:clk_sys, 1)
        ctrl.propagate
      end

      expect(ce2x_pulses).to be > 0
    end

    it 'ce_2x has different timing than ce' do
      ctrl = build_speed_ctrl
      speed_reset(ctrl)

      ce_pulses = 0
      ce2x_pulses = 0
      16.times do
        ctrl.set_input(:clk_sys, 0)
        ctrl.propagate
        ce_pulses += 1 if ctrl.get_output(:ce) == 1
        ce2x_pulses += 1 if ctrl.get_output(:ce_2x) == 1
        ctrl.set_input(:clk_sys, 1)
        ctrl.propagate
      end

      expect(ce2x_pulses).to be > ce_pulses
    end
  end

  describe 'Savestate Support' do
    it 'has savestate interface' do
      # Reference speedcontrol has no savestate bus; verify deterministic reset
      # and state restoration through reset sequence.
      ctrl = build_speed_ctrl
      ctrl.write_reg(:state, 3)
      ctrl.write_reg(:ff_on_reg, 1)
      speed_reset(ctrl)
      expect(ctrl.read_reg(:state)).to eq(0)
      expect(ctrl.read_reg(:ff_on_reg)).to eq(0)
    end
  end
end
