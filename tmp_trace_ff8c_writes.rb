#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# to story
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

# press start at story
r.inject_key(7)
release_at = r.cycle_count + 56_000

hits = 0
120_000.times do
  r.run_steps(1)
  r.release_key(7) if r.cycle_count == release_at

  addr = r.sim.peek('gb_core__cpu_addr') & 0xFFFF rescue 0
  mreq_n = r.sim.peek('gb_core__cpu__mreq_n') & 1 rescue 1
  wr_n = r.sim.peek('gb_core__cpu__wr_n') & 1 rescue 1
  next unless addr == 0xFF8C && mreq_n == 0 && wr_n == 0

  pc = r.cpu_state[:pc] & 0xFFFF
  a = r.cpu_state[:a] & 0xFF
  do_v = r.sim.peek('gb_core__cpu_do') & 0xFF rescue 0
  ff8b = r.sim.read_zpram(0x0B) & 0xFF rescue 0
  ff8c = r.sim.read_zpram(0x0C) & 0xFF rescue 0
  joy = r.sim.peek('joystick') & 0xFF rescue 0
  p54 = r.sim.peek('gb_core__joy_p54') & 0x3 rescue 0
  di = r.sim.peek('gb_core__cpu_di') & 0xFF rescue 0
  puts "cyc=#{r.cycle_count} pc=%04X A=%02X cpu_do=%02X di=%02X ff8b=%02X ff8c=%02X joy=%02X p54=%d" % [pc,a,do_v,di,ff8b,ff8c,joy,p54]
  hits += 1
  break if hits >= 40
end
puts "hits=#{hits}"
