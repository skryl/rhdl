#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

target = 30_000_000
step = 200

while r.cycle_count < target
  r.run_steps(step)
  # cart write edge == CPU write to cart area in this simplified top-level
  cw = r.peek_output('cart_wr') & 1
  if cw == 1
    addr = ((r.peek_output('ext_bus_a15') & 1) << 15) | (r.peek_output('ext_bus_addr') & 0x7FFF)
    data = r.peek_output('cart_di') & 0xFF
    if (0x2000..0x3FFF).include?(addr)
      pc = r.cpu_state[:pc] & 0xFFFF
      puts "cyc=#{r.cycle_count} pc=%04X WR[%04X]=%02X" % [pc, addr, data]
    end
  end
end
