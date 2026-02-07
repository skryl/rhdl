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
start = 20_294_480
stop = 20_294_560
addr = 0x01B8

while cycle < start
  step = [50_000, start - cycle, press_at - cycle].select { |x| x > 0 }.min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step
  if cycle == press_at
    c.inject_key(7)
    v.inject_key(7)
  end
end

rc = ->(n){ c.peek_output(n) rescue 0 }
rv = ->(n){ v.send(:verilator_peek, n) rescue 0 }

while cycle < stop
  c.run_steps(1)
  v.run_steps(1)
  cycle += 1

  cs = c.cpu_state
  vs = v.cpu_state
  cdi = rc.call('gb_core__cpu_di') & 0xFF
  vdi = rv.call('gb_core__cpu_di') & 0xFF
  t = rc.call('gb_core__cpu__debug_t_state') & 0xFF
  m = rc.call('gb_core__cpu__debug_m_cycle') & 0xFF
  irc = rc.call('gb_core__cpu__debug_ir') & 0xFF
  irv = rv.call('debug_ir') & 0xFF
  waddr = rc.call('gb_core__wram__address_a') & 0x7FFF
  wwren = rc.call('gb_core__wram__wren_a') & 1
  wdata = rc.call('gb_core__wram__data_a') & 0xFF
  valc = c.sim.read_wram(addr)
  valv = v.send(:verilator_read_wram, addr)

  puts "cy=#{cycle} pc_c=%04X pc_v=%04X t=%d m=%d ir_c=%02X ir_v=%02X a_c=%02X a_v=%02X di_c=%02X di_v=%02X wa=%04X we=%d wd=%02X mem_c=%02X mem_v=%02X" % [
    cs[:pc] & 0xFFFF, vs[:pc] & 0xFFFF, t, m, irc, irv, cs[:a] & 0xFF, vs[:a] & 0xFF,
    cdi, vdi, waddr, wwren, wdata, valc, valv
  ]
end
