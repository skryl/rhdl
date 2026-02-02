# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/gameboy'

# Game Boy Timer Unit Tests
# Tests the Timer component (DIV, TIMA, TMA, TAC registers)
#
# The Timer uses the SequentialComponent DSL for IR compilation.
# Tests verify the component structure via IR and test timer behavior through
# the IR runner when available.
#
# Register Addresses:
# - FF04: DIV  - Divider register (increments at 16384 Hz)
# - FF05: TIMA - Timer counter (increments at selected frequency)
# - FF06: TMA  - Timer modulo (reloaded on TIMA overflow)
# - FF07: TAC  - Timer control (enable and frequency select)

RSpec.describe 'GameBoy Timer' do
  describe 'Module Loading' do
    it 'defines the Timer class' do
      expect(defined?(GameBoy::Timer)).to eq('constant')
    end

    it 'inherits from SequentialComponent' do
      expect(GameBoy::Timer.superclass).to eq(RHDL::HDL::SequentialComponent)
    end
  end

  describe 'Timer Component Structure' do
    let(:timer) { GameBoy::Timer.new('timer') }
    let(:ir) { timer.class.to_ir }
    let(:port_names) { ir.ports.map { |p| p.name.to_sym } }

    describe 'Input Ports (via IR)' do
      it 'has reset input' do
        expect(port_names).to include(:reset)
      end

      it 'has clk_sys input' do
        expect(port_names).to include(:clk_sys)
      end

      it 'has ce (clock enable) input' do
        expect(port_names).to include(:ce)
      end

      it 'has cpu_sel input for register selection' do
        expect(port_names).to include(:cpu_sel)
      end

      it 'has cpu_addr input (2-bit for 4 registers)' do
        expect(port_names).to include(:cpu_addr)
      end

      it 'has cpu_wr input for writes' do
        expect(port_names).to include(:cpu_wr)
      end

      it 'has cpu_di input for data in (8-bit)' do
        expect(port_names).to include(:cpu_di)
      end
    end

    describe 'Output Ports (via IR)' do
      it 'has irq output for timer interrupt' do
        expect(port_names).to include(:irq)
      end

      it 'has cpu_do output for data out (8-bit)' do
        expect(port_names).to include(:cpu_do)
      end
    end

    describe 'IR Generation' do
      it 'can generate IR representation' do
        expect(ir).not_to be_nil
        expect(ir.ports.length).to be > 0
      end

      it 'can generate flattened IR' do
        flat_ir = timer.class.to_flat_ir
        expect(flat_ir).not_to be_nil
      end

      it 'has the correct number of ports' do
        # Reset, clk_sys, ce, cpu_sel, cpu_addr, cpu_wr, cpu_di (7 inputs)
        # irq, cpu_do (2 outputs)
        expect(ir.ports.length).to be >= 9
      end
    end
  end

  describe 'Timer Integration Tests' do
    before(:all) do
      begin
        require_relative '../../../../examples/gameboy/utilities/gameboy_ir'
        @ir_available = RHDL::Codegen::IR::COMPILER_AVAILABLE rescue false
        # Try to actually initialize a runner to verify it works
        if @ir_available
          test_runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
          test_runner = nil
        end
      rescue LoadError, NameError, RuntimeError => e
        @ir_available = false
        @ir_error = e.message
      end
    end

    before(:each) do
      skip "IR compiler not available: #{@ir_error}" unless @ir_available
      @runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
    end

    # Helper to create ROM that accesses timer registers
    def create_timer_test_rom(code_bytes, entry: 0x0100)
      rom = Array.new(32 * 1024, 0x00)

      # Nintendo logo
      nintendo_logo = [
        0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
        0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
        0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
        0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
        0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
        0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
      ]
      nintendo_logo.each_with_index { |b, i| rom[0x104 + i] = b }

      "TIMERTEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

      checksum = 0
      (0x134...0x14D).each { |i| checksum = (checksum - rom[i] - 1) & 0xFF }
      rom[0x14D] = checksum

      rom[0x100] = 0xC3
      rom[0x101] = entry & 0xFF
      rom[0x102] = (entry >> 8) & 0xFF

      code_bytes.each_with_index { |b, i| rom[entry + i] = b }

      rom.pack('C*')
    end

    def run_test_code(code_bytes, cycles: 1000, skip_boot: true)
      @runner.load_rom(create_timer_test_rom(code_bytes))
      @runner.reset

      if skip_boot
        while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
          @runner.run_steps(1000)
        end
      end

      @runner.run_steps(cycles)
      @runner.cpu_state
    end

    describe 'DIV Register ($FF04)' do
      it 'DIV can be read' do
        # LDH A, ($04) - read DIV register
        code = [
          0xF0, 0x04,  # LDH A, (FF04)
          0x76         # HALT
        ]
        state = run_test_code(code)
        expect(state[:a]).to be_a(Integer)
      end

      it 'DIV resets when written to' do
        # Write to DIV, then read it back
        code = [
          0x3E, 0xFF,  # LD A, 0xFF
          0xE0, 0x04,  # LDH (FF04), A  - write resets DIV
          0xF0, 0x04,  # LDH A, (FF04)  - read DIV
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 100)
        # DIV should be small after reset
        expect(state[:a]).to be < 50
      end
    end

    describe 'TMA Register ($FF06)' do
      it 'TMA can be written and read' do
        code = [
          0x3E, 0xAB,  # LD A, 0xAB
          0xE0, 0x06,  # LDH (FF06), A  - write TMA
          0xF0, 0x06,  # LDH A, (FF06)  - read TMA
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 100)
        expect(state[:a]).to eq(0xAB)
      end
    end

    describe 'Timer Increment' do
      it 'TIMA increments when timer is enabled' do
        code = [
          0x3E, 0x00,  # LD A, 0
          0xE0, 0x05,  # LDH (FF05), A - TIMA = 0
          0x3E, 0x05,  # LD A, 0x05 (enable, 262144 Hz - fastest)
          0xE0, 0x07,  # LDH (FF07), A - enable timer
          # Wait loop
          0x06, 0x10,  # LD B, 16
          0x00,        # NOP (loop body)
          0x05,        # DEC B
          0x20, 0xFC,  # JR NZ, -4
          # Read TIMA
          0xF0, 0x05,  # LDH A, (FF05)
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 500)
        # TIMA should have incremented from 0
        expect(state[:a]).to be > 0
      end
    end
  end
end
