#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

names = %w[
  clk_sys
  ce ce_n ce_2x
  gb_core__ce gb_core__ce_n gb_core__ce_2x
  gb_core__video_unit__ce gb_core__video_unit__ce_cpu gb_core__video_unit__ce_n
  gb_core__video_unit__lcdc gb_core__video_unit__h_cnt gb_core__video_unit__h_div_cnt gb_core__video_unit__v_cnt gb_core__video_unit__pcnt
  gb_core__cpu__debug_pc
]

p = ->(n){ r.send(:verilator_peek, n) rescue nil }

[0, 100_000, 500_000, 1_000_000, 1_500_000, 2_000_000].each do |target|
  delta = target - r.cycle_count
  r.run_steps(delta) if delta > 0
  puts "-- cyc=#{r.cycle_count} frame=#{r.frame_count}"
  names.each do |n|
    v = p.call(n)
    puts "%35s = %s" % [n, v.nil? ? 'nil' : ("0x%X" % v)]
  end
end
