function resolveAssetCandidates(path: string) {
  const trimmed = String(path || '').trim();
  if (!trimmed) {
    return [];
  }

  const urls = [trimmed];
  const seen = new Set(urls);
  const addCandidate = (candidate: unknown) => {
    const url = String(candidate || '').trim();
    if (!url || seen.has(url)) {
      return;
    }
    seen.add(url);
    urls.push(url);
  };

  const addFromBase = (base: unknown) => {
    try {
      addCandidate(new URL(trimmed, String(base)).toString());
    } catch (_error) {
      // ignore invalid bases.
    }
  };

  if (typeof document === 'object' && document?.baseURI) {
    addFromBase(document.baseURI);
  }
  if (typeof location === 'object' && location?.href) {
    addFromBase(location.href);
  }
  addFromBase(import.meta.url);

  if (trimmed.startsWith('./')) {
    addCandidate(trimmed.slice(2));
    addCandidate(`/${trimmed.slice(2)}`);
  }

  return urls;
}

function messageFromError(err: unknown) {
  return err instanceof Error ? err.message : String(err);
}

function isUsableResponse(response: Response) {
  if (response.ok) {
    return true;
  }
  return response.status === 0;
}

export async function fetchTextAsset(path: string, label = 'asset', fetchImpl: typeof fetch = globalThis.fetch) {
  const requestUrls = resolveAssetCandidates(path);
  let lastResponse: Response | null = null;
  const failures: string[] = [];

  for (const requestUrl of requestUrls) {
    try {
      const response = await fetchImpl(requestUrl);
      if (isUsableResponse(response)) {
        return response.text();
      }
      const detail = response.status === 0 ? `${response.type}/${response.url || requestUrl}` : response.status;
      failures.push(`${requestUrl} -> ${detail}`);
      lastResponse = response;
    } catch (err: unknown) {
      failures.push(`${requestUrl} -> ${messageFromError(err)}`);
    }
  }

  const lastRequestUrl = lastResponse?.url || requestUrls[requestUrls.length - 1] || path;
  throw new Error(`${label} load failed (${failures.join(', ') || `No usable fetch URL for ${lastRequestUrl}`})`);

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
