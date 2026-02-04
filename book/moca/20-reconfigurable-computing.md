# Chapter 16: Reconfigurable Computing

*Hardware that can change itself*

---

## The Flexibility Gap

Traditional computing offers a choice:

| Approach | Flexibility | Performance | Power |
|----------|-------------|-------------|-------|
| CPU (software) | High | Low | High |
| ASIC (fixed hardware) | None | High | Low |

What if we could have both?

**FPGAs** (Field-Programmable Gate Arrays) fill this gap—hardware that can be reprogrammed.

---

## What is an FPGA?

An FPGA is a chip containing:
- **Configurable Logic Blocks (CLBs)**: Programmable logic
- **Programmable Interconnect**: Configurable wiring
- **I/O Blocks**: Programmable pins
- **Hard Blocks**: Fixed-function units (multipliers, RAM, PLLs)

```
┌─────────────────────────────────────────────────────┐
│  I/O   I/O   I/O   I/O   I/O   I/O   I/O   I/O     │
├─────────────────────────────────────────────────────┤
│        ┌─────┐    ┌─────┐    ┌─────┐               │
│  I/O   │ CLB │────│ CLB │────│ CLB │   I/O         │
│        └─────┘    └─────┘    └─────┘               │
│           │          │          │                   │
│        ┌─────┐    ┌─────┐    ┌─────┐               │
│  I/O   │ CLB │────│ RAM │────│ CLB │   I/O         │
│        └─────┘    └─────┘    └─────┘               │
│           │          │          │                   │
│        ┌─────┐    ┌─────┐    ┌─────┐               │
│  I/O   │ CLB │────│ CLB │────│ DSP │   I/O         │
│        └─────┘    └─────┘    └─────┘               │
├─────────────────────────────────────────────────────┤
│  I/O   I/O   I/O   I/O   I/O   I/O   I/O   I/O     │
└─────────────────────────────────────────────────────┘
```

---

## Lookup Tables (LUTs)

The heart of FPGA logic: a small memory that implements any boolean function.

### How LUTs Work

A 4-input LUT can implement ANY function of 4 inputs:

```
Inputs: A, B, C, D (4 bits = 16 combinations)
Contents: 16-bit truth table

Example: 4-input AND
Address: DCBA  Output
0000      0
0001      0
...       0
1111      1

Example: XOR
Address: DCBA  Output
0000      0
0001      1
0010      1
0011      0
...       ...
```

**The magic**: Any 4-input combinational function is just 16 bits of memory.

### LUT Sizes

| LUT Size | Combinations | Common In |
|----------|--------------|-----------|
| 4-LUT | 16 entries | Older FPGAs |
| 5-LUT | 32 entries | Xilinx Spartan |
| 6-LUT | 64 entries | Xilinx 7-series, Intel Stratix |

Larger LUTs = fewer levels of logic = faster circuits.

---

## Configurable Logic Blocks

A CLB combines multiple LUTs with flip-flops and muxes:

```
┌─────────────────────────────────────────────┐
│                    CLB                       │
│  ┌────────────────────────────────────────┐ │
│  │              SLICE                      │ │
│  │   ┌─────┐     ┌───┐                    │ │
│  │   │ LUT │────▶│MUX│──┬──▶ Combinational│ │
│  │   └─────┘     └───┘  │                 │ │
│  │                      │   ┌────┐        │ │
│  │                      └──▶│ FF │──▶ Reg │ │
│  │                          └────┘        │ │
│  │   ┌─────┐     Carry                    │ │
│  │   │ LUT │────────────▶                 │ │
│  │   └─────┘                              │ │
│  └────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────┐ │
│  │              SLICE                      │ │
│  │         (similar structure)             │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Slice features:**
- Multiple LUTs (typically 4-8 per slice)
- Flip-flops for registered outputs
- Carry chains for fast arithmetic
- Wide function muxes

---

## Programmable Interconnect

The routing is as important as the logic:

```
           ┌─────────────────────────────────┐
           │     Programmable Switch Box     │
           │                                 │
     ──────┼──●───────────────────●──────────┼──────
           │  │                   │          │
     ──────┼──┼──●────────────●──┼──────────┼──────
           │  │  │            │  │          │
           │  │  │   ┌───┐    │  │          │
           │  └──┼──▶│PIP│◀───┘  │          │
           │     │   └───┘       │          │
           │     │               │          │
           │     └───────────────┘          │
           └─────────────────────────────────┘

PIP = Programmable Interconnect Point
```

**Routing hierarchy:**
1. **Local interconnect**: Between nearby CLBs
2. **Single-length lines**: Short hops
3. **Double-length lines**: Span 2 CLBs
4. **Long lines**: Cross the chip

---

## Hard Blocks

Modern FPGAs include fixed-function units:

### Block RAM (BRAM)
- Dedicated memory blocks
- True dual-port RAM
- Typically 18-36 Kbit per block
- Much denser than LUT-based memory

### DSP Blocks
- Hardwired multiply-accumulate
- 18×18 or 27×27 multipliers
- Essential for signal processing

### Clock Management
- PLLs (Phase-Locked Loops)
- Clock buffers
- Clock distribution networks

### High-Speed I/O
- LVDS, SERDES transceivers
- DDR memory interfaces
- PCIe, Ethernet MACs

---

## Configuration

FPGAs are configured by loading a **bitstream**:

```
Power On ──▶ Load Bitstream ──▶ Operating
              (milliseconds)

┌──────────────────────────────────────────┐
│            Configuration Memory           │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐    │
│  │LUT │ │ FF │ │MUX │ │PIP │ │I/O │    │
│  │bits│ │init│ │sel │ │bits│ │cfg │    │
│  └────┘ └────┘ └────┘ └────┘ └────┘    │
└──────────────────────────────────────────┘
```

**Configuration modes:**
- **JTAG**: Debug and development
- **Serial Flash**: Boot from SPI flash
- **Parallel Flash**: Faster boot
- **Processor**: Loaded by CPU

---

## Partial Reconfiguration

Change part of the FPGA while the rest runs:

```
┌────────────────────────────────────────┐
│  Static Region  │  Reconfigurable      │
│  (always runs)  │     Region           │
│                 │                      │
│  ┌──────────┐   │  ┌──────────┐       │
│  │ Control  │───┼─▶│ Function │       │
│  │  Logic   │   │  │    A     │       │
│  └──────────┘   │  └──────────┘       │
│                 │         ▼            │
│                 │  ┌──────────┐       │
│                 │  │ Function │       │
│                 │  │    B     │       │
│                 │  └──────────┘       │
└────────────────────────────────────────┘

Swap A↔B without stopping control logic!
```

**Applications:**
- Time-multiplexing functions (don't fit otherwise)
- Software-defined radio (change modulation on the fly)
- Fault tolerance (reload failed region)
- Hardware updates (field upgrades)

---

## FPGA vs ASIC vs CPU

| Metric | FPGA | ASIC | CPU |
|--------|------|------|-----|
| **Clock Speed** | 100-500 MHz | 1-5 GHz | 2-5 GHz |
| **Performance/Watt** | Medium | High | Low |
| **Development Time** | Days-weeks | Months-years | Hours |
| **Unit Cost (1000s)** | $10-$1000 | $1-$10 | $10-$100 |
| **NRE Cost** | $0 | $1M-$100M | $0 |
| **Flexibility** | Reprogrammable | Fixed | Software |

**When to use FPGA:**
- Prototyping ASICs
- Low-volume production
- Algorithms that need parallelism
- Real-time constraints
- Field-upgradable hardware

---

## Soft Processors

Run a CPU inside your FPGA:

```
┌───────────────────────────────────────────────────┐
│                      FPGA                          │
│  ┌─────────────────────┐   ┌──────────────────┐  │
│  │    Soft CPU         │   │  Custom Hardware │  │
│  │  (MicroBlaze/RISC-V)│◀─▶│   Accelerator    │  │
│  │                     │   │                  │  │
│  │    Runs C code      │   │   Fast datapath  │  │
│  └─────────────────────┘   └──────────────────┘  │
│             │                       │             │
│             ▼                       ▼             │
│  ┌─────────────────────────────────────────────┐ │
│  │            Memory Controller                 │ │
│  └─────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────┘
```

**Common soft processors:**
- **MicroBlaze** (Xilinx): 32-bit, configurable
- **Nios II** (Intel): 32-bit, RISC
- **RISC-V cores**: VexRiscv, PicoRV32, Rocket
- **ARM Cortex-M0**: Can be implemented in LUTs

**Hard processors (SoC FPGAs):**
- Xilinx Zynq: ARM Cortex-A9/A53 + FPGA fabric
- Intel Cyclone V SoC: ARM Cortex-A9 + FPGA

---

## High-Level Synthesis (HLS)

Write C/C++, get hardware:

```c
// C code
void matrix_multiply(int A[N][K], int B[K][M], int C[N][M]) {
  for (int i = 0; i < N; i++) {
    for (int j = 0; j < M; j++) {
      C[i][j] = 0;
      for (int k = 0; k < K; k++) {
        C[i][j] += A[i][k] * B[k][j];
      }
    }
  }
}
```

HLS tools (Vitis HLS, Intel HLS) generate:
- Pipelined datapath
- Control FSM
- Memory interfaces

**Pragmas control optimization:**
```c
#pragma HLS PIPELINE II=1    // Fully pipelined
#pragma HLS UNROLL factor=4  // Parallel iterations
#pragma HLS ARRAY_PARTITION  // Memory banking
```

---

## Real-World Applications

### Data Centers
- **Amazon F1**: FPGA instances in AWS
- **Microsoft Catapult**: Bing search acceleration
- **Compression/encryption**: Line-rate processing

### Networking
- SmartNICs with FPGA
- High-frequency trading (<1μs latency)
- 100Gbps packet processing

### Machine Learning
- CNN inference acceleration
- Low-latency, low-power edge AI
- Quantized networks fit well

### Scientific Computing
- Radio astronomy (CASPER)
- Particle physics (CERN triggers)
- DNA sequencing (alignment)

### Video/Image Processing
- Real-time 4K/8K processing
- Camera ISP pipelines
- Medical imaging

---

## FPGA Development Flow

```
┌─────────────┐
│   Design    │  Verilog/VHDL/RHDL
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Synthesis  │  Logic optimization
└──────┬──────┘
       │
       ▼
┌─────────────┐
│Implementation│  Place & Route
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Timing    │  Verify constraints met
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Bitstream  │  Binary configuration
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Program   │  Load into FPGA
└─────────────┘
```

---

## FPGA Vendors

### Xilinx (now AMD)
- **Artix**: Low-cost, low-power
- **Kintex**: Mid-range, balanced
- **Virtex**: High-performance
- **Zynq**: ARM + FPGA
- **Versal**: AI-optimized (AI Engines)

### Intel (formerly Altera)
- **Cyclone**: Low-cost
- **Arria**: Mid-range
- **Stratix**: High-performance
- **Agilex**: Latest generation

### Lattice
- **iCE40**: Tiny, low-power
- **ECP5**: Open-source toolchain support
- **CrossLink**: Video bridging

### Others
- **Microchip (Microsemi)**: Radiation-hardened
- **Gowin**: Chinese vendor, low-cost
- **Efinix**: Quantum fabric architecture

---

## RHDL and FPGAs

RHDL designs can target FPGAs:

```ruby
# Design in RHDL
cpu = RHDL::HDL::CPU.new('my_cpu', width: 8)

# Export to Verilog
verilog = RHDL::Export::Verilog.export(cpu)
File.write('cpu.v', verilog)

# Then use FPGA vendor tools:
# - Vivado (Xilinx)
# - Quartus (Intel)
# - Diamond (Lattice)
```

See [Appendix P](appendix-p-reconfigurable.md) for LUT-based implementations.

---

## Summary

- **FPGAs are programmable hardware**: LUTs + interconnect + hard blocks
- **LUTs are small memories**: Any boolean function in 16-64 bits
- **Trade-offs**: Slower than ASIC, faster than CPU, reprogrammable
- **Modern FPGAs**: Include DSP, RAM, high-speed I/O, even CPUs
- **Partial reconfiguration**: Change hardware while running
- **HLS**: Write C, get hardware (with caveats)
- **Applications**: Data centers, networking, ML, video, science

---

## Exercises

1. Estimate LUT count for a 4-bit ALU
2. Design a simple FPGA routing algorithm
3. Compare soft vs hard processor for a given task
4. Implement partial reconfiguration controller
5. Port an RHDL design to an FPGA development board

---

## Further Reading

- Kuon & Rose, "FPGA Architecture: Survey and Challenges"
- Xilinx UG474: 7 Series FPGA CLB User Guide
- Intel Quartus Prime Handbook
- Lattice iCE40 Programming and Configuration Guide

---

*Next: [Chapter 20 - The MOS 6502](17-mos6502.md)*

*Appendix: [Appendix P - FPGA Implementation](appendix-p-reconfigurable.md)*
