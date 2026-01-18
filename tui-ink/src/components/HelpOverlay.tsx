import React from 'react';
import { Box, Text } from 'ink';

interface HelpOverlayProps {
  onClose: () => void;
}

export function HelpOverlay({ onClose }: HelpOverlayProps) {
  return (
    <Box
      flexDirection="column"
      borderStyle="double"
      borderColor="cyan"
      paddingX={2}
      paddingY={1}
    >
      <Text bold color="cyan">═══ RHDL Simulator Help ═══</Text>
      <Text> </Text>
      <Text bold>Keys:</Text>
      <Text>  <Text color="yellow">Space</Text>  - Step one cycle</Text>
      <Text>  <Text color="yellow">n</Text>      - Step half cycle</Text>
      <Text>  <Text color="yellow">r</Text>      - Run simulation</Text>
      <Text>  <Text color="yellow">s</Text>      - Stop simulation</Text>
      <Text>  <Text color="yellow">R</Text>      - Reset simulation</Text>
      <Text>  <Text color="yellow">c</Text>      - Continue until breakpoint</Text>
      <Text>  <Text color="yellow">w</Text>      - Add watchpoint</Text>
      <Text>  <Text color="yellow">b</Text>      - Add breakpoint</Text>
      <Text>  <Text color="yellow">j/k</Text>    - Navigate lists</Text>
      <Text>  <Text color="yellow">Tab</Text>    - Switch panel focus</Text>
      <Text>  <Text color="yellow">:</Text>      - Enter command mode</Text>
      <Text>  <Text color="yellow">h/?</Text>    - Show this help</Text>
      <Text>  <Text color="yellow">q</Text>      - Quit</Text>
      <Text> </Text>
      <Text bold>Commands:</Text>
      <Text>  <Text color="green">run [n]</Text>           - Run n cycles</Text>
      <Text>  <Text color="green">step</Text>              - Single step</Text>
      <Text>  <Text color="green">watch sig [type]</Text>  - Add watchpoint</Text>
      <Text>  <Text color="green">break [cycle]</Text>     - Add breakpoint</Text>
      <Text>  <Text color="green">delete id</Text>         - Delete breakpoint</Text>
      <Text>  <Text color="green">set sig val</Text>       - Set signal value</Text>
      <Text>  <Text color="green">print sig</Text>         - Print signal value</Text>
      <Text>  <Text color="green">export file</Text>       - Export VCD</Text>
      <Text>  <Text color="green">clear [what]</Text>      - Clear breaks/waves/log</Text>
      <Text> </Text>
      <Text dimColor>Watch types: change, equals, rising_edge, falling_edge</Text>
      <Text> </Text>
      <Text dimColor>Press any key to close</Text>
    </Box>
  );
}
