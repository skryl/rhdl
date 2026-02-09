# frozen_string_literal: true

require 'pathname'
require 'time'

module RHDL
  module Codegen
    module Source
      module_function

      def collect_component_classes(top_class)
        classes = [top_class]
        if top_class.respond_to?(:collect_submodule_classes, true)
          classes.concat(Array(top_class.send(:collect_submodule_classes)))
        end
        classes.compact.uniq
      end

      def component_entry(component_class, relative_to: nil)
        class_name = component_class.name.to_s
        source_location = Object.const_source_location(class_name)
        source_path = source_location&.first
        source_text = if source_path && File.file?(source_path)
                        File.read(source_path)
                      else
                        ''
                      end

        {
          component_class: class_name,
          module_name: component_class.respond_to?(:verilog_module_name) ? component_class.verilog_module_name : nil,
          source_path: relative_path(source_path, root: relative_to),
          rhdl_source: source_text
        }.compact
      end

      def bundle(top_class, runner: nil, relative_to: nil)
        components = collect_component_classes(top_class).map do |component_class|
          component_entry(component_class, relative_to: relative_to)
        end
        components.sort_by! { |entry| entry[:component_class].to_s }

        top_class_name = top_class.name.to_s
        top_entry = components.find { |entry| entry[:component_class] == top_class_name } || components.first

        {
          format: 'rhdl.web.component_sources.v1',
          runner: runner,
          generated_at: Time.now.utc.iso8601,
          top_component_class: top_class_name,
          top: top_entry,
          components: components
        }.compact
      end

      def relative_path(path, root: nil)
        return nil unless path && !path.empty?
        return path unless root

        Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
      rescue StandardError
        path
      end
    end
  end
end
