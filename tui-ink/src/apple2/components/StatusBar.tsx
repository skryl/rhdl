import React from 'react';
import { Box, Text } from 'ink';
import { apple2Theme, apple2Chars } from '../theme.js';
import type { LogEntry } from '../useApple2.js';

interface StatusBarProps {
  running: boolean;
  halted: boolean;
  connected: boolean;
  mode: 'hdl' | 'isa';
  cycles: number;
  speed: number;
  width?: number;
}

export function StatusBar({
  running,
  halted,
  connected,
  mode,
  cycles,
  speed,
  width = 80
}: StatusBarProps) {
  const statusText = halted ? 'HALT' : running ? 'RUN ' : 'STOP';
  const statusColor = halted ? apple2Theme.error : running ? apple2Theme.phosphor : apple2Theme.textDim;

  return (
    <Box flexDirection="column">
      <Box>
        <Text color={apple2Theme.border}>{apple2Chars.boxH.repeat(width)}</Text>
      </Box>
      <Box justifyContent="space-between">
        <Box>
          <Text color={apple2Theme.border}>{apple2Chars.boxV}</Text>
          <Text color={statusColor} bold> [{statusText}] </Text>
          <Text color={apple2Theme.textDim}>{apple2Chars.boxV}</Text>
          <Text color={apple2Theme.textDim}> MODE:</Text>
          <Text color={apple2Theme.phosphor}>{mode.toUpperCase()}</Text>
          <Text color={apple2Theme.textDim}> {apple2Chars.boxV}</Text>
          <Text color={apple2Theme.textDim}> CYC:</Text>
          <Text color={apple2Theme.phosphor}>{cycles.toString().padStart(10)}</Text>
          <Text color={apple2Theme.textDim}> {apple2Chars.boxV}</Text>
          <Text color={connected ? apple2Theme.phosphor : apple2Theme.error}>
            {connected ? ' ONLINE ' : ' OFFLINE'}
          </Text>
        </Box>
        <Box>
          <Text color={apple2Theme.textMuted}>
            SPC:Step r:Run s:Stop R:Reset h:Help q:Quit
          </Text>
          <Text color={apple2Theme.border}> {apple2Chars.boxV}</Text>
        </Box>
      </Box>
      <Box>
        <Text color={apple2Theme.border}>{apple2Chars.boxH.repeat(width)}</Text>
      </Box>
    </Box>
  );
}

// Console/log display
interface ConsolePanelProps {
  logs: LogEntry[];
  width?: number;
  height?: number;
  focused?: boolean;
}

export function ConsolePanel({ logs, width = 40, height = 8, focused = false }: ConsolePanelProps) {
  const borderColor = focused ? apple2Theme.phosphor : apple2Theme.border;
  const visibleHeight = height - 3;
  const visibleLogs = logs.slice(-visibleHeight);

  const LEVEL_COLORS: Record<string, string> = {
    info: apple2Theme.phosphor,
    warning: apple2Theme.phosphorBright,
    error: apple2Theme.error,
  };

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxTL}{apple2Chars.boxH}</Text>
        <Text color={apple2Theme.phosphor} bold>[ CONSOLE ]</Text>
        <Text color={borderColor}>
          {apple2Chars.boxH.repeat(Math.max(0, width - 14))}
          {apple2Chars.boxTR}
        </Text>
      </Box>

      {/* Logs */}
      {visibleLogs.length === 0 ? (
        <Box>
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
          <Text color={apple2Theme.textDim}> ]READY</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
        </Box>
      ) : (
        visibleLogs.map((log) => (
          <Box key={log.id}>
            <Text color={borderColor}>{apple2Chars.boxV}</Text>
            <Text color={LEVEL_COLORS[log.level] || apple2Theme.textDim}>
              {' '}{log.message.slice(0, width - 4)}
            </Text>
            <Box flexGrow={1} />
            <Text color={borderColor}>{apple2Chars.boxV}</Text>
          </Box>
        ))
      )}

      {/* Fill empty */}
      {Array.from({ length: Math.max(0, visibleHeight - visibleLogs.length - 1) }).map((_, i) => (
        <Box key={`empty-${i}`}>
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
        </Box>
      ))}

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxBL}
          {apple2Chars.boxH.repeat(width - 2)}
          {apple2Chars.boxBR}
        </Text>
      </Box>
    </Box>
  );
}

// Help overlay
interface HelpOverlayProps {
  onClose: () => void;
}

export function HelpOverlay({ onClose }: HelpOverlayProps) {
  return (
    <Box flexDirection="column">
      <Box>
        <Text color={apple2Theme.phosphor}>
          {apple2Chars.boxTL}{apple2Chars.boxH.repeat(40)}{apple2Chars.boxTR}
        </Text>
      </Box>
      <Box>
        <Text color={apple2Theme.phosphor}>{apple2Chars.boxV}</Text>
        <Text color={apple2Theme.phosphorBright} bold>      APPLE ][ EMULATOR HELP      </Text>
        <Text color={apple2Theme.phosphor}>{apple2Chars.boxV}</Text>
      </Box>
      <Box>
        <Text color={apple2Theme.phosphor}>
          {apple2Chars.boxV}{apple2Chars.boxH.repeat(40)}{apple2Chars.boxV}
        </Text>
      </Box>

      {[
        ['SPC', 'Step one instruction'],
        ['n', 'Step one cycle (HDL mode)'],
        ['r', 'Run continuously'],
        ['s', 'Stop/pause execution'],
        ['R', 'Reset CPU'],
        ['m', 'Show memory view'],
        ['d', 'Show disassembly'],
        ['TAB', 'Switch panel focus'],
        ['h', 'Toggle this help'],
        ['q', 'Quit emulator'],
      ].map(([key, desc]) => (
        <Box key={key}>
          <Text color={apple2Theme.phosphor}>{apple2Chars.boxV} </Text>
          <Text color={apple2Theme.phosphorBright}>{(key as string).padEnd(6)}</Text>
          <Text color={apple2Theme.textDim}>{desc}</Text>
          <Box flexGrow={1} />
          <Text color={apple2Theme.phosphor}>{apple2Chars.boxV}</Text>
        </Box>
      ))}

      <Box>
        <Text color={apple2Theme.phosphor}>
          {apple2Chars.boxV}{apple2Chars.boxH.repeat(40)}{apple2Chars.boxV}
        </Text>
      </Box>
      <Box>
        <Text color={apple2Theme.phosphor}>{apple2Chars.boxV}</Text>
        <Text color={apple2Theme.textDim}>     Press any key to close        </Text>
        <Text color={apple2Theme.phosphor}>{apple2Chars.boxV}</Text>
      </Box>
      <Box>
        <Text color={apple2Theme.phosphor}>
          {apple2Chars.boxBL}{apple2Chars.boxH.repeat(40)}{apple2Chars.boxBR}
        </Text>
      </Box>
    </Box>
  );
}
