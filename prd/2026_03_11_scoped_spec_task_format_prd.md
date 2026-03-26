## Status

Completed 2026-03-11

## Context

The repository currently supports parameterized scoped test runs via `bundle exec rake "spec[scope]"` and `bundle exec rake "pspec[scope]"`, but it also defines duplicate colon-scoped aliases such as `spec:ao486` and `pspec:apple2`.

Those aliases create two public entry points for the same behavior, keep `rake -T` noisier than necessary, and leave current guidance split between both formats.

## Goals

1. Make `spec[scope]` the only supported scoped sequential test format.
2. Make `pspec[scope]` the only supported scoped parallel test format.
3. Update current repo guidance and interface tests to match the single canonical format.

## Non-Goals

1. Changing `spec`, `pspec`, or `spec:bench[...]` semantics.
2. Rewriting historical PRDs that reference the old alias tasks.
3. Changing the available scope names.

## Phased Plan

### Phase 1: Red

Add or update the rake interface spec so it fails while legacy `spec:<scope>` and `pspec:<scope>` alias tasks still exist.

Exit criteria:
1. The focused interface spec fails specifically because the legacy alias tasks are defined.

### Phase 2: Green

Remove the legacy alias task definitions from the `Rakefile` and update current docs and agent guidance to use only `spec[scope]` and `pspec[scope]`.

Exit criteria:
1. The focused interface spec passes.
2. `bundle exec rake -T` no longer advertises `spec:<scope>` or `pspec:<scope>` alias tasks.
3. Current guidance in `AGENTS.md` uses the parameterized format.

### Phase 3: Refactor

Keep the implementation minimal and leave the shared scope handling unchanged apart from the public task surface cleanup.

Exit criteria:
1. No additional task behavior changes beyond alias removal are introduced.

## Acceptance Criteria

1. `bundle exec rake "spec[ao486]"`, `bundle exec rake "spec[apple2]"`, and other scoped sequential runs remain supported.
2. `bundle exec rake "pspec[ao486]"`, `bundle exec rake "pspec[apple2]"`, and other scoped parallel runs remain supported.
3. `spec:bench[...]` remains available.
4. Current repo docs no longer advertise `spec:<scope>` or `pspec:<scope>` aliases as supported usage.

## Risks And Mitigations

1. Risk: Removing aliases may break internal references.
   Mitigation: Search current non-PRD repo files for colon-scoped usage and update any active references.
2. Risk: The task surface could unintentionally drop supported scopes.
   Mitigation: Keep the existing parameterized `spec` and `pspec` task bodies unchanged and verify via focused interface tests.

## Verification

1. Red: `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb` failed while legacy scoped alias tasks were still defined.
2. Green: `bundle exec rspec spec/rhdl/cli/rakefile_interface_spec.rb` passed after alias removal.
3. Surface check: `bundle exec rake -T` lists `spec[scope]` and `pspec[scope]` without `spec:<scope>` or `pspec:<scope>` aliases.

## Implementation Checklist

- [x] Phase 1 Red: Update the rake interface spec to reject legacy scoped aliases.
- [x] Phase 2 Green: Remove legacy scoped alias tasks from the `Rakefile`.
- [x] Phase 2 Green: Update current docs and agent guidance to the parameterized format.
- [x] Phase 2 Green: Run focused verification for the rake interface and task listing.
- [x] Phase 3 Refactor: Confirm no extra behavior changes were introduced.
