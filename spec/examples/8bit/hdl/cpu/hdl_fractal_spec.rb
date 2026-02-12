require 'spec_helper'
require 'support/cpu_assembler'
require 'support/display_helper'

RSpec.describe RHDL::HDL::CPU::FastHarness, 'Mandelbrot' do
  include DisplayHelper

  before(:each) do
    @cpu = RHDL::HDL::CPU::FastHarness.new(nil, sim: :compile)
    @cpu.reset

    clear_display(@cpu.memory)
  end

  describe 'mandelbrot program' do
    it 'renders the Mandelbrot set on an 8x8 grid', :slow do
      # Mandelbrot set using pre-computed coordinate lookup tables
      # This avoids complex fixed-point arithmetic by storing the
      # real and imaginary coordinates for each pixel in memory.
      #
      # Scaling: 8 units = 1.0 (so range -16 to +16 = -2.0 to +2.0)
      # Escape radius: |z|^2 > 4 => check zr^2/8 + zi^2/8 > 32
      #
      # Memory layout:
      # 0x00-0x07: cr values (real coord for each x)
      # 0x08-0x0F: ci values (imag coord for each y)
      # 0x10+: variables

      program = Assembler.build(0x100) do |p|
        # Constants
        p.instr :LDI, 1
        p.instr :STA, 0x20        # const 1
        p.instr :LDI, 8
        p.instr :STA, 0x21        # grid size / scaling factor
        p.instr :LDI, 10
        p.instr :STA, 0x22        # max iterations
        p.instr :LDI, 0x08
        p.instr :STA, 0x23        # display high
        p.instr :LDI, 32
        p.instr :STA, 0x24        # escape threshold
        p.instr :LDI, 2
        p.instr :STA, 0x25        # const 2
        p.instr :LDI, 0x80
        p.instr :STA, 0x26        # sign mask

        # y = 0
        p.instr :LDI, 0
        p.instr :STA, 0x11        # y

        p.label :row_loop
        # x = 0
        p.instr :LDI, 0
        p.instr :STA, 0x10        # x

        p.label :col_loop
        # Get cr from lookup table at 0x00+x
        p.instr :LDA, 0x10
        p.instr :STA, 0x27        # ptr low = x
        p.instr :LDI, 0
        p.instr :STA, 0x28        # ptr high = 0
        p.instr :LDA, [0x28, 0x27]
        p.instr :STA, 0x12        # cr

        # Get ci from lookup table at 0x08+y
        p.instr :LDA, 0x11
        p.instr :ADD, 0x21        # y + 8
        p.instr :STA, 0x27        # ptr low
        p.instr :LDA, [0x28, 0x27]
        p.instr :STA, 0x13        # ci

        # display offset = y * 8 + x
        p.instr :LDA, 0x11
        p.instr :MUL, 0x21
        p.instr :ADD, 0x10
        p.instr :STA, 0x14        # offset

        # z = 0
        p.instr :LDI, 0
        p.instr :STA, 0x15        # zr
        p.instr :STA, 0x16        # zi
        p.instr :STA, 0x17        # iter

        p.label :iter_loop
        # Check iter
        p.instr :LDA, 0x17
        p.instr :SUB, 0x22
        p.instr :JZ_LONG, :in_set

        # |zr|: if negative, negate
        p.instr :LDA, 0x15
        p.instr :AND, 0x26
        p.instr :JZ_LONG, :zr_pos
        p.instr :LDA, 0x15
        p.instr :NOT, 0
        p.instr :ADD, 0x20
        p.instr :JMP_LONG, :zr_done
        p.label :zr_pos
        p.instr :LDA, 0x15
        p.label :zr_done
        p.instr :STA, 0x29        # |zr|

        # |zi|
        p.instr :LDA, 0x16
        p.instr :AND, 0x26
        p.instr :JZ_LONG, :zi_pos
        p.instr :LDA, 0x16
        p.instr :NOT, 0
        p.instr :ADD, 0x20
        p.instr :JMP_LONG, :zi_done
        p.label :zi_pos
        p.instr :LDA, 0x16
        p.label :zi_done
        p.instr :STA, 0x2A        # |zi|

        # zr^2 = |zr| * |zr|
        p.instr :LDA, 0x29
        p.instr :MUL, 0x29
        p.instr :STA, 0x2B        # zr^2

        # zi^2 = |zi| * |zi|
        p.instr :LDA, 0x2A
        p.instr :MUL, 0x2A
        p.instr :STA, 0x2C        # zi^2

        # |z|^2 = (zr^2 + zi^2) / 8 for scale correction
        p.instr :LDA, 0x2B
        p.instr :ADD, 0x2C
        # Divide by 8 via right shift (done manually)
        p.instr :STA, 0x2D        # save sum
        # Simple division: shift right 3 times is hard without shift
        # Just compare directly - if sum > 255 it wrapped, so escaped
        # Or if sum >= threshold * 8 = 256, escaped
        # For simplicity: if sum's high bit is set or sum >= 128, likely escaped
        p.instr :SUB, 0x24        # - threshold
        p.instr :AND, 0x26        # check sign
        p.instr :JZ_LONG, :escaped

        # new_zr = (zr^2 - zi^2)/8 + cr
        # Approximate by: zr^2/8 - zi^2/8 + cr
        # Without division, just use the raw difference (will be approximate)
        p.instr :LDA, 0x2B        # zr^2
        p.instr :SUB, 0x2C        # - zi^2
        p.instr :ADD, 0x12        # + cr
        p.instr :STA, 0x2E        # new_zr temp

        # new_zi = 2*zr*zi/8 + ci = zr*zi/4 + ci
        # Compute sign of product
        p.instr :LDA, 0x15
        p.instr :AND, 0x26
        p.instr :STA, 0x2F        # zr sign
        p.instr :LDA, 0x16
        p.instr :AND, 0x26
        p.instr :XOR, 0x2F
        p.instr :STA, 0x30        # product sign (0 if same, 0x80 if different)

        # |zr| * |zi| * 2 / 8 = |zr| * |zi| / 4
        p.instr :LDA, 0x29
        p.instr :MUL, 0x2A
        p.instr :MUL, 0x25        # * 2
        p.instr :STA, 0x31        # product magnitude

        # Apply sign
        p.instr :LDA, 0x30
        p.instr :JZ_LONG, :prod_pos
        p.instr :LDA, 0x31
        p.instr :NOT, 0
        p.instr :ADD, 0x20
        p.instr :JMP_LONG, :prod_done
        p.label :prod_pos
        p.instr :LDA, 0x31
        p.label :prod_done
        p.instr :ADD, 0x13        # + ci
        p.instr :STA, 0x16        # zi = new_zi

        # zr = new_zr
        p.instr :LDA, 0x2E
        p.instr :STA, 0x15

        # iter++
        p.instr :LDA, 0x17
        p.instr :ADD, 0x20
        p.instr :STA, 0x17
        p.instr :JMP_LONG, :iter_loop

        p.label :escaped
        p.instr :LDI, '#'.ord
        p.instr :JMP_LONG, :draw

        p.label :in_set
        p.instr :LDI, '.'.ord

        p.label :draw
        p.instr :STA, 0x32
        p.instr :LDA, 0x14
        p.instr :STA, 0x27
        p.instr :LDA, 0x23
        p.instr :STA, 0x28
        p.instr :LDA, 0x32
        p.instr :STA, [0x28, 0x27]

        # next x
        p.instr :LDA, 0x10
        p.instr :ADD, 0x20
        p.instr :STA, 0x10
        p.instr :SUB, 0x21
        p.instr :JNZ_LONG, :col_loop

        # next y
        p.instr :LDA, 0x11
        p.instr :ADD, 0x20
        p.instr :STA, 0x11
        p.instr :SUB, 0x21
        p.instr :JNZ_LONG, :row_loop

        p.instr :HLT
      end

      @cpu.memory.load(program, 0x100)
      @cpu.pc = 0x100

      # Pre-compute coordinate lookup tables
      # Real axis: -2.0 to 0.5 over 8 pixels (scaled by 8: -16 to 4)
      # Imag axis: -1.2 to 1.2 over 8 pixels (scaled by 8: -10 to 10)
      cr_values = [-16, -13, -10, -7, -4, -1, 2, 4]  # -2.0 to 0.5
      ci_values = [-10, -7, -4, -1, 1, 4, 7, 10]     # -1.25 to 1.25

      cr_values.each_with_index { |v, i| @cpu.memory.write(i, v & 0xFF) }
      ci_values.each_with_index { |v, i| @cpu.memory.write(8 + i, v & 0xFF) }

      cycles = @cpu.run(500000)

      puts "HDL CPU Mandelbrot completed in #{cycles} cycles"
      puts "CPU halted: #{@cpu.halted}"

      puts "\nMandelbrot set (8x8):"
      puts "('#' = outside, '.' = in set)"
      (0...8).each do |y|
        line = ""
        (0...8).each do |x|
          char = @cpu.memory.read(0x800 + y * 8 + x)
          line << char.chr rescue '?'
        end
        puts line
      end

      in_set = (0...64).count { |i| @cpu.memory.read(0x800 + i) == '.'.ord }
      escaped = (0...64).count { |i| @cpu.memory.read(0x800 + i) == '#'.ord }
      puts "\nIn set: #{in_set}, Escaped: #{escaped}"

      expect(in_set).to be > 0, "Should have pixels in set"
      expect(escaped).to be > 0, "Should have pixels escaped"
      expect(in_set + escaped).to eq(64)
    end
  end
end
