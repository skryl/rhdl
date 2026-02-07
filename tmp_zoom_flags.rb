#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each { |r| r.load_rom(rom); r.reset }

cycle = 0
press_at = 20_000_000
start = 20_294_482
stop = 20_294_490

while cycle < start
  step = [50_000, start - cycle, press_at - cycle].select { |x| x > 0 }.min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step
  if cycle == press_at
    c.inject_key(7)
    v.inject_key(7)
  end
end

rc = ->(n){ c.peek_output(n) rescue 0 }
rv = ->(n){ v.send(:verilator_peek, n) rescue 0 }

while cycle < stop
  c.run_steps(1)
  v.run_steps(1)
  cycle += 1

  cs = c.cpu_state
  vs = v.cpu_state
  puts "cy=#{cycle} pc=%04X/%04X t=%d m=%d ir=%02X/%02X A=%02X/%02X F=%02X/%02X busa=%02X/%02X busb=%02X/%02X alur=%02X/%02X aluf=%02X/%02X z=%d/%d" % [
    cs[:pc]&0xFFFF, vs[:pc]&0xFFFF,
    rc.call('gb_core__cpu__debug_t_state')&0xFF,
    rc.call('gb_core__cpu__debug_m_cycle')&0xFF,
    rc.call('gb_core__cpu__debug_ir')&0xFF,
    rv.call('debug_ir')&0xFF,
    cs[:a]&0xFF, vs[:a]&0xFF,
    cs[:f]&0xFF, vs[:f]&0xFF,
    rc.call('gb_core__cpu__debug_bus_a')&0xFF,
    rv.call('debug_bus_a')&0xFF,
    rc.call('gb_core__cpu__debug_bus_b')&0xFF,
    rv.call('debug_bus_b')&0xFF,
    rc.call('gb_core__cpu__debug_alu_result')&0xFF,
    rv.call('debug_alu_result')&0xFF,
    rc.call('gb_core__cpu__debug_alu_flags')&0xFF,
    rv.call('debug_alu_flags')&0xFF,
    rc.call('gb_core__cpu__debug_z_flag')&0x1,
    rv.call('debug_z_flag')&0x1
  ]
end
