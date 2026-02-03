# Apple ][-style memory bus with I/O page and soft switches

require_relative '../../../../lib/rhdl/hdl'
require_relative '../input/disk2'
require_relative '../output/speaker'
require_relative '../renderers/color_renderer'

module RHDL
  module Examples
    module MOS6502
      class Apple2Bus < RHDL::HDL::Component
    IO_PAGE_START = 0xC000
    IO_PAGE_END = 0xC0FF

    TEXT_PAGE1_START = 0x0400
    TEXT_PAGE1_END = 0x07FF
    TEXT_PAGE2_START = 0x0800
    TEXT_PAGE2_END = 0x0BFF

    # Hi-res graphics pages (280x192, 8KB each)
    HIRES_PAGE1_START = 0x2000
    HIRES_PAGE1_END = 0x3FFF
    HIRES_PAGE2_START = 0x4000
    HIRES_PAGE2_END = 0x5FFF

    HIRES_WIDTH = 280   # pixels
    HIRES_HEIGHT = 192  # lines
    HIRES_BYTES_PER_LINE = 40  # 280 pixels / 7 bits per byte

    ROM_START = 0xF800
    ROM_END = 0xFFFF

    SOFT_SWITCHES = {
      0xC050 => [:text, false], # GRAPHICS
      0xC051 => [:text, true],  # TEXT
      0xC052 => [:mixed, false],
      0xC053 => [:mixed, true],
      0xC054 => [:page2, false],
      0xC055 => [:page2, true],
      0xC056 => [:hires, false],
      0xC057 => [:hires, true]
    }.freeze

    attr_reader :speaker_toggles, :video, :disk_controller, :speaker

    def initialize(name = nil)
      @memory = Array.new(0x10000, 0)
      @rom_mask = Array.new(0x10000, false)
      @prev_clk = 0
      @key_ready = false
      @key_value = 0
      @speaker_toggles = 0
      @video = {
        text: true,
        mixed: false,
        page2: false,
        hires: false
      }
      @soft_switch_access = Hash.new(0)
      @disk_controller = Disk2.new
      @speaker = Apple2Speaker.new
      @current_cycle = 0
      super(name)
    end

    def setup_ports
      input :clk
      input :addr, width: 16
      input :data_in, width: 8
      input :rw
      input :cs

      output :data_out, width: 8
    end

    def rising_edge?
      prev = @prev_clk
      @prev_clk = in_val(:clk)
      prev == 0 && @prev_clk == 1
    end

    def propagate
      addr = in_val(:addr) & 0xFFFF
      cs = in_val(:cs)
      rw = in_val(:rw)

      if cs == 1
        if rising_edge? && rw == 0
          handle_write(addr, in_val(:data_in))
        end

        out_set(:data_out, handle_read(addr))
      else
        out_set(:data_out, 0)
      end
    end

    def read(addr)
      handle_read(addr & 0xFFFF)
    end

    def write(addr, data)
      handle_write(addr & 0xFFFF, data)
    end

    # I/O region access methods (called by native CPU for $C000-$CFFF)
    # These only handle the I/O page - for ROM addresses like $C600, return internal memory value
    def io_read(addr)
      addr = addr & 0xFFFF
      if io_page?(addr)
        handle_io(:read, addr, 0)
      else
        # Return value from internal memory (for expansion ROM like Disk II at $C600)
        @memory[addr]
      end
    end

    def io_write(addr, value)
      addr = addr & 0xFFFF
      if io_page?(addr)
        handle_io(:write, addr, value)
      end
      # Writes outside I/O page in $C000-$CFFF region are typically ROM and ignored
    end

    # Read a byte from memory - uses native CPU's memory if available
    # This allows the bus to read screen memory when native CPU is active
    def mem_read(addr)
      if defined?(@native_cpu) && @native_cpu
        @native_cpu.peek(addr)
      else
        @memory[addr]
      end
    end

    def load_rom(bytes, base_addr:)
      to_bytes(bytes).each_with_index do |byte, i|
        addr = (base_addr + i) & 0xFFFF
        @memory[addr] = byte & 0xFF
        @rom_mask[addr] = true
      end
    end

    def load_ram(bytes, base_addr:)
      to_bytes(bytes).each_with_index do |byte, i|
        addr = (base_addr + i) & 0xFFFF
        @memory[addr] = byte & 0xFF
        @rom_mask[addr] = false
      end
    end

    def reset_vector
      low = @memory[0xFFFC]
      high = @memory[0xFFFD]
      (high << 8) | low
    end

    def inject_key(ascii)
      @key_value = ascii & 0x7F
      @key_ready = true
    end

    # Load a disk image into the specified drive
    # Also installs the Disk II boot ROM at $C600 if not already present
    def load_disk(path_or_bytes, drive: 0)
      @disk_controller.load_disk(path_or_bytes, drive: drive)
      install_disk_boot_rom
    end

    # Install the Disk II boot ROM at $C600-$C6FF (slot 6 expansion ROM)
    # Uses the real Apple II Disk II ROM (P5 - 341-0027)
    def install_disk_boot_rom
      return if @disk_boot_rom_installed

      # Install boot ROM at $C600
      boot_rom = Disk2.boot_rom
      boot_rom.each_with_index do |byte, i|
        @memory[0xC600 + i] = byte & 0xFF
        @rom_mask[0xC600 + i] = true
      end

      @disk_boot_rom_installed = true
    end

    # Check if a disk is loaded
    def disk_loaded?(drive: 0)
      @disk_controller.disk_loaded?(drive: drive)
    end

    # Eject disk from drive
    def eject_disk(drive: 0)
      @disk_controller.eject_disk(drive: drive)
    end

    def soft_switch_accessed?(addr)
      @soft_switch_access[addr & 0xFFFF] > 0
    end

    def text_page_written?
      (TEXT_PAGE1_START..TEXT_PAGE1_END).any? { |addr| mem_read(addr) != 0 }
    end

    # Read the text page as a 2D array of character codes (24 rows x 40 columns)
    def read_text_page
      result = []
      24.times do |row|
        line = []
        base = text_line_address(row)
        40.times do |col|
          line << mem_read(base + col)
        end
        result << line
      end
      result
    end

    # Read the text page as 24 lines of strings
    def read_text_page_string
      read_text_page.map do |line|
        line.map { |c| ((c & 0x7F) >= 0x20 ? (c & 0x7F).chr : ' ') }.join
      end
    end

    # Check if the screen has been modified
    def text_page_dirty?
      @text_page_dirty ||= false
    end

    # Clear the screen dirty flag
    def clear_text_page_dirty
      @text_page_dirty = false
    end

    # Mark the screen as dirty
    def mark_text_page_dirty
      @text_page_dirty = true
    end

    # Get the key ready state
    def key_ready
      @key_ready
    end

    # Clear the key ready flag
    def clear_key
      @key_ready = false
    end

    # Get base address for hi-res page
    def hires_page_base
      @video[:page2] ? HIRES_PAGE2_START : HIRES_PAGE1_START
    end

    # Check if hi-res page has been written to
    def hires_page_dirty?
      @hires_page_dirty ||= false
    end

    # Clear hi-res dirty flag
    def clear_hires_page_dirty
      @hires_page_dirty = false
    end

    # Read hi-res graphics as raw bitmap (192 rows x 280 pixels)
    # Returns 2D array of 0/1 values
    def read_hires_bitmap
      base = hires_page_base
      bitmap = []

      HIRES_HEIGHT.times do |row|
        line = []
        line_addr = hires_line_address(row, base)

        HIRES_BYTES_PER_LINE.times do |col|
          byte = mem_read(line_addr + col)
          # Each byte has 7 pixels (bit 7 is color/palette select)
          7.times do |bit|
            line << ((byte >> bit) & 1)
          end
        end

        bitmap << line
      end

      bitmap
    end

    # Read hi-res as raw bytes (192 rows x 40 bytes)
    def read_hires_bytes
      base = hires_page_base
      result = []

      HIRES_HEIGHT.times do |row|
        line = []
        line_addr = hires_line_address(row, base)
        HIRES_BYTES_PER_LINE.times do |col|
          line << mem_read(line_addr + col)
        end
        result << line
      end

      result
    end

    # Render hi-res screen to ASCII art (downsampled)
    # chars_wide: target width in characters (default 70)
    def render_hires_ascii(chars_wide: 70)
      bitmap = read_hires_bitmap
      chars_tall = (chars_wide * HIRES_HEIGHT / HIRES_WIDTH / 2).to_i

      # Calculate sampling ratios
      x_ratio = HIRES_WIDTH.to_f / chars_wide
      y_ratio = HIRES_HEIGHT.to_f / chars_tall

      lines = []
      chars_tall.times do |char_y|
        line = ""
        chars_wide.times do |char_x|
          # Sample pixels in this character cell
          pixels_on = 0
          samples = 0

          # Sample a 2x2 block of pixels
          2.times do |dy|
            2.times do |dx|
              px = ((char_x + dx * 0.5) * x_ratio).to_i
              py = ((char_y + dy * 0.5) * y_ratio).to_i
              px = [px, HIRES_WIDTH - 1].min
              py = [py, HIRES_HEIGHT - 1].min
              pixels_on += bitmap[py][px]
              samples += 1
            end
          end

          # Map to density character
          density = pixels_on.to_f / samples
          char = if density > 0.75
            '#'
          elsif density > 0.5
            '+'
          elsif density > 0.25
            '.'
          else
            ' '
          end
          line << char
        end
        lines << line
      end

      lines.join("\n")
    end

    # Render hi-res screen using Unicode braille characters (2x4 dots per char)
    # This gives much higher resolution than ASCII art
    # chars_wide: target width in characters (default 140 = full resolution)
    def render_hires_braille(chars_wide: 140, invert: false)
      bitmap = read_hires_bitmap

      # Braille characters are 2 dots wide × 4 dots tall
      chars_tall = (HIRES_HEIGHT / 4.0).ceil

      # Scale factors
      x_scale = HIRES_WIDTH.to_f / (chars_wide * 2)
      y_scale = HIRES_HEIGHT.to_f / (chars_tall * 4)

      # Braille dot positions (Unicode mapping):
      # Dot 1 (0x01) Dot 4 (0x08)
      # Dot 2 (0x02) Dot 5 (0x10)
      # Dot 3 (0x04) Dot 6 (0x20)
      # Dot 7 (0x40) Dot 8 (0x80)
      dot_map = [
        [0x01, 0x08],  # row 0
        [0x02, 0x10],  # row 1
        [0x04, 0x20],  # row 2
        [0x40, 0x80]   # row 3
      ]

      lines = []
      chars_tall.times do |char_y|
        line = ""
        chars_wide.times do |char_x|
          pattern = 0

          # Sample 2x4 grid for this braille character
          4.times do |dy|
            2.times do |dx|
              px = ((char_x * 2 + dx) * x_scale).to_i
              py = ((char_y * 4 + dy) * y_scale).to_i
              px = [px, HIRES_WIDTH - 1].min
              py = [py, HIRES_HEIGHT - 1].min

              pixel = bitmap[py][px]
              pixel = 1 - pixel if invert
              pattern |= dot_map[dy][dx] if pixel == 1
            end
          end

          # Unicode braille starts at U+2800
          line << (0x2800 + pattern).chr(Encoding::UTF_8)
        end
        lines << line
      end

      lines.join("\n")
    end

    # Render hi-res screen using NTSC artifact colors
    # Uses half-block characters with truecolor ANSI escape sequences
    # chars_wide: target width in characters (default 140 = full resolution)
    def render_hires_color(chars_wide: 140)
      base = hires_page_base
      renderer = ColorRenderer.new(chars_wide: chars_wide)

      # Build memory accessor that uses mem_read for native CPU support
      ram = ->(addr) { mem_read(addr) }

      renderer.render(ram, base_addr: base, chars_wide: chars_wide)
    end

    # Render using Unicode half-block characters (▀▄█ )
    # 2 vertical pixels per character
    def render_hires_blocks(chars_wide: 140, invert: false)
      bitmap = read_hires_bitmap

      chars_tall = (HIRES_HEIGHT / 2.0).ceil
      x_scale = HIRES_WIDTH.to_f / chars_wide
      y_scale = HIRES_HEIGHT.to_f / (chars_tall * 2)

      # Block characters
      blocks = [' ', '▄', '▀', '█']  # 00, 01, 10, 11 (top, bottom bits)

      lines = []
      chars_tall.times do |char_y|
        line = ""
        chars_wide.times do |char_x|
          px = (char_x * x_scale).to_i
          py_top = (char_y * 2 * y_scale).to_i
          py_bot = ((char_y * 2 + 1) * y_scale).to_i

          px = [px, HIRES_WIDTH - 1].min
          py_top = [py_top, HIRES_HEIGHT - 1].min
          py_bot = [py_bot, HIRES_HEIGHT - 1].min

          top = bitmap[py_top][px]
          bot = bitmap[py_bot][px]

          if invert
            top = 1 - top
            bot = 1 - bot
          end

          idx = (top << 1) | bot
          line << blocks[idx]
        end
        lines << line
      end

      lines.join("\n")
    end

    # Export hi-res screen to PBM (Portable Bitmap) format
    # Returns string in PBM P1 format (ASCII)
    def export_hires_pbm
      bitmap = read_hires_bitmap
      lines = ["P1", "#{HIRES_WIDTH} #{HIRES_HEIGHT}"]

      bitmap.each do |row|
        # PBM uses 1 for black, 0 for white (inverted from Apple II)
        lines << row.map { |p| p == 1 ? '0' : '1' }.join(' ')
      end

      lines.join("\n")
    end

    # Export hi-res screen to PGM with optional scaling
    # This is grayscale and can show color fringing
    def export_hires_pgm(scale: 1)
      bitmap = read_hires_bitmap
      width = HIRES_WIDTH * scale
      height = HIRES_HEIGHT * scale

      lines = ["P2", "#{width} #{height}", "255"]

      (HIRES_HEIGHT * scale).times do |y|
        row = []
        (HIRES_WIDTH * scale).times do |x|
          src_y = y / scale
          src_x = x / scale
          pixel = bitmap[src_y][src_x]
          # White on black (Apple II green phosphor)
          row << (pixel == 1 ? 255 : 0)
        end
        lines << row.join(' ')
      end

      lines.join("\n")
    end

    # Save hi-res screen to file
    # Formats: :pbm, :pgm, :ascii, :braille, :blocks
    def save_hires_screen(filename, format: :pbm, **options)
      content = case format
      when :pbm
        export_hires_pbm
      when :pgm
        export_hires_pgm(**options)
      when :ascii
        render_hires_ascii(**options)
      when :braille
        render_hires_braille(**options)
      when :blocks
        render_hires_blocks(**options)
      else
        raise ArgumentError, "Unknown format: #{format}. Use :pbm, :pgm, :ascii, :braille, or :blocks"
      end

      File.write(filename, content)
      filename
    end

    # Check if currently in hi-res graphics mode
    def hires_mode?
      !@video[:text] && @video[:hires]
    end

    # Check if currently in text mode
    def text_mode?
      @video[:text]
    end

    # Get current display mode as symbol
    def display_mode
      if @video[:text]
        :text
      elsif @video[:hires]
        @video[:mixed] ? :hires_mixed : :hires
      else
        @video[:mixed] ? :lores_mixed : :lores
      end
    end

    # Advance disk spin simulation by one or more CPU cycles
    # Call this after each CPU step to simulate continuous disk rotation
    def tick(cycles = 1)
      @current_cycle += cycles
      @disk_controller.tick(cycles)
      @speaker.update_cycle(@current_cycle)
    end

    # Get current cycle count for speaker timing
    def current_cycle
      @current_cycle
    end

    # Start audio playback
    def start_audio
      @speaker.start
    end

    # Stop audio playback
    def stop_audio
      @speaker.stop
    end

    # Enable/disable audio
    def enable_audio(state)
      @speaker.enable(state)
    end

    private

    # Apple II text page has a non-linear layout
    def text_line_address(row)
      base = TEXT_PAGE1_START
      # Apple II screen memory layout: interleaved in groups of 8
      group = row / 8
      offset = row % 8
      base + (offset * 0x80) + (group * 0x28)
    end

    # Apple II hi-res memory layout
    # Screen is 192 lines split into 3 sections of 64 lines each
    # Within each section, lines are interleaved in groups of 8
    def hires_line_address(row, base = HIRES_PAGE1_START)
      # row 0-191
      # Each group of 8 consecutive rows is separated by 0x400 bytes
      # Groups of 8 lines within a section are 0x80 apart
      # Sections (0-63, 64-127, 128-191) are 0x28 apart

      section = row / 64           # 0, 1, or 2
      row_in_section = row % 64
      group = row_in_section / 8   # 0-7
      line_in_group = row_in_section % 8  # 0-7

      base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
    end

    def handle_read(addr)
      if io_page?(addr)
        return handle_io(:read, addr, 0)
      end

      @memory[addr]
    end

    def handle_write(addr, value)
      if io_page?(addr)
        handle_io(:write, addr, value)
        return
      end

      return if @rom_mask[addr]

      @memory[addr] = value & 0xFF

      # Mark text page dirty if writing to text area
      if addr >= TEXT_PAGE1_START && addr <= TEXT_PAGE1_END
        @text_page_dirty = true
      end

      # Mark hi-res page dirty if writing to hi-res area
      if (addr >= HIRES_PAGE1_START && addr <= HIRES_PAGE1_END) ||
         (addr >= HIRES_PAGE2_START && addr <= HIRES_PAGE2_END)
        @hires_page_dirty = true
      end
    end

    def io_page?(addr)
      addr >= IO_PAGE_START && addr <= IO_PAGE_END
    end

    def handle_io(direction, addr, value)
      # Check Disk II controller first (slot 6: $C0E0-$C0EF)
      if @disk_controller.handles_address?(addr)
        return @disk_controller.access(addr, value, write: direction == :write)
      end

      case addr
      when 0xC000
        @key_ready ? (@key_value | 0x80) : 0x00
      when 0xC010
        @key_ready = false
        0x00
      when 0xC030
        @speaker_toggles += 1
        @speaker.toggle(@current_cycle)
        0x00
      else
        if SOFT_SWITCHES.key?(addr)
          setting, state = SOFT_SWITCHES[addr]
          @video[setting] = state
          @soft_switch_access[addr] += 1
        end
        0x00
      end
    end

    def to_bytes(source)
      return source.bytes if source.is_a?(String)

      source
    end
      end
    end
  end
end
