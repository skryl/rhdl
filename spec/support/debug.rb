# Debug output helper
# Enable debug output by setting RHDL_DEBUG=1 environment variable
#
# Usage:
#   Debug.log("message")  # Only prints when RHDL_DEBUG=1
#   Debug.enabled?        # Check if debug mode is enabled
#
module Debug
  class << self
    def enabled?
      ENV['RHDL_DEBUG'] == '1'
    end

    def log(message)
      puts "[DEBUG] #{message}" if enabled?
    end

    def enable!
      ENV['RHDL_DEBUG'] = '1'
    end

    def disable!
      ENV['RHDL_DEBUG'] = nil
    end
  end
end
