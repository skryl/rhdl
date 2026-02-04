require 'spec_helper'
require 'support/cpu_assembler'
require 'support/display_helper'
require 'rhdl/hdl/cpu/harness'

RSpec.describe RHDL::HDL::CPU::FastHarness, 'Conway' do
  include DisplayHelper

  before(:each) do
    @cpu = RHDL::HDL::CPU::FastHarness.new(nil, sim: :compile)
    @cpu.reset
  end

  describe 'game of life' do
    it 'evolves a glider pattern on a 10x10 grid', :slow do
      # Conway's Game of Life for HDL CPU using indirect addressing
      # Uses a 10x10 grid with a glider pattern
      #
      # Initial state (glider at top-left):
      #   . X . . . . . . . .
      #   . . X . . . . . . .
      #   X X X . . . . . . .
      #   . . . . . . . . . .
      #   ... (rest empty)
      #
      # After 4 generations, glider moves down-right by 1 cell
      #
      # Memory map:
      # 0x00: row counter
      # 0x01: col counter
      # 0x02: constant 1
      # 0x03: constant 10 (grid size)
      # 0x04: neighbor count
      # 0x05: current cell offset
      # 0x06: pointer high byte (for indirect access)
      # 0x07: pointer low byte (for indirect access)
      # 0x08: constant 'X' (0x58)
      # 0x09: constant '.' (0x2E)
      # 0x0A: constant 2 (for survival check)
      # 0x0B: constant 3 (for birth/survival)
      # 0x0C: constant 9 (boundary = grid_size - 1)
      # 0x0D: current cell value
      # 0x0E: display high byte (0x08)
      #
      # Read buffer:  0x0100-0x0163 (100 bytes, 10x10 grid)
      # Write buffer: 0x0200-0x0263 (100 bytes, 10x10 grid)
      # Display:      0x0800-0x0863

      grid_size = 10

      program = Assembler.build(0x10) do |p|
        # Initialize constants
        p.instr :LDI, 1
        p.instr :STA, 0x02        # constant 1
        p.instr :LDI, grid_size
        p.instr :STA, 0x03        # grid size
        p.instr :LDI, 'X'.ord
        p.instr :STA, 0x08        # constant 'X'
        p.instr :LDI, '.'.ord
        p.instr :STA, 0x09        # constant '.'
        p.instr :LDI, 2
        p.instr :STA, 0x0A        # constant 2
        p.instr :LDI, 3
        p.instr :STA, 0x0B        # constant 3
        p.instr :LDI, grid_size - 1
        p.instr :STA, 0x0C        # boundary (grid_size - 1)
        p.instr :LDI, 0x08
        p.instr :STA, 0x0E        # display high byte

        # Initialize row=0
        p.instr :LDI, 0
        p.instr :STA, 0x00        # row = 0

        p.label :row_loop
        # Initialize col=0
        p.instr :LDI, 0
        p.instr :STA, 0x01        # col = 0

        p.label :col_loop
        # Reset neighbor count
        p.instr :LDI, 0
        p.instr :STA, 0x04        # neighbor_count = 0

        # Calculate current cell offset: row*10 + col
        p.instr :LDA, 0x00        # row
        p.instr :MUL, 0x03        # row * 10
        p.instr :ADD, 0x01        # + col
        p.instr :STA, 0x05        # offset

        # Set up pointer for read buffer (0x01XX)
        p.instr :LDI, 0x01
        p.instr :STA, 0x06        # pointer high = 0x01

        # Check North neighbor (offset - 10) if row > 0
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_north
        p.instr :LDA, 0x05        # current offset
        p.instr :SUB, 0x03        # - 10
        p.instr :STA, 0x07        # pointer low
        p.instr :CALL, :check_neighbor

        p.label :skip_north
        # Check South neighbor (offset + 10) if row < 9
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C        # row - 9
        p.instr :JZ_LONG, :skip_south
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 10
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_south
        # Check West neighbor (offset - 1) if col > 0
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_west
        p.instr :LDA, 0x05
        p.instr :SUB, 0x02        # - 1
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_west
        # Check East neighbor (offset + 1) if col < 9
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C        # col - 9
        p.instr :JZ_LONG, :skip_east
        p.instr :LDA, 0x05
        p.instr :ADD, 0x02        # + 1
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_east
        # Check NW neighbor (offset - 11) if row > 0 and col > 0
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_nw
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_nw
        p.instr :LDA, 0x05
        p.instr :SUB, 0x03        # - 10
        p.instr :SUB, 0x02        # - 1 = -11
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_nw
        # Check NE neighbor (offset - 9) if row > 0 and col < 9
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_ne
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_ne
        p.instr :LDA, 0x05
        p.instr :SUB, 0x03        # - 10
        p.instr :ADD, 0x02        # + 1 = -9
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_ne
        # Check SW neighbor (offset + 9) if row < 9 and col > 0
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_sw
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_sw
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 10
        p.instr :SUB, 0x02        # - 1 = +9
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_sw
        # Check SE neighbor (offset + 11) if row < 9 and col < 9
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_se
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_se
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 10
        p.instr :ADD, 0x02        # + 1 = +11
        p.instr :STA, 0x07
        p.instr :CALL, :check_neighbor

        p.label :skip_se
        # Read current cell value using indirect LDA
        p.instr :LDA, 0x05        # offset
        p.instr :STA, 0x07        # pointer low
        p.instr :LDA, [0x06, 0x07] # indirect load from [0x01:offset]
        p.instr :STA, 0x0D        # save current cell value

        # Apply Conway rules
        p.instr :CALL, :apply_rules

        # Write result to write buffer using indirect STA
        p.instr :LDI, 0x02
        p.instr :STA, 0x06        # pointer high = 0x02 (write buffer)
        p.instr :LDA, 0x0D        # load result
        p.instr :STA, [0x06, 0x07] # indirect store to [0x02:offset]

        # Also write to display
        p.instr :LDA, 0x0E        # 0x08
        p.instr :STA, 0x06        # pointer high = 0x08 (display)
        p.instr :LDA, 0x0D        # load result
        p.instr :STA, [0x06, 0x07] # indirect store to [0x08:offset]

        # Restore read buffer pointer for next iteration
        p.instr :LDI, 0x01
        p.instr :STA, 0x06        # pointer high = 0x01

        # Next column
        p.instr :LDA, 0x01
        p.instr :ADD, 0x02        # col++
        p.instr :STA, 0x01
        p.instr :SUB, 0x03        # - grid_size
        p.instr :JNZ_LONG, :col_loop

        # Next row
        p.instr :LDA, 0x00
        p.instr :ADD, 0x02        # row++
        p.instr :STA, 0x00
        p.instr :SUB, 0x03        # - grid_size
        p.instr :JNZ_LONG, :row_loop

        p.instr :HLT

        # Subroutine: check_neighbor - read cell at [0x06:0x07] and increment count if alive
        p.label :check_neighbor
        p.instr :LDA, [0x06, 0x07] # indirect load from pointer
        p.instr :SUB, 0x08        # compare with 'X'
        p.instr :JNZ_LONG, :neighbor_not_alive
        # Neighbor is alive - increment count
        p.instr :LDA, 0x04
        p.instr :ADD, 0x02
        p.instr :STA, 0x04

        p.label :neighbor_not_alive
        p.instr :RET

        # Subroutine: apply_rules - determine next state based on neighbors
        # Input: 0x04 = neighbor count, 0x0D = current cell value
        # Output: 0x0D = new cell value
        p.label :apply_rules
        # Check if current cell is alive
        p.instr :LDA, 0x0D
        p.instr :SUB, 0x08        # compare with 'X'
        p.instr :JZ_LONG, :cell_is_alive

        # Cell is dead - check for birth (exactly 3 neighbors)
        p.instr :LDA, 0x04
        p.instr :SUB, 0x0B        # - 3
        p.instr :JZ_LONG, :make_alive
        p.instr :JMP_LONG, :make_dead

        p.label :cell_is_alive
        # Cell is alive - survive if 2 or 3 neighbors
        p.instr :LDA, 0x04
        p.instr :SUB, 0x0A        # - 2
        p.instr :JZ_LONG, :make_alive
        p.instr :LDA, 0x04
        p.instr :SUB, 0x0B        # - 3
        p.instr :JZ_LONG, :make_alive

        p.label :make_dead
        p.instr :LDA, 0x09        # '.'
        p.instr :STA, 0x0D
        p.instr :RET

        p.label :make_alive
        p.instr :LDA, 0x08        # 'X'
        p.instr :STA, 0x0D
        p.instr :RET
      end

      # Load program at address 0x10 (matching Assembler.build base address)
      @cpu.memory.load(program, 0x10)
      @cpu.pc = 0x10

      # Initialize buffers with empty cells
      cells = grid_size * grid_size
      (0...cells).each { |i| @cpu.memory.write(0x100 + i, '.'.ord) }
      (0...cells).each { |i| @cpu.memory.write(0x200 + i, '.'.ord) }

      # Set up glider pattern at top-left (offset by 1 to avoid edge)
      # Glider shape:
      #   . X .
      #   . . X
      #   X X X
      # At row 0-2, col 0-2 (positions: 1, 12, 20, 21, 22)
      glider_cells = [
        [0, 1],  # row 0, col 1
        [1, 2],  # row 1, col 2
        [2, 0],  # row 2, col 0
        [2, 1],  # row 2, col 1
        [2, 2],  # row 2, col 2
      ]
      glider_cells.each do |row, col|
        @cpu.memory.write(0x100 + row * grid_size + col, 'X'.ord)
      end

      # Store constant for MUL instruction
      @cpu.memory.write(0x03, grid_size)

      puts "Initial state (10x10 grid with glider):"
      print_grid(@cpu.memory, 0x100, grid_size)

      # Run the program for one generation
      cycles = @cpu.run(500000)

      puts "\nHDL CPU Conway completed in #{cycles} cycles"
      puts "CPU halted: #{@cpu.halted}"

      puts "\nAfter 1 generation (write buffer):"
      print_grid(@cpu.memory, 0x200, grid_size)

      # After 1 generation, glider transforms to:
      #   . . .
      #   X . X
      #   . X X
      #   . X .
      # Expected alive cells after gen 1: (1,0), (1,2), (2,1), (2,2), (3,1)
      expected_alive_gen1 = [
        [1, 0],  # row 1, col 0
        [1, 2],  # row 1, col 2
        [2, 1],  # row 2, col 1
        [2, 2],  # row 2, col 2
        [3, 1],  # row 3, col 1
      ]

      # Verify each expected alive cell
      expected_alive_gen1.each do |row, col|
        addr = 0x200 + row * grid_size + col
        expect(@cpu.memory.read(addr)).to eq('X'.ord),
          "Cell (#{row},#{col}) at 0x#{addr.to_s(16)} should be alive"
      end

      # Verify the original glider cells that should now be dead
      dead_cells = [
        [0, 1],  # was alive, now dead
        [2, 0],  # was alive, now dead
      ]
      dead_cells.each do |row, col|
        addr = 0x200 + row * grid_size + col
        expect(@cpu.memory.read(addr)).to eq('.'.ord),
          "Cell (#{row},#{col}) at 0x#{addr.to_s(16)} should be dead"
      end

      # Count total alive cells (should be 5 for a glider)
      alive_count = (0...cells).count { |i| @cpu.memory.read(0x200 + i) == 'X'.ord }
      expect(alive_count).to eq(5), "Glider should have exactly 5 alive cells, got #{alive_count}"
    end
  end

  private

  def print_grid(memory, base_addr, size)
    (0...size).each do |row|
      line = ""
      (0...size).each do |col|
        char = memory.read(base_addr + row * size + col)
        line << (char == 'X'.ord ? 'X' : '.')
      end
      puts line
    end
  end
end
