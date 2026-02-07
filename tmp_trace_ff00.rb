#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

count = 0
50_000.times do
  r.run_steps(1)
  addr = r.sim.peek('gb_core__cpu_addr') & 0xFFFF rescue 0
  mreq_n = r.sim.peek('gb_core__cpu__mreq_n') & 1 rescue 1
  wr_n = r.sim.peek('gb_core__cpu__wr_n') & 1 rescue 1
  rd_n = r.sim.peek('gb_core__cpu__rd_n') & 1 rescue 1
  if addr == 0xFF00 && mreq_n == 0
    pc = r.cpu_state[:pc] & 0xFFFF
    cpu_do = r.sim.peek('gb_core__cpu_do') & 0xFF rescue 0
    cpu_di = r.sim.peek('gb_core__cpu_di') & 0xFF rescue 0
    p54 = r.sim.peek('gb_core__joy_p54') & 0x3 rescue 0
    puts "cyc=#{r.cycle_count} pc=%04X wr_n=%d rd_n=%d do=%02X di=%02X p54=%d" % [pc, wr_n, rd_n, cpu_do, cpu_di, p54]
    count += 1
    break if count >= 30
  end
end
puts "done count=#{count}"
