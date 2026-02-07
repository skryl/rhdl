#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'

r = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset

last = nil
step = 1000

while r.cycle_count < 30_000_000
  r.run_steps(step)
  # internal GB register wired to cart data bus; capture changes
  val = r.peek_output('gb_core__cart_do') & 0xFF rescue nil
  # mapper lives in backend; probe if signal exists
  low5 = r.sim.get_signal(r.sim.signal_index('gb_mbc_state_mbc1_rom_bank_low5')) rescue nil
  # fallback: look at pc neighborhood only
  pc = r.cpu_state[:pc] & 0xFFFF
  if last != pc
    if pc >= 0x3A00 || pc == 0x0218 || pc == 0x0FE2 || pc == 0x11C0
      puts "cyc=#{r.cycle_count} pc=%04X" % pc
    end
    last = pc
  end
end
