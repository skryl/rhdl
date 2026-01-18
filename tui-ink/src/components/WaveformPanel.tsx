import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { theme, box } from '../theme.js';
import type { WaveformProbe } from '../protocol.js';

interface WaveformPanelProps {
  waveforms: WaveformProbe[];
  width?: number;
  height?: number;
  focused?: boolean;
  timeScale?: number;
}

// Oscilloscope-style waveform characters
const WAVE = {
  high: '▔',      // High level
  low: '▁',       // Low level
  rising: '╱',    // Rising edge
  falling: '╲',   // Falling edge
  mid: '─',       // Mid level for multi-bit
  change: '┃',    // Value change marker
  gridDot: '·',   // Grid dots
  gridLine: '┊',  // Grid line
};

// Render digital waveform for oscilloscope display
function renderWaveform(probe: WaveformProbe, width: number): string[] {
  if (probe.samples.length === 0) {
    return [' '.repeat(width), ' '.repeat(width)];
  }

  const samples = probe.samples;
  const startTime = samples[0]?.time ?? 0;
  const endTime = samples[samples.length - 1]?.time ?? startTime;
  const timeRange = Math.max(1, endTime - startTime);

  let topLine = '';
  let botLine = '';
  let prevValue: number | null = null;

  for (let i = 0; i < width; i++) {
    const t = startTime + (i / width) * timeRange;
    let sampleValue = 0;
    for (const sample of samples) {
      if (sample.time <= t) {
        sampleValue = sample.value;
      } else {
        break;
      }
    }

    // Grid dots every 8 characters
    const isGrid = i % 8 === 0;

    if (probe.width === 1) {
      // Single-bit digital waveform
      const high = sampleValue === 1;
      const changed = prevValue !== null && prevValue !== sampleValue;

      if (changed) {
        topLine += high ? '╭' : '╮';
        botLine += high ? '╯' : '╰';
      } else if (high) {
        topLine += '─';
        botLine += isGrid ? '·' : ' ';
      } else {
        topLine += isGrid ? '·' : ' ';
        botLine += '─';
      }
    } else {
      // Multi-bit value display
      const changed = prevValue !== null && prevValue !== sampleValue;
      topLine += changed ? '╳' : '═';
      botLine += changed ? '╳' : '═';
    }

    prevValue = sampleValue;
  }

  return [topLine, botLine];
}

// Format current value
function formatValue(probe: WaveformProbe): string {
  const lastSample = probe.samples[probe.samples.length - 1];
  const value = lastSample?.value ?? 0;
  if (probe.width === 1) {
    return value ? '1' : '0';
  }
  const hexDigits = Math.ceil(probe.width / 4);
  return value.toString(16).toUpperCase().padStart(hexDigits, '0');
}

export function WaveformPanel({ waveforms, width = 60, height = 15, focused = false }: WaveformPanelProps) {
  const [scrollOffset, setScrollOffset] = useState(0);
  const [selectedIndex, setSelectedIndex] = useState(0);

  // Each waveform takes 2 lines + name
  const linesPerWave = 2;
  const visibleWaves = Math.floor((height - 4) / linesPerWave);
  const waveWidth = width - 22; // Space for name and value

  useInput((input, key) => {
    if (!focused) return;

    if (key.upArrow || input === 'k') {
      setSelectedIndex(prev => Math.max(0, prev - 1));
      if (selectedIndex - 1 < scrollOffset) {
        setScrollOffset(prev => Math.max(0, prev - 1));
      }
    } else if (key.downArrow || input === 'j') {
      setSelectedIndex(prev => Math.min(waveforms.length - 1, prev + 1));
      if (selectedIndex + 1 >= scrollOffset + visibleWaves) {
        setScrollOffset(prev => Math.min(Math.max(0, waveforms.length - visibleWaves), prev + 1));
      }
    }
  });

  const visibleWaveforms = waveforms.slice(scrollOffset, scrollOffset + visibleWaves);
  const borderColor = focused ? theme.primary : theme.border;
  const titleColor = focused ? theme.primaryBright : theme.primary;

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{box.topLeft}{box.horizontal}</Text>
        <Text color={titleColor} bold>[ SCOPE ]</Text>
        <Text color={borderColor}>{box.horizontal.repeat(width - 13)}{box.topRight}</Text>
      </Box>

      {/* Time scale indicator */}
      <Box>
        <Text color={borderColor}>{box.vertical}</Text>
        <Text color={theme.textMuted}> T{box.horizontal}</Text>
        <Text color={theme.textDim}>
          {'├' + '───────┼'.repeat(Math.floor(waveWidth / 8)).slice(0, waveWidth - 2) + '►'}
        </Text>
        <Text color={borderColor}>{box.vertical}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {box.teeLeft}{box.horizontal.repeat(width - 2)}{box.teeRight}
        </Text>
      </Box>

      {/* Waveforms */}
      {waveforms.length === 0 ? (
        <Box>
          <Text color={borderColor}>{box.vertical}</Text>
          <Text color={theme.textMuted}> No probes attached</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{box.vertical}</Text>
        </Box>
      ) : (
        visibleWaveforms.map((probe, idx) => {
          const actualIdx = scrollOffset + idx;
          const isSelected = actualIdx === selectedIndex;
          const [topLine, botLine] = renderWaveform(probe, waveWidth);
          const currentVal = formatValue(probe);
          const nameColor = isSelected && focused ? theme.primaryBright : theme.primary;

          return (
            <React.Fragment key={probe.name}>
              {/* Signal name and top waveform line */}
              <Box>
                <Text color={borderColor}>{box.vertical}</Text>
                <Text color={nameColor}>
                  {isSelected ? box.arrowRight : ' '}
                  {probe.name.slice(-10).padEnd(10)}
                </Text>
                <Text color={theme.border}>{box.vertical}</Text>
                <Text color={theme.primary}>{topLine}</Text>
                <Text color={theme.border}>{box.vertical}</Text>
                <Text color={theme.amber} bold>{currentVal.padStart(4)}</Text>
                <Text color={borderColor}>{box.vertical}</Text>
              </Box>
              {/* Bottom waveform line */}
              <Box>
                <Text color={borderColor}>{box.vertical}</Text>
                <Text> </Text>
                <Box width={10} />
                <Text color={theme.border}>{box.vertical}</Text>
                <Text color={theme.primary}>{botLine}</Text>
                <Text color={theme.border}>{box.vertical}</Text>
                <Box width={4} />
                <Text color={borderColor}>{box.vertical}</Text>
              </Box>
            </React.Fragment>
          );
        })
      )}

      {/* Footer with scroll info */}
      <Box>
        <Text color={borderColor}>
          {box.bottomLeft}{box.horizontal.repeat(2)}
        </Text>
        {waveforms.length > visibleWaves && (
          <Text color={theme.textMuted}>
            [{scrollOffset + 1}-{Math.min(scrollOffset + visibleWaves, waveforms.length)}/{waveforms.length}]
          </Text>
        )}
        <Text color={borderColor}>
          {box.horizontal.repeat(Math.max(0, width - 15))}{box.bottomRight}
        </Text>
      </Box>
    </Box>
  );
}
