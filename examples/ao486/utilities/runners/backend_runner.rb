# frozen_string_literal: true

require_relative '../display_adapter'

module RHDL
  module Examples
    module AO486
      class BackendRunner
        DEFAULT_UNLIMITED_CHUNK = 100_000
        SOFTWARE_ROOT = File.expand_path('../../software', __dir__)
        ROM_ROOT = File.join(SOFTWARE_ROOT, 'rom')
        BIN_ROOT = File.join(SOFTWARE_ROOT, 'bin')
        BOOT0_ADDR = 0xF0000
        BOOT1_ADDR = 0xC0000
        CURSOR_BDA = DisplayAdapter::CURSOR_BDA

        MAX_FLOPPY_SLOTS = 2

        attr_reader :backend, :sim_backend, :cycles_run, :floppy_image, :last_run_stats, :active_floppy_slot

        def initialize(backend:, sim: nil, debug: false, speed: nil, headless: false, cycles: nil)
          @backend = backend.to_sym
          @sim_backend = sim&.to_sym
          @debug = !!debug
          @speed = speed
          @headless = !!headless
          @requested_cycles = cycles
          @memory = Hash.new(0)
          @rom = {}
          @floppy_image = nil
          @floppy_slots = {}
          @active_floppy_slot = nil
          @active_floppy_geometry = nil
          @mounted_disk_size = 0
          @cycles_run = 0
          @last_io = nil
          @last_irq = nil
          @last_run_stats = nil
          @keyboard_buffer = +''
          @shell_prompt_detected = false
          @display_adapter = DisplayAdapter.new
          @display_buffer = Array.new(DisplayAdapter::TEXT_ROWS * DisplayAdapter::TEXT_COLUMNS * 2, 0)
          set_cursor(0, 0)
        end

        def software_root
          SOFTWARE_ROOT
        end

        def software_path(*parts)
          return software_root if parts.empty?

          File.expand_path(File.join(*parts), software_root)
        end

        def bios_paths
          {
            boot0: software_path('rom', 'boot0.rom'),
            boot1: software_path('rom', 'boot1.rom')
          }
        end

        def dos_path
          software_path('bin', 'fdboot.img')
        end

        def load_bios(boot0: bios_paths.fetch(:boot0), boot1: bios_paths.fetch(:boot1))
          boot0_path = File.expand_path(boot0)
          boot1_path = File.expand_path(boot1)
          ensure_file!(boot0_path, 'AO486 BIOS ROM')
          ensure_file!(boot1_path, 'AO486 BIOS ROM')

          boot0_bytes = File.binread(boot0_path).bytes
          boot1_bytes = File.binread(boot1_path).bytes

          load_bytes(BOOT0_ADDR, boot0_bytes, target: @rom)
          load_bytes(BOOT1_ADDR, boot1_bytes, target: @rom)

          {
            boot0: { path: boot0_path, size: boot0_bytes.length },
            boot1: { path: boot1_path, size: boot1_bytes.length }
          }
        end

        def load_dos(path: dos_path, slot: 0, activate: nil)
          dos_image_path = File.expand_path(path)
          ensure_file!(dos_image_path, 'AO486 DOS image')
          slot_index = normalize_floppy_slot(slot)
          bytes = File.binread(dos_image_path)
          metadata = {
            path: dos_image_path,
            size: bytes.bytesize,
            bytes: bytes,
            geometry: infer_floppy_geometry(bytes)
          }
          @floppy_slots[slot_index] = metadata
          activate = slot_index.zero? || @active_floppy_slot.nil? if activate.nil?
          return metadata.merge(slot: slot_index, active: false) unless activate

          activate_dos(slot_index)
        end

        def swap_dos(slot)
          slot_index = normalize_floppy_slot(slot)
          metadata = @floppy_slots[slot_index]
          raise ArgumentError, "AO486 DOS slot #{slot_index} has not been loaded" unless metadata

          activate_dos(slot_index)
        end

        def load_bytes(base, bytes, target: @memory)
          normalized_bytes = bytes.is_a?(String) ? bytes.bytes : Array(bytes)
          normalized_bytes.each_with_index do |byte, idx|
            target[base + idx] = byte.to_i & 0xFF
          end
          self
        end

        def read_bytes(base, length, mapped: true)
          Array.new(length) do |idx|
            addr = base + idx
            if mapped && @rom.key?(addr)
              @rom.fetch(addr)
            else
              @memory.fetch(addr, 0)
            end
          end
        end

        def dump_memory(base, length, mapped: true, bytes_per_row: 16)
          row_width = bytes_per_row.to_i
          raise ArgumentError, 'bytes_per_row must be positive' unless row_width.positive?

          bytes = read_bytes(base, length.to_i, mapped: mapped)
          return '' if bytes.empty?

          field_width = row_width * 3 - 1
          bytes.each_slice(row_width).with_index.map do |slice, idx|
            addr = base + (idx * row_width)
            hex = slice.map { |byte| format('%02X', byte) }.join(' ')
            ascii = slice.map { |byte| printable_ascii(byte) }.join
            format('%08X  %-*s  %s', addr, field_width, hex, ascii)
          end.join("\n")
        end

        def write_memory(addr, value)
          @memory[addr] = value.to_i & 0xFF
        end

        def clear_memory!
          @memory.clear
          self
        end

        def bios_loaded?
          !@rom.empty?
        end

        def dos_loaded?
          !@active_floppy_slot.nil?
        end

        def native?
          true
        end

        def simulator_type
          :"ao486_#{backend}"
        end

        def display_buffer
          @display_buffer.dup
        end

        def memory
          @memory
        end

        def sim
          nil
        end

        def update_display_buffer(buffer)
          @display_buffer = Array(buffer).dup
          @display_buffer.each_with_index do |byte, idx|
            @memory[DisplayAdapter::TEXT_BASE + idx] = byte.to_i & 0xFF
          end
          self
        end

        def render_display(debug_lines: [])
          @display_adapter.render(memory: @memory, cursor: :auto, debug_lines: Array(debug_lines))
        end

        def cursor_position
          page = @memory.fetch(DisplayAdapter::VIDEO_PAGE_BDA, 0) & 0xFF
          base = CURSOR_BDA + (page * 2)
          {
            row: @memory.fetch(base + 1, 0),
            col: @memory.fetch(base, 0),
            page: page
          }
        end

        def reset
          @cycles_run = 0
          @last_run_stats = nil
          @keyboard_buffer.clear
          @shell_prompt_detected = false
          self
        end

        def run(cycles: nil, speed: nil, headless: @headless, max_cycles: nil)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_cycles = @cycles_run
          chunk = max_cycles || cycles || @requested_cycles || speed || @speed || DEFAULT_UNLIMITED_CHUNK
          @cycles_run += tick_backend(chunk.to_i)
          @shell_prompt_detected ||= false
          record_run_stats(operation: :run, cycles: @cycles_run - start_cycles, started_at: started_at)

          state.merge(cycles: @cycles_run, speed: speed || @speed, headless: headless)
        end

        def send_keys(text)
          @keyboard_buffer << text.to_s
          self
        end

        def state
          snapshot = {
            backend: backend,
            sim_backend: sim_backend,
            simulator_type: simulator_type,
            native: native?,
            bios_loaded: bios_loaded?,
            dos_loaded: dos_loaded?,
            cycles_run: @cycles_run,
            floppy_image_size: @floppy_image&.bytesize || 0,
            active_floppy_slot: @active_floppy_slot,
            floppy_slots: @floppy_slots.transform_values { |metadata| metadata.slice(:path, :size) },
            active_floppy_geometry: @active_floppy_geometry&.dup,
            last_io: @last_io,
            last_irq: @last_irq,
            keyboard_buffer_size: @keyboard_buffer.bytesize,
            shell_prompt_detected: @shell_prompt_detected,
            cursor: cursor_position,
            last_run_stats: @last_run_stats
          }
          snapshot
        end

        def run_fetch_words(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-word traces"
        end

        def run_fetch_trace(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch traces"
        end

        def run_fetch_groups(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-group traces"
        end

        def run_fetch_pc_groups(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support fetch-pc traces"
        end

        def run_step_trace(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support step traces"
        end

        def run_final_state(max_cycles: nil)
          raise NoMethodError, "#{self.class} does not support final-state traces"
        end

        def final_state_snapshot
          raise NoMethodError, "#{self.class} does not support final-state snapshots"
        end

        def step(cycle)
          raise NoMethodError, "#{self.class} does not support single-cycle stepping"
        end

        def peek(signal_name)
          current_sim = sim
          raise NoMethodError, "#{self.class} does not expose signal peeks" unless current_sim&.respond_to?(:peek)

          current_sim.peek(signal_name)
        end

        protected

        def capture_run_stats(operation:, cycles:)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          record_run_stats(operation: operation, cycles: cycles, started_at: started_at)
          result
        end

        def record_run_stats(operation:, cycles:, started_at:)
          elapsed_seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          cycles_per_second = elapsed_seconds.positive? ? (cycles.to_f / elapsed_seconds) : Float::INFINITY
          @last_run_stats = {
            backend: backend,
            operation: operation,
            cycles: cycles.to_i,
            elapsed_seconds: elapsed_seconds,
            cycles_per_second: cycles_per_second
          }
        end

        def tick_backend(cycles)
          [cycles, 0].max
        end

        def rom_store
          @rom
        end

        def memory_store
          @memory
        end

        def set_cursor(row, col)
          @memory[CURSOR_BDA] = col.to_i & 0xFF
          @memory[CURSOR_BDA + 1] = row.to_i & 0xFF
        end

        def ensure_file!(path, label)
          return if File.file?(path)

          raise ArgumentError, "#{label} not found: #{path}"
        end

        def activate_dos(slot_index)
          metadata = @floppy_slots.fetch(slot_index)
          @active_floppy_slot = slot_index
          @active_floppy_geometry = metadata[:geometry]&.dup
          @floppy_image = metadata.fetch(:bytes).dup
          sync_active_dos_image!(metadata)
          metadata.merge(slot: slot_index, active: true)
        end

        def dos_shortcut_enabled_for?(metadata = nil)
          active = metadata || (@active_floppy_slot.nil? ? nil : @floppy_slots[@active_floppy_slot])
          return false if active.nil?

          active.fetch(:path) == File.expand_path(dos_path) && (@active_floppy_slot || 0).zero?
        end

        def sync_active_dos_image!(_metadata)
          nil
        end

        def normalize_floppy_slot(slot)
          slot_index = Integer(slot)
          return slot_index if slot_index.between?(0, MAX_FLOPPY_SLOTS - 1)

          raise ArgumentError, "AO486 DOS slot must be 0 or 1, got #{slot.inspect}"
        rescue ArgumentError, TypeError
          raise ArgumentError, "AO486 DOS slot must be 0 or 1, got #{slot.inspect}"
        end

        def printable_ascii(byte)
          value = byte.to_i & 0xFF
          return value.chr if value.between?(32, 126)

          '.'
        end

        def infer_floppy_geometry(bytes)
          raw = bytes.is_a?(String) ? bytes.b : Array(bytes).pack('C*')
          bytes_per_sector = little_endian_u16(raw, 11)
          sectors_per_track = little_endian_u16(raw, 24)
          heads = little_endian_u16(raw, 26)
          total_sectors = little_endian_u16(raw, 19)
          total_sectors = little_endian_u32(raw, 32) if total_sectors.zero?

          geometry = geometry_from_size(raw.bytesize)
          if bytes_per_sector.positive? && sectors_per_track.positive? && heads.positive? && total_sectors.positive?
            cylinders = total_sectors / (sectors_per_track * heads)
            geometry[:bytes_per_sector] = bytes_per_sector
            geometry[:sectors_per_track] = sectors_per_track
            geometry[:heads] = heads
            geometry[:cylinders] = cylinders if cylinders.positive?
          end
          geometry
        end

        def geometry_from_size(bytesize)
          case bytesize
          when 368_640
            { bytes_per_sector: 512, sectors_per_track: 9, heads: 2, cylinders: 40, drive_type: 1 }
          when 737_280
            { bytes_per_sector: 512, sectors_per_track: 9, heads: 2, cylinders: 80, drive_type: 3 }
          when 1_474_560
            { bytes_per_sector: 512, sectors_per_track: 18, heads: 2, cylinders: 80, drive_type: 4 }
          else
            { bytes_per_sector: 512, sectors_per_track: 18, heads: 2, cylinders: 80, drive_type: 4 }
          end
        end

        def little_endian_u16(raw, offset)
          bytes = raw.byteslice(offset, 2)
          return 0 unless bytes && bytes.bytesize == 2

          bytes.unpack1('v')
        end

        def little_endian_u32(raw, offset)
          bytes = raw.byteslice(offset, 4)
          return 0 unless bytes && bytes.bytesize == 4

          bytes.unpack1('V')
        end
      end
    end
  end
end
