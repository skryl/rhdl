#!/usr/bin/env ruby
# Benchmark: Ruby vs Native Rust ISA Simulator
# Run from project root: bundle exec ruby examples/mos6502/utilities/benchmark_native.rb

require_relative '../../../lib/rhdl'
require_relative 'isa_simulator_native'
require_relative 'isa_simulator'

puts "=" * 70
puts "ISA Simulator Benchmark: Ruby vs Native Rust"
puts "=" * 70

# Simple loop: count down X from 255 to 0 (quick test)
# Note: Use illegal opcode 0x02 to halt (BRK jumps to IRQ vector, doesn't halt)
program = [
  0xA2, 0xFF,       # LDX #$FF
  0xCA,             # loop: DEX
  0xD0, 0xFD,       # BNE loop
  0x02              # Illegal opcode (halts both implementations)
]

puts "\nTest 1: Simple loop (X from 255 to 0) - single run"

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

# Native internal memory
cpu = MOS6502::ISASimulatorNative.new(nil)
program.each_with_index { |b, idx| cpu.write(0x8000 + idx, b) }
cpu.write(0xFFFC, 0x00); cpu.write(0xFFFD, 0x80)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_int_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (int):   #{(native_int_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

# Native external memory
mem = Array.new(0x10000, 0)
program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
memory = Object.new
memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
cpu = MOS6502::ISASimulatorNative.new(memory)
cpu.reset
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cpu.step until cpu.halted?
native_ext_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (ext):   #{(native_ext_time * 1000).round(3)} ms (#{cpu.cycles} cycles)"

puts "\nTest 2: 1000 iterations of simple loop"

# Ruby - run 1000 iterations
total_ruby = 0.0
1000.times do
  mem = Array.new(0x10000, 0)
  program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
  mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
  memory = Object.new
  memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
  memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
  cpu = MOS6502::ISASimulator.new(memory)
  cpu.reset
  cpu.step until cpu.halted?
  total_ruby += cpu.cycles
end
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
1000.times do
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

# Native internal - run 1000 iterations
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
1000.times do
  cpu = MOS6502::ISASimulatorNative.new(nil)
  program.each_with_index { |b, idx| cpu.write(0x8000 + idx, b) }
  cpu.write(0xFFFC, 0x00); cpu.write(0xFFFD, 0x80)
  cpu.reset
  cpu.step until cpu.halted?
end
native_int_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (int):   #{(native_int_total * 1000).round(1)} ms"

# Native external - run 1000 iterations
start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
1000.times do
  mem = Array.new(0x10000, 0)
  program.each_with_index { |b, idx| mem[0x8000 + idx] = b }
  mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x80
  memory = Object.new
  memory.define_singleton_method(:read) { |addr| mem[addr & 0xFFFF] }
  memory.define_singleton_method(:write) { |addr, val| mem[addr & 0xFFFF] = val & 0xFF }
  cpu = MOS6502::ISASimulatorNative.new(memory)
  cpu.reset
  cpu.step until cpu.halted?
end
native_ext_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
puts "  Native (ext):   #{(native_ext_total * 1000).round(1)} ms"

puts
puts "=" * 70
puts "Summary (1000 iterations of 255-count loop):"
puts "=" * 70
puts "  Ruby ISASimulator:              #{(ruby_total * 1000).round(1)} ms"
puts "  Native (internal memory):       #{(native_int_total * 1000).round(1)} ms"
puts "  Native (external memory):       #{(native_ext_total * 1000).round(1)} ms"
puts
puts "Speedup vs Ruby:"
puts "  Native (internal memory):       #{(ruby_total / native_int_total).round(1)}x faster"
puts "  Native (external memory):       #{(ruby_total / native_ext_total).round(1)}x faster"
puts "=" * 70
