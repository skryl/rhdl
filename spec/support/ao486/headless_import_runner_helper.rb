# frozen_string_literal: true

require_relative '../../../examples/ao486/utilities/runners/headless_runner'

module AO486SpecSupport
  module HeadlessImportRunnerHelper
    def build_ao486_import_headless_runner(cleaned_mlir, mode:, sim: :compile, work_dir: nil)
      RHDL::Examples::AO486::HeadlessRunner.build_from_cleaned_mlir(
        cleaned_mlir,
        mode: mode,
        sim: sim,
        headless: true,
        work_dir: work_dir
      )
    end
  end
end
