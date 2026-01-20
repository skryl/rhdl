# frozen_string_literal: true

# =============================================================================
# RHDL Rakefile
# =============================================================================
#
# All rake tasks are defined in cli/tasks/*.rake files.
# This file only handles loading and provides helper methods.

# Try to load bundler, but don't fail if it's not available
begin
  require "bundler/gem_tasks"
rescue LoadError
  # Bundler not available, skip gem tasks
end

# Project root constant (used by task files)
RHDL_ROOT = __dir__

# Load CLI tasks for shared functionality
def load_cli_tasks
  require_relative 'lib/rhdl/cli'
end

# Load all rake task files from cli/tasks/
Dir.glob(File.join(__dir__, 'cli', 'tasks', '*.rake')).sort.each do |task_file|
  load task_file
end
