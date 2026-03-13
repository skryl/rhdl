# frozen_string_literal: true

require_relative '../../codegen'
require_relative 'mlir'

module RHDL
  module Codegen
    module CIRCT
      module ImportCleanup
        module_function

        CleanupResult = Struct.new(:success, :cleaned_text, :import_result, :stubbed_modules, keyword_init: true) do
          def success?
            !!success
          end
        end

        # Normalize imported CIRCT MLIR into pure core dialects by parsing it
        # through the existing CIRCT importer and re-emitting structural MLIR.
        # This strips surviving LLHD signal/time overlays from circt-verilog
        # imports before downstream tools such as firtool consume the artifact.
        def parse_imported_core_mlir(text, strict: true, top: nil, extern_modules: [], resolve_forward_refs: false)
          RHDL::Codegen.import_circt_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: resolve_forward_refs
          )
        end

        def emit_cleaned_core_mlir(modules)
          RHDL::Codegen::CIRCT::MLIR.generate(modules)
        end

        def cleanup_imported_core_mlir(text, strict: true, top: nil, extern_modules: [], stub_modules: [])
          stub_specs = normalize_stub_modules(stub_modules)
          needs_cleanup = cleanup_markers?(text)
          return success_result(text, stubbed_modules: []) unless needs_cleanup || !stub_specs.empty?

          package = split_top_level_package(text)
          return cleanup_whole_text(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            stub_specs: stub_specs
          ) unless package

          wrapped = package.fetch(:wrapped)
          entries = package.fetch(:entries)
          module_names = entries.filter_map { |entry| module_name_for_entry(entry) }
          missing_stubs = stub_specs.keys - module_names
          return failure_result(stub_not_found_diagnostics(missing_stubs), stubbed_modules: []) unless missing_stubs.empty?

          diagnostics = []
          stubbed_modules = []
          cleaned_entries = entries.map do |entry|
            entry_name = module_name_for_entry(entry)
            needs_entry_cleanup = cleanup_markers?(entry)
            needs_entry_stub = entry_name && stub_specs.key?(entry_name)

            unless needs_entry_cleanup || needs_entry_stub
              next normalize_entry_text(entry)
            end

            entry_externs = Array(extern_modules).map(&:to_s) | (module_names - Array(entry_name))
            import_result = parse_imported_core_mlir(
              entry,
              strict: strict,
              top: entry_name || top,
              extern_modules: entry_externs,
              resolve_forward_refs: true
            )
            return failure_result(import_result.diagnostics, stubbed_modules: stubbed_modules) unless import_result.success?

            diagnostics.concat(Array(import_result.diagnostics))
            transformed_modules, transformed_names, stub_diags = apply_stub_modules(
              import_result.modules,
              stub_specs
            )
            return failure_result(diagnostics + stub_diags, stubbed_modules: stubbed_modules | transformed_names) unless stub_diags.empty?

            stubbed_modules |= transformed_names
            normalize_entry_text(emit_cleaned_core_mlir(transformed_modules))
          end

          cleaned_text = rebuild_top_level_package(entries: cleaned_entries, wrapped: wrapped)

          CleanupResult.new(
            success: !cleaned_text.to_s.include?('llhd.'),
            cleaned_text: cleaned_text,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: diagnostics),
            stubbed_modules: stubbed_modules.sort
          )
        end

        def success_result(text, stubbed_modules: [])
          CleanupResult.new(
            success: true,
            cleaned_text: text,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: []),
            stubbed_modules: Array(stubbed_modules).sort
          )
        end

        def failure_result(diagnostics, stubbed_modules: [])
          CleanupResult.new(
            success: false,
            cleaned_text: nil,
            import_result: RHDL::Codegen::CIRCT::ImportResult.new(modules: [], diagnostics: diagnostics),
            stubbed_modules: Array(stubbed_modules).sort
          )
        end

        def cleanup_markers?(text)
          text.include?('llhd.')
        end

        def cleanup_whole_text(text, strict:, top:, extern_modules:, stub_specs:)
          import_result = parse_imported_core_mlir(
            text,
            strict: strict,
            top: top,
            extern_modules: extern_modules,
            resolve_forward_refs: true
          )
          return failure_result(import_result.diagnostics, stubbed_modules: []) unless import_result.success?

          transformed_modules, stubbed_modules, stub_diags = apply_stub_modules(import_result.modules, stub_specs)
          return failure_result(Array(import_result.diagnostics) + stub_diags, stubbed_modules: stubbed_modules) unless stub_diags.empty?

          missing_stubs = stub_specs.keys - stubbed_modules
          return failure_result(stub_not_found_diagnostics(missing_stubs), stubbed_modules: stubbed_modules) unless missing_stubs.empty?

          cleaned_text = emit_cleaned_core_mlir(transformed_modules)
          CleanupResult.new(
            success: !cleaned_text.to_s.include?('llhd.'),
            cleaned_text: cleaned_text,
            import_result: import_result,
            stubbed_modules: stubbed_modules.sort
          )
        end

        def normalize_stub_modules(stub_modules)
          Array(stub_modules).each_with_object({}) do |entry, acc|
            spec = normalize_stub_module_entry(entry)
            next if spec.nil?

            acc[spec.fetch(:name)] = spec
          end
        end

        def normalize_stub_module_entry(entry)
          case entry
          when nil
            nil
          when String, Symbol
            name = entry.to_s.strip
            raise ArgumentError, 'stub module name cannot be empty' if name.empty?

            { name: name, outputs: {} }
          when Hash
            name = (entry[:name] || entry['name'] || entry[:module] || entry['module']).to_s.strip
            raise ArgumentError, "stub module hash requires :name or :module: #{entry.inspect}" if name.empty?

            outputs = entry[:outputs] || entry['outputs'] || {}
            unless outputs.is_a?(Hash)
              raise ArgumentError, "stub module outputs must be a Hash for #{name}: #{outputs.inspect}"
            end

            {
              name: name,
              outputs: normalize_stub_output_overrides(outputs)
            }
          else
            raise ArgumentError, "unsupported stub module entry: #{entry.inspect}"
          end
        end

        def normalize_stub_output_overrides(outputs)
          outputs.each_with_object({}) do |(port_name, override), acc|
            key = port_name.to_s.strip
            raise ArgumentError, "stub output name cannot be empty: #{outputs.inspect}" if key.empty?

            acc[key] = normalize_stub_output_override(override)
          end
        end

        def normalize_stub_output_override(override)
          case override
          when Integer
            { kind: :literal, value: override }
          when true
            { kind: :literal, value: 1 }
          when false
            { kind: :literal, value: 0 }
          when String, Symbol
            signal = override.to_s.strip
            raise ArgumentError, "stub signal override cannot be empty: #{override.inspect}" if signal.empty?

            { kind: :signal, signal: signal }
          when Hash
            if override.key?(:signal) || override.key?('signal') || override.key?(:input) || override.key?('input')
              signal = (override[:signal] || override['signal'] || override[:input] || override['input']).to_s.strip
              raise ArgumentError, "stub signal override cannot be empty: #{override.inspect}" if signal.empty?

              { kind: :signal, signal: signal }
            elsif override.key?(:value) || override.key?('value') || override.key?(:const) || override.key?('const')
              value = override[:value]
              value = override['value'] if value.nil?
              value = override[:const] if value.nil?
              value = override['const'] if value.nil?
              literal =
                case value
                when true then 1
                when false then 0
                when Integer then value
                else
                  raise ArgumentError, "stub literal override must be Integer/boolean: #{override.inspect}"
                end
              { kind: :literal, value: literal }
            else
              raise ArgumentError, "unsupported stub output override: #{override.inspect}"
            end
          else
            raise ArgumentError, "unsupported stub output override: #{override.inspect}"
          end
        end

        def apply_stub_modules(modules, stub_specs)
          return [modules, [], []] if stub_specs.empty?

          stubbed_modules = []
          diagnostics = []
          transformed = Array(modules).map do |mod|
            spec = stub_specs[mod.name.to_s]
            next mod unless spec

            stubbed_modules << mod.name.to_s
            module_diags = validate_stub_module_spec(mod, spec)
            diagnostics.concat(module_diags)
            next mod unless module_diags.empty?

            build_stub_module(mod, spec)
          end

          [transformed, stubbed_modules.uniq.sort, diagnostics]
        end

        def validate_stub_module_spec(mod, spec)
          diagnostics = []
          output_ports = mod.ports.select { |port| port.direction.to_s == 'out' }
          output_port_names = output_ports.map { |port| port.name.to_s }
          input_port_names = mod.ports.reject { |port| port.direction.to_s == 'out' }.map { |port| port.name.to_s }
          override_outputs = spec.fetch(:outputs).keys
          unknown_outputs = override_outputs - output_port_names
          unless unknown_outputs.empty?
            diagnostics << Diagnostic.new(
              severity: :error,
              op: 'import.stub',
              message: "Stub for @#{mod.name} references unknown output port(s): #{unknown_outputs.sort.join(', ')}"
            )
          end

          spec.fetch(:outputs).each do |port_name, override|
            next unless override.fetch(:kind) == :signal
            next if input_port_names.include?(override.fetch(:signal))

            diagnostics << Diagnostic.new(
              severity: :error,
              op: 'import.stub',
              message: "Stub for @#{mod.name} output #{port_name} references unknown input signal #{override.fetch(:signal)}"
            )
          end

          diagnostics
        end

        def build_stub_module(mod, spec)
          output_overrides = spec.fetch(:outputs)
          assigns = mod.ports.select { |port| port.direction.to_s == 'out' }.map do |port|
            IR::Assign.new(
              target: port.name.to_s,
              expr: build_stub_output_expr(port, output_overrides[port.name.to_s])
            )
          end

          IR::ModuleOp.new(
            name: mod.name,
            ports: mod.ports.map do |port|
              IR::Port.new(
                name: port.name,
                direction: port.direction,
                width: port.width,
                default: port.default
              )
            end,
            nets: [],
            regs: [],
            assigns: assigns,
            processes: [],
            instances: [],
            memories: [],
            write_ports: [],
            sync_read_ports: [],
            parameters: (mod.parameters || {}).dup
          )
        end

        def build_stub_output_expr(port, override)
          width = [port.width.to_i, 1].max
          return IR::Literal.new(value: 0, width: width) if override.nil?

          case override.fetch(:kind)
          when :literal
            IR::Literal.new(value: override.fetch(:value), width: width)
          when :signal
            IR::Signal.new(name: override.fetch(:signal), width: width)
          else
            IR::Literal.new(value: 0, width: width)
          end
        end

        def stub_not_found_diagnostics(module_names)
          return [] if module_names.nil? || module_names.empty?

          [
            Diagnostic.new(
              severity: :error,
              op: 'import.stub',
              message: "Requested stub module(s) not found: #{module_names.sort.join(', ')}"
            )
          ]
        end

        def split_top_level_package(text)
          stripped = text.to_s.strip
          return nil if stripped.empty?

          lines = if wrapped_package_text?(text)
                    unwrap_builtin_module_lines(text)
                  else
                    text.lines
                  end
          entries = split_top_level_entries(lines)
          return nil if entries.empty?

          {
            wrapped: wrapped_package_text?(text),
            entries: entries
          }
        end

        def wrapped_package_text?(text)
          significant = text.to_s.lines.map(&:strip).reject(&:empty?)
          significant.length >= 2 &&
            significant.first == 'module {' &&
            significant.last == '}'
        end

        def unwrap_builtin_module_lines(text)
          lines = text.lines
          first = lines.index { |line| !line.strip.empty? }
          last = lines.rindex { |line| !line.strip.empty? }
          return [] unless first && last
          return [] if lines[first].strip != 'module {'
          return [] if lines[last].strip != '}'

          lines[(first + 1)...last] || []
        end

        def split_top_level_entries(lines)
          entries = []
          current = []
          depth = 0

          Array(lines).each do |line|
            next if current.empty? && line.strip.empty?

            current << line
            depth += brace_delta(line)
            next unless depth <= 0

            entries << current.join
            current = []
            depth = 0
          end

          entries << current.join unless current.empty?
          entries.reject { |entry| entry.to_s.strip.empty? }
        end

        def brace_delta(line)
          delta = 0
          in_string = false
          escape = false

          line.to_s.each_char do |char|
            if in_string
              if escape
                escape = false
              elsif char == '\\'
                escape = true
              elsif char == '"'
                in_string = false
              end
              next
            end

            if char == '"'
              in_string = true
            elsif char == '{'
              delta += 1
            elsif char == '}'
              delta -= 1
            end
          end

          delta
        end

        def module_name_for_entry(entry)
          entry.to_s[/^\s*(?:hw|sv)\.module(?:\s+\w+)*\s+@([A-Za-z_$][A-Za-z0-9_$.]*)/, 1]
        end

        def normalize_entry_text(entry)
          entry.to_s.strip
        end

        def rebuild_top_level_package(entries:, wrapped:)
          body = Array(entries).map { |entry| normalize_entry_text(entry) }.reject(&:empty?)
          return "#{body.join("\n\n")}\n" unless wrapped

          indented = body.map do |entry|
            entry.lines.map { |line| line.strip.empty? ? line : "  #{line}" }.join
          end
          "module {\n#{indented.join("\n\n")}\n}\n"
        end

      end
    end
  end
end
