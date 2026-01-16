#!/usr/bin/env ruby
# Direct test script for HDL CPU - bypasses bundler

$LOAD_PATH.unshift File.expand_path('lib', __dir__)

require 'active_support/core_ext/string/inflections'
require 'rhdl'

# Simple memory implementation
class TestMemory
  def initialize
    @memory = Array.new(0x10000, 0)
  end

  def read(addr)
    @memory[addr & 0xFFFF]
  end

  def write(addr, value)
    @memory[addr & 0xFFFF] = value & 0xFF
  end

  def load(program, start_addr = 0)
    program.each_with_index do |byte, i|
      write(start_addr + i, byte)
    end
  end
end

def test(name, &block)
  print "Testing #{name}... "
  begin
    block.call
    puts "PASSED"
    true
  rescue => e
    puts "FAILED: #{e.message}"
    puts e.backtrace.first(3).join("\n")
    false
  end
end

def assert_eq(actual, expected, msg = "")
  unless actual == expected
    raise "Expected #{expected.inspect}, got #{actual.inspect}. #{msg}"
  end
end

# Test counter
passed = 0
failed = 0

puts "=" * 60
puts "Testing HDL CPU Implementation"
puts "=" * 60

# Test 1: Basic creation and reset
result = test("HDL CPU creation and reset") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.reset  # Explicit reset
  assert_eq cpu.acc, 0, "ACC should be 0"
  assert_eq cpu.pc, 0, "PC should be 0"
  assert_eq cpu.halted, false, "Should not be halted"
  assert_eq cpu.sp, 0xFF, "SP should be 0xFF"
end
result ? passed += 1 : failed += 1

# Test 2: LDI instruction
result = test("LDI instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0x42], 0)  # LDI 0x42
  cpu.step
  assert_eq cpu.acc, 0x42, "ACC should be 0x42"
  assert_eq cpu.pc, 2, "PC should be 2"
end
result ? passed += 1 : failed += 1

# Test 3: LDA instruction
result = test("LDA instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 0x99)
  cpu.memory.load([0x15], 0)  # LDA 0x5
  cpu.step
  assert_eq cpu.acc, 0x99, "ACC should be 0x99"
  assert_eq cpu.pc, 1, "PC should be 1"
end
result ? passed += 1 : failed += 1

# Test 4: STA instruction
result = test("STA instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0x55, 0x23], 0)  # LDI 0x55, STA 3
  cpu.step  # LDI
  cpu.step  # STA
  assert_eq cpu.memory.read(3), 0x55, "Memory[3] should be 0x55"
end
result ? passed += 1 : failed += 1

# Test 5: ADD instruction
result = test("ADD instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 20)
  cpu.memory.load([0xA0, 10, 0x35], 0)  # LDI 10, ADD 5
  cpu.step  # LDI
  cpu.step  # ADD
  assert_eq cpu.acc, 30, "ACC should be 30"
end
result ? passed += 1 : failed += 1

# Test 6: SUB instruction
result = test("SUB instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 20)
  cpu.memory.load([0xA0, 50, 0x45], 0)  # LDI 50, SUB 5
  cpu.step  # LDI
  cpu.step  # SUB
  assert_eq cpu.acc, 30, "ACC should be 30"
end
result ? passed += 1 : failed += 1

# Test 7: AND instruction
result = test("AND instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 0x0F)
  cpu.memory.load([0xA0, 0xFF, 0x55], 0)  # LDI 0xFF, AND 5
  cpu.step  # LDI
  cpu.step  # AND
  assert_eq cpu.acc, 0x0F, "ACC should be 0x0F"
end
result ? passed += 1 : failed += 1

# Test 8: OR instruction
result = test("OR instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 0x0F)
  cpu.memory.load([0xA0, 0xF0, 0x65], 0)  # LDI 0xF0, OR 5
  cpu.step  # LDI
  cpu.step  # OR
  assert_eq cpu.acc, 0xFF, "ACC should be 0xFF"
end
result ? passed += 1 : failed += 1

# Test 9: XOR instruction
result = test("XOR instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 0x0F)
  cpu.memory.load([0xA0, 0xFF, 0x75], 0)  # LDI 0xFF, XOR 5
  cpu.step  # LDI
  cpu.step  # XOR
  assert_eq cpu.acc, 0xF0, "ACC should be 0xF0"
end
result ? passed += 1 : failed += 1

# Test 10: NOT instruction
result = test("NOT instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0xF0, 0xF2], 0)  # LDI 0xF0, NOT
  cpu.step  # LDI
  cpu.step  # NOT
  assert_eq cpu.acc, 0x0F, "ACC should be 0x0F"
end
result ? passed += 1 : failed += 1

# Test 11: JMP instruction
result = test("JMP instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xBA], 0)  # JMP 0xA
  cpu.step
  assert_eq cpu.pc, 0x0A, "PC should be 0x0A"
end
result ? passed += 1 : failed += 1

# Test 12: JZ instruction (zero flag set)
result = test("JZ instruction (zero flag set)") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0x00, 0x8A], 0)  # LDI 0, JZ 0xA
  cpu.step  # LDI 0 (sets zero flag)
  cpu.step  # JZ
  assert_eq cpu.pc, 0x0A, "PC should be 0x0A"
end
result ? passed += 1 : failed += 1

# Test 13: JZ instruction (zero flag clear)
result = test("JZ instruction (zero flag clear)") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0x01, 0x8A], 0)  # LDI 1, JZ 0xA
  cpu.step  # LDI 1 (clears zero flag)
  cpu.step  # JZ (should not jump)
  assert_eq cpu.pc, 3, "PC should be 3 (no jump)"
end
result ? passed += 1 : failed += 1

# Test 14: JNZ instruction (zero flag clear)
result = test("JNZ instruction (zero flag clear)") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xA0, 0x01, 0x9A], 0)  # LDI 1, JNZ 0xA
  cpu.step  # LDI 1
  cpu.step  # JNZ
  assert_eq cpu.pc, 0x0A, "PC should be 0x0A"
end
result ? passed += 1 : failed += 1

# Test 15: HLT instruction
result = test("HLT instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0xF0], 0)  # HLT
  cpu.step
  assert_eq cpu.halted, true, "CPU should be halted"
end
result ? passed += 1 : failed += 1

# Test 16: MUL instruction
result = test("MUL instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x0A, 3)
  cpu.memory.load([0xA0, 5, 0xF1, 0x0A], 0)  # LDI 5, MUL 0x0A
  cpu.step  # LDI
  cpu.step  # MUL
  assert_eq cpu.acc, 15, "ACC should be 15"
end
result ? passed += 1 : failed += 1

# Test 17: DIV instruction
result = test("DIV instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 4)
  cpu.memory.load([0xA0, 20, 0xE5], 0)  # LDI 20, DIV 5
  cpu.step  # LDI
  cpu.step  # DIV
  assert_eq cpu.acc, 5, "ACC should be 5"
end
result ? passed += 1 : failed += 1

# Test 18: NOP instruction
result = test("NOP instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.load([0x00], 0)  # NOP
  cpu.step
  assert_eq cpu.pc, 1, "PC should be 1"
  assert_eq cpu.acc, 0, "ACC should be 0"
end
result ? passed += 1 : failed += 1

# Test 19: CALL and RET
result = test("CALL and RET instructions") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  # Program: LDI 5, CALL 5, HLT, NOP, ADD 0xF, RET
  # Address 0-1: LDI 5 (A0 05)
  # Address 2: CALL 5 (C5) - call subroutine at address 5
  # Address 3: HLT (F0)
  # Address 4: NOP (00) - padding
  # Address 5: ADD 0xF (3F) - add memory[0xF]
  # Address 6: RET (D0)
  # Memory[0x0F] = 0x24
  cpu.memory.load([0xA0, 0x05, 0xC5, 0xF0, 0x00, 0x3F, 0xD0], 0)
  cpu.memory.write(0x0F, 0x24)  # Write after load so it's not overwritten

  # Run until halted
  max_cycles = 100
  cycles = 0
  while !cpu.halted && cycles < max_cycles
    cpu.step
    cycles += 1
  end

  assert_eq cpu.halted, true, "CPU should be halted"
  assert_eq cpu.pc, 3, "PC should be 3 (after HLT)"
  assert_eq cpu.acc, 0x05 + 0x24, "ACC should be 0x29"
end
result ? passed += 1 : failed += 1

# Test 20: Zero flag setting
result = test("Zero flag after SUB resulting in 0") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  cpu.memory.write(0x05, 42)
  cpu.memory.load([0xA0, 42, 0x45], 0)  # LDI 42, SUB 5 (42-42=0)
  cpu.step  # LDI
  cpu.step  # SUB
  assert_eq cpu.acc, 0, "ACC should be 0"
  assert_eq cpu.zero_flag, true, "Zero flag should be true"
end
result ? passed += 1 : failed += 1

# Test 21: Simple program execution
result = test("Simple program: count 3 + 5 = 8") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  # LDI 3, STA 10, LDI 5, ADD 10, STA 11, HLT
  program = [
    0xA0, 0x03,  # LDI 3
    0x2A,        # STA 10
    0xA0, 0x05,  # LDI 5
    0x3A,        # ADD 10
    0x2B,        # STA 11
    0xF0         # HLT
  ]
  cpu.memory.load(program, 0)

  while !cpu.halted
    cpu.step
  end

  assert_eq cpu.memory.read(10), 3, "Memory[10] should be 3"
  assert_eq cpu.memory.read(11), 8, "Memory[11] should be 8"
  assert_eq cpu.halted, true, "CPU should be halted"
end
result ? passed += 1 : failed += 1

# Test 22: Indirect STA
result = test("Indirect STA instruction") do
  memory = TestMemory.new
  cpu = RHDL::HDL::CPU::CPUAdapter.new(memory)
  # Setup: store address 0x0800 in locations 0x20 (high) and 0x21 (low)
  # Then use indirect STA to write to 0x0800
  program = [
    0xA0, 0x08,  # LDI 0x08 (high byte)
    0x21, 0x20,  # STA 0x20 (2-byte direct STA)
    0xA0, 0x00,  # LDI 0x00 (low byte)
    0x21, 0x21,  # STA 0x21
    0xA0, 0x42,  # LDI 0x42 (value to store)
    0x20, 0x20, 0x21,  # STA [0x20, 0x21] (indirect)
    0xF0         # HLT
  ]
  cpu.memory.load(program, 0)

  while !cpu.halted
    cpu.step
  end

  assert_eq cpu.memory.read(0x800), 0x42, "Memory[0x800] should be 0x42"
end
result ? passed += 1 : failed += 1

puts "=" * 60
puts "Results: #{passed} passed, #{failed} failed"
puts "=" * 60

exit(failed > 0 ? 1 : 0)
