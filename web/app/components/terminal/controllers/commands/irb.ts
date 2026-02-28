export async function handleIrbCommand({ cmd, tokens, context }) {
  if (cmd !== 'irb' && cmd !== 'mirb') {
    return undefined;
  }

  const source = tokens.join(' ').trim();
  if (cmd === 'mirb' && !source) {
    const startMirbSession = context?.helpers?.startMirbSession;
    if (typeof startMirbSession !== 'function') {
      throw new Error('mirb session runtime is unavailable.');
    }
    const started = startMirbSession();
    return started
      ? 'mirb session started. Enter Ruby lines; type `exit` to close.'
      : 'mirb session is already active';
  }

  if (!source) {
    throw new Error(`Usage: ${cmd} <ruby-code>`);
  }

  const runMirb = context?.helpers?.runMirb;
  if (typeof runMirb !== 'function') {
    throw new Error('mirb runtime is unavailable.');
  }

  const result = await runMirb(source);
  const stdout = String(result?.stdout || '').trim();
  const stderr = String(result?.stderr || '').trim();
  const exitCode = Number(result?.exitCode || 0);

  if (stderr && exitCode !== 0) {
    throw new Error(stderr);
  }
  if (stdout && stderr) {
    return `${stdout}\n${stderr}`;
  }
  if (stdout) {
    return stdout;
  }
  if (stderr) {
    return stderr;
  }
  return `(mirb exit ${exitCode})`;
}
