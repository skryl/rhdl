import React from 'react';
import { Box, Text } from 'ink';
import { apple2Theme, apple2Chars } from '../theme.js';
import type { Instruction } from '../protocol.js';
import { formatHex8, formatHex16 } from '../protocol.js';

interface DisassemblyViewProps {
  instructions: Instruction[];
  currentPC?: number;
  width?: number;
  height?: number;
  focused?: boolean;
  breakpoints?: Set<number>;
}

// Disassembly listing view
export function DisassemblyView({
  instructions,
  currentPC,
  width = 35,
  height = 15,
  focused = false,
  breakpoints = new Set()
}: DisassemblyViewProps) {
  const borderColor = focused ? apple2Theme.phosphor : apple2Theme.border;
  const visibleRows = height - 3;

  // Find index of current PC
  const pcIndex = instructions.findIndex(i => i.address === currentPC);

  // Center on current PC if found
  let startIdx = 0;
  if (pcIndex >= 0) {
    startIdx = Math.max(0, pcIndex - Math.floor(visibleRows / 2));
  }

  const displayInstructions = instructions.slice(startIdx, startIdx + visibleRows);

  return (
    <Box flexDirection="column" width={width}>
      {/* Header */}
      <Box>
        <Text color={borderColor}>{apple2Chars.boxTL}{apple2Chars.boxH}</Text>
        <Text color={apple2Theme.phosphor} bold>[ DISASSEMBLY ]</Text>
        <Text color={borderColor}>
          {apple2Chars.boxH.repeat(Math.max(0, width - 17))}
          {apple2Chars.boxTR}
        </Text>
      </Box>

      {/* Instructions */}
      {displayInstructions.length === 0 ? (
        <Box>
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
          <Text color={apple2Theme.textMuted}> No disassembly</Text>
          <Box flexGrow={1} />
          <Text color={borderColor}>{apple2Chars.boxV}</Text>
        </Box>
      ) : (
        displayInstructions.map((inst, idx) => {
          const isCurrent = inst.address === currentPC;
          const hasBreakpoint = breakpoints.has(inst.address);
          const bgColor = isCurrent ? apple2Theme.phosphor : undefined;
          const fgColor = isCurrent ? apple2Theme.bg : apple2Theme.phosphor;

          // Format bytes as hex
          const bytesHex = inst.bytes.map(b => formatHex8(b)).join(' ');

          return (
            <Box key={inst.address}>
              <Text color={borderColor}>{apple2Chars.boxV}</Text>

              {/* Breakpoint indicator */}
              <Text color={hasBreakpoint ? apple2Theme.error : apple2Theme.textMuted}>
                {hasBreakpoint ? '*' : ' '}
              </Text>

              {/* PC indicator */}
              <Text color={isCurrent ? apple2Theme.phosphorBright : apple2Theme.textMuted}>
                {isCurrent ? '>' : ' '}
              </Text>

              {/* Address */}
              <Text color={fgColor} backgroundColor={bgColor}>
                ${formatHex16(inst.address)}
              </Text>

              <Text color={apple2Theme.textDim}> </Text>

              {/* Bytes */}
              <Box width={9}>
                <Text color={apple2Theme.textDim}>{bytesHex.padEnd(8)}</Text>
              </Box>

              {/* Mnemonic */}
              <Text color={fgColor} backgroundColor={bgColor} bold>
                {inst.mnemonic.padEnd(4)}
              </Text>

              {/* Operand */}
              <Text color={isCurrent ? fgColor : apple2Theme.phosphorDim} backgroundColor={bgColor}>
                {inst.operand.slice(0, 10)}
              </Text>

              <Box flexGrow={1} />
              <Text color={borderColor}>{apple2Chars.boxV}</Text>
            </Box>
          );
        })
      )}

      {/* Fill empty rows */}
      {Array.from({ length: Math.max(0, visibleRows - displayInstructions.length) }).map((_, i) => (
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

// Compact current instruction display
export function CurrentInstruction({ instruction, currentPC }: { instruction?: Instruction; currentPC?: number }) {
  if (!instruction) {
    return (
      <Box>
        <Text color={apple2Theme.textDim}>PC: </Text>
        <Text color={apple2Theme.phosphor}>${formatHex16(currentPC ?? 0)}</Text>
        <Text color={apple2Theme.textDim}> ???</Text>
      </Box>
    );
  }

  const bytesHex = instruction.bytes.map(b => formatHex8(b)).join(' ');

  return (
    <Box>
      <Text color={apple2Theme.textDim}>></Text>
      <Text color={apple2Theme.phosphor}>${formatHex16(instruction.address)}</Text>
      <Text color={apple2Theme.textDim}> {bytesHex.padEnd(8)} </Text>
      <Text color={apple2Theme.phosphor} bold>{instruction.mnemonic} </Text>
      <Text color={apple2Theme.phosphorDim}>{instruction.operand}</Text>
    </Box>
  );
}
