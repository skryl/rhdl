# frozen_string_literal: true

require 'spec_helper'

# Game Boy Color HDMA (H-Blank DMA) Tests
# Tests the HDMA controller for GDMA and HDMA transfers
#
# The HDMA uses the SequentialComponent DSL for IR compilation.
# Tests verify the component structure and register access.
# Complex DMA behavior tests are run through the IR runner when available.
#
# Registers:
# - FF51: HDMA1 - Source High
# - FF52: HDMA2 - Source Low (lower 4 bits ignored)
# - FF53: HDMA3 - Destination High (only bits 0-4 used, ORed with 0x80)
# - FF54: HDMA4 - Destination Low (lower 4 bits ignored)
# - FF55: HDMA5 - Length/Mode/Start

RSpec.describe 'GameBoy HDMA' do
  before(:all) do
    begin
      require_relative '../../../../../examples/gameboy/gameboy'
      require_relative '../../../../../examples/gameboy/hdl/dma/hdma'
      @component_available = defined?(RHDL::Examples::GameBoy::HDMA)
    rescue LoadError => e
      @component_available = false
      @load_error = e.message
    end
  end

  before(:each) do
    skip "HDMA component not available: #{@load_error}" unless @component_available
  end

  # ==========================================================================
  # Component Definition Tests
  # ==========================================================================
  describe 'Component Definition' do
    it 'defines HDMA class' do
      expect(defined?(RHDL::Examples::GameBoy::HDMA)).to eq('constant')
    end

    it 'can be instantiated' do
      hdma = RHDL::Examples::GameBoy::HDMA.new('test_hdma')
      expect(hdma).to be_a(RHDL::Examples::GameBoy::HDMA)
    end

    it 'inherits from SequentialComponent' do
      expect(RHDL::Examples::GameBoy::HDMA.superclass).to eq(RHDL::HDL::SequentialComponent)
    end
  end

  describe 'HDMA Component Structure' do
    let(:hdma) { RHDL::Examples::GameBoy::HDMA.new('hdma') }
    let(:ir) { hdma.class.to_ir }
    let(:port_names) { ir.ports.map { |p| p.name.to_sym } }

    describe 'Input Ports (via IR)' do
      it 'has reset input' do
        expect(port_names).to include(:reset)
      end

      it 'has clk input' do
        expect(port_names).to include(:clk)
      end

      it 'has ce (clock enable) input' do
        expect(port_names).to include(:ce)
      end

      it 'has speed input for CPU speed mode' do
        expect(port_names).to include(:speed)
      end

      it 'has sel_reg input for register selection' do
        expect(port_names).to include(:sel_reg)
      end

      it 'has addr input (4-bit for register address)' do
        expect(port_names).to include(:addr)
      end

      it 'has wr input for write enable' do
        expect(port_names).to include(:wr)
      end

      it 'has din input for data in (8-bit)' do
        expect(port_names).to include(:din)
      end

      it 'has lcd_mode input (2-bit)' do
        expect(port_names).to include(:lcd_mode)
      end
    end

    describe 'Output Ports (via IR)' do
      it 'has dout output for data out (8-bit)' do
        expect(port_names).to include(:dout)
      end

      it 'has hdma_rd output' do
        expect(port_names).to include(:hdma_rd)
      end

      it 'has hdma_active output' do
        expect(port_names).to include(:hdma_active)
      end

      it 'has hdma_source_addr output (16-bit)' do
        expect(port_names).to include(:hdma_source_addr)
      end

      it 'has hdma_target_addr output (16-bit)' do
        expect(port_names).to include(:hdma_target_addr)
      end
    end

    describe 'IR Generation' do
      it 'can generate IR representation' do
        expect(ir).not_to be_nil
        expect(ir.ports.length).to be > 0
      end

      it 'can generate flattened IR' do
        flat_ir = hdma.class.to_flat_ir
        expect(flat_ir).not_to be_nil
      end

      it 'includes behavior block in IR' do
        expect(hdma.class.behavior_defined?).to eq(true)
      end

      it 'includes sequential block in IR' do
        expect(hdma.class.sequential_defined?).to eq(true)
      end
    end
  end

  # ==========================================================================
  # Register Access Tests (via read_reg/write_reg methods)
  # ==========================================================================
  describe 'Register State Access' do
    let(:hdma) { RHDL::Examples::GameBoy::HDMA.new('hdma') }

    before(:each) do
      # Initialize default inputs
      hdma.set_input(:reset, 0)
      hdma.set_input(:clk, 0)
      hdma.set_input(:ce, 1)
      hdma.set_input(:speed, 0)
      hdma.set_input(:sel_reg, 0)
      hdma.set_input(:addr, 0)
      hdma.set_input(:wr, 0)
      hdma.set_input(:din, 0)
      hdma.set_input(:lcd_mode, 0)
    end

    it 'can write source_hi register' do
      hdma.write_reg(:source_hi, 0x80)
      expect(hdma.read_reg(:source_hi)).to eq(0x80)
    end

    it 'can write source_lo register' do
      hdma.write_reg(:source_lo, 0xF0)
      expect(hdma.read_reg(:source_lo)).to eq(0xF0)
    end

    it 'can write dest_hi register' do
      hdma.write_reg(:dest_hi, 0x10)
      expect(hdma.read_reg(:dest_hi)).to eq(0x10)
    end

    it 'can write dest_lo register' do
      hdma.write_reg(:dest_lo, 0xA0)
      expect(hdma.read_reg(:dest_lo)).to eq(0xA0)
    end

    it 'initializes dma_active to 0' do
      expect(hdma.read_reg(:dma_active)).to eq(0)
    end

    it 'initializes hdma_mode to 0' do
      expect(hdma.read_reg(:hdma_mode)).to eq(0)
    end

    it 'initializes remaining to 0' do
      expect(hdma.read_reg(:remaining)).to eq(0)
    end

    it 'initializes byte_counter to 0' do
      expect(hdma.read_reg(:byte_counter)).to eq(0)
    end
  end

end
