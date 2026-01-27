# frozen_string_literal: true

require 'spec_helper'
require 'rhdl/cli'

RSpec.describe 'Rakefile interface' do
  # Test that all rake tasks that use CLI task classes work correctly
  # by running them in dry_run mode and verifying the expected actions

  describe 'deps tasks' do
    it 'deps:install runs DepsTask with install action' do
      task = RHDL::CLI::Tasks::DepsTask.new(dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:install_deps)
    end

    it 'deps:check runs DepsTask with check action' do
      task = RHDL::CLI::Tasks::DepsTask.new(check: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:check_deps)
    end
  end

  describe 'bench tasks' do
    it 'bench:gates runs BenchmarkTask with gates type' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :gates, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:benchmark_gates)
    end

    it 'bench:ir runs BenchmarkTask with ir type' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :ir, cycles: 50_000, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:benchmark_ir)
      expect(result.first[:description]).to include('50000')
    end
  end

  describe 'benchmark tasks' do
    it 'benchmark:timing runs BenchmarkTask with timing type' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :timing, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:benchmark_timing)
    end

    it 'benchmark:quick runs BenchmarkTask with quick type' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :quick, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:benchmark_quick)
    end
  end

  describe 'spec:bench tasks' do
    it 'spec:bench:all runs BenchmarkTask with tests type for all specs' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :tests, pattern: 'spec/', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:benchmark_tests)
      expect(result.first[:pattern]).to eq('spec/')
    end

    it 'spec:bench:lib runs BenchmarkTask with tests type for lib specs' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :tests, pattern: 'spec/rhdl/', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:benchmark_tests)
      expect(result.first[:pattern]).to eq('spec/rhdl/')
    end

    it 'spec:bench:hdl runs BenchmarkTask with tests type for hdl specs' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :tests, pattern: 'spec/rhdl/hdl/', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:benchmark_tests)
      expect(result.first[:pattern]).to eq('spec/rhdl/hdl/')
    end

    it 'spec:bench:mos6502 runs BenchmarkTask with tests type for mos6502 specs' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :tests, pattern: 'spec/examples/mos6502/', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:benchmark_tests)
      expect(result.first[:pattern]).to eq('spec/examples/mos6502/')
    end

    it 'spec:bench:apple2 runs BenchmarkTask with tests type for apple2 specs' do
      task = RHDL::CLI::Tasks::BenchmarkTask.new(type: :tests, pattern: 'spec/examples/apple2/', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.first[:action]).to eq(:benchmark_tests)
      expect(result.first[:pattern]).to eq('spec/examples/apple2/')
    end
  end

  describe 'native tasks' do
    it 'native:build runs NativeTask with build action' do
      task = RHDL::CLI::Tasks::NativeTask.new(build: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to be > 0
      expect(result.first[:action]).to eq(:cargo_build)
      expect(result.first).to have_key(:extension)
      expect(result.first).to have_key(:name)
    end

    it 'native:clean runs NativeTask with clean action' do
      task = RHDL::CLI::Tasks::NativeTask.new(clean: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to be > 0
      expect(result.first[:action]).to eq(:clean_extension)
    end

    it 'native:check runs NativeTask with check action' do
      task = RHDL::CLI::Tasks::NativeTask.new(check: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to be > 0
      expect(result.first[:action]).to eq(:check_extension)
    end
  end

  describe 'gates tasks' do
    it 'gates:export runs GatesTask with export_all action' do
      task = RHDL::CLI::Tasks::GatesTask.new(dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:export_all)
      expect(result.first).to have_key(:output_dir)
    end

    it 'gates:clean runs GatesTask with clean action' do
      task = RHDL::CLI::Tasks::GatesTask.new(clean: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:clean_gates)
    end

    it 'gates:stats runs GatesTask with stats action' do
      task = RHDL::CLI::Tasks::GatesTask.new(stats: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:show_stats)
    end

    it 'gates:simcpu runs GatesTask with simcpu action' do
      task = RHDL::CLI::Tasks::GatesTask.new(simcpu: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:export_simcpu)
    end
  end

  describe 'export tasks' do
    it 'export:all runs ExportTask with all action' do
      task = RHDL::CLI::Tasks::ExportTask.new(all: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:export_all)
      expect(result.first).to have_key(:output_dir)
    end

    it 'export:clean runs ExportTask with clean action' do
      task = RHDL::CLI::Tasks::ExportTask.new(clean: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:clean_verilog)
    end

    it 'export:single runs ExportTask with single action' do
      task = RHDL::CLI::Tasks::ExportTask.new(
        component: 'RHDL::HDL::ALU',
        lang: 'verilog',
        out: '/tmp/test',
        dry_run: true
      )
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:export_single)
      expect(result.first[:component]).to eq('RHDL::HDL::ALU')
    end
  end

  describe 'diagram tasks' do
    it 'diagrams:generate runs DiagramTask with all action' do
      task = RHDL::CLI::Tasks::DiagramTask.new(all: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:generate_all)
      expect(result.first).to have_key(:output_dir)
    end

    it 'diagrams:clean runs DiagramTask with clean action' do
      task = RHDL::CLI::Tasks::DiagramTask.new(clean: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:clean_diagrams)
    end

    it 'diagrams:single runs DiagramTask with single action' do
      task = RHDL::CLI::Tasks::DiagramTask.new(
        component: 'RHDL::HDL::ALU',
        level: 'component',
        format: 'svg',
        out: '/tmp/test',
        dry_run: true
      )
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:generate_single)
      expect(result.first[:component]).to eq('RHDL::HDL::ALU')
    end
  end

  describe 'generate tasks' do
    it 'generate:all runs GenerateTask with generate action' do
      task = RHDL::CLI::Tasks::GenerateTask.new(dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:generate_all)
    end

    it 'generate:clean runs GenerateTask with clean action' do
      task = RHDL::CLI::Tasks::GenerateTask.new(action: :clean, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:clean_all)
    end

    it 'generate:regenerate runs GenerateTask with regenerate action' do
      task = RHDL::CLI::Tasks::GenerateTask.new(action: :regenerate, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:regenerate_all)
    end
  end

  describe 'tui tasks' do
    it 'tui:list runs TuiTask with list action' do
      task = RHDL::CLI::Tasks::TuiTask.new(list: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:list_components)
    end

    it 'tui:run runs TuiTask with run action' do
      task = RHDL::CLI::Tasks::TuiTask.new(component: 'sequential/counter', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_tui)
      expect(result.first[:component]).to eq('sequential/counter')
    end
  end

  describe 'apple2 tasks' do
    it 'apple2:demo runs Apple2Task with demo action' do
      task = RHDL::CLI::Tasks::Apple2Task.new(demo: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_demo)
    end

    it 'apple2:appleiigo runs Apple2Task with appleiigo action' do
      task = RHDL::CLI::Tasks::Apple2Task.new(appleiigo: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_appleiigo)
      expect(result.first).to have_key(:rom)
    end

    it 'apple2:karateka runs Apple2Task with karateka action' do
      task = RHDL::CLI::Tasks::Apple2Task.new(karateka: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_karateka)
    end

    it 'apple2 default runs Apple2Task with emulator action' do
      task = RHDL::CLI::Tasks::Apple2Task.new(rom: '/path/to/rom', mode: :hdl, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_emulator)
    end
  end

  describe 'mos6502 tasks' do
    it 'mos6502:build runs MOS6502Task with build action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(build: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:build_rom)
    end

    it 'mos6502:clean runs MOS6502Task with clean action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(clean: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:clean_rom)
    end

    it 'mos6502:demo runs MOS6502Task with demo action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(demo: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_demo)
    end

    it 'mos6502:appleiigo runs MOS6502Task with appleiigo action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(appleiigo: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_appleiigo)
    end

    it 'mos6502:karateka runs MOS6502Task with karateka action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(karateka: true, dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_karateka)
    end

    it 'mos6502 default runs MOS6502Task with emulator action' do
      task = RHDL::CLI::Tasks::MOS6502Task.new(rom: '/path/to/rom', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:run_emulator)
    end
  end

  describe 'disk tasks' do
    it 'disk:info runs DiskConvertTask with info action' do
      task = RHDL::CLI::Tasks::DiskConvertTask.new(info: true, disk: '/path/to/disk.dsk', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:show_disk_info)
      expect(result.first[:disk]).to eq('/path/to/disk.dsk')
    end

    it 'disk:convert runs DiskConvertTask with convert action' do
      task = RHDL::CLI::Tasks::DiskConvertTask.new(convert: true, disk: '/path/to/disk.dsk', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:convert_disk)
    end

    it 'disk:extract_boot runs DiskConvertTask with extract_boot action' do
      task = RHDL::CLI::Tasks::DiskConvertTask.new(extract_boot: true, disk: '/path/to/disk.dsk', dry_run: true)
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:extract_boot)
    end

    it 'disk:extract_tracks runs DiskConvertTask with extract_tracks action' do
      task = RHDL::CLI::Tasks::DiskConvertTask.new(
        extract_tracks: true,
        disk: '/path/to/disk.dsk',
        start_track: 0,
        end_track: 2,
        dry_run: true
      )
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:extract_tracks)
    end

    it 'disk:dump_after_boot runs DiskConvertTask with dump_after_boot action' do
      task = RHDL::CLI::Tasks::DiskConvertTask.new(
        dump_after_boot: true,
        disk: '/path/to/disk.dsk',
        rom: '/path/to/rom',
        dry_run: true
      )
      result = task.run

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:action]).to eq(:dump_after_boot)
    end
  end

  describe 'dry_run option inheritance' do
    it 'Task base class provides dry_run? method' do
      task = RHDL::CLI::Task.new(dry_run: true)
      expect(task.dry_run?).to be true

      task = RHDL::CLI::Task.new
      expect(task.dry_run?).to be false
    end

    it 'Task base class provides would method for recording actions' do
      task = RHDL::CLI::Task.new(dry_run: true)
      task.would(:test_action, foo: 'bar')
      expect(task.dry_run_output).to eq([{ action: :test_action, foo: 'bar' }])
    end

    it 'ensure_dir is a no-op in dry_run mode' do
      task = RHDL::CLI::Task.new(dry_run: true)
      # Should not raise or create directory
      expect { task.send(:ensure_dir, '/nonexistent/path/that/should/not/be/created') }.not_to raise_error
    end
  end
end
