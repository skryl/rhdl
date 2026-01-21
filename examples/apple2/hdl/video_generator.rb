# frozen_string_literal: true

# Apple II Video Generator
# Based on Stephen A. Edwards' neoapple2 implementation
#
# This module takes data from memory and various mode switches to produce
# the serial one-bit video data stream.
#
# Supports three display modes:
# - TEXT: 40x24 character display using character ROM
# - LORES: 40x48 low-resolution graphics (16 colors)
# - HIRES: 280x192 high-resolution graphics (6 colors)

require 'rhdl'

module RHDL
  module Apple2
    class VideoGenerator < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      # Clock inputs
      input :clk_14m                       # 14.31818 MHz master clock
      input :clk_7m                        # 7.15909 MHz clock
      input :ax                            # Address multiplexer select
      input :cas_n                         # Column address strobe (active low)

      # Mode inputs
      input :text_mode                     # Text mode enable
      input :page2                         # Display page select
      input :hires_mode                    # High-resolution mode enable
      input :mixed_mode                    # Mixed text/graphics mode

      # Timing inputs from timing generator
      input :h0                            # Horizontal counter bit 0
      input :va                            # Vertical counter bits
      input :vb
      input :vc
      input :v2
      input :v4
      input :blank                         # Composite blanking signal
      input :ldps_n                        # Load parallel shift (active low)
      input :ld194                         # Load signal for 74LS194

      # Data input
      input :dl, width: 8                  # Data from RAM

      # Misc input
      input :flash_clk                     # Low-frequency flashing text clock

      # Outputs
      output :hires                        # HIRES active (to address generator)
      output :video                        # Serial video output
      output :color_line                   # Color burst enable

      # Internal registers (declared as wires for sequential access)
      wire :text_shiftreg, width: 6
      wire :invert_character
      wire :graph_shiftreg, width: 8
      wire :graphics_time_1
      wire :graphics_time_2
      wire :graphics_time_3
      wire :pixel_select, width: 2
      wire :hires_delayed
      wire :blank_delayed
      wire :video_sig

      # Character ROM interface
      # addr = DL(5:0) & VC & VB & VA (9 bits)
      # ROM outputs 5 bits per character row

      # Internal state for text mode shift register and graphics
      sequential clock: :clk_14m, reset_values: {
        text_shiftreg: 0,
        invert_character: 0,
        graph_shiftreg: 0,
        graphics_time_1: 0,
        graphics_time_2: 0,
        graphics_time_3: 0,
        pixel_select: 0,
        hires_delayed: 0,
        blank_delayed: 0,
        video_sig: 0
      } do
        # Text mode shift register (74166)
        # Load when LDPS_N is low, shift otherwise
        char_rom_addr = cat(dl[5..0], vc, vb, va)

        # Simulate character ROM lookup
        # In actual hardware, this comes from character_rom entity
        # Here we'll need to integrate with the character ROM component
        char_rom_out = lit(0, width: 5)  # Placeholder - connected via port

        # Text shifter operation
        text_shiftreg_next = mux(ldps_n,
          text_shiftreg >> 1,              # Shift right
          cat(char_rom_out, lit(0, width: 1))  # Load
        )
        text_shiftreg <= mux(clk_7m, text_shiftreg, text_shiftreg_next)

        # Flash/invert character latch
        invert_character <= mux(ld194,
          invert_character,
          ~(dl[7] | (dl[6] & flash_clk))
        )

        # Graphics time pipeline (74LS174)
        # Captures when in graphics mode
        graphics_mode = ~(text_mode | (v2 & v4 & mixed_mode))
        graphics_time_update = ax & ~cas_n

        graphics_time_3 <= mux(graphics_time_update, graphics_time_2, graphics_time_3)
        graphics_time_2 <= mux(graphics_time_update, graphics_time_1, graphics_time_2)
        graphics_time_1 <= mux(graphics_time_update, graphics_mode, graphics_time_1)

        # Lores/Hires timing
        lores_time = ~hires_mode & graphics_time_3

        # Pixel select register (74LS194)
        pixel_select <= mux(ld194,
          pixel_select,
          mux(lores_time,
            cat(vc, h0),                   # LORES: select nibble
            cat(graphics_time_1, dl[7])    # HIRES: delay bit
          )
        )

        # Hires delay flip-flop (74LS74)
        hires_delayed <= graph_shiftreg[0]

        # Graphics shift register (74LS194 pair)
        # Either shifts (hires) or rotates nibbles (lores)
        graph_shiftreg_shifted = mux(clk_7m,
          graph_shiftreg,
          cat(graph_shiftreg[4], graph_shiftreg[7..1])  # Shift right with bit 4
        )

        # Lores rotation: swap nibbles around
        graph_shiftreg_rotated = cat(
          graph_shiftreg[4], graph_shiftreg[7..5],
          graph_shiftreg[0], graph_shiftreg[3..1]
        )

        graph_shiftreg <= mux(ld194,
          mux(lores_time, graph_shiftreg_rotated, graph_shiftreg_shifted),
          dl
        )

        # Blank delay
        blank_delayed <= mux(ld194, blank_delayed, blank)

        # Video output mux
        # Text pixel with inversion
        text_pixel = text_shiftreg[0] ^ invert_character

        # Lores pixel selection (4 pixels per byte)
        # pixel_select[1:0] selects one of 4 pixels
        lores_pixel = case_select(pixel_select, {
          0 => graph_shiftreg[0],
          1 => graph_shiftreg[2],
          2 => graph_shiftreg[4],
          3 => graph_shiftreg[6]
        }, default: graph_shiftreg[0])

        # Hires pixel with delay for color shift
        hires_pixel = mux(pixel_select[0],
          hires_delayed,
          graph_shiftreg[0]
        )

        # Final video mux
        video_output = mux(blank_delayed,
          lit(0, width: 1),                # Blanked
          mux(lores_time,
            lores_pixel,                   # LORES
            mux(pixel_select[1],
              hires_pixel,                 # HIRES
              text_pixel                   # TEXT
            )
          )
        )

        video_sig <= video_output
      end

      # Combinational outputs
      behavior do
        video <= video_sig
        color_line <= graphics_time_1
        hires <= hires_mode & graphics_time_3
      end
    end
  end
end
