import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import { Panel } from './Box.js';
import type { WaveformProbe } from '../protocol.js';

interface WaveformPanelProps {
  waveforms: WaveformProbe[];
  width?: number;
  height?: number;
  focused?: boolean;
}

// Characters for waveform rendering
const WAVE_CHARS = {
  high: '▀',
  low: '▄',
  rising: '╱',
  falling: '╲',
  both: '█',
  mid: '─',
  empty: ' ',
};

function renderWaveform(probe: WaveformProbe, width: number): string {
  if (probe.samples.length === 0) return WAVE_CHARS.empty.repeat(width);

  const samples = probe.samples;
  const startTime = samples[0]?.time ?? 0;
  const endTime = samples[samples.length - 1]?.time ?? startTime;
  const timeRange = Math.max(1, endTime - startTime);

  let result = '';
  let prevValue: number | null = null;

  for (let i = 0; i < width; i++) {
    const t = startTime + (i / width) * timeRange;
    // Find the sample at or before time t
    let sampleValue = 0;
    for (const sample of samples) {
      if (sample.time <= t) {
        sampleValue = sample.value;
      } else {
        break;
      }
    }

    // For single-bit signals, render as waveform
    if (probe.width === 1) {
      const high = sampleValue === 1;
      if (prevValue === null) {
        result += high ? WAVE_CHARS.high : WAVE_CHARS.low;
      } else if (prevValue !== sampleValue) {
        result += high ? WAVE_CHARS.rising : WAVE_CHARS.falling;
      } else {
        result += high ? WAVE_CHARS.high : WAVE_CHARS.low;
      }
    } else {
      // For multi-bit signals, use mid-line with value changes marked
      if (prevValue !== sampleValue) {
        result += '|';
      } else {
        result += WAVE_CHARS.mid;
      }
    }

    prevValue = sampleValue;
  }

  return result;
}

export function WaveformPanel({ waveforms, width = 60, height = 15, focused = false }: WaveformPanelProps) {
  const [scrollOffset, setScrollOffset] = useState(0);
  const visibleHeight = height - 3;
  const waveWidth = width - 25; // Leave room for signal name

  useInput((input, key) => {
    if (!focused) return;

    if (key.upArrow || input === 'k') {
      setScrollOffset(prev => Math.max(0, prev - 1));
    } else if (key.downArrow || input === 'j') {
      setScrollOffset(prev => Math.min(Math.max(0, waveforms.length - visibleHeight), prev + 1));
    }
  });

  const visibleWaveforms = waveforms.slice(scrollOffset, scrollOffset + visibleHeight);

  return (
    <Panel title="Waveform" width={width} height={height} borderColor={focused ? 'cyan' : 'gray'}>
      {waveforms.length === 0 ? (
        <Text dimColor>No waveforms captured</Text>
      ) : (
        <>
          {visibleWaveforms.map((probe) => (
            <Box key={probe.name}>
              <Text color="green">{probe.name.slice(0, 18).padEnd(18)}</Text>
              <Text dimColor> │</Text>
              <Text color="cyan">{renderWaveform(probe, waveWidth)}</Text>
            </Box>
          ))}
        </>
      )}
    </Panel>
  );
}
