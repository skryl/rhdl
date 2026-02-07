#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

nonzero = 0
rd_nonzero = 0
100_000.times do
  wr = r.send(:verilator_peek, 'cart_wr') & 1
  rd = r.send(:verilator_peek, 'cart_rd') & 1
  nonzero += 1 if wr == 1
  rd_nonzero += 1 if rd == 1
  r.run_steps(1)
end
puts "cart_wr_ones=#{nonzero} cart_rd_ones=#{rd_nonzero} cycles=#{r.cycle_count}"
