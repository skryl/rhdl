# Extended Behavior DSL - now merged into Behavior
#
# This file exists for backwards compatibility.
# All extended behavior features (local, case_of, if_chain) are now
# part of the main Behavior module.
#
# Usage: Include RHDL::DSL::Behavior instead of ExtendedBehavior

require_relative 'behavior'

module RHDL
  module DSL
    # ExtendedBehavior is now an alias for Behavior
    # All features have been merged into the base Behavior module
    module ExtendedBehavior
      def self.included(base)
        base.include(Behavior)
      end
    end
  end
end
