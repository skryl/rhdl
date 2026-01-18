import React from 'react';
import { Box as InkBox, Text } from 'ink';

interface PanelProps {
  title: string;
  children: React.ReactNode;
  width?: number | string;
  height?: number | string;
  borderColor?: string;
}

// Panel component with border and title
export function Panel({ title, children, width, height, borderColor = 'gray' }: PanelProps) {
  return (
    <InkBox
      flexDirection="column"
      width={width}
      height={height}
      borderStyle="single"
      borderColor={borderColor}
    >
      <InkBox marginLeft={1}>
        <Text bold color="cyan">{title}</Text>
      </InkBox>
      <InkBox flexDirection="column" paddingX={1}>
        {children}
      </InkBox>
    </InkBox>
  );
}

// Horizontal divider
export function Divider({ char = '─' }: { char?: string }) {
  return (
    <Text dimColor>{char.repeat(40)}</Text>
  );
}
