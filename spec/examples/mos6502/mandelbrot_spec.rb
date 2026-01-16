require_relative 'spec_helper'
require_relative '../../../examples/mos6502/cpu'

RSpec.describe 'Mandelbrot set on 6502' do
  let(:cpu) { MOS6502::CPU.new }

  # Using 4.4 fixed-point format: 4 bits integer, 4 bits fraction
  # Range: -8.0 to +7.9375, resolution: 0.0625
  # Value = byte / 16.0 (or byte >> 4 for integer part)

  def to_fixed(float_val)
    val = (float_val * 16).round
    val & 0xFF
  end

  def from_fixed(byte_val)
    if byte_val > 127
      byte_val = byte_val - 256
    end
    byte_val / 16.0
  end

  describe 'Fixed-point multiplication' do
    it 'multiplies two 4.4 fixed-point numbers' do
      # Multiply 1.5 * 2.0 = 3.0
      # 1.5 = 0x18, 2.0 = 0x20
      # 0x18 * 0x20 = 768 = 0x0300, >> 4 = 0x30 = 48 = 3.0
      source = <<~'ASM'
        ; 4.4 fixed-point multiply: $10 * $11 -> $20
        LDA #$18          ; 1.5
        STA $10
        LDA #$20          ; 2.0
        STA $11

        ; 8-bit multiply with 16-bit result
        ; Use shift-and-add: result = 0, for each bit of multiplier,
        ; if set, add multiplicand to result, then shift multiplicand left

        LDA #$00
        STA $22           ; result_lo
        STA $23           ; result_hi
        STA $24           ; multiplicand_hi (for 16-bit shift)

        LDA $10
        STA $25           ; copy of multiplicand

        LDY #$08          ; 8 bits
      MUL_LOOP:
        LDA $11           ; multiplier
        AND #$01          ; test low bit
        BEQ SKIP_ADD

        ; Add multiplicand to result
        CLC
        LDA $22
        ADC $25
        STA $22
        LDA $23
        ADC $24
        STA $23

      SKIP_ADD:
        ; Shift multiplicand left (16-bit)
        ASL $25
        ROL $24

        ; Shift multiplier right
        LSR $11

        DEY
        BNE MUL_LOOP

        ; Divide by 16 (shift right 4) to get fixed-point result
        LDX #$04
      DIV_LOOP:
        LSR $23
        ROR $22
        DEX
        BNE DIV_LOOP

        LDA $22
        STA $20           ; final result
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      300.times do
        cpu.step
        break if cpu.halted?
      end

      result = cpu.read_mem(0x20)
      expect(from_fixed(result)).to be_within(0.1).of(3.0)
    end

    it 'handles smaller values' do
      # 0.5 * 0.5 = 0.25
      # 0x08 * 0x08 = 64 = 0x40, >> 4 = 0x04 = 0.25
      source = <<~'ASM'
        LDA #$08          ; 0.5
        STA $10
        LDA #$08          ; 0.5
        STA $11

        LDA #$00
        STA $22
        STA $23
        STA $24

        LDA $10
        STA $25

        LDY #$08
      MUL_LOOP:
        LDA $11
        AND #$01
        BEQ SKIP_ADD
        CLC
        LDA $22
        ADC $25
        STA $22
        LDA $23
        ADC $24
        STA $23
      SKIP_ADD:
        ASL $25
        ROL $24
        LSR $11
        DEY
        BNE MUL_LOOP

        LDX #$04
      DIV_LOOP:
        LSR $23
        ROR $22
        DEX
        BNE DIV_LOOP

        LDA $22
        STA $20
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      300.times do
        cpu.step
        break if cpu.halted?
      end

      result = cpu.read_mem(0x20)
      expect(from_fixed(result)).to be_within(0.1).of(0.25)
    end
  end

  describe 'Mandelbrot escape test' do
    it 'detects point outside set (escapes quickly)' do
      # c = (2, 0), z starts at 0
      # After 1 iteration: z = 0 + c = (2, 0), |z| = 2, escapes
      source = <<~'ASM'
        ; c = (2.0, 0)
        LDA #$20          ; 2.0 in 4.4
        STA $10           ; c_real
        LDA #$00
        STA $11           ; c_imag
        STA $12           ; z_real = 0
        STA $13           ; z_imag = 0
        STA $20           ; iterations = 0

        LDA #$10
        STA $14           ; max_iter = 16

      ITER_LOOP:
        ; Escape test: |z_real| >= 2 (0x20)
        LDA $12
        BPL POS_R
        EOR #$FF
        CLC
        ADC #$01
      POS_R:
        CMP #$20
        BCS ESCAPED

        LDA $13
        BPL POS_I
        EOR #$FF
        CLC
        ADC #$01
      POS_I:
        CMP #$20
        BCS ESCAPED

        ; Simple iteration: z = z + c (approximation for first iter from 0)
        CLC
        LDA $12
        ADC $10
        STA $12

        CLC
        LDA $13
        ADC $11
        STA $13

        INC $20

        LDA $20
        CMP $14
        BNE ITER_LOOP

        ; In set
        LDA #$00
        STA $20
        JMP DONE

      ESCAPED:
      DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      200.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(1)
    end

    it 'detects point inside set (origin)' do
      # c = (0, 0), z stays at 0 forever
      source = <<~'ASM'
        LDA #$00
        STA $10
        STA $11
        STA $12
        STA $13
        STA $20

        LDA #$08
        STA $14           ; max_iter = 8

      ITER_LOOP:
        LDA $12
        BPL POS_R
        EOR #$FF
        CLC
        ADC #$01
      POS_R:
        CMP #$20
        BCS ESCAPED

        LDA $13
        BPL POS_I
        EOR #$FF
        CLC
        ADC #$01
      POS_I:
        CMP #$20
        BCS ESCAPED

        CLC
        LDA $12
        ADC $10
        STA $12

        CLC
        LDA $13
        ADC $11
        STA $13

        INC $20

        LDA $20
        CMP $14
        BNE ITER_LOOP

        LDA #$00
        STA $20
        JMP DONE

      ESCAPED:
      DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      200.times do
        cpu.step
        break if cpu.halted?
      end

      expect(cpu.read_mem(0x20)).to eq(0)
    end
  end

  describe 'Full Mandelbrot z² computation' do
    it 'computes z_real² correctly' do
      # z_real = 1.5 (0x18), z_real² = 2.25 (0x24)
      source = <<~'ASM'
        LDA #$18          ; z_real = 1.5
        STA $10

        ; Square it using multiply routine
        LDA $10
        STA $25           ; multiplicand copy
        LDA #$00
        STA $24           ; multiplicand_hi
        STA $22           ; result_lo
        STA $23           ; result_hi

        LDA $10
        STA $11           ; multiplier = same value

        LDY #$08
      SQ_LOOP:
        LDA $11
        AND #$01
        BEQ SKIP_ADD
        CLC
        LDA $22
        ADC $25
        STA $22
        LDA $23
        ADC $24
        STA $23
      SKIP_ADD:
        ASL $25
        ROL $24
        LSR $11
        DEY
        BNE SQ_LOOP

        ; >> 4 for fixed point
        LDX #$04
      SHIFT:
        LSR $23
        ROR $22
        DEX
        BNE SHIFT

        LDA $22
        STA $20           ; z_real² result
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      300.times do
        cpu.step
        break if cpu.halted?
      end

      result = cpu.read_mem(0x20)
      # 1.5² = 2.25 = 0x24
      expect(from_fixed(result)).to be_within(0.2).of(2.25)
    end

    it 'computes z = z² + c for one iteration' do
      # z = (1, 0), c = (0.25, 0)
      # z² = (1, 0), z² + c = (1.25, 0)
      source = <<~'ASM'
        ; z_real=1.0 (0x10), z_imag=0, c_real=0.25 (0x04), c_imag=0
        LDA #$10
        STA $10           ; z_real
        LDA #$00
        STA $11           ; z_imag
        LDA #$04
        STA $12           ; c_real
        LDA #$00
        STA $13           ; c_imag

        ; Compute z_real² -> $30
        LDA $10
        STA $25
        LDA #$00
        STA $24
        STA $22
        STA $23

        LDA $10
        STA $26           ; multiplier

        LDY #$08
      SQ_R:
        LDA $26
        AND #$01
        BEQ SKIP_R
        CLC
        LDA $22
        ADC $25
        STA $22
        LDA $23
        ADC $24
        STA $23
      SKIP_R:
        ASL $25
        ROL $24
        LSR $26
        DEY
        BNE SQ_R

        LDX #$04
      SH_R:
        LSR $23
        ROR $22
        DEX
        BNE SH_R

        LDA $22
        STA $30           ; z_real²

        ; z_imag² = 0 (since z_imag = 0)

        ; new_z_real = z_real² - z_imag² + c_real
        ; = 0x10 - 0 + 0x04 = 0x14 = 1.25
        CLC
        LDA $30
        ADC $12
        STA $40           ; new z_real

        ; new_z_imag = 2 * z_real * z_imag + c_imag = 0 + 0 = 0
        LDA #$00
        STA $41           ; new z_imag

        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      400.times do
        cpu.step
        break if cpu.halted?
      end

      new_z_real = cpu.read_mem(0x40)
      new_z_imag = cpu.read_mem(0x41)

      expect(from_fixed(new_z_real)).to be_within(0.1).of(1.25)
      expect(new_z_imag).to eq(0)
    end
  end

  describe 'Mandelbrot iteration count' do
    it 'counts iterations until escape' do
      # c = (1, 0) - escapes after a few iterations
      # z0 = 0, z1 = 1, z2 = 1+1=2 (escaped)
      source = <<~'ASM'
        ; c = (1.0, 0)
        LDA #$10
        STA $10           ; c_real = 1.0
        LDA #$00
        STA $11           ; c_imag = 0
        STA $12           ; z_real = 0
        STA $13           ; z_imag = 0
        STA $20           ; iter = 0

        LDA #$10
        STA $14           ; max = 16

      MAIN:
        ; Check |z_real| >= 2
        LDA $12
        BPL CHK_R
        EOR #$FF
        CLC
        ADC #$01
      CHK_R:
        CMP #$20
        BCS ESC

        ; Simple: z = z + c (linearized for small z)
        ; Real iteration would need z², but this tests the framework
        CLC
        LDA $12
        ADC $10
        STA $12

        INC $20
        LDA $20
        CMP $14
        BNE MAIN

        LDA #$00
        STA $20
        JMP DONE

      ESC:
      DONE:
        BRK
      ASM

      cpu.assemble_and_load(source)
      cpu.reset

      300.times do
        cpu.step
        break if cpu.halted?
      end

      # z goes 0 -> 1 -> 2, escapes at iter 2
      expect(cpu.read_mem(0x20)).to eq(2)
    end
  end
end
