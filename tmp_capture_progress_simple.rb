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

checkpoints = [
  500_000,
  2_000_000,
  5_000_000,
  20_000_000,
  40_000_000,
  60_000_000,
  80_000_000,
  100_000_000
]

checkpoints.each_with_index do |cyc, i|
  delta = cyc - r.cycle_count
  r.run_steps(delta) if delta > 0

  # press start around title, then release
  if cyc == 20_000_000
    r.inject_key(7)
  elsif cyc == 40_000_000
    r.release_key(7)
  end

  fb = r.read_framebuffer
  out = File.expand_path("tmp_prog_#{i}.ppm", __dir__)
  save_ppm(out, fb)
  st = r.cpu_state
  puts "saved #{out} cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X" % st[:pc]
end
