#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

class RHDL::Examples::GameBoy::VerilatorRunner
  alias_method :__orig_mapper_write, :mapper_write unless method_defined?(:__orig_mapper_write)
  def mapper_write(addr, value)
    old = @mbc1_rom_bank_low5
    __orig_mapper_write(addr, value)
    newb = @mbc1_rom_bank_low5
    if (addr & 0x7FFF) >= 0x2000 && (addr & 0x7FFF) <= 0x3FFF
      pc = cpu_state[:pc] & 0xFFFF
      puts "mapper cyc=#{@cycles} pc=%04X write %04X=%02X bank %02X->%02X hi2=%02X mode=%d" % [pc, addr & 0x7FFF, value & 0xFF, old, newb, @mbc1_bank_high2, @mbc1_mode]
    end
  end
end

r = RHDL::Examples::GameBoy::VerilatorRunner.new
r.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
r.reset
r.run_steps(20_000_000)
r.inject_key(7)
r.run_steps(2_000_000)
r.release_key(7)
r.run_steps(20_000_000)
puts "done cyc=#{r.cycle_count} frame=#{r.frame_count} pc=%04X bank=%02X" % [r.cpu_state[:pc] & 0xFFFF, r.instance_variable_get(:@mbc1_rom_bank_low5)]
