#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each{|r| r.load_rom(rom); r.reset }

cycle = 0
press_at = 20_000_000
start = 20_338_800
stop = 20_342_000

while cycle < start
  step = [100_000, start - cycle, press_at - cycle].select{|x| x > 0}.min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step
  if cycle == press_at
    c.inject_key(7)
    v.inject_key(7)
  end
end

readc = ->(n){ c.peek_output(n) rescue 0 }
readv = ->(n){ v.send(:verilator_peek, n) rescue 0 }

while cycle < stop
  c.run_steps(1)
  c.sim.evaluate  # extra settle every cycle
  v.run_steps(1)
  cycle += 1

  cs = c.cpu_state
  vs = v.cpu_state
  if %i[pc a f b c d e h l sp].any? { |k| (cs[k] & (k==:pc || k==:sp ? 0xFFFF : 0xFF)) != (vs[k] & (k==:pc || k==:sp ? 0xFFFF : 0xFF)) }
    puts "REG DIVERGE cycle=#{cycle} c_pc=%04X v_pc=%04X c_a=%02X v_a=%02X" % [cs[:pc]&0xFFFF, vs[:pc]&0xFFFF, cs[:a]&0xFF, vs[:a]&0xFF]
    break
  end

  cdi = readc.call('gb_core__cpu_di') & 0xFF
  vdi = readv.call('gb_core__cpu_di') & 0xFF
  if cdi != vdi
    puts "DI DIVERGE cycle=#{cycle} pc=%04X t=%d m=%d c_di=%02X v_di=%02X" % [cs[:pc]&0xFFFF, readc.call('gb_core__cpu__debug_t_state')&0xFF, readc.call('gb_core__cpu__debug_m_cycle')&0xFF, cdi, vdi]
    break
  end
end
puts "done at cycle=#{cycle}"
