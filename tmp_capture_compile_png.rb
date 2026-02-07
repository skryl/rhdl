#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

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

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

checkpoints = [2_000_000, 5_000_000, 20_000_000, 30_000_000, 40_000_000, 60_000_000]
checkpoints.each_with_index do |cyc, i|
  d = cyc - r.cycle_count
  r.run_steps(d) if d > 0
  r.inject_key(7) if cyc == 20_000_000
  r.release_key(7) if cyc == 40_000_000

  fb = r.read_framebuffer
  ppm = File.expand_path("tmp_compile_fix_#{i}.ppm", __dir__)
  png = File.expand_path("tmp_compile_fix_#{i}.png", __dir__)
  save_ppm(ppm, fb)
  system('sips', '-s', 'format', 'png', ppm, '--out', png, out: File::NULL, err: File::NULL)
  st = r.cpu_state
  puts "#{cyc} #{png} pc=%04X frame=#{r.sim.frame_count}" % (st[:pc] & 0xFFFF)
end
