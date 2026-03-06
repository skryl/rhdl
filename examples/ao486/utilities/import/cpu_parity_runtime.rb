# frozen_string_literal: true

require 'rhdl/codegen'
require_relative 'cpu_parity_package'

module RHDL
  module Examples
    module AO486
      module Import
        # Runtime helper for the parity-oriented imported AO486 CPU package.
        #
        # This runner currently targets the IR JIT backend and drives the
        # CPU-top Avalon fetch port with a deterministic no-wait burst model.
        # It is intentionally scoped to the parity-package flow where
        # `cache_disable=1`.
        class CpuParityRuntime
          RESET_VECTOR_PHYSICAL = 0xFFFF0
          DEFAULT_FETCH_BURST_BEATS = 8
          DEFAULT_MAX_CYCLES = 200
          STARTUP_CS_BASE = 0xF0000

          attr_reader :sim, :memory

          StepEvent = Struct.new(:cycle, :eip, :consumed, :bytes, keyword_init: true)

          def self.build_from_cleaned_mlir(mlir_text)
            parity = CpuParityPackage.from_cleaned_mlir(mlir_text)
            raise ArgumentError, Array(parity[:diagnostics]).join("\n") unless parity[:success]

            flat = RHDL::Codegen::CIRCT::Flatten.to_flat_module(parity.fetch(:package), top: 'ao486')
            ir_json = RHDL::Sim::Native::IR.sim_json(flat, backend: :jit)
            sim = RHDL::Sim::Native::IR::Simulator.new(ir_json, backend: :jit)

            new(sim: sim)
          end

          def initialize(sim:)
            @sim = sim
            @memory = Hash.new(0)
            @burst = nil
            @previous_trace_key = nil
            apply_default_inputs
          end

          def load_bytes(base, bytes)
            Array(bytes).each_with_index do |byte, idx|
              @memory[base + idx] = byte.to_i & 0xFF
            end
          end

          def reset!
            @burst = nil
            @previous_trace_key = nil
            apply_default_inputs
            @sim.poke('clk', 0)
            @sim.poke('rst_n', 0)
            @sim.evaluate
            @sim.poke('clk', 1)
            @sim.tick
          end

          def step(cycle)
            drive_read_data_inputs

            @sim.poke('clk', 0)
            @sim.poke('rst_n', 1)
            @sim.evaluate

            @sim.poke('clk', 1)
            @sim.poke('rst_n', 1)
            @sim.tick

            advance_read_burst
            arm_read_burst_if_needed

            capture_step_event(cycle)
          end

          def run(max_cycles: DEFAULT_MAX_CYCLES)
            reset!
            events = []

            max_cycles.times do |cycle|
              event = step(cycle)
              events << event if event
            end

            events
          end

          def run_fetch_words(max_cycles: DEFAULT_MAX_CYCLES)
            reset!
            words = []

            max_cycles.times do |cycle|
              step(cycle)
              words << @sim.peek('avm_readdata') if @sim.peek('avm_readdatavalid') == 1
            end

            words
          end

          private

          def apply_default_inputs
            {
              'a20_enable' => 1,
              'cache_disable' => 1,
              'interrupt_do' => 0,
              'interrupt_vector' => 0,
              'avm_waitrequest' => 0,
              'avm_readdatavalid' => 0,
              'avm_readdata' => 0,
              'dma_address' => 0,
              'dma_16bit' => 0,
              'dma_write' => 0,
              'dma_writedata' => 0,
              'dma_read' => 0,
              'io_read_data' => 0,
              'io_read_done' => 0,
              'io_write_done' => 0
            }.each do |name, value|
              @sim.poke(name, value)
            end
          end

          def drive_read_data_inputs
            if @burst && @burst[:started]
              addr = @burst[:base] + (@burst[:beat_index] * 4)
              @sim.poke('avm_readdatavalid', 1)
              @sim.poke('avm_readdata', little_endian_word(addr))
            else
              @sim.poke('avm_readdatavalid', 0)
              @sim.poke('avm_readdata', 0)
            end
          end

          def little_endian_word(addr)
            4.times.reduce(0) do |acc, idx|
              acc | ((@memory[addr + idx] || 0) << (8 * idx))
            end
          end

          def advance_read_burst
            return unless @burst

            if @burst[:started]
              @burst[:beat_index] += 1
              @burst = nil if @burst[:beat_index] >= @burst[:beats_total]
            else
              @burst[:started] = true
            end
          end

          def arm_read_burst_if_needed
            return unless @burst.nil?
            return unless @sim.peek('avm_read') == 1

            @burst = {
              base: @sim.peek('avm_address') << 2,
              beat_index: 0,
              beats_total: DEFAULT_FETCH_BURST_BEATS,
              started: false
            }
          end

          def capture_step_event(cycle)
            trace_key = [@sim.peek('trace_wr_eip'), @sim.peek('trace_wr_consumed')]
            return nil if trace_key == [0, 0]
            return nil if trace_key == @previous_trace_key

            @previous_trace_key = trace_key
            consumed = trace_key[1]
            start_eip = trace_key[0] - consumed

            StepEvent.new(
              cycle: cycle,
              eip: start_eip,
              consumed: consumed,
              bytes: bytes_at(STARTUP_CS_BASE + start_eip, consumed)
            )
          end

          def bytes_at(addr, length)
            Array.new(length) { |idx| @memory[addr + idx] || 0 }
          end
        end
      end
    end
  end
end
