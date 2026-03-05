# frozen_string_literal: true

require_relative 'arc_to_gpu_lowering'

module RHDL
  module Codegen
    module FIRRTL
      # Local Synth/HW -> SynthToGPU lowering stage.
      #
      # This reuses the existing GPU codegen backend but accepts synthesized
      # hw/seq/comb/synth MLIR directly, without requiring arc.define wrappers.
      module SynthToGpuLowering
        class LoweringError < StandardError; end

        module_function

        def lower(synth_mlir_path:, gpu_mlir_path:, metadata_path: nil, metal_source_path: nil, profile: :riscv_netlist)
          ArcToGpuLowering.lower(
            arc_mlir_path: synth_mlir_path,
            gpu_mlir_path: gpu_mlir_path,
            metadata_path: metadata_path,
            metal_source_path: metal_source_path,
            profile: profile,
            require_arc_define: false,
            metadata_version: 'SynthToGpuLoweringV1',
            lowering_label: 'SynthToGpuLowering'
          )
        rescue ArcToGpuLowering::LoweringError => e
          raise LoweringError, e.message
        end
      end
    end
  end
end
