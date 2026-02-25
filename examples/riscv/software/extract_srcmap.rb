#!/usr/bin/env ruby
# frozen_string_literal: true

# Extracts a source map from objdump -S output (kernel.asm) and nm output (kernel.nm).
# Produces a JSON file mapping addresses to source file/line and function names.
#
# Usage:
#   ruby extract_srcmap.rb --asm kernel.asm --nm kernel.nm --source-dir kernel/ -o kernel_srcmap.json
#
# The JSON format:
#   {
#     "format": "rhdl.riscv.srcmap.v1",
#     "files":     ["kernel/start.c", ...],
#     "functions": [[addr, size, "name", fileIndex], ...],  (sorted by addr)
#     "lines":     [[addr, fileIndex, lineNumber], ...],    (sorted by addr)
#     "sources":   { "kernel/start.c": "full source...", ... }
#   }

require 'json'
require 'optparse'

def parse_nm(nm_path)
  return [] unless nm_path && File.exist?(nm_path)

  symbols = []
  File.readlines(nm_path, chomp: true).each do |line|
    # nm -n format: "80000024 T start"
    match = line.match(/\A([0-9a-fA-F]+)\s+[TtWw]\s+(\S+)\z/)
    next unless match

    addr = match[1].to_i(16)
    name = match[2]
    symbols << { addr: addr, name: name }
  end

  # Sort by address and compute sizes from gaps.
  symbols.sort_by! { |s| s[:addr] }
  symbols.each_with_index do |sym, i|
    sym[:size] = if i + 1 < symbols.length
                   symbols[i + 1][:addr] - sym[:addr]
                 else
                   0
                 end
  end
  symbols
end

def parse_asm(asm_path)
  return { functions: [], lines: [] } unless asm_path && File.exist?(asm_path)

  functions = []
  lines = []
  current_file = nil
  current_function = nil

  File.readlines(asm_path, chomp: true).each do |line|
    # Function label: "80000024 <start>:"
    if (match = line.match(/\A([0-9a-fA-F]+)\s+<(\S+)>:\z/))
      addr = match[1].to_i(16)
      name = match[2]
      current_function = { addr: addr, name: name, file: current_file }
      functions << current_function
      next
    end

    # Source file reference from objdump -S: "kernel/start.c:21"  or  "/path/kernel/start.c:21"
    if (match = line.match(%r{\A(\S+/[\w.]+):(\d+)\z}))
      current_file = match[1]
      # Normalize path: strip leading absolute components, keep from "kernel/" onward.
      if (rel = current_file.match(%r{(kernel/\S+)}))
        current_file = rel[1]
      end
      next
    end

    # Also handle the simpler objdump -S source path format: "start.c:21"  (no directory)
    if (match = line.match(/\A([\w]+\.[cShsC]):(\d+)\z/))
      basename = match[1]
      current_file = "kernel/#{basename}" if current_function
      next
    end

    # Instruction line: "  80000024:\tff010113\taddi\tsp,sp,-16"
    if (match = line.match(/\A\s+([0-9a-fA-F]+):\s/))
      addr = match[1].to_i(16)

      # Check if the previous non-blank, non-instruction line is source.
      # objdump -S interleaves: source lines appear before their instructions.
      next unless current_file

      # Try to extract the source file:line from the context above.
      # In objdump -S output, source references appear as "filename:lineno" lines.
      next
    end

    # Source code lines (not addresses, not labels, not blank) - these appear
    # between file:line references and instruction lines in objdump -S output.
  end

  { functions: functions }
end

# More robust parser: reads objdump -S output line by line, tracking state.
def parse_objdump_s(asm_path)
  return { lines: [], functions: [] } unless asm_path && File.exist?(asm_path)

  result_lines = []
  functions = []
  current_file = nil
  current_line_no = nil

  content = File.read(asm_path)
  raw_lines = content.lines.map(&:chomp)

  i = 0
  while i < raw_lines.length
    line = raw_lines[i]

    # Function label: "80000024 <start>:"
    if (match = line.match(/\A([0-9a-fA-F]+)\s+<([^>]+)>:\s*\z/))
      addr = match[1].to_i(16)
      name = match[2]
      functions << { addr: addr, name: name, file: current_file }
      i += 1
      next
    end

    # Source file:line reference: "kernel/start.c:24" or "/abs/path/kernel/start.c:24"
    if (match = line.match(%r{(\S*[\w./]+\.[cSshH]):(\d+)(?:\s.*)?$}))
      raw_file = match[1]
      current_line_no = match[2].to_i
      # Normalize: keep from "kernel/" onward, or prefix "kernel/" for bare names.
      if (rel = raw_file.match(%r{(kernel/\S+)}))
        current_file = rel[1]
      elsif raw_file.match?(/\A[\w]+\.[cSshH]\z/)
        current_file = "kernel/#{raw_file}"
      else
        current_file = raw_file
      end
      i += 1
      next
    end

    # Instruction: "  80000024:\tff010113 \taddi\tsp,sp,-16"
    if (match = line.match(/\A\s+([0-9a-fA-F]+):\s/))
      addr = match[1].to_i(16)
      if current_file && current_line_no
        result_lines << { addr: addr, file: current_file, line: current_line_no }
      end
      i += 1
      next
    end

    i += 1
  end

  { lines: result_lines, functions: functions }
end

def collect_sources(source_dir, files)
  sources = {}
  return sources unless source_dir && File.directory?(source_dir)

  files.each do |relative_path|
    # Try to find the file relative to source_dir.
    # relative_path is like "kernel/start.c", source_dir might be "kernel/".
    basename = File.basename(relative_path)
    candidates = [
      File.join(source_dir, relative_path),
      File.join(source_dir, basename)
    ]
    path = candidates.find { |p| File.exist?(p) }
    if path
      sources[relative_path] = File.read(path)
    end
  end
  sources
end

def main
  options = {}
  OptionParser.new do |opts|
    opts.banner = 'Usage: extract_srcmap.rb [options]'
    opts.on('--asm PATH', 'Path to kernel.asm (objdump -S output)') { |v| options[:asm] = v }
    opts.on('--nm PATH', 'Path to kernel.nm (nm -n output)') { |v| options[:nm] = v }
    opts.on('--source-dir DIR', 'Path to kernel source directory') { |v| options[:source_dir] = v }
    opts.on('-o', '--output PATH', 'Output JSON path') { |v| options[:output] = v }
    opts.on('--no-sources', 'Omit inline source text (reference files only)') { options[:no_sources] = true }
  end.parse!

  unless options[:asm]
    warn 'error: --asm is required'
    exit 1
  end

  output_path = options[:output] || 'kernel_srcmap.json'

  # Parse nm for function boundaries.
  nm_symbols = parse_nm(options[:nm])

  # Parse objdump -S for source line mappings.
  parsed = parse_objdump_s(options[:asm])

  # Build file index.
  all_files = Set.new
  parsed[:lines].each { |l| all_files << l[:file] if l[:file] }
  parsed[:functions].each { |f| all_files << f[:file] if f[:file] }
  nm_symbols.each do |s|
    fn = parsed[:functions].find { |f| f[:addr] == s[:addr] }
    all_files << fn[:file] if fn && fn[:file]
  end
  file_list = all_files.to_a.sort
  file_index = file_list.each_with_index.to_h

  # Build functions array: prefer nm for boundaries, enrich with objdump data.
  functions = if nm_symbols.any?
                nm_symbols.map do |s|
                  fn = parsed[:functions].find { |f| f[:addr] == s[:addr] }
                  file = fn ? fn[:file] : nil
                  fi = file ? (file_index[file] || -1) : -1
                  [s[:addr], s[:size], s[:name], fi]
                end
              else
                parsed[:functions].map do |f|
                  fi = f[:file] ? (file_index[f[:file]] || -1) : -1
                  [f[:addr], 0, f[:name], fi]
                end
              end
  functions.sort_by! { |f| f[0] }

  # Build lines array.
  lines = parsed[:lines].map do |l|
    fi = file_index[l[:file]] || -1
    [l[:addr], fi, l[:line]]
  end
  lines.sort_by! { |l| l[0] }

  # Deduplicate consecutive lines with same file+line (keep first addr only).
  deduped = []
  lines.each do |entry|
    if deduped.empty? || deduped.last[1] != entry[1] || deduped.last[2] != entry[2]
      deduped << entry
    end
  end
  lines = deduped

  # Collect source files.
  sources = {}
  unless options[:no_sources]
    sources = collect_sources(options[:source_dir], file_list)
  end

  result = {
    format: 'rhdl.riscv.srcmap.v1',
    files: file_list,
    functions: functions,
    lines: lines,
    sources: sources
  }

  json = JSON.pretty_generate(result)
  File.write(output_path, json)
  puts "Wrote #{output_path} (#{file_list.length} files, #{functions.length} functions, #{lines.length} line mappings)"
end

main if __FILE__ == $PROGRAM_NAME
