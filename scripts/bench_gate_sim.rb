#!/usr/bin/env ruby

require_relative '../lib/rhdl'

lanes = (ENV['RHDL_BENCH_LANES'] || '64').to_i
cycles = (ENV['RHDL_BENCH_CYCLES'] || '100000').to_i

not_gate = RHDL::HDL::NotGate.new('inv')
dff = RHDL::HDL::DFlipFlop.new('reg')

RHDL::HDL::SimComponent.connect(dff.outputs[:q], not_gate.inputs[:a])
RHDL::HDL::SimComponent.connect(not_gate.outputs[:y], dff.inputs[:d])

sim = RHDL::Gates.gate_level([not_gate, dff], backend: :cpu, lanes: lanes, name: 'bench_toggle')

sim.poke('reg.rst', 0)
sim.poke('reg.en', (1 << lanes) - 1)

start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
cycles.times { sim.tick }
finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

elapsed = finish - start
rate = cycles / elapsed
puts "Gate-level CPU sim: #{cycles} cycles in #{format('%.3f', elapsed)}s (#{format('%.2f', rate)} cycles/s)"
