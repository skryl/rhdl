#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

p = ->(n){ r.send(:verilator_peek, n) rescue nil }

[300_000, 1_000_000, 1_500_000, 2_000_000].each do |target|
  r.run_steps(target - r.cycle_count)
  st = r.cpu_state
  puts "cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X" % st[:pc]
  %w[lcd_on lcd_clkena lcd_vsync gb_core__video_unit__lcdc gb_core__video_unit__scx gb_core__video_unit__scy gb_core__video_unit__bgp gb_core__video_unit__wx gb_core__video_unit__wy].each do |s|
    v = p.call(s)
    puts "  %-30s %s" % [s, v.nil? ? 'nil' : ("0x%X" % v)]
  end

  # Read some live VRAM tile/map bytes
  [0x0000,0x0001,0x0002,0x0010,0x0100,0x1800,0x1801,0x1802,0x1810].each do |a|
    v = r.send(:verilator_read_vram, a)
    puts "  VRAM[%04X]=%02X" % [a, v]
  end
end
