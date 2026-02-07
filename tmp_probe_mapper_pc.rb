#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)

checkpoints = [28_000_000, 30_000_000, 31_000_000, 31_300_000, 31_380_000, 31_500_000, 32_000_000, 34_000_000, 38_000_000, 40_000_000]

checkpoints.each do |cyc|
  r.run_steps(cyc - r.cycle_count) if cyc > r.cycle_count
  state = r.cpu_state
  pc = state[:pc] & 0xFFFF
  mapped = r.send(:mapped_rom_addr, pc)
  byte = r.instance_variable_get(:@rom)[mapped] || 0
  mbc_low5 = r.instance_variable_get(:@mbc1_rom_bank_low5)
  mbc_hi2 = r.instance_variable_get(:@mbc1_bank_high2)
  mbc_mode = r.instance_variable_get(:@mbc1_mode)
  lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
  puts "cyc=#{cyc} frame=#{r.frame_count} pc=%04X mapped=%05X op=%02X bank_low5=%02X bank_hi2=%02X mode=%d lcdc=%02X" % [pc,mapped,byte,mbc_low5,mbc_hi2,mbc_mode,lcdc]
end
