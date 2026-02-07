#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

v = RHDL::Examples::GameBoy::VerilatorRunner.new
v.load_rom(File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__)))
v.reset

names = %w[ce gb_core__ce gb_core__cpu_clken debug_clken]
mins = Hash.new(1)
maxs = Hash.new(0)
counts_low = Hash.new(0)
cycle = 0
while cycle < 1_000_000
  step = 1000
  v.run_steps(step)
  cycle += step
  names.each do |n|
    val = (v.send(:verilator_peek, n) rescue 0) & 1
    mins[n] = [mins[n], val].min
    maxs[n] = [maxs[n], val].max
    counts_low[n] += 1 if val == 0
  end
end
names.each { |n| puts "#{n}: min=#{mins[n]} max=#{maxs[n]} low_samples=#{counts_low[n]}" }
