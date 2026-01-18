import React from 'react';
import { Box, Text, useInput } from 'ink';
import { Panel } from './Box.js';
import type { Breakpoint, Watchpoint } from '../protocol.js';

interface BreakpointPanelProps {
  breakpoints: Breakpoint[];
  watchpoints: Watchpoint[];
  height?: number;
  focused?: boolean;
  onDelete?: (id: number) => void;
}

export function BreakpointPanel({
  breakpoints,
  watchpoints,
  height = 10,
  focused = false,
  onDelete
}: BreakpointPanelProps) {
  const [selectedIndex, setSelectedIndex] = React.useState(0);
  const allItems = [...breakpoints, ...watchpoints];

  useInput((input, key) => {
    if (!focused) return;

    if (key.upArrow || input === 'k') {
      setSelectedIndex(prev => Math.max(0, prev - 1));
    } else if (key.downArrow || input === 'j') {
      setSelectedIndex(prev => Math.min(allItems.length - 1, prev + 1));
    } else if ((input === 'd' || key.delete) && onDelete && allItems[selectedIndex]) {
      onDelete(allItems[selectedIndex].id);
    }
  });

  return (
    <Panel title="Breakpoints" height={height} borderColor={focused ? 'cyan' : 'gray'}>
      {allItems.length === 0 ? (
        <Text dimColor>No breakpoints</Text>
      ) : (
        <>
          {allItems.map((item, idx) => {
            const isSelected = idx === selectedIndex;
            const isWatchpoint = 'signal' in item;
            const icon = isWatchpoint ? '👁' : '●';
            const color = item.enabled ? (isWatchpoint ? 'magenta' : 'red') : 'gray';

            return (
              <Box key={`${isWatchpoint ? 'w' : 'b'}-${item.id}`}>
                <Text inverse={isSelected && focused}>
                  <Text color={color}>{icon}</Text>
                  <Text dimColor> #{item.id} </Text>
                  <Text>{item.description.slice(0, 25)}</Text>
                  {item.hit_count > 0 && (
                    <Text dimColor> ({item.hit_count})</Text>
                  )}
                </Text>
              </Box>
            );
          })}
          <Box marginTop={1}>
            <Text dimColor>d: delete</Text>
          </Box>
        </>
      )}
    </Panel>
  );
}
