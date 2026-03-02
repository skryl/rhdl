# frozen_string_literal: true

module RHDL
  module Import
    class Result
      attr_reader :status,
                  :out_dir,
                  :report_path,
                  :report,
                  :errors,
                  :diagnostics,
                  :converted_modules,
                  :failed_modules

      def self.success(out_dir:, report_path:, report: nil, errors: [], diagnostics: [], converted_modules: [], failed_modules: [])
        new(
          status: :success,
          out_dir: out_dir,
          report_path: report_path,
          report: report,
          errors: errors,
          diagnostics: diagnostics,
          converted_modules: converted_modules,
          failed_modules: failed_modules
        )
      end

      def self.failure(out_dir:, report_path:, report: nil, errors: [], diagnostics: [], converted_modules: [], failed_modules: [])
        new(
          status: :failure,
          out_dir: out_dir,
          report_path: report_path,
          report: report,
          errors: errors,
          diagnostics: diagnostics,
          converted_modules: converted_modules,
          failed_modules: failed_modules
        )
      end

      def initialize(status:, out_dir:, report_path:, report: nil, errors: [], diagnostics: [], converted_modules: [], failed_modules: [])
        @status = status.to_sym
        @out_dir = out_dir
        @report_path = report_path
        @report = report
        @errors = Array(errors).dup
        @diagnostics = Array(diagnostics).dup
        @converted_modules = Array(converted_modules).dup
        @failed_modules = Array(failed_modules).dup
      end

      def success?
        status == :success
      end

      def failure?
        !success?
      end

      def to_h
        {
          status: status,
          out_dir: out_dir,
          report_path: report_path,
          report: report,
          errors: errors,
          diagnostics: diagnostics,
          converted_modules: converted_modules,
          failed_modules: failed_modules
        }
      end
    end
  end
end
