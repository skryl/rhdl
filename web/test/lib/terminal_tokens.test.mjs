import test from 'node:test';
import assert from 'node:assert/strict';

import { tokenizeCommandLine, parseBooleanToken } from '../../app/lib/terminal_tokens.mjs';

test('tokenizeCommandLine splits whitespace and honors quotes', () => {
  assert.deepEqual(tokenizeCommandLine('run 100'), ['run', '100']);
  assert.deepEqual(tokenizeCommandLine('set watch "pc_debug"'), ['set', 'watch', 'pc_debug']);
  assert.deepEqual(tokenizeCommandLine("set label 'hello world'"), ['set', 'label', 'hello world']);
});

test('tokenizeCommandLine supports backslash escaping', () => {
  assert.deepEqual(tokenizeCommandLine('set value hello\\ world'), ['set', 'value', 'hello world']);
  assert.deepEqual(tokenizeCommandLine('cmd one\\ two\\ three'), ['cmd', 'one two three']);
});

test('tokenizeCommandLine rejects unclosed quotes', () => {
  assert.throws(() => tokenizeCommandLine('set "oops'), /Unclosed quote/);
});

test('parseBooleanToken accepts expected aliases', () => {
  assert.equal(parseBooleanToken('on'), true);
  assert.equal(parseBooleanToken('YES'), true);
  assert.equal(parseBooleanToken('disable'), false);
  assert.equal(parseBooleanToken('0'), false);
  assert.equal(parseBooleanToken('maybe'), null);
});
