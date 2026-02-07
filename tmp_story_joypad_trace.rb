#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# pass title
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

puts "before story press: cyc=#{r.cycle_count} frame=#{r.sim.frame_count} pc=%04X" % [r.cpu_state[:pc] & 0xFFFF]

# press start on story
r.inject_key(7)

2000.times do |i|
  r.run_steps(1)
  next unless i < 300 || (i % 100 == 0)
  pc = r.cpu_state[:pc] & 0xFFFF
  joy = r.sim.peek('joystick') & 0xFF rescue 0
  joy_p54 = r.sim.peek('gb_core__joy_p54') & 0x3 rescue 0
  joy_din = r.sim.peek('gb_core__joy_din') & 0xF rescue 0
  joy_prev = r.sim.peek('gb_core__joy_din_prev') & 0xF rescue 0
  joy_samp = r.sim.peek('gb_core__joy_din_sampled') & 0xF rescue 0
  joy_irq = r.sim.peek('gb_core__joypad_irq') & 1 rescue 0
  ifr = r.sim.peek('gb_core__if_r') & 0x1F rescue 0
  ie = r.sim.peek('gb_core__ie_r') & 0x1F rescue 0
  puts "%04d pc=%04X joy=%02X p54=%X din=%X prev=%X samp=%X irq=%d IF=%02X IE=%02X" % [i, pc, joy, joy_p54, joy_din, joy_prev, joy_samp, joy_irq, ifr, ie]
end

r.release_key(7)
puts "after release pc=%04X" % [r.cpu_state[:pc] & 0xFFFF]
