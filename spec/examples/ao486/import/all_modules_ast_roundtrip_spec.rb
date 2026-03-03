# frozen_string_literal: true

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe "ao486 all-module AST roundtrip", :slow, timeout: 600 do
  AST_SOURCE_ROOT = File.expand_path("../../../../examples/ao486/reference/rtl", __dir__)
  PACKAGE_DECLARATION_REGEX = /^\s*package\b/.freeze
  AST_FRONTEND_TOP = "system"
  AST_WARNING_FLAGS = %w[
    -Wno-PINMISSING
    -Wno-IMPLICITSTATIC
    -Wno-MULTITOP
    -Wno-TIMESCALEMOD
    -Wno-REALCVT
    -Wno-ASCRANGE
    -Wno-WIDTHEXPAND
    -Wno-WIDTHTRUNC
  ].freeze

  class AstRoundtripCommandBuilder < RHDL::Import::Frontend::CommandBuilder
    def build(**kwargs)
      command = super
      AST_WARNING_FLAGS.each do |flag|
        command << flag unless command.include?(flag)
      end
      command
    end
  end

  def ast_frontend_adapter
    @ast_frontend_adapter ||= RHDL::Import::Frontend::VerilatorAdapter.new(
      command_builder: AstRoundtripCommandBuilder.new
    )
  end

  def parse_normalized_payload(frontend_input:, work_dir:, frontend_adapter: nil)
    adapter = frontend_adapter || ast_frontend_adapter
    raw_payload = adapter.call(
      resolved_input: frontend_input,
      work_dir: work_dir
    )

    RHDL::Import::Frontend::Normalizer.normalize(raw_payload)
  rescue RHDL::Import::Frontend::VerilatorAdapter::ExecutionError => e
    command = Array(e.command).join(" ")
    details = [
      e.message,
      "work_dir=#{work_dir}",
      "stderr:",
      e.stderr.to_s.strip,
      "command:",
      command
    ].join("\n")
    raise RSpec::Expectations::ExpectationNotMetError, details
  end

  def parse_design(frontend_input:, work_dir:, frontend_adapter: nil)
    parse_normalized_payload(
      frontend_input: frontend_input,
      work_dir: work_dir,
      frontend_adapter: frontend_adapter
    ).fetch(:design)
  end

  def canonical_module_map(design)
    Array(value_for(design, :modules))
      .map { |entry| canonical_module(entry) }
      .each_with_object({}) do |entry, memo|
        memo[entry.fetch(:name)] = entry
      end
  end

  def canonical_module(entry)
    hash = deep_symbolize(entry)
    canonical = { name: hash.fetch(:name).to_s }

    # Verilator JSON regularization rewrites internal declaration/statement/process
    # trees across equivalent source/generation forms. For ao486 roundtrip stability
    # we compare module boundary and hierarchy shape (ports/parameters/instances).
    ports = canonical_port_signature_section(hash[:ports])
    parameters = canonical_parameter_signature_section(hash[:parameters])
    instances = canonical_instance_signature_section(hash[:instances])

    canonical[:ports] = ports unless ports.empty?
    canonical[:parameters] = parameters unless parameters.empty?
    canonical[:instances] = instances unless instances.empty?
    canonical
  end

  def canonical_port_signature_section(entries)
    Array(entries)
      .map do |entry|
        hash = canonical_value(entry)
        {
          direction: value_for(hash, :direction).to_s,
          name: value_for(hash, :name).to_s
        }
      end
      .sort_by { |entry| entry[:name] }
  end

  def canonical_parameter_signature_section(entries)
    Array(entries)
      .map { |entry| value_for(canonical_value(entry), :name).to_s }
      .reject(&:empty?)
      .sort
  end

  def canonical_instance_signature_section(entries)
    Array(entries)
      .map do |entry|
        hash = canonical_value(entry)
        {
          name: value_for(hash, :name).to_s,
          module_name: value_for(hash, :module_name).to_s,
          parameter_overrides: Array(value_for(hash, :parameter_overrides))
            .map { |override| value_for(override, :name).to_s }
            .reject(&:empty?)
            .sort,
          connections: Array(value_for(hash, :connections))
            .map { |connection| canonical_value(connection) }
            .select do |connection|
              !value_for(connection, :signal).nil? ||
                !value_for(connection, :expression).nil? ||
                !value_for(connection, :expr).nil?
            end
            .map { |connection| value_for(connection, :port).to_s }
            .reject(&:empty?)
            .sort
        }
      end
      .sort_by { |entry| entry[:name] }
  end

  def canonical_named_section(entries, key)
    Array(entries)
      .map { |entry| canonical_value(entry) }
      .sort_by { |entry| value_for(entry, key).to_s }
  end

  def canonical_statement_section(entries)
    Array(entries).map { |entry| canonical_value(entry) }
  end

  def canonical_process_section(entries)
    Array(entries)
      .map do |entry|
        hash = canonical_value(entry)
        sensitivity = Array(value_for(hash, :sensitivity))
          .sort_by { |value| stable_dump(value) }
        hash[:sensitivity] = sensitivity unless sensitivity.empty?
        hash
      end
      .sort_by { |entry| stable_dump(entry) }
  end

  def canonical_instance_section(entries)
    Array(entries)
      .map do |entry|
        hash = canonical_value(entry)
        overrides = Array(value_for(hash, :parameter_overrides))
        connections = Array(value_for(hash, :connections))
        hash[:parameter_overrides] = overrides.sort_by { |value| value_for(value, :name).to_s } unless overrides.empty?
        hash[:connections] = connections.sort_by { |value| value_for(value, :port).to_s } unless connections.empty?
        hash
      end
      .sort_by { |entry| value_for(entry, :name).to_s }
  end

  def canonical_value(value)
    case value
    when Hash
      value.keys.map(&:to_sym).sort_by(&:to_s).each_with_object({}) do |key, memo|
        memo[key] = canonical_value(value_for(value, key))
      end
    when Array
      value.map { |entry| canonical_value(entry) }
    else
      value
    end
  end

  def stable_dump(value)
    JSON.generate(value, max_nesting: false)
  end

  def value_for(hash, key)
    return nil unless hash.is_a?(Hash)
    return hash[key] if hash.key?(key)
    return hash[key.to_s] if hash.key?(key.to_s)

    hash[key.to_sym]
  end

  def deep_symbolize(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, inner), memo|
        memo[key.to_sym] = deep_symbolize(inner)
      end
    when Array
      value.map { |inner| deep_symbolize(inner) }
    else
      value
    end
  end

  def load_generated_component_map(out_dir:)
    project_file = Dir.glob(File.join(out_dir, "lib", "*.rb")).first
    raise "generated import project file not found in #{out_dir}" if project_file.nil?

    load project_file

    module_files = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "*.rb")).sort
    map = {}

    module_files.each do |module_file|
      source = File.read(module_file)
      source_module_name = source[/^\s*#\s*source_module:\s*(.+?)\s*$/, 1]
      class_name = source[/^\s*class\s+([A-Za-z0-9_]+)\s+<\s+RHDL::Component/, 1]
      next if source_module_name.nil? || source_module_name.empty?
      next if class_name.nil? || class_name.empty?

      map[source_module_name] = Object.const_get(class_name)
    end

    map
  end

  def write_generated_verilog_for_modules(component_map:, module_names:, output_dir:)
    FileUtils.mkdir_p(output_dir)
    export_failures = []

    module_names.each do |module_name|
      component_class = component_map[module_name]
      raise "missing generated component class for #{module_name}" if component_class.nil?

      begin
        verilog = RHDL::Export.to_verilog(component_class, top_name: module_name)
        safe_filename = module_name.gsub(/[^A-Za-z0-9_.-]/, "_")
        File.write(File.join(output_dir, "#{safe_filename}.v"), verilog)
      rescue StandardError => e
        export_failures << {
          module: module_name,
          component: component_class.name,
          error_class: e.class.name,
          message: e.message
        }
      end
    end

    {
      files: Dir.glob(File.join(output_dir, "*.v")).sort,
      export_failures: export_failures
    }
  end

  def mismatch_summary_message(missing:, extra:, mismatched:)
    lines = []
    lines << "module AST mismatch summary:"
    lines << "  missing_generated=#{missing.length}"
    lines << "  extra_generated=#{extra.length}"
    lines << "  ast_mismatched=#{mismatched.length}"
    lines << "  missing_sample=#{missing.first(10).join(', ')}" unless missing.empty?
    lines << "  extra_sample=#{extra.first(10).join(', ')}" unless extra.empty?
    lines << "  mismatched_sample=#{mismatched.first(10).join(', ')}" unless mismatched.empty?
    lines.join("\n")
  end

  def export_failure_summary_message(export_failures)
    lines = []
    lines << "module export failures: total=#{export_failures.length}"
    export_failures.first(20).each do |entry|
      lines << "  #{entry[:module]} (#{entry[:component]}): #{entry[:error_class]}: #{entry[:message]}"
    end
    lines.join("\n")
  end

  def package_compile_units(root:)
    pattern = File.join(root, "**", "*.sv")
    Dir.glob(pattern).sort.select do |path|
      next false unless File.file?(path)

      has_package = false
      File.foreach(path) do |line|
        if PACKAGE_DECLARATION_REGEX.match?(line)
          has_package = true
          break
        end
      end
      has_package
    rescue ArgumentError, Errno::ENOENT
      false
    end
  end

  it "imports all ao486 RTL modules and preserves per-module canonical AST after re-export" do
    skip "ao486 reference RTL is unavailable: #{AST_SOURCE_ROOT}" unless Dir.exist?(AST_SOURCE_ROOT)
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      out_dir = File.join(dir, "ao486_roundtrip_import")

      resolved_input = RHDL::Import::InputResolver.resolve(
        src: [AST_SOURCE_ROOT],
        dependency_resolution: "none",
        compile_unit_filter: "modules_only"
      )
      module_source_files = Array(resolved_input[:source_files]).map(&:to_s).reject(&:empty?)
      package_files = package_compile_units(root: AST_SOURCE_ROOT)
      source_files = (package_files + module_source_files).uniq
      include_dirs = Array(resolved_input[:include_dirs]).map(&:to_s).reject(&:empty?)
      defines = Array(resolved_input[:defines]).map(&:to_s).reject(&:empty?)
      expect(source_files).not_to be_empty

      resolved_input = resolved_input.merge(
        source_files: source_files,
        frontend_input: {
          source_files: source_files,
          include_dirs: include_dirs,
          defines: defines,
          top_modules: [AST_FRONTEND_TOP],
          missing_modules: "blackbox_stubs"
        }
      )

      source_payload = parse_normalized_payload(
        frontend_input: resolved_input.fetch(:frontend_input),
        work_dir: File.join(dir, "tmp", "source_frontend"),
        frontend_adapter: ast_frontend_adapter
      )
      source_design = source_payload.fetch(:design)
      source_modules = canonical_module_map(source_design)
      source_module_names = source_modules.keys.sort
      expect(source_module_names).not_to be_empty

      mapped_program = RHDL::Import::Mapper.map(source_payload)
      mapped_modules = Array(mapped_program.modules).map(&:to_h)
      mapped_module_names = mapped_modules.map { |entry| value_for(entry, :name).to_s }.reject(&:empty?).uniq.sort
      expect(mapped_module_names).to eq(source_module_names)

      result = RHDL::Import.project(
        out: out_dir,
        src: [AST_SOURCE_ROOT],
        resolved_input: resolved_input,
        dependency_resolution: "none",
        compile_unit_filter: "modules_only",
        missing_modules: "blackbox_stubs",
        mapped_modules: mapped_modules,
        top: mapped_module_names,
        no_check: true
      )
      expect(result).to be_success
      report = assert_import_report_skeleton!(result.report, status: :success)
      expect(report.dig("summary", "failed_modules")).to eq(0)

      component_map = load_generated_component_map(out_dir: out_dir)
      missing_components = source_module_names - component_map.keys.sort
      expect(missing_components).to eq([]),
        "missing generated component classes for source modules: #{missing_components.first(20).join(', ')}"

      export_result = write_generated_verilog_for_modules(
        component_map: component_map,
        module_names: source_module_names,
        output_dir: File.join(dir, "generated_verilog")
      )
      generated_files = export_result.fetch(:files)
      export_failures = export_result.fetch(:export_failures)
      expect(export_failures).to eq([]), export_failure_summary_message(export_failures)
      expect(generated_files.length).to eq(source_module_names.length)

      generated_design = parse_design(
        frontend_input: {
          source_files: generated_files,
          include_dirs: [File.join(dir, "generated_verilog")],
          defines: [],
          top_modules: [],
          missing_modules: "blackbox_stubs"
        },
        work_dir: File.join(dir, "tmp", "generated_frontend"),
        frontend_adapter: ast_frontend_adapter
      )
      generated_modules = canonical_module_map(generated_design)
      generated_module_names = generated_modules.keys.sort

      missing_generated = source_module_names - generated_module_names
      extra_generated = generated_module_names - source_module_names
      mismatched_modules = source_module_names.select do |module_name|
        generated_modules[module_name] != source_modules[module_name]
      end

      expect(missing_generated).to eq([]),
        mismatch_summary_message(
          missing: missing_generated,
          extra: extra_generated,
          mismatched: mismatched_modules
        )
      expect(extra_generated).to eq([]),
        mismatch_summary_message(
          missing: missing_generated,
          extra: extra_generated,
          mismatched: mismatched_modules
        )
      expect(mismatched_modules).to eq([]),
        mismatch_summary_message(
          missing: missing_generated,
          extra: extra_generated,
          mismatched: mismatched_modules
        )
    end
  end
end
