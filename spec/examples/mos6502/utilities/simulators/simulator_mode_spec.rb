# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'

require_relative '../../../../../examples/mos6502/utilities/apple2/harness'
require_relative '../../../../../examples/mos6502/utilities/simulators/isa_simulator'

RSpec.describe 'Simulator mode selection', :slow do
  describe 'Apple2Harness::ISARunner' do
    it 'creates a runner that responds to native?' do
      runner = Apple2Harness::ISARunner.new
      expect(runner).to respond_to(:native?)
    end

    it 'returns :native or :ruby for simulator_type' do
      runner = Apple2Harness::ISARunner.new
      expect([:native, :ruby]).to include(runner.simulator_type)
    end

    it 'uses native simulator when available' do
      skip 'Native extension not available' unless MOS6502::NATIVE_AVAILABLE
      runner = Apple2Harness::ISARunner.new
      expect(runner.native?).to be true
      expect(runner.simulator_type).to eq(:native)
    end
  end

  describe 'pure Ruby ISASimulator' do
    let(:bus) { MOS6502::Apple2Bus.new('test_bus') }
    let(:cpu) { MOS6502::ISASimulator.new(bus) }

    it 'is a Ruby class' do
      expect(cpu).to be_a(MOS6502::ISASimulator)
    end

    it 'responds to standard CPU methods' do
      expect(cpu).to respond_to(:pc)
      expect(cpu).to respond_to(:a)
      expect(cpu).to respond_to(:x)
      expect(cpu).to respond_to(:y)
      expect(cpu).to respond_to(:sp)
      expect(cpu).to respond_to(:p)
      expect(cpu).to respond_to(:cycles)
      expect(cpu).to respond_to(:reset)
      expect(cpu).to respond_to(:step)
      expect(cpu).to respond_to(:run_cycles)
    end

    it 'can execute instructions' do
      # Load a simple program: LDA #$42
      bus.load_ram([0xA9, 0x42, 0x00], base_addr: 0x0800)
      bus.write(0xFFFC, 0x00)
      bus.write(0xFFFD, 0x08)
      cpu.reset

      expect(cpu.pc).to eq(0x0800)
      cpu.step
      expect(cpu.a).to eq(0x42)
    end
  end

  describe 'HDL Runner' do
    it 'creates a cycle-accurate runner' do
      runner = Apple2Harness::Runner.new
      expect(runner.simulator_type).to eq(:hdl)
    end

    it 'responds to standard runner methods' do
      runner = Apple2Harness::Runner.new
      expect(runner).to respond_to(:cpu)
      expect(runner).to respond_to(:bus)
      expect(runner).to respond_to(:reset)
      expect(runner).to respond_to(:run_steps)
      expect(runner).to respond_to(:cpu_state)
    end
  end

  describe 'mode parameter behavior' do
    # These tests verify that the correct simulator is instantiated based on mode

    context 'with :native mode' do
      it 'uses ISARunner which prefers native extension' do
        runner = Apple2Harness::ISARunner.new
        # ISARunner automatically uses native if available
        if MOS6502::NATIVE_AVAILABLE
          expect(runner.native?).to be true
        else
          expect(runner.native?).to be false
        end
      end
    end

    context 'with :ruby mode' do
      it 'can create pure Ruby ISASimulator directly' do
        bus = MOS6502::Apple2Bus.new('test_bus')
        cpu = MOS6502::ISASimulator.new(bus)

        # This is the Ruby implementation
        expect(cpu.class.name).to eq('MOS6502::ISASimulator')
        expect(cpu).not_to respond_to(:native?)
      end
    end

    context 'with :hdl mode' do
      it 'creates cycle-accurate HDL runner' do
        runner = Apple2Harness::Runner.new
        expect(runner.simulator_type).to eq(:hdl)
      end
    end
  end

  describe 'simulator compatibility' do
    # Test that all simulators can run the same program

    let(:test_program) do
      # LDA #$00, STA $00, LDA #$04, STA $01, LDY #$00, LDA #$C1, STA ($00),Y, BRK
      [
        0xA9, 0x00,        # LDA #$00
        0x85, 0x00,        # STA $00
        0xA9, 0x04,        # LDA #$04
        0x85, 0x01,        # STA $01
        0xA0, 0x00,        # LDY #$00
        0xA9, 0xC1,        # LDA #$C1 ('A' with high bit)
        0x91, 0x00,        # STA ($00),Y
        0x00               # BRK
      ]
    end

    it 'ISARunner produces correct result' do
      runner = Apple2Harness::ISARunner.new
      runner.load_ram(test_program, base_addr: 0x0800)

      # For native mode, write reset vector to CPU memory
      if runner.native?
        runner.cpu.poke(0xFFFC, 0x00)
        runner.cpu.poke(0xFFFD, 0x08)
      else
        runner.bus.write(0xFFFC, 0x00)
        runner.bus.write(0xFFFD, 0x08)
      end

      runner.reset
      runner.run_steps(100)

      # Check that 'A' was written to text page
      # For native mode, read from CPU memory
      if runner.native?
        expect(runner.cpu.peek(0x0400)).to eq(0xC1)
      else
        expect(runner.bus.read(0x0400)).to eq(0xC1)
      end
    end

    it 'Ruby ISASimulator produces correct result' do
      bus = MOS6502::Apple2Bus.new('test_bus')
      cpu = MOS6502::ISASimulator.new(bus)
      bus.load_ram(test_program, base_addr: 0x0800)
      bus.write(0xFFFC, 0x00)
      bus.write(0xFFFD, 0x08)
      cpu.reset
      cpu.run_cycles(100)

      # Check that 'A' was written to text page
      expect(bus.read(0x0400)).to eq(0xC1)
    end

    it 'HDL Runner produces correct result' do
      runner = Apple2Harness::Runner.new
      runner.load_ram(test_program, base_addr: 0x0800)
      runner.bus.write(0xFFFC, 0x00)
      runner.bus.write(0xFFFD, 0x08)
      runner.reset
      runner.run_steps(500)  # HDL needs more cycles

      # Check that 'A' was written to text page
      expect(runner.bus.read(0x0400)).to eq(0xC1)
    end
  end
end
