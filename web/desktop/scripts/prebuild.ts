/**
 * Electrobun prebuild script for RHDL Desktop.
 *
 * Syncs the web simulator's static files from the parent web/ directory
 * into src/simulator/ so that Electrobun's build.copy can package them
 * into the views://simulator/ namespace.
 *
 * Run automatically by Electrobun via the `scripts.preBuild` config hook.
 */

import { existsSync, mkdirSync, cpSync, rmSync } from "node:fs";
import { resolve, dirname } from "node:path";

const desktopDir = dirname(dirname(new URL(import.meta.url).pathname));
const webDir = resolve(desktopDir, "..");
const destDir = resolve(desktopDir, "src", "simulator");

// Items to sync from web/ into src/simulator/
const syncItems = [
  { src: "index.html", type: "file" as const },
  { src: "coi-serviceworker.js", type: "file" as const },
  { src: "app", type: "dir" as const },
  { src: "assets", type: "dir" as const },
];

console.log("[prebuild] Syncing web simulator files into src/simulator/");
console.log(`[prebuild]   from: ${webDir}`);
console.log(`[prebuild]   to:   ${destDir}`);

for (const item of syncItems) {
  const srcPath = resolve(webDir, item.src);
  const dstPath = resolve(destDir, item.src);

  if (!existsSync(srcPath)) {
    console.warn(`[prebuild] WARNING: source not found, skipping: ${srcPath}`);
    continue;
  }

  // Remove existing destination to ensure a clean sync
  if (existsSync(dstPath)) {
    rmSync(dstPath, { recursive: true, force: true });
  }

  if (item.type === "dir") {
    cpSync(srcPath, dstPath, { recursive: true });
    console.log(`[prebuild]   synced dir:  ${item.src}/`);
  } else {
    mkdirSync(dirname(dstPath), { recursive: true });
    cpSync(srcPath, dstPath);
    console.log(`[prebuild]   synced file: ${item.src}`);
  }
}

console.log("[prebuild] Done.");
