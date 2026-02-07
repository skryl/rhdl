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

counts = Hash.new(0)
prev = {}

200_000.times do
  r.run_steps(1)
  {
    'video_irq' => 'gb_core__video_irq',
    'vblank_irq' => 'gb_core__vblank_irq',
    'timer_irq' => 'gb_core__timer_irq',
    'serial_irq' => 'gb_core__serial_irq',
    'joypad_irq' => 'gb_core__joypad_irq',
    'irq_ack' => 'gb_core__irq_ack',
    'irq_n' => 'gb_core__irq_n'
  }.each do |name, sig|
    v = (r.sim.peek(sig) & 1) rescue 0
    counts["#{name}_high"] += 1 if v == 1
    if prev.key?(name) && prev[name] == 0 && v == 1
      counts["#{name}_rise"] += 1
    end
    prev[name] = v
  end
end

puts "cycles=#{r.cycle_count} frame=#{r.sim.frame_count} pc=%04X" % [r.cpu_state[:pc] & 0xFFFF]
counts.sort.each { |k,v| puts "%s=%d" % [k,v] }
puts "IF=%02X IE=%02X" % [r.sim.peek('gb_core__if_r') & 0x1F, r.sim.peek('gb_core__ie_r') & 0x1F]
