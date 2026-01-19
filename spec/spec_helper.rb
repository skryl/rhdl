begin
  require "bundler/setup"
rescue Bundler::GemNotFound, Bundler::BundlerError
  # Bundler not fully set up, continue without it
end

require "rhdl"

# Require all support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  # Use process-specific status file for parallel test runs
  if ENV['TEST_ENV_NUMBER']
    config.example_status_persistence_file_path = ".rspec_status#{ENV['TEST_ENV_NUMBER']}"
  else
    config.example_status_persistence_file_path = ".rspec_status"
  end

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Random ordering helps detect order-dependent tests
  config.order = :random

  # Seed for reproducibility (use TEST_ENV_NUMBER for parallel runs)
  config.seed = ENV.fetch('RSPEC_SEED', srand % 0xFFFF).to_i
end
