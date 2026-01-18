import React from 'react';
import { Box, Text } from 'ink';
import { theme, box } from '../theme.js';
import type { Signal } from '../protocol.js';

interface RegisterViewProps {
  signals: Signal[];
  title?: string;
  active?: boolean;
}

// Format value as hex with leading zeros
function formatHex(value: number, width: number): string {
  const hexDigits = Math.ceil(width / 4);
  return value.toString(16).toUpperCase().padStart(hexDigits, '0');
}

// Format value as binary with groups of 4
function formatBinary(value: number, width: number): string {
  const bin = value.toString(2).padStart(width, '0');
  // Group by 4 bits
  const groups = [];
  for (let i = 0; i < bin.length; i += 4) {
    groups.push(bin.slice(i, i + 4));
  }
  return groups.join(' ');
}

// Single register row
function RegisterRow({ signal, showBinary = false }: { signal: Signal; showBinary?: boolean }) {
  const hex = formatHex(signal.value, signal.width);
  const binary = showBinary ? formatBinary(signal.value, signal.width) : null;

  return (
    <Box>
      <Box width={14}>
        <Text color={theme.textDim}>{signal.name.slice(-12).padEnd(12)}</Text>
      </Box>
      <Text color={theme.border}>{box.vertical}</Text>
      <Box width={10}>
        <Text color={theme.primary} bold> 0x{hex} </Text>
      </Box>
      <Text color={theme.border}>{box.vertical}</Text>
      <Box width={6}>
        <Text color={theme.amber}> {signal.value.toString().padStart(4)} </Text>
      </Box>
      {binary && (
        <>
          <Text color={theme.border}>{box.vertical}</Text>
          <Text color={theme.textDim}> {binary}</Text>
        </>
      )}
    </Box>
  );
}

// SHENZHEN I/O style register view
export function RegisterView({ signals, title = 'REGISTERS', active = false }: RegisterViewProps) {
  const borderColor = active ? theme.primary : theme.border;
  const titleColor = active ? theme.primaryBright : theme.primary;

  // Separate by width (1-bit vs multi-bit)
  const flags = signals.filter(s => s.width === 1);
  const regs = signals.filter(s => s.width > 1);

  return (
    <Box flexDirection="column">
      {/* Header */}
      <Box>
        <Text color={borderColor}>{box.topLeft}{box.horizontal}</Text>
        <Text color={titleColor} bold>[ {title} ]</Text>
        <Text color={borderColor}>{box.horizontal.repeat(25)}{box.topRight}</Text>
      </Box>

      {/* Column headers */}
      <Box>
        <Text color={borderColor}>{box.vertical}</Text>
        <Box width={14}>
          <Text color={theme.textDim}> NAME</Text>
        </Box>
        <Text color={theme.border}>{box.vertical}</Text>
        <Box width={10}>
          <Text color={theme.textDim}> HEX</Text>
        </Box>
        <Text color={theme.border}>{box.vertical}</Text>
        <Box width={6}>
          <Text color={theme.textDim}> DEC</Text>
        </Box>
        <Text color={borderColor}>{box.vertical}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {box.teeLeft}{box.horizontal.repeat(14)}{box.cross}
          {box.horizontal.repeat(10)}{box.cross}
          {box.horizontal.repeat(6)}{box.teeRight}
        </Text>
      </Box>

      {/* Multi-bit registers */}
      {regs.map((signal) => (
        <Box key={signal.name}>
          <Text color={borderColor}>{box.vertical}</Text>
          <RegisterRow signal={signal} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ))}

      {/* Flags section if any */}
      {flags.length > 0 && (
        <>
          <Box>
            <Text color={borderColor}>
              {box.teeLeft}{box.horizontal}{box.horizontal}
            </Text>
            <Text color={theme.amber}>[ FLAGS ]</Text>
            <Text color={borderColor}>{box.horizontal.repeat(18)}{box.teeRight}</Text>
          </Box>
          <Box>
            <Text color={borderColor}>{box.vertical} </Text>
            {flags.map((flag, i) => (
              <React.Fragment key={flag.name}>
                <Text color={flag.value ? theme.primary : theme.textMuted}>
                  {flag.name.slice(-3).toUpperCase()}
                </Text>
                <Text color={flag.value ? theme.primary : theme.textMuted}>
                  :{flag.value ? '1' : '0'}
                </Text>
                {i < flags.length - 1 && <Text color={theme.border}> </Text>}
              </React.Fragment>
            ))}
            <Text color={borderColor}> {box.vertical}</Text>
          </Box>
        </>
      )}

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {box.bottomLeft}{box.horizontal.repeat(32)}{box.bottomRight}
        </Text>
      </Box>
    </Box>
  );
}

// Compact single-line register display
export function RegisterCompact({ signal }: { signal: Signal }) {
  const hex = formatHex(signal.value, signal.width);
  return (
    <Box>
      <Text color={theme.textDim}>{signal.name.slice(-6)}</Text>
      <Text color={theme.border}>:</Text>
      <Text color={theme.primary} bold>{hex}</Text>
    </Box>
  );
}

// Memory-style hex dump display
interface MemoryViewProps {
  address: number;
  data: number[];
  bytesPerRow?: number;
}

export function MemoryView({ address, data, bytesPerRow = 8 }: MemoryViewProps) {
  const rows = [];
  for (let i = 0; i < data.length; i += bytesPerRow) {
    rows.push(data.slice(i, i + bytesPerRow));
  }

  return (
    <Box flexDirection="column">
      {rows.map((row, rowIdx) => {
        const addr = address + rowIdx * bytesPerRow;
        const addrHex = addr.toString(16).toUpperCase().padStart(4, '0');
        const hexValues = row.map(b => b.toString(16).toUpperCase().padStart(2, '0')).join(' ');
        const ascii = row.map(b => (b >= 0x20 && b < 0x7f) ? String.fromCharCode(b) : '.').join('');

        return (
          <Box key={addr}>
            <Text color={theme.amber}>{addrHex}</Text>
            <Text color={theme.border}>: </Text>
            <Text color={theme.primary}>{hexValues.padEnd(bytesPerRow * 3 - 1)}</Text>
            <Text color={theme.border}> {box.vertical} </Text>
            <Text color={theme.textDim}>{ascii}</Text>
          </Box>
        );
      })}
    </Box>
  );
}
