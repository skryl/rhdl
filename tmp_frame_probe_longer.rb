#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

runner = RHDL::Examples::GameBoy::VerilatorRunner.new
runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
runner.reset

last_frame = runner.frame_count
frames = 0
iters = 0
max_iters = 1_000_000
last_frame_hit_iter = 0

while frames < 1200 && iters < max_iters
  runner.run_steps(1000)
  fc = runner.frame_count
  if fc > last_frame
    frames += (fc - last_frame)
    last_frame = fc
    last_frame_hit_iter = iters
    if (frames % 100).zero?
      st = runner.cpu_state
      puts "f=#{frames} cyc=#{runner.cycle_count} pc=%04X" % st[:pc]
    end
  elsif iters - last_frame_hit_iter > 5000
    puts "stalled_at_iter=#{iters} frame=#{frames} cyc=#{runner.cycle_count}"
    break
  end
  iters += 1
end
st = runner.cpu_state
puts "done frames=#{frames} iters=#{iters} cycle=#{runner.cycle_count} pc=%04X" % st[:pc]
