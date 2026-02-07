#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
j = RHDL::Examples::GameBoy::IrRunner.new(backend: :jit)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[j,v].each{|r| r.load_rom(rom); r.reset }

cycle = 0
press_at = 20_000_000
end_cycle = 20_500_000

while cycle < end_cycle
  if cycle == press_at
    j.inject_key(7)
    v.inject_key(7)
    puts "press at #{cycle}"
  end
  step = 50_000
  step = [step, press_at-cycle].min if cycle < press_at
  step = [step, end_cycle-cycle].min
  j.run_steps(step)
  v.run_steps(step)
  cycle += step

  js = j.cpu_state
  vs = v.cpu_state
  mismatch = %i[pc a f b c d e h l sp].any? { |k| (js[k] & (k==:pc || k==:sp ? 0xFFFF : 0xFF)) != (vs[k] & (k==:pc || k==:sp ? 0xFFFF : 0xFF)) }
  if mismatch
    puts "DIVERGE at cycle=#{cycle} jit=#{js} verilog=#{vs}"
    exit 0
  end
  puts "cycle=#{cycle} pc=%04X" % (js[:pc] & 0xFFFF) if (cycle % 1_000_000).zero?
end

puts "no divergence through #{end_cycle}"
