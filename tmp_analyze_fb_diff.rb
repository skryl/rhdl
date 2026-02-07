#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'
rom = File.binread('examples/gameboy/software/roms/pop.gb')
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each{|r| r.load_rom(rom); r.reset }
c.run_steps(2_000_000)
v.run_steps(2_000_000)
cfb = c.read_framebuffer.flatten
vfb = v.read_framebuffer.flatten
same = cfb.each_with_index.count{|px,i| px==vfb[i] }
inv = cfb.each_with_index.count{|px,i| px==(3-vfb[i]) }
map_counts = Hash.new(0)
cfb.each_with_index { |px,i| map_counts[[px,vfb[i]]] += 1 }
puts "same=#{same} inv=#{inv} total=#{cfb.size}"
(0..3).each do |a|
  row=(0..3).map{|b| map_counts[[a,b]]}
  puts "c=#{a}: #{row.join(' ')}"
end
