interface BlobDownloaderDeps {
  windowRef?: Unsafe;
  documentRef?: Unsafe;
}

function createBlobDownloader({
  windowRef = globalThis.window,
  documentRef = globalThis.document
}: BlobDownloaderDeps = {}) {
  return function downloadBlob(blob: Blob, filename: string) {
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
}: BlobDownloaderDeps = {}) {
  const downloadBlob = createBlobDownloader({ windowRef, documentRef });

  function downloadMemoryDump(bytes: Uint8Array, filename: string) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return;
    }
    const blobBytes = new Uint8Array(bytes);
    downloadBlob(new Blob([blobBytes], { type: 'application/octet-stream' }), filename);
  }

  function downloadSnapshot(snapshot: Unsafe, filename: string) {
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
