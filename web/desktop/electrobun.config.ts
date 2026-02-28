import type { ElectrobunConfig } from "electrobun";

export default {
  app: {
    name: "RHDL Simulator",
    identifier: "com.rhdl.simulator",
    version: "0.1.0",
  },
  runtime: {
    exitOnLastWindowClosed: true,
  },
  build: {
    bun: {
      entrypoint: "src/bun/index.ts",
    },
    views: {},
    copy: {
      // The prebuild script syncs the bundled output from web/dist/
      // into src/simulator/. The bundle contains index.html, the
      // hashed JS bundle, service worker, and assets/.
      "src/simulator": "views/simulator",
    },
  },
  mac: {
    codesign: false,
    notarize: false,
    bundleCEF: false,
    defaultRenderer: "native",
  },
  linux: {
    bundleCEF: false,
    defaultRenderer: "native",
  },
  win: {
    bundleCEF: false,
    defaultRenderer: "native",
  },
  scripts: {
    preBuild: "bun run scripts/prebuild.ts",
  },
} satisfies ElectrobunConfig;
