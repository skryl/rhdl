export async function fetchTextAsset(path, label = 'asset', fetchImpl = globalThis.fetch) {
  const response = await fetchImpl(path);
  if (!response.ok) {
    throw new Error(`${label} load failed (${response.status})`);
  }
  return response.text();
}

export async function fetchJsonAsset(path, label = 'asset', fetchImpl = globalThis.fetch) {
  const text = await fetchTextAsset(path, label, fetchImpl);
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${label} parse failed: ${err.message || err}`);
  }
}
