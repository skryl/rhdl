# frozen_string_literal: true

require 'rhdl/cli/tasks/ao486_task'

module RHDL
  module Examples
    module AO486
      module Tasks
        class ImportTask
          attr_reader :options

          def initialize(options = {})
            @options = options
          end

          def run
            RHDL::CLI::Tasks::AO486Task.new(options.merge(action: :import)).run
          end
        end
      end
    end
  end
end
