import test from 'node:test';
import assert from 'node:assert/strict';

import { parseHexOrDec, hexWord, hexByte } from '../../../../app/core/lib/numeric_utils';
import { createApple2MemoryController } from '../../../../app/components/apple2/controllers/memory_controller';

function createHarness() {
  const renderCalls = [];
  const statusMessages = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x0000' },
    memoryLength: { value: '32' }
  };
  const state = {
    memory: {
      followPc: false,
      disasmLines: 4
    }
  };
  const runtime = {
    sim: null
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => false,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: () => ['LDA #$01'],
    setMemoryDumpStatus: (message) => statusMessages.push(message),
    addressSpace: 0x10000
  });
  return { controller, dom, state, runtime, renderCalls, statusMessages };
}

test('getApple2ProgramCounter returns null when unavailable', () => {
  const { controller } = createHarness();
  assert.equal(controller.getApple2ProgramCounter(), null);
});

test('readApple2MappedMemory returns empty without simulator', () => {
  const { controller } = createHarness();
  const bytes = controller.readApple2MappedMemory(0, 16);
  assert.equal(bytes.length, 0);
});

test('refreshMemoryView shows placeholder when simulator is missing', () => {
  const { controller, renderCalls } = createHarness();
  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.equal(renderCalls[0].dumpText, '');
  assert.equal(renderCalls[0].disasmText, '');
});

test('refreshMemoryView shows apple2-required message when disabled', () => {
  const { controller, runtime, renderCalls, statusMessages } = createHarness();
  runtime.sim = {};
  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.match(renderCalls[0].dumpText, /Load a runner with memory \+ I\/O support/);
  assert.equal(statusMessages.includes('Memory dump loading requires a runner with memory + I/O support.'), true);
});

test('refreshMemoryView allows full-memory length and caps at 64k max', () => {
  const renderCalls = [];
  const disasmCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x0000' },
    memoryLength: { value: '0x20000' }
  };
  const state = {
    memory: {
      followPc: false,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x20000,
          viewMapped: true
        }
      }
    }
  };
  const runtime = {
    sim: {
      memory_read: (start, length) => {
        assert.equal(start, 0);
        assert.equal(length, 0x10000);
        return new Uint8Array(length);
      },
      has_signal: () => false
    }
  };

  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: (startAddress, lineCount) => {
      disasmCalls.push([startAddress, lineCount]);
      return ['NOP'];
    },
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.ok(String(renderCalls[0].dumpText || '').includes('0000:'));
  assert.deepEqual(disasmCalls, [[0, 4096]]);
});

test('refreshMemoryView formats 32-bit memory addresses when configured', () => {
  const renderCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '16' }
  };
  const state = {
    memory: {
      followPc: false,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        }
      }
    }
  };
  const runtime = {
    sim: {
      memory_read: (start, length) => {
        assert.equal(start, 0x80000000);
        assert.equal(length, 16);
        return new Uint8Array(length);
      },
      has_signal: () => false,
      memory_mode: () => true
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: () => ['NOP'],
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.match(renderCalls[0].dumpRows[0].addressHex, /80000000/);
});

test('refreshMemoryView uses riscv disassembly for riscv runner', () => {
  const renderCalls = [];
  const riscvDisasmCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '16' }
  };
  const state = {
    memory: {
      followPc: false,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        }
      }
    }
  };
  const runtime = {
    sim: {
      memory_read: (_start, length) => new Uint8Array(length),
      has_signal: () => false,
      runner_kind: () => 'riscv'
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: () => ['NOP'],
    disassembleRiscvLinesWithMemory: (start, count, readMem, opts) => {
      riscvDisasmCalls.push({ start, count, opts });
      return ['unimp'];
    },
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.equal(renderCalls[0].disasmText, 'unimp');
  assert.equal(riscvDisasmCalls.length, 1);
  assert.equal(riscvDisasmCalls[0].start, 0x80000000);
});

test('refreshMemoryView passes sourceMap to riscv disassembler when showSource is enabled', () => {
  const riscvDisasmCalls = [];
  const fakeSourceMap = { lookup: () => null };
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '16' }
  };
  const state = {
    memory: {
      followPc: false,
      showSource: true,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        }
      },
      sourceMap: fakeSourceMap
    }
  };
  const runtime = {
    sim: {
      memory_read: (_start, length) => new Uint8Array(length),
      has_signal: () => false,
      runner_kind: () => 'riscv'
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: () => {},
    disassemble6502LinesWithMemory: () => ['NOP'],
    disassembleRiscvLinesWithMemory: (start, count, readMem, opts) => {
      riscvDisasmCalls.push({ start, count, opts });
      return ['nop'];
    },
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(riscvDisasmCalls.length, 1);
  assert.equal(riscvDisasmCalls[0].opts.sourceMap, fakeSourceMap);
});

test('refreshMemoryView does not pass sourceMap when showSource is false', () => {
  const riscvDisasmCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '16' }
  };
  const state = {
    memory: {
      followPc: false,
      showSource: false,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        }
      },
      sourceMap: { lookup: () => null }
    }
  };
  const runtime = {
    sim: {
      memory_read: (_start, length) => new Uint8Array(length),
      has_signal: () => false,
      runner_kind: () => 'riscv'
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: () => {},
    disassemble6502LinesWithMemory: () => ['NOP'],
    disassembleRiscvLinesWithMemory: (start, count, readMem, opts) => {
      riscvDisasmCalls.push({ start, count, opts });
      return ['nop'];
    },
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(riscvDisasmCalls.length, 1);
  assert.equal(riscvDisasmCalls[0].opts.sourceMap, undefined);
});

test('refreshMemoryView sets showSourceDisabled when no sourceMap', () => {
  const renderCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '16' }
  };
  const state = {
    memory: {
      followPc: false,
      showSource: false,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        }
      }
    }
  };
  const runtime = {
    sim: {
      memory_read: (_start, length) => new Uint8Array(length),
      has_signal: () => false,
      runner_kind: () => 'riscv'
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: () => ['NOP'],
    disassembleRiscvLinesWithMemory: () => ['nop'],
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.equal(renderCalls[0].showSourceDisabled, true);
  assert.equal(renderCalls[0].showSourceChecked, false);
});

test('refreshMemoryView aligns follow-pc start for riscv high addresses', () => {
  const renderCalls = [];
  const dom = {
    memoryDump: {},
    memoryStart: { value: '0x80000000' },
    memoryLength: { value: '64' }
  };
  const state = {
    memory: {
      followPc: true,
      disasmLines: 4
    },
    apple2: {
      ioConfig: {
        memory: {
          addressSpace: 0x100000000,
          viewMapped: true
        },
        pcSignalCandidates: ['debug_pc']
      }
    }
  };
  const runtime = {
    sim: {
      memory_read: (_start, length) => new Uint8Array(length),
      has_signal: (name) => name === 'debug_pc',
      peek: () => 0x800000A8,
      runner_kind: () => 'riscv'
    }
  };
  const controller = createApple2MemoryController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    parseHexOrDec,
    hexWord,
    hexByte,
    renderMemoryPanel: (_dom, payload) => renderCalls.push(payload),
    disassemble6502LinesWithMemory: () => ['NOP'],
    disassembleRiscvLinesWithMemory: () => ['nop'],
    setMemoryDumpStatus: () => {},
    addressSpace: 0x10000
  });

  controller.refreshMemoryView();
  assert.equal(renderCalls.length, 1);
  assert.equal(dom.memoryStart.value, '0x80000080');
  assert.equal(renderCalls[0].dumpRows[0].addressHex, '80000080');
});
