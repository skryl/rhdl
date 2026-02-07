#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

OUT_DIR = File.expand_path('tmp_frames_baseline', __dir__)
Dir.mkdir(OUT_DIR) unless Dir.exist?(OUT_DIR)

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

runner = RHDL::Examples::GameBoy::VerilatorRunner.new
runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
runner.reset

wanted = (1..120).step(10).to_a
saved = []
last_fc = runner.frame_count
while saved.length < wanted.length
  runner.run_steps(1000)
  fc = runner.frame_count
  next if fc <= last_fc
  ((last_fc + 1)..fc).each do |fnum|
    if wanted.include?(fnum)
      fb = runner.read_framebuffer
      ppm = File.join(OUT_DIR, format('f_%03d.ppm', fnum))
      save_ppm(ppm, fb)
      st = runner.cpu_state
      puts "saved frame #{fnum} pc=%04X cyc=#{runner.cycle_count}" % st[:pc]
      saved << fnum
    end
  end
  last_fc = fc
end
