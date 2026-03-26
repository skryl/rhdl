# frozen_string_literal: true

require 'spec_helper'

require_relative './headless_runtime_support'

RSpec.describe GameboyImportHeadlessRuntimeSupport do
  let(:helper) do
    Object.new.tap do |obj|
      obj.extend(described_class)
    end
  end

  describe '#sampled_state' do
    it 'falls back to cpu_state pc when imported debug pc is zero' do
      headless = instance_double(
        'RHDL::Examples::GameBoy::HeadlessRunner',
        cpu_state: { pc: 0x8000, cycles: 128 },
        frame_count: 0,
        cycle_count: 128
      )

      allow(helper).to receive(:runtime_debug_snapshot).with(headless).and_return(
        gb_core_cpu_pc: 0,
        gb_core_cpu_tstate: 0,
        gb_core_cpu_mcycle: 1,
        gb_core_cpu_addr: 0,
        gb_core_cpu_rd_n: 1,
        gb_core_cpu_wr_n: 1,
        gb_core_cpu_m1_n: 1
      )

      expect(helper.sampled_state(headless)).to include(
        pc: 0x8000,
        tstate: 0,
        mcycle: 1,
        addr: 0,
        rd_n: 1,
        wr_n: 1,
        m1_n: 1,
        frame_count: 0,
        cycles: 128
      )
    end
  end
end
