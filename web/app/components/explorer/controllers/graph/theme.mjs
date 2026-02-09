export function createSchematicPalette(theme = 'shenzhen') {
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

export function createSchematicStyle(palette) {
  return [
    {
      selector: 'node',
      style: {
        'label': 'data(label)',
        'font-size': 8,
        'color': palette.componentText,
        'text-wrap': 'ellipsis',
        'text-max-width': 140,
        'text-halign': 'center',
        'text-valign': 'center',
        'border-width': 1.2
      }
    },
    {
      selector: 'node.schem-symbol',
      style: {
        'shape': 'round-rectangle',
        'width': 'data(symbolWidth)',
        'height': 'data(symbolHeight)',
        'padding-left': 10,
        'padding-right': 10
      }
    },
    {
      selector: 'node.schem-component',
      style: {
        'background-color': palette.componentBg,
        'border-color': palette.componentBorder,
        'border-width': 1.7
      }
    },
    {
      selector: 'node.schem-component-fallback',
      style: {
        'width': 168,
        'height': 64
      }
    },
    {
      selector: 'node.schem-focus',
      style: {
        'border-width': 2.2
      }
    },
    {
      selector: 'node.schem-net',
      style: {
        'shape': 'round-rectangle',
        'background-color': palette.netBg,
        'border-color': palette.netBorder,
        'color': palette.netText,
        'width': 52,
        'height': 18,
        'font-size': 7,
        'text-max-width': 74,
        'padding-left': 4,
        'padding-right': 4
      }
    },
    {
      selector: 'node.schem-net.schem-bus',
      style: {
        'border-width': 2.2
      }
    },
    {
      selector: 'node.schem-net.net-active',
      style: {
        'background-color': palette.wireActive,
        'border-color': palette.wireActive,
        'color': '#001513'
      }
    },
    {
      selector: 'node.schem-net.net-toggled',
      style: {
        'border-color': palette.wireToggle,
        'border-width': 2.2
      }
    },
    {
      selector: 'node.schem-net.net-selected',
      style: {
        'border-color': palette.selected,
        'border-width': 2.8
      }
    },
    {
      selector: 'node.schem-pin',
      style: {
        'shape': 'round-rectangle',
        'label': '',
        'background-color': palette.pinBg,
        'border-color': palette.pinBorder,
        'width': 14,
        'height': 10,
        'border-width': 1.2
      }
    },
    {
      selector: 'node.schem-pin.schem-bus',
      style: {
        'height': 12,
        'border-width': 2.1
      }
    },
    {
      selector: 'node.schem-pin.pin-active',
      style: {
        'background-color': palette.wireActive,
        'border-color': palette.wireActive
      }
    },
    {
      selector: 'node.schem-pin.pin-toggled',
      style: {
        'border-color': palette.wireToggle
      }
    },
    {
      selector: 'node.schem-pin.pin-selected',
      style: {
        'border-color': palette.selected,
        'border-width': 2.4
      }
    },
    {
      selector: 'node.schem-io',
      style: {
        'shape': 'round-rectangle',
        'background-color': palette.ioBg,
        'border-color': palette.ioBorder,
        'width': 34,
        'height': 16,
        'font-size': 6,
        'text-max-width': 56
      }
    },
    {
      selector: 'node.schem-op',
      style: {
        'background-color': palette.opBg,
        'border-color': palette.wire,
        'width': 104,
        'height': 42,
        'font-size': 8
      }
    },
    {
      selector: 'node.schem-memory',
      style: {
        'shape': 'round-rectangle',
        'background-color': palette.memoryBg,
        'border-color': palette.wire,
        'border-style': 'double',
        'width': 124,
        'height': 56,
        'font-size': 8
      }
    },
    {
      selector: 'node.selected',
      style: {
        'border-color': palette.selected,
        'border-width': 2.6
      }
    },
    {
      selector: 'edge',
      style: {
        'width': 1.4,
        'line-color': palette.wire,
        'target-arrow-color': palette.wire,
        'target-arrow-shape': 'none',
        'source-arrow-shape': 'none',
        'curve-style': 'taxi',
        'taxi-direction': 'auto',
        'taxi-turn': 18,
        'opacity': 0.9
      }
    },
    {
      selector: 'edge.schem-bus',
      style: {
        'width': 2.4
      }
    },
    {
      selector: 'edge.schem-bidir',
      style: {
        'line-style': 'dashed'
      }
    },
    {
      selector: 'edge.wire-active',
      style: {
        'line-color': palette.wireActive,
        'target-arrow-color': palette.wireActive,
        'source-arrow-color': palette.wireActive,
        'width': 2
      }
    },
    {
      selector: 'edge.wire-toggled',
      style: {
        'line-color': palette.wireToggle,
        'target-arrow-color': palette.wireToggle,
        'source-arrow-color': palette.wireToggle,
        'width': 2.7
      }
    },
    {
      selector: 'edge.wire-selected',
      style: {
        'line-color': '#ffffff',
        'target-arrow-color': '#ffffff',
        'source-arrow-color': '#ffffff',
        'width': 3.2
      }
    }
  ];
}
