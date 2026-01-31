# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

# Focused test to find the exact point of divergence at ~9.6M cycles
# Both JIT and Compiler diverge at the same point, suggesting a bug in shared MOS6502 extension code
RSpec.describe 'MOS6502 IR Divergence at 9.6M cycles' do
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

  def hires_checksum_isa(bus)
    checksum = 0
    (0x2000..0x3FFF).each { |a| checksum = (checksum + bus.mem_read(a)) & 0xFFFFFFFF }
    checksum
  end

  def hires_checksum_ir(runner)
    checksum = 0
    # Sync screen memory from Rust to Ruby bus
    runner.send(:sync_screen_memory_from_rust) if runner.instance_variable_get(:@use_rust_memory)
    (0x2000..0x3FFF).each { |a| checksum = (checksum + runner.bus.mem_read(a)) & 0xFFFFFFFF }
    checksum
  end

  def zp_checksum_isa(bus)
    checksum = 0
    (0x00..0xFF).each { |a| checksum = (checksum + bus.mem_read(a)) & 0xFFFFFFFF }
    checksum
  end

  def zp_checksum_ir(runner)
    checksum = 0
    (0x00..0xFF).each { |a| checksum = (checksum + runner.sim.mos6502_read_memory(a)) & 0xFFFFFFFF }
    checksum
  end

  def stack_bytes_isa(bus, sp)
    bytes = []
    (sp + 1).upto(0xFF) { |i| bytes << bus.mem_read(0x100 + i) }
    bytes
  end

  def stack_bytes_ir(runner, sp)
    bytes = []
    (sp + 1).upto(0xFF) { |i| bytes << runner.sim.mos6502_read_memory(0x100 + i) }
    bytes
  end

  def read_ram_ir(runner, addr, len)
    (0...len).map { |i| runner.sim.mos6502_read_memory(addr + i) }
  end

  it 'finds exact divergence point with binary search', timeout: 600 do
    skip 'ROM not found' unless @rom_available
    skip 'Karateka memory not found' unless @karateka_available
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    puts "\n" + "=" * 80
    puts "Finding exact divergence point (binary search)"
    puts "=" * 80

    # Known bounds: passes at 9M, fails at 10M, diverges around 9.6M
    low = 9_000_000
    high = 10_000_000

    # Binary search to find exact divergence cycle
    while high - low > 1000
      mid = (low + high) / 2
      mid = (mid / 1000) * 1000  # Round to 1K boundary

      puts "\nTesting #{mid} cycles (range: #{low}-#{high})..."

      isa = create_isa_simulator
      ir = create_ir_simulator(:compile)

      # Run to mid point
      isa[:cpu].run_cycles(mid)
      ir.run_steps(mid)

      isa_hires = hires_checksum_isa(isa[:bus])
      ir_hires = hires_checksum_ir(ir)

      if isa_hires == ir_hires
        puts "  MATCH at #{mid} cycles"
        low = mid
      else
        puts "  DIVERGED at #{mid} cycles"
        puts "    ISA HiRes: 0x#{isa_hires.to_s(16)}"
        puts "    IR HiRes:  0x#{ir_hires.to_s(16)}"
        high = mid
      end
    end

    puts "\n" + "-" * 80
    puts "Divergence occurs between #{low} and #{high} cycles"
    puts "-" * 80

    # Now do fine-grained search in 100-cycle increments
    puts "\nFine-grained search (100-cycle increments)..."

    isa = create_isa_simulator
    ir = create_ir_simulator(:compile)

    # Run to low point first
    isa[:cpu].run_cycles(low)
    ir.run_steps(low)

    cycles = low
    divergence_cycle = nil

    while cycles < high
      # Run 100 cycles
      isa[:cpu].run_cycles(100)
      ir.run_steps(100)
      cycles += 100

      isa_hires = hires_checksum_isa(isa[:bus])
      ir_hires = hires_checksum_ir(ir)

      if isa_hires != ir_hires
        divergence_cycle = cycles
        puts "  DIVERGED at exactly #{cycles} cycles!"
        break
      end
    end

    expect(divergence_cycle).not_to be_nil

    puts "\n" + "=" * 80
    puts "DIVERGENCE FOUND AT #{divergence_cycle} CYCLES"
    puts "=" * 80

    # Now capture detailed state at divergence
    puts "\nCapturing detailed state..."

    # Get CPU state
    isa_cpu = isa[:cpu]
    isa_state = { pc: isa_cpu.pc, a: isa_cpu.a, x: isa_cpu.x, y: isa_cpu.y, sp: isa_cpu.sp, p: isa_cpu.p }
    ir_state = ir.cpu_state

    puts "\nCPU State comparison:"
    puts "  ISA: PC=$#{isa_state[:pc].to_s(16).upcase.rjust(4,'0')} A=$#{isa_state[:a].to_s(16).upcase.rjust(2,'0')} X=$#{isa_state[:x].to_s(16).upcase.rjust(2,'0')} Y=$#{isa_state[:y].to_s(16).upcase.rjust(2,'0')} SP=$#{isa_state[:sp].to_s(16).upcase.rjust(2,'0')} P=$#{isa_state[:p].to_s(16).upcase.rjust(2,'0')}"
    puts "  IR:  PC=$#{ir_state[:pc].to_s(16).upcase.rjust(4,'0')} A=$#{ir_state[:a].to_s(16).upcase.rjust(2,'0')} X=$#{ir_state[:x].to_s(16).upcase.rjust(2,'0')} Y=$#{ir_state[:y].to_s(16).upcase.rjust(2,'0')} SP=$#{ir_state[:sp].to_s(16).upcase.rjust(2,'0')} P=$#{ir_state[:p].to_s(16).upcase.rjust(2,'0')}"

    # Check ZP checksums
    isa_zp = zp_checksum_isa(isa[:bus])
    ir_zp = zp_checksum_ir(ir)
    puts "\nZero page checksum:"
    puts "  ISA: 0x#{isa_zp.to_s(16)}"
    puts "  IR:  0x#{ir_zp.to_s(16)}"
    puts "  Match: #{isa_zp == ir_zp}"

    # Check stack
    isa_stack = stack_bytes_isa(isa[:bus], isa_state[:sp])
    ir_stack = stack_bytes_ir(ir, ir_state[:sp])
    puts "\nStack (#{isa_stack.length} / #{ir_stack.length} bytes):"
    puts "  ISA SP=$#{isa_state[:sp].to_s(16).upcase.rjust(2,'0')}: #{isa_stack.first(8).map{|b| b.to_s(16).rjust(2,'0')}.join(' ')}"
    puts "  IR  SP=$#{ir_state[:sp].to_s(16).upcase.rjust(2,'0')}: #{ir_stack.first(8).map{|b| b.to_s(16).rjust(2,'0')}.join(' ')}"

    # Read opcode at each PC
    isa_opcode = isa[:bus].mem_read(isa_state[:pc])
    ir_ram = read_ram_ir(ir, ir_state[:pc], 3)
    ir_opcode = ir_ram[0]

    puts "\nOpcode at PC:"
    puts "  ISA @ $#{isa_state[:pc].to_s(16).upcase}: $#{isa_opcode.to_s(16).upcase.rjust(2,'0')}"
    puts "  IR  @ $#{ir_state[:pc].to_s(16).upcase}: $#{ir_opcode.to_s(16).upcase.rjust(2,'0')}"
  end

  it 'traces instructions leading up to divergence', timeout: 600 do
    skip 'ROM not found' unless @rom_available
    skip 'Karateka memory not found' unless @karateka_available
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    # Run to just before divergence and trace
    divergence_cycle = 9_550_000  # Approximate from binary search

    puts "\n" + "=" * 80
    puts "Tracing instructions around divergence point"
    puts "=" * 80

    isa = create_isa_simulator
    ir = create_ir_simulator(:compile)

    # Run to just before divergence
    warmup = divergence_cycle - 10_000
    puts "\nWarming up to #{warmup} cycles..."
    isa[:cpu].run_cycles(warmup)
    ir.run_steps(warmup)

    # Verify still in sync
    isa_hires = hires_checksum_isa(isa[:bus])
    ir_hires = hires_checksum_ir(ir)
    isa_pc = isa[:cpu].pc
    ir_pc = ir.cpu_state[:pc]
    puts "After warmup: ISA HiRes=0x#{isa_hires.to_s(16)} IR HiRes=0x#{ir_hires.to_s(16)} Match=#{isa_hires == ir_hires}"
    puts "After warmup: ISA PC=$#{isa_pc.to_s(16).upcase.rjust(4,'0')} IR PC=$#{ir_pc.to_s(16).upcase.rjust(4,'0')} Match=#{isa_pc == ir_pc}"

    if isa_pc != ir_pc
      puts "  => PC already diverged during warmup!"
    end

    if isa_hires != ir_hires
      puts "Already diverged! Need earlier warmup point."
      return
    end

    # Now trace cycle by cycle looking for first difference
    puts "\nTracing cycle by cycle looking for divergence..."

    cycles = warmup
    trace_log = []
    last_match_cycle = cycles

    10_000.times do |i|
      # Capture state before step
      isa_pc_before = isa[:cpu].pc
      ir_state_before = ir.cpu_state
      ir_pc_before = ir_state_before[:pc]

      # Step both
      isa[:cpu].step
      ir.run_steps(1)
      cycles += 1

      # Capture state after step
      isa_pc = isa[:cpu].pc
      ir_state_after = ir.cpu_state
      ir_pc = ir_state_after[:pc]

      # Check for PC divergence
      if isa_pc != ir_pc
        puts "\n  PC DIVERGENCE at cycle #{cycles}!"
        puts "    Before: ISA=$#{isa_pc_before.to_s(16).upcase.rjust(4,'0')} IR=$#{ir_pc_before.to_s(16).upcase.rjust(4,'0')}"
        puts "    After:  ISA=$#{isa_pc.to_s(16).upcase.rjust(4,'0')} IR=$#{ir_pc.to_s(16).upcase.rjust(4,'0')}"

        # Get opcode that was executed
        opcode = isa[:bus].mem_read(isa_pc_before)
        puts "    Opcode executed: $#{opcode.to_s(16).upcase.rjust(2,'0')}"

        # Show CPU state
        isa_cpu = isa[:cpu]
        isa_state = { a: isa_cpu.a, x: isa_cpu.x, y: isa_cpu.y, sp: isa_cpu.sp, p: isa_cpu.p }
        puts "    ISA state: A=$#{isa_state[:a].to_s(16).rjust(2,'0')} X=$#{isa_state[:x].to_s(16).rjust(2,'0')} Y=$#{isa_state[:y].to_s(16).rjust(2,'0')} SP=$#{isa_state[:sp].to_s(16).rjust(2,'0')} P=$#{isa_state[:p].to_s(16).rjust(2,'0')}"
        puts "    IR state:  A=$#{ir_state_after[:a].to_s(16).rjust(2,'0')} X=$#{ir_state_after[:x].to_s(16).rjust(2,'0')} Y=$#{ir_state_after[:y].to_s(16).rjust(2,'0')} SP=$#{ir_state_after[:sp].to_s(16).rjust(2,'0')} P=$#{ir_state_after[:p].to_s(16).rjust(2,'0')}"

        # Show last 20 trace entries
        puts "\n  Last 20 instructions before divergence:"
        trace_log.last(20).each do |entry|
          puts "    #{entry}"
        end

        break
      end

      # Log this instruction
      opcode = isa[:bus].mem_read(isa_pc_before)
      trace_log << "cycle=#{cycles} PC=$#{isa_pc_before.to_s(16).upcase.rjust(4,'0')} op=$#{opcode.to_s(16).upcase.rjust(2,'0')} -> PC=$#{isa_pc.to_s(16).upcase.rjust(4,'0')}"

      # Keep trace log bounded
      trace_log.shift if trace_log.length > 100

      # Check HiRes every 1000 cycles
      if cycles % 1000 == 0
        isa_hires = hires_checksum_isa(isa[:bus])
        ir_hires = hires_checksum_ir(ir)
        if isa_hires != ir_hires
          puts "\n  HiRes DIVERGENCE at cycle #{cycles}!"
          puts "    ISA HiRes: 0x#{isa_hires.to_s(16)}"
          puts "    IR HiRes:  0x#{ir_hires.to_s(16)}"
          puts "    Last matched at cycle #{last_match_cycle}"
          break
        end
        last_match_cycle = cycles
      end

      # Progress every 2000 cycles
      if cycles % 2000 == 0
        print "."
        $stdout.flush
      end
    end

    puts "\n"
  end

  it 'compares memory regions at divergence', timeout: 300 do
    skip 'ROM not found' unless @rom_available
    skip 'Karateka memory not found' unless @karateka_available
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE

    puts "\n" + "=" * 80
    puts "Comparing memory regions at divergence point"
    puts "=" * 80

    # Run to just before known divergence
    target = 9_500_000

    isa = create_isa_simulator
    ir = create_ir_simulator(:compile)

    puts "\nRunning to #{target} cycles..."
    isa[:cpu].run_cycles(target)
    ir.run_steps(target)

    # Compare memory regions
    regions = [
      { name: "Zero Page", start: 0x0000, size: 0x100 },
      { name: "Stack", start: 0x0100, size: 0x100 },
      { name: "Text Page 1", start: 0x0400, size: 0x400 },
      { name: "HiRes Page 1", start: 0x2000, size: 0x2000 },
      { name: "HiRes Page 2", start: 0x4000, size: 0x2000 },
      { name: "Game RAM", start: 0x6000, size: 0x2000 },
      { name: "High RAM", start: 0x8000, size: 0x4000 },
    ]

    puts "\nMemory region comparison:"
    regions.each do |region|
      isa_data = []
      (region[:start]...(region[:start] + region[:size])).each do |addr|
        isa_data << isa[:bus].mem_read(addr)
      end

      ir_data = read_ram_ir(ir, region[:start], region[:size])

      differences = 0
      first_diff = nil
      isa_data.each_with_index do |b, i|
        if b != ir_data[i]
          differences += 1
          first_diff ||= { addr: region[:start] + i, isa: b, ir: ir_data[i] }
        end
      end

      status = differences == 0 ? "MATCH" : "#{differences} differences"
      puts "  #{region[:name].ljust(15)}: #{status}"
      if first_diff
        puts "    First diff at $#{first_diff[:addr].to_s(16).upcase}: ISA=$#{first_diff[:isa].to_s(16).upcase.rjust(2,'0')} IR=$#{first_diff[:ir].to_s(16).upcase.rjust(2,'0')}"
      end
    end
  end
end
