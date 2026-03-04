# Repository Hygiene

## Hygiene Checks

Run:

```bash
rhdl hygiene
# or
bundle exec rake hygiene:check
```

The hygiene task validates:

1. `.gitmodules` and gitlink parity.
2. `.gitignore` coverage for current simulator native paths.
3. No tracked ephemeral probe/test-run files.
4. Shared-asset symlink policy for duplicated Apple2/MOS6502 software assets.

## Shared Asset Policy (Apple2/MOS6502)

For known identical software artifacts, Apple2 files are canonical and MOS6502
paths should be symlinks to those canonical files.

Configured mapping lives in:

- `config/hygiene_allowlist.yml` under `shared_symlinks`.

## Intentional Duplicates

Some duplicate content is intentional and allowlisted:

1. Diagram outputs under `diagrams/component/**` and `diagrams/hierarchical/**`.
2. Generated web config module pairs (`*.ts` and `*.mjs`).
