import React from 'react';
import { Box, Text, useInput } from 'ink';
import { theme, box } from '../theme.js';
import type { Breakpoint, Watchpoint } from '../protocol.js';

interface BreakpointPanelProps {
  breakpoints: Breakpoint[];
  watchpoints: Watchpoint[];
  width?: number;
  height?: number;
  focused?: boolean;
  onDelete?: (id: number) => void;
}

export function BreakpointPanel({
  breakpoints,
  watchpoints,
  width = 35,
  height = 10,
  focused = false,
  onDelete
}: BreakpointPanelProps) {
  const [selectedIndex, setSelectedIndex] = React.useState(0);
  const allItems = [...breakpoints, ...watchpoints];
  const visibleHeight = height - 4;
  const borderColor = focused ? theme.primary : theme.border;
  const titleColor = focused ? theme.primaryBright : theme.primary;

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
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{box.topLeft}{box.horizontal}</Text>
        <Text color={titleColor} bold>[ BREAKS ]</Text>
        <Text color={borderColor}>{box.horizontal.repeat(width - 13)}{box.topRight}</Text>
      </Box>

      {/* Column headers */}
      <Box>
        <Text color={borderColor}>{box.vertical}</Text>
        <Text color={theme.textDim}> # </Text>
        <Text color={theme.border}>{box.vertical}</Text>
        <Text color={theme.textDim}> TYPE </Text>
        <Text color={theme.border}>{box.vertical}</Text>
        <Text color={theme.textDim}> CONDITION</Text>
        <Box flexGrow={1} />
        <Text color={borderColor}>{box.vertical}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {box.teeLeft}{box.horizontal.repeat(3)}{box.cross}
          {box.horizontal.repeat(6)}{box.cross}
          {box.horizontal.repeat(width - 13)}{box.teeRight}
        </Text>
      </Box>

      {/* Breakpoint list */}
      {allItems.length === 0 ? (
        <Box>
          <Text color={borderColor}>{box.vertical}</Text>
          <Text color={theme.textMuted}> No breakpoints set</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ) : (
        allItems.slice(0, visibleHeight).map((item, idx) => {
          const isSelected = idx === selectedIndex;
          const isWatchpoint = 'signal' in item;
          const typeLabel = isWatchpoint ? 'WATCH' : 'BREAK';
          const typeColor = isWatchpoint ? theme.amber : theme.error;
          const enabledChar = item.enabled ? box.circle : box.lightShade;

          // Truncate description
          const maxDescLen = width - 16;
          const desc = item.description.slice(0, maxDescLen);

          return (
            <Box key={`${isWatchpoint ? 'w' : 'b'}-${item.id}`}>
              <Text color={borderColor}>{box.vertical}</Text>
              <Text color={isSelected && focused ? theme.primaryBright : theme.primary}>
                {isSelected ? box.arrowRight : ' '}
              </Text>
              <Text color={item.enabled ? theme.primary : theme.textMuted}>
                {item.id.toString().padStart(2)}
              </Text>
              <Text color={theme.border}>{box.vertical}</Text>
              <Text color={typeColor}>{typeLabel}</Text>
              <Text color={theme.border}>{box.vertical}</Text>
              <Text color={theme.textDim}> {desc}</Text>
              <Box flexGrow={1} />
              <Text color={item.enabled ? theme.primary : theme.textMuted}>
                {enabledChar}
              </Text>
              <Text color={borderColor}>{box.vertical}</Text>
            </Box>
          );
        })
      )}

      {/* Fill remaining space */}
      {Array.from({ length: Math.max(0, visibleHeight - allItems.length) }).map((_, i) => (
        <Box key={`empty-${i}`}>
          <Text color={borderColor}>{box.vertical}</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ))}

      {/* Footer with hints */}
      <Box>
        <Text color={borderColor}>
          {box.bottomLeft}{box.horizontal}
        </Text>
        <Text color={theme.textMuted}> d:Del b:Add </Text>
        <Text color={borderColor}>
          {box.horizontal.repeat(Math.max(0, width - 15))}{box.bottomRight}
        </Text>
      </Box>
    </Box>
  );
}
