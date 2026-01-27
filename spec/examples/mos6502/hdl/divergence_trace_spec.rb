# frozen_string_literal: true

# Test to find exactly where and why JIT diverges from ISA at ~2M cycles
# The JIT ends up at PC=$6200 (illegal opcode) while ISA continues normally

require 'spec_helper'
require 'rhdl'

RSpec.describe 'JIT Divergence Trace', :hdl do
  ROM_PATH = File.expand_path('../../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

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
    rom[0x2FFC] = 0x2A  # low byte of $B82A
    rom[0x2FFD] = 0xB8  # high byte of $B82A
    rom
  end

  def create_isa_simulator
    require_relative '../../../../examples/mos6502/utilities/apple2_bus'
    require_relative '../../../../examples/mos6502/utilities/isa_simulator_native'

    karateka_rom = create_karateka_rom
    bus = MOS6502::Apple2Bus.new
    bus.load_rom(karateka_rom, base_addr: 0xD000)
    bus.load_ram(@karateka_mem, base_addr: 0x0000)

    cpu = MOS6502::ISASimulatorNative.new(bus)
    cpu.load_bytes(@karateka_mem, 0x0000)
    cpu.load_bytes(karateka_rom, 0xD000)

    bus.instance_variable_set(:@native_cpu, cpu)
    bus.read(0xC050)  # TXTCLR
    bus.read(0xC052)  # MIXCLR
    bus.read(0xC054)  # PAGE1
    bus.read(0xC057)  # HIRES
    cpu.set_video_state(false, false, false, true)
    cpu.reset

    { cpu: cpu, bus: bus }
  end

  def create_jit_simulator
    require_relative '../../../../examples/mos6502/utilities/ir_simulator_runner'
    require_relative '../../../../examples/mos6502/utilities/apple2_bus'

    runner = IRSimulatorRunner.new(:jit)
    karateka_rom = create_karateka_rom

    runner.load_rom(karateka_rom, base_addr: 0xD000)
    runner.load_ram(@karateka_mem, base_addr: 0x0000)
    runner.set_reset_vector(0xB82A)
    runner.reset

    runner
  end

  # Compare memory checksums to detect divergence
  def hires_checksum(bus, base_addr)
    checksum = 0
    (base_addr..(base_addr + 0x1FFF)).each do |addr|
      checksum = (checksum + bus.read(addr)) & 0xFFFFFFFF
    end
    checksum
  end

  it 'finds exact divergence point between ISA and JIT' do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available

    isa = create_isa_simulator
    jit = create_jit_simulator

    puts "\n=== Tracing JIT Divergence ==="

    # Run in chunks to find approximate divergence point
    # Use "steps" which is instructions for ISA and cycles for JIT
    # The Rust run_mos6502_cycles actually runs instructions internally
    chunk_size = 50_000
    total_steps = 0
    max_steps = 2_500_000

    last_match_steps = 0
    last_match_isa_pc = nil
    last_match_jit_pc = nil

    while total_steps < max_steps
      # Save state before running
      isa_pc_before = isa[:cpu].pc
      jit_pc_before = jit.cpu_state[:pc]

      # Run chunk - both use "steps" but ISA runs instructions, JIT runs cycles
      # For JIT with Rust memory, run_mos6502_cycles may run instructions internally
      chunk_size.times do
        break if isa[:cpu].halted?
        isa[:cpu].step
      end
      jit.run_steps(chunk_size)
      total_steps += chunk_size

      isa_pc = isa[:cpu].pc
      jit_pc = jit.cpu_state[:pc]

      # Compare screen memory checksums instead of just PC
      # This is how karateka_divergence_spec detects real divergence
      isa_hires = hires_checksum(isa[:bus], 0x2000)
      jit_hires = hires_checksum(jit.bus, 0x2000)

      if isa_hires != jit_hires
        puts "\nDivergence detected between #{last_match_steps} and #{total_steps} steps!"
        puts "  Before: ISA PC=$#{isa_pc_before.to_s(16).upcase}, JIT PC=$#{jit_pc_before.to_s(16).upcase}"
        puts "  After:  ISA PC=$#{isa_pc.to_s(16).upcase}, JIT PC=$#{jit_pc.to_s(16).upcase}"
        puts "  HiRes checksum: ISA=$#{isa_hires.to_s(16).upcase}, JIT=$#{jit_hires.to_s(16).upcase}"

        # Reset and re-run to find exact point
        puts "\nResetting to find exact divergence cycle..."
        isa = create_isa_simulator
        jit = create_jit_simulator

        # Run to last known good checkpoint
        if last_match_steps > 0
          puts "Running to last match point (#{last_match_steps} cycles)..."
          last_match_steps.times do
            break if isa[:cpu].halted?
            isa[:cpu].step
          end
          jit.run_steps(last_match_steps)
        end

        # Now step cycle by cycle
        puts "Stepping cycle by cycle to find exact divergence..."
        step_count = 0
        max_steps = chunk_size + 10_000

        # Track last 10 instructions for context
        isa_history = []
        jit_history = []

        while step_count < max_steps
          # Get state before step
          isa_state_before = {
            pc: isa[:cpu].pc,
            a: isa[:cpu].a,
            x: isa[:cpu].x,
            y: isa[:cpu].y,
            sp: isa[:cpu].sp,
            p: isa[:cpu].p
          }
          jit_state_before = jit.cpu_state.dup

          # Get opcode at PC
          isa_opcode = isa[:bus].mem_read(isa_state_before[:pc])
          jit_opcode = jit.bus.read(jit_state_before[:pc])

          # Step one cycle
          isa[:cpu].step unless isa[:cpu].halted?
          jit.run_steps(1)
          step_count += 1

          # Get state after step
          isa_state_after = {
            pc: isa[:cpu].pc,
            a: isa[:cpu].a,
            x: isa[:cpu].x,
            y: isa[:cpu].y,
            sp: isa[:cpu].sp,
            p: isa[:cpu].p
          }
          jit_state_after = jit.cpu_state

          # Record history
          isa_history << { before: isa_state_before, after: isa_state_after, opcode: isa_opcode }
          jit_history << { before: jit_state_before, after: jit_state_after, opcode: jit_opcode }
          isa_history.shift if isa_history.size > 10
          jit_history.shift if jit_history.size > 10

          # Check for divergence
          if isa_state_after[:pc] != jit_state_after[:pc]
            actual_cycle = last_match_steps + step_count
            puts "\n" + "=" * 70
            puts "EXACT DIVERGENCE FOUND AT CYCLE #{actual_cycle}"
            puts "=" * 70

            puts "\n--- Last 5 matching instructions (ISA) ---"
            isa_history[0..-2].last(5).each_with_index do |h, i|
              puts "  #{decode_opcode(h[:opcode]).ljust(15)} PC=$#{h[:before][:pc].to_s(16).upcase} -> $#{h[:after][:pc].to_s(16).upcase}"
            end

            puts "\n--- Divergent instruction ---"
            isa_h = isa_history.last
            jit_h = jit_history.last

            puts "\nISA:"
            puts "  Before: PC=$#{isa_h[:before][:pc].to_s(16).upcase} A=$#{isa_h[:before][:a].to_s(16).upcase} X=$#{isa_h[:before][:x].to_s(16).upcase} Y=$#{isa_h[:before][:y].to_s(16).upcase} SP=$#{isa_h[:before][:sp].to_s(16).upcase} P=$#{isa_h[:before][:p].to_s(16).upcase}"
            puts "  Opcode: $#{isa_h[:opcode].to_s(16).upcase} (#{decode_opcode(isa_h[:opcode])})"
            puts "  After:  PC=$#{isa_h[:after][:pc].to_s(16).upcase} A=$#{isa_h[:after][:a].to_s(16).upcase} X=$#{isa_h[:after][:x].to_s(16).upcase} Y=$#{isa_h[:after][:y].to_s(16).upcase} SP=$#{isa_h[:after][:sp].to_s(16).upcase} P=$#{isa_h[:after][:p].to_s(16).upcase}"

            puts "\nJIT:"
            puts "  Before: PC=$#{jit_h[:before][:pc].to_s(16).upcase} A=$#{jit_h[:before][:a].to_s(16).upcase} X=$#{jit_h[:before][:x].to_s(16).upcase} Y=$#{jit_h[:before][:y].to_s(16).upcase} SP=$#{jit_h[:before][:sp].to_s(16).upcase} P=$#{jit_h[:before][:p].to_s(16).upcase}"
            puts "  Opcode: $#{jit_h[:opcode].to_s(16).upcase} (#{decode_opcode(jit_h[:opcode])})"
            puts "  After:  PC=$#{jit_h[:after][:pc].to_s(16).upcase} A=$#{jit_h[:after][:a].to_s(16).upcase} X=$#{jit_h[:after][:x].to_s(16).upcase} Y=$#{jit_h[:after][:y].to_s(16).upcase} SP=$#{jit_h[:after][:sp].to_s(16).upcase} P=$#{jit_h[:after][:p].to_s(16).upcase}"

            # Show memory around the PC
            pc = isa_h[:before][:pc]
            puts "\nMemory at PC $#{pc.to_s(16).upcase}:"
            bytes = (0..7).map { |i| isa[:bus].mem_read(pc + i) }
            puts "  " + bytes.map { |b| "$#{b.to_s(16).upcase.rjust(2, '0')}" }.join(" ")

            # Check if it's an indirect addressing mode
            if [0x6C, 0x01, 0x11, 0x21, 0x31, 0x41, 0x51, 0x61, 0x71, 0x81, 0x91, 0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1].include?(isa_h[:opcode])
              puts "\n(This is an indirect addressing mode instruction)"
              if isa_h[:opcode] == 0x6C
                # JMP indirect
                lo = isa[:bus].mem_read(pc + 1)
                hi = isa[:bus].mem_read(pc + 2)
                ptr = (hi << 8) | lo
                target_lo = isa[:bus].mem_read(ptr)
                target_hi = isa[:bus].mem_read(ptr + 1)
                target = (target_hi << 8) | target_lo
                puts "  JMP ($#{ptr.to_s(16).upcase}) -> $#{target.to_s(16).upcase}"
              end
            end

            puts "\n" + "=" * 70
            break
          end
        end
        break
      else
        last_match_steps = total_steps
        last_match_isa_pc = isa_pc
        last_match_jit_pc = jit_pc
        print "\r  #{total_steps / 1_000_000.0}M cycles - PC match at $#{isa_pc.to_s(16).upcase}    "
      end
    end

    puts "\n"
  end

  def decode_opcode(opcode)
    opcodes = {
      0x00 => "BRK", 0x01 => "ORA (zp,X)", 0x05 => "ORA zp", 0x06 => "ASL zp",
      0x08 => "PHP", 0x09 => "ORA #", 0x0A => "ASL A", 0x0D => "ORA abs",
      0x0E => "ASL abs", 0x10 => "BPL", 0x11 => "ORA (zp),Y", 0x15 => "ORA zp,X",
      0x16 => "ASL zp,X", 0x18 => "CLC", 0x19 => "ORA abs,Y", 0x1D => "ORA abs,X",
      0x1E => "ASL abs,X", 0x20 => "JSR", 0x21 => "AND (zp,X)", 0x24 => "BIT zp",
      0x25 => "AND zp", 0x26 => "ROL zp", 0x28 => "PLP", 0x29 => "AND #",
      0x2A => "ROL A", 0x2C => "BIT abs", 0x2D => "AND abs", 0x2E => "ROL abs",
      0x30 => "BMI", 0x31 => "AND (zp),Y", 0x35 => "AND zp,X", 0x36 => "ROL zp,X",
      0x38 => "SEC", 0x39 => "AND abs,Y", 0x3D => "AND abs,X", 0x3E => "ROL abs,X",
      0x40 => "RTI", 0x41 => "EOR (zp,X)", 0x45 => "EOR zp", 0x46 => "LSR zp",
      0x48 => "PHA", 0x49 => "EOR #", 0x4A => "LSR A", 0x4C => "JMP abs",
      0x4D => "EOR abs", 0x4E => "LSR abs", 0x50 => "BVC", 0x51 => "EOR (zp),Y",
      0x55 => "EOR zp,X", 0x56 => "LSR zp,X", 0x58 => "CLI", 0x59 => "EOR abs,Y",
      0x5D => "EOR abs,X", 0x5E => "LSR abs,X", 0x60 => "RTS", 0x61 => "ADC (zp,X)",
      0x65 => "ADC zp", 0x66 => "ROR zp", 0x68 => "PLA", 0x69 => "ADC #",
      0x6A => "ROR A", 0x6C => "JMP (ind)", 0x6D => "ADC abs", 0x6E => "ROR abs",
      0x70 => "BVS", 0x71 => "ADC (zp),Y", 0x75 => "ADC zp,X", 0x76 => "ROR zp,X",
      0x78 => "SEI", 0x79 => "ADC abs,Y", 0x7D => "ADC abs,X", 0x7E => "ROR abs,X",
      0x81 => "STA (zp,X)", 0x84 => "STY zp", 0x85 => "STA zp", 0x86 => "STX zp",
      0x88 => "DEY", 0x8A => "TXA", 0x8C => "STY abs", 0x8D => "STA abs",
      0x8E => "STX abs", 0x90 => "BCC", 0x91 => "STA (zp),Y", 0x94 => "STY zp,X",
      0x95 => "STA zp,X", 0x96 => "STX zp,Y", 0x98 => "TYA", 0x99 => "STA abs,Y",
      0x9A => "TXS", 0x9D => "STA abs,X", 0xA0 => "LDY #", 0xA1 => "LDA (zp,X)",
      0xA2 => "LDX #", 0xA4 => "LDY zp", 0xA5 => "LDA zp", 0xA6 => "LDX zp",
      0xA8 => "TAY", 0xA9 => "LDA #", 0xAA => "TAX", 0xAC => "LDY abs",
      0xAD => "LDA abs", 0xAE => "LDX abs", 0xB0 => "BCS", 0xB1 => "LDA (zp),Y",
      0xB4 => "LDY zp,X", 0xB5 => "LDA zp,X", 0xB6 => "LDX zp,Y", 0xB8 => "CLV",
      0xB9 => "LDA abs,Y", 0xBA => "TSX", 0xBC => "LDY abs,X", 0xBD => "LDA abs,X",
      0xBE => "LDX abs,Y", 0xC0 => "CPY #", 0xC1 => "CMP (zp,X)", 0xC4 => "CPY zp",
      0xC5 => "CMP zp", 0xC6 => "DEC zp", 0xC8 => "INY", 0xC9 => "CMP #",
      0xCA => "DEX", 0xCC => "CPY abs", 0xCD => "CMP abs", 0xCE => "DEC abs",
      0xD0 => "BNE", 0xD1 => "CMP (zp),Y", 0xD5 => "CMP zp,X", 0xD6 => "DEC zp,X",
      0xD8 => "CLD", 0xD9 => "CMP abs,Y", 0xDD => "CMP abs,X", 0xDE => "DEC abs,X",
      0xE0 => "CPX #", 0xE1 => "SBC (zp,X)", 0xE4 => "CPX zp", 0xE5 => "SBC zp",
      0xE6 => "INC zp", 0xE8 => "INX", 0xE9 => "SBC #", 0xEA => "NOP",
      0xEC => "CPX abs", 0xED => "SBC abs", 0xEE => "INC abs", 0xF0 => "BEQ",
      0xF1 => "SBC (zp),Y", 0xF5 => "SBC zp,X", 0xF6 => "INC zp,X", 0xF8 => "SED",
      0xF9 => "SBC abs,Y", 0xFD => "SBC abs,X", 0xFE => "INC abs,X"
    }
    opcodes[opcode] || "??? ($#{opcode.to_s(16).upcase})"
  end
end
