#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/ir_runner'
require_relative 'examples/gameboy/utilities/runners/verilator_runner'

ROM_PATH = File.expand_path('examples/gameboy/software/roms/pop.gb', __dir__)
PRESS_AT = 20_000_000
RELEASE_AT = 40_000_000
WINDOW_START = 20_338_900
WINDOW_END = 20_341_200

puts "init compile..."
comp = RHDL::Examples::GameBoy::IrRunner.new(backend: :compile)
puts "init verilog..."
veri = RHDL::Examples::GameBoy::VerilatorRunner.new
rom = File.binread(ROM_PATH)

[comp, veri].each do |r|
  r.load_rom(rom)
  r.reset
end

cycle = 0

apply_input = lambda do |c|
  if c == PRESS_AT
    comp.inject_key(7)
    veri.inject_key(7)
    puts "[#{c}] START pressed"
  elsif c == RELEASE_AT
    comp.release_key(7)
    veri.release_key(7)
    puts "[#{c}] START released"
  end
end

read_comp = lambda do |name|
  begin
    comp.peek_output(name)
  rescue
    0
  end
end

read_veri = lambda do |name|
  begin
    veri.send(:verilator_peek, name)
  rescue
    0
  end
end

run_pair = lambda do |n|
  comp.run_steps(n)
  veri.run_steps(n)
end

# fast-forward
while cycle < WINDOW_START
  apply_input.call(cycle)
  next_event = [PRESS_AT, RELEASE_AT, WINDOW_START].select { |x| x > cycle }.min
  step = [100_000, next_event - cycle].min
  run_pair.call(step)
  cycle += step
  puts "...cycle=#{cycle}" if (cycle % 2_000_000).zero?
end

puts "entered window at cycle=#{cycle}"

first_diff = nil
while cycle < WINDOW_END
  apply_input.call(cycle)
  run_pair.call(1)
  cycle += 1

  cs = comp.cpu_state
  vs = veri.cpu_state

  cvals = {
    pc: cs[:pc] & 0xFFFF,
    a: cs[:a] & 0xFF,
    f: cs[:f] & 0xFF,
    b: cs[:b] & 0xFF,
    c: cs[:c] & 0xFF,
    d: cs[:d] & 0xFF,
    e: cs[:e] & 0xFF,
    h: cs[:h] & 0xFF,
    l: cs[:l] & 0xFF,
    sp: cs[:sp] & 0xFFFF,
    t: read_comp.call('gb_core__cpu__debug_t_state') & 0xFF,
    m: read_comp.call('gb_core__cpu__debug_m_cycle') & 0xFF,
    ir: read_comp.call('gb_core__cpu__debug_ir') & 0xFF,
    di: read_comp.call('gb_core__cpu_di') & 0xFF,
    wram_addr: read_comp.call('gb_core__wram_addr') & 0x7FFF,
    wram_wren: read_comp.call('gb_core__wram_wren') & 0x1,
    wram_do: read_comp.call('gb_core__wram_do') & 0xFF,
    cpu_do: read_comp.call('gb_core__cpu_do') & 0xFF,
    ext: (read_comp.call('ext_bus_addr') & 0x7FFF) | ((read_comp.call('ext_bus_a15') & 1) << 15),
    cart_rd: read_comp.call('cart_rd') & 1,
    cart_wr: read_comp.call('cart_wr') & 1,
  }

  vvals = {
    pc: vs[:pc] & 0xFFFF,
    a: vs[:a] & 0xFF,
    f: vs[:f] & 0xFF,
    b: vs[:b] & 0xFF,
    c: vs[:c] & 0xFF,
    d: vs[:d] & 0xFF,
    e: vs[:e] & 0xFF,
    h: vs[:h] & 0xFF,
    l: vs[:l] & 0xFF,
    sp: vs[:sp] & 0xFFFF,
    t: read_veri.call('debug_t_state') & 0xFF,
    m: read_veri.call('debug_m_cycle') & 0xFF,
    ir: read_veri.call('debug_ir') & 0xFF,
    di: read_veri.call('gb_core__cpu_di') & 0xFF,
    wram_addr: read_veri.call('gb_core__wram_addr') & 0x7FFF,
    wram_wren: read_veri.call('gb_core__wram_wren') & 0x1,
    wram_do: read_veri.call('gb_core__wram_do') & 0xFF,
    cpu_do: read_veri.call('gb_core__cpu_do') & 0xFF,
    ext: (read_veri.call('ext_bus_addr') & 0x7FFF) | ((read_veri.call('ext_bus_a15') & 1) << 15),
    cart_rd: read_veri.call('cart_rd') & 1,
    cart_wr: read_veri.call('cart_wr') & 1,
  }

  if cvals != vvals
    if first_diff.nil?
      first_diff = cycle
      puts "FIRST_DIFF cycle=#{cycle}"
    end
    puts "C #{cvals}"
    puts "V #{vvals}"
    break if cycle >= first_diff + 20
  end
end

puts "done cycle=#{cycle} first_diff=#{first_diff || 'none'}"
