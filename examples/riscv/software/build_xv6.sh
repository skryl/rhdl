#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOFTWARE_DIR="${SCRIPT_DIR}"
XV6_DIR="${SOFTWARE_DIR}/xv6"
PATCH_DIR="${SOFTWARE_DIR}/xv6_patches"
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

Inputs:
  xv6 source: ${XV6_DIR}
  local patches: ${PATCH_DIR}

Builds xv6 (RV32) and writes artifacts to:
  source: ${XV6_DIR}
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
  echo "hint: initialize submodule with:" >&2
  echo "  git submodule update --init --recursive ${XV6_DIR}" >&2
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
require_cmd git

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

apply_xv6_patches() {
  local -a patches=()
  local patch

  if [[ -d "${PATCH_DIR}" ]]; then
    while IFS= read -r patch; do
      patches+=("${patch}")
    done < <(find "${PATCH_DIR}" -maxdepth 1 -type f \( -name '*.patch' -o -name '*.diff' \) -print | LC_ALL=C sort)
  fi

  if [[ "${#patches[@]}" -eq 0 ]]; then
    echo "no xv6 patches found in ${PATCH_DIR}; continuing without local patches."
    return 0
  fi

  echo "applying xv6 patch series from ${PATCH_DIR}:"
  for patch in "${patches[@]}"; do
    echo "  - $(basename "${patch}")"
    if git -C "${XV6_DIR}" apply --check "${patch}"; then
      git -C "${XV6_DIR}" apply "${patch}"
    elif git -C "${XV6_DIR}" apply --reverse --check "${patch}"; then
      echo "    already applied; skipping."
    else
      echo "error: patch failed pre-check: ${patch}" >&2
      exit 1
    fi
  done
}

apply_xv6_patches

pushd "${XV6_DIR}" >/dev/null
if [[ "${CLEAN}" -eq 1 ]]; then
  make "${MAKE_ARGS[@]}" clean
fi
make -j"${JOBS}" "${MAKE_ARGS[@]}" kernel/kernel fs.img
rm -f "${BIN_DIR}/kernel.bin" "${BIN_DIR}/kernel.elf" "${BIN_DIR}/kernel.sym" "${BIN_DIR}/kernel.asm" "${BIN_DIR}/kernel.nm" "${BIN_DIR}/kernel_srcmap.json" "${BIN_DIR}/fs.img"
rm -f "${BIN_DIR}/xv6_kernel.bin" "${BIN_DIR}/xv6_kernel.elf" "${BIN_DIR}/xv6_kernel.sym" "${BIN_DIR}/xv6_kernel.asm" "${BIN_DIR}/xv6_kernel.nm" "${BIN_DIR}/xv6_kernel_srcmap.json" "${BIN_DIR}/xv6_fs.img"
"${TOOLPREFIX}objcopy" -S -O binary kernel/kernel "${BIN_DIR}/xv6_kernel.bin"
cp -f kernel/kernel "${BIN_DIR}/xv6_kernel.elf"
cp -f kernel/kernel.sym "${BIN_DIR}/xv6_kernel.sym"
cp -f kernel/kernel.asm "${BIN_DIR}/xv6_kernel.asm"
"${TOOLPREFIX}nm" -n kernel/kernel > "${BIN_DIR}/xv6_kernel.nm"
cp -f fs.img "${BIN_DIR}/xv6_fs.img"
popd >/dev/null

# Extract source map for web simulator (address → source file/line + function mapping).
EXTRACT_SCRIPT="${SOFTWARE_DIR}/extract_srcmap.rb"
if command -v ruby >/dev/null 2>&1 && [[ -f "${EXTRACT_SCRIPT}" ]]; then
  ruby "${EXTRACT_SCRIPT}" \
    --asm "${BIN_DIR}/xv6_kernel.asm" \
    --nm "${BIN_DIR}/xv6_kernel.nm" \
    --source-dir "${XV6_DIR}" \
    -o "${BIN_DIR}/xv6_kernel_srcmap.json"
else
  echo "warning: ruby not found or extract_srcmap.rb missing; skipping source map generation"
fi

echo "xv6 artifacts generated in ${BIN_DIR}:"
ls -lh "${BIN_DIR}/xv6_kernel.bin" "${BIN_DIR}/xv6_kernel.elf" "${BIN_DIR}/xv6_kernel.sym" "${BIN_DIR}/xv6_kernel.asm" "${BIN_DIR}/xv6_kernel.nm" "${BIN_DIR}/xv6_kernel_srcmap.json" "${BIN_DIR}/xv6_fs.img" 2>/dev/null || true
