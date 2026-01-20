# frozen_string_literal: true

# HDL export tasks

namespace :cli do
  namespace :hdl do
    desc "[CLI] Export all DSL components to Verilog (lib/ and examples/)"
    task export: [:export_lib, :export_examples] do
      puts
      puts "=" * 50
      puts "HDL export complete!"
      load_cli_tasks
      puts "Verilog files: #{RHDL::CLI::Config.verilog_dir}"
    end

    desc "[CLI] Export lib/ DSL components to Verilog"
    task :export_lib do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'lib').run
    end

    desc "[CLI] Export examples/ components to Verilog"
    task :export_examples do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'examples').run
    end

    desc "[CLI] Export Verilog files"
    task :verilog do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(all: true, scope: 'lib').run
    end

    desc "[CLI] Clean all generated HDL files"
    task :clean do
      load_cli_tasks
      RHDL::CLI::Tasks::ExportTask.new(clean: true).run
    end
  end

  desc "[CLI] Export all HDL (alias for cli:hdl:export)"
  task hdl: 'cli:hdl:export'
end
