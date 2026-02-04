# frozen_string_literal: true

# Apple II Hi-Res Color Renderer
# Renders Apple II hi-res screen with NTSC artifact colors
#
# The Apple II produces color through NTSC artifact coloring:
# - Pixels at 7.16 MHz (2x NTSC colorburst at 3.58 MHz)
# - Adjacent pixels of different phases produce colors
# - Bit 7 of each byte selects between two color palettes:
#   - Palette 0 (bit7=0): Black, Green, Purple, White
#   - Palette 1 (bit7=1): Black, Orange, Blue, White
#
# Features:
# - Multiple color palettes (NTSC authentic, AppleWin, Kegs, custom)
# - Monochrome phosphor modes (green, amber, white)
# - Quality modes: :ntsc (7-bit window with fringing) or :fast (3-bit window)
# - Double hi-res support (560 pixels)
# - Configurable scaling and aspect ratio

module RHDL
  module Examples
    module Apple2
      # Renders Apple II hi-res graphics with NTSC artifact colors
    # Default quality mode uses 7-bit sliding window for accurate NTSC simulation
    class ColorRenderer
      HIRES_WIDTH = 280          # Standard hi-res pixels
      DHIRES_WIDTH = 560         # Double hi-res pixels
      HIRES_HEIGHT = 192         # Screen lines
      HIRES_BYTES_PER_LINE = 40  # Bytes per line (280/7)

      # ANSI escape codes
      ESC = "\e"
      NORMAL_VIDEO = "#{ESC}[0m"

      # Quality modes
      QUALITY_MODES = [:ntsc, :fast].freeze

      # Color palettes - different emulator/monitor profiles
      # Each palette has RGB values for the 6 artifact colors plus fringe colors
      PALETTES = {
        # Classic NTSC artifact colors (default)
        ntsc: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x14, 0xF5, 0x3C],
          purple: [0xD6, 0x60, 0xEF],
          orange: [0xFF, 0x6A, 0x3C],
          blue:   [0x14, 0xCF, 0xFD],
          # Fringe colors for NTSC mode (color bleeding at edges)
          dark_green:   [0x0A, 0x7A, 0x1E],
          dark_purple:  [0x6B, 0x30, 0x78],
          dark_orange:  [0x80, 0x35, 0x1E],
          dark_blue:    [0x0A, 0x68, 0x7F],
          light_green:  [0x8A, 0xFA, 0x9E],
          light_purple: [0xEB, 0xB0, 0xF7],
          light_orange: [0xFF, 0xB5, 0x9E],
          light_blue:   [0x8A, 0xE7, 0xFE]
        },

        # AppleWin emulator colors
        applewin: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xC0, 0x00],
          purple: [0xBB, 0x36, 0xFF],
          orange: [0xFF, 0x64, 0x00],
          blue:   [0x09, 0x75, 0xFF],
          dark_green:   [0x00, 0x60, 0x00],
          dark_purple:  [0x5E, 0x1B, 0x80],
          dark_orange:  [0x80, 0x32, 0x00],
          dark_blue:    [0x05, 0x3B, 0x80],
          light_green:  [0x80, 0xE0, 0x80],
          light_purple: [0xDD, 0x9B, 0xFF],
          light_orange: [0xFF, 0xB2, 0x80],
          light_blue:   [0x84, 0xBA, 0xFF]
        },

        # KEGS/GSport emulator colors (more saturated)
        kegs: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xFF, 0x00],
          purple: [0xFF, 0x00, 0xFF],
          orange: [0xFF, 0x80, 0x00],
          blue:   [0x00, 0x80, 0xFF],
          dark_green:   [0x00, 0x80, 0x00],
          dark_purple:  [0x80, 0x00, 0x80],
          dark_orange:  [0x80, 0x40, 0x00],
          dark_blue:    [0x00, 0x40, 0x80],
          light_green:  [0x80, 0xFF, 0x80],
          light_purple: [0xFF, 0x80, 0xFF],
          light_orange: [0xFF, 0xC0, 0x80],
          light_blue:   [0x80, 0xC0, 0xFF]
        },

        # Authentic CRT phosphor (slightly warm white, softer colors)
        crt: {
          black:  [0x10, 0x10, 0x10],
          white:  [0xF0, 0xF0, 0xE0],
          green:  [0x20, 0xD0, 0x40],
          purple: [0xC0, 0x50, 0xE0],
          orange: [0xE0, 0x60, 0x30],
          blue:   [0x30, 0xA0, 0xE0],
          dark_green:   [0x18, 0x68, 0x28],
          dark_purple:  [0x60, 0x28, 0x70],
          dark_orange:  [0x70, 0x30, 0x18],
          dark_blue:    [0x18, 0x50, 0x70],
          light_green:  [0x88, 0xE8, 0xA0],
          light_purple: [0xE0, 0xA8, 0xF0],
          light_orange: [0xF0, 0xB0, 0x98],
          light_blue:   [0x98, 0xD0, 0xF0]
        },

        # IIgs RGB mode (pure digital colors)
        iigs: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xFF, 0x00],
          purple: [0xFF, 0x00, 0xFF],
          orange: [0xFF, 0x7F, 0x00],
          blue:   [0x00, 0x7F, 0xFF],
          dark_green:   [0x00, 0x80, 0x00],
          dark_purple:  [0x80, 0x00, 0x80],
          dark_orange:  [0x80, 0x40, 0x00],
          dark_blue:    [0x00, 0x40, 0x80],
          light_green:  [0x80, 0xFF, 0x80],
          light_purple: [0xFF, 0x80, 0xFF],
          light_orange: [0xFF, 0xBF, 0x80],
          light_blue:   [0x80, 0xBF, 0xFF]
        },

        # Virtual II emulator colors (macOS)
        virtual2: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFE],
          green:  [0x20, 0xC0, 0x40],
          purple: [0xC0, 0x48, 0xF0],
          orange: [0xE0, 0x70, 0x20],
          blue:   [0x20, 0x90, 0xF0],
          dark_green:   [0x10, 0x60, 0x20],
          dark_purple:  [0x60, 0x24, 0x78],
          dark_orange:  [0x70, 0x38, 0x10],
          dark_blue:    [0x10, 0x48, 0x78],
          light_green:  [0x90, 0xE0, 0xA0],
          light_purple: [0xE0, 0xA4, 0xF8],
          light_orange: [0xF0, 0xB8, 0x90],
          light_blue:   [0x90, 0xC8, 0xF8]
        }
      }.freeze

      # Monochrome phosphor colors
      PHOSPHORS = {
        green:  [0x33, 0xFF, 0x33],  # P1 green phosphor
        amber:  [0xFF, 0xBB, 0x00],  # Amber phosphor
        white:  [0xFF, 0xFF, 0xFF],  # White phosphor
        cool:   [0xE0, 0xE8, 0xFF],  # Cool white (slightly blue)
        warm:   [0xFF, 0xF0, 0xE0]   # Warm white (slightly amber)
      }.freeze

      # Half-block characters for rendering
      UPPER_HALF = "\u2580"  # Upper half block
      LOWER_HALF = "\u2584"  # Lower half block
      FULL_BLOCK = "\u2588"  # Full block

      # Shade blocks for antialiasing (quarter blocks not widely supported)
      LIGHT_SHADE = "\u2591"  # Light shade
      MEDIUM_SHADE = "\u2592" # Medium shade
      DARK_SHADE = "\u2593"   # Dark shade

      attr_reader :chars_wide, :palette, :monochrome, :quality

      def initialize(options = {})
        @chars_wide = options[:chars_wide] || 140
        @palette_name = options[:palette] || :ntsc
        @palette = PALETTES[@palette_name] || PALETTES[:ntsc]
        @monochrome = options[:monochrome]  # nil, :green, :amber, :white, etc.
        @quality = options[:quality] || :ntsc  # :ntsc (default) or :fast
        @aspect_correction = options[:aspect_correction] || false
        @double_hires = options[:double_hires] || false

        # Precompute effective colors based on settings
        @colors = build_color_table
      end

      # Legacy blend accessor (now always enabled in :ntsc mode)
      def blend
        @quality == :ntsc
      end

      # Render hi-res memory to colored string
      # ram: memory array or callable with hi-res data
      # base_addr: base address of hi-res page (0x2000 for page 1)
      # Returns multi-line string with ANSI color codes
      def render(ram, base_addr: 0x2000, chars_wide: @chars_wide)
        # Decode the bitmap with color information based on quality mode
        color_bitmap = if @quality == :ntsc
                         decode_hires_colors_ntsc(ram, base_addr)
                       else
                         decode_hires_colors_fast(ram, base_addr)
                       end

        # Render using half-block characters (2 rows per character)
        render_half_blocks(color_bitmap, chars_wide)
      end

      # High-quality NTSC decoding with 7-bit sliding window and color fringing
      # Returns 2D array of RGB values (192 rows x 280 pixels)
      def decode_hires_colors_ntsc(ram, base_addr)
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base_addr)

          # Read all bytes for this line plus neighbors for the sliding window
          line_bytes = []
          HIRES_BYTES_PER_LINE.times do |col|
            line_bytes << read_mem(ram, line_addr + col)
          end

          # Process each pixel with 7-bit context (3 before, current, 3 after)
          HIRES_WIDTH.times do |x|
            byte_idx = x / 7
            bit_idx = x % 7
            byte = line_bytes[byte_idx]
            high_bit = (byte >> 7) & 1

            # Build 7-bit window centered on current pixel
            window = build_7bit_window(line_bytes, x)

            # Determine color with fringing
            color = determine_color_ntsc(window, high_bit, x, line_bytes, byte_idx)
            line << color
          end

          bitmap << line
        end

        bitmap
      end

      # Build a 7-bit window centered on pixel at position x
      # Returns array of 7 pixel values [x-3, x-2, x-1, x, x+1, x+2, x+3]
      def build_7bit_window(line_bytes, x)
        window = []
        (-3..3).each do |offset|
          px = x + offset
          if px < 0 || px >= HIRES_WIDTH
            window << 0
          else
            byte_idx = px / 7
            bit_idx = px % 7
            byte = line_bytes[byte_idx]
            window << ((byte >> bit_idx) & 1)
          end
        end
        window
      end

      # Determine color using 7-bit NTSC algorithm with fringing
      # window: [p-3, p-2, p-1, p, p+1, p+2, p+3]
      def determine_color_ntsc(window, high_bit, x_pos, line_bytes, byte_idx)
        # Extract key positions
        far_prev = window[0]   # x-3
        mid_prev = window[1]   # x-2
        prev = window[2]       # x-1
        curr = window[3]       # current pixel
        nxt = window[4]        # x+1
        mid_next = window[5]   # x+2
        far_next = window[6]   # x+3

        # Check for palette transitions (high bit changes between bytes)
        prev_byte_idx = [byte_idx - 1, 0].max
        next_byte_idx = [byte_idx + 1, HIRES_BYTES_PER_LINE - 1].min
        prev_high = (line_bytes[prev_byte_idx] >> 7) & 1
        next_high = (line_bytes[next_byte_idx] >> 7) & 1

        # Current pixel is off
        return :black if curr == 0

        # Count neighbors for density analysis
        near_neighbors = prev + nxt
        far_neighbors = mid_prev + mid_next
        total_neighbors = near_neighbors + far_neighbors + far_prev + far_next

        # Determine base color from position and palette
        base_color = if high_bit == 0
                       x_pos.even? ? :purple : :green
                     else
                       x_pos.even? ? :blue : :orange
                     end

        # White detection: pixel with immediate neighbors
        if near_neighbors >= 1
          # Check for solid white run
          if prev == 1 && nxt == 1
            return :white
          end
          # Edge of white region - use lighter fringe
          if prev == 1 || nxt == 1
            return :white if total_neighbors >= 3
            return light_fringe(base_color)
          end
        end

        # Isolated pixel analysis
        if near_neighbors == 0
          # Completely isolated - full color
          if far_neighbors == 0
            return base_color
          end
          # Near other pixels but not adjacent - dark fringe
          return dark_fringe(base_color)
        end

        # Single neighbor - transitional
        if near_neighbors == 1
          if total_neighbors >= 2
            return light_fringe(base_color)
          end
          return base_color
        end

        base_color
      end

      # Get dark fringe variant of a color
      def dark_fringe(color)
        case color
        when :green  then :dark_green
        when :purple then :dark_purple
        when :orange then :dark_orange
        when :blue   then :dark_blue
        else color
        end
      end

      # Get light fringe variant of a color
      def light_fringe(color)
        case color
        when :green  then :light_green
        when :purple then :light_purple
        when :orange then :light_orange
        when :blue   then :light_blue
        else color
        end
      end

      # Fast 3-bit decoding (original algorithm)
      # Returns 2D array of color symbols (192 rows x 280 pixels)
      def decode_hires_colors_fast(ram, base_addr)
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base_addr)

          # Process each byte in the line
          HIRES_BYTES_PER_LINE.times do |col|
            byte = read_mem(ram, line_addr + col)
            high_bit = (byte >> 7) & 1  # Palette select

            # Get previous byte's last pixel for sliding window
            prev_byte = col > 0 ? read_mem(ram, line_addr + col - 1) : 0
            prev_pixel = (prev_byte >> 6) & 1

            # Get next byte's first pixel for sliding window
            next_byte = col < HIRES_BYTES_PER_LINE - 1 ? read_mem(ram, line_addr + col + 1) : 0
            next_first = next_byte & 1

            # Process 7 pixels in this byte
            7.times do |bit|
              curr_pixel = (byte >> bit) & 1

              # Get adjacent pixels for the 3-bit window
              if bit == 0
                prev = prev_pixel
              else
                prev = (byte >> (bit - 1)) & 1
              end

              if bit == 6
                nxt = next_first
              else
                nxt = (byte >> (bit + 1)) & 1
              end

              # Determine color from 3-bit pattern
              color = determine_color_fast(prev, curr_pixel, nxt, high_bit, col * 7 + bit)
              line << color
            end
          end

          bitmap << line
        end

        bitmap
      end

      # Legacy method name alias
      alias decode_hires_colors decode_hires_colors_fast

      # Determine pixel color using fast 3-bit sliding window algorithm
      # prev: previous pixel (0/1)
      # curr: current pixel (0/1)
      # nxt: next pixel (0/1)
      # high_bit: palette select (0 = green/purple, 1 = blue/orange)
      # x_pos: horizontal position (for odd/even determination)
      def determine_color_fast(prev, curr, nxt, high_bit, x_pos)
        pattern = (prev << 2) | (curr << 1) | nxt

        case pattern
        when 0b000, 0b001, 0b100
          # No current pixel lit, or isolated edges -> black
          :black
        when 0b011, 0b110, 0b111
          # Current pixel with neighbor(s) -> white
          :white
        when 0b010
          # Isolated pixel - color depends on position and palette
          if high_bit == 0
            x_pos.odd? ? :green : :purple
          else
            x_pos.odd? ? :orange : :blue
          end
        when 0b101
          # Gap between two pixels - creates artifact color
          if high_bit == 0
            x_pos.odd? ? :purple : :green
          else
            x_pos.odd? ? :blue : :orange
          end
        else
          :black
        end
      end

      # Legacy method name alias
      alias determine_color determine_color_fast

      # Decode double hi-res memory (560 pixels wide)
      # Uses aux memory interleaved with main memory
      def decode_double_hires_colors(main_ram, aux_ram, base_addr)
        bitmap = []

        HIRES_HEIGHT.times do |row|
          line = []
          line_addr = hires_line_address(row, base_addr)

          HIRES_BYTES_PER_LINE.times do |col|
            # Aux memory provides even pixels, main provides odd
            aux_byte = read_mem(aux_ram, line_addr + col)
            main_byte = read_mem(main_ram, line_addr + col)

            # Interleave 7 bits from each byte
            7.times do |bit|
              # Aux pixel (even column in double-wide pixel space)
              line << ((aux_byte >> bit) & 1 == 1 ? :white : :black)
              # Main pixel (odd column)
              line << ((main_byte >> bit) & 1 == 1 ? :white : :black)
            end
          end

          bitmap << line
        end

        bitmap
      end

      # Render color bitmap using half-block characters
      # Each terminal character shows 2 vertical pixels
      def render_half_blocks(color_bitmap, chars_wide)
        output = String.new

        width = @double_hires ? DHIRES_WIDTH : HIRES_WIDTH
        x_scale = width.to_f / chars_wide

        # Process 2 rows at a time (upper/lower half blocks)
        (HIRES_HEIGHT / 2).times do |char_row|
          upper_row = char_row * 2
          lower_row = char_row * 2 + 1

          chars_wide.times do |char_col|
            # Sample pixel at this position
            px = (char_col * x_scale).to_i
            px = [px, width - 1].min

            upper_color = color_bitmap[upper_row][px]
            lower_color = color_bitmap[lower_row][px]

            # Generate character with appropriate colors
            output << color_char(upper_color, lower_color)
          end

          output << NORMAL_VIDEO << "\n"
        end

        output
      end

      # Generate a colored character for upper/lower pixel colors
      def color_char(upper_color, lower_color)
        upper_rgb = @colors[upper_color] || @colors[:black]
        lower_rgb = @colors[lower_color] || @colors[:black]

        if upper_color == lower_color
          # Same color - use full block or space
          if upper_color == :black
            bg_color(@colors[:black]) + " "
          else
            fg_color(upper_rgb) + bg_color(@colors[:black]) + FULL_BLOCK
          end
        elsif upper_color == :black
          # Only lower pixel lit
          fg_color(lower_rgb) + bg_color(@colors[:black]) + LOWER_HALF
        elsif lower_color == :black
          # Only upper pixel lit
          fg_color(upper_rgb) + bg_color(@colors[:black]) + UPPER_HALF
        else
          # Both different colors - use upper half with fg/bg
          fg_color(upper_rgb) + bg_color(lower_rgb) + UPPER_HALF
        end
      end

      # ANSI truecolor foreground escape sequence
      def fg_color(rgb)
        "#{ESC}[38;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m"
      end

      # ANSI truecolor background escape sequence
      def bg_color(rgb)
        "#{ESC}[48;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m"
      end

      # Hi-res screen line address calculation (Apple II interleaved layout)
      def hires_line_address(row, base)
        # Each group of 8 consecutive rows is separated by 0x400 bytes
        # Groups of 8 lines within a section are 0x80 apart
        # Sections (0-63, 64-127, 128-191) are 0x28 apart
        section = row / 64           # 0, 1, or 2
        row_in_section = row % 64
        group = row_in_section / 8   # 0-7
        line_in_group = row_in_section % 8  # 0-7

        base + (line_in_group * 0x400) + (group * 0x80) + (section * 0x28)
      end

      # Read memory from ram, supporting both Array and callable (lambda/proc)
      def read_mem(ram, addr)
        if ram.respond_to?(:call)
          ram.call(addr) || 0
        else
          ram[addr] || 0
        end
      end

      # Render to array of lines
      def render_lines(ram, base_addr: 0x2000, chars_wide: @chars_wide)
        render(ram, base_addr: base_addr, chars_wide: chars_wide).split("\n")
      end

      # Class method for quick rendering
      def self.render(ram, base_addr: 0x2000, chars_wide: 140, **options)
        new(chars_wide: chars_wide, **options).render(ram, base_addr: base_addr)
      end

      # Get list of available palettes
      def self.available_palettes
        PALETTES.keys
      end

      # Get list of available monochrome phosphors
      def self.available_phosphors
        PHOSPHORS.keys
      end

      # Get list of available quality modes
      def self.available_quality_modes
        QUALITY_MODES
      end

      private

      # Build the effective color table based on palette and monochrome settings
      def build_color_table
        if @monochrome
          # Monochrome mode: convert all colors to shades of the phosphor
          phosphor = PHOSPHORS[@monochrome] || PHOSPHORS[:green]
          {
            black: [0, 0, 0],
            white: phosphor,
            green: scale_color(phosphor, 0.7),
            purple: scale_color(phosphor, 0.5),
            orange: scale_color(phosphor, 0.6),
            blue: scale_color(phosphor, 0.4),
            # Fringe colors in monochrome
            dark_green: scale_color(phosphor, 0.35),
            dark_purple: scale_color(phosphor, 0.25),
            dark_orange: scale_color(phosphor, 0.30),
            dark_blue: scale_color(phosphor, 0.20),
            light_green: scale_color(phosphor, 0.85),
            light_purple: scale_color(phosphor, 0.75),
            light_orange: scale_color(phosphor, 0.80),
            light_blue: scale_color(phosphor, 0.70)
          }
        else
          @palette.dup
        end
      end

      # Scale a color by a factor (for monochrome brightness levels)
      def scale_color(rgb, factor)
        rgb.map { |c| (c * factor).to_i.clamp(0, 255) }
      end
    end

    # Legacy alias for backwards compatibility
    HiResColorRenderer = ColorRenderer
  end
  end
end
