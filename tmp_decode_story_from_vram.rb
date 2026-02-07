#!/usr/bin/env ruby

bin = File.binread('tmp_story_vram.bin').bytes
map_base = 0x1800

palette = {
  0 => [155,188,15],
  1 => [139,172,15],
  2 => [48,98,48],
  3 => [15,56,15]
}

width = 160
height = 144
img = Array.new(height) { Array.new(width, 0) }

scx = 0
scy = 0
lcdc_tile_data_sel = 0 # signed mode

height.times do |y|
  src_y = (scy + y) & 0xFF
  tile_row = (src_y >> 3) & 0x1F
  row_in_tile = src_y & 7
  width.times do |x|
    src_x = (scx + x) & 0xFF
    tile_col = (src_x >> 3) & 0x1F
    map_addr = map_base + tile_row * 32 + tile_col
    tile_num = bin[map_addr]

    tile_addr = if lcdc_tile_data_sel == 1
      ((tile_num << 4) + (row_in_tile << 1)) & 0x1FFF
    else
      signed = tile_num < 0x80 ? tile_num : tile_num - 0x100
      (0x1000 + signed * 16 + (row_in_tile << 1)) & 0x1FFF
    end

    lo = bin[tile_addr]
    hi = bin[(tile_addr + 1) & 0x1FFF]
    bit = 7 - (src_x & 7)
    raw = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
    # use identity palette for clarity
    img[y][x] = raw
  end
end

ppm = 'tmp_story_vram_decode.ppm'
File.open(ppm, 'wb') do |f|
  f.write("P6\n#{width} #{height}\n255\n")
  height.times do |y|
    width.times do |x|
      r,g,b = palette.fetch(img[y][x])
      f.write([r,g,b].pack('C3'))
    end
  end
end

system('sips', '-s', 'format', 'png', ppm, '--out', 'tmp_story_vram_decode.png', out: File::NULL, err: File::NULL)
puts 'wrote tmp_story_vram_decode.png'
