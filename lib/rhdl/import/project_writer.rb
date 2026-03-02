# frozen_string_literal: true

require "fileutils"
require "digest/sha1"
require "set"
require "time"
require "yaml"
require "pathname"
require_relative "ruby_prettyfier"

module RHDL
  module Import
    class ProjectWriter
      class << self
        def write(**kwargs)
          new.write(**kwargs)
        end
      end

      def write(out:, project_slug:, modules:, source_files: [], source_roots: [])
        out_dir = File.expand_path(out)
        slug = project_slug.to_s
        normalized_modules = normalize_modules(modules)
        source_root = infer_source_root(source_files: source_files, source_roots: source_roots)
        module_relpaths = build_module_relpaths(normalized_modules, source_root: source_root)

        module_files = write_module_files(
          out_dir: out_dir,
          slug: slug,
          modules: normalized_modules,
          module_relpaths: module_relpaths
        )
        removed_module_files = prune_stale_module_files(
          out_dir: out_dir,
          slug: slug,
          expected_paths: module_files.values
        )
        project_file = write_project_file(
          out_dir: out_dir,
          slug: slug,
          modules: normalized_modules,
          module_relpaths: module_relpaths
        )
        vendor_dir = copy_source_files(out_dir: out_dir, source_files: source_files, source_root: source_root)
        removed_vendor_files = prune_stale_vendor_files(
          vendor_dir: vendor_dir,
          source_files: source_files,
          source_root: source_root
        )
        config_file = write_config_file(
          out_dir: out_dir,
          slug: slug,
          modules: normalized_modules,
          source_files: source_files,
          source_root: source_root
        )

        {
          project_file: project_file,
          module_files: module_files,
          vendor_dir: vendor_dir,
          config_file: config_file,
          removed_module_files: removed_module_files,
          removed_vendor_files: removed_vendor_files
        }
      end

      private

      def normalize_modules(modules)
        Array(modules).map do |entry|
          hash = entry.is_a?(Hash) ? entry : {}
          name = value_for(hash, :name).to_s
          next if name.empty?

          {
            name: name,
            source: value_for(hash, :source) || value_for(hash, :ruby_source),
            source_path: source_path_for(hash),
            dependencies: normalize_dependencies(value_for(hash, :dependencies))
          }
        end.compact.sort_by { |entry| entry[:name] }
      end

      def write_module_files(out_dir:, slug:, modules:, module_relpaths:)
        module_root = File.join(out_dir, "lib", slug, "modules")
        FileUtils.mkdir_p(module_root)

        modules.each_with_object({}) do |entry, memo|
          relative_module_path = "#{module_relpaths.fetch(entry[:name])}.rb"
          module_path = File.join(module_root, relative_module_path)
          FileUtils.mkdir_p(File.dirname(module_path))
          File.write(module_path, normalize_source(entry))
          memo[entry[:name]] = module_path
        end
      end

      def prune_stale_module_files(out_dir:, slug:, expected_paths:)
        module_root = File.join(out_dir, "lib", slug, "modules")
        return [] unless Dir.exist?(module_root)

        expected = Array(expected_paths).map { |path| File.expand_path(path) }.to_set
        removed = []

        Dir.glob(File.join(module_root, "**", "*.rb")).sort.each do |path|
          absolute = File.expand_path(path)
          next if expected.include?(absolute)

          File.delete(absolute)
          removed << absolute
        end

        prune_empty_directories(module_root)
        removed
      end

      def write_project_file(out_dir:, slug:, modules:, module_relpaths:)
        project_file = File.join(out_dir, "lib", "#{slug}.rb")
        FileUtils.mkdir_p(File.dirname(project_file))

        require_lines = require_ordered_modules(modules).map do |entry|
          %(require_relative "#{slug}/modules/#{module_relpaths.fetch(entry[:name])}")
        end

        lines = []
        lines << "# frozen_string_literal: true"
        lines << ""
        lines.concat(require_lines)
        lines << ""
        lines << "module #{project_module_name(slug)}"
        lines << "end"
        lines << ""

        File.write(project_file, RubyPrettyfier.format(lines.join("\n")))
        project_file
      end

      def copy_source_files(out_dir:, source_files:, source_root:)
        vendor_dir = File.join(out_dir, "vendor", "source_hdl")
        FileUtils.mkdir_p(vendor_dir)

        Array(source_files).each do |source_file|
          next unless File.file?(source_file)

          relative = source_relative_path(source_file, source_root: source_root)
          target = File.join(vendor_dir, relative)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source_file, target)
        end

        vendor_dir
      end

      def prune_stale_vendor_files(vendor_dir:, source_files:, source_root:)
        return [] unless Dir.exist?(vendor_dir)

        expected = Array(source_files)
          .select { |source_file| File.file?(source_file) }
          .map { |source_file| source_relative_path(source_file, source_root: source_root) }
          .to_set
        removed = []

        Dir.glob(File.join(vendor_dir, "**", "*")).sort.each do |path|
          next unless File.file?(path)
          relative = Pathname.new(path).relative_path_from(Pathname.new(vendor_dir)).to_s
          next if expected.include?(relative)

          File.delete(path)
          removed << path
        end

        prune_empty_directories(vendor_dir)
        removed
      end

      def write_config_file(out_dir:, slug:, modules:, source_files:, source_root:)
        config_file = File.join(out_dir, "rhdl_import.yml")
        config = {
          "project" => slug,
          "generated_at" => Time.now.utc.iso8601,
          "modules" => modules.map { |entry| entry[:name] },
          "source_files" => Array(source_files)
            .map { |path| source_relative_path(path, source_root: source_root) }
            .uniq
            .sort
        }

        File.write(config_file, YAML.dump(config))
        config_file
      end

      def build_module_relpaths(modules, source_root:)
        grouped = modules.group_by { |entry| module_relpath_base(entry, source_root: source_root) }
        grouped.each_with_object({}) do |(base, entries), memo|
          if entries.length == 1
            memo[entries.first[:name]] = base
            next
          end

          entries.sort_by { |entry| entry[:name] }.each do |entry|
            suffix = Digest::SHA1.hexdigest(entry[:name].to_s)[0, 8]
            memo[entry[:name]] = "#{base}__#{suffix}"
          end
        end
      end

      def module_relpath_base(entry, source_root:)
        source_path = entry[:source_path].to_s
        if !source_path.empty?
          relative_source = normalize_relative_path(
            source_relative_path(source_path, source_root: source_root)
          )
          unless relative_source.empty?
            base = module_filename_base(File.basename(relative_source, ".*"))
            relative_dir = File.dirname(relative_source)
            return base if relative_dir == "."

            return File.join(relative_dir, base)
          end
        end

        module_filename_base(entry[:name])
      end

      def module_filename_base(name)
        sanitized = name.to_s
          .gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .tr("-", "_")
          .gsub(/[^A-Za-z0-9_]/, "_")
          .downcase

        sanitized.empty? ? "unnamed_module" : sanitized
      end

      def project_module_name(slug)
        tokens = slug.to_s.split(/[^A-Za-z0-9]+/).reject(&:empty?)
        candidate = tokens.map { |token| token[0].upcase + token[1..] }.join
        candidate = "ImportedProject" if candidate.empty?
        candidate = "M#{candidate}" if candidate.match?(/\A\d/)
        candidate
      end

      def normalize_source(entry)
        source = entry[:source].to_s
        source = "# Converted module: #{entry[:name]}\n" if source.empty?
        source = source.end_with?("\n") ? source : "#{source}\n"
        RubyPrettyfier.format(source)
      end

      def normalize_dependencies(values)
        Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      end

      def source_path_for(hash)
        explicit = value_for(hash, :source_path).to_s.strip
        return explicit unless explicit.empty?

        span = value_for(hash, :span)
        span_hash = span.is_a?(Hash) ? span : {}
        candidate = value_for(span_hash, :source_path) ||
          value_for(span_hash, :path) ||
          value_for(span_hash, :file)
        candidate.to_s.strip
      end

      def infer_source_root(source_files:, source_roots:)
        roots = Array(source_roots).map(&:to_s).reject(&:empty?).map { |path| File.expand_path(path) }.uniq
        return roots.reduce { |prefix, path| common_path_prefix(prefix, path) } unless roots.empty?

        files = Array(source_files).map(&:to_s).reject(&:empty?)
        return nil if files.empty?

        directories = files.map do |source_file|
          expanded = File.expand_path(source_file)
          File.directory?(expanded) ? expanded : File.dirname(expanded)
        end.uniq
        return nil if directories.empty?

        directories.reduce do |prefix, path|
          common_path_prefix(prefix, path)
        end
      end

      def common_path_prefix(left, right)
        left_parts = File.expand_path(left).split(File::SEPARATOR)
        right_parts = File.expand_path(right).split(File::SEPARATOR)
        max = [left_parts.length, right_parts.length].min
        idx = 0
        idx += 1 while idx < max && left_parts[idx] == right_parts[idx]
        common_parts = left_parts[0...idx]
        return File::SEPARATOR if common_parts.empty?

        common_parts.join(File::SEPARATOR)
      end

      def source_relative_path(source_path, source_root:)
        normalized = source_path.to_s.strip
        normalized = File.expand_path(normalized) if absolute_path?(normalized)

        relative =
          if absolute_path?(normalized) && !source_root.to_s.empty?
            root = File.expand_path(source_root)
            if path_within_root?(normalized, root)
              Pathname.new(normalized).relative_path_from(Pathname.new(root)).to_s
            else
              File.basename(normalized)
            end
          elsif absolute_path?(normalized)
            File.basename(normalized)
          else
            normalized
          end

        cleaned = normalize_relative_path(relative)
        cleaned.empty? ? File.basename(normalized) : cleaned
      end

      def normalize_relative_path(path)
        return "" if path.to_s.strip.empty?

        path
          .tr("\\", "/")
          .split("/")
          .reject { |segment| segment.empty? || segment == "." || segment == ".." }
          .join("/")
      end

      def absolute_path?(path)
        value = path.to_s
        return false if value.empty?

        value.start_with?("/") || value.match?(/\A[A-Za-z]:[\\\/]/)
      end

      def path_within_root?(path, root)
        normalized_path = File.expand_path(path)
        normalized_root = File.expand_path(root)
        return true if normalized_root == File::SEPARATOR
        return true if normalized_path == normalized_root

        normalized_path.start_with?("#{normalized_root}#{File::SEPARATOR}")
      end

      def prune_empty_directories(root)
        return unless Dir.exist?(root)

        Dir.glob(File.join(root, "**", "*"))
          .select { |path| File.directory?(path) }
          .sort_by { |path| -path.length }
          .each do |path|
            Dir.rmdir(path) if Dir.empty?(path)
          rescue SystemCallError
            nil
          end
      end

      def require_ordered_modules(modules)
        index = {}
        modules.each { |entry| index[entry[:name]] = entry }

        indegree = Hash.new(0)
        dependents = Hash.new { |memo, key| memo[key] = [] }
        modules.each do |entry|
          name = entry[:name]
          indegree[name] ||= 0

          Array(entry[:dependencies]).each do |dependency|
            next unless index.key?(dependency)

            indegree[name] += 1
            dependents[dependency] << name
          end
        end

        ready = modules.map { |entry| entry[:name] }.select { |name| indegree[name].zero? }.sort
        ordered_names = []

        until ready.empty?
          current = ready.shift
          ordered_names << current

          dependents[current].sort.each do |dependent|
            indegree[dependent] -= 1
            ready << dependent if indegree[dependent].zero?
          end
          ready.sort!
        end

        if ordered_names.length < modules.length
          remaining = modules.map { |entry| entry[:name] }.reject { |name| ordered_names.include?(name) }.sort
          ordered_names.concat(remaining)
        end

        ordered_names.map { |name| index.fetch(name) }
      end

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
