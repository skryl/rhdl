# HDL Signal Probing and Debugging
# Provides waveform capture, breakpoints, and debugging features

require_relative 'debug/signal_probe'
require_relative 'debug/waveform_capture'
require_relative 'debug/breakpoint'
require_relative 'debug/watchpoint'
require_relative 'debug/debug_simulator'

module RHDL
  module Debug
    # Debug logging helper compatible with spec/support/debug.rb
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
end