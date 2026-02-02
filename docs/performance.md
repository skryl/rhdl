# Performance Guide

This guide covers RHDL's execution backends, their performance characteristics, and how to benchmark your designs.

## Execution Backends Overview

RHDL provides multiple simulation backends with different performance/flexibility tradeoffs:

| Backend | Type | Speed | Startup | Best For |
|---------|------|-------|---------|----------|
| Ruby Behavioral | Interpreted | Baseline | Immediate | Development, debugging |
| IR Interpreter | Native (Rust) | ~60K cycles/s | Immediate | Interactive debugging |
| IR JIT | Native (Cranelift) | ~200-600K cycles/s | 0.05-0.5s | Moderate simulations |
| IR Compiler | Native (AOT) | ~1-2M cycles/s | 5-8s | Long simulations |
| Verilator | External (C++) | ~5-6M cycles/s | 10-30s | Maximum performance |

## Benchmarking Rake Tasks

RHDL includes rake tasks for benchmarking different system configurations:

### MOS 6502 CPU Benchmark

Benchmarks the MOS 6502 CPU running Karateka game code with memory bridging:

```bash
rake bench:mos6502              # Default: 5M cycles
rake bench:mos6502[1000000]     # Custom: 1M cycles
```

**Sample Results (1M cycles):**

| Backend | Init Time | Run Time | Rate | Speedup |
|---------|-----------|----------|------|---------|
| Interpreter | - | - | - | (skipped >100K) |
| JIT | 0.06s | 4.32s | 0.23M/s | 1.0x |
| Compiler | 7.88s | 0.63s | 1.58M/s | 6.8x |
| Verilator | ~15s | ~0.18s | ~5.6M/s | ~24x |

### Apple II Full System Benchmark

Benchmarks the complete Apple II system (CPU + memory + I/O) running Karateka:

```bash
rake bench:apple2               # Default: 5M cycles
rake bench:apple2[1000000]      # Custom: 1M cycles
```

**Sample Results (1M cycles):**

| Backend | Init Time | Run Time | Rate | Speedup |
|---------|-----------|----------|------|---------|
| Interpreter | - | - | - | (skipped >100K) |
| JIT | 0.05s | 17.38s | 0.06M/s | 1.0x |
| Compiler | 6.46s | 3.62s | 0.28M/s | 4.8x |
| Verilator | ~20s | ~0.18s | ~5.6M/s | ~97x |

### GameBoy Benchmark

Benchmarks the GameBoy running Prince of Persia ROM for a specified number of frames:

```bash
rake bench:gameboy              # Default: 1000 frames
rake bench:gameboy[100]         # Custom: 100 frames
```

**Sample Results (100 frames / 7M cycles):**

| Backend | Init Time | Run Time | Speed | % Real-time |
|---------|-----------|----------|-------|-------------|
| IR Compiler | 5.63s | 5.51s | 1.27 MHz | 30.4% |
| Verilator | ~15s | ~1.2s | ~5.8 MHz | ~138% |

The GameBoy runs at 4.19 MHz, so backends achieving >100% can run faster than real hardware.

### Gate-Level Benchmark

Benchmarks low-level gate simulation:

```bash
rake bench:gates                # Gate-level toggle benchmark
```

## Backend Selection Guide

### When to Use Each Backend

**Ruby Behavioral**
- Developing new components
- Interactive debugging with detailed error messages
- Small test cases where performance isn't critical
- Validating correctness before synthesis

**IR Interpreter**
- Interactive CPU debugging with breakpoints
- Small simulation runs (<100K cycles)
- When you need visibility into instruction execution

**IR JIT (Cranelift)**
- Moderate length simulations (100K - 10M cycles)
- Good balance between startup time and sustained speed
- Running games interactively

**IR Compiler (AOT)**
- Long simulations (>1M cycles)
- Full system simulation
- When compilation time is acceptable for faster execution
- Batch testing

**Verilator**
- Maximum performance requirements
- Reference validation against RTL
- Running complex games at real-time or faster
- When you need cycle-accurate RTL simulation

### Performance vs. Startup Tradeoff

The backends have an inverse relationship between startup time and runtime performance:

```
                  Startup Time
Fast ←───────────────────────────────────→ Slow
 │                                           │
 │  Interpreter   JIT    Compiler  Verilator │
 │      ↓          ↓         ↓         ↓     │
 │    Slow      Medium    Fast     Fastest   │
 │                                           │
Slow ←───────────────────────────────────→ Fast
                  Runtime Speed
```

**Rule of thumb:**
- For <100K cycles: Use Interpreter or JIT
- For 100K-1M cycles: Use JIT
- For 1M-10M cycles: Use Compiler
- For >10M cycles: Use Verilator (if available)

## Building Native Extensions

Native backends require the Rust toolchain. Build all extensions with:

```bash
rake native:build    # Build all Rust extensions
rake native:check    # Verify availability
rake native:clean    # Clean build artifacts
```

The build process compiles:
- ISA Simulator Native (MOS 6502)
- Netlist Interpreter (gate-level)
- Netlist JIT (gate-level Cranelift)
- Netlist Compiler (gate-level SIMD)
- IR Interpreter
- IR JIT (Cranelift)
- IR Compiler (AOT)

## Installing Verilator

Verilator provides the fastest simulation by compiling Verilog to optimized C++:

```bash
# Ubuntu/Debian
sudo apt-get install verilator

# macOS
brew install verilator

# Verify installation
verilator --version
```

When Verilator is available, it's automatically included in benchmark comparisons.

## Interpreting Benchmark Results

### Key Metrics

- **Init Time**: Time to initialize the backend (includes JIT/AOT compilation)
- **Run Time**: Time to execute the specified cycles
- **Rate**: Cycles per second (higher is better)
- **Speed**: For GameBoy, percentage of real hardware speed (4.19 MHz)

### Factors Affecting Performance

1. **Circuit Complexity**: More gates/signals = slower simulation
2. **Memory Access Patterns**: Frequent memory operations add overhead
3. **Backend Optimization Level**: Compiler > JIT > Interpreter
4. **Hardware**: CPU speed, cache size, SIMD support (AVX2/AVX512)

### Typical Performance Ranges

| System | IR JIT | IR Compiler | Verilator |
|--------|--------|-------------|-----------|
| MOS 6502 (CPU only) | 200-300K/s | 1.5-2M/s | 5-6M/s |
| Apple II (full system) | 50-100K/s | 250-400K/s | 5-6M/s |
| GameBoy (full system) | 400-600K/s | 1-1.5M/s | 5-6M/s |

## Profiling Tips

### Identifying Bottlenecks

1. **Compare backends**: Large JIT-to-Compiler speedup suggests bytecode overhead
2. **Check init time**: Long init suggests complex IR generation
3. **Monitor memory**: High memory usage may indicate inefficient signal storage

### Optimizing Designs

1. **Reduce hierarchy depth**: Flatter designs simulate faster
2. **Minimize wire fan-out**: High fan-out increases update propagation
3. **Use registers wisely**: Excessive registers add clock overhead
4. **Batch operations**: Process multiple test vectors with SIMD backends

## See Also

- [Simulation](simulation.md) - Detailed backend documentation
- [Gate-Level Backend](gate_level_backend.md) - Gate-level synthesis and simulation
- [CLI Reference](cli.md) - Command-line tools
