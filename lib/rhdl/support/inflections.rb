# frozen_string_literal: true

module RHDL
  module Support
    module Inflections
      def underscore
        value = dup
        value.gsub!('::', '/')
        value.gsub!(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        value.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
        value.tr!('-', '_')
        value.downcase!
        value
      end
    end
  end
end

class String
  include RHDL::Support::Inflections unless method_defined?(:underscore)
end
