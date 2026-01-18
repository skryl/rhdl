import React from 'react';
import { Box, Text } from 'ink';
import { apple2Theme, apple2Chars, STATUS_FLAGS } from '../theme.js';
import type { CPUState } from '../protocol.js';
import { formatHex8, formatHex16, formatFlags, getFlag } from '../protocol.js';

interface RegisterViewProps {
  cpu: CPUState | null;
  focused?: boolean;
}

// 6502 CPU Register display
export function RegisterView({ cpu, focused = false }: RegisterViewProps) {
  const borderColor = focused ? apple2Theme.phosphor : apple2Theme.border;
  const labelColor = apple2Theme.textDim;
  const valueColor = apple2Theme.phosphor;

  const pc = cpu?.pc ?? 0;
  const a = cpu?.a ?? 0;
  const x = cpu?.x ?? 0;
  const y = cpu?.y ?? 0;
  const sp = cpu?.sp ?? 0;
  const p = cpu?.p ?? 0;
  const cycles = cpu?.cycles ?? 0;

  return (
    <Box flexDirection="column">
      {/* Header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxTL}{apple2Chars.boxH}</Text>
        <Text color={apple2Theme.phosphor} bold>[ 6502 CPU ]</Text>
        <Text color={borderColor}>{apple2Chars.boxH.repeat(10)}{apple2Chars.boxTR}</Text>
      </Box>

      {/* Program Counter */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>PC  </Text>
        <Text color={valueColor} bold>${formatHex16(pc)}</Text>
        <Text color={borderColor}>    {apple2Chars.boxV}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxTeeL}{apple2Chars.boxH.repeat(20)}{apple2Chars.boxTeeR}
        </Text>
      </Box>

      {/* Accumulator */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>A   </Text>
        <Text color={valueColor} bold>${formatHex8(a)}</Text>
        <Text color={labelColor}>  ({a.toString().padStart(3)})</Text>
        <Text color={borderColor}> {apple2Chars.boxV}</Text>
      </Box>

      {/* X Register */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>X   </Text>
        <Text color={valueColor} bold>${formatHex8(x)}</Text>
        <Text color={labelColor}>  ({x.toString().padStart(3)})</Text>
        <Text color={borderColor}> {apple2Chars.boxV}</Text>
      </Box>

      {/* Y Register */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>Y   </Text>
        <Text color={valueColor} bold>${formatHex8(y)}</Text>
        <Text color={labelColor}>  ({y.toString().padStart(3)})</Text>
        <Text color={borderColor}> {apple2Chars.boxV}</Text>
      </Box>

      {/* Stack Pointer */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>SP  </Text>
        <Text color={valueColor} bold>${formatHex8(sp)}</Text>
        <Text color={labelColor}>  ($01{formatHex8(sp)})</Text>
        <Text color={borderColor}>{apple2Chars.boxV}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxTeeL}{apple2Chars.boxH.repeat(20)}{apple2Chars.boxTeeR}
        </Text>
      </Box>

      {/* Status flags header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>P   </Text>
        <Text color={valueColor} bold>${formatHex8(p)}</Text>
        <Text color={labelColor}>          </Text>
        <Text color={borderColor}>{apple2Chars.boxV}</Text>
      </Box>

      {/* Flag display */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>    </Text>
        {Object.entries(STATUS_FLAGS).map(([key, flag]) => {
          const isSet = getFlag(p, flag.bit);
          return (
            <Text key={key} color={isSet ? apple2Theme.phosphorBright : apple2Theme.textMuted}>
              {flag.name}
            </Text>
          );
        })}
        <Text color={borderColor}>        {apple2Chars.boxV}</Text>
      </Box>

      {/* Separator */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxTeeL}{apple2Chars.boxH.repeat(20)}{apple2Chars.boxTeeR}
        </Text>
      </Box>

      {/* Cycles */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxV} </Text>
        <Text color={labelColor}>CYC </Text>
        <Text color={valueColor}>{cycles.toString().padStart(12)}</Text>
        <Text color={borderColor}> {apple2Chars.boxV}</Text>
      </Box>

      {/* Footer */}
      <Box>
        <Text color={borderColor}>
          {apple2Chars.boxBL}{apple2Chars.boxH.repeat(20)}{apple2Chars.boxBR}
        </Text>
      </Box>
    </Box>
  );
}

// Compact single-line register display
export function RegisterCompact({ cpu }: { cpu: CPUState | null }) {
  const pc = cpu?.pc ?? 0;
  const a = cpu?.a ?? 0;
  const x = cpu?.x ?? 0;
  const y = cpu?.y ?? 0;
  const sp = cpu?.sp ?? 0;
  const p = cpu?.p ?? 0;

  return (
    <Box>
      <Text color={apple2Theme.textDim}>PC:</Text>
      <Text color={apple2Theme.phosphor}>{formatHex16(pc)} </Text>
      <Text color={apple2Theme.textDim}>A:</Text>
      <Text color={apple2Theme.phosphor}>{formatHex8(a)} </Text>
      <Text color={apple2Theme.textDim}>X:</Text>
      <Text color={apple2Theme.phosphor}>{formatHex8(x)} </Text>
      <Text color={apple2Theme.textDim}>Y:</Text>
      <Text color={apple2Theme.phosphor}>{formatHex8(y)} </Text>
      <Text color={apple2Theme.textDim}>SP:</Text>
      <Text color={apple2Theme.phosphor}>{formatHex8(sp)} </Text>
      <Text color={apple2Theme.textDim}>P:</Text>
      <Text color={apple2Theme.phosphor}>{formatFlags(p)}</Text>
    </Box>
  );
}
