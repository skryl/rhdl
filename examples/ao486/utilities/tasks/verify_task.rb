# frozen_string_literal: true

require 'rhdl/cli/tasks/ao486_task'

module RHDL
  module Examples
    module AO486
      module Tasks
        class VerifyTask
          def run
            RHDL::CLI::Tasks::AO486Task.new(action: :verify).run
          end
        end
      end
    end
  end
end
