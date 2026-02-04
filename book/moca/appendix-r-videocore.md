# Appendix O: VideoCore IV Implementation

*Companion appendix to [Chapter 15: VideoCore IV](15-videocore-iv.md)*

## Overview

This appendix provides RHDL implementations of VideoCore IV components and sample QPU assembly programs.

## QPU Register File

```ruby
class QpuRegisterFile < SimComponent
  input :clk
  input :reset

  # Read ports (A and B files)
  input :raddr_a, width: 6      # Register address A (0-63)
  input :raddr_b, width: 6      # Register address B (0-63)
  output :rdata_a, width: 512   # 16 × 32-bit elements
  output :rdata_b, width: 512

  # Write port
  input :waddr, width: 6
  input :wdata, width: 512
  input :write_enable

  # Accumulator access (r0-r5)
  input :acc_raddr, width: 3
  output :acc_rdata, width: 512
  input :acc_waddr, width: 3
  input :acc_wdata, width: 512
  input :acc_write_enable

  behavior do
    # 64 registers × 16 elements × 32 bits = 32KB per QPU
    # Accumulators are separate: 6 × 16 × 32 = 384 bytes

    on_posedge(:clk) do
      if reset.high?
        @reg_a = Array.new(32) { Array.new(16, 0) }
        @reg_b = Array.new(32) { Array.new(16, 0) }
        @accumulators = Array.new(6) { Array.new(16, 0) }
      else
        # Write to register file
        if write_enable.high?
          file = waddr.to_i < 32 ? @reg_a : @reg_b
          idx = waddr.to_i % 32
          16.times do |e|
            file[idx][e] = wdata.bits((e * 32)...((e + 1) * 32)).to_i
          end
        end

        # Write to accumulators
        if acc_write_enable.high?
          16.times do |e|
            @accumulators[acc_waddr.to_i][e] =
              acc_wdata.bits((e * 32)...((e + 1) * 32)).to_i
          end
        end
      end
    end

    # Combinational reads
    always do
      # Read A file
      result_a = 0
      if raddr_a.to_i < 32
        16.times do |e|
          result_a |= (@reg_a[raddr_a.to_i][e] & 0xFFFFFFFF) << (e * 32)
        end
      end
      rdata_a <= result_a

      # Read B file
      result_b = 0
      if raddr_b.to_i < 32
        16.times do |e|
          result_b |= (@reg_b[raddr_b.to_i][e] & 0xFFFFFFFF) << (e * 32)
        end
      end
      rdata_b <= result_b

      # Read accumulators
      result_acc = 0
      16.times do |e|
        result_acc |= (@accumulators[acc_raddr.to_i][e] & 0xFFFFFFFF) << (e * 32)
      end
      acc_rdata <= result_acc
    end
  end

  def initialize(name, params = {})
    super
    @reg_a = Array.new(32) { Array.new(16, 0) }
    @reg_b = Array.new(32) { Array.new(16, 0) }
    @accumulators = Array.new(6) { Array.new(16, 0) }
  end
end
```

## ADD ALU

The ADD ALU handles integer and floating-point addition:

```ruby
class QpuAddAlu < SimComponent
  input :op, width: 5           # Operation code
  input :a, width: 512          # Input A (16 × 32-bit)
  input :b, width: 512          # Input B (16 × 32-bit)
  input :cond, width: 3         # Condition code
  input :flags_in, width: 16    # Per-element condition flags

  output :result, width: 512    # Result (16 × 32-bit)
  output :flags_out, width: 16  # Updated flags

  # Operation codes
  OP_NOP    = 0
  OP_FADD   = 1
  OP_FSUB   = 2
  OP_FMIN   = 3
  OP_FMAX   = 4
  OP_FMINABS = 5
  OP_FMAXABS = 6
  OP_FTOI   = 7
  OP_ITOF   = 8
  OP_ADD    = 12
  OP_SUB    = 13
  OP_SHR    = 14
  OP_ASR    = 15
  OP_ROR    = 16
  OP_SHL    = 17
  OP_MIN    = 18
  OP_MAX    = 19
  OP_AND    = 20
  OP_OR     = 21
  OP_XOR    = 22
  OP_NOT    = 23
  OP_CLZ    = 24

  behavior do
    always do
      res = 0
      flags = 0

      16.times do |e|
        elem_a = a.bits((e * 32)...((e + 1) * 32)).to_i
        elem_b = b.bits((e * 32)...((e + 1) * 32)).to_i

        elem_result = case op.to_i
          when OP_NOP then elem_a
          when OP_ADD then (elem_a + elem_b) & 0xFFFFFFFF
          when OP_SUB then (elem_a - elem_b) & 0xFFFFFFFF
          when OP_SHR then elem_a >> (elem_b & 31)
          when OP_SHL then (elem_a << (elem_b & 31)) & 0xFFFFFFFF
          when OP_ASR then sign_extend_shift(elem_a, elem_b & 31)
          when OP_MIN then [elem_a, elem_b].min
          when OP_MAX then [elem_a, elem_b].max
          when OP_AND then elem_a & elem_b
          when OP_OR  then elem_a | elem_b
          when OP_XOR then elem_a ^ elem_b
          when OP_NOT then (~elem_a) & 0xFFFFFFFF
          when OP_CLZ then count_leading_zeros(elem_a)
          when OP_FADD then float_add(elem_a, elem_b)
          when OP_FSUB then float_sub(elem_a, elem_b)
          when OP_FMIN then float_min(elem_a, elem_b)
          when OP_FMAX then float_max(elem_a, elem_b)
          else 0
        end

        res |= (elem_result & 0xFFFFFFFF) << (e * 32)

        # Update flags (N, Z, C for each element)
        flags |= (elem_result == 0 ? 1 : 0) << e  # Zero flag
      end

      result <= res
      flags_out <= flags
    end
  end

  private

  def sign_extend_shift(val, shift)
    sign = (val >> 31) & 1
    if sign == 1
      mask = (0xFFFFFFFF << (32 - shift)) & 0xFFFFFFFF
      (val >> shift) | mask
    else
      val >> shift
    end
  end

  def count_leading_zeros(val)
    return 32 if val == 0
    count = 0
    (31).downto(0) do |i|
      if (val >> i) & 1 == 1
        return 31 - i
      end
    end
    32
  end

  def float_add(a, b)
    # IEEE 754 single-precision add (simplified)
    fa = [a].pack('L').unpack('f').first
    fb = [b].pack('L').unpack('f').first
    [(fa + fb)].pack('f').unpack('L').first
  end

  def float_sub(a, b)
    fa = [a].pack('L').unpack('f').first
    fb = [b].pack('L').unpack('f').first
    [(fa - fb)].pack('f').unpack('L').first
  end

  def float_min(a, b)
    fa = [a].pack('L').unpack('f').first
    fb = [b].pack('L').unpack('f').first
    [[fa, fb].min].pack('f').unpack('L').first
  end

  def float_max(a, b)
    fa = [a].pack('L').unpack('f').first
    fb = [b].pack('L').unpack('f').first
    [[fa, fb].max].pack('f').unpack('L').first
  end
end
```

## MUL ALU

```ruby
class QpuMulAlu < SimComponent
  input :op, width: 3
  input :a, width: 512
  input :b, width: 512

  output :result, width: 512

  OP_NOP   = 0
  OP_FMUL  = 1
  OP_MUL24 = 2  # 24-bit integer multiply
  OP_V8ADDS = 3  # 8-bit saturating add
  OP_V8SUBS = 4  # 8-bit saturating sub
  OP_V8MIN  = 5
  OP_V8MAX  = 6
  OP_V8MULD = 7  # 8-bit multiply

  behavior do
    always do
      res = 0

      16.times do |e|
        elem_a = a.bits((e * 32)...((e + 1) * 32)).to_i
        elem_b = b.bits((e * 32)...((e + 1) * 32)).to_i

        elem_result = case op.to_i
          when OP_NOP then elem_a
          when OP_FMUL then float_mul(elem_a, elem_b)
          when OP_MUL24 then mul24(elem_a, elem_b)
          when OP_V8ADDS then v8_saturating_add(elem_a, elem_b)
          when OP_V8SUBS then v8_saturating_sub(elem_a, elem_b)
          when OP_V8MIN then v8_min(elem_a, elem_b)
          when OP_V8MAX then v8_max(elem_a, elem_b)
          when OP_V8MULD then v8_mul(elem_a, elem_b)
          else 0
        end

        res |= (elem_result & 0xFFFFFFFF) << (e * 32)
      end

      result <= res
    end
  end

  private

  def float_mul(a, b)
    fa = [a].pack('L').unpack('f').first
    fb = [b].pack('L').unpack('f').first
    [(fa * fb)].pack('f').unpack('L').first
  end

  def mul24(a, b)
    # 24-bit signed multiply, result is low 32 bits
    sa = (a & 0x800000) != 0 ? (a | 0xFF000000) : (a & 0xFFFFFF)
    sb = (b & 0x800000) != 0 ? (b | 0xFF000000) : (b & 0xFFFFFF)
    (sa * sb) & 0xFFFFFFFF
  end

  def v8_saturating_add(a, b)
    result = 0
    4.times do |i|
      byte_a = (a >> (i * 8)) & 0xFF
      byte_b = (b >> (i * 8)) & 0xFF
      sum = byte_a + byte_b
      sum = 255 if sum > 255
      result |= sum << (i * 8)
    end
    result
  end

  def v8_saturating_sub(a, b)
    result = 0
    4.times do |i|
      byte_a = (a >> (i * 8)) & 0xFF
      byte_b = (b >> (i * 8)) & 0xFF
      diff = byte_a - byte_b
      diff = 0 if diff < 0
      result |= diff << (i * 8)
    end
    result
  end

  def v8_min(a, b)
    result = 0
    4.times do |i|
      byte_a = (a >> (i * 8)) & 0xFF
      byte_b = (b >> (i * 8)) & 0xFF
      result |= [byte_a, byte_b].min << (i * 8)
    end
    result
  end

  def v8_max(a, b)
    result = 0
    4.times do |i|
      byte_a = (a >> (i * 8)) & 0xFF
      byte_b = (b >> (i * 8)) & 0xFF
      result |= [byte_a, byte_b].max << (i * 8)
    end
    result
  end

  def v8_mul(a, b)
    result = 0
    4.times do |i|
      byte_a = (a >> (i * 8)) & 0xFF
      byte_b = (b >> (i * 8)) & 0xFF
      result |= ((byte_a * byte_b) & 0xFF) << (i * 8)
    end
    result
  end
end
```

## Simplified QPU Core

```ruby
class QpuCore < SimComponent
  input :clk
  input :reset
  input :enable

  # Instruction input
  input :instruction, width: 64
  input :instruction_valid

  # Uniform (parameter) input
  input :uniform, width: 32
  input :uniform_valid

  # VPM interface
  output :vpm_write_data, width: 512
  output :vpm_write_enable
  input :vpm_read_data, width: 512

  # TMU interface
  output :tmu_addr, width: 32
  output :tmu_request
  input :tmu_data, width: 512
  input :tmu_ready

  # Status
  output :busy
  output :done

  # Internal components
  instance :regfile, QpuRegisterFile
  instance :add_alu, QpuAddAlu
  instance :mul_alu, QpuMulAlu

  wire :pc, width: 32
  wire :state, width: 3

  STATE_IDLE    = 0
  STATE_FETCH   = 1
  STATE_DECODE  = 2
  STATE_EXECUTE = 3
  STATE_WRITE   = 4
  STATE_DONE    = 5

  behavior do
    on_posedge(:clk) do
      if reset.high?
        state <= STATE_IDLE
        pc <= 0
        busy <= 0
        done <= 0
      elsif enable.high?
        case state.to_i
        when STATE_IDLE
          if instruction_valid.high?
            state <= STATE_DECODE
            busy <= 1
          end

        when STATE_DECODE
          # Decode 64-bit instruction
          # sig = instruction[63:60]
          # op_add = instruction[31:26]
          # op_mul = instruction[5:3]
          # etc.
          state <= STATE_EXECUTE

        when STATE_EXECUTE
          # Execute both ALUs in parallel
          # Results go to accumulators or registers
          state <= STATE_WRITE

        when STATE_WRITE
          # Write results
          state <= STATE_IDLE
          busy <= 0
        end
      end
    end
  end
end
```

## VPM (Vertex Pipe Memory)

```ruby
class Vpm < SimComponent
  input :clk
  input :reset

  # QPU write interface
  input :qpu_write_data, width: 512  # 16 × 32-bit
  input :qpu_write_addr, width: 12
  input :qpu_write_enable

  # QPU read interface
  input :qpu_read_addr, width: 12
  output :qpu_read_data, width: 512

  # DMA interface
  input :dma_write_data, width: 128
  input :dma_write_addr, width: 12
  input :dma_write_enable

  output :dma_read_data, width: 128
  input :dma_read_addr, width: 12
  input :dma_read_enable

  # 48KB organized as 16 rows × 64 columns × 32-bit
  # = 16 × 64 × 4 = 4096 bytes per "page"
  # 12 pages = 48KB

  behavior do
    on_posedge(:clk) do
      if reset.high?
        @memory = Array.new(12288, 0)  # 48KB / 4 = 12K words
      else
        # QPU write (16 words at a time)
        if qpu_write_enable.high?
          base = qpu_write_addr.to_i
          16.times do |i|
            word = qpu_write_data.bits((i * 32)...((i + 1) * 32)).to_i
            @memory[(base + i) % 12288] = word
          end
        end

        # DMA write (4 words at a time)
        if dma_write_enable.high?
          base = dma_write_addr.to_i
          4.times do |i|
            word = dma_write_data.bits((i * 32)...((i + 1) * 32)).to_i
            @memory[(base + i) % 12288] = word
          end
        end
      end
    end

    always do
      # QPU read (16 words)
      result = 0
      base = qpu_read_addr.to_i
      16.times do |i|
        word = @memory[(base + i) % 12288] || 0
        result |= (word & 0xFFFFFFFF) << (i * 32)
      end
      qpu_read_data <= result

      # DMA read (4 words)
      dma_result = 0
      dma_base = dma_read_addr.to_i
      4.times do |i|
        word = @memory[(dma_base + i) % 12288] || 0
        dma_result |= (word & 0xFFFFFFFF) << (i * 32)
      end
      dma_read_data <= dma_result
    end
  end

  def initialize(name, params = {})
    super
    @memory = Array.new(12288, 0)
  end
end
```

## Sample QPU Programs

### Vector Addition

```asm
# C[i] = A[i] + B[i] for 1024 elements
# Each iteration processes 16 elements

.set NUM_ELEMENTS, 1024
.set ITERATIONS, 64   # 1024 / 16

vc4_vector_add:
    # Load uniforms
    mov r0, unif      # A base address
    mov r1, unif      # B base address
    mov r2, unif      # C base address
    ldi r3, ITERATIONS

loop:
    # Request A[i:i+16] from TMU
    mov tmu0_s, r0
    add r0, r0, 64    # Advance by 16 floats

    # Request B[i:i+16] from TMU
    mov tmu0_s, r1
    add r1, r1, 64

    # Wait for TMU and get A
    ldtmu0
    mov r4, r4        # r4 = A values

    # Wait for TMU and get B
    ldtmu0            # r4 = B values

    # Add: r0 = A + B (ADD ALU)
    fadd r5, r4, r5   # Note: r5 still has A from mov

    # Store to VPM
    mov vpm, r5

    # DMA from VPM to memory
    ldi vw_setup, 0x1a00  # 16 words, horizontal
    mov vw_addr, r2
    add r2, r2, 64        # Advance C pointer

    # Loop
    sub.setf r3, r3, 1
    brr.nz -, loop
    nop
    nop
    nop

    # Done
    mov irq, 1
    thrend
    nop
    nop
```

### Matrix Multiply (4×4)

```asm
# 4x4 matrix multiply: C = A × B
# Uses all 4 rows of VPM for intermediate storage

mat4x4_mul:
    mov r0, unif      # A address
    mov r1, unif      # B address
    mov r2, unif      # C address

    # Load A matrix (4 rows × 4 cols = 16 floats)
    # Each TMU load gets 16 floats, perfect for one matrix
    mov tmu0_s, r0
    ldtmu0
    mov ra0, r4       # A row 0
    # ... load remaining A rows

    # Load B matrix
    mov tmu0_s, r1
    ldtmu0
    mov rb0, r4       # B col 0 (transposed)
    # ... load remaining B cols

    # Compute C[0,0] = A[0,:] · B[:,0]
    # Use fmul for element-wise multiply, then reduce
    fmul r0, ra0, rb0
    # Reduction would require shuffles...

    # Store result
    mov vpm, r0
    ldi vw_setup, 0x1a00
    mov vw_addr, r2

    thrend
    nop
    nop
```

### Mandelbrot Set

```asm
# Compute one 16-pixel strip of Mandelbrot set
# Each element computes one pixel

mandelbrot:
    mov r0, unif      # x_start (16 different x values)
    mov r1, unif      # y (same for all 16)
    mov r2, unif      # output address
    ldi r3, 256       # max iterations

    # z = 0
    ldi r4, 0         # z_real
    ldi r5, 0         # z_imag

iterate:
    # z_new = z² + c
    # z_real_new = z_real² - z_imag² + c_real
    # z_imag_new = 2 * z_real * z_imag + c_imag

    fmul ra0, r4, r4      # z_real²
    fmul ra1, r5, r5      # z_imag²
    fsub ra2, ra0, ra1    # z_real² - z_imag²
    fadd r4, ra2, r0      # + c_real

    fmul ra3, r4, r5      # z_real * z_imag
    fadd ra3, ra3, ra3    # 2 * z_real * z_imag (ADD ALU)
    fadd r5, ra3, r1      # + c_imag

    # Check |z|² < 4
    fmul ra4, r4, r4
    fmul ra5, r5, r5
    fadd ra6, ra4, ra5    # |z|²

    # Compare and update iteration count
    # (simplified - real code would track per-element)

    sub.setf r3, r3, 1
    brr.nz -, iterate
    nop
    nop
    nop

    # Store iteration counts
    mov vpm, r3
    ldi vw_setup, 0x1a00
    mov vw_addr, r2

    thrend
    nop
    nop
```

## Performance Notes

### Cycle Counting

| Operation | Latency | Throughput |
|-----------|---------|------------|
| Register read | 0 | 1/cycle |
| ALU operation | 1 | 1/cycle |
| TMU request | 9-12 | 1/4 cycles |
| VPM write | 3 | 1/cycle |
| VPM→DMA | 10+ | varies |

### Optimization Tips

1. **Keep both ALUs busy** - Schedule ADD and MUL operations together
2. **Hide TMU latency** - Issue TMU requests early, do other work while waiting
3. **Use VPM efficiently** - Batch writes, minimize DMA transfers
4. **Avoid register conflicts** - A and B files have separate read ports

## Further Reading

- Broadcom VideoCore IV 3D Architecture Reference Guide
- Raspberry Pi Kernel Documentation (QPU)
- github.com/hermanhermitage/videocoreiv
- github.com/maazl/vc4asm (assembler)

> Return to [Chapter 15](15-videocore-iv.md) for architecture overview.
