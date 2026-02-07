#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each{|r| r.load_rom(rom); r.reset }

cycle=0
while cycle < 20_338_900
  step=[100_000,20_338_900-cycle,20_000_000-cycle].select{|x|x>0}.min
  c.run_steps(step); v.run_steps(step); cycle += step
  if cycle==20_000_000
    c.inject_key(7); v.inject_key(7)
  end
end

rc = ->(n){ c.peek_output(n) rescue 0 }
rv = ->(n){ v.send(:verilator_peek,n) rescue 0 }

(0...400).each do
  c.run_steps(1); v.run_steps(1); cycle += 1
  cw = rc.call('gb_core__wram__wren_b') & 1
  zw = rc.call('gb_core__zpram__wren_b') & 1
  vw = rc.call('gb_core__vram0__wren_b') & 1
  if cw!=0 || zw!=0 || vw!=0
    puts "C cycle=#{cycle} wram_b=#{cw} zpram_b=#{zw} vram_b=#{vw} addr_w=#{rc.call('gb_core__wram__address_b')} data_w=#{rc.call('gb_core__wram__data_b')}"
  end
  cwv = rv.call('gb_core__wram__wren_b') & 1
  zwv = rv.call('gb_core__zpram__wren_b') & 1
  # vram0__wren_b isn't mapped in verilog wrapper
  if cwv!=0 || zwv!=0
    puts "V cycle=#{cycle} wram_b=#{cwv} zpram_b=#{zwv} addr_w=#{rv.call('gb_core__wram__address_b')} data_w=#{rv.call('gb_core__wram__data_b')}"
  end
end
puts "done"
