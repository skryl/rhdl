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
r.run_steps(15_000_000)
puts "pre cyc=#{r.cycle_count} pc=%04X" % [r.cpu_state[:pc] & 0xFFFF]

nonzero = 0
rd_nonzero = 0
one_samples = []
500_000.times do
  wr = r.send(:verilator_peek, 'cart_wr') & 1
  rd = r.send(:verilator_peek, 'cart_rd') & 1
  if wr == 1
    nonzero += 1
    if one_samples.length < 20
      one_samples << [r.cycle_count, r.cpu_state[:pc] & 0xFFFF, r.send(:verilator_peek,'ext_bus_addr') & 0x7FFF, r.send(:verilator_peek,'ext_bus_a15') & 1, r.send(:verilator_peek,'cart_di') & 0xFF]
    end
  end
  rd_nonzero += 1 if rd == 1
  r.run_steps(1)
end
puts "cart_wr_ones=#{nonzero} cart_rd_ones=#{rd_nonzero}"
one_samples.each do |cy,pc,a,a15,di|
  puts "wr cyc=#{cy} pc=%04X addr=%04X a15=%d di=%02X" % [pc,a,a15,di]
end
