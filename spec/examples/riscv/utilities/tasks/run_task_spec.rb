# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../../../examples/riscv/utilities/tasks/run_task'

RSpec.describe RHDL::Examples::RISCV::Tasks::RunTask do
  let(:program_file) do
    Tempfile.new(['riscv_prog', '.bin']).tap do |f|
      f.binmode
      # addi x1, x0, 1 ; addi x2, x0, 2
      f.write([0x93, 0x00, 0x10, 0x00, 0x13, 0x01, 0x20, 0x00].pack('C*'))
      f.flush
    end
  end

  after do
    program_file.close!
  end

  def build_task(options = {})
    described_class.new({ headless: true, cycles: 2 }.merge(options))
  rescue LoadError, RuntimeError => e
    skip "Backend unavailable for this environment: #{e.message}"
  end

  describe '#initialize' do
    it 'accepts options hash and stores mode/backend/io' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart, debug: true)
      expect(task.instance_variable_get(:@mode)).to eq(:ruby)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:ruby)
      expect(task.instance_variable_get(:@io_mode)).to eq(:uart)
      expect(task.instance_variable_get(:@debug)).to eq(true)
    end

    it 'defaults to ir mode and compile sim backend' do
      task = build_task
      expect(task.instance_variable_get(:@mode)).to eq(:ir)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:compile)
    end

    it 'creates HeadlessRunner internally' do
      task = build_task(mode: :ruby, sim: :ruby)
      expect(task.runner).to be_a(RHDL::Examples::RISCV::HeadlessRunner)
      expect(task.cpu).to equal(task.runner.cpu)
    end

    it 'accepts mmap geometry options' do
      task = build_task(mode: :ruby, sim: :ruby, mmap_width: 64, mmap_height: 12, mmap_stride: 96, mmap_start: 0x1000)
      expect(task.instance_variable_get(:@mmap_width)).to eq(64)
      expect(task.instance_variable_get(:@mmap_height)).to eq(12)
      expect(task.instance_variable_get(:@mmap_row_stride)).to eq(96)
      expect(task.instance_variable_get(:@mmap_start)).to eq(0x1000)
    end
  end

  describe 'run options integration' do
    run_cases = [
      { mode: :ruby, sim: :ruby, io: :mmap, debug: false },
      { mode: :ruby, sim: :interpret, io: :mmap, debug: false },
      { mode: :ruby, sim: :jit, io: :uart, debug: false },
      { mode: :ruby, sim: :compile, io: :uart, debug: true },
      { mode: :ir, sim: :interpret, io: :mmap, debug: false },
      { mode: :ir, sim: :jit, io: :mmap, debug: false },
      { mode: :ir, sim: :compile, io: :uart, debug: true },
      { mode: :netlist, sim: :compile, io: :mmap, debug: false },
      { mode: :verilog, sim: :ruby, io: :mmap, debug: false }
    ].freeze

    run_cases.each do |test_case|
      it "runs headless with #{test_case}" do
        task = build_task(test_case.merge(cycles: 1))
        task.load_program(program_file.path, base_addr: 0x0)
        task.set_pc(0x0)

        expect { task.run }.not_to raise_error

        state = task.cpu.state
        expect(state).to include(:pc, :cycles, :inst)
        expect(state[:cycles]).to be >= 1
      end
    end
  end

  describe 'uart input processing' do
    it 'stops running when Ctrl+C byte is seen in input stream' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart)
      task.instance_variable_set(:@running, true)
      bytes = task.send(:process_input_bytes, [0x61, 0x03, 0x62])

      expect(task.instance_variable_get(:@running)).to eq(false)
      expect(bytes).to eq([0x61])
    end

    it 'normalizes CR and DEL for UART RX bytes' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart)
      task.instance_variable_set(:@running, true)
      bytes = task.send(:process_input_bytes, [0x0D, 0x7F, 0x41])

      expect(task.instance_variable_get(:@running)).to eq(true)
      expect(bytes).to eq([0x0A, 0x08, 0x41])
    end

    it 'toggles keyboard command mode on ESC when debug is enabled' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart, debug: true)

      expect(task.instance_variable_get(:@keyboard_mode)).to eq(:normal)
      task.send(:handle_esc_key)
      expect(task.instance_variable_get(:@keyboard_mode)).to eq(:command)
      task.send(:handle_esc_key)
      expect(task.instance_variable_get(:@keyboard_mode)).to eq(:normal)
    end
  end

  describe 'uart display buffering' do
    it 'resets column to 0 on newline so lines do not drift right' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart)
      task.send(:apply_uart_bytes, "ab\ncd\n".bytes)

      cells = task.instance_variable_get(:@uart_cells)
      expect(cells[0][0, 2].join).to eq('ab')
      expect(cells[1][0, 2].join).to eq('cd')
      expect(task.instance_variable_get(:@uart_col)).to eq(0)
    end
  end

  describe 'interactive cycle stepping' do
    it 'runs frame work in bounded chunks' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart)
      calls = []
      cpu = instance_double('CPU')
      allow(cpu).to receive(:run_cycles) { |n| calls << n }

      task.instance_variable_set(:@cpu, cpu)
      task.instance_variable_set(:@running, true)
      task.instance_variable_set(:@cycles_per_frame, 5_000)
      task.instance_variable_set(:@cycle_chunk, 1_000)
      task.instance_variable_set(:@cycle_budget, 0)

      frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      task.send(:run_cpu_budgeted, frame_start)

      expect(calls).not_to be_empty
      expect(calls.all? { |value| value <= 1_000 }).to eq(true)
      expect(calls.sum).to eq(5_000)
    end

    it 'stops chunk loop quickly when running flag flips false' do
      task = build_task(mode: :ruby, sim: :ruby, io: :uart)
      calls = []
      cpu = instance_double('CPU')
      allow(cpu).to receive(:run_cycles) do |n|
        calls << n
        task.instance_variable_set(:@running, false)
      end

      task.instance_variable_set(:@cpu, cpu)
      task.instance_variable_set(:@running, true)
      task.instance_variable_set(:@cycles_per_frame, 10_000)
      task.instance_variable_set(:@cycle_chunk, 1_000)
      task.instance_variable_set(:@cycle_budget, 0)

      frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      task.send(:run_cpu_budgeted, frame_start)

      expect(calls.length).to eq(1)
      expect(calls.first).to eq(1_000)
    end
  end
end

RSpec.describe RHDL::Examples::RISCV::HeadlessRunner do
  let(:program_bytes) { [0x93, 0x00, 0x10, 0x00].pack('C*') } # addi x1, x0, 1

  describe '#initialize' do
    it 'defaults to ir mode and compile backend' do
      runner = described_class.new
      expect(runner.mode).to eq(:ir)
      expect(runner.sim_backend).to eq(:compile)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::IRHarness)
    end

    it 'accepts ruby-mode sim backend options' do
      [:ruby, :interpret, :jit, :compile].each do |sim_backend|
        runner = described_class.new(mode: :ruby, sim: sim_backend)
        expect(runner.sim_backend).to eq(sim_backend)
      rescue LoadError, RuntimeError => e
        skip "Backend #{sim_backend} unavailable: #{e.message}"
      end
    end

    it 'falls back netlist mode to ir effective mode' do
      runner = described_class.new(mode: :netlist, sim: :compile)
      expect(runner.mode).to eq(:netlist)
      expect(runner.effective_mode).to eq(:ir)
    rescue LoadError, RuntimeError => e
      skip "Backend unavailable for netlist fallback: #{e.message}"
    end

    it 'falls back verilog mode to ir effective mode' do
      runner = described_class.new(mode: :verilog, sim: :ruby)
      expect(runner.mode).to eq(:verilog)
      expect(runner.effective_mode).to eq(:ir)
    rescue LoadError, RuntimeError => e
      skip "Backend unavailable for verilog fallback: #{e.message}"
    end
  end

  describe 'program execution' do
    it 'loads bytes and advances cycles' do
      runner = described_class.new(mode: :ruby, sim: :ruby)
      runner.load_program_bytes(program_bytes, base_addr: 0x0)
      runner.set_pc(0x0)
      before = runner.cycle_count
      runner.run_steps(1)
      after = runner.cycle_count

      expect(after).to be > before
      expect(runner.cpu_state).to include(:pc, :cycles, :inst)
    end
  end

  describe 'xv6 fast-boot patching' do
    it 'rewrites PHYSTOP LUI immediate from 0x88000 to 0x80200' do
      runner = described_class.new(mode: :ruby, sim: :ruby)
      rd = 7
      target_word = (0x88000 << 12) | (rd << 7) | 0x37
      other_word = (0x12345 << 12) | (3 << 7) | 0x37
      bytes = [target_word, other_word].pack('V*')

      patches = runner.send(:patch_phystop_for_fast_boot!, bytes)
      words = bytes.unpack('V*')

      expect(patches).to eq(1)
      expect((words[0] >> 12) & 0xFFFFF).to eq(0x80200)
      expect((words[0] >> 7) & 0x1F).to eq(rd)
      expect(words[1]).to eq(other_word)
    end
  end
end
