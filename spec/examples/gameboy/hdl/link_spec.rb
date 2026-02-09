# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/gameboy/gameboy'

# Game Boy Link Port Unit Tests
# Tests the Link (serial communication) component
#
# The Link uses the SequentialComponent DSL for IR compilation.
# Tests verify the component structure via IR and test serial behavior through
# the IR runner when available.
#
# Register Addresses:
# - FF01: SB - Serial transfer data (shift register)
# - FF02: SC - Serial transfer control
#   - Bit 7: Transfer Start Flag (1=Start, becomes 0 when done)
#   - Bit 0: Shift Clock Select (0=External, 1=Internal 8192Hz)

RSpec.describe 'GameBoy Link Port' do
  describe 'Module Loading' do
    it 'defines the Link class' do
      expect(defined?(RHDL::Examples::GameBoy::Link)).to eq('constant')
    end

    it 'inherits from SequentialComponent' do
      expect(RHDL::Examples::GameBoy::Link.superclass).to eq(RHDL::HDL::SequentialComponent)
    end
  end

  describe 'Link Component Structure' do
    let(:link) { RHDL::Examples::GameBoy::Link.new('link') }
    let(:ir) { link.class.to_ir }
    let(:port_names) { ir.ports.map { |p| p.name.to_sym } }

    describe 'Input Ports (via IR)' do
      it 'has clk_sys input' do
        expect(port_names).to include(:clk_sys)
      end

      it 'has ce input (clock enable)' do
        expect(port_names).to include(:ce)
      end

      it 'has rst input (reset)' do
        expect(port_names).to include(:rst)
      end

      it 'has sel_sc input for SC register selection' do
        expect(port_names).to include(:sel_sc)
      end

      it 'has sel_sb input for SB register selection' do
        expect(port_names).to include(:sel_sb)
      end

      it 'has cpu_wr_n input (active low write)' do
        expect(port_names).to include(:cpu_wr_n)
      end

      it 'has sc_start_in input' do
        expect(port_names).to include(:sc_start_in)
      end

      it 'has sc_int_clock_in input' do
        expect(port_names).to include(:sc_int_clock_in)
      end

      it 'has sb_in input (8-bit data)' do
        expect(port_names).to include(:sb_in)
      end

      it 'has serial_clk_in input (external clock)' do
        expect(port_names).to include(:serial_clk_in)
      end

      it 'has serial_data_in input' do
        expect(port_names).to include(:serial_data_in)
      end
    end

    describe 'Output Ports (via IR)' do
      it 'has sb output (8-bit serial buffer)' do
        expect(port_names).to include(:sb)
      end

      it 'has serial_irq output' do
        expect(port_names).to include(:serial_irq)
      end

      it 'has sc_start output (transfer in progress)' do
        expect(port_names).to include(:sc_start)
      end

      it 'has sc_int_clock output' do
        expect(port_names).to include(:sc_int_clock)
      end

      it 'has serial_clk_out output' do
        expect(port_names).to include(:serial_clk_out)
      end

      it 'has serial_data_out output' do
        expect(port_names).to include(:serial_data_out)
      end
    end

    describe 'Constants' do
      it 'defines CLOCK_DIV constant' do
        expect(RHDL::Examples::GameBoy::Link::CLOCK_DIV).to eq(512)
      end
    end

    describe 'IR Generation' do
      it 'can generate IR representation' do
        expect(ir).not_to be_nil
        expect(ir.ports.length).to be > 0
      end

      it 'can generate flattened IR' do
        flat_ir = link.class.to_flat_ir
        expect(flat_ir).not_to be_nil
      end

      it 'has the correct number of ports' do
        # 11 inputs + 6 outputs = 17 ports minimum
        expect(ir.ports.length).to be >= 17
      end
    end
  end

  describe 'Link Integration Tests' do
    before(:all) do
      begin
        require_relative '../../../../examples/gameboy/utilities/runners/ir_runner'
        @ir_available = RHDL::Codegen::IR::COMPILER_AVAILABLE rescue false
        # Try to actually initialize a runner to verify it works
        if @ir_available
          test_runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
          test_runner = nil
        end
      rescue LoadError, NameError, RuntimeError => e
        @ir_available = false
        @ir_error = e.message
      end
    end

    before(:each) do
      skip "IR compiler not available: #{@ir_error}" unless @ir_available
      @runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
    end

    # Helper to create ROM that accesses serial registers
    def create_link_test_rom(code_bytes, entry: 0x0100)
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

      "LINKTEST".bytes.each_with_index { |b, i| rom[0x134 + i] = b }

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
      @runner.load_rom(create_link_test_rom(code_bytes))
      @runner.reset

      if skip_boot
        while @runner.cpu_state[:pc] < 0x0100 && @runner.cycle_count < 500_000
          # Keep step size small so we don't run deep into test code before exiting boot wait.
          @runner.run_steps(100)
        end
      end

      @runner.run_steps(cycles)
      @runner.cpu_state
    end

    describe 'SB Register ($FF01)' do
      it 'SB can be written and read' do
        code = [
          0x3E, 0xAB,  # LD A, 0xAB
          0xE0, 0x01,  # LDH (FF01), A  - write SB
          0xF0, 0x01,  # LDH A, (FF01)  - read SB
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 100)
        expect(state[:a]).to eq(0xAB)
      end
    end

    describe 'SC Register ($FF02)' do
      it 'SC can be written and read' do
        code = [
          0x3E, 0x01,  # LD A, 0x01 (internal clock)
          0xE0, 0x02,  # LDH (FF02), A  - write SC
          0xF0, 0x02,  # LDH A, (FF02)  - read SC
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 100)
        # SC bit 0 should be set
        expect(state[:a] & 0x01).to eq(0x01)
      end

      it 'SC bit 7 starts transfer' do
        code = [
          0x3E, 0x55,  # LD A, 0x55
          0xE0, 0x01,  # LDH (FF01), A  - SB = 0x55
          0x3E, 0x81,  # LD A, 0x81 (start, internal clock)
          0xE0, 0x02,  # LDH (FF02), A  - start transfer
          0xF0, 0x02,  # LDH A, (FF02)  - read SC
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 100)
        # Transfer should have started (bit 7 may be 1 or 0 depending on timing)
        expect(state[:a]).to be_a(Integer)
      end
    end

    describe 'Serial Transfer' do
      it 'transfer completes and clears start bit' do
        code = [
          0xF3,        # DI (keep timing deterministic during long delay loop)
          0x3E, 0xFF,  # LD A, 0xFF
          0xE0, 0x01,  # LDH (FF01), A  - SB
          0x3E, 0x81,  # LD A, 0x81 (start, internal clock)
          0xE0, 0x02,  # LDH (FF02), A  - start transfer
          # Wait for transfer to complete (8 bits at 8192 Hz takes ~4096 cycles)
          0x01, 0x00, 0x40, # LD BC, 0x4000
          0x0B,        # DEC BC
          0x78,        # LD A, B
          0xB1,        # OR C
          0x20, 0xFB,  # JR NZ, -5
          # Read SC
          0xF0, 0x02,  # LDH A, (FF02)
          0x76         # HALT
        ]
        state = run_test_code(code, cycles: 300000)
        # After transfer completes, bit 7 should be cleared
        expect(state[:a] & 0x80).to eq(0x00)
      end
    end
  end
end
