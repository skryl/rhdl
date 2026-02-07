#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

PALETTE={0=>[155,188,15],1=>[139,172,15],2=>[48,98,48],3=>[15,56,15]}

def save_png(path, fb)
  ppm = path.sub(/\.png$/, '.ppm')
  h = fb.length; w=fb.first.length
  File.open(ppm,'wb'){|f| f.write("P6\n#{w} #{h}\n255\n"); h.times{|y| w.times{|x| r,g,b=PALETTE[fb[y][x]&3]; f.write([r,g,b].pack('C3')) }}}
  system('sips','-s','format','png',ppm,'--out',path, out: File::NULL, err: File::NULL)
end

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# let intro run
r.run_steps(20_000_000)
# short START tap (~2 frames)
r.inject_key(7)
r.run_steps(140_000)
r.release_key(7)

cp = [20_000_000, 22_000_000, 24_000_000, 26_000_000, 28_000_000, 30_000_000, 32_000_000, 34_000_000, 36_000_000, 40_000_000, 50_000_000, 60_000_000, 70_000_000, 80_000_000]
cp.each_with_index do |c, i|
  d = c - r.cycle_count
  r.run_steps(d) if d > 0
  fb = r.read_framebuffer
  out = File.expand_path("tmp_shortstart_#{i}.png", __dir__)
  save_png(out, fb)
  st = r.cpu_state
  lcdc = r.peek_output('gb_core__video_unit__lcdc') & 0xFF
  stat = r.peek_output('gb_core__video_unit__stat') & 0xFF
  ifr = r.peek_output('gb_core__if_r') & 0x1F
  ier = r.peek_output('gb_core__ie_r') & 0x1F
  puts "cyc=#{c} frame=#{r.sim.frame_count} pc=%04X lcdc=%02X stat=%02X if=%02X ie=%02X #{out}" % [st[:pc]&0xFFFF, lcdc, stat, ifr, ier]
end
