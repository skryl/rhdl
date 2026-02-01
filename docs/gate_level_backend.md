# Gate-Level Synthesis Backend

RHDL provides a complete gate-level synthesis backend that lowers HDL components to primitive gate netlists. This enables hardware-accurate simulation at the gate level and supports verification against behavioral models.

## Overview

The gate-level backend converts high-level HDL components into netlists composed of seven primitive gate types plus D flip-flops. This provides:

- **Structural Verification**: Compare gate-level behavior against behavioral simulation
- **Timing Analysis**: Understand propagation delays through gate chains
- **FPGA/ASIC Estimation**: Get gate count metrics for synthesis planning
- **Educational Value**: Visualize how high-level constructs map to gates

## Architecture

```
HDL Component (Ruby DSL)
        │
        ▼
┌───────────────────┐
│   Netlist Lower   │  lib/rhdl/codegen/structure/lower.rb
└───────────────────┘
        │
        ▼
┌───────────────────┐
│  Structure IR     │  Gate-level intermediate representation
└───────────────────┘
        │
        ├──────────────┬──────────────┬──────────────┐
        ▼              ▼              ▼              ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  JSON Export│ │ CPU Sim     │ │ GPU Sim     │ │ Verilog Gen │
└─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘
```

## Primitive Gates

The backend uses seven combinational primitives plus flip-flops:

| Gate | Inputs | Function | Notes |
|------|--------|----------|-------|
| `AND` | 2+ | `a & b` | N-ary AND reduced to binary tree |
| `OR` | 2+ | `a \| b` | N-ary OR reduced to binary tree |
| `XOR` | 2 | `a ^ b` | Binary only |
| `NOT` | 1 | `~a` | Inverter |
| `MUX` | 3 | `sel ? t : f` | 2-to-1 multiplexer (select, when_true, when_false) |
| `BUF` | 1 | `a` | Buffer/identity (used for fan-out) |
| `CONST` | 0 | `value` | Constant 0 or 1 |

**Sequential Element:**

| Element | Inputs | Function |
|---------|--------|----------|
| `DFF` | d, clk, rst, en | D flip-flop with optional reset and enable |

## Netlist IR Structure

The Structure IR (`RHDL::Codegen::Structure::IR`) represents gate-level designs:

```ruby
ir = RHDL::Codegen::Structure::IR.new(
  name: "component_name",
  net_count: 42,           # Total number of nets
  gates: [...],            # Array of Gate structs
  dffs: [...],             # Array of DFF structs
  inputs: { "a" => [0, 1, 2, 3, 4, 5, 6, 7] },  # Input net mappings
  outputs: { "y" => [32, 33, 34, 35, 36, 37, 38, 39] }  # Output net mappings
)
```

### Gate Structure

```ruby
Gate = Struct.new(:type, :inputs, :output, :value)
# type:   :AND, :OR, :XOR, :NOT, :MUX, :BUF, :CONST
# inputs: Array of net indices feeding this gate
# output: Net index for gate output
# value:  Constant value (for CONST gates only)
```

### DFF Structure

```ruby
DFF = Struct.new(:d, :q, :rst, :en, :async_reset, :reset_value)
# d:           D input net index
# q:           Q output net index
# rst:         Reset signal net index (optional)
# en:          Enable signal net index (optional)
# async_reset: Boolean for asynchronous reset behavior
# reset_value: Value on reset (0 or 1)
```

## Supported Components

The backend supports 53 HDL components for gate-level lowering:

### Gates (13 components)
- `AndGate`, `OrGate`, `XorGate`, `NotGate`
- `NandGate`, `NorGate`, `XnorGate`
- `Buffer`, `TristateBuffer`
- `BitwiseAnd`, `BitwiseOr`, `BitwiseXor`, `BitwiseNot`

### Sequential (12 components)
- `DFlipFlop`, `DFlipFlopAsync`
- `TFlipFlop`, `JKFlipFlop`
- `SRFlipFlop`, `SRLatch`
- `Register`, `RegisterLoad`, `ShiftRegister`
- `Counter`, `ProgramCounter`, `StackPointer`

### Arithmetic (10 components)
- `HalfAdder`, `FullAdder`, `RippleCarryAdder`
- `Subtractor`, `AddSub`, `IncDec`
- `Comparator`
- `Multiplier` (array multiplier)
- `Divider` (restoring divider)
- `ALU` (16 operations)

### Combinational (16 components)
- `Mux2`, `Mux4`, `Mux8`, `MuxN`
- `Demux2`, `Demux4`
- `Decoder2to4`, `Decoder3to8`
- `Encoder4to2`, `Encoder8to3`, `PriorityEncoder`
- `BarrelShifter`
- `BitReverse`, `SignExtend`, `ZeroExtend`
- `ZeroDetect`, `PopCount`, `LeadingZeroCount`

### CPU (2 components)
- `InstructionDecoder`
- `SynthDatapath` (hierarchical CPU datapath)

## Usage

### Basic Synthesis

```ruby
require 'rhdl'

# Create a component
alu = RHDL::HDL::ALU.new('alu', width: 8)

# Lower to gate-level IR
ir = RHDL::Codegen::Structure::Lower.from_components([alu], name: 'alu')

# Get statistics
puts "Gates: #{ir.gates.length}"
puts "DFFs: #{ir.dffs.length}"
puts "Nets: #{ir.net_count}"
```

### Export to JSON

```ruby
# Export netlist to JSON
File.write('alu.json', ir.to_json)
```

JSON structure:
```json
{
  "name": "alu",
  "net_count": 1234,
  "inputs": {
    "a": [0, 1, 2, 3, 4, 5, 6, 7],
    "b": [8, 9, 10, 11, 12, 13, 14, 15]
  },
  "outputs": {
    "result": [100, 101, 102, 103, 104, 105, 106, 107]
  },
  "gates": [
    {"type": "AND", "inputs": [0, 8], "output": 50},
    {"type": "XOR", "inputs": [0, 8], "output": 51}
  ],
  "dffs": []
}
```

### CLI Export

```bash
# Export all supported components to JSON netlists
rhdl gates --export

# Export specific CPU components
rhdl gates --simcpu

# Show synthesis statistics
rhdl gates --stats

# Clean generated files
rhdl gates --clean
```

### Rake Tasks

```bash
# Export gate-level netlists
rake cli:gates:export

# Show statistics
rake cli:gates:stats

# Run gate-level benchmark
rake dev:bench:gates
```

## Lowering Algorithms

### Arithmetic Lowering

**Ripple Carry Adder:**
```
For each bit i from 0 to width-1:
  sum[i] = a[i] XOR b[i] XOR carry[i]
  carry[i+1] = (a[i] AND b[i]) OR (carry[i] AND (a[i] XOR b[i]))

Overflow = (a[MSB] == b[MSB]) AND (sum[MSB] != a[MSB])
```

**Array Multiplier:**
```
For each bit i of multiplier:
  partial_product[i] = multiplicand AND multiplier[i]

Sum all partial products using ripple adders:
  result = PP[0] + (PP[1] << 1) + (PP[2] << 2) + ...
```

**Restoring Divider:**
```
remainder = dividend
quotient = 0
For each bit i from MSB to 0:
  remainder = remainder - (divisor << i)
  if remainder >= 0:
    quotient[i] = 1
  else:
    remainder = remainder + (divisor << i)  # Restore
    quotient[i] = 0
```

### Multiplexer Lowering

**2-to-1 MUX** (primitive):
```
output = (sel AND when_true) OR (NOT sel AND when_false)
```

**4-to-1 MUX** (two-level tree):
```
mux_01 = MUX(sel[0], in[0], in[1])
mux_23 = MUX(sel[0], in[2], in[3])
output = MUX(sel[1], mux_01, mux_23)
```

**8-to-1 MUX** (three-level tree):
```
Similar pattern with 3 select bits
```

### Decoder Lowering

**2-to-4 Decoder:**
```
out[0] = NOT a[1] AND NOT a[0]
out[1] = NOT a[1] AND a[0]
out[2] = a[1] AND NOT a[0]
out[3] = a[1] AND a[0]
```

## Simulation Backends

### CPU Interpreter (`sim_cpu.rb`)

The CPU interpreter evaluates gates in topologically sorted order:

```ruby
# Get simulation backend
sim = RHDL::Codegen.gate_level([component], backend: :interpreter)

# Set inputs
sim.poke('a', 0x42)
sim.poke('b', 0x13)

# Evaluate
sim.evaluate

# Read outputs
result = sim.peek('result')
```

**Algorithm:**
1. Topologically sort gates by dependencies
2. For each gate in sorted order:
   - Read input net values
   - Compute gate output
   - Write to output net
3. For DFFs on clock edge:
   - Sample D inputs
   - Update Q outputs

### GPU Simulator (`sim_gpu.rb`)

The GPU simulator uses SIMD-style parallel evaluation with 64 test vectors simultaneously:

```ruby
sim = RHDL::Codegen.gate_level([component], backend: :gpu, lanes: 64)

# Set inputs (bitmask across all lanes)
sim.poke('a', 0xFFFFFFFFFFFFFFFF)  # All 1s in all 64 lanes

# Evaluate all lanes in parallel
sim.evaluate

# Read outputs (bitmask)
result = sim.peek('result')
```

**SIMD Operations:**
- Each net is represented as a 64-bit integer
- Bit i of the integer = value in lane i
- AND/OR/XOR/NOT operate on full 64-bit words
- MUX: `(~sel & false_val) | (sel & true_val)`

### Native Rust Backend

For maximum performance, compile to native code:

```bash
# Build native extensions
rake native:build

# Use native interpreter
sim = RHDL::Codegen.gate_level([component], backend: :native_interpreter)

# Use JIT-compiled simulation
sim = RHDL::Codegen.gate_level([component], backend: :jit)
```

## Topological Sort

Gates must be evaluated in dependency order. The `toposort.rb` module implements Kahn's algorithm:

```ruby
schedule = RHDL::Codegen::Structure::Toposort.sort(ir)
# Returns array of gate indices in evaluation order
```

**Algorithm:**
1. Build dependency graph from gate inputs/outputs
2. Find gates with no dependencies (inputs come from component inputs)
3. Add to schedule, remove from graph
4. Repeat until all gates scheduled
5. Detect cycles (indicates combinational loop error)

## Gate Count Examples

Typical gate counts for common components:

| Component | Width | Gates | DFFs | Nets |
|-----------|-------|-------|------|------|
| AndGate | 1 | 1 | 0 | 3 |
| RippleCarryAdder | 8 | 48 | 0 | 67 |
| Register | 8 | 0 | 8 | 24 |
| Counter | 8 | ~60 | 8 | ~80 |
| ALU | 8 | ~400 | 0 | ~500 |
| Multiplier | 8 | ~800 | 0 | ~1000 |
| SynthDatapath | - | ~505 | 24 | ~600 |

## Verification Flow

Use gate-level simulation to verify against behavioral simulation:

```ruby
# Behavioral simulation
component = RHDL::HDL::ALU.new('alu', width: 8)
component.set_input(:a, 10)
component.set_input(:b, 5)
component.set_input(:op, 0)  # ADD
component.propagate
expected = component.get_output(:result)

# Gate-level simulation
ir = RHDL::Codegen::Structure::Lower.from_components([component])
sim = RHDL::Codegen.gate_level([component], backend: :interpreter)
sim.poke('a', 10)
sim.poke('b', 5)
sim.poke('op', 0)
sim.evaluate
actual = sim.peek('result')

# Verify
raise "Mismatch!" unless expected == actual
```

## Iverilog Integration

When Icarus Verilog is installed, the test suite includes gate-level equivalence tests:

```ruby
# In spec files (conditional execution)
if HdlToolchain.iverilog_available?
  it "matches behavioral simulation" do
    # Generate gate-level Verilog
    # Create testbench with test vectors
    # Compile with iverilog
    # Run and compare outputs
  end
end
```

To install Iverilog:
```bash
# Ubuntu/Debian
apt-get install iverilog

# macOS
brew install icarus-verilog
```

## Limitations

1. **Memories**: RAM/ROM not yet supported at gate level (use behavioral)
2. **Asynchronous Logic**: Only synchronous designs with single clock domain
3. **Tristate**: Tristate buffers lower to simple gates (not true high-Z)
4. **Large Designs**: Gate counts grow quadratically for multipliers/dividers
5. **Timing**: No propagation delay modeling (functional only)

## File Locations

```
lib/rhdl/codegen/structure/
├── ir.rb           # Gate-level IR data structures
├── lower.rb        # HDL to gate-level lowering (~80 components)
├── primitives.rb   # Gate primitive definitions
├── toposort.rb     # Topological sorting
├── sim_cpu.rb      # CPU-based interpreter
└── sim_gpu.rb      # SIMD-style GPU simulator

export/gates/       # Generated JSON netlists
├── arithmetic/     # ALU, adders, multiplier, divider
├── combinational/  # Mux, demux, decoders, encoders
├── sequential/     # Registers, counters, flip-flops
├── gates/          # Logic gate primitives
└── cpu/            # CPU components
```

## See Also

- [Export Guide](export.md) - Verilog and gate-level export overview
- [Components Reference](components.md) - Full component library
- [Diagrams](diagrams.md) - Gate-level diagram generation
