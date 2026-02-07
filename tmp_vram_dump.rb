#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# advance into boot/logo period
r.run_steps(2_000_000)

peek_vram = ->(addr){ r.send(:verilator_read_vram, addr) }

ranges = {
  'tile_data_0x0000' => (0x0000...0x0080),
  'tile_data_0x0100' => (0x0100...0x0180),
  'tile_data_0x0800' => (0x0800...0x0880),
  'bg_map_0x1800' => (0x1800...0x1860),
  'bg_map_0x1C00' => (0x1C00...0x1C60)
}

ranges.each do |name, rg|
  bytes = rg.map { |a| peek_vram.call(a) }
  uniq = bytes.uniq.sort
  nz = bytes.count { |b| b != 0 }
  puts "#{name}: nonzero=#{nz}/#{bytes.size} uniq=#{uniq.take(16).map{|x| '%02X'%x}.join(',')}"
  puts bytes.each_slice(16).map { |row| row.map { |b| '%02X' % b }.join(' ') }.join("\n")
  puts
end
