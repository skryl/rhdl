#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

runner = RHDL::Examples::GameBoy::VerilatorRunner.new
runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
runner.reset

last_frame = runner.frame_count
samples = []
max_iters = 5000
iters = 0
while samples.length < 30 && iters < max_iters
  runner.run_steps(1000)
  fc = runner.frame_count
  if fc > last_frame
    state = runner.cpu_state
    samples << {
      frame: fc,
      cycles: runner.cycle_count,
      pc: state[:pc],
      a: state[:a],
      lcd_on: runner.send(:verilator_peek, 'lcd_on')
    }
    last_frame = fc
  end
  iters += 1
end

puts "captured=#{samples.length} iters=#{iters}"
samples.each do |s|
  puts "f=%3d cyc=%9d pc=%04X a=%02X lcd_on=%d" % [s[:frame], s[:cycles], s[:pc], s[:a], s[:lcd_on]]
end
