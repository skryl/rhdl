# Chapter 5: Memory Systems

## Overview

How computers store data: RAM, ROM, caches, and memory hierarchies.

## Key Concepts

### Memory as an Array

From software perspective: `memory[address] = data`

From hardware perspective:
- Address decoder selects which cell
- Data lines carry the value
- Read/Write control signals

### Types of Memory

**ROM (Read-Only Memory):**
- Contents fixed at manufacture or programming
- Non-volatile (survives power off)
- Used for: boot code, lookup tables

**RAM (Random Access Memory):**
- Read and write
- Volatile (loses contents on power off)

**SRAM (Static RAM):**
- Uses flip-flops (6 transistors per bit)
- Fast, but expensive and large
- Used for: CPU registers, cache

**DRAM (Dynamic RAM):**
- Uses capacitors (1 transistor + 1 capacitor per bit)
- Slow, cheap, dense
- Needs refresh (capacitors leak)
- Used for: main memory

### Building Memory in Hardware

Simple 4x4 RAM:

```ruby
class RAM_4x4 < SimComponent
  input :clk
  input :addr, width: 2   # 4 locations
  input :data_in, width: 4
  input :write_en
  output :data_out, width: 4

  # Internal storage (4 registers)
  wire :mem0, width: 4
  wire :mem1, width: 4
  wire :mem2, width: 4
  wire :mem3, width: 4

  behavior do
    # Address decoding + read
    data_out <= case addr
      when 0 then mem0
      when 1 then mem1
      when 2 then mem2
      when 3 then mem3
    end

    # Write logic
    on rising_edge(clk) do
      if write_en
        case addr
          when 0 then mem0 <= data_in
          when 1 then mem1 <= data_in
          # ...
        end
      end
    end
  end
end
```

### ROM Implementation

```ruby
class ROM_8x8 < SimComponent
  input :addr, width: 3
  output :data, width: 8

  # Contents defined at design time
  CONTENTS = [
    0x00, 0x01, 0x02, 0x03,
    0xFF, 0xFE, 0x55, 0xAA
  ]

  behavior do
    data <= CONTENTS[addr]
  end
end
```

### Register Files

Multiple registers with read/write ports:
- Used in CPUs
- Multiple simultaneous reads (e.g., 2 operands)
- Usually 1 write port

```ruby
class RegisterFile < SimComponent
  input :clk
  input :read_addr1, width: 3
  input :read_addr2, width: 3
  input :write_addr, width: 3
  input :write_data, width: 8
  input :write_en
  output :read_data1, width: 8
  output :read_data2, width: 8

  # 8 registers
end
```

### Memory Hierarchy

Speed vs Size tradeoff:
1. **Registers** - Fastest, smallest (bytes)
2. **L1 Cache** - Very fast (KB)
3. **L2 Cache** - Fast (MB)
4. **L3 Cache** - Medium (MB)
5. **Main Memory** - Slow (GB)
6. **Storage** - Slowest (TB)

### Cache Basics

Why caches work:
- **Temporal locality**: Recently used data likely used again
- **Spatial locality**: Nearby data likely accessed together

Cache concepts:
- Cache line/block
- Hit vs Miss
- Direct-mapped vs Set-associative
- Write-through vs Write-back

## Hands-On Project: 256-Byte RAM

Build a working RAM:
- 8-bit address (256 locations)
- 8-bit data
- Read and write operations
- Test with a simple program

## Exercises

1. Implement a 2-way set-associative cache
2. Build a ROM containing a sine lookup table
3. Design a dual-port RAM

---

## Notes and Ideas

- Visualization: memory as a grid/spreadsheet
- Show actual SRAM cell circuit
- Discuss memory-mapped I/O (addresses that aren't memory)
- Real-world: why memory bandwidth matters for performance
- Software connection: how your array indexing becomes this
