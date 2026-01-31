#!/usr/bin/env ruby
# Debug script to check boot ROM data path in Game Boy IR simulation

require_relative 'examples/gameboy/utilities/gameboy_ir'

# Initialize the IR runner with compiler backend
runner = RHDL::GameBoy::IrRunner.new(backend: :compile)

# First, check signal names related to data path
sim = runner.sim
puts "\n=== Checking Data Path Signals ==="
%w[
  gb_core__boot_do boot_do
  gb_core__cpu_di cpu_di
  gb_core__cpu__data_in cpu__data_in data_in
  gb_core__cpu__di_reg cpu__di_reg di_reg
  gb_core__cpu__ir cpu__ir ir
  gb_core__sel_boot_rom sel_boot_rom
  gb_core__boot_rom_addr boot_rom_addr
].each do |name|
  begin
    value = sim.peek(name)
    puts "  #{name}: present (value=#{value})"
  rescue => e
    puts "  #{name}: NOT FOUND"
  end
end

# Create a ROM with Nintendo logo at 0x0104
# This is the official Nintendo logo that the boot ROM will compare
nintendo_logo = [
  0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B,
  0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
  0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
  0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
  0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC,
  0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
]

rom = Array.new(32768, 0x00)  # NOPs
# Place Nintendo logo at 0x0104
nintendo_logo.each_with_index { |b, i| rom[0x0104 + i] = b }
# Set cartridge type, ROM size, etc.
rom[0x0147] = 0x00  # ROM ONLY
rom[0x0148] = 0x00  # 32KB ROM
rom[0x0149] = 0x00  # No RAM
# Header checksum (sum of 0x0134-0x014C, inverted)
sum = 0
(0x0134..0x014C).each { |addr| sum = (sum - rom[addr] - 1) & 0xFF }
rom[0x014D] = sum

runner.load_rom(rom.pack('C*'))

# Load boot ROM
runner.load_boot_rom

# Reset
runner.reset

# Run enough cycles for more frames - boot ROM takes about 3 seconds
puts "\n=== Running Boot ROM ==="
cycles_per_frame = 70224
frames_to_run = 30  # About 0.5 seconds

start_time = Time.now
runner.run_steps(cycles_per_frame * frames_to_run)
elapsed = Time.now - start_time

puts "Ran #{cycles_per_frame * frames_to_run} cycles in #{elapsed.round(2)}s"
puts "Speed: #{(cycles_per_frame * frames_to_run / elapsed / 1_000_000).round(2)} MHz equivalent"

# Check CPU state
puts "\n=== CPU State ==="
state = runner.cpu_state
puts "  PC: 0x#{state[:pc].to_s(16).upcase.rjust(4, '0')}"
puts "  A: 0x#{state[:a].to_s(16).upcase.rjust(2, '0')}"
puts "  Cycles: #{state[:cycles]}"

# Check VRAM for Nintendo logo data
sim = runner.sim
puts "\n=== VRAM Check ==="
if sim.respond_to?(:read_ram)
  vram = sim.read_ram(0x8000, 256)
  non_zero = vram.count { |b| b != 0 }
  puts "  VRAM non-zero bytes in first 256: #{non_zero}"
  if non_zero > 0
    puts "  VRAM[0x0000..0x0010]: #{vram[0..15].map { |b| "%02X" % b }.join(' ')}"
  end

  # Check tile map area (0x9800-0x9BFF)
  tilemap = sim.read_ram(0x9800, 256)
  non_zero_tiles = tilemap.count { |b| b != 0 }
  puts "  Tile map non-zero bytes: #{non_zero_tiles}"
end

# Check framebuffer
puts "\n=== Framebuffer Check ==="
fb = runner.read_framebuffer
non_zero_pixels = fb.flatten.count { |p| p != 0 }
puts "  Non-zero pixels: #{non_zero_pixels}/23040"

# Check PPU-related signals
puts "\n=== PPU Debug ==="
%w[
  gb_core__video_unit__lcdc gb_core__video_unit__lcdc_on gb_core__video_unit__lcdc_bg_ena
  gb_core__video_unit__bgp gb_core__video_unit__scx gb_core__video_unit__scy
  gb_core__video_unit__palette_color gb_core__video_unit__tile_idx
  gb_core__video_unit__tile_data_lo gb_core__video_unit__tile_data_hi
  gb_core__video_unit__fetch_phase gb_core__video_unit__vram_addr gb_core__video_unit__vram_data
  gb_core__video_unit__mode3 gb_core__video_unit__h_cnt gb_core__video_unit__v_cnt
  gb_core__video_unit__bg_x gb_core__video_unit__bg_y
  gb_core__video_unit__tile_num gb_core__video_unit__tile_map_addr gb_core__video_unit__tile_data_addr
  gb_core__video_unit__pcnt gb_core__video_unit__oam_eval gb_core__video_unit__vblank
  gb_core__vram_addr_ppu gb_core__vram_data_ppu
].each do |name|
  begin
    value = sim.peek(name)
    puts "  #{name.split('__').last}: 0x#{value.to_s(16).upcase}"
  rescue => e
    puts "  #{name}: NOT FOUND"
  end
end

# Check a few VRAM bytes that should contain logo data
puts "\n=== Checking VRAM for logo data ==="
if sim.respond_to?(:read_ram)
  # Check where boot ROM writes logo tiles (around 0x8190)
  logo_area = sim.read_ram(0x8190, 32)
  puts "  VRAM[0x8190..0x81AF]: #{logo_area.map { |b| "%02X" % b }.join(' ')}"

  # Check tile map area
  tilemap_area = sim.read_ram(0x9910, 32)
  puts "  Tilemap[0x9910..0x992F]: #{tilemap_area.map { |b| "%02X" % b }.join(' ')}"
end

puts "\n=== Rendering LCD (braille) ===" if non_zero_pixels > 0
puts runner.render_lcd_braille(chars_wide: 80) if non_zero_pixels > 0
