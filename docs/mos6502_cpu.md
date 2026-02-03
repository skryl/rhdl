# MOS 6502 CPU Implementation

The `examples/mos6502/` directory contains a complete behavior simulation of the MOS 6502 microprocessor, including all official instructions, addressing modes, a two-pass assembler, and multiple simulation backends.

## Architecture Overview

The implementation follows the actual 6502 architecture with these components:

```
┌─────────────────────────────────────────────────────────────┐
│                        MOS6502::CPU                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐    │
│  │                     Datapath                         │    │
│  │  ┌─────────────────────────────────────────────────┐│    │
│  │  │           Registers                             ││    │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐ ││    │
│  │  │  │ A (8b)  │  │ X (8b)  │  │ Y (8b)          │ ││    │
│  │  │  └─────────┘  └─────────┘  └─────────────────┘ ││    │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────────────┐ ││    │
│  │  │  │ PC(16b) │  │ SP (8b) │  │ Status (8b)     │ ││    │
│  │  │  └─────────┘  └─────────┘  │ N V - B D I Z C │ ││    │
│  │  │                            └─────────────────┘ ││    │
│  │  └─────────────────────────────────────────────────┘│    │
│  │  ┌─────────────────────────────────────────────────┐│    │
│  │  │                    ALU                          ││    │
│  │  │  14 Operations: ADC, SBC, AND, ORA, EOR,       ││    │
│  │  │  ASL, LSR, ROL, ROR, INC, DEC, CMP, BIT, TST   ││    │
│  │  └─────────────────────────────────────────────────┘│    │
│  │  ┌─────────────────────────────────────────────────┐│    │
│  │  │             Address Generator                   ││    │
│  │  │  13 Addressing Modes                           ││    │
│  │  └─────────────────────────────────────────────────┘│    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Control Unit (26 States)              │    │
│  │  RESET → FETCH → DECODE → EXECUTE → WRITE...      │    │
│  └────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌────────────────────────────────────────────────────┐    │
│  │           Instruction Decoder (151 opcodes)        │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │     Memory      │
                    │   64KB (RAM/ROM)│
                    └─────────────────┘
```

## Components

### CPU (`hdl/cpu.rb`)

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

### ALU (`hdl/alu.rb`)

Full arithmetic logic unit supporting all 6502 operations.

**Operations (14 total):**
| Code | Mnemonic | Description | Flags Affected |
|------|----------|-------------|----------------|
| 0x00 | ADC | Add with carry | N, V, Z, C |
| 0x01 | SBC | Subtract with borrow | N, V, Z, C |
| 0x02 | AND | Bitwise AND | N, Z |
| 0x03 | ORA | Bitwise OR | N, Z |
| 0x04 | EOR | Bitwise XOR | N, Z |
| 0x05 | ASL | Arithmetic shift left | N, Z, C |
| 0x06 | LSR | Logical shift right | N, Z, C |
| 0x07 | ROL | Rotate left through carry | N, Z, C |
| 0x08 | ROR | Rotate right through carry | N, Z, C |
| 0x09 | INC | Increment | N, Z |
| 0x0A | DEC | Decrement | N, Z |
| 0x0B | CMP | Compare (flags only) | N, Z, C |
| 0x0C | BIT | Bit test | N, V, Z |
| 0x0D | TST | Pass through (for transfers) | N, Z |

**BCD Mode:** Full decimal mode support for ADC and SBC operations, matching hardware behavior including the infamous BCD flags behavior.

### Control Unit (`hdl/control_unit.rb`)

State machine that sequences instruction execution with 26 distinct states.

**States:**
| State | Code | Description |
|-------|------|-------------|
| `RESET` | 0x00 | Reset sequence |
| `FETCH` | 0x01 | Fetch opcode from memory |
| `DECODE` | 0x02 | Decode instruction |
| `FETCH_OP1` | 0x03 | Fetch first operand byte |
| `FETCH_OP2` | 0x04 | Fetch second operand byte |
| `ADDR_LO` | 0x05 | Fetch indirect address low byte |
| `ADDR_HI` | 0x06 | Fetch indirect address high byte |
| `READ_MEM` | 0x07 | Read from effective address |
| `EXECUTE` | 0x08 | ALU operation |
| `WRITE_MEM` | 0x09 | Write to memory |
| `PUSH` | 0x0A | Push to stack |
| `PULL` | 0x0B | Pull from stack |
| `BRANCH` | 0x0C | Branch decision |
| `BRANCH_TAKE` | 0x0D | Branch taken, add offset |
| `JSR_PUSH_HI` | 0x0E | JSR: push PC high |
| `JSR_PUSH_LO` | 0x0F | JSR: push PC low |
| `RTS_PULL_LO` | 0x10 | RTS: pull PC low |
| `RTS_PULL_HI` | 0x11 | RTS: pull PC high |
| `RTI_PULL_P` | 0x12 | RTI: pull status |
| `RTI_PULL_LO` | 0x13 | RTI: pull PC low |
| `RTI_PULL_HI` | 0x14 | RTI: pull PC high |
| `BRK_PUSH_HI` | 0x15 | BRK: push PC high |
| `BRK_PUSH_LO` | 0x16 | BRK: push PC low |
| `BRK_PUSH_P` | 0x17 | BRK: push status |
| `BRK_VEC_LO` | 0x18 | BRK: read vector low |
| `BRK_VEC_HI` | 0x19 | BRK: read vector high |
| `HALT` | 0xFF | Halted |

### Instruction Decoder (`hdl/instruction_decoder.rb`)

Decodes opcodes into control signals. Supports all 56 official opcodes plus their addressing mode variants (151 valid opcodes).

**Instruction Categories:**
| Type | Instructions | Count |
|------|--------------|-------|
| ALU | ADC, SBC, AND, ORA, EOR, CMP | 6 |
| Load | LDA, LDX, LDY | 3 |
| Store | STA, STX, STY | 3 |
| Transfer | TAX, TXA, TAY, TYA, TSX, TXS | 6 |
| Increment | INC, INX, INY | 3 |
| Decrement | DEC, DEX, DEY | 3 |
| Shift | ASL, LSR, ROL, ROR | 4 |
| Branch | BCC, BCS, BEQ, BMI, BNE, BPL, BVC, BVS | 8 |
| Jump | JMP (abs), JMP (ind), JSR | 3 |
| Return | RTS, RTI | 2 |
| Stack | PHA, PHP, PLA, PLP | 4 |
| Flags | CLC, SEC, CLI, SEI, CLV, CLD, SED | 7 |
| Other | BIT, NOP, BRK | 3 |

### Address Generator (`hdl/address_gen.rb`)

Calculates effective addresses for all 13 addressing modes.

**Addressing Modes:**
| Mode | Code | Example | Description | Cycles |
|------|------|---------|-------------|--------|
| Implied | 0x00 | `CLC` | No operand | 2 |
| Accumulator | 0x01 | `ASL A` | Operates on A | 2 |
| Immediate | 0x02 | `LDA #$42` | 8-bit literal | 2 |
| Zero Page | 0x03 | `LDA $00` | 8-bit address (page 0) | 3 |
| Zero Page,X | 0x04 | `LDA $00,X` | ZP + X register | 4 |
| Zero Page,Y | 0x05 | `LDX $00,Y` | ZP + Y register | 4 |
| Absolute | 0x06 | `LDA $1234` | 16-bit address | 4 |
| Absolute,X | 0x07 | `LDA $1234,X` | Absolute + X | 4+ |
| Absolute,Y | 0x08 | `LDA $1234,Y` | Absolute + Y | 4+ |
| Indirect | 0x09 | `JMP ($1234)` | Pointer dereference | 5 |
| Indexed Indirect | 0x0A | `LDA ($00,X)` | (ZP + X) pointer | 6 |
| Indirect Indexed | 0x0B | `LDA ($00),Y` | (ZP) + Y | 5+ |
| Relative | 0x0C | `BNE label` | PC + signed offset | 2+ |
| Stack | 0x0D | `PHA` | Stack operations | 3-4 |

**Page Boundary Crossing:** Modes marked with "+" take an extra cycle when crossing page boundaries.

### Datapath (`hdl/datapath.rb`)

Integrates all CPU components with internal buses and control signals.

**Subcomponents:**
- **Registers** (`hdl/registers/`)
  - A, X, Y (8-bit general purpose)
  - Program Counter (16-bit)
  - Stack Pointer (8-bit, fixed to page $01)
  - Instruction Register (8-bit)
  - Address Latch (16-bit)
  - Data Latch (8-bit)
- **Status Register** - N, V, B, D, I, Z, C flags
- **ALU** - 14 operations
- **Control Unit** - 26-state FSM
- **Instruction Decoder** - Opcode to control signals
- **Address Generator** - Effective address calculation

### Memory (`hdl/memory.rb`)

64KB addressable memory with RAM and ROM regions.

**Memory Map:**
| Range | Size | Description |
|-------|------|-------------|
| $0000-$00FF | 256B | Zero Page |
| $0100-$01FF | 256B | Stack |
| $0200-$07FF | 1.5KB | Free RAM |
| $0000-$7FFF | 32KB | RAM (total) |
| $8000-$FFFF | 32KB | ROM (program space) |
| $FFFA-$FFFB | 2B | NMI Vector |
| $FFFC-$FFFD | 2B | Reset Vector |
| $FFFE-$FFFF | 2B | IRQ/BRK Vector |

## Simulation Backends

RHDL provides multiple simulation backends for the 6502 with different performance characteristics.

### ISA Simulator (`utilities/isa_simulator.rb`)

Fast instruction-level simulator for performance-critical applications. Executes instructions directly without HDL simulation overhead.

```ruby
require_relative 'examples/mos6502/utilities/isa_simulator'

sim = MOS6502::ISASimulator.new
sim.memory[0xFFFC] = 0x00  # Reset vector low
sim.memory[0xFFFD] = 0x80  # Reset vector high ($8000)

# Load program at $8000
program = [0xA9, 0x42, 0x00]  # LDA #$42; BRK
program.each_with_index { |b, i| sim.memory[0x8000 + i] = b }

sim.reset
sim.run(100)  # Run up to 100 instructions

puts "A = $#{sim.a.to_s(16).upcase}"  # A = $42
```

**Features:**
- All 56 official instructions
- All 13 addressing modes
- Full BCD arithmetic support
- Cycle-accurate timing
- Memory callback support for I/O

### Native Rust Extension (`utilities/isa_simulator_native.rb`)

High-performance ISA simulator implemented in Rust for ~7x speedup.

```ruby
require_relative 'examples/mos6502/utilities/isa_simulator_native'

# Build native extension first
# cd examples/mos6502/utilities/isa_simulator_native && rake

sim = MOS6502::ISASimulatorNative.new
# Same API as ISASimulator
```

**Performance Comparison:**
| Backend | Instructions/sec | Relative Speed |
|---------|-----------------|----------------|
| HDL Simulation | ~50,000 | 1x |
| Ruby ISA | ~500,000 | 10x |
| Native Rust | ~3,500,000 | 70x |

### Ruby ISA Runner (`utilities/runners/ruby_isa_runner.rb`)

Convenience wrapper for running programs with the ISA simulator.

```ruby
runner = MOS6502::RubyISARunner.new
runner.load_rom(rom_bytes, base_addr: 0xF800)
runner.load_ram(program, base_addr: 0x0800)
runner.reset
runner.run_until(max_cycles: 100_000) { runner.halted? }
```

### IR Simulator (`utilities/runners/ir_simulator_runner.rb`)

Runs programs using the gate-level intermediate representation.

```ruby
runner = MOS6502::IRSimulatorRunner.new(backend: :jit)
runner.load_rom(rom_bytes, base_addr: 0xF800)
runner.reset
runner.run_cycles(10_000)
```

**Backends:**
- `:interpreter` - Ruby-based gate evaluation
- `:jit` - JIT-compiled simulation
- `:compile` - AOT-compiled simulation

## Assembler

The two-pass assembler (`utilities/assembler.rb`) supports the full 6502 instruction set.

**Features:**
- All official mnemonics and addressing modes
- Labels (forward and backward references)
- Equates and constants
- Directives: `.ORG`, `*=`, `.BYTE`, `.WORD`, `.END`
- Expressions with `+`, `-`, `<` (low byte), `>` (high byte)
- Comments with `;`
- Case-insensitive mnemonics

**Example Program:**
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
        .WORD START     ; 16-bit address (little-endian)
        .WORD >START    ; High byte only
        .WORD <START    ; Low byte only
```

**API Usage:**
```ruby
require_relative 'examples/mos6502/utilities/asm/assembler'

program = MOS6502::Assembler.assemble(source_code, org: 0x8000)
File.binwrite("program.bin", program.pack("C*"))

# Or with the CPU directly
cpu = MOS6502::CPU.new
cpu.assemble_and_load(source_code, 0x8000)
cpu.reset
cpu.run
```

## Test Programs

The `spec/examples/mos6502/` directory contains comprehensive tests including:

### Algorithms (`algorithms_spec.rb`)

- **Bubble Sort**: Sorts 8-byte array in zero page
- **Fibonacci**: Computes Fibonacci sequence
- **Multiplication**: 8x8 → 16-bit multiply
- **Division**: 16÷8 → quotient and remainder
- **String Operations**: Length, copy, compare

### Instructions (`instructions_spec.rb`)

129 tests covering all official instructions:
- Load/Store operations
- Arithmetic (ADC, SBC with BCD)
- Logic (AND, ORA, EOR)
- Shifts/Rotates
- Branches (all 8 conditions)
- Stack operations
- Transfers
- Flag operations

### Addressing Modes (`addressing_modes_spec.rb`)

Tests for all 13 addressing modes including edge cases:
- Page boundary crossing
- Zero page wrapping
- Indirect addressing (including JMP bug at $xxFF)

## File Structure

```
examples/mos6502/
├── hdl/                        # HDL components
│   ├── cpu.rb                  # Main CPU class
│   ├── alu.rb                  # Arithmetic Logic Unit
│   ├── control_unit.rb         # 26-state FSM
│   ├── instruction_decoder.rb  # Opcode decoder
│   ├── address_gen.rb          # Address calculation loader
│   ├── address_gen/            # Address generator components
│   │   ├── address_generator.rb
│   │   └── indirect_address_calc.rb
│   ├── datapath.rb             # Component integration
│   ├── memory.rb               # 64KB memory
│   ├── status_register.rb      # Status flags (P register)
│   ├── harness.rb              # Test harness wrapper
│   └── registers/              # Register components
│       ├── registers.rb        # A, X, Y registers
│       ├── program_counter.rb  # 16-bit PC
│       ├── stack_pointer.rb    # 8-bit SP
│       ├── instruction_register.rb
│       ├── address_latch.rb
│       └── data_latch.rb
│
├── utilities/                  # Simulation utilities
│   ├── assembler.rb            # Two-pass assembler
│   ├── isa_simulator.rb        # Ruby ISA simulator
│   ├── isa_simulator_native.rb # Rust native extension
│   ├── isa_simulator_native/   # Native extension source
│   │   └── extconf.rb
│   ├── ruby_isa_runner.rb      # ISA runner wrapper
│   ├── ir_simulator_runner.rb  # IR/gate-level runner
│   ├── benchmark_native.rb     # Performance benchmarks
│   ├── apple2_bus.rb           # Apple II I/O support
│   ├── apple2_harness.rb       # Apple II test harness
│   ├── apple2_speaker.rb       # Audio simulation
│   ├── disk2.rb                # Disk II controller
│   ├── color_renderer.rb       # Terminal color output
│   └── mos6502_verilator.rb    # Verilator integration
```

## Testing

The implementation is thoroughly tested with 189+ tests covering:

- All official instructions (129 tests in `instructions_spec.rb`)
- All addressing modes
- BCD arithmetic
- Stack operations
- Interrupts and BRK
- Algorithmic tests: bubble sort, Fibonacci, multiplication (`algorithms_spec.rb`)

**Running Tests:**
```bash
# Run all 6502 tests
bundle exec rake spec_6502

# Run in parallel (faster)
bundle exec rake parallel:spec_6502

# Run specific test file
bundle exec rspec spec/examples/mos6502/instructions_spec.rb

# Run with documentation format
bundle exec rspec spec/examples/mos6502/ --format documentation
```

## Performance Benchmarks

Run benchmarks comparing different backends:

```bash
# Benchmark native vs Ruby ISA simulator
ruby examples/mos6502/utilities/benchmark_native.rb
```

**Typical Results (1 million instructions):**

| Backend | Time | IPS |
|---------|------|-----|
| Ruby ISA | ~2.0s | 500K |
| Native Rust | ~0.3s | 3.5M |
| Speedup | | 7x |

## Debugging

### Status String Format

```
A:42 X:00 Y:00 SP:FD PC:8006 P:30 [nv-BdIzc]
```

**Flag Display:**
- Uppercase = set (1)
- Lowercase = clear (0)
- `-` = unused bit (always 1)

### Disassembly

```ruby
cpu.disassemble(0x8000, 10)  # Disassemble 10 instructions from $8000
```

**Output:**
```
$8000: A9 42     LDA #$42
$8002: 85 00     STA $00
$8004: 00        BRK
```

### Breakpoints

```ruby
cpu.set_breakpoint(0x8004)  # Break at BRK
cpu.run                      # Stops at breakpoint
cpu.clear_breakpoint(0x8004)
```

## References

- [6502 Instruction Set](http://www.6502.org/tutorials/6502opcodes.html)
- [6502 Addressing Modes](http://www.emulator101.com/6502-addressing-modes.html)
- [Visual 6502](http://www.visual6502.org/)
- [Nesdev Wiki](https://www.nesdev.org/wiki/CPU)
- [6502 Decimal Mode](http://www.6502.org/tutorials/decimal_mode.html)

## See Also

- [Apple II Emulation](apple2.md) - Apple II system using 6502
- [Simulation Backends](simulation.md) - All simulation options
- [DSL Reference](dsl.md) - RHDL DSL documentation
