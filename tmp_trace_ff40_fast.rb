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

# Jump close to drop
r.run_steps(31_200_000 - r.cycle_count)
puts "start cyc=#{r.cycle_count} pc=%04X lcdc=%02X" % [r.cpu_state[:pc] & 0xFFFF, r.send(:verilator_peek,'gb_core__video_unit__lcdc') & 0xFF]

window = 250_000
window.times do
  cpu_addr = r.send(:verilator_peek, 'gb_core__cpu_addr') & 0xFFFF
  wr_n = r.send(:verilator_peek, 'gb_core__cpu_wr_n') & 1
  mreq_n = r.send(:verilator_peek, 'gb_core__cpu_mreq_n') & 1
  do_v = r.send(:verilator_peek, 'gb_core__cpu_do') & 0xFF
  pc = r.cpu_state[:pc] & 0xFFFF
  lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF

  if cpu_addr == 0xFF40 && wr_n == 0 && mreq_n == 0
    puts "WRITE FF40 cyc=#{r.cycle_count} pc=%04X do=%02X lcdc=%02X" % [pc, do_v, lcdc]
  end
  if cpu_addr == 0xFF0F && wr_n == 0 && mreq_n == 0
    puts "WRITE FF0F cyc=#{r.cycle_count} pc=%04X do=%02X if=%02X" % [pc, do_v, r.send(:verilator_peek,'gb_core__if_r') & 0x1F]
  end
  if cpu_addr == 0xFFFF && wr_n == 0 && mreq_n == 0
    puts "WRITE FFFF cyc=#{r.cycle_count} pc=%04X do=%02X ie=%02X" % [pc, do_v, r.send(:verilator_peek,'gb_core__ie_r') & 0xFF]
  end

  r.run_steps(1)
end
puts "end cyc=#{r.cycle_count} pc=%04X lcdc=%02X" % [r.cpu_state[:pc] & 0xFFFF, r.send(:verilator_peek,'gb_core__video_unit__lcdc') & 0xFF]
