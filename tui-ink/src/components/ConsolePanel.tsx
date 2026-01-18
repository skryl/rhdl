import React, { useEffect, useRef } from 'react';
import { Box, Text } from 'ink';
import { Panel } from './Box.js';
import type { LogEntry } from '../hooks/useSimulator.js';

interface ConsolePanelProps {
  logs: LogEntry[];
  height?: number;
  focused?: boolean;
}

const LEVEL_COLORS: Record<string, string> = {
  info: 'white',
  success: 'green',
  warning: 'yellow',
  error: 'red',
  debug: 'gray',
};

const LEVEL_ICONS: Record<string, string> = {
  info: 'ℹ',
  success: '✓',
  warning: '⚠',
  error: '✗',
  debug: '·',
};

export function ConsolePanel({ logs, height = 10, focused = false }: ConsolePanelProps) {
  const visibleHeight = height - 3;
  const visibleLogs = logs.slice(-visibleHeight);

  return (
    <Panel title="Console" height={height} borderColor={focused ? 'cyan' : 'gray'}>
      {logs.length === 0 ? (
        <Text dimColor>No messages</Text>
      ) : (
        visibleLogs.map((log) => (
          <Box key={log.id}>
            <Text color={LEVEL_COLORS[log.level]}>
              {LEVEL_ICONS[log.level]} {log.message}
            </Text>
          </Box>
        ))
      )}
    </Panel>
  );
}
