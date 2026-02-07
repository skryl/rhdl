#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(8_100_000)

# dump BG map 0x9800 area and tile region around 0x9000/0x8800 references
vram = []
0x2000.times { |i| vram << (r.sim.read_vram(i) & 0xFF) }

File.binwrite('tmp_story_vram.bin', vram.pack('C*'))
puts "wrote tmp_story_vram.bin size=#{vram.size}"

# print first 8 rows of BG map as tile IDs
base = 0x1800
8.times do |row|
  row_bytes = vram[base + row*32, 32]
  puts "%02d: %s" % [row, row_bytes.map { |b| "%02X" % b }.join(' ')]
end

# print signed tile data for tile ids around 0xE0-0xFF and 0x00-0x20 row0 bytes
[0xE0,0xE8,0xF0,0xF8,0x00,0x08,0x10,0x18,0x20].each do |t|
  addr = if t < 0x80
           0x1000 + t*16
         else
           0x1000 + (t-0x100)*16
         end
  lo = vram[addr]
  hi = vram[addr+1]
  puts "tile %02X addr %04X row0 lo=%02X hi=%02X" % [t, addr & 0x1FFF, lo, hi]
end
