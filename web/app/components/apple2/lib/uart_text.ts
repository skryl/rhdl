function decodeTextChar(code, textConfig = {}) {
  const charMask = Number.parseInt(textConfig.charMask, 10);
  const asciiMin = Number.parseInt(textConfig.asciiMin, 10);
  const asciiMax = Number.parseInt(textConfig.asciiMax, 10);
  const masked = Number.isFinite(charMask) ? (code & charMask) : (code & 0x7F);
  const min = Number.isFinite(asciiMin) ? asciiMin : 0x20;
  const max = Number.isFinite(asciiMax) ? asciiMax : 0x7E;
  if (masked >= min && masked <= max) {
    return String.fromCharCode(masked);
  }
  return ' ';
}

function makeRow(width) {
  return new Array(width).fill(' ');
}

export function renderUartTextGrid(bytes, {
  width = 80,
  height = 24,
  textConfig = {}
} = {}) {
  const cols = Math.max(1, Number.parseInt(width, 10) || 80);
  const rowsCount = Math.max(1, Number.parseInt(height, 10) || 24);

  const rows = Array.from({ length: rowsCount }, () => makeRow(cols));
  let row = 0;
  let col = 0;

  const scroll = () => {
    rows.shift();
    rows.push(makeRow(cols));
    row = rowsCount - 1;
    col = 0;
  };

  const newline = () => {
    row += 1;
    col = 0;
    if (row >= rowsCount) {
      scroll();
    }
  };

  const clearAtCursor = () => {
    if (row >= 0 && row < rowsCount && col >= 0 && col < cols) {
      rows[row][col] = ' ';
    }
  };

  if (bytes && typeof bytes[Symbol.iterator] === 'function') {
    let pendingCarriageReturn = false;

    const flushPendingCarriageReturn = () => {
      if (!pendingCarriageReturn) {
        return false;
      }
      newline();
      pendingCarriageReturn = false;
      return true;
    };

    for (const raw of bytes) {
      const byte = Number(raw) & 0xFF;

      if (pendingCarriageReturn) {
        if (byte === 0x0A) {
          // Treat CRLF as a single logical newline.
          newline();
          pendingCarriageReturn = false;
          continue;
        }
        flushPendingCarriageReturn();
      }

      if (byte === 0x0D) {
        // Some UART logs emit CR without LF; keep it as a newline.
        pendingCarriageReturn = true;
        continue;
      }

      if (byte === 0x0A) {
        newline();
        continue;
      }

      if (byte === 0x08) {
        if (col > 0) {
          col -= 1;
          clearAtCursor();
        }
        continue;
      }

      if (byte === 0x09) {
        if (col >= cols) {
          newline();
        }
        const nextStop = Math.min(cols, (Math.floor(col / 4) + 1) * 4);
        while (col < nextStop) {
          clearAtCursor();
          col += 1;
          if (col >= cols) {
            newline();
            break;
          }
        }
        continue;
      }

      if (col >= cols) {
        newline();
      }
      rows[row][col] = decodeTextChar(byte, textConfig);
      col += 1;
    }

    flushPendingCarriageReturn();
  }

  return rows.map((cells) => cells.join('')).join('\n');
}
