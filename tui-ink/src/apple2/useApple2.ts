import { useState, useEffect, useCallback, useRef } from 'react';
import * as readline from 'readline';
import type {
  EmulatorState,
  CPUState,
  ScreenData,
  MemoryDump,
  Instruction,
  Apple2Command,
  Apple2Event
} from './protocol.js';
import { serializeCommand, parseEvent } from './protocol.js';

export interface LogEntry {
  id: number;
  message: string;
  level: 'info' | 'warning' | 'error';
  timestamp: Date;
}

export interface Apple2Hook {
  state: EmulatorState | null;
  memory: MemoryDump | null;
  disassembly: Instruction[];
  logs: LogEntry[];
  connected: boolean;
  mode: 'hdl' | 'isa';

  // Commands
  sendCommand: (cmd: Apple2Command) => void;
  step: () => void;
  stepCycle: () => void;
  run: () => void;
  stop: () => void;
  reset: () => void;
  setSpeed: (cycles: number) => void;
  sendKey: (ascii: number) => void;
  readMemory: (address: number, length: number) => void;
  writeMemory: (address: number, value: number) => void;
  setBreakpoint: (address: number) => void;
  clearBreakpoint: (address: number) => void;
  disassemble: (address: number, count: number) => void;
  quit: () => void;
  clearLogs: () => void;
}

export function useApple2(): Apple2Hook {
  const [state, setState] = useState<EmulatorState | null>(null);
  const [memory, setMemory] = useState<MemoryDump | null>(null);
  const [disassembly, setDisassembly] = useState<Instruction[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [connected, setConnected] = useState(false);
  const [mode, setMode] = useState<'hdl' | 'isa'>('isa');
  const logIdRef = useRef(0);

  const addLog = useCallback((message: string, level: LogEntry['level']) => {
    setLogs(prev => [...prev.slice(-100), {
      id: ++logIdRef.current,
      message,
      level,
      timestamp: new Date()
    }]);
  }, []);

  const clearLogs = useCallback(() => {
    setLogs([]);
  }, []);

  const sendCommand = useCallback((cmd: Apple2Command) => {
    process.stdout.write(serializeCommand(cmd));
  }, []);

  // Set up stdin reading for events from Ruby
  useEffect(() => {
    const rl = readline.createInterface({
      input: process.stdin,
      terminal: false
    });

    rl.on('line', (line) => {
      const event = parseEvent(line);
      if (!event) return;

      switch (event.type) {
        case 'ready':
          setConnected(true);
          setMode(event.mode);
          addLog(`Apple ][ emulator ready (${event.mode.toUpperCase()} mode)`, 'info');
          sendCommand({ type: 'get_state' });
          break;

        case 'state':
          setState(event.state);
          break;

        case 'screen_update':
          setState(prev => prev ? { ...prev, screen: event.screen } : null);
          break;

        case 'memory':
          setMemory(event.dump);
          break;

        case 'disassembly':
          setDisassembly(event.instructions);
          break;

        case 'breakpoint_hit':
          addLog(`Breakpoint hit at $${event.address.toString(16).toUpperCase().padStart(4, '0')}`, 'warning');
          sendCommand({ type: 'get_state' });
          break;

        case 'halted':
          addLog(`CPU halted at $${event.pc.toString(16).toUpperCase().padStart(4, '0')}`, 'warning');
          setState(prev => prev ? {
            ...prev,
            cpu: { ...prev.cpu, halted: true },
            running: false
          } : null);
          break;

        case 'log':
          addLog(event.message, event.level);
          break;

        case 'error':
          addLog(event.message, 'error');
          break;

        case 'quit':
          process.exit(0);
          break;
      }
    });

    rl.on('close', () => {
      setConnected(false);
      addLog('Disconnected from emulator', 'error');
    });

    // Signal ready to Ruby
    sendCommand({ type: 'init' });

    return () => {
      rl.close();
    };
  }, [addLog, sendCommand]);

  // Command helpers
  const step = useCallback(() => sendCommand({ type: 'step' }), [sendCommand]);
  const stepCycle = useCallback(() => sendCommand({ type: 'step_cycle' }), [sendCommand]);
  const run = useCallback(() => sendCommand({ type: 'run' }), [sendCommand]);
  const stop = useCallback(() => sendCommand({ type: 'stop' }), [sendCommand]);
  const reset = useCallback(() => sendCommand({ type: 'reset' }), [sendCommand]);
  const setSpeed = useCallback((cycles: number) => sendCommand({ type: 'set_speed', cycles }), [sendCommand]);
  const sendKey = useCallback((ascii: number) => sendCommand({ type: 'key_press', ascii }), [sendCommand]);
  const readMemory = useCallback((address: number, length: number) => {
    sendCommand({ type: 'read_memory', address, length });
  }, [sendCommand]);
  const writeMemory = useCallback((address: number, value: number) => {
    sendCommand({ type: 'write_memory', address, value });
  }, [sendCommand]);
  const setBreakpoint = useCallback((address: number) => {
    sendCommand({ type: 'set_breakpoint', address });
  }, [sendCommand]);
  const clearBreakpoint = useCallback((address: number) => {
    sendCommand({ type: 'clear_breakpoint', address });
  }, [sendCommand]);
  const disassembleCmd = useCallback((address: number, count: number) => {
    sendCommand({ type: 'disassemble', address, count });
  }, [sendCommand]);
  const quit = useCallback(() => sendCommand({ type: 'quit' }), [sendCommand]);

  return {
    state,
    memory,
    disassembly,
    logs,
    connected,
    mode,
    sendCommand,
    step,
    stepCycle,
    run,
    stop,
    reset,
    setSpeed,
    sendKey,
    readMemory,
    writeMemory,
    setBreakpoint,
    clearBreakpoint,
    disassemble: disassembleCmd,
    quit,
    clearLogs
  };
}
