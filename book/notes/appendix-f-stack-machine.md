# Appendix F: Stack Machine ISA

*Companion appendix to [Chapter 5: Stack Machines](05-stack-machines.md)*

## Overview

This appendix provides a complete Forth-like instruction set architecture with full RHDL implementation of a stack-based CPU.

## Contents

- Complete 16-bit stack machine ISA
- Full instruction encoding
- Two-stack CPU architecture
- RHDL implementation of stack CPU
- Assembler and test programs
- Comparison with Forth hardware (RTX2000, GA144)

## Instruction Set Summary

| Opcode | Mnemonic | Stack Effect | Description |
|--------|----------|--------------|-------------|
| 0x00 | NOP | ( -- ) | No operation |
| 0x01 | DUP | ( a -- a a ) | Duplicate TOS |
| 0x02 | DROP | ( a -- ) | Discard TOS |
| 0x03 | SWAP | ( a b -- b a ) | Swap top two |
| 0x04 | OVER | ( a b -- a b a ) | Copy second to top |
| 0x05 | ROT | ( a b c -- b c a ) | Rotate top three |
| ... | ... | ... | ... |

## Notes

*Content to be expanded with complete RHDL CPU implementation.*

> Return to [Chapter 5](05-stack-machines.md) for conceptual introduction.
