# frozen_string_literal: true

require "shellwords"

module RHDL
  module Import
    class FilelistParser
      class << self
        def parse(path)
          new(path).parse
        end
      end

      def initialize(path)
        @path = File.expand_path(path)
      end

      def parse
        state = {
          source_files: [],
          include_dirs: [],
          defines: []
        }

        parse_file(@path, state: state, stack: [])

        {
          filelist_path: @path,
          source_files: state[:source_files],
          include_dirs: state[:include_dirs],
          defines: state[:defines]
        }
      end

      private

      def parse_file(path, state:, stack:)
        expanded_path = File.expand_path(path)
        raise ArgumentError, "cyclic filelist include detected: #{expanded_path}" if stack.include?(expanded_path)

        stack << expanded_path
        base_dir = File.dirname(expanded_path)

        File.readlines(expanded_path, chomp: true).each do |line|
          consume_tokens(tokenize(line), base_dir: base_dir, state: state, stack: stack)
        end
      ensure
        stack.pop
      end

      def tokenize(line)
        stripped = line.sub(%r{//.*$}, "").sub(/#.*$/, "").strip
        return [] if stripped.empty?

        Shellwords.split(stripped)
      end

      def consume_tokens(tokens, base_dir:, state:, stack:)
        index = 0
        while index < tokens.length
          token = tokens[index]

          if token == "-f" || token == "-F"
            index += 1
            next if index >= tokens.length

            parse_file(resolve_path(tokens[index], base_dir), state: state, stack: stack)
          elsif token.start_with?("-f") && token.length > 2
            parse_file(resolve_path(token[2..], base_dir), state: state, stack: stack)
          elsif token.start_with?("-F") && token.length > 2
            parse_file(resolve_path(token[2..], base_dir), state: state, stack: stack)
          elsif token == "-I"
            index += 1
            next if index >= tokens.length

            append_unique(state[:include_dirs], resolve_path(tokens[index], base_dir))
          elsif token.start_with?("-I") && token.length > 2
            append_unique(state[:include_dirs], resolve_path(token[2..], base_dir))
          elsif token == "-D"
            index += 1
            next if index >= tokens.length

            append_unique(state[:defines], tokens[index])
          elsif token.start_with?("-D") && token.length > 2
            append_unique(state[:defines], token[2..])
          elsif token.start_with?("+incdir+")
            token.sub(/\A\+incdir\+/, "").split("+").each do |dir|
              next if dir.empty?

              append_unique(state[:include_dirs], resolve_path(dir, base_dir))
            end
          elsif token.start_with?("+define+")
            token.sub(/\A\+define\+/, "").split("+").each do |define|
              next if define.empty?

              append_unique(state[:defines], define)
            end
          elsif token.start_with?("-") || token.start_with?("+")
            # Ignore unsupported directives in this tranche.
          else
            append_unique(state[:source_files], resolve_path(token, base_dir))
          end

          index += 1
        end
      end

      def resolve_path(path, base_dir)
        File.expand_path(path, base_dir)
      end

      def append_unique(list, value)
        return if list.include?(value)

        list << value
      end
    end
  end
end
