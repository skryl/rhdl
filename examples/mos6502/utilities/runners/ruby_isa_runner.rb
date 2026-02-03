# frozen_string_literal: true

# Wrapper for pure Ruby ISA simulator to match ISARunner interface
# Used when native Rust extension is not available
class RubyISARunner
  attr_reader :cpu, :bus

  def initialize(bus, cpu)
    @bus = bus
    @cpu = cpu
  end

  def native?
    false
  end

  def simulator_type
    :ruby
  end

  def load_rom(bytes, base_addr:)
    @bus.load_rom(bytes.is_a?(String) ? bytes.bytes : bytes, base_addr: base_addr)
  end

  def load_ram(bytes, base_addr:)
    @bus.load_ram(bytes.is_a?(String) ? bytes.bytes : bytes, base_addr: base_addr)
  end

  def load_disk(path_or_bytes, drive: 0)
    @bus.load_disk(path_or_bytes, drive: drive)
  end

  def disk_loaded?(drive: 0)
    @bus.disk_loaded?(drive: drive)
  end

  def reset
    @cpu.reset
  end

  def run_steps(steps)
    @cpu.run_cycles(steps)
  end

  def inject_key(ascii)
    @bus.inject_key(ascii)
  end

  def key_ready?
    @bus.key_ready
  end

  def clear_key
    @bus.clear_key
  end

  def read_screen
    @bus.read_text_page_string
  end

  def read_screen_array
    @bus.read_text_page
  end

  def screen_dirty?
    @bus.text_page_dirty?
  end

  def clear_screen_dirty
    @bus.clear_text_page_dirty
  end

  def cpu_state
    {
      pc: @cpu.pc,
      a: @cpu.a,
      x: @cpu.x,
      y: @cpu.y,
      sp: @cpu.sp,
      p: @cpu.p,
      cycles: @cpu.cycles,
      halted: @cpu.halted?,
      simulator_type: :ruby
    }
  end

  def halted?
    @cpu.halted?
  end

  def cycle_count
    @cpu.cycles
  end
end
