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
import { spawnSync } from "node:child_process";

const desktopDir = dirname(dirname(new URL(import.meta.url).pathname));
const webDir = resolve(desktopDir, "..");
const distDir = resolve(webDir, "dist");
const destDir = resolve(desktopDir, "src", "simulator");

const requiredDistPaths = [
  "index.html",
  "coi-serviceworker.js",
  "assets",
  "assets/pkg/ir_interpreter.wasm",
  "assets/pkg/ir_compiler.wasm",
  "assets/pkg/ir_compiler_cpu.wasm",
  "assets/pkg/ir_compiler_gameboy.wasm",
  "assets/pkg/ir_compiler_mos6502.wasm",
  "assets/pkg/ir_compiler_riscv.wasm",
  "assets/pkg/mrub*.{js,wasm}",
  "assets/pkg/ir_interpreter.wasm",
  "assets/pkg/vimwasm.js",
  "assets/pkg/vim.js",
  "assets/pkg/vim.wasm",
  "assets/pkg/vim.data",
  "assets/pkg/ghostty-web.js",
  "assets/pkg/ghostty-vt.wasm",
  "assets/pkg/__vite-browser-external-2447137e.js",
  "assets/fixtures/apple2/ir/apple2.json",
  "assets/fixtures/cpu/ir/cpu_lib_hdl.json",
  "assets/fixtures/mos6502/ir/mos6502.json",
  "assets/fixtures/gameboy/ir/gameboy.json",
  "assets/fixtures/riscv/ir/riscv.json",
  "assets/fixtures/riscv/software/bin/linux_bootstrap.bin",
];

const hasRequiredDist = (): boolean => {
  for (const relativePath of requiredDistPaths) {
    if (relativePath.includes("*")) {
      const fileDir = resolve(distDir, "assets", "pkg");
      if (!existsSync(fileDir)) {
        return false;
      }
      const files = readdirSync(fileDir, { withFileTypes: true }).filter(
        (entry) => entry.isFile() && entry.name.startsWith("mruby."),
      );
      if (files.length === 0) {
        return false;
      }
      continue;
    }

    if (!existsSync(resolve(distDir, relativePath))) {
      return false;
    }
  }

  const bundleFiles = readdirSync(distDir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name);
  const hasBundle = bundleFiles.some((name) => /^main\.[\w-]+\.(js|mjs)$/.test(name));
  return hasBundle;
};

if (!existsSync(distDir) || !hasRequiredDist()) {
  console.warn("[prebuild] web/dist/ not found. Running `bun run build` in web/ ...");
  const bunBinary = process.argv[0] || "bun";
  const buildResult = spawnSync(bunBinary, ["run", "build"], {
    cwd: webDir,
    stdio: "inherit",
  });

  if (buildResult.status !== 0 || !existsSync(distDir) || !hasRequiredDist()) {
    console.error("[prebuild] ERROR: web/dist/ still missing after `bun run build`.");
    console.error("[prebuild] Please run `bun run build` in web/ first and retry.");
    process.exit(1);
  }
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
