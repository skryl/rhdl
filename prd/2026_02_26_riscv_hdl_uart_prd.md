# RISC-V HDL UART for xv6 Shell E2E PRD

## Status
In Progress (2026-02-26)

## Context
The xv6 shell end-to-end spec now includes HDL backends (`:verilator`, `:arcilator`) through `HeadlessRunner`. Those tests currently time out waiting for shell UART output because HDL runner wrappers do not implement UART RX/TX queueing and treat UART MMIO writes as no-ops.

## Goals
- Make HDL runners support UART RX injection and UART TX capture.
- Enable xv6 shell UART e2e test to run meaningfully on Verilator/Arcilator.
- Keep HDL runner API parity with existing IR/Ruby runner UART methods.

## Non-goals
- Full, cycle-accurate 16550 model beyond xv6 console needs.
- Reworking VirtIO/PLIC beyond existing minimal behavior.
- Optimizing HDL boot performance in this change.

## Phased Plan

### Phase 1: Red
- Keep failing xv6 HDL shell spec as baseline signal.
- Add/confirm focused HDL UART behavior expectations where practical.

Exit criteria:
- A reproducible failing check demonstrates HDL UART path is broken before implementation.

### Phase 2: Green
- Add HDL wrapper FFI endpoints for UART RX enqueue, UART TX copy, UART TX clear.
- Extend shared C++ MMIO model in `Runner` to include minimal UART registers and queues.
- Wire Ruby `Runner` methods (`uart_receive_bytes`, `uart_tx_bytes`, `clear_uart_tx_bytes`) to new FFI endpoints.

Exit criteria:
- UART API returns real data for HDL runners.
- xv6 shell HDL backend test reaches shell output and command echo path.

### Phase 3: Refactor/Validation
- Keep implementation minimal and shared in `Runner` helper code for both wrappers.
- Run targeted specs and confirm no regressions in touched HDL runner specs.

Exit criteria:
- Relevant RSpec targets pass locally or are explicitly skipped with clear reasons.

## Acceptance Criteria
- `spec/examples/riscv/xv6_shell_io_spec.rb` HDL backend case(s) no longer fail due to missing UART plumbing.
- `VerilogRunner` and `ArcilatorRunner` expose functional UART RX/TX behavior through existing public API.
- No regressions in RISC-V HDL runner interface/behavior specs in touched areas.

## Risks and Mitigations
- Risk: Divergence between Verilator and Arcilator wrapper behavior.
  - Mitigation: Keep logic centralized in shared generated C++ snippet from `Runner`.
- Risk: UART register semantics mismatch with xv6 expectations.
  - Mitigation: Mirror existing Ruby UART model behavior for LSR/IIR/IER/RBR/THR path.
- Risk: Performance degradation in batched loop.
  - Mitigation: Use fixed-size ring buffers and O(1) enqueue/dequeue.

## Implementation Checklist
- [x] Phase 1 red baseline captured (xv6 HDL shell timeout observed).
- [ ] Add UART FFI functions to HDL wrapper headers/exports.
- [ ] Implement shared UART MMIO model and buffers in runner-generated C++.
- [ ] Wire Ruby-side UART methods to Fiddle calls.
- [ ] Run targeted HDL runner specs.
- [ ] Run xv6 shell HDL backend slow spec.
- [ ] Mark PRD status completed when all acceptance criteria are met.
