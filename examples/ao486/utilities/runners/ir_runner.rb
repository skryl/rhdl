# frozen_string_literal: true

require "json"
require "set"
require "tmpdir"

require "rhdl/import/checks/ao486_program_parity_harness"
require "rhdl/import/checks/ao486_trace_harness"
require_relative "dos_boot_shim"
require_relative "native_memory"

module RHDL
  module Examples
    module AO486
      class IrRunner
        DEFAULT_TOP = "ao486"
        DEFAULT_PROGRAM_BASE_ADDRESS = RHDL::Import::Checks::Ao486ProgramParityHarness::PROGRAM_BASE_ADDRESS
        DEFAULT_DATA_CHECK_ADDRESSES = [RHDL::Import::Checks::Ao486ProgramParityHarness::DATA_CHECK_ADDRESS].freeze
        DOS_BOOT_MAX_CYCLES = 131_072
        EVENT_HISTORY_LIMIT = 131_072
        VGA_TEXT_BASE = 0x000B_8000
        VGA_TEXT_COLUMNS = 80
        VGA_TEXT_ROWS = 25
        DISK_IMAGE_BASE = 0x0020_0000
        DISK_IMAGE_MAX_BYTES = 1_474_560
        DISK_IMAGE_CHUNK_BYTES = 64 * 1024
        I64_MAX = (1 << 63) - 1
        U64_MAX = (1 << 64) - 1

        attr_reader :out_dir, :vendor_root, :cwd, :top, :backend, :allow_fallback

        def initialize(
          out_dir:,
          vendor_root:,
          cwd: Dir.pwd,
          top: DEFAULT_TOP,
          backend: :compiler,
          allow_fallback: false
        )
          @cwd = File.expand_path(cwd)
          @out_dir = File.expand_path(out_dir, @cwd)
          @vendor_root = File.expand_path(vendor_root, @cwd)
          @top = top.to_s
          @backend = backend.to_sym
          @allow_fallback = !!allow_fallback
          unless %i[compiler interpreter jit].include?(@backend)
            raise ArgumentError, "unsupported ir backend #{@backend.inspect}; expected :compiler, :interpreter, or :jit"
          end
          @simulator = nil
          @touched_memory_addresses = Set.new
          @live_loaded = false
          @loaded_memory_addresses = Set.new
          @live_pc_sequence = []
          @live_instruction_sequence = []
          @live_memory_writes = []
          @live_memory = RHDL::Examples::AO486::NativeMemory.new
          @live_initial_memory_words = {}
          @live_tracked_addresses = []
          @live_cycles = 0
          @live_serial_output = ""
          @live_vga_fallback_lines = []
          @live_fallback_cursor_row = 0
          @live_fallback_cursor_col = 0
          @live_milestones = []
          @live_boot_metadata = {}
          @loaded_disk_bytes = 0
        end

        def run_program(
          program_binary:,
          cycles: RHDL::Import::Checks::Ao486ProgramParityHarness::DEFAULT_CYCLES,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          data_check_addresses: DEFAULT_DATA_CHECK_ADDRESSES
        )
          harness = build_harness(
            program_binary: program_binary,
            cycles: cycles,
            data_check_addresses: data_check_addresses,
            program_base_address: program_base_address,
            source_root: vendor_root
          )

          sim = simulator
          clear_touched_memory!(sim: sim, harness: harness) if sim.respond_to?(:runner_write_memory)
          trace = harness.send(:run_ir_program, sim: sim)
          record_touched_memory!(harness: harness, trace: trace) if sim.respond_to?(:runner_write_memory)
          trace
        end

        def run_dos_boot(
          bios_system: nil,
          bios_video: nil,
          dos_image: nil,
          bios_system_path: nil,
          bios_video_path: nil,
          dos_image_path: nil,
          disk_image: nil,
          disk: nil,
          cycles: DOS_BOOT_MAX_CYCLES
        )
          resolved_bios_system = resolve_boot_asset_path(
            explicit: bios_system || bios_system_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot0.rom"),
            label: "BIOS system ROM"
          )
          resolved_bios_video = resolve_boot_asset_path(
            explicit: bios_video || bios_video_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot1.rom"),
            label: "BIOS video ROM"
          )
          resolved_dos_image = resolve_boot_asset_path(
            explicit: dos_image || dos_image_path || disk_image || disk,
            fallback: File.join(cwd, "examples", "ao486", "software", "images", "dos4.img"),
            label: "DOS disk image"
          )

          requested_cycles = Integer(cycles)
          effective_cycles = [[requested_cycles, 64].max, DOS_BOOT_MAX_CYCLES].min
          load_dos_boot(
            bios_system: resolved_bios_system,
            bios_video: resolved_bios_video,
            dos_image: resolved_dos_image
          )
          run_cycles(effective_cycles)
          live_trace_snapshot.merge(
            "bios_system_path" => resolved_bios_system,
            "bios_video_path" => resolved_bios_video,
            "dos_image_path" => resolved_dos_image,
            "requested_cycles" => requested_cycles,
            "effective_cycles" => effective_cycles
          )
        end

        def supports_live_cycles?
          true
        end

        def load_program(
          program_binary:,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          data_check_addresses: DEFAULT_DATA_CHECK_ADDRESSES
        )
          harness = build_harness(
            program_binary: program_binary,
            cycles: 1,
            data_check_addresses: data_check_addresses,
            program_base_address: program_base_address,
            source_root: vendor_root
          )
          setup_live_session!(harness: harness, serial_output: "", vga_text_lines: [], milestones: [], boot_metadata: {})
        end

        def load_dos_boot(
          bios_system: nil,
          bios_video: nil,
          dos_image: nil,
          bios_system_path: nil,
          bios_video_path: nil,
          dos_image_path: nil,
          disk_image: nil,
          disk: nil
        )
          resolved_bios_system = resolve_boot_asset_path(
            explicit: bios_system || bios_system_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot0.rom"),
            label: "BIOS system ROM"
          )
          resolved_bios_video = resolve_boot_asset_path(
            explicit: bios_video || bios_video_path,
            fallback: File.join(cwd, "examples", "ao486", "software", "bin", "boot1.rom"),
            label: "BIOS video ROM"
          )
          resolved_dos_image = resolve_boot_asset_path(
            explicit: dos_image || dos_image_path || disk_image || disk,
            fallback: File.join(cwd, "examples", "ao486", "software", "images", "dos4.img"),
            label: "DOS disk image"
          )

          shim = RHDL::Examples::AO486::DosBootShim.new(disk_image_path: resolved_dos_image)
          harness = Dir.mktmpdir("ao486_dos_boot_ir_live") do |tmp_dir|
            shim_binary = File.join(tmp_dir, "dos_boot_shim.bin")
            File.binwrite(shim_binary, shim.binary)
            build_harness(
              program_binary: shim_binary,
              cycles: 1,
              data_check_addresses: DEFAULT_DATA_CHECK_ADDRESSES,
              program_base_address: RHDL::Examples::AO486::DosBootShim::LOAD_ADDRESS,
              source_root: vendor_root
            )
          end

          sim = simulator
          setup_live_session!(
            harness: harness,
            serial_output: "",
            vga_text_lines: [],
            milestones: [
              "bios:system_loaded",
              "bios:video_loaded",
              "disk:image_attached"
            ],
            boot_metadata: {
              "bios_system_path" => resolved_bios_system,
              "bios_video_path" => resolved_bios_video,
              "dos_image_path" => resolved_dos_image
            }
          )
          load_disk_image!(sim: sim, disk_image_path: resolved_dos_image)
          # Probe early progress to avoid presenting a fake/stalled shell session.
          sim.runner_run_cycles(8192)
          consume_live_events!(sim: sim)
          @live_cycles += 8192
          if @live_pc_sequence.length <= 8 && @live_memory_writes.empty?
            raise NotImplementedError,
              "AO486 core-only top does not progress past reset in DOS mode yet; " \
              "a real DOS shell requires full-system integration."
          end
        end

        def reset!
          raise ArgumentError, "no live program is loaded; call #load_program or #load_dos_boot first" unless @live_loaded

          sim = simulator
          sim.reset
          clear_runner_event_buffer!(sim: sim)
          clear_loaded_memory!(sim: sim)
          load_memory_words!(sim: sim, memory_words: @live_initial_memory_words)
          reset_live_trace_buffers!
          true
        end

        def run_cycles(cycles)
          raise ArgumentError, "no live program is loaded; call #load_program or #load_dos_boot first" unless @live_loaded

          requested_cycles = [Integer(cycles), 0].max
          return state if requested_cycles.zero?

          sim = simulator
          result = sim.runner_run_cycles(requested_cycles)
          ran = Integer(result.is_a?(Hash) ? result.fetch(:cycles_run, requested_cycles) : requested_cycles)
          @live_cycles += ran
          consume_live_events!(sim: sim)
          state
        end

        def send_keyboard_bytes(bytes)
          raise ArgumentError, "no live program is loaded; call #load_program or #load_dos_boot first" unless @live_loaded

          payload = if bytes.is_a?(String)
            bytes.b.bytes
          else
            Array(bytes)
          end.map { |entry| Integer(entry) & 0xFF }

          return true if payload.empty?

          sim = simulator
          unless sim.respond_to?(:runner_ao486_keyboard_bytes)
            raise NotImplementedError, "#{sim.class} does not support AO486 keyboard injection"
          end

          submitted = sim.runner_ao486_keyboard_bytes(payload)
          submitted
        rescue ArgumentError, TypeError
          false
        end

        def state
          raise ArgumentError, "no live program is loaded; call #load_program or #load_dos_boot first" unless @live_loaded

          decoded_vga_text_lines = decode_vga_text_lines(memory: @live_memory)
          vga_text_lines = if decoded_vga_text_lines.any? { |line| !line.to_s.strip.empty? }
            decoded_vga_text_lines
          else
            @live_vga_fallback_lines
          end
          {
            "pc" => @live_pc_sequence.last || 0,
            "instruction" => @live_instruction_sequence.last || 0,
            "cycles" => @live_cycles,
            "pc_sequence_length" => @live_pc_sequence.length,
            "memory_write_count" => @live_memory_writes.length,
            "serial_output" => @live_serial_output.to_s,
            "milestones" => @live_milestones.dup,
            "memory_contents" => @live_memory.snapshot(@live_tracked_addresses),
            "vga_text_lines" => vga_text_lines,
            "boot" => @live_boot_metadata.dup
          }
        end

        private

        def resolve_boot_asset_path(explicit:, fallback:, label:)
          candidate = explicit.to_s.strip
          candidate = fallback if candidate.empty?
          path = File.expand_path(candidate, cwd)
          raise ArgumentError, "#{label} not found: #{path}" unless File.file?(path)

          path
        end

        def simulator
          return @simulator if @simulator

          helper = RHDL::Import::Checks::Ao486TraceHarness.new(
            mode: "converted_ir",
            top: top,
            out: out_dir,
            cycles: 1,
            source_root: vendor_root,
            converted_export_mode: nil,
            cwd: cwd
          )
          components = helper.send(:load_converted_components)
          component_index = components.each_with_object({}) do |entry, memo|
            memo[entry.fetch(:source_module_name)] = entry
          end
          top_component = component_index[top]
          raise ArgumentError, "converted component #{top.inspect} not found under #{out_dir}" if top_component.nil?

          module_def = RHDL::Codegen::LIR::Lower.new(top_component.fetch(:component_class), top_name: top).build
          flattened = helper.send(:flatten_ir_module, module_def: module_def, component_index: component_index)
          helper.send(:populate_missing_sensitivity_lists!, flattened)
          ir_json = RHDL::Codegen::IR::IRToJson.convert(flattened)

          normalized_ir = normalize_i64_compatible_json(ir_json)
          normalized_ir_json = if normalized_ir.is_a?(String)
            normalized_ir
          else
            JSON.generate(normalized_ir, max_nesting: false)
          end
          sim = RHDL::Codegen::IR::IrSimulator.new(
            normalized_ir_json,
            backend: @backend,
            allow_fallback: @allow_fallback
          )
          unless sim.respond_to?(:runner_kind) && sim.runner_kind == :ao486
            raise ArgumentError,
              "ao486 IR runner extension unavailable for backend=#{@backend.inspect} " \
              "(runner_kind=#{sim.respond_to?(:runner_kind) ? sim.runner_kind.inspect : 'none'})"
          end
          @simulator = sim
        end

        def clear_touched_memory!(sim:, harness:)
          addresses = Set.new
          addresses.merge(@touched_memory_addresses)
          addresses.merge(harness.program_memory_words.keys.map { |entry| Integer(entry) & 0xFFFF_FFFF })
          addresses.merge(harness.program_fetch_addresses.map { |entry| Integer(entry) & 0xFFFF_FFFF })
          addresses.merge(harness.program_tracked_addresses.map { |entry| Integer(entry) & 0xFFFF_FFFF })
          zero_word = [0, 0, 0, 0].pack("C*")
          addresses.each do |address|
            sim.runner_write_memory(address, zero_word, mapped: false)
          end
        end

        def record_touched_memory!(harness:, trace:)
          @touched_memory_addresses.merge(
            harness.program_memory_words.keys.map { |entry| Integer(entry) & 0xFFFF_FFFF }
          )
          Array(trace.fetch("memory_writes", [])).each do |entry|
            @touched_memory_addresses << (Integer(entry.fetch("address")) & 0xFFFF_FFFF)
          end
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
            return value unless value > I64_MAX && value <= U64_MAX

            value - (1 << 64)
          else
            value
          end
        end

        def setup_live_session!(harness:, serial_output:, vga_text_lines:, milestones:, boot_metadata:)
          sim = simulator
          sim.reset
          clear_runner_event_buffer!(sim: sim)
          clear_loaded_memory!(sim: sim)

          @live_initial_memory_words = normalize_memory_words(harness.program_memory_words)
          @live_tracked_addresses = Array(harness.program_tracked_addresses).map { |entry| Integer(entry) & 0xFFFF_FFFF }.uniq.sort
          @live_memory = RHDL::Examples::AO486::NativeMemory.from_words(@live_initial_memory_words)
          @loaded_memory_addresses = @live_initial_memory_words.keys.to_set
          load_memory_words!(sim: sim, memory_words: @live_initial_memory_words)
          reset_live_trace_buffers!
          @live_serial_output = serial_output.to_s
          @live_vga_fallback_lines = Array(vga_text_lines).map(&:to_s)
          reset_fallback_cursor!
          @live_milestones = Array(milestones).map(&:to_s)
          @live_boot_metadata = boot_metadata.to_h.transform_keys(&:to_s)
          @loaded_disk_bytes = 0
          @live_loaded = true
          true
        end

        def reset_live_trace_buffers!
          @live_pc_sequence = []
          @live_instruction_sequence = []
          @live_memory_writes = []
          @live_cycles = 0
        end

        def clear_runner_event_buffer!(sim:)
          return unless sim.respond_to?(:runner_ao486_take_events)

          sim.runner_ao486_take_events
        end

        def clear_loaded_memory!(sim:)
          return if @loaded_memory_addresses.empty?
          zero_word = [0, 0, 0, 0].pack("C*")
          @loaded_memory_addresses.each do |address|
            sim.runner_write_memory(address, zero_word, mapped: false)
          end
        end

        def load_memory_words!(sim:, memory_words:)
          memory_words.each do |address, value|
            payload = [Integer(value) & 0xFFFF_FFFF].pack("L<")
            sim.runner_write_memory(Integer(address) & 0xFFFF_FFFF, payload, mapped: false)
          end
        end

        def normalize_memory_words(words)
          Array(words).each_with_object({}) do |(address, value), memo|
            memo[Integer(address) & 0xFFFF_FFFF] = Integer(value) & 0xFFFF_FFFF
          end
        end

        def consume_live_events!(sim:)
          text = sim.runner_ao486_take_events.to_s
          return if text.empty?

          text.each_line do |line|
            entry = line.to_s.strip
            next if entry.empty?

            case entry
            when /\AEV IF (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              @live_pc_sequence << Regexp.last_match(2).to_i(16)
              @live_instruction_sequence << Regexp.last_match(3).to_i(16)
            when /\AEV WR (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              write = {
                "cycle" => Integer(Regexp.last_match(1)),
                "address" => Regexp.last_match(2).to_i(16),
                "data" => Regexp.last_match(3).to_i(16),
                "byteenable" => Regexp.last_match(4).to_i(16)
              }
              @live_memory_writes << write
              @live_memory.write_word(
                address: write.fetch("address"),
                data: write.fetch("data"),
                byteenable: write.fetch("byteenable")
              )
            when /\AEV IO_WR (\d+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+) ([0-9A-Fa-f]+)\z/
              append_serial_from_io_write!(
                address: Regexp.last_match(2).to_i(16),
                data: Regexp.last_match(3).to_i(16),
                length: Regexp.last_match(4).to_i(16)
              )
            end
          end

          trim_live_history!
        end

        def trim_live_history!
          overflow = @live_pc_sequence.length - EVENT_HISTORY_LIMIT
          if overflow.positive?
            @live_pc_sequence.shift(overflow)
            @live_instruction_sequence.shift(overflow)
          end

          write_overflow = @live_memory_writes.length - EVENT_HISTORY_LIMIT
          return unless write_overflow.positive?

          @live_memory_writes.shift(write_overflow)
        end

        def build_harness(
          program_binary:,
          cycles:,
          data_check_addresses:,
          program_base_address: DEFAULT_PROGRAM_BASE_ADDRESS,
          source_root:
        )
          RHDL::Import::Checks::Ao486ProgramParityHarness.new(
            out: out_dir,
            top: top,
            cycles: Integer(cycles),
            source_root: source_root.to_s,
            cwd: cwd,
            program_binary: program_binary,
            program_binary_data_addresses: normalize_data_check_addresses(data_check_addresses),
            program_base_address: Integer(program_base_address),
            verilog_tool: "verilator"
          )
        end

        def live_trace_snapshot
          {
            "pc_sequence" => @live_pc_sequence.dup,
            "instruction_sequence" => @live_instruction_sequence.dup,
            "memory_writes" => @live_memory_writes.dup,
            "memory_contents" => @live_memory.snapshot(@live_tracked_addresses),
            "serial_output" => @live_serial_output.to_s,
            "vga_text_lines" => decode_vga_text_lines(memory: @live_memory),
            "milestones" => @live_milestones.dup
          }
        end

        def load_disk_image!(sim:, disk_image_path:)
          bytes = File.binread(disk_image_path.to_s)
          loadable = [bytes.bytesize, DISK_IMAGE_MAX_BYTES].min

          # Clear prior image window when reloading shorter images.
          if @loaded_disk_bytes.positive?
            clear_count = [@loaded_disk_bytes, DISK_IMAGE_MAX_BYTES].min
            zero = "\x00" * DISK_IMAGE_CHUNK_BYTES
            offset = 0
            while offset < clear_count
              chunk = [DISK_IMAGE_CHUNK_BYTES, clear_count - offset].min
              sim.runner_write_memory(DISK_IMAGE_BASE + offset, zero.byteslice(0, chunk), mapped: false)
              offset += chunk
            end
          end

          offset = 0
          while offset < loadable
            chunk = bytes.byteslice(offset, DISK_IMAGE_CHUNK_BYTES)
            sim.runner_write_memory(DISK_IMAGE_BASE + offset, chunk, mapped: false)
            offset += chunk.bytesize
          end
          @loaded_disk_bytes = loadable
        end

        def normalize_data_check_addresses(data_check_addresses)
          values = Array(data_check_addresses).map { |entry| Integer(entry) }
          values.empty? ? DEFAULT_DATA_CHECK_ADDRESSES : values
        end

        def append_serial_from_io_write!(address:, data:, length:)
          port = Integer(address) & 0xFFFF
          return unless (port & 0xFFFC) == 0x03F8

          count = Integer(length)
          count = 1 if count <= 0
          count = 4 if count > 4
          bytes = Array.new(count) { |index| (Integer(data) >> (index * 8)) & 0xFF }
          bytes.each do |value|
            @live_serial_output = "#{@live_serial_output}#{(value & 0xFF).chr}"
          rescue RangeError
            nil
          end
        end

        def decode_vga_text_lines(memory:)
          total_cells = VGA_TEXT_COLUMNS * VGA_TEXT_ROWS
          bytes = Array.new(total_cells * 2, 0)
          bytes.each_index do |index|
            bytes[index] = memory.read_byte(VGA_TEXT_BASE + index)
          end

          Array.new(VGA_TEXT_ROWS) do |row|
            row_offset = row * VGA_TEXT_COLUMNS * 2
            chars = Array.new(VGA_TEXT_COLUMNS) do |col|
              code = bytes[row_offset + (col * 2)] || 0
              printable_ascii(code)
            end
            chars.join.rstrip
          end
        end

        def printable_ascii(code)
          value = Integer(code) & 0xFF
          return " " if value.zero?
          return value.chr if (32..126).cover?(value)

          "."
        rescue ArgumentError, TypeError
          " "
        end

        def reset_fallback_cursor!
          @live_fallback_cursor_row = [@live_vga_fallback_lines.length - 1, 0].max
          @live_fallback_cursor_col = @live_vga_fallback_lines[@live_fallback_cursor_row].to_s.length
        end

        def echo_keyboard_bytes_to_fallback!(bytes)
          ensure_fallback_screen!
          Array(bytes).each do |entry|
            value = Integer(entry) & 0xFF
            case value
            when 8
              backspace_fallback!
            when 10, 13
              @live_serial_output = "#{@live_serial_output}\r\n"
              newline_fallback!
            when 32..126
              putchar_fallback!(value.chr)
            end
          end
        rescue ArgumentError, TypeError
          nil
        end

        def ensure_fallback_screen!
          @live_vga_fallback_lines = [""] if @live_vga_fallback_lines.empty?
          @live_fallback_cursor_row = [[@live_fallback_cursor_row, 0].max, @live_vga_fallback_lines.length - 1].min
          @live_fallback_cursor_col = [@live_fallback_cursor_col, @live_vga_fallback_lines[@live_fallback_cursor_row].to_s.length].min
        end

        def backspace_fallback!
          return if @live_fallback_cursor_col <= 0

          line = @live_vga_fallback_lines[@live_fallback_cursor_row].to_s.dup
          line = line[0, @live_fallback_cursor_col - 1].to_s + line[@live_fallback_cursor_col..].to_s
          @live_fallback_cursor_col -= 1
          @live_vga_fallback_lines[@live_fallback_cursor_row] = line
        end

        def newline_fallback!
          @live_fallback_cursor_row += 1
          @live_fallback_cursor_col = 0
          @live_vga_fallback_lines[@live_fallback_cursor_row] ||= ""
        end

        def putchar_fallback!(char)
          line = @live_vga_fallback_lines[@live_fallback_cursor_row].to_s.dup
          if @live_fallback_cursor_col >= line.length
            line << char
          else
            line[@live_fallback_cursor_col] = char
          end
          @live_fallback_cursor_col += 1
          @live_vga_fallback_lines[@live_fallback_cursor_row] = line
          @live_serial_output = "#{@live_serial_output}#{char}"
        end
      end
    end
  end
end
