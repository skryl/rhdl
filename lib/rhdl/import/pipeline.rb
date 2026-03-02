# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "set"
require "fileutils"

require_relative "blackbox_stub_generator"
require_relative "dependency_graph"
require_relative "missing_module_signature_extractor"
require_relative "project_writer"
require_relative "report"
require_relative "result"
require_relative "top_detector"
require_relative "checks/comparator"
require_relative "checks/report_writer"
require_relative "checks/runner"
require_relative "checks/stimulus_generator"
require_relative "checks/ao486_trace_harness"
require_relative "checks/ao486_component_parity_harness"
require_relative "checks/ao486_program_parity_harness"
require_relative "checks/trace_comparator"
require_relative "checks/trace_report_writer"
require_relative "checks/component_parity_report_writer"
require_relative "checks/program_parity_report_writer"

module RHDL
  module Import
    class Pipeline
      class << self
        def run(
          out:,
          project_slug:,
          options:,
          translated_modules:,
          failed_modules: [],
          diagnostics: [],
          writer: ProjectWriter.new,
          top_detector: TopDetector,
          dependency_graph_class: DependencyGraph,
          check_runner: nil,
          stimulus_generator: nil,
          comparator: nil,
          check_report_writer: nil,
          trace_comparator: nil,
          trace_report_writer: nil,
          ao486_trace_harness: nil,
          ao486_component_parity_harness: nil,
          ao486_program_parity_harness: nil,
          component_parity_report_writer: nil,
          program_parity_report_writer: nil,
          blackbox_stub_generator: BlackboxStubGenerator,
          report_builder: Report,
          result_class: Result
        )
          new(
            out: out,
            project_slug: project_slug,
            options: options,
            translated_modules: translated_modules,
            failed_modules: failed_modules,
            diagnostics: diagnostics,
            writer: writer,
            top_detector: top_detector,
            dependency_graph_class: dependency_graph_class,
            check_runner: check_runner,
            stimulus_generator: stimulus_generator,
            comparator: comparator,
            check_report_writer: check_report_writer,
            trace_comparator: trace_comparator,
            trace_report_writer: trace_report_writer,
            ao486_trace_harness: ao486_trace_harness,
            ao486_component_parity_harness: ao486_component_parity_harness,
            ao486_program_parity_harness: ao486_program_parity_harness,
            component_parity_report_writer: component_parity_report_writer,
            program_parity_report_writer: program_parity_report_writer,
            blackbox_stub_generator: blackbox_stub_generator,
            report_builder: report_builder,
            result_class: result_class
          ).run
        end
      end

      def initialize(
        out:,
        project_slug:,
        options:,
        translated_modules:,
        failed_modules:,
        diagnostics:,
        writer:,
        top_detector:,
        dependency_graph_class:,
        check_runner:,
        stimulus_generator:,
        comparator:,
        check_report_writer:,
        trace_comparator:,
        trace_report_writer:,
        ao486_trace_harness:,
        ao486_component_parity_harness:,
        ao486_program_parity_harness:,
        component_parity_report_writer:,
        program_parity_report_writer:,
        blackbox_stub_generator:,
        report_builder:,
        result_class:
      )
        @out = out
        @project_slug = project_slug
        @options = options.is_a?(Hash) ? options : {}
        @translated_modules = normalize_translated_modules(translated_modules)
        @failed_modules = normalize_failed_modules(failed_modules)
        @diagnostics = Array(diagnostics)
        @writer = writer
        @top_detector = top_detector
        @dependency_graph_class = dependency_graph_class
        @check_runner = check_runner || Checks::Runner.new
        @stimulus_generator = stimulus_generator || Checks::StimulusGenerator
        @comparator = comparator || Checks::Comparator
        @check_report_writer = check_report_writer || Checks::ReportWriter
        @trace_comparator = trace_comparator || Checks::TraceComparator
        @trace_report_writer = trace_report_writer || Checks::TraceReportWriter
        @ao486_trace_harness = ao486_trace_harness || Checks::Ao486TraceHarness
        @ao486_component_parity_harness =
          ao486_component_parity_harness || Checks::Ao486ComponentParityHarness
        @ao486_program_parity_harness =
          ao486_program_parity_harness || Checks::Ao486ProgramParityHarness
        @component_parity_report_writer =
          component_parity_report_writer || Checks::ComponentParityReportWriter
        @program_parity_report_writer =
          program_parity_report_writer || Checks::ProgramParityReportWriter
        @blackbox_stub_generator = blackbox_stub_generator || BlackboxStubGenerator
        @report_builder = report_builder
        @result_class = result_class
        @trace_input_cache = {}
      end

      def run
        missing_policy = missing_modules_policy
        initial_missing_failures =
          if missing_policy == "blackbox_stubs"
            []
          else
            build_missing_module_failures(
              infer_missing_module_signatures(
                modules: @translated_modules,
                failed_modules: @failed_modules
              )
            )
          end
        custom_export_failures = detect_custom_verilog_export_failures(@translated_modules)
        direct_failed_modules = merge_failed_modules(@failed_modules, initial_missing_failures)
        direct_failed_modules = merge_failed_modules(direct_failed_modules, custom_export_failures)

        detected_tops = @top_detector.detect(
          modules: modules_for_top_detection,
          explicit_tops: option_value(:top)
        )

        graph = @dependency_graph_class.new(modules: @translated_modules)
        prune_result = graph.prune_for_failures(
          roots: detected_tops,
          failed_modules: direct_failed_modules
        )

        direct_failed_name_set = Array(direct_failed_modules)
          .map { |entry| value_for(entry, :name).to_s }
          .reject(&:empty?)
          .to_set
        kept_names = prune_result.fetch(:kept).reject { |name| direct_failed_name_set.include?(name) }
        kept_name_set = kept_names.to_set
        kept_modules = @translated_modules.select { |entry| kept_name_set.include?(entry[:name]) }

        pruned_failures = prune_result.fetch(:pruned).map do |entry|
          dependencies = Array(entry[:failed_dependencies])
          {
            name: entry[:name],
            code: "failed_dependency",
            message: "depends on failed modules: #{dependencies.join(', ')}",
            failed_dependencies: dependencies
          }
        end

        merged_failed_modules = merge_failed_modules(direct_failed_modules, pruned_failures)
        blackbox_modules = build_blackbox_modules(
          modules: kept_modules,
          failed_modules: merged_failed_modules,
          missing_policy: missing_policy
        )
        written_modules = (kept_modules + blackbox_modules).sort_by { |entry| entry[:name] }

        @writer.write(
          out: @out,
          project_slug: @project_slug,
          modules: written_modules,
          source_files: option_value(:source_files),
          source_roots: option_value(:source_roots)
        )

        checks = run_checks(kept_modules: kept_modules, detected_tops: detected_tops)
        prune_stale_report_artifacts(checks: checks)
        status = merged_failed_modules.empty? && checks_all_passed?(checks) ? :success : :failure

        report = @report_builder.build(
          out: @out,
          options: options_with_tops(detected_tops),
          status: status,
          diagnostics: @diagnostics,
          converted_modules: kept_names,
          failed_modules: merged_failed_modules,
          checks: checks,
          blackboxes_generated: blackbox_modules.map { |entry| entry[:name] },
          recovery: option_value(:recovery),
          hints: option_value(:hints)
        )
        report_path = @report_builder.write(report, out: @out)

        result_payload = {
          out_dir: @out,
          report_path: report_path,
          report: report,
          diagnostics: @diagnostics,
          converted_modules: kept_names,
          failed_modules: merged_failed_modules
        }

        if status == :success
          @result_class.success(**result_payload)
        else
          @result_class.failure(**result_payload)
        end
      end

      private

      def run_checks(kept_modules:, detected_tops:)
        return [] unless checks_enabled?

        profile = check_profile
        if profile == "ao486_program_parity"
          run_program_parity_checks(kept_modules: kept_modules)
        elsif profile == "ao486_component_parity"
          run_component_parity_checks(kept_modules: kept_modules)
        else
          selected_tops = select_check_tops(
            detected_tops: detected_tops,
            converted_tops: kept_modules.map { |entry| value_for(entry, :name).to_s }
          )
          if %w[ao486_trace ao486_trace_ir].include?(profile)
            selected_tops.map { |top| run_trace_check_for_top(top: top, profile: profile) }
          else
            selected_tops.map { |top| run_check_for_top(top: top, kept_modules: kept_modules) }
          end
        end
      end

      def prune_stale_report_artifacts(checks:)
        report_root = File.join(@out, "reports")
        return [] unless Dir.exist?(report_root)

        managed_roots = %w[differential trace component_parity program_parity]
          .map { |entry| File.join(report_root, entry) }
        expected = expected_report_paths(checks: checks)
        removed = []

        managed_roots.each do |managed_root|
          next unless Dir.exist?(managed_root)

          Dir.glob(File.join(managed_root, "**", "*"), File::FNM_DOTMATCH).sort.reverse_each do |path|
            base = File.basename(path)
            next if base == "." || base == ".."

            if File.file?(path)
              expanded = File.expand_path(path)
              next if expected.include?(expanded)

              File.delete(expanded)
              removed << expanded
              next
            end

            begin
              Dir.rmdir(path) if File.directory?(path)
            rescue SystemCallError
              # keep non-empty directories
            end
          end
        end

        removed
      end

      def expected_report_paths(checks:)
        Array(checks).each_with_object(Set.new) do |entry, memo|
          report_path = value_for(entry, :report_path).to_s.strip
          next if report_path.empty?

          memo << File.expand_path(report_path)
        end
      end

      def run_component_parity_checks(kept_modules:)
        component_targets = component_check_targets(kept_modules: kept_modules)
        return [] if component_targets.empty?

        harness_results = invoke_component_parity_harness(components: component_targets)
        normalized = normalize_component_parity_results(
          requested_components: component_targets,
          harness_results: harness_results
        )

        normalized.map do |entry|
          component = value_for(entry, :component).to_s
          summary = normalize_component_summary(value_for(entry, :summary))
          mismatches = normalize_component_mismatches(value_for(entry, :mismatches))
          status = value_for(entry, :status).to_s
          reason = value_for(entry, :reason)
          message = value_for(entry, :message)

          report_path = @component_parity_report_writer.write(
            root_dir: File.join(@out, "reports", "component_parity"),
            component: component,
            summary: summary,
            mismatches: mismatches,
            profile: "ao486_component_parity"
          )

          check_entry = {
            top: component,
            component: component,
            profile: "ao486_component_parity",
            status: status.empty? ? "tool_failure" : status,
            summary: summary,
            mismatches: mismatches,
            report_path: report_path
          }
          check_entry[:reason] = reason unless reason.nil?
          check_entry[:message] = message unless message.nil?
          check_entry
        end
      rescue StandardError => e
        [{
          top: "component_parity",
          component: "component_parity",
          profile: "ao486_component_parity",
          status: "tool_failure",
          reason: "harness_error",
          message: e.message,
          summary: {
            cycles_compared: 0,
            signals_compared: 0,
            pass_count: 0,
            fail_count: 1
          },
          mismatches: []
        }]
      end

      def run_program_parity_checks(kept_modules:)
        top = program_check_top(kept_modules: kept_modules)
        return [] if top.nil?

        harness_result = invoke_program_parity_harness(top: top)
        summary = normalize_program_summary(value_for(harness_result, :summary))
        mismatches = normalize_program_mismatches(value_for(harness_result, :mismatches))
        traces = normalize_program_traces(value_for(harness_result, :traces))
        status = value_for(harness_result, :status).to_s
        reason = value_for(harness_result, :reason)
        message = value_for(harness_result, :message)

        report_path = @program_parity_report_writer.write(
          root_dir: File.join(@out, "reports", "program_parity"),
          top: top,
          summary: summary,
          mismatches: mismatches,
          traces: traces,
          profile: "ao486_program_parity"
        )

        check_entry = {
          top: top,
          profile: "ao486_program_parity",
          status: status.empty? ? "tool_failure" : status,
          summary: summary,
          mismatches: mismatches,
          report_path: report_path
        }
        check_entry[:reason] = reason unless reason.nil?
        check_entry[:message] = message unless message.nil?
        [check_entry]
      rescue StandardError => e
        [{
          top: "ao486",
          profile: "ao486_program_parity",
          status: "tool_failure",
          reason: "harness_error",
          message: e.message,
          summary: {
            cycles_requested: 0,
            pc_events_compared: 0,
            instruction_events_compared: 0,
            write_events_compared: 0,
            memory_words_compared: 0,
            pass_count: 0,
            fail_count: 1,
            first_mismatch: nil
          },
          mismatches: []
        }]
      end

      def invoke_component_parity_harness(components:)
        kwargs = {
          out: @out.to_s,
          components: components,
          cycles: option_value(:vectors) || option_value(:trace_cycles) || 16,
          seed: option_value(:seed) || 1,
          source_root: option_value(:trace_reference_root),
          cwd: Dir.pwd
        }

        if @ao486_component_parity_harness.respond_to?(:run)
          @ao486_component_parity_harness.run(**kwargs)
        elsif @ao486_component_parity_harness.respond_to?(:call)
          @ao486_component_parity_harness.call(**kwargs)
        else
          raise ArgumentError,
                "ao486 component parity harness #{@ao486_component_parity_harness.class} does not respond to #run or #call"
        end
      end

        def invoke_program_parity_harness(top:)
          kwargs = {
            out: @out.to_s,
            top: top.to_s,
            cycles: option_value(:trace_cycles) || option_value(:vectors) || 256,
            source_root: option_value(:trace_reference_root) || Array(option_value(:src)).first,
            program_binary: option_value(:program_binary),
            program_binary_data_addresses: option_value(:program_binary_data_addresses),
            program_base_address: option_value(:program_base_address) || Checks::Ao486ProgramParityHarness::PROGRAM_BASE_ADDRESS,
            verilog_tool: option_value(:verilog_tool) || "iverilog",
            data_check_addresses: option_value(:data_check_addresses),
            cwd: Dir.pwd
          }

        if @ao486_program_parity_harness.respond_to?(:run)
          @ao486_program_parity_harness.run(**kwargs)
        elsif @ao486_program_parity_harness.respond_to?(:call)
          @ao486_program_parity_harness.call(**kwargs)
        else
          raise ArgumentError,
                "ao486 program parity harness #{@ao486_program_parity_harness.class} does not respond to #run or #call"
        end
      end

      def program_check_top(kept_modules:)
        available = Array(kept_modules)
          .map { |entry| value_for(entry, :name).to_s }
          .reject(&:empty?)
          .uniq
        return nil unless available.include?("ao486")

        selected = component_check_targets(kept_modules: kept_modules)
        return "ao486" if selected.empty?

        selected.include?("ao486") ? "ao486" : nil
      end

      def component_check_targets(kept_modules:)
        available = Array(kept_modules)
          .map { |entry| value_for(entry, :name).to_s }
          .reject(&:empty?)
          .sort

        scope = option_value(:check_scope)
        return available if scope.nil?

        selected =
          if scope.is_a?(Array)
            scope.map(&:to_s)
          else
            token = scope.to_s.strip
            if token.empty? || token == "all"
              available
            else
              token.split(",").map(&:strip)
            end
          end

        requested = selected.reject(&:empty?).uniq
        return available if requested.empty?

        requested.select { |name| available.include?(name) }
      end

      def normalize_component_parity_results(requested_components:, harness_results:)
        by_component = {}
        Array(harness_results).each do |entry|
          hash = normalize_hash(entry)
          component = value_for(hash, :component).to_s
          next if component.empty? || by_component.key?(component)

          by_component[component] = hash
        end

        requested_components.map do |component|
          by_component.fetch(component) do
            {
              component: component,
              status: "tool_failure",
              reason: "missing_component_result",
              message: "harness did not return a result for component #{component}",
              summary: {
                cycles_compared: 0,
                signals_compared: 0,
                pass_count: 0,
                fail_count: 1
              },
              mismatches: []
            }
          end
        end
      end

      def normalize_component_summary(summary)
        hash = normalize_hash(summary)
        {
          cycles_compared: integer_or_zero(value_for(hash, :cycles_compared)),
          signals_compared: integer_or_zero(value_for(hash, :signals_compared)),
          pass_count: integer_or_zero(value_for(hash, :pass_count)),
          fail_count: integer_or_zero(value_for(hash, :fail_count))
        }
      end

      def normalize_component_mismatches(mismatches)
        Array(mismatches).map do |entry|
          hash = normalize_hash(entry)
          {
            cycle: value_for(hash, :cycle),
            signal: value_for(hash, :signal).to_s,
            original: value_for(hash, :original),
            generated_verilog: value_for(hash, :generated_verilog),
            generated_ir: value_for(hash, :generated_ir)
          }
        end
      end

      def normalize_program_summary(summary)
        hash = normalize_hash(summary)
        {
          cycles_requested: integer_or_zero(value_for(hash, :cycles_requested)),
          pc_events_compared: integer_or_zero(value_for(hash, :pc_events_compared)),
          instruction_events_compared: integer_or_zero(value_for(hash, :instruction_events_compared)),
          write_events_compared: integer_or_zero(value_for(hash, :write_events_compared)),
          memory_words_compared: integer_or_zero(value_for(hash, :memory_words_compared)),
          pass_count: integer_or_zero(value_for(hash, :pass_count)),
          fail_count: integer_or_zero(value_for(hash, :fail_count)),
          first_mismatch: value_for(hash, :first_mismatch)
        }
      end

      def normalize_program_mismatches(mismatches)
        Array(mismatches).map do |entry|
          hash = normalize_hash(entry)
          {
            kind: value_for(hash, :kind).to_s,
            index: integer_or_zero(value_for(hash, :index)),
            address: value_for(hash, :address),
            reference: value_for(hash, :reference),
            generated_verilog: value_for(hash, :generated_verilog),
            generated_ir: value_for(hash, :generated_ir)
          }
        end
      end

      def normalize_program_traces(traces)
        hash = normalize_hash(traces)
        %i[reference generated_verilog generated_ir].each_with_object({}) do |name, memo|
          source = normalize_hash(value_for(hash, name))
          memo[name] = {
            pc_sequence: Array(value_for(source, :pc_sequence)),
            instruction_sequence: Array(value_for(source, :instruction_sequence)),
            memory_writes: Array(value_for(source, :memory_writes)),
            memory_contents: normalize_hash(value_for(source, :memory_contents))
          }
        end
      end

      def integer_or_zero(value)
        Integer(value)
      rescue ArgumentError, TypeError
        0
      end

      def run_check_for_top(top:, kept_modules:)
        module_entry = kept_modules.find { |entry| entry[:name] == top }
        return skipped_check(top: top, reason: "top_not_converted") unless module_entry

        source_files = Array(option_value(:source_files)).map(&:to_s).reject(&:empty?)
        return skipped_check(top: top, reason: "no_source_files") if source_files.empty?

        check_root = File.join(@out, "reports", "differential")
        check_work_dir = File.join(@out, "tmp", "checks", top)
        commands = build_backend_commands(top: top, source_files: source_files)
        return skipped_check(top: top, reason: "no_backend_command") if commands[:icarus_command].nil? && commands[:verilator_command].nil?

        runner_result = @check_runner.call(
          work_dir: check_work_dir,
          icarus_command: commands[:icarus_command],
          verilator_command: commands[:verilator_command],
          env: normalize_env(option_value(:check_env))
        )

        if runner_result[:status].to_sym != :ok
          summary = {
            cycles_compared: 0,
            signals_compared: 0,
            pass_count: 0,
            fail_count: 1
          }
          report_path = @check_report_writer.write(root_dir: check_root, top: top, summary: summary, mismatches: [])
          return {
            top: top,
            status: "tool_failure",
            backend: runner_result[:selected_backend].to_s,
            reason: runner_result[:status].to_s,
            summary: summary,
            mismatches: [],
            report_path: report_path,
            command: runner_result[:selected_command],
            attempts: runner_result[:attempts]
          }
        end

        vectors = @stimulus_generator.generate(
          top_signature: module_entry,
          vectors: option_value(:vectors) || 16,
          seed: option_value(:seed) || 1
        )

        expected = waveform_for(kind: :expected_waveforms, top: top) || vectors_to_waveform(vectors)
        actual = waveform_for(kind: :actual_waveforms, top: top) || expected
        comparison = @comparator.compare(expected: expected, actual: actual)
        report_path = @check_report_writer.write(
          root_dir: check_root,
          top: top,
          summary: comparison[:summary],
          mismatches: comparison[:mismatches]
        )

        {
          top: top,
          status: comparison[:passed] ? "pass" : "fail",
          backend: runner_result[:selected_backend].to_s,
          summary: comparison[:summary],
          mismatches: comparison[:mismatches],
          report_path: report_path,
          command: runner_result[:selected_command],
          attempts: runner_result[:attempts]
        }
      end

      def build_backend_commands(top:, source_files:)
        backend = option_value(:check_backend).to_s.downcase

        icarus_command = [
          "iverilog",
          "-g2012",
          "-s",
          top,
          "-o",
          "#{top}.simv",
          *source_files
        ]
        verilator_command = [
          "verilator",
          "--binary",
          "--top-module",
          top,
          *source_files
        ]

        case backend
        when "iverilog", "icarus"
          { icarus_command: icarus_command, verilator_command: nil }
        when "verilator"
          { icarus_command: nil, verilator_command: verilator_command }
        else
          { icarus_command: icarus_command, verilator_command: verilator_command }
        end
      end

      def waveform_for(kind:, top:)
        waveforms = option_value(kind)
        return nil unless waveforms.is_a?(Hash)

        waveforms[top] || waveforms[top.to_sym]
      end

      def vectors_to_waveform(vectors)
        Array(vectors).each_with_object({}) do |vector, memo|
          hash = vector.is_a?(Hash) ? vector : {}
          cycle = value_for(hash, :cycle)
          inputs = value_for(hash, :inputs)
          next unless cycle.is_a?(Numeric) && inputs.is_a?(Hash)

          memo[cycle] = inputs
        end
      end

      def normalize_env(env)
        return {} unless env.is_a?(Hash)

        env.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value.to_s
        end
      end

      def skipped_check(top:, reason:)
        {
          top: top,
          status: "skipped",
          reason: reason,
          summary: {
            cycles_compared: 0,
            signals_compared: 0,
            pass_count: 0,
            fail_count: 0
          },
          mismatches: []
        }
      end

      def run_trace_check_for_top(top:, profile: check_profile)
        expected_input = trace_input_for(kind: :expected_trace_events, top: top)
        actual_input = trace_input_for(kind: :actual_trace_events, top: top)
        expected_events = extract_trace_events(input: expected_input, top: top)
        actual_events = extract_trace_events(input: actual_input, top: top)
        return skipped_trace_check(top: top, reason: "no_trace_events", profile: profile) if expected_events.nil? && actual_events.nil?

        comparison = @trace_comparator.compare(
          expected: expected_events || [],
          actual: actual_events || [],
          keys: option_value(:trace_keys)
        )
        report_path = @trace_report_writer.write(
          root_dir: File.join(@out, "reports", "trace"),
          top: top,
          summary: comparison[:summary],
          mismatches: comparison[:mismatches],
          profile: profile
        )

        {
          top: top,
          profile: profile,
          status: comparison[:passed] ? "pass" : "fail",
          trace_sources: trace_sources(expected_input: expected_input, actual_input: actual_input),
          summary: comparison[:summary],
          mismatches: comparison[:mismatches],
          report_path: report_path
        }
      rescue StandardError => e
        summary = {
          events_compared: 0,
          pass_count: 0,
          fail_count: 1,
          first_mismatch: nil
        }
        report_path = @trace_report_writer.write(
          root_dir: File.join(@out, "reports", "trace"),
          top: top,
          summary: summary,
          mismatches: [],
          profile: profile
        )

        {
          top: top,
          profile: profile,
          status: "tool_failure",
          reason: "trace_input_error",
          message: e.message,
          trace_sources: trace_sources(expected_input: expected_input, actual_input: actual_input),
          summary: summary,
          mismatches: [],
          report_path: report_path
        }
      end

      def skipped_trace_check(top:, reason:, profile:)
        {
          top: top,
          profile: profile,
          status: "skipped",
          reason: reason,
          summary: {
            events_compared: 0,
            pass_count: 0,
            fail_count: 0,
            first_mismatch: nil
          },
          mismatches: []
        }
      end

      def trace_input_for(kind:, top:)
        cache_key = [kind.to_sym, top.to_s]
        return @trace_input_cache[cache_key] if @trace_input_cache.key?(cache_key)

        input = build_trace_input(kind: kind, top: top)
        @trace_input_cache[cache_key] = input
      end

      def build_trace_input(kind:, top:)
        inline_events = option_value(kind)
        if !inline_events.nil?
          return {
            source: {
              type: "inline",
              detail: kind.to_s
            },
            events: inline_events
          }
        end

        from_path = trace_events_from_path(kind: kind)
        return from_path unless from_path.nil?

        from_command = trace_events_from_command(kind: kind, top: top)
        return from_command unless from_command.nil?

        trace_events_from_ao486_harness(kind: kind, top: top)
      end

      def extract_trace_events(input:, top:)
        return nil if input.nil?

        events = value_for(input, :events)
        if events.is_a?(Hash)
          return events[top] || events[top.to_sym]
        end

        events
      end

      def trace_events_from_path(kind:)
        path_key =
          case kind.to_sym
          when :expected_trace_events
            :expected_trace_path
          when :actual_trace_events
            :actual_trace_path
          else
            return nil
          end

        path = option_value(path_key).to_s.strip
        return nil if path.empty?

        expanded_path = File.expand_path(path)
        {
          source: {
            type: "file",
            detail: expanded_path
          },
          events: JSON.parse(File.read(expanded_path), max_nesting: false)
        }
      rescue StandardError => e
        raise ArgumentError, "failed to load #{path_key} from #{path.inspect}: #{e.message}"
      end

      def trace_events_from_command(kind:, top:)
        command_key =
          case kind.to_sym
          when :expected_trace_events
            :expected_trace_command
          when :actual_trace_events
            :actual_trace_command
          else
            return nil
          end

        command_value = option_value(command_key)
        trace_context = {
          top: top.to_s,
          out: @out.to_s,
          project_slug: @project_slug.to_s,
          profile: check_profile
        }
        argv =
          if command_value.is_a?(Array)
            command_value
              .map { |part| interpolate_trace_template(part.to_s, context: trace_context) }
              .reject(&:empty?)
          else
            text = interpolate_trace_template(command_value.to_s, context: trace_context).strip
            return nil if text.empty?

            Shellwords.split(text)
          end
        return nil if argv.empty?

        env = normalize_env(option_value(:trace_env)).merge(
          "RHDL_IMPORT_TOP" => top.to_s,
          "RHDL_IMPORT_OUT" => @out.to_s,
          "RHDL_IMPORT_PROJECT_SLUG" => @project_slug.to_s,
          "RHDL_IMPORT_CHECK_PROFILE" => check_profile,
          "RHDL_IMPORT_TRACE_KIND" => kind.to_s
        )
        capture_options = {}
        trace_cwd = option_value(:trace_command_cwd).to_s.strip
        capture_options[:chdir] = File.expand_path(trace_cwd) unless trace_cwd.empty?
        stdout, stderr, status = Open3.capture3(env, *argv, **capture_options)
        unless status.success?
          raise ArgumentError,
                "#{command_key} exited with #{status.exitstatus}: #{stderr.to_s.strip}"
        end

        {
          source: {
            type: "command",
            detail: command_value.is_a?(Array) ? argv : argv.join(" ")
          },
          events: JSON.parse(stdout, max_nesting: false)
        }
      rescue StandardError => e
        raise ArgumentError, "failed to load #{command_key} via command #{command_value.inspect}: #{e.message}"
      end

      def trace_events_from_ao486_harness(kind:, top:)
        return nil unless %w[ao486_trace ao486_trace_ir].include?(check_profile)
        return nil unless top.to_s == "ao486"

        mode =
          case kind.to_sym
          when :expected_trace_events
            "reference"
          when :actual_trace_events
            check_profile == "ao486_trace_ir" ? "converted_ir" : "converted"
          else
            nil
          end
        return nil if mode.nil?

        unless @ao486_trace_harness.respond_to?(:capture) || @ao486_trace_harness.respond_to?(:call)
          raise ArgumentError,
                "ao486 trace harness #{@ao486_trace_harness.class} does not respond to #capture or #call"
        end

        cycles_value = option_value(:trace_cycles)
        cycles = cycles_value.nil? ? 1024 : Integer(cycles_value)
        source_root = option_value(:trace_reference_root)
        harness_kwargs = {
          mode: mode,
          top: top.to_s,
          out: @out.to_s,
          cycles: cycles,
          source_root: source_root,
          converted_export_mode: option_value(:trace_converted_export_mode),
          cwd: Dir.pwd
        }
        events =
          if @ao486_trace_harness.respond_to?(:capture)
            @ao486_trace_harness.capture(**harness_kwargs)
          else
            @ao486_trace_harness.call(**harness_kwargs)
          end

        {
          source: {
            type: "ao486_harness",
            detail: "mode=#{mode} cycles=#{cycles}"
          },
          events: events
        }
      rescue StandardError => e
        raise ArgumentError, "failed to load #{kind} via ao486 harness: #{e.message}"
      end

      def trace_sources(expected_input:, actual_input:)
        {
          expected: value_for(expected_input, :source),
          actual: value_for(actual_input, :source)
        }
      end

      def interpolate_trace_template(value, context:)
        text = value.to_s
        return text unless text.include?("%{")

        text % context
      rescue StandardError
        text
      end

      def select_check_tops(detected_tops:, converted_tops:)
        scope = option_value(:check_scope)
        detected = Array(detected_tops).map(&:to_s)
        converted_set = normalize_top_list(converted_tops).to_set
        selected =
          case scope
          when nil
            detected
          when Array
            scope.map(&:to_s)
          else
            token = scope.to_s.strip
            if token.empty? || token == "all"
              detected
            else
              token.split(",").map(&:strip)
            end
          end

        if scope.nil? || scope.to_s.strip.empty? || scope.to_s.strip == "all"
          selected = selected.select { |top| converted_set.include?(top) }
        end

        selected.reject(&:empty?).uniq
      end

      def normalize_top_list(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def checks_enabled?
        return false if truthy?(option_value(:no_check))

        check_value = option_value(:check)
        return true if check_value.nil?

        truthy?(check_value)
      end

      def check_profile
        value = option_value(:check_profile).to_s.strip.downcase
        value.empty? ? "default" : value
      end

      def checks_all_passed?(checks)
        Array(checks).none? do |entry|
          status = value_for(entry, :status).to_s
          !%w[pass skipped].include?(status)
        end
      end

      def truthy?(value)
        case value
        when true then true
        when false, nil then false
        when Numeric then !value.zero?
        else
          %w[1 true yes on].include?(value.to_s.strip.downcase)
        end
      end

      def modules_for_top_detection
        all_modules = {}

        @translated_modules.each do |entry|
          all_modules[entry[:name]] = {
            name: entry[:name],
            dependencies: entry[:dependencies]
          }
        end

        @failed_modules.each do |entry|
          all_modules[entry[:name]] ||= {
            name: entry[:name],
            dependencies: []
          }
        end

        all_modules.values
      end

      def normalize_translated_modules(modules)
        Array(modules).map do |entry|
          hash = entry.is_a?(Hash) ? entry : {}
          name = value_for(hash, :name).to_s
          next if name.empty?

          {
            name: name,
            source: value_for(hash, :source) || value_for(hash, :ruby_source),
            source_path: extract_source_path(hash),
            dependencies: extract_dependencies(hash),
            ports: normalize_ports(value_for(hash, :ports)),
            instances: normalize_instances(value_for(hash, :instances))
          }
        end.compact.sort_by { |entry| entry[:name] }
      end

      def normalize_failed_modules(failed_modules)
        Array(failed_modules).map do |entry|
          if entry.is_a?(Hash)
            normalized = entry.each_with_object({}) { |(key, value), memo| memo[key.to_sym] = value }
            normalized[:name] = value_for(entry, :name).to_s
            normalized[:code] ||= "failed"
            normalized[:message] ||= "module conversion failed"
            next if normalized[:name].empty?

            normalized
          else
            name = entry.to_s
            next if name.empty?

            {
              name: name,
              code: "failed",
              message: "module conversion failed"
            }
          end
        end.compact
      end

      def merge_failed_modules(direct_failures, pruned_failures)
        merged = []
        seen = Set.new

        (Array(direct_failures) + Array(pruned_failures)).each do |entry|
          name = value_for(entry, :name).to_s
          next if name.empty? || seen.include?(name)

          seen << name
          merged << entry
        end

        merged
      end

      def extract_dependencies(entry)
        explicit_dependencies = value_for(entry, :dependencies)
        if !explicit_dependencies.nil?
          return Array(explicit_dependencies).map(&:to_s).reject(&:empty?).uniq
        end

        instances = Array(value_for(entry, :instances))
        dependencies = instances.map do |instance|
          instance_hash = instance.is_a?(Hash) ? instance : {}
          value_for(instance_hash, :module_name) || value_for(instance_hash, :module)
        end

        dependencies.map(&:to_s).reject(&:empty?).uniq
      end

      def extract_source_path(entry)
        explicit = value_for(entry, :source_path).to_s.strip
        return explicit unless explicit.empty?

        span_hash = normalize_hash(value_for(entry, :span))
        source_path = value_for(span_hash, :source_path) || value_for(span_hash, :path) || value_for(span_hash, :file)
        source_path.to_s.strip
      end

      def normalize_ports(ports)
        Array(ports).filter_map do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s
          next if name.empty?

          {
            name: name,
            direction: value_for(hash, :direction).to_s,
            width: value_for(hash, :width)
          }
        end
      end

      def normalize_instances(instances)
        Array(instances).filter_map do |entry|
          hash = normalize_hash(entry)
          module_name = value_for(hash, :module_name) || value_for(hash, :module)
          module_name = module_name.to_s
          next if module_name.empty?

          {
            name: value_for(hash, :name).to_s,
            module_name: module_name,
            parameter_overrides: normalize_parameter_overrides(value_for(hash, :parameter_overrides)),
            connections: normalize_connections(value_for(hash, :connections))
          }
        end
      end

      def normalize_parameter_overrides(overrides)
        Array(overrides).filter_map do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s
          next if name.empty?

          {
            name: name,
            value: value_for(hash, :value)
          }
        end
      end

      def normalize_connections(connections)
        Array(connections).filter_map do |entry|
          hash = normalize_hash(entry)
          port = value_for(hash, :port).to_s
          next if port.empty?

          {
            port: port,
            signal: value_for(hash, :signal)
          }
        end
      end

      def missing_modules_policy
        normalized = option_value(:missing_modules).to_s.strip.downcase
        normalized.empty? ? "fail" : normalized
      end

      def build_missing_module_failures(signatures)
        Array(signatures).map do |signature|
          name = value_for(signature, :name).to_s
          next if name.empty?

          referenced_by = Array(value_for(signature, :referenced_by)).map(&:to_s).reject(&:empty?).uniq.sort
          message =
            if referenced_by.empty?
              "unresolved dependency module #{name.inspect}"
            else
              "unresolved dependency module #{name.inspect}, referenced by: #{referenced_by.join(', ')}"
            end

          {
            name: name,
            code: "missing_module",
            message: message,
            referenced_by: referenced_by
          }
        end.compact.sort_by { |entry| entry[:name] }
      end

      def build_blackbox_modules(modules:, failed_modules:, missing_policy:)
        return [] unless missing_policy == "blackbox_stubs"

        signatures = infer_missing_module_signatures(modules: modules, failed_modules: failed_modules)
        return [] if signatures.empty?

        if @blackbox_stub_generator.respond_to?(:generate)
          @blackbox_stub_generator.generate(signatures: signatures)
        elsif @blackbox_stub_generator.respond_to?(:call)
          @blackbox_stub_generator.call(signatures: signatures)
        else
          raise ArgumentError, "blackbox stub generator #{@blackbox_stub_generator.class} does not respond to #generate or #call"
        end
      end

      def infer_missing_module_signatures(modules:, failed_modules:)
        module_names = Array(modules).map { |entry| value_for(entry, :name).to_s }.reject(&:empty?).to_set
        failed_names = Array(failed_modules).map { |entry| value_for(entry, :name).to_s }.reject(&:empty?).to_set
        signatures = {}

        Array(modules).each do |module_entry|
          owner_name = value_for(module_entry, :name).to_s
          next if owner_name.empty?

          Array(value_for(module_entry, :instances)).each do |instance|
            instance_hash = normalize_hash(instance)
            missing_name = (value_for(instance_hash, :module_name) || value_for(instance_hash, :module)).to_s
            next if missing_name.empty?
            next if module_names.include?(missing_name)
            next if failed_names.include?(missing_name)

            signature = signatures[missing_name] ||= {
              name: missing_name,
              ports: Set.new,
              parameters: Set.new,
              referenced_by: Set.new
            }
            signature[:referenced_by] << owner_name

            Array(value_for(instance_hash, :connections)).each do |connection|
              port_name = value_for(connection, :port).to_s
              signature[:ports] << port_name unless port_name.empty?
            end

            Array(value_for(instance_hash, :parameter_overrides)).each do |override|
              parameter_name = value_for(override, :name).to_s
              signature[:parameters] << parameter_name unless parameter_name.empty?
            end
          end
        end

        normalized_signatures = signatures.values.map do |signature|
          {
            name: signature[:name],
            ports: signature[:ports].to_a.sort,
            parameters: signature[:parameters].to_a.sort,
            referenced_by: signature[:referenced_by].to_a.sort
          }
        end.sort_by { |entry| entry[:name] }

        MissingModuleSignatureExtractor.augment(
          signatures: normalized_signatures,
          source_files: option_value(:source_files)
        )
      end

      def detect_custom_verilog_export_failures(modules)
        Array(modules).filter_map do |entry|
          name = value_for(entry, :name).to_s
          source = (value_for(entry, :source) || value_for(entry, :ruby_source)).to_s
          next if name.empty? || source.empty?

          methods = source.scan(/^\s*def\s+self\.(to_verilog(?:_generated)?)\b/).flatten.uniq.sort
          next if methods.empty?

          {
            name: name,
            code: "forbidden_custom_verilog_export",
            message: "module defines forbidden custom export method(s): #{methods.join(', ')}"
          }
        end.sort_by { |entry| entry[:name] }
      end

      def normalize_hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def options_with_tops(tops)
        options = @options.dup
        options[:top] = Array(tops)
        options
      end

      def option_value(key)
        return @options[key] if @options.key?(key)

        string_key = key.to_s
        return @options[string_key] if @options.key?(string_key)

        symbol_key = key.to_sym
        return @options[symbol_key] if @options.key?(symbol_key)

        nil
      end

      def value_for(hash, key)
        return nil unless hash.is_a?(Hash)

        return hash[key] if hash.key?(key)

        string_key = key.to_s
        return hash[string_key] if hash.key?(string_key)

        symbol_key = key.to_sym
        return hash[symbol_key] if hash.key?(symbol_key)

        nil
      end
    end
  end
end
