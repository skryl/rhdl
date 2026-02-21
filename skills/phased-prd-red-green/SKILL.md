---
name: phased-prd-red-green
description: Create or update a phased PRD and then execute delivery using a strict red/green workflow. Use when a task spans multiple steps, has cross-cutting impact, needs explicit exit criteria, or requires reliable test-driven implementation sequencing.
---

# Phased PRD + Red/Green Delivery

## Overview

Use this skill to drive a task from planning to completion with explicit phase gates.

Read `references/prd_red_green_template.md` before writing a new PRD.

## Workflow

1. Confirm scope, success target, and constraints.
2. Decide whether to create/update a PRD.
3. Draft or revise the PRD with phased red/green structure.
4. Execute each phase in order: red -> green -> refactor.
5. Track completion in the checklist and update status.

## PRD Authoring Rules

1. Place documents in `prd/`.
2. Use dated file names: `YYYY_MM_DD_<topic>_prd.md`.
3. Include at minimum:
   - Status
   - Context
   - Goals and non-goals
   - Phased plan
   - Exit criteria per phase
   - Acceptance criteria
   - Risks and mitigations
   - Implementation checklist
4. Keep phases independently testable and incremental.

## Red/Green Execution Rules

1. Write failing tests/checks first for each phase.
2. Record the failing signal (error, unsupported op, mismatch, or failing assertion).
3. Implement the smallest possible change set to pass.
4. Re-run targeted tests, then adjacent regression tests.
5. Refactor only after green and keep semantics unchanged.

## Evidence And Reporting

1. Report which commands ran and which did not run.
2. Include key pass/fail outputs for each phase gate.
3. Do not mark a phase complete until exit criteria are verified.
4. Mark PRD as `Completed` only when all checklist items are done.

## Reference

Use `references/prd_red_green_template.md` as the default skeleton and execution checklist.
