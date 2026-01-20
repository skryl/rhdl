# frozen_string_literal: true

# Combined CLI tasks

namespace :cli do
  desc "[CLI] Generate all output files (diagrams + HDL exports)"
  task generate_all: ['cli:diagrams:generate', 'cli:hdl:export']

  desc "[CLI] Clean all generated files"
  task clean_all: ['cli:diagrams:clean', 'cli:hdl:clean', 'cli:gates:clean']

  desc "[CLI] Regenerate all output files (clean + generate)"
  task regenerate: ['cli:clean_all', 'cli:generate_all']
end
