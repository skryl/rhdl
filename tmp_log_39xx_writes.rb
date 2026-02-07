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
r.run_steps(36_900_000 - r.cycle_count)

puts "start cyc=#{r.cycle_count} pc=%04X" % [r.cpu_state[:pc] & 0xFFFF]
count=0
300_000.times do
  pc = r.cpu_state[:pc] & 0xFFFF
  wr = r.send(:verilator_peek,'cart_wr') & 1
  if wr == 1 && pc >= 0x3900 && pc <= 0x39FF
    addr = (r.send(:verilator_peek,'ext_bus_addr') & 0x7FFF) | ((r.send(:verilator_peek,'ext_bus_a15') & 1) << 15)
    di = r.send(:verilator_peek,'cart_di') & 0xFF
    puts "cyc=#{r.cycle_count} pc=%04X cart_wr addr=%04X di=%02X" % [pc,addr,di]
    count += 1
    break if count >= 80
  end
  r.run_steps(1)
end
puts "end cyc=#{r.cycle_count} pc=%04X count=#{count}" % [r.cpu_state[:pc] & 0xFFFF]
