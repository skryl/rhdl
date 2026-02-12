# frozen_string_literal: true

require 'json'
require 'time'
require 'base64'
require 'etc'
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
        APPLE2_AOT_IR_PATH = File.join(SCRIPT_DIR, 'apple2', 'ir', 'apple2.json')
        CPU8BIT_AOT_IR_PATH = File.join(SCRIPT_DIR, 'cpu', 'ir', 'cpu_lib_hdl.json')
        MOS6502_AOT_IR_PATH = File.join(SCRIPT_DIR, 'mos6502', 'ir', 'mos6502.json')
        AOT_GEN_PATH = File.join(SIM_DIR, 'ir_compiler/src/aot_generated.rs')
        APPLE2_ROM_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/roms/appleiigo.rom')
        KARATEKA_MEM_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/disks/karateka_mem.bin')
        KARATEKA_META_SOURCE = File.join(PROJECT_ROOT, 'examples/apple2/software/disks/karateka_mem_meta.txt')
        CPU8BIT_DEFAULT_BIN_SOURCE = File.join(PROJECT_ROOT, 'examples/8bit/software/bin/conway_glider_80x24.bin')
        CPU8BIT_SOFTWARE_BIN_DIR = File.join(PROJECT_ROOT, 'examples/8bit/software/bin')
        MOS6502_DEFAULT_BIN_SOURCE = File.join(PROJECT_ROOT, 'examples/mos6502/software/disks/karateka_mem.bin')
        MOS6502_DEFAULT_SNAPSHOT_SOURCE = File.join(SCRIPT_DIR, 'apple2', 'memory', 'karateka_mem.rhdlsnap')
        GAMEBOY_DEFAULT_BIN_SOURCE = File.join(PROJECT_ROOT, 'examples/gameboy/software/roms/dmg_boot.bin')
        SNAPSHOT_KIND = 'rhdl.apple2.ram_snapshot'
        SNAPSHOT_VERSION = 1
        DEFAULT_KARATEKA_PC = 0xB82A
        DEFAULT_BIN_ASSETS = [
          {
            src: CPU8BIT_DEFAULT_BIN_SOURCE,
            dst: File.join(SCRIPT_DIR, 'cpu', 'software', 'conway_glider_80x24.bin')
          },
          {
            src: MOS6502_DEFAULT_BIN_SOURCE,
            dst: File.join(SCRIPT_DIR, 'mos6502', 'memory', 'karateka_mem.bin')
          },
          {
            src: MOS6502_DEFAULT_SNAPSHOT_SOURCE,
            dst: File.join(SCRIPT_DIR, 'mos6502', 'memory', 'karateka_mem.rhdlsnap')
          },
          {
            src: GAMEBOY_DEFAULT_BIN_SOURCE,
            dst: File.join(SCRIPT_DIR, 'gameboy', 'roms', 'dmg_boot.bin')
          }
        ].freeze

        $LOAD_PATH.unshift(File.join(PROJECT_ROOT, 'lib'))
        require 'rhdl'

        def run
          ensure_wasm_backends_built
          ensure_dir(SCRIPT_DIR)

          runner_exports.each do |runner|
            generate_runner_assets(runner)
          end

          write_runner_preset_module(runner_configs)
          generate_apple2_memory_assets
          generate_runner_default_bin_assets
          write_memory_dump_asset_module

          puts 'Web artifact generation complete.'
        end

        def run_build
          build_wasm_backends
          mark_wasm_build_complete!
          puts 'Web WASM build complete.'
        end

        private

        def run_command(*args, chdir: nil)
          if chdir
            Dir.chdir(chdir) { system(*args) }
          else
            system(*args)
          end
        end

        def ensure_wasm_backends_built
          if wasm_backends_built?
            puts 'Web WASM build already completed; skipping build.'
          else
            puts 'Web WASM build not found; building first...'
            run_build
          end
        end

        def wasm_backends_built?
          return false unless File.file?(WASM_BUILD_STAMP_PATH)

          REQUIRED_WASM_OUTPUTS.all? do |artifact|
            File.file?(File.join(PKG_DIR, artifact))
          end
        end

        def mark_wasm_build_complete!
          ensure_dir(PKG_DIR)
          File.write(WASM_BUILD_STAMP_PATH, "#{Time.now.utc.iso8601}\n")
        end

        def build_wasm_backends
          puts 'Building web WASM artifacts...'
          ensure_dir(PKG_DIR)
          File.write(File.join(PKG_DIR, '.gitignore'), "*\n!.gitignore\n")

          build_mruby_wasm
          ensure_aot_ir_inputs

          unless run_rustup_target_add!
            warn 'WARNING: failed to add rustup target wasm32-unknown-unknown; skipping WASM backend builds'
            return
          end

          restore_aot_placeholder = <<~RUST
            compile_error!(
                "ir_compiler feature `aot` requires generated source at src/aot_generated.rs; run aot_codegen first"
            );
          RUST

          begin
            build_wasm_backend(crate_dir: File.join(SIM_DIR, 'ir_interpreter'), artifact: 'ir_interpreter.wasm')
            build_wasm_backend(crate_dir: File.join(SIM_DIR, 'ir_jit'), artifact: 'ir_jit.wasm')
            build_compiler_aot_wasm(ir_path: APPLE2_AOT_IR_PATH, artifact: 'ir_compiler.wasm')
            build_compiler_aot_wasm(ir_path: CPU8BIT_AOT_IR_PATH, artifact: 'ir_compiler_cpu.wasm')
            build_compiler_aot_wasm(ir_path: MOS6502_AOT_IR_PATH, artifact: 'ir_compiler_mos6502.wasm')
          ensure
            File.write(AOT_GEN_PATH, restore_aot_placeholder)
          end
        end

        def build_mruby_wasm
          unless command_available?('emcc')
            warn 'WARNING: emcc not found; install emscripten to build mruby wasm artifacts'
            return
          end

          ensure_dir(File.join(PROJECT_ROOT, 'tmp'))
          source_dir = File.join(PROJECT_ROOT, 'tmp', "mruby-#{MRUBY_VERSION}")
          source_git_dir = File.join(source_dir, '.git')

          unless File.directory?(source_git_dir)
            FileUtils.rm_rf(source_dir)
            puts "Cloning mruby #{MRUBY_VERSION} into #{source_dir}"
            cloned = run_command(
              'git', 'clone', '--depth', '1', '--branch', MRUBY_VERSION, MRUBY_REPO, source_dir,
              chdir: PROJECT_ROOT
            )
            unless cloned
              warn "WARNING: failed to clone mruby #{MRUBY_VERSION}; mruby artifacts not updated"
              return
            end
          end

          puts 'Building mruby -> mruby.js/mruby.wasm + mirb.js/mirb.wasm'
          jobs = Etc.respond_to?(:nprocessors) ? Etc.nprocessors : 4
          ok = run_command(
            'rake', 'MRUBY_CONFIG=build_config/emscripten.rb', "-j#{jobs}",
            chdir: source_dir
          )
          unless ok
            warn 'WARNING: mruby wasm build failed; mruby artifacts not updated'
            return
          end

          js_src = File.join(source_dir, 'build', 'emscripten', 'bin', 'mruby')
          wasm_src = File.join(source_dir, 'build', 'emscripten', 'bin', 'mruby.wasm')
          mirb_js_src = File.join(source_dir, 'build', 'emscripten', 'bin', 'mirb')
          mirb_wasm_src = File.join(source_dir, 'build', 'emscripten', 'bin', 'mirb.wasm')
          unless File.file?(js_src) && File.file?(wasm_src) && File.file?(mirb_js_src) && File.file?(mirb_wasm_src)
            warn "WARNING: expected mruby wasm outputs not found in #{File.join(source_dir, 'build', 'emscripten', 'bin')}"
            return
          end

          js_out = File.join(PKG_DIR, 'mruby.js')
          wasm_out = File.join(PKG_DIR, 'mruby.wasm')
          mirb_js_out = File.join(PKG_DIR, 'mirb.js')
          mirb_wasm_out = File.join(PKG_DIR, 'mirb.wasm')
          version_out = File.join(PKG_DIR, 'mruby.version.json')

          FileUtils.cp(js_src, js_out)
          FileUtils.cp(wasm_src, wasm_out)
          FileUtils.cp(mirb_js_src, mirb_js_out)
          FileUtils.cp(mirb_wasm_src, mirb_wasm_out)
          File.chmod(0o644, js_out) if File.file?(js_out)
          File.chmod(0o644, wasm_out) if File.file?(wasm_out)
          File.chmod(0o644, mirb_js_out) if File.file?(mirb_js_out)
          File.chmod(0o644, mirb_wasm_out) if File.file?(mirb_wasm_out)

          metadata = {
            name: 'mruby',
            version: MRUBY_VERSION,
            source: MRUBY_REPO,
            builtAtUtc: Time.now.utc.iso8601,
            binaries: %w[mruby mirb]
          }
          File.write(version_out, JSON.pretty_generate(metadata) + "\n")

          puts "Wrote #{js_out}"
          puts "Wrote #{wasm_out}"
          puts "Wrote #{mirb_js_out}"
          puts "Wrote #{mirb_wasm_out}"
          puts "Wrote #{version_out}"
        end

        def ensure_aot_ir_inputs
          aot_inputs = {
            'apple2' => APPLE2_AOT_IR_PATH,
            'cpu' => CPU8BIT_AOT_IR_PATH,
            'mos6502' => MOS6502_AOT_IR_PATH
          }
          missing = aot_inputs.select { |_runner_id, path| !File.file?(path) }
          return if missing.empty?

          puts 'Generating missing AOT IR inputs for WASM build...'
          ensure_dir(SCRIPT_DIR)

          exports_by_id = runner_exports.each_with_object({}) { |runner, acc| acc[runner[:id]] = runner }
          missing.each do |runner_id, path|
            runner = exports_by_id[runner_id]
            unless runner
              warn "WARNING: no runner export found for #{runner_id}; cannot generate #{path}"
              next
            end

            generate_runner_assets(runner)
            warn "WARNING: failed to generate AOT IR source #{path}" unless File.file?(path)
          end
        end

        def command_available?(command)
          ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).any? do |path|
            candidate = File.join(path, command.to_s)
            File.file?(candidate) && File.executable?(candidate)
          end
        end

        def run_rustup_target_add!
          run_command('rustup', 'target', 'add', 'wasm32-unknown-unknown')
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

        def build_compiler_aot_wasm(ir_path:, artifact:)
          puts "Building ir_compiler -> #{artifact} (AOT from #{ir_path})"
          unless File.file?(ir_path)
            warn "WARNING: AOT IR source not found: #{ir_path}; #{artifact} not updated"
            return
          end

          compiler_dir = File.join(SIM_DIR, 'ir_compiler')
          generated = run_command(
            'cargo', 'run', '--quiet', '--bin', 'aot_codegen', '--', ir_path, AOT_GEN_PATH,
            chdir: compiler_dir
          )
          unless generated
            warn "WARNING: ir_compiler AOT code generation failed; #{artifact} not updated"
            return
          end

          built = run_command(
            'cargo', 'build', '--release', '--target', 'wasm32-unknown-unknown', '--features', 'aot',
            chdir: compiler_dir
          )
          unless built
            warn "WARNING: ir_compiler AOT build failed; #{artifact} not updated"
            return
          end

          src_wasm = File.join(compiler_dir, 'target', 'wasm32-unknown-unknown', 'release', 'ir_compiler.wasm')
          unless File.file?(src_wasm)
            warn "WARNING: missing wasm output #{src_wasm}; #{artifact} not updated"
            return
          end

          out_file = File.join(PKG_DIR, artifact)
          FileUtils.cp(src_wasm, out_file)
          puts "Wrote #{out_file}"
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

        def generate_runner_default_bin_assets
          puts 'Generating web default binary assets...'
          assets = (DEFAULT_BIN_ASSETS + cpu8bit_software_bin_assets)
            .uniq { |entry| entry[:dst] }
          assets.each do |asset|
            ensure_dir(File.dirname(asset[:dst]))
            copy_required_file(asset[:src], asset[:dst])
          end
        end

        def cpu8bit_software_bin_assets
          Dir.glob(File.join(CPU8BIT_SOFTWARE_BIN_DIR, '*.bin')).sort.map do |src|
            {
              src: src,
              dst: File.join(SCRIPT_DIR, 'cpu', 'software', File.basename(src))
            }
          end
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
          File.write(runner[:hier_ir], JSON.generate(hier_ir_hash, max_nesting: false))
          puts "Wrote #{runner[:hier_ir]}"

          source_bundle = build_source_bundle(top_class, runner[:id])
          File.write(runner[:source_output], JSON.pretty_generate(source_bundle, { max_nesting: false }))
          puts "Wrote #{runner[:source_output]} (#{Array(source_bundle[:components]).length} components)"
          write_component_source_files(runner: runner, bundle: source_bundle)

          schematic_bundle = top_class.to_schematic(sim_ir: flat_ir, runner: runner[:id])
          File.write(runner[:schematic_output], JSON.pretty_generate(schematic_bundle, { max_nesting: false }))
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
          parsed = JSON.parse(json, max_nesting: false)
          File.write(output_path, JSON.generate(parsed, max_nesting: false))
          puts "Wrote #{output_path}"
        end

        def constantize(name)
          name.split('::').reject(&:empty?).inject(Object) { |scope, const_name| scope.const_get(const_name) }
        end

        def runner_configs
          @runner_configs ||= load_runner_configs
        end

        def runner_exports
          @runner_exports ||= runner_configs.filter_map do |config|
            preset = config[:preset]
            next if preset['usesManualIr']

            {
              id: config[:id],
              top_class_name: config[:top_class_name],
              requires: config[:requires],
              source_output: web_asset_path_to_disk(preset.fetch('sourceBundlePath'), config[:config_path], 'sourceBundlePath'),
              sim_ir: web_asset_path_to_disk(preset.fetch('simIrPath'), config[:config_path], 'simIrPath'),
              hier_ir: web_asset_path_to_disk(preset.fetch('explorerIrPath'), config[:config_path], 'explorerIrPath'),
              schematic_output: web_asset_path_to_disk(preset.fetch('schematicPath'), config[:config_path], 'schematicPath')
            }
          end
        end

        def load_runner_configs
          RUNNER_CONFIG_PATHS.map { |path| load_runner_config(path) }
        end

        def load_runner_config(config_path)
          raise "Missing runner config: #{config_path}" unless File.file?(config_path)

          raw = JSON.parse(File.read(config_path))
          runner = raw.fetch('runner') do
            raise "Runner config #{config_path} is missing top-level key: runner"
          end

          id = String(runner.fetch('id')).strip
          raise "Runner config #{config_path} has empty runner.id" if id.empty?

          label = String(runner.fetch('label')).strip
          raise "Runner config #{config_path} has empty runner.label" if label.empty?

          top_class_name = String(runner.fetch('topClassName')).strip
          raise "Runner config #{config_path} has empty runner.topClassName" if top_class_name.empty?

          requires = Array(runner.fetch('requires')).map do |raw_path|
            resolved = File.expand_path(raw_path.to_s, PROJECT_ROOT)
            raise "Runner config #{config_path} has missing require file: #{raw_path}" unless File.file?("#{resolved}.rb") || File.file?(resolved)

            resolved
          end

          if requires.empty?
            raise "Runner config #{config_path} must include at least one runner.requires path"
          end

          preset = runner.each_with_object({}) do |(key, value), acc|
            next if %w[order default topClassName requires].include?(key)

            acc[key] = value
          end
          preset['id'] = id
          preset['label'] = label
          preset['usesManualIr'] = !!preset['usesManualIr']
          preset['preferredTab'] = String(preset['preferredTab'] || 'vcdTab')
          preset['enableApple2Ui'] = !!preset['enableApple2Ui']

          unless preset['usesManualIr']
            %w[simIrPath explorerIrPath sourceBundlePath schematicPath].each do |required_key|
              value = String(preset[required_key] || '').strip
              raise "Runner config #{config_path} missing runner.#{required_key}" if value.empty?
            end
          end

          {
            id: id,
            order: normalize_runner_order(runner['order']),
            default: runner['default'] == true,
            top_class_name: top_class_name,
            requires: requires,
            preset: preset,
            config_path: config_path
          }
        end

        def normalize_runner_order(value)
          return 1000 if value.nil?

          Integer(value)
        rescue StandardError
          raise "Runner config has non-integer runner.order: #{value.inspect}"
        end

        def web_asset_path_to_disk(web_path, config_path, key_name)
          normalized = String(web_path || '').strip.sub(%r{\A\./}, '')
          unless normalized.start_with?('assets/fixtures/')
            raise "Runner config #{config_path} has invalid #{key_name}: #{web_path.inspect} (expected ./assets/fixtures/...)"
          end

          File.join(WEB_ROOT, normalized)
        end

        def write_runner_preset_module(configs)
          ordered = configs.sort_by { |config| [config[:order], config[:id]] }
          presets = {}
          ordered.each do |config|
            presets[config[:id]] = config[:preset]
          end

          runner_order = ordered.map { |config| config[:id] }
          default_runner_id = ordered.find { |config| config[:default] }&.dig(:id) || runner_order.first

          content = <<~MJS
            // Auto-generated by `rake web:generate`. Do not edit manually.
            export const GENERATED_RUNNER_PRESETS = Object.freeze(#{JSON.pretty_generate(presets)});
            export const GENERATED_RUNNER_ORDER = Object.freeze(#{JSON.generate(runner_order)});
            export const GENERATED_DEFAULT_RUNNER_ID = #{JSON.generate(default_runner_id)};
          MJS

          ensure_dir(File.dirname(RUNNER_PRESET_MODULE_PATH))
          File.write(RUNNER_PRESET_MODULE_PATH, content)
          puts "Wrote #{RUNNER_PRESET_MODULE_PATH}"
        end

        def collect_memory_dump_asset_paths
          Dir.glob(File.join(ASSET_ROOT, '**', '*')).filter_map do |path|
            next unless File.file?(path)

            ext = File.extname(path).downcase
            next unless DUMP_ASSET_EXTENSIONS.include?(ext)

            relative = path.sub(%r{\A#{Regexp.escape(WEB_ROOT)}/}, '')
            "./#{relative}"
          end.sort
        end

        def write_memory_dump_asset_module
          asset_paths = collect_memory_dump_asset_paths
          content = <<~MJS
            // Auto-generated by `rake web:generate`. Do not edit manually.
            export const GENERATED_MEMORY_DUMP_ASSET_FILES = Object.freeze(#{JSON.pretty_generate(asset_paths)});
          MJS

          ensure_dir(File.dirname(MEMORY_DUMP_ASSET_MODULE_PATH))
          File.write(MEMORY_DUMP_ASSET_MODULE_PATH, content)
          puts "Wrote #{MEMORY_DUMP_ASSET_MODULE_PATH}"
        end

        RUNNER_CONFIG_PATHS = %w[8bit mos6502 apple2 gameboy].map do |name|
          File.join(PROJECT_ROOT, 'examples', name, 'config.json')
        end.freeze
        MRUBY_VERSION = '3.4.0'
        MRUBY_REPO = 'https://github.com/mruby/mruby.git'
        REQUIRED_WASM_OUTPUTS = %w[
          mruby.js
          mruby.wasm
          mirb.js
          mirb.wasm
          mruby.version.json
        ].freeze
        ASSET_ROOT = File.join(WEB_ROOT, 'assets')
        WASM_BUILD_STAMP_PATH = File.join(PKG_DIR, '.web_build_stamp')
        DUMP_ASSET_EXTENSIONS = %w[.bin .mem .dat .rhdlsnap .snapshot].freeze
        RUNNER_PRESET_MODULE_PATH = File.join(PROJECT_ROOT, 'web', 'app', 'components', 'runner', 'config', 'generated_presets.mjs')
        MEMORY_DUMP_ASSET_MODULE_PATH = File.join(PROJECT_ROOT, 'web', 'app', 'components', 'memory', 'config', 'generated_dump_assets.mjs')
      end
    end
  end
end
