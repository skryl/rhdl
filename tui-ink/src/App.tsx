import React, { useState, useCallback } from 'react';
import { Box, Text, useInput, useApp, useStdout } from 'ink';
import {
  SignalPanel,
  WaveformPanel,
  BreakpointPanel,
  ConsolePanel,
  StatusBar,
  HelpOverlay,
  CommandInput
} from './components/index.js';
import { useSimulator } from './hooks/useSimulator.js';

type Mode = 'normal' | 'command' | 'help';
type FocusedPanel = 'signals' | 'waveform' | 'console' | 'breakpoints';

export function App() {
  const { stdout } = useStdout();
  const { exit } = useApp();
  const simulator = useSimulator();

  const [mode, setMode] = useState<Mode>('normal');
  const [focusedPanel, setFocusedPanel] = useState<FocusedPanel>('signals');
  const [commandBuffer, setCommandBuffer] = useState('');

  // Calculate dimensions
  const termWidth = stdout?.columns ?? 120;
  const termHeight = stdout?.rows ?? 40;

  const leftWidth = Math.floor(termWidth * 0.4);
  const rightWidth = termWidth - leftWidth - 2;
  const topHeight = Math.floor(termHeight * 0.65);
  const bottomHeight = termHeight - topHeight - 3;

  const executeCommand = useCallback((cmd: string) => {
    const parts = cmd.trim().split(/\s+/);
    if (parts.length === 0 || !parts[0]) return;

    const command = parts[0].toLowerCase();
    const args = parts.slice(1);

    switch (command) {
      case 'run':
      case 'r':
        simulator.run(args[0] ? parseInt(args[0], 10) : undefined);
        break;
      case 'step':
      case 's':
        simulator.step();
        break;
      case 'watch':
      case 'w':
        if (args[0]) {
          simulator.addWatchpoint(args[0], args[1] || 'change', args[2] ? parseInt(args[2], 10) : undefined);
        }
        break;
      case 'break':
      case 'b':
        simulator.addBreakpoint(args[0] ? parseInt(args[0], 10) : undefined);
        break;
      case 'delete':
      case 'del':
      case 'd':
        if (args[0]) {
          simulator.deleteBreakpoint(parseInt(args[0], 10));
        }
        break;
      case 'clear':
        if (args[0] === 'breaks' || args[0] === 'breakpoints') {
          simulator.clearBreakpoints();
        } else if (args[0] === 'waves' || args[0] === 'waveform') {
          simulator.clearWaveforms();
        } else if (args[0] === 'log' || args[0] === 'console') {
          simulator.clearLogs();
        }
        break;
      case 'set':
        if (args[0] && args[1]) {
          simulator.setSignal(args[0], parseInt(args[1], 10));
        }
        break;
      case 'export':
        simulator.exportVcd(args[0] || 'waveform.vcd');
        break;
      case 'quit':
      case 'q':
        simulator.quit();
        exit();
        break;
      default:
        // Unknown command - logged by Ruby side
        break;
    }
  }, [simulator, exit]);

  const handleCommandSubmit = useCallback((cmd: string) => {
    executeCommand(cmd);
    setMode('normal');
    setCommandBuffer('');
  }, [executeCommand]);

  const handleCommandCancel = useCallback(() => {
    setMode('normal');
    setCommandBuffer('');
  }, []);

  // Cycle through panels
  const cycleFocus = useCallback(() => {
    const panels: FocusedPanel[] = ['signals', 'waveform', 'console', 'breakpoints'];
    const currentIndex = panels.indexOf(focusedPanel);
    setFocusedPanel(panels[(currentIndex + 1) % panels.length]);
  }, [focusedPanel]);

  useInput((input, key) => {
    // Handle help mode - any key closes
    if (mode === 'help') {
      setMode('normal');
      return;
    }

    // Handle command mode
    if (mode === 'command') {
      return; // Handled by CommandInput
    }

    // Normal mode key handling
    if (key.escape) {
      setMode('normal');
    } else if (input === 'q' || (key.ctrl && input === 'c')) {
      simulator.quit();
      exit();
    } else if (input === 'h' || input === '?') {
      setMode('help');
    } else if (input === ':') {
      setMode('command');
      setCommandBuffer('');
    } else if (input === ' ') {
      simulator.step();
    } else if (input === 'n') {
      simulator.stepHalf();
    } else if (input === 'r') {
      simulator.run();
    } else if (input === 's') {
      simulator.stop();
    } else if (input === 'R') {
      simulator.reset();
    } else if (input === 'c') {
      simulator.continueUntilBreak();
    } else if (input === 'w') {
      setMode('command');
      setCommandBuffer('watch ');
    } else if (input === 'b') {
      setMode('command');
      setCommandBuffer('break ');
    } else if (key.tab) {
      cycleFocus();
    }
  });

  const state = simulator.state;

  return (
    <Box flexDirection="column" width={termWidth} height={termHeight}>
      {/* Main content area */}
      <Box flexGrow={1}>
        {/* Left column - Signals */}
        <Box flexDirection="column" width={leftWidth}>
          <SignalPanel
            signals={state?.signals ?? []}
            height={topHeight}
            focused={focusedPanel === 'signals'}
          />
          <ConsolePanel
            logs={simulator.logs}
            height={bottomHeight}
            focused={focusedPanel === 'console'}
          />
        </Box>

        {/* Right column - Waveform and Breakpoints */}
        <Box flexDirection="column" width={rightWidth}>
          <WaveformPanel
            waveforms={state?.waveforms ?? []}
            width={rightWidth}
            height={topHeight}
            focused={focusedPanel === 'waveform'}
          />
          <BreakpointPanel
            breakpoints={state?.breakpoints ?? []}
            watchpoints={state?.watchpoints ?? []}
            height={bottomHeight}
            focused={focusedPanel === 'breakpoints'}
            onDelete={simulator.deleteBreakpoint}
          />
        </Box>
      </Box>

      {/* Command input (when in command mode) */}
      {mode === 'command' && (
        <CommandInput
          initialValue={commandBuffer}
          onSubmit={handleCommandSubmit}
          onCancel={handleCommandCancel}
        />
      )}

      {/* Status bar */}
      <StatusBar
        time={state?.time ?? 0}
        cycle={state?.cycle ?? 0}
        running={state?.running ?? false}
        paused={state?.paused ?? false}
        connected={simulator.connected}
        mode={mode}
        commandBuffer={commandBuffer}
      />

      {/* Help overlay */}
      {mode === 'help' && <HelpOverlay onClose={() => setMode('normal')} />}
    </Box>
  );
}
