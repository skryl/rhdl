# frozen_string_literal: true

require_relative 'backend_runner'
require_relative '../import/cpu_parity_verilator_runtime'

module RHDL
  module Examples
    module AO486
      class VerilatorRunner < BackendRunner
        def self.build_from_cleaned_mlir(mlir_text, work_dir:)
          runtime = RHDL::Examples::AO486::Import::CpuParityVerilatorRuntime.build_from_cleaned_mlir(
            mlir_text,
            work_dir: work_dir
          )
          new(import_runtime: runtime, headless: true)
        end

        def initialize(import_runtime: nil, **kwargs)
          super(backend: :verilator, import_runtime: import_runtime, **kwargs)
        end
      end
    end
  end
end
