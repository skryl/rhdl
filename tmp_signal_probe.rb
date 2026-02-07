#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

probe_signals = %w[
  lcd_on lcd_clkena lcd_vsync lcd_data_gb
  gb_core__video_unit__lcdc
  gb_core__video_unit__h_cnt
  gb_core__video_unit__h_div_cnt
  gb_core__video_unit__v_cnt
  gb_core__video_unit__pcnt
  gb_core__video_unit__mode
  gb_core__video_unit__mode_wire
  gb_core__video_unit__fetch_phase
  gb_core__video_unit__tile_num
  gb_core__video_unit__tile_data_lo
  gb_core__video_unit__tile_data_hi
  gb_core__video_unit__vram_addr
  gb_core__video_unit__vram_data
  gb_core__video_unit__vram_rd
  gb_core__vram_do
  gb_core__vram_data_ppu
  gb_core__vram_addr_ppu
  gb_core__vram_addr_cpu
  gb_core__vram_wren_cpu
  cart_rd cart_wr ext_bus_addr ext_bus_a15
]

p = ->(n){ r.send(:verilator_peek, n) rescue nil }

snap = ->(tag){
  puts "-- #{tag} cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X" % r.cpu_state[:pc]
  probe_signals.each do |s|
    v = p.call(s)
    puts "%30s = %s" % [s, v.nil? ? 'nil' : ("0x%X" % v)]
  end
}

# sample at reset+early
snap.call('after reset')

[1000, 5000, 20000, 100000, 300000, 600000].each do |n|
  r.run_steps(n)
  snap.call("+#{n}")
end
