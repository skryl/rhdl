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
search_end = 20_300_000

while cycle < press_at
  step = [100_000, press_at - cycle].min
  c.run_steps(step)
  v.run_steps(step)
  cycle += step
end

c.inject_key(7)
v.inject_key(7)
puts "pressed at #{cycle}"

while cycle < search_end
  c.run_steps(1)
  v.run_steps(1)
  cycle += 1

  cs = c.cpu_state
  vs = v.cpu_state

  diffs = []
  diffs << :pc if (cs[:pc] & 0xFFFF) != (vs[:pc] & 0xFFFF)
  diffs << :a  if (cs[:a] & 0xFF) != (vs[:a] & 0xFF)
  diffs << :f  if (cs[:f] & 0xFF) != (vs[:f] & 0xFF)
  diffs << :b  if (cs[:b] & 0xFF) != (vs[:b] & 0xFF)
  diffs << :c  if (cs[:c] & 0xFF) != (vs[:c] & 0xFF)
  diffs << :d  if (cs[:d] & 0xFF) != (vs[:d] & 0xFF)
  diffs << :e  if (cs[:e] & 0xFF) != (vs[:e] & 0xFF)
  diffs << :h  if (cs[:h] & 0xFF) != (vs[:h] & 0xFF)
  diffs << :l  if (cs[:l] & 0xFF) != (vs[:l] & 0xFF)
  diffs << :sp if (cs[:sp] & 0xFFFF) != (vs[:sp] & 0xFFFF)

  next if diffs.empty?

  rc = ->(n){ c.peek_output(n) rescue 0 }
  rv = ->(n){ v.send(:verilator_peek, n) rescue 0 }
  puts "first reg diff cycle=#{cycle} diffs=#{diffs.inspect}"
  puts "c pc=%04X a=%02X f=%02X b=%02X c=%02X d=%02X e=%02X h=%02X l=%02X sp=%04X t=%d m=%d ir=%02X di=%02X" % [
    cs[:pc]&0xFFFF, cs[:a]&0xFF, cs[:f]&0xFF, cs[:b]&0xFF, cs[:c]&0xFF, cs[:d]&0xFF, cs[:e]&0xFF, cs[:h]&0xFF, cs[:l]&0xFF, cs[:sp]&0xFFFF,
    rc.call('gb_core__cpu__debug_t_state')&0xFF, rc.call('gb_core__cpu__debug_m_cycle')&0xFF, rc.call('gb_core__cpu__debug_ir')&0xFF, rc.call('gb_core__cpu_di')&0xFF
  ]
  puts "v pc=%04X a=%02X f=%02X b=%02X c=%02X d=%02X e=%02X h=%02X l=%02X sp=%04X t=%d m=%d ir=%02X di=%02X" % [
    vs[:pc]&0xFFFF, vs[:a]&0xFF, vs[:f]&0xFF, vs[:b]&0xFF, vs[:c]&0xFF, vs[:d]&0xFF, vs[:e]&0xFF, vs[:h]&0xFF, vs[:l]&0xFF, vs[:sp]&0xFFFF,
    rv.call('debug_t_state')&0xFF, rv.call('debug_m_cycle')&0xFF, rv.call('debug_ir')&0xFF, rv.call('gb_core__cpu_di')&0xFF
  ]
  exit 0
end

puts "no reg diff through #{search_end}"
