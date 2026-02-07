#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'
rom = File.binread(File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__))
c = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
v = RHDL::Examples::GameBoy::VerilatorRunner.new
[c,v].each{|r| r.load_rom(rom); r.reset }
cycle=0; press=20_000_000; start=20_294_84; stop=20_294_90
while cycle < start
  step=[50_000,start-cycle,press-cycle].select{|x|x>0}.min
  c.run_steps(step); v.run_steps(step); cycle+=step
  if cycle==press then c.inject_key(7); v.inject_key(7); end
end
rc=->(n){c.peek_output(n) rescue 0}; rv=->(n){v.send(:verilator_peek,n) rescue 0}
while cycle<stop
  c.run_steps(1); v.run_steps(1); cycle+=1
  puts "cy=#{cycle} t=#{rc.call('gb_core__cpu__debug_t_state')}\/#{rv.call('debug_t_state')} m=#{rc.call('gb_core__cpu__debug_m_cycle')}\/#{rv.call('debug_m_cycle')} ir=#{'%02X'% (rc.call('gb_core__cpu__debug_ir')&0xFF)}\/#{'%02X'% (rv.call('debug_ir')&0xFF)} save=#{rc.call('gb_core__cpu__debug_save_alu')}\/#{rv.call('debug_save_alu')} op=#{rc.call('gb_core__cpu__debug_alu_op')}\/#{rv.call('debug_alu_op')} flags=#{'%02X'% (rc.call('gb_core__cpu__debug_alu_flags')&0xFF)}\/#{'%02X'% (rv.call('debug_alu_flags')&0xFF)} f=#{'%02X'% (c.cpu_state[:f]&0xFF)}\/#{'%02X'% (v.cpu_state[:f]&0xFF)}"
end
