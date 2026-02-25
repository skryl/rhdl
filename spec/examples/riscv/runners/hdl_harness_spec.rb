# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'

RSpec.describe 'RISC-V HdlHarness' do
  def verilator_available?
    ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, 'verilator'))
    end
  end

  def arcilator_available?
    %w[firtool arcilator].all? do |tool|
      ENV['PATH'].split(File::PATH_SEPARATOR).any? do |path|
        File.executable?(File.join(path, tool))
      end
    end
  end

  before(:all) do
    @verilator_available = verilator_available?
    @arcilator_available = arcilator_available?

    if @verilator_available || @arcilator_available
      require_relative '../../../../examples/riscv/hdl/hdl_harness'
      require_relative '../../../../examples/riscv/utilities/assembler'
    end
  end

  describe 'class definition' do
    it 'defines HdlHarness in RHDL::Examples::RISCV namespace' do
      skip 'No HDL backend available' unless @verilator_available || @arcilator_available
      expect(defined?(RHDL::Examples::RISCV::HdlHarness)).to eq('constant')
    end

    it 'has the required public interface methods' do
      skip 'No HDL backend available' unless @verilator_available || @arcilator_available

      required_methods = %i[
        native? simulator_type backend reset!
        clock_cycle run_cycles clock_count
        read_reg read_pc load_program load_data
        read_inst_word read_data_word write_data_word
        set_interrupts set_plic_sources
        uart_receive_byte uart_receive_bytes uart_receive_text
        uart_tx_bytes clear_uart_tx_bytes
        load_virtio_disk read_virtio_disk_byte
        state current_inst
      ]

      required_methods.each do |method|
        expect(RHDL::Examples::RISCV::HdlHarness.instance_methods).to include(method),
          "Missing method: #{method}"
      end
    end
  end

  describe 'HeadlessRunner integration' do
    it 'creates verilator-backed runner' do
      skip 'Verilator not available' unless @verilator_available
      require_relative '../../../../examples/riscv/utilities/runners/headless_runner'

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :verilog)
      expect(runner.mode).to eq(:verilog)
      expect(runner.effective_mode).to eq(:verilog)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::HdlHarness)
      expect(runner.cpu.simulator_type).to eq(:hdl_verilator)
    rescue LoadError, RuntimeError => e
      skip "Verilator backend unavailable: #{e.message}"
    end

    it 'creates arcilator-backed runner' do
      skip 'Arcilator not available' unless @arcilator_available
      require_relative '../../../../examples/riscv/utilities/runners/headless_runner'

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :arcilator)
      expect(runner.mode).to eq(:arcilator)
      expect(runner.effective_mode).to eq(:arcilator)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::HdlHarness)
      expect(runner.cpu.simulator_type).to eq(:hdl_arcilator)
    rescue LoadError, RuntimeError => e
      skip "Arcilator backend unavailable: #{e.message}"
    end
  end

  shared_examples 'RISC-V HDL backend' do |backend_sym|
    let(:asm) { RHDL::Examples::RISCV::Assembler }

    def create_harness(backend)
      RHDL::Examples::RISCV::HdlHarness.new(backend: backend, mem_size: 4096)
    end

    it 'reports native simulation' do
      harness = create_harness(backend_sym)
      expect(harness.native?).to eq(true)
    end

    it 'reports correct simulator type' do
      harness = create_harness(backend_sym)
      expected = backend_sym == :verilator ? :hdl_verilator : :hdl_arcilator
      expect(harness.simulator_type).to eq(expected)
    end

    it 'reports correct backend' do
      harness = create_harness(backend_sym)
      expect(harness.backend).to eq(backend_sym)
    end

    it 'starts at cycle 0 after reset' do
      harness = create_harness(backend_sym)
      expect(harness.clock_count).to eq(0)
    end

    it 'executes ADDI and reads register' do
      harness = create_harness(backend_sym)
      harness.load_program([asm.addi(1, 0, 42)])
      harness.reset!
      harness.run_cycles(1)

      expect(harness.read_reg(1)).to eq(42)
    end

    it 'increments cycle count' do
      harness = create_harness(backend_sym)
      harness.load_program([asm.addi(1, 0, 1), asm.addi(2, 0, 2), asm.addi(3, 0, 3)])
      harness.reset!
      harness.run_cycles(3)

      expect(harness.clock_count).to eq(3)
    end

    it 'reads PC via debug port' do
      harness = create_harness(backend_sym)
      harness.load_program([asm.addi(1, 0, 1)])
      harness.reset!
      pc_before = harness.read_pc
      harness.run_cycles(1)
      pc_after = harness.read_pc

      expect(pc_after).to be > pc_before
    end

    it 'loads and reads instruction memory' do
      harness = create_harness(backend_sym)
      program = [asm.addi(1, 0, 99)]
      harness.load_program(program, 0)

      word = harness.read_inst_word(0)
      expect(word).to eq(program[0])
    end

    it 'loads and reads data memory' do
      harness = create_harness(backend_sym)
      harness.load_data([0xDEAD_BEEF], 0x100)

      word = harness.read_data_word(0x100)
      expect(word).to eq(0xDEAD_BEEF)
    end

    it 'executes store and load through data memory' do
      harness = create_harness(backend_sym)
      # lui x1, 0 (x1 = 0x0000_0000 - data base address)
      # addi x2, x0, 42  (x2 = 42)
      # sw x2, 256(x1)   (store 42 at address 0x100)
      # lw x3, 256(x1)   (load from address 0x100 into x3)
      program = [
        asm.lui(1, 0),
        asm.addi(2, 0, 42),
        asm.sw(2, 1, 0x100),
        asm.lw(3, 1, 0x100)
      ]
      harness.load_program(program)
      harness.reset!
      harness.run_cycles(4)

      expect(harness.read_reg(3)).to eq(42)
    end

    it 'returns state hash' do
      harness = create_harness(backend_sym)
      harness.load_program([asm.addi(1, 0, 1)])
      harness.reset!
      harness.run_cycles(1)

      state = harness.state
      expect(state).to include(:pc, :x1, :x2, :x10, :x11, :inst, :cycles)
      expect(state[:x1]).to eq(1)
      expect(state[:cycles]).to eq(1)
    end

    it 'handles UART TX via MMIO' do
      harness = create_harness(backend_sym)
      # lui x1, 0x10000 (UART base)
      # addi x2, x0, 0x41 ('A')
      # sb x2, 0(x1)  (write to UART THR)
      program = [
        asm.lui(1, 0x10000),
        asm.addi(2, 0, 0x41),
        asm.sb(2, 1, 0)
      ]
      harness.load_program(program)
      harness.reset!
      harness.run_cycles(program.length + 2)

      expect(harness.uart_tx_bytes).to include(0x41)
    end

    it 'handles UART RX via MMIO' do
      harness = create_harness(backend_sym)
      # lui x1, 0x10000 (UART base)
      # nop (let UART settle)
      # lb x3, 0(x1) (read from UART RBR)
      program = [
        asm.lui(1, 0x10000),
        asm.nop,
        asm.lb(3, 1, 0)
      ]
      harness.load_program(program)
      harness.reset!
      harness.uart_receive_byte(0x55)
      harness.run_cycles(program.length + 2)

      expect(harness.read_reg(3)).to eq(0x55)
    end

    it 'clears UART TX buffer' do
      harness = create_harness(backend_sym)
      harness.load_program([asm.lui(1, 0x10000), asm.addi(2, 0, 0x42), asm.sb(2, 1, 0)])
      harness.reset!
      harness.run_cycles(5)

      harness.clear_uart_tx_bytes
      expect(harness.uart_tx_bytes).to eq([])
    end

    it 'handles VirtIO disk load and read' do
      harness = create_harness(backend_sym)
      harness.reset!
      harness.load_virtio_disk([0xAA, 0xBB, 0xCC], offset: 0)

      expect(harness.read_virtio_disk_byte(0)).to eq(0xAA)
      expect(harness.read_virtio_disk_byte(1)).to eq(0xBB)
      expect(harness.read_virtio_disk_byte(2)).to eq(0xCC)
    end
  end

  context 'with Verilator backend', :slow do
    before do
      skip 'Verilator not available' unless @verilator_available
    end

    include_examples 'RISC-V HDL backend', :verilator
  end

  context 'with Arcilator backend', :slow do
    before do
      skip 'Arcilator not available' unless @arcilator_available
    end

    include_examples 'RISC-V HDL backend', :arcilator
  end

  context 'backend parity', :slow do
    before do
      skip 'Both backends required' unless @verilator_available && @arcilator_available
    end

    let(:asm) { RHDL::Examples::RISCV::Assembler }

    it 'produces identical register state after running the same program' do
      program = [
        asm.addi(1, 0, 10),
        asm.addi(2, 0, 20),
        asm.add(3, 1, 2),
        asm.slli(4, 3, 2),
        asm.xori(5, 4, 0xFF)
      ]

      verilator = RHDL::Examples::RISCV::HdlHarness.new(backend: :verilator, mem_size: 4096)
      arcilator = RHDL::Examples::RISCV::HdlHarness.new(backend: :arcilator, mem_size: 4096)

      verilator.load_program(program)
      arcilator.load_program(program)
      verilator.reset!
      arcilator.reset!

      5.times do
        verilator.clock_cycle
        arcilator.clock_cycle
      end

      (1..5).each do |reg|
        expect(verilator.read_reg(reg)).to eq(arcilator.read_reg(reg)),
          "Register x#{reg} mismatch: verilator=#{verilator.read_reg(reg)} arcilator=#{arcilator.read_reg(reg)}"
      end

      expect(verilator.read_pc).to eq(arcilator.read_pc)
    end
  end
end
