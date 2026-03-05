# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe RHDL::CLI::Tasks::BenchmarkTask do
  describe 'initialization' do
    it 'can be instantiated with no options' do
      expect { described_class.new }.not_to raise_error
    end

    it 'can be instantiated with type: :gates' do
      expect { described_class.new(type: :gates) }.not_to raise_error
    end

    it 'can be instantiated with type: :tests' do
      expect { described_class.new(type: :tests) }.not_to raise_error
    end

    it 'can be instantiated with type: :timing' do
      expect { described_class.new(type: :timing) }.not_to raise_error
    end

    it 'can be instantiated with type: :quick' do
      expect { described_class.new(type: :quick) }.not_to raise_error
    end

    it 'can be instantiated with lanes option' do
      expect { described_class.new(type: :gates, lanes: 8) }.not_to raise_error
    end

    it 'can be instantiated with cycles option' do
      expect { described_class.new(type: :gates, cycles: 1000) }.not_to raise_error
    end

    it 'can be instantiated with count option' do
      expect { described_class.new(type: :tests, count: 10) }.not_to raise_error
    end

    it 'can be instantiated with pattern option' do
      expect { described_class.new(type: :tests, pattern: 'spec/rhdl/') }.not_to raise_error
    end
  end

  describe '#run' do
    context 'with type: :gates' do
      it 'starts gate benchmark without error' do
        task = described_class.new(type: :gates, lanes: 2, cycles: 10)
        expect { task.run }.to output(/Gate-level Simulation Benchmark/).to_stdout
      end

      it 'respects lanes and cycles parameters' do
        task = described_class.new(type: :gates, lanes: 4, cycles: 50)
        expect { task.run }.to output(/Lanes: 4/).to_stdout
      end
    end

    context 'with type: :web_apple2' do
      it 'dispatches to benchmark_web_apple2' do
        task = described_class.new(type: :web_apple2)
        expect(task).to receive(:benchmark_web_apple2)
        task.run
      end
    end

    context 'with type: :web_riscv' do
      it 'dispatches to benchmark_web_riscv' do
        task = described_class.new(type: :web_riscv)
        expect(task).to receive(:benchmark_web_riscv)
        task.run
      end
    end

    context 'with type: :cpu8bit' do
      it 'dispatches to benchmark_cpu8bit' do
        task = described_class.new(type: :cpu8bit)
        expect(task).to receive(:benchmark_cpu8bit)
        task.run
      end
    end

    context 'with type: :gem_metal' do
      it 'dispatches to benchmark_gem_metal' do
        task = described_class.new(type: :gem_metal)
        expect(task).to receive(:benchmark_gem_metal)
        task.run
      end
    end

    context 'with type: :gem_metal_cpu8bit' do
      it 'dispatches to benchmark_gem_metal_cpu8bit' do
        task = described_class.new(type: :gem_metal_cpu8bit)
        expect(task).to receive(:benchmark_gem_metal_cpu8bit)
        task.run
      end
    end

    context 'with type: :gem_metal_apple2' do
      it 'dispatches to benchmark_gem_metal_apple2' do
        task = described_class.new(type: :gem_metal_apple2)
        expect(task).to receive(:benchmark_gem_metal_apple2)
        task.run
      end
    end

  end

  describe '#benchmark_gates' do
    it 'runs gate benchmark and reports results' do
      task = described_class.new(type: :gates, lanes: 2, cycles: 10)
      expect { task.benchmark_gates }.to output(/Result:/).to_stdout
    end
  end

  describe '#benchmark_cpu8bit' do
    it 'maps arc filter alias to the arcilator_gpu runner' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV['RHDL_BENCH_BACKENDS'] = 'arc'

      task = described_class.new(type: :cpu8bit, cycles: 16, batch_size: 8)
      memory = double('memory', load: true)
      harness = double('fast_harness', memory: memory, pc: 0, run_cycles: 16, parallel_instances: 1, :"pc=" => true)

      allow(RHDL::HDL::CPU::FastHarness).to receive(:arcilator_gpu_status).and_return({ ready: true })
      allow(RHDL::HDL::CPU::FastHarness).to receive(:new).with(nil, sim: :arcilator_gpu).and_return(harness)

      expect { task.benchmark_cpu8bit }.to output(/ArcilatorGPU/).to_stdout
      expect(RHDL::HDL::CPU::FastHarness).to have_received(:new).with(nil, sim: :arcilator_gpu)
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end

    it 'reports effective throughput when runner has parallel instances' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV['RHDL_BENCH_BACKENDS'] = 'arc'

      task = described_class.new(type: :cpu8bit, cycles: 16, batch_size: 8)
      memory = double('memory', load: true)
      harness = double('fast_harness', memory: memory, pc: 0, run_cycles: 16, parallel_instances: 8, :"pc=" => true)

      allow(RHDL::HDL::CPU::FastHarness).to receive(:arcilator_gpu_status).and_return({ ready: true })
      allow(RHDL::HDL::CPU::FastHarness).to receive(:new).with(nil, sim: :arcilator_gpu).and_return(harness)

      output = capture_stdout { task.benchmark_cpu8bit }
      expect(output).to match(/Instances:\s+8/)
      expect(output).to include('Effective:')
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end
  end

  describe 'environment variables' do
    it 'respects RHDL_BENCH_LANES environment variable' do
      original_lanes = ENV['RHDL_BENCH_LANES']
      ENV['RHDL_BENCH_LANES'] = '16'

      task = described_class.new(type: :gates, cycles: 10)
      expect { task.benchmark_gates }.to output(/Lanes: 16/).to_stdout

      ENV['RHDL_BENCH_LANES'] = original_lanes
    end

    it 'respects RHDL_BENCH_CYCLES environment variable' do
      original_cycles = ENV['RHDL_BENCH_CYCLES']
      ENV['RHDL_BENCH_CYCLES'] = '200'

      task = described_class.new(type: :gates, lanes: 2)
      expect { task.benchmark_gates }.to output(/Cycles: 200/).to_stdout

      ENV['RHDL_BENCH_CYCLES'] = original_cycles
    end
  end

  describe 'private methods' do
    let(:task) { described_class.new(type: :tests) }

    describe '#rspec_cmd' do
      it 'returns a command string' do
        cmd = task.send(:rspec_cmd)
        expect(cmd).to be_a(String)
      end
    end

    describe '#prepare_web_riscv_wasm_backends' do
      it 'includes verilator backend when riscv_verilator.wasm exists' do
        benchmark_task_path = described_class.instance_method(:prepare_web_riscv_wasm_backends).source_location.first
        project_root = File.expand_path('../../../..', File.dirname(benchmark_task_path))
        verilator_wasm = File.join(project_root, 'web', 'assets', 'pkg', 'riscv_verilator.wasm')

        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(verilator_wasm).and_return(true)

        backends = task.send(:prepare_web_riscv_wasm_backends, [:verilator])
        expect(backends).to contain_exactly(
          include(
            name: 'Verilator',
            wasm_path: verilator_wasm,
            ir_json_path: nil
          )
        )
      end
    end

    describe '#disable_riscv_mmu_for_gem_rtl' do
      it 'forces satp_translate low and replaces TLB instances with constants' do
        rtl = <<~VERILOG
          module riscv_cpu;
            wire itlb__hit;
            wire [19:0] itlb__ppn;
            wire itlb__perm_r;
            wire itlb__perm_w;
            wire itlb__perm_x;
            wire itlb__perm_u;
            wire dtlb__hit;
            wire [19:0] dtlb__ppn;
            wire dtlb__perm_r;
            wire dtlb__perm_w;
            wire dtlb__perm_x;
            wire dtlb__perm_u;
            assign satp_translate = some_expr;
            riscv_sv32_tlb itlb (
              .hit(itlb__hit),
              .ppn(itlb__ppn),
              .perm_r(itlb__perm_r),
              .perm_w(itlb__perm_w),
              .perm_x(itlb__perm_x),
              .perm_u(itlb__perm_u)
            );
            riscv_sv32_tlb dtlb (
              .hit(dtlb__hit),
              .ppn(dtlb__ppn),
              .perm_r(dtlb__perm_r),
              .perm_w(dtlb__perm_w),
              .perm_x(dtlb__perm_x),
              .perm_u(dtlb__perm_u)
            );
          endmodule
        VERILOG

        patched = task.send(:disable_riscv_mmu_for_gem_rtl, rtl)
        expect(patched).to include("assign satp_translate = 1'b0;")
        expect(patched).to include("assign itlb__hit = 1'b0;")
        expect(patched).to include("assign dtlb__hit = 1'b0;")
        expect(patched).not_to include('riscv_sv32_tlb itlb')
        expect(patched).not_to include('riscv_sv32_tlb dtlb')
      end
    end
  end

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
