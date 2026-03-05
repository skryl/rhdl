# frozen_string_literal: true

require_relative '../task'
require_relative '../config'
require 'open3'
require 'yaml'

module RHDL
  module CLI
    module Tasks
      # Task for validating repository hygiene invariants
      class HygieneTask < Task
        REQUIRED_SUBMODULES = %w[
          examples/apple2/reference
          examples/gameboy/reference
          examples/riscv/software/linux
          examples/riscv/software/xv6
          examples/ao486/reference
        ].freeze

        FORBIDDEN_IGNORE_ENTRIES = %w[
          lib/rhdl/codegen/netlist/sim/netlist_interpreter/target/
          lib/rhdl/codegen/netlist/sim/netlist_interpreter/lib/
          lib/rhdl/codegen/netlist/sim/netlist_jit/target/
          lib/rhdl/codegen/netlist/sim/netlist_jit/lib/
          lib/rhdl/codegen/netlist/sim/netlist_compiler/target/
          lib/rhdl/codegen/netlist/sim/netlist_compiler/lib/
          lib/rhdl/codegen/ir/sim/ir_interpreter/target/
          lib/rhdl/codegen/ir/sim/ir_interpreter/lib/
          lib/rhdl/codegen/ir/sim/ir_jit/target/
          lib/rhdl/codegen/ir/sim/ir_jit/lib/
          lib/rhdl/codegen/ir/sim/ir_compiler/target/
          lib/rhdl/codegen/ir/sim/ir_compiler/lib/
          lib/rhdl/codegen/ir/sim/ir_compiler/*.json
        ].freeze

        REQUIRED_IGNORE_ENTRIES = %w[
          /.tmp/
          /web/test-results/
          lib/rhdl/sim/native/netlist/netlist_interpreter/target/
          lib/rhdl/sim/native/netlist/netlist_interpreter/lib/
          lib/rhdl/sim/native/netlist/netlist_jit/target/
          lib/rhdl/sim/native/netlist/netlist_jit/lib/
          lib/rhdl/sim/native/netlist/netlist_compiler/target/
          lib/rhdl/sim/native/netlist/netlist_compiler/lib/
          lib/rhdl/sim/native/ir/ir_interpreter/target/
          lib/rhdl/sim/native/ir/ir_interpreter/lib/
          lib/rhdl/sim/native/ir/ir_jit/target/
          lib/rhdl/sim/native/ir/ir_jit/lib/
          lib/rhdl/sim/native/ir/ir_compiler/target/
          lib/rhdl/sim/native/ir/ir_compiler/lib/
          lib/rhdl/sim/native/ir/ir_compiler/*.json
        ].freeze

        REQUIRED_LOCAL_CRATE_IGNORES = {
          'lib/rhdl/sim/native/netlist/netlist_interpreter/.gitignore' => %w[/target/ /lib/],
          'lib/rhdl/sim/native/netlist/netlist_jit/.gitignore' => %w[/target/ /lib/],
          'lib/rhdl/sim/native/netlist/netlist_compiler/.gitignore' => %w[/target/ /lib/]
        }.freeze

        TRACKED_EPHEMERA = %w[
          .tmp/riscv_ext_probe.err
          .tmp/riscv_ext_probe.s
          web/test-results/.last-run.json
        ].freeze

        DEFAULT_SHARED_SYMLINKS = {
          'examples/mos6502/software/code/fig_forth/fig6502.asm' => 'examples/apple2/software/code/fig_forth/fig6502.asm',
          'examples/mos6502/software/code/fig_forth/Makefile' => 'examples/apple2/software/code/fig_forth/Makefile',
          'examples/mos6502/software/code/fig_forth/README.TXT' => 'examples/apple2/software/code/fig_forth/README.TXT',
          'examples/mos6502/software/disks/karateka.dsk' => 'examples/apple2/software/disks/karateka.dsk',
          'examples/mos6502/software/disks/karateka.bin' => 'examples/apple2/software/disks/karateka.bin',
          'examples/mos6502/software/disks/karateka_mem.bin' => 'examples/apple2/software/disks/karateka_mem.bin',
          'examples/mos6502/software/disks/karateka_mem_meta.txt' => 'examples/apple2/software/disks/karateka_mem_meta.txt',
          'examples/mos6502/software/roms/appleiigo.rom' => 'examples/apple2/software/roms/appleiigo.rom',
          'examples/mos6502/software/roms/disk2_boot.bin' => 'examples/apple2/software/roms/disk2_boot.bin'
        }.freeze

        LEGACY_NAMESPACE_PATTERNS = {
          'RHDL::Export' => /\bRHDL::Export\b/,
          'Codegen::Structure' => /\b(?:RHDL::)?Codegen::Structure\b/,
          'RHDL::Codegen::IR' => /\bRHDL::Codegen::IR\b/,
          "require 'rhdl/simulation'" => /require\s+['"]rhdl\/simulation['"]/,
          'RHDL::HDL::Synth* aliases' => /\bRHDL::HDL::Synth[A-Za-z0-9_]*\b/,
          'RHDL::Codegen.gate_level' => /\bRHDL::Codegen\.gate_level\b/,
          'legacy backend symbols (:cpu/:gpu/:native_interpreter)' => /\bbackend:\s*:(?:cpu|gpu|native_interpreter)\b/
        }.freeze

        LEGACY_SCAN_GLOBS = %w[
          README.md
          Rakefile
          exe/rhdl
          lib/**/*.rb
          docs/**/*.md
        ].freeze

        LEGACY_SCAN_EXCLUSIONS = %w[
          lib/rhdl/cli/tasks/hygiene_task.rb
        ].freeze

        def run
          puts_header('Repository Hygiene Check')

          failures = []
          failures.concat(check_submodule_parity)
          failures.concat(check_ignore_rules)
          failures.concat(check_tracked_ephemera)
          failures.concat(check_duplicate_policy)
          failures.concat(check_legacy_namespace_patterns)

          if failures.empty?
            puts '[OK] All hygiene checks passed.'
            return true
          end

          puts_error("Found #{failures.length} hygiene issue(s):")
          failures.each { |msg| puts "  - #{msg}" }
          raise "Hygiene check failed (#{failures.length} issue#{failures.length == 1 ? '' : 's'})"
        end

        private

        def root
          @root ||= File.expand_path(options[:root] || Config.project_root)
        end

        def allowlist_path
          options[:allowlist_path] || File.join(root, 'config', 'hygiene_allowlist.yml')
        end

        def load_allowlist
          return {} unless File.exist?(allowlist_path)

          YAML.safe_load(File.read(allowlist_path), permitted_classes: [], aliases: false) || {}
        rescue Psych::SyntaxError => e
          { '_load_error' => "Invalid YAML in #{allowlist_path}: #{e.message}" }
        end

        def check_submodule_parity
          failures = []
          module_paths = parse_gitmodules_paths
          gitlink_paths = parse_gitlink_paths

          (module_paths - gitlink_paths).sort.each do |path|
            failures << ".gitmodules lists '#{path}' but git index has no submodule gitlink"
          end

          (gitlink_paths - module_paths).sort.each do |path|
            failures << "Git index has submodule gitlink '#{path}' but .gitmodules has no matching entry"
          end

          REQUIRED_SUBMODULES.each do |path|
            failures << "Required submodule missing from .gitmodules: #{path}" unless module_paths.include?(path)
            failures << "Required submodule missing from git index: #{path}" unless gitlink_paths.include?(path)
          end

          failures
        end

        def check_ignore_rules
          failures = []
          gitignore_path = File.join(root, '.gitignore')
          unless File.exist?(gitignore_path)
            return ['Missing .gitignore']
          end

          lines = File.readlines(gitignore_path, chomp: true).map(&:strip)
          effective = lines.reject { |line| line.empty? || line.start_with?('#') }

          FORBIDDEN_IGNORE_ENTRIES.each do |entry|
            failures << ".gitignore contains stale ignore entry: #{entry}" if effective.include?(entry)
          end

          REQUIRED_IGNORE_ENTRIES.each do |entry|
            failures << ".gitignore is missing required ignore entry: #{entry}" unless effective.include?(entry)
          end

          REQUIRED_LOCAL_CRATE_IGNORES.each do |path, required_entries|
            abs = File.join(root, path)
            unless File.exist?(abs)
              failures << "Missing crate-local ignore file: #{path}"
              next
            end

            crate_lines = File.readlines(abs, chomp: true).map(&:strip)
            required_entries.each do |entry|
              failures << "#{path} missing required entry: #{entry}" unless crate_lines.include?(entry)
            end
          end

          failures
        end

        def check_tracked_ephemera
          out, status = git_capture('ls-files', '--', *TRACKED_EPHEMERA)
          return ["Failed to list tracked ephemera: #{out.strip}"] unless status.success?

          out.lines.map(&:strip).reject(&:empty?).map do |path|
            "Tracked ephemeral file must be removed from git: #{path}"
          end
        end

        def check_duplicate_policy
          failures = []
          allowlist = load_allowlist
          if allowlist.key?('_load_error')
            return [allowlist['_load_error']]
          end

          symlink_map = allowlist.fetch('shared_symlinks', DEFAULT_SHARED_SYMLINKS)
          unless symlink_map.is_a?(Hash)
            return ["Invalid allowlist format: 'shared_symlinks' must be a mapping in #{allowlist_path}"]
          end

          symlink_map.each do |link_path, target_path|
            link_abs = File.join(root, link_path)
            target_abs = File.join(root, target_path)

            unless File.exist?(target_abs)
              failures << "Shared canonical target is missing: #{target_path}"
              next
            end

            unless File.exist?(link_abs) || File.symlink?(link_abs)
              failures << "Shared file missing: #{link_path}"
              next
            end

            unless File.symlink?(link_abs)
              failures << "Shared file must be a symlink: #{link_path}"
              next
            end

            begin
              resolved_link = File.realpath(link_abs)
              resolved_target = File.realpath(target_abs)
              failures << "Symlink target mismatch for #{link_path} (expected #{target_path})" unless resolved_link == resolved_target
            rescue StandardError => e
              failures << "Failed to resolve symlink #{link_path}: #{e.message}"
            end
          end

          failures
        end

        def check_legacy_namespace_patterns
          failures = []

          active_files_for_legacy_scan.each do |path|
            abs_path = File.join(root, path)
            next unless File.file?(abs_path)

            content = File.binread(abs_path)
            next if content.include?("\x00")

            text = content.encode('UTF-8', invalid: :replace, undef: :replace)
            text.each_line.with_index(1) do |line, line_no|
              LEGACY_NAMESPACE_PATTERNS.each do |label, pattern|
                next unless pattern.match?(line)

                failures << "Forbidden legacy pattern '#{label}' in #{path}:#{line_no}"
              end
            end
          end

          failures
        end

        def active_files_for_legacy_scan
          files = []
          Dir.chdir(root) do
            LEGACY_SCAN_GLOBS.each do |glob|
              files.concat(Dir.glob(glob))
            end
          end

          files.uniq.reject { |path| LEGACY_SCAN_EXCLUSIONS.include?(path) }.sort
        end

        def parse_gitmodules_paths
          gitmodules = File.join(root, '.gitmodules')
          return [] unless File.exist?(gitmodules)

          File.readlines(gitmodules).filter_map do |line|
            match = line.match(/^\s*path\s*=\s*(.+?)\s*$/)
            match&.captures&.first
          end.sort
        end

        def parse_gitlink_paths
          out, status = git_capture('ls-files', '-s')
          return [] unless status.success?

          out.lines.filter_map do |line|
            match = line.match(/^160000\s+[0-9a-f]{40}\s+\d+\t(.+)$/)
            match&.captures&.first
          end.sort
        end

        def git_capture(*args)
          Open3.capture2e('git', '-C', root, *args)
        end
      end
    end
  end
end
