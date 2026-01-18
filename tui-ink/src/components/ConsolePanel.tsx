import React from 'react';
import { Box, Text } from 'ink';
import { theme, box } from '../theme.js';
import type { LogEntry } from '../hooks/useSimulator.js';

interface ConsolePanelProps {
  logs: LogEntry[];
  width?: number;
  height?: number;
  focused?: boolean;
}

const LEVEL_COLORS: Record<string, string> = {
  info: theme.primary,
  success: theme.primary,
  warning: theme.amber,
  error: theme.error,
  debug: theme.textDim,
};

const LEVEL_PREFIX: Record<string, string> = {
  info: '[INF]',
  success: '[OK ]',
  warning: '[WRN]',
  error: '[ERR]',
  debug: '[DBG]',
};

export function ConsolePanel({ logs, width = 50, height = 10, focused = false }: ConsolePanelProps) {
  const visibleHeight = height - 3;
  const visibleLogs = logs.slice(-visibleHeight);
  const borderColor = focused ? theme.primary : theme.border;
  const titleColor = focused ? theme.primaryBright : theme.primary;

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{box.topLeft}{box.horizontal}</Text>
        <Text color={titleColor} bold>[ CONSOLE ]</Text>
        <Text color={borderColor}>{box.horizontal.repeat(width - 15)}{box.topRight}</Text>
      </Box>

      {/* Log messages */}
      {logs.length === 0 ? (
        <Box>
          <Text color={borderColor}>{box.vertical}</Text>
          <Text color={theme.textMuted}> System ready.</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ) : (
        visibleLogs.map((log) => {
          const prefix = LEVEL_PREFIX[log.level] || '[---]';
          const color = LEVEL_COLORS[log.level] || theme.textDim;
          const maxMsgLen = width - prefix.length - 5;
          const msg = log.message.length > maxMsgLen
            ? log.message.slice(0, maxMsgLen - 2) + '..'
            : log.message;

          return (
            <Box key={log.id}>
              <Text color={borderColor}>{box.vertical}</Text>
              <Text color={theme.textDim}> {prefix}</Text>
              <Text color={color}> {msg}</Text>
              <Box flexGrow={1} />
              <Text color={borderColor}>{box.vertical}</Text>
            </Box>
          );
        })
      )}

      {/* Fill remaining space */}
      {Array.from({ length: Math.max(0, visibleHeight - visibleLogs.length - 1) }).map((_, i) => (
        <Box key={`empty-${i}`}>
          <Text color={borderColor}>{box.vertical}</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ))}

      {/* Footer with line count */}
      <Box>
        <Text color={borderColor}>
          {box.bottomLeft}{box.horizontal.repeat(2)}
        </Text>
        <Text color={theme.textMuted}>[{logs.length} lines]</Text>
        <Text color={borderColor}>
          {box.horizontal.repeat(Math.max(0, width - 14))}{box.bottomRight}
        </Text>
      </Box>
    </Box>
  );
}
