# frozen_string_literal: true

# Apple II Keyboard Interface
# Based on Stephen A. Edwards' neoapple2 implementation
#
# PS/2 keyboard controller with scancode to ASCII translation
# Supports US English keyboard layout

require 'rhdl'

module RHDL
  module Apple2
    # PS/2 Controller - handles low-level PS/2 protocol
    class PS2Controller < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential

      input :clk
      input :reset
      input :ps2_clk                     # PS/2 clock from keyboard
      input :ps2_data                    # PS/2 data from keyboard

      output :scan_code, width: 8        # Received scancode
      output :scan_dav                   # Data available strobe

      # Internal registers
      wire :ps2_clk_sync, width: 2
      wire :ps2_data_sync
      wire :bit_count, width: 4
      wire :shift_reg, width: 11
      wire :scan_code_reg, width: 8
      wire :scan_dav_reg

      # PS/2 protocol: 11 bits - 1 start + 8 data + 1 parity + 1 stop
      # Data is valid on falling edge of PS/2 clock

      sequential clock: :clk, reset: :reset, reset_values: {
        ps2_clk_sync: 0b11,
        ps2_data_sync: 1,
        bit_count: 0,
        shift_reg: 0,
        scan_code_reg: 0,
        scan_dav_reg: 0
      } do
        # Synchronize PS/2 signals to system clock
        ps2_clk_sync <= cat(ps2_clk_sync[0], ps2_clk)
        ps2_data_sync <= ps2_data

        # Detect falling edge of PS/2 clock
        falling_edge = ps2_clk_sync[1] & ~ps2_clk_sync[0]

        # Shift register for incoming bits
        shift_reg_next = mux(falling_edge,
          cat(ps2_data_sync, shift_reg[10..1]),
          shift_reg
        )
        shift_reg <= shift_reg_next

        # Bit counter
        bit_count_next = mux(falling_edge,
          mux(bit_count == lit(10, width: 4),
            lit(0, width: 4),
            bit_count + lit(1, width: 4)
          ),
          bit_count
        )
        bit_count <= bit_count_next

        # Output scancode when all 11 bits received
        complete = falling_edge & (bit_count == lit(10, width: 4))
        scan_code_reg <= mux(complete, shift_reg[8..1], scan_code_reg)
        scan_dav_reg <= complete
      end

      behavior do
        scan_code <= scan_code_reg
        scan_dav <= scan_dav_reg
      end
    end

    # Main Keyboard Controller
    class Keyboard < SequentialComponent
      include RHDL::DSL::Behavior
      include RHDL::DSL::Sequential
      include RHDL::DSL::Memory

      input :clk_14m                     # 14.31818 MHz clock
      input :reset
      input :ps2_clk                     # PS/2 clock from keyboard
      input :ps2_data                    # PS/2 data from keyboard
      input :read                        # Read strobe (clears key_pressed)

      output :k, width: 8                # Latched, decoded keyboard data

      # PS/2 special codes
      KEY_UP_CODE     = 0xF0
      EXTENDED_CODE   = 0xE0
      LEFT_SHIFT      = 0x12
      RIGHT_SHIFT     = 0x59
      LEFT_CTRL       = 0x14
      ALT_GR          = 0x11

      # FSM states
      STATE_IDLE           = 0
      STATE_HAVE_CODE      = 1
      STATE_DECODE         = 2
      STATE_GOT_KEY_UP     = 3
      STATE_GOT_KEY_UP2    = 4
      STATE_GOT_KEY_UP3    = 5
      STATE_KEY_UP         = 6
      STATE_NORMAL_KEY     = 7

      # Sub-component: PS/2 controller
      instance :ps2_ctrl, PS2Controller

      # Connect PS/2 controller
      port :clk_14m => [:ps2_ctrl, :clk]
      port :reset => [:ps2_ctrl, :reset]
      port :ps2_clk => [:ps2_ctrl, :ps2_clk]
      port :ps2_data => [:ps2_ctrl, :ps2_data]

      # Internal wires
      wire :code, width: 8
      wire :code_available

      port [:ps2_ctrl, :scan_code] => :code
      port [:ps2_ctrl, :scan_dav] => :code_available

      # Internal state registers
      wire :state, width: 4
      wire :latched_code, width: 8
      wire :key_pressed
      wire :shift
      wire :ctrl
      wire :alt
      wire :ascii, width: 8

      sequential clock: :clk_14m, reset: :reset, reset_values: {
        state: STATE_IDLE,
        latched_code: 0,
        key_pressed: 0,
        shift: 0,
        ctrl: 0,
        alt: 0,
        ascii: 0
      } do
        # Clear key_pressed on read
        key_pressed <= mux(read, lit(0, width: 1), key_pressed)

        # Modifier key handling
        is_left_shift = (code == lit(LEFT_SHIFT, width: 8))
        is_right_shift = (code == lit(RIGHT_SHIFT, width: 8))
        is_shift_key = is_left_shift | is_right_shift
        is_ctrl_key = (code == lit(LEFT_CTRL, width: 8))
        is_alt_key = (code == lit(ALT_GR, width: 8))

        # FSM state machine using case_select
        # Decode state determines next state based on code received
        decode_next = mux(code == lit(KEY_UP_CODE, width: 8),
          lit(STATE_GOT_KEY_UP, width: 4),
          mux(code == lit(EXTENDED_CODE, width: 8),
            lit(STATE_IDLE, width: 4),
            mux(is_shift_key | is_ctrl_key,
              lit(STATE_IDLE, width: 4),
              lit(STATE_NORMAL_KEY, width: 4)
            )
          )
        )

        state_next = case_select(state, {
          STATE_IDLE       => mux(code_available, lit(STATE_HAVE_CODE, width: 4), lit(STATE_IDLE, width: 4)),
          STATE_HAVE_CODE  => lit(STATE_DECODE, width: 4),
          STATE_DECODE     => decode_next,
          STATE_GOT_KEY_UP => lit(STATE_GOT_KEY_UP2, width: 4),
          STATE_GOT_KEY_UP2 => lit(STATE_GOT_KEY_UP3, width: 4),
          STATE_GOT_KEY_UP3 => mux(code_available, lit(STATE_KEY_UP, width: 4), lit(STATE_GOT_KEY_UP3, width: 4)),
          STATE_KEY_UP     => lit(STATE_IDLE, width: 4),
          STATE_NORMAL_KEY => lit(STATE_IDLE, width: 4)
        }, default: lit(STATE_IDLE, width: 4))

        state <= state_next

        # Modifier updates in HAVE_CODE state
        shift <= mux(state == lit(STATE_HAVE_CODE, width: 4),
          mux(is_shift_key, lit(1, width: 1), shift),
          mux(state == lit(STATE_KEY_UP, width: 4),
            mux(is_shift_key, lit(0, width: 1), shift),
            shift
          )
        )

        ctrl <= mux(state == lit(STATE_HAVE_CODE, width: 4),
          mux(is_ctrl_key, lit(1, width: 1), ctrl),
          mux(state == lit(STATE_KEY_UP, width: 4),
            mux(is_ctrl_key, lit(0, width: 1), ctrl),
            ctrl
          )
        )

        alt <= mux(state == lit(STATE_HAVE_CODE, width: 4),
          mux(is_alt_key, lit(1, width: 1), alt),
          mux(state == lit(STATE_KEY_UP, width: 4),
            mux(is_alt_key, lit(0, width: 1), alt),
            alt
          )
        )

        # Latch code on NORMAL_KEY state
        latched_code <= mux(state == lit(STATE_NORMAL_KEY, width: 4),
          code, latched_code
        )

        key_pressed <= mux(state == lit(STATE_NORMAL_KEY, width: 4),
          lit(1, width: 1), key_pressed
        )
      end

      # Scancode to ASCII lookup table using memory DSL
      # Two ROMs: one for unshifted, one for shifted codes
      # Address is 8-bit scancode, data is 8-bit ASCII
      UNSHIFTED_MAP = build_scancode_rom(false)
      SHIFTED_MAP = build_scancode_rom(true)

      memory :unshifted_rom, depth: 256, width: 8, initial: UNSHIFTED_MAP
      memory :shifted_rom, depth: 256, width: 8, initial: SHIFTED_MAP

      # Async read from both ROMs
      wire :unshifted_ascii, width: 8
      wire :shifted_ascii, width: 8

      async_read :unshifted_ascii, from: :unshifted_rom, addr: :latched_code
      async_read :shifted_ascii, from: :shifted_rom, addr: :latched_code

      # Combinational ASCII lookup
      behavior do
        # Select shifted or unshifted based on shift key
        ascii_value = mux(shift, shifted_ascii, unshifted_ascii)

        # Apply ctrl modifier (mask to 5 bits)
        k <= mux(ctrl,
          cat(key_pressed, lit(0, width: 2), ascii_value[4..0]),
          cat(key_pressed, ascii_value[6..0])
        )
      end

      # Build scancode to ASCII ROM data
      def self.build_scancode_rom(shifted)
        rom = Array.new(256, 0)

        # Scancode mappings: scancode => [unshifted, shifted]
        mappings = {
          0x1C => [0x41, 0x41],  # A
          0x32 => [0x42, 0x42],  # B
          0x21 => [0x43, 0x43],  # C
          0x23 => [0x44, 0x44],  # D
          0x24 => [0x45, 0x45],  # E
          0x2B => [0x46, 0x46],  # F
          0x34 => [0x47, 0x47],  # G
          0x33 => [0x48, 0x48],  # H
          0x43 => [0x49, 0x49],  # I
          0x3B => [0x4A, 0x4A],  # J
          0x42 => [0x4B, 0x4B],  # K
          0x4B => [0x4C, 0x4C],  # L
          0x3A => [0x4D, 0x4D],  # M
          0x31 => [0x4E, 0x4E],  # N
          0x44 => [0x4F, 0x4F],  # O
          0x4D => [0x50, 0x50],  # P
          0x15 => [0x51, 0x51],  # Q
          0x2D => [0x52, 0x52],  # R
          0x1B => [0x53, 0x53],  # S
          0x2C => [0x54, 0x54],  # T
          0x3C => [0x55, 0x55],  # U
          0x2A => [0x56, 0x56],  # V
          0x1D => [0x57, 0x57],  # W
          0x22 => [0x58, 0x58],  # X
          0x35 => [0x59, 0x59],  # Y
          0x1A => [0x5A, 0x5A],  # Z
          0x45 => [0x30, 0x29],  # 0 )
          0x16 => [0x31, 0x21],  # 1 !
          0x1E => [0x32, 0x40],  # 2 @
          0x26 => [0x33, 0x23],  # 3 #
          0x25 => [0x34, 0x24],  # 4 $
          0x2E => [0x35, 0x25],  # 5 %
          0x36 => [0x36, 0x5E],  # 6 ^
          0x3D => [0x37, 0x26],  # 7 &
          0x3E => [0x38, 0x2A],  # 8 *
          0x46 => [0x39, 0x28],  # 9 (
          0x29 => [0x20, 0x20],  # Space
          0x5A => [0x0D, 0x0D],  # Enter
          0x66 => [0x08, 0x08],  # Backspace
          0x0D => [0x09, 0x09],  # Tab
          0x76 => [0x1B, 0x1B],  # Escape
          0x71 => [0x7F, 0x7F],  # Delete
          0x74 => [0x15, 0x15],  # Right arrow (Ctrl-U)
          0x6B => [0x08, 0x08],  # Left arrow (BS)
          0x75 => [0x0B, 0x0B],  # Up arrow
          0x72 => [0x0A, 0x0A],  # Down arrow (LF)
        }

        mappings.each do |scancode, values|
          rom[scancode] = shifted ? values[1] : values[0]
        end

        rom
      end
    end
  end
end
