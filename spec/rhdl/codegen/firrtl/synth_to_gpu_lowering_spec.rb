# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'rhdl/codegen/firrtl/synth_to_gpu_lowering'

RSpec.describe RHDL::Codegen::FIRRTL::SynthToGpuLowering do
  describe '.lower' do
    it 'lowers synth/hw mlir without requiring arc.define wrappers' do
      synth_fixture = <<~MLIR
        module {
          hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
            %clk_clock = seq.to_clock %clk
            %cfalse = hw.constant false
            %c0_i8 = hw.constant 0 : i8
            %c0_i16 = hw.constant 0 : i16
            %pc_state = seq.firreg %c0_i16 clock %clk_clock reset sync %rst, %c0_i16 : i16
            %acc_state = seq.firreg %mem_data_in clock %clk_clock : i8
            hw.output %acc_state, %pc_state, %cfalse, %cfalse, %pc_state, %acc_state, %c0_i8, %cfalse, %c0_i8, %cfalse : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
          }
        }
      MLIR

      Dir.mktmpdir('synth_to_gpu_lowering_spec') do |dir|
        synth_path = File.join(dir, 'cpu8bit.synth.mlir')
        gpu_path = File.join(dir, 'cpu8bit.gpu.mlir')
        meta_path = File.join(dir, 'cpu8bit.synth_to_gpu.json')
        metal_path = File.join(dir, 'cpu8bit.synth_to_gpu.metal')
        File.write(synth_path, synth_fixture)

        summary = described_class.lower(
          synth_mlir_path: synth_path,
          gpu_mlir_path: gpu_path,
          metadata_path: meta_path,
          metal_source_path: metal_path,
          profile: :cpu8bit
        )

        expect(summary[:module]).to eq('cpu8bit')
        expect(summary[:profile]).to eq(:cpu8bit)
        expect(summary[:arc_define_count]).to eq(0)
        metadata = JSON.parse(File.read(meta_path))
        expect(metadata['version']).to eq('SynthToGpuLoweringV1')
        expect(metadata['profile']).to eq('cpu8bit')
        expect(File.read(metal_path)).to include('kernel void')
      end
    end
  end
end
