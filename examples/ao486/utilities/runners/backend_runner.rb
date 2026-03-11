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

        attr_reader :backend, :sim_backend, :memory, :cycles_run, :floppy_image

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
          @cycles_run = 0
          @last_io = nil
          @last_irq = nil
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

        def load_dos(path: dos_path)
          dos_image_path = File.expand_path(path)
          ensure_file!(dos_image_path, 'AO486 DOS image')
          @floppy_image = File.binread(dos_image_path)

          {
            path: dos_image_path,
            size: @floppy_image.bytesize,
            bytes: @floppy_image.dup
          }
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

        def write_memory(addr, value)
          @memory[addr] = value.to_i & 0xFF
        end

        def bios_loaded?
          !@rom.empty?
        end

        def dos_loaded?
          !@floppy_image.nil?
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
          @keyboard_buffer.clear
          @shell_prompt_detected = false
          self
        end

        def run(cycles: nil, speed: nil, headless: @headless)
          chunk = cycles || @requested_cycles || speed || @speed || DEFAULT_UNLIMITED_CHUNK
          @cycles_run += tick_backend(chunk.to_i)
          @shell_prompt_detected ||= false

          state.merge(cycles: @cycles_run, speed: speed || @speed, headless: headless)
        end

        def send_keys(text)
          @keyboard_buffer << text.to_s
          self
        end

        def state
          {
            backend: backend,
            sim_backend: sim_backend,
            simulator_type: simulator_type,
            native: native?,
            bios_loaded: bios_loaded?,
            dos_loaded: dos_loaded?,
            cycles_run: @cycles_run,
            floppy_image_size: @floppy_image&.bytesize || 0,
            last_io: @last_io,
            last_irq: @last_irq,
            keyboard_buffer_size: @keyboard_buffer.bytesize,
            shell_prompt_detected: @shell_prompt_detected,
            cursor: cursor_position
          }
        end

        protected

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
      end
    end
  end
end
