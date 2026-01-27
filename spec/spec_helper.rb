begin
  require "bundler/setup"
rescue Bundler::GemNotFound, Bundler::BundlerError
  # Bundler not fully set up, continue without it
end

require "rhdl"

# Require all support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

require 'timeout'

# Test timeouts (can be overridden with env vars)
# - RSPEC_TIMEOUT: Default timeout for regular tests (default: 10 seconds)
# - RSPEC_SLOW_TIMEOUT: Timeout for tests tagged :slow (default: 60 seconds)
# - Set to 0 to disable timeout
#
# To exclude slow tests: rspec --tag ~slow
# To run only slow tests: rspec --tag slow
RSPEC_TEST_TIMEOUT = ENV.fetch('RSPEC_TIMEOUT', 10).to_i
RSPEC_SLOW_TIMEOUT = ENV.fetch('RSPEC_SLOW_TIMEOUT', 60).to_i

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

  # Exclude slow tests by default (run with: rspec --tag slow to include them)
  config.filter_run_excluding slow: true unless ENV['INCLUDE_SLOW_TESTS']

  # Seed for reproducibility (use TEST_ENV_NUMBER for parallel runs)
  config.seed = ENV.fetch('RSPEC_SEED', srand % 0xFFFF).to_i

  # Fail tests that take longer than timeout (default: 10s, slow tests: 60s)
  # Skip timeout if timeout value is 0
  # Custom timeout can be specified via example.metadata[:timeout]
  config.around(:each) do |example|
    timeout = if example.metadata[:timeout]
      example.metadata[:timeout]
    elsif example.metadata[:slow]
      RSPEC_SLOW_TIMEOUT
    else
      RSPEC_TEST_TIMEOUT
    end

    if timeout > 0
      Timeout.timeout(timeout, Timeout::Error, "Test exceeded #{timeout} second timeout") do
        example.run
      end
    else
      example.run
    end
  end
end
