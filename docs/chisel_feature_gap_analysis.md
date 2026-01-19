# Chisel HDL Feature Gap Analysis for RHDL

This document analyzes Chisel HDL features that RHDL currently lacks, providing a roadmap for potential enhancements.

## Executive Summary

Chisel is a hardware construction language embedded in Scala that provides advanced features for parameterized hardware generation. While RHDL shares many concepts with Chisel (both are HDL DSLs embedded in general-purpose programming languages), Chisel has several sophisticated features developed over 10+ years of use in production SoCs like RISC-V Rocket Chip.

**Priority Legend:**
- **P0**: Critical - fundamental language features
- **P1**: High - significantly improves productivity
- **P2**: Medium - nice-to-have for advanced designs
- **P3**: Low - specialized use cases

---

## 1. Type System Enhancements

### 1.1 Aggregate Types: Bundle (P0)

**Chisel Feature:**
```scala
class MyBundle extends Bundle {
  val addr = UInt(32.W)
  val data = UInt(64.W)
  val valid = Bool()
}
val io = IO(new MyBundle)
io.addr := 0x1000.U
```

Bundles group named fields into structured types, similar to Verilog structs or C structs.

**RHDL Status:** Missing. RHDL has no equivalent to Bundle. Ports are defined individually.

**Gap:** Cannot group related signals into reusable interface types.

**Recommendation:** Add a `bundle` DSL:
```ruby
bundle :AxiLite do
  field :awaddr, width: 32
  field :awvalid, width: 1
  field :awready, width: 1
  field :wdata, width: 32
end

input :axi, type: :AxiLite
```

---

### 1.2 Aggregate Types: Vec (P0)

**Chisel Feature:**
```scala
val myVec = Vec(4, UInt(8.W))        // 4-element array of 8-bit values
val regFile = Reg(Vec(32, UInt(64.W))) // Register file
myVec(idx) := value                    // Hardware indexing
```

Vec creates arrays of hardware elements with hardware-indexed access.

**RHDL Status:** Partial. RHDL supports `RegisterFile` component but lacks general-purpose Vec type for wires/ports.

**Gap:** Cannot create parameterized arrays of signals or bundle ports.

**Recommendation:** Add `vec` type:
```ruby
input :data_in, width: 8, count: 4  # Vec(4, UInt(8.W))
wire :pipeline_stages, width: 32, count: 5
```

---

### 1.3 MixedVec (P2)

**Chisel Feature:**
```scala
val mixedVec = MixedVec(Seq(UInt(8.W), UInt(16.W), UInt(32.W)))
```

Arrays where elements can have different widths/types.

**RHDL Status:** Missing.

**Gap:** Cannot create heterogeneous collections.

---

### 1.4 Flipped (P1)

**Chisel Feature:**
```scala
class ProducerIO extends Bundle {
  val data = Output(UInt(8.W))
  val valid = Output(Bool())
  val ready = Input(Bool())
}

class ConsumerIO extends Bundle {
  val port = Flipped(new ProducerIO) // All directions reversed
}
```

`Flipped()` recursively reverses all signal directions in a Bundle.

**RHDL Status:** Missing.

**Gap:** Must manually define mirrored interfaces for bidirectional protocols.

**Recommendation:** Add `flipped` modifier for bundle definitions.

---

### 1.5 Signed Types (SInt) (P1)

**Chisel Feature:**
```scala
val signed = SInt(8.W)
val unsigned = UInt(8.W)
val result = signed + unsigned  // Proper signed arithmetic
```

First-class signed integer type with proper arithmetic semantics.

**RHDL Status:** Partial. RHDL has `SignExtend` component but no native signed type.

**Gap:** No distinction between signed/unsigned at the type level; manual sign handling required.

**Recommendation:** Add `signed: true` option to ports/wires:
```ruby
input :a, width: 8, signed: true
output :result, width: 9, signed: true
```

---

## 2. Control Flow Constructs

### 2.1 when/elsewhen/otherwise (P0)

**Chisel Feature:**
```scala
when(condition1) {
  output := value1
} .elsewhen(condition2) {
  output := value2
} .otherwise {
  output := value3
}
```

Chisel's conditional assignment with proper chaining.

**RHDL Status:** Partial. RHDL has `if_else`, `case_select`, `case_of`, and `if_chain` in behavior blocks.

**Gap:** Syntax is more verbose; `if_chain` is closest equivalent.

**Current RHDL:**
```ruby
behavior do
  if_chain do |i|
    i.when_cond(condition1) { output <= value1 }
    i.when_cond(condition2) { output <= value2 }
    i.else_do { output <= value3 }
  end
end
```

**Recommendation:** Consider adding `when`/`otherwise` syntax sugar.

---

### 2.2 switch/is (P1)

**Chisel Feature:**
```scala
switch(opcode) {
  is(OP_ADD) { result := a + b }
  is(OP_SUB) { result := a - b }
  is(OP_AND, OP_OR) { result := ... } // Multiple values
}
```

Pattern matching on hardware values.

**RHDL Status:** Has `case_select` and `case_of` but less ergonomic.

**Gap:** `case_select` requires hash syntax; `case_of` doesn't support multiple values per case.

---

## 3. Sequential Logic

### 3.1 RegNext / RegInit / RegEnable (P1)

**Chisel Feature:**
```scala
val reg = RegInit(0.U(8.W))           // Register with reset value
val delayed = RegNext(signal)          // Delay by one cycle
val gated = RegEnable(data, enable)    // Conditional update
```

Concise register primitives with different initialization/enable semantics.

**RHDL Status:** Has `Register` component, but more verbose for simple use cases.

**Gap:** No single-line register declarations; must instantiate Register component.

**Recommendation:** Add inline register syntax:
```ruby
wire :delayed, reg_next: :signal
wire :counter, reg_init: 0, width: 8
wire :gated, reg_enable: [:data, :enable]
```

---

### 3.2 ShiftRegister Utility (P2)

**Chisel Feature:**
```scala
val delayed = ShiftRegister(signal, n)          // n-cycle delay
val delayedWithReset = ShiftRegister(signal, n, init, enable)
```

Built-in utility for multi-cycle delays.

**RHDL Status:** Has `ShiftRegister` component.

**Gap:** None - functionally equivalent.

---

### 3.3 Asynchronous vs Synchronous Reset (P1)

**Chisel Feature:**
```scala
val asyncReg = withReset(asyncReset) { RegInit(0.U) } // AsyncReset type
val syncReg = withReset(syncReset) { RegInit(0.U) }   // Bool type

class MyModule extends Module with RequireAsyncReset { ... }
```

Explicit control over reset type with type-safe reset signals.

**RHDL Status:** Partial. Sequential DSL supports `reset_values` but no explicit async/sync distinction.

**Gap:** No type-level distinction; reset behavior is implicit.

**Recommendation:** Add reset type specifier:
```ruby
sequential clock: :clk, reset: :rst, reset_type: :async do
  ...
end
```

---

### 3.4 Multiple Clock Domains (P1)

**Chisel Feature:**
```scala
withClockAndReset(clock2, reset2) {
  val reg = RegInit(0.U)
}
```

Explicit clock domain crossing with scoped blocks.

**RHDL Status:** Partial. Clock can be specified per-component, but no scoped clock domain syntax.

**Gap:** No `withClock` style scoping.

**Recommendation:** Add clock domain scoping:
```ruby
with_clock :clk2 do
  instance :reg, Register, ...
end
```

---

## 4. Memories

### 4.1 Mem / SyncReadMem (P1)

**Chisel Feature:**
```scala
val mem = Mem(1024, UInt(32.W))          // Async read
val syncMem = SyncReadMem(1024, UInt(32.W)) // Sync read (BRAM inference)

mem.read(addr)
mem.write(addr, data)
```

Explicit async vs sync read memory types for proper BRAM/distributed RAM inference.

**RHDL Status:** Has `RAM` (sync write, async read) and `ROM` components.

**Gap:** No explicit `SyncReadMem` for synchronous-read memories (critical for FPGA BRAM inference).

**Recommendation:** Add `SyncRAM` or `sync_read: true` option:
```ruby
memory :bram, depth: 1024, width: 32, sync_read: true
```

---

### 4.2 Memory Masking (P2)

**Chisel Feature:**
```scala
val mem = SyncReadMem(1024, Vec(4, UInt(8.W)))
mem.write(addr, data, mask) // Byte-level write enable
```

Per-element write masking for sub-word writes.

**RHDL Status:** Missing.

**Gap:** Cannot do byte-enable writes to wider memories.

---

## 5. Parameterization & Generators

### 5.1 Scala-Level Generators (P0)

**Chisel Feature:**
```scala
class ParamModule[T <: Data](gen: T, n: Int) extends Module {
  val io = IO(new Bundle {
    val inputs = Input(Vec(n, gen))
    val output = Output(gen)
  })
}

// Usage
new ParamModule(UInt(8.W), 4)
new ParamModule(new MyBundle, 8)
```

Full Scala generics with type parameters.

**RHDL Status:** Has `parameter` DSL but no type parameters.

**Gap:** Cannot parameterize by data type, only by numeric values.

**Recommendation:** Ruby's duck typing makes this less critical, but could support:
```ruby
class ParamModule < SimComponent
  parameter :gen_type  # Pass class as parameter
  parameter :n, default: 4
end
```

---

### 5.2 Functional Collection Operations (P1)

**Chisel Feature:**
```scala
val inputs = Seq.fill(n)(IO(Input(UInt(8.W))))
val sum = inputs.reduce(_ + _)
val mapped = inputs.map(_ + 1.U)
val zipped = (a zip b).map { case (x, y) => x + y }
```

Full Scala collection operations for hardware generation.

**RHDL Status:** Partial. Ruby has `map`, `reduce`, etc., but not integrated into DSL.

**Gap:** Collection operations must be done at Ruby level, not in behavior blocks.

**Recommendation:** Already available via Ruby - just needs documentation of patterns:
```ruby
inputs = (0...n).map { |i| input :"in_#{i}", width: 8 }
```

---

### 5.3 Elaboration-Time vs Hardware-Time (P1)

**Chisel Feature:**
Chisel clearly distinguishes:
- Scala code: runs at elaboration time (circuit generation)
- Chisel hardware: describes circuit behavior

```scala
// Elaboration time (generates n adders)
for (i <- 0 until n) {
  regs(i) := regs(i) + i.U
}
```

**RHDL Status:** Similar model via Ruby, but less explicit.

**Gap:** Could benefit from clearer documentation/patterns.

---

## 6. Standard Library

### 6.1 DecoupledIO / Ready-Valid Interface (P1)

**Chisel Feature:**
```scala
val producer = IO(Decoupled(UInt(8.W)))      // valid, ready, bits
val consumer = IO(Flipped(Decoupled(UInt(8.W))))

producer.valid := true.B
producer.bits := data
when(producer.fire) { ... } // valid && ready
```

Standard ready-valid handshake interface with helper methods.

**RHDL Status:** Missing.

**Gap:** No standard handshaking interface; must define manually.

**Recommendation:** Add standard interfaces:
```ruby
bundle :Decoupled, width: 8 do
  field :valid, width: 1, direction: :output
  field :ready, width: 1, direction: :input
  field :bits, width: :width, direction: :output
end
```

---

### 6.2 Queue (FIFO with Backpressure) (P1)

**Chisel Feature:**
```scala
val queue = Queue(producer, entries = 4)
consumer <> queue
```

One-line FIFO with Decoupled interfaces.

**RHDL Status:** Has `FIFO` component but not integrated with standard interfaces.

**Gap:** FIFO exists but not connected to standard ready-valid protocol.

---

### 6.3 Arbiter / RRArbiter (P1)

**Chisel Feature:**
```scala
val arb = Module(new Arbiter(UInt(8.W), n))
val rrArb = Module(new RRArbiter(UInt(8.W), n))
arb.io.in <> producers
consumer <> arb.io.out
```

Priority and round-robin arbiters for N-to-1 multiplexing with backpressure.

**RHDL Status:** Missing.

**Gap:** No built-in arbitration components.

**Recommendation:** Add `Arbiter` and `RRArbiter` components.

---

### 6.4 Counter Utility (P2)

**Chisel Feature:**
```scala
val (count, wrap) = Counter(enable, n)
val (count2, _) = Counter(0 until 10 by 2)  // Custom range
```

Utility returning counter value and wrap signal.

**RHDL Status:** Has `Counter` component.

**Gap:** Less ergonomic - doesn't return tuple with wrap signal.

---

### 6.5 PopCount / PriorityEncoder / OHToUInt (P2)

**Chisel Feature:**
```scala
val count = PopCount(bits)           // Count 1s
val idx = PriorityEncoder(oneHot)    // First 1 position
val binary = OHToUInt(oneHot)        // One-hot to binary
```

Combinational utilities.

**RHDL Status:** Has `PopCount`, `Encoder`, but lacks `PriorityEncoder`, `OHToUInt`.

**Gap:** Missing some encoder variants.

---

## 7. Connections & Bulk Operations

### 7.1 Bulk Connect (<>) (P1)

**Chisel Feature:**
```scala
producer.io <> consumer.io  // Connect all matching fields
```

Automatically connects fields with matching names.

**RHDL Status:** Missing.

**Gap:** Must connect each signal individually.

**Recommendation:** Add bulk connect operator:
```ruby
connect producer, consumer  # Match by name
```

---

### 7.2 := vs :>= vs :<= Operators (P2)

**Chisel Feature:**
```scala
a := b    // Mono-directional, all bits
a :<= b   // Consumer := producer (respects direction)
a :>= b   // Producer := consumer (respects direction)
a :#= b   // Coercion (force connection)
```

Direction-aware connection operators.

**RHDL Status:** Uses `port` DSL for connections.

**Gap:** No direction-aware connection operators.

---

### 7.3 DontCare (P1)

**Chisel Feature:**
```scala
io.output := DontCare  // Intentionally undriven
```

Explicitly marks signals as intentionally unconnected.

**RHDL Status:** Missing.

**Gap:** No way to mark intentionally undriven signals; may cause warnings.

**Recommendation:** Add `dont_care` value:
```ruby
output <= DONT_CARE
```

---

### 7.4 dontTouch (P2)

**Chisel Feature:**
```scala
dontTouch(signal)  // Prevent optimization removal
```

Prevents dead code elimination for debugging.

**RHDL Status:** Missing.

**Gap:** No way to preserve signals through synthesis.

---

## 8. Verification & Debug

### 8.1 ChiselTest Framework (P1)

**Chisel Feature:**
```scala
test(new MyModule) { dut =>
  dut.io.a.poke(5.U)
  dut.io.b.poke(3.U)
  dut.clock.step()
  dut.io.out.expect(8.U)
}
```

Integrated test framework with poke/peek/expect/step.

**RHDL Status:** Uses RSpec with manual `set_input`/`get_output`.

**Gap:** Less integrated; requires more boilerplate.

**Current RHDL:**
```ruby
component.set_input(:a, 5)
component.set_input(:b, 3)
component.propagate
expect(component.get_output(:out)).to eq(8)
```

**Recommendation:** Add test DSL:
```ruby
test(MyModule) do |dut|
  dut.poke(:a, 5)
  dut.poke(:b, 3)
  dut.step
  dut.expect(:out, 8)
end
```

---

### 8.2 Printf Debugging (P1)

**Chisel Feature:**
```scala
printf(cf"counter = $counter%d, state = $state%x\n")
printf(p"Debug: $myBundle\n")  // Pretty print
```

Simulation-time printf with format specifiers.

**RHDL Status:** Missing at HDL level (Ruby `puts` at elaboration time only).

**Gap:** No simulation-time debug printing in synthesized circuits.

**Recommendation:** Add printf support:
```ruby
behavior do
  hdl_printf "counter = %d, state = %x", counter, state
end
```

---

### 8.3 Formal Verification (P2)

**Chisel Feature:**
```scala
verify(new MyModule, Seq(BoundedCheck(10)))
assert(condition)
assume(precondition)
cover(reachability)
```

Formal verification with bounded model checking.

**RHDL Status:** Missing.

**Gap:** No formal verification integration.

---

### 8.4 Temporal Assertions (P2)

**Chisel Feature:**
```scala
// SVA-like assertions
AssertProperty(valid |-> ##[1:3] ack)
```

Multi-cycle property assertions.

**RHDL Status:** Missing.

**Gap:** No temporal property specification.

---

## 9. BlackBox / External Module Integration

### 9.1 BlackBox (P1)

**Chisel Feature:**
```scala
class MyBlackBox extends BlackBox with HasBlackBoxResource {
  val io = IO(new Bundle {
    val in = Input(UInt(8.W))
    val out = Output(UInt(8.W))
  })
  addResource("/vsrc/mymodule.v")
}
```

Integrate external Verilog modules.

**RHDL Status:** Missing.

**Gap:** Cannot instantiate external Verilog modules.

**Recommendation:** Add blackbox support:
```ruby
class MyBlackBox < BlackBox
  verilog_resource "vsrc/mymodule.v"

  input :in, width: 8
  output :out, width: 8
end
```

---

### 9.2 ExtModule with Parameters (P2)

**Chisel Feature:**
```scala
class IBUFDS extends ExtModule(Map(
  "DIFF_TERM" -> "TRUE",
  "IOSTANDARD" -> "DEFAULT"
)) {
  val O = IO(Output(Bool()))
  val I = IO(Input(Bool()))
  val IB = IO(Input(Bool()))
}
```

Pass Verilog parameters to external modules.

**RHDL Status:** Missing.

**Gap:** Cannot parameterize external modules.

---

## 10. Advanced Features

### 10.1 Layers (Optional Debug) (P2)

**Chisel Feature:**
```scala
object Debug extends layer.Layer(layer.Convention.Bind)

layer.block(Debug) {
  printf("Debug: %d\n", signal)
  assert(valid)
}
```

Conditionally included debug/verification code.

**RHDL Status:** Missing.

**Gap:** No optional layer system for debug code.

---

### 10.2 Annotations (P2)

**Chisel Feature:**
```scala
annotate(new ChiselAnnotation {
  def toFirrtl = DoNotOptimizeAnnotation(signal.toTarget)
})
```

Metadata system for communicating with FIRRTL transforms.

**RHDL Status:** Missing.

**Gap:** No annotation system for synthesis directives.

---

### 10.3 Diplomacy (SoC Integration) (P3)

**Chisel Feature:**
```scala
class MyPeripheral(implicit p: Parameters) extends LazyModule {
  val node = TLRegisterNode(address = Seq(AddressSet(0x1000, 0xfff)))
  lazy val module = new LazyModuleImp(this) {
    ...
  }
}
```

Two-phase elaboration with parameter negotiation for SoC interconnects.

**RHDL Status:** Missing.

**Gap:** No equivalent SoC integration framework.

**Note:** This is a very advanced feature specific to Rocket Chip ecosystem.

---

### 10.4 ChiselEnum (P1)

**Chisel Feature:**
```scala
object State extends ChiselEnum {
  val idle, running, done = Value
}
val state = RegInit(State.idle)
switch(state) {
  is(State.idle) { ... }
}
```

Type-safe enumerated states.

**RHDL Status:** Uses constants, but not type-safe enums.

**Gap:** No enum type; constants don't form a type.

**Recommendation:** Add enum DSL:
```ruby
enum :State do
  value :idle, 0
  value :running, 1
  value :done, 2
end

wire :state, type: :State
```

---

## 11. FIRRTL / IR Features

### 11.1 Intermediate Representation (P2)

**Chisel Feature:**
Chisel compiles to FIRRTL, which enables:
- Optimization passes
- Multiple backend targets
- Custom transforms

**RHDL Status:** Has gate-level IR for synthesis.

**Gap:** No high-level IR for optimization passes.

---

### 11.2 Custom Transforms (P3)

**Chisel Feature:**
```scala
class MyTransform extends Transform {
  def execute(state: CircuitState): CircuitState = {
    // Modify circuit
  }
}
```

Extensible compilation pipeline.

**RHDL Status:** Missing.

**Gap:** No transform/pass infrastructure.

---

## Priority Summary

### P0 (Critical - Core Language)
1. **Bundle** - Structured interface types
2. **Vec** - Hardware arrays with indexing
3. **when/elsewhen/otherwise** - Ergonomic conditionals (partial - has alternatives)

### P1 (High - Productivity)
4. **Flipped** - Interface direction reversal
5. **SInt** - First-class signed types
6. **DecoupledIO** - Standard ready-valid interface
7. **Arbiter** - N-to-1 arbitration
8. **BlackBox** - External Verilog integration
9. **RegNext/RegInit/RegEnable** - Inline register syntax
10. **Async/Sync Reset** - Explicit reset types
11. **Multiple Clock Domains** - Scoped clock switching
12. **ChiselEnum** - Type-safe enumerations
13. **Bulk Connect** - Automatic signal matching
14. **DontCare** - Intentionally undriven signals
15. **Printf** - Simulation debug printing
16. **Better Test DSL** - Poke/peek/expect pattern

### P2 (Medium - Advanced)
17. **MixedVec** - Heterogeneous arrays
18. **SyncReadMem** - BRAM inference
19. **Memory Masking** - Byte enables
20. **Formal Verification** - Bounded model checking
21. **Temporal Assertions** - Multi-cycle properties
22. **dontTouch** - Prevent optimization
23. **Layers** - Optional debug code
24. **Annotations** - Synthesis metadata
25. **FIRRTL-level IR** - Optimization passes

### P3 (Low - Specialized)
26. **Diplomacy** - SoC interconnect framework
27. **Custom Transforms** - Compilation passes
28. **TileLink** - Cache-coherent protocol

---

## Sources

- [Chisel GitHub Repository](https://github.com/chipsalliance/chisel)
- [Chisel Official Documentation](https://www.chisel-lang.org/)
- [Bundles and Vecs](https://www.chisel-lang.org/docs/explanations/bundles-and-vecs)
- [Chisel Data Types](https://www.chisel-lang.org/docs/explanations/data-types)
- [Chisel Bootcamp](https://github.com/freechipsproject/chisel-bootcamp)
- [Interfaces and Connections](https://www.chisel-lang.org/docs/explanations/interfaces-and-connections)
- [External Modules (BlackBoxes)](https://www.chisel-lang.org/docs/explanations/blackboxes)
- [ChiselTest](https://github.com/ucb-bar/chiseltest)
- [Reset Types](https://www.chisel-lang.org/docs/explanations/reset)
- [Layers](https://www.chisel-lang.org/docs/explanations/layers)
- [Annotations](https://www.chisel-lang.org/docs/explanations/annotations)
- [Diplomacy and TileLink](https://lowrisc.org/docs/diplomacy/)
- [Rocket Chip Generator](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2016/EECS-2016-17.pdf)
- [Printing/Printf](https://www.chisel-lang.org/docs/explanations/printing)
- [General Cookbook](https://www.chisel-lang.org/docs/cookbooks/cookbook)
- [Functional Abstraction](https://www.chisel-lang.org/docs/explanations/functional-abstraction)
