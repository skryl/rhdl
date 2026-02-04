# Chapter 22: RISC-V RV32I

*The open instruction set architecture reshaping computing*

---

## Why RISC-V Matters

RISC-V is the first successful **open** instruction set architecture. Unlike x86 (Intel) or ARM (ARM Ltd), anyone can implement RISC-V without licensing fees.

**Key properties:**
- **Open**: Free to implement, modify, extend
- **Clean**: Modern design without legacy baggage
- **Modular**: Base ISA + optional extensions
- **Growing**: Academia, startups, and giants adopting it

---

## RISC-V Design Philosophy

### Simplicity First

RISC-V RV32I has only **47 instructions**—compare to x86's thousands.

```
┌────────────────────────────────────────┐
│         RV32I: The Base ISA            │
├────────────────────────────────────────┤
│  Arithmetic:  ADD, SUB, AND, OR, XOR   │
│               SLT, SLTU                │
│  Shifts:      SLL, SRL, SRA            │
│  Immediate:   ADDI, ANDI, ORI, XORI    │
│               SLTI, SLTIU              │
│               SLLI, SRLI, SRAI         │
│  Loads:       LB, LH, LW, LBU, LHU     │
│  Stores:      SB, SH, SW               │
│  Branches:    BEQ, BNE, BLT, BGE       │
│               BLTU, BGEU               │
│  Jumps:       JAL, JALR                │
│  Upper Imm:   LUI, AUIPC               │
│  System:      ECALL, EBREAK            │
│  Fence:       FENCE, FENCE.I           │
│                                        │
│  Total: 47 instructions                │
└────────────────────────────────────────┘
```

### Modular Extensions

Build what you need:

| Extension | Description |
|-----------|-------------|
| **I** | Base integer (required) |
| **M** | Multiply/divide |
| **A** | Atomics |
| **F** | Single-precision float |
| **D** | Double-precision float |
| **C** | Compressed (16-bit) instructions |
| **V** | Vector operations |
| **B** | Bit manipulation |

**RV32IMFD** = Base + Multiply + Atomics + Floats

---

## Register File

### 32 General-Purpose Registers

```
┌─────────────────────────────────────────┐
│           RISC-V Registers              │
├─────────────────────────────────────────┤
│  x0  = zero   (hardwired to 0)          │
│  x1  = ra     (return address)          │
│  x2  = sp     (stack pointer)           │
│  x3  = gp     (global pointer)          │
│  x4  = tp     (thread pointer)          │
│  x5  = t0     (temporary)               │
│  x6  = t1     (temporary)               │
│  x7  = t2     (temporary)               │
│  x8  = s0/fp  (saved/frame pointer)     │
│  x9  = s1     (saved)                   │
│  x10 = a0     (argument/return)         │
│  x11 = a1     (argument/return)         │
│  x12 = a2     (argument)                │
│  x13 = a3     (argument)                │
│  x14 = a4     (argument)                │
│  x15 = a5     (argument)                │
│  x16 = a6     (argument)                │
│  x17 = a7     (argument)                │
│  x18 = s2     (saved)                   │
│  ...                                    │
│  x31 = t6     (temporary)               │
│                                         │
│  pc  = Program Counter (not in x regs)  │
└─────────────────────────────────────────┘
```

**x0 is always zero**—simplifies many operations:
- `mv rd, rs` = `addi rd, rs, 0`
- `nop` = `addi x0, x0, 0`
- `neg rd, rs` = `sub rd, x0, rs`

---

## Instruction Formats

RISC-V has just **6 instruction formats**, all 32 bits:

```
R-type (register-register):
┌───────┬─────┬─────┬─────┬─────┬───────┐
│funct7 │ rs2 │ rs1 │func3│ rd  │opcode │
│  7    │  5  │  5  │  3  │  5  │   7   │
└───────┴─────┴─────┴─────┴─────┴───────┘

I-type (immediate):
┌─────────────┬─────┬─────┬─────┬───────┐
│  imm[11:0]  │ rs1 │func3│ rd  │opcode │
│     12      │  5  │  3  │  5  │   7   │
└─────────────┴─────┴─────┴─────┴───────┘

S-type (store):
┌───────┬─────┬─────┬─────┬───────┬───────┐
│imm[11:5]│rs2│ rs1 │func3│imm[4:0]│opcode│
│   7   │  5  │  5  │  3  │   5   │   7   │
└───────┴─────┴─────┴─────┴───────┴───────┘

B-type (branch):
┌─┬──────┬─────┬─────┬─────┬─────┬─┬───────┐
│12│10:5 │ rs2 │ rs1 │func3│4:1  │11│opcode│
└─┴──────┴─────┴─────┴─────┴─────┴─┴───────┘

U-type (upper immediate):
┌────────────────────┬─────┬───────┐
│     imm[31:12]     │ rd  │opcode │
│         20         │  5  │   7   │
└────────────────────┴─────┴───────┘

J-type (jump):
┌──┬────────┬─┬────────┬─────┬───────┐
│20│ 10:1   │11│ 19:12  │ rd  │opcode │
└──┴────────┴─┴────────┴─────┴───────┘
```

**Key insight**: `rs1`, `rs2`, `rd` are always in the same bit positions!

---

## Core Instructions

### Arithmetic

```assembly
add  rd, rs1, rs2    # rd = rs1 + rs2
sub  rd, rs1, rs2    # rd = rs1 - rs2
addi rd, rs1, imm    # rd = rs1 + sign_extend(imm)

and  rd, rs1, rs2    # rd = rs1 & rs2
or   rd, rs1, rs2    # rd = rs1 | rs2
xor  rd, rs1, rs2    # rd = rs1 ^ rs2
andi rd, rs1, imm    # rd = rs1 & sign_extend(imm)

slt  rd, rs1, rs2    # rd = (rs1 < rs2) ? 1 : 0  (signed)
sltu rd, rs1, rs2    # rd = (rs1 < rs2) ? 1 : 0  (unsigned)
slti rd, rs1, imm    # rd = (rs1 < imm) ? 1 : 0  (signed)
```

### Shifts

```assembly
sll  rd, rs1, rs2    # rd = rs1 << rs2[4:0]  (logical left)
srl  rd, rs1, rs2    # rd = rs1 >> rs2[4:0]  (logical right)
sra  rd, rs1, rs2    # rd = rs1 >>> rs2[4:0] (arithmetic right)

slli rd, rs1, shamt  # rd = rs1 << shamt
srli rd, rs1, shamt  # rd = rs1 >> shamt
srai rd, rs1, shamt  # rd = rs1 >>> shamt
```

### Loads and Stores

```assembly
lw  rd, offset(rs1)  # rd = mem[rs1 + offset] (32-bit)
lh  rd, offset(rs1)  # rd = sign_extend(mem[rs1 + offset]) (16-bit)
lb  rd, offset(rs1)  # rd = sign_extend(mem[rs1 + offset]) (8-bit)
lhu rd, offset(rs1)  # rd = zero_extend(mem[rs1 + offset])
lbu rd, offset(rs1)  # rd = zero_extend(mem[rs1 + offset])

sw  rs2, offset(rs1) # mem[rs1 + offset] = rs2 (32-bit)
sh  rs2, offset(rs1) # mem[rs1 + offset] = rs2[15:0]
sb  rs2, offset(rs1) # mem[rs1 + offset] = rs2[7:0]
```

### Branches

```assembly
beq  rs1, rs2, offset  # if (rs1 == rs2) pc += offset
bne  rs1, rs2, offset  # if (rs1 != rs2) pc += offset
blt  rs1, rs2, offset  # if (rs1 < rs2)  pc += offset (signed)
bge  rs1, rs2, offset  # if (rs1 >= rs2) pc += offset (signed)
bltu rs1, rs2, offset  # unsigned less than
bgeu rs1, rs2, offset  # unsigned greater or equal
```

### Jumps

```assembly
jal  rd, offset      # rd = pc + 4; pc += offset
jalr rd, rs1, offset # rd = pc + 4; pc = (rs1 + offset) & ~1
```

**Function call**: `jal ra, function`
**Return**: `jalr x0, ra, 0` (discard return address)

### Upper Immediate

```assembly
lui   rd, imm        # rd = imm << 12
auipc rd, imm        # rd = pc + (imm << 12)
```

For loading 32-bit constants:
```assembly
lui  t0, 0x12345     # t0 = 0x12345000
addi t0, t0, 0x678   # t0 = 0x12345678
```

---

## Example: Factorial

```assembly
# int factorial(int n) - n in a0, result in a0
factorial:
    addi sp, sp, -8     # Allocate stack
    sw   ra, 4(sp)      # Save return address
    sw   a0, 0(sp)      # Save n

    slti t0, a0, 2      # t0 = (n < 2)
    bne  t0, zero, base # if n < 2, return 1

    addi a0, a0, -1     # a0 = n - 1
    jal  ra, factorial  # recursive call
    lw   t0, 0(sp)      # restore n
    mul  a0, a0, t0     # a0 = factorial(n-1) * n
    j    done

base:
    li   a0, 1          # return 1

done:
    lw   ra, 4(sp)      # Restore ra
    addi sp, sp, 8      # Deallocate stack
    jalr x0, ra, 0      # Return
```

---

## Pipeline Implementation

### Classic 5-Stage Pipeline

```
┌────────┬────────┬────────┬────────┬────────┐
│ Fetch  │ Decode │Execute │ Memory │Writeback│
│  (IF)  │  (ID)  │  (EX)  │  (MEM) │  (WB)  │
└────────┴────────┴────────┴────────┴────────┘

Cycle: 1    2    3    4    5    6    7    8
ADD:   IF   ID   EX   MEM  WB
LW:        IF   ID   EX   MEM  WB
BEQ:            IF   ID   EX   MEM  WB
```

### Hazards

**Data hazard (RAW)**:
```assembly
add x1, x2, x3    # x1 written in WB
sub x4, x1, x5    # x1 needed in EX - hazard!
```
Solution: Forwarding (bypass EX result to next EX)

**Control hazard**:
```assembly
beq x1, x2, target  # Branch decision in EX
add x3, x4, x5      # Already fetched, may be wrong!
```
Solution: Branch prediction, flush on mispredict

**Load-use hazard**:
```assembly
lw  x1, 0(x2)     # x1 available after MEM
add x3, x1, x4    # x1 needed in EX - must stall!
```
Solution: Insert bubble (can't forward from MEM to EX)

---

## The RISC-V Ecosystem

### Open Implementations

| Name | Bits | Pipeline | Target |
|------|------|----------|--------|
| PicoRV32 | 32 | 2-4 stage | FPGA, tiny |
| VexRiscv | 32 | 2-5 stage | FPGA, configurable |
| BOOM | 64 | OoO | Research |
| Rocket | 64 | In-order | Tapeout-ready |
| CVA6 | 64 | 6-stage | Linux-capable |

### Commercial

- **SiFive**: Performance/U-series cores
- **Alibaba**: Xuantie (T-Head) cores
- **Western Digital**: SweRV cores
- **Qualcomm**, **NVIDIA**: Evaluating/adopting

---

## Comparison with Other ISAs

| Feature | RISC-V | ARM | x86 |
|---------|--------|-----|-----|
| Instruction size | 32-bit (C: 16) | 32-bit (Thumb: 16) | Variable (1-15) |
| Registers | 32 | 16 (AArch64: 31) | 8 (x64: 16) |
| License | Open | Proprietary | Proprietary |
| Condition codes | No | Yes | Yes |
| Predication | No | Yes (AArch64: limited) | No |
| Load/store | Only | Only | Memory operands |
| Complexity | Low | Medium | Very high |

---

## Why No Condition Codes?

RISC-V uses **compare-and-branch** instead of flags:

```assembly
# Traditional (ARM/x86): set flags, then branch
cmp  r1, r2       # Sets N, Z, C, V flags
beq  target       # Branch if Z=1

# RISC-V: compare in branch instruction
beq  x1, x2, target  # Compare AND branch
```

**Advantages:**
- No flag register to save/restore
- No dependencies between compare and branch
- Simpler out-of-order execution

---

## RHDL Implementation

See [Appendix V](appendix-v-riscv.md) for complete implementation:

```ruby
# RV32I instruction decoder
class RV32IDecoder < SimComponent
  input :instr, width: 32

  output :opcode, width: 7
  output :rd, width: 5
  output :rs1, width: 5
  output :rs2, width: 5
  output :funct3, width: 3
  output :funct7, width: 7
  output :imm, width: 32

  behavior do
    opcode <= instr[6:0]
    rd     <= instr[11:7]
    rs1    <= instr[19:15]
    rs2    <= instr[24:20]
    funct3 <= instr[14:12]
    funct7 <= instr[31:25]

    # Immediate extraction based on opcode
    # ...
  end
end
```

---

## Summary

- **Open ISA**: Free to implement, no licensing
- **Clean design**: 47 base instructions, 6 formats
- **Modular**: RV32I + MAFDCV extensions as needed
- **No flags**: Compare-and-branch simplifies hardware
- **Growing ecosystem**: From microcontrollers to supercomputers
- **Educational**: Ideal for learning CPU design

---

## Exercises

1. Implement the RV32I decoder in RHDL
2. Build a single-cycle RV32I datapath
3. Add forwarding to a 5-stage pipeline
4. Implement the M extension (multiply/divide)
5. Compare code density: RV32I vs RV32IC

---

## Further Reading

- RISC-V Specifications: riscv.org/specifications
- Patterson & Waterman, "The RISC-V Reader"
- Harris & Harris, "Digital Design and Computer Architecture: RISC-V Edition"

---

*Next: [Chapter 23 - The Transputer](23-transputer.md)*

*Appendix: [Appendix V - RISC-V Implementation](appendix-v-riscv.md)*
