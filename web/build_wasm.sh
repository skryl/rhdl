#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SIM_DIR="${REPO_ROOT}/lib/rhdl/codegen/ir/sim"
OUT_DIR="${SCRIPT_DIR}/pkg"
AOT_IR="${AOT_IR:-${SCRIPT_DIR}/samples/apple2.json}"
AOT_GEN="${SIM_DIR}/ir_compiler/src/aot_generated.rs"

restore_aot_placeholder() {
  cat > "${AOT_GEN}" <<'EOF'
compile_error!(
    "ir_compiler feature `aot` requires generated source at src/aot_generated.rs; run aot_codegen first"
);
EOF
}
trap restore_aot_placeholder EXIT

build_backend() {
  local crate_dir="$1"
  local artifact="$2"
  local out_file="${OUT_DIR}/${artifact}"
  local crate_name
  crate_name="$(basename "${crate_dir}")"

  echo "Building ${crate_name} -> ${artifact}"
  if (cd "${crate_dir}" && cargo build --release --target wasm32-unknown-unknown); then
    cp "${crate_dir}/target/wasm32-unknown-unknown/release/${crate_name}.wasm" "${out_file}"
    echo "Built ${out_file}"
  else
    echo "WARNING: ${crate_name} failed for wasm32-unknown-unknown; ${artifact} not updated" >&2
  fi
}

mkdir -p "${OUT_DIR}"
rustup target add wasm32-unknown-unknown

build_backend "${SIM_DIR}/ir_interpreter" "ir_interpreter.wasm"
build_backend "${SIM_DIR}/ir_jit" "ir_jit.wasm"

echo "Building ir_compiler -> ir_compiler.wasm (AOT)"
if [[ ! -f "${AOT_IR}" ]]; then
  echo "WARNING: AOT IR source not found: ${AOT_IR}; ir_compiler.wasm not updated" >&2
else
  if (cd "${SIM_DIR}/ir_compiler" && cargo run --quiet --bin aot_codegen -- "${AOT_IR}" "${AOT_GEN}"); then
    if (cd "${SIM_DIR}/ir_compiler" && cargo build --release --target wasm32-unknown-unknown --features aot); then
      cp "${SIM_DIR}/ir_compiler/target/wasm32-unknown-unknown/release/ir_compiler.wasm" "${OUT_DIR}/ir_compiler.wasm"
      echo "Built ${OUT_DIR}/ir_compiler.wasm (AOT from ${AOT_IR})"
    else
      echo "WARNING: ir_compiler AOT build failed; ir_compiler.wasm not updated" >&2
    fi
  else
    echo "WARNING: ir_compiler AOT code generation failed; ir_compiler.wasm not updated" >&2
  fi
fi
