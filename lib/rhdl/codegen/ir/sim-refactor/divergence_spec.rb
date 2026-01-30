# frozen_string_literal: true

# Temporary test to verify sim-refactor matches monolithic sim
#
# Run with: bundle exec rspec lib/rhdl/codegen/ir/sim-refactor/divergence_spec.rb
#
# This test compares the refactored (modularized extension architecture) IR simulators
# against the monolithic versions to ensure they produce identical results.

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

# Load refactored wrappers (these are in RHDL::Codegen::IR::Refactored module)
require_relative 'ir_interpreter'
require_relative 'ir_compiler'
require_relative 'ir_jit'

RSpec.describe 'Refactored vs Monolithic IR Simulator Divergence' do
  ROM_PATH = File.expand_path('../../../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)

  before(:all) do
    @rom_available = File.exist?(ROM_PATH)
    if @rom_available
      @rom_data = File.binread(ROM_PATH).bytes
    end

    # Check availability of both sets of simulators
    @monolithic_interpreter_available = RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
    @monolithic_compiler_available = RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    @monolithic_jit_available = RHDL::Codegen::IR::IR_JIT_AVAILABLE

    @refactored_interpreter_available = RHDL::Codegen::IR::Refactored::INTERPRETER_AVAILABLE
    @refactored_compiler_available = RHDL::Codegen::IR::Refactored::COMPILER_AVAILABLE
    @refactored_jit_available = RHDL::Codegen::IR::Refactored::JIT_AVAILABLE

    puts "\n  Extension availability:"
    puts "  Monolithic Interpreter: #{@monolithic_interpreter_available}"
    puts "  Monolithic Compiler: #{@monolithic_compiler_available}"
    puts "  Monolithic JIT: #{@monolithic_jit_available}"
    puts "  Refactored Interpreter: #{@refactored_interpreter_available}"
    puts "  Refactored Compiler: #{@refactored_compiler_available}"
    puts "  Refactored JIT: #{@refactored_jit_available}"
  end

  def create_ir_json
    require_relative '../../../../../examples/apple2/hdl/apple2'
    ir = RHDL::Apple2::Apple2.to_flat_ir
    RHDL::Codegen::IR::IRToJson.convert(ir)
  end

  # Create monolithic simulators (from sim/)
  def create_monolithic_interpreter
    ir_json = create_ir_json
    RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
  end

  def create_monolithic_compiler
    ir_json = create_ir_json
    RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
  end

  def create_monolithic_jit
    ir_json = create_ir_json
    RHDL::Codegen::IR::IrJitWrapper.new(ir_json)
  end

  # Create refactored simulators (from sim-refactor/)
  def create_refactored_interpreter
    ir_json = create_ir_json
    RHDL::Codegen::IR::Refactored::IrInterpreterWrapper.new(ir_json)
  end

  def create_refactored_compiler
    ir_json = create_ir_json
    RHDL::Codegen::IR::Refactored::IrCompilerWrapper.new(ir_json)
  end

  def create_refactored_jit
    ir_json = create_ir_json
    RHDL::Codegen::IR::Refactored::IrJitWrapper.new(ir_json)
  end

  # Adapter methods to handle different APIs between monolithic and refactored
  def sim_load_rom(sim, data)
    if sim.respond_to?(:apple2_load_rom)
      sim.apple2_load_rom(data)
    else
      sim.load_rom(data)
    end
  end

  def sim_run_cpu_cycles(sim, n, key_data, key_ready)
    if sim.respond_to?(:apple2_run_cpu_cycles)
      sim.apple2_run_cpu_cycles(n, key_data, key_ready)
    else
      sim.run_cpu_cycles(n, key_data, key_ready)
    end
  end

  def sim_read_ram(sim, offset, length)
    if sim.respond_to?(:apple2_read_ram)
      sim.apple2_read_ram(offset, length)
    else
      sim.read_ram(offset, length)
    end
  end

  # Boot simulator through reset sequence
  def boot_simulator(sim)
    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    10.times { sim_run_cpu_cycles(sim, 1, 0, false) }
  end

  # Collect PC and opcode values for N cycles
  def collect_trace(sim, num_cycles)
    trace = []
    num_cycles.times do |i|
      pc = sim.peek('cpu__pc_reg')
      opcode = sim.peek('opcode_debug') rescue 0
      trace << { cycle: i, pc: pc, opcode: opcode }
      sim_run_cpu_cycles(sim, 1, 0, false)
    end
    trace
  end

  # Compare two traces and return divergence info
  def compare_traces(trace_a, trace_b, label_a, label_b)
    divergences = []

    trace_a.zip(trace_b).each_with_index do |(a, b), i|
      next if a.nil? || b.nil?

      if a[:pc] != b[:pc] || a[:opcode] != b[:opcode]
        divergences << {
          cycle: i,
          "#{label_a}_pc" => a[:pc],
          "#{label_b}_pc" => b[:pc],
          "#{label_a}_opcode" => a[:opcode],
          "#{label_b}_opcode" => b[:opcode]
        }
      end
    end

    divergences
  end

  # ============================================================================
  # Monolithic vs Refactored Interpreter Tests
  # ============================================================================

  describe 'Monolithic vs Refactored Interpreter' do
    it 'produces identical PC sequence for 1000 cycles' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic Interpreter not available' unless @monolithic_interpreter_available
      skip 'Refactored Interpreter not available' unless @refactored_interpreter_available

      mono = create_monolithic_interpreter
      refac = create_refactored_interpreter

      sim_load_rom(mono, @rom_data)
      sim_load_rom(refac, @rom_data)

      boot_simulator(mono)
      boot_simulator(refac)

      num_cycles = 1000
      mono_trace = collect_trace(mono, num_cycles)
      refac_trace = collect_trace(refac, num_cycles)

      divergences = compare_traces(mono_trace, refac_trace, 'mono', 'refac')

      puts "\n  Monolithic vs Refactored Interpreter comparison:"
      puts "  Cycles compared: #{num_cycles}"
      puts "  Divergences: #{divergences.length}"

      if divergences.any?
        puts "  First 10 divergences:"
        divergences.first(10).each do |d|
          mono_pc = d[:mono_pc] || 0
          mono_opcode = d[:mono_opcode] || 0
          refac_pc = d[:refac_pc] || 0
          refac_opcode = d[:refac_opcode] || 0
          puts format("    Cycle %d: mono PC=$%04X op=$%02X | refac PC=$%04X op=$%02X",
                      d[:cycle], mono_pc, mono_opcode, refac_pc, refac_opcode)
        end
      end

      match_rate = 1.0 - (divergences.length.to_f / num_cycles)
      puts "  Match rate: #{(match_rate * 100).round(1)}%"

      expect(divergences.length).to eq(0),
        "Expected identical behavior, got #{divergences.length} divergences"
    end
  end

  # ============================================================================
  # Monolithic vs Refactored Compiler Tests
  # ============================================================================

  describe 'Monolithic vs Refactored Compiler' do
    it 'produces identical PC sequence for 1000 cycles' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic Compiler not available' unless @monolithic_compiler_available
      skip 'Refactored Compiler not available' unless @refactored_compiler_available

      mono = create_monolithic_compiler
      refac = create_refactored_compiler

      sim_load_rom(mono, @rom_data)
      sim_load_rom(refac, @rom_data)

      boot_simulator(mono)
      boot_simulator(refac)

      num_cycles = 1000
      mono_trace = collect_trace(mono, num_cycles)
      refac_trace = collect_trace(refac, num_cycles)

      divergences = compare_traces(mono_trace, refac_trace, 'mono', 'refac')

      puts "\n  Monolithic vs Refactored Compiler comparison:"
      puts "  Cycles compared: #{num_cycles}"
      puts "  Divergences: #{divergences.length}"

      if divergences.any?
        puts "  First 10 divergences:"
        divergences.first(10).each do |d|
          mono_pc = d[:mono_pc] || 0
          mono_opcode = d[:mono_opcode] || 0
          refac_pc = d[:refac_pc] || 0
          refac_opcode = d[:refac_opcode] || 0
          puts format("    Cycle %d: mono PC=$%04X op=$%02X | refac PC=$%04X op=$%02X",
                      d[:cycle], mono_pc, mono_opcode, refac_pc, refac_opcode)
        end
      end

      match_rate = 1.0 - (divergences.length.to_f / num_cycles)
      puts "  Match rate: #{(match_rate * 100).round(1)}%"

      expect(divergences.length).to eq(0),
        "Expected identical behavior, got #{divergences.length} divergences"
    end
  end

  # ============================================================================
  # Monolithic vs Refactored JIT Tests
  # ============================================================================

  describe 'Monolithic vs Refactored JIT' do
    it 'produces identical PC sequence for 1000 cycles' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic JIT not available' unless @monolithic_jit_available
      skip 'Refactored JIT not available' unless @refactored_jit_available

      mono = create_monolithic_jit
      refac = create_refactored_jit

      sim_load_rom(mono, @rom_data)
      sim_load_rom(refac, @rom_data)

      boot_simulator(mono)
      boot_simulator(refac)

      num_cycles = 1000
      mono_trace = collect_trace(mono, num_cycles)
      refac_trace = collect_trace(refac, num_cycles)

      divergences = compare_traces(mono_trace, refac_trace, 'mono', 'refac')

      puts "\n  Monolithic vs Refactored JIT comparison:"
      puts "  Cycles compared: #{num_cycles}"
      puts "  Divergences: #{divergences.length}"

      if divergences.any?
        puts "  First 10 divergences:"
        divergences.first(10).each do |d|
          mono_pc = d[:mono_pc] || 0
          mono_opcode = d[:mono_opcode] || 0
          refac_pc = d[:refac_pc] || 0
          refac_opcode = d[:refac_opcode] || 0
          puts format("    Cycle %d: mono PC=$%04X op=$%02X | refac PC=$%04X op=$%02X",
                      d[:cycle], mono_pc, mono_opcode, refac_pc, refac_opcode)
        end
      end

      match_rate = 1.0 - (divergences.length.to_f / num_cycles)
      puts "  Match rate: #{(match_rate * 100).round(1)}%"

      expect(divergences.length).to eq(0),
        "Expected identical behavior, got #{divergences.length} divergences"
    end
  end

  # ============================================================================
  # All Simulators Comparison (sanity check)
  # ============================================================================

  describe 'All six simulators' do
    it 'all produce identical PC sequence for 500 cycles' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic Interpreter not available' unless @monolithic_interpreter_available
      skip 'Monolithic Compiler not available' unless @monolithic_compiler_available
      skip 'Monolithic JIT not available' unless @monolithic_jit_available
      skip 'Refactored Interpreter not available' unless @refactored_interpreter_available
      skip 'Refactored Compiler not available' unless @refactored_compiler_available
      skip 'Refactored JIT not available' unless @refactored_jit_available

      sims = {
        'mono_interp' => create_monolithic_interpreter,
        'mono_comp' => create_monolithic_compiler,
        'mono_jit' => create_monolithic_jit,
        'refac_interp' => create_refactored_interpreter,
        'refac_comp' => create_refactored_compiler,
        'refac_jit' => create_refactored_jit
      }

      sims.each { |_, sim| sim_load_rom(sim, @rom_data) }
      sims.each { |_, sim| boot_simulator(sim) }

      num_cycles = 500
      traces = {}
      sims.each { |name, sim| traces[name] = collect_trace(sim, num_cycles) }

      # Compare all pairs
      puts "\n  All six simulators comparison (#{num_cycles} cycles):"

      pairs = sims.keys.combination(2).to_a
      all_match = true

      pairs.each do |name_a, name_b|
        divergences = compare_traces(traces[name_a], traces[name_b], name_a, name_b)
        match = divergences.empty?
        all_match &&= match
        status = match ? 'MATCH' : "#{divergences.length} divergences"
        puts "    #{name_a} vs #{name_b}: #{status}"
      end

      expect(all_match).to be(true), "Not all simulator pairs produced identical traces"
    end
  end

  # ============================================================================
  # Extended Execution Tests (longer runs)
  # ============================================================================

  describe 'Extended execution verification', :slow do
    it 'monolithic vs refactored interpreter for 10K cycles' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic Interpreter not available' unless @monolithic_interpreter_available
      skip 'Refactored Interpreter not available' unless @refactored_interpreter_available

      mono = create_monolithic_interpreter
      refac = create_refactored_interpreter

      sim_load_rom(mono, @rom_data)
      sim_load_rom(refac, @rom_data)

      boot_simulator(mono)
      boot_simulator(refac)

      num_cycles = 10_000
      divergence_count = 0
      first_divergence = nil

      num_cycles.times do |i|
        mono_pc = mono.peek('cpu__pc_reg')
        refac_pc = refac.peek('cpu__pc_reg')

        if mono_pc != refac_pc
          divergence_count += 1
          first_divergence ||= { cycle: i, mono_pc: mono_pc, refac_pc: refac_pc }
        end

        sim_run_cpu_cycles(mono, 1, 0, false)
        sim_run_cpu_cycles(refac, 1, 0, false)
      end

      puts "\n  Extended Interpreter comparison (#{num_cycles} cycles):"
      puts "  Divergences: #{divergence_count}"

      if first_divergence
        puts format("  First divergence at cycle %d: mono=$%04X refac=$%04X",
                    first_divergence[:cycle], first_divergence[:mono_pc], first_divergence[:refac_pc])
      end

      expect(divergence_count).to eq(0),
        "Expected identical behavior, got #{divergence_count} divergences"
    end
  end

  # ============================================================================
  # Memory State Comparison
  # ============================================================================

  describe 'Memory state verification' do
    it 'monolithic vs refactored have identical RAM after execution' do
      skip 'ROM not available' unless @rom_available
      skip 'Monolithic Interpreter not available' unless @monolithic_interpreter_available
      skip 'Refactored Interpreter not available' unless @refactored_interpreter_available

      mono = create_monolithic_interpreter
      refac = create_refactored_interpreter

      sim_load_rom(mono, @rom_data)
      sim_load_rom(refac, @rom_data)

      boot_simulator(mono)
      boot_simulator(refac)

      # Run some cycles
      1000.times do
        sim_run_cpu_cycles(mono, 1, 0, false)
        sim_run_cpu_cycles(refac, 1, 0, false)
      end

      # Compare zero page
      mono_zp = sim_read_ram(mono, 0x00, 0x100).to_a rescue []
      refac_zp = sim_read_ram(refac, 0x00, 0x100).to_a rescue []

      if mono_zp.any? && refac_zp.any?
        zp_diff = mono_zp.zip(refac_zp).each_with_index.count { |(a, b), _| a != b }

        puts "\n  Zero page comparison after 1000 cycles:"
        puts "  Differences: #{zp_diff} / 256 bytes"

        expect(zp_diff).to eq(0),
          "Expected identical zero page, got #{zp_diff} differences"
      end

      # Compare stack area
      mono_stack = sim_read_ram(mono, 0x100, 0x100).to_a rescue []
      refac_stack = sim_read_ram(refac, 0x100, 0x100).to_a rescue []

      if mono_stack.any? && refac_stack.any?
        stack_diff = mono_stack.zip(refac_stack).each_with_index.count { |(a, b), _| a != b }

        puts "  Stack comparison:"
        puts "  Differences: #{stack_diff} / 256 bytes"

        expect(stack_diff).to eq(0),
          "Expected identical stack, got #{stack_diff} differences"
      end
    end
  end
end
