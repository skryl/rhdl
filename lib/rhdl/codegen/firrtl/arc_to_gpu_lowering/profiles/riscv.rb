# frozen_string_literal: true

module RHDL
  module Codegen
    module FIRRTL
      module ArcToGpuLowering
        module Profiles
          module Riscv
            module_function

            def required_inputs
              ArcToGpuLowering::REQUIRED_RISCV_INPUTS
            end

            def required_outputs
              ArcToGpuLowering::REQUIRED_RISCV_OUTPUTS
            end

            def runtime_input_names
              required_inputs
            end

            def runtime_output_names
              ArcToGpuLowering::RUNTIME_RISCV_OUTPUTS
            end

            def prepare_source(source:, lowerer:)
              lowerer.optimize_arc_mlir_source(source)
            end

            def pack_wide_scalars?(inferred_scalar_bits:)
              _ = inferred_scalar_bits
              true
            end

            def narrow_scalar_types?
              true
            end

            def post_parse_transform(parsed:, lowerer:)
              transformed = lowerer.flatten_simple_arc_calls(
                parsed,
                max_ops: flatten_max_ops,
                max_depth: flatten_max_depth
              )
              transformed = lowerer.fold_constant_array_gets(transformed)
              lowerer.prune_unreachable_functions(transformed)
            end

            def flatten_max_ops
              96
            end

            def flatten_max_depth
              6
            end

            def dirty_settle_enabled?
              false
            end

            def scheduled_emit_enabled?
              false
            end

            def split_low_wdata_eval_enabled?
              true
            end

            def split_high_data_addr_eval_enabled?
              true
            end

            def split_low_data_addr_eval_enabled?
              true
            end

            def schedule_mode
              scheduled_emit_enabled? ? 'levelized' : 'legacy'
            end

            def fast_low_wdata_mode
              split_low_wdata_eval_enabled? ? 'split' : 'inline'
            end

            def fast_high_data_addr_mode
              split_high_data_addr_eval_enabled? ? 'split' : 'inline'
            end

            def fast_low_data_addr_mode
              split_low_data_addr_eval_enabled? ? 'split' : 'inline'
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
              lowerer.with_scalar_config(
                scalar_bits,
                pack_wide_scalars: pack_wide_scalars,
                narrow_scalar_types: narrow_scalar_types?
              ) do
                lowerer.emit_metal_source_riscv(
                  parsed: parsed,
                  state_layout: state_layout,
                  metal_entry: metal_entry,
                  dirty_settle_enabled: dirty_settle_enabled?,
                  schedule_aware_emit: scheduled_emit_enabled?,
                  split_low_wdata_eval: split_low_wdata_eval_enabled?,
                  split_high_data_addr_eval: split_high_data_addr_eval_enabled?,
                  split_low_data_addr_eval: split_low_data_addr_eval_enabled?,
                  runtime_output_names: runtime_output_names
                )
              end
            end
          end
        end
      end
    end
  end
end
