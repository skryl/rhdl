# frozen_string_literal: true

require_relative 'coverage_manifest'

module RHDL
  module Examples
    module AO486
      module Unit
        module SourceFileDefinition
          module_function

          def define!(source_relative_path:, module_names:)
            normalized_source = source_relative_path.to_s
            normalized_modules = Array(module_names).map(&:to_s).sort.freeze
            expected_modules = RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILES.fetch(normalized_source)

            raise ArgumentError, "Coverage mismatch for #{normalized_source}" unless normalized_modules == expected_modules

            RSpec.describe "AO486 CPU unit #{normalized_source}",
                           :ao486,
                           :ao486_unit,
                           source_relative_path: normalized_source do
              metadata[:ao486_unit_modules] = normalized_modules

              if (driver = RHDL::Examples::AO486::Unit::SourceFileDefinition.driver)
                driver.install_examples(
                  self,
                  source_relative_path: normalized_source,
                  module_names: normalized_modules
                )
              else
                it 'locks the mirrored module list' do
                  expect(RHDL::Examples::AO486::Unit::COVERED_SOURCE_FILES.fetch(normalized_source)).to eq(normalized_modules)
                end
              end
            end
          end

          def driver
            if Object.const_defined?(:AO486UnitSupport) && AO486UnitSupport.const_defined?(:SourceFileDriver, false)
              candidate = AO486UnitSupport.const_get(:SourceFileDriver, false)
              return candidate if candidate.respond_to?(:install_examples)
            end

            if RHDL::Examples::AO486::Unit.const_defined?(:SourceFileDriver, false)
              candidate = RHDL::Examples::AO486::Unit.const_get(:SourceFileDriver, false)
              return candidate if candidate.respond_to?(:install_examples)
            end

            nil
          rescue NameError
            nil
          end
        end
      end
    end
  end
end
