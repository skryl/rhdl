# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/runners/verilator_runner'

RSpec.describe RHDL::Examples::SPARC64::VerilatorRunner do
  let(:mock_sim) do
    Class.new do
      attr_reader :rom_loads, :memory_loads, :memory_writes

      def initialize
        @memory = Hash.new(0)
        @rom_loads = []
        @memory_loads = []
        @memory_writes = []
        @signals = {}
      end

      def runner_supported?
        true
      end

      def runner_kind
        :sparc64
      end

      def reset
        true
      end

      def close; end

      def runner_run_cycles(n)
        { cycles_run: n }
      end

      def runner_load_rom(data, offset)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        @rom_loads << [offset, bytes]
        true
      end

      def runner_load_memory(data, offset, _is_rom)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        bytes.each_with_index { |byte, index| @memory[offset + index] = byte & 0xFF }
        @memory_loads << [offset, bytes]
        true
      end

      def runner_read_memory(offset, length, mapped:)
        Array.new(length) { |index| @memory[offset + index] || 0 }
      end

      def runner_write_memory(offset, data, mapped:)
        bytes = data.is_a?(String) ? data.bytes : Array(data)
        bytes.each_with_index { |byte, index| @memory[offset + index] = byte & 0xFF }
        @memory_writes << [offset, bytes]
        bytes.length
      end

      def runner_sparc64_wishbone_trace
        []
      end

      def runner_sparc64_unmapped_accesses
        []
      end

      def set_signal(name, value)
        @signals[name] = value
      end

      def has_signal?(name)
        @signals.key?(name)
      end

      def peek(name)
        @signals.fetch(name)
      end
    end.new
  end

  def build_runner_with_mock_sim(sim)
    runner = described_class.allocate
    runner.instance_variable_set(:@source_bundle, nil)
    runner.instance_variable_set(:@top_module, 's1_top')
    runner.instance_variable_set(:@verilator_prefix, 'Vs1_top')
    runner.instance_variable_set(:@clock_count, 0)
    runner.instance_variable_set(:@sim, sim)
    runner
  end

  it 'exposes the standard-ABI public metadata' do
    runner = build_runner_with_mock_sim(mock_sim)

    expect(runner.native?).to eq(true)
    expect(runner.simulator_type).to eq(:hdl_verilator)
    expect(runner.backend).to eq(:verilator)
  end

  it 'delegates run_cycles and load_images through the standard-ABI sim' do
    runner = build_runner_with_mock_sim(mock_sim)
    runner.load_images(boot_image: [0xAA], program_image: [0xBB, 0xCC])

    expect(mock_sim.rom_loads).to eq([[RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE, [0xAA]]])
    expect(mock_sim.memory_loads).to include(
      [0, [0xAA]],
      [RHDL::Examples::SPARC64::Integration::BOOT_PROM_ALIAS_BASE, [0xAA]],
      [RHDL::Examples::SPARC64::Integration::PROGRAM_BASE, [0xBB, 0xCC]]
    )

    result = runner.run_cycles(12)
    expect(result).to be_a(Hash)
    expect(result[:cycles_run]).to eq(12)
    expect(runner.clock_count).to eq(12)
  end

  it 'can prepare RHDL-generated Verilog sources without compiling immediately' do
    component_class = Class.new do
      def self.verilog_module_name
        's1_top'
      end

      def self.to_verilog_hierarchy(top_name: nil)
        "module #{top_name || 's1_top'};\nendmodule\n"
      end
    end

    runner = described_class.new(
      source_kind: :rhdl_verilog,
      component_class: component_class,
      compile_now: false
    )
    source_bundle = runner.instance_variable_get(:@source_bundle)

    expect(runner.source_kind).to eq(:rhdl_verilog)
    expect(source_bundle.top_module).to eq('s1_top')
    expect(File).to exist(source_bundle.top_file)
    expect(File.read(source_bundle.top_file)).to include('module s1_top;')
  end

  it 'exposes VerilatorRunner as the primary class' do
    expect(RHDL::Examples::SPARC64::VerilatorRunner).to eq(described_class)
  end

  it 'captures a structured debug snapshot from the underlying simulator' do
    mock_sim.set_signal('os2wb_inst__state', 7)
    mock_sim.set_signal('sparc_0__ifu__swl__thrfsm0__thr_state', 3)
    mock_sim.set_signal('sparc_0__ifu__swl__thrfsm1__thr_state', 0)
    mock_sim.set_signal('sparc_0__ifu__fcl__rune_ff__q', 1)
    mock_sim.set_signal('sparc_0__ifu__fcl__rund_ff__q', 1)
    mock_sim.set_signal('sparc_0__ifu__fcl__runm_ff__q', 0)
    mock_sim.set_signal('sparc_0__ifu__fcl__runw_ff__q', 0)
    mock_sim.set_signal('sparc_1__ifu__swl__thrfsm0__thr_state', 4)
    mock_sim.set_signal('sparc_1__ifu__swl__thrfsm1__thr_state', 4)
    mock_sim.set_signal('sparc_1__ifu__fcl__rune_ff__q', 0)
    mock_sim.set_signal('sparc_1__ifu__fcl__rund_ff__q', 0)
    mock_sim.set_signal('sparc_1__ifu__fcl__runm_ff__q', 0)
    mock_sim.set_signal('sparc_1__ifu__fcl__runw_ff__q', 0)

    runner = build_runner_with_mock_sim(mock_sim)
    runner.run_cycles(12)

    expect(runner.debug_snapshot).to include(
      reset: {
        cycle_counter: 12,
        mailbox_status: 0,
        mailbox_value: 0
      },
      bridge: include(
        state: 7
      ),
      thread0: include(
        thread_states: [3, 0],
        run_flags: {
          rune: true,
          rund: true,
          runm: false,
          runw: false
        }
      ),
      thread1: include(
        thread_states: [4, 4],
        run_flags: {
          rune: false,
          rund: false,
          runm: false,
          runw: false
        }
      )
    )
  end
end
