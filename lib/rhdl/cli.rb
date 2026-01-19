# frozen_string_literal: true

# RHDL CLI module - provides reusable task classes for both binary and rake
module RHDL
  module CLI
  end
end

require_relative 'cli/config'
require_relative 'cli/task'
require_relative 'cli/tasks/diagram_task'
require_relative 'cli/tasks/export_task'
require_relative 'cli/tasks/gates_task'
require_relative 'cli/tasks/tui_task'
require_relative 'cli/tasks/apple2_task'
require_relative 'cli/tasks/deps_task'
require_relative 'cli/tasks/benchmark_task'
require_relative 'cli/tasks/generate_task'
