begin
  require "bundler/setup"
rescue Bundler::GemNotFound, Bundler::BundlerError
  # Bundler not fully set up, continue without it
end

require "rhdl"

# Require all support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

require 'timeout'

# Default test timeout (can be overridden with RSPEC_TIMEOUT env var)
RSPEC_TEST_TIMEOUT = ENV.fetch('RSPEC_TIMEOUT', 10).to_i

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

  # Fail tests that take longer than RSPEC_TEST_TIMEOUT seconds (default: 10)
  # Skip timeout if RSPEC_TIMEOUT=0 or running in debug mode
  config.around(:each) do |example|
    if RSPEC_TEST_TIMEOUT > 0
      Timeout.timeout(RSPEC_TEST_TIMEOUT, Timeout::Error, "Test exceeded #{RSPEC_TEST_TIMEOUT} second timeout") do
        example.run
      end
    else
      example.run
    end
  end
end
