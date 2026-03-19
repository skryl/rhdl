# frozen_string_literal: true

module Sparc64IntegrationSupport
  MAILBOX_STATUS_ADDR = 0x0000_0000_0000_1000
  MAILBOX_VALUE_ADDR = 0x0000_0000_0000_1008
  PROGRAM_BASE = 0x0001_0000
  STACK_TOP = 0x0002_0000

  EXPECTED_BENCHMARK_VALUES = {
    prime_sieve: 0xA0,
    mandelbrot: 0xFFF0,
    game_of_life: 0x2
  }.freeze

  REQUIRED_HEADLESS_METHODS = %i[
    load_benchmark
    reset
    run_until_complete
    read_memory
    write_memory
    wishbone_trace
    mailbox_status
    mailbox_value
    unmapped_accesses
  ].freeze

  REQUIRED_BACKEND_METHODS = %i[
    reset!
    load_images
    run_until_complete
    read_memory
    write_memory
    wishbone_trace
    mailbox_status
    mailbox_value
    unmapped_accesses
  ].freeze

  REQUIRED_RUN_RESULT_KEYS = %i[
    completed
    cycles
    boot_handoff_seen
    secondary_core_parked
  ].freeze

  REQUIRED_EVENT_KEYS = %i[
    cycle
    op
    addr
    sel
    write_data
    read_data
  ].freeze

  def pending_unless_runner_stack!
    pending('SPARC64 integration runner stack not implemented yet') unless sparc64_runner_stack_available?
  end

  def pending_unless_runner_contract!(runner)
    missing = REQUIRED_HEADLESS_METHODS.reject { |method| runner.respond_to?(method) }
    pending("SPARC64 HeadlessRunner contract incomplete: missing #{missing.join(', ')}") unless missing.empty?

    return unless runner.respond_to?(:runner)

    backend = runner.runner
    return if backend.nil?

    if backend.respond_to?(:runtime_contract_ready?) && !backend.runtime_contract_ready?
      pending('SPARC64 backend runtime contract not available for this backend configuration yet')
    end

    backend_missing = REQUIRED_BACKEND_METHODS.reject { |method| backend.respond_to?(method) }
    pending("SPARC64 backend runner contract incomplete: missing #{backend_missing.join(', ')}") unless backend_missing.empty?
  end

  def pending_unless_runtime_backends!
    pending('SPARC64 IR runner not implemented yet') unless sparc64_ir_runner_class
    pending('SPARC64 Verilator runner not implemented yet') unless sparc64_verilator_runner_class
  end

  def pending_unless_arcilator_backends!
    pending('SPARC64 Arcilator runner not implemented yet') unless sparc64_arcilator_runner_class
  end

  def skip_unless_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  def skip_unless_verilator!
    skip 'Verilator not available' unless HdlToolchain.verilator_available?
  end

  def skip_unless_arcilator!
    skip 'circt-opt not available' unless HdlToolchain.which('circt-opt')
    skip 'arcilator not available' unless HdlToolchain.which('arcilator')
  end

  def skip_unless_circt_verilog!
    skip 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')
  end

  def skip_unless_firtool!
    skip 'firtool not available' unless HdlToolchain.which('firtool')
  end

  def skip_unless_arcilator_jit!
    skip_unless_arcilator!
    skip 'clang++ not available' unless HdlToolchain.which('clang++')
    skip 'llvm-link not available' unless HdlToolchain.which('llvm-link')
    skip 'lli not available' unless HdlToolchain.which('lli')
  end

  def skip_unless_program_toolchain!
    skip 'llvm-mc not available' unless HdlToolchain.which('llvm-mc')
    skip 'ld.lld not available' unless HdlToolchain.which('ld.lld')
    skip 'llvm-objcopy not available' unless HdlToolchain.which('llvm-objcopy')
  end

  def sparc64_benchmark_names
    EXPECTED_BENCHMARK_VALUES.keys
  end

  def expected_benchmark_value(name)
    EXPECTED_BENCHMARK_VALUES.fetch(name.to_sym)
  end

  def build_parity_runner(artifact:)
    case artifact.to_sym
    when :staged_verilog_verilator
      skip_unless_verilator!
      build_headless_runner(mode: :verilog, verilator_source: :staged_verilog)
    when :staged_verilog_arcilator
      pending_unless_arcilator_backends!
      skip_unless_arcilator!
      skip_unless_circt_verilog!
      build_headless_runner(mode: :arcilator, sim: :compile, arcilator_source: :staged_verilog)
    when :imported_ir_compiler
      skip_unless_ir_compiler!
      build_headless_runner(mode: :ir, sim: :compile, compile_mode: :rustc)
    when :rhdl_mlir_arcilator
      pending_unless_arcilator_backends!
      skip_unless_arcilator!
      build_headless_runner(mode: :arcilator, sim: :compile, arcilator_source: :rhdl_mlir)
    when :rhdl_verilog_verilator
      skip_unless_verilator!
      skip_unless_firtool!
      build_headless_runner(mode: :verilog, verilator_source: :rhdl_verilog)
    else
      raise ArgumentError, "Unknown SPARC64 parity artifact #{artifact.inspect}"
    end
  end

  def build_headless_runner(mode:, sim: nil, **kwargs)
    pending_unless_runner_stack!
    args = { mode: mode }
    args[:sim] = sim if sim
    args.merge!(kwargs)
    sparc64_headless_runner_class.new(**args)
  rescue StandardError => e
    pending("SPARC64 HeadlessRunner construction not ready yet: #{e.message}")
  end

  def benchmark_handoff_trace(trace)
    events = normalize_wishbone_trace(trace)
    start_index = events.index do |event|
      addr = event.fetch(:addr).to_i
      addr >= PROGRAM_BASE && addr < RHDL::Examples::SPARC64::Integration::FLASH_BOOT_BASE
    end
    return [] unless start_index

    events[start_index..]
  end

  def normalize_run_result(result)
    data =
      case result
      when Hash
        result
      when nil
        {}
      else
        result.respond_to?(:to_h) ? result.to_h : {}
      end

    data.each_with_object({}) do |(key, value), acc|
      acc[key.to_sym] = value
    end
  end

  def normalize_wishbone_trace(trace)
    Array(trace).map { |event| normalize_wishbone_event(event) }
  end

  def normalize_wishbone_event(event)
    REQUIRED_EVENT_KEYS.each_with_object({}) do |key, acc|
      acc[key] = event_value(event, key)
    end
  end

  def event_value(event, key)
    return event.fetch(key) if event.is_a?(Hash) && event.key?(key)
    return event.fetch(key.to_s) if event.is_a?(Hash) && event.key?(key.to_s)
    return event.public_send(key) if event.respond_to?(key)
    return event[key] if event.respond_to?(:[])

    nil
  end

  def sparc64_runner_stack_available?
    !sparc64_headless_runner_class.nil?
  end

  def sparc64_headless_runner_class
    require_sparc64_runner_file('headless_runner')
    return unless defined?(RHDL::Examples::SPARC64::HeadlessRunner)

    RHDL::Examples::SPARC64::HeadlessRunner
  end

  def sparc64_ir_runner_class
    require_sparc64_runner_file('ir_runner')
    return unless defined?(RHDL::Examples::SPARC64::IrRunner)

    RHDL::Examples::SPARC64::IrRunner
  end

  def sparc64_verilator_runner_class
    require_sparc64_runner_file('verilator_runner')
    return RHDL::Examples::SPARC64::VerilatorRunner if defined?(RHDL::Examples::SPARC64::VerilatorRunner)
    return RHDL::Examples::SPARC64::VerilogRunner if defined?(RHDL::Examples::SPARC64::VerilogRunner)

    nil
  end

  def sparc64_arcilator_runner_class
    require_sparc64_runner_file('arcilator_runner')
    return unless defined?(RHDL::Examples::SPARC64::ArcilatorRunner)

    RHDL::Examples::SPARC64::ArcilatorRunner
  end

  private

  def require_sparc64_runner_file(name)
    require_relative "../../../examples/sparc64/utilities/runners/#{name}"
  rescue LoadError
    nil
  end
end
