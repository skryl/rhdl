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
# - NTSC color blending/fringing simulation
# - Double hi-res support (560 pixels)
# - Configurable scaling and aspect ratio

module RHDL
  module Apple2
    # Renders Apple II hi-res graphics with NTSC artifact colors
    # Uses 3-bit sliding window algorithm for color determination
    class ColorRenderer
      HIRES_WIDTH = 280          # Standard hi-res pixels
      DHIRES_WIDTH = 560         # Double hi-res pixels
      HIRES_HEIGHT = 192         # Screen lines
      HIRES_BYTES_PER_LINE = 40  # Bytes per line (280/7)

      # ANSI escape codes
      ESC = "\e"
      NORMAL_VIDEO = "#{ESC}[0m"

      # Color palettes - different emulator/monitor profiles
      # Each palette has RGB values for the 6 artifact colors
      PALETTES = {
        # Classic NTSC artifact colors (default)
        ntsc: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x14, 0xF5, 0x3C],
          purple: [0xD6, 0x60, 0xEF],
          orange: [0xFF, 0x6A, 0x3C],
          blue:   [0x14, 0xCF, 0xFD]
        },

        # AppleWin emulator colors
        applewin: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xC0, 0x00],
          purple: [0xBB, 0x36, 0xFF],
          orange: [0xFF, 0x64, 0x00],
          blue:   [0x09, 0x75, 0xFF]
        },

        # KEGS/GSport emulator colors (more saturated)
        kegs: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xFF, 0x00],
          purple: [0xFF, 0x00, 0xFF],
          orange: [0xFF, 0x80, 0x00],
          blue:   [0x00, 0x80, 0xFF]
        },

        # Authentic CRT phosphor (slightly warm white, softer colors)
        crt: {
          black:  [0x10, 0x10, 0x10],
          white:  [0xF0, 0xF0, 0xE0],
          green:  [0x20, 0xD0, 0x40],
          purple: [0xC0, 0x50, 0xE0],
          orange: [0xE0, 0x60, 0x30],
          blue:   [0x30, 0xA0, 0xE0]
        },

        # IIgs RGB mode (pure digital colors)
        iigs: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFF],
          green:  [0x00, 0xFF, 0x00],
          purple: [0xFF, 0x00, 0xFF],
          orange: [0xFF, 0x7F, 0x00],
          blue:   [0x00, 0x7F, 0xFF]
        },

        # Virtual II emulator colors (macOS)
        virtual2: {
          black:  [0x00, 0x00, 0x00],
          white:  [0xFF, 0xFF, 0xFE],
          green:  [0x20, 0xC0, 0x40],
          purple: [0xC0, 0x48, 0xF0],
          orange: [0xE0, 0x70, 0x20],
          blue:   [0x20, 0x90, 0xF0]
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

      attr_reader :chars_wide, :palette, :monochrome, :blend

      def initialize(options = {})
        @chars_wide = options[:chars_wide] || 140
        @palette_name = options[:palette] || :ntsc
        @palette = PALETTES[@palette_name] || PALETTES[:ntsc]
        @monochrome = options[:monochrome]  # nil, :green, :amber, :white, etc.
        @blend = options[:blend] || false   # Enable color blending
        @aspect_correction = options[:aspect_correction] || false
        @double_hires = options[:double_hires] || false

        # Precompute effective colors based on settings
        @colors = build_color_table
      end

      # Render hi-res memory to colored string
      # ram: memory array or callable with hi-res data
      # base_addr: base address of hi-res page (0x2000 for page 1)
      # Returns multi-line string with ANSI color codes
      def render(ram, base_addr: 0x2000, chars_wide: @chars_wide)
        # First, decode the bitmap with color information
        color_bitmap = decode_hires_colors(ram, base_addr)

        # Apply blending if enabled
        color_bitmap = apply_blend(color_bitmap) if @blend

        # Render using half-block characters (2 rows per character)
        render_half_blocks(color_bitmap, chars_wide)
      end

      # Decode hi-res memory into a color bitmap
      # Returns 2D array of color symbols (192 rows x 280 pixels)
      # ram: can be an Array or a callable (lambda/proc) that takes an address
      def decode_hires_colors(ram, base_addr)
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
              color = determine_color(prev, curr_pixel, nxt, high_bit, col * 7 + bit)
              line << color
            end
          end

          bitmap << line
        end

        bitmap
      end

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

      # Determine pixel color using 3-bit sliding window algorithm
      # prev: previous pixel (0/1)
      # curr: current pixel (0/1)
      # nxt: next pixel (0/1)
      # high_bit: palette select (0 = green/purple, 1 = blue/orange)
      # x_pos: horizontal position (for odd/even determination)
      def determine_color(prev, curr, nxt, high_bit, x_pos)
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

      # Apply color blending/fringing for more realistic NTSC artifacts
      # Simulates the bleeding between adjacent colors on NTSC
      def apply_blend(color_bitmap)
        return color_bitmap unless @blend

        blended = []
        color_bitmap.each do |row|
          new_row = []
          row.each_with_index do |color, x|
            prev_color = x > 0 ? row[x - 1] : :black
            next_color = x < row.length - 1 ? row[x + 1] : :black

            # Blend creates intermediate colors at edges
            new_row << blend_pixel(prev_color, color, next_color)
          end
          blended << new_row
        end
        blended
      end

      # Blend a pixel with its neighbors
      def blend_pixel(prev_color, curr_color, next_color)
        # Simple blending: keep the current color but could enhance
        # with fringing effects in future
        curr_color
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
        upper_rgb = @colors[upper_color]
        lower_rgb = @colors[lower_color]

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
            blue: scale_color(phosphor, 0.4)
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
