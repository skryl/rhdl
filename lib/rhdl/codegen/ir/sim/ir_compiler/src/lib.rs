//! IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This compiler generates Rust source code that directly implements the circuit
//! evaluation logic, then compiles it with rustc at runtime for maximum performance.
//!
//! The generated code uses the exact same evaluation semantics as the ir_interpreter,
//! making it easy to verify correctness via PC progression comparison.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::fs;
use std::process::Command;

// ============================================================================
// IR Data Structures (matching JSON format from Ruby's IRToJson)
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Direction {
    In,
    Out,
}

#[derive(Debug, Clone, Deserialize)]
struct PortDef {
    name: String,
    direction: Direction,
    width: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct NetDef {
    name: String,
    width: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct RegDef {
    name: String,
    width: usize,
    #[serde(default)]
    reset_value: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ExprDef {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
    UnaryOp { op: String, operand: Box<ExprDef>, width: usize },
    BinaryOp { op: String, left: Box<ExprDef>, right: Box<ExprDef>, width: usize },
    Mux { condition: Box<ExprDef>, when_true: Box<ExprDef>, when_false: Box<ExprDef>, width: usize },
    Slice { base: Box<ExprDef>, low: usize, #[allow(dead_code)] high: usize, width: usize },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
    MemRead { memory: String, addr: Box<ExprDef>, width: usize },
}

#[derive(Debug, Clone, Deserialize)]
struct AssignDef {
    target: String,
    expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
struct SeqAssignDef {
    target: String,
    expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
struct ProcessDef {
    #[allow(dead_code)]
    name: String,
    clock: Option<String>,
    clocked: bool,
    statements: Vec<SeqAssignDef>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryDef {
    name: String,
    depth: usize,
    #[allow(dead_code)]
    width: usize,
    #[serde(default)]
    initial_data: Vec<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct ModuleIR {
    #[allow(dead_code)]
    name: String,
    ports: Vec<PortDef>,
    nets: Vec<NetDef>,
    regs: Vec<RegDef>,
    assigns: Vec<AssignDef>,
    processes: Vec<ProcessDef>,
    #[serde(default)]
    memories: Vec<MemoryDef>,
}

// ============================================================================
// Simulator State
// ============================================================================

struct IrSimulator {
    /// IR definition
    ir: ModuleIR,
    /// Signal values (Vec for O(1) access)
    signals: Vec<u64>,
    /// Signal widths
    widths: Vec<usize>,
    /// Signal name to index mapping
    name_to_idx: HashMap<String, usize>,
    /// Input names
    input_names: Vec<String>,
    /// Output names
    output_names: Vec<String>,
    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
    /// Next register values buffer
    next_regs: Vec<u64>,
    /// Sequential assignment target indices
    seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    old_clocks: Vec<u64>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Memory arrays
    memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index
    memory_name_to_idx: HashMap<String, usize>,
    /// Compiled library (if compilation succeeded)
    compiled_lib: Option<libloading::Library>,
    /// Whether compilation succeeded
    compiled: bool,
    /// Apple II specific: RAM
    ram: Vec<u8>,
    /// Apple II specific: ROM
    rom: Vec<u8>,
    /// Apple II specific signal indices
    ram_addr_idx: usize,
    ram_do_idx: usize,
    ram_we_idx: usize,
    d_idx: usize,
    clk_idx: usize,
    k_idx: usize,
    read_key_idx: usize,
    cpu_addr_idx: usize,
}

impl IrSimulator {
    fn new(json: &str) -> Result<Self, String> {
        let ir: ModuleIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse IR JSON: {}", e))?;

        let mut signals = Vec::new();
        let mut widths = Vec::new();
        let mut name_to_idx = HashMap::new();
        let mut input_names = Vec::new();
        let mut output_names = Vec::new();

        // Build signal table - ports first
        for port in &ir.ports {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(port.width);
            name_to_idx.insert(port.name.clone(), idx);
            match port.direction {
                Direction::In => input_names.push(port.name.clone()),
                Direction::Out => output_names.push(port.name.clone()),
            }
        }

        // Wires
        for net in &ir.nets {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(net.width);
            name_to_idx.insert(net.name.clone(), idx);
        }

        // Registers with reset values
        let mut reset_values: Vec<(usize, u64)> = Vec::new();
        for reg in &ir.regs {
            let idx = signals.len();
            let reset_val = reg.reset_value.unwrap_or(0);
            signals.push(reset_val);
            widths.push(reg.width);
            name_to_idx.insert(reg.name.clone(), idx);
            if reset_val != 0 {
                reset_values.push((idx, reset_val));
            }
        }

        // Build memory arrays
        let mut memory_arrays = Vec::new();
        let mut memory_name_to_idx = HashMap::new();
        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val;
                }
            }
            memory_arrays.push(data);
            memory_name_to_idx.insert(mem.name.clone(), idx);
        }

        // Build sequential assignment tracking
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_set = std::collections::HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| name_to_idx.get(c).copied())
                .unwrap_or_else(|| *name_to_idx.get("clk_14m").unwrap_or(&0));
            clock_set.insert(clock_idx);

            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                seq_targets.push(target_idx);
                seq_clocks.push(clock_idx);
            }
        }

        // Sort clock indices for deterministic order (HashSet iteration is non-deterministic)
        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let old_clocks = vec![0u64; clock_indices.len()];
        let next_regs = vec![0u64; seq_targets.len()];

        // Build clock_domain_assigns: for each clock domain, list of (seq_assign_idx, target_idx)
        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(clock_list_idx) = clock_indices.iter().position(|&ci| ci == clk_idx) {
                let target_idx = seq_targets[seq_idx];
                clock_domain_assigns[clock_list_idx].push((seq_idx, target_idx));
            }
        }

        // Apple II signal indices
        let ram_addr_idx = *name_to_idx.get("ram_addr").unwrap_or(&0);
        let ram_do_idx = *name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *name_to_idx.get("read_key").unwrap_or(&0);
        // Use CPU's address register for memory reads (not ram_addr which may show video address)
        let cpu_addr_idx = *name_to_idx.get("cpu__addr_reg").unwrap_or(&0);

        Ok(Self {
            ir,
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            reset_values,
            next_regs,
            seq_targets,
            seq_clocks,
            clock_indices,
            old_clocks,
            clock_domain_assigns,
            memory_arrays,
            memory_name_to_idx,
            compiled_lib: None,
            compiled: false,
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx,
            ram_do_idx,
            ram_we_idx,
            d_idx,
            clk_idx,
            k_idx,
            read_key_idx,
            cpu_addr_idx,
        })
    }

    #[inline(always)]
    fn mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    fn expr_width(&self, expr: &ExprDef) -> usize {
        match expr {
            ExprDef::Signal { name, width } => {
                self.name_to_idx.get(name)
                    .and_then(|&idx| self.widths.get(idx).copied())
                    .unwrap_or(*width)
            }
            ExprDef::Literal { width, .. } => *width,
            ExprDef::UnaryOp { width, .. } => *width,
            ExprDef::BinaryOp { width, .. } => *width,
            ExprDef::Mux { width, .. } => *width,
            ExprDef::Slice { width, .. } => *width,
            ExprDef::Concat { width, .. } => *width,
            ExprDef::Resize { width, .. } => *width,
            ExprDef::MemRead { width, .. } => *width,
        }
    }

    /// Evaluate an expression (interpreter mode)
    fn eval_expr(&self, expr: &ExprDef) -> u64 {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                self.signals.get(idx).copied().unwrap_or(0) & Self::mask(*width)
            }
            ExprDef::Literal { value, width } => {
                (*value as u64) & Self::mask(*width)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let val = self.eval_expr(operand);
                let m = Self::mask(*width);
                match op.as_str() {
                    "~" | "not" => (!val) & m,
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let op_mask = Self::mask(op_width);
                        if (val & op_mask) == op_mask { 1 } else { 0 }
                    }
                    "|" | "reduce_or" => if val != 0 { 1 } else { 0 },
                    "^" | "reduce_xor" => (val.count_ones() & 1) as u64,
                    _ => val,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr(left);
                let r = self.eval_expr(right);
                let m = Self::mask(*width);
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
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.eval_expr(condition);
                let m = Self::mask(*width);
                if cond != 0 {
                    self.eval_expr(when_true) & m
                } else {
                    self.eval_expr(when_false) & m
                }
            }
            ExprDef::Slice { base, low, width, .. } => {
                let val = self.eval_expr(base);
                (val >> low) & Self::mask(*width)
            }
            ExprDef::Concat { parts, width } => {
                // Parts are ordered [high, ..., low], process in reverse
                let mut result = 0u64;
                let mut shift = 0usize;
                for part in parts.iter().rev() {
                    let part_val = self.eval_expr(part);
                    let part_width = self.expr_width(part);
                    result |= (part_val & Self::mask(part_width)) << shift;
                    shift += part_width;
                }
                result & Self::mask(*width)
            }
            ExprDef::Resize { expr, width } => {
                self.eval_expr(expr) & Self::mask(*width)
            }
            ExprDef::MemRead { memory, addr, width } => {
                if let Some(&mem_idx) = self.memory_name_to_idx.get(memory) {
                    if let Some(arr) = self.memory_arrays.get(mem_idx) {
                        let addr_val = self.eval_expr(addr) as usize;
                        if addr_val < arr.len() {
                            arr[addr_val] & Self::mask(*width)
                        } else {
                            0
                        }
                    } else {
                        0
                    }
                } else {
                    0
                }
            }
        }
    }

    /// Evaluate all combinational assignments
    fn evaluate(&mut self) {
        if let Some(ref lib) = self.compiled_lib {
            // Use compiled evaluate function
            unsafe {
                let func: libloading::Symbol<unsafe extern "C" fn(*mut u64, usize)> =
                    lib.get(b"evaluate").expect("evaluate function not found");
                func(self.signals.as_mut_ptr(), self.signals.len());
            }
        } else {
            // Interpreted mode
            self.evaluate_interpreted();
        }
    }

    fn evaluate_interpreted(&mut self) {
        for assign in self.ir.assigns.clone() {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                let value = self.eval_expr(&assign.expr);
                let width = self.widths.get(idx).copied().unwrap_or(64);
                self.signals[idx] = value & Self::mask(width);
            }
        }
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let mask = Self::mask(self.widths[idx]);
        self.signals[idx] = value & mask;
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        Ok(self.signals[idx])
    }

    /// Clock tick - sample registers on rising edges
    fn tick(&mut self) {
        // Multi-clock domain timing:
        // 1. Sample ALL register expressions ONCE at tick start (before any updates)
        // 2. Evaluate combinational logic and detect clock edges
        // 3. Update registers for clocks with rising edges
        // 4. Iterate for derived clock domains

        // Save old clock values FIRST (before evaluate changes them)
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.old_clocks[i] = self.signals[clk_idx];
        }

        // Evaluate combinational logic (may change derived clocks)
        self.evaluate();

        // Sample ALL register inputs
        let mut reg_idx = 0;
        for process in self.ir.processes.clone() {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let value = self.eval_expr(&stmt.expr);
                let target_idx = self.seq_targets[reg_idx];
                let width = self.widths.get(target_idx).copied().unwrap_or(64);
                self.next_regs[reg_idx] = value & Self::mask(width);
                reg_idx += 1;
            }
        }

        // Iterate for derived clock domains
        // Each iteration may cause new clock edges as registers update
        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            let mut any_edge = false;

            for (clock_list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
                let old_val = self.old_clocks[clock_list_idx];
                let new_val = self.signals[clk_idx];

                // Check for rising edge (0 -> 1)
                if old_val == 0 && new_val == 1 {
                    any_edge = true;

                    // Update only registers clocked by this signal (pre-grouped for efficiency)
                    for &(seq_idx, target_idx) in &self.clock_domain_assigns[clock_list_idx] {
                        self.signals[target_idx] = self.next_regs[seq_idx];
                    }

                    // Mark this clock as processed (set old to 1 to prevent re-triggering)
                    self.old_clocks[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            // Re-evaluate combinational logic (may trigger derived clocks)
            self.evaluate();
        }
    }

    fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
    }

    fn signal_count(&self) -> usize {
        self.signals.len()
    }

    fn reg_count(&self) -> usize {
        self.seq_targets.len()
    }

    // ========================================================================
    // Code Generation
    // ========================================================================

    fn generate_code(&self) -> String {
        let mut code = String::new();

        code.push_str("//! Auto-generated circuit simulation code\n");
        code.push_str("//! Generated by RHDL IR Compiler\n\n");

        // Generate mask helper
        code.push_str("#[inline(always)]\n");
        code.push_str("fn mask(width: usize) -> u64 {\n");
        code.push_str("    if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }\n");
        code.push_str("}\n\n");

        // Generate memory arrays if any
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!("static MEM_{}: &[u64] = &[\n", idx));
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i > 0 && i % 8 == 0 {
                    code.push_str("\n");
                }
                code.push_str(&format!("    {},", val));
            }
            if mem.initial_data.is_empty() {
                for i in 0..mem.depth.min(256) {
                    if i > 0 && i % 8 == 0 {
                        code.push_str("\n");
                    }
                    code.push_str("    0,");
                }
            }
            code.push_str("\n];\n\n");
        }

        // Generate evaluate function
        code.push_str("/// Evaluate all combinational assignments\n");
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(signals: *mut u64, len: usize) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");

        for assign in &self.ir.assigns {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                let width = self.widths.get(idx).copied().unwrap_or(64);
                let expr_code = self.expr_to_rust(&assign.expr);
                code.push_str(&format!("    signals[{}] = ({}) & mask({});\n", idx, expr_code, width));
            }
        }

        code.push_str("}\n\n");

        // Generate tick function
        self.generate_tick_function(&mut code);

        // Generate run_cpu_cycles function
        self.generate_run_cpu_cycles(&mut code);

        code
    }

    fn expr_to_rust(&self, expr: &ExprDef) -> String {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                format!("(signals[{}] & mask({}))", idx, width)
            }
            ExprDef::Literal { value, width } => {
                format!("({}u64 & mask({}))", *value as u64, width)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code = self.expr_to_rust(operand);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & mask({}))", operand_code, width),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        format!("(if ({} & mask({})) == mask({}) {{ 1 }} else {{ 0 }})",
                                operand_code, op_width, op_width)
                    }
                    "|" | "reduce_or" => format!("(if {} != 0 {{ 1 }} else {{ 0 }})", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u64 & 1)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust(left);
                let r = self.expr_to_rust(right);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & mask({}))", l, r, width),
                    "-" => format!("({}.wrapping_sub({}) & mask({}))", l, r, width),
                    "*" => format!("({}.wrapping_mul({}) & mask({}))", l, r, width),
                    "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0 }})", r, l, r),
                    "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0 }})", r, l, r),
                    "<<" => format!("(({} << {}.min(63)) & mask({}))", l, r, width),
                    ">>" => format!("({} >> {}.min(63))", l, r),
                    "==" => format!("(if {} == {} {{ 1 }} else {{ 0 }})", l, r),
                    "!=" => format!("(if {} != {} {{ 1 }} else {{ 0 }})", l, r),
                    "<" => format!("(if {} < {} {{ 1 }} else {{ 0 }})", l, r),
                    ">" => format!("(if {} > {} {{ 1 }} else {{ 0 }})", l, r),
                    "<=" | "le" => format!("(if {} <= {} {{ 1 }} else {{ 0 }})", l, r),
                    ">=" => format!("(if {} >= {} {{ 1 }} else {{ 0 }})", l, r),
                    _ => "0".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.expr_to_rust(condition);
                let t = self.expr_to_rust(when_true);
                let f = self.expr_to_rust(when_false);
                format!("(if {} != 0 {{ {} }} else {{ {} }} & mask({}))", cond, t, f, width)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust(base);
                format!("(({} >> {}) & mask({}))", base_code, low, width)
            }
            ExprDef::Concat { parts, width } => {
                // Wrap the entire concat expression in parens to ensure proper precedence
                // when used as operand in binary ops like + (wrapping_add)
                let mut result = String::from("((");
                let mut shift = 0usize;
                let mut first = true;
                for part in parts.iter().rev() {
                    let part_code = self.expr_to_rust(part);
                    let part_width = self.expr_width(part);
                    if !first {
                        result.push_str(" | ");
                    }
                    first = false;
                    if shift > 0 {
                        result.push_str(&format!("(({} & mask({})) << {})", part_code, part_width, shift));
                    } else {
                        result.push_str(&format!("({} & mask({}))", part_code, part_width));
                    }
                    shift += part_width;
                }
                result.push_str(&format!(") & mask({}))", width));
                result
            }
            ExprDef::Resize { expr, width } => {
                let expr_code = self.expr_to_rust(expr);
                format!("({} & mask({}))", expr_code, width)
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust(addr);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & mask({}))",
                        mem_idx, addr_code, width)
            }
        }
    }

    fn generate_tick_function(&self, code: &mut String) {
        // Build clock domain info
        let mut clock_domains: std::collections::HashMap<usize, Vec<usize>> = std::collections::HashMap::new();
        let mut seq_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| self.name_to_idx.get(c).copied())
                .unwrap_or_else(|| *self.name_to_idx.get("clk_14m").unwrap_or(&0));

            for _ in &process.statements {
                clock_domains.entry(clock_idx).or_default().push(seq_idx);
                seq_idx += 1;
            }
        }

        // IMPORTANT: Use self.clock_indices for consistent ordering (HashMaps have non-deterministic order)
        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        code.push_str("/// Clock tick - sample registers on rising edges\n");
        code.push_str("#[no_mangle]\n");
        code.push_str(&format!("pub unsafe extern \"C\" fn tick(signals: *mut u64, len: usize, old_clocks: *mut u64, next_regs: *mut u64) {{\n"));
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str(&format!("    let old_clocks = std::slice::from_raw_parts_mut(old_clocks, {});\n", num_clocks));
        code.push_str(&format!("    let next_regs = std::slice::from_raw_parts_mut(next_regs, {});\n", num_regs));
        code.push_str("\n");

        // Save old clock values FIRST (before evaluate changes derived clocks)
        // At this point clk_14m=1 but derived clocks haven't propagated yet
        for (i, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk_idx));
        }
        code.push_str("\n");

        // Call evaluate (propagates clk_14m=1 to derived clocks)
        code.push_str("    evaluate(signals.as_mut_ptr(), signals.len());\n\n");

        // Sample all register inputs
        code.push_str("    // Sample register inputs\n");
        let mut reg_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let expr_code = self.expr_to_rust(&stmt.expr);
                let target_idx = self.seq_targets[reg_idx];
                let width = self.widths.get(target_idx).copied().unwrap_or(64);
                code.push_str(&format!("    next_regs[{}] = ({}) & mask({});\n", reg_idx, expr_code, width));
                reg_idx += 1;
            }
        }
        code.push_str("\n");

        // Iterate for derived clock domains
        code.push_str("    // Iterate for derived clock domains\n");
        code.push_str("    for _ in 0..10 {\n");
        code.push_str("        let mut any_edge = false;\n\n");

        // Check for rising edges and update registers
        for (clock_list_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        if old_clocks[{}] == 0 && signals[{}] == 1 {{\n", clock_list_idx, clk_idx));
            code.push_str("            any_edge = true;\n");

            if let Some(reg_indices) = clock_domains.get(&clk_idx) {
                for &ri in reg_indices {
                    let target_idx = self.seq_targets[ri];
                    code.push_str(&format!("            signals[{}] = next_regs[{}];\n", target_idx, ri));
                }
            }

            code.push_str(&format!("            old_clocks[{}] = 1;\n", clock_list_idx));
            code.push_str("        }\n");
        }

        code.push_str("\n        if !any_edge { break; }\n");
        code.push_str("        evaluate(signals.as_mut_ptr(), signals.len());\n");
        code.push_str("    }\n");

        code.push_str("}\n\n");
    }

    fn generate_run_cpu_cycles(&self, code: &mut String) {
        let clk_idx = self.clk_idx;
        let k_idx = self.k_idx;
        let ram_addr_idx = self.ram_addr_idx;
        let cpu_addr_idx = self.cpu_addr_idx;  // Use CPU's addr reg for reads
        let ram_do_idx = self.ram_do_idx;
        let ram_we_idx = self.ram_we_idx;
        let d_idx = self.d_idx;
        let read_key_idx = self.read_key_idx;

        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        code.push_str("/// Run N CPU cycles\n");
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_cpu_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    ram: *mut u8,\n");
        code.push_str("    ram_len: usize,\n");
        code.push_str("    rom: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    key_data: u8,\n");
        code.push_str("    key_ready: bool,\n");
        code.push_str(") -> (bool, bool) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let ram = std::slice::from_raw_parts_mut(ram, ram_len);\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom, rom_len);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut text_dirty = false;\n");
        code.push_str("    let mut key_cleared = false;\n");
        code.push_str("    let mut key_is_ready = key_ready;\n\n");

        // Initialize old_clocks
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");
        code.push_str("        for _ in 0..14 {\n");

        // Set keyboard input
        code.push_str(&format!("            signals[{}] = if key_is_ready {{ (key_data as u64) | 0x80 }} else {{ 0 }};\n\n", k_idx));

        // Falling edge
        code.push_str(&format!("            // Falling edge\n"));
        code.push_str(&format!("            signals[{}] = 0;\n", clk_idx));
        code.push_str("            evaluate(signals.as_mut_ptr(), signals.len());\n\n");

        // Provide RAM/ROM data (use ram_addr to match Ruby behavior simulator)
        code.push_str(&format!("            // Provide RAM/ROM data\n"));
        code.push_str(&format!("            let addr = signals[{}] as usize;\n", ram_addr_idx));
        code.push_str(&format!("            signals[{}] = if addr >= 0xD000 {{\n", ram_do_idx));
        code.push_str("                let rom_offset = addr.wrapping_sub(0xD000);\n");
        code.push_str("                if rom_offset < rom.len() { rom[rom_offset] as u64 } else { 0 }\n");
        code.push_str("            } else if addr >= 0xC000 {\n");
        code.push_str("                0  // I/O space\n");
        code.push_str("            } else if addr < ram.len() {\n");
        code.push_str("                ram[addr] as u64\n");
        code.push_str("            } else {\n");
        code.push_str("                0\n");
        code.push_str("            };\n\n");

        // Rising edge
        code.push_str(&format!("            // Rising edge\n"));
        code.push_str(&format!("            signals[{}] = 1;\n", clk_idx));
        code.push_str("            tick(signals.as_mut_ptr(), signals.len(), old_clocks.as_mut_ptr(), next_regs.as_mut_ptr());\n\n");

        // Handle RAM writes
        code.push_str(&format!("            // Handle RAM writes\n"));
        code.push_str(&format!("            if signals[{}] == 1 {{\n", ram_we_idx));
        code.push_str(&format!("                let write_addr = signals[{}] as usize;\n", ram_addr_idx));
        code.push_str("                if write_addr < 0xC000 && write_addr < ram.len() {\n");
        code.push_str(&format!("                    ram[write_addr] = (signals[{}] & 0xFF) as u8;\n", d_idx));
        code.push_str("                    if write_addr >= 0x0400 && write_addr <= 0x07FF {\n");
        code.push_str("                        text_dirty = true;\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("            }\n\n");

        // Check keyboard strobe
        code.push_str(&format!("            // Check keyboard strobe\n"));
        code.push_str(&format!("            if signals[{}] == 1 {{\n", read_key_idx));
        code.push_str("                key_is_ready = false;\n");
        code.push_str("                key_cleared = true;\n");
        code.push_str("            }\n");

        code.push_str("        }\n");
        code.push_str("    }\n\n");
        code.push_str("    (text_dirty, key_cleared)\n");
        code.push_str("}\n");
    }

    fn compile(&mut self) -> Result<bool, String> {
        let code = self.generate_code();

        // Compute hash for caching
        let code_hash = {
            let mut hash: u64 = 0xcbf29ce484222325;
            for byte in code.bytes() {
                hash ^= byte as u64;
                hash = hash.wrapping_mul(0x100000001b3);
            }
            hash
        };

        // Cache paths
        let cache_dir = std::env::temp_dir().join("rhdl_cache");
        let _ = fs::create_dir_all(&cache_dir);

        let lib_ext = if cfg!(target_os = "macos") {
            "dylib"
        } else if cfg!(target_os = "windows") {
            "dll"
        } else {
            "so"
        };
        let lib_name = format!("rhdl_ir_{:016x}.{}", code_hash, lib_ext);
        let lib_path = cache_dir.join(&lib_name);
        let src_path = cache_dir.join(format!("rhdl_ir_{:016x}.rs", code_hash));

        // Check cache
        if lib_path.exists() {
            unsafe {
                let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
                self.compiled_lib = Some(lib);
            }
            self.compiled = true;
            return Ok(true);
        }

        // Write source and compile
        fs::write(&src_path, &code).map_err(|e| e.to_string())?;

        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "-C", "opt-level=3",
                "-C", "target-cpu=native",
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

        // Load compiled library
        unsafe {
            let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
            self.compiled_lib = Some(lib);
        }

        self.compiled = true;
        Ok(true)
    }

    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> BatchResult {
        if let Some(ref lib) = self.compiled_lib {
            unsafe {
                #[allow(improper_ctypes_definitions)]
                type RunCpuCyclesFn = unsafe extern "C" fn(
                    *mut u64, usize, *mut u8, usize, *const u8, usize, usize, u8, bool
                ) -> (bool, bool);
                let func: libloading::Symbol<RunCpuCyclesFn> =
                    lib.get(b"run_cpu_cycles").expect("run_cpu_cycles not found");
                let (text_dirty, key_cleared) = func(
                    self.signals.as_mut_ptr(),
                    self.signals.len(),
                    self.ram.as_mut_ptr(),
                    self.ram.len(),
                    self.rom.as_ptr(),
                    self.rom.len(),
                    n,
                    key_data,
                    key_ready,
                );
                return BatchResult { cycles_run: n, text_dirty, key_cleared };
            }
        }

        // Fallback to interpreted mode
        let mut text_dirty = false;
        let mut key_cleared = false;
        let mut key_is_ready = key_ready;

        for _ in 0..n {
            for _ in 0..14 {
                // Set keyboard input
                self.signals[self.k_idx] = if key_is_ready { (key_data as u64) | 0x80 } else { 0 };

                // Falling edge
                self.signals[self.clk_idx] = 0;
                self.evaluate();

                // Provide RAM/ROM data (use ram_addr to match Ruby behavior simulator)
                let addr = self.signals[self.ram_addr_idx] as usize;
                self.signals[self.ram_do_idx] = if addr >= 0xD000 {
                    let rom_offset = addr.wrapping_sub(0xD000);
                    if rom_offset < self.rom.len() { self.rom[rom_offset] as u64 } else { 0 }
                } else if addr >= 0xC000 {
                    0
                } else if addr < self.ram.len() {
                    self.ram[addr] as u64
                } else {
                    0
                };

                // Rising edge
                self.signals[self.clk_idx] = 1;
                self.tick();

                // Handle RAM writes
                if self.signals[self.ram_we_idx] == 1 {
                    let write_addr = self.signals[self.ram_addr_idx] as usize;
                    if write_addr < 0xC000 && write_addr < self.ram.len() {
                        self.ram[write_addr] = (self.signals[self.d_idx] & 0xFF) as u8;
                        if write_addr >= 0x0400 && write_addr <= 0x07FF {
                            text_dirty = true;
                        }
                    }
                }

                // Check keyboard strobe
                if self.signals[self.read_key_idx] == 1 {
                    key_is_ready = false;
                    key_cleared = true;
                }
            }
        }

        BatchResult { cycles_run: n, text_dirty, key_cleared }
    }

    fn load_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.rom.len());
        self.rom[..len].copy_from_slice(&data[..len]);
    }

    fn load_ram(&mut self, data: &[u8], offset: usize) {
        let end = (offset + data.len()).min(self.ram.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.ram[offset..end].copy_from_slice(&data[..len]);
        }
    }
}

struct BatchResult {
    text_dirty: bool,
    key_cleared: bool,
    cycles_run: usize,
}

// ============================================================================
// Ruby Bindings
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

#[magnus::wrap(class = "RHDL::Codegen::IR::IrCompiler")]
struct RubyIrCompiler {
    sim: RefCell<IrSimulator>,
}

impl RubyIrCompiler {
    fn new(json: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = IrSimulator::new(&json)
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
        self.sim.borrow().generate_code()
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

    fn reset(&self) {
        self.sim.borrow_mut().reset();
    }

    fn signal_count(&self) -> usize {
        self.sim.borrow().signal_count()
    }

    fn reg_count(&self) -> usize {
        self.sim.borrow().reg_count()
    }

    fn input_names(&self) -> Vec<String> {
        self.sim.borrow().input_names.clone()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().output_names.clone()
    }

    fn load_rom(&self, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid ROM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_rom(&bytes);
        Ok(())
    }

    fn load_ram(&self, data: RArray, offset: usize) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid RAM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_ram(&bytes, offset);
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

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("signal_count"), sim.signal_count() as i64)?;
        hash.aset(ruby.sym_new("reg_count"), sim.reg_count() as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.input_names.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.output_names.len() as i64)?;
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
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let ir = codegen.define_module("IR")?;

    let class = ir.define_class("IrCompiler", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyIrCompiler::new, 1))?;
    class.define_method("compile", method!(RubyIrCompiler::compile, 0))?;
    class.define_method("compiled?", method!(RubyIrCompiler::is_compiled, 0))?;
    class.define_method("generated_code", method!(RubyIrCompiler::generated_code, 0))?;
    class.define_method("poke", method!(RubyIrCompiler::poke, 2))?;
    class.define_method("peek", method!(RubyIrCompiler::peek, 1))?;
    class.define_method("evaluate", method!(RubyIrCompiler::evaluate, 0))?;
    class.define_method("tick", method!(RubyIrCompiler::tick, 0))?;
    class.define_method("reset", method!(RubyIrCompiler::reset, 0))?;
    class.define_method("signal_count", method!(RubyIrCompiler::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyIrCompiler::reg_count, 0))?;
    class.define_method("input_names", method!(RubyIrCompiler::input_names, 0))?;
    class.define_method("output_names", method!(RubyIrCompiler::output_names, 0))?;
    class.define_method("load_rom", method!(RubyIrCompiler::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyIrCompiler::load_ram, 2))?;
    class.define_method("run_cpu_cycles", method!(RubyIrCompiler::run_cpu_cycles, 3))?;
    class.define_method("read_ram", method!(RubyIrCompiler::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyIrCompiler::write_ram, 2))?;
    class.define_method("stats", method!(RubyIrCompiler::stats, 0))?;
    class.define_method("native?", method!(RubyIrCompiler::native, 0))?;

    Ok(())
}
