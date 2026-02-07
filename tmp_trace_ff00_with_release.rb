#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# First start to get to story
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

# story press
r.inject_key(7)
release_at = r.cycle_count + 56_000

count = 0
while count < 180
  r.run_steps(1)
  r.release_key(7) if r.cycle_count == release_at

  addr = r.sim.peek('gb_core__cpu_addr') & 0xFFFF rescue 0
  mreq_n = r.sim.peek('gb_core__cpu__mreq_n') & 1 rescue 1
  next unless addr == 0xFF00 && mreq_n == 0

  wr_n = r.sim.peek('gb_core__cpu__wr_n') & 1 rescue 1
  rd_n = r.sim.peek('gb_core__cpu__rd_n') & 1 rescue 1
  p54 = r.sim.peek('gb_core__joy_p54') & 0x3 rescue 0
  di = r.sim.peek('gb_core__cpu_di') & 0xFF rescue 0
  joy = r.sim.peek('joystick') & 0xFF rescue 0
  pc = r.cpu_state[:pc] & 0xFFFF
  puts "cyc=#{r.cycle_count} pc=%04X wr_n=%d rd_n=%d p54=%d di=%02X joy=%02X" % [pc, wr_n, rd_n, p54, di, joy]
  count += 1
end
