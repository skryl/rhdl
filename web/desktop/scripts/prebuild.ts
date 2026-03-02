/**
 * Electrobun prebuild script for RHDL Desktop.
 *
 * Syncs the bundled web simulator from web/dist/ into src/simulator/
 * so that Electrobun's build.copy can package them into the
 * views://simulator/ namespace.
 *
 * Expects `bun run build` to have been run in web/ first (the Bun
 * bundler produces dist/index.html + dist/main.*.js + dist/assets/).
 *
 * Run automatically by Electrobun via the `scripts.preBuild` config hook.
 */

import { existsSync, mkdirSync, cpSync, rmSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";

const desktopDir = dirname(dirname(new URL(import.meta.url).pathname));
const webDir = resolve(desktopDir, "..");
const distDir = resolve(webDir, "dist");
const destDir = resolve(desktopDir, "src", "simulator");

if (!existsSync(distDir)) {
  console.error("[prebuild] ERROR: web/dist/ not found. Run `bun run build` in web/ first.");
  process.exit(1);
}

console.log("[prebuild] Syncing bundled web simulator into src/simulator/");
console.log(`[prebuild]   from: ${distDir}`);
console.log(`[prebuild]   to:   ${destDir}`);

// Clean destination
if (existsSync(destDir)) {
  rmSync(destDir, { recursive: true, force: true });
}
mkdirSync(destDir, { recursive: true });

// Copy entire dist/ contents into src/simulator/
cpSync(distDir, destDir, { recursive: true });

const items = readdirSync(destDir);
console.log(`[prebuild] Synced ${items.length} items: ${items.join(", ")}`);
console.log("[prebuild] Done.");
