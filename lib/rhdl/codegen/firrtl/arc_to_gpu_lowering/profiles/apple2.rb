# frozen_string_literal: true

module RHDL
  module Codegen
    module FIRRTL
      module ArcToGpuLowering
        module Profiles
          module Apple2
            module_function

            def required_inputs
              ArcToGpuLowering::REQUIRED_APPLE2_INPUTS
            end

            def required_outputs
              ArcToGpuLowering::REQUIRED_APPLE2_OUTPUTS
            end

            def prepare_source(source:, lowerer:)
              lowerer.optimize_arc_mlir_source(source)
            end

            def pack_wide_scalars?(inferred_scalar_bits:)
              inferred_scalar_bits > 32
            end

            def post_parse_transform(parsed:, lowerer:)
              if ENV['RHDL_ARC_TO_GPU_FLATTEN'] == '1'
                lowerer.flatten_simple_arc_calls(parsed, max_ops: 12, max_depth: 2)
              else
                parsed
              end
            end

            def emit_metal_source(
              lowerer:,
              parsed:,
              state_layout:,
              metal_entry:,
              scalar_bits:,
              pack_wide_scalars:,
              gem_kernel_interpreter: false
            )
              _ = gem_kernel_interpreter
              lowerer.with_scalar_config(scalar_bits, pack_wide_scalars: pack_wide_scalars) do
                lowerer.emit_metal_source_apple2(
                  parsed: parsed,
                  state_layout: state_layout,
                  metal_entry: metal_entry
                )
              end
            end
          end
        end
      end
    end
  end
end
