# frozen_string_literal: true

module RHDL
  module Codegen
    module CIRCT
      module ImportCleanup
        module_function

        CleanupResult = Struct.new(:success, :cleaned_text, :import_result, keyword_init: true) do
          def success?
            !!success
          end
        end

        # Normalize imported CIRCT MLIR into pure core dialects by parsing it
        # through the existing CIRCT importer and re-emitting structural MLIR.
        # This strips surviving LLHD signal/time overlays from circt-verilog
        # imports before downstream tools such as firtool consume the artifact.
        def parse_imported_core_mlir(text, strict: true, top: nil, extern_modules: [], resolve_forward_refs: false)
          RHDL::Codegen.import_circt_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: resolve_forward_refs
          )
        end

        def emit_cleaned_core_mlir(modules)
          RHDL::Codegen::CIRCT::MLIR.generate(modules)
        end

        def cleanup_imported_core_mlir(text, strict: true, top: nil, extern_modules: [])
          needs_cleanup = text.include?('llhd.') ||
                          text.include?('hw.array_inject') ||
                          text.include?('hw.aggregate_constant') ||
                          text.include?('seq.clock_inv') ||
                          text.match?(/!hw\.array</)
          return success_result(text) unless needs_cleanup

          import_result = parse_imported_core_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: true
          )
          return failure_result(import_result.diagnostics) unless import_result.success?

          cleaned_text = emit_cleaned_core_mlir(import_result.modules)

          CleanupResult.new(
            success: !cleaned_text.to_s.include?('llhd.'),
            cleaned_text: cleaned_text,
            import_result: import_result
          )
        end

        def success_result(text)
          CleanupResult.new(
            success: true,
            cleaned_text: text,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: [])
          )
        end

        def failure_result(diagnostics)
          CleanupResult.new(
            success: false,
            cleaned_text: nil,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: diagnostics)
          )
        end

      end
    end
  end
end
