#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOFTWARE_DIR="${SCRIPT_DIR}/software"
LINUX_DIR="${SOFTWARE_DIR}/linux"
PATCH_DIR="${SOFTWARE_DIR}/linux_patches"
BIN_DIR="${SOFTWARE_DIR}/bin"
DEFAULT_BUILD_DIR="${LINUX_DIR}/.rhdl-build"
BUILD_DIR="${BUILD_DIR:-${DEFAULT_BUILD_DIR}}"
INITRAMFS_PATH="${BIN_DIR}/linux_initramfs.cpio"
BUILDROOT_INITRAMFS_PATH="${BIN_DIR}/linux_initramfs_buildroot.cpio"
FS_IMG_PATH="${BIN_DIR}/linux_fs.img"
LINUX_DTS_PATH="${BIN_DIR}/rhdl_riscv_virt.dts"
LINUX_DTB_PATH="${BIN_DIR}/rhdl_riscv_virt.dtb"
LINUX_INITRAMFS_LOAD_ADDR="${LINUX_INITRAMFS_LOAD_ADDR:-0x84000000}"
LINUX_BOOT_CMDLINE="${LINUX_BOOT_CMDLINE:-console=ttyS0 earlycon=uart8250,mmio,0x10000000 rdinit=/sbin/init}"
LINUX_RISCV_ISA="${LINUX_RISCV_ISA:-rv32imasu_zicsr_zifencei}"

BUILDROOT_VERSION="${BUILDROOT_VERSION:-2025.02.1}"
BUILDROOT_CACHE_DIR="${SOFTWARE_DIR}/.cache"
BUILDROOT_DOCKER_CONTEXT="${SOFTWARE_DIR}/.docker-build"
BUILDROOT_DEFCONFIG="${BUILDROOT_DEFCONFIG:-${SOFTWARE_DIR}/buildroot/rhdl_riscv32_mmu_busybox_defconfig}"
BUILDROOT_IMAGE="${BUILDROOT_IMAGE:-linux-riscv-builder-busybox:latest}"
BUILDROOT_JOBS="${BUILDROOT_JOBS:-1}"
BUILDROOT_DL_DIR="${SOFTWARE_DIR}/.cache/buildroot-dl"
BUILDROOT_HOST_CFLAGS="${BUILDROOT_HOST_CFLAGS:--O0}"
BUILDROOT_HOST_CXXFLAGS="${BUILDROOT_HOST_CXXFLAGS:--O0}"

DEFAULT_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
if [[ -z "${DEFAULT_JOBS}" ]]; then
  DEFAULT_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

JOBS="${JOBS:-${DEFAULT_JOBS}}"
TOOLPREFIX="${TOOLPREFIX:-}"
DEFCONFIG="${DEFCONFIG:-rv32_defconfig}"
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
  ${BIN_DIR}/linux_fs.img
  ${BIN_DIR}/linux_busybox
  ${BIN_DIR}/linux_rootfs.config

Options:
  --toolprefix PREFIX      Cross-tool prefix (for example: riscv64-linux-gnu-)
  --jobs N                 Parallel make jobs for Linux kernel build (default: ${DEFAULT_JOBS})
  --defconfig TARGET       Linux defconfig target (default: ${DEFCONFIG})
  --no-min-profile         Skip optional aggressive RV32 minimum-size boot profile
  --no-rootfs              Skip BusyBox rootfs generation
  --buildroot-version VER  Buildroot version to use (default: ${BUILDROOT_VERSION})
  --buildroot-defconfig F  Buildroot defconfig path (default: ${BUILDROOT_DEFCONFIG})
  --buildroot-jobs N       Parallel jobs for Buildroot build (default: 1)
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
  BUILDROOT_IMAGE          Same as --buildroot-image
  BUILDROOT_HOST_CFLAGS    Host C flags used by Buildroot (default: -O0)
  BUILDROOT_HOST_CXXFLAGS  Host C++ flags used by Buildroot (default: -O0)
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
    return 0
  fi

  if [[ -n "${MAKE_PATH_PREFIX}" ]]; then
    PATH="${MAKE_PATH_PREFIX}:${PATH}" "${MAKE_BIN}" "$@"
    return 0
  fi

  "${MAKE_BIN}" "$@"
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

ensure_buildroot_image() {
  require_cmd docker

  if docker image inspect "${BUILDROOT_IMAGE}" >/dev/null 2>&1; then
    return 0
  fi

  if [[ ! -f "${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" ]]; then
    echo "error: docker image ${BUILDROOT_IMAGE} is missing and no Dockerfile was found at ${BUILDROOT_DOCKER_CONTEXT}/Dockerfile" >&2
    exit 1
  fi

  echo "building docker image ${BUILDROOT_IMAGE} for Buildroot tooling..."
  docker build -t "${BUILDROOT_IMAGE}" "${BUILDROOT_DOCKER_CONTEXT}"
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

build_busybox_userspace() {
  local tarball
  tarball="$(buildroot_tarball_path)"

  if [[ ! -f "${BUILDROOT_DEFCONFIG}" ]]; then
    echo "error: Buildroot defconfig not found: ${BUILDROOT_DEFCONFIG}" >&2
    exit 1
  fi

  ensure_buildroot_tarball
  ensure_buildroot_image

  mkdir -p "${BIN_DIR}" "${BUILDROOT_DL_DIR}"
  cp -f "${BUILDROOT_DEFCONFIG}" "${SOFTWARE_DIR}/.buildroot.defconfig"

  echo "building BusyBox rootfs via Buildroot (this can take a while on the first run)..."
  docker run --rm \
    -u "$(id -u):$(id -g)" \
    -e "BUILDROOT_JOBS=${BUILDROOT_JOBS}" \
    -e "BUILDROOT_VERSION=${BUILDROOT_VERSION}" \
    -e "BR2_DL_DIR=/workspace/software/.cache/buildroot-dl" \
    -e "BR2_DEFCONFIG=/workspace/software/.buildroot.defconfig" \
    -e "BR2_HOST_CFLAGS=${BUILDROOT_HOST_CFLAGS}" \
    -e "BR2_HOST_CXXFLAGS=${BUILDROOT_HOST_CXXFLAGS}" \
    -v "${tarball}:/workspace/software/.cache/buildroot.tar.gz:ro" \
    -v "${SOFTWARE_DIR}:/workspace/software" \
    "${BUILDROOT_IMAGE}" \
    bash -lc '
set -euo pipefail
rm -rf /tmp/rhdl-buildroot
mkdir -p /tmp/rhdl-buildroot/out "${BR2_DL_DIR}"
tar -xf /workspace/software/.cache/buildroot.tar.gz -C /tmp/rhdl-buildroot
BUILDROOT_SRC="/tmp/rhdl-buildroot/buildroot-${BUILDROOT_VERSION}"

make -C "${BUILDROOT_SRC}" O=/tmp/rhdl-buildroot/out BR2_DL_DIR="${BR2_DL_DIR}" BR2_DEFCONFIG="${BR2_DEFCONFIG}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}" defconfig
make -C "${BUILDROOT_SRC}" O=/tmp/rhdl-buildroot/out BR2_DL_DIR="${BR2_DL_DIR}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}" olddefconfig
make -j"${BUILDROOT_JOBS}" -C "${BUILDROOT_SRC}" O=/tmp/rhdl-buildroot/out BR2_DL_DIR="${BR2_DL_DIR}" HOSTCFLAGS="${BR2_HOST_CFLAGS}" HOSTCXXFLAGS="${BR2_HOST_CXXFLAGS}"
cp -f /tmp/rhdl-buildroot/out/images/rootfs.cpio /workspace/software/bin/linux_initramfs_buildroot.cpio
cp -f /tmp/rhdl-buildroot/out/images/rootfs.cpio /workspace/software/bin/linux_initramfs.cpio
cp -f /tmp/rhdl-buildroot/out/images/rootfs.ext2 /workspace/software/bin/linux_fs.img
cp -f /tmp/rhdl-buildroot/out/target/bin/busybox /workspace/software/bin/linux_busybox
cp -f /tmp/rhdl-buildroot/out/.config /workspace/software/bin/linux_rootfs.config
'

  rm -f "${SOFTWARE_DIR}/.buildroot.defconfig"
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
    --disable EFI \
    --disable EFI_STUB \
    --disable DMI \

  "${scripts_config}" --file "${config_file}" \
    --enable BLK_DEV_INITRD \
    --enable DEVTMPFS \
    --enable DEVTMPFS_MOUNT \
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
    --disable JUMP_LABEL \
    --disable MODULES \
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
    --enable VIRTIO_BLK \
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
  ensure_buildroot_image
fi

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
run_make "${MAKE_ARGS[@]}" "${DEFCONFIG}"

if [[ "${MIN_PROFILE}" -eq 1 ]]; then
  echo "applying aggressive rv32 minimum-size boot profile..."
  apply_minimal_rv32_profile
fi

echo "configuring linux boot cmdline..."
apply_linux_boot_cmdline

echo "finalizing kernel configuration..."
run_make "${MAKE_ARGS[@]}" olddefconfig

echo "building kernel artifacts..."
run_make -j"${JOBS}" "${MAKE_ARGS[@]}" Image vmlinux

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
  for artifact in "${INITRAMFS_PATH}" "${FS_IMG_PATH}" "${BIN_DIR}/linux_busybox"; do
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
    "${BIN_DIR}/linux_fs.img"
    "${BIN_DIR}/linux_busybox"
    "${BIN_DIR}/linux_rootfs.config"
  )
fi

echo "linux artifacts generated in ${BIN_DIR}:"
ls -lh "${artifacts[@]}"
