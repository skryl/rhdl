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
import { theme, box, headerCompact } from './theme.js';

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

  // SHENZHEN I/O style layout - 3 columns
  const leftWidth = Math.floor(termWidth * 0.35);
  const middleWidth = Math.floor(termWidth * 0.40);
  const rightWidth = termWidth - leftWidth - middleWidth - 2;
  const mainHeight = termHeight - 6; // Header + Status bar

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

  const cycleFocus = useCallback(() => {
    const panels: FocusedPanel[] = ['signals', 'waveform', 'console', 'breakpoints'];
    const currentIndex = panels.indexOf(focusedPanel);
    setFocusedPanel(panels[(currentIndex + 1) % panels.length]);
  }, [focusedPanel]);

  useInput((input, key) => {
    if (mode === 'help') {
      setMode('normal');
      return;
    }

    if (mode === 'command') {
      return;
    }

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
      {/* Header bar - SHENZHEN I/O style */}
      <Box>
        <Text color={theme.border}>{box.dHorizontal.repeat(termWidth)}</Text>
      </Box>
      <Box justifyContent="space-between">
        <Box>
          <Text color={theme.border}>{box.dVertical}</Text>
          <Text color={theme.primaryBright} bold> RHDL </Text>
          <Text color={theme.primary}>HARDWARE SIMULATOR</Text>
        </Box>
        <Box>
          <Text color={theme.textMuted}>v1.0</Text>
          <Text color={theme.border}> {box.dVertical}</Text>
        </Box>
      </Box>
      <Box>
        <Text color={theme.border}>{box.dHorizontal.repeat(termWidth)}</Text>
      </Box>

      {/* Main content - 3 column layout */}
      <Box flexGrow={1}>
        {/* Left column - Signals */}
        <Box flexDirection="column" width={leftWidth}>
          <SignalPanel
            signals={state?.signals ?? []}
            width={leftWidth}
            height={mainHeight}
            focused={focusedPanel === 'signals'}
          />
        </Box>

        {/* Middle column - Waveform */}
        <Box flexDirection="column" width={middleWidth}>
          <WaveformPanel
            waveforms={state?.waveforms ?? []}
            width={middleWidth}
            height={Math.floor(mainHeight * 0.6)}
            focused={focusedPanel === 'waveform'}
          />
          <ConsolePanel
            logs={simulator.logs}
            width={middleWidth}
            height={Math.floor(mainHeight * 0.4)}
            focused={focusedPanel === 'console'}
          />
        </Box>

        {/* Right column - Breakpoints */}
        <Box flexDirection="column" width={rightWidth}>
          <BreakpointPanel
            breakpoints={state?.breakpoints ?? []}
            watchpoints={state?.watchpoints ?? []}
            width={rightWidth}
            height={mainHeight}
            focused={focusedPanel === 'breakpoints'}
            onDelete={simulator.deleteBreakpoint}
          />
        </Box>
      </Box>

      {/* Command input */}
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
        width={termWidth}
      />

      {/* Help overlay - centered */}
      {mode === 'help' && (
        <Box
          position="absolute"
          marginTop={5}
          marginLeft={Math.floor((termWidth - 60) / 2)}
        >
          <HelpOverlay onClose={() => setMode('normal')} />
        </Box>
      )}
    </Box>
  );
}
