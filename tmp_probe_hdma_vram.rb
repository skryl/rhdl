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

checkpoints = [30_000_000, 31_000_000, 31_300_000, 31_380_000, 32_000_000, 34_000_000, 38_000_000]
checkpoints.each do |cyc|
  r.run_steps(cyc - r.cycle_count) if cyc > r.cycle_count
  pc = r.cpu_state[:pc] & 0xFFFF
  lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
  hdma_active = r.send(:verilator_peek, 'gb_core__hdma_active') & 1
  hdma_rd = r.send(:verilator_peek, 'gb_core__hdma_rd') & 1
  hdma_do = r.send(:verilator_peek, 'gb_core__hdma_do') & 0xFF
  hdma_src = r.send(:verilator_peek, 'gb_core__hdma_source_addr') & 0xFFFF
  hdma_dst = r.send(:verilator_peek, 'gb_core__hdma_target_addr') & 0xFFFF
  vram_wren_cpu = r.send(:verilator_peek, 'gb_core__vram_wren_cpu') & 1
  vram_wren = r.send(:verilator_peek, 'gb_core__vram_wren') & 1
  vram_addr_mux = r.send(:verilator_peek, 'gb_core__vram_addr_mux') & 0x1FFF
  vram_do = r.send(:verilator_peek, 'gb_core__vram_do') & 0xFF
  vram1_do = r.send(:verilator_peek, 'gb_core__vram1_do') & 0xFF
  cpu_clken = r.send(:verilator_peek, 'gb_core__cpu_clken') & 1
  puts "cyc=#{cyc} frame=#{r.frame_count} pc=%04X lcdc=%02X hdma_active=%d hdma_rd=%d hdma_do=%02X hdma_src=%04X hdma_dst=%04X vram_wren_cpu=%d vram_wren=%d vram_addr_mux=%04X vram_do=%02X vram1=%02X cpu_clken=%d" %
       [pc,lcdc,hdma_active,hdma_rd,hdma_do,hdma_src,hdma_dst,vram_wren_cpu,vram_wren,vram_addr_mux,vram_do,vram1_do,cpu_clken]
end
