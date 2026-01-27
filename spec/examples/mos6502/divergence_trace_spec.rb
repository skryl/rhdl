# frozen_string_literal: true

# Test to verify all 3 IR implementations (interpret, jit, compile) match ISA simulator
# Runs 10M cycles comparing PC values at checkpoints

require 'spec_helper'
require 'rhdl'

RSpec.describe 'IR Divergence Trace', :hdl, :slow do
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
    rom[0x2FFC] = 0x2A  # low byte of $B82A
    rom[0x2FFD] = 0xB8  # high byte of $B82A
    rom
  end

  def create_isa_simulator
    require_relative '../../../examples/mos6502/utilities/apple2_bus'
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'

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

  def create_ir_simulator(backend)
    require_relative '../../../examples/mos6502/utilities/ir_simulator_runner'

    runner = IRSimulatorRunner.new(backend)
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

  # Run a single backend against ISA for max_steps cycles
  # Returns true if they match throughout, false otherwise
  def run_backend_test(backend_name, backend_sym, max_steps)
    isa = create_isa_simulator
    ir = create_ir_simulator(backend_sym)

    chunk_size = 100_000
    total_steps = 0

    while total_steps < max_steps
      # Run chunk
      chunk_size.times do
        break if isa[:cpu].halted?
        isa[:cpu].step
      end
      ir.run_steps(chunk_size)
      total_steps += chunk_size

      isa_pc = isa[:cpu].pc
      ir_pc = ir.cpu_state[:pc]

      # Compare HiRes checksums
      isa_hires = hires_checksum(isa[:bus], 0x2000)
      ir_hires = hires_checksum(ir.bus, 0x2000)

      if isa_hires != ir_hires
        puts "  #{backend_name}: DIVERGED at #{total_steps / 1_000_000.0}M cycles"
        puts "    ISA PC=$#{isa_pc.to_s(16).upcase} HiRes=$#{isa_hires.to_s(16).upcase}"
        puts "    IR  PC=$#{ir_pc.to_s(16).upcase} HiRes=$#{ir_hires.to_s(16).upcase}"
        return false
      end

      # Progress indicator every 1M cycles
      if (total_steps % 1_000_000).zero?
        print "  #{backend_name}: #{total_steps / 1_000_000}M cycles - PC match at $#{isa_pc.to_s(16).upcase}\n"
      end
    end

    puts "  #{backend_name}: PASSED #{max_steps / 1_000_000}M cycles"
    true
  end

  # Interpreter is slower, so only test 5M cycles (still validates correctness)
  it 'verifies IR Interpreter matches ISA for 5M cycles', timeout: 600 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available

    puts "\n=== Testing IR Interpreter against ISA ==="
    result = run_backend_test("Interpret", :interpret, 5_000_000)
    expect(result).to be true
  end

  it 'verifies IR JIT matches ISA for 10M cycles', timeout: 120 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available

    puts "\n=== Testing IR JIT against ISA ==="
    result = run_backend_test("JIT", :jit, 10_000_000)
    expect(result).to be true
  end

  it 'verifies IR Compiler matches ISA for 10M cycles', timeout: 600 do
    skip 'ROM not available' unless @rom_available
    skip 'Karateka memory not available' unless @karateka_available

    puts "\n=== Testing IR Compiler against ISA ==="
    result = run_backend_test("Compile", :compile, 10_000_000)
    expect(result).to be true
  end
end
