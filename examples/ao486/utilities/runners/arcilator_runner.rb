# frozen_string_literal: true

require_relative 'backend_runner'
require_relative '../import/cpu_parity_arcilator_runtime'

module RHDL
  module Examples
    module AO486
      class ArcilatorRunner < BackendRunner
        def self.build_from_cleaned_mlir(mlir_text, work_dir:)
          runtime = RHDL::Examples::AO486::Import::CpuParityArcilatorRuntime.build_from_cleaned_mlir(
            mlir_text,
            work_dir: work_dir
          )
          new(import_runtime: runtime, headless: true)
        end

        def initialize(import_runtime: nil, **kwargs)
          super(backend: :arcilator, import_runtime: import_runtime, **kwargs)
        end
      end
    end
  end
end
