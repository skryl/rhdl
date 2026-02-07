#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

# Move to near transition
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(18_000_000) # now at 40M

names = [
  'debug_pc',
  'gb_core__video_unit__lcdc',
  'gb_core__video_unit__stat',
  'gb_core__if_r',
  'gb_core__ie_r',
  'gb_core__video_irq',
  'gb_core__vblank_irq',
  'gb_core__timer_irq',
  'gb_core__serial_irq',
  'gb_core__irq_n',
  'gb_core__irq_ack',
  'gb_core__video_unit__v_cnt',
  'gb_core__video_unit__h_cnt',
  'gb_core__video_unit__mode_wire',
  'gb_core__video_unit__mode_prev',
  'gb_core__video_unit__lyc',
  'gb_core__video_unit__h_div_cnt',
  'gb_core__video_unit__pcnt',
  'gb_core__cpu_addr',
  'gb_core__cpu_wr_n',
  'gb_core__cpu_mreq_n',
  'gb_core__cpu_do',
  'gb_core__cpu_di'
]

puts "cycle=#{r.cycle_count} frame=#{r.frame_count}"

20.times do |i|
  r.run_steps(200_000)
  pc = r.cpu_state[:pc]
  vals = names.map { |n| [n, r.send(:verilator_peek, n)] }.to_h
  printf("[%2d] cyc=%d frame=%d pc=%04X lcdc=%02X stat=%02X if=%02X ie=%02X irq_n=%d v_irq=%d vb_irq=%d tim_irq=%d mode=%d v=%d h=%d pcnt=%d\n",
         i, r.cycle_count, r.frame_count, pc & 0xFFFF,
         vals['gb_core__video_unit__lcdc'] & 0xFF,
         vals['gb_core__video_unit__stat'] & 0xFF,
         vals['gb_core__if_r'] & 0x1F,
         vals['gb_core__ie_r'] & 0xFF,
         vals['gb_core__irq_n'] & 1,
         vals['gb_core__video_irq'] & 1,
         vals['gb_core__vblank_irq'] & 1,
         vals['gb_core__timer_irq'] & 1,
         vals['gb_core__video_unit__mode_wire'] & 0x3,
         vals['gb_core__video_unit__v_cnt'] & 0xFF,
         vals['gb_core__video_unit__h_cnt'] & 0x7F,
         vals['gb_core__video_unit__pcnt'] & 0xFF)
end
