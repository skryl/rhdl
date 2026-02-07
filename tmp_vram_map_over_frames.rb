#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

wanted = [1,2,3,4,5,6,7,8,9,10,15,20,30,40,50,80,100]
idx = 0
last_fc = r.frame_count

while idx < wanted.length
  r.run_steps(1000)
  fc = r.frame_count
  next if fc <= last_fc
  ((last_fc + 1)..fc).each do |f|
    next unless f == wanted[idx]
    st = r.cpu_state
    lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc')
    scx = r.send(:verilator_peek, 'gb_core__video_unit__scx')
    scy = r.send(:verilator_peek, 'gb_core__video_unit__scy')
    bgp = r.send(:verilator_peek, 'gb_core__video_unit__bgp')
    map0 = (0x1800...0x1C00).map{|a| r.send(:verilator_read_vram,a)}
    map1 = (0x1C00...0x2000).map{|a| r.send(:verilator_read_vram,a)}
    nz0 = map0.count{|b| b != 0}
    nz1 = map1.count{|b| b != 0}
    uniq0 = map0.uniq.length
    uniq1 = map1.uniq.length
    puts "f=%3d pc=%04X lcdc=%02X scx=%02X scy=%02X bgp=%02X map0_nz=%4d uniq=%3d map1_nz=%4d uniq=%3d" % [f, st[:pc], lcdc, scx, scy, bgp, nz0, uniq0, nz1, uniq1]
    idx += 1
    break if idx >= wanted.length
  end
  last_fc = fc
end
