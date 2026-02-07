#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'digest'
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread('examples/gameboy/software/roms/pop.gb')
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each { |r| r.load_rom(rom); r.reset }

checkpoints = [500_000, 2_000_000, 5_000_000, 20_000_000, 30_000_000, 40_000_000, 50_000_000, 60_000_000]
checkpoints.each do |cyc|
  delta = cyc - c.cycle_count
  c.run_steps(delta)
  v.run_steps(delta)

  if cyc == 20_000_000
    c.inject_key(7)
    v.inject_key(7)
  elsif cyc == 40_000_000
    c.release_key(7)
    v.release_key(7)
  end

  cfb = c.read_framebuffer.flatten.pack('C*')
  vfb = v.read_framebuffer.flatten.pack('C*')
  cstate = c.cpu_state
  vstate = v.cpu_state
  reg_same = %i[pc a f b c d e h l sp].all? do |k|
    mask = (k == :pc || k == :sp) ? 0xFFFF : 0xFF
    (cstate[k] & mask) == (vstate[k] & mask)
  end

  puts "cyc=#{cyc} reg_same=#{reg_same} fb_same=#{cfb == vfb} c_pc=%04X v_pc=%04X c_f=%02X v_f=%02X c_sha=#{Digest::SHA1.hexdigest(cfb)[0,8]} v_sha=#{Digest::SHA1.hexdigest(vfb)[0,8]}" % [
    cstate[:pc] & 0xFFFF, vstate[:pc] & 0xFFFF, cstate[:f] & 0xFF, vstate[:f] & 0xFF
  ]
end
