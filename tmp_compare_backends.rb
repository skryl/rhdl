#!/usr/bin/env ruby
$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require_relative 'examples/gameboy/gameboy'
require_relative 'examples/gameboy/utilities/runners/headless_runner'

PALETTE = {
  0 => [155,188,15],
  1 => [139,172,15],
  2 => [48,98,48],
  3 => [15,56,15]
}.freeze

def save_ppm(path, fb)
  h = fb.length
  w = fb.first.length
  File.open(path, 'wb') do |f|
    f.write("P6\n#{w} #{h}\n255\n")
    h.times do |y|
      w.times do |x|
        r,g,b = PALETTE.fetch(fb[y][x] & 0x3)
        f.write([r,g,b].pack('C3'))
      end
    end
  end
end

def run_backend(mode:, sim:, tag:)
  runner = RHDL::Examples::GameBoy::HeadlessRunner.new(mode: mode, sim: sim)
  runner.load_rom(File.binread('examples/gameboy/software/roms/pop.gb'))
  runner.reset

  checkpoints = [2_000_000, 20_000_000, 22_000_000, 30_000_000, 40_000_000]
  checkpoints.each_with_index do |cyc, i|
    d = cyc - runner.cycle_count
    runner.run_steps(d) if d > 0

    if cyc == 20_000_000
      runner.runner.inject_key(7)
    elsif cyc == 22_000_000
      runner.runner.release_key(7)
    end

    fb = runner.runner.read_framebuffer
    ppm = File.expand_path("tmp_#{tag}_#{i}.ppm", __dir__)
    png = File.expand_path("tmp_#{tag}_#{i}.png", __dir__)
    save_ppm(ppm, fb)
    system('sips', '-s', 'format', 'png', ppm, '--out', png, out: File::NULL, err: File::NULL)

    st = runner.cpu_state
    frame_count = if runner.runner.respond_to?(:sim) && runner.runner.sim.respond_to?(:frame_count)
                    runner.runner.sim.frame_count
                  elsif runner.runner.respond_to?(:verilator_get_frame_count)
                    runner.runner.verilator_get_frame_count
                  else
                    -1
                  end

    puts "#{tag} cyc=#{cyc} frame=#{frame_count} pc=%04X #{png}" % (st[:pc] & 0xFFFF)
  end
end

run_backend(mode: :hdl, sim: :compile, tag: 'compile')
run_backend(mode: :verilog, sim: :compile, tag: 'verilog')
