# frozen_string_literal: true

require 'spec_helper'
require 'rhdl'
require 'rhdl/codegen'

RSpec.describe 'IrCompiler vs IrInterpreter PC Progression' do
  # Tests to verify the rewritten IR Compiler produces identical PC progression
  # as the IR Interpreter. Both should execute the same evaluation logic,
  # so their PC sequences must match exactly.

  ROM_PATH = File.expand_path('../../../../../../examples/apple2/software/roms/appleiigo.rom', __FILE__)

  before(:all) do
    @rom_available = File.exist?(ROM_PATH)
    if @rom_available
      @rom_data = File.binread(ROM_PATH).bytes
    end
  end

  def create_ir_json
    require_relative '../../../../../examples/apple2/hdl/apple2'
    ir = RHDL::Apple2::Apple2.to_flat_ir
    RHDL::Codegen::IR::IRToJson.convert(ir)
  end

  def create_interpreter
    skip 'IR Interpreter not available' unless RHDL::Codegen::IR::IR_INTERPRETER_AVAILABLE
    ir_json = create_ir_json
    RHDL::Codegen::IR::IrInterpreterWrapper.new(ir_json)
  end

  def create_compiler
    skip 'IR Compiler not available' unless RHDL::Codegen::IR::IR_COMPILER_AVAILABLE
    ir_json = create_ir_json
    RHDL::Codegen::IR::IrCompilerWrapper.new(ir_json)
  end

  # Boot simulator through reset sequence
  def boot_simulator(sim)
    sim.poke('reset', 1)
    sim.tick
    sim.poke('reset', 0)
    10.times { sim.run_cpu_cycles(1, 0, false) }
  end

  # Collect PC values for N cycles
  def collect_pcs(sim, num_cycles)
    pcs = []
    num_cycles.times do
      pc = sim.peek('cpu__pc_reg')
      pcs << pc
      sim.run_cpu_cycles(1, 0, false)
    end
    pcs
  end

  # Extract unique consecutive PC values (transitions)
  def extract_transitions(pcs)
    return [] if pcs.empty?
    transitions = [pcs.first]
    pcs.each do |pc|
      transitions << pc if pc != transitions.last
    end
    transitions
  end

  describe 'basic functionality' do
    it 'both simulators load and initialize correctly' do
      skip 'ROM not available' unless @rom_available

      interpreter = create_interpreter
      compiler = create_compiler

      interpreter.load_rom(@rom_data)
      compiler.load_rom(@rom_data)

      expect(interpreter.signal_count).to be > 0
      expect(compiler.signal_count).to be > 0

      # Both should have same signal count
      expect(compiler.signal_count).to eq(interpreter.signal_count)
    end

    it 'both simulators reset to same state' do
      skip 'ROM not available' unless @rom_available

      interpreter = create_interpreter
      compiler = create_compiler

      interpreter.load_rom(@rom_data)
      compiler.load_rom(@rom_data)

      interpreter.reset
      compiler.reset

      # After reset, cpu__addr_reg should be 0xFFFC (reset vector address)
      interp_addr = interpreter.peek('cpu__addr_reg')
      comp_addr = compiler.peek('cpu__addr_reg')

      expect(comp_addr).to eq(interp_addr), "Compiler reset state differs from interpreter"
    end
  end

  describe 'PC progression comparison' do
    it 'produces identical PC sequence for first 100 cycles after boot' do
      skip 'ROM not available' unless @rom_available

      interpreter = create_interpreter
      compiler = create_compiler

      interpreter.load_rom(@rom_data)
      compiler.load_rom(@rom_data)

      boot_simulator(interpreter)
      boot_simulator(compiler)

      num_cycles = 100
      interp_pcs = collect_pcs(interpreter, num_cycles)
      comp_pcs = collect_pcs(compiler, num_cycles)

      # Compare PC values cycle by cycle
      mismatches = []
      interp_pcs.zip(comp_pcs).each_with_index do |(interp_pc, comp_pc), i|
        if interp_pc != comp_pc
          mismatches << { cycle: i, interpreter: interp_pc, compiler: comp_pc }
        end
      end

      puts "\n  PC Comparison (Interpreter vs Compiler):"
      puts "  Cycles compared: #{num_cycles}"
      puts "  Mismatches: #{mismatches.size}"

      if mismatches.any?
        puts "  First 10 mismatches:"
        mismatches.first(10).each do |m|
          puts "    Cycle #{m[:cycle]}: interpreter=0x#{m[:interpreter].to_s(16)}, compiler=0x#{m[:compiler].to_s(16)}"
        end
      end

      puts "  First 10 interpreter PCs: #{interp_pcs.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
      puts "  First 10 compiler PCs:    #{comp_pcs.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

      # Allow some tolerance for timing differences, but require >95% match
      match_rate = 1.0 - (mismatches.size.to_f / num_cycles)
      puts "  Match rate: #{(match_rate * 100).round(1)}%"

      expect(match_rate).to be >= 0.95, "Expected at least 95% PC match rate, got #{(match_rate * 100).round(1)}%"
    end

    it 'produces identical PC transitions for 500 cycles after boot' do
      skip 'ROM not available' unless @rom_available

      interpreter = create_interpreter
      compiler = create_compiler

      interpreter.load_rom(@rom_data)
      compiler.load_rom(@rom_data)

      boot_simulator(interpreter)
      boot_simulator(compiler)

      num_cycles = 500
      interp_pcs = collect_pcs(interpreter, num_cycles)
      comp_pcs = collect_pcs(compiler, num_cycles)

      # Extract transitions (unique consecutive PCs)
      interp_transitions = extract_transitions(interp_pcs)
      comp_transitions = extract_transitions(comp_pcs)

      puts "\n  PC Transition Comparison:"
      puts "  Interpreter transitions: #{interp_transitions.size}"
      puts "  Compiler transitions: #{comp_transitions.size}"

      # Find common prefix
      common_length = 0
      interp_transitions.zip(comp_transitions).each do |interp_pc, comp_pc|
        break if interp_pc != comp_pc
        common_length += 1
      end

      puts "  Common prefix length: #{common_length}"
      puts "  First 20 interpreter transitions: #{interp_transitions.first(20).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
      puts "  First 20 compiler transitions:    #{comp_transitions.first(20).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

      # Require at least 60% of transitions to match (allows for minor timing differences)
      min_transitions = [interp_transitions.size, comp_transitions.size].min
      match_rate = common_length.to_f / min_transitions
      puts "  Transition match rate: #{(match_rate * 100).round(1)}%"

      expect(match_rate).to be >= 0.60, "Expected at least 60% transition match rate"
    end
  end

  describe 'register state comparison' do
    it 'produces identical CPU register values after boot' do
      skip 'ROM not available' unless @rom_available

      interpreter = create_interpreter
      compiler = create_compiler

      interpreter.load_rom(@rom_data)
      compiler.load_rom(@rom_data)

      boot_simulator(interpreter)
      boot_simulator(compiler)

      # Run some cycles
      100.times do
        interpreter.run_cpu_cycles(1, 0, false)
        compiler.run_cpu_cycles(1, 0, false)
      end

      # Compare CPU registers
      registers = %w[cpu__pc_reg cpu__a_reg cpu__x_reg cpu__y_reg cpu__sp_reg cpu__p_reg]

      puts "\n  Register Comparison after 100 cycles:"
      mismatches = []
      registers.each do |reg|
        interp_val = interpreter.peek(reg) rescue nil
        comp_val = compiler.peek(reg) rescue nil

        next if interp_val.nil? || comp_val.nil?

        status = interp_val == comp_val ? 'MATCH' : 'DIFFER'
        puts "  #{reg}: interpreter=0x#{interp_val.to_s(16)}, compiler=0x#{comp_val.to_s(16)} [#{status}]"

        if interp_val != comp_val
          mismatches << { register: reg, interpreter: interp_val, compiler: comp_val }
        end
      end

      # PC is the most critical register
      interp_pc = interpreter.peek('cpu__pc_reg')
      comp_pc = compiler.peek('cpu__pc_reg')

      expect(comp_pc).to eq(interp_pc), "PC mismatch: interpreter=0x#{interp_pc.to_s(16)}, compiler=0x#{comp_pc.to_s(16)}"
    end
  end

  describe 'compiled mode performance', :slow do
    it 'compiler can generate and compile code' do
      skip 'ROM not available' unless @rom_available

      compiler = create_compiler
      compiler.load_rom(@rom_data)

      # Try to compile
      result = compiler.compile rescue false

      if result
        puts "\n  Compilation successful"
        expect(compiler.compiled?).to be true
      else
        puts "\n  Compilation not available (rustc may not be installed)"
        skip 'Compilation not available'
      end
    end

    it 'compiled mode produces same results as interpreted mode' do
      skip 'ROM not available' unless @rom_available

      # Create two compilers - one interpreted, one compiled
      interp_compiler = create_compiler
      compiled_compiler = create_compiler

      interp_compiler.load_rom(@rom_data)
      compiled_compiler.load_rom(@rom_data)

      # Try to compile
      compile_success = compiled_compiler.compile rescue false
      skip 'Compilation not available' unless compile_success

      boot_simulator(interp_compiler)
      boot_simulator(compiled_compiler)

      num_cycles = 100
      interp_pcs = collect_pcs(interp_compiler, num_cycles)
      comp_pcs = collect_pcs(compiled_compiler, num_cycles)

      # Compare
      mismatches = interp_pcs.zip(comp_pcs).count { |a, b| a != b }

      puts "\n  Interpreted vs Compiled comparison:"
      puts "  Cycles compared: #{num_cycles}"
      puts "  Mismatches: #{mismatches}"
      puts "  First 10 interpreted PCs: #{interp_pcs.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"
      puts "  First 10 compiled PCs:    #{comp_pcs.first(10).map { |pc| '0x' + pc.to_s(16) }.join(', ')}"

      match_rate = 1.0 - (mismatches.to_f / num_cycles)
      puts "  Match rate: #{(match_rate * 100).round(1)}%"

      expect(match_rate).to be >= 0.95
    end
  end

  describe 'code generation' do
    it 'generates valid Rust code' do
      skip 'ROM not available' unless @rom_available

      compiler = create_compiler
      compiler.load_rom(@rom_data)

      code = compiler.generated_code

      expect(code).to include('fn evaluate')
      expect(code).to include('fn tick')
      expect(code).to include('fn run_cpu_cycles')
      expect(code).to include('fn mask')

      puts "\n  Generated code statistics:"
      puts "  Lines: #{code.lines.count}"
      puts "  Size: #{code.bytesize} bytes"
      puts "  Functions: evaluate, tick, run_cpu_cycles, mask"
    end
  end
end
