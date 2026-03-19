# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'
require 'shellwords'
require 'time'
require 'tmpdir'
require 'timeout'

require_relative '../../../examples/sparc64/utilities/integration/import_loader'
require_relative '../../../examples/sparc64/utilities/integration/import_patch_set'
require_relative '../../../examples/sparc64/utilities/import/system_importer'

module Sparc64MlirOptMatrixSupport
  VARIANTS = [
    {
      id: 'hw_flatten_modules_canonicalize_cse',
      label: 'hw-flatten-modules + canonicalize + cse',
      args: ['--hw-flatten-modules', '--canonicalize', '--cse']
    },
    {
      id: 'canonicalize_cse',
      label: 'canonicalize + cse',
      args: ['--canonicalize', '--cse']
    },
    {
      id: 'circt_opt_passthrough',
      label: 'circt-opt passthrough',
      args: []
    },
    {
      id: 'hw_flatten_modules',
      label: 'hw-flatten-modules',
      args: ['--hw-flatten-modules']
    }
  ].freeze

  module_function

  def build_report!(report_path:, top: nil)
    report_path = File.expand_path(report_path)
    work_dir = File.join(File.dirname(report_path), 'artifacts')
    FileUtils.mkdir_p(File.dirname(report_path))
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)

    import_dir = File.join(work_dir, 'fresh_import')
    raw_import = run_raw_core_import!(import_dir: import_dir)
    importer_run_seconds = raw_import.fetch(:elapsed_seconds)
    core_mlir_path = raw_import.fetch(:core_mlir_path)
    import_top = (top || raw_import.fetch(:top)).to_s
    core_mlir = File.read(core_mlir_path)
    input_mlir_path = File.join(work_dir, '00.input.core.mlir')
    File.write(input_mlir_path, core_mlir)
    input_mlir_bytes = core_mlir.bytesize

    variants = VARIANTS.each_with_index.map do |variant, index|
      run_variant(
        variant: variant,
        index: index + 1,
        input_mlir_path: input_mlir_path,
        input_mlir_bytes: input_mlir_bytes,
        work_dir: work_dir,
        import_top: import_top
      )
    end

    best_success_variant = variants.select { |variant| variant[:success] }
                                   .min_by { |variant| variant.fetch(:exported_mlir_bytes) }

    report = {
      generated_at: Time.now.utc.iso8601,
      import_dir: import_dir,
      fresh_import_dir: import_dir,
      importer_run_seconds: importer_run_seconds,
      source_core_mlir_path: core_mlir_path,
      circt_verilog_command: raw_import.fetch(:circt_verilog_command),
      import_top: import_top,
      input_mlir_path: input_mlir_path,
      input_mlir_bytes: input_mlir_bytes,
      variants: variants,
      best_success_variant: best_success_variant
    }

    File.write(report_path, JSON.pretty_generate(report))
    JSON.parse(JSON.generate(report))
  end

  def profile_variant_to_mlir_hierarchy!(report_path:, variant_id:, top: nil, sample_seconds: 60)
    require 'stackprof'

    report_path = File.expand_path(report_path)
    work_dir = File.join(File.dirname(report_path), 'artifacts')
    FileUtils.mkdir_p(File.dirname(report_path))
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)

    import_dir = File.join(work_dir, 'fresh_import')
    raw_import = run_raw_core_import!(import_dir: import_dir)
    importer_run_seconds = raw_import.fetch(:elapsed_seconds)
    core_mlir_path = raw_import.fetch(:core_mlir_path)
    import_top = (top || raw_import.fetch(:top)).to_s
    input_mlir_path = File.join(work_dir, '00.input.core.mlir')
    core_mlir = File.read(core_mlir_path)
    File.write(input_mlir_path, core_mlir)
    input_mlir_bytes = core_mlir.bytesize

    variant = VARIANTS.find { |entry| entry.fetch(:id) == variant_id.to_s }
    raise ArgumentError, "Unknown variant: #{variant_id}" unless variant

    optimized = optimize_variant(
      variant: variant,
      index: 1,
      input_mlir_path: input_mlir_path,
      input_mlir_bytes: input_mlir_bytes,
      work_dir: work_dir
    )
    unless optimized.fetch(:success)
      report = {
        generated_at: Time.now.utc.iso8601,
        import_dir: import_dir,
        fresh_import_dir: import_dir,
        importer_run_seconds: importer_run_seconds,
        source_core_mlir_path: core_mlir_path,
        circt_verilog_command: raw_import.fetch(:circt_verilog_command),
        import_top: import_top,
        variant: optimized
      }
      File.write(report_path, JSON.pretty_generate(report))
      return JSON.parse(JSON.generate(report))
    end

    optimized_mlir = File.read(optimized.fetch(:optimized_mlir_path))

    import_result = nil
    import_circt_mlir_seconds = measure_seconds do
      import_result = RHDL::Codegen.import_circt_mlir(optimized_mlir, strict: false, top: import_top)
    end
    unless import_result.success?
      report = {
        generated_at: Time.now.utc.iso8601,
        import_dir: import_dir,
        fresh_import_dir: import_dir,
        importer_run_seconds: importer_run_seconds,
        source_core_mlir_path: core_mlir_path,
        circt_verilog_command: raw_import.fetch(:circt_verilog_command),
        import_top: import_top,
        import_circt_mlir_seconds: import_circt_mlir_seconds,
        variant: optimized.merge(
          stage: 'import_circt_mlir',
          import_diagnostics: Array(import_result.diagnostics).map { |diag| diagnostic_message(diag) }
        )
      }
      File.write(report_path, JSON.pretty_generate(report))
      return JSON.parse(JSON.generate(report))
    end

    raise_result = nil
    raise_circt_components_seconds = measure_seconds do
      raise_result = RHDL::Codegen.raise_circt_components(
        optimized_mlir,
        namespace: Module.new,
        top: import_top,
        strict: false
      )
    end
    unless raise_result.success?
      report = {
        generated_at: Time.now.utc.iso8601,
        import_dir: import_dir,
        fresh_import_dir: import_dir,
        importer_run_seconds: importer_run_seconds,
        source_core_mlir_path: core_mlir_path,
        circt_verilog_command: raw_import.fetch(:circt_verilog_command),
        import_top: import_top,
        import_circt_mlir_seconds: import_circt_mlir_seconds,
        raise_circt_components_seconds: raise_circt_components_seconds,
        imported_module_count: Array(import_result.modules).length,
        variant: optimized.merge(
          stage: 'raise_circt_components',
          raise_diagnostics: Array(raise_result.diagnostics).map { |diag| diagnostic_message(diag) }
        )
      }
      File.write(report_path, JSON.pretty_generate(report))
      return JSON.parse(JSON.generate(report))
    end

    component_class = raise_result.components.fetch(import_top) do
      raise "Raised components missing top #{import_top}"
    end
    top_name = component_class.verilog_module_name.to_s

    dump_path = File.join(File.dirname(report_path), "#{variant_id}.to_mlir_hierarchy.stackprof.dump")
    text_path = File.join(File.dirname(report_path), "#{variant_id}.to_mlir_hierarchy.stackprof.txt")
    exported_mlir_path = File.join(work_dir, format('01.%s.exported.mlir', variant_id))

    completed = false
    timed_out = false
    export_error = nil
    exported_mlir_bytes = nil
    profile_data = nil

    to_mlir_profiled_seconds = measure_seconds do
      begin
        StackProf.start(mode: :wall, raw: true, interval: 1_000)
        Timeout.timeout(sample_seconds) do
          exported_mlir = component_class.to_mlir_hierarchy(top_name: top_name)
          File.write(exported_mlir_path, exported_mlir)
          exported_mlir_bytes = exported_mlir.bytesize
          completed = true
        end
      rescue Timeout::Error
        timed_out = true
      rescue StandardError => e
        export_error = {
          'class' => e.class.name,
          'message' => e.message
        }
      ensure
        StackProf.stop
        profile_data = StackProf.results
      end
    end

    File.binwrite(dump_path, Marshal.dump(profile_data))
    text_stdout, text_stderr, text_status = Open3.capture3(
      Gem.bin_path('stackprof', 'stackprof'),
      '--text',
      dump_path
    )
    File.write(text_path, text_stdout) if text_status.success?

    report = {
      generated_at: Time.now.utc.iso8601,
      import_dir: import_dir,
      fresh_import_dir: import_dir,
      importer_run_seconds: importer_run_seconds,
      source_core_mlir_path: core_mlir_path,
      circt_verilog_command: raw_import.fetch(:circt_verilog_command),
      import_top: import_top,
      imported_module_count: Array(import_result.modules).length,
      import_circt_mlir_seconds: import_circt_mlir_seconds,
      raise_circt_components_seconds: raise_circt_components_seconds,
      raised_top_component: component_class.name || component_class.to_s,
      component_class: component_class.name,
      top_module: top_name,
      sample_seconds: sample_seconds,
      to_mlir_profiled_seconds: to_mlir_profiled_seconds,
      completed: completed,
      timed_out: timed_out,
      export_error: export_error,
      exported_mlir_path: completed ? exported_mlir_path : nil,
      exported_mlir_bytes: exported_mlir_bytes,
      stackprof_dump_path: dump_path,
      stackprof_text_path: text_status.success? ? text_path : nil,
      stackprof_text_error: text_status.success? ? nil : text_stderr,
      top_frames: extract_top_stackprof_frames(profile_data, limit: 15),
      variant: optimized
    }

    File.write(report_path, JSON.pretty_generate(report))
    JSON.parse(JSON.generate(report))
  end

  def profile_to_mlir_hierarchy!(report_path:, top: nil, sample_seconds: 60)
    require 'stackprof'

    report_path = File.expand_path(report_path)
    work_dir = File.join(File.dirname(report_path), 'artifacts')
    FileUtils.mkdir_p(File.dirname(report_path))
    FileUtils.rm_rf(work_dir)
    FileUtils.mkdir_p(work_dir)

    import_dir = File.join(work_dir, 'fresh_import')
    raw_import = run_raw_core_import!(import_dir: import_dir)
    importer_run_seconds = raw_import.fetch(:elapsed_seconds)
    core_mlir_path = raw_import.fetch(:core_mlir_path)
    import_top = (top || raw_import.fetch(:top)).to_s
    core_mlir = File.read(core_mlir_path)

    import_result = nil
    import_circt_mlir_seconds = measure_seconds do
      import_result = RHDL::Codegen.import_circt_mlir(core_mlir, strict: false, top: import_top)
    end
    unless import_result.success?
      raise "CIRCT import failed for #{import_top}: #{format_diagnostics(import_result.diagnostics)}"
    end

    raise_result = nil
    raise_circt_components_seconds = measure_seconds do
      raise_result = RHDL::Codegen.raise_circt_components(
        core_mlir,
        namespace: Module.new,
        top: import_top,
        strict: false
      )
    end
    unless raise_result.success?
      raise "CIRCT raise failed for #{import_top}: #{format_diagnostics(raise_result.diagnostics)}"
    end

    component_class = raise_result.components.fetch(import_top) do
      raise "Raised components missing top #{import_top}"
    end
    top_name = component_class.verilog_module_name.to_s

    dump_path = File.join(File.dirname(report_path), 'to_mlir_hierarchy.stackprof.dump')
    text_path = File.join(File.dirname(report_path), 'to_mlir_hierarchy.stackprof.txt')

    completed = false
    timed_out = false
    export_error = nil
    input_mlir_bytes = nil
    input_mlir_path = File.join(work_dir, '00.input.mlir')
    profile_data = nil

    to_mlir_profiled_seconds = measure_seconds do
      begin
        StackProf.start(mode: :wall, raw: true, interval: 1_000)
        Timeout.timeout(sample_seconds) do
          input_mlir = component_class.to_mlir_hierarchy(top_name: top_name)
          File.write(input_mlir_path, input_mlir)
          input_mlir_bytes = input_mlir.bytesize
          completed = true
        end
      rescue Timeout::Error
        timed_out = true
      rescue StandardError => e
        export_error = {
          'class' => e.class.name,
          'message' => e.message
        }
      ensure
        StackProf.stop
        profile_data = StackProf.results
      end
    end

    File.binwrite(dump_path, Marshal.dump(profile_data))
    text_stdout, text_stderr, text_status = Open3.capture3(
      Gem.bin_path('stackprof', 'stackprof'),
      '--text',
      dump_path
    )
    File.write(text_path, text_stdout) if text_status.success?

    report = {
      generated_at: Time.now.utc.iso8601,
      import_dir: import_dir,
      fresh_import_dir: import_dir,
      importer_run_seconds: importer_run_seconds,
      source_core_mlir_path: core_mlir_path,
      import_top: import_top,
      imported_module_count: Array(import_result.modules).length,
      import_circt_mlir_seconds: import_circt_mlir_seconds,
      raise_circt_components_seconds: raise_circt_components_seconds,
      raised_top_component: component_class.name || component_class.to_s,
      component_class: component_class.name,
      top_module: top_name,
      sample_seconds: sample_seconds,
      to_mlir_profiled_seconds: to_mlir_profiled_seconds,
      completed: completed,
      timed_out: timed_out,
      export_error: export_error,
      input_mlir_path: completed ? input_mlir_path : nil,
      input_mlir_bytes: input_mlir_bytes,
      stackprof_dump_path: dump_path,
      stackprof_text_path: text_status.success? ? text_path : nil,
      stackprof_text_error: text_status.success? ? nil : text_stderr,
      top_frames: extract_top_stackprof_frames(profile_data, limit: 15)
    }

    File.write(report_path, JSON.pretty_generate(report))
    JSON.parse(JSON.generate(report))
  end

  def run_raw_core_import!(import_dir:)
    importer = RHDL::Examples::SPARC64::Import::SystemImporter.new(
      reference_root: RHDL::Examples::SPARC64::Integration::ImportLoader::DEFAULT_REFERENCE_ROOT,
      top: RHDL::Examples::SPARC64::Integration::ImportLoader::DEFAULT_IMPORT_TOP,
      top_file: RHDL::Examples::SPARC64::Integration::ImportLoader::DEFAULT_IMPORT_TOP_FILE,
      output_dir: import_dir,
      keep_workspace: false,
      clean_output: true,
      strict: false,
      patches_dir: RHDL::Examples::SPARC64::Integration::ImportPatchSet.patches_dir(fast_boot: false),
      emit_runtime_json: false,
      progress: ->(_message) {}
    )

    report_path = File.join(import_dir, 'import_report.json')
    requested_mlir_path = File.join(import_dir, '.mixed_import', "#{importer.top}.core.mlir")

    import_result = nil
    circt_verilog_command = nil
    elapsed_seconds = measure_seconds do
      Dir.mktmpdir('rhdl_sparc64_matrix_import') do |workspace|
        resolved = importer.send(:resolve_sources, workspace: workspace)
        importer.send(:prepare_output_dir!)
        source_bundle = importer.send(:write_import_source_bundle, workspace: workspace, resolved: resolved)
        extra_tool_args = [
          '--allow-use-before-declare',
          '--ignore-unknown-modules',
          '--timescale=1ns/1ps',
          "--top=#{importer.top}"
        ] + Array(source_bundle.fetch(:tool_args))
        circt_verilog_command = RHDL::Codegen::CIRCT::Tooling.circt_verilog_import_command_string(
          verilog_path: source_bundle.fetch(:input_path),
          extra_args: extra_tool_args
        )
        import_result = importer.send(
          :run_import_task,
          mode: :verilog,
          mlir_path: requested_mlir_path,
          report_path: report_path,
          input_path: source_bundle.fetch(:input_path),
          extra_tool_args: source_bundle.fetch(:tool_args)
        )
      end
    end

    diagnostics = Array(import_result && import_result[:diagnostics])
    raise_diagnostics = Array(import_result && import_result[:raise_diagnostics])
    unless import_result && import_result[:success]
      message = (diagnostics + raise_diagnostics).join("\n")
      raise "Fresh SPARC64 raw core import failed: #{message}"
    end

    core_mlir_path = requested_mlir_path
    core_mlir_path = File.expand_path(core_mlir_path)
    raise "Missing raw core MLIR at #{core_mlir_path}" unless File.file?(core_mlir_path)

    {
      elapsed_seconds: elapsed_seconds,
      core_mlir_path: core_mlir_path,
      report_path: report_path,
      circt_verilog_command: circt_verilog_command,
      top: importer.top
    }
  end

  def run_variant(variant:, index:, input_mlir_path:, input_mlir_bytes:, work_dir:, import_top:)
    result = optimize_variant(
      variant: variant,
      index: index,
      input_mlir_path: input_mlir_path,
      input_mlir_bytes: input_mlir_bytes,
      work_dir: work_dir
    )
    return result unless result.fetch(:success)

    variant_id = variant.fetch(:id)
    output_mlir_path = result.fetch(:optimized_mlir_path)
    optimized_mlir_bytes = result.fetch(:optimized_mlir_bytes)
    optimized_mlir = File.read(output_mlir_path)

    import_result = nil
    import_circt_mlir_seconds = measure_seconds do
      import_result = RHDL::Codegen.import_circt_mlir(optimized_mlir, strict: false, top: import_top)
    end
    unless import_result.success?
      return result.merge(
        stage: 'import_circt_mlir',
        optimized_mlir_bytes: optimized_mlir_bytes,
        bytes_saved: input_mlir_bytes - optimized_mlir_bytes,
        size_ratio: optimized_mlir_bytes.to_f / input_mlir_bytes.to_f,
        import_circt_mlir_seconds: import_circt_mlir_seconds,
        import_diagnostics: Array(import_result.diagnostics).map { |diag| diagnostic_message(diag) }
      )
    end

    raise_result = nil
    raise_circt_components_seconds = measure_seconds do
      raise_result = RHDL::Codegen.raise_circt_components(
        optimized_mlir,
        namespace: Module.new,
        top: import_top,
        strict: false
      )
    end
    unless raise_result.success?
      return result.merge(
        stage: 'raise_circt_components',
        optimized_mlir_bytes: optimized_mlir_bytes,
        bytes_saved: input_mlir_bytes - optimized_mlir_bytes,
        size_ratio: optimized_mlir_bytes.to_f / input_mlir_bytes.to_f,
        import_circt_mlir_seconds: import_circt_mlir_seconds,
        imported_module_count: Array(import_result.modules).length,
        raise_circt_components_seconds: raise_circt_components_seconds,
        raise_diagnostics: Array(raise_result.diagnostics).map { |diag| diagnostic_message(diag) }
      )
    end

    component_class = raise_result.components.fetch(import_top) do
      return result.merge(
        stage: 'raise_circt_components',
        optimized_mlir_bytes: optimized_mlir_bytes,
        bytes_saved: input_mlir_bytes - optimized_mlir_bytes,
        size_ratio: optimized_mlir_bytes.to_f / input_mlir_bytes.to_f,
        import_circt_mlir_seconds: import_circt_mlir_seconds,
        imported_module_count: Array(import_result.modules).length,
        raise_circt_components_seconds: raise_circt_components_seconds,
        raise_diagnostics: ["Raised components missing top #{import_top}"]
      )
    end

    top_name = component_class.verilog_module_name.to_s
    exported_mlir = nil
    to_mlir_hierarchy_seconds = measure_seconds do
      exported_mlir = component_class.to_mlir_hierarchy(top_name: top_name)
    end
    exported_mlir_path = File.join(work_dir, format('%02d.%s.exported.mlir', index, variant_id))
    File.write(exported_mlir_path, exported_mlir)

    result.merge(
      success: true,
      stage: 'to_mlir_hierarchy',
      optimized_mlir_bytes: optimized_mlir_bytes,
      bytes_saved: input_mlir_bytes - optimized_mlir_bytes,
      size_ratio: optimized_mlir_bytes.to_f / input_mlir_bytes.to_f,
      import_circt_mlir_seconds: import_circt_mlir_seconds,
      imported_module_count: Array(import_result.modules).length,
      raise_circt_components_seconds: raise_circt_components_seconds,
      raised_top_component: component_class.name || component_class.to_s,
      top_module: top_name,
      to_mlir_hierarchy_seconds: to_mlir_hierarchy_seconds,
      exported_mlir_path: exported_mlir_path,
      exported_mlir_bytes: exported_mlir.bytesize
    )
  rescue StandardError => e
    result.merge(
      stage: 'exception',
      error_class: e.class.name,
      error_message: e.message
    )
  end

  def optimize_variant(variant:, index:, input_mlir_path:, input_mlir_bytes:, work_dir:)
    variant_id = variant.fetch(:id)
    output_mlir_path = File.join(work_dir, format('%02d.%s.mlir', index, variant_id))
    cmd = ['circt-opt', *variant.fetch(:args), input_mlir_path, '-o', output_mlir_path]
    stdout, stderr, status = Open3.capture3(*cmd)

    result = {
      id: variant_id,
      label: variant.fetch(:label),
      args: variant.fetch(:args),
      command: Shellwords.join(cmd),
      optimized_mlir_path: output_mlir_path,
      success: false
    }

    return result.merge(stage: 'circt_opt', stdout: stdout, stderr: stderr) unless status.success?

    optimized_mlir_bytes = File.size(output_mlir_path)
    result.merge(
      success: true,
      stage: 'circt_opt',
      optimized_mlir_bytes: optimized_mlir_bytes,
      bytes_saved: input_mlir_bytes - optimized_mlir_bytes,
      size_ratio: optimized_mlir_bytes.to_f / input_mlir_bytes.to_f
    )
  rescue StandardError => e
    result.merge(
      stage: 'exception',
      error_class: e.class.name,
      error_message: e.message
    )
  end

  def read_import_report(import_dir)
    report_path = File.join(import_dir, 'import_report.json')
    return {} unless File.file?(report_path)

    JSON.parse(File.read(report_path))
  rescue JSON::ParserError
    {}
  end

  def measure_seconds
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  end

  def format_diagnostics(diagnostics)
    Array(diagnostics).map do |diagnostic|
      diagnostic_message(diagnostic)
    end.join("\n")
  end

  def diagnostic_message(diagnostic)
    if diagnostic.respond_to?(:message)
      diagnostic.message
    else
      diagnostic.to_s
    end
  end

  def extract_top_stackprof_frames(profile_data, limit:)
    frames = profile_data.is_a?(Hash) ? profile_data[:frames] || profile_data['frames'] : nil
    return [] unless frames.respond_to?(:values)

    frames.values
          .map do |frame|
            samples = frame[:samples] || frame['samples'] || frame[:total_samples] || frame['total_samples'] || 0
            next if samples.to_i <= 0

            {
              'name' => frame[:name] || frame['name'],
              'file' => frame[:file] || frame['file'],
              'line' => frame[:line] || frame['line'],
              'samples' => samples.to_i
            }
          end
          .compact
          .sort_by { |frame| -frame.fetch('samples') }
          .first(limit)
  end
end
