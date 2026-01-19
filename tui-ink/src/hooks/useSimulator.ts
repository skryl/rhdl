import { useState, useEffect, useCallback, useRef } from 'react';
import * as readline from 'readline';
import type { SimulatorState, Command, Event, Signal, WaveformProbe, Breakpoint, Watchpoint } from '../protocol.js';
import { serializeCommand, parseEvent } from '../protocol.js';

export interface LogEntry {
  id: number;
  message: string;
  level: 'info' | 'success' | 'warning' | 'error' | 'debug';
  timestamp: Date;
}

export interface SimulatorHook {
  state: SimulatorState | null;
  logs: LogEntry[];
  connected: boolean;
  sendCommand: (cmd: Command) => void;
  step: () => void;
  stepHalf: () => void;
  run: (cycles?: number) => void;
  stop: () => void;
  reset: () => void;
  continueUntilBreak: () => void;
  setSignal: (path: string, value: number) => void;
  addBreakpoint: (cycle?: number) => void;
  addWatchpoint: (signal: string, watchType: string, value?: number) => void;
  deleteBreakpoint: (id: number) => void;
  clearBreakpoints: () => void;
  clearWaveforms: () => void;
  exportVcd: (filename: string) => void;
  quit: () => void;
  clearLogs: () => void;
}

export function useSimulator(): SimulatorHook {
  const [state, setState] = useState<SimulatorState | null>(null);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [connected, setConnected] = useState(false);
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

  const sendCommand = useCallback((cmd: Command) => {
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
          addLog('Connected to simulator', 'success');
          sendCommand({ type: 'get_state' });
          break;

        case 'state':
          setState(event.state);
          break;

        case 'log':
          addLog(event.message, event.level);
          break;

        case 'break':
          addLog(event.message, 'warning');
          sendCommand({ type: 'get_state' });
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
      addLog('Disconnected from simulator', 'error');
    });

    // Signal ready to Ruby
    sendCommand({ type: 'init' });

    return () => {
      rl.close();
    };
  }, [addLog, sendCommand]);

  // Command helpers
  const step = useCallback(() => sendCommand({ type: 'step' }), [sendCommand]);
  const stepHalf = useCallback(() => sendCommand({ type: 'step_half' }), [sendCommand]);
  const run = useCallback((cycles?: number) => sendCommand({ type: 'run', cycles }), [sendCommand]);
  const stop = useCallback(() => sendCommand({ type: 'stop' }), [sendCommand]);
  const reset = useCallback(() => sendCommand({ type: 'reset' }), [sendCommand]);
  const continueUntilBreak = useCallback(() => sendCommand({ type: 'continue' }), [sendCommand]);

  const setSignal = useCallback((path: string, value: number) => {
    sendCommand({ type: 'set_signal', path, value });
  }, [sendCommand]);

  const addBreakpoint = useCallback((cycle?: number) => {
    sendCommand({ type: 'add_breakpoint', cycle });
  }, [sendCommand]);

  const addWatchpoint = useCallback((signal: string, watchType: string, value?: number) => {
    sendCommand({ type: 'add_watchpoint', signal, watch_type: watchType, value });
  }, [sendCommand]);

  const deleteBreakpoint = useCallback((id: number) => {
    sendCommand({ type: 'delete_breakpoint', id });
  }, [sendCommand]);

  const clearBreakpoints = useCallback(() => sendCommand({ type: 'clear_breakpoints' }), [sendCommand]);
  const clearWaveforms = useCallback(() => sendCommand({ type: 'clear_waveforms' }), [sendCommand]);

  const exportVcd = useCallback((filename: string) => {
    sendCommand({ type: 'export_vcd', filename });
  }, [sendCommand]);

  const quit = useCallback(() => sendCommand({ type: 'quit' }), [sendCommand]);

  return {
    state,
    logs,
    connected,
    sendCommand,
    step,
    stepHalf,
    run,
    stop,
    reset,
    continueUntilBreak,
    setSignal,
    addBreakpoint,
    addWatchpoint,
    deleteBreakpoint,
    clearBreakpoints,
    clearWaveforms,
    exportVcd,
    quit,
    clearLogs
  };
}
