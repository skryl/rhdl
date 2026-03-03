# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "set"
require "tmpdir"

require_relative "ao486_trace_harness"
require_relative "../missing_module_signature_extractor"

module RHDL
  module Import
    module Checks
      class Ao486ProgramParityHarness
        DEFAULT_CYCLES = 256
        MAX_COMPILE_ATTEMPTS = 8
        TOP_NAME = "ao486"
        DATA_CHECK_ADDRESS = 0x0000_0200
        DEFAULT_VERILOG_TOOL = "iverilog"
        PROGRAM_BASE_ADDRESS = 0x000F_FFF0
        DEFAULT_IR_BACKEND = :compiler
        DEFAULT_IR_ALLOW_FALLBACK = false

        class << self
          def run(**kwargs)
            new(**kwargs).run
          end

          def binary_layout_from_file(binary_path:, data_addresses:, base_address: PROGRAM_BASE_ADDRESS, cwd: Dir.pwd)
            path = File.expand_path(binary_path.to_s, cwd)
            bytes = File.binread(path).bytes
            binary_layout(
              bytes: bytes,
              base_address: base_address,
              data_addresses: data_addresses
            )
          end

          def assemble_program_layout(asm_source:, data_addresses:)
            register_codes = {
              "ax" => 0, "cx" => 1, "dx" => 2, "bx" => 3,
              "sp" => 4, "bp" => 5, "si" => 6, "di" => 7
            }
            bytes = {}
            address = 0

            asm_source.to_s.each_line do |raw_line|
              line = raw_line.to_s.split(";", 2).first.to_s.strip
              next if line.empty?

              if line.match?(/\Abits\s+16\z/i)
                next
              elsif (org_match = line.match(/\Aorg\s+(.+)\z/i))
                address = parse_asm_number(org_match[1]) & 0xFFFF_FFFF
              elsif (jmp_far = line.match(/\Ajmp\s+far\s+([^:]+)\s*:\s*([^\s]+)\z/i))
                segment = parse_asm_number(jmp_far[1]) & 0xFFFF
                offset = parse_asm_number(jmp_far[2]) & 0xFFFF
                address = append_bytes(
                  bytes: bytes,
                  address: address,
                  values: [0xEA, offset & 0xFF, (offset >> 8) & 0xFF, segment & 0xFF, (segment >> 8) & 0xFF]
                )
              elsif line.match?(/\Anop\z/i)
                address = append_bytes(bytes: bytes, address: address, values: [0x90])
              elsif line.match?(/\Ajmp\s+\$\z/i)
                address = append_bytes(bytes: bytes, address: address, values: [0xEB, 0xFE])
              elsif (mov_imm = line.match(/\Amov\s+([A-Za-z]{2})\s*,\s*([^\[][^,]*)\z/))
                destination = mov_imm[1].downcase
                immediate = parse_asm_number(mov_imm[2]) & 0xFFFF
                register_code = register_codes[destination]
                raise ArgumentError, "unsupported asm register #{destination.inspect}" if register_code.nil?

                address = append_bytes(
                  bytes: bytes,
                  address: address,
                  values: [0xB8 + register_code, immediate & 0xFF, (immediate >> 8) & 0xFF]
                )
              elsif (mov_mem = line.match(/\Amov\s+\[\s*([^\]]+)\s*\]\s*,\s*([A-Za-z]{2})\z/))
                memory_address = parse_asm_number(mov_mem[1]) & 0xFFFF
                source = mov_mem[2].downcase
                source_code = register_codes[source]
                raise ArgumentError, "unsupported asm register #{source.inspect}" if source_code.nil?

                if source == "ax"
                  address = append_bytes(
                    bytes: bytes,
                    address: address,
                    values: [0xA3, memory_address & 0xFF, (memory_address >> 8) & 0xFF]
                  )
                else
                  modrm = 0x06 | ((source_code & 0x7) << 3)
                  address = append_bytes(
                    bytes: bytes,
                    address: address,
                    values: [0x89, modrm, memory_address & 0xFF, (memory_address >> 8) & 0xFF]
                  )
                end
              elsif (add_rr = line.match(/\Aadd\s+([A-Za-z]{2})\s*,\s*([A-Za-z]{2})\z/))
                destination = add_rr[1].downcase
                source = add_rr[2].downcase
                destination_code = register_codes[destination]
                source_code = register_codes[source]
                raise ArgumentError, "unsupported asm add destination #{destination.inspect}" if destination_code.nil?
                raise ArgumentError, "unsupported asm add source #{source.inspect}" if source_code.nil?

                modrm = 0xC0 | ((source_code & 0x7) << 3) | (destination_code & 0x7)
                address = append_bytes(bytes: bytes, address: address, values: [0x01, modrm])
              else
                raise ArgumentError, "unsupported asm line #{line.inspect}"
              end
            end

            program_word_addresses = bytes.keys.map { |entry| entry & ~0x3 }.uniq.sort
            tracked_addresses = (program_word_addresses + Array(data_addresses).map { |entry| Integer(entry) & 0xFFFF_FFFF }).uniq.sort
            memory_words = tracked_addresses.each_with_object({}) do |word_address, memo|
              memo[word_address] = word_from_bytes(bytes: bytes, address: word_address)
            end

            # Keep high aliases deterministic when bus addresses are sign-extended.
            {
              0xFFFF_FFF0 => 0x000F_FFF0,
              0xFFFF_FFF4 => 0x000F_FFF4,
              0xFFFF_FFF8 => 0x000F_FFF8,
              0xFFFF_FFFC => 0x000F_FFFC
            }.each do |alias_address, canonical_address|
              next unless memory_words.key?(canonical_address)

              memory_words[alias_address] = memory_words.fetch(canonical_address)
            end

            fetch_addresses = program_word_addresses.dup
            fetch_addresses << 0xFFFF_FFF0 if memory_words.key?(0xFFFF_FFF0)
            fetch_addresses << 0xFFFF_FFF4 if memory_words.key?(0xFFFF_FFF4)
            fetch_addresses << 0xFFFF_FFF8 if memory_words.key?(0xFFFF_FFF8)
            fetch_addresses << 0xFFFF_FFFC if memory_words.key?(0xFFFF_FFFC)
            required_instruction_addresses = [0x000F_FFF0, 0x000F_FFF4, 0x000F_FFF8]
            required_instruction_words = required_instruction_addresses.filter_map { |word_address| memory_words[word_address] }

            {
              memory_words: memory_words,
              tracked_addresses: memory_words.keys.sort,
              fetch_addresses: fetch_addresses.uniq.sort,
              required_instruction_words: required_instruction_words
            }
          end

          private

          def append_bytes(bytes:, address:, values:)
            current = Integer(address) & 0xFFFF_FFFF
            Array(values).each do |value|
              bytes[current] = Integer(value) & 0xFF
              current = (current + 1) & 0xFFFF_FFFF
            end
            current
          end

          def parse_asm_number(token)
            text = token.to_s.strip.downcase
            raise ArgumentError, "empty asm numeric token" if text.empty?

            return Integer(text, 16) if text.start_with?("0x")
            return Integer(text, 10) if text.match?(/\A[+-]?\d+\z/)

            raise ArgumentError, "unsupported asm numeric token #{token.inspect}"
          end

          def word_from_bytes(bytes:, address:)
            base = Integer(address) & 0xFFFF_FFFC
            b0 = Integer(bytes.fetch(base + 0, 0)) & 0xFF
            b1 = Integer(bytes.fetch(base + 1, 0)) & 0xFF
            b2 = Integer(bytes.fetch(base + 2, 0)) & 0xFF
            b3 = Integer(bytes.fetch(base + 3, 0)) & 0xFF
            b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
          end

          def binary_layout(bytes:, base_address:, data_addresses:)
            raise ArgumentError, "binary program data cannot be empty" if bytes.empty?

            bytes_by_address = {}
            memory_words = {}
            base = Integer(base_address) & 0xFFFF_FFFF
            Array(bytes).each_with_index do |value, index|
              bytes_by_address[(base + index) & 0xFFFF_FFFF] = Integer(value) & 0xFF
            end
            inject_reset_vector!(bytes_by_address: bytes_by_address, target_linear_address: base) unless base == PROGRAM_BASE_ADDRESS

            program_word_addresses = bytes_by_address.keys.map { |entry| entry & 0xFFFF_FFFC }.uniq.sort
            tracked_addresses = (program_word_addresses + Array(data_addresses).map { |entry| Integer(entry) & 0xFFFF_FFFF }).uniq.sort

            tracked_addresses.each do |word_address|
              memory_words[word_address] = word_from_bytes(bytes: bytes_by_address, address: word_address)
            end

            {
              bytes: bytes_by_address,
              memory_words: memory_words,
              tracked_addresses: memory_words.keys.sort,
              fetch_addresses: fetch_addresses_for_binary(
                base: base,
                memory_words: memory_words,
                program_word_addresses: program_word_addresses
              ),
              required_instruction_words: required_instruction_words_for_binary(
                base: base,
                memory_words: memory_words
              )
            }
          end

          private

          def inject_reset_vector!(bytes_by_address:, target_linear_address:)
            target = Integer(target_linear_address) & 0xFFFF_FFFF
            offset = target & 0x0000_000F
            segment = (target >> 4) & 0x0000_FFFF
            reset_vector = [0xEA, offset & 0xFF, (offset >> 8) & 0xFF, segment & 0xFF, (segment >> 8) & 0xFF]
            reset_vector += Array.new(11, 0x90)

            reset_vector.each_with_index do |value, index|
              address = (PROGRAM_BASE_ADDRESS + index) & 0xFFFF_FFFF
              bytes_by_address[address] = Integer(value) & 0xFF
            end
          end

          def fetch_addresses_for_binary(base:, memory_words:, program_word_addresses:)
            program_addresses = program_word_addresses.dup
            program_addresses << (base | 0x000F_0000) if base == 0x000F_FFF0

            canonical_alias = {
              0xFFFF_FFF0 => 0x000F_FFF0,
              0xFFFF_FFF4 => 0x000F_FFF4,
              0xFFFF_FFF8 => 0x000F_FFF8,
              0xFFFF_FFFC => 0x000F_FFFC
            }.each do |alias_address, canonical_address|
              next unless memory_words.key?(canonical_address)

              memory_words[alias_address] = memory_words.fetch(canonical_address)
              program_addresses << alias_address
            end

            program_addresses.uniq.sort
          end

          def required_instruction_words_for_binary(base:, memory_words:)
            instruction_addresses = if memory_words.key?(PROGRAM_BASE_ADDRESS)
              [PROGRAM_BASE_ADDRESS, PROGRAM_BASE_ADDRESS + 4, PROGRAM_BASE_ADDRESS + 8]
            else
              [base, base + 4, base + 8]
            end

            instruction_addresses
              .map { |entry| memory_words.fetch(entry & 0xFFFF_FFFF, nil) }
              .compact
          end
        end

        PROGRAM_ASM_SOURCE = <<~ASM.freeze
          bits 16
          org 0x000FFFE0
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          nop
          org 0x000FFFF0
          mov ax, 0x1234
          mov bx, 0x00F0
          add ax, bx
          mov [0x0200], ax
          mov cx, 0xABCD
          mov [0x0202], cx
          jmp $
        ASM

        PROGRAM_LAYOUT = assemble_program_layout(
          asm_source: PROGRAM_ASM_SOURCE,
          data_addresses: [DATA_CHECK_ADDRESS]
        ).freeze
        MIN_REQUIRED_INSTRUCTION_HITS = 3

        def initialize(
          out:,
          top: TOP_NAME,
          cycles: DEFAULT_CYCLES,
          source_root: nil,
          cwd: Dir.pwd,
          program_layout: PROGRAM_LAYOUT,
          program_binary: nil,
          program_binary_data_addresses: [DATA_CHECK_ADDRESS],
          program_base_address: PROGRAM_BASE_ADDRESS,
          ir_backend: DEFAULT_IR_BACKEND,
          ir_allow_fallback: DEFAULT_IR_ALLOW_FALLBACK,
          verilog_tool: DEFAULT_VERILOG_TOOL,
          data_check_addresses: nil
        )
          @out = File.expand_path(out.to_s, cwd)
          @top = top.to_s.strip
          @cycles = normalize_cycles(cycles)
          @source_root = source_root.to_s.strip
          @cwd = cwd
          @program_layout = resolve_program_layout(
            program_layout: program_layout,
            program_binary: program_binary,
            program_binary_data_addresses: program_binary_data_addresses,
            program_base_address: program_base_address
          )
          @ir_backend = ir_backend.to_sym
          @ir_allow_fallback = !!ir_allow_fallback
          @verilog_tool = verilog_tool.to_s.strip.downcase
          @data_check_addresses = if data_check_addresses.nil?
            Array(program_binary_data_addresses)
          else
            data_addresses_from_input(data_check_addresses)
          end
          @data_check_addresses = Array(@data_check_addresses).map do |address|
            Integer(address) & 0xFFFF_FFFF
          end
          @data_check_addresses = [DATA_CHECK_ADDRESS] if @data_check_addresses.empty?
        end

        def run
          validate!

          Dir.mktmpdir("ao486_program_parity") do |work_dir|
            reference_contract = source_contract(mode: "reference", work_dir: File.join(work_dir, "reference_sources"))
            converted_contract = source_contract(mode: "converted", work_dir: File.join(work_dir, "converted_sources"))
            ir_simulator = build_ir_simulator

            reference_thread = Thread.new do
              run_verilog_program(
                label: "reference",
                source_files: reference_contract.fetch(:source_files),
                include_dirs: reference_contract.fetch(:include_dirs),
                work_dir: File.join(work_dir, "reference")
              )
            end
            generated_verilog_thread = Thread.new do
              run_verilog_program(
                label: "generated_verilog",
                source_files: converted_contract.fetch(:source_files),
                include_dirs: converted_contract.fetch(:include_dirs),
                work_dir: File.join(work_dir, "generated_verilog")
              )
            end
            generated_ir_thread = Thread.new do
              run_ir_program(sim: ir_simulator)
            end

            reference = reference_thread.value
            generated_verilog = generated_verilog_thread.value
            generated_ir = generated_ir_thread.value
            comparison = compare_runs(
              reference: reference,
              generated_verilog: generated_verilog,
              generated_ir: generated_ir
            )

            {
              top: @top,
              status: comparison.fetch(:mismatches).empty? ? "pass" : "fail",
              summary: comparison.fetch(:summary),
              mismatches: comparison.fetch(:mismatches),
              traces: {
                reference: reference,
                generated_verilog: generated_verilog,
                generated_ir: generated_ir
              }
            }
          end
        rescue StandardError => e
          {
            top: @top,
            status: "tool_failure",
            reason: "program_parity_error",
            message: e.message,
            summary: {
              cycles_requested: @cycles,
              pc_events_compared: 0,
              instruction_events_compared: 0,
              write_events_compared: 0,
              memory_words_compared: 0,
              pass_count: 0,
              fail_count: 1,
              first_mismatch: nil
            },
            mismatches: []
          }
        end

        def data_addresses_for_execution
          @data_check_addresses
        end

        def program_memory_words
          @program_layout.fetch(:memory_words)
            .to_h
            .each_with_object({}) do |entry, memo|
            address = coerce_numeric_key(entry[0])
            memo[address] = Integer(entry[1]) & 0xFFFFFFFF
          end
        end

        def program_tracked_addresses
          Array(@program_layout.fetch(:tracked_addresses)).map { |entry| Integer(entry) & 0xFFFF_FFFF }.uniq.sort
        end

        def program_fetch_addresses
          Array(@program_layout.fetch(:fetch_addresses))
            .map { |entry| Integer(entry) & 0xFFFF_FFFF }
            .uniq
            .sort
        end

        def required_instruction_words
          Array(@program_layout.fetch(:required_instruction_words)).map { |entry| Integer(entry) & 0xFFFFFFFF }
        end

        private

        def validate!
          raise ArgumentError, "top must be #{TOP_NAME} for ao486 program parity" unless @top == TOP_NAME
          raise ArgumentError, "cycles must be positive" if @cycles <= 0
          raise ArgumentError, "unsupported verilog simulator #{@verilog_tool.inspect}" unless %w[iverilog verilator].include?(@verilog_tool)
        end

        def resolve_program_layout(program_layout:, program_binary:, program_binary_data_addresses:, program_base_address:)
          return normalize_program_layout(program_layout: program_layout) if program_binary.to_s.empty?

          self.class.binary_layout_from_file(
            binary_path: program_binary,
            data_addresses: program_binary_data_addresses,
            base_address: program_base_address,
            cwd: @cwd
          )
        end

        def normalize_cycles(value)
          Integer(value || DEFAULT_CYCLES)
          rescue ArgumentError, TypeError
          DEFAULT_CYCLES
        end

        def normalize_program_layout(program_layout:)
          layout = program_layout.to_h
          {
            memory_words: layout.fetch(:memory_words).to_h,
            tracked_addresses: layout.fetch(:tracked_addresses),
            fetch_addresses: layout.fetch(:fetch_addresses),
            required_instruction_words: layout.fetch(:required_instruction_words)
          }
        rescue KeyError
          raise ArgumentError, "program layout missing required fields"
        end

        def data_addresses_from_input(values)
          Array(values).flat_map do |value|
            next if value.nil?

            if value.is_a?(Array)
              value
            else
              value
            end
          end.compact
        end

        def coerce_numeric_key(value)
          return value.to_i if value.is_a?(Integer)

          text = value.to_s.strip
          return 0 if text.empty?

          return Integer(text) if text.match?(%r{\A[+-]?\d+\z})
          return Integer(text, 16) if text.match?(%r{\A0x[0-9A-Fa-f]+\z})

          Integer(text, 16)
        rescue ArgumentError, TypeError
          0
        end

        def source_contract(mode:, work_dir:)
          FileUtils.mkdir_p(work_dir)
          helper = Ao486TraceHarness.new(
            mode: mode,
            top: @top,
            out: @out,
            cycles: @cycles,
            source_root: @source_root,
            converted_export_mode: nil,
            cwd: @cwd
          )
          contract = helper.send(:source_contract, work_dir: work_dir)

          {
            source_files: Array(contract[:source_files]).map(&:to_s).reject(&:empty?).uniq.sort,
            include_dirs: Array(contract[:include_dirs]).map(&:to_s).reject(&:empty?).uniq.sort
          }
        end

        def build_ir_simulator
          helper = Ao486TraceHarness.new(
            mode: "converted_ir",
            top: @top,
            out: @out,
            cycles: @cycles,
            source_root: @source_root,
            converted_export_mode: nil,
            cwd: @cwd
          )
          components = helper.send(:load_converted_components)
          component_index = components.each_with_object({}) do |entry, memo|
            memo[entry.fetch(:source_module_name)] = entry
          end
          top_component = component_index[@top]
          raise ArgumentError, "converted component #{@top.inspect} not found under #{@out}" if top_component.nil?

          module_def = RHDL::Codegen::LIR::Lower.new(top_component.fetch(:component_class), top_name: @top).build
          flattened = helper.send(:flatten_ir_module, module_def: module_def, component_index: component_index)
          helper.send(:populate_missing_sensitivity_lists!, flattened)
          ir_json = RHDL::Codegen::IR::IRToJson.convert(flattened)
          normalized_ir_json = normalize_i64_compatible_json(ir_json)
          normalized_ir_json = if normalized_ir_json.is_a?(String)
            normalized_ir_json
          else
            JSON.generate(normalized_ir_json, max_nesting: false)
          end

          sim = RHDL::Codegen::IR::IrSimulator.new(
            normalized_ir_json,
            backend: @ir_backend,
            allow_fallback: @ir_allow_fallback
          )
          unless sim.respond_to?(:runner_kind) && sim.runner_kind == :ao486
            raise ArgumentError,
              "ao486 IR runner extension unavailable for backend=#{@ir_backend.inspect} " \
              "(runner_kind=#{sim.respond_to?(:runner_kind) ? sim.runner_kind.inspect : 'none'})"
          end

          sim.reset if sim.respond_to?(:reset)
          sim
        end

        def normalize_i64_compatible_json(value)
          case value
          when String
            text = value.lstrip
            return value unless text.start_with?("{", "[")

            parsed = JSON.parse(value, max_nesting: false)
            normalize_i64_compatible_json(parsed)
          when Hash
            value.each_with_object({}) do |(key, entry), memo|
              memo[key] = normalize_i64_compatible_json(entry)
            end
          when Array
            value.map { |entry| normalize_i64_compatible_json(entry) }
          when Integer
            if value > ((1 << 63) - 1)
              (value & ((1 << 64) - 1)) - (1 << 64)
            elsif value < -(1 << 63)
              value % (1 << 63)
            else
              value
            end
          else
            value
          end
        end

        def run_verilog_program(label:, source_files:, include_dirs:, work_dir:)
          FileUtils.mkdir_p(work_dir)
          testbench_path = File.join(work_dir, "tb_ao486_program.sv")
          File.write(testbench_path, testbench_source(top: @top, cycles: @cycles))

          selected_sources = Array(source_files).map(&:to_s).reject(&:empty?).uniq.sort
          stub_paths = []
          compile_result = compile_verilog(
            work_dir: work_dir,
            source_files: selected_sources,
            include_dirs: include_dirs,
            testbench_path: testbench_path,
            stub_paths: stub_paths
          )

          attempts = 0
          while !compile_result[:status].success? && attempts < MAX_COMPILE_ATTEMPTS
            attempts += 1
            missing = extract_missing_modules(compile_result[:stderr])
            break if missing.empty?

            discovered_sources = resolve_missing_module_sources(
              missing_modules: missing,
              include_dirs: include_dirs,
              selected_sources: selected_sources
            )
            unless discovered_sources.empty?
              selected_sources = (selected_sources + discovered_sources.values).uniq.sort
              compile_result = compile_verilog(
                work_dir: work_dir,
                source_files: selected_sources,
                include_dirs: include_dirs,
                testbench_path: testbench_path,
                stub_paths: stub_paths
              )
              next
            end

            signatures = MissingModuleSignatureExtractor.augment(
              signatures: missing.map { |name| { name: name, ports: [], parameters: [] } },
              source_files: selected_sources
            )
            stub_paths = write_stub_sources(work_dir: work_dir, signatures: signatures)
            compile_result = compile_verilog(
              work_dir: work_dir,
              source_files: selected_sources,
              include_dirs: include_dirs,
              testbench_path: testbench_path,
              stub_paths: stub_paths
            )
          end

          unless compile_result[:status].success?
            raise ArgumentError, "#{label} compile failed: #{first_error_line(compile_result[:stderr])}"
          end

          simulation_command = if @verilog_tool == "verilator"
            run_command_binary(work_dir: work_dir)
          else
            ["vvp", "sim.out"]
          end
          run_result = run_command(command: simulation_command, chdir: work_dir)
          unless run_result[:status].success?
            raise ArgumentError, "#{label} simulation failed: #{first_error_line(run_result[:stderr])}"
          end

          parse_program_trace(stdout: run_result[:stdout])
        end

        def run_ir_program(sim:)
          if ao486_runner_batched_supported?(sim)
            return run_ir_program_batched(sim: sim)
          end

          input_names = Array(sim.input_names).map(&:to_s).to_set
          state = initial_input_state(input_names: input_names)
          memory = program_memory_words.dup
          pc_sequence = []
          instruction_sequence = []
          memory_writes = []
          pending_read_words = 0
          pending_read_address = 0

          apply_ir_inputs(sim: sim, input_names: input_names, inputs: state.merge("clk" => 0))
          sim.evaluate

          cycle = 0
          while cycle <= @cycles
            drive = state.dup
            drive["avm_readdatavalid"] = 0 if input_names.include?("avm_readdatavalid")
            drive["io_read_done"] = 0 if input_names.include?("io_read_done")
            drive["io_write_done"] = 0 if input_names.include?("io_write_done")
            drive["rst_n"] = rst_n_for_cycle(cycle) if input_names.include?("rst_n")

            if pending_read_words.positive?
              read_value = read_memory_word(memory, pending_read_address)
              drive["avm_readdata"] = read_value if input_names.include?("avm_readdata")
              drive["avm_readdatavalid"] = 1 if input_names.include?("avm_readdatavalid")

              if program_fetch_address?(pending_read_address)
                pc_sequence << pending_read_address
                instruction_sequence << read_value
              end

              pending_read_address = (pending_read_address + 4) & bit_mask(32)
              pending_read_words -= 1
            end

            apply_ir_inputs(sim: sim, input_names: input_names, inputs: drive.merge("clk" => 0))
            sim.evaluate
            outputs = sample_ir_outputs(sim: sim)
            next_state = drive.dup

            if pending_read_words.zero? && outputs[:avm_read] != 0 && state.fetch("avm_waitrequest", 0).zero?
              pending_read_address = (outputs[:avm_address] & bit_mask(30)) << 2
              burst_words = Integer(outputs[:avm_burstcount]) & bit_mask(4)
              pending_read_words = burst_words.zero? ? 1 : burst_words
            end

            if outputs[:avm_write] != 0 && state.fetch("avm_waitrequest", 0).zero?
              address = (outputs[:avm_address] & bit_mask(30)) << 2
              write_memory_word(
                memory,
                address: address,
                data: outputs[:avm_writedata],
                byteenable: outputs[:avm_byteenable]
              )
              memory_writes << {
                "cycle" => cycle,
                "address" => address,
                "data" => outputs[:avm_writedata],
                "byteenable" => outputs[:avm_byteenable]
              }
            end

            if outputs[:io_read_do] != 0
              next_state["io_read_data"] = 0 if input_names.include?("io_read_data")
              next_state["io_read_done"] = 1 if input_names.include?("io_read_done")
            end
            next_state["io_write_done"] = 1 if outputs[:io_write_do] != 0 && input_names.include?("io_write_done")

            apply_ir_inputs(sim: sim, input_names: input_names, inputs: drive.merge("clk" => 1))
            sim.tick

            state = next_state
            apply_ir_inputs(sim: sim, input_names: input_names, inputs: state.merge("clk" => 0))
            sim.evaluate
            cycle += 1
          end

          {
            "pc_sequence" => pc_sequence,
            "instruction_sequence" => instruction_sequence,
            "memory_writes" => memory_writes,
            "memory_contents" => tracked_memory_snapshot(memory)
          }
        end

        def ao486_runner_batched_supported?(sim)
          return false unless sim.respond_to?(:runner_kind)
          return false unless sim.respond_to?(:runner_run_cycles)
          return false unless sim.respond_to?(:runner_write_memory)
          return false unless sim.respond_to?(:runner_read_memory)
          return false unless sim.respond_to?(:runner_ao486_take_events)

          sim.runner_kind == :ao486
        rescue StandardError
          false
        end

        def run_ir_program_batched(sim:)
          sim.reset if sim.respond_to?(:reset)
          load_runner_program_memory(sim: sim, memory_words: program_memory_words)
          sim.runner_ao486_take_events # clear any reset/load residual events
          sim.runner_run_cycles(@cycles + 1)

          trace = parse_runner_events_trace(events_text: sim.runner_ao486_take_events.to_s)
          trace["memory_contents"] = tracked_runner_memory_snapshot(sim: sim)
          trace
        end

        def load_runner_program_memory(sim:, memory_words:)
          memory_words.to_h.each do |address, value|
            normalized_address = Integer(address) & bit_mask(32)
            normalized_value = Integer(value) & bit_mask(32)
            bytes = [normalized_value].pack("L<")
            sim.runner_write_memory(normalized_address, bytes, mapped: false)
          end
        end

        def parse_runner_events_trace(events_text:)
          fetch_addresses = program_fetch_addresses.to_set
          pc_sequence = []
          instruction_sequence = []
          memory_writes = []

          events_text.to_s.each_line do |line|
            text = line.to_s.strip
            next if text.empty?

            case text
            when /\AEV IF (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              address = Regexp.last_match(2).to_i(16) & bit_mask(32)
              next unless fetch_addresses.include?(address)

              data = Regexp.last_match(3).to_i(16) & bit_mask(32)
              pc_sequence << address
              instruction_sequence << data
            when /\AEV WR (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              memory_writes << {
                "cycle" => Integer(Regexp.last_match(1)),
                "address" => Regexp.last_match(2).to_i(16) & bit_mask(32),
                "data" => Regexp.last_match(3).to_i(16) & bit_mask(32),
                "byteenable" => Regexp.last_match(4).to_i(16) & bit_mask(4)
              }
            end
          end

          {
            "pc_sequence" => pc_sequence,
            "instruction_sequence" => instruction_sequence,
            "memory_writes" => memory_writes
          }
        end

        def tracked_runner_memory_snapshot(sim:)
          program_tracked_addresses.each_with_object({}) do |address, memo|
            bytes = Array(sim.runner_read_memory(address & bit_mask(32), 4, mapped: false))
            b0 = Integer(bytes[0] || 0) & 0xFF
            b1 = Integer(bytes[1] || 0) & 0xFF
            b2 = Integer(bytes[2] || 0) & 0xFF
            b3 = Integer(bytes[3] || 0) & 0xFF
            memo[format("%08x", address & bit_mask(32))] = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
          end
        end

        def compare_runs(reference:, generated_verilog:, generated_ir:)
          mismatches = []
          pass_count = 0

          pc_stats = compare_sequence_field(
            kind: "pc_sequence",
            reference: reference.fetch("pc_sequence"),
            generated_verilog: generated_verilog.fetch("pc_sequence"),
            generated_ir: generated_ir.fetch("pc_sequence"),
            mismatches: mismatches
          )
          pass_count += pc_stats.fetch(:pass_count)

          instruction_stats = compare_sequence_field(
            kind: "instruction_sequence",
            reference: reference.fetch("instruction_sequence"),
            generated_verilog: generated_verilog.fetch("instruction_sequence"),
            generated_ir: generated_ir.fetch("instruction_sequence"),
            mismatches: mismatches
          )
          pass_count += instruction_stats.fetch(:pass_count)

          writes_stats = compare_sequence_field(
            kind: "memory_writes",
            reference: reference.fetch("memory_writes"),
            generated_verilog: generated_verilog.fetch("memory_writes"),
            generated_ir: generated_ir.fetch("memory_writes"),
            mismatches: mismatches
          )
          pass_count += writes_stats.fetch(:pass_count)

          memory_stats = compare_memory_contents(
            reference: reference.fetch("memory_contents"),
            generated_verilog: generated_verilog.fetch("memory_contents"),
            generated_ir: generated_ir.fetch("memory_contents"),
            mismatches: mismatches
          )
          pass_count += memory_stats.fetch(:pass_count)

          enforce_program_execution(
            reference: reference,
            generated_verilog: generated_verilog,
            generated_ir: generated_ir,
            mismatches: mismatches
          )

          {
            summary: {
              cycles_requested: @cycles,
              pc_events_compared: pc_stats.fetch(:items_compared),
              instruction_events_compared: instruction_stats.fetch(:items_compared),
              write_events_compared: writes_stats.fetch(:items_compared),
              memory_words_compared: memory_stats.fetch(:items_compared),
              pass_count: pass_count,
              fail_count: mismatches.length,
              first_mismatch: mismatches.first
            },
            mismatches: mismatches
          }
        end

        def compare_sequence_field(kind:, reference:, generated_verilog:, generated_ir:, mismatches:)
          reference_values = Array(reference)
          generated_values = Array(generated_verilog)
          ir_values = Array(generated_ir)
          items_compared = [reference_values.length, generated_values.length, ir_values.length].max
          pass_count = 0

          items_compared.times do |index|
            left = canonicalize(reference_values[index])
            middle = canonicalize(generated_values[index])
            right = canonicalize(ir_values[index])
            if left == middle && left == right
              pass_count += 1
            else
              mismatches << {
                "kind" => kind,
                "index" => index,
                "reference" => left,
                "generated_verilog" => middle,
                "generated_ir" => right
              }
            end
          end

          { items_compared: items_compared, pass_count: pass_count }
        end

        def compare_memory_contents(reference:, generated_verilog:, generated_ir:, mismatches:)
          addresses = (
            reference.keys +
            generated_verilog.keys +
            generated_ir.keys
          ).map(&:to_s).uniq.sort
          pass_count = 0

          addresses.each_with_index do |address, index|
            left = canonicalize(reference[address])
            middle = canonicalize(generated_verilog[address])
            right = canonicalize(generated_ir[address])
            if left == middle && left == right
              pass_count += 1
            else
              mismatches << {
                "kind" => "memory_contents",
                "index" => index,
                "address" => address,
                "reference" => left,
                "generated_verilog" => middle,
                "generated_ir" => right
              }
            end
          end

          { items_compared: addresses.length, pass_count: pass_count }
        end

        def enforce_program_execution(reference:, generated_verilog:, generated_ir:, mismatches:)
          checks = {
            "reference" => execution_signature(reference),
            "generated_verilog" => execution_signature(generated_verilog),
            "generated_ir" => execution_signature(generated_ir)
          }

          pc_counts = checks.transform_values { |entry| entry.fetch("pc_event_count") }
          data_word_map = checks.transform_values { |entry| entry.fetch("data_words", {}) }
          instruction_hits = checks.transform_values { |entry| entry.fetch("required_instruction_hits") }
          executed = checks.transform_values { |entry| entry.fetch("executed") }

          unless executed.values.all?
            mismatches << {
              "kind" => "program_execution",
              "reference" => checks["reference"],
              "generated_verilog" => checks["generated_verilog"],
              "generated_ir" => checks["generated_ir"]
            }
          end

          unless pc_counts.values.uniq.length == 1
            mismatches << {
              "kind" => "program_pc_count",
              "reference" => pc_counts["reference"],
              "generated_verilog" => pc_counts["generated_verilog"],
              "generated_ir" => pc_counts["generated_ir"]
            }
          end

          unless data_word_map.values.uniq.length == 1
            mismatches << {
              "kind" => "program_data_word",
              "reference" => data_word_map["reference"],
              "generated_verilog" => data_word_map["generated_verilog"],
              "generated_ir" => data_word_map["generated_ir"]
            }
          end

          unless instruction_hits.values.uniq.length == 1
            mismatches << {
              "kind" => "program_instruction_hits",
              "reference" => instruction_hits["reference"],
              "generated_verilog" => instruction_hits["generated_verilog"],
              "generated_ir" => instruction_hits["generated_ir"]
            }
          end

          unless instruction_hits.values.all? { |count| Integer(count) >= MIN_REQUIRED_INSTRUCTION_HITS }
            mismatches << {
              "kind" => "program_instruction_execution",
              "reference" => checks["reference"],
              "generated_verilog" => checks["generated_verilog"],
              "generated_ir" => checks["generated_ir"]
            }
          end
        end

        def execution_signature(run_result)
          memory = run_result.fetch("memory_contents")
          data_words = data_addresses_for_execution.each_with_object({}) do |address, memo|
            normalized = Integer(address) & bit_mask(32)
            memo[format("%08x", normalized)] = Integer(memory.fetch(format("%08x", normalized), 0)) & bit_mask(32)
          end
          pc_sequence = Array(run_result["pc_sequence"]).map { |value| Integer(value) & bit_mask(32) }
          instruction_sequence = Array(run_result["instruction_sequence"]).map { |value| Integer(value) & bit_mask(32) }
          required_instruction_hits = required_instruction_words.count do |word|
            instruction_sequence.include?(Integer(word) & bit_mask(32))
          end
          pc_event_count = pc_sequence.length
          reset_vector_seen = !program_fetch_addresses.empty? && (
            pc_sequence.include?(program_fetch_addresses.min) || pc_sequence.include?(program_fetch_addresses.max)
          )
          {
            "pc_event_count" => pc_event_count,
            "data_words" => data_words,
            "data_word_0200" => data_words.fetch(format("%08x", DATA_CHECK_ADDRESS), 0),
            "required_instruction_hits" => required_instruction_hits,
            "reset_vector_seen" => reset_vector_seen,
            "executed" => pc_event_count.positive? && reset_vector_seen && required_instruction_hits >= MIN_REQUIRED_INSTRUCTION_HITS
          }
        end

        def canonicalize(value)
          case value
          when Hash
            value.keys.map(&:to_s).sort.each_with_object({}) do |key, memo|
              memo[key] = canonicalize(value[key] || value[key.to_sym])
            end
          when Array
            value.map { |entry| canonicalize(entry) }
          else
            value
          end
        end

        def compile_verilog(work_dir:, source_files:, include_dirs:, testbench_path:, stub_paths:)
          include_args = Array(include_dirs).map { |dir| "-I#{dir}" }
          if @verilog_tool == "verilator"
            command = [
              "verilator",
              "-Wall",
              "-Wno-fatal",
              "--binary",
              "--sv",
              "--top-module",
              "tb_ao486_program",
              *include_args,
              *Array(source_files).map(&:to_s),
              *Array(stub_paths).map(&:to_s),
              testbench_path.to_s
            ]
          else
            command = [
              "iverilog",
              "-g2012",
              "-s",
              "tb_ao486_program",
              "-o",
              "sim.out",
              *include_args,
              *Array(source_files).map(&:to_s),
              *Array(stub_paths).map(&:to_s),
              testbench_path.to_s
            ]
          end
          run_command(command: command, chdir: work_dir)
        end

        def run_command_binary(work_dir:)
          binary = File.join(work_dir, "obj_dir", "Vtb_ao486_program")
          [binary]
        end

        def run_command(command:, chdir:)
          stdout, stderr, status = Open3.capture3(*Array(command).map(&:to_s), chdir: chdir.to_s)
          { stdout: stdout.to_s, stderr: stderr.to_s, status: status }
        end

        def extract_missing_modules(stderr)
          text = stderr.to_s
          names = text.scan(/Unknown module type:\s*([A-Za-z_][A-Za-z0-9_$]*)/).flatten
          names += text.scan(/module:\s*'([A-Za-z_][A-Za-z0-9_$]*)'/).flatten
          names += text.scan(/Cannot find file containing module:\s*'([A-Za-z_][A-Za-z0-9_$]*)'/).flatten
          names += text.scan(/module\s+([A-Za-z_][A-Za-z0-9_$]*)\s+not found/i).flatten
          names += text.scan(/Module not found:\s*([A-Za-z_][A-Za-z0-9_$]*)/).flatten
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
          ports = (
            Array(value_for(signature, :ports)).map(&:to_s) +
            known_stub_ports(module_name: name)
          ).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
          parameters = (
            Array(value_for(signature, :parameters)).map(&:to_s) +
            known_stub_parameters(module_name: name)
          ).map(&:to_s).map(&:strip).reject(&:empty?).uniq.sort
          parameter_lookup = parameters.each_with_object({}) do |parameter, memo|
            memo[parameter.downcase] = parameter
          end
          port_specs = ports.map do |port|
            hint = stub_port_hint(module_name: name, port_name: port)
            {
              name: port,
              direction: hint.fetch(:direction, "input"),
              width: stub_port_width(hint.fetch(:width, 1), parameter_lookup: parameter_lookup)
            }
          end

          module_key = name.downcase
          if module_key == "altdpram"
            return emit_altdpram_stub_verilog(name: name, parameter_specs: parameters, port_specs: port_specs)
          end
          if module_key == "altsyncram"
            return emit_altsyncram_stub_verilog(name: name, parameter_specs: parameters, port_specs: port_specs)
          end

          emit_generic_stub_verilog(name: name, port_specs: port_specs, parameter_specs: parameters)
        end

        def emit_generic_stub_verilog(name:, port_specs:, parameter_specs:)
          lines = stub_module_header_lines(name: name, port_specs: port_specs, parameter_specs: parameter_specs)
          port_specs.each do |port|
            width_decl = verilog_width_decl(port.fetch(:width))
            lines << "  #{port.fetch(:direction)} #{width_decl}#{port.fetch(:name)};"
          end
          port_specs.select { |port| port.fetch(:direction) == "output" }.each do |port|
            lines << "  assign #{port.fetch(:name)} = #{verilog_zero_literal(port.fetch(:width))};"
          end
          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def emit_altdpram_stub_verilog(name:, parameter_specs:, port_specs:)
          lines = stub_module_header_lines(name: name, port_specs: port_specs, parameter_specs: parameter_specs)
          port_specs.each do |port|
            width_decl = verilog_width_decl(port.fetch(:width))
            lines << "  #{port.fetch(:direction)} #{width_decl}#{port.fetch(:name)};"
          end
          lines << "  localparam integer SAFE_WIDTH = (width > 0) ? width : 1;"
          lines << "  localparam integer SAFE_WIDTHAD = (widthad > 0) ? widthad : 1;"
          lines << "  localparam integer SAFE_WIDTH_BYTEENA = (width_byteena > 0) ? width_byteena : 1;"
          lines << "  localparam integer SAFE_DEPTH = (1 << SAFE_WIDTHAD);"
          lines << "  localparam integer SAFE_BYTE_COUNT = (SAFE_WIDTH + 7) / 8;"
          lines << ""
          lines << "  reg [SAFE_WIDTH-1:0] mem [0:SAFE_DEPTH-1];"
          lines << "  reg [SAFE_WIDTH-1:0] merged_word;"
          lines << "  integer init_i;"
          lines << "  integer byte_i;"
          lines << ""
          lines << "  wire [SAFE_WIDTHAD-1:0] wr_addr = wraddress[SAFE_WIDTHAD-1:0];"
          lines << "  wire [SAFE_WIDTHAD-1:0] rd_addr = rdaddress[SAFE_WIDTHAD-1:0];"
          lines << "  wire wr_clock_en = (inclocken === 1'b0) ? 1'b0 : 1'b1;"
          lines << "  wire wr_addr_stall = (wraddressstall === 1'b1) ? 1'b1 : 1'b0;"
          lines << "  wire wr_en = (wren === 1'b1) && wr_clock_en && !wr_addr_stall;"
          lines << ""
          lines << "  initial begin"
          lines << "    for (init_i = 0; init_i < SAFE_DEPTH; init_i = init_i + 1) begin"
          lines << "      mem[init_i] = {SAFE_WIDTH{1'b0}};"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  always @* begin"
          lines << "    merged_word = mem[wr_addr];"
          lines << "    if (SAFE_WIDTH_BYTEENA <= 1 || SAFE_BYTE_COUNT <= 1) begin"
          lines << "      merged_word = data;"
          lines << "    end else begin"
          lines << "      for (byte_i = 0; byte_i < SAFE_BYTE_COUNT; byte_i = byte_i + 1) begin"
          lines << "        if (byte_i < SAFE_WIDTH_BYTEENA && byteena[byte_i]) begin"
          lines << "          merged_word[(byte_i * 8) +: 8] = data[(byte_i * 8) +: 8];"
          lines << "        end"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  always @(posedge inclock) begin"
          lines << "    if (wr_en) begin"
          lines << "      mem[wr_addr] <= merged_word;"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  assign q = mem[rd_addr];"
          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def emit_altsyncram_stub_verilog(name:, parameter_specs:, port_specs:)
          lines = stub_module_header_lines(name: name, port_specs: port_specs, parameter_specs: parameter_specs)
          port_specs.each do |port|
            width_decl = verilog_width_decl(port.fetch(:width))
            lines << "  #{port.fetch(:direction)} #{width_decl}#{port.fetch(:name)};"
          end
          lines << "  localparam integer SAFE_WIDTH_A = (width_a > 0) ? width_a : 1;"
          lines << "  localparam integer SAFE_WIDTH_B = (width_b > 0) ? width_b : 1;"
          lines << "  localparam integer SAFE_WIDTHAD_A = (widthad_a > 0) ? widthad_a : 1;"
          lines << "  localparam integer SAFE_WIDTHAD_B = (widthad_b > 0) ? widthad_b : 1;"
          lines << "  localparam integer SAFE_WIDTH_BYTEENA_A = (width_byteena_a > 0) ? width_byteena_a : 1;"
          lines << "  localparam integer SAFE_WIDTH_BYTEENA_B = (width_byteena_b > 0) ? width_byteena_b : 1;"
          lines << "  localparam integer SAFE_DEPTH_A = (1 << SAFE_WIDTHAD_A);"
          lines << "  localparam integer SAFE_BYTE_COUNT_A = (SAFE_WIDTH_A + 7) / 8;"
          lines << "  localparam integer SAFE_BYTE_COUNT_B = (SAFE_WIDTH_B + 7) / 8;"
          lines << "  localparam integer SAFE_SUBWORDS_PER_A_B = (SAFE_WIDTH_A >= SAFE_WIDTH_B && SAFE_WIDTH_B > 0) ? (SAFE_WIDTH_A / SAFE_WIDTH_B) : 1;"
          lines << "  localparam integer SAFE_SUBWORD_BITS_B = (SAFE_SUBWORDS_PER_A_B <= 1) ? 1 : $clog2(SAFE_SUBWORDS_PER_A_B);"
          lines << ""
          lines << "  reg [SAFE_WIDTH_A-1:0] mem [0:SAFE_DEPTH_A-1];"
          lines << "  reg [SAFE_WIDTH_A-1:0] merged_a;"
          lines << "  reg [SAFE_WIDTH_A-1:0] merged_b_word;"
          lines << "  reg [SAFE_WIDTHAD_A-1:0] addr_b_word_reg;"
          lines << "  reg [SAFE_SUBWORD_BITS_B-1:0] addr_b_lane_reg;"
          lines << "  reg [SAFE_WIDTH_B-1:0] q_b_reg;"
          lines << "  integer init_i;"
          lines << "  integer byte_i;"
          lines << ""
          lines << "  wire [SAFE_WIDTHAD_A-1:0] addr_a = address_a[SAFE_WIDTHAD_A-1:0];"
          lines << "  wire [SAFE_WIDTHAD_B-1:0] addr_b_full = address_b[SAFE_WIDTHAD_B-1:0];"
          lines << "  wire [SAFE_WIDTHAD_A-1:0] addr_b_word_next = (SAFE_WIDTH_A >= SAFE_WIDTH_B) ?"
          lines << "    (addr_b_full / SAFE_SUBWORDS_PER_A_B) : addr_b_full[SAFE_WIDTHAD_A-1:0];"
          lines << "  wire [SAFE_SUBWORD_BITS_B-1:0] addr_b_lane_next = (SAFE_WIDTH_A >= SAFE_WIDTH_B) ?"
          lines << "    (addr_b_full % SAFE_SUBWORDS_PER_A_B) : {SAFE_SUBWORD_BITS_B{1'b0}};"
          lines << "  wire clocken0_en = (clocken0 === 1'b0) ? 1'b0 : 1'b1;"
          lines << "  wire clocken1_en = (clocken1 === 1'b0) ? 1'b0 : 1'b1;"
          lines << "  wire addressstall_a_en = (addressstall_a === 1'b1) ? 1'b1 : 1'b0;"
          lines << "  wire addressstall_b_en = (addressstall_b === 1'b1) ? 1'b1 : 1'b0;"
          lines << ""
          lines << "  initial begin"
          lines << "    for (init_i = 0; init_i < SAFE_DEPTH_A; init_i = init_i + 1) begin"
          lines << "      mem[init_i] = {SAFE_WIDTH_A{1'b0}};"
          lines << "    end"
          lines << "    addr_b_word_reg = {SAFE_WIDTHAD_A{1'b0}};"
          lines << "    addr_b_lane_reg = {SAFE_SUBWORD_BITS_B{1'b0}};"
          lines << "    q_b_reg = {SAFE_WIDTH_B{1'b0}};"
          lines << "  end"
          lines << ""
          lines << "  always @* begin"
          lines << "    merged_a = mem[addr_a];"
          lines << "    if (SAFE_WIDTH_BYTEENA_A <= 1 || SAFE_BYTE_COUNT_A <= 1) begin"
          lines << "      merged_a = data_a;"
          lines << "    end else begin"
          lines << "      for (byte_i = 0; byte_i < SAFE_BYTE_COUNT_A; byte_i = byte_i + 1) begin"
          lines << "        if (byte_i < SAFE_WIDTH_BYTEENA_A && byteena_a[byte_i]) begin"
            lines << "          merged_a[(byte_i * 8) +: 8] = data_a[(byte_i * 8) +: 8];"
          lines << "        end"
          lines << "      end"
          lines << "    end"
          lines << "    merged_b_word = mem[addr_b_word_next];"
          lines << "    if (SAFE_WIDTH_BYTEENA_B <= 1 || SAFE_BYTE_COUNT_B <= 1) begin"
          lines << "      if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin"
          lines << "        merged_b_word[(addr_b_lane_next * SAFE_WIDTH_B) +: SAFE_WIDTH_B] = data_b;"
          lines << "      end else begin"
          lines << "        merged_b_word[SAFE_WIDTH_B-1:0] = data_b;"
          lines << "      end"
          lines << "    end else begin"
          lines << "      for (byte_i = 0; byte_i < SAFE_BYTE_COUNT_B; byte_i = byte_i + 1) begin"
          lines << "        if (byte_i < SAFE_WIDTH_BYTEENA_B && byteena_b[byte_i]) begin"
          lines << "          if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin"
          lines << "            merged_b_word[(addr_b_lane_next * SAFE_WIDTH_B) + (byte_i * 8) +: 8] = data_b[(byte_i * 8) +: 8];"
          lines << "          end else begin"
          lines << "            merged_b_word[(byte_i * 8) +: 8] = data_b[(byte_i * 8) +: 8];"
          lines << "          end"
          lines << "        end"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  always @(posedge clock0) begin"
          lines << "    if (clocken0_en) begin"
          lines << "      if (!addressstall_b_en) begin"
          lines << "        addr_b_word_reg <= addr_b_word_next;"
          lines << "        addr_b_lane_reg <= addr_b_lane_next;"
          lines << "        if (rden_b === 1'b1) begin"
          lines << "          if (SAFE_WIDTH_A >= SAFE_WIDTH_B) begin"
          lines << "            q_b_reg <= mem[addr_b_word_next][(addr_b_lane_next * SAFE_WIDTH_B) +: SAFE_WIDTH_B];"
          lines << "          end else begin"
          lines << "            q_b_reg <= mem[addr_b_word_next][SAFE_WIDTH_B-1:0];"
          lines << "          end"
          lines << "        end"
          lines << "      end"
          lines << "      if ((wren_a === 1'b1) && !addressstall_a_en) begin"
          lines << "        mem[addr_a] <= merged_a;"
          lines << "      end"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  always @(posedge clock1) begin"
          lines << "    if (clocken1_en && (wren_b === 1'b1) && !addressstall_b_en) begin"
          lines << "      mem[addr_b_word_next] <= merged_b_word;"
          lines << "    end"
          lines << "  end"
          lines << ""
          lines << "  assign q_a = mem[addr_a];"
          lines << "  assign q_b = q_b_reg;"
          lines << "  assign eccstatus = 3'b000;"
          lines << "endmodule"
          lines << ""
          lines.join("\n")
        end

        def stub_module_header_lines(name:, port_specs:, parameter_specs:)
          lines = []
          if parameter_specs.empty?
            if port_specs.empty?
              lines << "module #{name};"
            else
              lines << "module #{name}("
              port_specs.each_with_index do |port, index|
                suffix = index == port_specs.length - 1 ? "" : ","
                lines << "  #{port.fetch(:name)}#{suffix}"
              end
              lines << ");"
            end
          else
            lines << "module #{name} #("
            parameter_specs.each_with_index do |parameter, index|
              suffix = index == parameter_specs.length - 1 ? "" : ","
              lines << "  parameter #{parameter} = 0#{suffix}"
            end
            if port_specs.empty?
              lines << ");"
            else
              lines << ") ("
              port_specs.each_with_index do |port, index|
                suffix = index == port_specs.length - 1 ? "" : ","
                lines << "  #{port.fetch(:name)}#{suffix}"
              end
              lines << ");"
            end
          end
          lines
        end

        def known_stub_ports(module_name:)
          case module_name.to_s.downcase
          when "altdpram"
            %w[
              aclr byteena data inclock inclocken outclock outclocken q
              rdaddress rdaddressstall rden sclr wraddress wraddressstall wren
            ]
          when "altsyncram"
            %w[
              aclr0 aclr1 address_a address_b addressstall_a addressstall_b
              byteena_a byteena_b clock0 clock1 clocken0 clocken1 clocken2 clocken3
              data_a data_b eccstatus q_a q_b rden_a rden_b wren_a wren_b
            ]
          when "cpu_export"
            %w[
              clk rst_n new_export commandcount eax ebx ecx edx esp ebp esi edi eip
            ]
          else
            []
          end
        end

        def stub_port_hint(module_name:, port_name:)
          module_key = module_name.to_s.downcase
          port_key = port_name.to_s.downcase

          if module_key == "altdpram"
            return { direction: "output", width: "width" } if port_key == "q"
            return { direction: "input", width: "width" } if port_key == "data"
            return { direction: "input", width: "widthad" } if %w[wraddress rdaddress].include?(port_key)
            return { direction: "input", width: "width_byteena" } if port_key == "byteena"
          end

          if module_key == "altsyncram"
            return { direction: "output", width: "width_a" } if port_key == "q_a"
            return { direction: "output", width: "width_b" } if port_key == "q_b"
            return { direction: "output", width: 3 } if port_key == "eccstatus"
            return { direction: "input", width: "widthad_a" } if port_key == "address_a"
            return { direction: "input", width: "widthad_b" } if port_key == "address_b"
            return { direction: "input", width: "width_a" } if port_key == "data_a"
            return { direction: "input", width: "width_b" } if port_key == "data_b"
            return { direction: "input", width: "width_byteena_a" } if port_key == "byteena_a"
            return { direction: "input", width: "width_byteena_b" } if port_key == "byteena_b"
          end

          if module_key == "cpu_export"
            return { direction: "output", width: 32 } if port_key == "commandcount"
            return { direction: "input", width: 32 } if %w[eax ebx ecx edx esp ebp esi edi eip].include?(port_key)
          end

          if port_key.match?(/\Aq(_[ab])?\z/) ||
              port_key.match?(/\Aq[ab]\z/) ||
              port_key.match?(/\Adataout(?:_[ab])?\z/) ||
              port_key.end_with?("_out")
            return { direction: "output", width: 1 }
          end

          { direction: "input", width: 1 }
        end

        def known_stub_parameters(module_name:)
          case module_name.to_s.downcase
          when "altdpram"
            %w[
              indata_aclr indata_reg intended_device_family lpm_type
              outdata_aclr outdata_reg ram_block_type
              rdaddress_aclr rdaddress_reg rdcontrol_aclr rdcontrol_reg
              read_during_write_mode_mixed_ports
              width widthad width_byteena
              wraddress_aclr wraddress_reg wrcontrol_aclr wrcontrol_reg
            ]
          when "altsyncram"
            %w[
              operation_mode ram_block_type intended_device_family
              width_a widthad_a numwords_a outdata_aclr_a outdata_reg_a
              width_b widthad_b numwords_b outdata_aclr_b outdata_reg_b
              width_byteena_a width_byteena_b
              read_during_write_mode_mixed_ports read_during_write_mode_port_a read_during_write_mode_port_b
              address_reg_b indata_reg_b wrcontrol_wraddress_reg_b
              clock_enable_input_a clock_enable_input_b
              clock_enable_output_a clock_enable_output_b
              power_up_uninitialized
            ]
          else
            []
          end
        end

        def stub_port_width(width_hint, parameter_lookup:)
          return 1 if width_hint.nil?
          return width_hint if width_hint.is_a?(Integer) && width_hint.positive?

          token = width_hint.to_s.strip
          return 1 if token.empty?
          return token.to_i if token.match?(/\A\d+\z/) && token.to_i.positive?

          parameter_lookup.fetch(token.downcase, 1)
        end

        def verilog_width_decl(width)
          if width.is_a?(Integer)
            return "" if width <= 1

            return "[#{width - 1}:0] "
          end

          token = width.to_s.strip
          return "" if token.empty? || token == "1"

          "[#{token}-1:0] "
        end

        def verilog_zero_literal(width)
          if width.is_a?(Integer)
            return "1'b0" if width <= 1

            return "#{width}'d0"
          end

          token = width.to_s.strip
          return "1'b0" if token.empty? || token == "1"

          "{#{token}{1'b0}}"
        end

        def parse_program_trace(stdout:)
          pc_sequence = []
          instruction_sequence = []
          memory_writes = []
          memory_contents = {}

          stdout.to_s.each_line do |line|
            text = line.to_s.strip
            next if text.empty?

            case text
            when /\AEV IF (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              _cycle = Integer(Regexp.last_match(1))
              address = Regexp.last_match(2).to_i(16)
              data = Regexp.last_match(3).to_i(16)
              pc_sequence << address
              instruction_sequence << data
            when /\AEV WR (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              memory_writes << {
                "cycle" => Integer(Regexp.last_match(1)),
                "address" => Regexp.last_match(2).to_i(16),
                "data" => Regexp.last_match(3).to_i(16),
                "byteenable" => Regexp.last_match(4).to_i(16)
              }
            when /\AEV MEM ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              memory_contents[Regexp.last_match(1).downcase] = Regexp.last_match(2).to_i(16)
            end
          end

          {
            "pc_sequence" => pc_sequence,
            "instruction_sequence" => instruction_sequence,
            "memory_writes" => memory_writes,
            "memory_contents" => memory_contents
          }
        end

        def initial_input_state(input_names:)
          state = {}
          input_names.each { |name| state[name] = 0 }
          state["a20_enable"] = 1 if input_names.include?("a20_enable")
          state["cache_disable"] = 0 if input_names.include?("cache_disable")
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

        def rst_n_for_cycle(cycle)
          index = Integer(cycle)
          index < 3 ? 0 : 1
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
            io_write_do: read_ir_signal(sim: sim, name: "io_write_do", width: 1)
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

        def tracked_memory_snapshot(memory_words)
          program_tracked_addresses.each_with_object({}) do |address, memo|
            memo[format("%08x", address)] = read_memory_word(memory_words, address)
          end
        end

        def read_memory_word(memory_words, address)
          Integer(memory_words.fetch(address & bit_mask(32), 0)) & bit_mask(32)
        rescue StandardError
          0
        end

        def write_memory_word(memory_words, address:, data:, byteenable:)
          normalized_address = address & bit_mask(32)
          current = read_memory_word(memory_words, normalized_address)
          merged = current
          merged = (merged & ~0x0000_00FF) | (data & 0x0000_00FF) if (byteenable & 0x1) != 0
          merged = (merged & ~0x0000_FF00) | (data & 0x0000_FF00) if (byteenable & 0x2) != 0
          merged = (merged & ~0x00FF_0000) | (data & 0x00FF_0000) if (byteenable & 0x4) != 0
          merged = (merged & ~0xFF00_0000) | (data & 0xFF00_0000) if (byteenable & 0x8) != 0
          memory_words[normalized_address] = merged & bit_mask(32)
        end

        def program_fetch_address?(address)
          program_fetch_addresses.include?(address & bit_mask(32))
        end

        def bit_mask(width)
          normalized = width.to_i
          return 0 if normalized <= 0

          (1 << normalized) - 1
        end

        def first_error_line(stderr)
          line = stderr.to_s.each_line.find { |entry| !entry.strip.empty? }
          message = line.to_s.strip
          message.empty? ? "unknown error" : message
        end

        def resolve_missing_module_sources(missing_modules:, include_dirs:, selected_sources:)
          chosen = Array(selected_sources).map { |path| File.expand_path(path.to_s) }.to_set
          resolved = {}
          search_dirs = reference_search_dirs(include_dirs: include_dirs)

          Array(missing_modules).map(&:to_s).map(&:strip).reject(&:empty?).uniq.each do |module_name|
            source_path = find_module_source_file(module_name: module_name, search_dirs: search_dirs, chosen: chosen)
            next if source_path.nil?

            resolved[module_name] = source_path
            chosen << File.expand_path(source_path)
          end

          resolved
        end

        def reference_search_dirs(include_dirs:)
          source_root = @source_root.to_s.strip
          source_root = if source_root.empty?
                          File.expand_path(File.join("examples", "ao486", "reference", "rtl", "ao486"), @cwd)
                        else
                          File.expand_path(source_root, @cwd)
                        end
          parent_root = File.expand_path("..", source_root)

          (Array(include_dirs).map(&:to_s) + [source_root, parent_root])
            .map { |path| File.expand_path(path, @cwd) }
            .uniq
            .select { |path| Dir.exist?(path) }
        end

        def find_module_source_file(module_name:, search_dirs:, chosen:)
          basenames = ["#{module_name}.v", "#{module_name}.sv"]

          Array(search_dirs).each do |dir|
            basenames.each do |basename|
              candidate = File.expand_path(File.join(dir.to_s, basename))
              next unless File.file?(candidate)
              next if chosen.include?(candidate)
              next unless module_declares?(path: candidate, module_name: module_name)

              return candidate
            end
          end

          Array(search_dirs).each do |dir|
            basenames.each do |basename|
              Dir.glob(File.join(dir.to_s, "**", basename)).sort.each do |candidate|
                expanded = File.expand_path(candidate)
                next unless File.file?(expanded)
                next if chosen.include?(expanded)
                next unless module_declares?(path: expanded, module_name: module_name)

                return expanded
              end
            end
          end

          nil
        rescue StandardError
          nil
        end

        def module_declares?(path:, module_name:)
          pattern = /^\s*(?:module|macromodule)\s+#{Regexp.escape(module_name)}\b/
          File.foreach(path) do |line|
            return true if pattern.match?(line)
          end
          false
        rescue StandardError
          false
        end

        def memory_var_name(address)
          "mem_#{format('%08x', address)}"
        end

        def testbench_source(top:, cycles:)
          declarations = program_tracked_addresses.map do |address|
            "  reg [31:0] #{memory_var_name(address)} = 32'h#{format('%08x', program_memory_words.fetch(address, 0))};"
          end.join("\n")
          read_cases = program_tracked_addresses.map do |address|
            "        32'h#{format('%08x', address)}: mem_read_word = #{memory_var_name(address)};"
          end.join("\n")
          write_cases = program_tracked_addresses.map do |address|
            "        32'h#{format('%08x', address)}: #{memory_var_name(address)} = merged_word;"
          end.join("\n")
          program_cases = program_fetch_addresses.map do |address|
            "        32'h#{format('%08x', address)}: is_program_address = 1'b1;"
          end.join("\n")
          dump_lines = program_tracked_addresses.map do |address|
            "    $display(\"EV MEM %08x %08x\", 32'h#{format('%08x', address)}, #{memory_var_name(address)});"
          end.join("\n")

          <<~VERILOG
            `timescale 1ns/1ps

            module tb_ao486_program;
              reg clk = 1'b0;
              reg rst_n = 1'b0;

              reg a20_enable = 1'b1;
              reg cache_disable = 1'b0;
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

            #{declarations}

              integer cycle = 0;
              reg [31:0] read_addr;
              reg [31:0] read_data;
              integer pending_read_words = 0;
              reg [31:0] pending_read_addr = 32'h0;

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

              function [31:0] mem_read_word;
                input [31:0] address;
                begin
                  case (address)
            #{read_cases}
                    default: mem_read_word = 32'h00000000;
                  endcase
                end
              endfunction

              task mem_write_word;
                input [31:0] address;
                input [31:0] data_word;
                input [3:0] byteenable;
                reg [31:0] merged_word;
                begin
                  merged_word = mem_read_word(address);
                  if (byteenable[0]) merged_word[7:0] = data_word[7:0];
                  if (byteenable[1]) merged_word[15:8] = data_word[15:8];
                  if (byteenable[2]) merged_word[23:16] = data_word[23:16];
                  if (byteenable[3]) merged_word[31:24] = data_word[31:24];
                  case (address)
            #{write_cases}
                    default: ;
                  endcase
                end
              endtask

              function is_program_address;
                input [31:0] address;
                begin
                  case (address)
            #{program_cases}
                    default: is_program_address = 1'b0;
                  endcase
                end
              endfunction

              initial begin
                rst_n = 1'b0;
                clk = 1'b0;
                avm_readdatavalid = 1'b0;
                io_read_done = 1'b0;
                io_write_done = 1'b0;
                avm_readdata = 32'h0;

                for (cycle = 0; cycle <= #{cycles}; cycle = cycle + 1) begin
                  io_read_done = 1'b0;
                  io_write_done = 1'b0;
                  if (cycle < 3) rst_n = 1'b0;
                  else rst_n = 1'b1;

                  avm_readdatavalid = 1'b0;
                  if (pending_read_words > 0) begin
                    read_addr = pending_read_addr;
                    read_data = mem_read_word(read_addr);
                    avm_readdata = read_data;
                    avm_readdatavalid = 1'b1;
                    if (is_program_address(read_addr)) begin
                      $display("EV IF %0d %08x %08x", cycle, read_addr, read_data);
                    end
                    pending_read_addr = pending_read_addr + 32'h00000004;
                    pending_read_words = pending_read_words - 1;
                  end

                  clk = 1'b0;
                  #1;

                  if (avm_read && !avm_waitrequest && pending_read_words == 0) begin
                    read_addr = {avm_address, 2'b00};
                    pending_read_addr = read_addr;
                    pending_read_words = (avm_burstcount == 4'b0000) ? 1 : avm_burstcount;
                  end

                  if (avm_write && !avm_waitrequest) begin
                    read_addr = {avm_address, 2'b00};
                    mem_write_word(read_addr, avm_writedata, avm_byteenable);
                    $display("EV WR %0d %08x %08x %1x", cycle, read_addr, avm_writedata, avm_byteenable);
                  end

                  if (io_read_do) begin
                    io_read_data = 32'h0;
                    io_read_done = 1'b1;
                  end
                  if (io_write_do) begin
                    io_write_done = 1'b1;
                  end

                  clk = 1'b1;
                  #1;

                  clk = 1'b0;
                  #1;
                end

            #{dump_lines}
                $finish;
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
