// RISC-V source map loader for the web simulator.
// Loads a kernel_srcmap.json and provides address-to-source lookups.
//
// JSON format (produced by extract_srcmap.rb):
//   {
//     "format": "rhdl.riscv.srcmap.v1",
//     "files":     ["kernel/start.c", ...],
//     "functions": [[addr, size, "name", fileIndex], ...],
//     "lines":     [[addr, fileIndex, lineNumber], ...],
//     "sources":   { "kernel/start.c": "full source text...", ... }
//   }

// Binary search: find the last entry whose [0] (address) is <= target.
function bsearchFloor(arr: any, target: any) {
  let lo = 0;
  let hi = arr.length - 1;
  let result = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >>> 1;
    if (arr[mid][0] <= target) {
      result = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return result;
}

export function createRiscvSourceMap(json: any) {
  if (!json || json.format !== 'rhdl.riscv.srcmap.v1') {
    return null;
  }

  const files = json.files || [];
  const functions = json.functions || [];
  const lines = json.lines || [];
  const sources = json.sources || {};

  // Pre-split source files into line arrays for efficient line lookup.
  const sourceLines: Record<string, string[]> = {};
  for (const [path, text] of Object.entries(sources)) {
    sourceLines[path] = String(text).split('\n');
  }

  function lookupFunction(addr: any) {
    const idx = bsearchFloor(functions, addr >>> 0);
    if (idx < 0) return null;
    const entry = functions[idx];
    const fnAddr = entry[0];
    const fnSize = entry[1];
    const fnName = entry[2];
    const fnFileIdx = entry[3];
    // If size is known, check the address falls within the function.
    if (fnSize > 0 && (addr >>> 0) >= fnAddr + fnSize) return null;
    return {
      addr: fnAddr,
      size: fnSize,
      name: fnName,
      file: fnFileIdx >= 0 && fnFileIdx < files.length ? files[fnFileIdx] : null
    };
  }

  function lookupLine(addr: any) {
    const idx = bsearchFloor(lines, addr >>> 0);
    if (idx < 0) return null;
    const entry = lines[idx];
    const fileIdx = entry[1];
    const lineNo = entry[2];
    const file = fileIdx >= 0 && fileIdx < files.length ? files[fileIdx] : null;
    return { file, line: lineNo };
  }

  function getSourceLine(file: any, lineNo: any) {
    const fileLines = (sourceLines as Record<string, any>)[file];
    if (!fileLines || lineNo < 1 || lineNo > fileLines.length) return null;
    return fileLines[lineNo - 1];
  }

  function lookup(addr: any) {
    const fn = lookupFunction(addr);
    const line = lookupLine(addr);
    if (!fn && !line) return null;
    const file = (line && line.file) || (fn && fn.file) || null;
    const lineNo = line ? line.line : null;
    const sourceText = file && lineNo ? getSourceLine(file, lineNo) : null;
    return {
      function: fn ? fn.name : null,
      file,
      line: lineNo,
      source: sourceText != null ? sourceText.trimStart() : null
    };
  }

  return {
    lookup,
    lookupFunction,
    lookupLine,
    getSourceLine,
    fileCount: files.length,
    functionCount: functions.length,
    lineCount: lines.length
  };
}
