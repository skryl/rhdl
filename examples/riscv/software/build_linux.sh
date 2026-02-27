#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
SOFTWARE_DIR="${SCRIPT_DIR}"
LINUX_DIR="${SOFTWARE_DIR}/linux"
LINUX_DEFCONFIG_DIR="${SOFTWARE_DIR}/linux_configs"
PATCH_DIR="${SOFTWARE_DIR}/linux_patches"
BIN_DIR="${SOFTWARE_DIR}/bin"
DEFAULT_BUILD_DIR="${SOFTWARE_DIR}/.linux-build/linux"
BUILD_DIR="${BUILD_DIR:-${DEFAULT_BUILD_DIR}}"
INITRAMFS_PATH="${BIN_DIR}/linux_initramfs.cpio"
BUILDROOT_INITRAMFS_PATH="${BIN_DIR}/linux_initramfs_buildroot.cpio"
FS_IMG_PATH="${BIN_DIR}/linux_fs.img"
LINUX_DTS_PATH="${BIN_DIR}/rhdl_riscv_virt.dts"
LINUX_DTB_PATH="${BIN_DIR}/rhdl_riscv_virt.dtb"
LINUX_INITRAMFS_LOAD_ADDR="${LINUX_INITRAMFS_LOAD_ADDR:-0x84000000}"
LINUX_BOOT_CMDLINE="${LINUX_BOOT_CMDLINE:-console=ttyS0 earlycon=uart8250,mmio,0x10000000 rdinit=/sbin/init}"
LINUX_RISCV_ISA="${LINUX_RISCV_ISA:-rv32imafsu_zicsr_zifencei}"

BUILDROOT_VERSION="${BUILDROOT_VERSION:-2025.02.1}"
BUILDROOT_CACHE_DIR="${SOFTWARE_DIR}/.cache"
BUILDROOT_DOCKER_CONTEXT="${SOFTWARE_DIR}/.docker-build"
BUILDROOT_DEFCONFIG="${BUILDROOT_DEFCONFIG:-${SOFTWARE_DIR}/linux_configs/tiny_busybox_buildroot_defconfig}"
BUILDROOT_IMAGE="${BUILDROOT_IMAGE:-linux-riscv-builder-busybox:latest}"
BUILDROOT_JOBS="${BUILDROOT_JOBS:-}"
RETRIES="${RETRIES:-${BUILDROOT_RETRIES:-1}}"
BUILDROOT_WORKDIR="${BUILDROOT_WORKDIR:-}"
BUILDROOT_VOLUME="${BUILDROOT_VOLUME:-}"
BUILDROOT_PLATFORM="${BUILDROOT_PLATFORM:-linux/amd64}"
BUILDROOT_DL_DIR="${SOFTWARE_DIR}/.cache/buildroot-dl"
BUILDROOT_HOST_CFLAGS="${BUILDROOT_HOST_CFLAGS:--O0}"
BUILDROOT_HOST_CXXFLAGS="${BUILDROOT_HOST_CXXFLAGS:--O0}"
BUILDROOT_HOST_CC="${BUILDROOT_HOST_CC:-}"
BUILDROOT_HOST_CXX="${BUILDROOT_HOST_CXX:-}"
BUILDROOT_FORCE_GCC_HOST_TOOLS="${BUILDROOT_FORCE_GCC_HOST_TOOLS:-1}"
BUILDROOT_RETRY_MODE="${BUILDROOT_RETRY_MODE:-clean}"
BUILDROOT_RUNTIME_IMAGE="${BUILDROOT_IMAGE}"
BUILDROOT_DOCKER_PLATFORM_ARG=()
DOCKER_CONFIG_FALLBACK_DIR=""

cleanup_docker_config_fallback() {
  if [[ -n "${DOCKER_CONFIG_FALLBACK_DIR}" ]] && [[ -d "${DOCKER_CONFIG_FALLBACK_DIR}" ]]; then
    rm -rf "${DOCKER_CONFIG_FALLBACK_DIR}"
  fi
}

trap cleanup_docker_config_fallback EXIT

HOST_DEFAULT_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
if [[ -z "${HOST_DEFAULT_JOBS}" ]]; then
  HOST_DEFAULT_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi
DEFAULT_JOBS="${HOST_DEFAULT_JOBS}"
DEFAULT_BUILDROOT_JOBS="${HOST_DEFAULT_JOBS}"
DOCKER_DEFAULT_JOBS=""

JOBS="${JOBS:-}"
TOOLPREFIX="${TOOLPREFIX:-}"
DEFCONFIG="${DEFCONFIG:-tiny_kernel_defconfig}"
MIN_PROFILE="${MIN_PROFILE:-1}"
ROOTFS_BUILD=1
CLEAN=1
MAKE_PATH_PREFIX=""
MAKE_IN_DOCKER=0
MAKE_BIN="${MAKE_BIN:-${MAKE:-}}"
if [[ -z "${MAKE_BIN}" ]]; then
  if command -v gmake >/dev/null 2>&1; then
    MAKE_BIN="gmake"
  else
    MAKE_BIN="make"
  fi
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build Linux kernel + BusyBox rootfs artifacts for the RHDL RISC-V target.

Inputs:
  Linux source: ${LINUX_DIR}
  Local patches: ${PATCH_DIR}
  Buildroot defconfig: ${BUILDROOT_DEFCONFIG}

Outputs (deterministic names):
  ${BIN_DIR}/linux_kernel.bin
  ${BIN_DIR}/linux_kernel.elf
  ${BIN_DIR}/linux_kernel.map
  ${BIN_DIR}/linux_kernel.config
  ${BIN_DIR}/rhdl_riscv_virt.dts
  ${BIN_DIR}/rhdl_riscv_virt.dtb
  ${BIN_DIR}/linux_initramfs.cpio
  ${BIN_DIR}/linux_fs.img (only when enabled by Buildroot defconfig)
  ${BIN_DIR}/linux_busybox
  ${BIN_DIR}/linux_rootfs.config

Options:
  --toolprefix PREFIX      Cross-tool prefix (for example: riscv64-linux-gnu-)
  --jobs N                 Parallel make jobs for Linux kernel build (default: auto)
  --defconfig TARGET       Linux defconfig target (default: ${DEFCONFIG})
  --no-min-profile         Skip optional aggressive RV32 minimum-size boot profile
  --no-rootfs              Skip BusyBox rootfs generation
  --buildroot-version VER  Buildroot version to use (default: ${BUILDROOT_VERSION})
  --buildroot-defconfig F  Buildroot defconfig path (default: ${BUILDROOT_DEFCONFIG})
  --buildroot-jobs N       Parallel jobs for Buildroot build (default: auto)
  --retries N              Retry count for both Buildroot and kernel build steps (default: ${RETRIES})
  --buildroot-workdir DIR  Host directory bind-mounted for persistent Buildroot workspace (default: ${BUILDROOT_WORKDIR:-${SOFTWARE_DIR}/.linux-build/buildroot})
  --buildroot-volume NAME  Deprecated alias for --buildroot-workdir
  --buildroot-platform P   Docker platform for Buildroot rootfs stage (default: ${BUILDROOT_PLATFORM}, for example: linux/amd64)
  --buildroot-image IMAGE  Docker image for Buildroot (default: ${BUILDROOT_IMAGE})
  --no-clean               Skip source/build clean before applying patches
  -h, --help               Show this help

Environment:
  TOOLPREFIX               Same as --toolprefix
  JOBS                     Same as --jobs
  DEFCONFIG                Same as --defconfig
  MIN_PROFILE              Set to 0 to skip aggressive minimum profile
  BUILD_DIR                Override Linux out-of-tree build directory
  BUILDROOT_VERSION        Same as --buildroot-version
  BUILDROOT_DEFCONFIG      Same as --buildroot-defconfig
  BUILDROOT_JOBS           Same as --buildroot-jobs
  RETRIES                  Number of retries for Buildroot + kernel build steps (default: 1)
  BUILDROOT_RETRIES        Deprecated alias for RETRIES
  BUILDROOT_WORKDIR        Same as --buildroot-workdir
  BUILDROOT_VOLUME         Deprecated alias for BUILDROOT_WORKDIR
  BUILDROOT_PLATFORM       Same as --buildroot-platform (default: linux/amd64)
  BUILDROOT_IMAGE          Same as --buildroot-image
  BUILDROOT_HOST_CFLAGS    Host C flags used by Buildroot (default: -O0)
  BUILDROOT_HOST_CXXFLAGS  Host C++ flags used by Buildroot (default: -O0)
  BUILDROOT_HOST_CC        Host C compiler for Buildroot host tools (default: gcc)
  BUILDROOT_HOST_CXX       Host C++ compiler for Buildroot host tools (default: g++)
  BUILDROOT_FORCE_GCC_HOST_TOOLS
                           Force Buildroot host tools to gcc/g++ (default: 1)
  BUILDROOT_RETRY_MODE     Retry strategy: resume or clean (default: clean)
  MAKE / MAKE_BIN          GNU make command (for example: gmake)
EOF
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: required tool not found: ${cmd}" >&2
    exit 1
  fi
}

setup_make_compat() {
  local compat_dir="${BUILD_DIR}/.compat-bin"
  local src="${compat_dir}/cp.src"
  local dst="${compat_dir}/cp.dst"

  mkdir -p "${compat_dir}"
  printf 'x\n' > "${src}"

  if cp -T "${src}" "${dst}" >/dev/null 2>&1; then
    rm -f "${src}" "${dst}"
    return 0
  fi

  rm -f "${src}" "${dst}"

  cat > "${compat_dir}/cp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=()
for arg in "$@"; do
  if [[ "${arg}" == "-T" ]]; then
    continue
  fi
  args+=("${arg}")
done

exec /bin/cp "${args[@]}"
EOF
  chmod +x "${compat_dir}/cp"
  MAKE_PATH_PREFIX="${compat_dir}"
}

run_make() {
  if [[ "${MAKE_IN_DOCKER}" -eq 1 ]]; then
    docker run --rm \
      "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
      -u "$(id -u):$(id -g)" \
      -v "${REPO_ROOT}:${REPO_ROOT}" \
      -w "${REPO_ROOT}" \
      "${BUILDROOT_IMAGE}" \
      bash -lc '
set -euo pipefail
if command -v gmake >/dev/null 2>&1; then
  MAKE_BIN=gmake
else
  MAKE_BIN=make
fi
"${MAKE_BIN}" "$@"
' _ "$@"
    return $?
  fi

  if [[ -n "${MAKE_PATH_PREFIX}" ]]; then
    PATH="${MAKE_PATH_PREFIX}:${PATH}" "${MAKE_BIN}" "$@"
    return $?
  fi

  "${MAKE_BIN}" "$@"
}

run_make_with_retries() {
  local label="$1"
  shift
  local attempt=1
  local max_attempts=$((RETRIES + 1))

  while true; do
    if run_make "$@"; then
      return 0
    fi

    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      echo "error: ${label} failed after ${max_attempts} attempt(s)." >&2
      return 1
    fi

    echo "warning: ${label} failed (attempt ${attempt}/${max_attempts}). Retrying..."
    attempt=$((attempt + 1))
    sleep 2
  done
}

detect_toolprefix() {
  local candidates=(
    "riscv32-linux-gnu-"
    "riscv64-linux-gnu-"
    "riscv64-unknown-linux-gnu-"
    "riscv32-unknown-elf-"
    "riscv32-elf-"
    "riscv64-unknown-elf-"
    "riscv64-elf-"
  )
  local prefix
  for prefix in "${candidates[@]}"; do
    if command -v "${prefix}gcc" >/dev/null 2>&1 && \
       command -v "${prefix}ld" >/dev/null 2>&1; then
      echo "${prefix}"
      return 0
    fi
  done
  return 1
}

detect_toolprefix_in_docker() {
  docker run --rm \
    "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
    "${BUILDROOT_IMAGE}" \
    bash -lc '
set -euo pipefail
candidates=(
  "riscv32-linux-gnu-"
  "riscv64-linux-gnu-"
  "riscv64-unknown-linux-gnu-"
  "riscv32-unknown-elf-"
  "riscv32-elf-"
  "riscv64-unknown-elf-"
  "riscv64-elf-"
)
for prefix in "${candidates[@]}"; do
  if command -v "${prefix}gcc" >/dev/null 2>&1 && command -v "${prefix}ld" >/dev/null 2>&1; then
    echo "${prefix}"
    exit 0
  fi
done
exit 1
'
}

detect_docker_jobs() {
  docker run --rm \
    "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
    "${BUILDROOT_IMAGE}" \
    bash -lc '
set -euo pipefail
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
if [[ -z "${jobs}" ]] && command -v nproc >/dev/null 2>&1; then
  jobs="$(nproc 2>/dev/null || true)"
fi
if [[ "${jobs}" =~ ^[0-9]+$ ]] && [[ "${jobs}" -ge 1 ]]; then
  echo "${jobs}"
  exit 0
fi
exit 1
'
}

buildroot_tarball_path() {
  echo "${BUILDROOT_CACHE_DIR}/buildroot-${BUILDROOT_VERSION}.tar.gz"
}

ensure_buildroot_tarball() {
  local tarball
  tarball="$(buildroot_tarball_path)"

  mkdir -p "${BUILDROOT_CACHE_DIR}"

  if [[ ! -f "${tarball}" ]]; then
    require_cmd curl
    local url="https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.gz"
    echo "downloading Buildroot ${BUILDROOT_VERSION}..."
    curl -fsSL -o "${tarball}" "${url}"
  fi
}

setup_docker_config_fallback() {
  local docker_config_path creds_store helper

  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    return 0
  fi

  docker_config_path="${HOME}/.docker/config.json"
  if [[ ! -f "${docker_config_path}" ]]; then
    return 0
  fi

  creds_store="$(sed -n 's/.*"credsStore"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${docker_config_path}" | head -n 1)"
  if [[ -z "${creds_store}" ]]; then
    return 0
  fi

  helper="docker-credential-${creds_store}"
  if command -v "${helper}" >/dev/null 2>&1; then
    return 0
  fi

  DOCKER_CONFIG_FALLBACK_DIR="$(mktemp -d "${SOFTWARE_DIR}/.docker-config.XXXXXX")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${docker_config_path}" "${DOCKER_CONFIG_FALLBACK_DIR}/config.json" <<'PY'
import json
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]
with open(src_path, "r", encoding="utf-8") as src:
    data = json.load(src)
data.pop("credsStore", None)
data.pop("credHelpers", None)
with open(dst_path, "w", encoding="utf-8") as dst:
    json.dump(data, dst, indent=2)
    dst.write("\n")
PY
  elif command -v ruby >/dev/null 2>&1; then
    ruby -rjson -e '
src_path, dst_path = ARGV
data = JSON.parse(File.read(src_path))
data.delete("credsStore")
data.delete("credHelpers")
File.write(dst_path, JSON.pretty_generate(data) + "\n")
' "${docker_config_path}" "${DOCKER_CONFIG_FALLBACK_DIR}/config.json"
  else
    local current_context
    current_context="$(sed -n 's/.*"currentContext"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${docker_config_path}" | head -n 1)"
    cat > "${DOCKER_CONFIG_FALLBACK_DIR}/config.json" <<EOF
{
  "auths": {},
  "currentContext": "${current_context}"
}
EOF
  fi
  if [[ -d "${HOME}/.docker/contexts" ]]; then
    cp -a "${HOME}/.docker/contexts" "${DOCKER_CONFIG_FALLBACK_DIR}/contexts"
  fi
  export DOCKER_CONFIG="${DOCKER_CONFIG_FALLBACK_DIR}"
  echo "note: docker credential helper ${helper} is missing; using temporary anonymous docker config."
}

docker_platform_arch() {
  echo "${1##*/}"
}

build_buildroot_image_fallback() {
  local target_image="$1"
  local base_image container_name

  base_image="$(awk 'toupper($1) == "FROM" { print $2; exit }' "${BUILDROOT_DOCKER_CONTEXT}/Dockerfile")"
  if [[ -z "${base_image}" ]]; then
    echo "error: unable to determine base image from ${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" >&2
    exit 1
  fi

  container_name="rhdl-buildroot-image-${RANDOM}-$$"
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  docker run --name "${container_name}" --platform "${BUILDROOT_PLATFORM}" "${base_image}" bash -lc '
set -euo pipefail
apt-get update
apt-get install -y --no-install-recommends \
  bash \
  bc \
  binutils-riscv64-linux-gnu \
  bison \
  build-essential \
  ca-certificates \
  clang \
  cpio \
  file \
  flex \
  gawk \
  gcc-riscv64-linux-gnu \
  git \
  make \
  patch \
  perl \
  python3 \
  rsync \
  sed \
  tar \
  unzip \
  wget \
  xz-utils
rm -rf /var/lib/apt/lists/*
'
  docker commit "${container_name}" "${target_image}" >/dev/null
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
}

build_buildroot_image() {
  local target_image="$1"
  local expected_arch actual_arch

  docker build "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" -t "${target_image}" "${BUILDROOT_DOCKER_CONTEXT}"

  expected_arch="$(docker_platform_arch "${BUILDROOT_PLATFORM}")"
  actual_arch="$(docker image inspect "${target_image}" --format '{{.Architecture}}' 2>/dev/null || true)"
  if [[ -n "${expected_arch}" ]] && [[ -n "${actual_arch}" ]] && [[ "${actual_arch}" != "${expected_arch}" ]]; then
    echo "warning: docker build produced architecture ${actual_arch} for ${target_image}, expected ${expected_arch}."
    echo "warning: rebuilding ${target_image} via docker run/commit fallback for ${BUILDROOT_PLATFORM}."
    build_buildroot_image_fallback "${target_image}"
  fi
}

docker_image_has_tool() {
  local image="$1"
  local tool="$2"
  docker run --rm \
    "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
    "${image}" \
    bash -lc 'command -v "$1" >/dev/null 2>&1' _ "${tool}"
}

ensure_buildroot_image() {
  require_cmd docker
  local needs_build=0

  if ! docker image inspect "${BUILDROOT_IMAGE}" >/dev/null 2>&1; then
    needs_build=1
  else
    if ! docker_image_has_tool "${BUILDROOT_IMAGE}" "${BUILDROOT_HOST_CC}"; then
      echo "note: docker image ${BUILDROOT_IMAGE} does not contain ${BUILDROOT_HOST_CC}; rebuilding image."
      needs_build=1
    elif ! docker_image_has_tool "${BUILDROOT_IMAGE}" "${BUILDROOT_HOST_CXX}"; then
      echo "note: docker image ${BUILDROOT_IMAGE} does not contain ${BUILDROOT_HOST_CXX}; rebuilding image."
      needs_build=1
    fi
  fi

  if [[ "${needs_build}" -eq 0 ]]; then
    return 0
  fi

  if [[ ! -f "${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" ]]; then
    echo "error: docker image ${BUILDROOT_IMAGE} is missing and no Dockerfile was found at ${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" >&2
    exit 1
  fi

  echo "building docker image ${BUILDROOT_IMAGE} for Buildroot tooling..."
  build_buildroot_image "${BUILDROOT_IMAGE}"
}

ensure_buildroot_runtime_image() {
  ensure_buildroot_image

  if [[ "${BUILDROOT_RUNTIME_IMAGE}" == "${BUILDROOT_IMAGE}" ]]; then
    return 0
  fi

  if docker image inspect "${BUILDROOT_RUNTIME_IMAGE}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -f "${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" ]]; then
    echo "error: docker image ${BUILDROOT_RUNTIME_IMAGE} is missing and no Dockerfile was found at ${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" >&2
    exit 1
  fi

  echo "building docker image ${BUILDROOT_RUNTIME_IMAGE} for Buildroot tooling..."
  build_buildroot_image "${BUILDROOT_RUNTIME_IMAGE}"
}

prepare_buildroot_workspace_dir() {
  mkdir -p "${BUILDROOT_WORKDIR}"
}

apply_linux_patches() {
  local -a patches=()
  local patch

  if [[ -d "${PATCH_DIR}" ]]; then
    while IFS= read -r patch; do
      patches+=("${patch}")
    done < <(find "${PATCH_DIR}" -maxdepth 1 -type f \( -name '*.patch' -o -name '*.diff' \) -print | LC_ALL=C sort)
  fi

  if [[ "${#patches[@]}" -eq 0 ]]; then
    echo "no linux patches found in ${PATCH_DIR}; continuing without local patches."
    return 0
  fi

  echo "applying linux patch series from ${PATCH_DIR}:"
  for patch in "${patches[@]}"; do
    echo "  - $(basename "${patch}")"
    if git -C "${LINUX_DIR}" apply --check "${patch}"; then
      git -C "${LINUX_DIR}" apply "${patch}"
    elif git -C "${LINUX_DIR}" apply --reverse --check "${patch}"; then
      echo "    already applied; skipping."
    else
      echo "error: patch failed pre-check: ${patch}" >&2
      exit 1
    fi
  done
}

sync_custom_linux_defconfig() {
  local src dst
  src="${LINUX_DEFCONFIG_DIR}/${DEFCONFIG}"
  dst="${LINUX_DIR}/arch/riscv/configs/${DEFCONFIG}"

  if [[ -f "${src}" ]]; then
    mkdir -p "$(dirname "${dst}")"
    cp -f "${src}" "${dst}"
    return 0
  fi

  if [[ "${DEFCONFIG}" == "rhdl_rv32_virt_min_defconfig" || "${DEFCONFIG}" == "tiny_kernel_defconfig" ]]; then
    echo "error: missing default custom defconfig: ${src}" >&2
    exit 1
  fi
}

build_busybox_userspace() {
  local tarball buildroot_defconfig_copy buildroot_attempt_log failed_pkg
  local attempt=1
  local max_attempts=$((RETRIES + 1))
  local -a buildroot_docker_user_args
  local -a buildroot_docker_env_args
  tarball="$(buildroot_tarball_path)"

  buildroot_docker_user_args=(-u "$(id -u):$(id -g)")
  buildroot_docker_env_args=()
  if [[ "$(uname -s)" == "Darwin" ]]; then
    # Docker Desktop bind mounts can reject chmod/chown from non-root UIDs during
    # incremental Buildroot package rebuilds (for example host-tar tests files).
    buildroot_docker_user_args=()
    # Buildroot host-tar configure refuses root unless this is explicitly set.
    buildroot_docker_env_args=(-e "FORCE_UNSAFE_CONFIGURE=1")
  fi

  if [[ ! -f "${BUILDROOT_DEFCONFIG}" ]]; then
    echo "error: Buildroot defconfig not found: ${BUILDROOT_DEFCONFIG}" >&2
    exit 1
  fi

  ensure_buildroot_tarball
  ensure_buildroot_runtime_image

  mkdir -p "${BIN_DIR}" "${BUILDROOT_DL_DIR}"
  buildroot_defconfig_copy="${SOFTWARE_DIR}/.buildroot.defconfig"
  buildroot_attempt_log="${SOFTWARE_DIR}/.buildroot.retry.log"
  cp -f "${BUILDROOT_DEFCONFIG}" "${buildroot_defconfig_copy}"
  prepare_buildroot_workspace_dir
  trap 'rm -f "${buildroot_defconfig_copy}" "${buildroot_attempt_log}"' RETURN

  echo "building BusyBox rootfs via Buildroot (workspace bind: ${BUILDROOT_WORKDIR})..."
  while true; do
    if docker run --rm \
      "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
      "${buildroot_docker_user_args[@]}" \
      "${buildroot_docker_env_args[@]}" \
      -e "BUILDROOT_JOBS=${BUILDROOT_JOBS}" \
      -e "BUILDROOT_VERSION=${BUILDROOT_VERSION}" \
      -e "BR2_DL_DIR=/workspace/software/.cache/buildroot-dl" \
      -e "BR2_DEFCONFIG=/workspace/software/.buildroot.defconfig" \
      -e "BR2_HOST_CFLAGS=${BUILDROOT_HOST_CFLAGS}" \
      -e "BR2_HOST_CXXFLAGS=${BUILDROOT_HOST_CXXFLAGS}" \
      -e "BUILDROOT_HOST_CC=${BUILDROOT_HOST_CC}" \
      -e "BUILDROOT_HOST_CXX=${BUILDROOT_HOST_CXX}" \
      -e "BUILDROOT_WORK_DIR=/workspace/buildroot-work" \
      -v "${tarball}:/workspace/software/.cache/buildroot.tar.gz:ro" \
      -v "${SOFTWARE_DIR}:/workspace/software" \
      -v "${BUILDROOT_WORKDIR}:/workspace/buildroot-work" \
      "${BUILDROOT_RUNTIME_IMAGE}" \
      bash -lc '
set -euo pipefail
mkdir -p "${BUILDROOT_WORK_DIR}" "${BR2_DL_DIR}"
BUILDROOT_SRC="${BUILDROOT_WORK_DIR}/buildroot-${BUILDROOT_VERSION}"
BUILDROOT_OUT="${BUILDROOT_WORK_DIR}/out"
BUILDROOT_HOST_SIGNATURE="${BUILDROOT_HOST_CC}|${BUILDROOT_HOST_CXX}|${BR2_HOST_CFLAGS}|${BR2_HOST_CXXFLAGS}"
BUILDROOT_HOST_MARKER="${BUILDROOT_OUT}/.rhdl-host-toolchain"
BUILDROOT_EXTRACT_DIR="$(mktemp -d /tmp/rhdl-buildroot-extract-${BUILDROOT_VERSION}.XXXXXX)"
BUILDROOT_STAGE_DIR="${BUILDROOT_WORK_DIR}/.stage-${BUILDROOT_VERSION}.$$"
if [[ ! -f "${BUILDROOT_SRC}/Makefile" ]] || \
   [[ ! -f "${BUILDROOT_SRC}/Config.in" ]] || \
   [[ ! -f "${BUILDROOT_SRC}/docs/manual/manual.mk" ]] || \
   [[ ! -f "${BUILDROOT_SRC}/support/scripts/setlocalversion" ]] || \
   [[ ! -f "${BUILDROOT_SRC}/support/scripts/br2-external" ]] || \
   [[ ! -d "${BUILDROOT_SRC}/package" ]]; then
  rm -rf "${BUILDROOT_SRC}" "${BUILDROOT_STAGE_DIR}"
  tar -xf /workspace/software/.cache/buildroot.tar.gz -C "${BUILDROOT_EXTRACT_DIR}"
  if [[ ! -d "${BUILDROOT_EXTRACT_DIR}/buildroot-${BUILDROOT_VERSION}" ]]; then
    echo "error: Buildroot tarball did not contain expected directory buildroot-${BUILDROOT_VERSION}" >&2
    exit 1
  fi
  mkdir -p "${BUILDROOT_STAGE_DIR}"
  cp -a "${BUILDROOT_EXTRACT_DIR}/buildroot-${BUILDROOT_VERSION}/." "${BUILDROOT_STAGE_DIR}/"
  mv "${BUILDROOT_STAGE_DIR}" "${BUILDROOT_SRC}"
fi
rm -rf "${BUILDROOT_EXTRACT_DIR}"

mkdir -p "${BUILDROOT_OUT}"
if [[ -f "${BUILDROOT_HOST_MARKER}" ]]; then
  PREV_BUILDROOT_HOST_SIGNATURE="$(cat "${BUILDROOT_HOST_MARKER}" 2>/dev/null || true)"
  if [[ "${PREV_BUILDROOT_HOST_SIGNATURE}" != "${BUILDROOT_HOST_SIGNATURE}" ]]; then
    echo "note: Buildroot host compiler settings changed; pruning host package outputs."
    rm -rf "${BUILDROOT_OUT}/host" "${BUILDROOT_OUT}/staging"
    if [[ -d "${BUILDROOT_OUT}/build" ]]; then
      find "${BUILDROOT_OUT}/build" -mindepth 1 -maxdepth 1 -name 'host-*' -exec rm -rf {} +
      rm -rf "${BUILDROOT_OUT}/build/buildroot-config"
    fi
  fi
fi
printf "%s\n" "${BUILDROOT_HOST_SIGNATURE}" > "${BUILDROOT_HOST_MARKER}"

if [[ "${BUILDROOT_HOST_CC}" == "gcc" ]] && [[ -d "${BUILDROOT_OUT}/build" ]]; then
  if grep -Rqs "CC=.*clang" "${BUILDROOT_OUT}/build"/host-*/config.log 2>/dev/null || \
     grep -Rqs "CXX=.*clang" "${BUILDROOT_OUT}/build"/host-*/config.log 2>/dev/null; then
    echo "note: detected stale clang-configured Buildroot host package state; pruning host package outputs."
    rm -rf "${BUILDROOT_OUT}/host" "${BUILDROOT_OUT}/staging"
    find "${BUILDROOT_OUT}/build" -mindepth 1 -maxdepth 1 -name 'host-*' -exec rm -rf {} +
    rm -rf "${BUILDROOT_OUT}/build/buildroot-config"
  fi
fi

if [[ "${BUILDROOT_HOST_CC}" == clang* ]] || [[ "${BUILDROOT_HOST_CXX}" == clang* ]]; then
  python3 - "${BUILDROOT_SRC}/support/dependencies/dependencies.sh" <<\PY
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
sq = chr(39)
probe_candidates = [
    "sed -n " + sq + "/^gcc version/p" + sq,
    "sed -n " + sq + "/^\\(gcc\\|clang\\) version/p" + sq,
]
parse_candidates = [
    "s/^gcc version \\([0-9\\.]\\)/\\1/g",
    "s/^\\(gcc\\|clang\\) version \\([0-9\\.]\\)/\\2/g",
]
new_probe = "sed -n " + sq + "/gcc version/p;/clang version/p" + sq
new_parse = "s/^.*\\(gcc\\|clang\\) version \\([0-9\\.]\\)/\\2/g"
for candidate in probe_candidates:
    text = text.replace(candidate, new_probe)
for candidate in parse_candidates:
    text = text.replace(candidate, new_parse)
path.write_text(text)
PY
fi

make -C "${BUILDROOT_SRC}" O="${BUILDROOT_OUT}" BR2_DL_DIR="${BR2_DL_DIR}" BR2_DEFCONFIG="${BR2_DEFCONFIG}" HOSTCC="${BUILDROOT_HOST_CC}" HOSTCXX="${BUILDROOT_HOST_CXX}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}" HOST_CFLAGS="${BR2_HOST_CFLAGS}" HOST_CXXFLAGS="${BR2_HOST_CXXFLAGS}" defconfig
make -C "${BUILDROOT_SRC}" O="${BUILDROOT_OUT}" BR2_DL_DIR="${BR2_DL_DIR}" HOSTCC="${BUILDROOT_HOST_CC}" HOSTCXX="${BUILDROOT_HOST_CXX}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}" HOST_CFLAGS="${BR2_HOST_CFLAGS}" HOST_CXXFLAGS="${BR2_HOST_CXXFLAGS}" olddefconfig
make -j"${BUILDROOT_JOBS}" -C "${BUILDROOT_SRC}" O="${BUILDROOT_OUT}" BR2_DL_DIR="${BR2_DL_DIR}" HOSTCC="${BUILDROOT_HOST_CC}" HOSTCXX="${BUILDROOT_HOST_CXX}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}" HOST_CFLAGS="${BR2_HOST_CFLAGS}" HOST_CXXFLAGS="${BR2_HOST_CXXFLAGS}"
ROOTFS_CPIO_SOURCE="${BUILDROOT_OUT}/images/rootfs.cpio"
if [[ ! -f "${ROOTFS_CPIO_SOURCE}" ]]; then
  if [[ -f "${BUILDROOT_OUT}/images/rootfs.cpio.gz" ]]; then
    ROOTFS_CPIO_SOURCE="${BUILDROOT_OUT}/images/rootfs.cpio.gz"
  else
    echo "error: Buildroot did not produce a rootfs.cpio artifact." >&2
    echo "hint: inspect ${BUILDROOT_OUT}/images for generated artifacts." >&2
    ls -1 "${BUILDROOT_OUT}/images" >&2 || true
    exit 1
  fi
fi
cp -f "${ROOTFS_CPIO_SOURCE}" /workspace/software/bin/linux_initramfs_buildroot.cpio
cp -f "${ROOTFS_CPIO_SOURCE}" /workspace/software/bin/linux_initramfs.cpio
if [[ -f "${BUILDROOT_OUT}/images/rootfs.ext2" ]]; then
  cp -f "${BUILDROOT_OUT}/images/rootfs.ext2" /workspace/software/bin/linux_fs.img
else
  rm -f /workspace/software/bin/linux_fs.img
fi
      cp -f "${BUILDROOT_OUT}/target/bin/busybox" /workspace/software/bin/linux_busybox
      cp -f "${BUILDROOT_OUT}/.config" /workspace/software/bin/linux_rootfs.config
' 2>&1 | tee "${buildroot_attempt_log}"
    then
      break
    fi

    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      echo "error: Buildroot rootfs build failed after ${max_attempts} attempt(s)." >&2
      exit 1
    fi

    failed_pkg="$(sed -n 's/^>>>[[:space:]]\+\([^[:space:]]\+\).*/\1/p' "${buildroot_attempt_log}" | tail -n 1 || true)"
    if [[ -z "${failed_pkg}" ]]; then
      # Fallback: derive package from Buildroot out/build path in compiler errors
      # (for example: .../out/build/host-tar-1.35/... -> host-tar).
      failed_pkg="$(sed -n 's#.*\/out\/build\/\([^/]*\)-[0-9][0-9A-Za-z._-]*\/.*#\1#p' "${buildroot_attempt_log}" | tail -n 1 || true)"
    fi
    if [[ "${BUILDROOT_RETRY_MODE}" == "clean" ]] && [[ -n "${failed_pkg}" ]]; then
      echo "warning: targeted clean for failed Buildroot package '${failed_pkg}' before retry..."
      docker run --rm \
        "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
        "${buildroot_docker_user_args[@]}" \
        "${buildroot_docker_env_args[@]}" \
        -e "BUILDROOT_VERSION=${BUILDROOT_VERSION}" \
        -e "BUILDROOT_WORK_DIR=/workspace/buildroot-work" \
        -e "FAILED_PKG=${failed_pkg}" \
        -v "${BUILDROOT_WORKDIR}:/workspace/buildroot-work" \
        "${BUILDROOT_RUNTIME_IMAGE}" \
        bash -lc '
set -euo pipefail
BUILDROOT_SRC="${BUILDROOT_WORK_DIR}/buildroot-${BUILDROOT_VERSION}"
BUILDROOT_OUT="${BUILDROOT_WORK_DIR}/out"
if [[ -f "${BUILDROOT_SRC}/Makefile" ]] && [[ -d "${BUILDROOT_OUT}" ]] && [[ -n "${FAILED_PKG}" ]]; then
  make -C "${BUILDROOT_SRC}" O="${BUILDROOT_OUT}" "${FAILED_PKG}-dirclean" || true
  find "${BUILDROOT_OUT}/build" -mindepth 1 -maxdepth 1 -name "${FAILED_PKG}-*" -exec rm -rf {} +
  rm -f "${BUILDROOT_OUT}/build/.stamp_${FAILED_PKG}_*" 2>/dev/null || true
fi
'
    elif [[ "${BUILDROOT_RETRY_MODE}" == "clean" ]]; then
      echo "warning: retry requested with BUILDROOT_RETRY_MODE=clean but failed package could not be identified; retrying without cleanup."
    fi

    echo "warning: Buildroot rootfs build failed (attempt ${attempt}/${max_attempts}). Retrying..."
    attempt=$((attempt + 1))
    sleep 2
  done

  trap - RETURN
  rm -f "${buildroot_defconfig_copy}" "${buildroot_attempt_log}"
}

build_linux_dtb() {
  local dtc_bin="${BUILD_DIR}/scripts/dtc/dtc"
  if [[ ! -x "${dtc_bin}" ]]; then
    echo "error: dtc binary not found: ${dtc_bin}" >&2
    echo "hint: ensure the kernel build completed successfully before DTB generation." >&2
    exit 1
  fi

  local initrd_start=$((LINUX_INITRAMFS_LOAD_ADDR))
  local initrd_end=${initrd_start}
  if [[ -f "${INITRAMFS_PATH}" ]]; then
    local initramfs_size
    initramfs_size="$(wc -c < "${INITRAMFS_PATH}")"
    initrd_end=$((initrd_start + initramfs_size))
  fi

  local initrd_start_hi initrd_start_lo initrd_end_hi initrd_end_lo
  local initrd_start_hi_hex initrd_start_lo_hex initrd_end_hi_hex initrd_end_lo_hex
  initrd_start_hi=$(((initrd_start >> 32) & 0xFFFFFFFF))
  initrd_start_lo=$((initrd_start & 0xFFFFFFFF))
  initrd_end_hi=$(((initrd_end >> 32) & 0xFFFFFFFF))
  initrd_end_lo=$((initrd_end & 0xFFFFFFFF))
  printf -v initrd_start_hi_hex "0x%08x" "${initrd_start_hi}"
  printf -v initrd_start_lo_hex "0x%08x" "${initrd_start_lo}"
  printf -v initrd_end_hi_hex "0x%08x" "${initrd_end_hi}"
  printf -v initrd_end_lo_hex "0x%08x" "${initrd_end_lo}"

  cat > "${LINUX_DTS_PATH}" <<EOF
/dts-v1/;

/ {
  #address-cells = <2>;
  #size-cells = <2>;
  compatible = "rhdl,riscv-virt", "riscv-virtio";
  model = "rhdl-riscv-virt";

  chosen {
    stdout-path = "/soc/serial@10000000:115200n8";
    bootargs = "${LINUX_BOOT_CMDLINE}";
    linux,initrd-start = <${initrd_start_hi_hex} ${initrd_start_lo_hex}>;
    linux,initrd-end = <${initrd_end_hi_hex} ${initrd_end_lo_hex}>;
  };

  memory@80000000 {
    device_type = "memory";
    reg = <0x0 0x80000000 0x0 0x08000000>;
  };

  cpus {
    #address-cells = <1>;
    #size-cells = <0>;
    timebase-frequency = <10000000>;

    cpu0: cpu@0 {
      device_type = "cpu";
      reg = <0>;
      status = "okay";
      compatible = "riscv";
      riscv,isa = "${LINUX_RISCV_ISA}";

      cpu0_intc: interrupt-controller {
        #interrupt-cells = <1>;
        interrupt-controller;
        compatible = "riscv,cpu-intc";
      };
    };
  };

  soc {
    #address-cells = <2>;
    #size-cells = <2>;
    compatible = "simple-bus";
    ranges;

    clint@2000000 {
      compatible = "sifive,clint0";
      reg = <0x0 0x02000000 0x0 0x00010000>;
      interrupts-extended = <&cpu0_intc 3 &cpu0_intc 7>;
    };

    plic: interrupt-controller@c000000 {
      compatible = "sifive,plic-1.0.0";
      reg = <0x0 0x0c000000 0x0 0x04000000>;
      #address-cells = <0>;
      #interrupt-cells = <1>;
      interrupt-controller;
      interrupts-extended = <&cpu0_intc 11 &cpu0_intc 9>;
      riscv,ndev = <31>;
    };

    serial@10000000 {
      compatible = "ns16550a";
      reg = <0x0 0x10000000 0x0 0x100>;
      clock-frequency = <1843200>;
      reg-shift = <0>;
      reg-io-width = <1>;
      interrupt-parent = <&plic>;
      interrupts = <10>;
    };

    virtio_block@10001000 {
      compatible = "virtio,mmio";
      reg = <0x0 0x10001000 0x0 0x1000>;
      interrupt-parent = <&plic>;
      interrupts = <1>;
    };
  };
};
EOF

  if [[ "${MAKE_IN_DOCKER}" -eq 1 ]]; then
    docker run --rm \
      "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
      -u "$(id -u):$(id -g)" \
      -v "${REPO_ROOT}:${REPO_ROOT}" \
      -w "${REPO_ROOT}" \
      "${BUILDROOT_IMAGE}" \
      bash -lc '"$1" -q -I dts -O dtb -o "$2" "$3"' _ "${dtc_bin}" "${LINUX_DTB_PATH}" "${LINUX_DTS_PATH}"
  else
    "${dtc_bin}" -q -I dts -O dtb -o "${LINUX_DTB_PATH}" "${LINUX_DTS_PATH}"
  fi
}

apply_minimal_rv32_profile() {
  local config_file="${BUILD_DIR}/.config"
  local scripts_config="${LINUX_DIR}/scripts/config"

  if [[ ! -x "${scripts_config}" ]]; then
    echo "error: missing linux config helper: ${scripts_config}" >&2
    exit 1
  fi

  "${scripts_config}" --file "${config_file}" \
    --enable ARCH_VIRT \
    --enable ARCH_RV32I \
    --enable 32BIT \
    --enable MMU \
    --enable NONPORTABLE \
    --disable ARCH_ANDES \
    --disable ARCH_ANLOGIC \
    --disable ARCH_ESWIN \
    --disable ARCH_MICROCHIP_POLARFIRE \
    --disable ARCH_MICROCHIP \
    --disable ARCH_RENESAS \
    --disable ARCH_SIFIVE \
    --disable ARCH_SOPHGO \
    --disable ARCH_SPACEMIT \
    --disable ARCH_STARFIVE \
    --disable SOC_STARFIVE \
    --disable ARCH_SUNXI \
    --disable ARCH_TENSTORRENT \
    --disable ARCH_THEAD \
    --disable ARCH_CANAAN \
    --disable SOC_CANAAN_K210 \
    --disable ERRATA_ANDES \
    --disable ERRATA_ANDES_CMO \
    --disable ERRATA_MIPS \
    --disable ERRATA_MIPS_P8700_PAUSE_OPCODE \
    --disable ERRATA_SIFIVE \
    --disable ERRATA_SIFIVE_CIP_453 \
    --disable ERRATA_SIFIVE_CIP_1200 \
    --disable ERRATA_STARFIVE_JH7100 \
    --disable ERRATA_THEAD \
    --disable ERRATA_THEAD_MAE \
    --disable ERRATA_THEAD_CMO \
    --disable ERRATA_THEAD_PMU \
    --disable ERRATA_THEAD_GHOSTWRITE \
    --disable EFI \
    --disable EFI_STUB \
    --disable DMI \
    --disable RISCV_ISA_VENDOR_EXT \
    --disable RISCV_ISA_VENDOR_EXT_ANDES \
    --disable RISCV_ISA_VENDOR_EXT_MIPS \
    --disable RISCV_ISA_VENDOR_EXT_SIFIVE \
    --disable RISCV_ISA_VENDOR_EXT_THEAD \
    --disable RISCV_ISA_XTHEADVECTOR \
    --disable RISCV_ISA_ZABHA \
    --enable FPU \
    --enable RISCV_ISA_C \
    --enable RISCV_ISA_V \
    --enable RISCV_ISA_ZBA \
    --enable RISCV_ISA_ZBB \
    --enable RISCV_ISA_ZBKB \
    --enable RISCV_ISA_ZBC \
    --enable RISCV_ISA_ZAWRS \
    --enable RISCV_ISA_ZICBOM \
    --enable RISCV_ISA_ZICBOZ \
    --enable RISCV_ISA_ZICBOP \
    --enable RISCV_ISA_ZACAS \
    --enable RISCV_ISA_V_DEFAULT_ENABLE

  "${scripts_config}" --file "${config_file}" \
    --enable RISCV_EMULATED_UNALIGNED_ACCESS \
    --disable RISCV_PROBE_UNALIGNED_ACCESS \
    --disable RISCV_SLOW_UNALIGNED_ACCESS \
    --disable RISCV_EFFICIENT_UNALIGNED_ACCESS \
    --enable RISCV_SLOW_VECTOR_UNALIGNED_ACCESS \
    --disable RISCV_PROBE_VECTOR_UNALIGNED_ACCESS \
    --disable RISCV_EFFICIENT_VECTOR_UNALIGNED_ACCESS

  "${scripts_config}" --file "${config_file}" \
    --enable BLK_DEV_INITRD \
    --enable OF \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
    --enable BINFMT_ELF \
    --enable BINFMT_SCRIPT \
    --enable PRINTK \
    --enable TTY \
    --enable SERIAL_8250 \
    --enable SERIAL_8250_CONSOLE \
    --set-val SERIAL_8250_NR_UARTS 1 \
    --set-val SERIAL_8250_RUNTIME_UARTS 1 \
    --enable SERIAL_OF_PLATFORM \
    --enable SERIAL_EARLYCON_RISCV_SBI \
    --enable PROC_FS \
    --enable SYSFS \
    --enable SHMEM \
    --enable TMPFS \
    --disable RD_GZIP \
    --disable RD_BZIP2 \
    --disable RD_LZMA \
    --disable RD_XZ \
    --disable RD_LZO \
    --disable RD_LZ4 \
    --disable RD_ZSTD \
    --disable FHANDLE \
    --disable SIGNALFD \
    --disable TIMERFD \
    --disable EVENTFD \
    --disable AIO \
    --disable IO_URING \
    --disable ADVISE_SYSCALLS \
    --disable DNOTIFY \
    --disable INOTIFY_USER \
    --disable AUTOFS_FS \
    --disable CONFIGFS_FS \
    --enable RISCV_SBI_V01 \
    --enable CC_OPTIMIZE_FOR_SIZE \
    --disable CRYPTO \
    --disable CRYPTO_HW \
    --disable CRYPTO_DEV_VIRTIO \
    --disable CRYPTO_JITTERENTROPY \
    --disable SMP \
    --disable RISCV_ALTERNATIVE \
    --disable RISCV_ALTERNATIVE_EARLY \
    --disable RISCV_ISA_FALLBACK \
    --disable JUMP_LABEL \
    --disable SUSPEND \
    --disable MODULES \
    --disable BLOCK \
    --disable SWAP \
    --disable PREEMPT_LAZY \
    --disable BPF \
    --disable BPF_SYSCALL \
    --disable PERF_EVENTS \
    --disable KPROBES \
    --disable UPROBES \
    --disable KVM \
    --disable KVM_GENERIC_HARDWARE_ENABLING \
    --disable KVM_MMIO \
    --disable NET \
    --disable PCI \
    --disable USB_SUPPORT \
    --disable SCSI \
    --disable ATA \
    --disable DRM \
    --disable FB \
    --disable SOUND \
    --disable INPUT \
    --disable HID \
    --disable I2C \
    --disable SPI \
    --disable IOMMU_SUPPORT \
    --disable MEDIA_SUPPORT \
    --disable THERMAL \
    --disable CPU_IDLE \
    --disable CPU_FREQ \
    --disable PM \
    --disable MTD \
    --disable MD \
    --enable VIRTIO \
    --disable VIRTIO_BLK \
    --enable VIRTIO_MMIO \
    --disable VIRTIO_CONSOLE \
    --disable VIRTIO_BALLOON \
    --disable VIRTIO_INPUT \
    --disable FW_LOADER \
    --disable INPUT \
    --disable SERIO \
    --disable MOUSE_PS2 \
    --disable MMC \
    --disable RTC_CLASS \
    --disable EXTCON \
    --disable VT \
    --disable LEGACY_PTYS \
    --disable BTRFS_FS \
    --disable EXT4_FS \
    --disable FUSE_FS \
    --disable NFS_FS \
    --disable 9P_FS \
    --disable OVERLAY_FS \
    --disable ISO9660_FS \
    --disable MSDOS_FS \
    --disable VFAT_FS \
    --disable HW_RANDOM \
    --disable HW_RANDOM_ATMEL \
    --disable HW_RANDOM_VIRTIO \
    --disable HW_RANDOM_JH7110 \
    --disable TRACING \
    --disable TRACEPOINTS \
    --disable EVENT_TRACING \
    --disable FTRACE \
    --disable DEBUG_KERNEL \
    --disable LOCK_DEBUGGING_SUPPORT \
    --set-str INITRAMFS_SOURCE "" \
    --set-val LOG_BUF_SHIFT 12
}

apply_linux_boot_cmdline() {
  local config_file="${BUILD_DIR}/.config"
  local scripts_config="${LINUX_DIR}/scripts/config"

  if [[ ! -x "${scripts_config}" ]]; then
    echo "error: missing linux config helper: ${scripts_config}" >&2
    exit 1
  fi

  "${scripts_config}" --file "${config_file}" \
    --set-str CMDLINE "${LINUX_BOOT_CMDLINE}" \
    --enable CMDLINE_FORCE
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
    --defconfig)
      DEFCONFIG="${2:-}"
      shift 2
      ;;
    --no-min-profile)
      MIN_PROFILE=0
      shift
      ;;
    --no-rootfs)
      ROOTFS_BUILD=0
      shift
      ;;
    --buildroot-version)
      BUILDROOT_VERSION="${2:-}"
      shift 2
      ;;
    --buildroot-defconfig)
      BUILDROOT_DEFCONFIG="${2:-}"
      shift 2
      ;;
    --buildroot-jobs)
      BUILDROOT_JOBS="${2:-}"
      shift 2
      ;;
    --retries)
      RETRIES="${2:-}"
      shift 2
      ;;
    --buildroot-retries)
      RETRIES="${2:-}"
      shift 2
      ;;
    --buildroot-workdir)
      BUILDROOT_WORKDIR="${2:-}"
      shift 2
      ;;
    --buildroot-volume)
      BUILDROOT_WORKDIR="${2:-}"
      shift 2
      ;;
    --buildroot-platform)
      BUILDROOT_PLATFORM="${2:-}"
      shift 2
      ;;
    --buildroot-image)
      BUILDROOT_IMAGE="${2:-}"
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

if [[ -z "${BUILDROOT_WORKDIR}" ]] && [[ -n "${BUILDROOT_VOLUME}" ]]; then
  BUILDROOT_WORKDIR="${BUILDROOT_VOLUME}"
fi

if [[ -z "${BUILDROOT_WORKDIR}" ]]; then
  BUILDROOT_WORKDIR="${SOFTWARE_DIR}/.linux-build/buildroot"
fi

if [[ "${BUILDROOT_WORKDIR}" != /* ]]; then
  BUILDROOT_WORKDIR="${PWD}/${BUILDROOT_WORKDIR}"
fi

if [[ -z "${BUILDROOT_PLATFORM}" ]]; then
  BUILDROOT_PLATFORM="linux/amd64"
fi

if [[ -n "${BUILDROOT_PLATFORM}" ]]; then
  platform_suffix="${BUILDROOT_PLATFORM//\//-}"
  image_repo="${BUILDROOT_IMAGE}"
  image_tag="latest"
  if [[ "${BUILDROOT_IMAGE}" == *:* && "${BUILDROOT_IMAGE##*/}" == *:* ]]; then
    image_repo="${BUILDROOT_IMAGE%:*}"
    image_tag="${BUILDROOT_IMAGE##*:}"
  fi

  if [[ "${image_repo}" != *"-${platform_suffix}" ]]; then
    image_repo="${image_repo}-${platform_suffix}"
  fi

  BUILDROOT_IMAGE="${image_repo}:${image_tag}"
  BUILDROOT_DOCKER_PLATFORM_ARG=(--platform "${BUILDROOT_PLATFORM}")
  BUILDROOT_RUNTIME_IMAGE="${BUILDROOT_IMAGE}"
fi

if [[ -z "${BUILDROOT_HOST_CC}" ]]; then
  BUILDROOT_HOST_CC="gcc"
fi
if [[ -z "${BUILDROOT_HOST_CXX}" ]]; then
  BUILDROOT_HOST_CXX="g++"
fi

if [[ "${BUILDROOT_FORCE_GCC_HOST_TOOLS}" == "1" ]]; then
  if [[ "${BUILDROOT_HOST_CC}" != "gcc" || "${BUILDROOT_HOST_CXX}" != "g++" ]]; then
    echo "note: forcing Buildroot host compilers to gcc/g++ (set BUILDROOT_FORCE_GCC_HOST_TOOLS=0 to opt out)."
  fi
  BUILDROOT_HOST_CC="gcc"
  BUILDROOT_HOST_CXX="g++"
fi

if [[ ! -d "${LINUX_DIR}" ]]; then
  echo "error: linux source tree not found: ${LINUX_DIR}" >&2
  echo "hint: initialize submodule with:" >&2
  echo "  git submodule update --init --recursive ${LINUX_DIR}" >&2
  exit 1
fi

require_cmd git

if [[ "$(uname -s)" == "Darwin" ]]; then
  MAKE_IN_DOCKER=1
fi

if [[ "${MAKE_IN_DOCKER}" -eq 0 ]]; then
  require_cmd "${MAKE_BIN}"
fi

if [[ "${MAKE_IN_DOCKER}" -eq 1 || "${ROOTFS_BUILD}" -eq 1 ]]; then
  require_cmd docker
  setup_docker_config_fallback
  ensure_buildroot_image
  DOCKER_DEFAULT_JOBS="$(detect_docker_jobs || true)"
fi

if [[ "${MAKE_IN_DOCKER}" -eq 1 && -n "${DOCKER_DEFAULT_JOBS}" ]]; then
  DEFAULT_JOBS="${DOCKER_DEFAULT_JOBS}"
fi
if [[ -n "${DOCKER_DEFAULT_JOBS}" ]]; then
  DEFAULT_BUILDROOT_JOBS="${DOCKER_DEFAULT_JOBS}"
fi

if [[ -z "${JOBS}" ]]; then
  JOBS="${DEFAULT_JOBS}"
fi
if [[ -z "${BUILDROOT_JOBS}" ]]; then
  BUILDROOT_JOBS="${DEFAULT_BUILDROOT_JOBS}"
fi

if [[ "$(uname -s)" == "Darwin" ]] && [[ "${BUILDROOT_PLATFORM}" == "linux/amd64" ]] && [[ "${BUILDROOT_JOBS}" =~ ^[0-9]+$ ]] && [[ "${BUILDROOT_JOBS}" -gt 1 ]]; then
  echo "note: forcing buildroot_jobs=1 on macOS for linux/amd64 emulation stability."
  BUILDROOT_JOBS=1
fi

if ! [[ "${JOBS}" =~ ^[0-9]+$ ]] || [[ "${JOBS}" -lt 1 ]]; then
  echo "error: --jobs must be a positive integer (got: ${JOBS})" >&2
  exit 1
fi
if ! [[ "${BUILDROOT_JOBS}" =~ ^[0-9]+$ ]] || [[ "${BUILDROOT_JOBS}" -lt 1 ]]; then
  echo "error: --buildroot-jobs must be a positive integer (got: ${BUILDROOT_JOBS})" >&2
  exit 1
fi
if ! [[ "${RETRIES}" =~ ^[0-9]+$ ]]; then
  echo "error: --retries must be a non-negative integer (got: ${RETRIES})" >&2
  exit 1
fi
if [[ "${BUILDROOT_RETRY_MODE}" != "resume" && "${BUILDROOT_RETRY_MODE}" != "clean" ]]; then
  echo "error: BUILDROOT_RETRY_MODE must be one of 'resume' or 'clean' (got: ${BUILDROOT_RETRY_MODE})" >&2
  exit 1
fi

if [[ "${MAKE_IN_DOCKER}" -eq 1 && -n "${DOCKER_DEFAULT_JOBS}" && "${DOCKER_DEFAULT_JOBS}" -lt "${HOST_DEFAULT_JOBS}" ]]; then
  echo "note: docker runtime exposes ${DOCKER_DEFAULT_JOBS} CPU(s) (host has ${HOST_DEFAULT_JOBS})."
  echo "note: for faster Linux builds with Lima, increase VM CPUs (for example: limactl edit <instance>; then restart)."
fi

echo "build parallelism: kernel_jobs=${JOBS} buildroot_jobs=${BUILDROOT_JOBS}"
echo "buildroot host toolchain: cc=${BUILDROOT_HOST_CC} cxx=${BUILDROOT_HOST_CXX}"

if [[ -z "${TOOLPREFIX}" ]]; then
  if [[ "${MAKE_IN_DOCKER}" -eq 1 ]]; then
    TOOLPREFIX="$(detect_toolprefix_in_docker || true)"
  else
    TOOLPREFIX="$(detect_toolprefix || true)"
  fi
fi

if [[ -z "${TOOLPREFIX}" ]]; then
  echo "error: unable to detect a RISC-V cross-toolchain." >&2
  echo "hint: set --toolprefix (for example riscv64-linux-gnu-)." >&2
  exit 1
fi

if [[ "${MAKE_IN_DOCKER}" -eq 0 ]]; then
  require_cmd "${TOOLPREFIX}gcc"
  require_cmd "${TOOLPREFIX}ld"
  require_cmd "${TOOLPREFIX}objcopy"
fi

if [[ "${CLEAN}" -eq 1 ]]; then
  echo "cleaning linux source tree and previous build outputs..."
  git -C "${LINUX_DIR}" reset --hard HEAD >/dev/null
  git -C "${LINUX_DIR}" clean -fdx >/dev/null
  rm -rf "${BUILD_DIR}"
  rm -f "${LINUX_DTS_PATH}" "${LINUX_DTB_PATH}"
  if [[ "${ROOTFS_BUILD}" -eq 1 ]]; then
    rm -f "${INITRAMFS_PATH}" "${BUILDROOT_INITRAMFS_PATH}" "${FS_IMG_PATH}" "${BIN_DIR}/linux_busybox" "${BIN_DIR}/linux_rootfs.config"
  fi
fi

mkdir -p "${BIN_DIR}" "${BUILD_DIR}"
setup_make_compat

apply_linux_patches
sync_custom_linux_defconfig

if [[ "${ROOTFS_BUILD}" -eq 1 ]]; then
  build_busybox_userspace
fi

if [[ "${ROOTFS_BUILD}" -eq 1 && ! -f "${INITRAMFS_PATH}" ]]; then
  echo "error: missing Buildroot initramfs artifact: ${INITRAMFS_PATH}" >&2
  echo "hint: verify Buildroot build completed and produced images/rootfs.cpio." >&2
  exit 1
fi

MAKE_ARGS=(
  "-C" "${LINUX_DIR}"
  "O=${BUILD_DIR}"
  "ARCH=riscv"
  "CROSS_COMPILE=${TOOLPREFIX}"
)

echo "configuring kernel with ${DEFCONFIG}..."
run_make_with_retries "kernel defconfig (${DEFCONFIG})" "${MAKE_ARGS[@]}" "${DEFCONFIG}"

if [[ "${MIN_PROFILE}" -eq 1 ]]; then
  echo "applying aggressive rv32 minimum-size boot profile..."
  apply_minimal_rv32_profile
fi

echo "configuring linux boot cmdline..."
apply_linux_boot_cmdline

echo "finalizing kernel configuration..."
run_make_with_retries "kernel olddefconfig" "${MAKE_ARGS[@]}" olddefconfig

if [[ "${MIN_PROFILE}" -eq 1 ]]; then
  if ! grep -Eq '^CONFIG_PRINTK=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_PRINTK=y for Linux UART boot visibility." >&2
    echo "hint: verify printk support is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_TTY=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_TTY=y for Linux UART console support." >&2
    echo "hint: verify TTY support is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_SERIAL_8250_CONSOLE=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_SERIAL_8250_CONSOLE=y for Linux UART console support." >&2
    echo "hint: verify 8250 console support is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_BINFMT_ELF=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_BINFMT_ELF=y to execute /sbin/init from initramfs." >&2
    echo "hint: verify ELF binary format support is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_BINFMT_SCRIPT=(y|m)' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_BINFMT_SCRIPT for BusyBox init scripts." >&2
    echo "hint: verify script binary format support is enabled in final kernel configuration." >&2
    exit 1
  fi
  if grep -Eq '^CONFIG_RISCV_PROBE_UNALIGNED_ACCESS=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE must disable CONFIG_RISCV_PROBE_UNALIGNED_ACCESS on this simulator path." >&2
    echo "hint: keep emulated or fixed unaligned access mode to avoid boot-time probe stalls." >&2
    exit 1
  fi
  if grep -Eq '^CONFIG_RISCV_PROBE_VECTOR_UNALIGNED_ACCESS=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE must disable CONFIG_RISCV_PROBE_VECTOR_UNALIGNED_ACCESS on this simulator path." >&2
    echo "hint: keep fixed vector unaligned mode to avoid boot-time probe stalls." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_FPU=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_FPU=y for this Linux profile." >&2
    echo "hint: verify FPU is not disabled by profile overrides or defconfig." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZBA=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZBA=y for this phase profile." >&2
    echo "hint: verify Zba is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZBB=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZBB=y for this phase profile." >&2
    echo "hint: verify Zbb is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZBKB=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZBKB=y for this phase profile." >&2
    echo "hint: verify Zbkb is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZBC=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZBC=y for this phase profile." >&2
    echo "hint: verify Zbc is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZAWRS=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZAWRS=y for this phase profile." >&2
    echo "hint: verify Zawrs is enabled in final kernel configuration." >&2
    exit 1
  fi
  if grep -Eq '^CONFIG_TOOLCHAIN_HAS_ZACAS=y' "${BUILD_DIR}/.config"; then
    if ! grep -Eq '^CONFIG_RISCV_ISA_ZACAS=y' "${BUILD_DIR}/.config"; then
      echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZACAS=y when toolchain supports Zacas." >&2
      echo "hint: verify Zacas is enabled in final kernel configuration." >&2
      exit 1
    fi
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZICBOM=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZICBOM=y for this phase profile." >&2
    echo "hint: verify Zicbom is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZICBOZ=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZICBOZ=y for this phase profile." >&2
    echo "hint: verify Zicboz is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_ZICBOP=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_ZICBOP=y for this phase profile." >&2
    echo "hint: verify Zicbop is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_C=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_C=y for this phase profile." >&2
    echo "hint: verify C extension is enabled in final kernel configuration." >&2
    exit 1
  fi
  if ! grep -Eq '^CONFIG_RISCV_ISA_V=y' "${BUILD_DIR}/.config"; then
    echo "error: MIN_PROFILE requires CONFIG_RISCV_ISA_V=y for this phase profile." >&2
    echo "hint: verify V extension is enabled in final kernel configuration." >&2
    exit 1
  fi
fi

echo "building kernel artifacts..."
run_make_with_retries "kernel Image/vmlinux build" -j"${JOBS}" "${MAKE_ARGS[@]}" Image vmlinux

if [[ "${ROOTFS_BUILD}" -eq 1 && ! -f "${INITRAMFS_PATH}" ]]; then
  echo "error: missing Buildroot initramfs artifact: ${INITRAMFS_PATH}" >&2
  echo "hint: verify Buildroot build completed and produced images/rootfs.cpio." >&2
  exit 1
fi

echo "generating default Linux DTB..."
build_linux_dtb

IMAGE_SRC="${BUILD_DIR}/arch/riscv/boot/Image"
VMLINUX_SRC="${BUILD_DIR}/vmlinux"
MAP_SRC="${BUILD_DIR}/System.map"
CONFIG_SRC="${BUILD_DIR}/.config"

for artifact in "${IMAGE_SRC}" "${VMLINUX_SRC}" "${MAP_SRC}" "${CONFIG_SRC}"; do
  if [[ ! -f "${artifact}" ]]; then
    echo "error: expected build artifact not found: ${artifact}" >&2
    exit 1
  fi
done

if [[ ! -f "${LINUX_DTB_PATH}" ]]; then
  echo "error: expected DTB artifact not found: ${LINUX_DTB_PATH}" >&2
  exit 1
fi

if [[ "${ROOTFS_BUILD}" -eq 1 ]]; then
  for artifact in "${INITRAMFS_PATH}" "${BIN_DIR}/linux_busybox" "${BIN_DIR}/linux_rootfs.config"; do
    if [[ ! -f "${artifact}" ]]; then
      echo "error: expected rootfs artifact not found: ${artifact}" >&2
      exit 1
    fi
  done
fi

cp -f "${IMAGE_SRC}" "${BIN_DIR}/linux_kernel.bin"
cp -f "${VMLINUX_SRC}" "${BIN_DIR}/linux_kernel.elf"
cp -f "${MAP_SRC}" "${BIN_DIR}/linux_kernel.map"
cp -f "${CONFIG_SRC}" "${BIN_DIR}/linux_kernel.config"

# Generate source-interleaved disassembly and source map for web simulator.
echo "generating source map artifacts..."
if [[ "${MAKE_IN_DOCKER}" -eq 1 ]]; then
  docker run --rm \
    "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
    -u "$(id -u):$(id -g)" \
    -v "${REPO_ROOT}:${REPO_ROOT}" \
    -w "${REPO_ROOT}" \
    "${BUILDROOT_IMAGE}" \
    bash -lc '"$@"' _ "${TOOLPREFIX}objdump" -S "${VMLINUX_SRC}" > "${BIN_DIR}/linux_kernel.asm" || true
  docker run --rm \
    "${BUILDROOT_DOCKER_PLATFORM_ARG[@]}" \
    -u "$(id -u):$(id -g)" \
    -v "${REPO_ROOT}:${REPO_ROOT}" \
    -w "${REPO_ROOT}" \
    "${BUILDROOT_IMAGE}" \
    bash -lc '"$@"' _ "${TOOLPREFIX}nm" -n "${VMLINUX_SRC}" > "${BIN_DIR}/linux_kernel.nm" || true
elif command -v "${TOOLPREFIX}objdump" >/dev/null 2>&1; then
  "${TOOLPREFIX}objdump" -S "${VMLINUX_SRC}" > "${BIN_DIR}/linux_kernel.asm" || true
  "${TOOLPREFIX}nm" -n "${VMLINUX_SRC}" > "${BIN_DIR}/linux_kernel.nm" || true
else
  echo "warning: ${TOOLPREFIX}objdump not found; skipping source map generation"
fi

EXTRACT_SCRIPT="${SOFTWARE_DIR}/extract_srcmap.rb"
if command -v ruby >/dev/null 2>&1 && [[ -f "${EXTRACT_SCRIPT}" ]] && [[ -f "${BIN_DIR}/linux_kernel.asm" ]]; then
  ruby "${EXTRACT_SCRIPT}" \
    --asm "${BIN_DIR}/linux_kernel.asm" \
    --nm "${BIN_DIR}/linux_kernel.nm" \
    --source-dir "${LINUX_DIR}" \
    --strip-prefix "${LINUX_DIR}" \
    --strip-prefix "${BUILD_DIR}" \
    -o "${BIN_DIR}/linux_kernel_srcmap.json"
else
  echo "warning: ruby not found or source map inputs missing; skipping source map extraction"
fi

declare -a artifacts=(
  "${BIN_DIR}/linux_kernel.bin"
  "${BIN_DIR}/linux_kernel.elf"
  "${BIN_DIR}/linux_kernel.map"
  "${BIN_DIR}/linux_kernel.config"
  "${BIN_DIR}/rhdl_riscv_virt.dts"
  "${BIN_DIR}/rhdl_riscv_virt.dtb"
)

if [[ "${ROOTFS_BUILD}" -eq 1 ]]; then
  artifacts+=(
    "${BIN_DIR}/linux_initramfs.cpio"
    "${BIN_DIR}/linux_busybox"
    "${BIN_DIR}/linux_rootfs.config"
  )
  if [[ -f "${BIN_DIR}/linux_fs.img" ]]; then
    artifacts+=("${BIN_DIR}/linux_fs.img")
  fi
fi

echo "linux artifacts generated in ${BIN_DIR}:"
ls -lh "${artifacts[@]}"
