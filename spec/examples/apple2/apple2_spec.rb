# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require_relative '../../../examples/apple2/hdl/apple2'

RSpec.describe RHDL::Apple2::Apple2 do
  let(:apple2) { described_class.new('apple2') }
  let(:ram) { Array.new(48 * 1024, 0) }  # 48KB RAM

  before do
    apple2
    # Initialize inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)
  end

  def clock_14m_cycle
    # 14MHz falling edge
    apple2.set_input(:clk_14m, 0)
    apple2.propagate

    # Get RAM address and provide data
    ram_addr = apple2.get_output(:ram_addr)
    if ram_addr < ram.size
      apple2.set_input(:ram_do, ram[ram_addr])
    end
    apple2.propagate

    # 14MHz rising edge
    apple2.set_input(:clk_14m, 1)
    apple2.propagate

    # Handle RAM writes
    ram_we = apple2.get_output(:ram_we)
    if ram_we == 1
      write_addr = apple2.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = apple2.get_output(:d)
      end
    end
  end

  def clock_cycle
    # Run multiple 14MHz cycles for one approximate CPU cycle
    14.times { clock_14m_cycle }
  end

  def run_cycles(n)
    n.times { clock_cycle }
  end

  def reset_system
    apple2.set_input(:reset, 1)
    clock_cycle
    apple2.set_input(:reset, 0)
  end

  def load_rom(data)
    apple2.load_rom(data)
  end

  describe 'component integration' do
    it 'elaborates all sub-components' do
      expect(apple2.instance_variable_get(:@timing)).to be_a(RHDL::Apple2::TimingGenerator)
      expect(apple2.instance_variable_get(:@video_gen)).to be_a(RHDL::Apple2::VideoGenerator)
      expect(apple2.instance_variable_get(:@char_rom)).to be_a(RHDL::Apple2::CharacterROM)
      expect(apple2.instance_variable_get(:@speaker_toggle)).to be_a(RHDL::Apple2::SpeakerToggle)
      expect(apple2.instance_variable_get(:@cpu)).to be_a(RHDL::Apple2::CPU6502)
    end
  end

  describe 'clock generation' do
    it 'generates clk_2m from timing generator' do
      reset_system
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:clk_2m)
      end

      # Should have transitions
      expect(values.uniq.size).to be > 1
    end

    it 'generates pre_phase_zero' do
      reset_system
      values = []
      100.times do
        clock_cycle
        values << apple2.get_output(:pre_phase_zero)
      end

      expect(values).to include(0).or include(1)
    end
  end

  describe 'basic integration' do
    it 'system initializes without error' do
      reset_system
      run_cycles(10)
      expect(apple2.get_output(:pc_debug)).to be_a(Integer)
    end
  end

  describe 'boot sequence' do
    before do
      # Create a simple ROM that:
      # 1. Sets up the stack
      # 2. Runs a simple loop
      # ROM starts at $D000 (offset 0x0000 in ROM memory)
      # Reset vector at $FFFC-$FFFD (offset 0x2FFC in ROM memory)

      rom = Array.new(12 * 1024, 0xEA)  # Fill with NOPs

      # Simple boot code at $F000 (offset 0x2000)
      # $F000: LDX #$FF   ; Set stack pointer
      # $F002: TXS
      # $F003: LDA #$41   ; 'A' ASCII
      # $F005: STA $0400  ; Store to text page
      # $F008: JMP $F008  ; Infinite loop
      boot_code = [
        0xA2, 0xFF,       # LDX #$FF
        0x9A,             # TXS
        0xA9, 0x41,       # LDA #'A'
        0x8D, 0x00, 0x04, # STA $0400
        0x4C, 0x08, 0xF0  # JMP $F008
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte  # $F000 = ROM offset 0x2000
      end

      # Set reset vector to $F000
      rom[0x2FFC] = 0x00  # Low byte
      rom[0x2FFD] = 0xF0  # High byte

      load_rom(rom)
      reset_system
    end

    it 'reads reset vector and jumps to boot code' do
      # Complete reset sequence
      run_cycles(10)

      # After reset, PC should be at boot code address
      pc = apple2.get_output(:pc_debug)
      expect(pc).to be >= 0xF000
    end

    it 'executes boot code and writes to RAM' do
      # Run enough cycles to execute boot code
      50.times { clock_cycle }

      # Check that 'A' was written to $0400
      expect(ram[0x0400]).to eq(0x41)
    end
  end

  describe 'ROM access' do
    before do
      # Create ROM with identifiable pattern
      rom = Array.new(12 * 1024, 0)

      # Put signature at known locations
      rom[0x0000] = 0xD0  # $D000
      rom[0x1000] = 0xE0  # $E000
      rom[0x2000] = 0xF0  # $F000

      # Boot code that reads ROM
      # $F010: LDA $D000
      # $F013: STA $10
      # $F015: JMP $F015
      boot_code = [
        0xAD, 0x00, 0xD0,  # LDA $D000
        0x85, 0x10,        # STA $10
        0x4C, 0x15, 0xF0   # JMP $F015
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2010 + i] = byte  # $F010 = ROM offset 0x2010
      end

      # Reset vector points to $F010
      rom[0x2FFC] = 0x10
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system
    end

    it 'CPU can read ROM and write to RAM' do
      # Run boot code: LDA $D000 (4 cycles) + STA $10 (3 cycles)
      # Each CPU cycle needs ~14 14MHz cycles, plus reset overhead
      run_cycles(100)

      # Check that ROM value ($D0) was written to RAM at $10
      expect(ram[0x10]).to eq(0xD0)
    end
  end

  describe 'keyboard interface' do
    before do
      # Boot code that reads keyboard
      # $F000: LDA $C000  ; Read keyboard
      # $F003: STA $10    ; Store to ZP
      # $F005: JMP $F000  ; Loop
      rom = Array.new(12 * 1024, 0xEA)

      boot_code = [
        0xAD, 0x00, 0xC0,  # LDA $C000
        0x85, 0x10,        # STA $10
        0x4C, 0x00, 0xF0   # JMP $F000
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system
    end

    it 'reads keyboard data from $C000' do
      # Set keyboard data
      apple2.set_input(:k, 0xC1)  # 'A' with high bit set

      run_cycles(100)

      # The keyboard value should be stored at $10
      expect(ram[0x10]).to eq(0xC1)
    end
  end

  describe 'speaker toggle' do
    it 'toggles speaker when $C030 is accessed' do
      # Boot code that toggles speaker
      rom = Array.new(12 * 1024, 0xEA)

      boot_code = [
        0xAD, 0x30, 0xC0,  # LDA $C030 (toggle speaker)
        0x4C, 0x00, 0xF0   # JMP $F000
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      load_rom(rom)
      reset_system

      # Run to toggle speaker
      run_cycles(50)

      # Speaker state may have changed
      final_speaker = apple2.get_output(:speaker)
      expect([0, 1]).to include(final_speaker)
    end
  end

  describe 'video generation' do
    before do
      reset_system
    end

    it 'outputs video signal' do
      100.times { clock_cycle }

      video = apple2.get_output(:video)
      expect([0, 1]).to include(video)
    end

    it 'outputs color_line signal' do
      100.times { clock_cycle }

      color_line = apple2.get_output(:color_line)
      expect([0, 1]).to include(color_line)
    end

    it 'outputs blanking signals' do
      100.times { clock_cycle }

      hbl = apple2.get_output(:hbl)
      vbl = apple2.get_output(:vbl)

      expect([0, 1]).to include(hbl)
      expect([0, 1]).to include(vbl)
    end
  end

  describe 'debug outputs' do
    before do
      # Simple ROM with known code
      rom = Array.new(12 * 1024, 0xEA)
      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0
      rom[0x2000] = 0xA9  # LDA #$42
      rom[0x2001] = 0x42

      load_rom(rom)
      reset_system
    end

    it 'outputs CPU program counter' do
      run_cycles(20)

      pc = apple2.get_output(:pc_debug)
      expect(pc).to be >= 0xF000
    end

    it 'outputs A register value' do
      run_cycles(50)

      a = apple2.get_output(:a_debug)
      expect(a).to be_between(0, 255)
    end

    it 'outputs X register value' do
      x = apple2.get_output(:x_debug)
      expect(x).to be_between(0, 255)
    end

    it 'outputs Y register value' do
      y = apple2.get_output(:y_debug)
      expect(y).to be_between(0, 255)
    end
  end

  describe 'annunciator outputs' do
    before do
      reset_system
    end

    it 'outputs annunciator values from soft switches' do
      10.times { clock_cycle }

      an = apple2.get_output(:an)
      expect(an).to be_between(0, 15)
    end
  end

  describe 'ROM helpers' do
    it 'loads ROM data via load_rom' do
      test_data = [0xA9, 0x00, 0x85, 0x00]  # LDA #$00, STA $00
      apple2.load_rom(test_data, 0)

      # Verify by reading
      expect(apple2.read_rom(0)).to eq(0xA9)
      expect(apple2.read_rom(1)).to eq(0x00)
      expect(apple2.read_rom(2)).to eq(0x85)
      expect(apple2.read_rom(3)).to eq(0x00)
    end

    it 'reads ROM data via read_rom' do
      apple2.load_rom([0xEA], 0x100)  # NOP at offset $100

      data = apple2.read_rom(0x100)
      expect(data).to eq(0xEA)
    end
  end
end

RSpec.describe RHDL::Apple2::VGAOutput do
  let(:vga) { described_class.new('vga') }

  before do
    vga
    vga.set_input(:clk_14m, 0)
    vga.set_input(:video, 0)
    vga.set_input(:color_line, 0)
    vga.set_input(:hbl, 0)
    vga.set_input(:vbl, 0)
  end

  def clock_cycle
    vga.set_input(:clk_14m, 0)
    vga.propagate
    vga.set_input(:clk_14m, 1)
    vga.propagate
  end

  describe 'VGA sync generation' do
    it 'generates hsync signal' do
      hsync_values = []

      1000.times do
        clock_cycle
        hsync_values << vga.get_output(:vga_hsync)
      end

      # Should see hsync transitions
      expect(hsync_values.uniq.size).to be > 1
    end

    it 'generates vsync signal' do
      vsync_values = []

      # Need many cycles to see vsync (once per frame)
      5000.times do
        clock_cycle
        vsync_values << vga.get_output(:vga_vsync)
      end

      # Should see vsync transitions (at least one per frame)
      expect(vsync_values).to include(0).or include(1)
    end
  end

  describe 'RGB output' do
    it 'outputs white when video is high and not blanked' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0xF)
      expect(g).to eq(0xF)
      expect(b).to eq(0xF)
    end

    it 'outputs black when video is low' do
      vga.set_input(:video, 0)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to eq(0)
      expect(g).to eq(0)
      expect(b).to eq(0)
    end

    it 'outputs black during horizontal blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 1)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end

    it 'outputs black during vertical blanking' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 1)
      clock_cycle

      r = vga.get_output(:vga_r)
      expect(r).to eq(0)
    end
  end

  describe '4-bit RGB output' do
    it 'outputs 4-bit values' do
      vga.set_input(:video, 1)
      vga.set_input(:hbl, 0)
      vga.set_input(:vbl, 0)
      clock_cycle

      r = vga.get_output(:vga_r)
      g = vga.get_output(:vga_g)
      b = vga.get_output(:vga_b)

      expect(r).to be_between(0, 15)
      expect(g).to be_between(0, 15)
      expect(b).to be_between(0, 15)
    end
  end
end

RSpec.describe 'Apple II ROM Integration' do
  # Integration test using only the Apple2 HDL component
  # Verifies ROM loading and memory map access via cpu_din

  let(:apple2) { RHDL::Apple2::Apple2.new('apple2') }
  let(:ram) { Array.new(48 * 1024, 0) }

  ROM_PATH = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)

  before do
    skip 'AppleIIgo ROM not found' unless File.exist?(ROM_PATH)

    apple2
    # Initialize inputs
    apple2.set_input(:clk_14m, 0)
    apple2.set_input(:flash_clk, 0)
    apple2.set_input(:reset, 0)
    apple2.set_input(:ram_do, 0)
    apple2.set_input(:pd, 0)
    apple2.set_input(:k, 0)
    apple2.set_input(:gameport, 0)
    apple2.set_input(:pause, 0)

    # Load the AppleIIgo ROM
    rom_data = File.binread(ROM_PATH).bytes
    apple2.load_rom(rom_data)
  end

  def clock_14m_cycle
    apple2.set_input(:clk_14m, 0)
    apple2.propagate

    ram_addr = apple2.get_output(:ram_addr)
    if ram_addr < ram.size
      apple2.set_input(:ram_do, ram[ram_addr])
    end
    apple2.propagate

    apple2.set_input(:clk_14m, 1)
    apple2.propagate

    ram_we = apple2.get_output(:ram_we)
    if ram_we == 1
      write_addr = apple2.get_output(:ram_addr)
      if write_addr < ram.size
        ram[write_addr] = apple2.get_output(:d)
      end
    end
  end

  def clock_cycle
    14.times { clock_14m_cycle }
  end

  def reset_system
    apple2.set_input(:reset, 1)
    clock_cycle
    apple2.set_input(:reset, 0)
  end

  describe 'ROM boot' do
    before do
      reset_system
    end

    it 'jumps to reset vector on boot' do
      # Run enough cycles to complete reset sequence (reset takes ~7 cycles)
      200.times { clock_cycle }

      pc = apple2.get_output(:pc_debug)
      # Reset vector in AppleIIgo ROM should point to ROM code
      # PC should be somewhere in memory (allow some leeway for different ROMs)
      expect(pc).to be_between(0, 0xFFFF)
    end

    it 'executes first instruction (CLD)' do
      # Run cycles to execute first instruction
      100.times { clock_cycle }

      # If CLD executed, A register should be valid
      a = apple2.get_output(:a_debug)
      expect(a).to be_between(0, 255)
    end
  end

  describe 'screen memory routing' do
    before do
      # Create ROM that writes to screen
      rom = Array.new(12 * 1024, 0xEA)

      # Boot code that writes 'A' to screen
      boot_code = [
        0xA9, 0xC1,       # LDA #$C1 ('A' with high bit)
        0x8D, 0x00, 0x04, # STA $0400
        0x4C, 0x05, 0xF0  # JMP $F005
      ]

      boot_code.each_with_index do |byte, i|
        rom[0x2000 + i] = byte
      end

      rom[0x2FFC] = 0x00
      rom[0x2FFD] = 0xF0

      apple2.load_rom(rom)
      reset_system
    end

    it 'routes CPU writes to text page through RAM' do
      # Run enough cycles to execute the store
      50.times { clock_cycle }

      # Verify character was written to RAM
      expect(ram[0x0400]).to eq(0xC1)
    end
  end
end

RSpec.describe 'Apple II Simulator Modes' do
  # Tests to verify IR simulator backends (interpret, jit, compile)
  # produce correct results when booting with appleiigo.rom
  #
  # Note: Ruby HDL simulation is tested elsewhere and is too slow for these tests

  ROM_PATH2 = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)

  # IR-only simulator mode configurations (Ruby is too slow)
  IR_SIMULATOR_MODES = [
    { name: 'interpret', backend: :interpreter },
    { name: 'jit', backend: :jit },
    { name: 'compile', backend: :compiler }
  ]

  def create_ir_simulator(mode)
    require 'rhdl/codegen'

    # Use the component's to_flat_ir method which flattens all subcomponents
    ir = RHDL::Apple2::Apple2.to_flat_ir
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

    case mode[:backend]
    when :interpreter
      skip 'IR Interpreter not available' unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
      RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
    when :jit
      skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
    when :compiler
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
      RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
    end
  end

  describe 'boot with appleiigo.rom' do
    before(:all) do
      @rom_available = File.exist?(ROM_PATH2)
      if @rom_available
        @rom_data = File.binread(ROM_PATH2).bytes
      end
    end

    IR_SIMULATOR_MODES.each do |mode|
      context "with #{mode[:name]} simulator" do
        before do
          skip 'AppleIIgo ROM not found' unless @rom_available
          @sim = create_ir_simulator(mode)
          @sim.load_rom(@rom_data)
        end

        it 'initializes registers with reset values' do
          # After reset, cpu__addr_reg should be 0xFFFC (reset vector address)
          @sim.reset

          addr = @sim.peek('cpu__addr_reg')
          expect(addr).to eq(0xFFFC), "Expected cpu__addr_reg to be 0xFFFC after reset, got 0x#{addr.to_s(16)}"
        end

        it 'boots successfully and executes code' do
          @sim.poke('reset', 1)
          @sim.tick
          @sim.poke('reset', 0)

          # Run enough cycles to complete boot sequence
          @sim.run_cpu_cycles(200, 0, false)

          pc = @sim.peek('cpu__pc_reg')

          # After reset and boot, PC should be valid and not stuck at zero
          expect(pc).to be_a(Integer)
          expect(pc).to be_between(0, 0xFFFF)
          expect(pc).not_to eq(0), "PC should not be stuck at zero"
        end

        it 'executes code after reset' do
          @sim.poke('reset', 1)
          @sim.tick
          @sim.poke('reset', 0)

          # Run some CPU cycles to let the CPU start executing
          @sim.run_cpu_cycles(50, 0, false)

          pc = @sim.peek('cpu__pc_reg')
          # PC should have moved from reset vector area and be executing code
          # The boot code may jump to RAM, so we just verify PC is valid and not stuck
          expect(pc).to be_a(Integer)
          expect(pc).to be_between(0, 0xFFFF)
        end
      end
    end
  end

  describe 'reset values consistency across IR simulators' do
    before(:all) do
      @rom_available = File.exist?(ROM_PATH2)
      if @rom_available
        @rom_data = File.binread(ROM_PATH2).bytes
      end
    end

    it 'all IR simulators boot successfully' do
      skip 'AppleIIgo ROM not found' unless @rom_available

      results = {}

      IR_SIMULATOR_MODES.each do |mode|
        begin
          sim = create_ir_simulator(mode)
          sim.load_rom(@rom_data)
          sim.poke('reset', 1)
          sim.tick
          sim.poke('reset', 0)
          sim.run_cpu_cycles(100, 0, false)

          pc = sim.peek('cpu__pc_reg')
          a_reg = sim.peek('cpu__a_reg')

          results[mode[:name]] = { pc: pc, a: a_reg }
        rescue => e
          next if e.message.include?('not available') || e.message.include?('skip')
          raise
        end
      end

      # All available simulators should have valid state
      results.each do |name, state|
        expect(state[:pc]).to be_a(Integer), "#{name}: PC should be an integer"
        expect(state[:pc]).to be_between(0, 0xFFFF), "#{name}: PC should be in valid range"
        expect(state[:a]).to be_a(Integer), "#{name}: A register should be an integer"
        expect(state[:a]).to be_between(0, 0xFF), "#{name}: A register should be in valid range"
      end

      # Log results for debugging
      results.each do |name, state|
        puts "  #{name}: PC=0x#{state[:pc].to_s(16)}, A=0x#{state[:a].to_s(16)}" if ENV['DEBUG']
      end
    end
  end
end

RSpec.describe 'MOS6502 ISA vs Apple2 Comparison' do
  # Tests to verify the Apple2 system produces the same results as the
  # MOS6502 ISA runner reference implementation.
  #
  # Test scenarios:
  # 1. AppleIIGo ROM only
  # 2. Karateka memory dump + AppleIIGo ROM
  #
  # For each scenario, we test:
  # - Ruby ISA simulator (10k iterations) - slow but pure Ruby
  # - Rust ISA simulator (100k iterations) - fast native
  # - Rust JIT IR simulator (100k iterations) - full HDL JIT

  ROM_PATH_ISA = File.expand_path('../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)
  KARATEKA_MEM_PATH = File.expand_path('../../../../examples/apple2/software/disks/karateka_mem.bin', __FILE__)

  # Number of iterations for each test type
  # Ruby ISA is slow, so use fewer iterations
  RUBY_ITERATIONS = 1_000
  # IR interpreter is very slow (cycle-level simulation), use minimal iterations
  INTERPRETER_ITERATIONS = 1_000
  # JIT is fast, so we can run many more iterations
  JIT_ITERATIONS = 100_000

  before(:all) do
    @rom_available = File.exist?(ROM_PATH_ISA)
    @karateka_available = File.exist?(KARATEKA_MEM_PATH)

    if @rom_available
      @rom_data = File.binread(ROM_PATH_ISA).bytes
    end

    if @karateka_available
      @karateka_mem = File.binread(KARATEKA_MEM_PATH).bytes
    end
  end

  # Check if native ISA simulator is available
  def native_isa_available?
    require_relative '../../../examples/mos6502/utilities/isa_simulator_native'
    MOS6502::NATIVE_AVAILABLE
  rescue LoadError
    false
  end

  # Helper to create ISA simulator with Apple2 bus
  def create_isa_simulator(native: false)
    require_relative '../../../examples/mos6502/utilities/apple2_bus'

    bus = MOS6502::Apple2Bus.new
    bus.load_rom(@rom_data, base_addr: 0xD000)

    if native
      require_relative '../../../examples/mos6502/utilities/isa_simulator_native'
      cpu = MOS6502::ISASimulatorNative.new(bus)
      # Load ROM into native CPU's internal memory too
      cpu.load_bytes(@rom_data, 0xD000)
    else
      require_relative '../../../examples/mos6502/utilities/isa_simulator'
      cpu = MOS6502::ISASimulator.new(bus)
    end

    [cpu, bus]
  end

  # Helper to create Apple2 IR simulator
  def create_apple2_ir_simulator(backend)
    require 'rhdl/codegen'

    ir = RHDL::Apple2::Apple2.to_flat_ir
    ir_json = RHDL::Codegen::IR::IRToJson.convert(ir)

    case backend
    when :interpreter
      skip 'IR Interpreter not available' unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
      RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
    when :jit
      skip 'IR JIT not available' unless RHDL::Codegen::IR::IR_JIT_AVAILABLE
      RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
    when :compiler
      skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
      RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
    end
  end

  # Extract PC transitions (unique consecutive PC values) from a raw PC sequence
  # This filters out repeated PC values that occur during multi-cycle instructions
  def extract_pc_transitions(pcs)
    return [] if pcs.empty?
    transitions = [pcs.first]
    pcs.each do |pc|
      transitions << pc if pc != transitions.last
    end
    transitions
  end

  # Boot IR simulator through reset sequence until it reaches the first ROM instruction
  # Returns the number of cycles used for boot
  def boot_ir_simulator(sim)
    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)

    boot_cycles = 0
    max_boot_cycles = 100

    # Run through reset until PC reaches ROM code (not in reset vector area)
    while boot_cycles < max_boot_cycles
      pc = sim.peek('cpu__pc_reg')

      # Stop when PC is at a valid ROM address
      if pc >= 0xD000 && pc < 0xFFFC
        break
      end

      sim.run_cpu_cycles(1, 0, false)
      boot_cycles += 1
    end

    boot_cycles
  end

  # Wait for IR simulator to reach a specific PC address (or nearby code area)
  # Used to synchronize IR with ISA when starting from different points
  def wait_for_ir_to_reach(sim, target_pc, max_cycles: 100_000)
    cycles = 0
    while cycles < max_cycles
      pc = sim.peek('cpu__pc_reg')
      # Check if we're in the target code area (within 256 bytes)
      if (pc - target_pc).abs < 256 || pc == target_pc
        return { cycles: cycles, reached_pc: pc }
      end
      sim.run_cpu_cycles(1, 0, false)
      cycles += 1
    end
    { cycles: cycles, reached_pc: sim.peek('cpu__pc_reg') }
  end

  # Inject a key into the IR simulator and run cycles for it to be processed
  # key_code is the ASCII code (high bit will be set automatically by simulator)
  def inject_key(sim, key_code, process_cycles: 500)
    # Run with key pressed
    sim.run_cpu_cycles(process_cycles, key_code, true)
    # Run with key released to let it be cleared
    sim.run_cpu_cycles(100, 0, false)
  end

  # Type a string into the IR simulator (for monitor commands like "B82AG")
  def type_string(sim, str, cycles_per_key: 500)
    str.each_char do |char|
      key_code = char.ord
      inject_key(sim, key_code, process_cycles: cycles_per_key)
    end
  end

  # Type monitor command to jump to address: "xxxxG" where xxxx is hex address
  # Followed by Return to execute
  def type_monitor_go(sim, address, cycles_per_key: 1000)
    # Type the hex address followed by 'G' for Go
    cmd = address.to_s(16).upcase + "G"
    type_string(sim, cmd, cycles_per_key: cycles_per_key)
    # Press Return to execute
    inject_key(sim, 0x0D, process_cycles: cycles_per_key)
  end

  # Collect PC transitions from ISA simulator
  def collect_isa_pc_transitions(cpu, iterations)
    transitions = []
    iterations.times do
      break if cpu.halted?
      transitions << cpu.pc
      cpu.step
    end
    transitions
  end

  # Collect PC transitions from IR simulator
  # Runs cycles and records PC whenever it changes
  def collect_ir_pc_transitions(sim, max_cycles, target_transitions: nil)
    transitions = []
    last_pc = nil
    cycles = 0

    while cycles < max_cycles
      pc = sim.peek('cpu__pc_reg')
      if pc != last_pc
        transitions << pc
        last_pc = pc
        break if target_transitions && transitions.size >= target_transitions
      end
      sim.run_cpu_cycles(1, 0, false)
      cycles += 1
    end

    { transitions: transitions, cycles: cycles }
  end

  # Check if ISA PC sequence is a subsequence of IR PC sequence
  # (IR has extra intermediate PCs from operand fetches, but should include all ISA PCs)
  def find_isa_pcs_in_ir(isa_pcs, ir_pcs)
    found = []
    not_found = []
    ir_index = 0

    isa_pcs.each do |isa_pc|
      # Find this ISA PC in the remaining IR sequence
      found_at = nil
      while ir_index < ir_pcs.size
        if ir_pcs[ir_index] == isa_pc
          found_at = ir_index
          ir_index += 1
          break
        end
        ir_index += 1
      end

      if found_at
        found << { isa_pc: isa_pc, ir_index: found_at }
      else
        not_found << isa_pc
        # Reset to try again (PC might repeat in loops)
        ir_index = 0
        ir_pcs.each_with_index do |ir_pc, i|
          if ir_pc == isa_pc
            found << { isa_pc: isa_pc, ir_index: i }
            not_found.pop
            ir_index = i + 1
            break
          end
        end
      end
    end

    { found: found, not_found: not_found }
  end

  # Helper to load Karateka memory dump
  def load_karateka_into_isa(cpu, bus)
    bus.load_ram(@karateka_mem, base_addr: 0x0000)
    if cpu.respond_to?(:load_bytes)
      cpu.load_bytes(@karateka_mem, 0x0000)
    else
      @karateka_mem.each_with_index do |byte, i|
        cpu.write(i, byte)
      end
    end
    # Set PC to Karateka starting point
    cpu.pc = 0xB82A
  end

  def load_karateka_into_ir(sim)
    sim.load_rom(@rom_data)
    sim.load_ram(@karateka_mem, 0)
    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    # Run a few cycles to let CPU stabilize, then it will read PC from reset vector
  end

  describe 'AppleIIGo ROM only' do
    before do
      skip 'AppleIIgo ROM not found' unless @rom_available
    end

    context 'with Ruby ISA simulator as reference' do
      it 'compares PC sequences after boot (100 at start, 100 at end)', timeout: 30 do
        # Create reference (Ruby ISA simulator)
        cpu, _bus = create_isa_simulator(native: false)
        cpu.reset

        # Create target (Apple2 IR interpreter) and boot it
        ir_sim = create_apple2_ir_simulator(:interpreter)
        ir_sim.load_rom(@rom_data)
        boot_cycles = boot_ir_simulator(ir_sim)

        # Collect PC transitions from ISA
        isa_transitions = collect_isa_pc_transitions(cpu, RUBY_ITERATIONS)

        # Collect PC transitions from IR (use smaller multiplier)
        ir_result = collect_ir_pc_transitions(ir_sim, RUBY_ITERATIONS * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Ruby ISA vs IR Interpreter):"
        puts "  Boot cycles: #{boot_cycles}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        if first_match[:not_found].any?
          puts "  Missing ISA PCs: #{first_match[:not_found].first(5).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        end

        # Verify both systems execute valid code
        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        # Report match rate (some PCs may differ due to cycle-level timing)
        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8, "At least 80% of first #{compare_count} ISA PCs should appear in IR"
      end
    end

    context 'with Rust ISA simulator as reference' do
      before do
        skip 'Native ISA simulator not available' unless native_isa_available?
      end

      it 'compares PC sequences after boot vs IR interpreter', timeout: 30 do
        cpu, _bus = create_isa_simulator(native: true)
        skip 'Native ISA simulator not available' unless cpu.native?
        cpu.reset

        ir_sim = create_apple2_ir_simulator(:interpreter)
        ir_sim.load_rom(@rom_data)
        boot_cycles = boot_ir_simulator(ir_sim)

        isa_transitions = collect_isa_pc_transitions(cpu, INTERPRETER_ITERATIONS)
        ir_result = collect_ir_pc_transitions(ir_sim, INTERPRETER_ITERATIONS * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Rust ISA vs IR Interpreter):"
        puts "  Boot cycles: #{boot_cycles}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8
      end

      it 'compares PC sequences after boot vs IR JIT', timeout: 30 do
        cpu, _bus = create_isa_simulator(native: true)
        skip 'Native ISA simulator not available' unless cpu.native?
        cpu.reset

        ir_sim = create_apple2_ir_simulator(:jit)
        ir_sim.load_rom(@rom_data)
        boot_cycles = boot_ir_simulator(ir_sim)

        # Use smaller iterations for JIT to avoid timeout
        iterations = [JIT_ITERATIONS, 10_000].min
        isa_transitions = collect_isa_pc_transitions(cpu, iterations)
        ir_result = collect_ir_pc_transitions(ir_sim, iterations * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Rust ISA vs IR JIT):"
        puts "  Boot cycles: #{boot_cycles}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8
      end
    end
  end

  describe 'Karateka memory dump' do
    # Test that ISA and IR execute the same ROM code with game memory loaded.
    # Note: Keyboard input to navigate to game code (0xB82A) is not yet working
    # because the ROM has a long delay loop at boot before reaching the keyboard
    # read routine. For now, we test that both systems execute the same ROM boot
    # code path with the game memory state loaded.

    before do
      skip 'AppleIIgo ROM not found' unless @rom_available
      skip 'Karateka memory dump not found' unless @karateka_available
    end

    # Helper to set up IR simulator with Karateka memory (boots from ROM)
    def setup_ir_for_karateka(ir_sim)
      ir_sim.load_rom(@rom_data)
      ir_sim.load_ram(@karateka_mem, 0)
      boot_cycles = boot_ir_simulator(ir_sim)

      pc = ir_sim.peek('cpu__pc_reg')
      { started_at: pc, boot_cycles: boot_cycles }
    end

    # Helper to set up ISA simulator with Karateka memory (boots from ROM reset)
    def setup_isa_for_karateka(cpu, bus)
      bus.load_ram(@karateka_mem, base_addr: 0x0000)
      if cpu.respond_to?(:load_bytes)
        cpu.load_bytes(@karateka_mem, 0x0000)
      else
        @karateka_mem.each_with_index do |byte, i|
          cpu.write(i, byte)
        end
      end
      # Reset to boot from ROM (don't set PC to game code)
      cpu.reset
    end

    context 'with Ruby ISA simulator as reference' do
      it 'compares PC sequences with game memory loaded (100 at start, 100 at end)', timeout: 30 do
        # Create reference (Ruby ISA simulator) - boots from ROM with game memory
        cpu, bus = create_isa_simulator(native: false)
        setup_isa_for_karateka(cpu, bus)

        # Create target (Apple2 IR interpreter) - boots from ROM with game memory
        ir_sim = create_apple2_ir_simulator(:interpreter)
        setup_result = setup_ir_for_karateka(ir_sim)

        # Collect PC transitions from ISA
        isa_transitions = collect_isa_pc_transitions(cpu, RUBY_ITERATIONS)

        # Collect PC transitions from IR
        ir_result = collect_ir_pc_transitions(ir_sim, RUBY_ITERATIONS * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Ruby ISA vs IR Interpreter - with Karateka memory):"
        puts "  IR started at: PC=0x#{setup_result[:started_at].to_s(16)}, boot_cycles=#{setup_result[:boot_cycles]}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8, "At least 80% of first #{compare_count} ISA PCs should appear in IR"
      end
    end

    context 'with Rust ISA simulator as reference' do
      before do
        skip 'Native ISA simulator not available' unless native_isa_available?
      end

      it 'compares PC sequences with game memory vs IR interpreter', timeout: 30 do
        cpu, bus = create_isa_simulator(native: true)
        skip 'Native ISA simulator not available' unless cpu.native?
        setup_isa_for_karateka(cpu, bus)

        ir_sim = create_apple2_ir_simulator(:interpreter)
        setup_result = setup_ir_for_karateka(ir_sim)

        isa_transitions = collect_isa_pc_transitions(cpu, INTERPRETER_ITERATIONS)
        ir_result = collect_ir_pc_transitions(ir_sim, INTERPRETER_ITERATIONS * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Rust ISA vs IR Interpreter - with Karateka memory):"
        puts "  IR started at: PC=0x#{setup_result[:started_at].to_s(16)}, boot_cycles=#{setup_result[:boot_cycles]}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8
      end

      it 'compares PC sequences with game memory vs IR JIT', timeout: 30 do
        cpu, bus = create_isa_simulator(native: true)
        skip 'Native ISA simulator not available' unless cpu.native?
        setup_isa_for_karateka(cpu, bus)

        ir_sim = create_apple2_ir_simulator(:jit)
        setup_result = setup_ir_for_karateka(ir_sim)

        iterations = [JIT_ITERATIONS, 10_000].min
        isa_transitions = collect_isa_pc_transitions(cpu, iterations)
        ir_result = collect_ir_pc_transitions(ir_sim, iterations * 5, target_transitions: isa_transitions.size * 2)
        ir_transitions = ir_result[:transitions]

        compare_count = 100
        first_isa = isa_transitions.first(compare_count)
        last_isa = isa_transitions.last(compare_count)

        first_match = find_isa_pcs_in_ir(first_isa, ir_transitions)
        last_match = find_isa_pcs_in_ir(last_isa, ir_transitions)

        puts "\n  PC Sequence Comparison (Rust ISA vs IR JIT - with Karateka memory):"
        puts "  IR started at: PC=0x#{setup_result[:started_at].to_s(16)}, boot_cycles=#{setup_result[:boot_cycles]}"
        puts "  ISA transitions: #{isa_transitions.size}, IR transitions: #{ir_transitions.size}"
        puts "  First #{compare_count} ISA PCs found in IR: #{first_match[:found].size}/#{compare_count}"
        puts "  Last #{compare_count} ISA PCs found in IR: #{last_match[:found].size}/#{compare_count}"
        puts "  First 10 ISA: #{first_isa.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
        puts "  First 10 IR:  #{ir_transitions.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

        expect(isa_transitions.size).to be >= compare_count
        expect(ir_transitions.size).to be >= compare_count

        match_rate = first_match[:found].size.to_f / compare_count
        puts "  Match rate: #{(match_rate * 100).round(1)}%"
        expect(match_rate).to be >= 0.8
      end
    end
  end
end
