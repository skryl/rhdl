# frozen_string_literal: true

# PS/2 Protocol Encoder
# Converts ASCII key codes to PS/2 scancodes and bit-bangs the PS/2 protocol

module RHDL
  module Apple2
    # PS/2 keyboard encoder - converts ASCII to PS/2 scancodes
    # and handles the PS/2 protocol bit-banging
    class PS2Encoder
      # PS/2 special codes
      KEY_UP_CODE = 0xF0

      # Build reverse lookup table: ASCII -> [scancode, needs_shift]
      # Based on the scancode mappings in keyboard.rb
      ASCII_TO_SCANCODE = {
        # Letters (A-Z) - all unshifted in Apple II (uppercase only)
        0x41 => [0x1C, false], # A
        0x42 => [0x32, false], # B
        0x43 => [0x21, false], # C
        0x44 => [0x23, false], # D
        0x45 => [0x24, false], # E
        0x46 => [0x2B, false], # F
        0x47 => [0x34, false], # G
        0x48 => [0x33, false], # H
        0x49 => [0x43, false], # I
        0x4A => [0x3B, false], # J
        0x4B => [0x42, false], # K
        0x4C => [0x4B, false], # L
        0x4D => [0x3A, false], # M
        0x4E => [0x31, false], # N
        0x4F => [0x44, false], # O
        0x50 => [0x4D, false], # P
        0x51 => [0x15, false], # Q
        0x52 => [0x2D, false], # R
        0x53 => [0x1B, false], # S
        0x54 => [0x2C, false], # T
        0x55 => [0x3C, false], # U
        0x56 => [0x2A, false], # V
        0x57 => [0x1D, false], # W
        0x58 => [0x22, false], # X
        0x59 => [0x35, false], # Y
        0x5A => [0x1A, false], # Z

        # Numbers (unshifted)
        0x30 => [0x45, false], # 0
        0x31 => [0x16, false], # 1
        0x32 => [0x1E, false], # 2
        0x33 => [0x26, false], # 3
        0x34 => [0x25, false], # 4
        0x35 => [0x2E, false], # 5
        0x36 => [0x36, false], # 6
        0x37 => [0x3D, false], # 7
        0x38 => [0x3E, false], # 8
        0x39 => [0x46, false], # 9

        # Shifted numbers (symbols)
        0x29 => [0x45, true],  # )
        0x21 => [0x16, true],  # !
        0x40 => [0x1E, true],  # @
        0x23 => [0x26, true],  # #
        0x24 => [0x25, true],  # $
        0x25 => [0x2E, true],  # %
        0x5E => [0x36, true],  # ^
        0x26 => [0x3D, true],  # &
        0x2A => [0x3E, true],  # *
        0x28 => [0x46, true],  # (

        # Special keys
        0x20 => [0x29, false], # Space
        0x0D => [0x5A, false], # Enter/Return
        0x08 => [0x66, false], # Backspace
        0x09 => [0x0D, false], # Tab
        0x1B => [0x76, false], # Escape
        0x7F => [0x71, false], # Delete

        # Arrow keys (Apple II control codes)
        0x15 => [0x74, false], # Right arrow (Ctrl-U)
        # 0x08 already mapped to backspace, but Left uses same
        0x0B => [0x75, false], # Up arrow (Ctrl-K)
        0x0A => [0x72, false], # Down arrow (LF/Ctrl-J)
      }.freeze

      # Left shift scancode for shifted keys
      LEFT_SHIFT_SCANCODE = 0x12

      def initialize
        @ps2_queue = []  # Queue of [clk, data] pairs to send
        @current_bit = 0
        @sending = false
      end

      # Queue a key press (and optionally release) for PS/2 transmission
      # @param ascii [Integer] ASCII code of the key
      # @param release [Boolean] Whether to also queue a key release after
      def queue_key(ascii, release: true)
        mapping = ASCII_TO_SCANCODE[ascii]
        return unless mapping

        scancode, needs_shift = mapping

        # Send shift press if needed
        queue_scancode(LEFT_SHIFT_SCANCODE) if needs_shift

        # Send the key scancode
        queue_scancode(scancode)

        if release
          # Send key release (F0 + scancode)
          queue_key_release(scancode)

          # Send shift release if needed
          queue_key_release(LEFT_SHIFT_SCANCODE) if needs_shift
        end
      end

      # Queue just a key release
      def queue_key_release(scancode)
        queue_scancode(KEY_UP_CODE)
        queue_scancode(scancode)
      end

      # Queue a scancode for PS/2 transmission
      # PS/2 protocol: 11 bits - 1 start (0) + 8 data (LSB first) + 1 parity (odd) + 1 stop (1)
      # Data is sampled on falling edge of clock
      def queue_scancode(scancode)
        # Calculate odd parity (total 1-bits including parity should be odd)
        parity = 1  # Start with 1 for odd parity
        8.times { |i| parity ^= (scancode >> i) & 1 }

        # Build the 11-bit frame
        frame = []
        frame << 0  # Start bit
        8.times { |i| frame << ((scancode >> i) & 1) }  # Data bits (LSB first)
        frame << parity  # Parity bit
        frame << 1  # Stop bit

        # Convert to clock/data pairs
        # PS/2 clock is normally high, data changes when clock is high,
        # then clock goes low (falling edge = sample point), then clock goes high
        frame.each do |bit|
          # Data setup: clock high, set data
          @ps2_queue << [1, bit]
          # Falling edge: clock low (receiver samples here)
          @ps2_queue << [0, bit]
          # Clock returns high
          @ps2_queue << [1, bit]
        end

        # Inter-byte gap (clock high, data high)
        10.times { @ps2_queue << [1, 1] }
      end

      # Get the next PS/2 clock/data pair to send
      # @return [Array<Integer>] [clk, data] or [1, 1] if idle
      def next_ps2_state
        if @ps2_queue.empty?
          [1, 1]  # Idle state: clock and data both high
        else
          @ps2_queue.shift
        end
      end

      # Check if there's data queued to send
      def sending?
        !@ps2_queue.empty?
      end

      # Clear the queue
      def clear
        @ps2_queue.clear
      end

      # Get queue length (for debugging)
      def queue_length
        @ps2_queue.length
      end
    end
  end
end
