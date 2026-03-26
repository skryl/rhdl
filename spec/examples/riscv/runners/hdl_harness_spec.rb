# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'benchmark'
require 'etc'

RSpec.describe 'RISC-V HDL Runners' do
  before(:all) do
    @verilator_available = HdlToolchain.verilator_available?
    @arcilator_available = HdlToolchain.arcilator_available?

    if @verilator_available || @arcilator_available
      require_relative '../../../../examples/riscv/utilities/runners/headless_runner'
      require_relative '../../../../examples/riscv/utilities/assembler'
      require_relative '../../../../examples/riscv/utilities/runners/verilator_runner' if @verilator_available
      require_relative '../../../../examples/riscv/utilities/runners/arcilator_runner' if @arcilator_available
    end
  end

  describe 'VerilogRunner' do
    it 'is defined when verilator is available' do
      skip 'Verilator not available' unless @verilator_available
      require_relative '../../../../examples/riscv/utilities/runners/verilator_runner'
      expect(defined?(RHDL::Examples::RISCV::VerilogRunner)).to eq('constant')
    end

    it 'has the required public interface methods' do
      skip 'Verilator not available' unless @verilator_available
      require_relative '../../../../examples/riscv/utilities/runners/verilator_runner'

      required_methods = %i[
        native? simulator_type backend reset!
        run_cycles clock_count
        read_reg read_pc load_program load_data
        read_inst_word read_data_word write_data_word
        set_interrupts set_plic_sources
        uart_receive_byte uart_receive_bytes uart_receive_text
        uart_tx_bytes clear_uart_tx_bytes
        load_virtio_disk read_virtio_disk_byte
        state current_inst
      ]

      required_methods.each do |method|
        expect(RHDL::Examples::RISCV::VerilogRunner.instance_methods).to include(method),
          "Missing method: #{method}"
      end
    end

    it 'rejects native libraries that do not expose the standardized RISC-V runner ABI' do
      skip 'Verilator not available' unless @verilator_available

      runner = RHDL::Examples::RISCV::VerilogRunner.allocate
      sim = instance_double('Sim', runner_supported?: false, close: true)

      expect(sim).to receive(:close)
      expect do
        runner.send(:ensure_runner_abi!, sim, expected_kind: :riscv, backend_label: 'RISC-V Verilator')
      end.to raise_error(RuntimeError, /runner ABI/)
    end
  end

  describe 'ArcilatorRunner' do
    it 'is defined when arcilator is available' do
      skip 'Arcilator not available' unless @arcilator_available
      require_relative '../../../../examples/riscv/utilities/runners/arcilator_runner'
      expect(defined?(RHDL::Examples::RISCV::ArcilatorRunner)).to eq('constant')
    end

    it 'has the required public interface methods' do
      skip 'Arcilator not available' unless @arcilator_available
      require_relative '../../../../examples/riscv/utilities/runners/arcilator_runner'

      required_methods = %i[
        native? simulator_type backend reset!
        run_cycles clock_count
        read_reg read_pc load_program load_data
        read_inst_word read_data_word write_data_word
        set_interrupts set_plic_sources
        uart_receive_byte uart_receive_bytes uart_receive_text
        uart_tx_bytes clear_uart_tx_bytes
        load_virtio_disk read_virtio_disk_byte
        state current_inst
      ]

      required_methods.each do |method|
        expect(RHDL::Examples::RISCV::ArcilatorRunner.instance_methods).to include(method),
          "Missing method: #{method}"
      end
    end

    it 'rejects native libraries with the wrong runner kind' do
      skip 'Arcilator not available' unless @arcilator_available

      runner = RHDL::Examples::RISCV::ArcilatorRunner.allocate
      sim = instance_double('Sim', runner_supported?: true, runner_kind: :apple2, close: true)

      expect(sim).to receive(:close)
      expect do
        runner.send(:ensure_runner_abi!, sim, expected_kind: :riscv, backend_label: 'RISC-V Arcilator')
      end.to raise_error(RuntimeError, /expected :riscv/i)
    end
  end

  describe 'HeadlessRunner integration' do
    it 'creates verilator-backed runner' do
      skip 'Verilator not available' unless @verilator_available

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :verilog)
      expect(runner.mode).to eq(:verilog)
      expect(runner.effective_mode).to eq(:verilog)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::VerilogRunner)
      expect(runner.cpu.simulator_type).to eq(:hdl_verilator)
    rescue LoadError, RuntimeError => e
      skip "Verilator backend unavailable: #{e.message}"
    end

    it 'forwards threads to the verilator-backed runner' do
      skip 'Verilator not available' unless @verilator_available

      fake_cpu = instance_double(
        'RHDL::Examples::RISCV::VerilogRunner',
        native?: true,
        simulator_type: :hdl_verilator,
        backend: :verilator,
        sim: instance_double('Sim')
      )
      allow(RHDL::Examples::RISCV::VerilogRunner).to receive(:new).and_return(fake_cpu)

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :verilog, threads: 4)

      expect(runner.cpu).to eq(fake_cpu)
      expect(RHDL::Examples::RISCV::VerilogRunner).to have_received(:new).with(
        mem_size: RHDL::Examples::RISCV::HeadlessRunner::DEFAULT_MEM_SIZE,
        threads: 4
      )
    end

    it 'creates arcilator-backed runner' do
      skip 'Arcilator not available' unless @arcilator_available

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :circt)
      expect(runner.mode).to eq(:circt)
      expect(runner.effective_mode).to eq(:circt)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::ArcilatorRunner)
      expect(runner.cpu.simulator_type).to eq(:hdl_arcilator)
    rescue LoadError, RuntimeError => e
      skip "Arcilator backend unavailable: #{e.message}"
    end

    it 'exposes the native sim object uniformly when the backend has one' do
      skip 'Arcilator not available' unless @arcilator_available

      fake_sim = instance_double('Sim')
      fake_cpu = instance_double(
        'RHDL::Examples::RISCV::ArcilatorRunner',
        native?: true,
        simulator_type: :hdl_arcilator,
        backend: :arcilator,
        sim: fake_sim
      )
      allow(RHDL::Examples::RISCV::ArcilatorRunner).to receive(:new).and_return(fake_cpu)

      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :circt)
      expect(runner.sim).to eq(fake_sim)
    end

    it 'creates ruby-backed runner' do
      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :ruby, sim: :ruby)
      expect(runner.mode).to eq(:ruby)
      expect(runner.effective_mode).to eq(:ruby)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::RubyRunner)
      expect(runner.cpu.simulator_type).to eq(:ruby)
    rescue LoadError, RuntimeError => e
      skip "Ruby backend unavailable: #{e.message}"
    end

    it 'creates ir-backed runner' do
      runner = RHDL::Examples::RISCV::HeadlessRunner.new(mode: :ir)
      expect(runner.mode).to eq(:ir)
      expect(runner.effective_mode).to eq(:ir)
      expect(runner.cpu).to be_a(RHDL::Examples::RISCV::IrRunner)
    rescue LoadError, RuntimeError => e
      skip "IR backend unavailable: #{e.message}"
    end
  end

  shared_examples 'RISC-V HDL backend' do |runner_class_name|
    let(:asm) { RHDL::Examples::RISCV::Assembler }
    let(:runner_class) { RHDL::Examples::RISCV.const_get(runner_class_name) }

    def create_runner
      runner_class.new(mem_size: 4096)
    end

    it 'reports native simulation' do
      expect(create_runner.native?).to eq(true)
    end

    it 'reports correct simulator type' do
      expected_type = runner_class_name == :VerilogRunner ? :hdl_verilator : :hdl_arcilator
      expect(create_runner.simulator_type).to eq(expected_type)
    end

    it 'starts at cycle 0 after reset' do
      expect(create_runner.clock_count).to eq(0)
    end

    it 'executes ADDI and reads register' do
      runner = create_runner
      runner.load_program([asm.addi(1, 0, 42)])
      runner.reset!
      runner.run_cycles(1)

      expect(runner.read_reg(1)).to eq(42)
    end

    it 'increments cycle count' do
      runner = create_runner
      runner.load_program([asm.addi(1, 0, 1), asm.addi(2, 0, 2), asm.addi(3, 0, 3)])
      runner.reset!
      runner.run_cycles(3)

      expect(runner.clock_count).to eq(3)
    end

    it 'reads PC via debug port' do
      runner = create_runner
      runner.load_program([asm.addi(1, 0, 1)])
      runner.reset!
      pc_before = runner.read_pc
      runner.run_cycles(1)
      pc_after = runner.read_pc

      expect(pc_after).to be > pc_before
    end

    it 'loads and reads instruction memory' do
      runner = create_runner
      program = [asm.addi(1, 0, 99)]
      runner.load_program(program, 0)

      word = runner.read_inst_word(0)
      expect(word).to eq(program[0])
    end

    it 'loads and reads data memory' do
      runner = create_runner
      runner.load_data([0xDEAD_BEEF], 0x100)

      word = runner.read_data_word(0x100)
      expect(word).to eq(0xDEAD_BEEF)
    end

    it 'executes store and load through data memory' do
      runner = create_runner
      program = [
        asm.lui(1, 0),
        asm.addi(2, 0, 42),
        asm.sw(2, 1, 0x100),
        asm.lw(3, 1, 0x100)
      ]
      runner.load_program(program)
      runner.reset!
      runner.run_cycles(4)

      expect(runner.read_reg(3)).to eq(42)
    end

    it 'captures UART TX bytes and supports buffer clear' do
      runner = create_runner
      program = [
        asm.lui(1, 0x10000), # x1 = 0x1000_0000 (UART base)
        asm.addi(2, 0, 65),  # 'A'
        asm.sb(2, 1, 0)
      ]
      runner.load_program(program)
      runner.reset!
      runner.run_cycles(3)

      expect(runner.uart_tx_bytes).to include(65)
      runner.clear_uart_tx_bytes
      expect(runner.uart_tx_bytes).to eq([])
    end

    it 'supports UART RX injection through MMIO read path' do
      runner = create_runner
      program = [
        asm.lui(1, 0x10000), # x1 = 0x1000_0000 (UART base)
        asm.lb(3, 1, 0)
      ]
      runner.load_program(program)
      runner.reset!
      runner.uart_receive_byte(0x41)
      runner.run_cycles(2)

      expect(runner.read_reg(3) & 0xFF).to eq(0x41)
    end

    it 'returns state hash' do
      runner = create_runner
      runner.load_program([asm.addi(1, 0, 1)])
      runner.reset!
      runner.run_cycles(1)

      state = runner.state
      expect(state).to include(:pc, :x1, :x2, :x10, :x11, :inst, :cycles)
      expect(state[:x1]).to eq(1)
      expect(state[:cycles]).to eq(1)
    end

    it 'handles VirtIO disk load and read' do
      runner = create_runner
      runner.reset!
      runner.load_virtio_disk([0xAA, 0xBB, 0xCC], offset: 0)

      expect(runner.read_virtio_disk_byte(0)).to eq(0xAA)
      expect(runner.read_virtio_disk_byte(1)).to eq(0xBB)
      expect(runner.read_virtio_disk_byte(2)).to eq(0xCC)
    end
  end

  context 'with VerilogRunner', :slow do
    let(:asm) { RHDL::Examples::RISCV::Assembler }

    before do
      skip 'Verilator not available' unless @verilator_available
    end

    include_examples 'RISC-V HDL backend', :VerilogRunner

    it 'benchmarks default Verilator against a --threads 4 build on the same workload' do
      skip 'Need at least 4 host CPUs for a meaningful threaded comparison' if Etc.nprocessors < 4

      bench_cycles = Integer(ENV.fetch('RHDL_RISCV_VERILATOR_BENCH_CYCLES', '200000'), 10)
      program = [
        asm.addi(1, 0, 0),
        asm.addi(2, 0, 1),
        asm.addi(3, 0, 200),
        asm.add(1, 1, 2),
        asm.xori(2, 2, 0x55),
        asm.addi(3, 3, -1),
        asm.bne(3, 0, -12),
        asm.jal(0, -16)
      ]

      single = RHDL::Examples::RISCV::VerilogRunner.new(mem_size: 4096)
      threaded = RHDL::Examples::RISCV::VerilogRunner.new(mem_size: 4096, threads: 4)

      [single, threaded].each do |runner|
        runner.load_program(program)
        runner.reset!
        runner.run_cycles(1024)
        runner.load_program(program)
        runner.reset!
      end

      single_time = Benchmark.measure { single.run_cycles(bench_cycles) }
      threaded_time = Benchmark.measure { threaded.run_cycles(bench_cycles) }

      expect(threaded.read_pc).to eq(single.read_pc)
      [1, 2, 3].each do |reg|
        expect(threaded.read_reg(reg)).to eq(single.read_reg(reg))
      end

      puts "\n" + "=" * 60
      puts "RISC-V Verilator Thread Benchmark (#{bench_cycles} cycles)"
      puts "=" * 60
      puts "Verilator default:     #{single_time.real.round(4)}s (#{(bench_cycles / single_time.real).round(0)} cycles/s)"
      puts "Verilator --threads 4: #{threaded_time.real.round(4)}s (#{(bench_cycles / threaded_time.real).round(0)} cycles/s)"
      puts "Ratio (threads/default): #{(threaded_time.real / single_time.real).round(3)}x"
      puts "=" * 60

      expect(single_time.real).to be > 0
      expect(threaded_time.real).to be > 0
    end
  end

  context 'with ArcilatorRunner', :slow do
    before do
      skip 'Arcilator not available' unless @arcilator_available
    end

    include_examples 'RISC-V HDL backend', :ArcilatorRunner
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

      verilator = RHDL::Examples::RISCV::VerilogRunner.new(mem_size: 4096)
      arcilator = RHDL::Examples::RISCV::ArcilatorRunner.new(mem_size: 4096)

      verilator.load_program(program)
      arcilator.load_program(program)
      verilator.reset!
      arcilator.reset!

      verilator.run_cycles(5)
      arcilator.run_cycles(5)

      (1..5).each do |reg|
        expect(verilator.read_reg(reg)).to eq(arcilator.read_reg(reg)),
          "Register x#{reg} mismatch: verilator=#{verilator.read_reg(reg)} arcilator=#{arcilator.read_reg(reg)}"
      end

      expect(verilator.read_pc).to eq(arcilator.read_pc)
    end
  end
end
