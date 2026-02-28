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
      // The web simulator is a static site served from the parent web/
      // directory. The prebuild script (scripts/prebuild.ts) syncs the
      // necessary files into src/simulator/ before Electrobun's copy step.
      "src/simulator/index.html": "views/simulator/index.html",
      "src/simulator/coi-serviceworker.js": "views/simulator/coi-serviceworker.js",
      "src/simulator/app": "views/simulator/app",
      "src/simulator/assets": "views/simulator/assets",
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
