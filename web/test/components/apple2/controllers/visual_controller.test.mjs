import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2VisualController } from '../../../../app/components/apple2/controllers/visual_controller.mjs';

function createHarness() {
  const debugCalls = [];
  const ioCalls = [];
  const dom = {
    apple2TextScreen: { textContent: '' },
    apple2HiresCanvas: null
  };
  const state = {
    apple2: {
      displayHires: false,
      displayColor: false,
      lastCpuResult: { speaker_toggles: 7 }
    }
  };
  const runtime = {
    sim: null
  };
  const controller = createApple2VisualController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => false,
    updateIoToggleUi: () => ioCalls.push('io'),
    renderApple2DebugRows: (...args) => debugCalls.push(args),
    apple2HiresLineAddress: (row) => row
  });
  return { controller, dom, debugCalls, ioCalls };
}

test('refreshApple2Screen renders disabled message when runner is unavailable', () => {
  const { controller, dom, ioCalls } = createHarness();
  controller.refreshApple2Screen();
  assert.match(dom.apple2TextScreen.textContent, /Load a runner with memory \+ I\/O support/);
  assert.equal(ioCalls.length, 1);
});

test('refreshApple2Debug renders disabled placeholder when runner is unavailable', () => {
  const { controller, debugCalls } = createHarness();
  controller.refreshApple2Debug();
  assert.equal(debugCalls.length, 1);
  assert.equal(Array.isArray(debugCalls[0][1]), true);
  assert.equal(debugCalls[0][1].length, 0);
  assert.match(debugCalls[0][2], /Speaker toggles/);
  assert.equal(debugCalls[0][3], false);
});

test('refreshApple2Screen renders UART mode output when configured', () => {
  const controllerConfig = {
    dom: {
      apple2TextScreen: { textContent: '' },
      apple2HiresCanvas: null
    },
    state: {
      apple2: {
        displayHires: false,
        displayColor: false,
        lastCpuResult: { speaker_toggles: 7 },
        ioConfig: {
          display: {
            mode: 'uart',
            text: {
              width: 4,
              height: 2,
              rowStride: 4,
              charMask: 255,
              asciiMin: 32,
              asciiMax: 126
            }
          }
        }
      }
    },
    runtime: {
      sim: {
        runner_riscv_uart_tx_len: () => 8,
        runner_riscv_uart_tx_bytes: () => new Uint8Array([65, 66, 67, 68, 69, 70, 71, 72])
      }
    },
    isApple2UiEnabled: () => true,
    ioCalls: []
  };
  const controller = createApple2VisualController({
    dom: controllerConfig.dom,
    state: controllerConfig.state,
    runtime: controllerConfig.runtime,
    isApple2UiEnabled: controllerConfig.isApple2UiEnabled,
    updateIoToggleUi: () => controllerConfig.ioCalls.push('io'),
    renderApple2DebugRows: () => {},
    apple2HiresLineAddress: (row) => row
  });

  controller.refreshApple2Screen();
  assert.equal(controllerConfig.dom.apple2TextScreen.textContent, 'ABCD\nEFGH');
});
