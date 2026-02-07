#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# advance to stable logo state
r.run_steps(2_000_000)

target_line = 80
samples = []
tries = 0
while samples.length < 500 && tries < 5_000_000
  r.run_steps(1)
  y = r.send(:verilator_peek, 'gb_core__video_unit__v_cnt')
  next unless y == target_line
  h = r.send(:verilator_peek, 'gb_core__video_unit__h_cnt')
  hd = r.send(:verilator_peek, 'gb_core__video_unit__h_div_cnt')
  pcnt = r.send(:verilator_peek, 'gb_core__video_unit__pcnt')
  clken = r.send(:verilator_peek, 'lcd_clkena')
  mode3 = r.send(:verilator_peek, 'gb_core__video_unit__oam_eval') # placeholder not mode3 directly
  samples << [h, hd, pcnt, clken]
  tries += 1
end

# Print transitions and unique counts
puts "samples=#{samples.length}"
ones = samples.count{|s| s[3]==1}
puts "clken ones=#{ones}"
puts "first 120:"
samples.first(120).each_with_index do |(h,hd,pc,ck),i|
  puts "%3d h=%3d hd=%d pc=%3d ck=%d" % [i,h,hd,pc,ck]
end
