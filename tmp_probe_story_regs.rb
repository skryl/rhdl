#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# press start to skip title
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)

# run to story screen checkpoint
r.run_steps(8_000_000) # total 30M

names = %w[
  gb_core__video_unit__lcdc
  gb_core__video_unit__stat
  gb_core__video_unit__scx
  gb_core__video_unit__scy
  gb_core__video_unit__wx
  gb_core__video_unit__wy
  gb_core__video_unit__pcnt
  gb_core__video_unit__h_cnt
  gb_core__video_unit__h_div_cnt
  gb_core__video_unit__v_cnt
  gb_core__video_unit__fetch_phase
  gb_core__video_unit__tile_num
  gb_core__video_unit__tile_data_lo
  gb_core__video_unit__tile_data_hi
  gb_core__video_unit__tile_out_lo
  gb_core__video_unit__tile_out_hi
  gb_core__video_unit__vram_addr
  gb_core__video_unit__vram_data
  gb_core__video_unit__vram_rd
  gb_core__vram_addr_mux
  gb_core__vram_do
]

puts "cycles=#{r.cycle_count} frame=#{r.sim.frame_count}"
state = r.cpu_state
puts "pc=%04X a=%02X f=%02X" % [state[:pc] & 0xFFFF, state[:a] & 0xFF, state[:f] & 0xFF]

names.each do |n|
  begin
    v = r.sim.peek(n)
    puts "%s = 0x%X (%d)" % [n, v, v]
  rescue => e
    puts "%s = <na> (%s)" % [n, e.class]
  end
end
