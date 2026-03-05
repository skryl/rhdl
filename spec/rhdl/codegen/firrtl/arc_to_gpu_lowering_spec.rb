# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'json'
require 'rhdl/codegen/firrtl/arc_to_gpu_lowering'

RSpec.describe RHDL::Codegen::FIRRTL::ArcToGpuLowering do
  def arc_fixture(top_outputs: nil, extra_op_line: nil)
    outputs = top_outputs || 'out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1'

    <<~MLIR
      module {
        arc.define @arc_probe_passthrough(%arg0: i8) -> i8 {
          #{extra_op_line}
          arc.output %arg0 : i8
        }

        arc.define @arc_probe_clock(%arg0: i1) -> !seq.clock {
          %0 = seq.to_clock %arg0
          arc.output %0 : !seq.clock
        }

        hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, #{outputs}) {
          %c0_i16 = hw.constant 0 : i16
          %false = hw.constant false
          %clk_i = arc.call @arc_probe_clock(%clk) : (i1) -> !seq.clock
          %state = arc.state @arc_probe_passthrough(%mem_data_in) clock %clk_i reset %rst latency 1 : (i8) -> i8
          hw.output %state, %c0_i16, %false, %false, %c0_i16, %state, %state, %false, %state, %false : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
        }
      }
    MLIR
  end

  def riscv_arc_fixture(top_outputs: nil)
    outputs = top_outputs || 'out inst_addr : i32, out inst_ptw_addr1 : i32, out inst_ptw_addr0 : i32, out data_addr : i32, out data_wdata : i32, out data_we : i1, out data_re : i1, out data_funct3 : i3, out data_ptw_addr1 : i32, out data_ptw_addr0 : i32, out debug_pc : i32, out debug_inst : i32, out debug_x1 : i32, out debug_x2 : i32, out debug_x10 : i32, out debug_x11 : i32, out debug_reg_data : i32'

    <<~MLIR
      module {
        arc.define @riscv_passthrough(%arg0: i32) -> i32 {
          arc.output %arg0 : i32
        }

        arc.define @riscv_clock(%arg0: i1) -> !seq.clock {
          %0 = seq.to_clock %arg0
          arc.output %0 : !seq.clock
        }

        hw.module @riscv_cpu(in %clk : i1, in %rst : i1, in %irq_software : i1, in %irq_timer : i1, in %irq_external : i1, in %inst_data : i32, in %inst_ptw_pte1 : i32, in %inst_ptw_pte0 : i32, in %data_rdata : i32, in %data_ptw_pte1 : i32, in %data_ptw_pte0 : i32, in %debug_reg_addr : i5, #{outputs}) {
          %false = hw.constant false
          %c0_i3 = hw.constant 0 : i3
          %clk_i = arc.call @riscv_clock(%clk) : (i1) -> !seq.clock
          %state = arc.state @riscv_passthrough(%inst_data) clock %clk_i reset %rst latency 1 : (i32) -> i32
          hw.output %state, %state, %state, %state, %state, %false, %false, %c0_i3, %state, %state, %state, %state, %state, %state, %state, %state, %state : i32, i32, i32, i32, i32, i1, i1, i3, i32, i32, i32, i32, i32, i32, i32, i32, i32
        }
      }
    MLIR
  end

  def arc_fixture_with_dead_define
    <<~MLIR
      module {
        arc.define @arc_used_passthrough(%arg0: i8) -> i8 {
          arc.output %arg0 : i8
        }

        arc.define @arc_dead_passthrough(%arg0: i8) -> i8 {
          %c1 = hw.constant 1 : i8
          arc.output %c1 : i8
        }

        arc.define @arc_probe_clock(%arg0: i1) -> !seq.clock {
          %0 = seq.to_clock %arg0
          arc.output %0 : !seq.clock
        }

        hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
          %c0_i16 = hw.constant 0 : i16
          %false = hw.constant false
          %clk_i = arc.call @arc_probe_clock(%clk) : (i1) -> !seq.clock
          %state = arc.state @arc_used_passthrough(%mem_data_in) clock %clk_i reset %rst latency 1 : (i8) -> i8
          hw.output %state, %c0_i16, %false, %false, %c0_i16, %state, %state, %false, %state, %false : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
        }
      }
    MLIR
  end

  def arc_fixture_with_constant_array_get
    <<~MLIR
      module {
        arc.define @arc_probe_passthrough(%arg0: i8) -> i8 {
          %c1 = hw.constant 1 : i8
          %c2 = hw.constant 2 : i8
          %c3 = hw.constant 3 : i8
          %idx = hw.constant 5 : i8
          %arr = hw.array_create %c1, %c2, %c3 : i8
          %sel = hw.array_get %arr[%idx] : !hw.array<3xi8>, i8
          arc.output %sel : i8
        }

        arc.define @arc_probe_clock(%arg0: i1) -> !seq.clock {
          %0 = seq.to_clock %arg0
          arc.output %0 : !seq.clock
        }

        hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
          %c0_i16 = hw.constant 0 : i16
          %false = hw.constant false
          %clk_i = arc.call @arc_probe_clock(%clk) : (i1) -> !seq.clock
          %state = arc.state @arc_probe_passthrough(%mem_data_in) clock %clk_i reset %rst latency 1 : (i8) -> i8
          hw.output %state, %c0_i16, %false, %false, %c0_i16, %state, %state, %false, %state, %false : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
        }
      }
    MLIR
  end

  def arc_fixture_with_aggregate_array_get
    <<~MLIR
      module {
        arc.define @arc_probe_passthrough(%arg0: i8) -> i8 {
          %idx = hw.constant 2 : i8
          %arr = hw.aggregate_constant [11 : i8, 22 : i8, 33 : i8] : !hw.array<3xi8>
          %sel = hw.array_get %arr[%idx] : !hw.array<3xi8>, i8
          arc.output %sel : i8
        }

        arc.define @arc_probe_clock(%arg0: i1) -> !seq.clock {
          %0 = seq.to_clock %arg0
          arc.output %0 : !seq.clock
        }

        hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
          %c0_i16 = hw.constant 0 : i16
          %false = hw.constant false
          %clk_i = arc.call @arc_probe_clock(%clk) : (i1) -> !seq.clock
          %state = arc.state @arc_probe_passthrough(%mem_data_in) clock %clk_i reset %rst latency 1 : (i8) -> i8
          hw.output %state, %c0_i16, %false, %false, %c0_i16, %state, %state, %false, %state, %false : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
        }
      }
    MLIR
  end

  it 'emits ArcToGPU artifacts and metadata for supported Arc MLIR' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'input.arc.mlir')
      gpu_path = File.join(dir, 'output.gpu.mlir')
      meta_path = File.join(dir, 'output.arc_to_gpu.json')

      File.write(arc_path, arc_fixture)

      summary = described_class.lower(
        arc_mlir_path: arc_path,
        gpu_mlir_path: gpu_path,
        metadata_path: meta_path
      )

      expect(summary[:module]).to eq('cpu8bit')
      expect(summary[:arc_define_count]).to be >= 1
      expect(summary[:arc_state_count]).to be >= 1
      expect(File).to exist(gpu_path)
      expect(File).to exist(meta_path)

      gpu_text = File.read(gpu_path)
      expect(gpu_text).to include('gpu.module')
      expect(gpu_text).to include('rhdl.arc_to_gpu.version')

      metadata = JSON.parse(File.read(meta_path))
      expect(metadata['version']).to eq('ArcToGpuLoweringV2')
      expect(metadata['module']).to eq('cpu8bit')
      expect(metadata.dig('metal', 'entry')).to match(/cpu8bit/)
      expect(metadata.dig('metal', 'state_count')).to be >= 1
    end
  end

  it 'fails when required top outputs are missing' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'input.arc.mlir')
      gpu_path = File.join(dir, 'output.gpu.mlir')

      File.write(
        arc_path,
        arc_fixture(top_outputs: 'out mem_data_out : i8, out mem_addr : i16')
      )

      expect do
        described_class.lower(arc_mlir_path: arc_path, gpu_mlir_path: gpu_path)
      end.to raise_error(described_class::LoweringError, /missing required outputs/i)
    end
  end

  it 'fails when unsupported operations are present' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'input.arc.mlir')
      gpu_path = File.join(dir, 'output.gpu.mlir')

      File.write(
        arc_path,
        arc_fixture(extra_op_line: '%x = comb.shrs %arg0, %arg0 : i8')
      )

      expect do
        described_class.lower(arc_mlir_path: arc_path, gpu_mlir_path: gpu_path)
      end.to raise_error(described_class::LoweringError, /does not support ops/i)
    end
  end

  it 'supports comb.concat with more than two operands' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'input.arc.mlir')
      gpu_path = File.join(dir, 'output.gpu.mlir')
      metal_path = File.join(dir, 'output.metal')

      concat_fixture = <<~MLIR
        module {
          arc.define @arc_probe_passthrough(%arg0: i8) -> i8 {
            %x = comb.concat %arg0, %arg0, %arg0 : i8, i8, i8
            %y = comb.extract %x from 0 : (i24) -> i8
            arc.output %y : i8
          }

          arc.define @arc_probe_clock(%arg0: i1) -> !seq.clock {
            %0 = seq.to_clock %arg0
            arc.output %0 : !seq.clock
          }

          hw.module @cpu8bit(in %clk : i1, in %rst : i1, in %mem_data_in : i8, out mem_data_out : i8, out mem_addr : i16, out mem_write_en : i1, out mem_read_en : i1, out pc_out : i16, out acc_out : i8, out sp_out : i8, out halted : i1, out state_out : i8, out zero_flag_out : i1) {
            %c0_i16 = hw.constant 0 : i16
            %false = hw.constant false
            %clk_i = arc.call @arc_probe_clock(%clk) : (i1) -> !seq.clock
            %state = arc.state @arc_probe_passthrough(%mem_data_in) clock %clk_i reset %rst latency 1 : (i8) -> i8
            hw.output %state, %c0_i16, %false, %false, %c0_i16, %state, %state, %false, %state, %false : i8, i16, i1, i1, i16, i8, i8, i1, i8, i1
          }
        }
      MLIR
      File.write(arc_path, concat_fixture)

      described_class.lower(
        arc_mlir_path: arc_path,
        gpu_mlir_path: gpu_path,
        metal_source_path: metal_path
      )

      metal_source = File.read(metal_path)
      expect(metal_source).to include('<< 16u')
      expect(metal_source).to include('<< 8u')
    end
  end

  it 'emits ArcToGPU artifacts for riscv profile' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'riscv.arc.mlir')
      gpu_path = File.join(dir, 'riscv.gpu.mlir')
      meta_path = File.join(dir, 'riscv.arc_to_gpu.json')
      metal_path = File.join(dir, 'riscv.metal')

      File.write(arc_path, riscv_arc_fixture)

      summary = described_class.lower(
        arc_mlir_path: arc_path,
        gpu_mlir_path: gpu_path,
        metadata_path: meta_path,
        metal_source_path: metal_path,
        profile: :riscv
      )

      expect(summary[:module]).to eq('riscv_cpu')
      expect(summary[:profile]).to eq(:riscv)
      metadata = JSON.parse(File.read(meta_path))
      expect(metadata['profile']).to eq('riscv')
      expect(metadata.dig('metal', 'entry')).to include('riscv_cpu')
      runtime_output_names = Array(metadata.dig('metal', 'runtime_output_layout')).map { |entry| entry.fetch('name') }
      expect(runtime_output_names).not_to include('debug_pc')
      expect(runtime_output_names).not_to include('debug_inst')
      expect(runtime_output_names).not_to include('debug_x1')
      expect(runtime_output_names).not_to include('debug_x2')
      expect(runtime_output_names).not_to include('debug_x10')
      expect(runtime_output_names).not_to include('debug_x11')
      expect(runtime_output_names).not_to include('debug_reg_data')
      introspection = metadata.dig('metal', 'introspection')
      expect(introspection).to include('pc_slot', 'pc_width', 'regfile_base_slot', 'regfile_length')
      expect(introspection.fetch('pc_width')).to eq(32)
      expect(introspection.fetch('regfile_length')).to be >= 0
      expect(metadata.dig('metal', 'schedule_mode')).to eq('legacy')
      expect(metadata.dig('metal', 'fast_low_wdata_mode')).to eq('split')
      expect(metadata.dig('metal', 'fast_high_data_addr_mode')).to eq('split')
      expect(metadata.dig('metal', 'fast_low_data_addr_mode')).to eq('split')
      expect(metadata['top_inputs']).to include('inst_data')
      metal_source = File.read(metal_path)
      expect(metal_source).to include('rhdl_read_mem_funct3')
      io_struct = metal_source[/struct RhdlArcGpuIo \{.*?\n\};/m]
      expect(io_struct).not_to be_nil
      expect(io_struct).not_to include('uint debug_pc;')
      expect(io_struct).not_to include('uint debug_reg_data;')
      expect(metal_source).to include('riscv_eval_low_wdata_fast')
      expect(metal_source).to include('riscv_eval_low_data_addr_fast')
      expect(metal_source).to include('riscv_eval_high_data_addr_fast')
    end
  end

  it 'emits ArcToGPU artifacts for riscv_netlist profile' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'riscv.arc.mlir')
      gpu_path = File.join(dir, 'riscv_netlist.gpu.mlir')
      meta_path = File.join(dir, 'riscv_netlist.arc_to_gpu.json')
      metal_path = File.join(dir, 'riscv_netlist.metal')

      File.write(arc_path, riscv_arc_fixture)

      summary = described_class.lower(
        arc_mlir_path: arc_path,
        gpu_mlir_path: gpu_path,
        metadata_path: meta_path,
        metal_source_path: metal_path,
        profile: :riscv_netlist
      )

      expect(summary[:module]).to eq('riscv_cpu')
      expect(summary[:profile]).to eq(:riscv_netlist)
      metadata = JSON.parse(File.read(meta_path))
      expect(metadata['profile']).to eq('riscv_netlist')
      expect(metadata.dig('metal', 'entry')).to include('riscv_cpu')
      expect(metadata.dig('metal', 'schedule_mode')).to eq('netlist_aig_legacy')
      runtime_output_names = Array(metadata.dig('metal', 'runtime_output_layout')).map { |entry| entry.fetch('name') }
      expect(runtime_output_names).to be_empty
      introspection = metadata.dig('metal', 'introspection')
      expect(introspection).to include('pc_slot', 'pc_width', 'regfile_base_slot', 'regfile_length')
      expect(introspection.fetch('pc_width')).to eq(32)
      metal_source = File.read(metal_path)
      expect(metal_source).to include('rhdl_read_mem_funct3')
      expect(metal_source).to include('riscv_eval_low_wdata_fast')
      expect(metal_source).to include('riscv_eval_low_data_addr_fast')
      expect(metal_source).to include('riscv_eval_high_data_addr_fast')
    end
  end

  it 'uses fixed riscv fast-default modes regardless of removed env toggles' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'riscv.arc.mlir')
      gpu_path = File.join(dir, 'riscv.gpu.mlir')
      meta_path = File.join(dir, 'riscv.arc_to_gpu.json')
      metal_path = File.join(dir, 'riscv.metal')
      original_split_low_wdata = ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_WDATA']
      original_split_high_data_addr = ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_HIGH_DATA_ADDR']
      original_split_low_data_addr = ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_DATA_ADDR']
      original_dirty_settle = ENV['RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE']
      original_scheduled_emit = ENV['RHDL_ARC_TO_GPU_RISCV_SCHEDULED_EMIT']
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_WDATA'] = '0'
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_HIGH_DATA_ADDR'] = '0'
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_DATA_ADDR'] = '0'
      ENV['RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE'] = '1'
      ENV['RHDL_ARC_TO_GPU_RISCV_SCHEDULED_EMIT'] = '1'

      File.write(arc_path, riscv_arc_fixture)

      described_class.lower(
        arc_mlir_path: arc_path,
        gpu_mlir_path: gpu_path,
        metadata_path: meta_path,
        metal_source_path: metal_path,
        profile: :riscv
      )

      metal_source = File.read(metal_path)
      metadata = JSON.parse(File.read(meta_path))
      expect(metal_source).to include('riscv_eval_low_wdata_fast')
      expect(metal_source).to include('loww = riscv_cpu_riscv_eval_low_wdata_fast(')
      expect(metadata.dig('metal', 'fast_low_wdata_mode')).to eq('split')
      expect(metal_source).to include('riscv_eval_high_data_addr_fast')
      expect(metal_source).to include('high_addr = riscv_cpu_riscv_eval_high_data_addr_fast(')
      expect(metadata.dig('metal', 'fast_high_data_addr_mode')).to eq('split')
      expect(metal_source).to include('riscv_eval_low_data_addr_fast')
      expect(metal_source).to include('low_addr = riscv_cpu_riscv_eval_low_data_addr_fast(')
      expect(metadata.dig('metal', 'fast_low_data_addr_mode')).to eq('split')
      expect(metadata.dig('metal', 'schedule_mode')).to eq('legacy')
      expect(metal_source).not_to include('state_dirty')
      expect(metal_source).not_to include('// schedule_phase:')
      expect(metal_source).not_to include('// schedule_level')
    ensure
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_WDATA'] = original_split_low_wdata
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_HIGH_DATA_ADDR'] = original_split_high_data_addr
      ENV['RHDL_ARC_TO_GPU_RISCV_SPLIT_LOW_DATA_ADDR'] = original_split_low_data_addr
      ENV['RHDL_ARC_TO_GPU_RISCV_DIRTY_SETTLE'] = original_dirty_settle
      ENV['RHDL_ARC_TO_GPU_RISCV_SCHEDULED_EMIT'] = original_scheduled_emit
    end
  end

  it 'fails riscv profile when required outputs are missing' do
    Dir.mktmpdir('arc_to_gpu_lowering_spec') do |dir|
      arc_path = File.join(dir, 'riscv.arc.mlir')
      gpu_path = File.join(dir, 'riscv.gpu.mlir')

      File.write(
        arc_path,
        riscv_arc_fixture(top_outputs: 'out inst_addr : i32, out inst_ptw_addr1 : i32')
      )

      expect do
        described_class.lower(
          arc_mlir_path: arc_path,
          gpu_mlir_path: gpu_path,
          profile: :riscv
        )
      end.to raise_error(described_class::LoweringError, /missing required outputs/i)
    end
  end

  it 'prunes unreachable arc.define functions from parsed graph' do
    parsed = described_class.parse_arc_mlir(arc_fixture_with_dead_define)
    expect(parsed[:functions].keys).to include('arc_dead_passthrough')

    pruned = described_class.prune_unreachable_functions(parsed)
    expect(pruned[:functions].keys).to include('arc_used_passthrough')
    expect(pruned[:functions].keys).not_to include('arc_dead_passthrough')
  end

  it 'folds array_get(array_create(...), constant) to alias' do
    parsed = described_class.parse_arc_mlir(arc_fixture_with_constant_array_get)
    folded = described_class.fold_constant_array_gets(parsed)
    fn = folded.fetch(:functions).fetch('arc_probe_passthrough')
    sel_op = fn.fetch(:ops).find { |op| op.fetch(:result_refs).include?('%sel') }

    expect(sel_op.fetch(:kind)).to eq(:alias)
    expect(sel_op.fetch(:source_ref)).to eq('%c3')
  end

  it 'folds array_get(aggregate_constant(...), constant) to constant' do
    parsed = described_class.parse_arc_mlir(arc_fixture_with_aggregate_array_get)
    folded = described_class.fold_constant_array_gets(parsed)
    fn = folded.fetch(:functions).fetch('arc_probe_passthrough')
    sel_op = fn.fetch(:ops).find { |op| op.fetch(:result_refs).include?('%sel') }

    expect(sel_op.fetch(:kind)).to eq(:constant)
    expect(sel_op.fetch(:value)).to eq(11)
  end
end
