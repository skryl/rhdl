#!/usr/bin/env ruby
# Debug script for 6502 CPU execution

require_relative 'lib/rhdl'
require_relative 'examples/mos6502/cpu'

cpu = MOS6502::CPU.new

# Test: count from 0 to 5
source = <<~'ASM'
  LDA #$00
LOOP:
  CLC
  ADC #$01
  CMP #$05
  BNE LOOP
ASM

bytes = cpu.assemble_and_load(source)
cpu.reset

puts "=== Test: Count from 0 to 5 ==="
puts "Assembled bytes: #{bytes.map { |b| '0x' + b.to_s(16).upcase.rjust(2,'0') }.join(' ')}"
puts ""
puts "Memory dump:"
(0x8000...0x8000+bytes.length).each do |addr|
  puts "  0x#{addr.to_s(16).upcase.rjust(4,'0')}: 0x#{cpu.read_mem(addr).to_s(16).upcase.rjust(2,'0')}"
end
puts ""
puts "Initial: A=#{cpu.a}, PC=0x#{cpu.pc.to_s(16).upcase.rjust(4,'0')}"
puts ""

datapath = cpu.instance_variable_get(:@datapath)
control = datapath.instance_variable_get(:@control)

puts "Before first step:"
puts "  State output: #{datapath.get_output(:state)}"
puts "  Control internal state: #{control.current_state}"
puts ""

puts "=== Stepping through program ==="
30.times do |i|
  pc = cpu.pc
  opcode = cpu.read_mem(pc)
  a_before = cpu.a

  cpu.step

  puts "Step #{i+1}: PC=0x#{pc.to_s(16).upcase.rjust(4,'0')} Op=0x#{opcode.to_s(16).upcase.rjust(2,'0')} => A=0x#{cpu.a.to_s(16).upcase.rjust(2,'0')} (#{cpu.a}), C=#{cpu.flag_c}, Z=#{cpu.flag_z}, PC_after=0x#{cpu.pc.to_s(16).upcase.rjust(4,'0')}"

  break if opcode == 0x00 || cpu.halted?
  break if cpu.a == 5
end

puts ""
puts "Final: A=#{cpu.a} (expected: 5)"
