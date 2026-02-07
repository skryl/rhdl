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

# Wait for title loop then press Start for ~0.5s
r.run_steps(5_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)

wanted = [1,5,10,20,30,40,60,80,100,140,180,220]
idx = 0
last_fc = r.frame_count

while idx < wanted.length
  r.run_steps(1000)
  fc = r.frame_count
  next if fc <= last_fc
  ((last_fc + 1)..fc).each do |f|
    rel = f - wanted.first + 1
    next unless rel == wanted[idx]
    fb = r.read_framebuffer
    out = File.expand_path("tmp_start_f#{rel}.ppm", __dir__)
    save_ppm(out, fb)
    puts "saved #{out} frame=#{f} pc=%04X" % r.cpu_state[:pc]
    idx += 1
    break if idx >= wanted.length
  end
  last_fc = fc
end
