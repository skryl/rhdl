# frozen_string_literal: true

module RHDL
  module Codegen
    module FIRRTL
      module ArcToGpuLowering
        module Profiles
          module Cpu8bit
            module_function

            def required_inputs
              ArcToGpuLowering::REQUIRED_TOP_INPUTS
            end

            def required_outputs
              ArcToGpuLowering::REQUIRED_TOP_OUTPUTS
            end

            def prepare_source(source:, lowerer:)
              if ENV['RHDL_ARC_TO_GPU_OPT_ALL'] == '1'
                lowerer.optimize_arc_mlir_source(source)
              else
                source
              end
            end

            def pack_wide_scalars?(inferred_scalar_bits:)
              _ = inferred_scalar_bits
              false
            end

            def post_parse_transform(parsed:, lowerer:)
              _ = lowerer
              parsed
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
              lowerer.emit_metal_source(
                parsed: parsed,
                state_layout: state_layout,
                metal_entry: metal_entry,
                scalar_bits: scalar_bits,
                pack_wide_scalars: pack_wide_scalars,
                gem_kernel_interpreter: gem_kernel_interpreter,
                use_state_snapshot: false,
                split_post_comb_liveness: true,
                trust_state_masks: true,
                load_state_in_comb_fn: true,
                eval_always_inline: true,
                schedule_aware_emit: true
              )
            end
          end
        end
      end
    end
  end
end
