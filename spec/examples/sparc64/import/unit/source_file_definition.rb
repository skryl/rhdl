# frozen_string_literal: true

require_relative 'coverage_manifest'

module RHDL
  module Examples
    module SPARC64
      module Unit
        module SourceFileDefinition
          module_function

          def define!(source_relative_path:, module_names:)
            normalized_source = source_relative_path.to_s
            normalized_modules = Array(module_names).map(&:to_s).sort.freeze
            expected_modules = RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILES.fetch(normalized_source)

            raise ArgumentError, "Coverage mismatch for #{normalized_source}" unless normalized_modules == expected_modules

            RSpec.describe "SPARC64 W1 unit #{normalized_source}",
                           :sparc64,
                           :sparc64_unit,
                           source_relative_path: normalized_source do
              metadata[:sparc64_unit_modules] = normalized_modules

              if (driver = RHDL::Examples::SPARC64::Unit::SourceFileDefinition.driver)
                driver.install_examples(
                  self,
                  source_relative_path: normalized_source,
                  module_names: normalized_modules
                )
              else
                it 'locks the mirrored module list' do
                  expect(RHDL::Examples::SPARC64::Unit::COVERED_SOURCE_FILES.fetch(normalized_source)).to eq(normalized_modules)
                end
              end
            end
          end

          def driver
            return nil unless RHDL::Examples::SPARC64::Unit.const_defined?(:SourceFileDriver, false)

            candidate = RHDL::Examples::SPARC64::Unit.const_get(:SourceFileDriver, false)
            return candidate if candidate.respond_to?(:install_examples)

            nil
          rescue NameError
            nil
          end
        end
      end
    end
  end
end
