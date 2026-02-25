// Renderer-agnostic theme system.
// Port of controllers/graph/theme.mjs palette + style rules.

export function getThemePalette(theme = 'shenzhen') {
  if (theme === 'shenzhen') {
    return {
      componentBg: '#1b3d32',
      componentBorder: '#76d4a4',
      componentText: '#d8eee0',
      pinBg: '#2d5d4f',
      pinBorder: '#8bd7b5',
      netBg: '#243a35',
      netBorder: '#527a6d',
      netText: '#b6d2c5',
      ioBg: '#28463d',
      ioBorder: '#7ecdad',
      opBg: '#3f4c3a',
      memoryBg: '#4f3e2f',
      wire: '#4f7d6d',
      wireActive: '#7be9ad',
      wireToggle: '#f4bf66',
      selected: '#9cffe3'
    };
  }

  // original theme
  return {
    componentBg: '#214c71',
    componentBorder: '#2f6b97',
    componentText: '#e7f3ff',
    pinBg: '#35597a',
    pinBorder: '#79bde3',
    netBg: '#223247',
    netBorder: '#3e5f83',
    netText: '#c0d7ef',
    ioBg: '#1f4258',
    ioBorder: '#6eaed4',
    opBg: '#3b4559',
    memoryBg: '#54434e',
    wire: '#3a5f82',
    wireActive: '#3dd7c2',
    wireToggle: '#ffbc5a',
    selected: '#7fdfff'
  };
}

export function resolveElementColors(element, palette) {
  const type = element.type || '';

  // Wire
  if (type === 'wire') {
    if (element.selected) return { stroke: '#ffffff', strokeWidth: 3.2 };
    if (element.toggled) return { stroke: palette.wireToggle, strokeWidth: 2.7 };
    if (element.active) return { stroke: palette.wireActive, strokeWidth: 2.0 };
    return { stroke: palette.wire, strokeWidth: element.bus ? 2.4 : 1.4 };
  }

  // Net
  if (type === 'net') {
    let fill = palette.netBg;
    let stroke = palette.netBorder;
    let text = palette.netText;
    let strokeWidth = element.bus ? 2.2 : 1.2;

    if (element.selected) {
      stroke = palette.selected;
      strokeWidth = 2.8;
    } else if (element.toggled) {
      stroke = palette.wireToggle;
      strokeWidth = 2.2;
    } else if (element.active) {
      fill = palette.wireActive;
      stroke = palette.wireActive;
      text = '#001513';
    }

    return { fill, stroke, text, strokeWidth };
  }

  // Pin
  if (type === 'pin') {
    let fill = palette.pinBg;
    let stroke = palette.pinBorder;
    let strokeWidth = element.bus ? 2.1 : 1.2;

    if (element.selected) {
      stroke = palette.selected;
      strokeWidth = 2.4;
    } else if (element.toggled) {
      stroke = palette.wireToggle;
    } else if (element.active) {
      fill = palette.wireActive;
      stroke = palette.wireActive;
    }

    return { fill, stroke, strokeWidth };
  }

  // Symbol types: focus, component, memory, op, io
  let fill = palette.componentBg;
  let stroke = palette.componentBorder;
  let text = palette.componentText;
  let strokeWidth = 1.7;

  if (type === 'focus') {
    strokeWidth = 2.2;
  } else if (type === 'memory') {
    fill = palette.memoryBg;
    stroke = palette.wire;
  } else if (type === 'op') {
    fill = palette.opBg;
    stroke = palette.wire;
  } else if (type === 'io') {
    fill = palette.ioBg;
    stroke = palette.ioBorder;
  }

  return { fill, stroke, text, strokeWidth };
}
