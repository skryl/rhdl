require 'spec_helper'
require 'support/cpu_assembler'
require 'support/display_helper'

RSpec.describe RHDL::HDL::CPU::Harness, 'Conway' do
  include CpuTestHelper
  include DisplayHelper

  before(:each) do
    use_hdl_cpu!
    @memory = MemorySimulator::Memory.new
    @cpu = cpu_class.new(@memory)
    @cpu.reset
  end

  describe 'game of life' do
    it 'evolves a blinker pattern for one generation' do
      # Simplified Conway's Game of Life for HDL CPU
      # Uses a 5x5 grid stored in low memory for direct addressing
      #
      # Initial state (blinker):     After 1 generation:
      #   . . . . .                    . . . . .
      #   . . X . .                    . . . . .
      #   . . X . .         ->         . X X X .
      #   . . X . .                    . . . . .
      #   . . . . .                    . . . . .
      #
      # Read buffer:  0x10-0x28 (25 bytes, 5x5 grid)
      # Write buffer: 0x30-0x48 (25 bytes, 5x5 grid)
      # Display copy: 0x800+ (for visualization)
      #
      # Memory map:
      # 0x00: row counter
      # 0x01: col counter
      # 0x02: constant 1
      # 0x03: constant 5 (grid size)
      # 0x04: neighbor count
      # 0x05: temp storage
      # 0x06: current cell address (for direct LDA)
      # 0x07: cell value temp
      # 0x08: constant 'X' (0x58)
      # 0x09: constant '.' (0x2E)
      # 0x0A: constant 2 (for survival check)
      # 0x0B: constant 3 (for birth/survival)
      # 0x0C: constant 4 (boundary check)
      # 0x0D: constant 0x10 (read buffer base)
      # 0x0E: constant 0x30 (write buffer base)
      # 0x0F: display address low byte

      program = Assembler.build(0x100) do |p|
        # Initialize constants
        p.instr :LDI, 1
        p.instr :STA, 0x02        # constant 1
        p.instr :LDI, 5
        p.instr :STA, 0x03        # grid size
        p.instr :LDI, 'X'.ord
        p.instr :STA, 0x08        # constant 'X'
        p.instr :LDI, '.'.ord
        p.instr :STA, 0x09        # constant '.'
        p.instr :LDI, 2
        p.instr :STA, 0x0A        # constant 2
        p.instr :LDI, 3
        p.instr :STA, 0x0B        # constant 3
        p.instr :LDI, 4
        p.instr :STA, 0x0C        # constant 4 (boundary)
        p.instr :LDI, 0x10
        p.instr :STA, 0x0D        # read buffer base
        p.instr :LDI, 0x30
        p.instr :STA, 0x0E        # write buffer base

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

        # Calculate current cell address: base + row*5 + col
        # Using simplified approach: just loop through the fixed offsets
        p.instr :LDA, 0x00        # row
        p.instr :MUL, 0x03        # row * 5
        p.instr :ADD, 0x01        # + col
        p.instr :STA, 0x05        # offset

        # Check North neighbor (offset - 5) if row > 0
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_north
        p.instr :LDA, 0x05        # current offset
        p.instr :SUB, 0x03        # - 5
        p.instr :ADD, 0x0D        # + read buffer base
        p.instr :STA, 0x06        # neighbor address
        p.instr :CALL, :check_cell

        p.label :skip_north
        # Check South neighbor (offset + 5) if row < 4
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C        # row - 4
        p.instr :JZ_LONG, :skip_south
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 5
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_south
        # Check West neighbor (offset - 1) if col > 0
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_west
        p.instr :LDA, 0x05
        p.instr :SUB, 0x02        # - 1
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_west
        # Check East neighbor (offset + 1) if col < 4
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C        # col - 4
        p.instr :JZ_LONG, :skip_east
        p.instr :LDA, 0x05
        p.instr :ADD, 0x02        # + 1
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_east
        # Check NW neighbor (offset - 6) if row > 0 and col > 0
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_nw
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_nw
        p.instr :LDA, 0x05
        p.instr :SUB, 0x03        # - 5
        p.instr :SUB, 0x02        # - 1 more = -6
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_nw
        # Check NE neighbor (offset - 4) if row > 0 and col < 4
        p.instr :LDA, 0x00
        p.instr :JZ_LONG, :skip_ne
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_ne
        p.instr :LDA, 0x05
        p.instr :SUB, 0x03        # - 5
        p.instr :ADD, 0x02        # + 1 = -4
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_ne
        # Check SW neighbor (offset + 4) if row < 4 and col > 0
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_sw
        p.instr :LDA, 0x01
        p.instr :JZ_LONG, :skip_sw
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 5
        p.instr :SUB, 0x02        # - 1 = +4
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_sw
        # Check SE neighbor (offset + 6) if row < 4 and col < 4
        p.instr :LDA, 0x00
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_se
        p.instr :LDA, 0x01
        p.instr :SUB, 0x0C
        p.instr :JZ_LONG, :skip_se
        p.instr :LDA, 0x05
        p.instr :ADD, 0x03        # + 5
        p.instr :ADD, 0x02        # + 1 = +6
        p.instr :ADD, 0x0D
        p.instr :STA, 0x06
        p.instr :CALL, :check_cell

        p.label :skip_se
        # Read current cell value
        p.instr :LDA, 0x05        # offset
        p.instr :ADD, 0x0D        # + read buffer base
        p.instr :STA, 0x06        # cell address
        # We need to read from the address in 0x06, but we can't do indirect LDA
        # Instead, use a lookup table approach - read each cell position directly
        p.instr :CALL, :read_current_cell

        # Apply Conway rules
        p.instr :CALL, :apply_rules

        # Write result to write buffer
        p.instr :LDA, 0x05        # offset
        p.instr :ADD, 0x0E        # + write buffer base
        p.instr :STA, 0x06        # write address
        p.instr :CALL, :write_cell

        # Next column
        p.instr :LDA, 0x01
        p.instr :ADD, 0x02        # col++
        p.instr :STA, 0x01
        p.instr :SUB, 0x03        # - 5
        p.instr :JNZ_LONG, :col_loop

        # Next row
        p.instr :LDA, 0x00
        p.instr :ADD, 0x02        # row++
        p.instr :STA, 0x00
        p.instr :SUB, 0x03        # - 5
        p.instr :JNZ_LONG, :row_loop

        # Copy write buffer to display (0x800)
        p.instr :CALL, :copy_to_display

        p.instr :HLT

        # Subroutine: check_cell - check if cell at address in 0x06 is alive
        # Increments neighbor_count (0x04) if alive
        # Since we can't do indirect LDA, we'll check against known addresses
        p.label :check_cell
        # Read cell value by checking each possible address
        # This is inefficient but works without indirect LDA
        # Use a series of comparisons for addresses 0x10-0x28

        # For simplicity in the test, read directly using the address
        # The trick: we store the neighbor address, then use a switch-like structure
        p.instr :LDA, 0x06        # get address

        # Compare with each cell address and load that cell
        p.instr :SUB, 0x0D        # subtract base (0x10)
        # Now we have offset 0-24

        # Check cell at that offset in read buffer
        # Since cells are at 0x10-0x28, we check if cell == 'X'
        # Load from address 0x10+offset which is in the nibble range for direct LDA
        p.instr :ADD, 0x0D        # add back base to get address
        # Now check the value - but we still can't do indirect load!

        # Workaround: Use fixed cell reads for this small grid
        # Store offset in 0x05 temporarily
        p.instr :SUB, 0x0D        # back to offset
        p.instr :STA, 0x07        # save offset

        # Check if offset == 0 (cell 0x10)
        p.instr :JZ_LONG, :check_cell_0
        p.instr :SUB, 0x02        # offset - 1
        p.instr :JZ_LONG, :check_cell_1
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_2
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_3
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_4
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_5
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_6
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_7
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_8
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_9
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_10
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_11
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_12
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_13
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_14
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_15
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_16
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_17
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_18
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_19
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_20
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_21
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_22
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :check_cell_23
        p.instr :JMP_LONG, :check_cell_24

        # Individual cell checks - load from fixed address
        (0..24).each do |i|
          p.label :"check_cell_#{i}"
          p.instr :LDA, 0x10 + i    # Load cell directly
          p.instr :JMP_LONG, :check_cell_done
        end

        p.label :check_cell_done
        # ACC now has cell value - check if 'X'
        p.instr :SUB, 0x08        # compare with 'X'
        p.instr :JNZ_LONG, :neighbor_dead
        # Neighbor is alive - increment count
        p.instr :LDA, 0x04
        p.instr :ADD, 0x02
        p.instr :STA, 0x04

        p.label :neighbor_dead
        p.instr :RET

        # Subroutine: read_current_cell - read current cell value into 0x07
        p.label :read_current_cell
        p.instr :LDA, 0x05        # offset

        # Same lookup approach as check_cell
        p.instr :JZ_LONG, :read_cell_0
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_1
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_2
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_3
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_4
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_5
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_6
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_7
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_8
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_9
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_10
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_11
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_12
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_13
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_14
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_15
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_16
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_17
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_18
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_19
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_20
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_21
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_22
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :read_cell_23
        p.instr :JMP_LONG, :read_cell_24

        (0..24).each do |i|
          p.label :"read_cell_#{i}"
          p.instr :LDA, 0x10 + i
          p.instr :JMP_LONG, :read_cell_done
        end

        p.label :read_cell_done
        p.instr :STA, 0x07        # save cell value
        p.instr :RET

        # Subroutine: apply_rules - determine next state based on neighbors
        # Input: 0x04 = neighbor count, 0x07 = current cell value
        # Output: 0x07 = new cell value
        p.label :apply_rules
        # Check if current cell is alive
        p.instr :LDA, 0x07
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
        p.instr :STA, 0x07
        p.instr :RET

        p.label :make_alive
        p.instr :LDA, 0x08        # 'X'
        p.instr :STA, 0x07
        p.instr :RET

        # Subroutine: write_cell - write value from 0x07 to address based on offset in 0x05
        p.label :write_cell
        p.instr :LDA, 0x05        # offset

        p.instr :JZ_LONG, :write_cell_0
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_1
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_2
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_3
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_4
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_5
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_6
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_7
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_8
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_9
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_10
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_11
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_12
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_13
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_14
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_15
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_16
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_17
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_18
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_19
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_20
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_21
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_22
        p.instr :SUB, 0x02
        p.instr :JZ_LONG, :write_cell_23
        p.instr :JMP_LONG, :write_cell_24

        (0..24).each do |i|
          p.label :"write_cell_#{i}"
          p.instr :LDA, 0x07      # load value to write
          p.instr :STA, 0x30 + i  # write to buffer (need 2-byte STA for addresses > 0x0F)
          p.instr :RET
        end

        # Subroutine: copy_to_display - copy write buffer to display at 0x800
        p.label :copy_to_display
        p.instr :LDI, 0x08
        p.instr :STA, 0x06        # display high byte

        # Copy each cell using indirect STA
        (0..24).each do |i|
          p.instr :LDA, 0x30 + i  # read from write buffer
          p.instr :LDI, i
          p.instr :STA, 0x0F      # display low byte offset
          p.instr :LDA, 0x30 + i  # reload value (STA might have changed ACC)
          p.instr :STA, [0x06, 0x0F]  # write to display
        end

        p.instr :RET
      end

      # Load program
      @cpu.memory.load(program, 0x100)
      @cpu.pc = 0x100

      # Initialize read buffer with blinker pattern (0x10-0x28)
      # Clear all cells first
      (0...25).each { |i| @cpu.memory.write(0x10 + i, '.'.ord) }
      (0...25).each { |i| @cpu.memory.write(0x30 + i, '.'.ord) }

      # Set up vertical blinker at center
      # Grid positions: row*5 + col
      # (1,2), (2,2), (3,2) = positions 7, 12, 17
      @cpu.memory.write(0x10 + 7, 'X'.ord)   # row 1, col 2
      @cpu.memory.write(0x10 + 12, 'X'.ord)  # row 2, col 2
      @cpu.memory.write(0x10 + 17, 'X'.ord)  # row 3, col 2

      puts "Initial state (read buffer at 0x10):"
      print_5x5_grid(@cpu.memory, 0x10)

      # Run the program
      cycles = @cpu.run(500000)

      puts "\nHDL CPU Conway completed in #{cycles} cycles"
      puts "CPU halted: #{@cpu.halted}"

      puts "\nFinal state (write buffer at 0x30):"
      print_5x5_grid(@cpu.memory, 0x30)

      puts "\nDisplay copy (at 0x800):"
      print_5x5_grid(@cpu.memory, 0x800)

      # Verify the blinker evolved correctly
      expect(@cpu.halted).to be true

      # Check the evolved pattern in write buffer
      # Horizontal blinker: (2,1), (2,2), (2,3) = positions 11, 12, 13
      expect(@cpu.memory.read(0x30 + 11)).to eq('X'.ord), "Cell (2,1) should be alive"
      expect(@cpu.memory.read(0x30 + 12)).to eq('X'.ord), "Cell (2,2) should be alive"
      expect(@cpu.memory.read(0x30 + 13)).to eq('X'.ord), "Cell (2,3) should be alive"

      # Old vertical positions (except center) should be dead
      expect(@cpu.memory.read(0x30 + 7)).to eq('.'.ord), "Cell (1,2) should be dead"
      expect(@cpu.memory.read(0x30 + 17)).to eq('.'.ord), "Cell (3,2) should be dead"
    end
  end

  private

  def print_5x5_grid(memory, base_addr)
    (0...5).each do |row|
      line = ""
      (0...5).each do |col|
        char = memory.read(base_addr + row * 5 + col)
        line << (char == 'X'.ord ? 'X' : '.')
      end
      puts line
    end
  end
end
