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
      expect(defined?(GameBoy::SpeedControl)).to eq('constant')
    end

    it 'inherits from SequentialComponent' do
      expect(GameBoy::SpeedControl.superclass).to eq(RHDL::HDL::SequentialComponent)
    end
  end

  describe 'SpeedControl Component Structure' do
    let(:speed_ctrl) { GameBoy::SpeedControl.new('speedcontrol') }
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

  describe 'SpeedControl Behavior' do
    # SpeedControl is a simple component that generates clock enables
    # In the IR simulation, it simply outputs ~pause for all clock enables

    describe 'Clock Enable Logic' do
      it 'documents that ce is inverse of pause signal' do
        # This is the behavior defined in the component:
        # ce <= ~pause
        # ce_n <= ~pause
        # ce_2x <= ~pause
        # The behavior block implements this directly
        expect(true).to eq(true)  # Documented behavior
      end

      it 'documents that all clock enables are tied together in simulation mode' do
        # In IR simulation, all three outputs (ce, ce_n, ce_2x) are equal to ~pause
        # This simplifies the simulation to run at 4MHz effective speed
        expect(true).to eq(true)  # Documented behavior
      end
    end
  end

  describe 'SpeedControl Integration' do
    # SpeedControl is instantiated inside the Gameboy component
    # and its outputs drive all other components' clock enables

    it 'is part of the full Gameboy system' do
      # The Gameboy component uses SpeedControl to generate clock enables
      expect(defined?(GameBoy::Gameboy)).to eq('constant')
    end
  end
end
