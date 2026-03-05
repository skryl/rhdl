# frozen_string_literal: true

require_relative 'metal_runner'

module RHDL
  module Examples
    module RISCV
      # Experimental Metal runner that netlistizes the Arc comb graph through
      # CIRCT synth(AIG) before ArcToGPU codegen.
      class RiscvNetlistRunner < MetalRunner
        BUILD_VARIANT = 'riscv_netlist'.freeze
        SHARED_LIB_NAME = 'libriscv_netlist_sim.so'.freeze

        def initialize(mem_size: Memory::DEFAULT_SIZE, instances: nil, core_specialize: nil)
          super(
            mem_size: mem_size,
            instances: instances,
            core_specialize: core_specialize,
            arc_to_gpu_profile: :riscv_netlist,
            build_variant: BUILD_VARIANT,
            shared_lib_name: SHARED_LIB_NAME,
            backend_symbol: :riscv_netlist,
            simulator_type_symbol: :hdl_metal_riscv_netlist
          )
        end
      end
    end
  end
end
