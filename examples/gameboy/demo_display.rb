#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script that runs Game Boy simulation and displays braille screen output

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require_relative 'utilities/runners/ir_runner'

rom_path = ARGV[0] || File.join(__dir__, 'software/roms/tobu.gb')
total_frames = (ARGV[1] || 60).to_i

unless File.exist?(rom_path)
  puts "ROM not found: #{rom_path}"
  exit 1
end

puts "Game Boy Display Demo"
puts "=" * 60
puts "ROM: #{File.basename(rom_path)}"
puts "Frames to render: #{total_frames}"
puts "=" * 60

# Initialize
runner = RHDL::GameBoy::IrRunner.new(backend: :compile)
runner.load_rom(File.binread(rom_path))
runner.reset

renderer = RHDL::GameBoy::LcdRenderer.new(chars_wide: 80, invert: false)

# 70224 CPU cycles per frame, but SpeedControl divides clk_sys by 8 to get CE
# So we need 8x more clk_sys cycles
cpu_cycles_per_frame = 154 * 456  # 70224 CPU cycles
cycles_per_frame = cpu_cycles_per_frame * 8  # 561792 clk_sys cycles
frame_count = 0

puts "\nRunning simulation...\n"

start_time = Time.now

while frame_count < total_frames
  # Run one frame worth of cycles
  runner.run_steps(cycles_per_frame)
  frame_count += 1

  # Display every 10 frames
  if frame_count % 10 == 0 || frame_count == 1
    elapsed = Time.now - start_time
    # cycle_count is clk_sys cycles, divide by 8 for CPU MHz
    speed_mhz = runner.cycle_count / 8 / elapsed / 1_000_000.0

    # Clear screen and move cursor to top
    print "\e[2J\e[H"

    puts "=" * 80
    puts "Game Boy Display - Frame #{frame_count}/#{total_frames}"
    puts "Cycles: #{runner.cycle_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} | " \
         "Speed: #{'%.2f' % speed_mhz} MHz (#{'%.1f' % (speed_mhz / 4.19 * 100)}% realtime)"
    puts "=" * 80

    # Render the framebuffer
    framebuffer = runner.read_framebuffer
    output = renderer.render_braille(framebuffer)
    framed = renderer.frame(output, title: "Game Boy LCD - #{File.basename(rom_path)}")
    puts framed

    puts "\n" + "=" * 80
    # cycle_count is clk_sys, divide by 8 to get CPU cycles for LY calculation
    cpu_cycles = runner.cycle_count / 8
    puts "LY: #{(cpu_cycles / 456) % 154} | Screen dirty: #{runner.screen_dirty?}"

    runner.clear_screen_dirty
  end
end

elapsed = Time.now - start_time
puts "\n" + "=" * 80
puts "Completed #{frame_count} frames in #{'%.2f' % elapsed}s"
# cycle_count is clk_sys cycles, divide by 8 for CPU MHz
puts "Average speed: #{'%.2f' % (runner.cycle_count / 8 / elapsed / 1_000_000.0)} MHz"
puts "=" * 80
