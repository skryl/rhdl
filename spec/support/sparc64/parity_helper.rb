# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'open3'
require 'set'
require 'timeout'

require_relative '../../../examples/sparc64/utilities/import/system_importer'

module Sparc64ParityHelper
  RAISE_DEGRADE_OPS = %w[
    raise.behavior
    raise.expr
    raise.memory_read
    raise.case
    raise.sequential
  ].freeze
  PLACEHOLDER_PATTERNS = [
    /placeholder/i,
    /partial output/i,
    /unsupported/i,
    /fallback/i,
    /unable to raise/i
  ].freeze
  CLOCK_CANDIDATES = %w[
    clk
    clock
    clk_i
    clock_i
    rclk
    clk_sys
    sysclk
    sys_clock_i
  ].freeze
  RESET_CANDIDATES = %w[
    rst
    rst_i
    rstn
    rst_n
    reset
    reset_i
    resetn
    reset_n
    reset_ni
    sysrst
    sys_rst
  ].freeze
  QUIESCENT_INPUT_PATTERNS = [
    /\Ase\z/i,
    /\Asi\z/i,
    /_vld\b/i,
    /rdreq/i,
    /wrreq/i,
    /invreq/i,
    /stallreq/i,
    /quad_ld/i,
    /scan/i,
    /test/i,
    /bist/i,
    /mbist/i,
    /jtag/i
  ].freeze
  VERILATOR_WARNING_FLAGS = %w[
    --no-timing
    -Wno-fatal
    -Wno-ASCRANGE
    -Wno-MULTIDRIVEN
    -Wno-PINMISSING
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
    -Wno-UNOPTFLAT
    -Wno-CASEINCOMPLETE
  ].freeze
  VERILATOR_DEFAULT_FLAGS = %w[
    -DFPGA_SYN
    -DCMP_CLK_PERIOD=1333
  ].freeze

  module_function

  MAX_COMPILER_RUNTIME_SIGNAL_WIDTH = 128
  MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH = 128
  COMPILER_RUNTIME_EXPORT_TIMEOUT = ENV.fetch('SPARC64_COMPILER_RUNTIME_EXPORT_TIMEOUT', 60).to_f

  def diagnostic_messages(diagnostics)
    Array(diagnostics).map do |diag|
      if diag.respond_to?(:message)
        "[#{diag.respond_to?(:severity) ? diag.severity : 'warning'}]" \
          "#{diag.respond_to?(:op) && diag.op ? " #{diag.op}:" : ''} #{diag.message}"
      elsif diag.is_a?(Hash)
        "[#{diag['severity'] || diag[:severity] || 'warning'}]" \
          "#{diag['op'] || diag[:op] ? " #{diag['op'] || diag[:op]}:" : ''} #{diag['message'] || diag[:message]}"
      else
        diag.to_s
      end
    end
  end

  def degrade_diagnostics(diagnostics)
    Array(diagnostics).select do |diag|
      op = if diag.respond_to?(:op)
             diag.op.to_s
           elsif diag.is_a?(Hash)
             (diag['op'] || diag[:op]).to_s
           end
      RAISE_DEGRADE_OPS.include?(op)
    end
  end

  def placeholder_diagnostics(diagnostics)
    Array(diagnostics).select do |diag|
      message = if diag.respond_to?(:message)
                  diag.message.to_s
                elsif diag.is_a?(Hash)
                  (diag['message'] || diag[:message]).to_s
                else
                  diag.to_s
                end
      PLACEHOLDER_PATTERNS.any? { |pattern| pattern.match?(message) }
    end
  end

  def staged_verilog_semantic_report(original_path: nil, staged_path: nil, original_paths: nil, staged_paths: nil,
                                     base_dir:, module_names: nil, original_include_dirs: nil,
                                     staged_include_dirs: nil, top_module: nil)
    original_inputs = Array(original_paths || original_path).compact
    staged_inputs = Array(staged_paths || staged_path).compact
    stem = File.basename(original_inputs.first || staged_inputs.first, File.extname(original_inputs.first || staged_inputs.first))

    original_report = semantic_signature_report_for_verilog_paths(
      inputs: original_inputs,
      base_dir: File.join(base_dir, 'original'),
      stem: stem,
      include_dirs: original_include_dirs,
      top_module: top_module,
      module_names: module_names
    )
    staged_report = semantic_signature_report_for_verilog_paths(
      inputs: staged_inputs,
      base_dir: File.join(base_dir, 'staged'),
      stem: stem,
      include_dirs: staged_include_dirs,
      top_module: top_module,
      module_names: module_names
    )

    {
      match: original_report.fetch(:signature) == staged_report.fetch(:signature),
      original_signature: original_report.fetch(:signature),
      staged_signature: staged_report.fetch(:signature),
      source_only_fallback_used: original_report.fetch(:source_only_fallback_used) || staged_report.fetch(:source_only_fallback_used)
    }
  end

  def rhdl_level_report(generated_ruby_path:, original_verilog_path:, module_name:, suite_raise_diagnostics: [],
                        component_class: nil, expected_verilog_path: nil)
    source = File.read(generated_ruby_path)
    expected_verilog = File.read(expected_verilog_path || original_verilog_path)
    expected_body = module_body(expected_verilog, module_name)
    actual_level = infer_actual_rhdl_level(source)
    expected_level = infer_expected_rhdl_level(
      expected_verilog,
      module_name: module_name,
      actual_level: actual_level
    )
    if source.match?(/^\s+instance\s+/)
      expected_level = :behavioral if actual_level == :behavioral
      expected_level = :structural if actual_level == :structural
    end
    expected_level = :structural if actual_level == :structural && source.match?(/^\s+instance\s+/)
    issues = []

    issues.concat(diagnostic_messages(degrade_diagnostics(suite_raise_diagnostics)).map { |line| "raise degrade: #{line}" })
    issues.concat(
      diagnostic_messages(placeholder_diagnostics(suite_raise_diagnostics)).map { |line| "placeholder output: #{line}" }
    )

    if expected_level == :sequential && !source.include?('sequential clock:')
      issues << "expected sequential DSL for #{module_name}, but #{generated_ruby_path} does not include `sequential clock:`"
    end
    if %i[sequential behavioral].include?(expected_level) && !source.include?('behavior do')
      issues << "expected behavioral DSL for #{module_name}, but #{generated_ruby_path} does not include `behavior do`"
    end
    if expected_level == :structural && actual_level == :unknown && !outputless_module?(expected_body)
      issues << "expected at least structural DSL for #{module_name}, but #{generated_ruby_path} has no recognizable wiring/behavior blocks"
    end
    if source.match?(/TODO|unsupported|fallback/i)
      issues << "generated Ruby source for #{module_name} still contains fallback/placeholder text"
    end

    if component_class
      unless component_class.respond_to?(:verilog_module_name)
        issues << "#{component_class} does not expose `verilog_module_name`"
      end
      unless component_class.respond_to?(:to_circt_runtime_json)
        issues << "#{component_class} does not expose `to_circt_runtime_json`"
      end
      if component_class.respond_to?(:verilog_module_name) && component_class.verilog_module_name.to_s != module_name.to_s
        issues << "component class verilog_module_name=#{component_class.verilog_module_name.inspect} does not match #{module_name.inspect}"
      end
    end

    {
      expected_level: expected_level,
      actual_level: actual_level,
      source: source,
      issues: issues
    }
  end

  def deterministic_vector_plan(component_class:, functional_steps: 8, combinational_steps: 10, seed: nil)
    ports = component_ports(component_class)
    inputs = ports.reject { |port| port[:direction] == :out }
    clock_name = detect_clock_name(inputs)
    reset_info = detect_reset_info(inputs)
    seed ||= "#{component_class.respond_to?(:verilog_module_name) ? component_class.verilog_module_name : component_class.name}:sparc64"
    sequential = sequential_component?(component_class)

    steps = if sequential
              reset_steps(inputs, clock_name: clock_name, reset_info: reset_info, seed: seed) +
                functional_vector_steps(inputs, clock_name: clock_name, reset_info: reset_info,
                                        seed: seed, count: functional_steps)
            else
              functional_vector_steps(inputs, clock_name: clock_name, reset_info: reset_info,
                                      seed: seed, count: combinational_steps)
            end

    {
      clock_name: clock_name,
      reset_info: reset_info,
      sequential: sequential,
      steps: steps
    }
  end

  def ir_runtime_report(component_class:, vector_plan:)
    if (reason = compiler_parity_skip_reason(component_class: component_class))
      return {
        success: false,
        error: reason,
        fallback_allowed: true
      }
    end

    runtime_probe = compiler_runtime_probe(component_class)
    unless runtime_probe[:success]
      return {
        success: false,
        error: "IR compiler runtime export failed: #{runtime_probe[:error]}",
        fallback_allowed: true
      }
    end

    backend = ir_runtime_backend(component_class: component_class, runtime_json: runtime_probe.fetch(:runtime_json))
    sim = RHDL::Sim::Native::IR::Simulator.new(
      runtime_probe.fetch(:runtime_json),
      backend: backend,
      sub_cycles: 0
    )
    outputs = component_ports(component_class).select { |port| port[:direction] == :out }

    results = vector_plan.fetch(:steps).map do |step|
      step.fetch(:inputs).each do |name, value|
        next if name.to_s == vector_plan[:clock_name].to_s

        sim.poke(name.to_s, value)
      end

      if vector_plan[:sequential]
        if vector_plan[:clock_name]
          sim.poke(vector_plan[:clock_name], 0)
          sim.evaluate
          sim.poke(vector_plan[:clock_name], 1)
          sim.tick
          sim.poke(vector_plan[:clock_name], 0)
          sim.evaluate
        else
          sim.tick
        end
      else
        sim.evaluate
      end

      outputs.each_with_object({}) do |port, acc|
        acc[port[:name].to_sym] = normalize_value(sim.peek(port[:name]), port[:width])
      end
    end

    { success: true, results: results, backend: backend }
  rescue StandardError => e
    backend_label =
      case backend
      when :jit then 'IR JIT'
      else 'IR compiler'
      end

    { success: false, error: "#{backend_label} execution failed: #{e.message}", fallback_allowed: false }
  end

  def ruby_runtime_report(component_class:, vector_plan:)
    component = component_class.new('dut')
    outputs = component_ports(component_class).select { |port| port[:direction] == :out }

    results = vector_plan.fetch(:steps).map do |step|
      apply_component_inputs(component, step.fetch(:inputs), except: vector_plan[:clock_name])

      if vector_plan[:sequential]
        if vector_plan[:clock_name]
          drive_component_input(component, vector_plan[:clock_name], 0)
          component.propagate
          drive_component_input(component, vector_plan[:clock_name], 1)
          component.propagate
          drive_component_input(component, vector_plan[:clock_name], 0)
          component.propagate
        else
          component.propagate
        end
      else
        component.propagate
      end

      outputs.each_with_object({}) do |port, acc|
        acc[port[:name].to_sym] = normalize_value(read_component_output(component, port[:name]), port[:width])
      end
    end

    { success: true, results: results, backend: :ruby }
  rescue StandardError => e
    { success: false, error: "Ruby simulation failed: #{e.class}: #{e.message}" }
  end

  def parity_runtime_report(component_class:, vector_plan:)
    ir = ir_runtime_report(component_class: component_class, vector_plan: vector_plan)
    return ir if ir[:success]
    return ir unless ir[:fallback_allowed]

    ruby = ruby_runtime_report(component_class: component_class, vector_plan: vector_plan)
    return ruby.merge(native_ir_error: ir[:error]) if ruby[:success]

    {
      success: false,
      error: [
        ir[:error],
        ruby[:error]
      ].compact.join("\nRuby fallback also failed: ")
    }
  end

  def verilator_runtime_report(component_class:, module_name:, verilog_files:, original_verilog_path: nil,
                               staged_verilog_path: nil, base_dir:, vector_plan:, include_dirs: [],
                               extra_verilator_flags: [])
    verilator_flags = (VERILATOR_DEFAULT_FLAGS + Array(extra_verilator_flags)).uniq
    inputs = component_ports(component_class).reject { |port| port[:direction] == :out }
    outputs = component_ports(component_class).select { |port| port[:direction] == :out }
    parameter_overrides = infer_verilog_parameter_overrides(
      component_class: component_class,
      module_name: module_name,
      original_verilog_path: original_verilog_path || Array(verilog_files).first
    )
    cache_key = Digest::SHA256.hexdigest(
      JSON.generate(
        module_name: module_name,
        verilog_files: Array(verilog_files).map { |path| [path, Digest::SHA256.file(path).hexdigest] },
        staged_verilog_path: staged_verilog_path && [staged_verilog_path, Digest::SHA256.file(staged_verilog_path).hexdigest],
        include_dirs: Array(include_dirs).sort,
        vector_plan: vector_plan,
        ports: component_ports(component_class),
        parameter_overrides: parameter_overrides,
        extra_verilator_flags: verilator_flags
      )
    )
    build_dir = File.join(base_dir, "verilator_#{cache_key}")
    obj_dir = File.join(build_dir, 'obj_dir')
    FileUtils.mkdir_p(build_dir)
    FileUtils.mkdir_p(obj_dir)

    wrapper_top = "RhdlWrapper#{sanitized_module_token(module_name)}"
    wrapper_path = File.join(build_dir, 'wrapper.v')
    harness_path = File.join(build_dir, 'tb.cpp')
    binary_path = File.join(obj_dir, "V#{wrapper_top}")

    File.write(
      wrapper_path,
      wrapper_source(
        wrapper_top: wrapper_top,
        original_module_name: module_name,
        component_ports: component_ports(component_class),
        parameter_overrides: parameter_overrides,
        original_port_by_component_name: original_port_by_component_name(
          component_class: component_class,
          original_verilog_path: original_verilog_path || Array(verilog_files).first,
          staged_verilog_path: staged_verilog_path,
          module_name: module_name
        )
      )
    )
    File.write(
      harness_path,
      verilator_harness_source(
        wrapper_top: wrapper_top,
        component_ports: component_ports(component_class),
        vector_plan: vector_plan
      )
    )

    unless File.executable?(binary_path)
      cmd = [
        'verilator',
        '--cc',
        '--exe',
        '--build',
        '--top-module', wrapper_top,
        '--x-assign', '0',
        '--x-initial', '0',
        '--no-timing',
        '-O0',
        '--Mdir', obj_dir,
        *VERILATOR_WARNING_FLAGS,
        *Array(include_dirs).sort.map { |dir| "-I#{dir}" },
        *verilator_flags,
        wrapper_path,
        *Array(verilog_files),
        harness_path
      ]
      stdout, stderr, status = Open3.capture3(*cmd)
      unless status.success?
        detail = [stdout, stderr].join("\n").lines.first(200).join
        return { success: false, error: "Verilator build failed:\n#{detail}" }
      end
    end

    stdout, stderr, status = Open3.capture3(binary_path)
    unless status.success?
      detail = [stdout, stderr].join("\n").lines.first(200).join
      return { success: false, error: "Verilator run failed:\n#{detail}" }
    end

    { success: true, results: parse_verilator_samples(stdout, outputs) }
  rescue StandardError => e
    { success: false, error: "Verilator parity execution failed: #{e.message}" }
  end

  def parity_report(component_class:, module_name:, verilog_files:, base_dir:, original_verilog_path: nil,
                    staged_verilog_path: nil, include_dirs: [], extra_verilator_flags: [], vector_plan: nil)
    vector_plan ||= deterministic_vector_plan(component_class: component_class)
    runtime = parity_runtime_report(component_class: component_class, vector_plan: vector_plan)
    return runtime.merge(match: false) unless runtime[:success]

    verilator = verilator_runtime_report(
      component_class: component_class,
      module_name: module_name,
      verilog_files: verilog_files,
      original_verilog_path: original_verilog_path,
      staged_verilog_path: staged_verilog_path,
      base_dir: base_dir,
      vector_plan: vector_plan,
      include_dirs: include_dirs,
      extra_verilator_flags: extra_verilator_flags
    )
    return verilator.merge(
      match: false,
      ir_results: runtime[:results],
      runtime_results: runtime[:results],
      runtime_backend: runtime[:backend],
      native_ir_error: runtime[:native_ir_error],
      vector_plan: vector_plan
    ) unless verilator[:success]

    mismatch = first_result_mismatch(
      runtime[:results],
      verilator[:results],
      component_ports(component_class),
      steps: vector_plan.fetch(:steps)
    )
    {
      match: mismatch.nil?,
      mismatch: mismatch,
      vector_plan: vector_plan,
      ir_results: runtime[:results],
      runtime_results: runtime[:results],
      runtime_backend: runtime[:backend],
      native_ir_error: runtime[:native_ir_error],
      verilator_results: verilator[:results]
    }
  end

  def component_ports(component_class)
    Array(component_class._ports).map do |port|
      {
        name: port.name.to_s,
        direction: port.direction.to_sym,
        width: [port.width.to_i, 1].max
      }
    end.uniq { |port| port[:name] }
  end

  def parity_skip_reason(component_class:)
    return 'verilator not available' unless HdlToolchain.verilator_available?

    nil
  end

  def compiler_parity_skip_reason(component_class:)
    unless RHDL::Sim::Native::IR::COMPILER_AVAILABLE || RHDL::Sim::Native::IR::JIT_AVAILABLE
      return 'IR native parity backend unavailable'
    end

    runtime_probe = compiler_runtime_probe(component_class)
    unless runtime_probe[:success]
      return "IR native parity runtime export is not available for #{component_class}: #{runtime_probe[:error]}"
    end

    runtime_json = runtime_probe[:runtime_json]

    unsupported_ports = unsupported_ir_ports(component_class, max_width: MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH)
    unless unsupported_ports.empty?
      port_list = unsupported_ports.first(8).map do |port|
        "#{port[:name]}(#{port[:width]})"
      end.join(', ')
      suffix = unsupported_ports.length > 8 ? ', ...' : ''
      max_width = unsupported_ports.map { |port| port[:width].to_i }.max.to_i

      return "IR native parity currently supports inspected component ports up to #{MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH} bits; " \
             "#{component_class} exposes #{port_list}#{suffix} (max #{max_width})"
    end

    unsupported_signals = unsupported_ir_internal_signals(
      runtime_json: runtime_json,
      max_width: MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH
    )
    unless unsupported_signals.empty?
      signal_list = unsupported_signals.first(8).map do |signal|
        "#{signal[:name]}(#{signal[:width]})"
      end.join(', ')
      suffix = unsupported_signals.length > 8 ? ', ...' : ''
      max_width = unsupported_signals.map { |signal| signal[:width].to_i }.max.to_i

      return "IR native parity currently supports flattened internal signals up to #{MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH} bits; " \
             "#{component_class} exposes #{signal_list}#{suffix} (max #{max_width})"
    end

    backend = ir_runtime_backend(component_class: component_class, runtime_json: runtime_json)
    return nil if backend == :compiler || backend == :jit

    case backend
    when :jit_required_for_ports
      unsupported_ports = unsupported_ir_ports(component_class)
      port_list = unsupported_ports.first(8).map do |port|
        "#{port[:name]}(#{port[:width]})"
      end.join(', ')
      suffix = unsupported_ports.length > 8 ? ', ...' : ''
      max_width = unsupported_ports.map { |port| port[:width].to_i }.max.to_i

      "IR native parity requires the IR JIT backend for inspected component ports wider than #{MAX_COMPILER_RUNTIME_SIGNAL_WIDTH} bits; " \
        "#{component_class} exposes #{port_list}#{suffix} (max #{max_width})"
    when :jit_required_for_internal_signals
      unsupported_signals = unsupported_ir_internal_signals(runtime_json: runtime_json)
      signal_list = unsupported_signals.first(8).map do |signal|
        "#{signal[:name]}(#{signal[:width]})"
      end.join(', ')
      suffix = unsupported_signals.length > 8 ? ', ...' : ''
      max_width = unsupported_signals.map { |signal| signal[:width].to_i }.max.to_i

      "IR native parity requires the IR JIT backend for flattened internal signals wider than #{MAX_COMPILER_RUNTIME_SIGNAL_WIDTH} bits; " \
        "#{component_class} exposes #{signal_list}#{suffix} (max #{max_width})"
    else
      'IR native parity backend unavailable'
    end

  rescue StandardError => e
    port_max_width = component_ports(component_class).map { |port| port[:width].to_i }.max.to_i
    if port_max_width > MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH
      "IR native parity currently supports inspected component ports up to #{MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH} bits; " \
        "#{component_class} exposes ports up to #{port_max_width} bits"
    else
      "IR native parity runtime export is not available for #{component_class}: #{e.message}"
    end
  end

  def ir_runtime_backend(component_class:, runtime_json:)
    compiler_unsupported_ports = unsupported_ir_ports(component_class)
    compiler_unsupported_signals = unsupported_ir_internal_signals(runtime_json: runtime_json)

    if compiler_unsupported_ports.empty? && compiler_unsupported_signals.empty?
      return :compiler if RHDL::Sim::Native::IR::COMPILER_AVAILABLE
      return :jit if RHDL::Sim::Native::IR::JIT_AVAILABLE

      return :backend_unavailable
    end

    return :jit if RHDL::Sim::Native::IR::JIT_AVAILABLE && native_ir_supported?(component_class: component_class, runtime_json: runtime_json)
    return :jit_required_for_ports unless compiler_unsupported_ports.empty?
    return :jit_required_for_internal_signals unless compiler_unsupported_signals.empty?

    :backend_unavailable
  end

  def native_ir_supported?(component_class:, runtime_json:)
    unsupported_ir_ports(component_class, max_width: MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH).empty? &&
      unsupported_ir_internal_signals(runtime_json: runtime_json, max_width: MAX_NATIVE_IR_RUNTIME_SIGNAL_WIDTH).empty?
  end

  def unsupported_ir_ports(component_class, max_width: MAX_COMPILER_RUNTIME_SIGNAL_WIDTH)
    component_ports(component_class).select { |port| port[:width].to_i > max_width.to_i }
  end

  def unsupported_ir_internal_signals(runtime_json:, max_width: MAX_COMPILER_RUNTIME_SIGNAL_WIDTH)
    runtime_internal_signals(runtime_json).select { |signal| signal[:width].to_i > max_width.to_i }
  end

  def runtime_internal_signals(runtime_json)
    runtime_module = first_runtime_module(runtime_json)
    [
      *runtime_signal_entries(runtime_module['nets']),
      *runtime_signal_entries(runtime_module['regs']),
      *runtime_memory_entries(runtime_module['memories'])
    ].uniq { |signal| signal[:name] }
  end

  def first_runtime_module(runtime_json)
    payload =
      if runtime_json.is_a?(String)
        JSON.parse(runtime_json, max_nesting: false)
      else
        runtime_json
      end

    modules =
      if payload.is_a?(Hash)
        payload['modules'] || payload[:modules]
      else
        []
      end
    Array(modules).first || {}
  end

  def runtime_signal_entries(entries)
    Array(entries).filter_map do |entry|
      width = (entry['width'] || entry[:width]).to_i
      next if width <= 0

      {
        name: (entry['name'] || entry[:name]).to_s,
        width: width
      }
    end
  end

  def runtime_memory_entries(entries)
    Array(entries).filter_map do |entry|
      width = (entry['width'] || entry[:width]).to_i
      next if width <= 0

      {
        name: (entry['name'] || entry[:name]).to_s,
        width: width
      }
    end
  end

  def sequential_component?(component_class, seen = Set.new)
    return false unless component_class.is_a?(Class)

    token = component_class.object_id
    return false if seen.include?(token)

    seen << token

    return true if component_class <= RHDL::Sim::SequentialComponent

    Array(component_class.respond_to?(:_instance_defs) ? component_class._instance_defs : []).any? do |instance_def|
      child_class = instance_def[:component_class]
      sequential_component?(child_class, seen)
    end
  rescue StandardError
    false
  end

  def detect_clock_name(input_ports)
    names = Array(input_ports).map { |port| port[:name].to_s }
    CLOCK_CANDIDATES.find { |candidate| names.include?(candidate) } ||
      names.find { |name| name.match?(/\A(?:clk|clock)(?:_|$)/i) }
  end

  def detect_reset_info(input_ports)
    names = Array(input_ports).map { |port| port[:name].to_s }
    ranked_candidates = names.filter_map.with_index do |candidate, index|
      score = reset_detection_score(candidate)
      next unless score.positive?

      [candidate, score, index]
    end
    name = ranked_candidates.max_by { |candidate, score, index| [score, -index] }&.first
    return nil unless name

    { name: name, active_low: active_low_reset_name?(name) }
  end

  def reset_detection_score(name)
    value = name.to_s
    return 0 unless reset_like_input_name?(value)

    score = 0
    score += 100 if RESET_CANDIDATES.include?(value)
    score += 80 if active_low_reset_name?(value)
    score += 40 if value.match?(/\A(?:[ag]?rst|[ag]?reset|sysrst)(?:$|_)/i)
    score -= 120 if value.match?(/(?:^|_)(?:en|enable)(?:$|_)/i) || value.end_with?('_en', '_enable')
    score -= 80 if value.match?(/(?:^|_)(?:tri|scan|bist|mbist|test|jtag)(?:$|_)/i)
    score
  end

  def active_low_reset_name?(name)
    value = name.to_s
    value.match?(/(?:^|_)(?:rstn|resetn|rst_n|reset_n|reset_ni|nreset)(?:$|_)/i) ||
      value.match?(/\A(?:[ag]?rst|[ag]?reset)(?:_l|_n|n)\z/i)
  end

  def reset_like_input_name?(name)
    value = name.to_s
    RESET_CANDIDATES.include?(value) ||
      value.match?(/\A(?:[ag]?rst|[ag]?reset|sysrst)(?:$|_)/i) ||
      value.match?(/\A(?:[ag]?rst|[ag]?reset|sysrst)(?:_l|_n|n)\z/i)
  end

  def reset_steps(inputs, clock_name:, reset_info:, seed:)
    return functional_vector_steps(inputs, clock_name: clock_name, reset_info: reset_info, seed: seed, count: 2) unless reset_info

    2.times.map do |index|
      {
        tag: :reset,
        inputs: build_inputs_for_step(
          inputs,
          clock_name: clock_name,
          reset_info: reset_info,
          functional_index: index,
          seed: seed,
          reset_state: :asserted
        )
      }
    end
  end

  def functional_vector_steps(inputs, clock_name:, reset_info:, seed:, count:)
    count.times.map do |index|
      {
        tag: :functional,
        inputs: build_inputs_for_step(
          inputs,
          clock_name: clock_name,
          reset_info: reset_info,
          functional_index: index,
          seed: seed,
          reset_state: :inactive
        )
      }
    end
  end

  def build_inputs_for_step(inputs, clock_name:, reset_info:, functional_index:, seed:, reset_state:)
    Array(inputs).each_with_object({}) do |port, acc|
      name = port[:name].to_s
      next if name == clock_name

      width = port[:width].to_i
      if reset_info && name == reset_info[:name]
        acc[name] = reset_state == :asserted ? asserted_reset_value(reset_info) : inactive_reset_value(reset_info)
      elsif reset_like_input_name?(name)
        acc[name] = inactive_reset_value(name: name, active_low: active_low_reset_name?(name))
      elsif quiescent_input_name?(name)
        acc[name] = safe_default_value(name, width)
      else
        acc[name] = deterministic_input_value(name, width, functional_index, seed)
      end
    end
  end

  def quiescent_input_name?(name)
    QUIESCENT_INPUT_PATTERNS.any? { |pattern| pattern.match?(name.to_s) }
  end

  def safe_default_value(name, width)
    if active_low_reset_name?(name)
      normalize_value(1, width)
    else
      0
    end
  end

  def asserted_reset_value(reset_info)
    reset_info[:active_low] ? 0 : 1
  end

  def inactive_reset_value(reset_info = nil, name: nil, active_low: nil)
    if reset_info.is_a?(Hash)
      name = reset_info[:name]
      active_low = reset_info[:active_low]
    elsif !reset_info.nil? && name.nil?
      active_low = reset_info
    end

    resolved_active_low = active_low.nil? ? active_low_reset_name?(name) : active_low
    resolved_active_low ? 1 : 0
  end

  def deterministic_input_value(name, width, functional_index, seed)
    return 0 if width <= 0

    mask = value_mask(width)
    case functional_index % 5
    when 0
      0
    when 1
      mask
    when 2
      normalize_value(alternating_pattern(width, 'a'), width)
    when 3
      normalize_value(alternating_pattern(width, '5'), width)
    else
      digest = Digest::SHA256.hexdigest("#{seed}:#{name}:#{functional_index}")
      normalize_value(digest.to_i(16), width)
    end
  end

  def alternating_pattern(width, nibble)
    digits = [(width / 4.0).ceil, 1].max
    ([nibble] * digits).join.to_i(16)
  end

  def first_result_mismatch(lhs, rhs, ports, steps: nil)
    return 'result count mismatch' unless lhs.length == rhs.length

    output_ports = Array(ports).select { |port| port[:direction] == :out }
    lhs.each_with_index do |lhs_result, idx|
      next if Array(steps)[idx]&.fetch(:tag, nil) == :reset

      rhs_result = rhs[idx] || {}
      output_ports.each do |port|
        key = port[:name].to_sym
        width = port[:width].to_i
        next if normalize_value(lhs_result[key], width) == normalize_value(rhs_result[key], width)

        return "vector #{idx} output #{key} mismatch ir=#{lhs_result[key].inspect} verilator=#{rhs_result[key].inspect}"
      end
    end

    nil
  end

  def apply_component_inputs(component, inputs, except: nil)
    Array(inputs).each do |name, value|
      next if name.to_s == except.to_s

      drive_component_input(component, name, value)
    end
  end

  def drive_component_input(component, name, value)
    key = component_signal_key(component.inputs, name)
    component.set_input(key, value)
  end

  def read_component_output(component, name)
    key = component_signal_key(component.outputs, name)
    component.get_output(key)
  end

  def component_signal_key(signal_hash, name)
    return name if signal_hash.key?(name)

    symbolized = name.to_sym
    return symbolized if signal_hash.key?(symbolized)

    raise KeyError, "unknown component signal #{name.inspect}"
  end

  def normalized_semantic_signature_from_verilog(verilog_source, base_dir:, stem:)
    mlir = convert_verilog_to_mlir(verilog_source, base_dir: base_dir, stem: stem)
    normalized_semantic_signature_from_mlir(mlir)
  end

  def semantic_signature_report_for_verilog_paths(inputs:, base_dir:, stem:, include_dirs:, top_module:, module_names:)
    primary_path = Array(inputs).first
    extra_paths = Array(inputs).drop(1)
    signature = normalized_semantic_signature_from_verilog_path(
      primary_path,
      base_dir: base_dir,
      stem: stem,
      extra_verilog_paths: extra_paths,
      include_dirs: include_dirs,
      top_module: top_module,
      module_names: module_names
    )
    {
      signature: signature,
      source_only_fallback_used: false
    }
  rescue StandardError
    raise if extra_paths.empty?

    signature = normalized_semantic_signature_from_verilog_path(
      primary_path,
      base_dir: File.join(base_dir, 'source_only'),
      stem: stem,
      extra_verilog_paths: [],
      include_dirs: include_dirs,
      top_module: top_module,
      module_names: module_names
    )
    {
      signature: signature,
      source_only_fallback_used: true
    }
  end

  def normalized_semantic_signature_from_verilog_path(verilog_path, base_dir:, stem:, module_names: nil,
                                                      extra_verilog_paths: [], include_dirs: nil, top_module: nil)
    normalized_source = normalized_verilog_for_semantic_compare(File.read(verilog_path), source_path: verilog_path)
    selected_modules = Array(module_names || module_names_in_verilog_source(normalized_source)).map(&:to_s).sort
    mlir = convert_verilog_path_to_mlir(
      verilog_path,
      base_dir: base_dir,
      stem: stem,
      normalized_source: normalized_source,
      extra_verilog_paths: extra_verilog_paths,
      include_dirs: include_dirs,
      top_module: top_module
    )
    normalized_semantic_signature_from_mlir(mlir, module_names: selected_modules)
  end

  def convert_verilog_to_mlir(verilog_source, base_dir:, stem:)
    raise 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')

    FileUtils.mkdir_p(base_dir)
    verilog_path = File.join(base_dir, "#{stem}.v")
    core_mlir_path = File.join(base_dir, "#{stem}.core.mlir")
    File.write(verilog_path, verilog_source)

    result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
      verilog_path: verilog_path,
      out_path: core_mlir_path,
      tool: 'circt-verilog'
    )
    raise "Verilog->CIRCT failed:\n#{result[:command]}\n#{result[:stderr]}" unless result[:success]

    File.read(core_mlir_path)
  end

  def convert_verilog_path_to_mlir(verilog_path, base_dir:, stem:, normalized_source: nil, extra_verilog_paths: [],
                                   include_dirs: nil, top_module: nil)
    raise 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')

    FileUtils.mkdir_p(base_dir)
    core_mlir_path = File.join(base_dir, "#{stem}.core.mlir")
    normalized_path = File.join(base_dir, "#{stem}.normalized.v")
    source = normalized_source || normalized_verilog_for_semantic_compare(File.read(verilog_path), source_path: verilog_path)
    File.write(normalized_path, source)
    normalized_extra_paths = Array(extra_verilog_paths).each_with_index.map do |path, index|
      extra_source = normalized_verilog_for_semantic_compare(File.read(path), source_path: path)
      normalized_extra_path = File.join(base_dir, "#{stem}.extra_#{index}.v")
      File.write(normalized_extra_path, extra_source)
      normalized_extra_path
    end
    known_module_names = normalized_extra_paths.flat_map do |path|
      module_names_in_verilog_source(File.read(path))
    end.to_set
    support_stub_path = write_semantic_support_stubs(
      sources: [source, *normalized_extra_paths.map { |path| File.read(path) }],
      base_dir: base_dir,
      stem: stem,
      known_module_names: known_module_names
    )

    result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
      verilog_path: normalized_path,
      out_path: core_mlir_path,
      tool: 'circt-verilog',
      extra_args: inferred_verilog_tool_args(
        verilog_path,
        extra_verilog_paths: extra_verilog_paths,
        include_dirs: include_dirs,
        top_module: top_module
      ) +
        [support_stub_path, *normalized_extra_paths]
    )
    raise "Verilog->CIRCT failed:\n#{result[:command]}\n#{result[:stderr]}" unless result[:success]

    File.read(core_mlir_path)
  end

  def normalized_semantic_signature_from_mlir(mlir, module_names: nil)
    import_result = RHDL::Codegen.import_circt_mlir(mlir)
    raise "CIRCT import failed:\n#{diagnostic_messages(import_result.diagnostics).join("\n")}" unless import_result.success?

    selected = Array(module_names).map(&:to_s)
    modules = if selected.empty?
                import_result.modules
              else
                import_result.modules.select { |mod| selected.include?(mod.name.to_s) }
              end
    if selected.any?
      found = modules.map { |mod| mod.name.to_s }
      missing = selected - found
      raise "CIRCT import missing expected modules: #{missing.join(', ')}" if missing.any?
    end
    stable_sort(modules.map { |mod| [mod.name.to_s, semantic_signature_for_module(mod)] })
  end

  def semantic_signature_for_module(mod)
    {
      parameters: stable_sort((mod.parameters || {}).map { |key, value| [key.to_s, value] }),
      ports: stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
      regs: stable_sort(mod.regs.map { |reg| [reg.width.to_i, reg.reset_value] }),
      assigns: stable_sort(mod.assigns.map { |assign| expr_signature(assign.expr) }),
      processes: stable_sort(mod.processes.map { |process| process_signature(process) }),
      instances: stable_sort(mod.instances.map { |inst| instance_signature(inst) })
    }
  end

  def process_signature(process)
    {
      clocked: !!process.clocked,
      statements: Array(process.statements).map { |stmt| statement_signature(stmt) }
    }
  end

  def statement_signature(stmt)
    case stmt
    when RHDL::Codegen::CIRCT::IR::SeqAssign
      [:seq_assign, expr_signature(stmt.expr)]
    when RHDL::Codegen::CIRCT::IR::If
      [
        :if,
        expr_signature(stmt.condition),
        Array(stmt.then_statements).map { |s| statement_signature(s) },
        Array(stmt.else_statements).map { |s| statement_signature(s) }
      ]
    else
      [:stmt, stmt.class.name]
    end
  end

  def instance_signature(inst)
    {
      module: inst.module_name.to_s,
      parameters: stable_sort((inst.parameters || {}).map { |key, value| [key.to_s, value] }),
      connections: stable_sort(
        Array(inst.connections).map { |conn| [conn.direction.to_s, conn.port_name.to_s] }
      )
    }
  end

  def expr_signature(expr)
    case expr
    when RHDL::Codegen::CIRCT::IR::Signal
      [:signal, expr.width.to_i]
    when RHDL::Codegen::CIRCT::IR::Literal
      [:literal, expr.width.to_i, expr.value]
    when RHDL::Codegen::CIRCT::IR::UnaryOp
      [:unary, expr.op.to_s, expr.width.to_i, expr_signature(expr.operand)]
    when RHDL::Codegen::CIRCT::IR::BinaryOp
      left = expr_signature(expr.left)
      right = expr_signature(expr.right)
      left, right = stable_sort([left, right]) if commutative_binop?(expr.op)
      [:binary, expr.op.to_s, expr.width.to_i, left, right]
    when RHDL::Codegen::CIRCT::IR::Mux
      [:mux, expr.width.to_i, expr_signature(expr.condition), expr_signature(expr.when_true), expr_signature(expr.when_false)]
    when RHDL::Codegen::CIRCT::IR::Concat
      [:concat, expr.width.to_i, expr.parts.map { |part| expr_signature(part) }]
    when RHDL::Codegen::CIRCT::IR::Slice
      reduced = reduced_slice_signature(expr)
      return reduced if reduced

      [:slice, expr.width.to_i, expr_signature(expr.base), expr.range.min, expr.range.max]
    when RHDL::Codegen::CIRCT::IR::Resize
      [:resize, expr.width.to_i, expr_signature(expr.expr)]
    when RHDL::Codegen::CIRCT::IR::Case
      cases = stable_sort(expr.cases.map { |key, value| [key, expr_signature(value)] })
      [:case, expr.width.to_i, expr_signature(expr.selector), cases, expr_signature(expr.default)]
    when RHDL::Codegen::CIRCT::IR::MemoryRead
      [:memory_read, expr.memory.to_s, expr.width.to_i, expr_signature(expr.addr)]
    else
      width = expr.respond_to?(:width) ? expr.width.to_i : nil
      [:expr, expr.class.name, width]
    end
  end

  def reduced_slice_signature(expr)
    return nil unless expr.range.min == 0
    return nil unless expr.range.max == (expr.width.to_i - 1)
    return nil unless expr.base.is_a?(RHDL::Codegen::CIRCT::IR::BinaryOp)

    bin = expr.base
    left = maybe_unpadded_operand_signature(bin.left, expr.width.to_i)
    right = maybe_unpadded_operand_signature(bin.right, expr.width.to_i)
    return nil unless left && right

    left, right = stable_sort([left, right]) if commutative_binop?(bin.op)
    [:binary, bin.op.to_s, expr.width.to_i, left, right]
  end

  def maybe_unpadded_operand_signature(expr, width)
    return expr_signature(expr) if expr.respond_to?(:width) && expr.width.to_i == width

    return nil unless expr.is_a?(RHDL::Codegen::CIRCT::IR::Concat)
    return nil unless expr.width.to_i == width + 1
    return nil unless expr.parts.length == 2

    high, low = expr.parts
    return nil unless high.is_a?(RHDL::Codegen::CIRCT::IR::Literal)
    return nil unless high.width.to_i == 1 && high.value.to_i.zero?
    return nil unless low.respond_to?(:width) && low.width.to_i == width

    expr_signature(low)
  end

  def stable_sort(items)
    items.sort_by { |item| Marshal.dump(item) }
  end

  def commutative_binop?(op)
    %i[+ * & | ^ == !=].include?(op.to_sym)
  end

  def infer_expected_rhdl_level(verilog_source, module_name:, actual_level: nil)
    body = module_body(verilog_source, module_name)
    return :structural if outputless_module?(body)
    return :structural if actual_level == :structural && structural_wrapper_candidate?(body)
    return :behavioral if active_low_async_reset_module?(body)
    return :sequential if body.match?(/\balways(?:_ff|_comb|_latch)?\s*@\s*\([^)]*(?:posedge|negedge)[^)]*\)/m)
    return :behavioral if body.match?(/\balways(?:_ff|_comb|_latch)?\s*@/m)
    return :behavioral if body.match?(/\bassign\b/m)

    :structural
  end

  def infer_actual_rhdl_level(source)
    return :sequential if source.include?('sequential clock:')
    return :behavioral if source.include?('behavior do')
    return :structural if source.match?(/^\s+(?:wire|instance|port)\s+/)

    :unknown
  end

  def module_body(verilog_source, module_name)
    stripped = strip_comments(verilog_source)
    match = stripped.match(/\bmodule\s+#{Regexp.escape(module_name.to_s)}\b(.*?)\bendmodule\b/m)
    raise "Unable to find module #{module_name.inspect} in Verilog source" unless match

    match[1]
  end

  def structural_wrapper_candidate?(module_body_text)
    instance_count = module_body_text.scan(
      /\b([A-Za-z_][A-Za-z0-9_$]*)\s*(?:#\s*(?:\([^;]*?\)|\d+))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/m
    ).count do |target, _instance_name|
      !RHDL::Examples::SPARC64::Import::SystemImporter::INSTANCE_KEYWORDS.include?(target) && target != 'endcase'
    end
    instance_count.positive?
  end

  def outputless_module?(module_body_text)
    !module_body_text.match?(/^\s*(?:output|inout)\b/m)
  end

  def active_low_async_reset_module?(module_body_text)
    sensitivity = module_body_text[/\balways(?:_ff|_comb|_latch)?\s*@\s*\(([^)]*)\)/m, 1]
    return false unless sensitivity

    edge_terms = sensitivity.split(/\bor\b|,/).map(&:strip).select { |term| term.match?(/\b(?:posedge|negedge)\b/i) }
    return false unless edge_terms.length >= 2

    edge_terms.any? do |term|
      term.match?(/\bnegedge\s+(?:rst|reset)[A-Za-z0-9_$]*\b/i) ||
        term.match?(/\bnegedge\s+[A-Za-z_][A-Za-z0-9_$]*(?:_l|_n)\b/i)
    end
  end

  def strip_comments(text)
    text
      .gsub(%r{//.*$}, '')
      .gsub(%r{/\*.*?\*/}m, '')
  end

  def original_port_by_component_name(component_class:, original_verilog_path:, staged_verilog_path:, module_name:)
    component_names = component_ports(component_class).map { |port| port[:name].to_s }
    original_order = parse_port_order(File.read(original_verilog_path), module_name)
    staged_order = if staged_verilog_path
                     parse_port_order(File.read(staged_verilog_path), module_name)
                   else
                     original_order.dup
                   end

    index_by_staged_name = staged_order.each_with_index.to_h
    original_name_by_sanitized_name = unique_mapping(original_order) { |name| sanitized_rhdl_identifier(name) }
    staged_index_by_sanitized_name = unique_mapping(staged_order.each_with_index.to_a) do |(name, _)|
      sanitized_rhdl_identifier(name)
    end
    component_names.each_with_index.each_with_object({}) do |(name, fallback_index), mapping|
      if original_order.include?(name)
        mapping[name] = name
        next
      end

      if original_name_by_sanitized_name.key?(name)
        mapping[name] = original_name_by_sanitized_name.fetch(name)
        next
      end

      idx = index_by_staged_name[name] || staged_index_by_sanitized_name[name] || fallback_index
      mapping[name] = original_order.fetch(idx, name)
    end
  end

  def parse_port_order(verilog_source, module_name)
    stripped = strip_comments(verilog_source)
    match = stripped.match(/\bmodule\s+#{Regexp.escape(module_name.to_s)}\b\s*(?:#\s*\(.*?\)\s*)?\((.*?)\)\s*;/m)
    raise "Unable to parse port order for #{module_name.inspect}" unless match

    header = match[1]
    header = header.gsub(/\b(?:input|output|inout|wire|reg|logic|signed)\b/, ' ')
    header = header.gsub(/\[[^\]]+\]/, ' ')
    header.split(',').map do |token|
      cleaned = token.strip.gsub(/\s+/, ' ')
      cleaned.split(' ').last
    end.compact.reject(&:empty?)
  end

  def infer_verilog_parameter_overrides(component_class:, module_name:, original_verilog_path:)
    source = File.read(original_verilog_path)
    parameter_names = parse_module_parameter_names(source, module_name)
    return {} if parameter_names.empty?

    multibit_widths = component_ports(component_class).map { |port| port[:width].to_i }.select { |width| width > 1 }.uniq
    return {} if multibit_widths.empty?

    return { parameter_names.first => multibit_widths.max } if parameter_names.one?

    {}
  rescue Errno::ENOENT
    {}
  end

  def parse_module_parameter_names(verilog_source, module_name)
    module_body(verilog_source, module_name).scan(/^\s*parameter\s+([A-Za-z_][A-Za-z0-9_$]*)\s*=/).flatten.uniq
  end

  def unique_mapping(entries)
    Array(entries)
      .group_by { |entry| yield(entry) }
      .each_with_object({}) do |(key, grouped_entries), acc|
        next unless grouped_entries.one?

        acc[key] = block_given? ? yield_unique_mapping_value(grouped_entries.first) : grouped_entries.first
      end
  end

  def yield_unique_mapping_value(entry)
    entry.is_a?(Array) ? entry.last : entry
  end

  def sanitized_rhdl_identifier(name)
    value = name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
    value = "_#{value}" if value.empty? || value.match?(/\A\d/)
    value = "_#{value}" if rhdl_reserved_identifier?(value)
    value
  end

  def rhdl_reserved_identifier?(value)
    reserved = %w[
      BEGIN END alias and begin break case class def defined? do else elsif end ensure false for if in module
      next nil not or redo rescue retry return self super then true undef unless until when while yield
      __FILE__ __LINE__ __ENCODING__
    ]
    reserved.include?(value.to_s) || value.to_s.match?(/\A_[1-9]\d*\z/)
  end

  def wrapper_source(wrapper_top:, original_module_name:, component_ports:, parameter_overrides:,
                     original_port_by_component_name:)
    lines = []
    lines << '`timescale 1ns/1ps'
    lines << "module #{wrapper_top}("
    lines << component_ports.map { |port| "  #{port[:name]}" }.join(",\n")
    lines << ');'
    component_ports.each do |port|
      lines << "  #{wrapper_direction(port[:direction])}#{wrapper_width(port[:width])} #{port[:name]};"
    end
    lines << ''
    lines << "  #{original_module_name}#{wrapper_parameter_suffix(parameter_overrides)} uut ("
    lines << component_ports.map do |port|
      original_name = original_port_by_component_name.fetch(port[:name], port[:name])
      "    .#{original_name}(#{port[:name]})"
    end.join(",\n")
    lines << '  );'
    lines << 'endmodule'
    lines.join("\n")
  end

  def wrapper_direction(direction)
    direction == :out ? 'output' : 'input'
  end

  def wrapper_width(width)
    width.to_i > 1 ? " [#{width.to_i - 1}:0]" : ''
  end

  def sanitized_module_token(module_name)
    module_name.to_s.gsub(/[^A-Za-z0-9_]/, '_')
  end

  def wrapper_parameter_suffix(parameter_overrides)
    return '' if parameter_overrides.nil? || parameter_overrides.empty?

    assignments = parameter_overrides.sort_by { |name, _| name.to_s }.map do |name, value|
      ".#{name}(#{value})"
    end
    " #(\n    #{assignments.join(",\n    ")}\n  )"
  end

  def verilator_harness_source(wrapper_top:, component_ports:, vector_plan:)
    inputs = Array(component_ports).reject { |port| port[:direction] == :out }
    outputs = Array(component_ports).select { |port| port[:direction] == :out }
    clock_name = vector_plan[:clock_name]
    sequential = vector_plan[:sequential]

    lines = []
    lines << "#include \"V#{wrapper_top}.h\""
    lines << '#include "verilated.h"'
    lines << '#include <cstdint>'
    lines << '#include <cstdio>'
    lines << ''
    lines << 'static void print_wide_hex(const uint32_t* words, int word_count, int width) {'
    lines << '  int digits = (width + 3) / 4;'
    lines << '  for (int idx = word_count - 1; idx >= 0; --idx) {'
    lines << '    int chunk_digits = digits - (idx * 8);'
    lines << '    if (chunk_digits > 8) chunk_digits = 8;'
    lines << '    if (chunk_digits <= 0) chunk_digits = 1;'
    lines << '    std::printf("%0*x", chunk_digits, words[idx]);'
    lines << '  }'
    lines << '}'
    lines << ''
    lines << 'static void apply_inputs(V' + wrapper_top + '* dut, int idx) {'
    lines << '  switch (idx) {'
    vector_plan.fetch(:steps).each_with_index do |step, index|
      lines << "    case #{index}:"
      inputs.each do |port|
        value = step.fetch(:inputs).fetch(port[:name], safe_default_value(port[:name], port[:width]))
        lines.concat(verilator_assign_lines(target: "dut->#{port[:name]}", width: port[:width], value: value).map { |line| "      #{line}" })
      end
      lines << '      break;'
    end
    lines << '    default:'
    lines << '      break;'
    lines << '  }'
    lines << '}'
    lines << ''
    lines << 'static void emit_outputs(V' + wrapper_top + '* dut, int idx) {'
    lines << '  std::printf("SAMPLE %d", idx);'
    outputs.each do |port|
      lines.concat(verilator_print_lines(target: "dut->#{port[:name]}", name: port[:name], width: port[:width]).map { |line| "  #{line}" })
    end
    lines << '  std::printf("\\n");'
    lines << '}'
    lines << ''
    lines << 'int main(int argc, char** argv) {'
    lines << '  Verilated::commandArgs(argc, argv);'
    lines << "  V#{wrapper_top}* dut = new V#{wrapper_top}();"
    if clock_name
      lines << "  dut->#{clock_name} = 0;"
    end
    lines << "  for (int idx = 0; idx < #{vector_plan.fetch(:steps).length}; ++idx) {"
    lines << '    apply_inputs(dut, idx);'
    if sequential
      if clock_name
        lines << "    dut->#{clock_name} = 0;"
        lines << '    dut->eval();'
        lines << "    dut->#{clock_name} = 1;"
        lines << '    dut->eval();'
        lines << "    dut->#{clock_name} = 0;"
        lines << '    dut->eval();'
      else
        lines << '    dut->eval();'
      end
    else
      lines << '    dut->eval();'
    end
    lines << '    emit_outputs(dut, idx);'
    lines << '  }'
    lines << '  dut->final();'
    lines << '  delete dut;'
    lines << '  return 0;'
    lines << '}'
    lines.join("\n")
  end

  def verilator_assign_lines(target:, width:, value:)
    if width.to_i > 64
      words = split_words(normalize_value(value, width), width)
      words.each_with_index.map do |word, index|
        "#{target}[#{index}] = 0x#{format('%08x', word)}U;"
      end
    elsif width.to_i > 32
      ["#{target} = 0x#{normalize_value(value, width).to_s(16)}ULL;"]
    else
      ["#{target} = 0x#{normalize_value(value, width).to_s(16)}U;"]
    end
  end

  def verilator_print_lines(target:, name:, width:)
    digits = [(width.to_i / 4.0).ceil, 1].max
    if width.to_i > 64
      word_count = split_words(0, width).length
      [
        "std::printf(\" #{name}=\");",
        "print_wide_hex(#{target}, #{word_count}, #{width.to_i});"
      ]
    elsif width.to_i > 32
      ["std::printf(\" #{name}=%0#{digits}llx\", static_cast<unsigned long long>(#{target}));"]
    else
      ["std::printf(\" #{name}=%0#{digits}x\", static_cast<unsigned int>(#{target}));"]
    end
  end

  def split_words(value, width)
    word_count = [(width.to_i + 31) / 32, 1].max
    masked = normalize_value(value, width)
    Array.new(word_count) do |index|
      ((masked >> (index * 32)) & 0xFFFF_FFFF)
    end
  end

  def parse_verilator_samples(stdout, outputs)
    stdout.lines.filter_map do |line|
      next unless line.start_with?('SAMPLE ')

      sample = {}
      line.strip.split(' ').drop(2).each do |pair|
        key, value = pair.split('=')
        next unless key && value

        port = Array(outputs).find { |entry| entry[:name] == key }
        next unless port

        sample[key.to_sym] = normalize_value(value.to_i(16), port[:width])
      end
      sample
    end
  end

  def normalize_value(value, width)
    return 0 if width.to_i <= 0

    value.to_i & value_mask(width)
  end

  def value_mask(width)
    (1 << width.to_i) - 1
  end

  def inferred_verilog_tool_args(verilog_path, extra_verilog_paths: [], include_dirs: nil, top_module: nil)
    paths = [verilog_path, *Array(extra_verilog_paths)].map { |path| File.expand_path(path) }.uniq
    args = ['--ignore-unknown-modules', '--allow-use-before-declare', '--timescale=1ns/1ps', '-DFPGA_SYN']
    args.concat(['--top', top_module.to_s]) if top_module
    dirs = if include_dirs
             Array(include_dirs).map { |dir| File.expand_path(dir) }.uniq.sort
           else
             paths.flat_map { |path| inferred_include_dirs(path) }.uniq.sort
           end
    args.concat(dirs.flat_map { |dir| ['-I', dir] })
    args
  end

  def inferred_include_dirs(verilog_path)
    path = File.expand_path(verilog_path)
    dirs = []
    dirs << File.dirname(path)

    if path.include?('/examples/sparc64/reference/')
      reference_root = path.split('/examples/sparc64/reference/').first + '/examples/sparc64/reference'
      include_dir = File.join(reference_root, 'T1-common', 'include')
      dirs << include_dir if Dir.exist?(include_dir)
    elsif (idx = path.index('/mixed_sources/'))
      staged_root = path[0, idx + '/mixed_sources'.length]
      include_dir = File.join(staged_root, 'T1-common', 'include')
      dirs << include_dir if Dir.exist?(include_dir)
      wb_dir = File.join(staged_root, 'WB')
      dirs << wb_dir if Dir.exist?(wb_dir)
    end

    dirs.map { |dir| File.expand_path(dir) }.uniq.sort
  end

  def compiler_runtime_probe(component_class)
    compiler_runtime_probe_mutex.synchronize do
      compiler_runtime_probe_cache[component_class] ||= begin
        runtime_json =
          if COMPILER_RUNTIME_EXPORT_TIMEOUT.positive?
            Timeout.timeout(
              COMPILER_RUNTIME_EXPORT_TIMEOUT,
              Timeout::Error,
              "compiler runtime export exceeded #{COMPILER_RUNTIME_EXPORT_TIMEOUT} second timeout"
            ) do
              serialize_compiler_runtime_payload(component_class)
            end
          else
            serialize_compiler_runtime_payload(component_class)
          end

        {
          success: true,
          runtime_json: runtime_json
        }
      rescue StandardError => e
        {
          success: false,
          error: "#{e.class}: #{e.message}"
        }
      end
    end
  end

  def serialize_compiler_runtime_payload(component_class)
    flat_nodes = component_class.to_flat_circt_nodes
    RHDL::Sim::Native::IR.sim_json(flat_nodes, backend: :compiler)
  end

  def normalized_verilog_for_semantic_compare(verilog_source, source_path:)
    normalized = semantic_compare_importer.send(:normalize_verilog_for_import, verilog_source.dup, source_path: source_path)
    normalized = rewrite_escaped_identifiers_for_semantic_compare(normalized)
    rewrite_simple_gate_primitives_for_semantic_compare(normalized)
  end

  def semantic_compare_importer
    @semantic_compare_importer ||= RHDL::Examples::SPARC64::Import::SystemImporter.new(
      clean_output: false,
      keep_workspace: true
    )
  end

  def compiler_runtime_probe_cache
    @compiler_runtime_probe_cache ||= {}
  end

  def compiler_runtime_probe_mutex
    @compiler_runtime_probe_mutex ||= Mutex.new
  end

  def module_names_in_verilog_source(verilog_source)
    strip_comments(verilog_source).scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b/).flatten.uniq
  end

  def rewrite_simple_gate_primitives_for_semantic_compare(verilog_source)
    verilog_source.gsub(/^(?<indent>\s*)(?<primitive>buf|not|and|nand|or|nor|xor|xnor)\s*\((?<connections>[^;]+)\)\s*;\s*$/) do
      replacement = primitive_gate_assign_statement_for_semantic_compare(
        Regexp.last_match[:primitive],
        Regexp.last_match[:connections],
        indent: Regexp.last_match[:indent]
      )
      replacement || Regexp.last_match[0]
    end
  end

  def primitive_gate_assign_statement_for_semantic_compare(primitive, connection_text, indent:)
    args = split_top_level_csv(connection_text).map(&:strip).reject(&:empty?)
    return nil if args.length < 2

    case primitive
    when 'buf', 'not'
      input = args.pop
      outputs = args
      return nil if input.nil? || outputs.empty?

      outputs.map do |output|
        expr = primitive == 'buf' ? "(#{input})" : "~(#{input})"
        "#{indent}assign #{output} = #{expr};"
      end.join("\n")
    when 'and', 'nand', 'or', 'nor', 'xor', 'xnor'
      output = args.shift
      inputs = args
      return nil if output.nil? || inputs.empty?

      joiner = case primitive
               when 'and', 'nand' then ' & '
               when 'or', 'nor' then ' | '
               when 'xor', 'xnor' then ' ^ '
               end
      expr = "(#{inputs.join(joiner)})"
      expr = "~#{expr}" if %w[nand nor xnor].include?(primitive)
      "#{indent}assign #{output} = #{expr};"
    end
  end

  def rewrite_escaped_identifiers_for_semantic_compare(verilog_source)
    verilog_source.gsub(/\\([^\s]+)(\s+)/) do
      "#{sanitized_semantic_identifier(Regexp.last_match[1])}#{Regexp.last_match[2]}"
    end
  end

  def sanitized_semantic_identifier(name)
    value = name.to_s.gsub(/[^A-Za-z0-9_$]/, '_')
    value = "_#{value}" if value.empty? || value.match?(/\A\d/)
    value
  end

  def write_semantic_support_stubs(source: nil, sources: nil, base_dir:, stem:, known_module_names: Set.new)
    stub_path = File.join(base_dir, "#{stem}.semantic_support_stubs.v")
    source_texts = Array(sources || source).flatten.compact
    defined_modules = source_texts.flat_map { |text| module_names_in_verilog_source(text) }.to_set | known_module_names.to_set
    module_ports = Hash.new { |h, k| h[k] = [] }
    module_parameters = Hash.new { |h, k| h[k] = [] }

    source_texts.each do |text|
      semantic_support_stub_instances(text).each do |target, parameter_text, connection_text|
        next if defined_modules.include?(target)

        named_ports = connection_text.scan(/\.\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\(/).flatten.uniq
        ports = if named_ports.empty?
                  split_top_level_csv(connection_text).map(&:strip).reject(&:empty?).each_index.map { |idx| "p#{idx}" }
                else
                  named_ports
                end
        module_ports[target].concat(ports)
        module_parameters[target].concat(stub_parameter_names_for_instance(parameter_text))
      end
    end

    body = +"`timescale 1ns / 1ps\n\n"
    module_ports.keys.sort.each do |mod_name|
      ports = module_ports.fetch(mod_name).uniq
      parameters = module_parameters.fetch(mod_name).uniq
      if parameters.empty?
        body << "module #{mod_name}(#{ports.join(', ')});\n"
      else
        params = parameters.map { |name| "parameter #{name} = 0" }.join(', ')
        body << "module #{mod_name} #(#{params}) (#{ports.join(', ')});\n"
      end
      ports.each { |port| body << "  input #{port};\n" }
      body << "endmodule\n\n"
    end

    File.write(stub_path, body)
    stub_path
  end

  def semantic_support_stub_instances(source)
    text = strip_comments(source.to_s)
    text.scan(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)\b(.*?)\bendmodule\b/m).flat_map do |_module_name, body|
      instances = []
      body.to_enum(
        :scan,
        /\b([A-Za-z_][A-Za-z0-9_$]*)\s*(#\s*(?:\([^;]*?\)|\d+))?\s+([A-Za-z_][A-Za-z0-9_$]*)\s*\(/m
      ).each do
        target = Regexp.last_match[1]
        parameter_text = Regexp.last_match[2]
        next if RHDL::Examples::SPARC64::Import::SystemImporter::INSTANCE_KEYWORDS.include?(target)
        next if target == 'endcase'

        connection_text = instance_connection_text(body, Regexp.last_match.end(0))
        next unless connection_text

        instances << [target, parameter_text, connection_text]
      end
      instances
    end
  end

  def instance_connection_text(body, start_index)
    depth = 1
    cursor = start_index

    while cursor < body.length
      case body[cursor]
      when '('
        depth += 1
      when ')'
        depth -= 1
        if depth.zero?
          tail = body[(cursor + 1)..]
          return body[start_index...cursor] if tail&.match?(/\A\s*;/)

          return nil
        end
      end
      cursor += 1
    end

    nil
  end

  def stub_parameter_names_for_instance(parameter_text)
    text = parameter_text.to_s.sub(/\A#\s*/, '').strip
    return [] if text.empty?

    return ['P0'] if text.match?(/\A\d+\z/)

    inner = if text.start_with?('(') && text.end_with?(')')
              text[1...-1]
            else
              text
            end
    segments = split_top_level_csv(inner)
    named = []
    positional_count = 0

    segments.each do |segment|
      stripped = segment.strip
      next if stripped.empty?

      if (match = stripped.match(/\A\.\s*([A-Za-z_][A-Za-z0-9_$]*)\s*\(/))
        named << match[1]
      else
        positional_count += 1
      end
    end

    named.uniq + Array.new(positional_count) { |idx| "P#{idx}" }
  end

  def split_top_level_csv(text)
    segments = []
    current = +''
    depth = 0

    text.to_s.each_char do |char|
      case char
      when '(', '[', '{'
        depth += 1
        current << char
      when ')', ']', '}'
        depth -= 1 if depth.positive?
        current << char
      when ','
        if depth.zero?
          segments << current
          current = +''
        else
          current << char
        end
      else
        current << char
      end
    end

    segments << current unless current.empty?
    segments
  end
end
