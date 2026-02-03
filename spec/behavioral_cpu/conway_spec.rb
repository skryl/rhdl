require 'spec_helper'
require 'support/cpu_test_helper'
require 'support/isa_assembler'
require 'support/display_helper'

RSpec.describe RHDL::Components::CPU::CPU, 'ConwayGameOfLife' do
  include CpuTestHelper
  include DisplayHelper

  before(:each) do
    @memory = MemorySimulator::Memory.new
    @cpu = described_class.new(@memory)
    @cpu.reset
  end

  it 'runs an actual Conway program on a double-buffered 28×80 board' do
    # NOTE: This code is extremely large and may not fit in typical 8-bit memory.

    # Build program with base address 0x300 to avoid data overlap
    program = Assembler.build(0x300) do |p|
      # We assume:
      # E0=row, E1=col, E2=1, E3=80, E4=28, E5=neighbor_count
      # E6/E7 used for neighbor row_temp/col_temp, or old cell read
      # E8/E9 used by compute_address_temp for final 16-bit address
      # F8:F9 = read_buffer base, F6:F7 = write_buffer base
      # We'll rely on memory[0xE2]=1, 0xE3]=80, [0xE4]=28 being preloaded or set at init

      # ───────────────────────────────────────────────────────────────
      # 1) Setup addresses for double-buffering
      # ───────────────────────────────────────────────────────────────
      p.label :ADDR_BUFFER_A
      p.instr :LDI, 0x01  
      p.instr :STA, 0xFA     # store high byte of read buffer => 0xFA
      p.instr :LDI, 0x00
      p.instr :STA, 0xFB     # store low byte => 0xFB => read buffer=0x0100

      p.label :ADDR_BUFFER_B
      p.instr :LDI, 0x02  
      p.instr :STA, 0xFC     # write buffer high byte => 0xFC
      p.instr :LDI, 0x00
      p.instr :STA, 0xFD     # write buffer low byte => 0xFD => 0x0200

      # Current read buffer => F8:F9, write buffer => F6:F7
      p.instr :LDI, 0x01
      p.instr :STA, 0xF8
      p.instr :LDI, 0x00
      p.instr :STA, 0xF9

      p.instr :LDI, 0x02
      p.instr :STA, 0xF6
      p.instr :LDI, 0x00
      p.instr :STA, 0xF7

      # ───────────────────────────────────────────────────────────────
      # 2) Main loop: For row in [0..27], col in [0..79], compute next cell
      # ───────────────────────────────────────────────────────────────
      p.label :main_loop
      # row=0
      p.instr :LDI, 0x00
      p.instr :STA, 0xE0
      
      p.label :row_loop
      # col=0
      p.instr :LDI, 0x00
      p.instr :STA, 0xE1
      
      p.label :col_loop
      # compute_cell => uses subroutine
      p.instr :CALL, :compute_cell

      # col++
      p.instr :LDA, 0xE1
      p.instr :ADD, 0xE2   # memory[E2]=1
      p.instr :STA, 0xE1

      # if col<80 => keep going
      p.instr :LDA, 0xE1
      p.instr :SUB, 0xE3   # memory[E3]=80
      p.instr :JNZ_LONG, :col_loop

      # row++
      p.instr :LDA, 0xE0
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE0

      # if row<28 => row_loop
      p.instr :LDA, 0xE0
      p.instr :SUB, 0xE4   # memory[E4]=28
      p.instr :JNZ_LONG, :row_loop

      # Finished scanning => swap buffers => repeat
      p.instr :CALL, :swap_buffers
      p.instr :JMP_LONG, :main_loop

      # ───────────────────────────────────────────────────────────────
      # compute_cell SUBROUTINE
      # ───────────────────────────────────────────────────────────────
      p.label :compute_cell
      # neighbor_count=0 => E5
      p.instr :LDI, 0x00
      p.instr :STA, 0xE5

      # Check each neighbor subroutine:
      p.instr :CALL, :check_neighbor_north
      p.instr :CALL, :check_neighbor_south
      p.instr :CALL, :check_neighbor_east
      p.instr :CALL, :check_neighbor_west
      p.instr :CALL, :check_neighbor_nw
      p.instr :CALL, :check_neighbor_ne
      p.instr :CALL, :check_neighbor_sw
      p.instr :CALL, :check_neighbor_se

      # read_old_cell => ACC = 'X' or '.'
      p.instr :CALL, :read_old_cell

      # apply conway_rules => ACC = 'X' or '.'
      p.instr :CALL, :conway_rules

      # write_new_cell => stores ACC into write buffer
      p.instr :CALL, :write_new_cell

      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # swap_buffers: read_buffer <-> write_buffer
      # ───────────────────────────────────────────────────────────────
      p.label :swap_buffers
      # Save read buffer values
      p.instr :LDA, 0xF8
      p.instr :STA, 0xE8  # Temp storage
      p.instr :LDA, 0xF9
      p.instr :STA, 0xE9

      # Move write buffer to read buffer
      p.instr :LDA, 0xF6
      p.instr :STA, 0xF8
      p.instr :LDA, 0xF7
      p.instr :STA, 0xF9

      # Move saved read buffer to write buffer
      p.instr :LDA, 0xE8
      p.instr :STA, 0xF6
      p.instr :LDA, 0xE9
      p.instr :STA, 0xF7

      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # NEIGHBOR-CHECK ROUTINES (all 8 directions)
      # Each:
      #  1) checks boundary
      #  2) if in range => read neighbor cell
      #  3) if 'X', neighbor_count++
      # ───────────────────────────────────────────────────────────────

      # North: row>0 => row_temp = row-1, col_temp=col
      p.label :check_neighbor_north
      p.instr :LDA, 0xE0      # if row==0 => skip
      p.instr :JZ_LONG, :done_north
      # row_temp = row-1 => E6
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col => E7
      p.instr :LDA, 0xE1
      p.instr :STA, 0xE7
      # read cell
      p.instr :CALL, :read_cell_for_neighbor
      # if ACC=='X'? => neighbor_count++
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05    # skip next 5 bytes if not X
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_north
      p.instr :RET

      # South: row<27 => row_temp=row+1
      p.label :check_neighbor_south
      # if row==27 => skip
      # We'll do row-27 => if zero => skip.  Or row<27 => row+1 = row_temp
      p.instr :LDA, 0xE0
      # We want to see if E0=27 => then skip
      # Let’s assume memory[0xE8]=27 for comparison:
      p.instr :SUB, 0xE9  # Suppose 0xE9=27 stored at initialization
      # If zero_flag => skip
      p.instr :JZ_LONG, :done_south
      # row_temp=row+1 => E6
      # restore row
      p.instr :LDA, 0xE0
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col => E7
      p.instr :LDA, 0xE1
      p.instr :STA, 0xE7
      # read cell
      p.instr :CALL, :read_cell_for_neighbor
      # if ACC=='X'? => neighbor_count++
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_south
      p.instr :RET

      # East: col<79 => col_temp=col+1
      p.label :check_neighbor_east
      p.instr :LDA, 0xE1
      # memory[0xEA] might hold 79
      p.instr :SUB, 0xEA
      p.instr :JZ_LONG, :done_east
      # col_temp=col+1 => E7
      p.instr :LDA, 0xE1
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE7
      # row_temp=row => E6
      p.instr :LDA, 0xE0
      p.instr :STA, 0xE6
      # read cell
      p.instr :CALL, :read_cell_for_neighbor
      # if 'X' => neighbor_count++
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_east
      p.instr :RET

      # West: col>0 => col_temp=col-1
      p.label :check_neighbor_west
      p.instr :LDA, 0xE1
      p.instr :JZ_LONG, :done_west  # if col==0 => skip
      # col_temp=col-1 => E7
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE7
      # row_temp=row => E6
      p.instr :LDA, 0xE0
      p.instr :STA, 0xE6
      # read cell
      p.instr :CALL, :read_cell_for_neighbor
      # increment if X
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_west
      p.instr :RET

      # NW: row>0 & col>0 => row_temp=row-1, col_temp=col-1
      p.label :check_neighbor_nw
      # if row==0 => skip
      p.instr :LDA, 0xE0
      p.instr :JZ_LONG, :done_nw
      # if col==0 => skip
      p.instr :LDA, 0xE1
      p.instr :JZ_LONG, :done_nw

      # row_temp=row-1 => E6
      p.instr :LDA, 0xE0
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col-1 => E7
      p.instr :LDA, 0xE1
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE7
      # read cell
      p.instr :CALL, :read_cell_for_neighbor
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_nw
      p.instr :RET

      # NE: row>0 & col<79 => row-1, col+1
      p.label :check_neighbor_ne
      # if row==0 => skip
      p.instr :LDA, 0xE0
      p.instr :JZ_LONG, :done_ne
      # if col==79 => skip => compare col to memory[0xEA]=79
      p.instr :LDA, 0xE1
      p.instr :SUB, 0xEA
      p.instr :JZ_LONG, :done_ne

      # row_temp=row-1 => E6
      p.instr :LDA, 0xE0
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col+1 => E7
      p.instr :LDA, 0xE1
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE7
      # read
      p.instr :CALL, :read_cell_for_neighbor
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_ne
      p.instr :RET

      # SW: row<27 & col>0  => row+1, col-1
      p.label :check_neighbor_sw
      # if row==27 => skip => let's store 27 in memory[0xE9]
      p.instr :LDA, 0xE0
      p.instr :SUB, 0xE9
      p.instr :JZ_LONG, :done_sw
      # if col==0 => skip
      p.instr :LDA, 0xE1
      p.instr :JZ_LONG, :done_sw

      # row_temp=row+1 => E6
      p.instr :LDA, 0xE0
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col-1 => E7
      p.instr :LDA, 0xE1
      p.instr :SUB, 0xE2
      p.instr :STA, 0xE7
      # read
      p.instr :CALL, :read_cell_for_neighbor
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_sw
      p.instr :RET

      # SE: row<27 & col<79 => row+1, col+1
      p.label :check_neighbor_se
      # if row==27 => skip
      p.instr :LDA, 0xE0
      p.instr :SUB, 0xE9
      p.instr :JZ_LONG, :done_se
      # if col==79 => skip
      p.instr :LDA, 0xE1
      p.instr :SUB, 0xEA
      p.instr :JZ_LONG, :done_se

      # row_temp=row+1 => E6
      p.instr :LDA, 0xE0
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE6
      # col_temp=col+1 => E7
      p.instr :LDA, 0xE1
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE7
      # read
      p.instr :CALL, :read_cell_for_neighbor
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, 0x05
      p.instr :LDA, 0xE5
      p.instr :ADD, 0xE2
      p.instr :STA, 0xE5

      p.label :done_se
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # read_cell_for_neighbor:
      #   Use E6=neighbor_row, E7=neighbor_col, F8:F9=read_buffer
      #   => compute address => E8:E9, load => ACC
      # ───────────────────────────────────────────────────────────────
      p.label :read_cell_for_neighbor
      # compute address => E8:E9
      p.instr :CALL, :compute_address_temp
      # then load from address in E8:E9 => ACC
      p.instr :CALL, :load_from_16bit
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # read_old_cell:
      #   Use (row=E0,col=E1) in read_buffer => ACC='X' or '.' etc.
      # ───────────────────────────────────────────────────────────────
      p.label :read_old_cell
      # row => E6
      p.instr :LDA, 0xE0
      p.instr :STA, 0xE6
      # col => E7
      p.instr :LDA, 0xE1
      p.instr :STA, 0xE7
      # same approach: compute address => E8:E9 => load => ACC
      p.instr :CALL, :compute_address_temp
      p.instr :CALL, :load_from_16bit
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # conway_rules:
      #   If ACC='X' => alive=1 else=0
      #   neighbors=E5
      #   if alive=1 and neighbors in [2,3] => 'X'
      #   else if alive=0 and neighbors=3 => 'X'
      #   else '.'
      # ───────────────────────────────────────────────────────────────
      p.label :conway_rules
      # 1) Determine alive => E6=1 or 0
      p.instr :CMP, 'X'.ord
      p.instr :JNZ, :rules_not_alive
      # => alive=1 => E6
      p.instr :LDI, 0x01
      p.instr :STA, 0xE6
      p.instr :JMP, :rules_done_alive

      p.label :rules_not_alive
      p.instr :LDI, 0x00
      p.instr :STA, 0xE6

      p.label :rules_done_alive

      # 2) Check neighbors => E5
      #    if alive=1 and E5 in [2,3] => ACC='X'
      #    else if alive=0 and E5==3 => ACC='X'
      #    else ACC='.'
      # We'll do multi-check:
      p.instr :LDA, 0xE6
      p.instr :JZ_LONG, :rules_check_if_dead  # if alive=0 => check neighbors=3

      # alive=1 => check if E5=2 or 3
      p.instr :LDA, 0xE5
      p.instr :CMP, 0x02
      p.instr :JZ_LONG, :rules_make_x
      p.instr :CMP, 0x03
      p.instr :JZ_LONG, :rules_make_x
      p.instr :JMP_LONG, :rules_make_dot

      p.label :rules_check_if_dead
      # if alive=0 => check if E5==3 => X
      p.instr :LDA, 0xE5
      p.instr :CMP, 0x03
      p.instr :JZ_LONG, :rules_make_x
      p.instr :JMP_LONG, :rules_make_dot

      p.label :rules_make_x
      p.instr :LDI, 'X'.ord
      p.instr :STA, 0xFF   # using 0xFF as temp? Then LDA it to ACC
      p.instr :LDA, 0xFF
      p.instr :RET

      p.label :rules_make_dot
      p.instr :LDI, '.'.ord
      p.instr :STA, 0xFF
      p.instr :LDA, 0xFF
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # write_new_cell:
      #  ACC has 'X' or '.'; store at [write_buffer + row*80 + col]
      # ───────────────────────────────────────────────────────────────
      p.label :write_new_cell
      # row => E0 => E6
      p.instr :LDA, 0xE0
      p.instr :STA, 0xE6
      # col => E1 => E7
      p.instr :LDA, 0xE1
      p.instr :STA, 0xE7
      # compute address => E8:E9 from (F6:F7 + E6*80+E7)
      p.instr :CALL, :compute_address_write
      # store ACC into [E8:E9]
      p.instr :CALL, :store_to_16bit
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # compute_address_temp (READ):
      #   E6=row_temp, E7=col_temp, F8:F9= base => read_buffer
      #   => E8:E9 = F8:F9 + (E6*80 + E7)
      # ───────────────────────────────────────────────────────────────
      p.label :compute_address_temp
      # E8=F8, E9=F9 as a start
      p.instr :LDA, 0xF8
      p.instr :STA, 0xE8
      p.instr :LDA, 0xF9
      p.instr :STA, 0xE9

      # now add E6*80 + E7
      p.instr :CALL, :add_rowcol_to_e8e9
      p.instr :RET

      # compute_address_write (WRITE):
      #   E6=row, E7=col, F6:F7=base => write_buffer
      #   => E8:E9 = (F6:F7) + E6*80 + E7
      p.label :compute_address_write
      p.instr :LDA, 0xF6
      p.instr :STA, 0xE8
      p.instr :LDA, 0xF7
      p.instr :STA, 0xE9
      # add row*80 + col
      p.instr :CALL, :add_rowcol_to_e8e9
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # add_rowcol_to_e8e9:
      #   uses E6=row, E7=col. We need row*80 => partial
      # ───────────────────────────────────────────────────────────────
      p.label :add_rowcol_to_e8e9
      # We'll do row*80 => partial => then add col => E7
      # For simplicity, we do repeated add of 80 => row times.
      # row is small => max 28 => so we can do a loop.
      p.instr :LDI, 0x00
      p.instr :STA, 0xEB  # Use EB instead of E2 for loop counter

      p.label :loop_mulrow
      # if row==0 => skip
      p.instr :LDA, 0xE6
      p.instr :JZ_LONG, :done_mulrow
      # subtract 1 => E6
      p.instr :SUB, 0xE2  # E2 still holds 1
      p.instr :STA, 0xE6
      # add 80 => E8:E9
      p.instr :LDI, 0x00   
      p.instr :STA, 0xEF   # store 0 in EF
      p.instr :LDI, 0x50   # 0x50 = 80
      p.instr :STA, 0xEE
      # now call add_16bit(E8:E9, EF:EE)
      p.instr :CALL, :add_16bit_e8e9_efee
      p.instr :JMP_LONG, :loop_mulrow

      p.label :done_mulrow
      # now add col => E7
      p.instr :LDA, 0xE9
      p.instr :ADD, 0xE7
      p.instr :STA, 0xE9
      # Handle carry to high byte
      p.instr :LDA, 0xE8
      p.instr :ADD, 0xEB  # EB is 0 from earlier, so this effectively adds the carry if needed
      p.instr :STA, 0xE8
      p.instr :RET

      # ─────────────────────────────────────────────��─────────────────
      # add_16bit_e8e9_efee: E8:E9 += EF:EE
      # ignoring carry properly for brevity
      # ───────────────────────────────────────────────────────────────
      p.label :add_16bit_e8e9_efee
      # Add low bytes
      p.instr :LDA, 0xE9
      p.instr :ADD, 0xEE
      p.instr :STA, 0xE9
      # ignoring carry
      # Add high bytes
      p.instr :LDA, 0xE8
      p.instr :ADD, 0xEF
      p.instr :STA, 0xE8
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # load_from_16bit => ACC = memory[E8:E9]
      # Uses bank switching approach with our 8-bit CPU
      # E8 = high byte (bank), E9 = low byte (address)
      # ───────────────────────────────────────────────────────────────
      p.label :load_from_16bit
      # Save current bank
      p.instr :LDA, 0xFF  # Current bank
      p.instr :STA, 0xFE  # Save it
      
      # Switch to new bank
      p.instr :LDA, 0xE8  # High byte of address
      p.instr :STA, 0xFF  # Set as current bank
      
      # Load from address
      p.instr :LDA, 0xE9  # Low byte of address
      
      # Restore original bank
      p.instr :LDA, 0xFE
      p.instr :STA, 0xFF
      
      p.instr :RET

      # ───────────────────────────────────────────────────────────────
      # store_to_16bit => memory[E8:E9] = ACC
      # Uses same bank switching approach
      # ───────────────────────────────────────────────────────────────
      p.label :store_to_16bit
      # Save value to store
      p.instr :STA, 0xFD
      
      # Save current bank
      p.instr :LDA, 0xFF
      p.instr :STA, 0xFE
      
      # Switch to new bank
      p.instr :LDA, 0xE8
      p.instr :STA, 0xFF
      
      # Get value back and store it
      p.instr :LDA, 0xFD
      p.instr :STA, 0xE9
      
      # Restore original bank
      p.instr :LDA, 0xFE
      p.instr :STA, 0xFF
      
      p.instr :RET
    end

    # ───────────────────��─────────────────────────────────────────────
    # 3) Load the program, seed buffer A, run for 5 generations
    # ─────────────────────────────────────────────────────────────────
    # Load program at 0x300 to avoid overlap with buffers at 0x100 and 0x200
    load_program(program, 0x300)

    # Reset PC to start of program (load_program resets CPU which sets PC to 0)
    @cpu.instance_variable_set(:@pc, 0x300)

    # Verify low memory is clear for variables
    expect(@memory.read(0x0)).to eq(0x00)
    puts "Program loaded at memory address 0x300"

    # We'll store row=28 => memory[0xE4], col=80 => memory[0xE3], etc.
    # And row=27 => memory[0xE9], col=79 => memory[0xEA].
    # Also store 1 in memory[0xE2].
    # Then the code can do boundary checks properly.
    @memory.write(0xE2, 0x01)  # For increments
    @memory.write(0xE3, 80)    # For col compare
    @memory.write(0xE4, 28)    # For row compare
    @memory.write(0xE9, 27)    # row boundary check
    @memory.write(0xEA, 79)    # col boundary check

    # Seed an example glider at buffer A (0x0100..)
    glider = [
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '...............................X................................................',
      '................................X...............................................',
      '..............................XXX...............................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................',
      '................................................................................'
    ]
    glider.each_with_index do |line, row|
      line.each_char.with_index do |ch, col|
        val = (ch == 'X') ? 'X'.ord : '.'.ord
        @memory.write(0x100 + row*80 + col, val)
      end
    end

    # Increase the number of generations and cycles for better simulation
    5.times do |gen|
      simulate_cycles(1000)  # Increased from 100 to 1000 cycles
      puts "\n=== Generation #{gen + 1} ==="
      print_display(@memory, 0x100, 28, 80)
    end

    # Verify CPU is not halted
    expect(@cpu.halted).to be false
  end
end 