#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${ROOT_DIR}/source"
BIN_DIR="${ROOT_DIR}/bin"
TMP_DIR="${ROOT_DIR}/tmp"

CLANG_BIN="${CLANG_BIN:-clang}"
OBJCOPY_BIN="${OBJCOPY_BIN:-llvm-objcopy}"

PROGRAMS=(
  "04_cellular_automaton"
  "05_mandelbrot_fixedpoint"
  "06_prime_sieve"
)

mkdir -p "${BIN_DIR}" "${TMP_DIR}"

for program in "${PROGRAMS[@]}"; do
  src="${SOURCE_DIR}/${program}.S"
  obj="${TMP_DIR}/${program}.o"
  bin="${BIN_DIR}/${program}.bin"

  "${CLANG_BIN}" -target i386-none-elf -c "${src}" -o "${obj}"
  "${OBJCOPY_BIN}" -O binary "${obj}" "${bin}"
done

echo "Built ${#PROGRAMS[@]} ao486 complex program binaries into ${BIN_DIR}"
