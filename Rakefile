# Try to load bundler, but don't fail if it's not available
begin
  require "bundler/gem_tasks"
rescue LoadError
  # Bundler not available, skip gem tasks
end

# RSpec tasks
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  desc "Run RSpec tests (rspec not available via bundler, use bin/test)"
  task :spec do
    sh "bin/test"
  end
end

# RuboCop tasks (optional)
begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
  task default: %i[spec rubocop]
rescue LoadError
  # RuboCop not available
  task default: :spec
end

desc "Run 6502 CPU tests"
task :spec_6502 do
  sh "bin/test spec/examples/mos6502/ --format progress"
end

desc "Run all tests with documentation format"
task :spec_doc do
  sh "bin/test --format documentation"
end
