#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOFTWARE_DIR="${SCRIPT_DIR}"
XV6_DIR="${SOFTWARE_DIR}/xv6-rv32"
BIN_DIR="${SOFTWARE_DIR}/bin"

DEFAULT_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
if [[ -z "${DEFAULT_JOBS}" ]]; then
  DEFAULT_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

JOBS="${JOBS:-${DEFAULT_JOBS}}"
TOOLPREFIX="${TOOLPREFIX:-}"
CLEAN=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Builds xv6-rv32 and writes artifacts to:
  ${BIN_DIR}

Options:
  --toolprefix PREFIX  Cross-tool prefix (e.g. riscv32-unknown-elf-)
  --jobs N             Parallel make jobs (default: ${DEFAULT_JOBS})
  --no-clean           Skip 'make clean' before build
  -h, --help           Show this help

Environment:
  TOOLPREFIX           Same as --toolprefix
  JOBS                 Same as --jobs
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${cmd}" >&2
    exit 1
  fi
}

detect_toolprefix() {
  local candidates=(
    "riscv32-unknown-elf-"
    "riscv32-elf-"
    "riscv64-unknown-elf-"
    "riscv64-elf-"
  )
  local prefix
  for prefix in "${candidates[@]}"; do
    if command -v "${prefix}gcc" >/dev/null 2>&1 && \
       command -v "${prefix}ld" >/dev/null 2>&1 && \
       command -v "${prefix}objcopy" >/dev/null 2>&1 && \
       command -v "${prefix}objdump" >/dev/null 2>&1 && \
       command -v "${prefix}nm" >/dev/null 2>&1; then
      echo "${prefix}"
      return 0
    fi
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --toolprefix)
      TOOLPREFIX="${2:-}"
      shift 2
      ;;
    --jobs)
      JOBS="${2:-}"
      shift 2
      ;;
    --no-clean)
      CLEAN=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "${XV6_DIR}" ]]; then
  echo "error: xv6 source tree not found: ${XV6_DIR}" >&2
  echo "hint: initialize submodules: git submodule update --init --recursive" >&2
  exit 1
fi

if [[ -z "${TOOLPREFIX}" ]]; then
  TOOLPREFIX="$(detect_toolprefix || true)"
fi

if [[ -z "${TOOLPREFIX}" ]]; then
  echo "error: unable to detect a RISC-V toolchain." >&2
  echo "hint: install a riscv32/riscv64 elf toolchain and/or set --toolprefix." >&2
  exit 1
fi

require_cmd "${TOOLPREFIX}gcc"
require_cmd "${TOOLPREFIX}ld"
require_cmd "${TOOLPREFIX}objcopy"
require_cmd "${TOOLPREFIX}objdump"
require_cmd "${TOOLPREFIX}nm"

COMMON_CFLAGS="-Wall -Werror -Wno-error=infinite-recursion -O -fno-omit-frame-pointer -ggdb -MD -mcmodel=medany -ffreestanding -fno-common -nostdlib -mno-relax -I. -fno-stack-protector -fno-pie -no-pie"

MAKE_ARGS=(
  "TOOLPREFIX=${TOOLPREFIX}"
  "CFLAGS=${COMMON_CFLAGS}"
  "LDFLAGS=-z max-page-size=4096"
)

# riscv64-* toolchains can build rv32 when CC/LD are pinned to 32-bit mode.
if [[ "${TOOLPREFIX}" == riscv64-* ]]; then
  MAKE_ARGS+=(
    "CC=${TOOLPREFIX}gcc -march=rv32ima_zicsr -mabi=ilp32"
    "LD=${TOOLPREFIX}ld -melf32lriscv"
  )
else
  MAKE_ARGS+=(
    "CC=${TOOLPREFIX}gcc"
    "LD=${TOOLPREFIX}ld"
  )
fi

mkdir -p "${BIN_DIR}"

pushd "${XV6_DIR}" >/dev/null
if [[ "${CLEAN}" -eq 1 ]]; then
  make "${MAKE_ARGS[@]}" clean
fi
make -j"${JOBS}" "${MAKE_ARGS[@]}" kernel/kernel fs.img
"${TOOLPREFIX}objcopy" -S -O binary kernel/kernel "${BIN_DIR}/kernel.bin"
cp -f kernel/kernel "${BIN_DIR}/kernel.elf"
cp -f kernel/kernel.sym "${BIN_DIR}/kernel.sym"
cp -f kernel/kernel.asm "${BIN_DIR}/kernel.asm"
"${TOOLPREFIX}nm" -n kernel/kernel > "${BIN_DIR}/kernel.nm"
cp -f fs.img "${BIN_DIR}/fs.img"
popd >/dev/null

echo "xv6 artifacts generated in ${BIN_DIR}:"
ls -lh "${BIN_DIR}/kernel.bin" "${BIN_DIR}/kernel.elf" "${BIN_DIR}/kernel.sym" "${BIN_DIR}/kernel.asm" "${BIN_DIR}/kernel.nm" "${BIN_DIR}/fs.img"
