# frozen_string_literal: true

require 'spec_helper'

require_relative '../../../../examples/sparc64/utilities/runners/headless_runner'
require_relative '../../../../examples/sparc64/utilities/integration/programs'

RSpec.describe RHDL::Examples::SPARC64::HeadlessRunner do
  let(:fake_runner_class) do
    Class.new do
      attr_reader :clock_count, :loaded_images

      def initialize(**)
        @clock_count = 0
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def backend
        :compile
      end

      def reset!
        @clock_count = 0
      end

      def load_images(boot_image:, program_image:)
        @loaded_images = [boot_image, program_image]
      end

      def run_until_complete(max_cycles:, batch_cycles:)
        { completed: true, timeout: false, cycles: [max_cycles, batch_cycles] }
      end

      def read_memory(_addr, length)
        Array.new(length, 0)
      end

      def write_memory(_addr, _bytes)
        true
      end

      def wishbone_trace
        []
      end

      def mailbox_status
        1
      end

      def mailbox_value
        0xA0
      end

      def unmapped_accesses
        []
      end

      def debug_snapshot
        { reset: { cycle_counter: 0 }, bridge: { state: 7 } }
      end
    end
  end

  let(:builder) do
    Class.new do
      Result = Struct.new(:boot_bytes, :program_bytes, keyword_init: true)

      def build(program)
        Result.new(boot_bytes: [program.name.to_s.length], program_bytes: [program.expected_value & 0xFF])
      end
    end.new
  end

  let(:fake_verilog_runner_class) do
    Class.new(fake_runner_class) do
      class << self
        attr_reader :last_kwargs
      end

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
        super()
      end

      def simulator_type
        :hdl_verilator
      end

      def backend
        :verilator
      end
    end
  end

  let(:fake_arcilator_runner_class) do
    Class.new(fake_runner_class) do
      class << self
        attr_reader :last_kwargs
      end

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
        super()
      end

      def simulator_type
        :hdl_arcilator
      end

      def backend
        :arcilator
      end
    end
  end

  it 'constructs compile-backed IR runner by default' do
    runner = described_class.new(
      ir_runner_class: fake_runner_class,
      builder: builder
    )

    expect(runner.mode).to eq(:ir)
    expect(runner.backend).to eq(:compile)
    expect(runner.native?).to be(true)
  end

  it 'loads benchmark images through the configured builder' do
    runner = described_class.new(
      ir_runner_class: fake_runner_class,
      builder: builder
    )
    program = RHDL::Examples::SPARC64::Integration::Programs.fetch(:prime_sieve)

    runner.load_benchmark(program)

    expect(runner.runner.loaded_images).to eq([[11], [0xA0]])
    expect(runner.mailbox_value).to eq(0xA0)
    expect(runner.debug_snapshot).to eq(reset: { cycle_counter: 0 }, bridge: { state: 7 })
  end

  it 'creates a verilog-backed runner when requested' do
    runner = described_class.new(
      mode: :verilog,
      verilator_runner_class: fake_verilog_runner_class,
      builder: builder
    )

    expect(runner.mode).to eq(:verilog)
    expect(runner.backend).to eq(:verilator)
  end

  it 'forwards RHDL Verilog source selection to the Verilator runner' do
    described_class.new(
      mode: :verilog,
      verilator_runner_class: fake_verilog_runner_class,
      builder: builder,
      verilator_source: :rhdl_verilog
    )

    expect(fake_verilog_runner_class.last_kwargs).to include(fast_boot: true, source_kind: :rhdl_verilog)
  end

  it 'forwards threads to the Verilator runner' do
    described_class.new(
      mode: :verilog,
      verilator_runner_class: fake_verilog_runner_class,
      builder: builder,
      threads: 4
    )

    expect(fake_verilog_runner_class.last_kwargs).to include(
      fast_boot: true,
      source_kind: :staged_verilog,
      threads: 4
    )
  end

  it 'creates an arcilator-backed runner when requested' do
    runner = described_class.new(
      mode: :arcilator,
      sim: :compile,
      arcilator_runner_class: fake_arcilator_runner_class,
      builder: builder
    )

    expect(runner.mode).to eq(:arcilator)
    expect(runner.backend).to eq(:arcilator)
  end

  it 'forwards jit selection to the arcilator runner' do
    described_class.new(
      mode: :arcilator,
      sim: :jit,
      arcilator_runner_class: fake_arcilator_runner_class,
      builder: builder
    )

    expect(fake_arcilator_runner_class.last_kwargs).to include(fast_boot: true, jit: true)
  end

  it 'forwards staged-Verilog source selection to the Arcilator runner' do
    described_class.new(
      mode: :arcilator,
      sim: :compile,
      arcilator_runner_class: fake_arcilator_runner_class,
      builder: builder,
      arcilator_source: :staged_verilog
    )

    expect(fake_arcilator_runner_class.last_kwargs).to include(fast_boot: true, jit: false, source_kind: :staged_verilog)
  end

  it 'forwards fast_boot to the selected runner' do
    capturing_runner_class = Class.new do
      class << self
        attr_reader :last_kwargs
      end

      attr_reader :clock_count

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
        @clock_count = 0
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def backend
        :compile
      end

      def reset!
        @clock_count = 0
      end

      def load_images(**)
      end

      def run_until_complete(**)
        {}
      end

      def read_memory(_addr, length)
        Array.new(length, 0)
      end

      def write_memory(_addr, _bytes)
      end

      def wishbone_trace
        []
      end

      def mailbox_status
        0
      end

      def mailbox_value
        0
      end

      def unmapped_accesses
        []
      end
    end

    described_class.new(
      ir_runner_class: capturing_runner_class,
      builder: builder,
      fast_boot: false
    )

    expect(capturing_runner_class.last_kwargs).to include(backend: :compile, fast_boot: false)
  end

  it 'forwards interpret and jit IR backends to the IR runner' do
    capturing_runner_class = Class.new do
      class << self
        attr_reader :all_kwargs
      end

      def initialize(**kwargs)
        values = self.class.instance_variable_get(:@all_kwargs) || []
        self.class.instance_variable_set(:@all_kwargs, values + [kwargs])
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def backend
        :compile
      end

      def reset!
      end

      def load_images(**)
      end

      def run_until_complete(**)
        {}
      end

      def read_memory(_addr, length)
        Array.new(length, 0)
      end

      def write_memory(_addr, _bytes)
      end

      def wishbone_trace
        []
      end

      def mailbox_status
        0
      end

      def mailbox_value
        0
      end

      def unmapped_accesses
        []
      end
    end

    described_class.new(
      ir_runner_class: capturing_runner_class,
      builder: builder,
      sim: :interpret
    )
    described_class.new(
      ir_runner_class: capturing_runner_class,
      builder: builder,
      sim: :jit
    )

    expect(capturing_runner_class.all_kwargs).to include(include(backend: :interpret))
    expect(capturing_runner_class.all_kwargs).to include(include(backend: :jit))
  end

  it 'forwards compile_mode to the IR runner' do
    capturing_runner_class = Class.new do
      class << self
        attr_reader :last_kwargs
      end

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def backend
        :compile
      end

      def reset!
      end

      def load_images(**)
      end

      def run_until_complete(**)
        {}
      end

      def read_memory(_addr, length)
        Array.new(length, 0)
      end

      def write_memory(_addr, _bytes)
      end

      def wishbone_trace
        []
      end

      def mailbox_status
        0
      end

      def mailbox_value
        0
      end

      def unmapped_accesses
        []
      end
    end

    described_class.new(
      ir_runner_class: capturing_runner_class,
      builder: builder,
      compile_mode: :rustc
    )

    expect(capturing_runner_class.last_kwargs).to include(backend: :compile, compiler_mode: :rustc)
  end

  it 'defaults the SPARC64 compiler backend to rustc mode' do
    capturing_runner_class = Class.new do
      class << self
        attr_reader :last_kwargs
      end

      def initialize(**kwargs)
        self.class.instance_variable_set(:@last_kwargs, kwargs)
      end

      def native?
        true
      end

      def simulator_type
        :ir_compile
      end

      def backend
        :compile
      end

      def reset!
      end

      def load_images(**)
      end

      def run_until_complete(**)
        {}
      end

      def read_memory(_addr, length)
        Array.new(length, 0)
      end

      def write_memory(_addr, _bytes)
      end

      def wishbone_trace
        []
      end

      def mailbox_status
        0
      end

      def mailbox_value
        0
      end

      def unmapped_accesses
        []
      end
    end

    described_class.new(
      ir_runner_class: capturing_runner_class,
      builder: builder
    )

    expect(capturing_runner_class.last_kwargs).to include(backend: :compile, compiler_mode: :rustc)
  end

  it 'rejects removed SPARC64 runtime-only compiler mode' do
    expect do
      described_class.new(
        ir_runner_class: fake_runner_class,
        builder: builder,
        compile_mode: :runtime_only
      )
    end.to raise_error(ArgumentError, /rustc-only/)
  end
end
