# frozen_string_literal: true

require "fileutils"
require "set"
require_relative "import/input_resolver"
require_relative "import/frontend/verilator_adapter"
require_relative "import/frontend/surelog_hint_adapter"
require_relative "import/frontend/normalizer"
require_relative "import/mapper"
require_relative "import/translator"
require_relative "import/pipeline"
require_relative "import/result"
require_relative "import/report"
require_relative "import/missing_module_signature_extractor"
require_relative "import/blackbox_stub_generator"

module RHDL
  module Import
    class << self
      RECOVERY_MODES = %w[off recoverable strict].freeze
      HINT_BACKENDS = %w[off surelog].freeze
      HINT_CONFLICT_POLICIES = %w[prefer_ast prefer_hint strict].freeze
      HINT_CONFIDENCE_RANK = {
        "low" => 0,
        "medium" => 1,
        "high" => 2
      }.freeze

      PIPELINE_OPTION_KEYS = %i[
        filelist
        src
        exclude
        incdir
        define
        dependency_resolution
        compile_unit_filter
        missing_modules
        recovery_mode
        hint_backend
        hint_min_confidence
        hint_conflict_policy
        check_profile
        top
        check
        no_check
        check_scope
        check_backend
        vectors
        seed
        check_env
        expected_waveforms
        actual_waveforms
        expected_trace_events
        actual_trace_events
        expected_trace_path
        actual_trace_path
        expected_trace_command
        actual_trace_command
        trace_command_cwd
        trace_keys
        trace_env
        trace_cycles
        trace_reference_root
        trace_converted_export_mode
        program_binary
        program_binary_data_addresses
        program_base_address
        data_check_addresses
        verilog_tool
        report
        keep_temp
      ].freeze

      def project(out:, **options)
        out_dir = File.expand_path(out.to_s)
        runtime = build_runtime(options)
        resolved_input = nil
        diagnostics = []
        hint_summary = default_hint_summary(backend: normalize_hint_backend(value_for(options, :hint_backend)))

        resolved_input = resolve_input_contract(
          options: options,
          input_resolver: runtime[:input_resolver]
        )
        diagnostics.concat(Array(options[:diagnostics]))

        mapped_modules, mapped_diagnostics, hint_summary = resolve_mapped_modules(
          options: options,
          resolved_input: resolved_input,
          out_dir: out_dir,
          frontend_adapter: runtime[:frontend_adapter],
          frontend_normalizer: runtime[:frontend_normalizer],
          mapper: runtime[:mapper],
          surelog_hint_adapter: runtime[:surelog_hint_adapter]
        )
        diagnostics.concat(Array(mapped_diagnostics))

        recovery_mode = normalize_recovery_mode(value_for(options, :recovery_mode))
        recovery = build_recovery_report(
          mapped_modules: mapped_modules,
          diagnostics: diagnostics,
          hints: hint_summary,
          recovery_mode: recovery_mode
        )
        strict_failure = strict_recovery_failure(recovery: recovery, recovery_mode: recovery_mode)
        diagnostics.concat(diagnostics_for_failures([strict_failure])) if strict_failure

        empty_import_failure = infer_empty_import_failure(
          resolved_input: resolved_input,
          mapped_modules: mapped_modules
        )
        diagnostics.concat(diagnostics_for_failures([empty_import_failure])) if empty_import_failure

        failed_modules = merge_failures(
          normalize_failed_modules(options[:failed_modules]),
          infer_failed_modules_from_diagnostics(diagnostics),
          empty_import_failure,
          strict_failure
        )

        translated_modules, translation_failures = resolve_translated_modules(
          options: options,
          mapped_modules: mapped_modules,
          failed_modules: failed_modules,
          translator: runtime[:translator]
        )
        failed_modules = merge_failures(failed_modules, translation_failures)
        diagnostics.concat(diagnostics_for_failures(translation_failures))

        pipeline_options = build_pipeline_options(options: options, resolved_input: resolved_input)
        pipeline_options[:recovery] = recovery
        pipeline_options[:hints] = hint_summary
        project_slug = resolve_project_slug(options[:project_slug], out_dir)
        result = invoke_pipeline(
          pipeline: runtime[:pipeline],
          out_dir: out_dir,
          project_slug: project_slug,
          pipeline_options: pipeline_options,
          translated_modules: translated_modules,
          failed_modules: failed_modules,
          diagnostics: diagnostics,
          options: options,
          runtime: runtime
        )

        maybe_copy_report(
          result: result,
          report_target: options[:report],
          result_class: runtime[:result_class],
          cwd: options[:cwd]
        )
      rescue StandardError => e
        raise if truthy?(options[:raise_errors])

        failure_result = build_failure_result(
          out_dir: out_dir,
          options: build_pipeline_options(options: options, resolved_input: resolved_input || {}),
          runtime: runtime,
          diagnostics: diagnostics,
          error: e
        )

        maybe_copy_report(
          result: failure_result,
          report_target: options[:report],
          result_class: runtime[:result_class],
          cwd: options[:cwd]
        )
      ensure
        cleanup_temp_artifacts(out_dir: out_dir, keep_temp: options[:keep_temp])
      end

      private

      def build_runtime(options)
        {
          input_resolver: options[:input_resolver] || InputResolver,
          frontend_adapter: options[:frontend_adapter] || Frontend::VerilatorAdapter.new,
          surelog_hint_adapter: options[:surelog_hint_adapter] || Frontend::SurelogHintAdapter.new,
          frontend_normalizer: options[:frontend_normalizer] || Frontend::Normalizer,
          mapper: options[:mapper] || Mapper,
          translator: options[:translator] || Translator,
          pipeline: options[:pipeline] || Pipeline,
          report_builder: options[:report_builder] || Report,
          result_class: options[:result_class] || Result
        }
      end

      def resolve_input_contract(options:, input_resolver:)
        return value_for(options, :resolved_input) if option_provided?(options, :resolved_input)

        cwd = value_for(options, :cwd) || Dir.pwd
        src_roots = normalize_string_array(value_for(options, :src))
        src_roots = augment_ao486_source_roots(options: options, src: src_roots, cwd: cwd)

        invoke_component(
          input_resolver,
          method_name: :resolve,
          kwargs: {
            filelist: value_for(options, :filelist),
            src: src_roots,
            exclude: normalize_string_array(value_for(options, :exclude)),
            incdir: normalize_string_array(value_for(options, :incdir)),
            define: normalize_string_array(value_for(options, :define)),
            dependency_resolution: value_for(options, :dependency_resolution),
            compile_unit_filter: value_for(options, :compile_unit_filter),
            cwd: cwd
          }
        )
      end

      def augment_ao486_source_roots(options:, src:, cwd:)
        roots = normalize_string_array(src)
        profile = value_for(options, :check_profile).to_s.strip
        return roots unless profile == "ao486_program_parity"

        tops = normalize_string_array(value_for(options, :top))
        return roots unless tops.empty? || tops.include?("ao486")

        expanded = roots.dup
        roots.each do |entry|
          resolved = File.expand_path(entry, cwd)
          next unless File.basename(resolved) == "ao486"

          rtl_root = File.dirname(resolved)
          %w[common cache].each do |sibling|
            candidate = File.join(rtl_root, sibling)
            next unless Dir.exist?(candidate)

            expanded << candidate
          end
        end

        normalize_string_array(expanded)
      end

      def resolve_mapped_modules(options:, resolved_input:, out_dir:, frontend_adapter:, frontend_normalizer:, mapper:, surelog_hint_adapter:)
        hint_backend = normalize_hint_backend(value_for(options, :hint_backend))

        if option_provided?(options, :mapped_modules)
          mapped_modules = normalize_mapped_modules(value_for(options, :mapped_modules))
          return [mapped_modules, [], default_hint_summary(backend: hint_backend)]
        end

        return [[], [], default_hint_summary(backend: hint_backend)] unless frontend_execution_requested?(options: options, resolved_input: resolved_input)

        program = if option_provided?(options, :mapped_program)
          value_for(options, :mapped_program)
        else
          normalized_payload = if option_provided?(options, :normalized_payload)
            value_for(options, :normalized_payload)
          else
            raw_frontend_payload = resolve_raw_frontend_payload(
              options: options,
              resolved_input: resolved_input,
              out_dir: out_dir,
              frontend_adapter: frontend_adapter
            )
            normalize_payload(frontend_normalizer, raw_frontend_payload)
          end
          hinted_payload, hint_summary, hint_diagnostics = apply_hints(
            options: options,
            resolved_input: resolved_input,
            normalized_payload: normalized_payload,
            out_dir: out_dir,
            hint_backend: hint_backend,
            surelog_hint_adapter: surelog_hint_adapter
          )

          mapped_program = map_payload(mapper, hinted_payload)
          return [
            extract_program_modules(mapped_program),
            extract_program_diagnostics(mapped_program) + hint_diagnostics,
            hint_summary
          ]
        end

        [extract_program_modules(program), extract_program_diagnostics(program), default_hint_summary(backend: hint_backend)]
      end

      def frontend_execution_requested?(options:, resolved_input:)
        explicit = option_provided?(options, :execute_frontend)
        return truthy?(value_for(options, :execute_frontend)) if explicit

        return true if option_provided?(options, :mapped_program)
        return true if option_provided?(options, :normalized_payload)
        return true if option_provided?(options, :raw_frontend_payload)
        return true if option_provided?(options, :frontend_result)

        array_value(resolved_input, :source_files).any?
      end

      def resolve_raw_frontend_payload(options:, resolved_input:, out_dir:, frontend_adapter:)
        return value_for(options, :raw_frontend_payload) if option_provided?(options, :raw_frontend_payload)

        if option_provided?(options, :frontend_result)
          value_for(options, :frontend_result)
        else
          invoke_component(
            frontend_adapter,
            method_name: :call,
            kwargs: {
              resolved_input: build_frontend_input(options: options, resolved_input: resolved_input, out_dir: out_dir),
              work_dir: value_for(options, :frontend_work_dir) || File.join(out_dir, "tmp", "frontend"),
              env: normalize_env(value_for(options, :frontend_env))
            }
          )
        end
      end

      def build_frontend_input(options:, resolved_input:, out_dir:)
        frontend_input = value_for(resolved_input, :frontend_input)
        input_hash = normalize_hash(frontend_input)

        if input_hash.empty?
          input_hash = {
            source_files: array_value(resolved_input, :source_files),
            include_dirs: array_value(resolved_input, :include_dirs),
            defines: value_for(resolved_input, :defines)
          }
        end

        source_files = normalize_string_array(value_for(input_hash, :source_files))
        include_dirs = normalize_string_array(value_for(input_hash, :include_dirs))
        input_hash[:source_files] = source_files
        input_hash[:include_dirs] = include_dirs

        generated_stub = maybe_build_frontend_blackbox_stub(
          options: options,
          out_dir: out_dir,
          source_files: source_files
        )
        unless generated_stub.nil?
          input_hash[:source_files] = (source_files + [generated_stub]).uniq
        end

        top_modules = normalize_string_array(value_for(options, :top))
        input_hash[:top_modules] = top_modules unless top_modules.empty?
        input_hash[:missing_modules] = value_for(options, :missing_modules) if option_provided?(options, :missing_modules)
        input_hash
      end

      def maybe_build_frontend_blackbox_stub(options:, out_dir:, source_files:)
        return nil unless normalize_missing_modules_policy(value_for(options, :missing_modules)) == "blackbox_stubs"

        known_missing = %w[altdpram altsyncram]
        requested = known_missing.reject { |module_name| module_defined_in_sources?(module_name: module_name, source_files: source_files) }
        return nil if requested.empty?

        signatures = requested.map { |module_name| { name: module_name } }
        augmented = MissingModuleSignatureExtractor.augment(signatures: signatures, source_files: source_files)
        candidates = Array(augmented).filter_map do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s
          next if name.empty?

          ports = augment_frontend_stub_ports(
            module_name: name,
            ports: normalize_string_array(value_for(hash, :ports))
          )
          parameters = augment_frontend_stub_parameters(
            module_name: name,
            parameters: normalize_string_array(value_for(hash, :parameters)),
            ports: ports
          )
          next if parameters.empty? && ports.empty?

          { name: name, parameters: parameters, ports: ports }
        end
        return nil if candidates.empty?

        stub_source = emit_frontend_blackbox_stub_source(candidates)
        return nil if stub_source.to_s.strip.empty?

        stub_dir = File.join(out_dir, "tmp", "frontend")
        FileUtils.mkdir_p(stub_dir)
        stub_path = File.join(stub_dir, "frontend_blackbox_stubs.v")
        File.write(stub_path, stub_source)
        stub_path
      end

      def module_defined_in_sources?(module_name:, source_files:)
        pattern = /\bmodule\s+#{Regexp.escape(module_name)}\b/

        Array(source_files).any? do |path|
          next false unless File.file?(path)

          content = File.read(path)
          pattern.match?(content)
        rescue StandardError
          false
        end
      end

      def emit_frontend_blackbox_stub_source(signatures)
        lines = []
        Array(signatures).each do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s
          next if name.empty?
          module_key = name.downcase

          if module_key == "altdpram"
            lines << emit_frontend_altdpram_stub(name: name).strip
            lines << ""
            next
          end
          if module_key == "altsyncram"
            lines << emit_frontend_altsyncram_stub(name: name).strip
            lines << ""
            next
          end

          parameters = normalize_string_array(value_for(hash, :parameters))
          ports = normalize_string_array(value_for(hash, :ports))

          if parameters.empty?
            lines << "module #{name}("
          else
            lines << "module #{name} #("
            parameters.each_with_index do |parameter, index|
              suffix = index == parameters.length - 1 ? "" : ","
              lines << "  parameter #{parameter} = 1#{suffix}"
            end
            lines << ") ("
          end

          ports.each_with_index do |port, index|
            suffix = index == ports.length - 1 ? "" : ","
            lines << "  #{port}#{suffix}"
          end
          lines << ");"
          ports.each do |port|
            direction = frontend_stub_port_direction(module_name: name, port_name: port)
            width = frontend_stub_port_width(module_name: name, port_name: port)
            width_decl = width.nil? ? "" : "[#{width}-1:0] "
            lines << "  #{direction} #{width_decl}#{port};"
          end
          ports.each do |port|
            next unless frontend_stub_port_direction(module_name: name, port_name: port) == "output"

            lines << "  assign #{port} = '0;"
          end
          lines << "endmodule"
          lines << ""
        end
        lines.join("\n")
      end

      def emit_frontend_altdpram_stub(name:)
        <<~VERILOG
          /* verilator lint_off WIDTHEXPAND */
          /* verilator lint_off WIDTHTRUNC */
          /* verilator lint_off SELRANGE */
          /* verilator lint_off UNUSEDPARAM */
          /* verilator lint_off UNUSEDSIGNAL */
          module #{name} #(
            parameter indata_aclr = "OFF",
            parameter indata_reg = "INCLOCK",
            parameter intended_device_family = "Cyclone V",
            parameter lpm_type = "altdpram",
            parameter outdata_aclr = "OFF",
            parameter outdata_reg = "UNREGISTERED",
            parameter ram_block_type = "MLAB",
            parameter rdaddress_aclr = "OFF",
            parameter rdaddress_reg = "UNREGISTERED",
            parameter rdcontrol_aclr = "OFF",
            parameter rdcontrol_reg = "UNREGISTERED",
            parameter read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
            parameter width = 8,
            parameter widthad = 4,
            parameter width_byteena = 1,
            parameter wraddress_aclr = "OFF",
            parameter wraddress_reg = "INCLOCK",
            parameter wrcontrol_aclr = "OFF",
            parameter wrcontrol_reg = "INCLOCK"
          ) (
            input aclr,
            input [width_byteena-1:0] byteena,
            input [width-1:0] data,
            input inclock,
            input inclocken,
            input outclock,
            input outclocken,
            output [width-1:0] q,
            input [widthad-1:0] rdaddress,
            input rdaddressstall,
            input rden,
            input sclr,
            input [widthad-1:0] wraddress,
            input wraddressstall,
            input wren
          );
            localparam integer SAFE_WIDTH = (width > 0) ? width : 1;
            localparam integer SAFE_WIDTHAD = (widthad > 0) ? widthad : 1;
            localparam integer SAFE_WIDTH_BYTEENA = (width_byteena > 0) ? width_byteena : 1;
            localparam integer SAFE_DEPTH = (1 << SAFE_WIDTHAD);
            localparam integer SAFE_BYTE_COUNT = (SAFE_WIDTH + 7) / 8;

            reg [SAFE_WIDTH-1:0] mem [0:SAFE_DEPTH-1];
            reg [SAFE_WIDTH-1:0] merged_word;
            integer init_i;
            integer byte_i;

            wire [SAFE_WIDTHAD-1:0] wr_addr = wraddress;
            wire [SAFE_WIDTHAD-1:0] rd_addr = rdaddress;
            wire inclocken_en = (inclocken === 1'b0) ? 1'b0 : 1'b1;
            wire wr_stall = (wraddressstall === 1'b1) ? 1'b1 : 1'b0;
            wire wren_en = (wren === 1'b1) ? 1'b1 : 1'b0;
            wire wr_fire = wren_en && !wr_stall && inclocken_en;

            initial begin
              for (init_i = 0; init_i < SAFE_DEPTH; init_i = init_i + 1) begin
                mem[init_i] = {SAFE_WIDTH{1'b0}};
              end
            end

            always @* begin
              merged_word = mem[wr_addr];
              if (SAFE_WIDTH_BYTEENA <= 1 || SAFE_BYTE_COUNT <= 1) begin
                merged_word = data;
              end else begin
                for (byte_i = 0; byte_i < SAFE_BYTE_COUNT; byte_i = byte_i + 1) begin
                  if (byte_i < SAFE_WIDTH_BYTEENA && byteena[byte_i]) begin
                    merged_word[(byte_i * 8) +: 8] = data[(byte_i * 8) +: 8];
                  end
                end
              end
            end

            always @(posedge inclock or posedge aclr or posedge sclr) begin
              if (aclr || sclr) begin
                // Preserve memory contents on clear; deterministic power-up is enough.
              end else if (wr_fire) begin
                mem[wr_addr] <= merged_word;
              end
            end

            assign q = mem[rd_addr];
          endmodule
          /* verilator lint_on UNUSEDSIGNAL */
          /* verilator lint_on UNUSEDPARAM */
          /* verilator lint_on SELRANGE */
          /* verilator lint_on WIDTHTRUNC */
          /* verilator lint_on WIDTHEXPAND */
        VERILOG
      end

      def emit_frontend_altsyncram_stub(name:)
        <<~VERILOG
          /* verilator lint_off WIDTHEXPAND */
          /* verilator lint_off WIDTHTRUNC */
          /* verilator lint_off SELRANGE */
          /* verilator lint_off UNUSEDPARAM */
          /* verilator lint_off UNUSEDSIGNAL */
          module #{name} #(
            parameter operation_mode = "DUAL_PORT",
            parameter ram_block_type = "AUTO",
            parameter intended_device_family = "Cyclone V",
            parameter lpm_type = "altsyncram",
            parameter width_a = 32,
            parameter widthad_a = 10,
            parameter numwords_a = 1024,
            parameter outdata_aclr_a = "NONE",
            parameter outdata_reg_a = "UNREGISTERED",
            parameter width_b = 32,
            parameter widthad_b = 10,
            parameter numwords_b = 1024,
            parameter outdata_aclr_b = "NONE",
            parameter outdata_reg_b = "UNREGISTERED",
            parameter width_byteena_a = 4,
            parameter width_byteena_b = 4,
            parameter read_during_write_mode_mixed_ports = "DONT_CARE",
            parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
            parameter read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
            parameter address_reg_b = "UNREGISTERED",
            parameter address_aclr_b = "NONE",
            parameter indata_reg_b = "CLOCK1",
            parameter wrcontrol_wraddress_reg_b = "CLOCK1",
            parameter clock_enable_input_a = "BYPASS",
            parameter clock_enable_input_b = "BYPASS",
            parameter clock_enable_output_a = "BYPASS",
            parameter clock_enable_output_b = "BYPASS",
            parameter power_up_uninitialized = "FALSE",
            parameter byte_size = 8
          ) (
            input aclr0,
            input aclr1,
            input [widthad_a-1:0] address_a,
            input [widthad_b-1:0] address_b,
            input addressstall_a,
            input addressstall_b,
            input [width_byteena_a-1:0] byteena_a,
            input [width_byteena_b-1:0] byteena_b,
            input clock0,
            input clock1,
            input clocken0,
            input clocken1,
            input clocken2,
            input clocken3,
            input [width_a-1:0] data_a,
            input [width_b-1:0] data_b,
            output [2:0] eccstatus,
            output [width_a-1:0] q_a,
            output [width_b-1:0] q_b,
            input rden_a,
            input rden_b,
            input wren_a,
            input wren_b
          );
            localparam integer SAFE_WIDTH_A = (width_a > 0) ? width_a : 1;
            localparam integer SAFE_WIDTH_B = (width_b > 0) ? width_b : 1;
            localparam integer SAFE_WIDTHAD_A = (widthad_a > 0) ? widthad_a : 1;
            localparam integer SAFE_WIDTHAD_B = (widthad_b > 0) ? widthad_b : 1;
            localparam integer SAFE_WIDTH_BYTEENA_A = (width_byteena_a > 0) ? width_byteena_a : 1;
            localparam integer SAFE_WIDTH_BYTEENA_B = (width_byteena_b > 0) ? width_byteena_b : 1;
            localparam integer SAFE_DEPTH_A = (1 << SAFE_WIDTHAD_A);
            localparam integer SAFE_BYTE_COUNT_A = (SAFE_WIDTH_A + 7) / 8;
            localparam integer SAFE_BYTE_COUNT_B = (SAFE_WIDTH_B + 7) / 8;
            localparam integer SAFE_SUBWORDS_PER_A_B = (SAFE_WIDTH_A >= SAFE_WIDTH_B && SAFE_WIDTH_B > 0) ? (SAFE_WIDTH_A / SAFE_WIDTH_B) : 1;
            localparam integer SAFE_SUBWORD_BITS_B = (SAFE_SUBWORDS_PER_A_B <= 1) ? 1 : $clog2(SAFE_SUBWORDS_PER_A_B);

            reg [SAFE_WIDTH_A-1:0] mem [0:SAFE_DEPTH_A-1];
            reg [SAFE_WIDTH_A-1:0] merged_a;
            reg [SAFE_WIDTH_A-1:0] merged_b_word;
            reg [SAFE_WIDTH_B-1:0] read_b_data;
            reg [SAFE_WIDTHAD_A-1:0] addr_b_word_reg;
            reg [SAFE_SUBWORD_BITS_B-1:0] addr_b_lane_reg;
            integer init_i;
            integer byte_i;

            wire [SAFE_WIDTHAD_A-1:0] addr_a = address_a;
            wire [SAFE_WIDTHAD_B-1:0] addr_b_full = address_b;
            wire [SAFE_WIDTHAD_A-1:0] addr_b_word = (SAFE_WIDTH_A >= SAFE_WIDTH_B) ? (addr_b_full / SAFE_SUBWORDS_PER_A_B) : addr_b_full[SAFE_WIDTHAD_A-1:0];
            wire [SAFE_SUBWORD_BITS_B-1:0] addr_b_lane = (SAFE_WIDTH_A >= SAFE_WIDTH_B) ? (addr_b_full % SAFE_SUBWORDS_PER_A_B) : {SAFE_SUBWORD_BITS_B{1'b0}};
            wire clocken0_en = (clocken0 === 1'b0) ? 1'b0 : 1'b1;
            wire clocken1_en = (clocken1 === 1'b0) ? 1'b0 : 1'b1;
            wire addrstall_a_en = (addressstall_a === 1'b1) ? 1'b1 : 1'b0;
            wire addrstall_b_en = (addressstall_b === 1'b1) ? 1'b1 : 1'b0;
            wire wren_a_en = (wren_a === 1'b1) ? 1'b1 : 1'b0;
            wire wren_b_en = (wren_b === 1'b1) ? 1'b1 : 1'b0;
            wire rden_a_en = (rden_a === 1'b0) ? 1'b0 : 1'b1;
            wire rden_b_en = (rden_b === 1'b0) ? 1'b0 : 1'b1;
            wire wren_a_fire = wren_a_en && clocken0_en && !addrstall_a_en;
            wire wren_b_fire = wren_b_en && clocken1_en && !addrstall_b_en;
            wire rden_a_fire = rden_a_en && clocken0_en && !addrstall_a_en;
            wire rden_b_fire = rden_b_en && clocken1_en && !addrstall_b_en;

            initial begin
              for (init_i = 0; init_i < SAFE_DEPTH_A; init_i = init_i + 1) begin
                mem[init_i] = {SAFE_WIDTH_A{1'b0}};
              end
              addr_b_word_reg = {SAFE_WIDTHAD_A{1'b0}};
              addr_b_lane_reg = {SAFE_SUBWORD_BITS_B{1'b0}};
            end

            always @* begin
              merged_a = mem[addr_a];
              if (SAFE_WIDTH_BYTEENA_A <= 1 || SAFE_BYTE_COUNT_A <= 1) begin
                merged_a = data_a;
              end else begin
                for (byte_i = 0; byte_i < SAFE_BYTE_COUNT_A; byte_i = byte_i + 1) begin
                  if (byte_i < SAFE_WIDTH_BYTEENA_A && byteena_a[byte_i]) begin
                    merged_a[(byte_i * 8) +: 8] = data_a[(byte_i * 8) +: 8];
                  end
                end
              end

              merged_b_word = mem[addr_b_word];
              if (SAFE_WIDTH_BYTEENA_B <= 1 || SAFE_BYTE_COUNT_B <= 1) begin
                if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin
                  merged_b_word[(addr_b_lane * SAFE_WIDTH_B) +: SAFE_WIDTH_B] = data_b;
                end else begin
                  merged_b_word[SAFE_WIDTH_B-1:0] = data_b;
                end
              end else begin
                for (byte_i = 0; byte_i < SAFE_BYTE_COUNT_B; byte_i = byte_i + 1) begin
                  if (byte_i < SAFE_WIDTH_BYTEENA_B && byteena_b[byte_i]) begin
                    if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin
                      merged_b_word[(addr_b_lane * SAFE_WIDTH_B) + (byte_i * 8) +: 8] = data_b[(byte_i * 8) +: 8];
                    end else begin
                      merged_b_word[(byte_i * 8) +: 8] = data_b[(byte_i * 8) +: 8];
                    end
                  end
                end
              end

              if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin
                read_b_data = mem[addr_b_word_reg][(addr_b_lane_reg * SAFE_WIDTH_B) +: SAFE_WIDTH_B];
              end else begin
                read_b_data = mem[addr_b_word_reg][SAFE_WIDTH_B-1:0];
              end
            end

            always @(posedge clock0 or posedge aclr0) begin
              if (aclr0) begin
                addr_b_word_reg <= {SAFE_WIDTHAD_A{1'b0}};
                addr_b_lane_reg <= {SAFE_SUBWORD_BITS_B{1'b0}};
              end else begin
                if (clocken0_en && !addrstall_b_en) begin
                  addr_b_word_reg <= addr_b_word;
                  addr_b_lane_reg <= addr_b_lane;
                end
                if (wren_a_fire) begin
                  mem[addr_a] <= merged_a;
                end
              end
            end

            assign q_a = rden_a_fire ? mem[addr_a] : mem[addr_a];
            assign q_b = rden_b_fire ? read_b_data : read_b_data;
            assign eccstatus = 3'b000;
          endmodule
          /* verilator lint_on UNUSEDSIGNAL */
          /* verilator lint_on UNUSEDPARAM */
          /* verilator lint_on SELRANGE */
          /* verilator lint_on WIDTHTRUNC */
          /* verilator lint_on WIDTHEXPAND */
        VERILOG
      end

      def frontend_stub_port_direction(module_name:, port_name:)
        known = frontend_blackbox_port_hint(module_name: module_name, port_name: port_name)
        direction = value_for(known, :direction).to_s.downcase
        return "output" if direction == "output"
        return "input" if direction == "input"

        token = port_name.to_s
        return "output" if token.match?(/\Aq(?:_[ab])?\z/i)
        return "output" if token.match?(/\Aeccstatus\z/i)
        return "output" if token.match?(/_out\z/i)

        "input"
      end

      def frontend_stub_port_width(module_name:, port_name:)
        known = frontend_blackbox_port_hint(module_name: module_name, port_name: port_name)
        width = value_for(known, :width)
        token = width.to_s.strip
        return nil if token.empty? || token == "1"

        token
      end

      def frontend_blackbox_port_hint(module_name:, port_name:)
        by_module = RHDL::Import::BlackboxStubGenerator::KNOWN_BLACKBOX_PORTS
        module_key = module_name.to_s.downcase
        port_key = port_name.to_s.downcase
        normalize_hash(value_for(by_module, module_key))[port_key] || {}
      end

      def augment_frontend_stub_ports(module_name:, ports:)
        known_ports = frontend_known_stub_ports(module_name: module_name)
        normalize_string_array(Array(ports) + known_ports)
      end

      def augment_frontend_stub_parameters(module_name:, parameters:, ports:)
        known_parameters = frontend_known_stub_parameters(module_name: module_name)
        required = Array(ports).filter_map do |port_name|
          hint = frontend_blackbox_port_hint(module_name: module_name, port_name: port_name)
          token = value_for(hint, :width).to_s.strip
          next if token.empty?
          next token if integer_string?(token)

          token
        end

        normalize_string_array(Array(parameters) + known_parameters + required)
      end

      def frontend_known_stub_ports(module_name:)
        case module_name.to_s.downcase
        when "altdpram"
          %w[
            aclr byteena data inclock inclocken outclock outclocken q
            rdaddress rdaddressstall rden sclr wraddress wraddressstall wren
          ]
        when "altsyncram"
          %w[
            aclr0 aclr1 address_a address_b addressstall_a addressstall_b
            byteena_a byteena_b clock0 clock1 clocken0 clocken1 clocken2 clocken3
            data_a data_b eccstatus q_a q_b rden_a rden_b wren_a wren_b
          ]
        else
          []
        end
      end

      def frontend_known_stub_parameters(module_name:)
        case module_name.to_s.downcase
        when "altdpram"
          %w[
            indata_aclr indata_reg intended_device_family lpm_type
            outdata_aclr outdata_reg ram_block_type
            rdaddress_aclr rdaddress_reg rdcontrol_aclr rdcontrol_reg
            read_during_write_mode_mixed_ports
            width widthad width_byteena
            wraddress_aclr wraddress_reg wrcontrol_aclr wrcontrol_reg
          ]
        when "altsyncram"
          %w[
            operation_mode ram_block_type intended_device_family
            lpm_type
            width_a widthad_a numwords_a outdata_aclr_a outdata_reg_a
            width_b widthad_b numwords_b outdata_aclr_b outdata_reg_b
            width_byteena_a width_byteena_b
            read_during_write_mode_mixed_ports read_during_write_mode_port_a read_during_write_mode_port_b
            address_reg_b address_aclr_b indata_reg_b wrcontrol_wraddress_reg_b
            clock_enable_input_a clock_enable_input_b
            clock_enable_output_a clock_enable_output_b
            power_up_uninitialized byte_size
          ]
        else
          []
        end
      end

      def apply_hints(options:, resolved_input:, normalized_payload:, out_dir:, hint_backend:, surelog_hint_adapter:)
        payload = deep_symbolize(normalize_hash(normalized_payload))
        return [payload, default_hint_summary(backend: "off"), []] if hint_backend == "off"

        if hint_backend == "surelog"
          begin
            hint_result = invoke_component(
              surelog_hint_adapter,
              method_name: :call,
              kwargs: {
                resolved_input: build_frontend_input(options: options, resolved_input: resolved_input, out_dir: out_dir),
                work_dir: value_for(options, :hint_work_dir) || File.join(out_dir, "tmp", "hints"),
                env: normalize_env(value_for(options, :hint_env) || value_for(options, :frontend_env))
              }
            )
            raw_hints = Array(value_for(hint_result, :hints))
            hints = normalize_hint_entries(raw_hints)
            hint_diagnostics = normalize_hint_diagnostics(value_for(hint_result, :diagnostics))
            initial_summary = normalize_hint_summary(
              value_for(hint_result, :summary),
              extracted_default: raw_hints.length,
              applied_default: hints.length,
              diagnostics: hint_diagnostics
            )
            confidence = normalize_hint_min_confidence(value_for(options, :hint_min_confidence))
            conflict_policy = normalize_hint_conflict_policy(value_for(options, :hint_conflict_policy))
            filtered_hints, threshold_diagnostics = filter_hints_by_min_confidence(
              hints: hints,
              min_confidence: confidence
            )
            enriched_payload, fusion = fuse_hints_into_payload(
              normalized_payload: payload,
              hints: filtered_hints,
              conflict_policy: conflict_policy
            )
            all_diagnostics = normalize_hint_diagnostics(hint_diagnostics + threshold_diagnostics + fusion[:diagnostics])
            summary = finalize_hint_summary(
              initial_summary: initial_summary,
              applied_count: fusion[:applied_count],
              diagnostics: all_diagnostics
            )
            hint_summary = {
              backend: "surelog",
              available: truthy?(value_for(hint_result, :available)),
              applied_count: summary[:applied_count],
              summary: summary,
              diagnostics: all_diagnostics
            }

            return [merge_payload_hints(normalized_payload: enriched_payload, hints: filtered_hints), hint_summary, all_diagnostics]
          rescue StandardError => e
            warning = {
              severity: "warning",
              code: "hint_backend_unavailable",
              message: "surelog hint backend unavailable: #{e.message}",
              backend: "surelog"
            }
            hint_summary = {
              backend: "surelog",
              available: false,
              applied_count: 0,
              summary: {
                extracted_count: 0,
                applied_count: 0,
                discarded_count: 0,
                conflict_count: 0
              },
              diagnostics: [warning]
            }
            return [payload, hint_summary, [warning]]
          end
        end

        [payload, default_hint_summary(backend: hint_backend), []]
      end

      def merge_payload_hints(normalized_payload:, hints:)
        return normalized_payload if Array(hints).empty?

        normalized_payload.merge(hints: Array(hints))
      end

      def normalize_hint_entries(entries)
        Array(entries).filter_map do |entry|
          hash = normalize_hash(entry.respond_to?(:to_h) ? entry.to_h : entry)
          hint = canonical_hint_entry(hash)
          next if hint.nil?

          hint
        end.sort_by do |entry|
          span = normalize_hash(value_for(entry, :span))
          [
            value_for(entry, :module).to_s,
            value_for(span, :source_path).to_s,
            integer_or_default(value_for(span, :line), 0),
            integer_or_default(value_for(span, :column), 0),
            integer_or_default(value_for(span, :end_line), 0),
            integer_or_default(value_for(span, :end_column), 0),
            value_for(entry, :construct_family).to_s,
            value_for(entry, :construct_kind).to_s,
            value_for(entry, :confidence).to_s
          ]
        end
      end

      def filter_hints_by_min_confidence(hints:, min_confidence:)
        threshold = hint_confidence_rank(min_confidence)
        diagnostics = []

        filtered = Array(hints).filter_map do |hint|
          confidence = normalize_hint_confidence(value_for(hint, :confidence))
          if hint_confidence_rank(confidence) < threshold
            diagnostics << {
              severity: "warning",
              code: "hint_below_min_confidence",
              module: value_for(hint, :module).to_s,
              construct: value_for(hint, :construct_kind).to_s,
              message: "discarded hint below minimum confidence: #{confidence} < #{min_confidence}"
            }
            next
          end

          hint
        end

        [filtered, diagnostics]
      end

      def fuse_hints_into_payload(normalized_payload:, hints:, conflict_policy:)
        payload = deep_symbolize(normalized_payload)
        diagnostics = []
        applied_count = 0
        modules = Array(value_for(value_for(payload, :design), :modules))

        Array(hints).each do |hint|
          module_name = value_for(hint, :module).to_s
          module_entry = modules.find { |entry| value_for(entry, :name).to_s == module_name }
          unless module_entry
            diagnostics << {
              severity: "warning",
              code: "hint_discarded",
              module: module_name,
              construct: value_for(hint, :construct_kind).to_s,
              message: "discarded hint: target module not found"
            }
            next
          end

          family = value_for(hint, :construct_family).to_s
          if family == "process"
            applied, diags = apply_process_hint(module_entry: module_entry, hint: hint)
            applied_count += 1 if applied
            diagnostics.concat(diags)
            next
          end

          if family == "statement"
            applied, diags = apply_statement_hint(
              module_entry: module_entry,
              hint: hint,
              conflict_policy: conflict_policy
            )
            applied_count += 1 if applied
            diagnostics.concat(diags)
            next
          end

          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: module_name,
            construct: value_for(hint, :construct_kind).to_s,
            message: "discarded hint: unsupported construct family #{family.inspect}"
          }
        end

        [
          payload,
          {
            applied_count: applied_count,
            diagnostics: diagnostics
          }
        ]
      end

      def apply_process_hint(module_entry:, hint:)
        diagnostics = []
        data = normalize_hash(value_for(hint, :data))
        process_index = integer_or_default(value_for(data, :process_index), 0)
        processes = Array(value_for(module_entry, :processes))
        process_entry = processes[process_index]

        unless process_entry.is_a?(Hash)
          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: value_for(module_entry, :name).to_s,
            construct: value_for(hint, :construct_kind).to_s,
            message: "discarded process hint: process index out of range"
          }
          return [false, diagnostics]
        end

        process_entry[:intent] = value_for(hint, :construct_kind).to_s
        apply_hint_metadata(node: process_entry, hint: hint)
        [true, diagnostics]
      end

      def apply_statement_hint(module_entry:, hint:, conflict_policy:)
        diagnostics = []
        data = normalize_hash(value_for(hint, :data))
        process_index = integer_or_default(value_for(data, :process_index), 0)
        statement_index = integer_or_default(value_for(data, :statement_index), 0)
        processes = Array(value_for(module_entry, :processes))
        process_entry = processes[process_index]

        unless process_entry.is_a?(Hash)
          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: value_for(module_entry, :name).to_s,
            construct: value_for(hint, :construct_kind).to_s,
            message: "discarded statement hint: process index out of range"
          }
          return [false, diagnostics]
        end

        statements = Array(value_for(process_entry, :statements))
        target = statements[statement_index]
        unless target.is_a?(Hash)
          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: value_for(module_entry, :name).to_s,
            construct: value_for(hint, :construct_kind).to_s,
            message: "discarded statement hint: statement index out of range"
          }
          return [false, diagnostics]
        end

        kind = value_for(hint, :construct_kind).to_s
        case kind
        when "case_unique", "case_priority"
          qualifier = kind == "case_unique" ? "unique" : "priority"
          target_kind = value_for(target, :kind).to_s
          if target_kind == "case"
            target[:qualifier] = qualifier
            apply_hint_metadata(node: target, hint: hint)
            return [true, diagnostics]
          end

          diagnostics << hint_conflict_diagnostic(
            module_name: value_for(module_entry, :name).to_s,
            construct: kind,
            target_kind: target_kind,
            conflict_policy: conflict_policy
          )
          return [false, diagnostics]
        when "case_from_if"
          replacement_case = canonical_hint_case_node(value_for(data, :case))
          if replacement_case.nil?
            diagnostics << {
              severity: "warning",
              code: "hint_discarded",
              module: value_for(module_entry, :name).to_s,
              construct: kind,
              message: "discarded statement hint: missing canonical case payload"
            }
            return [false, diagnostics]
          end

          target_kind = value_for(target, :kind).to_s
          if target_kind == "if"
            case conflict_policy
            when "prefer_ast"
              diagnostics << hint_conflict_diagnostic(
                module_name: value_for(module_entry, :name).to_s,
                construct: kind,
                target_kind: target_kind,
                conflict_policy: conflict_policy
              )
              return [false, diagnostics]
            when "strict"
              diagnostics << hint_conflict_diagnostic(
                module_name: value_for(module_entry, :name).to_s,
                construct: kind,
                target_kind: target_kind,
                conflict_policy: conflict_policy
              )
              return [false, diagnostics]
            else
              apply_hint_metadata(node: replacement_case, hint: hint)
              statements[statement_index] = replacement_case
              process_entry[:statements] = statements
              diagnostics << hint_conflict_diagnostic(
                module_name: value_for(module_entry, :name).to_s,
                construct: kind,
                target_kind: target_kind,
                conflict_policy: conflict_policy
              )
              return [true, diagnostics]
            end
          end

          if target_kind == "case"
            if conflict_policy == "prefer_hint"
              apply_hint_metadata(node: replacement_case, hint: hint)
              statements[statement_index] = replacement_case
            end
            process_entry[:statements] = statements
            return [conflict_policy == "prefer_hint", diagnostics]
          end

          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: value_for(module_entry, :name).to_s,
            construct: kind,
            message: "discarded statement hint: unsupported target statement kind #{target_kind.inspect}"
          }
          return [false, diagnostics]
        else
          diagnostics << {
            severity: "warning",
            code: "hint_discarded",
            module: value_for(module_entry, :name).to_s,
            construct: kind,
            message: "discarded statement hint: unsupported construct kind #{kind.inspect}"
          }
          return [false, diagnostics]
        end
      end

      def canonical_hint_case_node(value)
        hash = normalize_hash(value)
        kind = value_for(hash, :kind).to_s
        return nil unless kind == "case"

        selector = normalize_hash(value_for(hash, :selector))
        return nil if selector.empty?

        items = Array(value_for(hash, :items)).filter_map do |item|
          item_hash = normalize_hash(item)
          values = Array(value_for(item_hash, :values)).map { |entry| deep_symbolize(normalize_hash(entry)) }.reject(&:empty?)
          next if values.empty?

          body = Array(value_for(item_hash, :body)).map { |entry| deep_symbolize(normalize_hash(entry)) }
          {
            values: values,
            body: body
          }
        end

        case_node = {
          kind: "case",
          selector: deep_symbolize(selector),
          items: items,
          default: Array(value_for(hash, :default)).map { |entry| deep_symbolize(normalize_hash(entry)) }
        }
        qualifier = value_for(hash, :qualifier).to_s.strip
        case_node[:qualifier] = qualifier unless qualifier.empty?
        origin = value_for(hash, :origin).to_s.strip
        case_node[:origin] = origin unless origin.empty?
        provenance = normalize_hint_metadata_hash(value_for(hash, :provenance))
        case_node[:provenance] = provenance if provenance
        case_node
      end

      def apply_hint_metadata(node:, hint:, source: "surelog_hint")
        node[:origin] = "hint"
        provenance = hint_provenance(hint, source: source)
        node[:provenance] = provenance if provenance
      end

      def hint_provenance(hint, source:)
        span = canonical_hint_span(value_for(hint, :span), hint)
        {
          source: source,
          construct_family: value_for(hint, :construct_family).to_s.strip,
          construct_kind: value_for(hint, :construct_kind).to_s.strip,
          confidence: normalize_hint_confidence(value_for(hint, :confidence)),
          span: span.nil? ? nil : deep_symbolize(span)
        }.reject do |_, value|
          value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end

      def normalize_hint_metadata_hash(value)
        hash = normalize_hash(value)
        return nil if hash.empty?

        deep_symbolize(hash)
      end

      def hint_conflict_diagnostic(module_name:, construct:, target_kind:, conflict_policy:)
        severity = conflict_policy == "strict" ? "error" : "warning"
        {
          severity: severity,
          code: "hint_conflict",
          module: module_name,
          construct: construct,
          message: "hint conflict under #{conflict_policy}: target statement kind #{target_kind.inspect}"
        }
      end

      def finalize_hint_summary(initial_summary:, applied_count:, diagnostics:)
        hash = normalize_hash(initial_summary)
        extracted_count = integer_or_default(value_for(hash, :extracted_count), 0)
        conflict_count = Array(diagnostics).count { |entry| value_for(entry, :code).to_s == "hint_conflict" }
        discarded_count = [extracted_count - applied_count, 0].max

        {
          extracted_count: extracted_count,
          applied_count: applied_count,
          discarded_count: discarded_count,
          conflict_count: conflict_count
        }
      end

      def normalize_hint_diagnostics(diagnostics)
        Array(diagnostics).filter_map do |entry|
          hash = normalize_hash(entry.respond_to?(:to_h) ? entry.to_h : entry)
          next if hash.empty?

          deep_symbolize(hash)
        end.sort_by do |entry|
          [
            value_for(entry, :severity).to_s,
            value_for(entry, :code).to_s,
            value_for(entry, :message).to_s
          ]
        end
      end

      def normalize_hint_summary(summary, extracted_default:, applied_default:, diagnostics:)
        hash = normalize_hash(summary)
        extracted_count = integer_or_default(value_for(hash, :extracted_count), extracted_default)
        applied_count = integer_or_default(value_for(hash, :applied_count), applied_default)
        discarded_default = [extracted_count - applied_count, 0].max
        discarded_count = integer_or_default(value_for(hash, :discarded_count), discarded_default)
        conflict_default = Array(diagnostics).count { |entry| value_for(entry, :code).to_s == "hint_conflict" }
        conflict_count = integer_or_default(value_for(hash, :conflict_count), conflict_default)

        {
          extracted_count: extracted_count,
          applied_count: applied_count,
          discarded_count: discarded_count,
          conflict_count: conflict_count
        }
      end

      def canonical_hint_entry(hash)
        module_name = value_for(hash, :module) || value_for(hash, :module_name)
        family = value_for(hash, :construct_family) || value_for(hash, :family)
        kind = value_for(hash, :construct_kind) || value_for(hash, :kind) || value_for(hash, :construct)

        module_name = module_name.to_s.strip
        family = family.to_s.strip
        kind = kind.to_s.strip
        return nil if module_name.empty? || family.empty? || kind.empty?

        {
          module: module_name,
          construct_family: family,
          construct_kind: kind,
          confidence: normalize_hint_confidence(value_for(hash, :confidence)),
          span: canonical_hint_span(value_for(hash, :span), hash),
          data: canonical_hint_data(value_for(hash, :data))
        }.compact
      end

      def canonical_hint_span(span, fallback_hash)
        span_hash = normalize_hash(span)
        span_hash = fallback_hash if span_hash.empty?

        source_path = value_for(span_hash, :source_path) || value_for(span_hash, :path) || value_for(span_hash, :file)
        line = integer_or_default(value_for(span_hash, :line), nil)
        column = integer_or_default(value_for(span_hash, :column), nil)
        end_line = integer_or_default(value_for(span_hash, :end_line), nil)
        end_column = integer_or_default(value_for(span_hash, :end_column), nil)
        normalized = {
          source_path: source_path&.to_s,
          line: line,
          column: column,
          end_line: end_line,
          end_column: end_column
        }.compact
        normalized.empty? ? nil : normalized
      end

      def canonical_hint_data(value)
        case value
        when Hash
          value.keys.map(&:to_s).sort.each_with_object({}) do |key, memo|
            memo[key.to_sym] = canonical_hint_data(value_for(value, key))
          end
        when Array
          value.map { |inner| canonical_hint_data(inner) }
        when String, Numeric, TrueClass, FalseClass, NilClass
          value
        else
          value.to_s
        end
      end

      def normalize_hint_confidence(value)
        normalized = value.to_s.strip.downcase
        return normalized if %w[high medium low].include?(normalized)

        "medium"
      end

      def extract_program_modules(program)
        modules = if program.respond_to?(:modules)
          program.modules
        else
          value_for(program, :modules)
        end

        normalize_mapped_modules(modules)
      end

      def extract_program_diagnostics(program)
        diagnostics = if program.respond_to?(:diagnostics)
          program.diagnostics
        else
          value_for(program, :diagnostics)
        end

        Array(diagnostics)
      end

      def resolve_translated_modules(options:, mapped_modules:, failed_modules:, translator:)
        if option_provided?(options, :translated_modules)
          translated = normalize_translated_modules(
            value_for(options, :translated_modules),
            mapped_modules: mapped_modules
          )
          failed_names = failed_modules.map { |entry| value_for(entry, :name).to_s }.to_set
          return [translated.reject { |entry| failed_names.include?(entry[:name]) }, []]
        end

        failed_names = failed_modules.map { |entry| value_for(entry, :name).to_s }.to_set
        translated_modules = []
        translation_failures = []

        mapped_modules.each do |mapped_module|
          name = value_for(mapped_module, :name).to_s
          next if name.empty? || failed_names.include?(name)

          begin
            translated_modules << {
              name: name,
              source: translate_module_source(translator, mapped_module).to_s,
              source_path: extract_source_path(mapped_module),
              dependencies: extract_dependencies(mapped_module),
              ports: normalize_ports(value_for(mapped_module, :ports)),
              instances: Array(value_for(mapped_module, :instances))
            }
          rescue StandardError => e
            translation_failures << {
              name: name,
              code: "translation_error",
              message: e.message
            }
          end
        end

        [translated_modules.sort_by { |entry| entry[:name] }, translation_failures.sort_by { |entry| entry[:name] }]
      end

      def translate_module_source(translator, mapped_module)
        if translator.respond_to?(:translate_module)
          return translator.translate_module(mapped_module)
        end

        translated =
          if translator.respond_to?(:translate)
            translator.translate([mapped_module])
          elsif translator.respond_to?(:call)
            translator.call([mapped_module])
          else
            raise ArgumentError, "translator #{translator.class} does not respond to #translate_module, #translate, or #call"
          end
        first = Array(translated).first
        value_for(first, :source)
      end

      def normalize_translated_modules(translated_modules, mapped_modules:)
        mapped_by_name = mapped_modules.each_with_object({}) do |entry, memo|
          name = value_for(entry, :name).to_s
          memo[name] = entry unless name.empty?
        end

        Array(translated_modules).map do |entry|
          hash = normalize_hash(entry.respond_to?(:to_h) ? entry.to_h : entry)
          name = value_for(hash, :name).to_s
          next if name.empty?

          mapped_entry = mapped_by_name[name] || {}
          dependencies = extract_dependencies(hash)
          dependencies = extract_dependencies(mapped_entry) if dependencies.empty?

          ports = normalize_ports(value_for(hash, :ports))
          ports = normalize_ports(value_for(mapped_entry, :ports)) if ports.empty?

          instances = Array(value_for(hash, :instances))
          instances = Array(value_for(mapped_entry, :instances)) if instances.empty?

          source_path = value_for(hash, :source_path).to_s.strip
          source_path = extract_source_path(mapped_entry) if source_path.empty?

          {
            name: name,
            source: value_for(hash, :source).to_s,
            source_path: source_path,
            dependencies: dependencies,
            ports: ports,
            instances: instances
          }
        end.compact.sort_by { |entry| entry[:name] }
      end

      def build_pipeline_options(options:, resolved_input:)
        pipeline_options = {}
        PIPELINE_OPTION_KEYS.each do |key|
          next unless option_provided?(options, key)

          pipeline_options[key] = value_for(options, key)
        end

        pipeline_options[:source_files] = array_value(resolved_input, :source_files)
        pipeline_options[:include_dirs] = array_value(resolved_input, :include_dirs)
        pipeline_options[:defines] = value_for(resolved_input, :defines) || []
        pipeline_options[:mode] = value_for(resolved_input, :mode)
        pipeline_options[:filelist_path] = value_for(resolved_input, :filelist_path)
        pipeline_options[:source_roots] = array_value(resolved_input, :source_roots)
        pipeline_options[:exclude_patterns] = array_value(resolved_input, :exclude_patterns)
        pipeline_options[:top] ||= normalize_string_array(value_for(options, :top))
        pipeline_options
      end

      def invoke_pipeline(pipeline:, out_dir:, project_slug:, pipeline_options:, translated_modules:, failed_modules:, diagnostics:, options:, runtime:)
        pipeline_kwargs = {
          out: out_dir,
          project_slug: project_slug,
          options: pipeline_options,
          translated_modules: translated_modules,
          failed_modules: failed_modules,
          diagnostics: diagnostics,
          report_builder: runtime[:report_builder],
          result_class: runtime[:result_class]
        }
        optional_dependencies = {
          writer: value_for(options, :project_writer),
          top_detector: value_for(options, :top_detector),
          dependency_graph_class: value_for(options, :dependency_graph_class),
          check_runner: value_for(options, :check_runner),
          stimulus_generator: value_for(options, :stimulus_generator),
          comparator: value_for(options, :comparator),
          check_report_writer: value_for(options, :check_report_writer),
          trace_comparator: value_for(options, :trace_comparator),
          trace_report_writer: value_for(options, :trace_report_writer),
          ao486_trace_harness: value_for(options, :ao486_trace_harness),
          ao486_component_parity_harness: value_for(options, :ao486_component_parity_harness),
          component_parity_report_writer: value_for(options, :component_parity_report_writer)
        }
        optional_dependencies.each do |key, value|
          pipeline_kwargs[key] = value unless value.nil?
        end

        invoke_component(pipeline, method_name: :run, kwargs: pipeline_kwargs)
      end

      def build_failure_result(out_dir:, options:, runtime:, diagnostics:, error:)
        normalized_diagnostics = Array(diagnostics).dup
        normalized_diagnostics << {
          severity: "error",
          code: "import_execution_error",
          message: error.message
        }

        failed_modules = [
          {
            name: "import",
            code: error.respond_to?(:exit_code) ? "tool_failure" : "import_execution_error",
            message: error.message
          }
        ]

        report = runtime[:report_builder].build(
          out: out_dir,
          options: options,
          status: :failure,
          diagnostics: normalized_diagnostics,
          converted_modules: [],
          failed_modules: failed_modules
        )
        report_path = runtime[:report_builder].write(report, out: out_dir)

        runtime[:result_class].failure(
          out_dir: out_dir,
          report_path: report_path,
          report: report,
          errors: [error.message],
          diagnostics: normalized_diagnostics,
          converted_modules: [],
          failed_modules: failed_modules
        )
      end

      def maybe_copy_report(result:, report_target:, result_class:, cwd:)
        target = report_target.to_s
        return result if target.empty?

        report_path = File.expand_path(target, cwd || Dir.pwd)
        source_path = result.report_path.to_s

        FileUtils.mkdir_p(File.dirname(report_path))
        if !source_path.empty? && File.exist?(source_path)
          expanded_source = File.expand_path(source_path)
          FileUtils.cp(expanded_source, report_path) unless expanded_source == report_path
        end

        rebuild_result_with_report_path(result: result, report_path: report_path, result_class: result_class)
      end

      def rebuild_result_with_report_path(result:, report_path:, result_class:)
        payload = {
          out_dir: result.out_dir,
          report_path: report_path,
          report: result.report,
          errors: result.errors,
          diagnostics: result.diagnostics,
          converted_modules: result.converted_modules,
          failed_modules: result.failed_modules
        }

        result.success? ? result_class.success(**payload) : result_class.failure(**payload)
      end

      def resolve_project_slug(project_slug, out_dir)
        explicit = project_slug.to_s.strip
        return explicit unless explicit.empty?

        fallback = File.basename(out_dir).to_s.gsub(/[^A-Za-z0-9]+/, "_").downcase
        fallback.empty? ? "imported_project" : fallback
      end

      def build_recovery_report(mapped_modules:, diagnostics:, hints:, recovery_mode:)
        hint_applied_count = integer_or_default(value_for(hints, :applied_count), 0)
        return default_recovery_report(hint_applied_count: hint_applied_count) if recovery_mode == "off"

        preserved = preserved_recovery_events(mapped_modules: mapped_modules)
        lowered = recovery_events_from_diagnostics(diagnostics: diagnostics, category: :lowered)
        nonrecoverable = recovery_events_from_diagnostics(diagnostics: diagnostics, category: :nonrecoverable)
        events = (preserved + lowered + nonrecoverable).sort_by do |entry|
          [
            value_for(entry, :status).to_s,
            value_for(entry, :module).to_s,
            value_for(entry, :construct).to_s,
            value_for(entry, :code).to_s,
            value_for(entry, :message).to_s
          ]
        end

        {
          summary: {
            preserved_count: preserved.length,
            lowered_count: lowered.length,
            nonrecoverable_count: nonrecoverable.length,
            hint_applied_count: hint_applied_count
          },
          events: events
        }
      end

      def strict_recovery_failure(recovery:, recovery_mode:)
        return nil unless recovery_mode == "strict"

        summary = normalize_hash(value_for(recovery, :summary))
        lowered_count = integer_or_default(value_for(summary, :lowered_count), 0)
        nonrecoverable_count = integer_or_default(value_for(summary, :nonrecoverable_count), 0)
        return nil if lowered_count.zero? && nonrecoverable_count.zero?

        {
          name: "import",
          code: "recovery_strict_failure",
          message: "strict recovery mode blocked import (lowered=#{lowered_count}, nonrecoverable=#{nonrecoverable_count})"
        }
      end

      def default_recovery_report(hint_applied_count:)
        {
          summary: {
            preserved_count: 0,
            lowered_count: 0,
            nonrecoverable_count: 0,
            hint_applied_count: hint_applied_count
          },
          events: []
        }
      end

      def default_hint_summary(backend:)
        {
          backend: backend.to_s,
          available: false,
          applied_count: 0,
          summary: {
            extracted_count: 0,
            applied_count: 0,
            discarded_count: 0,
            conflict_count: 0
          },
          diagnostics: []
        }
      end

      def preserved_recovery_events(mapped_modules:)
        events = []
        Array(mapped_modules).each do |module_entry|
          module_hash = normalize_hash(module_entry)
          module_name = value_for(module_hash, :name).to_s
          next if module_name.empty?

          Array(value_for(module_hash, :statements)).each do |statement|
            collect_preserved_recovery_events(statement: statement, module_name: module_name, events: events)
          end

          Array(value_for(module_hash, :processes)).each do |process|
            process_hash = normalize_hash(process)
            Array(value_for(process_hash, :statements)).each do |statement|
              collect_preserved_recovery_events(statement: statement, module_name: module_name, events: events)
            end
          end
        end

        events
      end

      def collect_preserved_recovery_events(statement:, module_name:, events:)
        hash = normalize_hash(statement.respond_to?(:to_h) ? statement.to_h : statement)
        kind = value_for(hash, :kind).to_s

        if kind == "case"
          events << {
            module: module_name,
            construct: "case",
            status: "preserved",
            code: "recovery_preserved"
          }
        elsif kind == "for"
          events << {
            module: module_name,
            construct: "for",
            status: "preserved",
            code: "recovery_preserved"
          }
        end

        Array(value_for(hash, :then)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
        Array(value_for(hash, :then_body)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
        Array(value_for(hash, :else)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
        Array(value_for(hash, :else_body)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
        Array(value_for(hash, :body)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end

        Array(value_for(hash, :items)).each do |item|
          item_hash = normalize_hash(item)
          Array(value_for(item_hash, :body)).each do |child|
            collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
          end
        end

        Array(value_for(hash, :default)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
        Array(value_for(hash, :default_body)).each do |child|
          collect_preserved_recovery_events(statement: child, module_name: module_name, events: events)
        end
      end

      def recovery_events_from_diagnostics(diagnostics:, category:)
        Array(diagnostics).filter_map do |entry|
          hash = normalize_hash(entry)
          code = value_for(hash, :code).to_s
          next if code.empty?

          status =
            case code
            when "recovery_lowered"
              "lowered"
            when "unsupported_construct", "recovery_nonrecoverable"
              "nonrecoverable"
            end
          next if status.nil?
          next if category == :lowered && status != "lowered"
          next if category == :nonrecoverable && status != "nonrecoverable"

          construct = value_for(hash, :construct).to_s
          construct = "unknown" if construct.empty?
          module_name = value_for(hash, :module).to_s
          module_name = "import" if module_name.empty?

          {
            module: module_name,
            construct: construct,
            status: status,
            code: code,
            message: value_for(hash, :message).to_s
          }
        end
      end

      def infer_failed_modules_from_diagnostics(diagnostics)
        failures = {}

        Array(diagnostics).each do |entry|
          code = value_for(entry, :code).to_s
          module_name = value_for(entry, :module).to_s
          next unless code == "unsupported_construct"
          next if module_name.empty?

          message = value_for(entry, :message).to_s
          message = "module contains unsupported constructs" if message.empty?
          failures[module_name] ||= {
            name: module_name,
            code: "unsupported_construct",
            message: message
          }
        end

        failures.values.sort_by { |entry| entry[:name] }
      end

      def infer_empty_import_failure(resolved_input:, mapped_modules:)
        source_files = array_value(resolved_input, :source_files)
        return nil if source_files.empty?
        return nil unless Array(mapped_modules).empty?

        {
          name: "import",
          code: "no_modules_detected",
          message: "no modules were detected in frontend payload for provided source files"
        }
      end

      def diagnostics_for_failures(failures)
        Array(failures).map do |entry|
          {
            severity: "error",
            code: value_for(entry, :code).to_s,
            message: value_for(entry, :message).to_s,
            module: value_for(entry, :name).to_s
          }
        end
      end

      def normalize_mapped_modules(modules)
        Array(modules).map do |entry|
          hash = normalize_hash(entry.respond_to?(:to_h) ? entry.to_h : entry)
          name = value_for(hash, :name).to_s
          next if name.empty?

          deep_symbolize(hash.merge(name: name))
        end.compact.sort_by { |entry| entry[:name] }
      end

      def normalize_failed_modules(failed_modules)
        Array(failed_modules).map do |entry|
          if entry.is_a?(Hash)
            name = value_for(entry, :name).to_s
            next if name.empty?

            {
              name: name,
              code: value_for(entry, :code) || "failed",
              message: value_for(entry, :message) || "module conversion failed"
            }
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

      def merge_failures(*groups)
        seen = Set.new
        merged = []

        groups.flatten.each do |entry|
          hash = normalize_hash(entry)
          name = value_for(hash, :name).to_s
          next if name.empty?
          next if seen.include?(name)

          seen << name
          merged << hash
        end

        merged
      end

      def extract_dependencies(module_entry)
        explicit_dependencies = value_for(module_entry, :dependencies)
        if !explicit_dependencies.nil?
          return normalize_string_array(explicit_dependencies)
        end

        instances = Array(value_for(module_entry, :instances))
        normalize_string_array(
          instances.map do |instance|
            hash = normalize_hash(instance)
            value_for(hash, :module_name) || value_for(hash, :module)
          end
        )
      end

      def normalize_ports(ports)
        Array(ports).map do |entry|
          hash = normalize_hash(entry.respond_to?(:to_h) ? entry.to_h : entry)
          next if value_for(hash, :name).to_s.empty?

          hash
        end.compact
      end

      def extract_source_path(module_entry)
        explicit = value_for(module_entry, :source_path).to_s.strip
        return explicit unless explicit.empty?

        span = normalize_hash(value_for(module_entry, :span))
        source_path = value_for(span, :source_path) || value_for(span, :path) || value_for(span, :file)
        source_path.to_s.strip
      end

      def cleanup_temp_artifacts(out_dir:, keep_temp:)
        return if out_dir.to_s.empty?
        return if truthy?(keep_temp)

        tmp_dir = File.join(out_dir, "tmp")
        FileUtils.rm_rf(tmp_dir) if Dir.exist?(tmp_dir)
      end

      def invoke_component(component, method_name:, kwargs:)
        callable =
          if component.respond_to?(method_name)
            ->(*args, **keyed) { component.public_send(method_name, *args, **keyed) }
          elsif component.respond_to?(:call)
            ->(*args, **keyed) { component.call(*args, **keyed) }
          end

        raise ArgumentError, "component #{component.class} does not respond to ##{method_name} or #call" unless callable

        begin
          callable.call(**kwargs)
        rescue ArgumentError => e
          begin
            callable.call(kwargs)
          rescue ArgumentError
            raise e
          end
        end
      end

      def normalize_payload(normalizer, raw_payload)
        if normalizer.respond_to?(:normalize)
          normalizer.normalize(raw_payload)
        elsif normalizer.respond_to?(:call)
          normalizer.call(raw_payload)
        else
          raise ArgumentError, "normalizer #{normalizer.class} does not respond to #normalize or #call"
        end
      end

      def map_payload(mapper, normalized_payload)
        if mapper.respond_to?(:map)
          mapper.map(normalized_payload)
        elsif mapper.respond_to?(:call)
          mapper.call(normalized_payload)
        else
          raise ArgumentError, "mapper #{mapper.class} does not respond to #map or #call"
        end
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

      def normalize_hash(value)
        value.is_a?(Hash) ? value : {}
      end

      def normalize_env(env)
        return {} unless env.is_a?(Hash)

        env.each_with_object({}) do |(key, value), memo|
          memo[key.to_s] = value.to_s
        end
      end

      def normalize_string_array(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def integer_string?(value)
        value.to_s.match?(/\A\d+\z/)
      end

      def normalize_missing_modules_policy(value)
        normalized = value.to_s.strip.downcase
        return "blackbox_stubs" if normalized == "blackbox_stubs"

        "fail"
      end

      def normalize_recovery_mode(value)
        normalized = value.to_s.strip.downcase
        normalized = "recoverable" if normalized.empty?
        return normalized if RECOVERY_MODES.include?(normalized)

        raise ArgumentError, "unknown recovery_mode: #{value.inspect}"
      end

      def normalize_hint_backend(value)
        normalized = value.to_s.strip.downcase
        normalized = "surelog" if normalized.empty?
        return normalized if HINT_BACKENDS.include?(normalized)

        raise ArgumentError, "unknown hint_backend: #{value.inspect}"
      end

      def normalize_hint_min_confidence(value)
        normalized = value.to_s.strip.downcase
        normalized = "medium" if normalized.empty?
        return normalized if HINT_CONFIDENCE_RANK.key?(normalized)

        raise ArgumentError, "unknown hint_min_confidence: #{value.inspect}"
      end

      def normalize_hint_conflict_policy(value)
        normalized = value.to_s.strip.downcase
        normalized = "prefer_ast" if normalized.empty?
        return normalized if HINT_CONFLICT_POLICIES.include?(normalized)

        raise ArgumentError, "unknown hint_conflict_policy: #{value.inspect}"
      end

      def hint_confidence_rank(value)
        HINT_CONFIDENCE_RANK.fetch(normalize_hint_confidence(value), HINT_CONFIDENCE_RANK["medium"])
      end

      def array_value(hash, key)
        normalize_string_array(value_for(hash, key))
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

      def option_provided?(options, key)
        options.key?(key) || options.key?(key.to_s)
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

      def integer_or_default(value, default)
        Integer(value)
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
