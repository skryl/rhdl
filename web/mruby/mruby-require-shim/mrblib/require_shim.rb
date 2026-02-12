# frozen_string_literal: true

unless Object.const_defined?(:LoadError)
  Object.const_set(:LoadError, Class.new(StandardError))
end

module Kernel
  unless method_defined?(:__rhdl_require_stack)
    def __rhdl_require_stack
      if $__rhdl_require_stack
        $__rhdl_require_stack
      else
        $__rhdl_require_stack = []
      end
    end
    private :__rhdl_require_stack
  end

  unless method_defined?(:__rhdl_require_builtin_feature?)
    def __rhdl_require_builtin_feature?(feature)
      case feature.to_s
      when 'set'
        Object.const_defined?(:Set)
      else
        false
      end
    end
    private :__rhdl_require_builtin_feature?
  end

  unless method_defined?(:__rhdl_loaded_features)
    def __rhdl_loaded_features
      if $LOADED_FEATURES
        $LOADED_FEATURES
      else
        $LOADED_FEATURES = []
      end
    end
    private :__rhdl_loaded_features
  end

  unless method_defined?(:__rhdl_load_path)
    def __rhdl_load_path
      if $LOAD_PATH
        $LOAD_PATH
      else
        $LOAD_PATH = []
      end
    end
    private :__rhdl_load_path
  end

  unless method_defined?(:__rhdl_require_candidates)
    def __rhdl_require_candidates(feature)
      value = feature.to_s
      return [value] if value.end_with?('.rb')

      ["#{value}.rb", value]
    end
    private :__rhdl_require_candidates
  end

  unless method_defined?(:__rhdl_require_join)
    def __rhdl_require_join(root, child)
      return child if child.start_with?('/')
      return child if root.nil? || root.empty? || root == '.'
      return "#{root}#{child}" if root.end_with?('/')

      "#{root}/#{child}"
    end
    private :__rhdl_require_join
  end

  unless method_defined?(:__rhdl_require_find_path)
    def __rhdl_require_find_path(feature, relative_base = nil)
      load_path = __rhdl_load_path
      load_path << '.' unless load_path.include?('.')
      load_path << '/' unless load_path.include?('/')

      roots = []
      roots << relative_base if relative_base && !relative_base.empty?
      roots.concat(load_path)
      roots << '.'
      roots << '/'

      __rhdl_require_candidates(feature).each do |name|
        roots.uniq.each do |root|
          candidate = __rhdl_require_join(root, name)
          return candidate if File.file?(candidate)
        end
      end

      feature_name = feature.to_s
      unless feature_name.start_with?('/')
        fallback_base = "/rhdl/#{feature_name}"
        return "#{fallback_base}.rb" if File.file?("#{fallback_base}.rb")
        return fallback_base if File.file?(fallback_base)
      end

      nil
    end
    private :__rhdl_require_find_path
  end

  unless method_defined?(:require)
    def require(feature)
      loaded = __rhdl_loaded_features
      feature_name = feature.to_s
      if __rhdl_require_builtin_feature?(feature_name)
        return false if loaded.include?(feature_name)

        loaded << feature_name
        return true
      end

      path = __rhdl_require_find_path(feature_name)
      raise LoadError, "cannot load such file -- #{feature_name}" unless path

      absolute = File.expand_path(path)
      return false if loaded.include?(absolute)

      previous_require_dir = $__rhdl_require_dir
      stack = __rhdl_require_stack
      stack << absolute
      $__rhdl_require_dir = File.dirname(absolute)
      begin
        if respond_to?(:load)
          load(absolute)
        else
          source = File.read(absolute)
          eval(source, binding, absolute)
        end
      ensure
        stack.pop
        $__rhdl_require_dir = previous_require_dir
      end
      loaded << absolute
      true
    end
  end

  unless method_defined?(:require_relative)
    def require_relative(feature)
      stack = __rhdl_require_stack
      current_file = stack.empty? ? nil : stack[-1]
      base = current_file ? File.dirname(current_file) : $__rhdl_require_dir
      path = __rhdl_require_find_path(feature, base)
      raise LoadError, "cannot load such file -- #{feature}" unless path

      require(path)
    end
  end
end
