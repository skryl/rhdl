#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOFTWARE_DIR="${SCRIPT_DIR}/software"
LINUX_DIR="${SOFTWARE_DIR}/linux"
PATCH_DIR="${SOFTWARE_DIR}/linux_patches"
BIN_DIR="${SOFTWARE_DIR}/bin"
DEFAULT_BUILD_DIR="${LINUX_DIR}/.rhdl-build"
BUILD_DIR="${BUILD_DIR:-${DEFAULT_BUILD_DIR}}"
INITRAMFS_PATH="${BIN_DIR}/linux_initramfs.cpio"
FS_IMG_PATH="${BIN_DIR}/linux_fs.img"

DEFAULT_JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
if [[ -z "${DEFAULT_JOBS}" ]]; then
  DEFAULT_JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

JOBS="${JOBS:-${DEFAULT_JOBS}}"
TOOLPREFIX="${TOOLPREFIX:-}"
DEFCONFIG="${DEFCONFIG:-rv32_nommu_virt_defconfig}"
MIN_PROFILE="${MIN_PROFILE:-1}"
CLEAN=1
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

Build Linux kernel artifacts for the RHDL RISC-V target.

Inputs:
  Linux source: ${LINUX_DIR}
  Local patches: ${PATCH_DIR}

Outputs (deterministic names):
  ${BIN_DIR}/linux_kernel.bin
  ${BIN_DIR}/linux_kernel.elf
  ${BIN_DIR}/linux_kernel.map
  ${BIN_DIR}/linux_kernel.config
  ${BIN_DIR}/linux_initramfs.cpio
  ${BIN_DIR}/linux_fs.img

Options:
  --toolprefix PREFIX    Cross-tool prefix (for example: riscv64-linux-gnu-)
  --jobs N               Parallel make jobs (default: ${DEFAULT_JOBS})
  --defconfig TARGET     Linux defconfig target (default: ${DEFCONFIG})
  --no-min-profile       Skip aggressive RV32 minimum-size boot profile
  --no-clean             Skip source/build clean before applying patches
  -h, --help             Show this help

Environment:
  TOOLPREFIX             Same as --toolprefix
  JOBS                   Same as --jobs
  DEFCONFIG              Same as --defconfig
  MIN_PROFILE            Set to 0 to skip aggressive minimum profile
  BUILD_DIR              Override Linux out-of-tree build directory
  FS_IMG_MB              Linux ext2 fs image size in MiB (default: 16)
  MAKE / MAKE_BIN        GNU make command (for example: gmake)
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

build_default_initramfs() {
  local staging_dir="${BUILD_DIR}/.initramfs"
  local root_dir="${staging_dir}/root"
  local init_src="${staging_dir}/init.c"
  local init_obj="${staging_dir}/init.o"
  local init_elf="${staging_dir}/init.elf"
  local init_code="${staging_dir}/init.code"
  local init_path="${root_dir}/init"
  local cpio_tool="${staging_dir}/gen_init_cpio"
  local cpio_list="${staging_dir}/initramfs.list"

  rm -rf "${staging_dir}"
  mkdir -p "${root_dir}/dev"

  cat > "${init_src}" <<'EOF'
typedef unsigned short u16;
static int console_fd = -1;

static inline long sys_call6(long n, long a0, long a1, long a2, long a3, long a4, long a5) {
  register long r0 asm("a0") = a0;
  register long r1 asm("a1") = a1;
  register long r2 asm("a2") = a2;
  register long r3 asm("a3") = a3;
  register long r4 asm("a4") = a4;
  register long r5 asm("a5") = a5;
  register long r7 asm("a7") = n;
  asm volatile ("ecall"
    : "+r"(r0)
    : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7)
    : "memory");
  return r0;
}

static void setup_stdio(void) {
  sys_call6(57, 0, 0, 0, 0, 0, 0);
  sys_call6(57, 1, 0, 0, 0, 0, 0);
  sys_call6(57, 2, 0, 0, 0, 0, 0);

  long fd = sys_call6(56, -100, (long)"/dev/console", 2, 0, 0, 0);
  if (fd < 0) {
    return;
  }
  console_fd = (int)fd;

  if (fd != 0) {
    sys_call6(24, fd, 0, 0, 0, 0, 0);
    sys_call6(57, fd, 0, 0, 0, 0, 0);
  }

  if (sys_call6(23, 0, 0, 0, 0, 0, 0) < 0) {
    return;
  }
  (void)sys_call6(23, 0, 0, 0, 0, 0, 0);
}

static long c_strlen(const char *s) {
  long n = 0;
  while (s[n] != 0) {
    n += 1;
  }
  return n;
}

static void write_all(int fd, const char *buf, long len) {
  long off = 0;
  while (off < len) {
    long n = sys_call6(64, fd, (long)(buf + off), len - off, 0, 0, 0);
    if (n <= 0) {
      return;
    }
    off += n;
  }
}

static void print_str(const char *s) {
  long len = c_strlen(s);
  if (console_fd >= 0) {
    write_all(console_fd, s, len);
    return;
  }

  write_all(1, s, len);
  write_all(2, s, len);
  write_all(0, s, len);
}

static int streq(const char *a, const char *b) {
  long i = 0;
  while (a[i] != 0 || b[i] != 0) {
    if (a[i] != b[i]) {
      return 0;
    }
    i += 1;
  }
  return 1;
}

static int starts_with(const char *s, const char *prefix) {
  long i = 0;
  while (prefix[i] != 0) {
    if (s[i] != prefix[i]) {
      return 0;
    }
    i += 1;
  }
  return 1;
}

static long read_line(char *buf, long max_len) {
  long i = 0;
  while (i < max_len - 1) {
    long n = sys_call6(63, 0, (long)(buf + i), 1, 0, 0, 0);
    if (n <= 0) {
      break;
    }
    char c = buf[i];
    if (c == '\r' || c == '\n') {
      break;
    }
    i += 1;
  }
  buf[i] = 0;
  return i;
}

static void cmd_ls(void) {
  char dent_buf[1024];
  long fd = sys_call6(56, -100, (long)".", 0, 0, 0, 0);
  if (fd < 0) {
    print_str("ls: open failed\n");
    return;
  }

  for (;;) {
    long nread = sys_call6(61, fd, (long)dent_buf, sizeof(dent_buf), 0, 0, 0);
    if (nread <= 0) {
      break;
    }

    long off = 0;
    while (off < nread) {
      u16 reclen = *(u16 *)(dent_buf + off + 16);
      char *name = dent_buf + off + 19;
      int is_dot = (name[0] == '.' && name[1] == 0);
      int is_dotdot = (name[0] == '.' && name[1] == '.' && name[2] == 0);
      if (!is_dot && !is_dotdot) {
        print_str(name);
        print_str("\n");
      }
      if (reclen == 0) {
        off = nread;
      } else {
        off += reclen;
      }
    }
  }

  sys_call6(57, fd, 0, 0, 0, 0, 0);
}

void _start(void) {
  char line[128];
  setup_stdio();
  print_str("rhdl mini init\n");
  for (;;) {
    print_str("rhdl-sh$ ");
    long n = read_line(line, sizeof(line));
    if (n <= 0) {
      continue;
    }

    if (streq(line, "ls")) {
      cmd_ls();
      continue;
    }
    if (streq(line, "help")) {
      print_str("commands: ls, help, echo <text>, exit\n");
      continue;
    }
    if (starts_with(line, "echo ")) {
      print_str(line + 5);
      print_str("\n");
      continue;
    }
    if (streq(line, "exit")) {
      for (;;) { }
    }
    print_str("unknown command\n");
  }
}
EOF

  "${TOOLPREFIX}gcc" -Os -nostdlib -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -fno-asynchronous-unwind-tables -fno-unwind-tables -mno-relax -mcmodel=medany -msmall-data-limit=0 -march=rv32ima -mabi=ilp32 -c "${init_src}" -o "${init_obj}"
  "${TOOLPREFIX}ld" -m elf32lriscv --no-relax -nostdlib -Ttext 0x0 -e _start "${init_obj}" -o "${init_elf}"
  "${TOOLPREFIX}objcopy" -O binary "${init_elf}" "${init_code}"

  python3 - "${init_elf}" "${init_code}" "${init_path}" <<'PY'
import struct
import sys

elf_path, code_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
elf = open(elf_path, "rb").read()
code = open(code_path, "rb").read()

if elf[:4] != b"\x7fELF":
    raise SystemExit("init.elf is not an ELF file")
if elf[4] != 1 or elf[5] != 1:
    raise SystemExit("init.elf must be ELF32 little-endian")

ehdr = struct.unpack_from("<16sHHIIIIIHHHHHH", elf, 0)
e_entry = ehdr[4]
e_phoff = ehdr[5]
e_phentsize = ehdr[9]
e_phnum = ehdr[10]

PT_LOAD = 1
PF_W = 2
rw_segment = None
for i in range(e_phnum):
    phoff = e_phoff + i * e_phentsize
    p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from("<IIIIIIII", elf, phoff)
    if p_type != PT_LOAD:
      continue
    if p_flags & PF_W:
      if rw_segment is None or p_vaddr < rw_segment[0]:
          rw_segment = (p_vaddr, p_filesz, p_memsz)

header_size = 0x40
entry = header_size + e_entry
if rw_segment is None:
    data_start = header_size + len(code)
    data_end = data_start
    bss_end = data_start
else:
    data_start = header_size + rw_segment[0]
    data_end = header_size + rw_segment[0] + rw_segment[1]
    bss_end = header_size + rw_segment[0] + rw_segment[2]

header = b"bFLT" + struct.pack(
    ">15I",
    4,           # rev
    entry,       # entry
    data_start,  # data_start
    data_end,    # data_end
    bss_end,     # bss_end
    0x4000,      # stack_size
    data_end,    # reloc_start
    0,           # reloc_count
    1,           # FLAT_FLAG_RAM
    0,           # build_date
    0, 0, 0, 0, 0
)

with open(out_path, "wb") as fh:
    fh.write(header)
    fh.write(code)
PY

  chmod 0755 "${init_path}"

  cc -O2 "${LINUX_DIR}/usr/gen_init_cpio.c" -o "${cpio_tool}"
  cat > "${cpio_list}" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
file /init ${init_path} 0755 0 0
EOF
  "${cpio_tool}" "${cpio_list}" > "${INITRAMFS_PATH}"
}

apply_default_initramfs_source() {
  local config_file="${BUILD_DIR}/.config"
  local scripts_config="${LINUX_DIR}/scripts/config"

  "${scripts_config}" --file "${config_file}" \
    --set-str INITRAMFS_SOURCE "${INITRAMFS_PATH}"
}

build_default_fs_image() {
  local root_dir="${BUILD_DIR}/.initramfs/root"
  local fs_img_mb="${FS_IMG_MB:-16}"

  rm -f "${FS_IMG_PATH}"
  dd if=/dev/zero of="${FS_IMG_PATH}" bs=1M count="${fs_img_mb}" status=none
  mke2fs -q -t ext2 -d "${root_dir}" -F "${FS_IMG_PATH}"
}

apply_minimal_rv32_profile() {
  local config_file="${BUILD_DIR}/.config"
  local scripts_config="${LINUX_DIR}/scripts/config"

  if [[ ! -x "${scripts_config}" ]]; then
    echo "error: missing linux config helper: ${scripts_config}" >&2
    exit 1
  fi

  "${scripts_config}" --file "${config_file}" \
    --disable RISCV_ISA_C \
    --disable RISCV_ISA_V \
    --disable RISCV_ISA_V_DEFAULT_ENABLE \
    --disable FPU \
    --disable RISCV_ISA_ZBA \
    --disable RISCV_ISA_ZBB \
    --disable RISCV_ISA_ZBKB \
    --disable RISCV_ISA_ZACAS \
    --disable RISCV_ISA_ZAWRS \
    --disable RISCV_ISA_ZICBOZ \
    --disable RISCV_ISA_VENDOR_EXT \
    --disable RISCV_ISA_VENDOR_EXT_ANDES \
    --disable RISCV_ISA_VENDOR_EXT_MIPS \
    --disable RISCV_ISA_VENDOR_EXT_SIFIVE \
    --disable RISCV_ISA_VENDOR_EXT_THEAD \
    --disable RISCV_ISA_XTHEADVECTOR \
    --disable SMP \
    --disable MODULES \
    --disable BLOCK \
    --disable VIRTIO \
    --disable VIRTIO_MENU \
    --disable VIRTIO_MMIO \
    --disable VIRTIO_MMIO_CMDLINE_DEVICES \
    --disable EXT2_FS \
    --disable PROC_FS \
    --disable SYSFS \
    --disable TMPFS \
    --disable SHMEM \
    --disable NET \
    --disable PCI \
    --disable USB_SUPPORT \
    --disable INPUT \
    --disable HID \
    --disable MEDIA_SUPPORT \
    --disable DRM \
    --disable FB \
    --disable FRAMEBUFFER_CONSOLE \
    --disable VT \
    --disable SYSVIPC \
    --disable POSIX_MQUEUE \
    --disable FUTEX \
    --disable COREDUMP

  "${scripts_config}" --file "${config_file}" \
    --enable EMBEDDED \
    --set-val LOG_BUF_SHIFT 12 \
    --set-str CMDLINE "console=ttyS0 earlycon=uart8250,mmio,0x10000000 rdinit=/init" \
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

require_cmd "${MAKE_BIN}"
require_cmd git
require_cmd python3
require_cmd cc
require_cmd mke2fs

if [[ -z "${TOOLPREFIX}" ]]; then
  TOOLPREFIX="$(detect_toolprefix || true)"
fi

if [[ -z "${TOOLPREFIX}" ]]; then
  echo "error: unable to detect a RISC-V cross-toolchain." >&2
  echo "hint: set --toolprefix (for example riscv64-linux-gnu-)." >&2
  exit 1
fi

require_cmd "${TOOLPREFIX}gcc"
require_cmd "${TOOLPREFIX}ld"
require_cmd "${TOOLPREFIX}objcopy"

if [[ "${CLEAN}" -eq 1 ]]; then
  echo "cleaning linux source tree and previous build outputs..."
  git -C "${LINUX_DIR}" reset --hard HEAD >/dev/null
  git -C "${LINUX_DIR}" clean -fdx >/dev/null
  rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BIN_DIR}" "${BUILD_DIR}"

apply_linux_patches

MAKE_ARGS=(
  "-C" "${LINUX_DIR}"
  "O=${BUILD_DIR}"
  "ARCH=riscv"
  "CROSS_COMPILE=${TOOLPREFIX}"
)

echo "configuring kernel with ${DEFCONFIG}..."
"${MAKE_BIN}" "${MAKE_ARGS[@]}" "${DEFCONFIG}"

echo "generating default initramfs artifact..."
build_default_initramfs
echo "generating default fs image artifact..."
build_default_fs_image
apply_default_initramfs_source

if [[ "${MIN_PROFILE}" -eq 1 ]]; then
  echo "applying aggressive rv32 minimum-size boot profile..."
  apply_minimal_rv32_profile
fi

echo "finalizing kernel configuration..."
"${MAKE_BIN}" "${MAKE_ARGS[@]}" olddefconfig

echo "building kernel artifacts..."
"${MAKE_BIN}" -j"${JOBS}" "${MAKE_ARGS[@]}" Image vmlinux

IMAGE_SRC="${BUILD_DIR}/arch/riscv/boot/Image"
VMLINUX_SRC="${BUILD_DIR}/vmlinux"
MAP_SRC="${BUILD_DIR}/System.map"
CONFIG_SRC="${BUILD_DIR}/.config"

for artifact in "${IMAGE_SRC}" "${VMLINUX_SRC}" "${MAP_SRC}" "${CONFIG_SRC}" "${INITRAMFS_PATH}" "${FS_IMG_PATH}"; do
  if [[ ! -f "${artifact}" ]]; then
    echo "error: expected build artifact not found: ${artifact}" >&2
    exit 1
  fi
done

cp -f "${IMAGE_SRC}" "${BIN_DIR}/linux_kernel.bin"
cp -f "${VMLINUX_SRC}" "${BIN_DIR}/linux_kernel.elf"
cp -f "${MAP_SRC}" "${BIN_DIR}/linux_kernel.map"
cp -f "${CONFIG_SRC}" "${BIN_DIR}/linux_kernel.config"

echo "linux kernel artifacts generated in ${BIN_DIR}:"
ls -lh \
  "${BIN_DIR}/linux_kernel.bin" \
  "${BIN_DIR}/linux_kernel.elf" \
  "${BIN_DIR}/linux_kernel.map" \
  "${BIN_DIR}/linux_kernel.config" \
  "${BIN_DIR}/linux_initramfs.cpio" \
  "${BIN_DIR}/linux_fs.img"
