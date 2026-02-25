require_relative '../spec_helper'
require_relative '../../../../examples/ao486/hdl/global_regs'

RSpec.describe RHDL::Examples::AO486::GlobalRegs do
  let(:regs) { RHDL::Examples::AO486::GlobalRegs.new }

  describe 'parameter registers' do
    it 'initializes all params to zero after reset' do
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      (1..5).each do |i|
        expect(regs.get_output(:"glob_param_#{i}")).to eq(0)
      end
    end

    it 'latches param_1 on set' do
      # Reset
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      # Set param_1
      regs.set_input(:rst_n, 1)
      regs.set_input(:glob_param_1_set, 1)
      regs.set_input(:glob_param_1_value, 0xDEAD_BEEF)
      regs.set_input(:clk, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      expect(regs.get_output(:glob_param_1)).to eq(0xDEAD_BEEF)
    end
  end

  describe 'descriptor registers' do
    it 'latches descriptor on set' do
      # Reset
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      # Set descriptor
      regs.set_input(:rst_n, 1)
      regs.set_input(:glob_descriptor_set, 1)
      regs.set_input(:glob_descriptor_value, 0x00CF_9A00_0000_FFFF)
      regs.set_input(:clk, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      expect(regs.get_output(:glob_descriptor)).to eq(0x00CF_9A00_0000_FFFF)
    end

    it 'computes glob_desc_base from descriptor' do
      # Reset
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      # Descriptor with base = 0x12345678
      # Bits [63:56] = base[31:24] = 0x12
      # Bits [39:16] = base[23:0]  = 0x345678
      # Full descriptor: base[31:24]=0x12, limit[19:16]=0x0, flags, base[23:0]=0x345678, limit[15:0]=0x0000
      desc = (0x12 << 56) | (0x34_5678 << 16)
      regs.set_input(:rst_n, 1)
      regs.set_input(:glob_descriptor_set, 1)
      regs.set_input(:glob_descriptor_value, desc)
      regs.set_input(:clk, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      expect(regs.get_output(:glob_desc_base)).to eq(0x12345678)
    end

    it 'computes glob_desc_limit with G=0 (byte granularity)' do
      # Reset
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      # Descriptor with G=0, limit = 0x12345
      # G bit is bit 55
      # limit[19:16] in bits [51:48] = 0x1
      # limit[15:0] in bits [15:0] = 0x2345
      desc = (0x1 << 48) | 0x2345
      regs.set_input(:rst_n, 1)
      regs.set_input(:glob_descriptor_set, 1)
      regs.set_input(:glob_descriptor_value, desc)
      regs.set_input(:clk, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      expect(regs.get_output(:glob_desc_limit)).to eq(0x0001_2345)
    end

    it 'computes glob_desc_limit with G=1 (page granularity)' do
      # Reset
      regs.set_input(:clk, 0)
      regs.set_input(:rst_n, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      # Descriptor with G=1, limit = 0x12345
      # G bit is bit 55 = 1
      # limit[19:16] in bits [51:48] = 0x1
      # limit[15:0] in bits [15:0] = 0x2345
      # Result should be { 0x1, 0x2345, 0xFFF } = 0x12345FFF
      desc = (1 << 55) | (0x1 << 48) | 0x2345
      regs.set_input(:rst_n, 1)
      regs.set_input(:glob_descriptor_set, 1)
      regs.set_input(:glob_descriptor_value, desc)
      regs.set_input(:clk, 0)
      regs.propagate
      regs.set_input(:clk, 1)
      regs.propagate

      expect(regs.get_output(:glob_desc_limit)).to eq(0x1234_5FFF)
    end
  end
end
