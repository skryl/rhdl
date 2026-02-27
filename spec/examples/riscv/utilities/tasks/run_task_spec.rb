# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../../../examples/riscv/utilities/tasks/run_task'
require_relative '../../../../../examples/riscv/utilities/assembler'

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
      expect(task.instance_variable_get(:@core)).to eq(:pipeline)
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

    it 'accepts core selection' do
      task = build_task(core: :single)
      expect(task.instance_variable_get(:@core)).to eq(:single)
    end
  end

  describe '#load_linux' do
    it 'delegates linux artifact loading to headless runner' do
      task = described_class.allocate
      runner = instance_double(RHDL::Examples::RISCV::HeadlessRunner)
      task.instance_variable_set(:@runner, runner)

      expect(runner).to receive(:load_linux).with(
        kernel: 'kernel.bin',
        initramfs: 'initramfs.cpio',
        dtb: 'virt.dtb',
        kernel_addr: 0x8040_0000,
        initramfs_addr: 0x8400_0000,
        dtb_addr: 0x87F0_0000,
        pc: 0x8020_1234
      )

      task.load_linux(
        kernel: 'kernel.bin',
        initramfs: 'initramfs.cpio',
        dtb: 'virt.dtb',
        kernel_addr: 0x8040_0000,
        initramfs_addr: 0x8400_0000,
        dtb_addr: 0x87F0_0000,
        pc: 0x8020_1234
      )
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
      { mode: :verilog, sim: :ruby, io: :mmap, debug: false },
      { mode: :circt, sim: :ruby, io: :mmap, debug: false }
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

  def sign_extend(value, bits)
    masked = value & ((1 << bits) - 1)
    sign_bit = 1 << (bits - 1)
    (masked ^ sign_bit) - sign_bit
  end

  def decode_li_value(words, start_index)
    lui = words.fetch(start_index)
    addi = words.fetch(start_index + 1)
    upper = lui & 0xFFFF_F000
    imm = sign_extend((addi >> 20) & 0xFFF, 12)
    (upper + imm) & 0xFFFF_FFFF
  end

  def find_li_values(words, rd)
    values = []
    words.each_cons(2) do |lui, addi|
      next unless (lui & 0x7F) == 0x37
      next unless ((lui >> 7) & 0x1F) == rd
      next unless (addi & 0x7F) == 0x13
      next unless ((addi >> 7) & 0x1F) == rd
      next unless ((addi >> 15) & 0x1F) == rd

      upper = lui & 0xFFFF_F000
      imm = sign_extend((addi >> 20) & 0xFFF, 12)
      values << ((upper + imm) & 0xFFFF_FFFF)
    end
    values
  end

  describe '#initialize' do
    it 'defaults to ir mode and compile backend' do
      runner = described_class.new
      expect(runner.mode).to eq(:ir)
      expect(runner.sim_backend).to eq(:compile)
      expect(runner.core).to eq(:single)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::IrRunner)
    rescue LoadError, RuntimeError => e
      skip "Default backend unavailable: #{e.message}"
    end

    it 'builds pipeline harness when core is pipeline' do
      runner = described_class.new(core: :pipeline)
      expect(runner.core).to eq(:pipeline)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::IrRunner)
    rescue LoadError, RuntimeError => e
      skip "Pipeline backend unavailable: #{e.message}"
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

    it 'accepts verilog mode without fallback' do
      runner = described_class.new(mode: :verilog)
      expect(runner.mode).to eq(:verilog)
      expect(runner.effective_mode).to eq(:verilog)
    rescue LoadError, RuntimeError => e
      skip "Verilator backend unavailable: #{e.message}"
    end

    it 'accepts circt mode without fallback' do
      runner = described_class.new(mode: :circt)
      expect(runner.mode).to eq(:circt)
      expect(runner.effective_mode).to eq(:circt)
    rescue LoadError, RuntimeError => e
      skip "Arcilator backend unavailable: #{e.message}"
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

  describe '#set_pc fallback behavior' do
    it 'does not raise when write_pc fails but PC already matches target' do
      runner = described_class.allocate
      sim = double('sim')
      cpu = double('cpu')

      allow(cpu).to receive(:write_pc).and_raise(RuntimeError, 'Unknown input: pc_reg__pc')
      allow(cpu).to receive(:read_pc).and_return(0)
      allow(cpu).to receive(:native?).and_return(false)
      allow(cpu).to receive(:sim).and_return(sim)

      runner.instance_variable_set(:@cpu, cpu)

      expect { runner.set_pc(0) }.not_to raise_error
    end

    it 're-raises write_pc error when target PC cannot be established' do
      runner = described_class.allocate
      sim = double('sim')
      cpu = double('cpu')

      allow(cpu).to receive(:write_pc).and_raise(RuntimeError, 'Unknown input: pc_reg__pc')
      allow(cpu).to receive(:read_pc).and_return(4)
      allow(cpu).to receive(:native?).and_return(false)
      allow(cpu).to receive(:sim).and_return(sim)

      runner.instance_variable_set(:@cpu, cpu)

      expect { runner.set_pc(0) }.to raise_error(RuntimeError, /Unknown input: pc_reg__pc/)
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

  describe '#load_linux' do
    def with_temp_binary(bytes)
      file = Tempfile.new(['linux_artifact', '.bin'])
      file.binmode
      file.write(bytes)
      file.flush
      yield file.path, bytes
    ensure
      file.close!
    end

    def build_minimal_dtb_with_initrd_props
      strings = +"linux,initrd-start\0linux,initrd-end\0"
      start_nameoff = 0
      end_nameoff = "linux,initrd-start\0".bytesize

      struct = +''
      struct << [0x0000_0001].pack('N') # FDT_BEGIN_NODE /
      struct << "\0".ljust(4, "\0")
      struct << [0x0000_0001].pack('N') # FDT_BEGIN_NODE chosen
      struct << "chosen\0".ljust(8, "\0")
      struct << [0x0000_0003, 8, start_nameoff].pack('N3') # FDT_PROP linux,initrd-start
      start_value_offset_in_struct = struct.bytesize
      struct << [0, 0].pack('N2')
      struct << [0x0000_0003, 8, end_nameoff].pack('N3') # FDT_PROP linux,initrd-end
      end_value_offset_in_struct = struct.bytesize
      struct << [0, 0].pack('N2')
      struct << [0x0000_0002, 0x0000_0002, 0x0000_0009].pack('N3') # END_NODE chosen, END_NODE /, END

      header_size = 40
      mem_rsv_size = 16
      off_mem_rsvmap = header_size
      off_dt_struct = off_mem_rsvmap + mem_rsv_size
      size_dt_struct = struct.bytesize
      off_dt_strings = off_dt_struct + size_dt_struct
      size_dt_strings = strings.bytesize
      totalsize = off_dt_strings + size_dt_strings

      header = [
        0xD00D_FEED,
        totalsize,
        off_dt_struct,
        off_dt_strings,
        off_mem_rsvmap,
        17,
        16,
        0,
        size_dt_strings,
        size_dt_struct
      ].pack('N10')

      start_value_offset = off_dt_struct + start_value_offset_in_struct
      end_value_offset = off_dt_struct + end_value_offset_in_struct
      dtb = +"#{header}#{("\0" * mem_rsv_size)}#{struct}#{strings}"
      [dtb, start_value_offset, end_value_offset]
    end

    it 'requires native riscv runner support' do
      with_temp_binary("KERN") do |kernel_path, _|
        runner = described_class.allocate
        sim = double('sim', runner_kind: :riscv)
        cpu = double('cpu', native?: false, sim: sim)
        runner.instance_variable_set(:@cpu, cpu)

        expect do
          runner.load_linux(kernel: kernel_path)
        end.to raise_error(RuntimeError, /Linux mode requires native RISC-V IR runner or HDL backend/)
      end
    end

    it 'requires riscv native runner kind' do
      with_temp_binary("KERN") do |kernel_path, _|
        runner = described_class.allocate
        sim = double('sim', runner_kind: :generic)
        cpu = double('cpu', native?: true, sim: sim)
        runner.instance_variable_set(:@cpu, cpu)

        expect do
          runner.load_linux(kernel: kernel_path)
        end.to raise_error(RuntimeError, /Linux mode requires native RISC-V IR runner or HDL backend/)
      end
    end

    it 'supports linux loading when using hdl backend runners' do
      with_temp_binary("KERN") do |kernel_path, kernel_bytes|
        runner = described_class.allocate
        sim = double('sim', runner_kind: :hdl)
        cpu = double('cpu', native?: true, sim: sim)
        allow(cpu).to receive(:clear_uart_tx_bytes)
        runner.instance_variable_set(:@cpu, cpu)
        expected_bootstrap = runner.send(
          :build_linux_bootstrap_program,
          hart_id: 0,
          dtb_pointer: 0,
          entry_pc: 0x8040_0000
        )
        bootstrap_addr = runner.send(:linux_bootstrap_addr, 0x8040_0000)

        expect(runner).to receive(:reset).ordered
        expect(cpu).to receive(:clear_uart_tx_bytes).ordered
        expect(runner).to receive(:load_instruction_bytes).with(kernel_bytes, 0x8040_0000).ordered
        expect(runner).to receive(:load_instruction_bytes).with(expected_bootstrap, bootstrap_addr).ordered
        expect(runner).to receive(:set_pc).with(bootstrap_addr).ordered

        runner.load_linux(kernel: kernel_path)
      end
    end

    it 'patches linux,initrd bounds in DTB chosen node when initramfs is provided' do
      runner = described_class.allocate
      dtb_bytes, start_offset, end_offset = build_minimal_dtb_with_initrd_props
      patched = runner.send(:patch_dtb_initrd_bounds, dtb_bytes, 0x8400_2000, 0x1234)

      expect(patched.byteslice(start_offset, 8)).to eq([0x0000_0000, 0x8400_2000].pack('N2'))
      expect(patched.byteslice(end_offset, 8)).to eq([0x0000_0000, 0x8400_3234].pack('N2'))
    end

    it 'loads linux artifacts to expected addresses and boots through a deterministic entry trampoline' do
      with_temp_binary("KERN") do |kernel_path, kernel_bytes|
        with_temp_binary("INIT") do |initramfs_path, initramfs_bytes|
          with_temp_binary("DTB!") do |dtb_path, dtb_bytes|
            runner = described_class.allocate
            sim = double('sim', runner_kind: :riscv)
            cpu = double('cpu', native?: true, sim: sim)
            allow(cpu).to receive(:clear_uart_tx_bytes)
            runner.instance_variable_set(:@cpu, cpu)
            expected_bootstrap = runner.send(
              :build_linux_bootstrap_program,
              hart_id: 0,
              dtb_pointer: 0x87F0_0000,
              entry_pc: 0x8020_1234
            )
            bootstrap_addr = runner.send(:linux_bootstrap_addr, 0x8040_0000)

            expect(runner).to receive(:reset).ordered
            expect(cpu).to receive(:clear_uart_tx_bytes).ordered
            expect(runner).to receive(:load_instruction_bytes).with(kernel_bytes, 0x8040_0000).ordered
            expect(runner).to receive(:load_data_bytes).with(initramfs_bytes, 0x8400_0000).ordered
            expect(runner).to receive(:load_data_bytes).with(dtb_bytes, 0x87F0_0000).ordered
            expect(runner).to receive(:load_instruction_bytes).with(expected_bootstrap, bootstrap_addr).ordered
            expect(runner).to receive(:set_pc).with(bootstrap_addr).ordered

            runner.load_linux(
              kernel: kernel_path,
              initramfs: initramfs_path,
              dtb: dtb_path,
              kernel_addr: 0x8040_0000,
              initramfs_addr: 0x8400_0000,
              dtb_addr: 0x87F0_0000,
              pc: 0x8020_1234
            )
          end
        end
      end
    end

    it 'uses kernel load address as trampoline jump target when pc override is omitted' do
      with_temp_binary("KERN") do |kernel_path, kernel_bytes|
        runner = described_class.allocate
        sim = double('sim', runner_kind: :riscv)
        cpu = double('cpu', native?: true, sim: sim)
        allow(cpu).to receive(:clear_uart_tx_bytes)
        runner.instance_variable_set(:@cpu, cpu)
        expected_bootstrap = runner.send(
          :build_linux_bootstrap_program,
          hart_id: 0,
          dtb_pointer: 0,
          entry_pc: 0x8030_0000
        )
        bootstrap_addr = runner.send(:linux_bootstrap_addr, 0x8030_0000)

        expect(runner).to receive(:reset).ordered
        expect(cpu).to receive(:clear_uart_tx_bytes).ordered
        expect(runner).to receive(:load_instruction_bytes).with(kernel_bytes, 0x8030_0000).ordered
        expect(runner).to receive(:load_instruction_bytes).with(expected_bootstrap, bootstrap_addr).ordered
        expect(runner).to receive(:set_pc).with(bootstrap_addr).ordered

        runner.load_linux(kernel: kernel_path, kernel_addr: 0x8030_0000)
      end
    end

    it 'encodes M-mode SBI handoff firmware with Linux entry register contract' do
      runner = described_class.allocate
      words = runner.send(
        :build_linux_bootstrap_program,
        hart_id: 0,
        dtb_pointer: 0x87F0_0000,
        entry_pc: 0x8020_1234
      ).unpack('V*')

      expect(words.length).to be > 40
      expect(words).to include(0x3020_0073) # mret
      expect(find_li_values(words, 10)).to include(0)
      expect(find_li_values(words, 11)).to include(0x87F0_0000)
      expect(find_li_values(words, 5)).to include(0x8020_1234)
    end

    it 'encodes a1 as zero when dtb pointer is not provided' do
      runner = described_class.allocate
      words = runner.send(
        :build_linux_bootstrap_program,
        hart_id: 0,
        dtb_pointer: 0,
        entry_pc: 0x8040_0000
      ).unpack('V*')

      expect(find_li_values(words, 11)).to include(0)
    end

    it 'hands off to supervisor mode and services SBI base get_spec_version ecall' do
      runner = described_class.new(mode: :ruby, sim: :ruby)
      bootstrap_addr = 0x100
      entry_pc = 0x1000

      bootstrap = runner.send(
        :build_linux_bootstrap_program,
        hart_id: 0,
        dtb_pointer: 0,
        entry_pc: entry_pc
      )
      payload_words = [
        RHDL::Examples::RISCV::Assembler.addi(17, 0, 0x10), # a7 = SBI_EXT_BASE
        RHDL::Examples::RISCV::Assembler.addi(16, 0, 0x0),  # a6 = get_spec_version
        RHDL::Examples::RISCV::Assembler.ecall,
        RHDL::Examples::RISCV::Assembler.addi(12, 10, 0),   # x12 <- a0 (error)
        RHDL::Examples::RISCV::Assembler.addi(13, 11, 0),   # x13 <- a1 (value)
        RHDL::Examples::RISCV::Assembler.jal(0, 0)
      ]

      runner.reset
      runner.send(:load_instruction_bytes, payload_words.pack('V*'), entry_pc)
      runner.send(:load_instruction_bytes, bootstrap, bootstrap_addr)
      runner.set_pc(bootstrap_addr)
      runner.run_steps(320)

      expect(runner.cpu.read_reg(12)).to eq(0)
      expect(runner.cpu.read_reg(13)).to eq(0x0000_0002)
    end
  end
end
