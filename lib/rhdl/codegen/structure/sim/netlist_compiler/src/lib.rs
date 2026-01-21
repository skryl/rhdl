//! Rustc-based compiler for gate-level netlist simulation
//!
//! This module generates specialized Rust code for the netlist and compiles
//! it with rustc for maximum simulation performance. The generated code
//! uses LLVM optimizations including vectorization and inlining.

use magnus::{method, prelude::*, Error, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::process::Command;

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

/// Compiled function type
type EvaluateFn = unsafe extern "C" fn(*mut u64, u64);
type TickFn = unsafe extern "C" fn(*mut u64, u64);

/// Compiled netlist simulator
struct NetlistCompiledSimulator {
    nets: Vec<u64>,
    dffs: Vec<DffDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    lanes: usize,
    lane_mask: u64,
    evaluate_fn: Option<EvaluateFn>,
    tick_fn: Option<TickFn>,
    #[allow(dead_code)]
    lib: Option<libloading::Library>,
    generated_code: String,
    compiled: bool,
}

impl NetlistCompiledSimulator {
    fn new(json: &str, lanes: usize) -> Result<Self, String> {
        let ir: NetlistIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let lane_mask = if lanes >= 64 { u64::MAX } else { (1u64 << lanes) - 1 };

        // Generate Rust code
        let generated_code = Self::generate_rust_code(&ir);

        Ok(Self {
            nets: vec![0; ir.net_count],
            dffs: ir.dffs,
            inputs: ir.inputs,
            outputs: ir.outputs,
            lanes,
            lane_mask,
            evaluate_fn: None,
            tick_fn: None,
            lib: None,
            generated_code,
            compiled: false,
        })
    }

    fn generate_rust_code(ir: &NetlistIR) -> String {
        let mut code = String::new();

        // Header
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

        // DFF updates
        if !ir.dffs.is_empty() {
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

        code.push_str("    evaluate(nets, lane_mask);\n");
        code.push_str("}\n");

        code
    }

    fn compile(&mut self) -> Result<(), String> {
        if self.compiled {
            return Ok(());
        }

        // Create temp directory for compilation
        let temp_dir = std::env::temp_dir().join(format!("netlist_compile_{}", std::process::id()));
        fs::create_dir_all(&temp_dir).map_err(|e| e.to_string())?;

        let src_path = temp_dir.join("netlist.rs");
        let lib_path = temp_dir.join("libnetlist.so");

        // Write source
        {
            let mut file = fs::File::create(&src_path).map_err(|e| e.to_string())?;
            file.write_all(self.generated_code.as_bytes()).map_err(|e| e.to_string())?;
        }

        // Compile with rustc
        let output = Command::new("rustc")
            .args([
                "--crate-type=cdylib",
                "-O",
                "-C", "opt-level=3",
                "-C", "lto=thin",
                "-o", lib_path.to_str().unwrap(),
                src_path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| format!("Failed to run rustc: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Compilation failed: {}", stderr));
        }

        // Load the compiled library
        let lib = unsafe { libloading::Library::new(&lib_path) }
            .map_err(|e| format!("Failed to load compiled library: {}", e))?;

        let evaluate_fn: EvaluateFn = unsafe {
            *lib.get(b"evaluate")
                .map_err(|e| format!("Failed to get evaluate symbol: {}", e))?
        };

        let tick_fn: TickFn = unsafe {
            *lib.get(b"tick")
                .map_err(|e| format!("Failed to get tick symbol: {}", e))?
        };

        self.evaluate_fn = Some(evaluate_fn);
        self.tick_fn = Some(tick_fn);
        self.lib = Some(lib);
        self.compiled = true;

        // Cleanup source file (keep lib loaded)
        let _ = fs::remove_file(&src_path);

        Ok(())
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let nets = self.inputs.get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;
        for &net in nets {
            self.nets[net] = value & self.lane_mask;
        }
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        let nets = self.outputs.get(name)
            .ok_or_else(|| format!("Unknown output: {}", name))?;
        Ok(self.nets[nets[0]])
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        if let Some(f) = self.evaluate_fn {
            unsafe { f(self.nets.as_mut_ptr(), self.lane_mask); }
        } else {
            // Fallback: interpret
            self.evaluate_interpreted();
        }
    }

    fn evaluate_interpreted(&mut self) {
        // Simple fallback - not used when compiled
    }

    fn tick(&mut self) {
        if let Some(f) = self.tick_fn {
            unsafe { f(self.nets.as_mut_ptr(), self.lane_mask); }
        } else {
            self.tick_interpreted();
        }
    }

    fn tick_interpreted(&mut self) {
        self.evaluate();
        // DFF update logic...
    }

    fn run_ticks(&mut self, n: usize) {
        if let Some(f) = self.tick_fn {
            for _ in 0..n {
                unsafe { f(self.nets.as_mut_ptr(), self.lane_mask); }
            }
        } else {
            for _ in 0..n {
                self.tick_interpreted();
            }
        }
    }

    fn reset(&mut self) {
        self.nets.fill(0);
        for dff in &self.dffs {
            if dff.reset_value != 0 {
                self.nets[dff.q] = self.lane_mask;
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
    fn new(json: String, lanes: Option<usize>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let lanes = lanes.unwrap_or(64);
        let sim = NetlistCompiledSimulator::new(&json, lanes)
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
        self.sim.borrow().nets.len()
    }

    fn dff_count(&self) -> usize {
        self.sim.borrow().dffs.len()
    }

    fn lanes(&self) -> usize {
        self.sim.borrow().lanes
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

        hash.aset(ruby.sym_new("net_count"), sim.nets.len() as i64)?;
        hash.aset(ruby.sym_new("dff_count"), sim.dffs.len() as i64)?;
        hash.aset(ruby.sym_new("lanes"), sim.lanes as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.inputs.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.outputs.len() as i64)?;
        hash.aset(ruby.sym_new("compiled"), sim.compiled)?;
        hash.aset(ruby.sym_new("backend"), "rustc_compiler")?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
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

    structure.const_set("NETLIST_COMPILER_AVAILABLE", true)?;

    Ok(())
}
