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

# Build custom framebuffer from rising-edge lcd_clkena
fb = Array.new(144) { Array.new(160, 0) }
x = 0
y = 0
prev_clkena = 0
prev_vsync = 0
frames = 0
cycles = 0

while frames < 30 && cycles < 20_000_000
  # emulate one cycle as in run_clock_cycle
  r.send(:verilator_poke, 'clk_sys', 0)
  r.send(:verilator_eval)

  addr = r.send(:verilator_peek, 'ext_bus_addr')
  a15 = r.send(:verilator_peek, 'ext_bus_a15')
  full_addr = ((a15 & 0x1) << 15) | (addr & 0x7FFF)

  cart_wr = r.send(:verilator_peek, 'cart_wr')
  if cart_wr == 1
    r.send(:mapper_write, full_addr, r.send(:verilator_peek, 'cart_di'))
  end

  cart_rd = r.send(:verilator_peek, 'cart_rd')
  if cart_rd == 1
    mapped_addr = r.send(:mapped_rom_addr, full_addr)
    rom = r.instance_variable_get(:@rom)
    rom_len = r.instance_variable_get(:@rom_len)
    data = mapped_addr < rom_len ? (rom[mapped_addr] || 0xFF) : 0xFF
    r.send(:verilator_poke, 'cart_do', data)
  end
  r.send(:verilator_eval)

  r.send(:verilator_poke, 'clk_sys', 1)
  r.send(:verilator_eval)

  lcd_clkena = r.send(:verilator_peek, 'lcd_clkena')
  lcd_vsync = r.send(:verilator_peek, 'lcd_vsync')
  lcd_data = r.send(:verilator_peek, 'lcd_data_gb') & 0x3

  # capture on rising edge only
  if lcd_clkena == 1 && prev_clkena == 0
    if x < 160 && y < 144
      fb[y][x] = lcd_data
    end
    x += 1
    if x >= 160
      x = 0
      y += 1
    end
  end

  if lcd_vsync == 1 && prev_vsync == 0
    frames += 1
    if [1, 5, 10, 20, 30].include?(frames)
      out = File.expand_path("tmp_edge_f#{frames}.ppm", __dir__)
      save_ppm(out, fb)
      puts "saved #{out} pc=%04X cyc=#{cycles}" % r.cpu_state[:pc]
    end
    x = 0
    y = 0
  end

  prev_clkena = lcd_clkena
  prev_vsync = lcd_vsync
  cycles += 1
end

puts "done frames=#{frames} cycles=#{cycles}"
