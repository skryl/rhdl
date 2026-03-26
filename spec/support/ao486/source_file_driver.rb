# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'set'

require_relative '../../../examples/ao486/utilities/import/cpu_importer'

module RHDL
  module Examples
    module AO486
      module Unit
        module SourceFileDriver
          module_function

          def install_examples(example_group, source_relative_path:, module_names:)
            normalized_source = source_relative_path.to_s
            normalized_modules = Array(module_names).map(&:to_s).sort.freeze

            example_group.include AO486UnitSupport::RuntimeImportRequirements

            example_group.let(:ao486_runtime_session) do
              require_reference_tree!
              require_import_tool!
              AO486UnitSupport::RuntimeImportSession.current
            end

            example_group.let(:ao486_source_records) do
              ao486_runtime_session.records_for_source(normalized_source)
            end

            example_group.it "stages #{normalized_source} as Verilog semantically close to the original", timeout: 480 do
              expect(ao486_source_records.map(&:module_name)).to eq(normalized_modules)

              record = ao486_source_records.first
              aggregate_failures 'source-backed module metadata' do
                expect(record.source_relative_path).to eq(normalized_source)
                expect(File.file?(record.source_path)).to be(true)
                expect(File.file?(record.staged_source_path)).to be(true)
                expect(File.file?(record.generated_ruby_path)).to be(true)
              end

              report = SourceFileDriver.staged_verilog_report_for(
                session: ao486_runtime_session,
                source_relative_path: normalized_source,
                source_path: record.source_path,
                staged_source_path: record.staged_source_path,
                module_names: normalized_modules
              )
              expect(report[:match]).to be(true), SourceFileDriver.format_source_report(normalized_source, report)
            end

            example_group.it "raises #{normalized_source} to high-level RHDL without semantic drift", timeout: 480 do
              expect(ao486_source_records.map(&:module_name)).to eq(normalized_modules)

              normalized_modules.each do |module_name|
                aggregate_failures(module_name) do
                  record = ao486_runtime_session.module_record(module_name)

                  rhdl_report = Sparc64ParityHelper.rhdl_level_report(
                    generated_ruby_path: record.generated_ruby_path,
                    original_verilog_path: record.source_path,
                    expected_verilog_path: record.staged_source_path,
                    module_name: module_name,
                    suite_raise_diagnostics: ao486_runtime_session.suite_raise_diagnostics,
                    component_class: record.component_class
                  )
                  expect(rhdl_report[:issues]).to eq([]), SourceFileDriver.format_rhdl_report(module_name, rhdl_report)

                  expected_signature = SourceFileDriver.package_signature_for(
                    session: ao486_runtime_session,
                    module_name: module_name
                  )
                  actual_signature = SourceFileDriver.raised_component_signature(record.component_class, module_name)
                  expect(actual_signature).to eq(expected_signature), SourceFileDriver.format_signature_report(
                    module_name,
                    expected_signature,
                    actual_signature
                  )
                end
              end
            end
          end

          def staged_verilog_report_for(session:, source_relative_path:, source_path:, staged_source_path:, module_names:)
            key = [session.temp_root, source_relative_path.to_s]
            source_cache_mutex.synchronize do
              source_report_cache[key] ||= begin
                original_signature = semantic_signature_for_paths(
                  primary_path: source_path,
                  extra_paths: session.dependency_verilog_files_for_source(source_relative_path),
                  base_dir: File.join(semantic_base_dir_for(session: session, source_relative_path: source_relative_path), 'original'),
                  source_relative_path: source_relative_path,
                  module_names: module_names,
                  include_dirs: session.include_dirs,
                  top_module: Array(module_names).one? ? Array(module_names).first : nil
                )
                staged_signature = semantic_signature_for_paths(
                  primary_path: staged_source_path,
                  extra_paths: session.staged_dependency_verilog_files_for_source(source_relative_path),
                  base_dir: File.join(semantic_base_dir_for(session: session, source_relative_path: source_relative_path), 'staged'),
                  source_relative_path: source_relative_path,
                  module_names: module_names,
                  include_dirs: session.staged_include_dirs,
                  top_module: Array(module_names).one? ? Array(module_names).first : nil
                )

                {
                  match: original_signature == staged_signature,
                  original_signature: original_signature,
                  staged_signature: staged_signature
                }
              end
            end
          end

          def staged_signature_for(session:, source_relative_path:, source_path:, staged_source_path:, module_names:, variant: :staged)
            key = [session.temp_root, source_relative_path.to_s, variant.to_s]
            source_cache_mutex.synchronize do
              source_signature_cache[key] ||= begin
                if variant == :original
                  primary_path = source_path
                  extra_paths = session.dependency_verilog_files_for_source(source_relative_path)
                  include_dirs = session.include_dirs
                else
                  primary_path = staged_source_path
                  extra_paths = session.staged_dependency_verilog_files_for_source(source_relative_path)
                  include_dirs = session.staged_include_dirs
                end

                semantic_signature_for_paths(
                  primary_path: primary_path,
                  extra_paths: extra_paths,
                  base_dir: semantic_base_dir_for(session: session, source_relative_path: source_relative_path, variant: variant),
                  source_relative_path: source_relative_path,
                  module_names: module_names,
                  include_dirs: include_dirs,
                  top_module: Array(module_names).one? ? Array(module_names).first : nil
                )
              end
            end
          end

          def semantic_signature_for_paths(primary_path:, extra_paths:, base_dir:, source_relative_path:, module_names:, include_dirs:,
                                           top_module:)
            begin
              normalized_semantic_signature_from_verilog_paths(
                primary_path: primary_path,
                extra_paths: extra_paths,
                base_dir: base_dir,
                stem: source_digest_for(source_relative_path),
                module_names: module_names,
                include_dirs: include_dirs,
                top_module: top_module
              )
            rescue StandardError
              raise if Array(extra_paths).empty?

              normalized_semantic_signature_from_verilog_paths(
                primary_path: primary_path,
                extra_paths: [],
                base_dir: File.join(base_dir, 'source_only'),
                stem: source_digest_for(source_relative_path),
                module_names: module_names,
                include_dirs: include_dirs,
                top_module: top_module
              )
            end
          end

          def normalized_semantic_signature_from_verilog_paths(primary_path:, extra_paths:, base_dir:, stem:, module_names:,
                                                               include_dirs:, top_module:)
            mlir = convert_verilog_paths_to_mlir(
              primary_path: primary_path,
              extra_paths: extra_paths,
              base_dir: base_dir,
              stem: stem,
              include_dirs: include_dirs,
              top_module: top_module
            )
            normalized_semantic_signature_from_mlir(mlir, module_names: Array(module_names).map(&:to_s).sort)
          end

          def convert_verilog_paths_to_mlir(primary_path:, extra_paths:, base_dir:, stem:, include_dirs:, top_module:)
            raise 'circt-verilog not available' unless HdlToolchain.which('circt-verilog')

            FileUtils.mkdir_p(base_dir)
            core_mlir_path = File.join(base_dir, "#{stem}.core.mlir")
            normalized_primary_path = File.join(base_dir, "#{stem}.normalized.v")
            File.write(normalized_primary_path, normalize_verilog_source_for_semantic_compare(File.read(primary_path)))

            normalized_extra_paths = Array(extra_paths).each_with_index.map do |path, index|
              normalized_extra_path = File.join(base_dir, "#{stem}.extra_#{index}.v")
              File.write(normalized_extra_path, normalize_verilog_source_for_semantic_compare(File.read(path)))
              normalized_extra_path
            end

            support_stub_path = write_semantic_support_stubs(
              normalized_paths: [normalized_primary_path, *normalized_extra_paths],
              base_dir: base_dir,
              stem: stem
            )
            helper_prelude_paths = semantic_helper_prelude_paths(
              primary_path: normalized_primary_path,
              include_dirs: include_dirs
            )
            wrapper_path = File.join(base_dir, "#{stem}.import_all.sv")
            File.open(wrapper_path, 'w') do |f|
              [*helper_prelude_paths, normalized_primary_path, *normalized_extra_paths, support_stub_path].each do |path|
                f.puts "`include \"#{File.expand_path(path)}\""
              end
            end

            result = RHDL::Codegen::CIRCT::Tooling.verilog_to_circt_mlir(
              verilog_path: wrapper_path,
              out_path: core_mlir_path,
              tool: 'circt-verilog',
              extra_args: Sparc64ParityHelper.inferred_verilog_tool_args(
                primary_path,
                extra_verilog_paths: extra_paths,
                include_dirs: include_dirs,
                top_module: top_module
              )
            )
            raise "Verilog->CIRCT failed:\n#{result[:command]}\n#{result[:stderr]}" unless result[:success]

            File.read(core_mlir_path)
          end

          def normalize_verilog_source_for_semantic_compare(source)
            normalized = source.dup
            normalized.gsub!(/^\s*defparam\b.*?;\s*/m, '')
            normalized
          end

          def semantic_helper_prelude_paths(primary_path:, include_dirs:)
            return [] if source_includes_helper_defines?(File.read(primary_path))

            defines_path = semantic_helper_defines_path(include_dirs)
            return [] unless defines_path

            [defines_path]
          end

          def source_includes_helper_defines?(source)
            source.match?(/`include\s+"(?:[^"]*\/)?defines\.v"/) ||
              source.match?(/`include\s+"(?:[^"]*\/)?startup_default\.v"/) ||
              source.match?(/`include\s+"(?:[^"]*\/)?autogen\/defines\.v"/)
          end

          def semantic_helper_defines_path(include_dirs)
            Array(include_dirs).each do |dir|
              candidate = File.expand_path(File.join(dir, 'defines.v'))
              return candidate if File.file?(candidate)
            end

            nil
          end

          def write_semantic_support_stubs(normalized_paths:, base_dir:, stem:)
            stub_path = File.join(base_dir, "#{stem}.semantic_support_stubs.v")
            stub_ports = {}
            defined_modules = Set.new

            Array(normalized_paths).each do |path|
              source = File.read(path)
              defined_modules.merge(semantic_compare_importer.send(:extract_defined_modules, source).map(&:to_s))
              semantic_compare_importer.send(
                :merge_stub_ports!,
                stub_ports,
                semantic_compare_importer.send(:extract_stub_ports, source)
              )
            end

            stub_ports.reject! { |module_name, _entry| defined_modules.include?(module_name.to_s) }
            semantic_compare_importer.send(:write_stub_file, stub_path, stub_ports)
            stub_path
          end

          def semantic_compare_importer
            @semantic_compare_importer ||= RHDL::Examples::AO486::Import::CpuImporter.allocate
          end

          def normalized_semantic_signature_from_mlir(mlir, module_names: nil)
            import_result = RHDL::Codegen.import_circt_mlir(mlir)
            unless import_result.success?
              raise "CIRCT import failed:\n#{Sparc64ParityHelper.diagnostic_messages(import_result.diagnostics).join("\n")}"
            end

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

            module_map = import_result.modules.each_with_object({}) { |mod, acc| acc[mod.name.to_s] = mod }
            cache = {}
            Sparc64ParityHelper.stable_sort(
              modules.map { |mod| [mod.name.to_s, semantic_signature_for_module_from_package(mod, module_map, cache)] }
            )
          end

          def semantic_signature_for_module_from_package(mod, module_map, cache)
            cache.fetch(mod.name.to_s) do
              cache[mod.name.to_s] = {
                parameters: Sparc64ParityHelper.stable_sort((mod.parameters || {}).map { |key, value| [key.to_s, value] }),
                ports: Sparc64ParityHelper.stable_sort(mod.ports.map { |port| [port.direction.to_s, port.width.to_i] }),
                regs: Sparc64ParityHelper.stable_sort(mod.regs.map { |reg| [reg.width.to_i, reg.reset_value] }),
                assigns: Sparc64ParityHelper.stable_sort(mod.assigns.map { |assign| Sparc64ParityHelper.expr_signature(assign.expr) }),
                processes: Sparc64ParityHelper.stable_sort(mod.processes.map { |process| Sparc64ParityHelper.process_signature(process) }),
                instances: Sparc64ParityHelper.stable_sort(
                  mod.instances.map { |inst| instance_signature_from_package(inst) }
                )
              }
            end
          end

          def instance_signature_from_package(inst)
            {
              module: canonical_instance_module_name(inst.module_name),
              parameters: Sparc64ParityHelper.stable_sort((inst.parameters || {}).map { |key, value| [key.to_s, value] }),
              connections: Sparc64ParityHelper.stable_sort(
                Array(inst.connections).map { |conn| [conn.direction.to_s, conn.port_name.to_s] }
              )
            }
          end

          def canonical_instance_module_name(name)
            name.to_s.sub(/_\d+\z/, '')
          end

          def package_signature_for(session:, module_name:)
            key = session.temp_root.to_s
            source_cache_mutex.synchronize do
              package_signature_cache[key] ||= begin
                mlir = File.read(session.import_result.normalized_core_mlir_path)
                normalized_semantic_signature_from_mlir(mlir, module_names: session.closure_modules).to_h.freeze
              end
            end.fetch(module_name.to_s)
          end

          def raised_component_signature(component_class, module_name)
            emitted_mlir = if component_class.respond_to?(:to_ir_hierarchy)
                             component_class.to_ir_hierarchy(top_name: module_name)
                           else
                             component_class.to_ir(top_name: module_name)
                           end
            normalized_semantic_signature_from_mlir(
              emitted_mlir,
              module_names: [module_name]
            ).to_h.fetch(module_name.to_s)
          end

          def semantic_base_dir_for(session:, source_relative_path:, variant: nil)
            parts = [session.temp_root, 'checks', 'semantic']
            parts << variant.to_s if variant
            parts << source_digest_for(source_relative_path)
            File.join(*parts)
          end

          def source_digest_for(source_relative_path)
            Digest::SHA256.hexdigest(source_relative_path.to_s)[0, 16]
          end

          def format_source_report(source_relative_path, report)
            [
              "staged Verilog drift for #{source_relative_path}",
              "original signature: #{report[:original_signature].inspect}",
              "staged signature: #{report[:staged_signature].inspect}"
            ].join("\n")
          end

          def format_rhdl_report(module_name, report)
            issues = Array(report[:issues])
            body = issues.empty? ? report.inspect : issues.join("\n")
            [
              "raised RHDL check failed for #{module_name}",
              body
            ].join("\n")
          end

          def format_signature_report(module_name, expected_signature, actual_signature)
            [
              "raised semantic drift for #{module_name}",
              "expected signature: #{expected_signature.inspect}",
              "actual signature: #{actual_signature.inspect}"
            ].join("\n")
          end

          def source_report_cache
            @source_report_cache ||= {}
          end

          def source_signature_cache
            @source_signature_cache ||= {}
          end

          def package_signature_cache
            @package_signature_cache ||= {}
          end

          def source_cache_mutex
            @source_cache_mutex ||= Mutex.new
          end
        end
      end
    end
  end
end
