import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { Panel } from './Box.js';
import type { Signal } from '../protocol.js';

interface SignalPanelProps {
  signals: Signal[];
  height?: number;
  focused?: boolean;
  onSelect?: (signal: Signal) => void;
}

export function SignalPanel({ signals, height = 15, focused = false, onSelect }: SignalPanelProps) {
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [scrollOffset, setScrollOffset] = useState(0);

  const visibleHeight = height - 3; // Account for border and title
  const maxScroll = Math.max(0, signals.length - visibleHeight);

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

  return (
    <Panel title="Signals" height={height} borderColor={focused ? 'cyan' : 'gray'}>
      {signals.length === 0 ? (
        <Text dimColor>No signals</Text>
      ) : (
        <>
          {visibleSignals.map((signal, idx) => {
            const actualIndex = scrollOffset + idx;
            const isSelected = actualIndex === selectedIndex;

            return (
              <Box key={signal.name}>
                <Text
                  inverse={isSelected && focused}
                  color={isSelected && focused ? 'cyan' : undefined}
                >
                  <Text dimColor>{isSelected ? '>' : ' '} </Text>
                  <Text bold>{signal.name.padEnd(20)}</Text>
                  <Text color="yellow">{signal.hex.padStart(10)}</Text>
                  <Text dimColor> ({signal.width}b)</Text>
                </Text>
              </Box>
            );
          })}
          {signals.length > visibleHeight && (
            <Box marginTop={1}>
              <Text dimColor>
                [{scrollOffset + 1}-{Math.min(scrollOffset + visibleHeight, signals.length)}/{signals.length}]
              </Text>
            </Box>
          )}
        </>
      )}
    </Panel>
  );
}
