# frozen_string_literal: true

module RHDL
  module Support
    # Lightweight replacement for ActiveSupport::Concern covering:
    # - `included do ... end`
    # - `class_methods do ... end`
    # - concern dependency inclusion via `include OtherConcern`
    module Concern
      def self.extended(base)
        base.instance_variable_set(:@_rhdl_concern_included_block, nil)
        base.instance_variable_set(:@_rhdl_concern_class_methods, nil)
        base.instance_variable_set(:@_rhdl_concern_dependencies, [])
      end

      def append_features(base)
        # If we're being included into another concern, register as dependency.
        if base.instance_variable_defined?(:@_rhdl_concern_dependencies)
          deps = base.instance_variable_get(:@_rhdl_concern_dependencies)
          deps << self unless deps.include?(self)
          return false
        end

        Array(@_rhdl_concern_dependencies).each { |dep| base.include(dep) }
        super

        if (class_methods_mod = @_rhdl_concern_class_methods)
          base.extend(class_methods_mod)
        end

        if (included_block = @_rhdl_concern_included_block)
          base.class_eval(&included_block)
        end
      end

      def included(base = nil, &block)
        if base.nil?
          @_rhdl_concern_included_block = block
        else
          super
        end
      end

      def class_methods(&block)
        @_rhdl_concern_class_methods ||= Module.new
        @_rhdl_concern_class_methods.module_eval(&block)
      end
    end
  end
end
