# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "set"
require "tmpdir"
require "yaml"

require_relative "../input_resolver"
require_relative "../missing_module_signature_extractor"

module RHDL
  module Import
    module Checks
      class Ao486ComponentParityHarness
        DEFAULT_CYCLES = 16
        MAX_MISSING_STUB_ATTEMPTS = 3

        class << self
          def run(**kwargs)
            new(**kwargs).run
          end
        end

        def initialize(out:, components:, cycles:, seed:, source_root:, cwd:)
          @out = File.expand_path(out.to_s, cwd)
          @requested_components = normalize_component_names(components)
          @cycles = normalize_cycles(cycles)
          @seed = Integer(seed)
          @source_root = source_root.to_s.strip
          @cwd = cwd
        end

        def run
          validate!

          Dir.mktmpdir("ao486_component_parity") do |work_dir|
            reference = reference_contract
            converted = converted_contract(work_dir: work_dir)
            selected = select_components(converted[:components])

            selected.map do |component|
              run_component_parity(
                component: component,
                reference: reference,
                converted: converted,
                work_dir: work_dir
              )
            end
          end
        end

        private

        def validate!
          raise ArgumentError, "cycles must be positive" if @cycles <= 0
        end

        def normalize_cycles(value)
          Integer(value || DEFAULT_CYCLES)
        rescue ArgumentError, TypeError
          DEFAULT_CYCLES
        end

        def normalize_component_names(values)
          Array(values).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
        end

        def reference_contract
          source_root = reference_root_for_harness
          resolved = InputResolver.resolve(
            src: [source_root],
            compile_unit_filter: "modules_only",
            dependency_resolution: "none",
            cwd: @cwd
          )

          {
            source_files: Array(resolved[:source_files]).map(&:to_s).reject(&:empty?).uniq.sort,
            include_dirs: Array(resolved[:include_dirs]).map(&:to_s).reject(&:empty?).uniq.sort
          }
        end

        def reference_root_for_harness
          return File.expand_path(@source_root, @cwd) unless @source_root.empty?

          File.expand_path(File.join("examples", "ao486", "reference", "rtl", "ao486"), @cwd)
        end

        def converted_contract(work_dir:)
          slug = converted_project_slug
          raise ArgumentError, "unable to resolve converted project slug under #{@out}/lib" if slug.empty?

          module_files = ordered_module_files_for_export(slug: slug)
          raise ArgumentError, "no converted module files found for project #{slug}" if module_files.empty?

          require "rhdl"

          namespace = Module.new
          components = load_converted_components(namespace: namespace, module_files: module_files)
          export_dir = File.join(work_dir, "converted_sources")
          FileUtils.mkdir_p(export_dir)

          verilog_paths = {}
          components.each do |component|
            source_module_name = component.fetch(:source_module_name)
            component_class = component.fetch(:component_class)
            output_path = File.join(export_dir, "#{source_module_name}.v")

            verilog = RHDL::Export.verilog(component_class, top_name: source_module_name)
            File.write(output_path, normalize_verilog_output(verilog))
            verilog_paths[source_module_name] = output_path
          end

          {
            slug: slug,
            components: components.sort_by { |entry| entry.fetch(:source_module_name) },
            component_index: components.each_with_object({}) do |entry, memo|
              memo[entry.fetch(:source_module_name)] = entry
            end,
            source_files: verilog_paths.values.sort,
            source_by_component: verilog_paths
          }
        end

        def converted_project_slug
          config_path = File.join(@out, "rhdl_import.yml")
          if File.file?(config_path)
            config = YAML.safe_load(File.read(config_path), permitted_classes: [], aliases: false)
            slug = value_for(config, :project).to_s.strip
            return slug unless slug.empty?
          end

          candidates = Dir.glob(File.join(@out, "lib", "*.rb")).map { |path| File.basename(path, ".rb") }.sort
          return candidates.first if candidates.length == 1

          ""
        rescue StandardError
          ""
        end

        def ordered_module_files_for_export(slug:)
          module_dir = File.join(@out, "lib", slug, "modules")
          module_files = Dir.glob(File.join(module_dir, "*.rb")).sort
          return module_files if module_files.empty?

          project_file = File.join(@out, "lib", "#{slug}.rb")
          return module_files unless File.file?(project_file)

          module_index = module_files.each_with_object({}) do |path, memo|
            memo[File.basename(path, ".rb")] = path
          end
          ordered = []

          File.read(project_file).scan(/require_relative\s+["']#{Regexp.escape(slug)}\/modules\/([^"']+)["']/).flatten.each do |basename|
            path = module_index[basename]
            next if path.nil? || ordered.include?(path)

            ordered << path
          end

          ordered.concat(module_files.reject { |path| ordered.include?(path) })
        rescue StandardError
          module_files
        end

        def load_converted_components(namespace:, module_files:)
          module_files.filter_map do |module_file|
            source = File.read(module_file)
            class_name = extract_component_class_name(source: source)
            next if class_name.nil?

            source_module_name = extract_source_module_name(source: source, fallback: File.basename(module_file, ".rb"))
            namespace.module_eval(source, module_file, 1)
            component_class = constantize_component(name: class_name, root: namespace)

            {
              source_module_name: source_module_name,
              class_name: class_name,
              component_class: component_class,
              ports: component_ports(component_class)
            }
          end
        end

        def extract_component_class_name(source:)
          source.to_s[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*<\s*RHDL::Component\b/, 1]
        end

        def extract_source_module_name(source:, fallback:)
          module_name = source.to_s[/^\s*#\s*source_module:\s*([A-Za-z_][A-Za-z0-9_$]*)\s*$/, 1]
          return module_name unless module_name.to_s.empty?

          fallback.to_s
        end

        def constantize_component(name:, root:)
          tokens = name.to_s.split("::").reject(&:empty?)
          tokens.inject(root) { |scope, const_name| scope.const_get(const_name) }
        rescue NameError => e
          if root != Object
            return constantize_component(name: name, root: Object)
          end

          raise ArgumentError, "unable to resolve component class #{name.inspect}: #{e.message}"
        end

        def component_ports(component_class)
          Array(component_class._ports).map do |port|
            {
              name: port.name.to_s,
              direction: normalize_port_direction(port.direction),
              width: normalize_width(port.width)
            }
          end
        end

        def normalize_port_direction(direction)
          case direction.to_s
          when "in", "input"
            "input"
          when "out", "output"
            "output"
          when "inout"
            "inout"
          else
            "input"
          end
        end

        def normalize_width(width)
          value = case width
          when Range
            begin_value = Integer(width.begin)
            end_value = Integer(width.end)
            (begin_value - end_value).abs + 1
          when String
            text = width.strip
            if (match = text.match(/\A(-?\d+)\s*\.\.\s*(-?\d+)\z/))
              (match[1].to_i - match[2].to_i).abs + 1
            else
              Integer(text)
            end
          else
            Integer(width || 1)
          end
          value <= 0 ? 1 : value
        rescue ArgumentError, TypeError
          1
        end

        def normalize_depth(depth)
          value = Integer(depth || 1)
          value <= 0 ? 1 : value
        rescue ArgumentError, TypeError
          1
        end

        def select_components(components)
          entries = Array(components)
          return entries if @requested_components.empty?

          requested = @requested_components.to_set
          entries.select { |entry| requested.include?(entry.fetch(:source_module_name)) }
        end

        def run_component_parity(component:, reference:, converted:, work_dir:)
          source_module_name = component.fetch(:source_module_name)
          ports = component.fetch(:ports)
          output_ports = ports.select { |port| %w[output inout].include?(port.fetch(:direction)) }
          return tool_failure_result(component: source_module_name, reason: "no_output_ports", message: "component has no observable outputs") if output_ports.empty?

          vectors, clock_name = build_vectors(source_module_name: source_module_name, ports: ports)
          original_trace = run_verilog_simulation(
            label: "reference",
            top: source_module_name,
            ports: ports,
            output_ports: output_ports,
            vectors: vectors,
            clock_name: clock_name,
            source_files: reference.fetch(:source_files),
            include_dirs: reference.fetch(:include_dirs),
            work_dir: File.join(work_dir, source_module_name, "reference")
          )
          generated_trace = run_verilog_simulation(
            label: "generated",
            top: source_module_name,
            ports: ports,
            output_ports: output_ports,
            vectors: vectors,
            clock_name: clock_name,
            source_files: converted.fetch(:source_files),
            include_dirs: [File.dirname(converted.fetch(:source_files).first)],
            work_dir: File.join(work_dir, source_module_name, "generated")
          )
          ir_trace = run_ir_simulation(
            component: component,
            output_ports: output_ports,
            vectors: vectors,
            clock_name: clock_name,
            component_index: converted.fetch(:component_index)
          )

          comparison = compare_three_way(
            output_ports: output_ports,
            original_trace: original_trace,
            generated_trace: generated_trace,
            ir_trace: ir_trace
          )

          {
            component: source_module_name,
            status: comparison[:summary][:fail_count].zero? ? "pass" : "fail",
            summary: comparison[:summary],
            mismatches: comparison[:mismatches]
          }
        rescue StandardError => e
          tool_failure_result(component: source_module_name, reason: "component_execution_error", message: e.message)
        end

        def build_vectors(source_module_name:, ports:)
          rng = Random.new(derived_seed(source_module_name))
          input_ports = ports.select { |port| %w[input inout].include?(port.fetch(:direction)) }
          clock_name = detect_clock_name(input_ports)

          vectors = Array.new(@cycles) do |cycle|
            input_ports.each_with_object({}) do |port, memo|
              name = port.fetch(:name)
              next if name == clock_name

              memo[name] = deterministic_input_value(name: name, width: port.fetch(:width), cycle: cycle, rng: rng)
            end
          end

          [vectors, clock_name]
        end

        def derived_seed(source_module_name)
          digest = Digest::SHA256.hexdigest(source_module_name.to_s)[0, 16].to_i(16)
          (@seed ^ digest) & 0xFFFFFFFFFFFFFFFF
        end

        def detect_clock_name(input_ports)
          names = Array(input_ports).map { |port| port.fetch(:name) }
          names.find { |name| name == "clk" } ||
            names.find { |name| name.match?(/\Aclk/i) } ||
            names.find { |name| name.match?(/clock/i) }
        end

        def deterministic_input_value(name:, width:, cycle:, rng:)
          normalized_name = name.to_s.downcase
          return cycle.zero? ? 0 : 1 if normalized_name.match?(/\A(rst_n|reset_n|resetn|nreset|n_rst)\z/)
          return cycle.zero? ? 1 : 0 if normalized_name.match?(/\A(reset|rst)\z/)

          effective_width = [normalize_width(width), 64].min
          mask = bit_mask(effective_width)
          random_value(width: effective_width, rng: rng) & mask
        end

        def random_value(width:, rng:)
          return rng.rand(0..1) if width <= 1

          chunks = (width.to_f / 32).ceil
          value = 0
          chunks.times do |index|
            value |= rng.rand(0..0xFFFF_FFFF) << (index * 32)
          end
          value
        end

        def bit_mask(width)
          return 0 if width <= 0

          (1 << width) - 1
        end

        def run_verilog_simulation(label:, top:, ports:, output_ports:, vectors:, clock_name:, source_files:, include_dirs:, work_dir:)
          FileUtils.mkdir_p(work_dir)

          testbench_path = File.join(work_dir, "tb_#{label}.sv")
          File.write(
            testbench_path,
            build_testbench(
              top: top,
              ports: ports,
              output_ports: output_ports,
              vectors: vectors,
              clock_name: clock_name
            )
          )

          stub_paths = []
          attempts = 0
          compile_result = compile_verilog(
            work_dir: work_dir,
            top: "tb",
            source_files: source_files,
            include_dirs: include_dirs,
            testbench_path: testbench_path,
            stub_paths: stub_paths
          )
          while !compile_result[:status].success? && attempts < MAX_MISSING_STUB_ATTEMPTS
            attempts += 1
            missing = extract_missing_modules(compile_result[:stderr])
            break if missing.empty?

            signatures = MissingModuleSignatureExtractor.augment(
              signatures: missing.map { |name| { name: name, ports: [], parameters: [] } },
              source_files: source_files
            )
            stub_paths = write_stub_sources(work_dir: work_dir, signatures: signatures)
            compile_result = compile_verilog(
              work_dir: work_dir,
              top: "tb",
              source_files: source_files,
              include_dirs: include_dirs,
              testbench_path: testbench_path,
              stub_paths: stub_paths
            )
          end

          unless compile_result[:status].success?
            raise ArgumentError, "#{label} compile failed for #{top}: #{first_error_line(compile_result[:stderr])}"
          end

          run_result = run_command(command: ["vvp", "sim.out"], chdir: work_dir)
          unless run_result[:status].success?
            raise ArgumentError, "#{label} simulation failed for #{top}: #{first_error_line(run_result[:stderr])}"
          end

          parse_simulation_output(stdout: run_result[:stdout], output_ports: output_ports, cycles: vectors.length)
        end

        def compile_verilog(work_dir:, top:, source_files:, include_dirs:, testbench_path:, stub_paths:)
          include_args = Array(include_dirs).map { |dir| "-I#{dir}" }
          command = [
            "iverilog",
            "-g2012",
            "-s",
            top.to_s,
            "-o",
            "sim.out",
            *include_args,
            *Array(source_files).map(&:to_s),
            *Array(stub_paths).map(&:to_s),
            testbench_path.to_s
          ]
          run_command(command: command, chdir: work_dir)
        end

        def run_command(command:, chdir:)
          stdout, stderr, status = Open3.capture3(*Array(command).map(&:to_s), chdir: chdir.to_s)
          { stdout: stdout.to_s, stderr: stderr.to_s, status: status }
        end

        def extract_missing_modules(stderr)
          text = stderr.to_s
          names = text.scan(/Unknown module type:\s*([A-Za-z_][A-Za-z0-9_$]*)/).flatten
          names += text.scan(/module\s+([A-Za-z_][A-Za-z0-9_$]*)\s+not found/i).flatten
          names.uniq.sort
        end

        def write_stub_sources(work_dir:, signatures:)
          stubs_dir = File.join(work_dir, "stubs")
          FileUtils.mkdir_p(stubs_dir)

          Array(signatures).map do |signature|
            name = value_for(signature, :name).to_s
            next if name.empty?

            path = File.join(stubs_dir, "#{name}.v")
            File.write(path, emit_stub_verilog(signature))
            path
          end.compact.sort
        end

        def emit_stub_verilog(signature)
          name = value_for(signature, :name).to_s
          ports = Array(value_for(signature, :ports)).map(&:to_s).reject(&:empty?).uniq.sort
          parameters = Array(value_for(signature, :parameters)).map(&:to_s).reject(&:empty?).uniq.sort

          lines = []
          if parameters.empty?
            if ports.empty?
              lines << "module #{name};"
            else
              lines << "module #{name}("
              ports.each_with_index do |port, index|
                suffix = index == ports.length - 1 ? "" : ","
                lines << "  #{port}#{suffix}"
              end
              lines << ");"
            end
          else
            lines << "module #{name} #("
            parameters.each_with_index do |parameter, index|
              suffix = index == parameters.length - 1 ? "" : ","
              lines << "  parameter #{parameter} = 0#{suffix}"
            end
            if ports.empty?
              lines << ");"
            else
              lines << ") ("
              ports.each_with_index do |port, index|
                suffix = index == ports.length - 1 ? "" : ","
                lines << "  #{port}#{suffix}"
              end
              lines << ");"
            end
          end

          ports.each do |port|
            lines << "  input #{port};"
          end
          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def build_testbench(top:, ports:, output_ports:, vectors:, clock_name:)
          input_ports = ports.select { |port| %w[input inout].include?(port.fetch(:direction)) }
          lines = []
          lines << "`timescale 1ns/1ps"
          lines << "module tb;"
          lines << ""

          input_ports.each do |port|
            lines << "  reg #{width_decl(port.fetch(:width))}#{port.fetch(:name)};"
          end
          output_ports.each do |port|
            lines << "  wire #{width_decl(port.fetch(:width))}#{port.fetch(:name)};"
          end
          lines << ""

          port_map = ports.map { |port| ".#{port.fetch(:name)}(#{port.fetch(:name)})" }.join(", ")
          lines << "  #{top} uut (#{port_map});"
          lines << ""
          lines << "  initial begin"

          input_ports.each do |port|
            lines << "    #{port.fetch(:name)} = #{literal_for_width(0, port.fetch(:width))};"
          end
          lines << ""

          vectors.each_with_index do |inputs, cycle|
            Array(inputs).each do |name, value|
              width = port_width(ports, name)
              lines << "    #{name} = #{literal_for_width(value, width)};"
            end

            if clock_name.nil?
              lines << "    #1;"
            else
              lines << "    #{clock_name} = 0;"
              lines << "    #1;"
              lines << "    #{clock_name} = 1;"
              lines << "    #1;"
              lines << "    #{clock_name} = 0;"
              lines << "    #1;"
            end

            if output_ports.empty?
              lines << "    $display(\"CYCLE #{cycle}\");"
            else
              format_tokens = output_ports.each_with_index.map { |_port, index| "OUT#{index}=%h" }
              format = ["CYCLE #{cycle}", *format_tokens].join(" ")
              args = output_ports.map { |port| port.fetch(:name) }.join(", ")
              lines << "    $display(\"#{format}\", #{args});"
            end
            lines << ""
          end

          lines << "    $finish;"
          lines << "  end"
          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def width_decl(width)
          normalized = normalize_width(width)
          normalized <= 1 ? "" : "[#{normalized - 1}:0] "
        end

        def literal_for_width(value, width)
          normalized_width = normalize_width(width)
          mask = bit_mask(normalized_width)
          numeric = Integer(value) & mask

          return numeric.to_s if normalized_width <= 1

          digits = (normalized_width.to_f / 4).ceil
          "#{normalized_width}'h#{format("%0#{digits}x", numeric)}"
        end

        def port_width(ports, name)
          port = Array(ports).find { |entry| entry.fetch(:name) == name.to_s }
          return 1 if port.nil?

          port.fetch(:width)
        end

        def parse_simulation_output(stdout:, output_ports:, cycles:)
          output_names = Array(output_ports).map { |port| port.fetch(:name) }
          traces = Array.new(cycles) { {} }
          stdout.to_s.each_line do |line|
            text = line.to_s.strip
            next if text.empty?

            match = text.match(/\ACYCLE\s+(\d+)(?:\s+(.*))?\z/)
            next if match.nil?

            cycle = Integer(match[1])
            next if cycle.negative? || cycle >= traces.length

            payload = match[2].to_s
            output_names.each_with_index do |name, index|
              token = payload[/OUT#{index}=([0-9a-fA-FxXzZ]+)/, 1]
              traces[cycle][name] = normalize_token_value(token)
            end
          end
          traces
        end

        def normalize_token_value(token)
          return nil if token.nil?

          text = token.to_s.strip
          return nil if text.empty?
          return text.downcase if text.match?(/[xXzZ]/)

          text.to_i(16)
        rescue StandardError
          text
        end

        def run_ir_simulation(component:, output_ports:, vectors:, clock_name:, component_index:)
          require "rhdl"

          component_class = component.fetch(:component_class)
          top_name = component.fetch(:source_module_name)
          ir_module = flatten_ir_module(
            module_def: RHDL::Codegen::LIR::Lower.new(component_class, top_name: top_name).build,
            component_index: component_index
          )
          populate_missing_sensitivity_lists!(ir_module)
          ir_json = RHDL::Codegen::IR::IRToJson.convert(ir_module)
          # Use Ruby IR simulation for component parity to preserve >64-bit signal
          # semantics that are truncated by native u64 backends.
          sim = RHDL::Codegen::IR::RubyIrSim.new(ir_json)
          sim.reset if sim.respond_to?(:reset)
          clock_list_idx = resolve_clock_list_idx(sim: sim, clock_name: clock_name)

          output_names = output_ports.map { |port| port.fetch(:name) }
          vectors.map do |inputs|
            apply_ir_inputs(sim: sim, inputs: inputs)

            if clock_name.nil?
              sim.evaluate
            else
              sim.poke(clock_name, 0)
              sim.evaluate
              apply_ir_inputs(sim: sim, inputs: inputs)
              sim.poke(clock_name, 1)
              if !clock_list_idx.nil? && sim.respond_to?(:set_prev_clock)
                sim.set_prev_clock(clock_list_idx, 0)
              end
              if sim.respond_to?(:tick_forced)
                sim.tick_forced
              else
                sim.tick
              end
              apply_ir_inputs(sim: sim, inputs: inputs)
              sim.poke(clock_name, 0)
              sim.evaluate
            end

            output_names.each_with_object({}) do |name, memo|
              memo[name] = sim.peek(name)
            end
          end
        end

        def resolve_clock_list_idx(sim:, clock_name:)
          return nil if clock_name.nil?
          return nil unless sim.respond_to?(:get_signal_idx) && sim.respond_to?(:get_clock_list_idx)

          signal_idx = sim.get_signal_idx(clock_name.to_s)
          return nil if signal_idx.nil? || signal_idx.to_i.negative?

          clock_list_idx = sim.get_clock_list_idx(signal_idx.to_i)
          return nil if clock_list_idx.nil? || clock_list_idx.to_i.negative?

          clock_list_idx.to_i
        rescue StandardError
          nil
        end

        def flatten_ir_module(module_def:, component_index:, stack: Set.new)
          instances = Array(module_def.instances)
          return module_def if instances.empty?

          module_name = module_def.name.to_s
          return module_def if stack.include?(module_name)

          next_stack = stack.dup
          next_stack.add(module_name)

          flattened = RHDL::Codegen::IR::ModuleDef.new(
            name: module_def.name,
            ports: module_def.ports.map { |entry| clone_ir_port(entry) },
            nets: module_def.nets.map { |entry| clone_ir_net(entry) },
            regs: module_def.regs.map { |entry| clone_ir_reg(entry) },
            assigns: module_def.assigns.dup,
            processes: module_def.processes.dup,
            reg_ports: module_def.reg_ports.dup,
            instances: [],
            memories: module_def.memories.map { |entry| clone_ir_memory(entry) },
            write_ports: module_def.write_ports.map { |entry| clone_ir_write_port(entry) },
            sync_read_ports: module_def.sync_read_ports.map { |entry| clone_ir_sync_read_port(entry) },
            parameters: module_def.parameters
          )

          instances.each do |instance|
            child_entry = component_index[instance.module_name.to_s]
            next if child_entry.nil?

            child_ir = RHDL::Codegen::LIR::Lower.new(
              child_entry.fetch(:component_class),
              top_name: instance.module_name.to_s
            ).build
            child_flat = flatten_ir_module(module_def: child_ir, component_index: component_index, stack: next_stack)
            inline_child_instance(parent: flattened, child: child_flat, instance: instance)
          end

          flattened
        end

        def inline_child_instance(parent:, child:, instance:)
          prefix = "#{instance.name}__"
          connection_map = Array(instance.connections).each_with_object({}) do |connection, memo|
            memo[connection.port_name.to_s] = connection.signal
          end

          input_bindings = {}
          output_ports = []
          child.ports.each do |port|
            port_name = port.name.to_s
            direction = port.direction.to_s
            if %w[in input].include?(direction)
              input_bindings[port_name] = connection_signal_expr(
                signal: connection_map[port_name],
                width: port.width,
                parent: parent
              )
            else
              output_ports << port
            end
          end

          child.regs.each do |reg|
            add_reg_unless_present(parent, name: "#{prefix}#{reg.name}", width: reg.width, reset_value: reg.reset_value)
          end
          child.nets.each do |net|
            add_net_unless_present(parent, name: "#{prefix}#{net.name}", width: net.width)
          end
          child.memories.each do |memory|
            add_memory_unless_present(
              parent,
              name: "#{prefix}#{memory.name}",
              depth: memory.depth,
              width: memory.width,
              initial_data: memory.initial_data
            )
          end

          output_ports.each do |port|
            local_name = "#{prefix}#{port.name}"
            if Array(child.reg_ports).map(&:to_s).include?(port.name.to_s)
              add_reg_unless_present(parent, name: local_name, width: port.width, reset_value: nil)
            else
              add_net_unless_present(parent, name: local_name, width: port.width)
            end
          end

          child.assigns.each do |assign|
            parent.assigns << RHDL::Codegen::IR::Assign.new(
              target: rewrite_signal_name(assign.target, prefix: prefix, input_bindings: input_bindings),
              expr: rewrite_ir_expression(assign.expr, prefix: prefix, input_bindings: input_bindings)
            )
          end

          child.processes.each do |process|
            parent.processes << RHDL::Codegen::IR::Process.new(
              name: "#{prefix}#{process.name}",
              clocked: process.clocked,
              clock: process.clock ? rewrite_signal_name(process.clock, prefix: prefix, input_bindings: input_bindings) : nil,
              sensitivity_list: Array(process.sensitivity_list).map do |signal|
                rewrite_signal_name(signal, prefix: prefix, input_bindings: input_bindings)
              end,
              statements: Array(process.statements).map do |statement|
                rewrite_ir_statement(statement, prefix: prefix, input_bindings: input_bindings)
              end.compact,
              initial: process.respond_to?(:initial) ? process.initial : false
            )
          end
          child.write_ports.each do |write_port|
            parent.write_ports << RHDL::Codegen::IR::MemoryWritePort.new(
              memory: "#{prefix}#{write_port.memory}",
              clock: rewrite_signal_name(write_port.clock, prefix: prefix, input_bindings: input_bindings),
              addr: rewrite_ir_expression(write_port.addr, prefix: prefix, input_bindings: input_bindings),
              data: rewrite_ir_expression(write_port.data, prefix: prefix, input_bindings: input_bindings),
              enable: rewrite_ir_expression(write_port.enable, prefix: prefix, input_bindings: input_bindings)
            )
          end
          child.sync_read_ports.each do |read_port|
            parent.sync_read_ports << RHDL::Codegen::IR::MemorySyncReadPort.new(
              memory: "#{prefix}#{read_port.memory}",
              clock: rewrite_signal_name(read_port.clock, prefix: prefix, input_bindings: input_bindings),
              addr: rewrite_ir_expression(read_port.addr, prefix: prefix, input_bindings: input_bindings),
              data: rewrite_signal_name(read_port.data, prefix: prefix, input_bindings: input_bindings),
              enable: read_port.enable ? rewrite_ir_expression(read_port.enable, prefix: prefix, input_bindings: input_bindings) : nil
            )
          end

          output_ports.each do |port|
            connected = connection_target_name(connection_map[port.name.to_s])
            next if connected.empty?

            parent.assigns << RHDL::Codegen::IR::Assign.new(
              target: connected,
              expr: RHDL::Codegen::IR::Signal.new(name: "#{prefix}#{port.name}", width: port.width)
            )
          end
        end

        def connection_signal_expr(signal:, width:, parent:)
          if open_connection_signal?(signal)
            return RHDL::Codegen::IR::Literal.new(value: 0, width: normalize_width(width))
          end

          case signal
          when RHDL::Codegen::IR::Expr
            signal
          when Symbol
            RHDL::Codegen::IR::Signal.new(name: signal.to_s, width: signal_width_in_module(parent, signal))
          when String
            if signal.empty?
              RHDL::Codegen::IR::Literal.new(value: 0, width: normalize_width(width))
            else
              RHDL::Codegen::IR::Signal.new(name: signal, width: signal_width_in_module(parent, signal))
            end
          else
            if signal.nil?
              RHDL::Codegen::IR::Literal.new(value: 0, width: normalize_width(width))
            else
              RHDL::Codegen::IR::Literal.new(value: Integer(signal), width: normalize_width(width))
            end
          end
        rescue StandardError
          RHDL::Codegen::IR::Literal.new(value: 0, width: normalize_width(width))
        end

        def connection_target_name(signal)
          return "" if open_connection_signal?(signal)

          case signal
          when Symbol
            signal.to_s
          when String
            signal
          else
            ""
          end
        end

        def open_connection_signal?(signal)
          return true if signal.nil?
          return true if signal == :__rhdl_unconnected

          token = signal.to_s.strip
          token.empty? || token == "__rhdl_unconnected"
        end

        def rewrite_ir_statement(statement, prefix:, input_bindings:)
          case statement
          when RHDL::Codegen::IR::SeqAssign
            RHDL::Codegen::IR::SeqAssign.new(
              target: rewrite_signal_name(statement.target, prefix: prefix, input_bindings: input_bindings),
              expr: rewrite_ir_expression(statement.expr, prefix: prefix, input_bindings: input_bindings),
              nonblocking: statement.nonblocking
            )
          when RHDL::Codegen::IR::If
            RHDL::Codegen::IR::If.new(
              condition: rewrite_ir_expression(statement.condition, prefix: prefix, input_bindings: input_bindings),
              then_statements: Array(statement.then_statements).map do |inner|
                rewrite_ir_statement(inner, prefix: prefix, input_bindings: input_bindings)
              end.compact,
              else_statements: Array(statement.else_statements).map do |inner|
                rewrite_ir_statement(inner, prefix: prefix, input_bindings: input_bindings)
              end.compact
            )
          when RHDL::Codegen::IR::CaseStmt
            RHDL::Codegen::IR::CaseStmt.new(
              selector: rewrite_ir_expression(statement.selector, prefix: prefix, input_bindings: input_bindings),
              branches: Array(statement.branches).map do |branch|
                RHDL::Codegen::IR::CaseBranch.new(
                  values: Array(branch.values).map do |value|
                    rewrite_ir_expression(value, prefix: prefix, input_bindings: input_bindings)
                  end,
                  statements: Array(branch.statements).map do |inner|
                    rewrite_ir_statement(inner, prefix: prefix, input_bindings: input_bindings)
                  end.compact
                )
              end,
              default_statements: Array(statement.default_statements).map do |inner|
                rewrite_ir_statement(inner, prefix: prefix, input_bindings: input_bindings)
              end.compact
            )
          when RHDL::Codegen::IR::MemoryWrite
            RHDL::Codegen::IR::MemoryWrite.new(
              memory: "#{prefix}#{statement.memory}",
              addr: rewrite_ir_expression(statement.addr, prefix: prefix, input_bindings: input_bindings),
              data: rewrite_ir_expression(statement.data, prefix: prefix, input_bindings: input_bindings)
            )
          else
            statement
          end
        end

        def rewrite_ir_expression(expression, prefix:, input_bindings:)
          case expression
          when RHDL::Codegen::IR::Signal
            binding = input_bindings[expression.name.to_s]
            return binding unless binding.nil?

            RHDL::Codegen::IR::Signal.new(name: "#{prefix}#{expression.name}", width: expression.width)
          when RHDL::Codegen::IR::Literal
            RHDL::Codegen::IR::Literal.new(value: expression.value, width: expression.width)
          when RHDL::Codegen::IR::UnaryOp
            RHDL::Codegen::IR::UnaryOp.new(
              op: expression.op,
              operand: rewrite_ir_expression(expression.operand, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::BinaryOp
            RHDL::Codegen::IR::BinaryOp.new(
              op: expression.op,
              left: rewrite_ir_expression(expression.left, prefix: prefix, input_bindings: input_bindings),
              right: rewrite_ir_expression(expression.right, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::Mux
            RHDL::Codegen::IR::Mux.new(
              condition: rewrite_ir_expression(expression.condition, prefix: prefix, input_bindings: input_bindings),
              when_true: rewrite_ir_expression(expression.when_true, prefix: prefix, input_bindings: input_bindings),
              when_false: rewrite_ir_expression(expression.when_false, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::Concat
            RHDL::Codegen::IR::Concat.new(
              parts: Array(expression.parts).map { |part| rewrite_ir_expression(part, prefix: prefix, input_bindings: input_bindings) },
              width: expression.width
            )
          when RHDL::Codegen::IR::Slice
            RHDL::Codegen::IR::Slice.new(
              base: rewrite_ir_expression(expression.base, prefix: prefix, input_bindings: input_bindings),
              range: expression.range,
              width: expression.width
            )
          when RHDL::Codegen::IR::DynamicSlice
            RHDL::Codegen::IR::DynamicSlice.new(
              base: rewrite_ir_expression(expression.base, prefix: prefix, input_bindings: input_bindings),
              msb: rewrite_ir_expression(expression.msb, prefix: prefix, input_bindings: input_bindings),
              lsb: rewrite_ir_expression(expression.lsb, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::Resize
            RHDL::Codegen::IR::Resize.new(
              expr: rewrite_ir_expression(expression.expr, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::MemoryRead
            RHDL::Codegen::IR::MemoryRead.new(
              memory: "#{prefix}#{expression.memory}",
              addr: rewrite_ir_expression(expression.addr, prefix: prefix, input_bindings: input_bindings),
              width: expression.width
            )
          when RHDL::Codegen::IR::Case
            rewritten_cases = {}
            Array(expression.cases).each do |raw_values, case_expr|
              values = Array(raw_values).map do |value|
                if value.is_a?(RHDL::Codegen::IR::Expr)
                  rewrite_ir_expression(value, prefix: prefix, input_bindings: input_bindings)
                else
                  value
                end
              end
              rewritten_cases[values] = rewrite_ir_expression(case_expr, prefix: prefix, input_bindings: input_bindings)
            end

            RHDL::Codegen::IR::Case.new(
              selector: rewrite_ir_expression(expression.selector, prefix: prefix, input_bindings: input_bindings),
              cases: rewritten_cases,
              default: expression.default ? rewrite_ir_expression(expression.default, prefix: prefix, input_bindings: input_bindings) : nil,
              width: expression.width
            )
          else
            expression
          end
        end

        def rewrite_signal_name(name, prefix:, input_bindings:)
          key = name.to_s
          binding = input_bindings[key]
          if binding.is_a?(RHDL::Codegen::IR::Signal)
            return binding.name.to_s
          end

          "#{prefix}#{key}"
        end

        def add_reg_unless_present(module_def, name:, width:, reset_value:)
          exists = Array(module_def.regs).any? { |entry| entry.name.to_s == name.to_s }
          return if exists

          module_def.regs << RHDL::Codegen::IR::Reg.new(name: name.to_s, width: normalize_width(width), reset_value: reset_value)
        end

        def add_net_unless_present(module_def, name:, width:)
          exists = Array(module_def.nets).any? { |entry| entry.name.to_s == name.to_s }
          return if exists

          module_def.nets << RHDL::Codegen::IR::Net.new(name: name.to_s, width: normalize_width(width))
        end

        def add_memory_unless_present(module_def, name:, depth:, width:, initial_data:)
          exists = Array(module_def.memories).any? { |entry| entry.name.to_s == name.to_s }
          return if exists

          module_def.memories << RHDL::Codegen::IR::Memory.new(
            name: name.to_s,
            depth: normalize_depth(depth),
            width: normalize_width(width),
            initial_data: initial_data.nil? ? nil : Array(initial_data).dup
          )
        rescue TypeError
          nil
        end

        def clone_ir_port(entry)
          RHDL::Codegen::IR::Port.new(
            name: entry.name,
            direction: entry.direction,
            width: normalize_width(entry.width),
            default: entry.respond_to?(:default) ? entry.default : nil
          )
        end

        def clone_ir_net(entry)
          RHDL::Codegen::IR::Net.new(
            name: entry.name,
            width: normalize_width(entry.width)
          )
        end

        def clone_ir_reg(entry)
          RHDL::Codegen::IR::Reg.new(
            name: entry.name,
            width: normalize_width(entry.width),
            reset_value: entry.reset_value
          )
        end

        def clone_ir_memory(entry)
          RHDL::Codegen::IR::Memory.new(
            name: entry.name.to_s,
            depth: normalize_depth(entry.depth),
            width: normalize_width(entry.width),
            read_ports: Array(entry.read_ports).dup,
            write_ports: Array(entry.write_ports).dup,
            initial_data: entry.initial_data.nil? ? nil : Array(entry.initial_data).dup
          )
        end

        def clone_ir_write_port(entry)
          RHDL::Codegen::IR::MemoryWritePort.new(
            memory: entry.memory.to_s,
            clock: entry.clock.to_s,
            addr: entry.addr,
            data: entry.data,
            enable: entry.enable
          )
        end

        def clone_ir_sync_read_port(entry)
          RHDL::Codegen::IR::MemorySyncReadPort.new(
            memory: entry.memory.to_s,
            clock: entry.clock.to_s,
            addr: entry.addr,
            data: entry.data.to_s,
            enable: entry.enable
          )
        end

        def populate_missing_sensitivity_lists!(module_def)
          normalized = Array(module_def.processes).map { |process| normalize_process_sensitivity(process) }
          module_def.processes.clear
          module_def.processes.concat(normalized)
          module_def
        end

        def normalize_process_sensitivity(process)
          initial = process.respond_to?(:initial) ? process.initial : false
          return process if process.clocked || initial

          sensitivity = Array(process.sensitivity_list).map(&:to_s).reject(&:empty?)
          return process unless sensitivity.empty?

          inferred = infer_sensitivity_from_statements(process.statements)
          return process if inferred.empty?

          RHDL::Codegen::IR::Process.new(
            name: process.name,
            clocked: process.clocked,
            clock: process.clock,
            sensitivity_list: inferred,
            statements: process.statements,
            initial: initial
          )
        end

        def infer_sensitivity_from_statements(statements)
          names = []
          Array(statements).each { |statement| collect_statement_sensitivity(statement, names) }
          names.uniq.sort
        end

        def collect_statement_sensitivity(statement, names)
          case statement
          when RHDL::Codegen::IR::SeqAssign
            collect_expression_sensitivity(statement.expr, names)
          when RHDL::Codegen::IR::If
            collect_expression_sensitivity(statement.condition, names)
            Array(statement.then_statements).each { |inner| collect_statement_sensitivity(inner, names) }
            Array(statement.else_statements).each { |inner| collect_statement_sensitivity(inner, names) }
          when RHDL::Codegen::IR::CaseStmt
            collect_expression_sensitivity(statement.selector, names)
            Array(statement.branches).each do |branch|
              Array(branch.values).each { |value| collect_expression_sensitivity(value, names) }
              Array(branch.statements).each { |inner| collect_statement_sensitivity(inner, names) }
            end
            Array(statement.default_statements).each { |inner| collect_statement_sensitivity(inner, names) }
          when RHDL::Codegen::IR::MemoryWrite
            collect_expression_sensitivity(statement.addr, names)
            collect_expression_sensitivity(statement.data, names)
          end
        end

        def collect_expression_sensitivity(expression, names)
          case expression
          when RHDL::Codegen::IR::Signal
            token = expression.name.to_s
            names << token unless token.empty?
          when RHDL::Codegen::IR::UnaryOp
            collect_expression_sensitivity(expression.operand, names)
          when RHDL::Codegen::IR::BinaryOp
            collect_expression_sensitivity(expression.left, names)
            collect_expression_sensitivity(expression.right, names)
          when RHDL::Codegen::IR::Mux
            collect_expression_sensitivity(expression.condition, names)
            collect_expression_sensitivity(expression.when_true, names)
            collect_expression_sensitivity(expression.when_false, names)
          when RHDL::Codegen::IR::Concat
            Array(expression.parts).each { |part| collect_expression_sensitivity(part, names) }
          when RHDL::Codegen::IR::Slice
            collect_expression_sensitivity(expression.base, names)
          when RHDL::Codegen::IR::DynamicSlice
            collect_expression_sensitivity(expression.base, names)
            collect_expression_sensitivity(expression.msb, names)
            collect_expression_sensitivity(expression.lsb, names)
          when RHDL::Codegen::IR::Resize
            collect_expression_sensitivity(expression.expr, names)
          when RHDL::Codegen::IR::MemoryRead
            collect_expression_sensitivity(expression.addr, names)
          when RHDL::Codegen::IR::Case
            collect_expression_sensitivity(expression.selector, names)
            Array(expression.cases).each do |raw_values, case_expr|
              Array(raw_values).each do |value|
                collect_expression_sensitivity(value, names) if value.is_a?(RHDL::Codegen::IR::Expr)
              end
              collect_expression_sensitivity(case_expr, names)
            end
            collect_expression_sensitivity(expression.default, names) if expression.default
          end
        end

        def signal_width_in_module(module_def, signal_name)
          token = signal_name.to_s
          port = Array(module_def.ports).find { |entry| entry.name.to_s == token }
          return normalize_width(port.width) unless port.nil?

          reg = Array(module_def.regs).find { |entry| entry.name.to_s == token }
          return normalize_width(reg.width) unless reg.nil?

          net = Array(module_def.nets).find { |entry| entry.name.to_s == token }
          return normalize_width(net.width) unless net.nil?

          1
        end

        def apply_ir_inputs(sim:, inputs:)
          (inputs || {}).each do |name, value|
            sim.poke(name.to_s, Integer(value))
          end
        end

        def compare_three_way(output_ports:, original_trace:, generated_trace:, ir_trace:)
          cycles = [original_trace.length, generated_trace.length, ir_trace.length].min
          mismatches = []
          signals_compared = 0
          pass_count = 0

          cycles.times do |cycle|
            output_ports.each do |port|
              signal = port.fetch(:name)
              width = port.fetch(:width)
              original = normalize_signal_value(original_trace.dig(cycle, signal), width: width)
              generated_verilog = normalize_signal_value(generated_trace.dig(cycle, signal), width: width)
              generated_ir = normalize_signal_value(ir_trace.dig(cycle, signal), width: width)

              signals_compared += 1
              if equivalent_signal_values?(original, generated_verilog, width: width) &&
                 equivalent_signal_values?(original, generated_ir, width: width) &&
                 equivalent_signal_values?(generated_verilog, generated_ir, width: width)
                pass_count += 1
              else
                mismatches << {
                  cycle: cycle,
                  signal: signal,
                  original: original,
                  generated_verilog: generated_verilog,
                  generated_ir: generated_ir
                }
              end
            end
          end

          {
            summary: {
              cycles_compared: cycles,
              signals_compared: signals_compared,
              pass_count: pass_count,
              fail_count: mismatches.length
            },
            mismatches: mismatches
          }
        end

        def equivalent_signal_values?(left, right, width:)
          return true if left == right
          return true if unknown_pattern_match?(pattern: left, candidate: right, width: width)
          return true if unknown_pattern_match?(pattern: right, candidate: left, width: width)

          false
        end

        def unknown_pattern_match?(pattern:, candidate:, width:)
          pattern_text = pattern.to_s.downcase
          return false unless pattern_text.match?(/[xz]/)

          digits = [((normalize_width(width) + 3) / 4), pattern_text.length].max
          normalized_pattern = pattern_text.rjust(digits, "0")
          candidate_text = value_to_hex_token(candidate, digits: digits)
          return false if candidate_text.nil?

          normalized_pattern.chars.zip(candidate_text.chars).all? do |pattern_char, candidate_char|
            if pattern_char.match?(/[0-9a-f]/)
              pattern_char == candidate_char || candidate_char.match?(/[xz]/)
            else
              true
            end
          end
        end

        def value_to_hex_token(value, digits:)
          case value
          when Integer
            format("%0#{digits}x", value & bit_mask(digits * 4))
          when String
            token = value.downcase.strip
            return nil if token.empty?

            token = token[2..] if token.start_with?("0x")
            token.rjust(digits, "0")[-digits, digits]
          else
            nil
          end
        end

        def normalize_signal_value(value, width:)
          case value
          when Integer
            value & bit_mask(width)
          when String
            return value.downcase if value.match?(/[xXzZ]/)

            Integer(value, 16) & bit_mask(width)
          else
            value
          end
        rescue StandardError
          value
        end

        def normalize_verilog_output(verilog)
          text = verilog.to_s
          text.end_with?("\n") ? text : "#{text}\n"
        end

        def first_error_line(stderr)
          text = stderr.to_s.each_line.map(&:strip).find { |line| !line.empty? }
          text || "unknown error"
        end

        def tool_failure_result(component:, reason:, message:)
          {
            component: component.to_s,
            status: "tool_failure",
            reason: reason.to_s,
            message: message.to_s,
            summary: {
              cycles_compared: 0,
              signals_compared: 0,
              pass_count: 0,
              fail_count: 1
            },
            mismatches: []
          }
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
end
