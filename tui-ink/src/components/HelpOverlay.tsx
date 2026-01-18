import React from 'react';
import { Box, Text } from 'ink';
import { theme, box } from '../theme.js';

interface HelpOverlayProps {
  onClose: () => void;
}

export function HelpOverlay({ onClose }: HelpOverlayProps) {
  const width = 60;

  return (
    <Box flexDirection="column">
      {/* Header */}
      <Box>
        <Text color={theme.primary}>
          {box.dTopLeft}{box.dHorizontal.repeat(width - 2)}{box.dTopRight}
        </Text>
      </Box>
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Box width={width - 4} justifyContent="center">
          <Text color={theme.primaryBright} bold>
            {'▄▄▄▄  ██  ██ ██████  ██      '}
          </Text>
        </Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Box width={width - 4} justifyContent="center">
          <Text color={theme.primaryBright} bold>
            {'█   █ █▄▄▄█ █    █ █       '}
          </Text>
        </Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Box width={width - 4} justifyContent="center">
          <Text color={theme.primaryBright} bold>
            {'█▄▄▄▀ █   █ █▄▄▄▄█ █▄▄▄▄▄  '}
          </Text>
        </Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>
      <Box>
        <Text color={theme.primary}>
          {box.dVertical}{box.horizontal.repeat(width - 2)}{box.dVertical}
        </Text>
      </Box>

      {/* Keyboard section */}
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Text color={theme.amber} bold> KEYBOARD </Text>
        <Text color={theme.border}>{box.horizontal.repeat(width - 13)}</Text>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>

      {[
        ['SPC', 'Step one cycle'],
        ['n', 'Step half cycle'],
        ['r', 'Run simulation'],
        ['s', 'Stop simulation'],
        ['R', 'Reset simulation'],
        ['c', 'Continue to breakpoint'],
        ['b', 'Add breakpoint'],
        ['w', 'Add watchpoint'],
        ['j/k', 'Navigate up/down'],
        ['TAB', 'Switch panel'],
        [':', 'Command mode'],
        ['h', 'This help'],
        ['q', 'Quit'],
      ].map(([key, desc]) => (
        <Box key={key}>
          <Text color={theme.primary}>{box.dVertical} </Text>
          <Box width={8}>
            <Text color={theme.amber}>{key.padEnd(6)}</Text>
          </Box>
          <Text color={theme.textDim}>{desc}</Text>
          <Box flexGrow={1} />
          <Text color={theme.primary}>{box.dVertical}</Text>
        </Box>
      ))}

      {/* Commands section */}
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Text color={theme.amber} bold> COMMANDS </Text>
        <Text color={theme.border}>{box.horizontal.repeat(width - 13)}</Text>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>

      {[
        ['run [n]', 'Execute n cycles'],
        ['step', 'Single step'],
        ['break [cyc]', 'Set breakpoint'],
        ['watch sig', 'Watch signal'],
        ['set sig val', 'Set signal value'],
        ['print sig', 'Print signal'],
        ['export file', 'Export VCD'],
        ['clear', 'Clear logs/breaks'],
      ].map(([cmd, desc]) => (
        <Box key={cmd}>
          <Text color={theme.primary}>{box.dVertical} </Text>
          <Box width={14}>
            <Text color={theme.primary}>{cmd}</Text>
          </Box>
          <Text color={theme.textDim}>{desc}</Text>
          <Box flexGrow={1} />
          <Text color={theme.primary}>{box.dVertical}</Text>
        </Box>
      ))}

      {/* Footer */}
      <Box>
        <Text color={theme.primary}>
          {box.dVertical}{box.horizontal.repeat(width - 2)}{box.dVertical}
        </Text>
      </Box>
      <Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
        <Box width={width - 4} justifyContent="center">
          <Text color={theme.textMuted}>Press any key to close</Text>
        </Box>
        <Text color={theme.primary}>{box.dVertical}</Text>
      </Box>
      <Box>
        <Text color={theme.primary}>
          {box.dBottomLeft}{box.dHorizontal.repeat(width - 2)}{box.dBottomRight}
        </Text>
      </Box>
    </Box>
  );
}
