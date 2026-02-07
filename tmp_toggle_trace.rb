#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

p = ->(n){ r.send(:verilator_peek, n) rescue nil }

last = {}
%w[lcd_on lcd_clkena lcd_vsync gb_core__video_unit__lcdc gb_core__video_unit__h_cnt gb_core__video_unit__h_div_cnt gb_core__video_unit__v_cnt gb_core__video_unit__pcnt].each do |s|
  last[s] = p.call(s)
end

changes = Hash.new(0)

5_000_000.times do |i|
  r.run_steps(1)
  if i % 500_000 == 0
    st = r.cpu_state
    puts "i=#{i} cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X lcd_on=%d clken=%d vs=%d h=%d hd=%d v=%d pcnt=%d" % [
      st[:pc],
      p.call('lcd_on') || 0,
      p.call('lcd_clkena') || 0,
      p.call('lcd_vsync') || 0,
      p.call('gb_core__video_unit__h_cnt') || 0,
      p.call('gb_core__video_unit__h_div_cnt') || 0,
      p.call('gb_core__video_unit__v_cnt') || 0,
      p.call('gb_core__video_unit__pcnt') || 0
    ]
  end

  last.keys.each do |s|
    v = p.call(s)
    if v != last[s]
      changes[s] += 1
      last[s] = v
    end
  end
end

puts "changes:"
changes.each { |k,v| puts "#{k}=#{v}" }
