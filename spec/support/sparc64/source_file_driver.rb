# frozen_string_literal: true

require 'digest'
require 'fileutils'

module RHDL
  module Examples
    module SPARC64
      module Unit
        module SourceFileDriver
          module_function

          def install_examples(example_group, source_relative_path:, module_names:)
            normalized_source = source_relative_path.to_s
            normalized_modules = Array(module_names).map(&:to_s).sort.freeze

            example_group.include Sparc64UnitSupport::RuntimeImportRequirements

            example_group.let(:sparc64_runtime_session) do
              require_reference_tree!
              require_import_tool!
              Sparc64UnitSupport::RuntimeImportSession.current
            end

            example_group.let(:sparc64_source_records) do
              sparc64_runtime_session.modules_for_source(normalized_source)
            end

            example_group.it 'matches the emitted W1 coverage inventory for this source file', timeout: 480 do
              expect(sparc64_source_records.map(&:module_name)).to eq(normalized_modules)
            end

            normalized_modules.each do |module_name|
              example_group.it "#{module_name} preserves staged Verilog, raises to high-level RHDL, and matches original Verilog",
                               timeout: 480 do
                record = sparc64_runtime_session.module_record(module_name)

                aggregate_failures 'source-backed module metadata' do
                  expect(record.source_relative_path).to eq(normalized_source)
                  expect(record.generated_ruby_path).to be_a(String)
                  expect(File.file?(record.source_path)).to be(true)
                  expect(File.file?(record.staged_source_path)).to be(true)
                  expect(File.file?(record.generated_ruby_path)).to be(true)
                end

                source_report = SourceFileDriver.staged_verilog_report_for(
                  session: sparc64_runtime_session,
                  source_relative_path: normalized_source,
                  source_path: record.source_path,
                  staged_source_path: record.staged_source_path,
                  module_names: normalized_modules
                )
                expect(source_report[:match]).to be(true), SourceFileDriver.format_source_report(
                  normalized_source,
                  source_report
                )

                rhdl_report = Sparc64ParityHelper.rhdl_level_report(
                  generated_ruby_path: record.generated_ruby_path,
                  original_verilog_path: record.source_path,
                  expected_verilog_path: record.staged_source_path,
                  module_name: module_name,
                  suite_raise_diagnostics: sparc64_runtime_session.suite_raise_diagnostics,
                  component_class: record.component_class
                )
                expect(rhdl_report[:issues]).to eq([]), SourceFileDriver.format_rhdl_report(
                  module_name,
                  rhdl_report
                )

                if (skip_reason = Sparc64ParityHelper.parity_skip_reason(component_class: record.component_class))
                  skip(skip_reason)
                end

                parity_report = Sparc64ParityHelper.parity_report(
                  component_class: record.component_class,
                  module_name: module_name,
                  verilog_files: SourceFileDriver.parity_verilog_files_for(
                    session: sparc64_runtime_session,
                    module_name: module_name
                  ),
                  original_verilog_path: record.source_path,
                  staged_verilog_path: record.staged_source_path,
                  base_dir: SourceFileDriver.parity_base_dir_for(
                    session: sparc64_runtime_session,
                    module_name: module_name
                  ),
                  include_dirs: sparc64_runtime_session.staged_include_dirs
                )
                expect(parity_report[:match]).to be(true), SourceFileDriver.format_parity_report(
                  module_name,
                  parity_report
                )
              end
            end
          end

          def staged_verilog_report_for(session:, source_relative_path:, source_path:, staged_source_path:, module_names:)
            key = [session.temp_root, source_relative_path.to_s]
            source_cache_mutex.synchronize do
              source_report_cache[key] ||= begin
                original_dependencies = session.dependency_verilog_files_for_source(source_relative_path)
                staged_dependencies = session.staged_dependency_verilog_files_for_source(source_relative_path)
                original_paths = [source_path, *original_dependencies.reject { |path| File.expand_path(path) == File.expand_path(source_path) }]
                staged_paths = [staged_source_path, *staged_dependencies.reject { |path| File.expand_path(path) == File.expand_path(staged_source_path) }]

                Sparc64ParityHelper.staged_verilog_semantic_report(
                  original_paths: original_paths,
                  staged_paths: staged_paths,
                  base_dir: semantic_base_dir_for(session: session, source_relative_path: source_relative_path),
                  module_names: module_names,
                  original_include_dirs: session.include_dirs,
                  staged_include_dirs: session.staged_include_dirs,
                  top_module: Array(module_names).one? ? Array(module_names).first : nil
                )
              end
            end
          end

          def semantic_base_dir_for(session:, source_relative_path:)
            File.join(session.temp_root, 'checks', 'semantic', source_digest_for(source_relative_path))
          end

          def parity_base_dir_for(session:, module_name:)
            File.join(session.temp_root, 'checks', 'parity', module_name.to_s)
          end

          def parity_verilog_files_for(session:, module_name:)
            base_dir = parity_base_dir_for(session: session, module_name: module_name)
            FileUtils.mkdir_p(base_dir)
            staged_files = session.parity_dependency_verilog_files_for(module_name).map do |path|
              session.staged_path_for_source(path)
            end.select { |path| File.file?(path) }.uniq

            importer = RHDL::Examples::SPARC64::Import::SystemImporter.new(
              clean_output: false,
              keep_workspace: true
            )
            support_stub_path = importer.send(
              :write_hierarchy_support_stubs,
              staged_root: base_dir,
              staged_module_files: staged_files,
              top_file: session.import_result&.staged_top_file || staged_files.first
            )

            [support_stub_path, *staged_files].uniq.freeze
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

          def format_parity_report(module_name, report)
            detail_lines = []
            detail_lines << "runtime backend: #{report[:runtime_backend]}" if report[:runtime_backend]
            detail_lines << "native IR fallback: #{report[:native_ir_error]}" if report[:native_ir_error]
            detail_lines << (report[:mismatch] || report[:error] || report.inspect)
            [
              "behavioral parity failed for #{module_name}",
              detail_lines.join("\n")
            ].join("\n")
          end

          def source_report_cache
            @source_report_cache ||= {}
          end

          def source_cache_mutex
            @source_cache_mutex ||= Mutex.new
          end
        end
      end
    end
  end
end
