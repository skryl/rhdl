require_relative '../spec_helper'
require_relative '../../../../examples/mos6502/hdl/harness'

RSpec.describe 'Mathematical computations on 6502', :slow do
  let(:cpu) { MOS6502::Harness.new }

  describe 'Multiplication by repeated addition' do
    it 'multiplies two numbers' do
      # Compute 7 * 6 = 42, result in $20
      source = <<~'ASM'
        ; Initialize values in code
        LDA #$07
        STA $10           ; multiplicand = 7
        LDA #$06
        STA $11           ; multiplier = 6

        LDA #$00
        STA $20           ; result = 0

        LDX $11           ; count = multiplier
      MUL_LOOP:
        CPX #$00
        BEQ MUL_DONE
        CLC
        LDA $20
        ADC $10           ; result += multiplicand
        STA $20
        DEX
        JMP MUL_LOOP
      MUL_DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(42)
    end
  end

  describe 'Division by repeated subtraction' do
    it 'divides with quotient and remainder' do
      # Divide 47 by 5 = 9 remainder 2
      source = <<~'ASM'
        LDA #$2F
        STA $10           ; dividend = 47
        LDA #$05
        STA $11           ; divisor = 5

        LDA #$00
        STA $20           ; quotient = 0

        LDA $10           ; A = dividend
      DIV_LOOP:
        CMP $11           ; Compare with divisor
        BCC DIV_DONE      ; If dividend < divisor, done
        SEC
        SBC $11           ; dividend -= divisor
        INC $20           ; quotient++
        JMP DIV_LOOP
      DIV_DONE:
        STA $21           ; remainder = what's left
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      150.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(9)   # quotient
      expect(cpu.read_mem(0x21)).to eq(2)   # remainder
    end
  end

  describe 'Counting bits set' do
    it 'counts number of 1 bits in a byte' do
      # Count bits in 0xAB = 10101011 = 5 bits set
      source = <<~'ASM'
        LDA #$00
        STA $20           ; count = 0

        LDX #$08          ; 8 bits to check
        LDA #$AB          ; value to count
      BIT_LOOP:
        LSR A             ; Shift right, bit 0 goes to carry
        BCC NO_BIT        ; If carry clear, no bit
        INC $20           ; count++
      NO_BIT:
        DEX
        BNE BIT_LOOP
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(5)
    end
  end

  describe 'Absolute value' do
    it 'computes absolute value of signed number' do
      # Absolute value of -50 (0xCE in two's complement) = 50
      source = <<~'ASM'
        LDA #$CE          ; -50 in two's complement
        BPL POSITIVE      ; If positive, done
        ; Negate: result = 0 - value
        EOR #$FF          ; Invert bits
        CLC
        ADC #$01          ; Add 1 (two's complement negation)
      POSITIVE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(50)
    end
  end

  describe 'Power of 2' do
    it 'computes 2^n using shift' do
      # Compute 2^5 = 32
      source = <<~'ASM'
        LDA #$01          ; Start with 1
        LDX #$05          ; count = 5
      POW_LOOP:
        CPX #$00
        BEQ POW_DONE
        ASL A             ; A = A * 2
        DEX
        JMP POW_LOOP
      POW_DONE:
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      50.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(32)
    end
  end

  describe 'Factorial' do
    it 'computes 5!' do
      # Compute 5! = 120
      source = <<~'ASM'
        LDA #$01
        STA $20           ; result = 1
        LDA #$05
        STA $10           ; n = 5

      FACT_LOOP:
        LDA $10
        CMP #$02          ; if n < 2, done
        BCC FACT_DONE

        ; result = result * n (by repeated addition)
        LDA $20
        STA $21           ; save current result
        LDA #$00
        STA $20           ; clear result for accumulation
        LDX $10           ; multiply by n
      MUL_INNER:
        CLC
        LDA $20
        ADC $21
        STA $20
        DEX
        BNE MUL_INNER

        DEC $10           ; n--
        JMP FACT_LOOP

      FACT_DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      500.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(120)  # 5! = 120
    end
  end

  describe 'GCD (Euclidean algorithm)' do
    it 'computes greatest common divisor' do
      # GCD(48, 18) = 6
      source = <<~'ASM'
        LDA #$30
        STA $10           ; a = 48
        LDA #$12
        STA $11           ; b = 18

      GCD_LOOP:
        LDA $11
        BEQ GCD_DONE      ; if b == 0, done (result in $10)

        ; Compute a mod b
        LDA $10
      MOD_LOOP:
        CMP $11
        BCC MOD_DONE      ; if a < b, done
        SEC
        SBC $11
        JMP MOD_LOOP
      MOD_DONE:
        ; Now A = a mod b
        LDX $11           ; temp = b
        STA $11           ; b = a mod b
        STX $10           ; a = temp (old b)
        JMP GCD_LOOP

      GCD_DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      200.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x10)).to eq(6)
    end
  end

  describe 'Check if power of 2' do
    it 'tests if number is a power of 2' do
      # 64 is a power of 2: (64 & 63) == 0
      source = <<~'ASM'
        LDA #$40          ; n = 64
        BEQ NOT_POW2      ; 0 is not a power of 2
        STA $21           ; save n
        SEC
        SBC #$01          ; n - 1 = 63
        AND $21           ; 64 & 63 = 0
        BNE NOT_POW2
        LDA #$01
        JMP STORE_RESULT
      NOT_POW2:
        LDA #$00
      STORE_RESULT:
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

    it 'returns 0 for non-power of 2' do
      # 48 is not a power of 2: (48 & 47) != 0
      source = <<~'ASM'
        LDA #$30          ; n = 48
        BEQ NOT_POW2
        STA $21
        SEC
        SBC #$01          ; n - 1 = 47
        AND $21           ; 48 & 47 = 32 (not zero)
        BNE NOT_POW2
        LDA #$01
        JMP STORE_RESULT
      NOT_POW2:
        LDA #$00
      STORE_RESULT:
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

  describe 'Byte reversal' do
    it 'reverses bit order of a byte' do
      # Reverse bits of 0xA5 (10100101) = 0xA5 (symmetric)
      # Let's use 0x1C (00011100) -> 0x38 (00111000)
      source = <<~'ASM'
        LDA #$1C          ; input = 00011100
        STA $10
        LDA #$00
        STA $20           ; output = 0

        LDX #$08          ; 8 bits
      REV_LOOP:
        ASL $20           ; Shift output left
        LSR $10           ; Shift input right, bit into carry
        BCC NO_SET
        INC $20           ; Set bit 0 of output
      NO_SET:
        DEX
        BNE REV_LOOP
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      100.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(0x38)
    end
  end
end
