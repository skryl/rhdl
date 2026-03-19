# Shared Verilator Threads Option and Benchmark Coverage PRD

Status: Completed (2026-03-19)
Date: 2026-03-19

## Context

RISC-V now has a benchmark-style comparison between the default Verilator build
and a `--threads 4` build, but the thread-count option currently exists as an
ad hoc RISC-V-only keyword (`verilator_threads:`). The user wants the option to
be shared as a generic `threads:` keyword so any backend that supports it can
consume it, with Verilator being the first supported backend. This also needs a
matching SPARC64 benchmark-style comparison so both example stacks exercise the
same threaded-Verilator path.

## Goals

1. Replace the RISC-V-specific `verilator_threads:` keyword with a shared
   `threads:` keyword.
2. Make the shared `threads:` keyword available on Verilator-backed runners
   across the examples that use `VerilogSimulator`.
3. Keep single-threaded behavior unchanged when `threads:` is omitted or set to
   a non-positive value.
4. Preserve side-by-side build isolation for single-threaded and threaded
   Verilator artifacts.
5. Add SPARC64 benchmark coverage that compares default Verilator against
   `threads: 4` on the same workload.

## Non-goals

1. Enforcing a hard performance threshold that would make benchmark specs flaky
   across machines.
2. Changing any CLI or task default to use threaded Verilator automatically.
3. Adding multithreading support to non-Verilator backends in this change.

## Scope

Files in scope are the shared Verilog simulator wrapper, Verilator-backed
example runners and relevant headless wrappers, the RISC-V and SPARC64 specs
covering the threaded path, and this PRD.

## Risks and mitigations

1. Risk: performance assertions are flaky across developer machines.
   Mitigation: keep the spec benchmark-style, print both timings, and assert the
   comparison executed rather than requiring a fixed speedup ratio.
2. Risk: threaded and single-threaded builds overwrite each other's artifacts.
   Mitigation: centralize artifact naming by requested thread count in the
   shared Verilator simulator wrapper.
3. Risk: some Verilator-backed runners expose the new option while others
   silently ignore it.
   Mitigation: update every Verilator runner constructor to accept `threads:`
   and cover the shared logic with simulator-level tests plus headless
   forwarding checks.
4. Risk: environments with missing Verilator or limited CPU parallelism fail the
   new benchmark specs spuriously.
   Mitigation: reuse availability skips and skip the comparison when the host
   cannot reasonably exercise a 4-thread variant.

## Acceptance criteria

1. `threads:` is the only thread-count keyword used by the new threaded
   Verilator coverage.
2. The shared Verilog simulator wrapper isolates Verilator artifacts and injects
   `--threads N` when `threads:` is greater than 1.
3. RISC-V continues to benchmark default Verilator against `threads: 4` using
   the shared keyword.
4. SPARC64 has a similar benchmark-style spec comparing default Verilator
   against `threads: 4` on a common workload.
5. Targeted simulator, RISC-V, and SPARC64 specs pass.

## Phased Plan

### Phase 0

Objective: capture the shared `threads:` contract and SPARC64 coverage as
failing tests.

Red:
- Update the RISC-V benchmark spec to use `threads: 4`.
- Add simulator-level coverage for threaded artifact naming / flag injection.
- Add SPARC64 coverage for headless `threads:` forwarding and a slow benchmark
  comparing default Verilator against `threads: 4`.
- Expected failure signal: missing `threads:` keyword support or missing
  threaded artifact isolation.

Green:
- None in this phase.

Exit criteria:
- The new or updated specs exist and fail for missing shared `threads:` support.

### Phase 1

Objective: centralize shared Verilator `threads:` handling and thread it through
the affected runners.

Red:
- Run the new targeted specs and capture the missing-argument or missing-build
  isolation failure.

Green:
- Add shared `threads:` handling to the Verilog simulator wrapper.
- Update Verilator-backed runners and headless wrappers to accept and forward
  `threads:`.
- Re-run the targeted simulator, RISC-V, and SPARC64 specs.

Exit criteria:
- Shared simulator and forwarding coverage are green, and both benchmark specs
  run to completion.

### Phase 2

Objective: verify adjacent regressions and finalize status.

Red:
- Run the nearby RISC-V and SPARC64 regression slices to catch fallout from the
  shared option rename.

Green:
- Address any regressions from the shared `threads:` plumbing.
- Update the PRD checklist and status with actual verification results.

Exit criteria:
- Targeted regression coverage is green or explicitly documented.

## Implementation checklist

- [x] Phase 0 complete
- [x] Phase 1 complete
- [x] Phase 2 complete
- [x] Integration/regression checks complete
- [x] Documentation/status updated

## Command log

1. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb -e 'benchmarks default Verilator against a --threads 4 build on the same workload'`
   - result: fail
   - notes: red signal was `ArgumentError: unknown keyword: :verilator_threads`
2. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb -e 'benchmarks default Verilator against a --threads 4 build on the same workload'`
   - result: pass
   - notes: threaded `--threads 4` variant built and the comparison benchmark completed in 47.8s wall-clock for the spec run
3. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb`
   - result: pass
   - notes: 11 examples, 0 failures, 1 pending (`creates arcilator-backed runner` pending because the existing arcilator integration timed out after 10 seconds)
4. `bundle exec rspec spec/rhdl/codegen/verilog/sim/verilog_simulator_spec.rb`
   - result: fail
   - notes: red signal was `ArgumentError: unknown keyword: :threads`
5. `bundle exec rspec spec/examples/sparc64/runners/headless_runner_spec.rb -e 'forwards threads to the Verilator runner'`
   - result: fail
   - notes: red signal was `ArgumentError: unknown keyword: :threads`
6. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb -e 'forwards threads to the verilator-backed runner'`
   - result: fail
   - notes: red signal was `ArgumentError: unknown keyword: :threads`
7. `bundle exec rspec spec/rhdl/codegen/verilog/sim/verilog_simulator_spec.rb`
   - result: pass
   - notes: 5 examples, 0 failures
8. `bundle exec rspec spec/examples/sparc64/runners/headless_runner_spec.rb`
   - result: pass
   - notes: 13 examples, 0 failures
9. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb -e 'forwards threads to the verilator-backed runner'`
   - result: pass
   - notes: 1 example, 0 failures
10. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb`
    - result: pass
    - notes: 12 examples, 0 failures
11. `bundle exec rspec spec/examples/riscv/runners/hdl_harness_spec.rb --tag slow -e 'benchmarks default Verilator against a --threads 4 build on the same workload'`
    - result: pass
    - notes: 1 example, 0 failures, 45.6s wall-clock
12. `bundle exec rspec spec/examples/sparc64/runners/verilator_runner_smoke_spec.rb --tag slow`
    - result: fail
    - notes: the existing concrete mailbox smoke program timed out on the current tree before the new threaded comparison was meaningful, so the SPARC64 benchmark coverage was moved to the maintained benchmark-program harness instead of piggybacking on that smoke path
13. `bundle exec rspec spec/examples/sparc64/integration/verilator_benchmark_smoke_spec.rb --tag slow -e 'benchmarks default Verilator against a --threads 4 build on prime_sieve'`
    - result: pass
    - notes: 1 example, 0 failures, 7m11s wall-clock
