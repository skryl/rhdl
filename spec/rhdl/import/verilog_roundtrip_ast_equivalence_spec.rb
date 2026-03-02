# frozen_string_literal: true

require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe "Verilog import/export AST equivalence", timeout: 90 do
  def parse_design(source_files:, top_modules:, work_dir:)
    adapter = RHDL::Import::Frontend::VerilatorAdapter.new
    raw_payload = adapter.call(
      resolved_input: {
        source_files: source_files,
        include_dirs: [],
        defines: [],
        top_modules: top_modules
      },
      work_dir: work_dir
    )

    RHDL::Import::Frontend::Normalizer.normalize(raw_payload).fetch(:design)
  end

  def canonical_design(design)
    modules = Array(value_for(design, :modules)).map { |entry| canonical_module(entry) }
    {
      modules: modules.sort_by { |entry| entry.fetch(:name) }
    }
  end

  def canonical_module(entry)
    hash = deep_symbolize(entry)
    canonical = { name: hash.fetch(:name).to_s }

    ports = canonical_named_section(hash[:ports], :name)
    parameters = canonical_named_section(hash[:parameters], :name)
    declarations = canonical_named_section(hash[:declarations], :name)
    statements = canonical_statement_section(hash[:statements])
    processes = canonical_process_section(hash[:processes])
    instances = canonical_instance_section(hash[:instances])

    canonical[:ports] = ports unless ports.empty?
    canonical[:parameters] = parameters unless parameters.empty?
    canonical[:declarations] = declarations unless declarations.empty?
    canonical[:statements] = statements unless statements.empty?
    canonical[:processes] = processes unless processes.empty?
    canonical[:instances] = instances unless instances.empty?
    canonical
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
    JSON.generate(value)
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

  def run_import(src_dir:, out_dir:, top:)
    result = RHDL::Import.project(
      out: out_dir,
      src: [src_dir],
      top: [top],
      dependency_resolution: "none",
      compile_unit_filter: "modules_only",
      no_check: true
    )

    expect(result).to be_success
    result
  end

  def load_component_class(out_dir:, source_module_name:)
    project_file = Dir.glob(File.join(out_dir, "lib", "*.rb")).first
    raise "generated import project file not found in #{out_dir}" if project_file.nil?

    load project_file

    module_file = Dir.glob(File.join(out_dir, "lib", "*", "modules", "**", "*.rb")).find do |path|
      File.read(path).include?("# source_module: #{source_module_name}")
    end
    raise "generated module file for #{source_module_name.inspect} not found" if module_file.nil?

    class_name = File.read(module_file)[/^\s*class\s+([A-Za-z0-9_]+)\s+<\s+RHDL::Component/, 1]
    raise "component class declaration missing in #{module_file}" if class_name.nil?

    Object.const_get(class_name)
  end

  it "preserves a structural single-module AST across import and re-export" do
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      source_dir = File.join(dir, "src")
      out_dir = File.join(dir, "out")
      FileUtils.mkdir_p(source_dir)

      top_name = "roundtrip_ast_single_top"
      source_file = File.join(source_dir, "#{top_name}.v")
      File.write(
        source_file,
        <<~VERILOG
          module #{top_name}(
            input logic [3:0] a,
            input logic [3:0] b,
            input logic sel,
            output logic [7:0] y
          );
            wire [3:0] chosen;
            assign chosen = sel ? a : b;
            assign y = {chosen, a};
          endmodule
        VERILOG
      )

      run_import(src_dir: source_dir, out_dir: out_dir, top: top_name)
      component_class = load_component_class(out_dir: out_dir, source_module_name: top_name)
      generated_verilog = RHDL::Export.to_verilog(component_class, top_name: top_name)
      generated_file = File.join(dir, "generated_single.v")
      File.write(generated_file, generated_verilog)

      source_design = parse_design(
        source_files: [source_file],
        top_modules: [top_name],
        work_dir: File.join(dir, "tmp", "source_frontend")
      )
      generated_design = parse_design(
        source_files: [generated_file],
        top_modules: [top_name],
        work_dir: File.join(dir, "tmp", "generated_frontend")
      )

      expect(canonical_design(generated_design)).to eq(canonical_design(source_design))
    end
  end

  it "preserves hierarchical module/instance AST across import and re-export" do
    skip "Verilator not available" unless HdlToolchain.verilator_available?

    Dir.mktmpdir do |dir|
      source_dir = File.join(dir, "src")
      out_dir = File.join(dir, "out")
      FileUtils.mkdir_p(source_dir)

      leaf_name = "roundtrip_ast_leaf"
      top_name = "roundtrip_ast_hier_top"
      leaf_file = File.join(source_dir, "#{leaf_name}.v")
      top_file = File.join(source_dir, "#{top_name}.v")

      File.write(
        leaf_file,
        <<~VERILOG
          module #{leaf_name}(
            input logic [7:0] in_a,
            output logic [7:0] out_z
          );
            assign out_z = in_a ^ 8'hFF;
          endmodule
        VERILOG
      )
      File.write(
        top_file,
        <<~VERILOG
          module #{top_name}(
            input logic [7:0] a,
            output logic [7:0] y
          );
            #{leaf_name} u_leaf(
              .in_a(a),
              .out_z(y)
            );
          endmodule
        VERILOG
      )

      run_import(src_dir: source_dir, out_dir: out_dir, top: top_name)
      top_class = load_component_class(out_dir: out_dir, source_module_name: top_name)
      leaf_class = load_component_class(out_dir: out_dir, source_module_name: leaf_name)
      generated_verilog = [
        RHDL::Export.to_verilog(leaf_class, top_name: leaf_name),
        RHDL::Export.to_verilog(top_class, top_name: top_name)
      ].join("\n\n")
      generated_file = File.join(dir, "generated_hierarchy.v")
      File.write(generated_file, generated_verilog)

      source_design = parse_design(
        source_files: [leaf_file, top_file],
        top_modules: [top_name],
        work_dir: File.join(dir, "tmp", "hier_source_frontend")
      )
      generated_design = parse_design(
        source_files: [generated_file],
        top_modules: [top_name],
        work_dir: File.join(dir, "tmp", "hier_generated_frontend")
      )

      expect(canonical_design(generated_design)).to eq(canonical_design(source_design))
    end
  end
end
