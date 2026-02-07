#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset
[500_000,2_000_000,5_000_000,20_000_000,30_000_000,40_000_000,50_000_000,60_000_000].each do |cyc|
  d = cyc - r.cycle_count
  r.run_steps(d)
  r.inject_key(7) if cyc == 20_000_000
  r.release_key(7) if cyc == 40_000_000
  s = r.cpu_state
  puts "cyc=#{cyc} frame=#{r.sim.frame_count} pc=%04X a=%02X f=%02X" % [s[:pc] & 0xFFFF, s[:a] & 0xFF, s[:f] & 0xFF]
end
