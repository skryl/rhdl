import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { theme, box } from '../theme.js';
import type { Signal } from '../protocol.js';

interface SignalPanelProps {
  signals: Signal[];
  width?: number;
  height?: number;
  focused?: boolean;
  onSelect?: (signal: Signal) => void;
}

// Format hex value with proper width
function formatHex(value: number, width: number): string {
  const hexDigits = Math.ceil(width / 4);
  return value.toString(16).toUpperCase().padStart(hexDigits, '0');
}

export function SignalPanel({ signals, width = 40, height = 15, focused = false, onSelect }: SignalPanelProps) {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [scrollOffset, setScrollOffset] = useState(0);

  const visibleHeight = height - 4; // Account for header, borders
  const maxScroll = Math.max(0, signals.length - visibleHeight);
  const contentWidth = width - 4;

  useInput((input, key) => {
    if (!focused) return;

    if (key.upArrow || input === 'k') {
      setSelectedIndex(prev => {
        const next = Math.max(0, prev - 1);
        if (next < scrollOffset) {
          setScrollOffset(next);
        }
        return next;
      });
    } else if (key.downArrow || input === 'j') {
      setSelectedIndex(prev => {
        const next = Math.min(signals.length - 1, prev + 1);
        if (next >= scrollOffset + visibleHeight) {
          setScrollOffset(Math.min(maxScroll, scrollOffset + 1));
        }
        return next;
      });
    } else if (key.return && onSelect && signals[selectedIndex]) {
      onSelect(signals[selectedIndex]);
    }
  });

  const visibleSignals = signals.slice(scrollOffset, scrollOffset + visibleHeight);
  const borderColor = focused ? theme.primary : theme.border;
  const titleColor = focused ? theme.primaryBright : theme.primary;

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{box.topLeft}{box.horizontal}</Text>
        <Text color={titleColor} bold>[ SIGNALS ]</Text>
        <Text color={borderColor}>{box.horizontal.repeat(width - 15)}{box.topRight}</Text>
      </Box>

      {/* Column headers */}
      <Box>
        <Text color={borderColor}>{box.vertical}</Text>
        <Text color={theme.textDim}> </Text>
        <Box width={16}><Text color={theme.textDim}>NAME</Text></Box>
        <Text color={theme.border}>{box.vertical}</Text>
        <Box width={10}><Text color={theme.textDim}> VALUE</Text></Box>
        <Text color={theme.border}>{box.vertical}</Text>
        <Box width={4}><Text color={theme.textDim}>W</Text></Box>
        <Text color={borderColor}>{box.vertical}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {box.teeLeft}{box.horizontal.repeat(17)}{box.cross}
          {box.horizontal.repeat(11)}{box.cross}
          {box.horizontal.repeat(4)}{box.teeRight}
        </Text>
      </Box>

      {/* Signal list */}
      {signals.length === 0 ? (
        <Box>
          <Text color={borderColor}>{box.vertical}</Text>
          <Text color={theme.textMuted}> No signals probed</Text>
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ) : (
        visibleSignals.map((signal, idx) => {
          const actualIndex = scrollOffset + idx;
          const isSelected = actualIndex === selectedIndex;
          const hex = formatHex(signal.value, signal.width);
          const indicator = isSelected ? box.arrowRight : ' ';

          return (
            <Box key={signal.name}>
              <Text color={borderColor}>{box.vertical}</Text>
              <Text color={isSelected && focused ? theme.primaryBright : theme.primary}>
                {indicator}
              </Text>
              <Box width={15}>
                <Text color={isSelected && focused ? theme.primaryBright : theme.primary}>
                  {signal.name.slice(-14)}
                </Text>
              </Box>
              <Text color={theme.border}>{box.vertical}</Text>
              <Box width={10}>
                <Text color={theme.amber} bold> 0x{hex}</Text>
              </Box>
              <Text color={theme.border}>{box.vertical}</Text>
              <Box width={4}>
                <Text color={theme.textDim}>{signal.width.toString().padStart(2)}</Text>
              </Box>
              <Text color={borderColor}>{box.vertical}</Text>
            </Box>
          );
        })
      )}

      {/* Scroll indicator */}
      {signals.length > visibleHeight && (
        <Box>
          <Text color={borderColor}>{box.vertical}</Text>
          <Text color={theme.textMuted}>
            {' '}[{scrollOffset + 1}-{Math.min(scrollOffset + visibleHeight, signals.length)}/{signals.length}]
          </Text>
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      )}

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {box.bottomLeft}{box.horizontal.repeat(width - 2)}{box.bottomRight}
        </Text>
      </Box>
    </Box>
  );
}
