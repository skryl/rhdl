# frozen_string_literal: true

# Gate-level synthesis tasks

namespace :cli do
  namespace :gates do
    desc "[CLI] Export all components to gate-level IR (JSON netlists)"
    task :export do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(export: true).run
    end

    desc "[CLI] Export simcpu datapath to gate-level"
    task :simcpu do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(simcpu: true).run
    end

    desc "[CLI] Clean gate-level synthesis output"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(clean: true).run
    end

    desc "[CLI] Show gate-level synthesis statistics"
    task :stats do
      load_cli_tasks
      RHDL::CLI::Tasks::GatesTask.new(stats: true).run
    end
  end

  desc "[CLI] Export gate-level synthesis (alias for cli:gates:export)"
  task gates: 'cli:gates:export'
end
