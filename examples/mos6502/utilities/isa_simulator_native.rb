# frozen_string_literal: true

# MOS 6502 Native ISA-Level Simulator
# High-performance instruction-level simulator implemented in Rust
# Falls back to pure Ruby implementation if native extension is not available

module MOS6502
  # Try to load the native extension
  NATIVE_AVAILABLE = begin
    require_relative 'isa_simulator_native/lib/isa_simulator_native'
    true
  rescue LoadError => e
    warn "Native ISA simulator not available: #{e.message}" if ENV['DEBUG']
    warn "Falling back to pure Ruby implementation" if ENV['DEBUG']
    false
  end

  unless NATIVE_AVAILABLE
    # Load the pure Ruby implementation as fallback
    require_relative 'isa_simulator'
  end

  # ISASimulatorNative - High-performance 6502 simulator
  #
  # The native Rust implementation provides ~7x speedup over the pure Ruby
  # implementation. It uses a hybrid memory model:
  #
  # - Internal 64KB memory for fast CPU access
  # - Optional I/O handler for memory-mapped I/O ($C000-$CFFF)
  # - External devices can access memory via peek/poke methods
  #
  # @example Basic usage with internal memory only
  #   cpu = MOS6502::ISASimulatorNative.new(nil)
  #   cpu.load_bytes([0xA9, 0x42, 0x85, 0x00], 0x8000)
  #   cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
  #   cpu.reset
  #   cpu.step
  #   puts cpu.a  # => 0x42
  #
  # @example Usage with I/O handler (for Apple II emulation)
  #   bus = MOS6502::Apple2Bus.new
  #   cpu = MOS6502::ISASimulatorNative.new(bus)  # bus provides io_read/io_write
  #   cpu.load_bytes(rom_bytes, 0xF800)           # load ROM to CPU memory
  #   cpu.reset
  #   cpu.step
  #
  if NATIVE_AVAILABLE
    # Native class is already defined by the Rust extension
    # Add any Ruby-only convenience methods here
    class ISASimulatorNative
      # Status flag bit positions (matching Ruby implementation)
      FLAG_C = 0  # Carry
      FLAG_Z = 1  # Zero
      FLAG_I = 2  # Interrupt Disable
      FLAG_D = 3  # Decimal Mode
      FLAG_B = 4  # Break
      FLAG_U = 5  # Unused (always 1)
      FLAG_V = 6  # Overflow
      FLAG_N = 7  # Negative

      # Interrupt vectors (also available as module constants)
      NMI_VECTOR   = 0xFFFA
      RESET_VECTOR = 0xFFFC
      IRQ_VECTOR   = 0xFFFE

      # Set a flag in the status register
      # @param flag [Integer] Flag bit position (0-7)
      # @param value [Integer, Boolean] Value to set (0/1 or true/false)
      def set_flag(flag, value)
        if value != 0 && value != false
          self.p = self.p | (1 << flag)
        else
          self.p = self.p & ~(1 << flag)
        end
      end
    end
  else
    # Fallback: alias the pure Ruby implementation
    ISASimulatorNative = ISASimulator

    # Add native? method to Ruby implementation
    class ISASimulatorNative
      def native?
        false
      end
    end
  end

  # Factory method to create the best available simulator for simple programs
  # @param io_handler [Object, nil] Optional I/O handler with io_read/io_write methods
  # @return [ISASimulatorNative] The native simulator instance (or Ruby fallback)
  def self.create_fast_simulator(io_handler = nil)
    ISASimulatorNative.new(io_handler)
  end

  # Check if native simulator is available
  # @return [Boolean] true if native Rust implementation is loaded
  def self.native_available?
    NATIVE_AVAILABLE
  end
end
