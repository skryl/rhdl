# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'
require 'tmpdir'

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

    it 'runs GemMetal by default alongside the other runners' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV.delete('RHDL_BENCH_BACKENDS')

      stub_const('RHDL::Codegen::IR::IR_COMPILER_AVAILABLE', false)
      allow(RHDL::HDL::CPU::FastHarness).to receive(:arcilator_gpu_status).and_return({ ready: false })

      task = described_class.new(type: :cpu8bit, cycles: 16, batch_size: 8)
      allow(task).to receive(:benchmark_gem_metal_cpu8bit).with(cycles: 16, standalone: false).and_return(
        {
          name: 'GemMetal',
          status: :success,
          init_time: 0.25,
          run_time: 0.5,
          cycles_per_sec: 32.0
        }
      )

      output = capture_stdout { task.benchmark_cpu8bit }
      expect(output).to include('GemMetal')
      expect(task).to have_received(:benchmark_gem_metal_cpu8bit).with(cycles: 16, standalone: false)
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end
  end

  describe '#benchmark_apple2' do
    it 'runs GemMetal by default alongside the other runners' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV.delete('RHDL_BENCH_BACKENDS')

      require_relative '../../../../examples/apple2/hdl'
      require_relative '../../../../examples/apple2/utilities/runners/arcilator_gpu_runner'

      rom_fixture = Array.new(0x3000, 0).pack('C*')
      mem_fixture = Array.new(48 * 1024, 0).pack('C*')

      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/appleiigo\.rom|karateka_mem\.bin/).and_return(true)
      allow(File).to receive(:binread).and_call_original
      allow(File).to receive(:binread).with(/appleiigo\.rom/).and_return(rom_fixture)
      allow(File).to receive(:binread).with(/karateka_mem\.bin/).and_return(mem_fixture)
      allow(RHDL::Examples::Apple2::Apple2).to receive(:to_flat_ir).and_return(:ir)
      allow(RHDL::Codegen::IR::IRToJson).to receive(:convert).with(:ir).and_return('{}')
      allow(RHDL::Codegen::IR).to receive(:const_get).and_call_original
      allow(RHDL::Codegen::IR).to receive(:const_get).with(:IR_INTERPRETER_AVAILABLE).and_return(false)
      allow(RHDL::Codegen::IR).to receive(:const_get).with(:IR_JIT_AVAILABLE).and_return(false)
      allow(RHDL::Codegen::IR).to receive(:const_get).with(:IR_COMPILER_AVAILABLE).and_return(false)

      task = described_class.new(type: :apple2, cycles: 16)
      allow(task).to receive(:verilator_available?).and_return(false)
      allow(task).to receive(:arcilator_available?).and_return(false)
      allow(RHDL::Examples::Apple2::ArcilatorGpuRunner).to receive(:available?).and_return(false)
      allow(task).to receive(:benchmark_gem_metal_apple2).with(cycles: 16, standalone: false).and_return(
        {
          name: 'GemMetal',
          status: :success,
          init_time: 0.5,
          run_time: 1.0,
          cycles_per_sec: 16.0
        }
      )

      output = capture_stdout { task.benchmark_apple2 }
      expect(output).to include('GemMetal')
      expect(task).to have_received(:benchmark_gem_metal_apple2).with(cycles: 16, standalone: false)
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end
  end

  describe '#benchmark_riscv' do
    it 'runs GemMetal by default alongside the other runners' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV.delete('RHDL_BENCH_BACKENDS')

      require_relative '../../../../examples/riscv/utilities/runners/headless_runner'
      require_relative '../../../../examples/riscv/utilities/runners/arcilator_gpu_runner'

      stub_const('RHDL::Codegen::IR::IR_COMPILER_AVAILABLE', false)
      task = described_class.new(type: :riscv, cycles: 16)

      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/xv6_kernel\.bin|xv6_fs\.img/).and_return(true)
      allow(task).to receive(:verilator_available?).and_return(false)
      allow(task).to receive(:arcilator_available?).and_return(false)
      allow(RHDL::Examples::RISCV::ArcilatorGpuRunner).to receive(:available?).and_return(false)
      allow(task).to receive(:benchmark_gem_metal_riscv).with(cycles: 16, standalone: false).and_return(
        {
          name: 'GemMetal',
          status: :success,
          init_time: 0.5,
          run_time: 1.0,
          cycles_per_sec: 16.0
        }
      )

      output = capture_stdout { task.benchmark_riscv }

      expect(output).to include('GemMetal')
      expect(task).to have_received(:benchmark_gem_metal_riscv).with(cycles: 16, standalone: false)
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end

    it 'marks ArcilatorGPU as failed when xv6 never establishes a non-zero PC' do
      original_filter = ENV['RHDL_BENCH_BACKENDS']
      ENV['RHDL_BENCH_BACKENDS'] = 'arcilator_gpu'

      require_relative '../../../../examples/riscv/utilities/runners/headless_runner'
      require_relative '../../../../examples/riscv/utilities/runners/arcilator_gpu_runner'

      task = described_class.new(type: :riscv, cycles: 16)
      runner = instance_double(RHDL::Examples::RISCV::HeadlessRunner)

      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(/xv6_kernel\.bin|xv6_fs\.img/).and_return(true)
      allow(RHDL::Examples::RISCV::ArcilatorGpuRunner).to receive(:available?).and_return(true)
      allow(RHDL::Examples::RISCV::HeadlessRunner).to receive(:new).with(mode: :arcilator_gpu, core: :single).and_return(runner)
      allow(runner).to receive(:load_xv6)
      allow(runner).to receive(:run_steps)
      allow(runner).to receive(:cpu_state).and_return({ pc: 0 })

      output = capture_stdout { task.benchmark_riscv }

      expect(output).to include('ArcilatorGPU')
      expect(output).to include('FAILED')
      expect(output).to match(/PC remained 0x0/i)
    ensure
      ENV['RHDL_BENCH_BACKENDS'] = original_filter
    end
  end

  describe '#benchmark_gem_metal_riscv' do
    it 'generates a yosys script with MMU disabled and a single explicit abc liberty mapping pass' do
      task = described_class.new(type: :riscv, cycles: 16)
      benchmark_task_path = described_class.instance_method(:benchmark_gem_metal_riscv).source_location.first
      project_root = File.expand_path('../../../..', File.dirname(benchmark_task_path))
      gem_root = File.join(project_root, 'external', 'GEM')
      aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')

      Dir.mktmpdir('gem_metal_riscv') do |build_dir|
        original_build_dir = ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR']
        ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR'] = build_dir

        netlist_path = File.join(build_dir, 'riscv_gatelevel.gv')
        gemparts_path = File.join(build_dir, 'riscv.gemparts')
        File.write(gemparts_path, "parts\n")

        allow(task).to receive(:command_available?) { |cmd| %w[cargo yosys].include?(cmd) }
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(gem_root).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(aigpdk_nomem_lib).and_return(true)

        require_relative '../../../../examples/riscv/hdl/cpu'
        allow(RHDL::Examples::RISCV::CPU).to receive(:to_verilog_hierarchy).and_return(<<~VERILOG)
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

        yosys_status = instance_double(Process::Status, success?: true)
        metal_status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture2e) do |*cmd, **kwargs|
          if cmd == ['yosys', '-q', '-s', File.join(build_dir, 'riscv_gem.ys')]
            File.write(netlist_path, "module riscv_cpu;\nendmodule\n")
            ['', yosys_status]
          elsif cmd.first(5) == ['cargo', 'run', '--release', '--features', 'metal']
            expect(kwargs[:chdir]).to eq(gem_root)
            ["metal_dummy_test: logical_dispatches=1 gpu_dispatches=1 total_ms=1.0 cycles_per_sec=16.0\n", metal_status]
          else
            raise "unexpected command: #{cmd.inspect}"
          end
        end

        capture_stdout { task.benchmark_gem_metal_riscv }

        yosys_script = File.read(File.join(build_dir, 'riscv_gem.ys'))
        rtl = File.read(File.join(build_dir, 'riscv_rtl.v'))
        expect(yosys_script.scan(/abc -liberty/).size).to eq(1)
        expect(yosys_script).not_to include("\ntechmap\n")
        expect(rtl).to include("assign satp_translate = 1'b0;")
        expect(rtl).to include("assign itlb__hit = 1'b0;")
        expect(rtl).to include("assign dtlb__hit = 1'b0;")
        expect(rtl).not_to include('riscv_sv32_tlb itlb')
        expect(rtl).not_to include('riscv_sv32_tlb dtlb')
      ensure
        ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR'] = original_build_dir
      end
    end

    it 'rebuilds stale artifacts when the RISC-V GEM build config is missing' do
      task = described_class.new(type: :riscv, cycles: 16)
      benchmark_task_path = described_class.instance_method(:benchmark_gem_metal_riscv).source_location.first
      project_root = File.expand_path('../../../..', File.dirname(benchmark_task_path))
      gem_root = File.join(project_root, 'external', 'GEM')
      aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')

      Dir.mktmpdir('gem_metal_riscv_stale') do |build_dir|
        original_build_dir = ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR']
        ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR'] = build_dir

        File.write(File.join(build_dir, 'riscv_gatelevel.gv'), "module stale;\nendmodule\n")
        File.write(File.join(build_dir, 'riscv.gemparts'), "stale\n")

        allow(task).to receive(:command_available?) { |cmd| %w[cargo yosys].include?(cmd) }
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(gem_root).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(aigpdk_nomem_lib).and_return(true)

        require_relative '../../../../examples/riscv/hdl/cpu'
        allow(RHDL::Examples::RISCV::CPU).to receive(:to_verilog_hierarchy).and_return(<<~VERILOG)
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

        yosys_status = instance_double(Process::Status, success?: true)
        metal_status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture2e) do |*cmd, **kwargs|
          if cmd == ['yosys', '-q', '-s', File.join(build_dir, 'riscv_gem.ys')]
            File.write(File.join(build_dir, 'riscv_gatelevel.gv'), "module riscv_cpu;\nendmodule\n")
            ['', yosys_status]
          elsif cmd.first(5) == ['cargo', 'run', '--release', '--features', 'metal']
            expect(kwargs[:chdir]).to eq(gem_root)
            ["metal_dummy_test: logical_dispatches=1 gpu_dispatches=1 total_ms=1.0 cycles_per_sec=16.0\n", metal_status]
          else
            raise "unexpected command: #{cmd.inspect}"
          end
        end

        capture_stdout { task.benchmark_gem_metal_riscv }

        expect(RHDL::Examples::RISCV::CPU).to have_received(:to_verilog_hierarchy)
        expect(File.exist?(File.join(build_dir, 'riscv_gem_build_config.json'))).to be(true)
      ensure
        ENV['RHDL_GEM_METAL_RISCV_BUILD_DIR'] = original_build_dir
      end
    end
  end

  describe '#benchmark_gem_metal_apple2' do
    it 'generates a yosys script with a single explicit abc liberty mapping pass' do
      task = described_class.new(type: :apple2, cycles: 16)
      benchmark_task_path = described_class.instance_method(:benchmark_gem_metal_apple2).source_location.first
      project_root = File.expand_path('../../../..', File.dirname(benchmark_task_path))
      gem_root = File.join(project_root, 'external', 'GEM')
      aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')

      Dir.mktmpdir('gem_metal_apple2') do |build_dir|
        original_build_dir = ENV['RHDL_GEM_METAL_APPLE2_BUILD_DIR']
        ENV['RHDL_GEM_METAL_APPLE2_BUILD_DIR'] = build_dir

        netlist_path = File.join(build_dir, 'apple2_gatelevel.gv')
        gemparts_path = File.join(build_dir, 'apple2.gemparts')
        File.write(gemparts_path, "parts\n")

        allow(task).to receive(:command_available?) { |cmd| %w[cargo yosys].include?(cmd) }
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(gem_root).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(aigpdk_nomem_lib).and_return(true)

        require_relative '../../../../examples/apple2/hdl'
        allow(RHDL::Examples::Apple2::Apple2).to receive(:to_verilog_hierarchy).and_return(<<~VERILOG)
          module apple2_apple2;
          endmodule
        VERILOG

        yosys_status = instance_double(Process::Status, success?: true)
        metal_status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture2e) do |*cmd, **kwargs|
          if cmd == ['yosys', '-q', '-s', File.join(build_dir, 'apple2_gem.ys')]
            File.write(netlist_path, "module apple2_apple2;\nendmodule\n")
            ['', yosys_status]
          elsif cmd.first(5) == ['cargo', 'run', '--release', '--features', 'metal']
            expect(kwargs[:chdir]).to eq(gem_root)
            ["metal_dummy_test: logical_dispatches=1 gpu_dispatches=1 total_ms=1.0 cycles_per_sec=16.0\n", metal_status]
          else
            raise "unexpected command: #{cmd.inspect}"
          end
        end

        capture_stdout { task.benchmark_gem_metal_apple2 }

        yosys_script = File.read(File.join(build_dir, 'apple2_gem.ys'))
        expect(yosys_script.scan(/abc -liberty/).size).to eq(1)
        expect(yosys_script).not_to include("\ntechmap\n")
      ensure
        ENV['RHDL_GEM_METAL_APPLE2_BUILD_DIR'] = original_build_dir
      end
    end
  end

  describe '#benchmark_gem_metal_cpu8bit' do
    it 'generates a yosys script with a single explicit abc liberty mapping pass' do
      task = described_class.new(type: :cpu8bit, cycles: 16)
      benchmark_task_path = described_class.instance_method(:benchmark_gem_metal_cpu8bit).source_location.first
      project_root = File.expand_path('../../../..', File.dirname(benchmark_task_path))
      gem_root = File.join(project_root, 'external', 'GEM')
      aigpdk_nomem_lib = File.join(gem_root, 'aigpdk', 'aigpdk_nomem.lib')

      Dir.mktmpdir('gem_metal_cpu8bit') do |build_dir|
        original_build_dir = ENV['RHDL_GEM_METAL_CPU8BIT_BUILD_DIR']
        ENV['RHDL_GEM_METAL_CPU8BIT_BUILD_DIR'] = build_dir

        netlist_path = File.join(build_dir, 'cpu8bit_gatelevel.gv')
        gemparts_path = File.join(build_dir, 'cpu8bit.gemparts')
        File.write(gemparts_path, "parts\n")

        allow(task).to receive(:command_available?) { |cmd| %w[cargo yosys].include?(cmd) }
        allow(Dir).to receive(:exist?).and_call_original
        allow(Dir).to receive(:exist?).with(gem_root).and_return(true)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(aigpdk_nomem_lib).and_return(true)

        require_relative '../../../../examples/8bit/hdl/cpu/cpu'
        allow(RHDL::HDL::CPU::CPU).to receive(:to_verilog_hierarchy).and_return(<<~VERILOG)
          module cpu8bit;
          endmodule
        VERILOG

        yosys_status = instance_double(Process::Status, success?: true)
        metal_status = instance_double(Process::Status, success?: true)
        allow(Open3).to receive(:capture2e) do |*cmd, **kwargs|
          if cmd == ['yosys', '-q', '-s', File.join(build_dir, 'cpu8bit_gem.ys')]
            File.write(netlist_path, "module cpu8bit;\nendmodule\n")
            ['', yosys_status]
          elsif cmd.first(5) == ['cargo', 'run', '--release', '--features', 'metal']
            expect(kwargs[:chdir]).to eq(gem_root)
            ["metal_dummy_test: logical_dispatches=1 gpu_dispatches=1 total_ms=1.0 cycles_per_sec=16.0\n", metal_status]
          else
            raise "unexpected command: #{cmd.inspect}"
          end
        end

        capture_stdout { task.benchmark_gem_metal_cpu8bit }

        yosys_script = File.read(File.join(build_dir, 'cpu8bit_gem.ys'))
        expect(yosys_script.scan(/abc -liberty/).size).to eq(1)
        expect(yosys_script).not_to include("\ntechmap\n")
      ensure
        ENV['RHDL_GEM_METAL_CPU8BIT_BUILD_DIR'] = original_build_dir
      end
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
