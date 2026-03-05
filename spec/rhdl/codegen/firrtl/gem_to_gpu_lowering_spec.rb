# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'rhdl/codegen/firrtl/gem_to_gpu_lowering'

RSpec.describe RHDL::Codegen::FIRRTL::GemToGpuLowering do
  describe '.lower' do
    it 'emits GEM metadata and produces deterministic partition stats' do
      synth_fixture = <<~MLIR
        module {
          hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
            %clk_clock = seq.to_clock %clk
            %cfalse = hw.constant false
            %ctrue = hw.constant true
            %c0_i8 = hw.constant 0 : i8
            %c0_i16 = hw.constant 0 : i16
            %pc_state = seq.firreg %c0_i16 clock %clk_clock reset sync %rst, %c0_i16 : i16
            %acc_state = seq.firreg %mem_data_in clock %clk_clock : i8
            %n0 = synth.aig.and_inv %cfalse, %ctrue : i1
            %n1 = synth.aig.and_inv %n0, not %cfalse : i1
            %n2 = synth.aig.and_inv %n0, %n1 : i1
            hw.output %acc_state, %pc_state, %n2, %cfalse, %pc_state, %acc_state, %c0_i8, %cfalse, %c0_i8, %cfalse : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
          }
        }
      MLIR

      Dir.mktmpdir('gem_to_gpu_lowering_spec') do |dir|
        synth_path = File.join(dir, 'cpu8bit.synth.mlir')
        gpu_path = File.join(dir, 'cpu8bit.gpu.mlir')
        meta_path = File.join(dir, 'cpu8bit.gem_gpu.json')
        metal_path = File.join(dir, 'cpu8bit.gem_gpu.metal')
        File.write(synth_path, synth_fixture)

        summary = described_class.lower(
          synth_mlir_path: synth_path,
          gpu_mlir_path: gpu_path,
          metadata_path: meta_path,
          metal_source_path: metal_path,
          profile: :cpu8bit,
          partition_size: 2
        )

        metadata = JSON.parse(File.read(meta_path))
        expect(metadata['version']).to eq('GemToGpuLoweringV1')
        expect(metadata['profile']).to eq('cpu8bit')
        expect(metadata).to include('gem')
        expect(metadata['gem']).to include(
          'partition_size' => 2,
          'node_count' => 3,
          'edge_count' => 3,
          'partition_count' => 2,
          'cross_partition_edges' => 2,
          'max_layer_depth' => 3,
          'max_layer_width' => 1
        )
        expect(metadata['gem']['average_layer_width']).to be_within(0.001).of(1.0)
        expect(metadata['gem']['execution']).to include(
          'schedule_version' => 'GemExecutionPlanV1',
          'partition_order' => [0, 1],
          'layer_count' => 3,
          'dispatch_cycle_granularity' => 6,
          'partition_dependency_edge_count' => 1,
          'ready_layer_count' => 2,
          'ready_layers' => [[0], [1]],
          'kernel_mode' => 'legacy_eval'
        )
        expect(metadata['gem']['partition_dependency_edges']).to eq(
          [{ 'from' => 0, 'to' => 1, 'count' => 2 }]
        )
        expect(metadata['gem']['instruction_stream']).to include(
          'version' => 'GemInstructionStreamV1',
          'instruction_count' => 3,
          'block_boundaries' => [0, 2, 3]
        )
        expect(metadata['gem']['instruction_stream']['output_watch_names']).to eq(
          %w[mem_write_en mem_read_en halted zero_flag_out]
        )
        expect(metadata['gem']['instruction_stream']['output_watch_sources']).to eq(
          [
            { 'kind' => 'node', 'id' => 2, 'inverted' => false },
            { 'kind' => 'extern', 'id' => 0, 'inverted' => false },
            { 'kind' => 'extern', 'id' => 0, 'inverted' => false },
            { 'kind' => 'extern', 'id' => 0, 'inverted' => false }
          ]
        )
        expect(metadata['gem']['instruction_stream']['watch_eval_indices']).to eq([0, 1, 2])
        expect(metadata['gem']['instruction_stream']['opcode_groups']).to include(
          'compute' => ['and_inv'],
          'state' => %w[state_read state_write],
          'memory' => %w[mem_read mem_write],
          'output' => ['output_materialize']
        )
        expect(metadata['gem']['instruction_stream']['primitive_counts']).to include(
          'and_inv' => 3,
          'state_read' => 2,
          'mem_read' => 1,
          'mem_write' => 1,
          'output_materialize' => 1
        )
        expect(metadata['gem']['instruction_stream']['control_program']).to eq(
          [
            { 'op' => 'cycle_begin' },
            { 'op' => 'eval_low' },
            { 'op' => 'mem_write' },
            { 'op' => 'mem_read' },
            { 'op' => 'eval_high' },
            { 'op' => 'output_materialize' },
            { 'op' => 'cycle_end' }
          ]
        )
        expect(metadata['gem']['instruction_stream']['extern_refs']).to include('%cfalse', '%ctrue')
        expect(metadata['gem']['instruction_stream']['extern_ref_kinds']).to include('const', 'const')
        expect(metadata['gem']['instruction_stream']['extern_ref_values']).to include(0, 1)
        expect(metadata['gem']['instruction_stream']['extern_sources']).to include(
          { 'kind' => 'const', 'value' => 0 },
          { 'kind' => 'const', 'value' => 1 }
        )
        first_inst = metadata['gem']['instruction_stream']['instructions'].first
        expect(first_inst).to include(
          'pc' => 0,
          'op' => 'and_inv',
          'dst_node' => 0
        )
        expect(first_inst.fetch('src').length).to eq(2)
        expect(metadata['gem']['instruction_stream']['checksum_sha256']).to match(/\A[0-9a-f]{64}\z/)

        expect(summary[:gem][:node_count]).to eq(3)
        expect(summary[:gem][:edge_count]).to eq(3)
        expect(summary[:gem][:cross_partition_edges]).to eq(2)
        expect(summary[:gem][:partition_dependency_edges]).to eq([{ from: 0, to: 1, count: 2 }])
        expect(summary[:gem][:execution][:dispatch_cycle_granularity]).to eq(6)
        expect(summary[:gem][:execution][:ready_layer_count]).to eq(2)
        expect(summary[:gem][:execution][:ready_layers]).to eq([[0], [1]])
        expect(summary[:gem][:execution][:kernel_mode]).to eq('legacy_eval')
        expect(summary[:gem][:instruction_stream][:instruction_count]).to eq(3)
        expect(summary[:gem][:instruction_stream][:block_boundaries]).to eq([0, 2, 3])
        expect(summary[:gem][:instruction_stream][:primitive_counts][:and_inv]).to eq(3)
        expect(summary[:gem][:instruction_stream][:control_program].map { |step| step.fetch(:op) }).to include('cycle_begin', 'cycle_end')
        metal = File.read(metal_path)
        expect(metal).to include('kernel void')
        expect(metal).not_to include('state_old_')
        expect(metal).to match(/always_inline\)\)\s+cpu8bit_outputs\s+eval_cpu8bit\(/)
        expect(metal).to include('compute_eval_cpu8bit_post_comb')
        expect(metal).to match(/compute_eval_cpu8bit_post_comb\([^)]*device uint\* state_slots/)

        second = described_class.lower(
          synth_mlir_path: synth_path,
          gpu_mlir_path: gpu_path,
          metadata_path: meta_path,
          metal_source_path: metal_path,
          profile: :cpu8bit,
          partition_size: 2
        )
        expect(second[:gem]).to eq(summary[:gem])
      end
    end

    it 'emits kernel-side control interpreter markers when interpreter mode is enabled' do
      synth_fixture = <<~MLIR
        module {
          hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
            %clk_clock = seq.to_clock %clk
            %cfalse = hw.constant false
            %ctrue = hw.constant true
            %c0_i8 = hw.constant 0 : i8
            %c0_i16 = hw.constant 0 : i16
            %pc_state = seq.firreg %c0_i16 clock %clk_clock reset sync %rst, %c0_i16 : i16
            %acc_state = seq.firreg %mem_data_in clock %clk_clock : i8
            %n0 = synth.aig.and_inv %cfalse, %ctrue : i1
            %n1 = synth.aig.and_inv %n0, not %cfalse : i1
            hw.output %acc_state, %pc_state, %n1, %cfalse, %pc_state, %acc_state, %c0_i8, %cfalse, %c0_i8, %cfalse : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
          }
        }
      MLIR

      old = ENV['RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER']
      ENV['RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER'] = '1'

      Dir.mktmpdir('gem_to_gpu_lowering_spec_interp') do |dir|
        synth_path = File.join(dir, 'cpu8bit.synth.mlir')
        gpu_path = File.join(dir, 'cpu8bit.gpu.mlir')
        meta_path = File.join(dir, 'cpu8bit.gem_gpu.json')
        metal_path = File.join(dir, 'cpu8bit.gem_gpu.metal')
        File.write(synth_path, synth_fixture)

        described_class.lower(
          synth_mlir_path: synth_path,
          gpu_mlir_path: gpu_path,
          metadata_path: meta_path,
          metal_source_path: metal_path,
          profile: :cpu8bit,
          partition_size: 2
        )

        metadata = JSON.parse(File.read(meta_path))
        expect(metadata.dig('gem', 'execution', 'kernel_mode')).to eq('instruction_stream_control')
        metal = File.read(metal_path)
        expect(metal).to include('constexpr ushort kGemControlOps[7]')
        expect(metal).to include('switch (op)')
        expect(metal).to include('uint control_count = gem_instr[control_off];')
        expect(metal).to include('uint op_count = control_count > 0u ? control_count : 7u;')
        expect(metal).to include('thread ushort control_ops[32];')
        expect(metal).to include('control_ops[op_idx] = ushort(gem_instr[control_off + 1u + op_idx] & 0xFFFFu);')
        expect(metal).to include('uint extern_count = gem_instr[extern_off];')
        expect(metal).to include('uint extern_desc_count = gem_instr[extern_desc_off];')
        expect(metal).to include('if ((gem_flags & 0x8u) != 0u && id < extern_desc_count)')
        expect(metal).to include('thread uint extern_values[kGemExternValueCap];')
        expect(metal).to include('for (uint e = 0u; e < extern_value_count; ++e)')
        expect(metal).to include('bool emit_shadow_hash = (gem_flags & 0x2u) != 0u;')
        expect(metal).to include('if ((gem_flags & 0x4u) != 0u)')
        expect(metal).to include('value = gem_instr[extern_off + 1u + id] & 1u;')
        expect(metal).to include('rhdl_gem_read_io_word')
        expect(metal).to include('if (need_watch_override || (i == 0u && need_debug_shadow))')
        expect(metal).to include('if (need_debug_shadow && (gem_shadow & 1u) != 0u)')
        expect(metal).to include('device const uint* gem_instr [[buffer(3)]]')
        expect(metal).to include('rhdl_gem_execute_shadow')
        expect(metal).not_to include('high.halted = (gem_watch_bits >> 2u) & 1u;')
      end
    ensure
      if old.nil?
        ENV.delete('RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER')
      else
        ENV['RHDL_CPU8BIT_GEM_KERNEL_INTERPRETER'] = old
      end
    end
  end
end
