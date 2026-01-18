// SHENZHEN I/O inspired theme
// Dark background, green/amber monochrome CRT aesthetic

export const theme = {
  // Primary colors - green CRT phosphor
  primary: '#33ff33',      // Bright green (P1 phosphor)
  primaryDim: '#1a8c1a',   // Dim green
  primaryBright: '#66ff66', // Highlighted green

  // Secondary colors - amber CRT
  amber: '#ffb000',        // Amber/orange
  amberDim: '#805800',     // Dim amber
  amberBright: '#ffd966',  // Bright amber

  // Status colors
  error: '#ff3333',        // Red for errors
  warning: '#ffb000',      // Amber for warnings
  success: '#33ff33',      // Green for success

  // Background/UI colors
  bg: '#0a0a0a',           // Near black
  bgLight: '#1a1a1a',      // Slightly lighter
  border: '#333333',       // Dark gray borders
  borderActive: '#33ff33', // Green active border

  // Text colors
  text: '#33ff33',         // Primary text (green)
  textDim: '#1a8c1a',      // Dimmed text
  textMuted: '#404040',    // Very dim/muted

  // Special
  cursor: '#33ff33',       // Cursor color
  selection: '#1a4d1a',    // Selection background
} as const;

// Box drawing characters for industrial look
export const box = {
  // Single line
  topLeft: '┌',
  topRight: '┐',
  bottomLeft: '└',
  bottomRight: '┘',
  horizontal: '─',
  vertical: '│',
  teeLeft: '├',
  teeRight: '┤',
  teeUp: '┴',
  teeDown: '┬',
  cross: '┼',

  // Double line (for emphasis)
  dTopLeft: '╔',
  dTopRight: '╗',
  dBottomLeft: '╚',
  dBottomRight: '╝',
  dHorizontal: '═',
  dVertical: '║',

  // Mixed (single vertical, double horizontal)
  mTopLeft: '╒',
  mTopRight: '╕',
  mBottomLeft: '╘',
  mBottomRight: '╛',

  // Block elements
  fullBlock: '█',
  lightShade: '░',
  mediumShade: '▒',
  darkShade: '▓',
  upperHalf: '▀',
  lowerHalf: '▄',

  // Arrows and indicators
  arrowRight: '►',
  arrowLeft: '◄',
  arrowUp: '▲',
  arrowDown: '▼',
  bullet: '•',
  diamond: '◆',
  square: '■',
  circle: '●',
  triangleRight: '▶',
} as const;

// Status indicators
export const indicators = {
  running: '▶ RUN',
  stopped: '■ STP',
  paused: '║║ PSE',
  error: '✖ ERR',
  ready: '● RDY',
  clock: '⏱',
  cycle: 'CYC',
  time: 'T',
} as const;

// ASCII art header
export const header = `
╔═══════════════════════════════════════════════════════════════════════════════╗
║  ██████╗ ██╗  ██╗██████╗ ██╗         ███████╗██╗███╗   ███╗                   ║
║  ██╔══██╗██║  ██║██╔══██╗██║         ██╔════╝██║████╗ ████║                   ║
║  ██████╔╝███████║██║  ██║██║         ███████╗██║██╔████╔██║                   ║
║  ██╔══██╗██╔══██║██║  ██║██║         ╚════██║██║██║╚██╔╝██║                   ║
║  ██║  ██║██║  ██║██████╔╝███████╗    ███████║██║██║ ╚═╝ ██║                   ║
║  ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝    ╚══════╝╚═╝╚═╝     ╚═╝                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝
`.trim();

// Compact header for smaller screens
export const headerCompact = '═══[ RHDL SIMULATOR ]═══';
