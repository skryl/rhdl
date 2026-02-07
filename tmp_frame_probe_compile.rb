#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

runner = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
runner.reset

sim = runner.sim
last_frame = sim.frame_count
frames = 0
iters = 0
max_iters = 300_000
pc_hist = Hash.new(0)

while frames < 300 && iters < max_iters
  runner.run_steps(1000)
  fc = sim.frame_count
  if fc > last_frame
    frames += (fc - last_frame)
    last_frame = fc
    st = runner.cpu_state
    pc_hist[st[:pc]] += 1
  end
  iters += 1
end
st = runner.cpu_state
puts "frames=#{frames} iters=#{iters} cycles=#{runner.cycle_count} final_pc=%04X" % st[:pc]
pc_hist.sort_by{|_,c| -c}.first(20).each { |pc,c| puts "%04X %d" % [pc,c] }
