# frozen_string_literal: true

require 'rhdl/sim/native/abi'
require 'rhdl/sim/native/mlir/arcilator/debug'

module RHDL
  module Sim
    module Native
      module MLIR
        module Arcilator
          module Runtime
            module_function

            def open(lib_path:, config: nil, sub_cycles: 14, signal_widths_by_name: {}, signal_widths_by_idx: nil,
                     backend_label: 'arcilator')
              simulator = RHDL::Sim::Native::ABI::Simulator.new(
                lib_path: lib_path,
                config: config,
                sub_cycles: sub_cycles,
                signal_widths_by_name: signal_widths_by_name,
                signal_widths_by_idx: signal_widths_by_idx,
                backend_label: backend_label
              )
              Debug.attach(simulator)
            end
          end
        end
      end
    end
  end
end
