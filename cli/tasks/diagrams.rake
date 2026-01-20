# frozen_string_literal: true

# Diagram generation tasks

namespace :cli do
  namespace :diagrams do
    desc "[CLI] Generate component-level diagrams (simple block view)"
    task :component do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'component').run
    end

    desc "[CLI] Generate hierarchical diagrams (with subcomponents)"
    task :hierarchical do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'hierarchical').run
    end

    desc "[CLI] Generate gate-level diagrams (primitive gates and flip-flops)"
    task :gate do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(all: true, mode: 'gate').run
    end

    desc "[CLI] Generate all circuit diagrams (component, hierarchical, gate)"
    task generate: [:component, :hierarchical, :gate] do
      load_cli_tasks
      # Generate README after all modes are done
      task = RHDL::CLI::Tasks::DiagramTask.new(all: true)
      task.send(:generate_readme)
      puts
      puts "=" * 60
      puts "Done! Diagrams generated in: #{RHDL::CLI::Config.diagrams_dir}"
      puts "=" * 60
    end

    desc "[CLI] Clean all generated diagrams"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::DiagramTask.new(clean: true).run
    end
  end

  desc "[CLI] Generate all diagrams (alias for cli:diagrams:generate)"
  task diagrams: 'cli:diagrams:generate'
end
