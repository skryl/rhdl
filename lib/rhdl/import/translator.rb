# frozen_string_literal: true

require_relative "translator/module_emitter"

module RHDL
  module Import
    module Translator
      class << self
        def translate(modules)
          Array(modules).map do |mapped_module|
            module_hash = mapped_module.is_a?(Hash) ? mapped_module : {}
            {
              name: value_for(module_hash, :name).to_s,
              source: ModuleEmitter.emit(module_hash)
            }
          end
        end

        def translate_module(mapped_module)
          ModuleEmitter.emit(mapped_module)
        end

        private

        def value_for(hash, key)
          return nil unless hash.is_a?(Hash)

          return hash[key] if hash.key?(key)

          string_key = key.to_s
          return hash[string_key] if hash.key?(string_key)

          symbol_key = key.to_sym
          return hash[symbol_key] if hash.key?(symbol_key)

          nil
        end
      end
    end
  end
end
