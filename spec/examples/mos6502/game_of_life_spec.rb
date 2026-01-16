require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu'

RSpec.describe "Conway's Game of Life on 6502" do
  let(:cpu) { MOS6502::CPU.new }

  # Grid layout: 8x8 grid stored at $00-$3F (64 bytes)
  # Each byte is 0 (dead) or 1 (alive)
  # Row 0: $00-$07, Row 1: $08-$0F, etc.
  # Next generation buffer at $40-$7F

  describe 'Neighbor counting' do
    it 'counts neighbors for a cell' do
      # Count neighbors for cell at (2,2) which is address 2*8+2 = 18
      source = <<~'ASM'
        ; Count neighbors for cell at $12 (address 18 = row 2, col 2)
        ; Result in $20

        LDA #$00
        STA $20           ; neighbor count = 0

        ; Neighbors of cell at address 18:
        ; (-1,-1): 18-9 = 9,  (-1,0): 18-8 = 10, (-1,+1): 18-7 = 11
        ; ( 0,-1): 18-1 = 17,                    ( 0,+1): 18+1 = 19
        ; (+1,-1): 18+7 = 25, (+1,0): 18+8 = 26, (+1,+1): 18+9 = 27

        LDA $09           ; top-left
        BEQ N1
        INC $20
      N1:
        LDA $0A           ; top
        BEQ N2
        INC $20
      N2:
        LDA $0B           ; top-right
        BEQ N3
        INC $20
      N3:
        LDA $11           ; left (17 = $11)
        BEQ N4
        INC $20
      N4:
        LDA $13           ; right (19 = $13)
        BEQ N5
        INC $20
      N5:
        LDA $19           ; bottom-left (25 = $19)
        BEQ N6
        INC $20
      N6:
        LDA $1A           ; bottom (26 = $1A)
        BEQ N7
        INC $20
      N7:
        LDA $1B           ; bottom-right (27 = $1B)
        BEQ N8
        INC $20
      N8:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      # Set up 3 neighbors: (1,1)=9, (1,2)=10, (3,2)=26
      cpu.write_mem(0x09, 1)  # (1,1) - top-left
      cpu.write_mem(0x0A, 1)  # (1,2) - top
      cpu.write_mem(0x1A, 1)  # (3,2) - bottom

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(3)
    end
  end

  describe 'Game rules' do
    it 'dead cell with exactly 3 neighbors becomes alive' do
      source = <<~'ASM'
        LDA #$00
        STA $10           ; cell is dead
        LDA #$03
        STA $11           ; 3 neighbors

        LDA $10
        BNE CHECK_ALIVE

        LDA $11
        CMP #$03
        BNE STAY_DEAD
        LDA #$01
        JMP STORE
      STAY_DEAD:
        LDA #$00
        JMP STORE

      CHECK_ALIVE:
        LDA $11
        CMP #$02
        BEQ SURVIVE
        CMP #$03
        BEQ SURVIVE
        LDA #$00
        JMP STORE
      SURVIVE:
        LDA #$01

      STORE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(1)
    end

    it 'live cell with 2 neighbors survives' do
      source = <<~'ASM'
        LDA #$01
        STA $10           ; cell is alive
        LDA #$02
        STA $11           ; 2 neighbors

        LDA $10
        BNE CHECK_ALIVE

        LDA $11
        CMP #$03
        BNE STAY_DEAD
        LDA #$01
        JMP STORE
      STAY_DEAD:
        LDA #$00
        JMP STORE

      CHECK_ALIVE:
        LDA $11
        CMP #$02
        BEQ SURVIVE
        CMP #$03
        BEQ SURVIVE
        LDA #$00
        JMP STORE
      SURVIVE:
        LDA #$01

      STORE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(1)
    end

    it 'live cell with 1 neighbor dies (underpopulation)' do
      source = <<~'ASM'
        LDA #$01
        STA $10           ; cell is alive
        LDA #$01
        STA $11           ; only 1 neighbor

        LDA $10
        BNE CHECK_ALIVE

        LDA $11
        CMP #$03
        BNE STAY_DEAD
        LDA #$01
        JMP STORE
      STAY_DEAD:
        LDA #$00
        JMP STORE

      CHECK_ALIVE:
        LDA $11
        CMP #$02
        BEQ SURVIVE
        CMP #$03
        BEQ SURVIVE
        LDA #$00
        JMP STORE
      SURVIVE:
        LDA #$01

      STORE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(0)
    end

    it 'live cell with 4 neighbors dies (overpopulation)' do
      source = <<~'ASM'
        LDA #$01
        STA $10           ; cell is alive
        LDA #$04
        STA $11           ; 4 neighbors

        LDA $10
        BNE CHECK_ALIVE

        LDA $11
        CMP #$03
        BNE STAY_DEAD
        LDA #$01
        JMP STORE
      STAY_DEAD:
        LDA #$00
        JMP STORE

      CHECK_ALIVE:
        LDA $11
        CMP #$02
        BEQ SURVIVE
        CMP #$03
        BEQ SURVIVE
        LDA #$00
        JMP STORE
      SURVIVE:
        LDA #$01

      STORE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(0)
    end
  end

  describe 'Pattern evolution' do
    # Helper to run one generation
    def generation_code
      # Process cells and apply rules - compact version
      <<~'ASM'
        ; Process one generation of Game of Life
        ; Grid at $00-$3F, next gen at $40-$7F

        LDX #$09          ; Start at cell (1,1)

      CELL_LOOP:
        STX $70           ; Save cell address

        ; Skip boundary (cols 0 and 7)
        TXA
        AND #$07
        BNE NOT_COL0
        JMP SKIP_CELL
      NOT_COL0:
        CMP #$07
        BNE NOT_COL7
        JMP SKIP_CELL
      NOT_COL7:

        ; Count neighbors using Y for address calc
        LDA #$00
        STA $71           ; count = 0

        ; Neighbor at X-9
        TXA
        SEC
        SBC #$09
        TAY
        LDA $00,Y
        BEQ N1
        INC $71
      N1:
        ; X-8
        TXA
        SEC
        SBC #$08
        TAY
        LDA $00,Y
        BEQ N2
        INC $71
      N2:
        ; X-7
        TXA
        SEC
        SBC #$07
        TAY
        LDA $00,Y
        BEQ N3
        INC $71
      N3:
        ; X-1
        TXA
        SEC
        SBC #$01
        TAY
        LDA $00,Y
        BEQ N4
        INC $71
      N4:
        ; X+1
        TXA
        CLC
        ADC #$01
        TAY
        LDA $00,Y
        BEQ N5
        INC $71
      N5:
        ; X+7
        TXA
        CLC
        ADC #$07
        TAY
        LDA $00,Y
        BEQ N6
        INC $71
      N6:
        ; X+8
        TXA
        CLC
        ADC #$08
        TAY
        LDA $00,Y
        BEQ N7
        INC $71
      N7:
        ; X+9
        TXA
        CLC
        ADC #$09
        TAY
        LDA $00,Y
        BEQ N8
        INC $71
      N8:

        ; Apply rules
        LDX $70
        LDA $00,X         ; Current state
        BNE ALIVE

        ; Dead: birth with 3 neighbors
        LDA $71
        CMP #$03
        BNE SET_DEAD
        LDA #$01
        JMP STORE
      SET_DEAD:
        LDA #$00
        JMP STORE

      ALIVE:
        ; Survive with 2 or 3
        LDA $71
        CMP #$02
        BEQ SET_ALIVE
        CMP #$03
        BEQ SET_ALIVE
        LDA #$00
        JMP STORE
      SET_ALIVE:
        LDA #$01

      STORE:
        STA $40,X

      SKIP_CELL:
        LDX $70
        INX
        CPX #$38
        BEQ DONE
        JMP CELL_LOOP

      DONE:
        ; Copy next gen to current
        LDX #$00
      COPY:
        LDA $40,X
        STA $00,X
        INX
        CPX #$40
        BNE COPY
        BRK
      ASM
    end

    it 'blinker oscillates (vertical to horizontal)' do
      # Blinker: 3 cells in a vertical line -> horizontal line
      # Vertical at (2,3), (3,3), (4,3): addresses 19, 27, 35
      # Horizontal at (3,2), (3,3), (3,4): addresses 26, 27, 28

      cpu.assemble_and_load(generation_code)
      cpu.reset

      # Set up vertical blinker
      cpu.write_mem(19, 1)  # (2,3)
      cpu.write_mem(27, 1)  # (3,3)
      cpu.write_mem(35, 1)  # (4,3)

      5000.times do
        cpu.step
        break if cpu.halted?
      end

      # Should now be horizontal
      expect(cpu.read_mem(19)).to eq(0)  # (2,3) dead
      expect(cpu.read_mem(26)).to eq(1)  # (3,2) alive
      expect(cpu.read_mem(27)).to eq(1)  # (3,3) alive
      expect(cpu.read_mem(28)).to eq(1)  # (3,4) alive
      expect(cpu.read_mem(35)).to eq(0)  # (4,3) dead
    end

    it 'block remains stable' do
      # Block: 2x2 square at (2,2), (2,3), (3,2), (3,3)
      # Addresses: 18, 19, 26, 27

      cpu.assemble_and_load(generation_code)
      cpu.reset

      cpu.write_mem(18, 1)
      cpu.write_mem(19, 1)
      cpu.write_mem(26, 1)
      cpu.write_mem(27, 1)

      5000.times do
        cpu.step
        break if cpu.halted?
      end

      # Block unchanged
      expect(cpu.read_mem(18)).to eq(1)
      expect(cpu.read_mem(19)).to eq(1)
      expect(cpu.read_mem(26)).to eq(1)
      expect(cpu.read_mem(27)).to eq(1)
    end

    it 'single cell dies (underpopulation)' do
      cpu.assemble_and_load(generation_code)
      cpu.reset

      # Single cell at (3,3) = address 27
      cpu.write_mem(27, 1)

      5000.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(27)).to eq(0)
    end

    it 'L-shape creates block' do
      # Three cells in L create a 4th
      # (2,2), (2,3), (3,2) -> adds (3,3)

      cpu.assemble_and_load(generation_code)
      cpu.reset

      cpu.write_mem(18, 1)  # (2,2)
      cpu.write_mem(19, 1)  # (2,3)
      cpu.write_mem(26, 1)  # (3,2)

      5000.times do
        cpu.step
        break if cpu.halted?
      end

      # Should form a block
      expect(cpu.read_mem(18)).to eq(1)
      expect(cpu.read_mem(19)).to eq(1)
      expect(cpu.read_mem(26)).to eq(1)
      expect(cpu.read_mem(27)).to eq(1)  # New cell born
    end
  end
end
