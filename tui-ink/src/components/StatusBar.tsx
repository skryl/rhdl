import React from 'react';
import { Box, Text } from 'ink';

interface StatusBarProps {
  time: number;
  cycle: number;
  running: boolean;
  paused: boolean;
  connected: boolean;
  mode: 'normal' | 'command' | 'help';
  commandBuffer?: string;
}

export function StatusBar({
  time,
  cycle,
  running,
  paused,
  connected,
  mode,
  commandBuffer = ''
}: StatusBarProps) {
  const statusColor = running ? 'green' : paused ? 'yellow' : 'gray';
  const statusText = running ? '▶ RUNNING' : paused ? '⏸ PAUSED' : '⏹ STOPPED';

  return (
    <Box flexDirection="column">
      {mode === 'command' && (
        <Box>
          <Text color="cyan">:</Text>
          <Text>{commandBuffer}</Text>
          <Text color="cyan">_</Text>
        </Box>
      )}
      <Box
        paddingX={1}
        justifyContent="space-between"
      >
        <Box>
          <Text color={statusColor} bold>{statusText}</Text>
          <Text dimColor> │ </Text>
          <Text>T:{time}</Text>
          <Text dimColor> </Text>
          <Text>C:{cycle}</Text>
          {!connected && (
            <>
              <Text dimColor> │ </Text>
              <Text color="red">DISCONNECTED</Text>
            </>
          )}
        </Box>
        <Box>
          {mode === 'help' && <Text color="magenta">[HELP] </Text>}
          {mode === 'command' && <Text color="cyan">[CMD] </Text>}
          <Text dimColor>h:Help q:Quit Space:Step r:Run s:Stop</Text>
        </Box>
      </Box>
    </Box>
  );
}
