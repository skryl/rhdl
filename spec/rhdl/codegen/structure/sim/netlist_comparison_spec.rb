# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/codegen'

# This spec validates that all available simulators produce matching results:
# - Without iverilog: expected (behavior), Ruby SimCPU, Native SimCPUNative must match
# - With iverilog: All 4 must match (behavior, Ruby, Native, Verilog)

RSpec.describe 'Netlist Simulator Comparison' do
  describe 'combinational logic' do
    describe 'NOT gate' do
      let(:test_cases) do
        [
          { a: 0 },
          { a: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::NotGate,
          'not_gate',
          test_cases,
          base_dir: 'tmp/netlist_comparison/not_gate',
          has_clock: false
        )
      end
    end

    describe 'AND gate' do
      let(:test_cases) do
        [
          { a0: 0, a1: 0 },
          { a0: 0, a1: 1 },
          { a0: 1, a1: 0 },
          { a0: 1, a1: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::AndGate,
          'and_gate',
          test_cases,
          base_dir: 'tmp/netlist_comparison/and_gate',
          has_clock: false
        )
      end
    end

    describe 'OR gate' do
      let(:test_cases) do
        [
          { a0: 0, a1: 0 },
          { a0: 0, a1: 1 },
          { a0: 1, a1: 0 },
          { a0: 1, a1: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::OrGate,
          'or_gate',
          test_cases,
          base_dir: 'tmp/netlist_comparison/or_gate',
          has_clock: false
        )
      end
    end

    describe 'XOR gate' do
      let(:test_cases) do
        [
          { a0: 0, a1: 0 },
          { a0: 0, a1: 1 },
          { a0: 1, a1: 0 },
          { a0: 1, a1: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::XorGate,
          'xor_gate',
          test_cases,
          base_dir: 'tmp/netlist_comparison/xor_gate',
          has_clock: false
        )
      end
    end

    describe '2-input MUX (1-bit)' do
      # Default Mux2 is 1-bit wide, so use 0/1 values
      let(:test_cases) do
        [
          { a: 0, b: 0, sel: 0 },
          { a: 0, b: 1, sel: 0 },  # select a (0)
          { a: 0, b: 1, sel: 1 },  # select b (1)
          { a: 1, b: 0, sel: 0 },  # select a (1)
          { a: 1, b: 0, sel: 1 },  # select b (0)
          { a: 1, b: 1, sel: 0 },
          { a: 1, b: 1, sel: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::Mux2,
          'mux2',
          test_cases,
          base_dir: 'tmp/netlist_comparison/mux2',
          has_clock: false
        )
      end
    end

    describe 'Full Adder' do
      let(:test_cases) do
        [
          { a: 0, b: 0, cin: 0 },
          { a: 0, b: 1, cin: 0 },
          { a: 1, b: 0, cin: 0 },
          { a: 1, b: 1, cin: 0 },
          { a: 0, b: 0, cin: 1 },
          { a: 1, b: 1, cin: 1 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::FullAdder,
          'full_adder',
          test_cases,
          base_dir: 'tmp/netlist_comparison/full_adder',
          has_clock: false
        )
      end
    end
  end

  describe 'sequential logic' do
    # Note: D Flip-Flop has a qn (inverted) output that requires separate
    # gate evaluation after tick. The Register (which only has q) is a
    # better test for basic sequential logic comparison.

    describe '8-bit Register' do
      let(:test_cases) do
        [
          { d: 0xAB, rst: 0, en: 1 },
          { d: 0x55, rst: 0, en: 1 },
          { d: 0xFF, rst: 0, en: 0 },  # hold
          { d: 0x00, rst: 1, en: 1 }   # reset
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::Register,
          'reg8',
          test_cases,
          base_dir: 'tmp/netlist_comparison/reg8',
          has_clock: true
        )
      end
    end
  end

  describe 'arithmetic' do
    describe 'Ripple Carry Adder (8-bit)' do
      let(:test_cases) do
        [
          { a: 0x00, b: 0x00, cin: 0 },
          { a: 0x01, b: 0x01, cin: 0 },
          { a: 0xFF, b: 0x01, cin: 0 },  # overflow
          { a: 0x0F, b: 0x0F, cin: 1 },
          { a: 0x55, b: 0xAA, cin: 0 }
        ]
      end

      it 'all simulators produce matching results' do
        NetlistHelper.compare_and_validate!(
          RHDL::HDL::RippleCarryAdder,
          'rca8',
          test_cases,
          base_dir: 'tmp/netlist_comparison/rca8',
          has_clock: false
        )
      end
    end
  end

  describe 'comparison summary' do
    it 'shows available simulators and results' do
      comparison = NetlistHelper.compare_behavior_to_netlist(
        RHDL::HDL::NotGate,
        'not_gate',
        [{ a: 0 }, { a: 1 }],
        base_dir: 'tmp/netlist_comparison/summary_test',
        has_clock: false
      )

      summary = NetlistHelper.comparison_summary(comparison)

      expect(summary).to include('Behavior: success=true')
      expect(summary).to include('Ruby SimCPU: success=true')

      if RHDL::Codegen::Structure::NATIVE_SIM_AVAILABLE
        expect(summary).to include('Native SimCPU: success=true')
      end

      if HdlToolchain.iverilog_available?
        expect(summary).to include('Verilog: success=true')
      end
    end
  end

  describe 'validation behavior' do
    context 'with iverilog available', if: HdlToolchain.iverilog_available? do
      it 'validates all 4 simulators match' do
        # Should pass with a simple component
        expect {
          NetlistHelper.compare_and_validate!(
            RHDL::HDL::NotGate,
            'not_gate',
            [{ a: 0 }],
            base_dir: 'tmp/netlist_comparison/validation_test',
            has_clock: false
          )
        }.not_to raise_error
      end
    end

    context 'without iverilog', unless: HdlToolchain.iverilog_available? do
      it 'validates 3 simulators match (behavior, Ruby, Native)' do
        expect {
          NetlistHelper.compare_and_validate!(
            RHDL::HDL::NotGate,
            'not_gate',
            [{ a: 0 }],
            base_dir: 'tmp/netlist_comparison/validation_test_no_iverilog',
            has_clock: false
          )
        }.not_to raise_error
      end
    end
  end
end
