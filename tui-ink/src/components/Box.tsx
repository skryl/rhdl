import React from 'react';
import { Box as InkBox, Text } from 'ink';
import { theme, box } from '../theme.js';

interface PanelProps {
  title: string;
  children: React.ReactNode;
  width?: number | string;
  height?: number | string;
  active?: boolean;
  variant?: 'single' | 'double' | 'mixed';
}

// SHENZHEN I/O style panel with box-drawing borders
export function Panel({
  title,
  children,
  width,
  height,
  active = false,
  variant = 'single'
}: PanelProps) {
  const borderColor = active ? theme.primary : theme.border;
  const titleColor = active ? theme.primaryBright : theme.primary;

  return (
    <InkBox flexDirection="column" width={width} height={height}>
      {/* Top border with title */}
      <InkBox>
        <Text color={borderColor}>
          {box.topLeft}{box.horizontal}{box.horizontal}
        </Text>
        <Text color={titleColor} bold>[</Text>
        <Text color={titleColor}> {title.toUpperCase()} </Text>
        <Text color={titleColor} bold>]</Text>
        <Text color={borderColor}>
          {box.horizontal.repeat(Math.max(0, (typeof width === 'number' ? width : 30) - title.length - 8))}
          {box.topRight}
        </Text>
      </InkBox>

      {/* Content area */}
      <InkBox flexDirection="column" flexGrow={1}>
        {children}
      </InkBox>

      {/* Bottom border */}
      <InkBox>
        <Text color={borderColor}>
          {box.bottomLeft}
          {box.horizontal.repeat(Math.max(0, (typeof width === 'number' ? width : 30) - 2))}
          {box.bottomRight}
        </Text>
      </InkBox>
    </InkBox>
  );
}

// Simple bordered box without title
interface BorderBoxProps {
  children: React.ReactNode;
  width?: number | string;
  active?: boolean;
}

export function BorderBox({ children, width, active = false }: BorderBoxProps) {
  return (
    <InkBox
      flexDirection="column"
      width={width}
      borderStyle="single"
      borderColor={active ? theme.primary : theme.border}
    >
      {children}
    </InkBox>
  );
}

// Horizontal divider line
export function Divider({ label }: { label?: string }) {
  if (label) {
    return (
      <InkBox>
        <Text color={theme.border}>{box.horizontal.repeat(2)}</Text>
        <Text color={theme.textDim}>[{label}]</Text>
        <Text color={theme.border}>{box.horizontal.repeat(20)}</Text>
      </InkBox>
    );
  }
  return <Text color={theme.border}>{box.horizontal.repeat(30)}</Text>;
}

// Section header with SHENZHEN I/O style
export function SectionHeader({ label }: { label: string }) {
  return (
    <InkBox>
      <Text color={theme.border}>{box.teeRight}{box.horizontal}</Text>
      <Text color={theme.amber} bold> {label.toUpperCase()} </Text>
      <Text color={theme.border}>{box.horizontal.repeat(15)}</Text>
    </InkBox>
  );
}

// LED indicator (on/off)
export function LED({ on, label }: { on: boolean; label?: string }) {
  return (
    <InkBox>
      <Text color={on ? theme.primary : theme.textMuted}>{box.circle}</Text>
      {label && <Text color={theme.textDim}> {label}</Text>}
    </InkBox>
  );
}

// Value display with label
export function ValueDisplay({ label, value, width = 8 }: { label: string; value: string | number; width?: number }) {
  const valStr = String(value).padStart(width, ' ');
  return (
    <InkBox>
      <Text color={theme.textDim}>{label}: </Text>
      <Text color={theme.primary} bold>{valStr}</Text>
    </InkBox>
  );
}
