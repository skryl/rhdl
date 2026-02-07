#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# reach story screen
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

# sample for ~2 frames
sample_every = 2000
samples = 120

puts "start cycles=#{r.cycle_count} frame=#{r.sim.frame_count}"

samples.times do |i|
  r.run_steps(sample_every)
  if_r = r.sim.peek('gb_core__if_r') & 0x1F rescue 0
  ie_r = r.sim.peek('gb_core__ie_r') & 0x1F rescue 0
  irq_n = r.sim.peek('gb_core__irq_n') & 1 rescue 0
  joy_irq = r.sim.peek('gb_core__joypad_irq') & 1 rescue 0
  video_irq = r.sim.peek('gb_core__video_irq') & 1 rescue 0
  vblank_irq = r.sim.peek('gb_core__vblank_irq') & 1 rescue 0
  timer_irq = r.sim.peek('gb_core__timer_irq') & 1 rescue 0
  serial_irq = r.sim.peek('gb_core__serial_irq') & 1 rescue 0
  pc = r.cpu_state[:pc] & 0xFFFF
  puts "%03d cyc=%d f=%d pc=%04X IF=%02X IE=%02X irq_n=%d src[v:%d vv:%d t:%d s:%d j:%d]" % [
    i, r.cycle_count, r.sim.frame_count, pc, if_r, ie_r, irq_n, video_irq, vblank_irq, timer_irq, serial_irq, joy_irq
  ]
end
