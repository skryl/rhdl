# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../examples/ao486/utilities/runners/headless_runner'

RSpec.describe RHDL::Examples::AO486::HeadlessRunner do
  let(:text_base) { RHDL::Examples::AO486::DisplayAdapter::TEXT_BASE }

  it 'defaults to compiler-backed IR mode' do
    runner = described_class.new(headless: true)

    expect(runner.mode).to eq(:ir)
    expect(runner.sim_backend).to eq(:compile)
    expect(runner.state[:backend]).to eq(:ir)
  end

  it 'loads BIOS ROMs from examples/ao486/software/rom into mapped ROM windows' do
    runner = described_class.new(headless: true)
    boot0_path = runner.bios_paths.fetch(:boot0)
    boot1_path = runner.bios_paths.fetch(:boot1)
    boot0_bytes = File.binread(boot0_path, 8).bytes
    boot1_bytes = File.binread(boot1_path, 8).bytes

    runner.load_bios

    expect(runner.runner.read_bytes(RHDL::Examples::AO486::BackendRunner::BOOT0_ADDR, 8)).to eq(boot0_bytes)
    expect(runner.runner.read_bytes(RHDL::Examples::AO486::BackendRunner::BOOT1_ADDR, 8)).to eq(boot1_bytes)
    expect(runner.state[:bios_loaded]).to be(true)
  end

  it 'loads the persistent DOS floppy image from examples/ao486/software/bin' do
    runner = described_class.new(headless: true)

    runner.load_dos

    expect(runner.state[:dos_loaded]).to be(true)
    expect(runner.state[:floppy_image_size]).to eq(File.size(runner.dos_path))
  end

  it 'forwards custom DOS slot loads and swaps through the shared headless runner surface' do
    runner = described_class.new(headless: true)
    backend = instance_double(
      'AO486Backend',
      last_run_stats: nil,
      state: {
        backend: :ir,
        sim_backend: :compile,
        cycles_run: 0,
        bios_loaded: false,
        dos_loaded: true,
        floppy_image_size: 368_640,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        cursor: { row: 0, col: 0, page: 0 },
        active_floppy_slot: 1,
        floppy_slots: {
          0 => { path: '/tmp/disk1.img', size: 368_640 },
          1 => { path: '/tmp/disk2.img', size: 368_640 }
        }
      }
    )
    allow(backend).to receive(:load_dos).and_return(path: '/tmp/disk2.img', size: 368_640, slot: 1, active: false)
    allow(backend).to receive(:swap_dos).and_return(path: '/tmp/disk2.img', size: 368_640, slot: 1, active: true)
    runner.instance_variable_set(:@runner, backend)

    expect(runner.load_dos(path: '/tmp/disk2.img', slot: 1, activate: false)).to be(runner)
    expect(runner.swap_dos(1)).to be(runner)
    expect(backend).to have_received(:load_dos).with(path: '/tmp/disk2.img', slot: 1, activate: false)
    expect(backend).to have_received(:swap_dos).with(1)
    expect(runner.state[:active_floppy_slot]).to eq(1)
    expect(runner.state[:floppy_slots]).to eq(
      0 => { path: '/tmp/disk1.img', size: 368_640 },
      1 => { path: '/tmp/disk2.img', size: 368_640 }
    )
  end

  it 'formats a shared hex/ascii memory dump through the headless runner surface' do
    runner = described_class.new(headless: true)
    runner.load_bytes(0x0600, [0x41, 0x42, 0x00, 0x7F, 0x20])

    dump = runner.dump_memory(0x0600, 5, mapped: false, bytes_per_row: 4)

    expect(dump.lines[0].chomp).to eq('00000600  41 42 00 7F  AB..')
    expect(dump.lines[1].chomp).to eq('00000604  20            ')
  end

  it 'passes through backend PC snapshot fields in headless state' do
    runner = described_class.new(headless: true)
    backend = instance_double(
      'AO486Backend',
      last_run_stats: nil,
      state: {
        backend: :ir,
        sim_backend: :compile,
        cycles_run: 12_345,
        bios_loaded: true,
        dos_loaded: true,
        floppy_image_size: 1_474_560,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        cursor: { row: 0, col: 7, page: 0 },
        pc: {
          trace: 0x7DCE,
          decode: 0x7DD0,
          read: 0x7DD0,
          execute: 0x7DD0,
          arch: 0x7DD0
        },
        exception_vector: 0x13,
        exception_eip: 0x7DCE,
        interrupt_done: 0,
        arch: {
          eax: 0x0201,
          ebx: 0x0000,
          ecx: 0x0013,
          edx: 0x0100,
          esi: 0x0000,
          edi: 0x0000,
          esp: 0x7B9B,
          ebp: 0x7C00,
          eip: 0x7DD0
        },
        active_video_page: 0,
        dos_bridge: {
          int13: { ax: 0x0201, bx: 0x0000, cx: 0x0013, dx: 0x0100, es: 0x01C0, result_ax: 0x0001, flags: 0 },
          int10: { ax: 0x0E46, result_ax: 0x0E46 },
          int16: { ax: 0x0000, result_ax: 0x0000, flags: 0 },
          int1a: { ax: 0x0000, result_ax: 0x0000, flags: 0 }
        }
      }
    )
    runner.instance_variable_set(:@runner, backend)

    snapshot = runner.state

    expect(snapshot[:pc]).to eq(
      trace: 0x7DCE,
      decode: 0x7DD0,
      read: 0x7DD0,
      execute: 0x7DD0,
      arch: 0x7DD0
    )
    expect(snapshot[:exception_vector]).to eq(0x13)
    expect(snapshot[:exception_eip]).to eq(0x7DCE)
    expect(snapshot[:interrupt_done]).to eq(0)
    expect(snapshot[:arch]).to eq(
      eax: 0x0201,
      ebx: 0x0000,
      ecx: 0x0013,
      edx: 0x0100,
      esi: 0x0000,
      edi: 0x0000,
      esp: 0x7B9B,
      ebp: 0x7C00,
      eip: 0x7DD0
    )
    expect(snapshot[:active_video_page]).to eq(0)
    expect(snapshot[:dos_bridge]).to eq(
      int13: { ax: 0x0201, bx: 0x0000, cx: 0x0013, dx: 0x0100, es: 0x01C0, result_ax: 0x0001, flags: 0 },
      int10: { ax: 0x0E46, result_ax: 0x0E46 },
      int16: { ax: 0x0000, result_ax: 0x0000, flags: 0 },
      int1a: { ax: 0x0000, result_ax: 0x0000, flags: 0 }
    )
  end

  it 'formats a compact AO486 progress line from backend state' do
    runner = described_class.new(headless: true)
    backend = instance_double(
      'AO486Backend',
      last_run_stats: nil,
      state: {
        backend: :verilator,
        cycles_run: 200_000,
        bios_loaded: true,
        dos_loaded: true,
        floppy_image_size: 1_474_560,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        last_irq: 0x08,
        last_io: { address: 0x0EDA, length: 1, data: 0x0100 },
        interrupt_done: 0,
        cursor: { row: 0, col: 7, page: 0 },
        pc: {
          trace: 0x7DCE,
          decode: 0x7DD0,
          read: 0x7DD0,
          execute: 0x7DD0,
          arch: 0x7DD0
        },
        arch: {
          eax: 0x0201,
          ebx: 0x0000,
          ecx: 0x000D,
          edx: 0x0100,
          esi: 0x0EE0,
          edi: 0x7E04,
          esp: 0x0EDD,
          ebp: 0x7B9C,
          eip: 0x7DD0
        },
        exception_vector: 0x13,
        exception_eip: 0x7DCE,
        dos_bridge: {
          int13: { ax: 0x0201, bx: 0x0000, cx: 0x000D, dx: 0x0100, es: 0x01C0, result_ax: 0x0001, flags: 0 }
        }
      }
    )
    runner.instance_variable_set(:@runner, backend)
    allow(runner).to receive(:read_text_screen).and_return("FreeDOS_\n")

    progress = runner.progress_line

    expect(progress).to include('cyc=200000')
    expect(progress).to include('pc[t/d/r/x/a]=0x00007DCE/0x00007DD0/0x00007DD0/0x00007DD0/0x00007DD0')
    expect(progress).to include('exc=0x13@0x00007DCE')
    expect(progress).to include('irq=0x08')
    expect(progress).to include('io=0x0EDA/1=0x00000100')
    expect(progress).to include('dos13=ax=0x0201 es:bx=0x01C0:0x0000 cx=0x000D dx=0x0100')
    expect(progress).to include('shell=0')
    expect(progress).to include('line0="FreeDOS_"')
  end

  it 'passes through backend cyc/s benchmark stats in headless state' do
    runner = described_class.new(headless: true)
    backend = instance_double(
      'AO486Backend',
      last_run_stats: {
        backend: :compile,
        operation: :run_final_state,
        cycles: 256,
        elapsed_seconds: 0.002,
        cycles_per_second: 128_000.0
      },
      state: {
        backend: :ir,
        sim_backend: :compile,
        cycles_run: 256,
        bios_loaded: false,
        dos_loaded: false,
        floppy_image_size: 0,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        cursor: { row: 0, col: 0, page: 0 }
      }
    )
    runner.instance_variable_set(:@runner, backend)

    expect(runner.last_run_stats).to eq(
      backend: :compile,
      operation: :run_final_state,
      cycles: 256,
      elapsed_seconds: 0.002,
      cycles_per_second: 128_000.0
    )
    expect(runner.state[:last_run_stats]).to eq(
      backend: :compile,
      operation: :run_final_state,
      cycles: 256,
      elapsed_seconds: 0.002,
      cycles_per_second: 128_000.0
    )
  end

  it 'renders text mode content with debug state below the display' do
    runner = described_class.new(headless: true, debug: true, speed: 1234)
    runner.load_bytes(text_base, ['O'.ord, 0x07, 'K'.ord, 0x07])
    runner.load_bytes(RHDL::Examples::AO486::DisplayAdapter::CURSOR_BDA, [2, 0])

    screen = runner.read_text_screen

    expect(screen).to include('OK')
    expect(screen).to include('Mode:IR')
    expect(screen).to include('Speed:1.2K')
  end

  it 'exposes the same runner contract across all AO486 public modes', timeout: 60 do
    {
      ir: :ir,
      verilog: :verilator,
      circt: :arcilator
    }.each do |mode, backend|
      runner = described_class.new(mode: mode, headless: true, cycles: 1)
      runner.send_keys("dir\r")
      state = runner.run

      expect(state[:effective_mode]).to eq(mode)
      expect(state[:backend]).to eq(backend)
      expect(state[:keyboard_buffer_size]).to be_between(3, 4)
    end
  end

  it 'keeps running backend chunks in interactive mode until interrupted' do
    runner = described_class.new(mode: :verilog, speed: 10_000)
    backend = instance_double(
      'AO486Backend',
      cycles_run: 20_000,
      last_run_stats: nil,
      state: {
        backend: :verilator,
        cycles_run: 20_000,
        bios_loaded: false,
        dos_loaded: false,
        floppy_image_size: 0,
        keyboard_buffer_size: 0,
        shell_prompt_detected: false,
        native: true,
        cursor: { row: 0, col: 0 }
      }
    )

    allow(backend).to receive(:run)
    runner.instance_variable_set(:@runner, backend)
    allow(runner).to receive(:read_text_screen).and_return("frame")
    allow(runner).to receive(:setup_terminal_input_mode).and_return(nil)
    allow(runner).to receive(:restore_terminal_input_mode)
    allow(runner).to receive(:sleep)
    allow(runner).to receive(:print)
    allow($stdout).to receive(:tty?).and_return(true)
    allow($stdout).to receive(:flush)

    iterations = 0
    allow(runner).to receive(:handle_keyboard_input) do |running_flag:|
      iterations += 1
      running_flag.call if iterations == 2
    end

    result = runner.run

    expect(backend).to have_received(:run).with(cycles: nil, speed: 10_000, headless: false).twice
    expect(result[:cycles]).to eq(20_000)
  end
end
