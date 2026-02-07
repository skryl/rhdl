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
target = 20_350_000
addr = 0x01B8

while cycle < target
  step = [50_000, target - cycle, press_at - cycle].select { |x| x > 0 }.min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step

  if cycle == press_at
    c.inject_key(7)
    v.inject_key(7)
    puts "pressed at #{cycle} c=#{'%02X' % c.sim.read_wram(addr)} v=#{'%02X' % v.send(:verilator_read_wram, addr)}"
  end

  cv = c.sim.read_wram(addr)
  vv = v.send(:verilator_read_wram, addr)
  puts "cycle=#{cycle} c=#{'%02X' % cv} v=#{'%02X' % vv}" if (cycle >= press_at && (cycle - press_at) % 10_000 == 0)
end
