#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'digest'
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread('examples/gameboy/software/roms/pop.gb')
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c, v].each { |r| r.load_rom(rom); r.reset }

[500_000, 1_000_000, 1_500_000, 2_000_000, 2_500_000, 3_000_000].each do |cyc|
  d = cyc - c.cycle_count
  c.run_steps(d)
  v.run_steps(d)

  cfb = c.read_framebuffer.flatten
  vfb = v.read_framebuffer.flatten
  diff = 0
  cfb.each_with_index { |px, i| diff += 1 if px != vfb[i] }

  puts "cyc=#{cyc} c_fc=#{c.sim.frame_count} v_fc=#{v.frame_count} diff_px=#{diff} c_sha=#{Digest::SHA1.hexdigest(cfb.pack('C*'))[0,8]} v_sha=#{Digest::SHA1.hexdigest(vfb.pack('C*'))[0,8]}"
end
