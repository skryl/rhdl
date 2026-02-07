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
start = 20_250_000
stop = 20_320_000
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

pc = ->(r){ r.cpu_state[:pc] & 0xFFFF }
val_c = c.sim.read_wram(addr)
val_v = v.send(:verilator_read_wram, addr)
puts "start cycle=#{cycle} c=#{'%02X' % val_c} v=#{'%02X' % val_v} pc_c=#{'%04X' % pc.call(c)} pc_v=#{'%04X' % pc.call(v)}"

while cycle < stop
  c.run_steps(1)
  v.run_steps(1)
  cycle += 1
  cv = c.sim.read_wram(addr)
  vv = v.send(:verilator_read_wram, addr)
  if cv != val_c || vv != val_v
    puts "change cycle=#{cycle} c=#{'%02X' % cv} v=#{'%02X' % vv} prev_c=#{'%02X' % val_c} prev_v=#{'%02X' % val_v} pc_c=#{'%04X' % pc.call(c)} pc_v=#{'%04X' % pc.call(v)}"
    val_c = cv
    val_v = vv
  end
end
