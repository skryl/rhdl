# Test Failure Categorization

**Date:** 2026-01-22
**Total Failures:** 71 (out of 2678 tests)
**Total Pending:** 19

---

## Category 1: Backend API Changes (12 failures)

**Root Cause:** The gate-level simulator backend API was changed. The `:cpu` backend no longer exists; valid backends are now `:interpreter`, `:jit`, `:compiler`.

**Error Message:**
```
ArgumentError: Unknown backend: cpu. Valid: :interpreter, :jit, :compiler
```

**Affected Files:**
- `spec/gate_level_equivalence_spec.rb` (4 tests)
  - Lines: 25, 53, 87, 147
- `spec/rhdl/cli/tasks/benchmark_task_spec.rb` (5 tests)
  - Lines: 47, 52, 60, 67, 77

**Fix:** Update test code to use valid backend names (`:interpreter`, `:jit`, or `:compiler` instead of `:cpu`).

---

## Category 2: Native Rust Extension Not Built (24 failures)

**Root Cause:** The native Rust extension (netlist_interpreter.so) is not built. Tests require the compiled native library.

**Error Message:**
```
LoadError: Netlist interpreter extension not found at:
/home/user/rhdl/lib/rhdl/codegen/netlist/sim/netlist_interpreter/lib/netlist_interpreter.so
Run 'rake native:build' to build it.
```

**Affected Files:**
- `spec/examples/apple2/netlist_runner_spec.rb` (22 tests)
  - Backend initialization tests
  - Basic operations tests
  - Performance characteristics tests
  - Netlist properties tests

**Fix:** Run `rake native:build` to build the Rust extension, or skip these tests when the native extension is unavailable.

---

## Category 3: Apple2 Simulation Timeout (11 failures)

**Root Cause:** Apple2 simulation tests exceed the 10-second test timeout. This could indicate a performance regression or an infinite loop in the simulation code.

**Error Message:**
```
Timeout::Error: Test exceeded 10 second timeout
```

**Affected Files:**
- `spec/examples/apple2/apple2_spec.rb` (11 tests)
  - Clock generation: Lines 80, 92
  - ROM access: Line 198
  - Keyboard interface: Line 233
  - Video generation: Lines 278, 285, 292
  - Debug outputs: Lines 316, 323
  - Boot sequence: Line 157
  - ROM boot: Lines 556, 566

**Fix:** Investigate Apple2 simulation performance; check for infinite loops in propagation logic.

---

## Category 4: Codegen Namespace/Verilog Export (3 failures)

**Root Cause:** The Verilog code generation namespace was reorganized. `RHDL::Codegen::Verilog::Verilog` no longer exists.

**Error Message:**
```
NameError: uninitialized constant RHDL::Codegen::Verilog::Verilog
```

**Affected Files:**
- `spec/rhdl/export_spec.rb` (3 tests)
  - Lines: 49, 132, 140

**Fix:** Update the `Codegen.verilog` method to use the correct class reference after the namespace reorganization.

---

## Category 5: Subtractor Lower Method Signature (4 failures)

**Root Cause:** The `lower_subtractor` method in `lib/rhdl/codegen/netlist/lower.rb` expects 3 arguments (`a_nets`, `b_nets`, `width`) but is being called with only 1 argument.

**Error Message:**
```
ArgumentError: wrong number of arguments (given 1, expected 3)
```

**Affected Files:**
- `spec/rhdl/hdl/arithmetic/subtractor_spec.rb` (4 tests)
  - Lines: 73, 79, 103

**Fix:** Update `dispatch_lower` to call `lower_subtractor` with the correct arguments.

---

## Category 6: Native Task EXTENSIONS Constant Renamed (1 failure)

**Root Cause:** Extension names were changed from `rtl_*` to `ir_*` in the source code, but the test still expects the old names.

**Error Message:**
```
expected [...:ir_interpreter, :ir_jit, :ir_compiler] to include :rtl_interpreter, :rtl_jit, and :rtl_compiler
```

**Affected Files:**
- `spec/rhdl/cli/tasks/native_task_spec.rb` (1 test)
  - Line: 8

**Fix:** Update the test to expect `:ir_interpreter`, `:ir_jit`, `:ir_compiler` instead of `:rtl_*`.

---

## Category 7: Dir.tmpdir Missing Require (2 failures)

**Root Cause:** The `Dir.tmpdir` method is being used without requiring `'tmpdir'` first.

**Error Message:**
```
NoMethodError: undefined method `tmpdir' for class Dir
```

**Affected Files:**
- `spec/rhdl/cli/task_spec.rb` (2 tests)
  - Lines: 100, 108

**Fix:** Add `require 'tmpdir'` to the spec file.

---

## Category 8: DepsTask Timeout (Network Issues) (5 failures)

**Root Cause:** The DepsTask tests actually try to run `sudo apt-get update && sudo apt-get install -y iverilog`, which times out due to network issues in the test environment.

**Error Message:**
```
Timeout::Error: Test exceeded 10 second timeout
```

**Affected Files:**
- `spec/rhdl/cli/tasks/deps_task_spec.rb` (5 tests)
  - Lines: 45, 51, 87, 91, 95

**Fix:** Mock the system calls in tests instead of actually running package installation commands.

---

## Category 9: MOS6502 Memory Gate-Level Test Expectation (1 failure)

**Root Cause:** The test expects `ArgumentError: Unsupported component` to be raised when trying to lower `MOS6502::Memory`, but no error is being raised. The behavior may have changed.

**Error Message:**
```
expected ArgumentError with message matching /Unsupported component/ but nothing was raised
```

**Affected Files:**
- `spec/examples/mos6502/memory_spec.rb` (1 test)
  - Line: 56

**Fix:** Investigate whether behavior memory lowering is now supported, or if the error handling changed. Update test accordingly.

---

## Summary by Priority

| Category | Failures | Priority | Effort |
|----------|----------|----------|--------|
| 1. Backend API Changes | 12 | High | Low |
| 2. Native Extension Missing | 24 | Medium | N/A (build required) |
| 3. Apple2 Timeout | 11 | High | Medium-High |
| 4. Codegen Namespace | 3 | High | Low |
| 5. Subtractor Signature | 4 | High | Low |
| 6. Native Task Constants | 1 | Low | Low |
| 7. Dir.tmpdir Missing | 2 | Low | Low |
| 8. DepsTask Network | 5 | Medium | Low |
| 9. Memory Gate-Level | 1 | Low | Low |

---

## Recommended Fix Order

1. **Category 7** - Add `require 'tmpdir'` (trivial fix)
2. **Category 6** - Update native task spec expectations (trivial fix)
3. **Category 4** - Fix Verilog namespace in codegen.rb
4. **Category 5** - Fix subtractor lowering method call
5. **Category 1** - Update backend API usage in tests
6. **Category 9** - Update memory gate-level test expectation
7. **Category 8** - Mock system calls in deps_task_spec
8. **Category 3** - Debug Apple2 simulation timeout issues
9. **Category 2** - Build native extension or add skip conditions
