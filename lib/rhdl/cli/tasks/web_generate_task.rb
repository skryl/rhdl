# frozen_string_literal: true

require 'json'
require 'time'
require 'base64'
require_relative '../task'
require_relative '../config'

module RHDL
  module CLI
    module Tasks
      # Task for generating web simulator artifacts (IR, sources, schematics)
      class WebGenerateTask < Task
        PROJECT_ROOT = Config.project_root
        SCRIPT_DIR = File.join(PROJECT_ROOT, 'web/assets/fixtures')
        WEB_ROOT = File.join(PROJECT_ROOT, 'web')
        PKG_DIR = File.join(WEB_ROOT, 'assets/pkg')
        SIM_DIR = File.join(PROJECT_ROOT, 'lib/rhdl/codegen/ir/sim')
        AOT_IR_PATH = File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2.json')
        AOT_GEN_PATH = File.join(SIM_DIR, 'ir_compiler/src/aot_generated.rs')
        APPLE2_ROM_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/roms/appleiigo.rom')
        KARATEKA_MEM_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/disks/karateka_mem.bin')
        KARATEKA_META_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/disks/karateka_mem_meta.txt')
        SNAPSHOT_KIND = 'rhdl.apple2.ram_snapshot'
        SNAPSHOT_VERSION = 1
        DEFAULT_KARATEKA_PC = 0xB82A

        $LOAD_PATH.unshift(File.join(PROJECT_ROOT, 'lib'))
        require 'rhdl'

        def run
          ensure_dir(SCRIPT_DIR)

          RUNNER_EXPORTS.each do |runner|
            generate_runner_assets(runner)
          end

          generate_apple2_memory_assets
          build_wasm_backends

          puts 'Web artifact generation complete.'
        end

        private

        def run_command(*args, chdir: nil)
          if chdir
            Dir.chdir(chdir) { system(*args) }
          else
            system(*args)
          end
        end

        def build_wasm_backends
          puts 'Building web WASM artifacts...'
          ensure_dir(PKG_DIR)
          File.write(File.join(PKG_DIR, '.gitignore'), "*\n!.gitignore\n")
          run_rustup_target_add!

          restore_aot_placeholder = <<~RUST
            compile_error!(
                "ir_compiler feature `aot` requires generated source at src/aot_generated.rs; run aot_codegen first"
            );
          RUST

          begin
            build_wasm_backend(crate_dir: File.join(SIM_DIR, 'ir_interpreter'), artifact: 'ir_interpreter.wasm')
            build_wasm_backend(crate_dir: File.join(SIM_DIR, 'ir_jit'), artifact: 'ir_jit.wasm')
            build_compiler_aot_wasm
          ensure
            File.write(AOT_GEN_PATH, restore_aot_placeholder)
          end
        end

        def run_rustup_target_add!
          ok = run_command('rustup', 'target', 'add', 'wasm32-unknown-unknown')
          raise 'Failed to add rustup target wasm32-unknown-unknown' unless ok
        end

        def build_wasm_backend(crate_dir:, artifact:, extra_args: [])
          crate_name = File.basename(crate_dir)
          puts "Building #{crate_name} -> #{artifact}"

          ok = run_command(
            'cargo', 'build', '--release', '--target', 'wasm32-unknown-unknown',
            *extra_args,
            chdir: crate_dir
          )

          unless ok
            warn "WARNING: #{crate_name} failed for wasm32-unknown-unknown; #{artifact} not updated"
            return
          end

          src_wasm = File.join(crate_dir, 'target', 'wasm32-unknown-unknown', 'release', "#{crate_name}.wasm")
          unless File.file?(src_wasm)
            warn "WARNING: missing wasm output #{src_wasm}; #{artifact} not updated"
            return
          end

          out_file = File.join(PKG_DIR, artifact)
          FileUtils.cp(src_wasm, out_file)
          puts "Wrote #{out_file}"
        end

        def build_compiler_aot_wasm
          puts 'Building ir_compiler -> ir_compiler.wasm (AOT)'
          unless File.file?(AOT_IR_PATH)
            warn "WARNING: AOT IR source not found: #{AOT_IR_PATH}; ir_compiler.wasm not updated"
            return
          end

          compiler_dir = File.join(SIM_DIR, 'ir_compiler')
          generated = run_command(
            'cargo', 'run', '--quiet', '--bin', 'aot_codegen', '--', AOT_IR_PATH, AOT_GEN_PATH,
            chdir: compiler_dir
          )
          unless generated
            warn 'WARNING: ir_compiler AOT code generation failed; ir_compiler.wasm not updated'
            return
          end

          built = run_command(
            'cargo', 'build', '--release', '--target', 'wasm32-unknown-unknown', '--features', 'aot',
            chdir: compiler_dir
          )
          unless built
            warn 'WARNING: ir_compiler AOT build failed; ir_compiler.wasm not updated'
            return
          end

          src_wasm = File.join(compiler_dir, 'target', 'wasm32-unknown-unknown', 'release', 'ir_compiler.wasm')
          unless File.file?(src_wasm)
            warn "WARNING: missing wasm output #{src_wasm}; ir_compiler.wasm not updated"
            return
          end

          out_file = File.join(PKG_DIR, 'ir_compiler.wasm')
          FileUtils.cp(src_wasm, out_file)
          puts "Wrote #{out_file} (AOT from #{AOT_IR_PATH})"
        end

        def generate_apple2_memory_assets
          puts 'Generating web memory assets for apple2...'
          memory_dir = File.join(SCRIPT_DIR, 'apple2', 'memory')
          ensure_dir(memory_dir)

          copy_required_file(APPLE2_ROM_SOURCE, File.join(memory_dir, 'appleiigo.rom'))
          copy_required_file(KARATEKA_MEM_SOURCE, File.join(memory_dir, 'karateka_mem.bin'))
          copy_required_file(KARATEKA_META_SOURCE, File.join(memory_dir, 'karateka_mem_meta.txt'))
          write_karateka_snapshot(memory_dir)
        end

        def copy_required_file(src, dst)
          raise "Missing source asset: #{src}" unless File.file?(src)

          FileUtils.cp(src, dst)
          puts "Wrote #{dst}"
        end

        def parse_pc_from_meta(text)
          match = text.to_s.match(/PC at dump:\s*\$([0-9A-Fa-f]{1,4})/)
          return nil unless match

          match[1].to_i(16) & 0xFFFF
        end

        def write_karateka_snapshot(memory_dir)
          bin_path = File.join(memory_dir, 'karateka_mem.bin')
          meta_path = File.join(memory_dir, 'karateka_mem_meta.txt')
          snapshot_path = File.join(memory_dir, 'karateka_mem.rhdlsnap')

          bytes = File.binread(bin_path)
          meta = File.file?(meta_path) ? File.read(meta_path) : ''
          start_pc = parse_pc_from_meta(meta) || DEFAULT_KARATEKA_PC
          now = Time.now.utc

          payload = {
            kind: SNAPSHOT_KIND,
            version: SNAPSHOT_VERSION,
            label: "Karateka dump (PC=$#{format('%04X', start_pc)})",
            offset: 0,
            length: bytes.bytesize,
            savedAtMs: (now.to_f * 1000).to_i,
            savedAtIso: now.iso8601,
            startPc: start_pc,
            dataB64: Base64.strict_encode64(bytes),
            sourceBin: './assets/fixtures/apple2/memory/karateka_mem.bin',
            sourceMeta: './assets/fixtures/apple2/memory/karateka_mem_meta.txt',
            notes: meta
          }

          File.write(snapshot_path, JSON.pretty_generate(payload))
          puts "Wrote #{snapshot_path}"
        end

        def generate_runner_assets(runner)
          puts "Generating web artifacts for #{runner[:id]}..."
          ensure_dir(File.dirname(runner[:sim_ir]))
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
          runner_dir = File.join(SCRIPT_DIR, runner[:id])
          ruby_dir = File.join(runner_dir, 'ruby')
          verilog_dir = File.join(runner_dir, 'verilog')
          ensure_dir(runner_dir)
          FileUtils.rm_rf(ruby_dir)
          FileUtils.rm_rf(verilog_dir)
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
            source_output: File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2_sources.json'),
            sim_ir: File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2.json'),
            hier_ir: File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2_hier.json'),
            schematic_output: File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2_schematic.json')
          },
          {
            id: 'cpu',
            top_class_name: 'RHDL::HDL::CPU::CPU',
            requires: [File.join(PROJECT_ROOT, 'lib/rhdl/hdl/cpu/cpu')],
            source_output: File.join(SCRIPT_DIR, 'cpu', 'ir', 'cpu_sources.json'),
            sim_ir: File.join(SCRIPT_DIR, 'cpu', 'ir', 'cpu_lib_hdl.json'),
            hier_ir: File.join(SCRIPT_DIR, 'cpu', 'ir', 'cpu_hier.json'),
            schematic_output: File.join(SCRIPT_DIR, 'cpu', 'ir', 'cpu_schematic.json')
          }
        ].freeze
      end
    end
  end
end
