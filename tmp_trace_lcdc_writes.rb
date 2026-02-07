#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# start press to advance title
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)

last_lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
puts "start cyc=#{r.cycle_count} lcdc=%02X" % last_lcdc

# monitor next 25M cycles in chunks, with in-chunk step for event resolution
chunk = 50_000
(25_000_000 / chunk).times do
  prev = r.cycle_count
  r.run_steps(chunk)
  lcdc = r.send(:verilator_peek, 'gb_core__video_unit__lcdc') & 0xFF
  if lcdc != last_lcdc
    # refine within the chunk to locate event more closely
    # backtracking not possible, so just print detection edge at chunk granularity + state
    pc = r.cpu_state[:pc] & 0xFFFF
    addr = r.send(:verilator_peek, 'gb_core__cpu_addr') & 0xFFFF
    wr_n = r.send(:verilator_peek, 'gb_core__cpu_wr_n') & 1
    mreq_n = r.send(:verilator_peek, 'gb_core__cpu_mreq_n') & 1
    do_v = r.send(:verilator_peek, 'gb_core__cpu_do') & 0xFF
    puts "lcdc change cyc=#{r.cycle_count} from=%02X to=%02X pc=%04X cpu_addr=%04X wr_n=%d mreq_n=%d do=%02X" % [last_lcdc, lcdc, pc, addr, wr_n, mreq_n, do_v]
    last_lcdc = lcdc
  end

  if (r.cycle_count % 2_000_000).zero?
    pc = r.cpu_state[:pc] & 0xFFFF
    puts "progress cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X lcdc=%02X" % [pc, lcdc]
  end
end
