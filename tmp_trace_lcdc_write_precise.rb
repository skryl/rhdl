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

# ensure we are before drop
target = 31_330_000
r.run_steps(target - r.cycle_count)

prev_lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
puts "start cyc=#{r.cycle_count} lcdc=%02X" % prev_lcdc

200_000.times do
  c0 = r.cycle_count
  pc0 = r.cpu_state[:pc] & 0xFFFF
  addr0 = r.send(:verilator_peek, 'gb_core__cpu_addr') & 0xFFFF
  wr_n0 = r.send(:verilator_peek, 'gb_core__cpu_wr_n') & 1
  mreq_n0 = r.send(:verilator_peek, 'gb_core__cpu_mreq_n') & 1
  do0 = r.send(:verilator_peek, 'gb_core__cpu_do') & 0xFF

  r.run_steps(1)

  lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
  if lcdc != prev_lcdc
    puts "LCDC change at cyc=#{r.cycle_count} #{'%02X'%prev_lcdc}->#{'%02X'%lcdc}"
    puts "before step: cyc=#{c0} pc=#{'%04X'%pc0} cpu_addr=#{'%04X'%addr0} wr_n=#{wr_n0} mreq_n=#{mreq_n0} do=#{'%02X'%do0}"
    24.times do |k|
      pc = r.cpu_state[:pc] & 0xFFFF
      addr = r.send(:verilator_peek, 'gb_core__cpu_addr') & 0xFFFF
      wr_n = r.send(:verilator_peek, 'gb_core__cpu_wr_n') & 1
      mreq_n = r.send(:verilator_peek, 'gb_core__cpu_mreq_n') & 1
      do_v = r.send(:verilator_peek, 'gb_core__cpu_do') & 0xFF
      lcdc_now = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
      puts "  [#{k}] cyc=#{r.cycle_count} pc=#{'%04X'%pc} addr=#{'%04X'%addr} wr_n=#{wr_n} mreq_n=#{mreq_n} do=#{'%02X'%do_v} lcdc=#{'%02X'%lcdc_now}"
      r.run_steps(1)
    end
    break
  end
  prev_lcdc = lcdc
end
