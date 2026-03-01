function messageFromError(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

export async function fetchTextAsset(path: string, label = 'asset', fetchImpl: typeof fetch = globalThis.fetch) {
  const response = await fetchImpl(path);
  if (!response.ok) {
    throw new Error(`${label} load failed (${response.status})`);
  }
  return response.text();
}

export async function fetchJsonAsset<T = unknown>(
  path: string,
  label = 'asset',
  fetchImpl: typeof fetch = globalThis.fetch
): Promise<T> {
  const text = await fetchTextAsset(path, label, fetchImpl);
  try {
    return JSON.parse(text) as T;
  } catch (err: unknown) {
    throw new Error(`${label} parse failed: ${messageFromError(err)}`);
  }
}
