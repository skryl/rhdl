#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

ROM_PATH = File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__)
PRESS_AT = 20_000_000
WINDOW_START = 20_338_900
WINDOW_END = 20_339_200

comp = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
veri = RHDL::Examples::GameBoy::VerilatorRunner.new
rom = File.binread(ROM_PATH)
[comp, veri].each { |r| r.load_rom(rom); r.reset }

cycle = 0
while cycle < WINDOW_START
  step = [100_000, WINDOW_START - cycle, PRESS_AT - cycle].select { |x| x > 0 }.min
  comp.run_steps(step)
  veri.run_steps(step)
  cycle += step
  if cycle == PRESS_AT
    comp.inject_key(7)
    veri.inject_key(7)
  end
end

readc = ->(n) { comp.peek_output(n) rescue 0 }
readv = ->(n) { veri.send(:verilator_peek, n) rescue 0 }

while cycle < WINDOW_END
  comp.run_steps(1)
  veri.run_steps(1)
  cycle += 1

  cd0 = readc.call('gb_core__cpu_di') & 0xFF
  vd  = readv.call('gb_core__cpu_di') & 0xFF
  pc  = comp.cpu_state[:pc] & 0xFFFF
  t   = readc.call('gb_core__cpu__debug_t_state') & 0xFF
  m   = readc.call('gb_core__cpu__debug_m_cycle') & 0xFF
  wa  = readc.call('gb_core__wram_addr') & 0x7FFF

  next if cd0 == vd

  comp.sim.evaluate
  cd1 = readc.call('gb_core__cpu_di') & 0xFF
  puts "cycle=#{cycle} pc=%04X t=%d m=%d wram_addr=%04X di_c_before=%02X di_c_after_eval=%02X di_v=%02X" % [pc, t, m, wa, cd0, cd1, vd]
end
