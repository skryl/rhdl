import test from 'node:test';
import assert from 'node:assert/strict';

import { createApple2VisualController } from '../../../../app/components/apple2/controllers/visual_controller';

function createHarness() {
  const debugCalls: unknown[][] = [];
  const ioCalls: string[] = [];
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
    renderApple2DebugRows: (...args: unknown[]) => debugCalls.push(args),
    apple2HiresLineAddress: (row: number) => row
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
  const call = debugCalls[0] as [unknown, unknown, unknown, unknown];
  assert.equal(debugCalls.length, 1);
  assert.equal(Array.isArray(call[1]), true);
  assert.equal((call[1] as unknown[]).length, 0);
  assert.match(String(call[2] || ''), /Speaker toggles/);
  assert.equal(call[3], false);
});

test('refreshApple2Screen renders UART mode output when configured', () => {
  let uartReadArgs: [number, number] | null = null;
  const uartBytes = new Uint8Array([65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76]);
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
        runner_riscv_uart_tx_len: () => uartBytes.length,
        runner_riscv_uart_tx_bytes: (offset = 0, length = uartBytes.length) => {
          uartReadArgs = [offset, length];
          return uartBytes.slice(offset, offset + length);
        }
      }
    },
    isApple2UiEnabled: () => true,
    ioCalls: [] as string[]
  };
  const controller = createApple2VisualController({
    dom: controllerConfig.dom,
    state: controllerConfig.state,
    runtime: controllerConfig.runtime,
    isApple2UiEnabled: controllerConfig.isApple2UiEnabled,
    updateIoToggleUi: () => controllerConfig.ioCalls.push('io'),
    renderApple2DebugRows: () => {},
    apple2HiresLineAddress: (row: number) => row
  });

  controller.refreshApple2Screen();
  assert.deepEqual(uartReadArgs, [4, 8]);
  assert.equal(controllerConfig.dom.apple2TextScreen.textContent, 'EFGH\nIJKL');
});

test('refreshApple2Screen renders UART CR/LF as line breaks', () => {
  const uartBytes = new Uint8Array([97, 98, 99, 13, 10, 100, 101, 102]);
  const dom = {
    apple2TextScreen: { textContent: '' },
    apple2HiresCanvas: null
  };
  const state = {
    apple2: {
      displayHires: false,
      displayColor: false,
      lastCpuResult: { speaker_toggles: 0 },
      ioConfig: {
        display: {
          mode: 'uart',
          text: {
            width: 8,
            height: 2,
            charMask: 255,
            asciiMin: 32,
            asciiMax: 126
          }
        }
      }
    }
  };
  const runtime = {
    sim: {
      runner_riscv_uart_tx_len: () => uartBytes.length,
      runner_riscv_uart_tx_bytes: () => uartBytes
    }
  };

  const controller = createApple2VisualController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    updateIoToggleUi: () => {},
    renderApple2DebugRows: () => {},
    apple2HiresLineAddress: (row: number) => row
  });

  controller.refreshApple2Screen();
  assert.equal(dom.apple2TextScreen.textContent, 'abc     \ndef     ');
});
