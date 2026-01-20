#!/usr/bin/env ruby
# Benchmark: Ruby vs Native Rust ISA Simulator
# Run from project root: bundle exec ruby examples/mos6502/utilities/benchmark_native.rb

require_relative '../../../lib/rhdl'
require_relative 'isa_simulator_native'
require_relative 'isa_simulator'

puts "=" * 70
puts "ISA Simulator Benchmark: Ruby vs Native Rust"
puts "=" * 70
puts
puts "Memory Model:"
puts "  Ruby:           All memory access via Ruby callbacks"
puts "  Native (int):   All memory internal to Rust (fastest)"
puts "  Native (I/O):   Internal memory + I/O handler for $C000-$CFFF"
puts

# Simple loop: count down X from 255 to 0 (quick test)
# Note: Use illegal opcode 0x02 to halt (BRK jumps to IRQ vector, doesn't halt)
program = [
  0xA2, 0xFF,       # LDX #$FF
  0xCA,             # loop: DEX
  0xD0, 0xFD,       # BNE loop
  0x02              # Illegal opcode (halts both implementations)
]

# Simple I/O handler that does nothing (simulates Apple2Bus I/O region)
class DummyIOHandler
  def io_read(addr)
    0
  end

  def io_write(addr, value)
  end
end

puts "Test 1: Simple loop (X from 255 to 0) - single run"

# Ruby implementation
mem = Array.new(0x10000, 0)
program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
memory = Object.new
memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
cpu = MOS6502::ISASimulator.new(memory)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
ruby_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Ruby:           #{(ruby_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

# Native internal memory (no I/O handler)
cpu = MOS6502::ISASimulatorNative.new(nil)
cpu.load_bytes(program, 0x8000)
cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_int_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (int):   #{(native_int_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

# Native with I/O handler (hybrid memory model)
io_handler = DummyIOHandler.new
cpu = MOS6502::ISASimulatorNative.new(io_handler)
cpu.load_bytes(program, 0x8000)
cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_io_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (I/O):   #{(native_io_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

puts
puts "Test 2: 100 iterations of simple loop"

# Ruby - run 100 iterations
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100.times do
  mem = Array.new(0x10000, 0)
  program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
  mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
  memory = Object.new
  memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
  memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
  cpu = MOS6502::ISASimulator.new(memory)
  cpu.reset
  cpu.step until cpu.halted?
end
ruby_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Ruby:           #{(ruby_total * 1000).round(1)} ms"

# Native internal - run 100 iterations
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100.times do
  cpu = MOS6502::ISASimulatorNative.new(nil)
  cpu.load_bytes(program, 0x8000)
  cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
  cpu.reset
  cpu.step until cpu.halted?
end
native_int_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (int):   #{(native_int_total * 1000).round(1)} ms"

# Native with I/O handler - run 100 iterations
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
100.times do
  io_handler = DummyIOHandler.new
  cpu = MOS6502::ISASimulatorNative.new(io_handler)
  cpu.load_bytes(program, 0x8000)
  cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
  cpu.reset
  cpu.step until cpu.halted?
end
native_io_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (I/O):   #{(native_io_total * 1000).round(1)} ms"

# Program that accesses I/O region to test callback overhead
io_program = [
  0xA2, 0xFF,        # LDX #$FF
                     # loop:
  0xAD, 0x00, 0xC0,  # LDA $C000 (I/O read)
  0xCA,              # DEX
  0xD0, 0xFA,        # BNE loop
  0x02               # Halt
]

puts
puts "Test 3: Loop with I/O access (255 reads from $C000)"

# Ruby implementation (all memory via callbacks)
mem = Array.new(0x10000, 0)
io_program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
memory = Object.new
memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
cpu = MOS6502::ISASimulator.new(memory)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
ruby_io_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Ruby:           #{(ruby_io_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

# Native internal (no I/O handler - reads from internal memory)
cpu = MOS6502::ISASimulatorNative.new(nil)
cpu.load_bytes(io_program, 0x8000)
cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_int_io_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (int):   #{(native_int_io_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

# Native with I/O handler (I/O reads go through Ruby)
io_handler = DummyIOHandler.new
cpu = MOS6502::ISASimulatorNative.new(io_handler)
cpu.load_bytes(io_program, 0x8000)
cpu.poke(0xFFFC, 0x00); cpu.poke(0xFFFD, 0x80)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_io_io_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (I/O):   #{(native_io_io_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

puts
puts "=" * 70
puts "Summary (100 iterations of 255-count loop):"
puts "=" * 70
puts "  Ruby ISASimulator:              #{(ruby_total * 1000).round(1)} ms"
puts "  Native (internal memory):       #{(native_int_total * 1000).round(1)} ms"
puts "  Native (I/O handler):           #{(native_io_total * 1000).round(1)} ms"
puts
puts "Speedup vs Ruby:"
puts "  Native (internal memory):       #{(ruby_total / native_int_total).round(1)}x faster"
puts "  Native (I/O handler):           #{(ruby_total / native_io_total).round(1)}x faster"
puts
puts "Note: Native I/O handler is nearly as fast as internal memory for"
puts "code that doesn't access the I/O region ($C000-$CFFF)."
puts "=" * 70
