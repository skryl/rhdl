import React from 'react';
import { Box, Text } from 'ink';
import { theme, box, indicators } from '../theme.js';

interface StatusBarProps {
  time: number;
  cycle: number;
  running: boolean;
  paused: boolean;
  connected: boolean;
  mode: 'normal' | 'command' | 'help';
  commandBuffer?: string;
  width?: number;
}

export function StatusBar({
  time,
  cycle,
  running,
  paused,
  connected,
  mode,
  commandBuffer = '',
  width = 80
}: StatusBarProps) {
  // Determine status
  const status = running ? indicators.running : paused ? indicators.paused : indicators.stopped;
  const statusColor = running ? theme.primary : paused ? theme.amber : theme.textMuted;

  // Format cycle and time with fixed width
  const cycleStr = cycle.toString().padStart(6, '0');
  const timeStr = time.toString().padStart(8, '0');

  return (
    <Box flexDirection="column">
      {/* Command input line */}
      {mode === 'command' && (
        <Box>
          <Text color={theme.primary}>{box.arrowRight} </Text>
          <Text color={theme.amber}>{commandBuffer}</Text>
          <Text color={theme.primary}>█</Text>
        </Box>
      )}

      {/* Main status bar */}
      <Box>
        <Text color={theme.border}>{box.dHorizontal.repeat(width)}</Text>
      </Box>

      <Box justifyContent="space-between">
        {/* Left: Status and counters */}
        <Box>
          <Text color={theme.border}>{box.dVertical}</Text>
          <Text color={statusColor} bold> {status} </Text>
          <Text color={theme.border}>{box.vertical}</Text>
          <Text color={theme.textDim}> CYC:</Text>
          <Text color={theme.primary}>{cycleStr}</Text>
          <Text color={theme.border}> {box.vertical}</Text>
          <Text color={theme.textDim}> T:</Text>
          <Text color={theme.primary}>{timeStr}</Text>
          <Text color={theme.border}> {box.vertical}</Text>

          {/* Connection status LED */}
          <Text color={connected ? theme.primary : theme.error}>
            {' '}{box.circle}
          </Text>
          <Text color={theme.textDim}>
            {connected ? ' LINK' : ' DISC'}
          </Text>
        </Box>

        {/* Right: Mode indicator and key hints */}
        <Box>
          {mode === 'help' && (
            <Text color={theme.amber} bold>[HELP] </Text>
          )}
          {mode === 'command' && (
            <Text color={theme.primary} bold>[CMD] </Text>
          )}
          <Text color={theme.textMuted}>
            SPC:Step r:Run s:Stop h:Help q:Quit
          </Text>
          <Text color={theme.border}> {box.dVertical}</Text>
        </Box>
      </Box>

      <Box>
        <Text color={theme.border}>{box.dHorizontal.repeat(width)}</Text>
      </Box>
    </Box>
  );
}

// Compact LED-style status indicators
export function StatusLEDs({ running, paused, error }: { running: boolean; paused: boolean; error?: boolean }) {
  return (
    <Box>
      <Text color={running ? theme.primary : theme.textMuted}>{box.circle}</Text>
      <Text color={theme.textDim}> RUN </Text>
      <Text color={paused ? theme.amber : theme.textMuted}>{box.circle}</Text>
      <Text color={theme.textDim}> PSE </Text>
      {error !== undefined && (
        <>
          <Text color={error ? theme.error : theme.textMuted}>{box.circle}</Text>
          <Text color={theme.textDim}> ERR</Text>
        </>
      )}
    </Box>
  );
}
