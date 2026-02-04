require 'spec_helper'
require 'support/cpu_assembler'
require 'support/display_helper'

RSpec.describe RHDL::HDL::CPU::Harness, 'Fractal' do
  include CpuTestHelper
  include DisplayHelper

  before(:each) do
    use_hdl_cpu!
    @memory = MemorySimulator::Memory.new
    @cpu = cpu_class.new(@memory)
    @cpu.reset

    clear_display(@cpu.memory)
  end

  describe 'fractal program' do
    it 'fills display with checkerboard pattern using HDL CPU', :slow do
      # Simplified fractal program for HDL CPU
      # Fills a 3x3 grid with a checkerboard pattern based on (x+y) % 2
      # Uses indirect STA to write to display memory at 0x800
      #
      # Memory map:
      # 0x00: x coordinate
      # 0x01: y coordinate
      # 0x02: constant 1 (for increment)
      # 0x03: constant 3 (grid size)
      # 0x05: display address low byte
      # 0x06: display address high byte (0x08 for 0x800 base)
      # 0x07: temp counter for multiplication

      program = Assembler.build(0x100) do |p|
        # Initialize constants
        p.instr :LDI, 1
        p.instr :STA, 0x02        # constant 1
        p.instr :LDI, 3
        p.instr :STA, 0x03        # grid size
        p.instr :LDI, 0x08
        p.instr :STA, 0x06        # display base high byte

        # Initialize x=0, y=0
        p.instr :LDI, 0
        p.instr :STA, 0x00        # x = 0
        p.instr :STA, 0x01        # y = 0

        p.label :row_loop
        # Reset x for new row
        p.instr :LDI, 0
        p.instr :STA, 0x00        # x = 0

        p.label :col_loop
        # Calculate y * 3 using repeated addition
        p.instr :LDI, 0
        p.instr :STA, 0x05        # sum = 0
        p.instr :LDA, 0x01        # load y
        p.instr :STA, 0x07        # temp counter = y

        p.label :mul_loop
        p.instr :LDA, 0x07        # load counter
        p.instr :JZ_LONG, :mul_done
        p.instr :SUB, 0x02        # counter--
        p.instr :STA, 0x07
        p.instr :LDA, 0x05        # load sum
        p.instr :ADD, 0x03        # add 3
        p.instr :STA, 0x05
        p.instr :JMP_LONG, :mul_loop

        p.label :mul_done
        # Add x to get final offset: y*3 + x
        p.instr :LDA, 0x05
        p.instr :ADD, 0x00        # add x
        p.instr :STA, 0x05        # low byte of address offset

        # Calculate (x + y) & 1 for checkerboard pattern
        p.instr :LDA, 0x00        # load x
        p.instr :ADD, 0x01        # add y
        p.instr :AND, 0x02        # AND with 1 (stored at 0x02)
        p.instr :JZ_LONG, :write_dot

        # Write '#' for odd (x+y)
        p.instr :LDI, '#'.ord
        p.instr :JMP_LONG, :do_write

        p.label :write_dot
        # Write '.' for even (x+y)
        p.instr :LDI, '.'.ord

        p.label :do_write
        # Write to display using indirect STA
        # Address is at [0x06:0x05] = 0x08XX where XX is the offset
        p.instr :STA, [0x06, 0x05]

        # Increment x
        p.instr :LDA, 0x00
        p.instr :ADD, 0x02        # x++
        p.instr :STA, 0x00

        # Check if x < 3
        p.instr :SUB, 0x03        # x - 3
        p.instr :JNZ_LONG, :col_loop

        # Increment y
        p.instr :LDA, 0x01
        p.instr :ADD, 0x02        # y++
        p.instr :STA, 0x01

        # Check if y < 3
        p.instr :SUB, 0x03        # y - 3
        p.instr :JNZ_LONG, :row_loop

        p.instr :HLT
      end

      # Load program at 0x100
      @cpu.memory.load(program, 0x100)
      @cpu.pc = 0x100

      # Run the program
      cycles = @cpu.run(10000)

      puts "HDL CPU Fractal completed in #{cycles} cycles"
      puts "CPU halted: #{@cpu.halted}"

      # Read and display the pattern
      puts "\nDisplay output (3x3 checkerboard pattern):"
      (0...3).each do |y|
        line = ""
        (0...3).each do |x|
          addr = 0x800 + y * 3 + x
          char = @cpu.memory.read(addr)
          line << (char == '.'.ord ? '.' : (char == '#'.ord ? '#' : '?'))
        end
        puts line
      end

      # Verify the checkerboard pattern
      expect(@cpu.halted).to be true

      # Check specific cells for checkerboard pattern
      # Expected pattern:
      # .#.
      # #.#
      # .#.
      expect(@cpu.memory.read(0x800)).to eq('.'.ord), "Cell (0,0) should be '.'"
      expect(@cpu.memory.read(0x801)).to eq('#'.ord), "Cell (1,0) should be '#'"
      expect(@cpu.memory.read(0x802)).to eq('.'.ord), "Cell (2,0) should be '.'"
      expect(@cpu.memory.read(0x803)).to eq('#'.ord), "Cell (0,1) should be '#'"
      expect(@cpu.memory.read(0x804)).to eq('.'.ord), "Cell (1,1) should be '.'"
      expect(@cpu.memory.read(0x805)).to eq('#'.ord), "Cell (2,1) should be '#'"
      expect(@cpu.memory.read(0x806)).to eq('.'.ord), "Cell (0,2) should be '.'"
      expect(@cpu.memory.read(0x807)).to eq('#'.ord), "Cell (1,2) should be '#'"
      expect(@cpu.memory.read(0x808)).to eq('.'.ord), "Cell (2,2) should be '.'"
    end
  end
end
