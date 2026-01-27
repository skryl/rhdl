#!/usr/bin/env ruby
# frozen_string_literal: true

# Karateka ISA vs IR Compiler Divergence Analysis
# Compares PC progression and screen state over 10M cycles

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../examples/apple2/utilities', __dir__)
$LOAD_PATH.unshift File.expand_path('../examples/mos6502/utilities', __dir__)

require 'rhdl'
require_relative '../examples/apple2/hdl/apple2'

ROM_PATH = File.expand_path('../examples/apple2/software/roms/appleiigo.rom', __dir__)
KARATEKA_MEM_PATH = File.expand_path('../examples/apple2/software/disks/karateka_mem.bin', __dir__)

# Note: ISA simulator runs INSTRUCTIONS, IR compiler runs CLOCK CYCLES
# Average 6502 instruction takes ~3.5 clock cycles
# So to compare at the same simulation point, we need to account for this
TOTAL_INSTRUCTIONS = 10_000_000
CHECKPOINT_INTERVAL = 500_000
AVG_CYCLES_PER_INSTRUCTION = 4  # Conservative estimate (actual ~3.5)

def create_karateka_rom(rom_data)
  rom = rom_data.dup
  rom[0x2FFC] = 0x2A  # low byte of $B82A
  rom[0x2FFD] = 0xB8  # high byte of $B82A
  rom
end

def create_isa_simulator(rom_data, karateka_mem)
  require 'apple2_bus'
  require 'isa_simulator_native'

  karateka_rom = create_karateka_rom(rom_data)
  bus = MOS6502::Apple2Bus.new
  bus.load_rom(karateka_rom, base_addr: 0xD000)
  bus.load_ram(karateka_mem, base_addr: 0x0000)

  cpu = MOS6502::ISASimulatorNative.new(bus)
  cpu.load_bytes(karateka_mem, 0x0000)
  cpu.load_bytes(karateka_rom, 0xD000)
  cpu.reset

  [cpu, bus]
end

def create_ir_compiler(rom_data, karateka_mem)
  require 'rhdl/codegen'

  ir = RHDL::Apple2::Apple2.to_flat_ir
  ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

  sim = RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json, sub_cycles: 14)

  karateka_rom = create_karateka_rom(rom_data)
  sim.load_rom(karateka_rom)
  sim.load_ram(karateka_mem.first(48 * 1024), 0)

  sim.poke('reset', 1)
  sim.tick
  sim.poke('reset', 0)
  3.times { sim.run_cpu_cycles(1, 0, false) }

  sim
end

def hires_checksum_isa(bus)
  checksum = 0
  (0x2000..0x3FFF).each do |addr|
    checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
  end
  checksum
end

def hires_checksum_ir(sim)
  checksum = 0
  data = sim.read_ram(0x2000, 0x2000).to_a
  data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
  checksum
end

def text_checksum_isa(bus)
  checksum = 0
  (0x0400..0x07FF).each do |addr|
    checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
  end
  checksum
end

def text_checksum_ir(sim)
  checksum = 0
  data = sim.read_ram(0x0400, 0x400).to_a
  data.each { |b| checksum = (checksum + b) & 0xFFFFFFFF }
  checksum
end

# Main
puts "=" * 70
puts "Karateka ISA vs IR Compiler Divergence Analysis"
puts "Total instructions: #{TOTAL_INSTRUCTIONS.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
puts "IR cycles per ISA instruction: #{AVG_CYCLES_PER_INSTRUCTION}"
puts "=" * 70

unless File.exist?(ROM_PATH)
  puts "ERROR: AppleIIgo ROM not found at #{ROM_PATH}"
  exit 1
end

unless File.exist?(KARATEKA_MEM_PATH)
  puts "ERROR: Karateka memory dump not found at #{KARATEKA_MEM_PATH}"
  exit 1
end

rom_data = File.binread(ROM_PATH).bytes
karateka_mem = File.binread(KARATEKA_MEM_PATH).bytes

puts "\nInitializing simulators..."
isa_cpu, isa_bus = create_isa_simulator(rom_data, karateka_mem)
ir_sim = create_ir_compiler(rom_data, karateka_mem)

puts "  ISA: Native Rust ISA simulator"
puts "  IR:  Rust IR Compiler (sub_cycles=14)"

checkpoints = []
divergence_point = nil

instructions_run = 0
start_time = Time.now

puts "\nRunning comparison..."
puts "-" * 70

while instructions_run < TOTAL_INSTRUCTIONS
  batch_size = [CHECKPOINT_INTERVAL, TOTAL_INSTRUCTIONS - instructions_run].min

  # Run ISA (instruction-level)
  batch_size.times do
    break if isa_cpu.halted?
    isa_cpu.step
  end

  # Run IR (cycle-level) - scale by average cycles per instruction
  ir_cycles = batch_size * AVG_CYCLES_PER_INSTRUCTION
  ir_sim.run_cpu_cycles(ir_cycles, 0, false)

  instructions_run += batch_size

  # Checkpoint
  isa_pc = isa_cpu.pc
  ir_pc = ir_sim.peek('cpu__pc_reg')

  isa_hires = hires_checksum_isa(isa_bus)
  ir_hires = hires_checksum_ir(ir_sim)
  isa_text = text_checksum_isa(isa_bus)
  ir_text = text_checksum_ir(ir_sim)

  isa_a = isa_cpu.a
  isa_x = isa_cpu.x
  isa_y = isa_cpu.y

  ir_a = ir_sim.peek('cpu__a_reg')
  ir_x = ir_sim.peek('cpu__x_reg')
  ir_y = ir_sim.peek('cpu__y_reg')

  checkpoint = {
    instructions: instructions_run,
    isa_pc: isa_pc,
    ir_pc: ir_pc,
    pc_match: isa_pc == ir_pc,
    isa_regs: { a: isa_a, x: isa_x, y: isa_y },
    ir_regs: { a: ir_a, x: ir_x, y: ir_y },
    regs_match: isa_a == ir_a && isa_x == ir_x && isa_y == ir_y,
    isa_hires: isa_hires,
    ir_hires: ir_hires,
    hires_match: isa_hires == ir_hires,
    isa_text: isa_text,
    ir_text: ir_text,
    text_match: isa_text == ir_text
  }
  checkpoints << checkpoint

  if divergence_point.nil? && (!checkpoint[:hires_match] || !checkpoint[:text_match])
    divergence_point = checkpoint
  end

  elapsed = Time.now - start_time
  rate = instructions_run / elapsed / 1_000_000
  pct = (instructions_run.to_f / TOTAL_INSTRUCTIONS * 100).round(1)

  puts format("  %5.1f%% | %7.1fM instr | PC: ISA=%04X IR=%04X %s | HiRes: %s | Text: %s | %.2fM/s",
              pct,
              instructions_run / 1_000_000.0,
              isa_pc, ir_pc,
              isa_pc == ir_pc ? "=" : "≠",
              checkpoint[:hires_match] ? "match" : "DIFF",
              checkpoint[:text_match] ? "match" : "DIFF",
              rate)
end

elapsed = Time.now - start_time
puts "-" * 70
puts format("Completed in %.1f seconds (%.2fM instr/sec)", elapsed, TOTAL_INSTRUCTIONS / elapsed / 1_000_000)

puts "\n" + "=" * 70
puts "ANALYSIS"
puts "=" * 70

if divergence_point
  puts "\n🔴 DIVERGENCE DETECTED at #{divergence_point[:instructions].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} instructions"
  puts "   ISA PC: 0x#{divergence_point[:isa_pc].to_s(16).upcase}"
  puts "   IR  PC: 0x#{divergence_point[:ir_pc].to_s(16).upcase}"
  puts "   ISA Regs: A=#{divergence_point[:isa_regs][:a].to_s(16)} X=#{divergence_point[:isa_regs][:x].to_s(16)} Y=#{divergence_point[:isa_regs][:y].to_s(16)}"
  puts "   IR  Regs: A=#{divergence_point[:ir_regs][:a].to_s(16)} X=#{divergence_point[:ir_regs][:x].to_s(16)} Y=#{divergence_point[:ir_regs][:y].to_s(16)}"
  puts "   HiRes checksum: ISA=#{divergence_point[:isa_hires].to_s(16)} IR=#{divergence_point[:ir_hires].to_s(16)}"
  puts "   Text checksum:  ISA=#{divergence_point[:isa_text].to_s(16)} IR=#{divergence_point[:ir_text].to_s(16)}"
else
  puts "\n🟢 No screen divergence detected over #{TOTAL_INSTRUCTIONS.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} instructions"
end

puts "\nCheckpoint Summary:"
puts "  Instr     | PC Match | Regs Match | HiRes Match | Text Match"
puts "  " + "-" * 60
checkpoints.each do |cp|
  puts format("  %9s | %-8s | %-10s | %-11s | %-10s",
              "#{cp[:instructions] / 1_000_000.0}M",
              cp[:pc_match] ? "yes" : "NO",
              cp[:regs_match] ? "yes" : "NO",
              cp[:hires_match] ? "yes" : "NO",
              cp[:text_match] ? "yes" : "NO")
end
