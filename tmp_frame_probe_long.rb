#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

runner = RHDL::Examples::GameBoy::VerilatorRunner.new
runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
runner.reset

last_frame = runner.frame_count
frames = 0
max_iters = 200_000
iters = 0
last_cycles = runner.cycle_count
stalls = 0
pc_hist = Hash.new(0)

while frames < 300 && iters < max_iters
  runner.run_steps(1000)
  fc = runner.frame_count
  if fc > last_frame
    frames += (fc - last_frame)
    last_frame = fc
    state = runner.cpu_state
    pc = state[:pc]
    pc_hist[pc] += 1
    # detect no cycle progress impossible
  else
    stalls += 1
  end
  iters += 1
end

state = runner.cpu_state
puts "frames=#{frames} iters=#{iters} cycle=#{runner.cycle_count} final_pc=%04X stalls=#{stalls}" % state[:pc]
puts "top_pc="
pc_hist.sort_by{|_,c| -c}.first(20).each { |pc,c| puts "%04X %d" % [pc,c] }
