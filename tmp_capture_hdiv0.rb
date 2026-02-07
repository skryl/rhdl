#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

PALETTE = {
  0 => [155,188,15],
  1 => [139,172,15],
  2 => [48,98,48],
  3 => [15,56,15]
}.freeze

def save_ppm(path, fb)
  h = fb.length
  w = fb.first.length
  File.open(path, 'wb') do |f|
    f.write("P6\n#{w} #{h}\n255\n")
    h.times do |y|
      w.times do |x|
        r,g,b = PALETTE.fetch(fb[y][x] & 0x3)
        f.write([r,g,b].pack('C3'))
      end
    end
  end
end

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

fb = Array.new(144) { Array.new(160, 0) }
last_frame = r.frame_count
saved = 0

while saved < 12
  r.run_steps(1)
  lcd_on = r.send(:verilator_peek, 'lcd_on')
  clken = r.send(:verilator_peek, 'lcd_clkena')
  hd = r.send(:verilator_peek, 'gb_core__video_unit__h_div_cnt')
  next unless lcd_on == 1 && clken == 1 && hd == 0

  y = r.send(:verilator_peek, 'gb_core__video_unit__v_cnt')
  x = r.send(:verilator_peek, 'gb_core__video_unit__pcnt')
  px = r.send(:verilator_peek, 'lcd_data_gb') & 0x3

  if y < 144 && x < 160
    fb[y][x] = px
  end

  fc = r.frame_count
  if fc > last_frame
    out = File.expand_path("tmp_hdiv0_f#{fc}.ppm", __dir__)
    save_ppm(out, fb)
    puts "saved #{out} pc=%04X" % r.cpu_state[:pc]
    saved += 1
    last_frame = fc
    fb = Array.new(144) { Array.new(160, 0) }
  end
end
