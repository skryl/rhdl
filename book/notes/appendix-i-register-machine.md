# Appendix I: Register Machine ISA

*Companion appendix to [Chapter 8: Register Machines](08-register-machines.md)*

## Overview

This appendix provides a complete 8-bit instruction set architecture with full RHDL implementation of a register-based CPU, ready to run programs.

## Contents

- Complete 8-bit ISA specification
- Instruction encoding formats
- Register file implementation
- ALU design
- Control unit state machine
- Memory interface
- Assembler and test programs

## Instruction Set

### Instruction Formats

```
R-type: [opcode:4][rd:2][rs:2]     - Register operations
I-type: [opcode:4][rd:2][imm:2]    - Immediate operations
J-type: [opcode:4][addr:4]         - Jump operations
```

### Complete Instruction Table

| Opcode | Mnemonic | Format | Operation |
|--------|----------|--------|-----------|
| 0x0 | NOP | - | No operation |
| 0x1 | LDI | I | rd = imm |
| 0x2 | LD | R | rd = mem[rs] |
| 0x3 | ST | R | mem[rd] = rs |
| 0x4 | MOV | R | rd = rs |
| 0x5 | ADD | R | rd = rd + rs |
| 0x6 | SUB | R | rd = rd - rs |
| 0x7 | AND | R | rd = rd & rs |
| 0x8 | OR | R | rd = rd \| rs |
| 0x9 | XOR | R | rd = rd ^ rs |
| 0xA | NOT | R | rd = ~rd |
| 0xB | SHL | R | rd = rd << 1 |
| 0xC | SHR | R | rd = rd >> 1 |
| 0xD | JMP | J | PC = addr |
| 0xE | JZ | J | if Z: PC = addr |
| 0xF | HALT | - | Stop execution |

## RHDL Implementation

*See Chapter 8 for core implementation. This appendix expands with:*
- Multi-cycle implementation
- Pipelined implementation
- Interrupt support
- Extended addressing modes

## Notes

*Content to be expanded with complete RHDL CPU and test suite.*

> Return to [Chapter 8](08-register-machines.md) for conceptual introduction.
