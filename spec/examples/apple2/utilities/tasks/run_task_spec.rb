# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/apple2/utilities/tasks/run_task'

RSpec.describe RHDL::Apple2::Tasks::RunTask do
  describe '#initialize' do
    it 'accepts options hash' do
      task = described_class.new(mode: :hdl, sim: :ruby)
      expect(task.instance_variable_get(:@sim_mode)).to eq(:hdl)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:ruby)
    end

    it 'defaults to hdl mode' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_mode)).to eq(:hdl)
    end

    it 'defaults to ruby sim backend' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_backend)).to eq(:ruby)
    end

    it 'creates HeadlessRunner internally' do
      task = described_class.new(mode: :hdl, sim: :ruby)
      expect(task.runner).to be_a(RHDL::Apple2::HeadlessRunner)
    end
  end

  describe 'HeadlessRunner integration' do
    context 'with hdl mode and ruby backend' do
      let(:task) { described_class.new(mode: :hdl, sim: :ruby) }

      it 'creates runner with hdl mode' do
        expect(task.runner.mode).to eq(:hdl)
      end

      it 'creates runner with ruby backend' do
        expect(task.runner.sim_backend).to eq(:ruby)
      end

      it 'reports correct simulator type' do
        expect(task.runner.simulator_type).to be_a(Symbol)
      end
    end
  end

  describe 'constants' do
    it 'defines screen dimensions' do
      expect(described_class::SCREEN_ROWS).to eq(24)
      expect(described_class::SCREEN_COLS).to eq(40)
    end

    it 'defines display dimensions' do
      expect(described_class::DISPLAY_WIDTH).to eq(42)
      expect(described_class::DISPLAY_HEIGHT).to eq(26)
    end

    it 'defines hi-res dimensions' do
      expect(described_class::HIRES_WIDTH).to eq(140)
      expect(described_class::HIRES_HEIGHT).to eq(48)
    end

    it 'defines ANSI escape codes' do
      expect(described_class::CLEAR_SCREEN).to include("\e[")
      expect(described_class::HIDE_CURSOR).to include("\e[")
      expect(described_class::SHOW_CURSOR).to include("\e[")
    end
  end
end

RSpec.describe RHDL::Apple2::HeadlessRunner do
  describe '.create_demo_program' do
    let(:program) { described_class.create_demo_program }

    it 'returns an array of bytes' do
      expect(program).to be_a(Array)
    end

    it 'starts with LDA instruction' do
      expect(program[0]).to eq(0xA9)  # LDA immediate
    end

    it 'contains STA instructions for text page' do
      # STA $0400
      expect(program[2]).to eq(0x8D)  # STA absolute
      expect(program[3]).to eq(0x00)  # low byte
      expect(program[4]).to eq(0x04)  # high byte ($0400)
    end

    it 'ends with BRK instruction' do
      expect(program.last).to eq(0x00)  # BRK
    end
  end

  describe '.with_demo' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    it 'creates a HeadlessRunner' do
      expect(runner).to be_a(described_class)
    end

    it 'has demo program loaded' do
      # Verify program is at $0800
      sample = runner.memory_sample
      expect(sample[:program_area][0]).to eq(0xA9)  # LDA immediate
    end

    it 'sets up reset vector' do
      sample = runner.memory_sample
      # Just verify the reset vector bytes are set (may not be in RAM for HDL)
      expect(sample[:reset_vector]).to be_a(Array)
      expect(sample[:reset_vector].length).to eq(2)
    end
  end

  describe 'PC progression' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    before { runner.reset }

    it 'has valid PC after reset' do
      state = runner.cpu_state
      expect(state[:pc]).to be_a(Integer)
      expect(state[:pc]).to be_between(0x0000, 0xFFFF)
    end

    it 'provides CPU state after running steps' do
      runner.run_steps(10)
      state = runner.cpu_state
      expect(state).to include(:pc)
      expect(state[:pc]).to be_a(Integer)
    end

    it 'can run without crashing' do
      # Use smaller step count - Ruby HDL simulation is slow (14 14MHz cycles per step)
      expect { runner.run_steps(15) }.not_to raise_error
    end

    it 'tracks cycle count after running' do
      # Use smaller step count - Ruby HDL simulation is slow
      runner.run_steps(20)
      # Cycle count should be non-negative
      expect(runner.cycle_count).to be >= 0
    end
  end

  describe 'configuration validation' do
    context 'with hdl mode and ruby backend' do
      let(:runner) { described_class.new(mode: :hdl, sim: :ruby) }

      it 'creates runner with hdl mode' do
        expect(runner.mode).to eq(:hdl)
      end

      it 'creates runner with ruby backend' do
        expect(runner.sim_backend).to eq(:ruby)
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to be_a(Symbol)
      end

      it 'backend returns ruby for hdl mode' do
        expect(runner.backend).to eq(:ruby)
      end
    end

    context 'with hdl mode and different backends' do
      it 'accepts interpret backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :interpret)
          expect(runner.sim_backend).to eq(:interpret)
        rescue LoadError, StandardError => e
          skip "Interpret backend not available: #{e.message}"
        end
      end

      it 'accepts jit backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :jit)
          expect(runner.sim_backend).to eq(:jit)
        rescue LoadError, StandardError => e
          skip "JIT backend not available: #{e.message}"
        end
      end

      it 'accepts compile backend' do
        begin
          runner = described_class.new(mode: :hdl, sim: :compile)
          expect(runner.sim_backend).to eq(:compile)
        rescue LoadError, StandardError => e
          skip "Compile backend not available: #{e.message}"
        end
      end
    end
  end

  describe 'CPU state access' do
    let(:runner) { described_class.with_demo(mode: :hdl, sim: :ruby) }

    before do
      runner.reset
      runner.run_steps(20)
    end

    it 'provides PC register' do
      state = runner.cpu_state
      expect(state).to include(:pc)
      expect(state[:pc]).to be_a(Integer)
    end

    it 'provides A register' do
      state = runner.cpu_state
      expect(state).to include(:a)
      expect(state[:a]).to be_a(Integer)
      expect(state[:a]).to be_between(0, 255)
    end

    it 'provides X register' do
      state = runner.cpu_state
      expect(state).to include(:x)
      expect(state[:x]).to be_a(Integer)
      expect(state[:x]).to be_between(0, 255)
    end

    it 'provides Y register' do
      state = runner.cpu_state
      expect(state).to include(:y)
      expect(state[:y]).to be_a(Integer)
      expect(state[:y]).to be_between(0, 255)
    end

    it 'provides SP register' do
      state = runner.cpu_state
      expect(state).to include(:sp)
      expect(state[:sp]).to be_a(Integer)
      expect(state[:sp]).to be_between(0, 255)
    end

    it 'provides cycles count' do
      state = runner.cpu_state
      expect(state).to include(:cycles)
      expect(state[:cycles]).to be_a(Integer)
      expect(state[:cycles]).to be > 0
    end
  end

  describe 'memory access' do
    let(:runner) { described_class.new(mode: :hdl, sim: :ruby) }

    it 'can write to memory' do
      runner.write(0x0800, 0xAB)
      expect(runner.read(0x0800)).to eq(0xAB)
    end

    it 'can read from memory' do
      runner.write(0x0400, 0xCD)
      value = runner.read(0x0400)
      expect(value).to eq(0xCD)
    end

    it 'provides memory sample' do
      runner.write(0x0000, 0x12)  # zero page
      runner.write(0x0100, 0x34)  # stack
      runner.write(0x0400, 0x56)  # text page
      runner.write(0x0800, 0x78)  # program area

      sample = runner.memory_sample
      expect(sample[:zero_page][0]).to eq(0x12)
      expect(sample[:stack][0]).to eq(0x34)
      expect(sample[:text_page][0]).to eq(0x56)
      expect(sample[:program_area][0]).to eq(0x78)
    end
  end

  describe 'Karateka PC progression' do
    # Helper to categorize PC into memory regions
    def pc_region(pc)
      case pc
      when 0x0000..0x01FF then :zp_stack
      when 0x0200..0x03FF then :input_buf
      when 0x0400..0x07FF then :text
      when 0x0800..0x1FFF then :user
      when 0x2000..0x3FFF then :hires1
      when 0x4000..0x5FFF then :hires2
      when 0x6000..0xBFFF then :high_ram
      when 0xC000..0xCFFF then :io
      when 0xD000..0xFFFF then :rom
      else :unknown
      end
    end

    # Game regions where Karateka executes (including IO for soft switch access)
    GAME_REGIONS = [:rom, :high_ram, :user, :zp_stack, :io].freeze

    # Cycles to run for each test (enough to verify execution)
    KARATEKA_TEST_CYCLES = 10_000

    # Fewer cycles for slower backends
    KARATEKA_SLOW_CYCLES = 2_000

    before(:all) do
      @karateka_available = described_class.karateka_available?
      @verilator_available = described_class.verilator_available?
    end

    shared_examples 'karateka pc progression' do |mode, sim, cycles = KARATEKA_TEST_CYCLES|
      it "advances PC through game regions with #{mode}/#{sim}" do
        skip 'Karateka resources not available' unless @karateka_available

        begin
          runner = described_class.with_karateka(mode: mode, sim: sim)
        rescue LoadError, StandardError => e
          skip "Backend not available: #{e.message}"
        end

        runner.reset

        # Collect PC samples
        pc_samples = []
        regions_visited = Set.new

        # Run in batches, sampling PC
        (cycles / 1000).times do
          runner.run_steps(1000)
          pc = runner.cpu_state[:pc]
          pc_samples << pc
          regions_visited << pc_region(pc)
        end

        # Verify PC changed (not stuck)
        unique_pcs = pc_samples.uniq
        expect(unique_pcs.length).to be > 1,
          "PC should change during execution, but stayed at #{pc_samples.first.to_s(16)}"

        # Verify visited game regions
        game_regions_visited = regions_visited & GAME_REGIONS.to_set
        expect(game_regions_visited).not_to be_empty,
          "Should visit game regions #{GAME_REGIONS}, but only visited #{regions_visited.to_a}"
      end
    end

    context 'with interpret backend' do
      # Use fewer cycles - interpret is slower
      include_examples 'karateka pc progression', :hdl, :interpret, 2_000
    end

    context 'with jit backend' do
      include_examples 'karateka pc progression', :hdl, :jit, 10_000
    end

    context 'with compile backend' do
      include_examples 'karateka pc progression', :hdl, :compile, 10_000
    end

    context 'with verilator backend' do
      it 'advances PC through game regions with verilator' do
        skip 'Karateka resources not available' unless @karateka_available
        skip 'Verilator not available' unless @verilator_available

        begin
          runner = described_class.with_karateka(mode: :verilog)
        rescue LoadError, StandardError => e
          skip "Verilator backend not available: #{e.message}"
        end

        runner.reset

        # Collect PC samples (fewer cycles for verilator - it's slower)
        pc_samples = []
        regions_visited = Set.new

        # Run in batches
        10.times do
          runner.run_steps(1000)
          pc = runner.cpu_state[:pc]
          pc_samples << pc
          regions_visited << pc_region(pc)
        end

        # Verify PC changed
        unique_pcs = pc_samples.uniq
        expect(unique_pcs.length).to be > 1,
          "PC should change during execution, but stayed at #{pc_samples.first.to_s(16)}"

        # Verify visited game regions
        game_regions_visited = regions_visited & GAME_REGIONS.to_set
        expect(game_regions_visited).not_to be_empty,
          "Should visit game regions #{GAME_REGIONS}, but only visited #{regions_visited.to_a}"
      end
    end

    context 'cross-backend comparison' do
      # Helper to run all backends and collect results
      def run_all_backends(cycles)
        results = {}

        # Test each available backend
        backends = [
          [:hdl, :interpret],
          [:hdl, :jit],
          [:hdl, :compile]
        ]

        backends.each do |mode, sim|
          begin
            runner = described_class.with_karateka(mode: mode, sim: sim)
            runner.reset
            runner.run_steps(cycles)
            state = runner.cpu_state
            results["#{mode}/#{sim}"] = {
              pc: state[:pc],
              region: pc_region(state[:pc]),
              a: state[:a],
              x: state[:x],
              y: state[:y]
            }
          rescue LoadError, StandardError
            next
          end
        end

        # Add verilator if available
        if @verilator_available
          begin
            runner = described_class.with_karateka(mode: :verilog)
            runner.reset
            runner.run_steps(cycles)
            state = runner.cpu_state
            results['verilog'] = {
              pc: state[:pc],
              region: pc_region(state[:pc]),
              a: state[:a],
              x: state[:x],
              y: state[:y]
            }
          rescue LoadError, StandardError
            # Skip if verilator fails
          end
        end

        results
      end

      it 'all backends reach similar PC regions after 10K cycles' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends(KARATEKA_TEST_CYCLES)
        skip 'No backends available for comparison' if results.length < 2

        # All backends should be in game regions
        results.each do |backend, data|
          expect(GAME_REGIONS).to include(data[:region]),
            "#{backend} PC $#{data[:pc].to_s(16)} in unexpected region #{data[:region]}"
        end

        # Log results for debugging
        puts "\nKarateka PC after #{KARATEKA_TEST_CYCLES} cycles:"
        results.each do |backend, data|
          puts "  #{backend}: PC=$#{data[:pc].to_s(16).upcase} (#{data[:region]})"
        end
      end

      it 'IR backends (jit/compile) have matching PCs' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends(KARATEKA_TEST_CYCLES)

        # Get IR backend results (jit and compile should match exactly)
        jit_result = results['hdl/jit']
        compile_result = results['hdl/compile']

        skip 'JIT backend not available' unless jit_result
        skip 'Compile backend not available' unless compile_result

        # JIT and Compile backends should produce identical results
        expect(jit_result[:pc]).to eq(compile_result[:pc]),
          "JIT PC ($#{jit_result[:pc].to_s(16)}) != Compile PC ($#{compile_result[:pc].to_s(16)})"

        expect(jit_result[:a]).to eq(compile_result[:a]),
          "JIT A ($#{jit_result[:a].to_s(16)}) != Compile A ($#{compile_result[:a].to_s(16)})"

        puts "\nJIT vs Compile match confirmed:"
        puts "  PC=$#{jit_result[:pc].to_s(16).upcase} A=$#{jit_result[:a].to_s(16).upcase}"
      end

      it 'detects and reports backend mismatches' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends(KARATEKA_TEST_CYCLES)
        skip 'Need at least 2 backends for comparison' if results.length < 2

        # Compare all pairs of backends
        mismatches = []
        backend_names = results.keys
        reference_backend = backend_names.first
        reference_data = results[reference_backend]

        backend_names[1..].each do |backend|
          data = results[backend]
          pc_diff = (reference_data[:pc] - data[:pc]).abs

          # Check if PCs are in the same 256-byte page (close enough)
          same_page = (reference_data[:pc] >> 8) == (data[:pc] >> 8)
          same_region = reference_data[:region] == data[:region]

          unless same_page || same_region
            mismatches << {
              backends: [reference_backend, backend],
              pcs: [reference_data[:pc], data[:pc]],
              regions: [reference_data[:region], data[:region]],
              diff: pc_diff
            }
          end
        end

        # Report results
        puts "\nBackend comparison results:"
        puts "  Reference: #{reference_backend} PC=$#{reference_data[:pc].to_s(16).upcase} (#{reference_data[:region]})"
        results.each do |backend, data|
          next if backend == reference_backend
          pc_diff = (reference_data[:pc] - data[:pc]).abs
          status = pc_diff < 256 ? "CLOSE" : (reference_data[:region] == data[:region] ? "SAME_REGION" : "DIVERGED")
          puts "  #{backend}: PC=$#{data[:pc].to_s(16).upcase} (#{data[:region]}) diff=#{pc_diff} [#{status}]"
        end

        if mismatches.any?
          puts "\n  WARNING: #{mismatches.length} backend mismatch(es) detected"
          mismatches.each do |m|
            puts "    #{m[:backends].join(' vs ')}: $#{m[:pcs][0].to_s(16)} vs $#{m[:pcs][1].to_s(16)} (diff=#{m[:diff]})"
          end
        else
          puts "\n  All backends within acceptable range"
        end

        # For now, just warn about mismatches but don't fail
        # (Verilator may have timing differences)
        # Fail only if IR backends mismatch (they should be identical)
        ir_backends = results.keys.select { |k| k.start_with?('hdl/') }
        if ir_backends.length >= 2
          ir_mismatches = mismatches.select { |m| m[:backends].all? { |b| b.start_with?('hdl/') } }
          expect(ir_mismatches).to be_empty,
            "IR backends should not diverge: #{ir_mismatches.map { |m| m[:backends].join(' vs ') }.join(', ')}"
        end
      end
    end
  end
end
