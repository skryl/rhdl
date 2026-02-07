#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

p = ->(n){ r.send(:verilator_peek, n) rescue nil }

[300_000, 1_000_000, 1_500_000, 2_000_000, 3_000_000].each do |target|
  delta = target - r.cycle_count
  r.run_steps(delta) if delta > 0
  st = r.cpu_state
  puts "cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X" % st[:pc]
  %w[lcd_on lcd_clkena lcd_vsync gb_core__video_unit__lcdc gb_core__video_unit__h_cnt gb_core__video_unit__h_div_cnt gb_core__video_unit__v_cnt gb_core__video_unit__pcnt gb_core__video_unit__mode gb_core__video_unit__mode_wire gb_core__video_unit__fetch_phase gb_core__video_unit__tile_num gb_core__video_unit__tile_data_lo gb_core__video_unit__tile_data_hi gb_core__video_unit__vram_addr gb_core__video_unit__vram_data gb_core__vram_data_ppu gb_core__vram_do gb_core__vram_addr_ppu].each do |s|
    v = p.call(s)
    puts "  %-35s %s" % [s, v.nil? ? 'nil' : ("0x%X" % v)]
  end
end
