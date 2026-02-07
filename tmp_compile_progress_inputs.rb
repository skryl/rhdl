#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

events = {
  20_000_000 => :press,
  22_000_000 => :release,
  55_000_000 => :press,
  56_000_000 => :release,
}

checkpoints = [20_000_000, 30_000_000, 40_000_000, 50_000_000, 60_000_000, 70_000_000]
cyc = 0
while cyc < checkpoints.max
  next_event = (events.keys + checkpoints).select { |x| x > cyc }.min
  step = [100_000, next_event - cyc].min
  r.run_steps(step)
  cyc += step

  case events[cyc]
  when :press
    r.inject_key(7)
    puts "event: press at #{cyc}"
  when :release
    r.release_key(7)
    puts "event: release at #{cyc}"
  end

  if checkpoints.include?(cyc)
    s = r.cpu_state
    puts "cp #{cyc} frame=#{r.sim.frame_count} pc=%04X a=%02X f=%02X" % [s[:pc]&0xFFFF, s[:a]&0xFF, s[:f]&0xFF]
  end
end
