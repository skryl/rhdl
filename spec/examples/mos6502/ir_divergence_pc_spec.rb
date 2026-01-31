# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

# Find exact PC divergence point
RSpec.describe 'MOS6502 PC Divergence' do
  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  before(:all) do
    @rom_available = File.exist?(ROM_PATH)
    @karateka_available = File.exist?(KARATEKA_MEM_PATH)
    if @rom_available
      @rom_data = File.binread(ROM_PATH).bytes
    end
    if @karateka_available
      @karateka_mem = File.binread(KARATEKA_MEM_PATH).bytes
    end
  end

  def create_karateka_rom
    rom = @rom_data.dup
    rom[0x2FFC] = 0x2A
    rom[0x2FFD] = 0xB8
    rom
  end

  def create_isa_simulator
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'
    require_relative '../../../examples/mos6502/utilities/apple2_bus'

    rom = create_karateka_rom
    bus = MOS6502::Apple2Bus.new
    bus.load_rom(rom, base_addr: 0xD000)
    bus.load_ram(@karateka_mem, base_addr: 0x0000)

    cpu = MOS6502::ISASimulatorNative.new(bus)
    cpu.load_bytes(@karateka_mem, 0x0000)
    cpu.load_bytes(rom, 0xD000)
    bus.read(0xC050); bus.read(0xC052); bus.read(0xC054); bus.read(0xC057)
    cpu.set_video_state(false, false, false, true)
    cpu.reset

    { cpu: cpu, bus: bus }
  end

  def create_ir_simulator(backend)
    require_relative '../../../examples/mos6502/utilities/ir_simulator_runner'

    runner = IRSimulatorRunner.new(backend)
    rom = create_karateka_rom
    runner.load_rom(rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)
    runner.reset
    runner
  end

  it 'finds exact PC divergence with binary search', timeout: 600 do
    skip 'ROM not found' unless @rom_available
    skip 'Karateka memory not found' unless @karateka_available
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    puts "\n" + "=" * 80
    puts "Finding exact PC divergence point"
    puts "=" * 80

    # We know PC diverges around 9.5M cycles
    low = 0
    high = 9_600_000

    # Binary search
    while high - low > 10_000
      mid = (low + high) / 2
      mid = (mid / 1000) * 1000

      puts "\nTesting #{mid} cycles..."

      isa = create_isa_simulator
      ir = create_ir_simulator(:compile)

      isa[:cpu].run_cycles(mid)
      ir.run_steps(mid)

      isa_pc = isa[:cpu].pc
      ir_pc = ir.cpu_state[:pc]

      if isa_pc == ir_pc
        puts "  MATCH: PC=$#{isa_pc.to_s(16).upcase.rjust(4,'0')}"
        low = mid
      else
        puts "  DIVERGED: ISA=$#{isa_pc.to_s(16).upcase.rjust(4,'0')} IR=$#{ir_pc.to_s(16).upcase.rjust(4,'0')}"
        high = mid
      end
    end

    puts "\n" + "-" * 80
    puts "PC divergence between #{low} and #{high} cycles"
    puts "-" * 80

    # Fine search in 100-cycle increments
    puts "\nFine search..."
    isa = create_isa_simulator
    ir = create_ir_simulator(:compile)

    isa[:cpu].run_cycles(low)
    ir.run_steps(low)

    cycles = low
    diverged_at = nil

    while cycles < high
      isa[:cpu].run_cycles(100)
      ir.run_steps(100)
      cycles += 100

      isa_pc = isa[:cpu].pc
      ir_pc = ir.cpu_state[:pc]

      if isa_pc != ir_pc
        diverged_at = cycles
        puts "  DIVERGED at #{cycles}: ISA=$#{isa_pc.to_s(16).upcase} IR=$#{ir_pc.to_s(16).upcase}"
        break
      end
    end

    expect(diverged_at).not_to be_nil

    # Now trace single steps to find exact instruction
    puts "\n" + "=" * 80
    puts "Tracing single instructions starting from #{diverged_at - 100}"
    puts "=" * 80

    isa = create_isa_simulator
    ir = create_ir_simulator(:compile)

    warmup = diverged_at - 100
    isa[:cpu].run_cycles(warmup)
    ir.run_steps(warmup)

    puts "\nAfter warmup to #{warmup}:"
    puts "  ISA PC=$#{isa[:cpu].pc.to_s(16).upcase} IR PC=$#{ir.cpu_state[:pc].to_s(16).upcase}"

    if isa[:cpu].pc != ir.cpu_state[:pc]
      puts "  Already diverged! Going back further..."

      # Find a point where they match
      (1..10).each do |i|
        test_point = warmup - i * 100
        isa2 = create_isa_simulator
        ir2 = create_ir_simulator(:compile)
        isa2[:cpu].run_cycles(test_point)
        ir2.run_steps(test_point)

        if isa2[:cpu].pc == ir2.cpu_state[:pc]
          puts "  Found match at #{test_point}"
          warmup = test_point
          isa = isa2
          ir = ir2
          break
        end
      end
    end

    cycles = warmup
    trace = []

    100.times do
      isa_pc_before = isa[:cpu].pc
      ir_pc_before = ir.cpu_state[:pc]

      # Get opcode
      opcode = isa[:bus].mem_read(isa_pc_before)

      # Step both
      isa[:cpu].step
      ir.run_steps(1)
      cycles += 1

      isa_pc_after = isa[:cpu].pc
      ir_pc_after = ir.cpu_state[:pc]

      # Log
      entry = {
        cycle: cycles,
        isa_before: isa_pc_before,
        ir_before: ir_pc_before,
        opcode: opcode,
        isa_after: isa_pc_after,
        ir_after: ir_pc_after
      }
      trace << entry

      if isa_pc_after != ir_pc_after
        puts "\n  PC DIVERGED at cycle #{cycles}!"
        puts "  Before: ISA=$#{isa_pc_before.to_s(16).upcase.rjust(4,'0')} IR=$#{ir_pc_before.to_s(16).upcase.rjust(4,'0')}"
        puts "  Opcode: $#{opcode.to_s(16).upcase.rjust(2,'0')} (#{opcode_name(opcode)})"
        puts "  After:  ISA=$#{isa_pc_after.to_s(16).upcase.rjust(4,'0')} IR=$#{ir_pc_after.to_s(16).upcase.rjust(4,'0')}"

        # Show registers
        isa_cpu = isa[:cpu]
        ir_state = ir.cpu_state
        puts "\n  Registers after:"
        puts "    ISA: A=$#{isa_cpu.a.to_s(16).rjust(2,'0')} X=$#{isa_cpu.x.to_s(16).rjust(2,'0')} Y=$#{isa_cpu.y.to_s(16).rjust(2,'0')} SP=$#{isa_cpu.sp.to_s(16).rjust(2,'0')} P=$#{isa_cpu.p.to_s(16).rjust(2,'0')}"
        puts "    IR:  A=$#{ir_state[:a].to_s(16).rjust(2,'0')} X=$#{ir_state[:x].to_s(16).rjust(2,'0')} Y=$#{ir_state[:y].to_s(16).rjust(2,'0')} SP=$#{ir_state[:sp].to_s(16).rjust(2,'0')} P=$#{ir_state[:p].to_s(16).rjust(2,'0')}"

        # Show memory around PCs
        puts "\n  Memory around ISA PC ($#{isa_pc_before.to_s(16).upcase}):"
        (-4..4).each do |offset|
          addr = isa_pc_before + offset
          byte = isa[:bus].mem_read(addr)
          marker = offset == 0 ? " <--" : ""
          puts "    $#{addr.to_s(16).upcase.rjust(4,'0')}: $#{byte.to_s(16).upcase.rjust(2,'0')}#{marker}"
        end

        # Show trace leading up to divergence
        puts "\n  Last 10 instructions:"
        trace.last(10).each do |e|
          puts "    cycle=#{e[:cycle]} ISA:$#{e[:isa_before].to_s(16).upcase.rjust(4,'0')}->$#{e[:isa_after].to_s(16).upcase.rjust(4,'0')} IR:$#{e[:ir_before].to_s(16).upcase.rjust(4,'0')}->$#{e[:ir_after].to_s(16).upcase.rjust(4,'0')} op=$#{e[:opcode].to_s(16).upcase.rjust(2,'0')}(#{opcode_name(e[:opcode])})"
        end

        break
      end
    end
  end

  def opcode_name(op)
    names = {
      0x00 => 'BRK', 0x01 => 'ORA izx', 0x05 => 'ORA zp', 0x06 => 'ASL zp',
      0x08 => 'PHP', 0x09 => 'ORA imm', 0x0A => 'ASL A', 0x0D => 'ORA abs',
      0x0E => 'ASL abs', 0x10 => 'BPL', 0x11 => 'ORA izy', 0x15 => 'ORA zpx',
      0x16 => 'ASL zpx', 0x18 => 'CLC', 0x19 => 'ORA aby', 0x1D => 'ORA abx',
      0x1E => 'ASL abx', 0x20 => 'JSR', 0x21 => 'AND izx', 0x24 => 'BIT zp',
      0x25 => 'AND zp', 0x26 => 'ROL zp', 0x28 => 'PLP', 0x29 => 'AND imm',
      0x2A => 'ROL A', 0x2C => 'BIT abs', 0x2D => 'AND abs', 0x2E => 'ROL abs',
      0x30 => 'BMI', 0x31 => 'AND izy', 0x35 => 'AND zpx', 0x36 => 'ROL zpx',
      0x38 => 'SEC', 0x39 => 'AND aby', 0x3D => 'AND abx', 0x3E => 'ROL abx',
      0x40 => 'RTI', 0x41 => 'EOR izx', 0x45 => 'EOR zp', 0x46 => 'LSR zp',
      0x48 => 'PHA', 0x49 => 'EOR imm', 0x4A => 'LSR A', 0x4C => 'JMP abs',
      0x4D => 'EOR abs', 0x4E => 'LSR abs', 0x50 => 'BVC', 0x51 => 'EOR izy',
      0x55 => 'EOR zpx', 0x56 => 'LSR zpx', 0x58 => 'CLI', 0x59 => 'EOR aby',
      0x5D => 'EOR abx', 0x5E => 'LSR abx', 0x60 => 'RTS', 0x61 => 'ADC izx',
      0x65 => 'ADC zp', 0x66 => 'ROR zp', 0x68 => 'PLA', 0x69 => 'ADC imm',
      0x6A => 'ROR A', 0x6C => 'JMP ind', 0x6D => 'ADC abs', 0x6E => 'ROR abs',
      0x70 => 'BVS', 0x71 => 'ADC izy', 0x75 => 'ADC zpx', 0x76 => 'ROR zpx',
      0x78 => 'SEI', 0x79 => 'ADC aby', 0x7D => 'ADC abx', 0x7E => 'ROR abx',
      0x81 => 'STA izx', 0x84 => 'STY zp', 0x85 => 'STA zp', 0x86 => 'STX zp',
      0x88 => 'DEY', 0x8A => 'TXA', 0x8C => 'STY abs', 0x8D => 'STA abs',
      0x8E => 'STX abs', 0x90 => 'BCC', 0x91 => 'STA izy', 0x94 => 'STY zpx',
      0x95 => 'STA zpx', 0x96 => 'STX zpy', 0x98 => 'TYA', 0x99 => 'STA aby',
      0x9A => 'TXS', 0x9D => 'STA abx', 0xA0 => 'LDY imm', 0xA1 => 'LDA izx',
      0xA2 => 'LDX imm', 0xA4 => 'LDY zp', 0xA5 => 'LDA zp', 0xA6 => 'LDX zp',
      0xA8 => 'TAY', 0xA9 => 'LDA imm', 0xAA => 'TAX', 0xAC => 'LDY abs',
      0xAD => 'LDA abs', 0xAE => 'LDX abs', 0xB0 => 'BCS', 0xB1 => 'LDA izy',
      0xB4 => 'LDY zpx', 0xB5 => 'LDA zpx', 0xB6 => 'LDX zpy', 0xB8 => 'CLV',
      0xB9 => 'LDA aby', 0xBA => 'TSX', 0xBC => 'LDY abx', 0xBD => 'LDA abx',
      0xBE => 'LDX aby', 0xC0 => 'CPY imm', 0xC1 => 'CMP izx', 0xC4 => 'CPY zp',
      0xC5 => 'CMP zp', 0xC6 => 'DEC zp', 0xC8 => 'INY', 0xC9 => 'CMP imm',
      0xCA => 'DEX', 0xCC => 'CPY abs', 0xCD => 'CMP abs', 0xCE => 'DEC abs',
      0xD0 => 'BNE', 0xD1 => 'CMP izy', 0xD5 => 'CMP zpx', 0xD6 => 'DEC zpx',
      0xD8 => 'CLD', 0xD9 => 'CMP aby', 0xDD => 'CMP abx', 0xDE => 'DEC abx',
      0xE0 => 'CPX imm', 0xE1 => 'SBC izx', 0xE4 => 'CPX zp', 0xE5 => 'SBC zp',
      0xE6 => 'INC zp', 0xE8 => 'INX', 0xE9 => 'SBC imm', 0xEA => 'NOP',
      0xEC => 'CPX abs', 0xED => 'SBC abs', 0xEE => 'INC abs', 0xF0 => 'BEQ',
      0xF1 => 'SBC izy', 0xF5 => 'SBC zpx', 0xF6 => 'INC zpx', 0xF8 => 'SED',
      0xF9 => 'SBC aby', 0xFD => 'SBC abx', 0xFE => 'INC abx'
    }
    names[op] || "???"
  end
end
