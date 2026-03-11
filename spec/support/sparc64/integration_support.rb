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
  end

  def pending_unless_runtime_backends!
    pending('SPARC64 IR runner not implemented yet') unless sparc64_ir_runner_class
    pending('SPARC64 Verilator runner not implemented yet') unless sparc64_verilator_runner_class
  end

  def skip_unless_ir_compiler!
    skip 'IR compiler backend unavailable' unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE
  end

  def skip_unless_verilator!
    skip 'Verilator not available' unless HdlToolchain.verilator_available?
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

  def build_headless_runner(mode:, sim: nil, **kwargs)
    pending_unless_runner_stack!
    args = { mode: mode }
    args[:sim] = sim if sim
    args.merge!(kwargs)
    sparc64_headless_runner_class.new(**args)
  rescue StandardError => e
    pending("SPARC64 HeadlessRunner construction not ready yet: #{e.message}")
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

  private

  def require_sparc64_runner_file(name)
    require_relative "../../../examples/sparc64/utilities/runners/#{name}"
  rescue LoadError
    nil
  end
end
