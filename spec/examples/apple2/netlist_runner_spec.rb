# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/utilities/apple2_netlist'

RSpec.describe RHDL::Apple2::NetlistRunner do
  # These tests verify all 3 backend options for netlist mode
  # Combined with hdl mode, this covers all 6 mode/sim combinations

  describe 'backend initialization' do
    describe 'interpret backend' do
      subject(:runner) { described_class.new(backend: :interpret) }

      it 'initializes with interpreter backend' do
        expect(runner).to be_a(described_class)
      end

      it 'uses native Rust implementation' do
        expect(runner.native?).to be true
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to eq(:netlist_interpret)
      end

      it 'creates the netlist IR' do
        expect(runner.ir).not_to be_nil
        expect(runner.ir.gates.length).to be > 0
      end
    end

    describe 'jit backend' do
      subject(:runner) { described_class.new(backend: :jit) }

      it 'initializes with JIT backend' do
        expect(runner).to be_a(described_class)
      end

      it 'uses native Rust implementation' do
        expect(runner.native?).to be true
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to eq(:netlist_jit)
      end

      it 'creates the netlist IR' do
        expect(runner.ir).not_to be_nil
        expect(runner.ir.gates.length).to be > 0
      end
    end

    describe 'compile backend', :slow do
      # Compile backend takes 60+ seconds to initialize due to rustc compilation
      # of 30K gates, so we skip by default. Run with: rspec --tag slow
      subject(:runner) { described_class.new(backend: :compile, simd: :scalar) }

      it 'initializes with compile backend' do
        expect(runner).to be_a(described_class)
      end

      it 'uses native Rust implementation' do
        expect(runner.native?).to be true
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to eq(:netlist_compile)
      end

      it 'creates the netlist IR' do
        expect(runner.ir).not_to be_nil
        expect(runner.ir.gates.length).to be > 0
      end
    end

    describe 'default backend' do
      subject(:runner) { described_class.new }

      it 'defaults to jit backend' do
        expect(runner.simulator_type).to eq(:netlist_jit)
      end
    end

    describe 'invalid backend' do
      it 'raises error for unknown backend' do
        expect { described_class.new(backend: :invalid) }.to raise_error(ArgumentError, /Unknown backend/)
      end
    end
  end

  describe 'netlist properties' do
    subject(:runner) { described_class.new(backend: :interpret) }

    it 'has Apple II gate count' do
      expect(runner.ir.gates.length).to be > 30_000
    end

    it 'has DFFs for state' do
      expect(runner.ir.dffs.length).to be > 0
    end

    it 'has input signals' do
      expect(runner.ir.inputs).not_to be_empty
    end

    it 'has output signals' do
      expect(runner.ir.outputs).not_to be_empty
    end
  end

  describe 'basic operations' do
    # Use interpret backend for faster test startup
    subject(:runner) { described_class.new(backend: :interpret) }

    describe '#reset' do
      it 'resets without error' do
        expect { runner.reset }.not_to raise_error
      end

      it 'resets cycle counter' do
        runner.run_steps(10)
        runner.reset
        expect(runner.cycle_count).to eq(0)
      end
    end

    describe '#run_steps' do
      it 'runs simulation steps' do
        expect { runner.run_steps(10) }.not_to raise_error
      end

      it 'increments cycle count' do
        initial_cycles = runner.cycle_count
        runner.run_steps(5)
        expect(runner.cycle_count).to eq(initial_cycles + 5)
      end
    end

    describe '#load_rom' do
      it 'loads ROM bytes' do
        rom_data = [0xEA] * 256  # NOP bytes
        expect { runner.load_rom(rom_data, base_addr: 0xD000) }.not_to raise_error
      end
    end

    describe '#load_ram' do
      it 'loads RAM bytes' do
        ram_data = [0x00] * 256
        expect { runner.load_ram(ram_data, base_addr: 0x0800) }.not_to raise_error
      end
    end

    describe '#inject_key' do
      it 'injects keyboard input' do
        expect { runner.inject_key(65) }.not_to raise_error  # 'A'
      end
    end

    describe '#key_ready?' do
      it 'returns keyboard status' do
        runner.inject_key(65)
        expect(runner.key_ready?).to be true
      end
    end

    describe '#clear_key' do
      it 'clears keyboard input' do
        runner.inject_key(65)
        runner.clear_key
        expect(runner.key_ready?).to be false
      end
    end

    describe '#halted?' do
      it 'returns halted status' do
        expect(runner.halted?).to be false
      end
    end

    describe '#cpu_state' do
      it 'returns CPU state hash' do
        state = runner.cpu_state
        expect(state).to be_a(Hash)
        expect(state).to have_key(:cycles)
        expect(state).to have_key(:simulator_type)
      end
    end
  end

  describe 'backend performance characteristics' do
    # Quick smoke test to verify each backend can run
    [:interpret, :jit].each do |backend|
      context "with #{backend} backend" do
        it 'can run 100 cycles' do
          runner = described_class.new(backend: backend)
          runner.reset
          expect { runner.run_steps(100) }.not_to raise_error
          expect(runner.cycle_count).to eq(100)
        end
      end
    end
  end
end
