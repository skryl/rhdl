# Electrobun Build Pipeline for RHDL Web Simulator

## Status
Completed (2026-02-28)

## Context
The RHDL web simulator is currently a browser-only application served via WEBrick or
static hosting (GitHub Pages). Users must open a browser, navigate to the URL, and rely
on a COI service worker for `SharedArrayBuffer` support (needed by WASM backends).

Electrobun is a cross-platform desktop application framework that uses the system's
native WebView, Bun as the backend runtime, and native Zig bindings. It produces ~14MB
bundles with <50ms startup and supports differential updates (~14KB patches).

Wrapping the web simulator in Electrobun provides:
- Native desktop app experience with proper COOP/COEP headers (no service worker hack)
- Offline operation
- System-level menus and keyboard shortcuts
- Future path to native file dialogs, system tray, etc.

## Goals
1. Add an Electrobun project under `web/desktop/` that wraps the existing web simulator.
2. Integrate with the existing `web:build` / `web:generate` pipeline via rake tasks.
3. Serve the web simulator's static files through Electrobun's `views://` protocol.
4. Provide `desktop:dev` and `desktop:build` rake tasks.
5. Set appropriate headers (COOP/COEP) for SharedArrayBuffer/WASM support.

## Non-Goals
- Modifying the existing web simulator code or module structure.
- Adding native features beyond window management (file dialogs, tray, etc. are future work).
- Cross-compilation (Electrobun builds for the current host platform only).
- Auto-update infrastructure (future work).

## Phased Plan

### Phase 1: Electrobun Project Scaffold
Create the project structure under `web/desktop/`:

```
web/desktop/
├── src/
│   ├── bun/
│   │   └── index.ts           # Main process: window creation
│   └── simulator/             # Populated by prebuild script (gitignored)
├── scripts/
│   └── prebuild.ts            # Syncs web/ files into src/simulator/
├── electrobun.config.ts       # Build configuration
├── package.json               # Dependencies and scripts
├── tsconfig.json              # TypeScript configuration
└── .gitignore                 # Build artifacts + synced files
```

**Exit criteria:** Files exist and are syntactically valid.

### Phase 2: Build Pipeline Integration
Add rake tasks that:
1. Run `bun install` in `web/desktop/`.
2. Copy/symlink web simulator assets into the Electrobun build.
3. Build the desktop app via `electrobun build`.

**Exit criteria:** `bundle exec rake desktop:dev` launches the app (or errors
clearly if Bun/Electrobun is not installed).

### Phase 3: Documentation
Update CLAUDE.md with the new rake tasks and desktop directory.

**Exit criteria:** CLAUDE.md reflects the new tasks.

## Acceptance Criteria
1. `web/desktop/` contains a complete Electrobun project scaffold.
2. `bundle exec rake desktop:dev` builds and launches the desktop app.
3. `bundle exec rake desktop:build` creates a distributable bundle.
4. The desktop app loads the web simulator with full WASM support.
5. CLAUDE.md documents the new tasks.

## Risks and Mitigations
| Risk | Mitigation |
|------|-----------|
| Bun/Electrobun not installed on dev machine | Rake tasks check prerequisites and print clear install instructions |
| Web simulator relies on CDN for some deps | Electrobun's webview has internet access; offline mode is a future concern |
| WASM COOP/COEP headers | Electrobun's native webview can set headers directly; also configurable in BrowserWindow |
| Large WASM assets in build | Use `build.copy` to reference existing `web/assets/` rather than duplicating |

## Implementation Checklist
- [x] Phase 1: Electrobun project scaffold
  - [x] `web/desktop/package.json`
  - [x] `web/desktop/tsconfig.json`
  - [x] `web/desktop/electrobun.config.ts`
  - [x] `web/desktop/src/bun/index.ts`
  - [x] `web/desktop/scripts/prebuild.ts` (syncs web app files)
  - [x] `web/desktop/.gitignore`
- [x] Phase 2: Build pipeline integration
  - [x] `desktop:install` rake task
  - [x] `desktop:dev` rake task
  - [x] `desktop:build` rake task
  - [x] `desktop:release` rake task
  - [x] `desktop:clean` rake task
  - [x] Prebuild script for asset syncing
- [x] Phase 3: Documentation
  - [x] Update CLAUDE.md
