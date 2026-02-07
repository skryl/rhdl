#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

PALETTE = {0=>[155,188,15],1=>[139,172,15],2=>[48,98,48],3=>[15,56,15]}
def save_ppm(path, fb)
  h=fb.length; w=fb.first.length
  File.open(path,'wb') do |f|
    f.write("P6\n#{w} #{h}\n255\n")
    h.times do |y|
      w.times do |x|
        r,g,b = PALETTE[fb[y][x]&3]
        f.write([r,g,b].pack('C3'))
      end
    end
  end
end

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# title skip
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)

# go into story
r.run_steps(8_000_000)

# press again on story
r.inject_key(7)
r.run_steps(1_000_000)
r.release_key(7)

# capture every ~1 frame for 12 frames
12.times do |i|
  r.run_steps(70_224)
  fb = r.read_framebuffer
  ppm = File.expand_path("tmp_story_press2_#{i}.ppm", __dir__)
  png = File.expand_path("tmp_story_press2_#{i}.png", __dir__)
  save_ppm(ppm, fb)
  system('sips', '-s', 'format', 'png', ppm, '--out', png, out: File::NULL, err: File::NULL)
  st = r.cpu_state
  puts "%02d cyc=%d frame=%d pc=%04X #{png}" % [i, r.cycle_count, r.sim.frame_count, st[:pc] & 0xFFFF]
end
