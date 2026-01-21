//! FIRRTL JIT Compiler
//!
//! This module generates specialized Rust code for a circuit and compiles it
//! at runtime for maximum simulation performance. Instead of interpreting
//! bytecode, we generate native code that directly computes signal values.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::process::Command;

// IR structures matching the JSON format
#[derive(Debug, Deserialize, Clone)]
struct CircuitIR {
    name: String,
    ports: Vec<Port>,
    nets: Vec<Net>,
    regs: Vec<Reg>,
    assigns: Vec<Assign>,
    processes: Vec<Process>,
    #[serde(default)]
    memories: Vec<Memory>,
}

#[derive(Debug, Deserialize, Clone)]
struct Port {
    name: String,
    direction: String,
    width: u32,
}

#[derive(Debug, Deserialize, Clone)]
struct Net {
    name: String,
    width: u32,
}

#[derive(Debug, Deserialize, Clone)]
struct Reg {
    name: String,
    width: u32,
}

#[derive(Debug, Deserialize, Clone)]
struct Assign {
    target: String,
    expr: Expr,
}

#[derive(Debug, Deserialize, Clone)]
struct Process {
    name: String,
    clock: Option<String>,
    clocked: bool,
    statements: Vec<Statement>,
}

#[derive(Debug, Deserialize, Clone)]
struct Statement {
    target: String,
    expr: Expr,
}

#[derive(Debug, Deserialize, Clone)]
struct Memory {
    name: String,
    depth: u32,
    width: u32,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(tag = "type")]
enum Expr {
    #[serde(rename = "signal")]
    Signal { name: String, width: u32 },
    #[serde(rename = "literal")]
    Literal { value: u64, width: u32 },
    #[serde(rename = "unary_op")]
    UnaryOp { op: String, operand: Box<Expr>, width: u32 },
    #[serde(rename = "binary_op")]
    BinaryOp { op: String, left: Box<Expr>, right: Box<Expr>, width: u32 },
    #[serde(rename = "mux")]
    Mux { condition: Box<Expr>, when_true: Box<Expr>, when_false: Box<Expr>, width: u32 },
    #[serde(rename = "slice")]
    Slice { base: Box<Expr>, low: u32, high: u32, width: u32 },
    #[serde(rename = "concat")]
    Concat { parts: Vec<Expr>, width: u32 },
    #[serde(rename = "resize")]
    Resize { expr: Box<Expr>, width: u32 },
}

/// Inner simulator state
struct SimulatorState {
    ir: CircuitIR,
    signal_indices: HashMap<String, usize>,
    signals: Vec<u64>,
    next_regs: Vec<u64>,
    ram: Vec<u8>,
    rom: Vec<u8>,
    compiled_lib: Option<libloading::Library>,
    compiled: bool,
}

impl SimulatorState {
    fn new(json: &str) -> Result<Self, String> {
        let ir: CircuitIR = serde_json::from_str(json)
            .map_err(|e| e.to_string())?;

        let mut signal_indices = HashMap::new();
        let mut idx = 0;

        // Assign indices to all signals
        for port in &ir.ports {
            signal_indices.insert(port.name.clone(), idx);
            idx += 1;
        }
        for net in &ir.nets {
            signal_indices.insert(net.name.clone(), idx);
            idx += 1;
        }
        for reg in &ir.regs {
            signal_indices.insert(reg.name.clone(), idx);
            idx += 1;
        }

        let signal_count = signal_indices.len();
        let reg_count = count_regs(&ir);

        Ok(SimulatorState {
            ir,
            signal_indices,
            signals: vec![0; signal_count],
            next_regs: vec![0; reg_count],
            ram: vec![0; 48 * 1024],
            rom: vec![0; 12 * 1024],
            compiled_lib: None,
            compiled: false,
        })
    }

    fn signal_count(&self) -> usize {
        self.signal_indices.len()
    }

    fn reg_count(&self) -> usize {
        count_regs(&self.ir)
    }

    fn poke(&mut self, name: &str, value: u64) {
        if let Some(&idx) = self.signal_indices.get(name) {
            self.signals[idx] = value;
        }
    }

    fn peek(&self, name: &str) -> u64 {
        self.signal_indices.get(name)
            .map(|&idx| self.signals[idx])
            .unwrap_or(0)
    }

    fn evaluate(&mut self) {
        if let Some(ref lib) = self.compiled_lib {
            unsafe {
                let func: libloading::Symbol<unsafe extern "C" fn(&mut [u64])> =
                    lib.get(b"evaluate").unwrap();
                func(&mut self.signals);
            }
        } else {
            self.evaluate_interpreted();
        }
    }

    fn evaluate_interpreted(&mut self) {
        for assign in &self.ir.assigns.clone() {
            if let Some(&idx) = self.signal_indices.get(&assign.target) {
                let value = self.eval_expr(&assign.expr);
                self.signals[idx] = value;
            }
        }
    }

    fn eval_expr(&self, expr: &Expr) -> u64 {
        match expr {
            Expr::Signal { name, width } => {
                let idx = self.signal_indices.get(name).cloned().unwrap_or(0);
                self.signals[idx] & mask(*width)
            }
            Expr::Literal { value, width } => {
                value & mask(*width)
            }
            Expr::UnaryOp { op, operand, width } => {
                let val = self.eval_expr(operand);
                let m = mask(*width);
                match op.as_str() {
                    "~" | "not" => (!val) & m,
                    "&" | "reduce_and" => {
                        let op_width = get_expr_width(operand);
                        let op_mask = mask(op_width);
                        if (val & op_mask) == op_mask { 1 } else { 0 }
                    }
                    "|" | "reduce_or" => if val != 0 { 1 } else { 0 },
                    "^" | "reduce_xor" => val.count_ones() as u64 & 1,
                    _ => val,
                }
            }
            Expr::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr(left);
                let r = self.eval_expr(right);
                let m = mask(*width);
                match op.as_str() {
                    "&" => l & r,
                    "|" => l | r,
                    "^" => l ^ r,
                    "+" => l.wrapping_add(r) & m,
                    "-" => l.wrapping_sub(r) & m,
                    "*" => l.wrapping_mul(r) & m,
                    "/" => if r != 0 { l / r } else { 0 },
                    "%" => if r != 0 { l % r } else { 0 },
                    "<<" => (l << r.min(63)) & m,
                    ">>" => l >> r.min(63),
                    "==" => if l == r { 1 } else { 0 },
                    "!=" => if l != r { 1 } else { 0 },
                    "<" => if l < r { 1 } else { 0 },
                    ">" => if l > r { 1 } else { 0 },
                    "<=" | "le" => if l <= r { 1 } else { 0 },
                    ">=" => if l >= r { 1 } else { 0 },
                    _ => 0,
                }
            }
            Expr::Mux { condition, when_true, when_false, width } => {
                let cond = self.eval_expr(condition);
                let m = mask(*width);
                if cond != 0 {
                    self.eval_expr(when_true) & m
                } else {
                    self.eval_expr(when_false) & m
                }
            }
            Expr::Slice { base, low, width, .. } => {
                let val = self.eval_expr(base);
                (val >> low) & mask(*width)
            }
            Expr::Concat { parts, width } => {
                let mut result = 0u64;
                let mut shift = 0u32;
                for part in parts {
                    let part_val = self.eval_expr(part);
                    let part_width = get_expr_width(part);
                    result |= (part_val & mask(part_width)) << shift;
                    shift += part_width;
                }
                result & mask(*width)
            }
            Expr::Resize { expr, width } => {
                self.eval_expr(expr) & mask(*width)
            }
        }
    }

    fn tick(&mut self) {
        self.evaluate();

        if let Some(ref lib) = self.compiled_lib {
            unsafe {
                let tick_func: libloading::Symbol<unsafe extern "C" fn(&mut [u64], &mut [u64])> =
                    lib.get(b"tick").unwrap();
                tick_func(&mut self.signals, &mut self.next_regs);

                let update_func: libloading::Symbol<unsafe extern "C" fn(&mut [u64], &[u64])> =
                    lib.get(b"update_regs").unwrap();
                update_func(&mut self.signals, &self.next_regs);
            }
        } else {
            self.tick_interpreted();
        }

        self.evaluate();
    }

    fn tick_interpreted(&mut self) {
        let mut reg_idx = 0;
        for process in &self.ir.processes.clone() {
            if process.clocked {
                for stmt in &process.statements {
                    self.next_regs[reg_idx] = self.eval_expr(&stmt.expr);
                    reg_idx += 1;
                }
            }
        }

        reg_idx = 0;
        for process in &self.ir.processes.clone() {
            if process.clocked {
                for stmt in &process.statements {
                    if let Some(&sig_idx) = self.signal_indices.get(&stmt.target) {
                        self.signals[sig_idx] = self.next_regs[reg_idx];
                    }
                    reg_idx += 1;
                }
            }
        }
    }

    fn reset(&mut self) {
        for sig in &mut self.signals {
            *sig = 0;
        }
        for reg in &mut self.next_regs {
            *reg = 0;
        }
    }

    fn compile(&mut self) -> Result<bool, String> {
        let code = generate_full_code(&self.ir, &self.signal_indices);

        // Write generated code to temp file
        let temp_dir = std::env::temp_dir();
        let src_path = temp_dir.join("rhdl_circuit.rs");
        let lib_path = temp_dir.join(if cfg!(target_os = "macos") {
            "librhdl_circuit.dylib"
        } else if cfg!(target_os = "windows") {
            "rhdl_circuit.dll"
        } else {
            "librhdl_circuit.so"
        });

        fs::write(&src_path, &code).map_err(|e| e.to_string())?;

        // Compile with rustc
        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "-O",
                "-o",
                lib_path.to_str().unwrap(),
                src_path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| e.to_string())?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Compilation failed: {}", stderr));
        }

        // Load the compiled library
        unsafe {
            let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
            self.compiled_lib = Some(lib);
        }

        self.compiled = true;
        Ok(true)
    }

    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> CycleResult {
        // Use compiled run_cpu_cycles if available - this is the big optimization!
        // The compiled version runs the entire loop without any function call overhead.
        if let Some(ref lib) = self.compiled_lib {
            unsafe {
                type RunCpuCyclesFn = unsafe extern "C" fn(
                    &mut [u64], &mut [u8], &[u8], usize, u8, bool
                ) -> (bool, bool);
                let func: libloading::Symbol<RunCpuCyclesFn> = lib.get(b"run_cpu_cycles").unwrap();
                let (text_dirty, key_cleared) = func(
                    &mut self.signals,
                    &mut self.ram,
                    &self.rom,
                    n,
                    key_data,
                    key_ready
                );
                return CycleResult { cycles_run: n, text_dirty, key_cleared };
            }
        }

        // Fallback to interpreted mode
        let mut text_dirty = false;
        let mut key_cleared = false;
        let mut key_is_ready = key_ready;

        let clk_idx = self.signal_indices.get("clk_14m").cloned();
        let k_idx = self.signal_indices.get("k").cloned();
        let ram_addr_idx = self.signal_indices.get("ram_addr").cloned();
        let ram_do_idx = self.signal_indices.get("ram_do").cloned();
        let ram_we_idx = self.signal_indices.get("ram_we").cloned();
        let d_idx = self.signal_indices.get("d").cloned();
        let read_key_idx = self.signal_indices.get("read_key").cloned();

        for _ in 0..n {
            for _ in 0..14 {
                if let Some(k) = k_idx {
                    self.signals[k] = if key_is_ready { (key_data as u64) | 0x80 } else { 0 };
                }

                if let Some(clk) = clk_idx {
                    self.signals[clk] = 0;
                }
                self.evaluate();

                if let (Some(addr_idx), Some(do_idx)) = (ram_addr_idx, ram_do_idx) {
                    let addr = self.signals[addr_idx] as usize;
                    let data = if addr >= 0xD000 && addr <= 0xFFFF {
                        let rom_offset = addr - 0xD000;
                        if rom_offset < self.rom.len() { self.rom[rom_offset] as u64 } else { 0 }
                    } else if addr < self.ram.len() {
                        self.ram[addr] as u64
                    } else {
                        0
                    };
                    self.signals[do_idx] = data;
                }
                self.evaluate();

                if let Some(clk) = clk_idx {
                    self.signals[clk] = 1;
                }
                self.tick();

                if let (Some(we_idx), Some(addr_idx), Some(d)) = (ram_we_idx, ram_addr_idx, d_idx) {
                    if self.signals[we_idx] == 1 {
                        let write_addr = self.signals[addr_idx] as usize;
                        if write_addr < self.ram.len() {
                            self.ram[write_addr] = (self.signals[d] & 0xFF) as u8;
                            if write_addr >= 0x0400 && write_addr <= 0x07FF {
                                text_dirty = true;
                            }
                        }
                    }
                }

                if let Some(rk) = read_key_idx {
                    if self.signals[rk] == 1 {
                        key_is_ready = false;
                        key_cleared = true;
                    }
                }
            }
        }

        CycleResult { cycles_run: n, text_dirty, key_cleared }
    }
}

struct CycleResult {
    cycles_run: usize,
    text_dirty: bool,
    key_cleared: bool,
}

fn count_regs(ir: &CircuitIR) -> usize {
    ir.processes.iter()
        .filter(|p| p.clocked)
        .map(|p| p.statements.len())
        .sum()
}

fn mask(width: u32) -> u64 {
    if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
}

fn get_expr_width(expr: &Expr) -> u32 {
    match expr {
        Expr::Signal { width, .. } => *width,
        Expr::Literal { width, .. } => *width,
        Expr::UnaryOp { width, .. } => *width,
        Expr::BinaryOp { width, .. } => *width,
        Expr::Mux { width, .. } => *width,
        Expr::Slice { width, .. } => *width,
        Expr::Concat { width, .. } => *width,
        Expr::Resize { width, .. } => *width,
    }
}

// Code generation functions
fn generate_mask_str(width: u32) -> String {
    if width >= 64 {
        "0xFFFFFFFFFFFFFFFF_u64".to_string()
    } else {
        format!("0x{:X}_u64", (1u64 << width) - 1)
    }
}

fn expr_to_rust(expr: &Expr, signal_indices: &HashMap<String, usize>) -> String {
    expr_to_rust_with_name(expr, signal_indices, "signals")
}

fn expr_to_rust_with_name(expr: &Expr, signal_indices: &HashMap<String, usize>, signals_name: &str) -> String {
    match expr {
        Expr::Signal { name, width } => {
            let idx = signal_indices.get(name).unwrap_or(&0);
            format!("({}[{}] & {})", signals_name, idx, generate_mask_str(*width))
        }
        Expr::Literal { value, width } => {
            format!("({}_u64 & {})", value, generate_mask_str(*width))
        }
        Expr::UnaryOp { op, operand, width } => {
            let operand_code = expr_to_rust_with_name(operand, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            match op.as_str() {
                "~" | "not" => format!("((!{}) & {})", operand_code, m),
                "&" | "reduce_and" => {
                    let op_width = get_expr_width(operand);
                    let op_mask = generate_mask_str(op_width);
                    format!("(if ({} & {}) == {} {{ 1_u64 }} else {{ 0_u64 }})", operand_code, op_mask, op_mask)
                }
                "|" | "reduce_or" => format!("(if {} != 0 {{ 1_u64 }} else {{ 0_u64 }})", operand_code),
                "^" | "reduce_xor" => format!("({}.count_ones() as u64 & 1)", operand_code),
                _ => operand_code,
            }
        }
        Expr::BinaryOp { op, left, right, width } => {
            let left_code = expr_to_rust_with_name(left, signal_indices, signals_name);
            let right_code = expr_to_rust_with_name(right, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            match op.as_str() {
                "&" => format!("({} & {})", left_code, right_code),
                "|" => format!("({} | {})", left_code, right_code),
                "^" => format!("({} ^ {})", left_code, right_code),
                "+" => format!("({}.wrapping_add({}) & {})", left_code, right_code, m),
                "-" => format!("({}.wrapping_sub({}) & {})", left_code, right_code, m),
                "*" => format!("({}.wrapping_mul({}) & {})", left_code, right_code, m),
                "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0 }})", right_code, left_code, right_code),
                "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0 }})", right_code, left_code, right_code),
                "<<" => format!("(({} << ({}.min(63))) & {})", left_code, right_code, m),
                ">>" => format!("({} >> ({}.min(63)))", left_code, right_code),
                "==" => format!("(if {} == {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                "!=" => format!("(if {} != {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                "<" => format!("(if {} < {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                ">" => format!("(if {} > {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                "<=" | "le" => format!("(if {} <= {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                ">=" => format!("(if {} >= {} {{ 1_u64 }} else {{ 0_u64 }})", left_code, right_code),
                _ => "0_u64".to_string(),
            }
        }
        Expr::Mux { condition, when_true, when_false, width } => {
            let cond_code = expr_to_rust_with_name(condition, signal_indices, signals_name);
            let true_code = expr_to_rust_with_name(when_true, signal_indices, signals_name);
            let false_code = expr_to_rust_with_name(when_false, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            format!("(if {} != 0 {{ {} }} else {{ {} }} & {})", cond_code, true_code, false_code, m)
        }
        Expr::Slice { base, low, width, .. } => {
            let base_code = expr_to_rust_with_name(base, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            format!("(({} >> {}) & {})", base_code, low, m)
        }
        Expr::Concat { parts, width } => {
            let m = generate_mask_str(*width);
            let mut result = String::from("(");
            let mut shift = 0u32;
            for (i, part) in parts.iter().enumerate() {
                let part_code = expr_to_rust_with_name(part, signal_indices, signals_name);
                let part_width = get_expr_width(part);
                let part_mask = generate_mask_str(part_width);
                if i > 0 { result.push_str(" | "); }
                if shift > 0 {
                    result.push_str(&format!("(({} & {}) << {})", part_code, part_mask, shift));
                } else {
                    result.push_str(&format!("({} & {})", part_code, part_mask));
                }
                shift += part_width;
            }
            result.push_str(&format!(") & {}", m));
            result
        }
        Expr::Resize { expr, width } => {
            let expr_code = expr_to_rust_with_name(expr, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            format!("({} & {})", expr_code, m)
        }
    }
}

fn generate_full_code(ir: &CircuitIR, signal_indices: &HashMap<String, usize>) -> String {
    let mut code = String::new();
    code.push_str("// Auto-generated circuit simulation code\n");
    code.push_str("// DO NOT EDIT - generated by FIRRTL compiler\n\n");

    // Generate inline evaluate logic as a macro for zero-overhead
    code.push_str("macro_rules! do_evaluate {\n");
    code.push_str("    ($signals:expr) => {{\n");
    for assign in &ir.assigns {
        if let Some(&idx) = signal_indices.get(&assign.target) {
            let expr_code = expr_to_rust_with_name(&assign.expr, signal_indices, "$signals");
            code.push_str(&format!("        $signals[{}] = {};\n", idx, expr_code));
        }
    }
    code.push_str("    }};\n}\n\n");

    // Generate inline tick logic as a macro
    code.push_str("macro_rules! do_tick {\n");
    code.push_str("    ($signals:expr, $next_regs:expr) => {{\n");
    let mut reg_idx = 0;
    for process in &ir.processes {
        if process.clocked {
            for stmt in &process.statements {
                let expr_code = expr_to_rust_with_name(&stmt.expr, signal_indices, "$signals");
                code.push_str(&format!("        $next_regs[{}] = {};\n", reg_idx, expr_code));
                reg_idx += 1;
            }
        }
    }
    code.push_str("    }};\n}\n\n");

    // Generate inline update_regs logic as a macro
    code.push_str("macro_rules! do_update_regs {\n");
    code.push_str("    ($signals:expr, $next_regs:expr) => {{\n");
    let mut reg_idx = 0;
    for process in &ir.processes {
        if process.clocked {
            for stmt in &process.statements {
                if let Some(&sig_idx) = signal_indices.get(&stmt.target) {
                    code.push_str(&format!("        $signals[{}] = $next_regs[{}];\n", sig_idx, reg_idx));
                    reg_idx += 1;
                }
            }
        }
    }
    code.push_str("    }};\n}\n\n");

    // Generate evaluate function (for compatibility)
    code.push_str("#[no_mangle]\npub extern \"C\" fn evaluate(signals: &mut [u64]) {\n");
    code.push_str("    do_evaluate!(signals);\n");
    code.push_str("}\n\n");

    // Generate tick function (for compatibility)
    code.push_str("#[no_mangle]\npub extern \"C\" fn tick(signals: &mut [u64], next_regs: &mut [u64]) {\n");
    code.push_str("    do_tick!(signals, next_regs);\n");
    code.push_str("}\n\n");

    // Generate update_regs function (for compatibility)
    code.push_str("#[no_mangle]\npub extern \"C\" fn update_regs(signals: &mut [u64], next_regs: &[u64]) {\n");
    code.push_str("    do_update_regs!(signals, next_regs);\n");
    code.push_str("}\n\n");

    // Generate run_cpu_cycles - the main optimized entry point
    // This runs the entire CPU cycle loop without any function call overhead
    let clk_idx = signal_indices.get("clk_14m").cloned().unwrap_or(0);
    let k_idx = signal_indices.get("k").cloned().unwrap_or(0);
    let ram_addr_idx = signal_indices.get("ram_addr").cloned().unwrap_or(0);
    let ram_do_idx = signal_indices.get("ram_do").cloned().unwrap_or(0);
    let ram_we_idx = signal_indices.get("ram_we").cloned().unwrap_or(0);
    let d_idx = signal_indices.get("d").cloned().unwrap_or(0);
    let read_key_idx = signal_indices.get("read_key").cloned().unwrap_or(0);
    let reg_count = count_regs(ir);

    code.push_str(&format!(r#"/// Run N CPU cycles with zero function-call overhead
/// Returns: (text_dirty: bool, key_cleared: bool)
#[no_mangle]
pub extern "C" fn run_cpu_cycles(
    signals: &mut [u64],
    ram: &mut [u8],
    rom: &[u8],
    n: usize,
    key_data: u8,
    key_ready: bool,
) -> (bool, bool) {{
    let mut next_regs = [0u64; {}];
    let mut text_dirty = false;
    let mut key_cleared = false;
    let mut key_is_ready = key_ready;

    for _ in 0..n {{
        for _ in 0..14 {{
            // Set keyboard state
            signals[{}] = if key_is_ready {{ (key_data as u64) | 0x80 }} else {{ 0 }};

            // Falling edge
            signals[{}] = 0;
            do_evaluate!(signals);

            // Provide RAM/ROM data
            let addr = signals[{}] as usize;
            signals[{}] = if addr >= 0xD000 && addr <= 0xFFFF {{
                let rom_offset = addr - 0xD000;
                if rom_offset < rom.len() {{ rom[rom_offset] as u64 }} else {{ 0 }}
            }} else if addr < ram.len() {{
                ram[addr] as u64
            }} else {{
                0
            }};
            do_evaluate!(signals);

            // Rising edge - clock triggers register update
            signals[{}] = 1;
            do_evaluate!(signals);
            do_tick!(signals, next_regs);
            do_update_regs!(signals, next_regs);
            do_evaluate!(signals);

            // Handle RAM writes
            if signals[{}] == 1 {{
                let write_addr = signals[{}] as usize;
                if write_addr < ram.len() {{
                    ram[write_addr] = (signals[{}] & 0xFF) as u8;
                    if write_addr >= 0x0400 && write_addr <= 0x07FF {{
                        text_dirty = true;
                    }}
                }}
            }}

            // Check keyboard strobe clear
            if signals[{}] == 1 {{
                key_is_ready = false;
                key_cleared = true;
            }}
        }}
    }}

    (text_dirty, key_cleared)
}}
"#, reg_count, k_idx, clk_idx, ram_addr_idx, ram_do_idx, clk_idx,
    ram_we_idx, ram_addr_idx, d_idx, read_key_idx));

    code
}

/// Ruby wrapper using RefCell for interior mutability
#[magnus::wrap(class = "FirrtlCompiler")]
struct RubyFirrtlCompiler {
    sim: RefCell<SimulatorState>,
}

impl RubyFirrtlCompiler {
    fn new(json: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = SimulatorState::new(&json)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self { sim: RefCell::new(sim) })
    }

    fn compile(&self) -> Result<bool, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        self.sim.borrow_mut().compile()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn is_compiled(&self) -> bool {
        self.sim.borrow().compiled
    }

    fn generated_code(&self) -> String {
        let sim = self.sim.borrow();
        generate_full_code(&sim.ir, &sim.signal_indices)
    }

    fn signal_count(&self) -> usize {
        self.sim.borrow().signal_count()
    }

    fn reg_count(&self) -> usize {
        self.sim.borrow().reg_count()
    }

    fn poke(&self, name: String, value: i64) {
        self.sim.borrow_mut().poke(&name, value as u64);
    }

    fn peek(&self, name: String) -> i64 {
        self.sim.borrow().peek(&name) as i64
    }

    fn evaluate(&self) {
        self.sim.borrow_mut().evaluate();
    }

    fn tick(&self) {
        self.sim.borrow_mut().tick();
    }

    fn reset(&self) {
        self.sim.borrow_mut().reset();
    }

    fn load_rom(&self, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid ROM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        let mut sim = self.sim.borrow_mut();
        for (i, &b) in bytes.iter().enumerate() {
            if i >= sim.rom.len() { break; }
            sim.rom[i] = b;
        }
        Ok(())
    }

    fn load_ram(&self, data: RArray, offset: usize) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid RAM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        let mut sim = self.sim.borrow_mut();
        for (i, &b) in bytes.iter().enumerate() {
            let addr = offset + i;
            if addr >= sim.ram.len() { break; }
            sim.ram[addr] = b;
        }
        Ok(())
    }

    fn read_ram(&self, start: usize, length: usize) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let end = (start + length).min(sim.ram.len());
        let data: Vec<i64> = sim.ram[start..end].iter().map(|&b| b as i64).collect();
        Ok(ruby.ary_from_vec(data))
    }

    fn write_ram(&self, start: usize, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        let mut sim = self.sim.borrow_mut();
        let end = (start + bytes.len()).min(sim.ram.len());
        let len = end - start;
        sim.ram[start..end].copy_from_slice(&bytes[..len]);
        Ok(())
    }

    fn run_cpu_cycles(&self, n: usize, key_data: i64, key_ready: bool) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let result = self.sim.borrow_mut().run_cpu_cycles(n, key_data as u8, key_ready);

        let hash = ruby.hash_new();
        hash.aset(ruby.sym_new("text_dirty"), result.text_dirty)?;
        hash.aset(ruby.sym_new("key_cleared"), result.key_cleared)?;
        hash.aset(ruby.sym_new("cycles_run"), result.cycles_run as i64)?;
        Ok(hash)
    }

    fn input_names(&self) -> Vec<String> {
        self.sim.borrow().ir.ports.iter()
            .filter(|p| p.direction == "in")
            .map(|p| p.name.clone())
            .collect()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().ir.ports.iter()
            .filter(|p| p.direction == "out")
            .map(|p| p.name.clone())
            .collect()
    }

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("signal_count"), sim.signal_count() as i64)?;
        hash.aset(ruby.sym_new("reg_count"), sim.reg_count() as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.ir.ports.iter().filter(|p| p.direction == "in").count() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.ir.ports.iter().filter(|p| p.direction == "out").count() as i64)?;
        hash.aset(ruby.sym_new("assign_count"), sim.ir.assigns.len() as i64)?;
        hash.aset(ruby.sym_new("process_count"), sim.ir.processes.len() as i64)?;
        hash.aset(ruby.sym_new("compiled"), sim.compiled)?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let class = ruby.define_class("FirrtlCompiler", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyFirrtlCompiler::new, 1))?;
    class.define_method("compile", method!(RubyFirrtlCompiler::compile, 0))?;
    class.define_method("compiled?", method!(RubyFirrtlCompiler::is_compiled, 0))?;
    class.define_method("generated_code", method!(RubyFirrtlCompiler::generated_code, 0))?;
    class.define_method("signal_count", method!(RubyFirrtlCompiler::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyFirrtlCompiler::reg_count, 0))?;
    class.define_method("poke", method!(RubyFirrtlCompiler::poke, 2))?;
    class.define_method("peek", method!(RubyFirrtlCompiler::peek, 1))?;
    class.define_method("evaluate", method!(RubyFirrtlCompiler::evaluate, 0))?;
    class.define_method("tick", method!(RubyFirrtlCompiler::tick, 0))?;
    class.define_method("reset", method!(RubyFirrtlCompiler::reset, 0))?;
    class.define_method("load_rom", method!(RubyFirrtlCompiler::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyFirrtlCompiler::load_ram, 2))?;
    class.define_method("read_ram", method!(RubyFirrtlCompiler::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyFirrtlCompiler::write_ram, 2))?;
    class.define_method("run_cpu_cycles", method!(RubyFirrtlCompiler::run_cpu_cycles, 3))?;
    class.define_method("input_names", method!(RubyFirrtlCompiler::input_names, 0))?;
    class.define_method("output_names", method!(RubyFirrtlCompiler::output_names, 0))?;
    class.define_method("stats", method!(RubyFirrtlCompiler::stats, 0))?;
    class.define_method("native?", method!(RubyFirrtlCompiler::native, 0))?;

    ruby.define_global_const("FIRRTL_COMPILER_AVAILABLE", true)?;

    Ok(())
}
