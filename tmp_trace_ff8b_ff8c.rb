#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# move to story
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_000_000)

read_ff8b = -> { (r.sim.read_zpram(0x0B) rescue 0) & 0xFF }
read_ff8c = -> { (r.sim.read_zpram(0x0C) rescue 0) & 0xFF }

puts "start cyc=#{r.cycle_count} pc=%04X ff8b=%02X ff8c=%02X" % [r.cpu_state[:pc]&0xFFFF, read_ff8b.call, read_ff8c.call]

seq = [
  [10_000, false],
  [50_000, false],
  [2_000, true],
  [10_000, true],
  [50_000, true],
  [2_000, false],
  [10_000, false],
  [50_000, false],
  [100_000, false],
  [200_000, false]
]

seq.each do |delta, pressed|
  pressed ? r.inject_key(7) : r.release_key(7)
  r.run_steps(delta)
  puts "cyc=#{r.cycle_count} pressed=#{pressed} pc=%04X ff8b=%02X ff8c=%02X joy=%02X p54=%d" % [
    r.cpu_state[:pc]&0xFFFF, read_ff8b.call, read_ff8c.call, (r.sim.peek('joystick')&0xFF rescue 0), (r.sim.peek('gb_core__joy_p54')&0x3 rescue 0)
  ]
end
