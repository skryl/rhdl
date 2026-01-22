//! Rustc-based compiler for gate-level netlist simulation with SIMD support
//!
//! This module generates specialized Rust code for the netlist and compiles
//! it with rustc for maximum simulation performance. The generated code
//! uses SIMD instructions (AVX2/AVX-512) to process multiple test vectors
//! in parallel.
//!
//! SIMD widths:
//! - Scalar: 64 lanes (1 × u64)
//! - AVX2:   256 lanes (4 × u64)
//! - AVX-512: 512 lanes (8 × u64)

use magnus::{method, prelude::*, Error, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::process::Command;

/// SIMD width configuration
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SimdWidth {
    Scalar,  // 1 × u64 = 64 lanes
    Avx2,    // 4 × u64 = 256 lanes
    Avx512,  // 8 × u64 = 512 lanes
}

impl SimdWidth {
    fn width(&self) -> usize {
        match self {
            SimdWidth::Scalar => 1,
            SimdWidth::Avx2 => 4,
            SimdWidth::Avx512 => 8,
        }
    }

    fn lanes(&self) -> usize {
        self.width() * 64
    }

    fn detect() -> Self {
        #[cfg(target_arch = "x86_64")]
        {
            if is_x86_feature_detected!("avx512f") {
                return SimdWidth::Avx512;
            }
            if is_x86_feature_detected!("avx2") {
                return SimdWidth::Avx2;
            }
        }
        SimdWidth::Scalar
    }
}

/// Gate types
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum GateType {
    And,
    Or,
    Xor,
    Not,
    Mux,
    Buf,
    Const,
}

/// Gate definition
#[derive(Debug, Clone, Deserialize)]
struct GateDef {
    #[serde(rename = "type")]
    gate_type: GateType,
    inputs: Vec<usize>,
    output: usize,
    value: Option<i64>,
}

/// DFF definition
#[derive(Debug, Clone, Deserialize)]
struct DffDef {
    d: usize,
    q: usize,
    rst: Option<usize>,
    en: Option<usize>,
    #[allow(dead_code)]
    async_reset: Option<bool>,
    #[serde(default)]
    reset_value: i64,
}

/// Netlist IR
#[derive(Debug, Clone, Deserialize)]
struct NetlistIR {
    #[allow(dead_code)]
    name: String,
    net_count: usize,
    gates: Vec<GateDef>,
    dffs: Vec<DffDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    schedule: Vec<usize>,
}

/// Compiled function types for different SIMD widths
type EvaluateFnScalar = unsafe extern "C" fn(*mut u64, u64);
type TickFnScalar = unsafe extern "C" fn(*mut u64, u64);
type EvaluateFnSimd = unsafe extern "C" fn(*mut u64, *const u64);
type TickFnSimd = unsafe extern "C" fn(*mut u64, *const u64);

/// Compiled netlist simulator with SIMD support
struct NetlistCompiledSimulator {
    nets: Vec<u64>,
    dffs: Vec<DffDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    simd_width: SimdWidth,
    lane_masks: Vec<u64>,  // One mask per SIMD lane
    evaluate_fn_scalar: Option<EvaluateFnScalar>,
    tick_fn_scalar: Option<TickFnScalar>,
    evaluate_fn_simd: Option<EvaluateFnSimd>,
    tick_fn_simd: Option<TickFnSimd>,
    #[allow(dead_code)]
    lib: Option<libloading::Library>,
    generated_code: String,
    compiled: bool,
    net_count: usize,
}

impl NetlistCompiledSimulator {
    fn new(json: &str, simd_width: SimdWidth) -> Result<Self, String> {
        let ir: NetlistIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let width = simd_width.width();

        // Create lane masks - all 1s for full lanes
        let lane_masks = vec![u64::MAX; width];

        // Generate SIMD-aware Rust code
        let generated_code = Self::generate_simd_code(&ir, simd_width);

        // Nets array: net_count * simd_width u64s
        let nets = vec![0u64; ir.net_count * width];

        Ok(Self {
            nets,
            dffs: ir.dffs,
            inputs: ir.inputs,
            outputs: ir.outputs,
            simd_width,
            lane_masks,
            evaluate_fn_scalar: None,
            tick_fn_scalar: None,
            evaluate_fn_simd: None,
            tick_fn_simd: None,
            lib: None,
            generated_code,
            compiled: false,
            net_count: ir.net_count,
        })
    }

    fn generate_simd_code(ir: &NetlistIR, simd_width: SimdWidth) -> String {
        match simd_width {
            SimdWidth::Scalar => Self::generate_scalar_code(ir),
            SimdWidth::Avx2 => Self::generate_avx2_code(ir),
            SimdWidth::Avx512 => Self::generate_avx512_code(ir),
        }
    }

    fn generate_scalar_code(ir: &NetlistIR) -> String {
        let mut code = String::new();

        // Header - scalar version
        code.push_str("#[no_mangle]\npub unsafe extern \"C\" fn evaluate(nets: *mut u64, lane_mask: u64) {\n");

        // Generate gate evaluations in schedule order
        for &gate_idx in &ir.schedule {
            let gate = &ir.gates[gate_idx];
            let out = gate.output;

            match gate.gate_type {
                GateType::And => {
                    code.push_str(&format!(
                        "    *nets.add({}) = *nets.add({}) & *nets.add({});\n",
                        out, gate.inputs[0], gate.inputs[1]
                    ));
                }
                GateType::Or => {
                    code.push_str(&format!(
                        "    *nets.add({}) = *nets.add({}) | *nets.add({});\n",
                        out, gate.inputs[0], gate.inputs[1]
                    ));
                }
                GateType::Xor => {
                    code.push_str(&format!(
                        "    *nets.add({}) = *nets.add({}) ^ *nets.add({});\n",
                        out, gate.inputs[0], gate.inputs[1]
                    ));
                }
                GateType::Not => {
                    code.push_str(&format!(
                        "    *nets.add({}) = (!*nets.add({})) & lane_mask;\n",
                        out, gate.inputs[0]
                    ));
                }
                GateType::Mux => {
                    code.push_str(&format!(
                        "    {{ let sel = *nets.add({}); *nets.add({}) = (*nets.add({}) & !sel) | (*nets.add({}) & sel); }}\n",
                        gate.inputs[2], out, gate.inputs[0], gate.inputs[1]
                    ));
                }
                GateType::Buf => {
                    code.push_str(&format!(
                        "    *nets.add({}) = *nets.add({});\n",
                        out, gate.inputs[0]
                    ));
                }
                GateType::Const => {
                    let val = if gate.value.unwrap_or(0) == 0 { "0" } else { "lane_mask" };
                    code.push_str(&format!("    *nets.add({}) = {};\n", out, val));
                }
            }
        }

        code.push_str("}\n\n");

        // Generate tick function
        code.push_str("#[no_mangle]\npub unsafe extern \"C\" fn tick(nets: *mut u64, lane_mask: u64) {\n");
        code.push_str("    evaluate(nets, lane_mask);\n");

        Self::generate_dff_update_scalar(&mut code, ir);

        code.push_str("    evaluate(nets, lane_mask);\n");
        code.push_str("}\n");

        code
    }

    fn generate_avx2_code(ir: &NetlistIR) -> String {
        let mut code = String::new();
        let width = 4usize;
        let net_count = ir.net_count;

        // Header with SIMD imports
        code.push_str("#![feature(portable_simd)]\n");
        code.push_str("use std::simd::u64x4;\n\n");

        // Evaluate function - processes 4 u64s at once (256 lanes)
        code.push_str("#[no_mangle]\n");
        code.push_str("#[target_feature(enable = \"avx2\")]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(nets: *mut u64, lane_masks: *const u64) {\n");
        code.push_str("    let mask = u64x4::from_slice(std::slice::from_raw_parts(lane_masks, 4));\n");
        code.push_str(&format!("    let nets = nets as *mut [u64; {}];\n", width));

        // Generate SIMD gate evaluations
        for &gate_idx in &ir.schedule {
            let gate = &ir.gates[gate_idx];
            let out = gate.output;

            match gate.gate_type {
                GateType::And => {
                    code.push_str(&format!(
                        "    {{ let a = u64x4::from_array(*nets.add({})); let b = u64x4::from_array(*nets.add({})); (*nets.add({})) = (a & b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Or => {
                    code.push_str(&format!(
                        "    {{ let a = u64x4::from_array(*nets.add({})); let b = u64x4::from_array(*nets.add({})); (*nets.add({})) = (a | b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Xor => {
                    code.push_str(&format!(
                        "    {{ let a = u64x4::from_array(*nets.add({})); let b = u64x4::from_array(*nets.add({})); (*nets.add({})) = (a ^ b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Not => {
                    code.push_str(&format!(
                        "    {{ let a = u64x4::from_array(*nets.add({})); (*nets.add({})) = (!a & mask).to_array(); }}\n",
                        gate.inputs[0], out
                    ));
                }
                GateType::Mux => {
                    code.push_str(&format!(
                        "    {{ let a = u64x4::from_array(*nets.add({})); let b = u64x4::from_array(*nets.add({})); let sel = u64x4::from_array(*nets.add({})); (*nets.add({})) = ((a & !sel) | (b & sel)).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], gate.inputs[2], out
                    ));
                }
                GateType::Buf => {
                    code.push_str(&format!(
                        "    (*nets.add({})) = *nets.add({});\n",
                        out, gate.inputs[0]
                    ));
                }
                GateType::Const => {
                    if gate.value.unwrap_or(0) == 0 {
                        code.push_str(&format!("    (*nets.add({})) = [0u64; 4];\n", out));
                    } else {
                        code.push_str(&format!("    (*nets.add({})) = mask.to_array();\n", out));
                    }
                }
            }
        }

        code.push_str("}\n\n");

        // Tick function
        code.push_str("#[no_mangle]\n");
        code.push_str("#[target_feature(enable = \"avx2\")]\n");
        code.push_str("pub unsafe extern \"C\" fn tick(nets: *mut u64, lane_masks: *const u64) {\n");
        code.push_str("    evaluate(nets, lane_masks);\n");
        code.push_str("    let mask = u64x4::from_slice(std::slice::from_raw_parts(lane_masks, 4));\n");
        code.push_str(&format!("    let nets = nets as *mut [u64; {}];\n", width));

        Self::generate_dff_update_simd(&mut code, ir, width, "u64x4");

        code.push_str("    evaluate(nets as *mut u64, lane_masks);\n");
        code.push_str("}\n");

        code
    }

    fn generate_avx512_code(ir: &NetlistIR) -> String {
        let mut code = String::new();
        let width = 8usize;
        let net_count = ir.net_count;

        // Header with SIMD imports
        code.push_str("#![feature(portable_simd)]\n");
        code.push_str("use std::simd::u64x8;\n\n");

        // Evaluate function - processes 8 u64s at once (512 lanes)
        code.push_str("#[no_mangle]\n");
        code.push_str("#[target_feature(enable = \"avx512f\")]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(nets: *mut u64, lane_masks: *const u64) {\n");
        code.push_str("    let mask = u64x8::from_slice(std::slice::from_raw_parts(lane_masks, 8));\n");
        code.push_str(&format!("    let nets = nets as *mut [u64; {}];\n", width));

        // Generate SIMD gate evaluations
        for &gate_idx in &ir.schedule {
            let gate = &ir.gates[gate_idx];
            let out = gate.output;

            match gate.gate_type {
                GateType::And => {
                    code.push_str(&format!(
                        "    {{ let a = u64x8::from_array(*nets.add({})); let b = u64x8::from_array(*nets.add({})); (*nets.add({})) = (a & b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Or => {
                    code.push_str(&format!(
                        "    {{ let a = u64x8::from_array(*nets.add({})); let b = u64x8::from_array(*nets.add({})); (*nets.add({})) = (a | b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Xor => {
                    code.push_str(&format!(
                        "    {{ let a = u64x8::from_array(*nets.add({})); let b = u64x8::from_array(*nets.add({})); (*nets.add({})) = (a ^ b).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], out
                    ));
                }
                GateType::Not => {
                    code.push_str(&format!(
                        "    {{ let a = u64x8::from_array(*nets.add({})); (*nets.add({})) = (!a & mask).to_array(); }}\n",
                        gate.inputs[0], out
                    ));
                }
                GateType::Mux => {
                    code.push_str(&format!(
                        "    {{ let a = u64x8::from_array(*nets.add({})); let b = u64x8::from_array(*nets.add({})); let sel = u64x8::from_array(*nets.add({})); (*nets.add({})) = ((a & !sel) | (b & sel)).to_array(); }}\n",
                        gate.inputs[0], gate.inputs[1], gate.inputs[2], out
                    ));
                }
                GateType::Buf => {
                    code.push_str(&format!(
                        "    (*nets.add({})) = *nets.add({});\n",
                        out, gate.inputs[0]
                    ));
                }
                GateType::Const => {
                    if gate.value.unwrap_or(0) == 0 {
                        code.push_str(&format!("    (*nets.add({})) = [0u64; 8];\n", out));
                    } else {
                        code.push_str(&format!("    (*nets.add({})) = mask.to_array();\n", out));
                    }
                }
            }
        }

        code.push_str("}\n\n");

        // Tick function
        code.push_str("#[no_mangle]\n");
        code.push_str("#[target_feature(enable = \"avx512f\")]\n");
        code.push_str("pub unsafe extern \"C\" fn tick(nets: *mut u64, lane_masks: *const u64) {\n");
        code.push_str("    evaluate(nets, lane_masks);\n");
        code.push_str("    let mask = u64x8::from_slice(std::slice::from_raw_parts(lane_masks, 8));\n");
        code.push_str(&format!("    let nets = nets as *mut [u64; {}];\n", width));

        Self::generate_dff_update_simd(&mut code, ir, width, "u64x8");

        code.push_str("    evaluate(nets as *mut u64, lane_masks);\n");
        code.push_str("}\n");

        code
    }

    fn generate_dff_update_scalar(code: &mut String, ir: &NetlistIR) {
        if ir.dffs.is_empty() {
            return;
        }

        // Sample DFF inputs
        for (i, dff) in ir.dffs.iter().enumerate() {
            code.push_str(&format!("    let d{} = *nets.add({});\n", i, dff.d));
            code.push_str(&format!("    let q{} = *nets.add({});\n", i, dff.q));

            if dff.en.is_some() || dff.rst.is_some() {
                code.push_str(&format!("    let mut next{} = d{};\n", i, i));
                if let Some(en) = dff.en {
                    code.push_str(&format!(
                        "    {{ let en = *nets.add({}); next{} = (q{} & !en) | (d{} & en); }}\n",
                        en, i, i, i
                    ));
                }
                if let Some(rst) = dff.rst {
                    let reset_target = if dff.reset_value == 0 { "0" } else { "lane_mask" };
                    code.push_str(&format!(
                        "    {{ let rst = *nets.add({}); next{} = (next{} & !rst) | (rst & {}); }}\n",
                        rst, i, i, reset_target
                    ));
                }
            } else {
                code.push_str(&format!("    let next{} = d{};\n", i, i));
            }
        }

        // Update DFF outputs
        for (i, dff) in ir.dffs.iter().enumerate() {
            code.push_str(&format!("    *nets.add({}) = next{};\n", dff.q, i));
        }
    }

    fn generate_dff_update_simd(code: &mut String, ir: &NetlistIR, width: usize, simd_type: &str) {
        if ir.dffs.is_empty() {
            return;
        }

        // Sample DFF inputs
        for (i, dff) in ir.dffs.iter().enumerate() {
            code.push_str(&format!("    let d{} = {}::from_array(*nets.add({}));\n", i, simd_type, dff.d));
            code.push_str(&format!("    let q{} = {}::from_array(*nets.add({}));\n", i, simd_type, dff.q));

            if dff.en.is_some() || dff.rst.is_some() {
                code.push_str(&format!("    let mut next{} = d{};\n", i, i));
                if let Some(en) = dff.en {
                    code.push_str(&format!(
                        "    {{ let en = {}::from_array(*nets.add({})); next{} = (q{} & !en) | (d{} & en); }}\n",
                        simd_type, en, i, i, i
                    ));
                }
                if let Some(rst) = dff.rst {
                    let reset_target = if dff.reset_value == 0 {
                        format!("{}::splat(0)", simd_type)
                    } else {
                        "mask".to_string()
                    };
                    code.push_str(&format!(
                        "    {{ let rst = {}::from_array(*nets.add({})); next{} = (next{} & !rst) | (rst & {}); }}\n",
                        simd_type, rst, i, i, reset_target
                    ));
                }
            } else {
                code.push_str(&format!("    let next{} = d{};\n", i, i));
            }
        }

        // Update DFF outputs
        for (i, dff) in ir.dffs.iter().enumerate() {
            code.push_str(&format!("    (*nets.add({})) = next{}.to_array();\n", dff.q, i));
        }
    }

    fn compile(&mut self) -> Result<(), String> {
        if self.compiled {
            return Ok(());
        }

        // Create unique temp directory for compilation (use timestamp + random for uniqueness)
        use std::time::{SystemTime, UNIX_EPOCH};
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let temp_dir = std::env::temp_dir().join(format!("netlist_compile_{}_{}", std::process::id(), timestamp));
        fs::create_dir_all(&temp_dir).map_err(|e| e.to_string())?;

        let src_path = temp_dir.join("netlist.rs");
        let lib_path = temp_dir.join("libnetlist.so");

        // Write source
        {
            let mut file = fs::File::create(&src_path).map_err(|e| e.to_string())?;
            file.write_all(self.generated_code.as_bytes()).map_err(|e| e.to_string())?;
        }

        // Compile with rustc - add appropriate target features
        // SIMD modes (AVX2/AVX512) require nightly for portable_simd
        let use_nightly = matches!(self.simd_width, SimdWidth::Avx2 | SimdWidth::Avx512);

        let mut args = vec![
            "--crate-type=cdylib".to_string(),
            "-O".to_string(),
            "-C".to_string(), "opt-level=3".to_string(),
            "-C".to_string(), "lto=thin".to_string(),
        ];

        // Add target features based on SIMD width
        match self.simd_width {
            SimdWidth::Avx512 => {
                args.push("-C".to_string());
                args.push("target-feature=+avx512f".to_string());
            }
            SimdWidth::Avx2 => {
                args.push("-C".to_string());
                args.push("target-feature=+avx2".to_string());
            }
            SimdWidth::Scalar => {}
        }

        args.push("-o".to_string());
        args.push(lib_path.to_str().unwrap().to_string());
        args.push(src_path.to_str().unwrap().to_string());

        // Use rustup run nightly for SIMD modes, otherwise use stable rustc
        let output = if use_nightly {
            Command::new("rustup")
                .args(["run", "nightly", "rustc"])
                .args(&args)
                .output()
                .map_err(|e| format!("Failed to run rustc nightly: {}", e))?
        } else {
            Command::new("rustc")
                .args(&args)
                .output()
                .map_err(|e| format!("Failed to run rustc: {}", e))?
        };

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Compilation failed: {}", stderr));
        }

        // Load the compiled library
        let lib = unsafe { libloading::Library::new(&lib_path) }
            .map_err(|e| format!("Failed to load compiled library: {}", e))?;

        // Load function symbols based on SIMD width
        match self.simd_width {
            SimdWidth::Scalar => {
                let evaluate_fn: EvaluateFnScalar = unsafe {
                    *lib.get(b"evaluate")
                        .map_err(|e| format!("Failed to get evaluate symbol: {}", e))?
                };
                let tick_fn: TickFnScalar = unsafe {
                    *lib.get(b"tick")
                        .map_err(|e| format!("Failed to get tick symbol: {}", e))?
                };
                self.evaluate_fn_scalar = Some(evaluate_fn);
                self.tick_fn_scalar = Some(tick_fn);
            }
            SimdWidth::Avx2 | SimdWidth::Avx512 => {
                let evaluate_fn: EvaluateFnSimd = unsafe {
                    *lib.get(b"evaluate")
                        .map_err(|e| format!("Failed to get evaluate symbol: {}", e))?
                };
                let tick_fn: TickFnSimd = unsafe {
                    *lib.get(b"tick")
                        .map_err(|e| format!("Failed to get tick symbol: {}", e))?
                };
                self.evaluate_fn_simd = Some(evaluate_fn);
                self.tick_fn_simd = Some(tick_fn);
            }
        }

        self.lib = Some(lib);
        self.compiled = true;

        // Cleanup source file (keep lib loaded)
        let _ = fs::remove_file(&src_path);

        Ok(())
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let net_indices = self.inputs.get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;

        let width = self.simd_width.width();

        // Set value for all SIMD lanes
        for &net in net_indices {
            let base = net * width;
            for i in 0..width {
                self.nets[base + i] = value;
            }
        }
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        let net_indices = self.outputs.get(name)
            .ok_or_else(|| format!("Unknown output: {}", name))?;

        let width = self.simd_width.width();
        let base = net_indices[0] * width;

        // Return first lane (all lanes should have same value for single test)
        Ok(self.nets[base])
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        match self.simd_width {
            SimdWidth::Scalar => {
                if let Some(f) = self.evaluate_fn_scalar {
                    unsafe { f(self.nets.as_mut_ptr(), self.lane_masks[0]); }
                }
            }
            SimdWidth::Avx2 | SimdWidth::Avx512 => {
                if let Some(f) = self.evaluate_fn_simd {
                    unsafe { f(self.nets.as_mut_ptr(), self.lane_masks.as_ptr()); }
                }
            }
        }
    }

    fn tick(&mut self) {
        match self.simd_width {
            SimdWidth::Scalar => {
                if let Some(f) = self.tick_fn_scalar {
                    unsafe { f(self.nets.as_mut_ptr(), self.lane_masks[0]); }
                }
            }
            SimdWidth::Avx2 | SimdWidth::Avx512 => {
                if let Some(f) = self.tick_fn_simd {
                    unsafe { f(self.nets.as_mut_ptr(), self.lane_masks.as_ptr()); }
                }
            }
        }
    }

    fn run_ticks(&mut self, n: usize) {
        match self.simd_width {
            SimdWidth::Scalar => {
                if let Some(f) = self.tick_fn_scalar {
                    let mask = self.lane_masks[0];
                    let ptr = self.nets.as_mut_ptr();
                    for _ in 0..n {
                        unsafe { f(ptr, mask); }
                    }
                }
            }
            SimdWidth::Avx2 | SimdWidth::Avx512 => {
                if let Some(f) = self.tick_fn_simd {
                    let masks_ptr = self.lane_masks.as_ptr();
                    let ptr = self.nets.as_mut_ptr();
                    for _ in 0..n {
                        unsafe { f(ptr, masks_ptr); }
                    }
                }
            }
        }
    }

    fn reset(&mut self) {
        self.nets.fill(0);
        let width = self.simd_width.width();
        for dff in &self.dffs {
            if dff.reset_value != 0 {
                let base = dff.q * width;
                for i in 0..width {
                    self.nets[base + i] = self.lane_masks[i];
                }
            }
        }
    }
}

// ============================================================================
// Ruby bindings
// ============================================================================

fn ruby_to_u64(value: Value) -> Result<u64, Error> {
    if let Ok(i) = <i64 as TryConvert>::try_convert(value) {
        return Ok(i as u64);
    }
    let ruby = unsafe { Ruby::get_unchecked() };
    let str_val: String = value.funcall("to_s", (16i32,))?;
    u64::from_str_radix(&str_val, 16)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid integer: {}", e)))
}

fn u64_to_ruby(ruby: &Ruby, value: u64) -> Value {
    if value <= i64::MAX as u64 {
        ruby.into_value(value as i64)
    } else {
        let hex_str = format!("{:x}", value);
        ruby.eval(&format!("0x{}", hex_str)).unwrap_or_else(|_| ruby.into_value(0i64))
    }
}

#[magnus::wrap(class = "RHDL::Codegen::Structure::NetlistCompiler")]
struct RubyNetlistCompiler {
    sim: RefCell<NetlistCompiledSimulator>,
}

impl RubyNetlistCompiler {
    fn new(json: String, simd_mode: Option<String>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };

        // Parse SIMD mode or auto-detect
        let simd_width = match simd_mode.as_deref() {
            Some("scalar") | Some("64") => SimdWidth::Scalar,
            Some("avx2") | Some("256") => SimdWidth::Avx2,
            Some("avx512") | Some("512") => SimdWidth::Avx512,
            Some("auto") | None => SimdWidth::detect(),
            Some(other) => return Err(Error::new(
                ruby.exception_arg_error(),
                format!("Unknown SIMD mode: {}. Valid: scalar, avx2, avx512, auto", other)
            )),
        };

        let sim = NetlistCompiledSimulator::new(&json, simd_width)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self { sim: RefCell::new(sim) })
    }

    fn compile(&self) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        self.sim.borrow_mut().compile()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn compiled(&self) -> bool {
        self.sim.borrow().compiled
    }

    fn generated_code(&self) -> String {
        self.sim.borrow().generated_code.clone()
    }

    fn simd_mode(&self) -> String {
        match self.sim.borrow().simd_width {
            SimdWidth::Scalar => "scalar".to_string(),
            SimdWidth::Avx2 => "avx2".to_string(),
            SimdWidth::Avx512 => "avx512".to_string(),
        }
    }

    fn lanes(&self) -> usize {
        self.sim.borrow().simd_width.lanes()
    }

    fn poke(&self, name: String, value: Value) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let v = ruby_to_u64(value)?;
        self.sim.borrow_mut().poke(&name, v)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn peek(&self, name: String) -> Result<Value, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let val = self.sim.borrow().peek(&name)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(u64_to_ruby(&ruby, val))
    }

    fn evaluate(&self) {
        self.sim.borrow_mut().evaluate();
    }

    fn tick(&self) {
        self.sim.borrow_mut().tick();
    }

    fn run_ticks(&self, n: usize) {
        self.sim.borrow_mut().run_ticks(n);
    }

    fn reset(&self) {
        self.sim.borrow_mut().reset();
    }

    fn net_count(&self) -> usize {
        self.sim.borrow().net_count
    }

    fn dff_count(&self) -> usize {
        self.sim.borrow().dffs.len()
    }

    fn input_names(&self) -> Vec<String> {
        self.sim.borrow().inputs.keys().cloned().collect()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().outputs.keys().cloned().collect()
    }

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("net_count"), sim.net_count as i64)?;
        hash.aset(ruby.sym_new("dff_count"), sim.dffs.len() as i64)?;
        hash.aset(ruby.sym_new("lanes"), sim.simd_width.lanes() as i64)?;
        hash.aset(ruby.sym_new("simd_width"), sim.simd_width.width() as i64)?;
        hash.aset(ruby.sym_new("simd_mode"), match sim.simd_width {
            SimdWidth::Scalar => "scalar",
            SimdWidth::Avx2 => "avx2",
            SimdWidth::Avx512 => "avx512",
        })?;
        hash.aset(ruby.sym_new("input_count"), sim.inputs.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.outputs.len() as i64)?;
        hash.aset(ruby.sym_new("compiled"), sim.compiled)?;
        hash.aset(ruby.sym_new("backend"), "rustc_compiler_simd")?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }

    fn debug_nets(&self) -> Vec<u64> {
        self.sim.borrow().nets.clone()
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let structure = codegen.define_module("Structure")?;

    let class = structure.define_class("NetlistCompiler", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyNetlistCompiler::new, 2))?;
    class.define_method("compile", method!(RubyNetlistCompiler::compile, 0))?;
    class.define_method("compiled?", method!(RubyNetlistCompiler::compiled, 0))?;
    class.define_method("generated_code", method!(RubyNetlistCompiler::generated_code, 0))?;
    class.define_method("simd_mode", method!(RubyNetlistCompiler::simd_mode, 0))?;
    class.define_method("poke", method!(RubyNetlistCompiler::poke, 2))?;
    class.define_method("peek", method!(RubyNetlistCompiler::peek, 1))?;
    class.define_method("evaluate", method!(RubyNetlistCompiler::evaluate, 0))?;
    class.define_method("tick", method!(RubyNetlistCompiler::tick, 0))?;
    class.define_method("run_ticks", method!(RubyNetlistCompiler::run_ticks, 1))?;
    class.define_method("reset", method!(RubyNetlistCompiler::reset, 0))?;
    class.define_method("net_count", method!(RubyNetlistCompiler::net_count, 0))?;
    class.define_method("dff_count", method!(RubyNetlistCompiler::dff_count, 0))?;
    class.define_method("lanes", method!(RubyNetlistCompiler::lanes, 0))?;
    class.define_method("input_names", method!(RubyNetlistCompiler::input_names, 0))?;
    class.define_method("output_names", method!(RubyNetlistCompiler::output_names, 0))?;
    class.define_method("stats", method!(RubyNetlistCompiler::stats, 0))?;
    class.define_method("native?", method!(RubyNetlistCompiler::native, 0))?;
    class.define_method("debug_nets", method!(RubyNetlistCompiler::debug_nets, 0))?;

    // Export detected SIMD capability
    let detected = SimdWidth::detect();
    structure.const_set("NETLIST_COMPILER_AVAILABLE", true)?;
    structure.const_set("NETLIST_COMPILER_SIMD", match detected {
        SimdWidth::Scalar => "scalar",
        SimdWidth::Avx2 => "avx2",
        SimdWidth::Avx512 => "avx512",
    })?;

    Ok(())
}
