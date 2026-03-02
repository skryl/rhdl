# frozen_string_literal: true

require "shellwords"

module RHDL
  module Import
    module Frontend
      class CommandBuilder
        DEFAULT_VERILATOR_BIN = "verilator"
        DEFAULT_LANGUAGE = "1800-2017"

        def initialize(verilator_bin: DEFAULT_VERILATOR_BIN)
          @verilator_bin = verilator_bin
        end

        def build(resolved_input:, frontend_json_path:, frontend_meta_path:)
          source_files = array_value(resolved_input, :source_files)
          raise ArgumentError, "resolved input must include source files" if source_files.empty?

          include_dirs = array_value(resolved_input, :include_dirs)
          defines = normalized_defines(value_for(resolved_input, :defines))
          language = value_for(resolved_input, :language)&.to_s
          language = DEFAULT_LANGUAGE if language.nil? || language.empty?

          top_modules = array_value(resolved_input, :top_modules)
          top_module = top_modules.first || value_for(resolved_input, :top_module)

          command = [
            @verilator_bin,
            "--json-only",
            "--json-only-output",
            frontend_json_path,
            "--json-only-meta-output",
            frontend_meta_path,
            "-Wno-fatal",
            "--language",
            language
          ]

          command << "-Wno-MODMISSING" if missing_modules_policy(resolved_input) == "blackbox_stubs"

          top_module_str = top_module&.to_s
          command.concat(["--top-module", top_module_str]) if top_module_str && !top_module_str.empty?
          include_dirs.each { |incdir| command << "-I#{incdir}" }
          defines.each { |define| command << "-D#{define}" }
          source_files.each { |source| command << source }
          command
        end

        def shell_command(resolved_input:, frontend_json_path:, frontend_meta_path:)
          Shellwords.join(
            build(
              resolved_input: resolved_input,
              frontend_json_path: frontend_json_path,
              frontend_meta_path: frontend_meta_path
            )
          )
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

        def array_value(hash, key)
          Array(value_for(hash, key)).compact.map(&:to_s)
        end

        def normalized_defines(defines)
          case defines
          when nil
            []
          when Hash
            define_pairs = defines.each_with_object([]) do |(key, value), memo|
              memo << [key.to_s, value]
            end
            define_pairs.sort_by(&:first).map do |key, value|
              value.nil? ? key : "#{key}=#{value}"
            end
          else
            Array(defines).compact.map(&:to_s)
          end
        end

        def missing_modules_policy(resolved_input)
          value_for(resolved_input, :missing_modules).to_s.strip.downcase
        end
      end
    end
  end
end
