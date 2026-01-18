import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { apple2Theme, apple2Chars, MEMORY_REGIONS } from '../theme.js';
import type { MemoryDump } from '../protocol.js';
import { formatHex8, formatHex16 } from '../protocol.js';

interface MemoryViewProps {
  memory: MemoryDump | null;
  width?: number;
  height?: number;
  focused?: boolean;
  onAddressChange?: (address: number) => void;
}

const BYTES_PER_ROW = 8;

// Memory hex dump display
export function MemoryView({
  memory,
  width = 45,
  height = 12,
  focused = false,
  onAddressChange
}: MemoryViewProps) {
  const borderColor = focused ? apple2Theme.phosphor : apple2Theme.border;
  const visibleRows = height - 4;

  const bytes = memory?.bytes ?? [];
  const baseAddress = memory?.address ?? 0;

  // Calculate rows of memory to display
  const rows: { address: number; bytes: number[]; ascii: string }[] = [];
  for (let i = 0; i < bytes.length; i += BYTES_PER_ROW) {
    const rowBytes = bytes.slice(i, i + BYTES_PER_ROW);
    const ascii = rowBytes.map(b =>
      (b >= 0x20 && b < 0x7F) ? String.fromCharCode(b) : '.'
    ).join('');
    rows.push({
      address: baseAddress + i,
      bytes: rowBytes,
      ascii
    });
  }

  const displayRows = rows.slice(0, visibleRows);

  // Determine which memory region we're in
  const regionName = Object.values(MEMORY_REGIONS).find(
    r => baseAddress >= r.start && baseAddress <= r.end
  )?.name ?? 'Memory';

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxTL}{apple2Chars.boxH}</Text>
        <Text color={apple2Theme.phosphor} bold>[ MEMORY: {regionName.toUpperCase()} ]</Text>
        <Text color={borderColor}>
          {apple2Chars.boxH.repeat(Math.max(0, width - regionName.length - 14))}
          {apple2Chars.boxTR}
        </Text>
      </Box>

      {/* Column headers */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV}</Text>
        <Text color={apple2Theme.textDim}> ADDR  </Text>
        {Array.from({ length: BYTES_PER_ROW }).map((_, i) => (
          <Text key={i} color={apple2Theme.textDim}>{formatHex8(i)} </Text>
        ))}
        <Text color={apple2Theme.textDim}>ASCII</Text>
        <Text color={borderColor}>{apple2Chars.boxV}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxTeeL}{apple2Chars.boxH.repeat(width - 2)}{apple2Chars.boxTeeR}
        </Text>
      </Box>

      {/* Memory rows */}
      {displayRows.length === 0 ? (
        <Box>
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
          <Text color={apple2Theme.textMuted}> No memory data</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
        </Box>
      ) : (
        displayRows.map((row, idx) => (
          <Box key={idx}>
            <Text color={borderColor}>{apple2Chars.boxV}</Text>
            <Text color={apple2Theme.phosphorDim}>${formatHex16(row.address)} </Text>
            {row.bytes.map((byte, byteIdx) => (
              <Text key={byteIdx} color={apple2Theme.phosphor}>
                {formatHex8(byte)}{' '}
              </Text>
            ))}
            {/* Pad if row is short */}
            {row.bytes.length < BYTES_PER_ROW && (
              <Text color={apple2Theme.textMuted}>
                {'   '.repeat(BYTES_PER_ROW - row.bytes.length)}
              </Text>
            )}
            <Text color={apple2Theme.textDim}>{row.ascii}</Text>
            <Text color={borderColor}>{apple2Chars.boxV}</Text>
          </Box>
        ))
      )}

      {/* Fill empty rows */}
      {Array.from({ length: Math.max(0, visibleRows - displayRows.length) }).map((_, i) => (
        <Box key={`empty-${i}`}>
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
        </Box>
      ))}

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxBL}
          {apple2Chars.boxH.repeat(width - 2)}
          {apple2Chars.boxBR}
        </Text>
      </Box>
    </Box>
  );
}

// Memory region selector
interface MemoryRegionSelectorProps {
  onSelect: (address: number) => void;
  focused?: boolean;
}

export function MemoryRegionSelector({ onSelect, focused = false }: MemoryRegionSelectorProps) {
  const [selectedIdx, setSelectedIdx] = useState(0);
  const regions = Object.values(MEMORY_REGIONS);

  useInput((input, key) => {
    if (!focused) return;

    if (key.upArrow || input === 'k') {
      setSelectedIdx(prev => Math.max(0, prev - 1));
    } else if (key.downArrow || input === 'j') {
      setSelectedIdx(prev => Math.min(regions.length - 1, prev + 1));
    } else if (key.return) {
      onSelect(regions[selectedIdx].start);
    }
  });

  return (
    <Box flexDirection="column">
      <Text color={apple2Theme.phosphor} bold>Memory Regions:</Text>
      {regions.map((region, idx) => (
        <Box key={region.name}>
          <Text color={idx === selectedIdx && focused ? apple2Theme.phosphorBright : apple2Theme.textDim}>
            {idx === selectedIdx ? '>' : ' '} ${formatHex16(region.start)}-${formatHex16(region.end)} {region.name}
          </Text>
        </Box>
      ))}
    </Box>
  );
}
