import test from 'node:test';
import assert from 'node:assert/strict';

import { renderUartTextGrid } from '../../../../app/components/apple2/lib/uart_text.mjs';

test('renderUartTextGrid treats CRLF as one newline', () => {
  const bytes = new Uint8Array([65, 13, 10, 66]);
  const text = renderUartTextGrid(bytes, { width: 4, height: 3 });
  assert.equal(text, 'A   \nB   \n    ');
});

test('renderUartTextGrid treats CR as newline when LF is missing', () => {
  const bytes = new Uint8Array([65, 13, 66]);
  const text = renderUartTextGrid(bytes, { width: 4, height: 3 });
  assert.equal(text, 'A   \nB   \n    ');
});

test('renderUartTextGrid keeps LF newline behavior unchanged', () => {
  const bytes = new Uint8Array([65, 10, 66]);
  const text = renderUartTextGrid(bytes, { width: 4, height: 3 });
  assert.equal(text, 'A   \nB   \n    ');
});
