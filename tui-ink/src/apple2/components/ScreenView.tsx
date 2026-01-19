import React from 'react';
import { Box, Text } from 'ink';
import { apple2Theme, apple2Chars, APPLE2_COLS, APPLE2_ROWS } from '../theme.js';
import type { ScreenData } from '../protocol.js';
import { apple2CharToAscii } from '../protocol.js';

interface ScreenViewProps {
  screen: ScreenData | null;
  focused?: boolean;
  showBorder?: boolean;
  cursorPos?: { row: number; col: number };
}

// Apple II 40-column text display
export function ScreenView({ screen, focused = false, showBorder = true, cursorPos }: ScreenViewProps) {
  const borderColor = focused ? apple2Theme.phosphor : apple2Theme.border;

  // Generate empty screen if no data
  const rows = screen?.rows ?? Array(APPLE2_ROWS).fill(null).map(() =>
    Array(APPLE2_COLS).fill(0xA0) // Space with high bit
  );

  return (
    <Box flexDirection="column">
      {/* Top border */}
      {showBorder && (
        <Box>
          <Text color={borderColor}>
            {apple2Chars.boxTL}
            {apple2Chars.boxH.repeat(APPLE2_COLS)}
            {apple2Chars.boxTR}
          </Text>
        </Box>
      )}

      {/* Screen content */}
      {rows.map((row, rowIdx) => (
        <Box key={rowIdx}>
          {showBorder && <Text color={borderColor}>{apple2Chars.boxV}</Text>}
          {row.map((charCode: number, colIdx: number) => {
            const char = apple2CharToAscii(charCode);
            const isInverse = (charCode & 0x80) === 0; // Low bit = inverse
            const isCursor = cursorPos?.row === rowIdx && cursorPos?.col === colIdx;

            if (isCursor) {
              return (
                <Text key={colIdx} color={apple2Theme.bg} backgroundColor={apple2Theme.phosphor}>
                  {char}
                </Text>
              );
            }

            if (isInverse) {
              return (
                <Text key={colIdx} color={apple2Theme.bg} backgroundColor={apple2Theme.phosphor}>
                  {char}
                </Text>
              );
            }

            return (
              <Text key={colIdx} color={apple2Theme.phosphor}>
                {char}
              </Text>
            );
          })}
          {showBorder && <Text color={borderColor}>{apple2Chars.boxV}</Text>}
        </Box>
      ))}

      {/* Bottom border */}
      {showBorder && (
        <Box>
          <Text color={borderColor}>
            {apple2Chars.boxBL}
            {apple2Chars.boxH.repeat(APPLE2_COLS)}
            {apple2Chars.boxBR}
          </Text>
        </Box>
      )}
    </Box>
  );
}

// Compact screen with title
interface ScreenPanelProps extends ScreenViewProps {
  title?: string;
}

export function ScreenPanel({ title = 'DISPLAY', ...props }: ScreenPanelProps) {
  const borderColor = props.focused ? apple2Theme.phosphor : apple2Theme.border;

  return (
    <Box flexDirection="column">
      {/* Header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxTL}{apple2Chars.boxH}</Text>
        <Text color={apple2Theme.phosphor} bold>[ {title} ]</Text>
        <Text color={borderColor}>
          {apple2Chars.boxH.repeat(APPLE2_COLS - title.length - 4)}
          {apple2Chars.boxTR}
        </Text>
      </Box>

      {/* Screen content with side borders only */}
      <ScreenView {...props} showBorder={false} />

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxBL}
          {apple2Chars.boxH.repeat(APPLE2_COLS)}
          {apple2Chars.boxBR}
        </Text>
      </Box>
    </Box>
  );
}
