# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for generating web simulator artifacts (IR, sources, schematics)
      class WebGenerateTask < Task
        PROJECT_ROOT = Config.project_root
        SCRIPT_DIR = File.join(PROJECT_ROOT, 'lib/rhdl/codegen/ir/sim/web/samples')

        $LOAD_PATH.unshift(File.join(PROJECT_ROOT, 'lib'))
        require 'rhdl'

        def run
          ensure_dir(SCRIPT_DIR)

          RUNNER_EXPORTS.each do |runner|
            generate_runner_assets(runner)
          end

          puts 'Web artifact generation complete.'
        end

        private

        def generate_runner_assets(runner)
          puts "Generating web artifacts for #{runner[:id]}..."
          top_class = load_runner_top_class(runner)

          flat_ir = top_class.to_flat_ir
          write_ir_json(flat_ir, runner[:sim_ir])

          hier_ir_hash = RHDL::Codegen::Schematic.hierarchical_ir_hash(
            top_class: top_class,
            instance_name: 'top',
            parameters: {},
            stack: []
          )
          File.write(runner[:hier_ir], JSON.generate(hier_ir_hash))
          puts "Wrote #{runner[:hier_ir]}"

          source_bundle = build_source_bundle(top_class, runner[:id])
          File.write(runner[:source_output], JSON.pretty_generate(source_bundle))
          puts "Wrote #{runner[:source_output]} (#{Array(source_bundle[:components]).length} components)"
          write_component_source_files(runner: runner, bundle: source_bundle)

          schematic_bundle = top_class.to_schematic(sim_ir: flat_ir, runner: runner[:id])
          File.write(runner[:schematic_output], JSON.pretty_generate(schematic_bundle))
          puts "Wrote #{runner[:schematic_output]} (#{Array(schematic_bundle[:components]).length} component scopes)"
          puts
        end

        def load_runner_top_class(runner)
          runner[:requires].each { |file_path| require file_path }
          constantize(runner[:top_class_name])
        end

        def build_source_bundle(top_class, runner_id)
          component_classes = RHDL::Codegen::Source.collect_component_classes(top_class)
          components = component_classes.map do |component_class|
            source_entry = component_class.to_source(relative_to: PROJECT_ROOT)
            source_entry[:verilog_source] = component_class.to_verilog
            source_entry
          end
          components.sort_by! { |entry| entry[:component_class].to_s }

          top_class_name = top_class.name.to_s
          top_entry = components.find { |entry| entry[:component_class] == top_class_name } || components.first

          {
            format: 'rhdl.web.component_sources.v1',
            runner: runner_id,
            generated_at: Time.now.utc.iso8601,
            top_component_class: top_class_name,
            top: top_entry,
            components: components
          }
        end

        def write_component_source_files(runner:, bundle:)
          runner_dir = File.join(SCRIPT_DIR, 'generated', runner[:id])
          ruby_dir = File.join(runner_dir, 'ruby')
          verilog_dir = File.join(runner_dir, 'verilog')
          FileUtils.rm_rf(runner_dir)
          ensure_dir(ruby_dir)
          ensure_dir(verilog_dir)

          Array(bundle[:components]).each do |entry|
            class_name = entry[:component_class].to_s
            slug = normalize_component_slug(class_name, 'component')

            rhdl_source = entry[:rhdl_source].to_s
            File.write(File.join(ruby_dir, "#{slug}.rb"), rhdl_source) unless rhdl_source.empty?

            verilog_source = entry[:verilog_source].to_s
            File.write(File.join(verilog_dir, "#{slug}.v"), verilog_source) unless verilog_source.empty?
          end

          puts "Wrote #{ruby_dir} and #{verilog_dir}"
        end

        def normalize_component_slug(value, fallback = 'component')
          token = value.to_s.strip
          token = fallback if token.empty?
          token = token.gsub(/[^a-zA-Z0-9]+/, '_')
          token = token.gsub(/\A_+|_+\z/, '')
          token = fallback if token.empty?
          token.downcase
        end

        def write_ir_json(ir_obj, output_path)
          json = RHDL::Codegen::IR::IRToJson.convert(ir_obj)
          parsed = JSON.parse(json)
          File.write(output_path, JSON.generate(parsed))
          puts "Wrote #{output_path}"
        end

        def constantize(name)
          name.split('::').reject(&:empty?).inject(Object) { |scope, const_name| scope.const_get(const_name) }
        end

        RUNNER_EXPORTS = [
          {
            id: 'apple2',
            top_class_name: 'RHDL::Examples::Apple2::Apple2',
            requires: [File.join(PROJECT_ROOT, 'examples/apple2/hdl/apple2')],
            source_output: File.join(SCRIPT_DIR, 'apple2_sources.json'),
            sim_ir: File.join(SCRIPT_DIR, 'apple2.json'),
            hier_ir: File.join(SCRIPT_DIR, 'apple2_hier.json'),
            schematic_output: File.join(SCRIPT_DIR, 'apple2_schematic.json')
          },
          {
            id: 'cpu',
            top_class_name: 'RHDL::HDL::CPU::CPU',
            requires: [File.join(PROJECT_ROOT, 'lib/rhdl/hdl/cpu/cpu')],
            source_output: File.join(SCRIPT_DIR, 'cpu_sources.json'),
            sim_ir: File.join(SCRIPT_DIR, 'cpu_lib_hdl.json'),
            hier_ir: File.join(SCRIPT_DIR, 'cpu_hier.json'),
            schematic_output: File.join(SCRIPT_DIR, 'cpu_schematic.json')
          }
        ].freeze
      end
    end
  end
end
