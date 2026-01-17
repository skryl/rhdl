require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu'

RSpec.describe 'MOS6502 Complex Programs' do
  let(:cpu) { MOS6502::CPU.new }

  describe 'Bubble sort' do
    it 'sorts an array of numbers' do
      # Sort 5 elements using indexed addressing
      source = <<~'ASM'
        ; Bubble sort 5 elements at $10-$14
        ; Uses $20 as swap flag

      OUTER:
        LDA #$00
        STA $20           ; swapped = false
        LDX #$00          ; index = 0

      INNER:
        LDA $10,X         ; Get arr[i]
        STA $21           ; Save in temp
        INX
        CMP $10,X         ; Compare with arr[i+1]
        BCC NO_SWAP       ; If arr[i] < arr[i+1], no swap needed
        BEQ NO_SWAP       ; If equal, no swap needed

        ; Swap arr[i] and arr[i+1]
        LDA $10,X         ; Get arr[i+1]
        DEX
        STA $10,X         ; Store at arr[i]
        INX
        LDA $21           ; Get saved arr[i]
        STA $10,X         ; Store at arr[i+1]

        LDA #$01
        STA $20           ; swapped = true

      NO_SWAP:
        CPX #$04          ; Done when X reaches 4
        BNE INNER

        LDA $20           ; Check if we swapped
        BNE OUTER         ; If swapped, do another pass

        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      # Set up unsorted array at $10-$14
      cpu.write_mem(0x10, 5)
      cpu.write_mem(0x11, 2)
      cpu.write_mem(0x12, 8)
      cpu.write_mem(0x13, 1)
      cpu.write_mem(0x14, 9)

      500.times do
        cpu.step
        break if cpu.halted?
      end

      # Should be sorted: 1, 2, 5, 8, 9
      expect(cpu.read_mem(0x10)).to eq(1)
      expect(cpu.read_mem(0x11)).to eq(2)
      expect(cpu.read_mem(0x12)).to eq(5)
      expect(cpu.read_mem(0x13)).to eq(8)
      expect(cpu.read_mem(0x14)).to eq(9)
    end
  end

  describe 'Fibonacci sequence' do
    it 'computes Fibonacci numbers' do
      # Compute first 10 Fibonacci numbers at $10-$19
      source = <<~'ASM'
        ; Initialize F(0)=0, F(1)=1
        LDA #$00
        STA $10           ; F(0) = 0
        LDA #$01
        STA $11           ; F(1) = 1

        LDX #$02          ; Start at index 2
      FIB_LOOP:
        ; F(n) = F(n-1) + F(n-2)
        DEX
        LDA $10,X         ; F(n-1)
        STA $20           ; Save it
        DEX
        CLC
        LDA $10,X         ; F(n-2)
        ADC $20           ; F(n-2) + F(n-1)
        INX
        INX
        STA $10,X         ; Store F(n)
        INX               ; Move to next
        CPX #$0A          ; Compute 10 numbers
        BNE FIB_LOOP
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      200.times do
        cpu.step
        break if cpu.halted?
      end

      # Fibonacci: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34
      expect(cpu.read_mem(0x10)).to eq(0)
      expect(cpu.read_mem(0x11)).to eq(1)
      expect(cpu.read_mem(0x12)).to eq(1)
      expect(cpu.read_mem(0x13)).to eq(2)
      expect(cpu.read_mem(0x14)).to eq(3)
      expect(cpu.read_mem(0x15)).to eq(5)
      expect(cpu.read_mem(0x16)).to eq(8)
      expect(cpu.read_mem(0x17)).to eq(13)
      expect(cpu.read_mem(0x18)).to eq(21)
      expect(cpu.read_mem(0x19)).to eq(34)
    end
  end

  describe 'Memory fill' do
    it 'fills a memory range with a value' do
      # Fill $20-$2F with $AA
      source = <<~'ASM'
        LDX #$00
        LDA #$AA
      FILL:
        STA $20,X
        INX
        CPX #$10
        BNE FILL
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      100.times do
        cpu.step
        break if cpu.halted?
      end

      (0x20..0x2F).each do |addr|
        expect(cpu.read_mem(addr)).to eq(0xAA), "Expected $AA at #{addr.to_s(16)}"
      end
    end
  end

  describe 'Sum array' do
    it 'computes sum of array elements' do
      # Sum 5 numbers at $10-$14, result in $20
      source = <<~'ASM'
        LDA #$00
        STA $20           ; sum = 0
        LDX #$00
      SUM_LOOP:
        CLC
        LDA $20
        ADC $10,X         ; sum += arr[X]
        STA $20
        INX
        CPX #$05
        BNE SUM_LOOP
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      # Set up array: 10, 20, 30, 40, 50 (sum = 150)
      cpu.write_mem(0x10, 10)
      cpu.write_mem(0x11, 20)
      cpu.write_mem(0x12, 30)
      cpu.write_mem(0x13, 40)
      cpu.write_mem(0x14, 50)

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(150)
    end
  end

  describe 'Find maximum' do
    it 'finds maximum value in array' do
      # Find max in 5 elements at $10-$14, result in $20
      source = <<~'ASM'
        LDA $10           ; max = arr[0]
        STA $20
        LDX #$01
      MAX_LOOP:
        LDA $10,X         ; Get arr[X]
        CMP $20           ; Compare with max
        BCC NOT_MAX       ; If arr[X] < max, skip
        STA $20           ; max = arr[X]
      NOT_MAX:
        INX
        CPX #$05
        BNE MAX_LOOP
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      # Set up array
      cpu.write_mem(0x10, 15)
      cpu.write_mem(0x11, 42)
      cpu.write_mem(0x12, 8)
      cpu.write_mem(0x13, 99)
      cpu.write_mem(0x14, 23)

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(99)
    end
  end
end
