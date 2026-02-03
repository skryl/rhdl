# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../examples/mos6502/utilities/tasks/run_task'

RSpec.describe MOS6502::Tasks::RunTask do
  describe '#initialize' do
    it 'accepts options hash' do
      task = described_class.new(mode: :isa, sim: :jit)
      expect(task.instance_variable_get(:@mode)).to eq(:isa)
      expect(task.instance_variable_get(:@sim_backend)).to eq(:jit)
    end

    it 'defaults to isa mode' do
      task = described_class.new
      expect(task.instance_variable_get(:@mode)).to eq(:isa)
    end

    it 'defaults to jit sim backend' do
      task = described_class.new
      expect(task.instance_variable_get(:@sim_backend)).to eq(:jit)
    end

    it 'creates HeadlessRunner internally' do
      task = described_class.new(mode: :isa)
      expect(task.runner).to be_a(MOS6502::HeadlessRunner)
    end
  end

  describe 'HeadlessRunner integration' do
    context 'with isa mode' do
      let(:task) { described_class.new(mode: :isa) }

      it 'creates runner with isa mode' do
        expect(task.runner.mode).to eq(:isa)
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

  describe 'speed calculation' do
    it 'calculates default speed for isa mode' do
      task = described_class.new(mode: :isa)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(17_030)
    end

    it 'calculates default speed for hdl interpret mode' do
      task = described_class.new(mode: :hdl, sim: :interpret)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(100)
    end

    it 'calculates default speed for hdl jit mode' do
      task = described_class.new(mode: :hdl, sim: :jit)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(5_000)
    end

    it 'calculates default speed for hdl compile mode' do
      task = described_class.new(mode: :hdl, sim: :compile)
      speed = task.send(:calculate_default_speed)
      expect(speed).to eq(10_000)
    end

    it 'calculates default speed for netlist mode' do
      begin
        task = described_class.new(mode: :netlist)
        speed = task.send(:calculate_default_speed)
        expect(speed).to eq(10)
      rescue RuntimeError => e
        skip "Netlist mode not implemented: #{e.message}"
      end
    end
  end
end

RSpec.describe MOS6502::HeadlessRunner do
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
    let(:runner) { described_class.with_demo(mode: :isa) }

    it 'creates a HeadlessRunner' do
      expect(runner).to be_a(described_class)
    end

    it 'has demo program loaded' do
      # Verify program is at $0800
      sample = runner.memory_sample
      expect(sample[:program_area][0]).to eq(0xA9)  # LDA immediate
    end

    it 'has reset vector set to $0800' do
      sample = runner.memory_sample
      reset_lo = sample[:reset_vector][0]
      reset_hi = sample[:reset_vector][1]
      reset_addr = (reset_hi << 8) | reset_lo
      expect(reset_addr).to eq(0x0800)
    end
  end

  describe 'PC progression' do
    let(:runner) { described_class.with_demo(mode: :isa) }

    before { runner.reset }

    it 'starts at reset vector address' do
      state = runner.cpu_state
      expect(state[:pc]).to eq(0x0800)
    end

    it 'advances PC after running steps' do
      initial_pc = runner.cpu_state[:pc]
      runner.run_steps(10)
      new_pc = runner.cpu_state[:pc]
      expect(new_pc).to be > initial_pc
    end

    it 'executes instructions and modifies memory' do
      # Run enough to execute the "HELLO" program
      runner.run_steps(50)

      # Check that 'H' was written to $0400
      sample = runner.memory_sample
      expect(sample[:text_page][0]).to eq(0xC8)  # 'H' with high bit
    end

    it 'tracks cycle count' do
      expect(runner.cycle_count).to eq(0)
      runner.run_steps(100)
      expect(runner.cycle_count).to be > 0
    end
  end

  describe 'configuration validation' do
    context 'with isa mode' do
      let(:runner) { described_class.new(mode: :isa) }

      it 'creates runner with isa mode' do
        expect(runner.mode).to eq(:isa)
      end

      it 'reports correct simulator type' do
        expect(runner.simulator_type).to be_a(Symbol)
      end

      it 'backend returns nil for isa mode' do
        expect(runner.backend).to be_nil
      end
    end

    context 'with hdl mode' do
      # Skip if HDL runner not available
      let(:runner) do
        begin
          described_class.new(mode: :hdl, sim: :jit)
        rescue LoadError, StandardError => e
          skip "HDL mode not available: #{e.message}"
        end
      end

      it 'creates runner with hdl mode' do
        expect(runner.mode).to eq(:hdl)
      end

      it 'reports jit backend' do
        expect(runner.backend).to eq(:jit)
      end
    end
  end

  describe 'CPU state access' do
    let(:runner) { described_class.with_demo(mode: :isa) }

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

    # Cycles to run for each test
    KARATEKA_TEST_CYCLES = 10_000

    before(:all) do
      @karateka_available = described_class.karateka_available?
      @verilator_available = described_class.verilator_available?
    end

    shared_examples 'karateka pc progression' do |mode, sim, cycles|
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

    context 'with isa backend' do
      include_examples 'karateka pc progression', :isa, :jit, 10_000
    end

    context 'with hdl/jit backend' do
      include_examples 'karateka pc progression', :hdl, :jit, 10_000
    end

    context 'with hdl/compile backend' do
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

        # Collect PC samples
        pc_samples = []
        regions_visited = Set.new

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
      # Sample interval for PC collection
      SAMPLE_INTERVAL = 500
      TOTAL_SAMPLES = 20

      # Helper to collect PC and opcode sequences from a backend
      def collect_sequences(runner, samples: TOTAL_SAMPLES, interval: SAMPLE_INTERVAL)
        runner.reset
        pc_sequence = []
        opcode_sequence = []

        samples.times do
          runner.run_steps(interval)
          pc = runner.cpu_state[:pc]
          pc_sequence << pc
          # Read opcode at current PC
          opcode = runner.read(pc) & 0xFF
          opcode_sequence << opcode
        end

        {
          pcs: pc_sequence,
          opcodes: opcode_sequence,
          final_pc: pc_sequence.last
        }
      end

      # Check if backend is ISA level (different abstraction, may have timing differences)
      def isa_backend?(name)
        name.start_with?('isa')
      end

      # Check if backend is HDL level (should be cycle-accurate)
      def hdl_backend?(name)
        name.start_with?('hdl') || name == 'verilog'
      end

      # Helper to run all backends and collect sequences
      def run_all_backends_with_sequences(samples: TOTAL_SAMPLES, interval: SAMPLE_INTERVAL)
        results = {}

        backends = [
          [:isa, :jit],
          [:hdl, :jit],
          [:hdl, :compile]
        ]

        backends.each do |mode, sim|
          begin
            runner = described_class.with_karateka(mode: mode, sim: sim)
            results["#{mode}/#{sim}"] = collect_sequences(runner, samples: samples, interval: interval)
          rescue LoadError, StandardError
            next
          end
        end

        # Add verilator if available
        if @verilator_available
          begin
            runner = described_class.with_karateka(mode: :verilog)
            results['verilog'] = collect_sequences(runner, samples: samples, interval: interval)
          rescue LoadError, StandardError
            # Skip if verilator fails
          end
        end

        results
      end

      it 'all HDL backends have identical PC sequences' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends_with_sequences
        hdl_results = results.select { |k, _| hdl_backend?(k) }
        skip 'No HDL backends available for comparison' if hdl_results.length < 2

        backend_names = hdl_results.keys
        reference = backend_names.first
        ref_pcs = hdl_results[reference][:pcs]

        puts "\nPC sequence comparison (HDL backends):"
        puts "  Reference: #{reference}"
        puts "    PCs: #{ref_pcs.map { |pc| '$' + pc.to_s(16).upcase }.join(', ')}"

        backend_names[1..].each do |backend|
          pcs = hdl_results[backend][:pcs]
          puts "  #{backend}:"
          puts "    PCs: #{pcs.map { |pc| '$' + pc.to_s(16).upcase }.join(', ')}"

          # HDL backends should have identical PC sequences
          expect(pcs).to eq(ref_pcs),
            "#{backend} PC sequence differs from #{reference}"
        end
      end

      it 'all HDL backends have identical opcode sequences' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends_with_sequences
        hdl_results = results.select { |k, _| hdl_backend?(k) }
        skip 'No HDL backends available for comparison' if hdl_results.length < 2

        backend_names = hdl_results.keys
        reference = backend_names.first
        ref_opcodes = hdl_results[reference][:opcodes]

        puts "\nOpcode sequence comparison (HDL backends):"
        puts "  Reference: #{reference}"
        puts "    Opcodes: #{ref_opcodes.map { |op| '$' + op.to_s(16).upcase.rjust(2, '0') }.join(', ')}"

        backend_names[1..].each do |backend|
          opcodes = hdl_results[backend][:opcodes]
          puts "  #{backend}:"
          puts "    Opcodes: #{opcodes.map { |op| '$' + op.to_s(16).upcase.rjust(2, '0') }.join(', ')}"

          # HDL backends should have identical opcode sequences
          expect(opcodes).to eq(ref_opcodes),
            "#{backend} opcode sequence differs from #{reference}"
        end
      end

      it 'detects first divergence point between backends' do
        skip 'Karateka resources not available' unless @karateka_available

        results = run_all_backends_with_sequences
        skip 'Need at least 2 backends for comparison' if results.length < 2

        backend_names = results.keys
        divergences = []

        backend_names.combination(2).each do |a, b|
          pcs_a = results[a][:pcs]
          pcs_b = results[b][:pcs]
          opcodes_a = results[a][:opcodes]
          opcodes_b = results[b][:opcodes]

          # Find first PC divergence
          first_pc_diff = pcs_a.zip(pcs_b).find_index { |pa, pb| pa != pb }

          # Find first opcode divergence
          first_op_diff = opcodes_a.zip(opcodes_b).find_index { |oa, ob| oa != ob }

          # Determine if this is an ISA vs HDL comparison (warn only)
          is_isa_comparison = isa_backend?(a) || isa_backend?(b)

          divergences << {
            backends: [a, b],
            first_pc_diff: first_pc_diff,
            first_op_diff: first_op_diff,
            pcs_at_diff: first_pc_diff ? [pcs_a[first_pc_diff], pcs_b[first_pc_diff]] : nil,
            ops_at_diff: first_op_diff ? [opcodes_a[first_op_diff], opcodes_b[first_op_diff]] : nil,
            is_isa_comparison: is_isa_comparison
          }
        end

        puts "\nDivergence analysis:"
        divergences.each do |d|
          if d[:first_pc_diff].nil? && d[:first_op_diff].nil?
            puts "  #{d[:backends].join(' vs ')}: IDENTICAL"
          else
            status = d[:is_isa_comparison] ? "DIVERGED (ISA - warning only)" : "DIVERGED"
            puts "  #{d[:backends].join(' vs ')}: #{status}"
            if d[:first_pc_diff]
              puts "    First PC diff at sample #{d[:first_pc_diff]}: $#{d[:pcs_at_diff][0].to_s(16).upcase} vs $#{d[:pcs_at_diff][1].to_s(16).upcase}"
            end
            if d[:first_op_diff]
              puts "    First opcode diff at sample #{d[:first_op_diff]}: $#{d[:ops_at_diff][0].to_s(16).upcase.rjust(2, '0')} vs $#{d[:ops_at_diff][1].to_s(16).upcase.rjust(2, '0')}"
            end
          end
        end

        # Only fail on HDL backend divergences (ISA divergence is a warning)
        hdl_divergences = divergences.reject { |d| d[:is_isa_comparison] }
        hdl_divergences.each do |d|
          expect(d[:first_pc_diff]).to be_nil,
            "#{d[:backends].join(' vs ')} PC sequences diverged at sample #{d[:first_pc_diff]}"
          expect(d[:first_op_diff]).to be_nil,
            "#{d[:backends].join(' vs ')} opcode sequences diverged at sample #{d[:first_op_diff]}"
        end
      end
    end
  end
end
