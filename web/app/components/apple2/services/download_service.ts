function createBlobDownloader({
  windowRef = globalThis.window,
  documentRef = globalThis.document
}: any = {}) {
  return function downloadBlob(blob: any, filename: any) {
    if (!blob || !filename) {
      return;
    }
    const url = windowRef.URL.createObjectURL(blob);
    const anchor = documentRef.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    windowRef.URL.revokeObjectURL(url);
  };
}

export function createApple2DownloadService({
  windowRef = globalThis.window,
  documentRef = globalThis.document
}: any = {}) {
  const downloadBlob = createBlobDownloader({ windowRef, documentRef });

  function downloadMemoryDump(bytes: any, filename: any) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return;
    }
    downloadBlob(new Blob([bytes as any], { type: 'application/octet-stream' }), filename);
  }

  function downloadSnapshot(snapshot: any, filename: any) {
    if (!snapshot || typeof snapshot !== 'object') {
      return;
    }
    const encoded = JSON.stringify(snapshot, null, 2);
    downloadBlob(new Blob([encoded], { type: 'application/json' }), filename);
  }

  return {
    downloadMemoryDump,
    downloadSnapshot
  };
}
