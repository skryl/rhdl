# frozen_string_literal: true

require "pathname"
require_relative "filelist_parser"

module RHDL
  module Import
    class InputResolver
      SOURCE_EXTENSIONS = %w[.v .sv].freeze
      EXCLUDE_MATCH_FLAGS = File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB
      MODULE_DECLARATION_REGEX = /^\s*(?:module|macromodule)\b/.freeze

      class << self
        def resolve(
          filelist: nil,
          src: [],
          exclude: [],
          incdir: [],
          define: [],
          dependency_resolution: nil,
          compile_unit_filter: nil,
          cwd: Dir.pwd
        )
          new(
            filelist: filelist,
            src: src,
            exclude: exclude,
            incdir: incdir,
            define: define,
            dependency_resolution: dependency_resolution,
            compile_unit_filter: compile_unit_filter,
            cwd: cwd
          ).resolve
        end
      end

      def initialize(filelist:, src:, exclude:, incdir:, define:, dependency_resolution:, compile_unit_filter:, cwd:)
        @filelist = filelist
        @src = Array(src).compact
        @exclude = unique_preserving_order(Array(exclude).compact)
        @incdir = Array(incdir).compact
        @define = Array(define).compact
        @dependency_resolution = normalize_dependency_resolution(dependency_resolution)
        @compile_unit_filter = normalize_compile_unit_filter(compile_unit_filter)
        @cwd = File.expand_path(cwd)
      end

      def resolve
        return resolve_filelist_mode if @filelist && !@filelist.empty?
        return resolve_autoscan_mode if @src.any?

        raise ArgumentError, "expected :filelist or at least one :src directory"
      end

      private

      def resolve_filelist_mode
        parsed = FilelistParser.parse(expand_from_cwd(@filelist))

        source_files = filter_compile_units(filter_excluded(parsed[:source_files]))
        include_dirs = unique_preserving_order(parsed[:include_dirs] + expand_paths(@incdir))
        defines = unique_preserving_order(parsed[:defines] + @define)

        build_contract(
          mode: :filelist,
          filelist_path: parsed[:filelist_path],
          source_roots: [],
          source_files: source_files,
          include_dirs: include_dirs,
          defines: defines
        )
      end

      def resolve_autoscan_mode
        source_roots = expand_paths(@src)
        scan_roots = roots_for_autoscan(source_roots)
        scanned = scan_roots.flat_map { |root| scan_sources(root) }.sort.uniq
        scanned_included = filter_excluded(scanned)
        source_files = filter_compile_units(scanned_included)
        include_dirs = build_autoscan_include_dirs(scan_roots: scan_roots, scanned_files: scanned_included)
        defines = unique_preserving_order(@define)

        build_contract(
          mode: :autoscan,
          filelist_path: nil,
          source_roots: scan_roots,
          source_files: source_files,
          include_dirs: include_dirs,
          defines: defines
        )
      end

      def build_contract(mode:, filelist_path:, source_roots:, source_files:, include_dirs:, defines:)
        {
          mode: mode,
          filelist_path: filelist_path,
          source_roots: source_roots,
          source_files: source_files,
          include_dirs: include_dirs,
          defines: defines,
          exclude_patterns: @exclude,
          frontend_input: {
            source_files: source_files,
            include_dirs: include_dirs,
            defines: defines
          }
        }
      end

      def scan_sources(root)
        pattern = File.join(root, "**", "*")
        Dir.glob(pattern).select do |path|
          File.file?(path) && SOURCE_EXTENSIONS.include?(File.extname(path))
        end
      end

      def expand_paths(paths)
        unique_preserving_order(paths.map { |path| expand_from_cwd(path) })
      end

      def expand_from_cwd(path)
        File.expand_path(path, @cwd)
      end

      def filter_excluded(paths)
        paths.reject { |path| excluded?(path) }
      end

      def excluded?(path)
        absolute = File.expand_path(path)
        relative = relative_to_cwd(absolute)
        basename = File.basename(absolute)

        @exclude.any? do |pattern|
          match_pattern?(pattern, absolute) ||
            match_pattern?(pattern, relative) ||
            match_pattern?(pattern, basename)
        end
      end

      def roots_for_autoscan(source_roots)
        return source_roots unless @dependency_resolution == "parent_root_auto_scan"

        parent_roots = source_roots.map { |root| File.expand_path("..", root) }
        unique_preserving_order(source_roots + parent_roots)
      end

      def build_autoscan_include_dirs(scan_roots:, scanned_files:)
        explicit = expand_paths(@incdir)
        inferred = unique_preserving_order(scan_roots + scanned_files.map { |path| File.dirname(path) })
        unique_preserving_order(explicit + inferred)
      end

      def filter_compile_units(paths)
        return paths unless @compile_unit_filter == "modules_only"

        paths.select { |path| module_compile_unit?(path) }
      end

      def module_compile_unit?(path)
        return false unless File.file?(path)

        File.foreach(path) do |line|
          return true if MODULE_DECLARATION_REGEX.match?(line)
        end
        false
      rescue ArgumentError, Errno::ENOENT
        false
      end

      def relative_to_cwd(path)
        Pathname.new(path).relative_path_from(Pathname.new(@cwd)).to_s
      rescue ArgumentError
        path
      end

      def match_pattern?(pattern, candidate)
        File.fnmatch?(pattern, normalize_slashes(candidate), EXCLUDE_MATCH_FLAGS)
      end

      def normalize_slashes(path)
        path.tr("\\", "/")
      end

      def unique_preserving_order(values)
        values.each_with_object([]) do |value, memo|
          memo << value unless memo.include?(value)
        end
      end

      def normalize_dependency_resolution(value)
        normalized = value.to_s.strip.downcase
        return "none" if normalized.empty?

        return normalized if %w[none parent_root_auto_scan].include?(normalized)

        raise ArgumentError, "unknown dependency_resolution: #{value.inspect}"
      end

      def normalize_compile_unit_filter(value)
        normalized = value.to_s.strip.downcase
        return "all" if normalized.empty?

        return normalized if %w[all modules_only].include?(normalized)

        raise ArgumentError, "unknown compile_unit_filter: #{value.inspect}"
      end
    end
  end
end
