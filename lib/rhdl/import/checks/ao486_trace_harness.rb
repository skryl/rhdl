# frozen_string_literal: true

require "json"
require "open3"
require "set"
require "tmpdir"
require "yaml"

require_relative "../input_resolver"
require_relative "../missing_module_signature_extractor"

module RHDL
  module Import
    module Checks
      class Ao486TraceHarness
        class << self
          def capture(
            mode:,
            top:,
            out:,
            cycles: 512,
            source_root: nil,
            converted_export_mode: nil,
            cwd: Dir.pwd
          )
            new(
              mode: mode,
              top: top,
              out: out,
              cycles: cycles,
              source_root: source_root,
              converted_export_mode: converted_export_mode,
              cwd: cwd
            ).capture
          end
        end

        def initialize(mode:, top:, out:, cycles:, source_root:, converted_export_mode:, cwd:)
          @mode = mode.to_s.strip.downcase
          @top = top.to_s.strip
          @out = File.expand_path(out.to_s, cwd)
          @cycles = Integer(cycles)
          @source_root = source_root.to_s.strip
          @converted_export_mode = converted_export_mode.to_s.strip
          @cwd = cwd
        end

        def capture
          validate!

          Dir.mktmpdir("ao486_trace_harness") do |work_dir|
            if @mode == "converted_ir"
              return {
                @top => capture_converted_ir_events(work_dir: work_dir)
              }
            end

            contract = source_contract(work_dir: work_dir)
            source_files = Array(contract[:source_files]).map(&:to_s).reject(&:empty?).uniq.sort
            include_dirs = Array(contract[:include_dirs]).map(&:to_s).reject(&:empty?).uniq.sort

            testbench_path = File.join(work_dir, "tb_ao486_trace.sv")
            File.write(testbench_path, testbench_source(top: @top, cycles: @cycles))

            stub_paths = []
            compile_result = compile(
              work_dir: work_dir,
              source_files: source_files,
              include_dirs: include_dirs,
              stub_paths: stub_paths,
              testbench_path: testbench_path
            )

            attempts = 0
            while !compile_result[:status].success? && attempts < 3
              attempts += 1
              missing_modules = extract_missing_modules(compile_result[:stderr])
              break if missing_modules.empty?

              signatures = MissingModuleSignatureExtractor.augment(
                signatures: missing_modules.map { |name| { name: name, ports: [], parameters: [] } },
                source_files: source_files
              )
              stub_paths = write_stub_sources(work_dir: work_dir, signatures: signatures)
              compile_result = compile(
                work_dir: work_dir,
                source_files: source_files,
                include_dirs: include_dirs,
                stub_paths: stub_paths,
                testbench_path: testbench_path
              )
            end

            unless compile_result[:status].success?
              raise ArgumentError, "verilator compile failed: #{first_error_line(compile_result[:stderr])}"
            end

            run_result = run_simulation(work_dir: work_dir)
            unless run_result[:status].success?
              raise ArgumentError, "trace simulation failed: #{first_error_line(run_result[:stderr])}"
            end

            {
              @top => parse_events(run_result[:stdout])
            }
          end
        end

        private

        def validate!
          raise ArgumentError, "mode must be reference, converted, or converted_ir" unless %w[reference converted converted_ir].include?(@mode)
          raise ArgumentError, "top must be ao486 for this harness" unless @top == "ao486"
          raise ArgumentError, "cycles must be positive" if @cycles <= 0
        end

        def source_contract(work_dir:)
          case @mode
          when "reference"
            source_root = @source_root.empty? ? default_source_root : File.expand_path(@source_root, @cwd)
            resolved = InputResolver.resolve(
              src: [source_root],
              compile_unit_filter: "modules_only",
              dependency_resolution: "none",
              cwd: @cwd
            )
            {
              source_files: resolved[:source_files],
              include_dirs: resolved[:include_dirs]
            }
          when "converted"
            source_files = export_converted_sources(work_dir: work_dir, export_mode: converted_export_mode)
            include_dirs = include_dirs_from_report
            include_dirs = include_dirs_from_reference_root if include_dirs.empty?
            generated_dirs = source_files.map { |path| File.dirname(path) }.uniq

            {
              source_files: source_files,
              include_dirs: (generated_dirs + include_dirs).uniq
            }
          else
            raise ArgumentError, "unsupported mode #{@mode.inspect}"
          end
        end

        def default_source_root
          File.expand_path(File.join("examples", "ao486", "reference", "rtl", "ao486"), @cwd)
        end

        def converted_export_mode
          mode = @converted_export_mode.to_s.strip.downcase
          mode.empty? ? "component" : mode
        end

        def export_converted_sources(work_dir:, export_mode:)
          components = load_converted_components
          export_dir = File.join(work_dir, "converted_sources")
          Dir.mkdir(export_dir) unless Dir.exist?(export_dir)

          components.map do |component|
            source_module_name = component.fetch(:source_module_name)
            module_file = component.fetch(:module_file)
            component_class = component.fetch(:component_class)
            class_name = component.fetch(:class_name)
            unless component_class.respond_to?(:to_verilog)
              raise ArgumentError, "component #{class_name} in #{module_file} does not implement .to_verilog"
            end

            verilog = render_component_verilog(
              component_class: component_class,
              top_name: source_module_name,
              export_mode: export_mode,
              module_file: module_file
            )
            output_path = File.join(export_dir, "#{verilog_module_file_name(source_module_name)}.v")
            File.write(output_path, normalize_verilog_output(verilog))
            output_path
          end.sort
        end

        def load_converted_components
          slug = converted_project_slug
          raise ArgumentError, "unable to resolve converted project slug under #{@out}/lib" if slug.empty?

          module_dir = File.join(@out, "lib", slug, "modules")
          module_files = Dir.glob(File.join(module_dir, "**", "*.rb")).sort
          raise ArgumentError, "no converted module files found in #{module_dir}" if module_files.empty?
          ordered_files = ordered_module_files_for_export(slug: slug, module_files: module_files)

          require "rhdl"

          namespace = Module.new
          ordered_files.filter_map do |module_file|
            source = File.read(module_file)
            class_name = extract_component_class_name(source: source)
            next if class_name.nil?

            source_module_name = extract_source_module_name(
              source: source,
              fallback: File.basename(module_file, ".rb")
            )
            namespace.module_eval(source, module_file, 1)
            component_class = constantize_component(name: class_name, root: namespace)

            {
              source_module_name: source_module_name,
              class_name: class_name,
              component_class: component_class,
              module_file: module_file,
              ports: component_ports(component_class)
            }
          end
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

        def ordered_module_files_for_export(slug:, module_files:)
          project_file = File.join(@out, "lib", "#{slug}.rb")
          return module_files unless File.file?(project_file)

          module_index = module_files.each_with_object({}) do |path, memo|
            relative_path = path
              .sub(%r{\A#{Regexp.escape(File.join(@out, "lib"))}/?}, "")
              .sub(%r{\A#{Regexp.escape(File.join(slug, "modules"))}/?}, "")
              .sub(/\.rb\z/, "")

            memo[relative_path] = path
            memo[File.basename(path, ".rb")] = path
          end
          ordered = []

          File.read(project_file).scan(/require_relative\s+["']#{Regexp.escape(slug)}\/modules\/([^"']+)["']/).flatten.each do |basename|
            required = basename.sub(/\.rb\z/, "")
            path = module_index[required] || module_index[File.basename(required)]
            next if path.nil? || ordered.include?(path)

            ordered << path
          end

          ordered.concat(module_files.reject { |path| ordered.include?(path) })
        rescue StandardError
          module_files
        end

        def render_component_verilog(component_class:, top_name:, export_mode:, module_file:)
          if generated_blackbox_stub_module?(module_file: module_file)
            method = component_class.method(:to_verilog)
            return rewrite_module_name(call_verilog_method(method: method, top_name: top_name), top_name: top_name)
          end

          case export_mode.to_s
          when "component"
            canonical_component_verilog(component_class: component_class, top_name: top_name)
          when "dsl_super"
            method = component_class.method(:to_verilog)
            super_method = method.super_method
            if custom_component_verilog_override?(component_class) && !super_method.nil?
              rewrite_module_name(
                call_verilog_method(method: super_method, top_name: top_name),
                top_name: top_name
              )
            else
              canonical_component_verilog(component_class: component_class, top_name: top_name)
            end
          else
            raise ArgumentError, "unsupported converted export mode #{export_mode.inspect} for #{module_file}"
          end
        end

        def generated_blackbox_stub_module?(module_file:)
          return false unless File.file?(module_file)

          File.foreach(module_file) do |line|
            return true if line.include?("generated_blackbox_stub: true")
          end
          false
        rescue StandardError
          false
        end

        def verilog_module_file_name(module_name)
          name = module_name.to_s.strip
          return "module" if name.empty?

          name.gsub(/[^\w$]/, "_")
        end

        def canonical_component_verilog(component_class:, top_name:)
          rewrite_module_name(
            RHDL::Export.verilog(component_class, top_name: top_name),
            top_name: top_name
          )
        end

        def custom_component_verilog_override?(component_class)
          component_class.method(:to_verilog).owner == component_class.singleton_class
        rescue NameError
          false
        end

        def call_verilog_method(method:, top_name:)
          params = Array(method.parameters)
          accepts_keyword = params.any? { |type, name| [:key, :keyreq].include?(type) && name == :top_name } ||
            params.any? { |type, _name| type == :keyrest }
          return method.call(top_name: top_name) if accepts_keyword

          accepts_positional = params.any? { |type, _name| [:req, :opt, :rest].include?(type) }
          return method.call(top_name) if accepts_positional

          method.call
        end

        def rewrite_module_name(verilog, top_name:)
          name = top_name.to_s.strip
          return verilog if name.empty?

          text = verilog.to_s
          text.sub(/\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)/) do
            "module #{name}"
          end
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

        def extract_component_class_name(source:)
          source.to_s[/^\s*class\s+([A-Za-z_][A-Za-z0-9_:]*)\s*<\s*RHDL::Component\b/, 1]
        end

        def extract_source_module_name(source:, fallback:)
          module_name = source.to_s[/^\s*#\s*source_module:\s*([A-Za-z_][A-Za-z0-9_$]*)\s*$/, 1]
          return module_name unless module_name.to_s.empty?

          fallback.to_s
        end

        def constantize_component(name:, root: Object)
          tokens = name.to_s.split("::").reject(&:empty?)
          tokens.inject(root) do |scope, const_name|
            scope.const_get(const_name)
          end
        rescue NameError => e
          if root != Object
            return constantize_component(name: name, root: Object)
          end

          raise ArgumentError, "unable to resolve component class #{name.inspect}: #{e.message}"
        end

        def normalize_verilog_output(verilog)
          text = verilog.to_s
          text = "`timescale 1ns/1ps\n\n#{text}" unless text.include?("`timescale")
          text.end_with?("\n") ? text : "#{text}\n"
        end

        def capture_converted_ir_events(work_dir:)
          _ = work_dir
          components = load_converted_components
          component_index = components.each_with_object({}) do |entry, memo|
            memo[entry.fetch(:source_module_name)] = entry
          end
          component = component_index[@top]
          raise ArgumentError, "converted component #{@top.inspect} not found" if component.nil?

          sim = build_ir_simulator(component: component, component_index: component_index)
          run_ir_trace_simulation(sim: sim)
        end

        def build_ir_simulator(component:, component_index:)
          component_class = component.fetch(:component_class)
          module_def = RHDL::Codegen::LIR::Lower.new(component_class, top_name: @top).build
          flattened = flatten_ir_module(module_def: module_def, component_index: component_index)
          populate_missing_sensitivity_lists!(flattened)
          ir_json = RHDL::Codegen::IR::IRToJson.convert(flattened)
          sim = RHDL::Codegen::IR::RubyIrSim.new(ir_json)
          sim.reset if sim.respond_to?(:reset)
          sim
        end

        def run_ir_trace_simulation(sim:)
          input_names = Array(sim.input_names).map(&:to_s).to_set
          state = initial_ir_input_state(input_names: input_names)
          memory_words = {}
          pending_read_words = 0
          pending_read_address = 0
          apply_ir_inputs(sim: sim, input_names: input_names, inputs: state.merge("clk" => 0))
          sim.evaluate

          events = []
          cycle = 0
          while cycle <= @cycles
            drive = state.dup
            drive["avm_readdatavalid"] = 0 if input_names.include?("avm_readdatavalid")
            drive["io_read_done"] = 0 if input_names.include?("io_read_done")
            drive["io_write_done"] = 0 if input_names.include?("io_write_done")
            drive["rst_n"] = 1 if cycle == 3 && input_names.include?("rst_n")

            if pending_read_words.positive?
              read_value = read_trace_memory_word(memory_words, pending_read_address)
              drive["avm_readdata"] = read_value if input_names.include?("avm_readdata")
              drive["avm_readdatavalid"] = 1 if input_names.include?("avm_readdatavalid")
              pending_read_address = (pending_read_address + 1) & bit_mask(30)
              pending_read_words -= 1
            end

            apply_ir_inputs(sim: sim, input_names: input_names, inputs: drive.merge("clk" => 1))
            sim.tick

            outputs = sample_ir_outputs(sim: sim)
            next_state = drive.dup

            if pending_read_words.zero? && outputs[:avm_read] != 0 && state.fetch("avm_waitrequest", 0).zero?
              pending_read_address = outputs[:avm_address] & bit_mask(30)
              burst_words = Integer(outputs[:avm_burstcount]) & bit_mask(4)
              pending_read_words = burst_words.zero? ? 1 : burst_words
              events << {
                "kind" => "avm_read",
                "cycle" => cycle,
                "address" => outputs[:avm_address],
                "byteenable" => outputs[:avm_byteenable],
                "burstcount" => outputs[:avm_burstcount]
              }
            end

            if outputs[:avm_write] != 0 && state.fetch("avm_waitrequest", 0).zero?
              write_trace_memory_word(
                memory_words,
                address_word: outputs[:avm_address],
                data: outputs[:avm_writedata],
                byteenable: outputs[:avm_byteenable]
              )
              events << {
                "kind" => "avm_write",
                "cycle" => cycle,
                "address" => outputs[:avm_address],
                "byteenable" => outputs[:avm_byteenable],
                "data" => outputs[:avm_writedata]
              }
            end

            if outputs[:io_read_do] != 0
              events << {
                "kind" => "io_read",
                "cycle" => cycle,
                "address" => outputs[:io_read_address],
                "length" => outputs[:io_read_length]
              }
              if input_names.include?("io_read_data")
                next_state["io_read_data"] = (outputs[:io_read_address] ^ 0x00AB_CDEF) & bit_mask(32)
              end
              next_state["io_read_done"] = 1 if input_names.include?("io_read_done")
            end

            if outputs[:io_write_do] != 0
              events << {
                "kind" => "io_write",
                "cycle" => cycle,
                "address" => outputs[:io_write_address],
                "length" => outputs[:io_write_length],
                "data" => outputs[:io_write_data]
              }
              next_state["io_write_done"] = 1 if input_names.include?("io_write_done")
            end

            if outputs[:interrupt_done] != 0
              events << {
                "kind" => "interrupt_done",
                "cycle" => cycle,
                "vector" => (state["interrupt_vector"] || 0) & bit_mask(8)
              }
            end

            events << {
              "kind" => "sample",
              "cycle" => cycle,
              "avm_read" => outputs[:avm_read],
              "avm_write" => outputs[:avm_write],
              "avm_address" => outputs[:avm_address],
              "avm_writedata" => outputs[:avm_writedata],
              "avm_byteenable" => outputs[:avm_byteenable],
              "avm_burstcount" => outputs[:avm_burstcount],
              "io_read_do" => outputs[:io_read_do],
              "io_write_do" => outputs[:io_write_do],
              "io_read_address" => outputs[:io_read_address],
              "io_write_address" => outputs[:io_write_address],
              "interrupt_done" => outputs[:interrupt_done]
            }

            state = next_state
            apply_ir_inputs(sim: sim, input_names: input_names, inputs: state.merge("clk" => 0))
            sim.evaluate
            cycle += 1
          end

          events
        end

        def initial_ir_input_state(input_names:)
          state = {}
          input_names.each { |name| state[name] = 0 }
          state["a20_enable"] = 1 if input_names.include?("a20_enable")
          state["cache_disable"] = 1 if input_names.include?("cache_disable")
          state["interrupt_do"] = 0 if input_names.include?("interrupt_do")
          state["interrupt_vector"] = 0 if input_names.include?("interrupt_vector")
          state["rst_n"] = 0 if input_names.include?("rst_n")
          state["avm_waitrequest"] = 0 if input_names.include?("avm_waitrequest")
          state["avm_readdatavalid"] = 0 if input_names.include?("avm_readdatavalid")
          state["avm_readdata"] = 0 if input_names.include?("avm_readdata")
          state["dma_address"] = 0 if input_names.include?("dma_address")
          state["dma_16bit"] = 0 if input_names.include?("dma_16bit")
          state["dma_write"] = 0 if input_names.include?("dma_write")
          state["dma_writedata"] = 0 if input_names.include?("dma_writedata")
          state["dma_read"] = 0 if input_names.include?("dma_read")
          state["io_read_data"] = 0 if input_names.include?("io_read_data")
          state["io_read_done"] = 0 if input_names.include?("io_read_done")
          state["io_write_done"] = 0 if input_names.include?("io_write_done")
          state
        end

        def sample_ir_outputs(sim:)
          {
            avm_read: read_ir_signal(sim: sim, name: "avm_read", width: 1),
            avm_write: read_ir_signal(sim: sim, name: "avm_write", width: 1),
            avm_address: read_ir_signal(sim: sim, name: "avm_address", width: 30),
            avm_writedata: read_ir_signal(sim: sim, name: "avm_writedata", width: 32),
            avm_byteenable: read_ir_signal(sim: sim, name: "avm_byteenable", width: 4),
            avm_burstcount: read_ir_signal(sim: sim, name: "avm_burstcount", width: 4),
            io_read_do: read_ir_signal(sim: sim, name: "io_read_do", width: 1),
            io_write_do: read_ir_signal(sim: sim, name: "io_write_do", width: 1),
            io_read_address: read_ir_signal(sim: sim, name: "io_read_address", width: 16),
            io_write_address: read_ir_signal(sim: sim, name: "io_write_address", width: 16),
            io_read_length: read_ir_signal(sim: sim, name: "io_read_length", width: 3),
            io_write_length: read_ir_signal(sim: sim, name: "io_write_length", width: 3),
            io_write_data: read_ir_signal(sim: sim, name: "io_write_data", width: 32),
            interrupt_done: read_ir_signal(sim: sim, name: "interrupt_done", width: 1)
          }
        end

        def read_ir_signal(sim:, name:, width:)
          value = Integer(sim.peek(name.to_s))
          value & bit_mask(width)
        rescue StandardError
          0
        end

        def apply_ir_inputs(sim:, input_names:, inputs:)
          (inputs || {}).each do |name, value|
            key = name.to_s
            next unless input_names.include?(key)

            sim.poke(key, Integer(value))
          end
        end

        def bit_mask(width)
          normalized = width.to_i
          return 0 if normalized <= 0

          (1 << normalized) - 1
        end

        def trace_seed_word(address_word)
          normalized = Integer(address_word) & bit_mask(30)
          (normalized ^ 0x1357_9BDF) & bit_mask(32)
        rescue StandardError
          0
        end

        def read_trace_memory_word(memory_words, address_word)
          normalized = Integer(address_word) & bit_mask(30)
          Integer(memory_words.fetch(normalized, trace_seed_word(normalized))) & bit_mask(32)
        rescue StandardError
          0
        end

        def write_trace_memory_word(memory_words, address_word:, data:, byteenable:)
          normalized = Integer(address_word) & bit_mask(30)
          current = read_trace_memory_word(memory_words, normalized)
          incoming = Integer(data) & bit_mask(32)
          mask = Integer(byteenable) & bit_mask(4)
          merged = current

          4.times do |byte_index|
            next if ((mask >> byte_index) & 1).zero?

            byte_shift = byte_index * 8
            byte_mask = 0xFF << byte_shift
            merged = (merged & ~byte_mask) | (incoming & byte_mask)
          end

          memory_words[normalized] = merged & bit_mask(32)
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

          slice_output_bindings = Hash.new { |hash, key| hash[key] = [] }

          output_ports.each do |port|
            connection_target = normalize_connection_target(connection_map[port.name.to_s])
            next if connection_target.nil?

            child_output = RHDL::Codegen::IR::Signal.new(
              name: "#{prefix}#{port.name}",
              width: normalize_width(port.width)
            )

            case connection_target[:kind]
            when :signal
              parent.assigns << RHDL::Codegen::IR::Assign.new(
                target: connection_target.fetch(:name),
                expr: child_output
              )
            when :slice
              slice_output_bindings[connection_target.fetch(:name)] << {
                msb: connection_target.fetch(:msb),
                lsb: connection_target.fetch(:lsb),
                expr: child_output
              }
            end
          end

          slice_output_bindings.each do |base_name, parts|
            base_width = signal_width_in_module(parent, base_name)
            base_expr = RHDL::Codegen::IR::Signal.new(name: base_name, width: base_width)
            merged_expr = parts.sort_by { |part| part.fetch(:lsb) }.reduce(base_expr) do |current, part|
              merge_slice_binding(
                base_expr: current,
                base_width: base_width,
                msb: part.fetch(:msb),
                lsb: part.fetch(:lsb),
                value_expr: part.fetch(:expr)
              )
            end

            parent.assigns << RHDL::Codegen::IR::Assign.new(
              target: base_name,
              expr: merged_expr
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

        def normalize_connection_target(signal)
          return nil if open_connection_signal?(signal)

          case signal
          when Symbol
            { kind: :signal, name: signal.to_s }
          when String
            token = signal.to_s
            return nil if token.empty?

            { kind: :signal, name: token }
          when RHDL::Codegen::IR::Signal
            { kind: :signal, name: signal.name.to_s }
          when RHDL::Codegen::IR::Slice
            normalize_slice_connection_target(signal)
          else
            nil
          end
        end

        def open_connection_signal?(signal)
          return true if signal.nil?
          return true if signal == :__rhdl_unconnected

          token = signal.to_s.strip
          token.empty? || token == "__rhdl_unconnected"
        end

        def normalize_slice_connection_target(signal)
          base = signal.base
          return nil unless base.is_a?(RHDL::Codegen::IR::Signal)

          range = signal.range
          return nil unless range.is_a?(Range)
          return nil unless range.begin.is_a?(Integer) && range.end.is_a?(Integer)

          msb = [range.begin, range.end].max
          lsb = [range.begin, range.end].min
          return nil if lsb.negative?
          return nil if msb < lsb

          {
            kind: :slice,
            name: base.name.to_s,
            msb: msb,
            lsb: lsb
          }
        end

        def merge_slice_binding(base_expr:, base_width:, msb:, lsb:, value_expr:)
          width = msb - lsb + 1
          return base_expr if width <= 0

          base_width = normalize_width(base_width)
          return base_expr if base_width <= 0

          full_mask = bit_mask(base_width)
          slice_mask = ((1 << width) - 1) << lsb
          clear_mask = full_mask ^ slice_mask

          base_expr = ensure_expr_width(base_expr, base_width)
          value_expr = ensure_expr_width(value_expr, width)

          cleared = RHDL::Codegen::IR::BinaryOp.new(
            op: :&,
            left: base_expr,
            right: RHDL::Codegen::IR::Literal.new(value: clear_mask, width: base_width),
            width: base_width
          )

          placed =
            if lsb.zero?
              ensure_expr_width(value_expr, base_width)
            else
              RHDL::Codegen::IR::BinaryOp.new(
                op: :<<,
                left: ensure_expr_width(value_expr, base_width),
                right: RHDL::Codegen::IR::Literal.new(value: lsb, width: base_width),
                width: base_width
              )
            end

          RHDL::Codegen::IR::BinaryOp.new(
            op: :|,
            left: cleared,
            right: placed,
            width: base_width
          )
        end

        def ensure_expr_width(expression, width)
          normalized_width = normalize_width(width)
          return expression if expression.width == normalized_width

          RHDL::Codegen::IR::Resize.new(expr: expression, width: normalized_width)
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

        def include_dirs_from_report
          report_path = File.join(@out, "reports", "import_report.json")
          return [] unless File.file?(report_path)

          report = JSON.parse(File.read(report_path), max_nesting: false)
          options = value_for(value_for(report, :project), :options)
          Array(value_for(options, :include_dirs)).map(&:to_s).map(&:strip).reject(&:empty?)
        rescue StandardError
          []
        end

        def include_dirs_from_reference_root
          resolved = InputResolver.resolve(
            src: [reference_root_for_harness],
            compile_unit_filter: "modules_only",
            dependency_resolution: "none",
            cwd: @cwd
          )
          Array(resolved[:include_dirs]).map(&:to_s).map(&:strip).reject(&:empty?)
        rescue StandardError
          []
        end

        def reference_root_for_harness
          @source_root.empty? ? default_source_root : File.expand_path(@source_root, @cwd)
        end

        def compile(work_dir:, source_files:, include_dirs:, stub_paths:, testbench_path:)
          obj_dir = File.join(work_dir, "obj_dir")
          args = [
            "verilator",
            "--binary",
            "--timing",
            "--top-module",
            "tb_ao486_trace",
            "--Mdir",
            obj_dir,
            "-Wno-fatal",
            "-Wno-lint",
            "-Wno-ALWNEVER",
            "-Wno-TIMESCALEMOD",
            "-Wno-PINMISSING"
          ]
          include_dirs.each do |include_dir|
            args << "-I#{include_dir}"
          end
          args.concat(source_files)
          args.concat(stub_paths)
          args << testbench_path

          stdout, stderr, status = Open3.capture3(*args)
          {
            stdout: stdout,
            stderr: stderr,
            status: status
          }
        end

        def write_stub_sources(work_dir:, signatures:)
          stub_dir = File.join(work_dir, "stubs")
          Dir.mkdir(stub_dir) unless Dir.exist?(stub_dir)

          Array(signatures).map do |signature|
            name = value_for(signature, :name).to_s
            next if name.empty?

            path = File.join(stub_dir, "#{name}.v")
            File.write(path, emit_stub_verilog(signature))
            path
          end.compact.sort
        end

        def emit_stub_verilog(signature)
          name = value_for(signature, :name).to_s
          ports = Array(value_for(signature, :ports)).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
          parameters = Array(value_for(signature, :parameters)).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort

          lines = []
          lines << "module #{name}"
          if parameters.any?
            lines << "#("
            parameters.each_with_index do |parameter, index|
              suffix = index == parameters.length - 1 ? "" : ","
              lines << "  parameter #{parameter} = 0#{suffix}"
            end
            lines << ")"
          end

          if ports.empty?
            lines << ";"
          else
            lines << "("
            ports.each_with_index do |port, index|
              suffix = index == ports.length - 1 ? "" : ","
              lines << "  #{port}#{suffix}"
            end
            lines << ");"
            ports.each do |port|
              lines << "  input #{port};"
            end
          end
          lines << "endmodule"
          lines.join("\n") + "\n"
        end

        def extract_missing_modules(stderr)
          stderr.to_s.scan(/module:\s+'([A-Za-z_][A-Za-z0-9_$]*)'/).flatten.uniq.sort
        end

        def run_simulation(work_dir:)
          binary_path = File.join(work_dir, "obj_dir", "Vtb_ao486_trace")
          stdout, stderr, status = Open3.capture3(binary_path)
          {
            stdout: stdout,
            stderr: stderr,
            status: status
          }
        end

        def parse_events(stdout)
          stdout.to_s.each_line.filter_map do |line|
            text = line.strip
            case text
            when /\AEV avm_read (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "avm_read",
                "cycle" => Regexp.last_match(1).to_i(10),
                "address" => Regexp.last_match(2).to_i(16),
                "byteenable" => Regexp.last_match(3).to_i(16),
                "burstcount" => Regexp.last_match(4).to_i(16)
              }
            when /\AEV avm_write (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "avm_write",
                "cycle" => Regexp.last_match(1).to_i(10),
                "address" => Regexp.last_match(2).to_i(16),
                "byteenable" => Regexp.last_match(3).to_i(16),
                "data" => Regexp.last_match(4).to_i(16)
              }
            when /\AEV io_read (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "io_read",
                "cycle" => Regexp.last_match(1).to_i(10),
                "address" => Regexp.last_match(2).to_i(16),
                "length" => Regexp.last_match(3).to_i(16)
              }
            when /\AEV io_write (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "io_write",
                "cycle" => Regexp.last_match(1).to_i(10),
                "address" => Regexp.last_match(2).to_i(16),
                "length" => Regexp.last_match(3).to_i(16),
                "data" => Regexp.last_match(4).to_i(16)
              }
            when /\AEV interrupt_done (\d+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "interrupt_done",
                "cycle" => Regexp.last_match(1).to_i(10),
                "vector" => Regexp.last_match(2).to_i(16)
              }
            when /\AEV sample (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              {
                "kind" => "sample",
                "cycle" => Regexp.last_match(1).to_i(10),
                "avm_read" => Regexp.last_match(2).to_i(16),
                "avm_write" => Regexp.last_match(3).to_i(16),
                "avm_address" => Regexp.last_match(4).to_i(16),
                "avm_writedata" => Regexp.last_match(5).to_i(16),
                "avm_byteenable" => Regexp.last_match(6).to_i(16),
                "avm_burstcount" => Regexp.last_match(7).to_i(16),
                "io_read_do" => Regexp.last_match(8).to_i(16),
                "io_write_do" => Regexp.last_match(9).to_i(16),
                "io_read_address" => Regexp.last_match(10).to_i(16),
                "io_write_address" => Regexp.last_match(11).to_i(16),
                "interrupt_done" => Regexp.last_match(12).to_i(16)
              }
            else
              nil
            end
          end
        end

        def first_error_line(stderr)
          line = stderr.to_s.each_line.find { |entry| !entry.strip.empty? }
          message = line.to_s.strip
          message.empty? ? "unknown error" : message
        end

        def testbench_source(top:, cycles:)
          <<~VERILOG
            `timescale 1ns/1ps

            module tb_ao486_trace;
              reg clk = 1'b0;
              reg rst_n = 1'b0;

              reg a20_enable = 1'b1;
              reg cache_disable = 1'b1;
              reg interrupt_do = 1'b0;
              reg [7:0] interrupt_vector = 8'h00;
              wire interrupt_done;

              wire [29:0] avm_address;
              wire [31:0] avm_writedata;
              wire [3:0] avm_byteenable;
              wire [3:0] avm_burstcount;
              wire avm_write;
              wire avm_read;
              reg avm_waitrequest = 1'b0;
              reg avm_readdatavalid = 1'b0;
              reg [31:0] avm_readdata = 32'h0;

              reg [23:0] dma_address = 24'h0;
              reg dma_16bit = 1'b0;
              reg dma_write = 1'b0;
              reg [15:0] dma_writedata = 16'h0;
              reg dma_read = 1'b0;
              wire [15:0] dma_readdata;
              wire dma_readdatavalid;
              wire dma_waitrequest;

              wire io_read_do;
              wire [15:0] io_read_address;
              wire [2:0] io_read_length;
              reg [31:0] io_read_data = 32'h0;
              reg io_read_done = 1'b0;

              wire io_write_do;
              wire [15:0] io_write_address;
              wire [2:0] io_write_length;
              wire [31:0] io_write_data;
              reg io_write_done = 1'b0;

              localparam integer MEM_WRITE_LOG_DEPTH = 4096;
              integer mem_write_count = 0;
              reg [29:0] mem_write_addr [0:MEM_WRITE_LOG_DEPTH-1];
              reg [31:0] mem_write_data [0:MEM_WRITE_LOG_DEPTH-1];
              integer pending_read_words = 0;
              reg [29:0] pending_read_addr = 30'h0;
              reg [31:0] read_data = 32'h0;

              function [31:0] mem_seed_word;
                input [29:0] address_word;
                begin
                  mem_seed_word = ({2'b0, address_word} ^ 32'h1357_9BDF);
                end
              endfunction

              function [31:0] mem_read_word;
                input [29:0] address_word;
                integer idx;
                reg [31:0] value;
                begin
                  value = mem_seed_word(address_word);
                  for (idx = 0; idx < mem_write_count; idx = idx + 1) begin
                    if (mem_write_addr[idx] == address_word) begin
                      value = mem_write_data[idx];
                    end
                  end
                  mem_read_word = value;
                end
              endfunction

              task mem_write_word;
                input [29:0] address_word;
                input [31:0] data_word;
                input [3:0] byteenable_word;
                reg [31:0] current_word;
                reg [31:0] merged_word;
                begin
                  current_word = mem_read_word(address_word);
                  merged_word = current_word;
                  if (byteenable_word[0]) merged_word[7:0] = data_word[7:0];
                  if (byteenable_word[1]) merged_word[15:8] = data_word[15:8];
                  if (byteenable_word[2]) merged_word[23:16] = data_word[23:16];
                  if (byteenable_word[3]) merged_word[31:24] = data_word[31:24];

                  if (mem_write_count < MEM_WRITE_LOG_DEPTH) begin
                    mem_write_addr[mem_write_count] = address_word;
                    mem_write_data[mem_write_count] = merged_word;
                    mem_write_count = mem_write_count + 1;
                  end else begin
                    mem_write_addr[MEM_WRITE_LOG_DEPTH-1] = address_word;
                    mem_write_data[MEM_WRITE_LOG_DEPTH-1] = merged_word;
                  end
                end
              endtask

              #{top} dut (
                .clk(clk),
                .rst_n(rst_n),
                .a20_enable(a20_enable),
                .cache_disable(cache_disable),
                .interrupt_do(interrupt_do),
                .interrupt_vector(interrupt_vector),
                .interrupt_done(interrupt_done),

                .avm_address(avm_address),
                .avm_writedata(avm_writedata),
                .avm_byteenable(avm_byteenable),
                .avm_burstcount(avm_burstcount),
                .avm_write(avm_write),
                .avm_read(avm_read),
                .avm_waitrequest(avm_waitrequest),
                .avm_readdatavalid(avm_readdatavalid),
                .avm_readdata(avm_readdata),

                .dma_address(dma_address),
                .dma_16bit(dma_16bit),
                .dma_write(dma_write),
                .dma_writedata(dma_writedata),
                .dma_read(dma_read),
                .dma_readdata(dma_readdata),
                .dma_readdatavalid(dma_readdatavalid),
                .dma_waitrequest(dma_waitrequest),

                .io_read_do(io_read_do),
                .io_read_address(io_read_address),
                .io_read_length(io_read_length),
                .io_read_data(io_read_data),
                .io_read_done(io_read_done),
                .io_write_do(io_write_do),
                .io_write_address(io_write_address),
                .io_write_length(io_write_length),
                .io_write_data(io_write_data),
                .io_write_done(io_write_done)
              );

              always #5 clk = ~clk;

              integer cycle = 0;
              always @(posedge clk) begin
                cycle <= cycle + 1;

                avm_readdatavalid <= 1'b0;
                io_read_done <= 1'b0;
                io_write_done <= 1'b0;

                if (cycle == 3) begin
                  rst_n <= 1'b1;
                end

                if (pending_read_words > 0) begin
                  read_data = mem_read_word(pending_read_addr);
                  avm_readdata <= read_data;
                  avm_readdatavalid <= 1'b1;
                  pending_read_addr = pending_read_addr + 30'd1;
                  pending_read_words = pending_read_words - 1;
                end

                if (pending_read_words == 0 && avm_read && !avm_waitrequest) begin
                  pending_read_addr = avm_address;
                  pending_read_words = (avm_burstcount == 0) ? 1 : avm_burstcount;
                  $display("EV avm_read %0d %08x %1x %1x", cycle, {2'b0, avm_address}, avm_byteenable, avm_burstcount);
                end

                if (avm_write && !avm_waitrequest) begin
                  mem_write_word(avm_address, avm_writedata, avm_byteenable);
                  $display("EV avm_write %0d %08x %1x %08x", cycle, {2'b0, avm_address}, avm_byteenable, avm_writedata);
                end

                if (io_read_do) begin
                  io_read_data <= ({16'h0, io_read_address} ^ 32'h00AB_CDEF);
                  io_read_done <= 1'b1;
                  $display("EV io_read %0d %04x %1x", cycle, io_read_address, io_read_length);
                end

                if (io_write_do) begin
                  io_write_done <= 1'b1;
                  $display("EV io_write %0d %04x %1x %08x", cycle, io_write_address, io_write_length, io_write_data);
                end

                if (interrupt_done) begin
                  $display("EV interrupt_done %0d %02x", cycle, interrupt_vector);
                end

                $display("EV sample %0d %1x %1x %08x %08x %1x %1x %1x %1x %04x %04x %1x",
                         cycle,
                         avm_read,
                         avm_write,
                         {2'b0, avm_address},
                         avm_writedata,
                         avm_byteenable,
                         avm_burstcount,
                         io_read_do,
                         io_write_do,
                         io_read_address,
                         io_write_address,
                         interrupt_done);

                if (cycle >= #{cycles}) begin
                  $finish;
                end
              end
            endmodule
          VERILOG
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
