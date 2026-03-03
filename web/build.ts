/**
 * Bun build script for the RHDL web simulator.
 *
 * Bundles the app entry point and worker into dist/, copies static assets
 * (WASM, HTML, service worker), and rewrites CDN URLs to local npm imports
 * via a Bun plugin.
 */

import { existsSync, mkdirSync, cpSync, readFileSync, writeFileSync } from "node:fs";
import { resolve, basename } from "node:path";

const isProduction = process.env.NODE_ENV === "production";
const webRoot = import.meta.dir;
const distDir = resolve(webRoot, "dist");

// ---------------------------------------------------------------------------
// Plugin: rewrite CDN ESM URLs to bare npm specifiers so Bun resolves them
// from node_modules.
// ---------------------------------------------------------------------------
const cdnRewritePlugin: import("bun").BunPlugin = {
  name: "cdn-rewrite",
  setup(build) {
    // Rewrite CDN ESM URLs to the local npm package.
    // e.g. https://cdn.jsdelivr.net/npm/lit@3.2.1/+esm -> lit
    //      https://cdn.jsdelivr.net/npm/lit-html@3.2.1/+esm -> lit-html
    build.onResolve({ filter: /^https:\/\/cdn\.jsdelivr\.net\/npm\// }, (args) => {
      const match = args.path.match(/\/npm\/([@\w/-]+?)@[\d.]+/);
      if (match) {
        const resolved = import.meta.resolve(match[1]);
        return { path: resolved.replace(/^file:\/\//, "") };
      }
      return undefined;
    });
  },
};

function copyRuntimeDependencyAssets(distDir: string, webRoot: string) {
  const dependencies = [
    ["vim-wasm/vimwasm.js", "vimwasm.js"],
    ["vim-wasm/vim.js", "vim.js"],
    ["vim-wasm/vim.wasm", "vim.wasm"],
    ["vim-wasm/vim.data", "vim.data"],
    ["ghostty-web/dist/ghostty-web.js", "ghostty-web.js"],
    ["ghostty-web/dist/ghostty-vt.wasm", "ghostty-vt.wasm"],
    ["ghostty-web/dist/__vite-browser-external-2447137e.js", "__vite-browser-external-2447137e.js"],
  ] as const;

  const sourceRoot = resolve(webRoot, "node_modules");
  const targetRoot = resolve(distDir, "assets", "pkg");

  for (const [relativeSource, targetName] of dependencies) {
    const sourcePath = resolve(sourceRoot, relativeSource);
    if (!existsSync(sourcePath)) {
      throw new Error(`[build] Missing dependency asset: ${sourcePath}`);
    }
    const targetPath = resolve(targetRoot, targetName);
    cpSync(sourcePath, targetPath, { force: true });
  }
}

// ---------------------------------------------------------------------------
// Main app bundle
// ---------------------------------------------------------------------------
const result = await Bun.build({
  entrypoints: [resolve(webRoot, "app/main.ts")],
  outdir: distDir,
  target: "browser",
  format: "esm",
  splitting: false,
  sourcemap: "linked",
  minify: isProduction,
  naming: "[name].[hash].js",
  plugins: [cdnRewritePlugin],
  external: [],
  define: {
    "process.env.NODE_ENV": JSON.stringify(isProduction ? "production" : "development"),
  },
});

if (!result.success) {
  console.error("Build failed:");
  for (const log of result.logs) {
    console.error(log);
  }
  process.exit(1);
}

// Find the hashed output filename
const appBundle = result.outputs.find((o) => o.kind === "entry-point");
if (!appBundle) {
  console.error("No entry-point output found");
  process.exit(1);
}
const appBundleName = basename(appBundle.path);

// ---------------------------------------------------------------------------
// Copy static assets into dist/
// ---------------------------------------------------------------------------

// HTML: read index.html, rewrite the module script src to the hashed bundle
let html = readFileSync(resolve(webRoot, "index.html"), "utf-8");

// Replace the module script tag with the hashed bundle
html = html.replace(
  /<script type="module" src="\.\/app\/main\.[^"]*"><\/script>/,
  `<script type="module" src="./${appBundleName}"></script>`,
);

mkdirSync(distDir, { recursive: true });
writeFileSync(resolve(distDir, "index.html"), html);

// COI service worker
if (existsSync(resolve(webRoot, "coi-serviceworker.js"))) {
  cpSync(resolve(webRoot, "coi-serviceworker.js"), resolve(distDir, "coi-serviceworker.js"));
}

// WASM and fixture assets
  if (existsSync(resolve(webRoot, "assets"))) {
  cpSync(resolve(webRoot, "assets"), resolve(distDir, "assets"), { recursive: true });
}

// mirb worker bundle (compiled from TypeScript source into static asset path)
mkdirSync(resolve(distDir, "assets", "pkg"), { recursive: true });
const mirbWorkerResult = await Bun.build({
  entrypoints: [resolve(webRoot, "app/components/terminal/workers/mirb_worker.ts")],
  outdir: resolve(distDir, "assets/pkg"),
  target: "browser",
  format: "esm",
  splitting: false,
  naming: "[name].js",
  minify: isProduction,
  sourcemap: "none"
});

if (!mirbWorkerResult.success) {
  console.error("mirb worker build failed:");
  for (const log of mirbWorkerResult.logs) {
    console.error(log);
  }
  process.exit(1);
}

const schematicWorkerResult = await Bun.build({
  entrypoints: [resolve(webRoot, "app/components/explorer/workers/schematic_render_worker.ts")],
  outdir: resolve(distDir, "assets/pkg"),
  target: "browser",
  format: "esm",
  splitting: false,
  naming: "[name].js",
  minify: isProduction,
  sourcemap: "none"
});

if (!schematicWorkerResult.success) {
  console.error("schematic render worker build failed:");
  for (const log of schematicWorkerResult.logs) {
    console.error(log);
  }
  process.exit(1);
}

try {
  copyRuntimeDependencyAssets(distDir, webRoot);
} catch (err) {
  console.error("Failed to copy dependency runtime assets:");
  console.error(err);
  process.exit(1);
}

// Source map
if (appBundle.sourcemap) {
  // Already written to distDir by Bun.build
}

console.log(`Build complete → dist/`);
console.log(`  Bundle: ${appBundleName} (${(appBundle.size / 1024).toFixed(1)} KB)`);
console.log(`  Mode: ${isProduction ? "production" : "development"}`);
