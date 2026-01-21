import React, { useState, useCallback, useEffect } from 'react';
import { Box, Text, useInput, useApp, useStdout } from 'ink';
import {
  ScreenPanel,
  RegisterView,
  MemoryView,
  DisassemblyView,
  StatusBar,
  ConsolePanel,
  HelpOverlay,
  RegisterCompact
} from './components/index.js';
import { useApple2 } from './useApple2.js';
import { apple2Theme, apple2Chars, APPLE2_COLS } from './theme.js';

type Mode = 'normal' | 'help' | 'memory' | 'disasm';
type FocusedPanel = 'screen' | 'registers' | 'memory' | 'disasm' | 'console';

export function Apple2App() {
  const { stdout } = useStdout();
  const { exit } = useApp();
  const emulator = useApple2();

  const [mode, setMode] = useState<Mode>('normal');
  const [focusedPanel, setFocusedPanel] = useState<FocusedPanel>('screen');
  const [memoryAddress, setMemoryAddress] = useState(0x0400); // Text page

  // Calculate dimensions
  const termWidth = stdout?.columns ?? 120;
  const termHeight = stdout?.rows ?? 40;

  // Layout: Screen on left, registers/debug on right
  const screenWidth = APPLE2_COLS + 2; // 40 + borders
  const rightWidth = termWidth - screenWidth - 2;
  const mainHeight = termHeight - 5; // Header + status bar

  // Request disassembly around PC when it changes
  useEffect(() => {
    if (emulator.state?.cpu?.pc) {
      emulator.disassemble(emulator.state.cpu.pc - 10, 20);
    }
  }, [emulator.state?.cpu?.pc, emulator.disassemble]);

  // Cycle through panels
  const cycleFocus = useCallback(() => {
    const panels: FocusedPanel[] = ['screen', 'registers', 'disasm', 'console'];
    const currentIndex = panels.indexOf(focusedPanel);
    setFocusedPanel(panels[(currentIndex + 1) % panels.length]);
  }, [focusedPanel]);

  // Handle keyboard input
  useInput((input, key) => {
    // Help mode - any key closes
    if (mode === 'help') {
      setMode('normal');
      return;
    }

    // Global keys
    if (key.escape) {
      setMode('normal');
    } else if (input === 'q' || (key.ctrl && input === 'c')) {
      emulator.quit();
      exit();
    } else if (input === 'h' || input === '?') {
      setMode('help');
    } else if (key.tab) {
      cycleFocus();
    }

    // Emulator control keys
    else if (input === ' ') {
      emulator.step();
    } else if (input === 'n') {
      emulator.stepCycle();
    } else if (input === 'r') {
      emulator.run();
    } else if (input === 's') {
      emulator.stop();
    } else if (input === 'R') {
      emulator.reset();
    }

    // View toggle keys
    else if (input === 'm') {
      setMode(mode === 'memory' ? 'normal' : 'memory');
      if (mode !== 'memory') {
        emulator.readMemory(memoryAddress, 128);
      }
    } else if (input === 'd') {
      setMode(mode === 'disasm' ? 'normal' : 'disasm');
    }

    // Pass through regular keys to emulator when focused on screen
    else if (focusedPanel === 'screen' && input && !key.ctrl && !key.meta) {
      let ascii = input.charCodeAt(0);
      // Convert to uppercase for Apple II
      if (ascii >= 97 && ascii <= 122) {
        ascii -= 32;
      }
      emulator.sendKey(ascii);
    }
  });

  const state = emulator.state;
  const cpu = state?.cpu ?? null;
  const screen = state?.screen ?? null;
  const running = state?.running ?? false;
  const halted = cpu?.halted ?? false;

  return (
    <Box flexDirection="column" width={termWidth} height={termHeight}>
      {/* Header */}
      <Box>
        <Text color={apple2Theme.border}>{apple2Chars.boxH.repeat(termWidth)}</Text>
      </Box>
      <Box justifyContent="space-between">
        <Box>
          <Text color={apple2Theme.border}>{apple2Chars.boxV}</Text>
          <Text color={apple2Theme.phosphorBright} bold> APPLE ][ </Text>
          <Text color={apple2Theme.phosphor}>EMULATOR</Text>
          <Text color={apple2Theme.textDim}> - RHDL 6502 Simulator</Text>
        </Box>
        <Box>
          <RegisterCompact cpu={cpu} />
          <Text color={apple2Theme.border}> {apple2Chars.boxV}</Text>
        </Box>
      </Box>
      <Box>
        <Text color={apple2Theme.border}>{apple2Chars.boxH.repeat(termWidth)}</Text>
      </Box>

      {/* Main content */}
      <Box flexGrow={1}>
        {/* Left: Apple II Screen */}
        <Box flexDirection="column">
          <ScreenPanel
            screen={screen}
            focused={focusedPanel === 'screen'}
            title="DISPLAY"
          />
        </Box>

        {/* Right: Debug panels */}
        <Box flexDirection="column" width={rightWidth}>
          {/* Top right: Registers or Memory */}
          {mode === 'memory' ? (
            <MemoryView
              memory={emulator.memory}
              width={rightWidth}
              height={Math.floor(mainHeight * 0.5)}
              focused={focusedPanel === 'memory'}
            />
          ) : (
            <Box>
              <RegisterView
                cpu={cpu}
                focused={focusedPanel === 'registers'}
              />
              {mode === 'disasm' && (
                <DisassemblyView
                  instructions={emulator.disassembly}
                  currentPC={cpu?.pc}
                  width={rightWidth - 24}
                  height={14}
                  focused={focusedPanel === 'disasm'}
                />
              )}
            </Box>
          )}

          {/* Bottom right: Console */}
          <ConsolePanel
            logs={emulator.logs}
            width={rightWidth}
            height={Math.floor(mainHeight * 0.35)}
            focused={focusedPanel === 'console'}
          />
        </Box>
      </Box>

      {/* Status bar */}
      <StatusBar
        running={running}
        halted={halted}
        connected={emulator.connected}
        mode={emulator.mode}
        cycles={cpu?.cycles ?? 0}
        speed={state?.speed ?? 10000}
        width={termWidth}
      />

      {/* Help overlay */}
      {mode === 'help' && (
        <Box
          position="absolute"
          marginTop={5}
          marginLeft={Math.floor((termWidth - 42) / 2)}
        >
          <HelpOverlay onClose={() => setMode('normal')} />
        </Box>
      )}
    </Box>
  );
}
