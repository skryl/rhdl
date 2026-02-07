#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each { |r| r.load_rom(rom); r.reset }

cycle = 0
press_at = 20_000_000
start = 20_330_000
stop = 20_39200
addr = 0x01B8

while cycle < start
  step = [100_000, start - cycle, press_at - cycle].select { |x| x > 0 }.min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step
  if cycle == press_at
    c.inject_key(7)
    v.inject_key(7)
  end
end

prev_c = c.sim.read_wram(addr)
prev_v = v.send(:verilator_read_wram, addr)
puts "start cycle=#{cycle} c=#{'%02X' % prev_c} v=#{'%02X' % prev_v}"

while cycle < stop
  c.run_steps(1)
  v.run_steps(1)
  cycle += 1

  cv = c.sim.read_wram(addr)
  vv = v.send(:verilator_read_wram, addr)

  if cv != prev_c || vv != prev_v
    puts "cycle=#{cycle} wram[#{'%04X' % addr}] c=#{'%02X' % cv} v=#{'%02X' % vv} pc_c=#{'%04X' % (c.cpu_state[:pc] & 0xFFFF)} pc_v=#{'%04X' % (v.cpu_state[:pc] & 0xFFFF)}"
    prev_c = cv
    prev_v = vv
  end

  cdi = c.peek_output('gb_core__cpu_di') & 0xFF
  vdi = v.send(:verilator_peek, 'gb_core__cpu_di') & 0xFF
  if cdi != vdi
    puts "cpu_di diverge cycle=#{cycle} cdi=#{'%02X' % cdi} vdi=#{'%02X' % vdi} pc=#{'%04X' % (c.cpu_state[:pc] & 0xFFFF)} t=#{c.peek_output('gb_core__cpu__debug_t_state') & 0xFF} m=#{c.peek_output('gb_core__cpu__debug_m_cycle') & 0xFF}"
    break
  end
end
