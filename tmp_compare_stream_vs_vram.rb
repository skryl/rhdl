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

def read_bg_pixel(sim, lcdc, scx, scy, x, y)
  src_x = (x + scx) & 0xFF
  src_y = (y + scy) & 0xFF

  bg_map_base = ((lcdc & 0x08) != 0) ? 0x1C00 : 0x1800
  unsigned_tiles = (lcdc & 0x10) != 0

  tile_row = (src_y >> 3) & 0x1F
  tile_col = (src_x >> 3) & 0x1F
  map_addr = bg_map_base + tile_row * 32 + tile_col
  tile_num = sim.read_vram(map_addr)

  row_in_tile = src_y & 0x07
  tile_addr = if unsigned_tiles
                ((tile_num << 4) + (row_in_tile << 1)) & 0x1FFF
              else
                signed = tile_num < 0x80 ? tile_num : tile_num - 0x100
                (0x1000 + signed * 16 + (row_in_tile << 1)) & 0x1FFF
              end

  lo = sim.read_vram(tile_addr)
  hi = sim.read_vram((tile_addr + 1) & 0x1FFF)
  bit = 7 - (src_x & 0x07)
  (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
end

def decode_bg_frame(sim, lcdc, scx, scy, bgp)
  Array.new(144) do |y|
    Array.new(160) do |x|
      raw = read_bg_pixel(sim, lcdc, scx, scy, x, y)
      (bgp >> (raw * 2)) & 0x03
    end
  end
end

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# Progress schedule used in prior repros
schedule = [
  [2_000_000, nil],
  [20_000_000, :press],
  [22_000_000, :release],
  [30_000_000, nil],
  [40_000_000, nil]
]

schedule.each_with_index do |(cyc, ev), i|
  d = cyc - r.cycle_count
  r.run_steps(d) if d > 0

  case ev
  when :press
    r.inject_key(7)
  when :release
    r.release_key(7)
  end

  lcdc = r.peek_output('gb_core__video_unit__lcdc') & 0xFF
  scx = r.peek_output('gb_core__video_unit__scx') & 0xFF
  scy = r.peek_output('gb_core__video_unit__scy') & 0xFF
  bgp = r.peek_output('gb_core__video_unit__bgp') & 0xFF

  stream = r.read_framebuffer
  bg = decode_bg_frame(r.sim, lcdc, scx, scy, bgp)

  mismatch = 0
  144.times do |y|
    160.times do |x|
      mismatch += 1 if (stream[y][x] & 0x3) != (bg[y][x] & 0x3)
    end
  end

  sppm = File.expand_path("tmp_stream_#{i}.ppm", __dir__)
  bppm = File.expand_path("tmp_bgdecode_#{i}.ppm", __dir__)
  spng = File.expand_path("tmp_stream_#{i}.png", __dir__)
  bpng = File.expand_path("tmp_bgdecode_#{i}.png", __dir__)

  save_ppm(sppm, stream)
  save_ppm(bppm, bg)
  system('sips', '-s', 'format', 'png', sppm, '--out', spng, out: File::NULL, err: File::NULL)
  system('sips', '-s', 'format', 'png', bppm, '--out', bpng, out: File::NULL, err: File::NULL)

  st = r.cpu_state
  puts "cyc=#{cyc} pc=%04X frame=#{r.sim.frame_count} lcdc=%02X scx=%02X scy=%02X mismatch=%d #{spng} #{bpng}" % [st[:pc] & 0xFFFF, lcdc, scx, scy, mismatch]
end
