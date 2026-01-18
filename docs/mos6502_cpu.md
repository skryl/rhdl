# MOS 6502 CPU Implementation

The `examples/mos6502/` directory contains a complete behavior simulation of the MOS 6502 microprocessor, including all official instructions, addressing modes, and a two-pass assembler.

## Architecture Overview

The implementation follows the actual 6502 architecture with these components:

```
┌─────────────────────────────────────────────────────────────┐
│                        MOS6502::CPU                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │                     Datapath                         │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐              │    │
│  │  │ Registers│  │   ALU   │  │ Status  │              │    │
│  │  │ A, X, Y  │  │         │  │ N V B D │              │    │
│  │  └─────────┘  └─────────┘  │ I Z C   │              │    │
│  │                            └─────────┘              │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐      │    │
│  │  │   PC    │  │   SP    │  │  Address Gen    │      │    │
│  │  │ 16-bit  │  │  8-bit  │  │                 │      │    │
│  │  └─────────┘  └─────────┘  └─────────────────┘      │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌────────────────┐  ┌────────────────────────────────┐    │
│  │ Control Unit   │  │   Instruction Decoder          │    │
│  │ State Machine  │  │                                │    │
│  └────────────────┘  └────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │     Memory      │
                    │   64KB (RAM/ROM)│
                    └─────────────────┘
```

## Components

### CPU (`cpu.rb`)

The main CPU class integrates the datapath and memory into a complete system.

**Features:**
- Clock-cycle accurate simulation
- Reset sequence with vector fetch
- Breakpoint support
- Register accessors (A, X, Y, SP, PC, P)
- Status flag accessors (N, V, B, D, I, Z, C)
- Disassembler for debugging

**Usage:**
```ruby
require_relative 'examples/mos6502/cpu'

cpu = MOS6502::CPU.new
cpu.assemble_and_load(<<~ASM, 0x8000)
  LDA #$42
  STA $00
  BRK
ASM
cpu.reset
cpu.run
puts cpu.status_string  # A:42 X:00 Y:00 SP:FD PC:8006 P:30 [nv-BdIzc]
```

### ALU (`alu.rb`)

Full arithmetic logic unit supporting all 6502 operations.

**Operations:**
| Code | Mnemonic | Description |
|------|----------|-------------|
| 0x00 | ADC | Add with carry |
| 0x01 | SBC | Subtract with borrow |
| 0x02 | AND | Bitwise AND |
| 0x03 | ORA | Bitwise OR |
| 0x04 | EOR | Bitwise XOR |
| 0x05 | ASL | Arithmetic shift left |
| 0x06 | LSR | Logical shift right |
| 0x07 | ROL | Rotate left through carry |
| 0x08 | ROR | Rotate right through carry |
| 0x09 | INC | Increment |
| 0x0A | DEC | Decrement |
| 0x0B | CMP | Compare (flags only) |
| 0x0C | BIT | Bit test |
| 0x0D | TST | Pass through (for transfers) |

**BCD Mode:** Full decimal mode support for ADC and SBC operations.

### Control Unit (`control_unit.rb`)

State machine that sequences instruction execution.

**States:**
- `RESET` - Reset sequence
- `FETCH` - Fetch opcode from memory
- `DECODE` - Decode instruction
- `FETCH_OP1/OP2` - Fetch operand bytes
- `ADDR_LO/HI` - Fetch indirect addresses
- `READ_MEM` - Read from effective address
- `EXECUTE` - ALU operation
- `WRITE_MEM` - Write to memory
- `BRANCH` - Branch decision
- `PUSH/PULL` - Stack operations
- `JSR/RTS/RTI/BRK` - Subroutine and interrupt handling

### Instruction Decoder (`instruction_decoder.rb`)

Decodes opcodes into control signals.

**Instruction Types:**
- ALU operations (ADC, SBC, AND, ORA, EOR, CMP)
- Load/Store (LDA, LDX, LDY, STA, STX, STY)
- Increment/Decrement (INC, DEC, INX, DEX, INY, DEY)
- Shifts/Rotates (ASL, LSR, ROL, ROR)
- Branches (BCC, BCS, BEQ, BMI, BNE, BPL, BVC, BVS)
- Jumps (JMP, JSR, RTS, RTI)
- Stack (PHA, PHP, PLA, PLP)
- Transfers (TAX, TXA, TAY, TYA, TSX, TXS)
- Flags (CLC, SEC, CLI, SEI, CLV, CLD, SED)

### Address Generator (`address_gen.rb`)

Calculates effective addresses for all addressing modes.

**Addressing Modes:**
| Mode | Example | Description |
|------|---------|-------------|
| Implied | `CLC` | No operand |
| Accumulator | `ASL A` | Operates on A |
| Immediate | `LDA #$42` | 8-bit literal |
| Zero Page | `LDA $00` | 8-bit address (page 0) |
| Zero Page,X | `LDA $00,X` | ZP + X register |
| Zero Page,Y | `LDX $00,Y` | ZP + Y register |
| Absolute | `LDA $1234` | 16-bit address |
| Absolute,X | `LDA $1234,X` | Absolute + X |
| Absolute,Y | `LDA $1234,Y` | Absolute + Y |
| Indirect | `JMP ($1234)` | Pointer dereference |
| Indexed Indirect | `LDA ($00,X)` | (ZP + X) pointer |
| Indirect Indexed | `LDA ($00),Y` | (ZP) + Y |
| Relative | `BNE label` | PC + signed offset |

### Datapath (`datapath.rb`)

Integrates all CPU components with internal buses and control signals.

**Subcomponents:**
- Registers (A, X, Y)
- Status Register (P)
- Program Counter (PC)
- Stack Pointer (SP)
- Instruction Register (IR)
- ALU
- Control Unit
- Instruction Decoder
- Address Generator
- Address/Data Latches

### Memory (`memory.rb`)

64KB addressable memory with RAM and ROM regions.

**Memory Map:**
| Range | Description |
|-------|-------------|
| $0000-$00FF | Zero Page |
| $0100-$01FF | Stack |
| $0000-$7FFF | RAM (32KB) |
| $8000-$FFFF | ROM (32KB) |
| $FFFA-$FFFB | NMI Vector |
| $FFFC-$FFFD | Reset Vector |
| $FFFE-$FFFF | IRQ/BRK Vector |

### Assembler (`assembler.rb`)

Two-pass assembler for 6502 assembly language.

**Features:**
- All official mnemonics and addressing modes
- Labels and equates
- Directives: `.ORG`, `.BYTE`, `.WORD`, `.END`
- Expressions with `+`, `-`, `<` (low byte), `>` (high byte)
- Comments with `;`

**Example:**
```asm
        *= $8000        ; Set origin
COUNT   = $10           ; Equate

START:  LDA #0          ; Initialize
        STA COUNT
LOOP:   INC COUNT       ; Increment
        LDA COUNT
        CMP #10
        BNE LOOP        ; Loop until 10
        BRK

        .BYTE $FF, $00  ; Data bytes
        .WORD START     ; 16-bit address
```

### Additional Components

- **Status Register** (`status_register.rb`) - N, V, B, D, I, Z, C flags
- **Registers** (`registers.rb`) - A, X, Y register file
- **Apple II Bus** (`apple2_bus.rb`) - Memory-mapped I/O for Apple II

## File Structure

```
examples/mos6502/
├── cpu.rb                 # Main CPU class
├── alu.rb                 # Arithmetic Logic Unit
├── control_unit.rb        # State machine
├── instruction_decoder.rb # Opcode decoder
├── address_gen.rb         # Address calculation
├── datapath.rb            # Component integration
├── memory.rb              # 64KB memory
├── assembler.rb           # Two-pass assembler
├── status_register.rb     # Status flags (P register)
├── registers.rb           # A, X, Y registers
└── apple2_bus.rb          # Apple II I/O support
```

## Testing

The implementation is thoroughly tested with 189+ tests covering:

- All official instructions (129 tests in `instructions_spec.rb`)
- All addressing modes
- BCD arithmetic
- Stack operations
- Interrupts and BRK
- Algorithmic tests: bubble sort, Fibonacci, multiplication (`algorithms_spec.rb`)

Run tests:
```bash
rake spec_6502
# or
bundle exec rspec spec/examples/mos6502/
```

## References

- [6502 Instruction Set](http://www.6502.org/tutorials/6502opcodes.html)
- [6502 Addressing Modes](http://www.emulator101.com/6502-addressing-modes.html)
- [Visual 6502](http://www.visual6502.org/)
