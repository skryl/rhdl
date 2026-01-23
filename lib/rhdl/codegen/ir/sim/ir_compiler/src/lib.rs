//! FIRRTL JIT Compiler
//!
//! This module generates specialized Rust code for a circuit and compiles it
//! at runtime for maximum simulation performance. Instead of interpreting
//! bytecode, we generate native code that directly computes signal values.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
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
    #[serde(default)]
    reset_value: Option<u64>,
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
    #[serde(default)]
    initial_data: Vec<u64>,
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
    #[serde(rename = "mem_read")]
    MemRead { memory: String, addr: Box<Expr>, width: u32 },
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
    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
    /// Multi-clock domain support: clock signal index for each sequential assignment
    seq_clocks: Vec<usize>,
    /// Unique clock signal indices used by any clocked process
    clock_indices: Vec<usize>,
    /// Old clock values for rising edge detection
    old_clocks: Vec<u64>,
    /// Memory arrays for mem_read operations
    memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index mapping
    mem_name_to_idx: HashMap<String, usize>,
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
        // Track reset values
        let mut reset_values: Vec<(usize, u64)> = Vec::new();
        for reg in &ir.regs {
            signal_indices.insert(reg.name.clone(), idx);
            if let Some(reset_val) = reg.reset_value {
                if reset_val != 0 {
                    reset_values.push((idx, reset_val));
                }
            }
            idx += 1;
        }

        let signal_count = signal_indices.len();
        let reg_count = count_regs(&ir);

        // Initialize signals (including reset values for registers)
        let mut signals = vec![0u64; signal_count];
        for &(idx, reset_val) in &reset_values {
            signals[idx] = reset_val;
        }

        // Build multi-clock domain tracking
        // seq_clocks[i] = clock signal index for sequential assignment i
        let mut seq_clocks = Vec::new();
        let mut clock_set = HashSet::new();
        for process in &ir.processes {
            if process.clocked {
                let clock_idx = process.clock.as_ref()
                    .and_then(|name| signal_indices.get(name))
                    .cloned()
                    .unwrap_or(0);
                clock_set.insert(clock_idx);
                for _ in &process.statements {
                    seq_clocks.push(clock_idx);
                }
            }
        }
        let clock_indices: Vec<usize> = clock_set.into_iter().collect();
        let old_clocks = clock_indices.iter().map(|&idx| signals[idx]).collect();

        // Build memory arrays and name-to-index mapping
        let mut memory_arrays = Vec::new();
        let mut mem_name_to_idx = HashMap::new();
        for (i, mem) in ir.memories.iter().enumerate() {
            mem_name_to_idx.insert(mem.name.clone(), i);
            let mut arr = vec![0u64; mem.depth as usize];
            // Initialize with initial_data if provided
            for (j, &val) in mem.initial_data.iter().enumerate() {
                if j < arr.len() {
                    arr[j] = val;
                }
            }
            memory_arrays.push(arr);
        }

        Ok(SimulatorState {
            ir,
            signal_indices,
            signals,
            next_regs: vec![0; reg_count],
            ram: vec![0; 48 * 1024],
            rom: vec![0; 12 * 1024],
            compiled_lib: None,
            compiled: false,
            reset_values,
            seq_clocks,
            clock_indices,
            old_clocks,
            memory_arrays,
            mem_name_to_idx,
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
        if std::env::var("RHDL_USE_COMPILED_EVAL").is_ok() {
            if let Some(ref lib) = self.compiled_lib {
                unsafe {
                    let func: libloading::Symbol<unsafe extern "C" fn(&mut [u64])> =
                        lib.get(b"evaluate").unwrap();
                    func(&mut self.signals);
                    return;
                }
            }
        }
        self.evaluate_interpreted();
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
                // Concat in HDL: cat(high, low) puts first arg in high bits
                // Parts are ordered [high, ..., low], so we process in REVERSE
                // to build up from low bits (shift = 0) to high bits
                let mut result = 0u64;
                let mut shift = 0u32;
                for part in parts.iter().rev() {
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
            Expr::MemRead { memory, addr, width } => {
                if let Some(&mem_idx) = self.mem_name_to_idx.get(memory) {
                    if let Some(arr) = self.memory_arrays.get(mem_idx) {
                        let addr_val = self.eval_expr(addr) as usize;
                        let bounded_addr = addr_val % arr.len().max(1);
                        arr.get(bounded_addr).cloned().unwrap_or(0) & mask(*width)
                    } else {
                        0
                    }
                } else {
                    0
                }
            }
        }
    }

    fn tick(&mut self) {
        // Capture initial clock values BEFORE any updates
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.old_clocks[i] = self.signals[clk_idx];
        }

        self.evaluate();

        // Always use the interpreted tick loop for proper derived clock handling
        // The compiled tick function uses static state that doesn't work well with iteration
        {
            // Iterate until no more rising edges are detected (delta-cycle simulation)
            // This handles cascading clocks (e.g., clk_14m -> timing__clk_14m -> q3 -> cpu__clk)
            // IMPORTANT: Keep old_clocks fixed at the start-of-tick values
            // This allows detecting cascading rising edges (e.g., q3 going 0->1 after timing__q3 update)
            let mut processed_clocks: HashSet<usize> = HashSet::new();
            let max_iterations = 10;
            for iteration in 0..max_iterations {
                let had_edges = self.tick_interpreted_check_edges_track(&mut processed_clocks);
                if !had_edges {
                    break;
                }
                // After updating registers, re-evaluate combinational logic
                // This may cause new clock signals to change (e.g., q3 = timing__q3)
                self.evaluate();
                if std::env::var("RHDL_DEBUG_TICK").is_ok() {
                    eprintln!("tick iteration {}: checking for more edges", iteration);
                }
            }
        }
    }

    /// Check for edges and update registers, tracking which clocks have been processed.
    /// Returns true if any NEW rising edges were detected (clocks not already processed).
    fn tick_interpreted_check_edges_track(&mut self, processed_clocks: &mut HashSet<usize>) -> bool {
        // Multi-clock domain: detect rising edges on each clock
        // Only consider clocks that haven't been processed yet in this tick
        let mut rising_clocks = HashSet::new();
        if std::env::var("RHDL_DEBUG_TICK").is_ok() {
            eprintln!("tick_interpreted_check_edges_track: checking {} clocks", self.clock_indices.len());
        }
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            // Skip already processed clocks
            if processed_clocks.contains(&clk_idx) {
                continue;
            }
            let old_val = self.old_clocks[i];
            let new_val = self.signals[clk_idx];
            if std::env::var("RHDL_DEBUG_TICK").is_ok() {
                eprintln!("  clock[{}] at signal[{}]: old={}, new={}", i, clk_idx, old_val, new_val);
            }
            if old_val == 0 && new_val != 0 {
                rising_clocks.insert(clk_idx);
                processed_clocks.insert(clk_idx);
                if std::env::var("RHDL_DEBUG_TICK").is_ok() {
                    eprintln!("    -> RISING EDGE!");
                }
            }
        }

        // If no new rising edges detected, nothing to do
        if rising_clocks.is_empty() {
            if std::env::var("RHDL_DEBUG_TICK").is_ok() {
                eprintln!("  No new rising edges detected");
            }
            return false;
        }
        if std::env::var("RHDL_DEBUG_TICK").is_ok() {
            eprintln!("  Rising edges detected on {} clocks", rising_clocks.len());
        }

        // Sample registers whose clocks have rising edges
        let mut reg_idx = 0;
        for process in &self.ir.processes.clone() {
            if process.clocked {
                let clock_name = process.clock.as_ref().map(|s| s.as_str()).unwrap_or("none");
                let clock_idx = process.clock.as_ref()
                    .and_then(|name| self.signal_indices.get(name))
                    .cloned()
                    .unwrap_or(0);
                let should_sample = rising_clocks.contains(&clock_idx);
                if std::env::var("RHDL_DEBUG_SAMPLE").is_ok() && should_sample {
                    eprintln!("  SAMPLE process {} (clock={}, idx={})",
                        process.name, clock_name, clock_idx);
                }
                for stmt in &process.statements {
                    if should_sample {
                        let value = self.eval_expr(&stmt.expr);
                        if std::env::var("RHDL_DEBUG_SAMPLE").is_ok() && stmt.target.starts_with("cpu__") {
                            eprintln!("    {} <= {}", stmt.target, value);
                        }
                        self.next_regs[reg_idx] = value;
                    }
                    reg_idx += 1;
                }
            }
        }

        // Update registers whose clocks had rising edges
        reg_idx = 0;
        for process in &self.ir.processes.clone() {
            if process.clocked {
                let clock_idx = process.clock.as_ref()
                    .and_then(|name| self.signal_indices.get(name))
                    .cloned()
                    .unwrap_or(0);
                let should_update = rising_clocks.contains(&clock_idx);
                for stmt in &process.statements {
                    if should_update {
                        if let Some(&sig_idx) = self.signal_indices.get(&stmt.target) {
                            let value = self.next_regs[reg_idx];
                            if std::env::var("RHDL_DEBUG_UPDATE").is_ok() && stmt.target.starts_with("cpu__") {
                                eprintln!("    UPDATE signals[{}] ({}) = {}", sig_idx, stmt.target, value);
                            }
                            self.signals[sig_idx] = value;
                        } else if std::env::var("RHDL_DEBUG_UPDATE").is_ok() && stmt.target.starts_with("cpu__") {
                            eprintln!("    UPDATE FAILED: {} not found in signal_indices!", stmt.target);
                        }
                    }
                    reg_idx += 1;
                }
            }
        }

        true
    }


    fn reset(&mut self) {
        for sig in &mut self.signals {
            *sig = 0;
        }
        for reg in &mut self.next_regs {
            *reg = 0;
        }
        // Apply register reset values
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
    }

    fn compile(&mut self) -> Result<bool, String> {
        let code = generate_full_code(&self.ir, &self.signal_indices);

        // Compute a simple hash of the code for caching
        let code_hash = {
            let mut hash: u64 = 0xcbf29ce484222325; // FNV-1a offset basis
            for byte in code.bytes() {
                hash ^= byte as u64;
                hash = hash.wrapping_mul(0x100000001b3); // FNV-1a prime
            }
            hash
        };

        // Cache directory and file paths
        let cache_dir = std::env::temp_dir().join("rhdl_cache");
        let _ = fs::create_dir_all(&cache_dir);

        let lib_ext = if cfg!(target_os = "macos") {
            "dylib"
        } else if cfg!(target_os = "windows") {
            "dll"
        } else {
            "so"
        };
        let lib_name = format!("rhdl_circuit_{:016x}.{}", code_hash, lib_ext);
        let lib_path = cache_dir.join(&lib_name);
        let src_path = cache_dir.join(format!("rhdl_circuit_{:016x}.rs", code_hash));

        // Check if cached library exists
        if lib_path.exists() {
            // Load cached library
            unsafe {
                let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
                self.compiled_lib = Some(lib);
            }
            self.compiled = true;
            return Ok(true);
        }

        // Write generated code and compile
        fs::write(&src_path, &code).map_err(|e| e.to_string())?;

        // Compile with rustc using aggressive optimizations
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

        // Load the compiled library
        unsafe {
            let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
            self.compiled_lib = Some(lib);
        }

        self.compiled = true;
        Ok(true)
    }

    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> CycleResult {
        // Use compiled run_cpu_cycles when available (default behavior).
        // Set RHDL_INTERPRETED_CYCLES=1 to force interpreted mode for debugging.
        if self.compiled && std::env::var("RHDL_INTERPRETED_CYCLES").is_err() {
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
        let cpu_addr_idx = self.signal_indices.get("cpu__addr_reg").cloned();

        for _ in 0..n {
            for _ in 0..14 {
                if let Some(k) = k_idx {
                    self.signals[k] = if key_is_ready { (key_data as u64) | 0x80 } else { 0 };
                }

                if let Some(clk) = clk_idx {
                    self.signals[clk] = 0;
                }
                self.evaluate();

                if let (Some(addr_idx), Some(do_idx)) = (cpu_addr_idx, ram_do_idx) {
                    let addr = self.signals[addr_idx] as usize;
                    let data = if addr >= 0xD000 && addr <= 0xFFFF {
                        let rom_offset = addr - 0xD000;
                        if rom_offset < self.rom.len() { self.rom[rom_offset] as u64 } else { 0 }
                    } else if addr >= 0xC000 {
                        0
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
        Expr::MemRead { width, .. } => *width,
    }
}

/// Extract all signal names read by an expression
fn get_signal_reads(expr: &Expr) -> HashSet<String> {
    let mut reads = HashSet::new();
    collect_signal_reads(expr, &mut reads);
    reads
}

fn collect_signal_reads(expr: &Expr, reads: &mut HashSet<String>) {
    match expr {
        Expr::Signal { name, .. } => { reads.insert(name.clone()); }
        Expr::Literal { .. } => {}
        Expr::UnaryOp { operand, .. } => collect_signal_reads(operand, reads),
        Expr::BinaryOp { left, right, .. } => {
            collect_signal_reads(left, reads);
            collect_signal_reads(right, reads);
        }
        Expr::Mux { condition, when_true, when_false, .. } => {
            collect_signal_reads(condition, reads);
            collect_signal_reads(when_true, reads);
            collect_signal_reads(when_false, reads);
        }
        Expr::Slice { base, .. } => collect_signal_reads(base, reads),
        Expr::Concat { parts, .. } => {
            for part in parts {
                collect_signal_reads(part, reads);
            }
        }
        Expr::Resize { expr, .. } => collect_signal_reads(expr, reads),
        Expr::MemRead { addr, .. } => collect_signal_reads(addr, reads),
    }
}

/// Levelize assignments by dependency for SIMD parallel evaluation
/// Returns a vector of levels, where each level contains assignment indices
/// that can be evaluated in parallel (they depend only on earlier levels)
fn levelize_assigns(assigns: &[Assign], inputs: &HashSet<String>) -> Vec<Vec<usize>> {
    let n = assigns.len();
    if n == 0 {
        return vec![];
    }

    // Build dependency info: for each assign, which signals does it read?
    let mut reads: Vec<HashSet<String>> = assigns.iter()
        .map(|a| get_signal_reads(&a.expr))
        .collect();

    // Which targets are assigned? (map target -> assign index)
    let mut target_to_idx: HashMap<String, usize> = HashMap::new();
    for (i, assign) in assigns.iter().enumerate() {
        target_to_idx.insert(assign.target.clone(), i);
    }

    // Compute level for each assignment
    // Level 0 = depends only on inputs/ports (not on other assignments)
    // Level N = depends on at least one assignment at level N-1
    let mut levels = vec![usize::MAX; n];
    let mut changed = true;
    let max_iterations = n + 1;
    let mut iteration = 0;

    // Initialize: assignments that depend only on inputs get level 0
    for i in 0..n {
        let deps_on_assigns: Vec<usize> = reads[i].iter()
            .filter_map(|sig| target_to_idx.get(sig).cloned())
            .filter(|&j| j != i)  // Exclude self-reference
            .collect();

        if deps_on_assigns.is_empty() {
            levels[i] = 0;
        }
    }

    // Iterate until stable
    while changed && iteration < max_iterations {
        changed = false;
        iteration += 1;

        for i in 0..n {
            if levels[i] != usize::MAX {
                continue;
            }

            // Find max level of dependencies
            let mut max_dep_level = 0usize;
            let mut all_deps_resolved = true;

            for sig in &reads[i] {
                if let Some(&j) = target_to_idx.get(sig) {
                    if j == i { continue; }  // Skip self
                    if levels[j] == usize::MAX {
                        all_deps_resolved = false;
                        break;
                    }
                    max_dep_level = max_dep_level.max(levels[j] + 1);
                }
            }

            if all_deps_resolved {
                levels[i] = max_dep_level;
                changed = true;
            }
        }
    }

    // Handle cycles - put remaining at highest level
    let max_level = levels.iter().filter(|&&l| l != usize::MAX).max().cloned().unwrap_or(0);
    for l in &mut levels {
        if *l == usize::MAX {
            *l = max_level + 1;
        }
    }

    // Group by level
    let num_levels = levels.iter().max().cloned().unwrap_or(0) + 1;
    let mut result: Vec<Vec<usize>> = vec![vec![]; num_levels];
    for (i, &level) in levels.iter().enumerate() {
        result[level].push(i);
    }

    result
}

/// Check if an expression is "simple" enough to benefit from AVX2 batching
/// Simple = signal, literal, or basic binary ops on simple operands (depth <= 2)
fn is_simple_assign(expr: &Expr) -> bool {
    is_simple_expr(expr, 0)
}

fn is_simple_expr(expr: &Expr, depth: usize) -> bool {
    if depth > 2 {
        return false;
    }
    match expr {
        Expr::Signal { .. } | Expr::Literal { .. } => true,
        Expr::UnaryOp { operand, op, .. } => {
            // Allow NOT and simple reduction ops
            matches!(op.as_str(), "~" | "not" | "|" | "&" | "^" | "reduce_and" | "reduce_or" | "reduce_xor")
                && is_simple_expr(operand, depth + 1)
        }
        Expr::BinaryOp { left, right, op, .. } => {
            // Allow basic bitwise and arithmetic ops
            matches!(op.as_str(), "&" | "|" | "^" | "+" | "-" | "==" | "!=" | "<" | ">" | "<=" | ">=")
                && is_simple_expr(left, depth + 1)
                && is_simple_expr(right, depth + 1)
        }
        Expr::Slice { base, .. } => is_simple_expr(base, depth + 1),
        Expr::Resize { expr, .. } => is_simple_expr(expr, depth + 1),
        // Mux, Concat, and MemRead are typically not worth batching
        Expr::Mux { .. } | Expr::Concat { .. } | Expr::MemRead { .. } => false,
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
                // Branchless reduce_and: compare masked value to mask
                "&" | "reduce_and" => {
                    let op_width = get_expr_width(operand);
                    let op_mask = generate_mask_str(op_width);
                    format!("((({} & {}) == {}) as u64)", operand_code, op_mask, op_mask)
                }
                // Branchless reduce_or: != 0 as bool
                "|" | "reduce_or" => format!("(({} != 0) as u64)", operand_code),
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
                // Branchless comparisons using `as u64`
                "==" => format!("(({} == {}) as u64)", left_code, right_code),
                "!=" => format!("(({} != {}) as u64)", left_code, right_code),
                "<" => format!("(({} < {}) as u64)", left_code, right_code),
                ">" => format!("(({} > {}) as u64)", left_code, right_code),
                "<=" | "le" => format!("(({} <= {}) as u64)", left_code, right_code),
                ">=" => format!("(({} >= {}) as u64)", left_code, right_code),
                _ => "0_u64".to_string(),
            }
        }
        Expr::Mux { condition, when_true, when_false, width } => {
            let cond_code = expr_to_rust_with_name(condition, signal_indices, signals_name);
            let true_code = expr_to_rust_with_name(when_true, signal_indices, signals_name);
            let false_code = expr_to_rust_with_name(when_false, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            // Branchless mux using bitwise select:
            // mask = -(cond != 0) as u64  // all 1s if true, all 0s if false
            // result = (true & mask) | (false & !mask)
            format!("({{ let _c = (({} != 0) as u64).wrapping_neg(); (({} & _c) | ({} & !_c)) & {} }})",
                    cond_code, true_code, false_code, m)
        }
        Expr::Slice { base, low, width, .. } => {
            let base_code = expr_to_rust_with_name(base, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            format!("(({} >> {}) & {})", base_code, low, m)
        }
        Expr::Concat { parts, width } => {
            // Concat in HDL: cat(high, low) puts first arg in high bits
            // Parts are ordered [high, ..., low], so we process in REVERSE
            // to build up from low bits (shift = 0) to high bits
            let m = generate_mask_str(*width);
            let mut result = String::from("(");
            let mut shift = 0u32;
            let mut first = true;
            for part in parts.iter().rev() {
                let part_code = expr_to_rust_with_name(part, signal_indices, signals_name);
                let part_width = get_expr_width(part);
                let part_mask = generate_mask_str(part_width);
                if !first { result.push_str(" | "); }
                first = false;
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
        Expr::MemRead { memory, addr, width } => {
            // Generate code to access static memory array MEM_<n>
            let addr_code = expr_to_rust_with_name(addr, signal_indices, signals_name);
            let m = generate_mask_str(*width);
            // Memory name is "mem_<name>", we need to convert to MEM_<NAME> format
            // For now, use a placeholder that will be resolved in generate_full_code
            format!("(MEM_{}.get(({}) as usize % MEM_{}.len()).copied().unwrap_or(0) & {})",
                    memory.to_uppercase().replace("__", "_"), addr_code, memory.to_uppercase().replace("__", "_"), m)
        }
    }
}

fn generate_full_code(ir: &CircuitIR, signal_indices: &HashMap<String, usize>) -> String {
    let mut code = String::new();
    code.push_str("// Auto-generated circuit simulation code\n");
    code.push_str("// DO NOT EDIT - generated by FIRRTL compiler\n\n");

    // Check if we should use AVX2
    code.push_str("#[cfg(target_arch = \"x86_64\")]\n");
    code.push_str("use std::arch::x86_64::*;\n\n");

    // Generate static memory arrays for mem_read operations
    for mem in &ir.memories {
        let mem_name = mem.name.to_uppercase().replace("__", "_");
        code.push_str(&format!("static MEM_{}: &[u64] = &[\n", mem_name));
        for i in 0..mem.depth as usize {
            if i > 0 && i % 16 == 0 {
                code.push_str("\n");
            }
            let val = mem.initial_data.get(i).copied().unwrap_or(0);
            code.push_str(&format!("    {}_u64,", val));
        }
        code.push_str("\n];\n\n");
    }

    // Build input set for levelization
    let inputs: HashSet<String> = ir.ports.iter()
        .filter(|p| p.direction == "in")
        .map(|p| p.name.clone())
        .collect();

    // Levelize assignments for optimal parallel evaluation
    let levels = levelize_assigns(&ir.assigns, &inputs);

    // Generate inline evaluate logic as a macro with levelized AVX2 SIMD
    code.push_str("macro_rules! do_evaluate {\n");
    code.push_str("    ($signals:expr) => {{\n");

    // Process each level
    for level in &levels {
        if level.is_empty() {
            continue;
        }

        // Group assignments at this level by 4s for AVX2
        let chunks: Vec<_> = level.chunks(4).collect();

        for chunk in chunks {
            if chunk.len() == 4 {
                // Generate AVX2 SIMD code for 4 parallel assignments
                // Note: AVX2 is great for simple ops, but for complex expressions
                // the scalar branchless code is often faster due to register pressure.
                // We use AVX2 only for simple signal copies and basic ops.
                let all_simple = chunk.iter().all(|&idx| {
                    is_simple_assign(&ir.assigns[idx].expr)
                });

                if all_simple {
                    // Use AVX2 for simple assignments
                    code.push_str("        #[cfg(target_arch = \"x86_64\")]\n");
                    code.push_str("        unsafe {\n");

                    // Load 4 values
                    code.push_str("            let _v = _mm256_set_epi64x(\n");
                    for (i, &idx) in chunk.iter().rev().enumerate() {
                        let assign = &ir.assigns[idx];
                        let expr_code = expr_to_rust_with_name(&assign.expr, signal_indices, "$signals");
                        if i < 3 {
                            code.push_str(&format!("                {} as i64,\n", expr_code));
                        } else {
                            code.push_str(&format!("                {} as i64\n", expr_code));
                        }
                    }
                    code.push_str("            );\n");

                    // Extract and store 4 values
                    // For x86_64, we extract each 64-bit lane
                    for (i, &idx) in chunk.iter().enumerate() {
                        let assign = &ir.assigns[idx];
                        if let Some(&sig_idx) = signal_indices.get(&assign.target) {
                            code.push_str(&format!(
                                "            $signals[{}] = _mm256_extract_epi64(_v, {}) as u64;\n",
                                sig_idx, i
                            ));
                        }
                    }
                    code.push_str("        }\n");

                    // Fallback for non-x86_64
                    code.push_str("        #[cfg(not(target_arch = \"x86_64\"))]\n");
                    code.push_str("        {\n");
                    for &idx in chunk {
                        let assign = &ir.assigns[idx];
                        if let Some(&sig_idx) = signal_indices.get(&assign.target) {
                            let expr_code = expr_to_rust_with_name(&assign.expr, signal_indices, "$signals");
                            code.push_str(&format!("            $signals[{}] = {};\n", sig_idx, expr_code));
                        }
                    }
                    code.push_str("        }\n");
                } else {
                    // Complex expressions - use scalar code
                    for &idx in chunk {
                        let assign = &ir.assigns[idx];
                        if let Some(&sig_idx) = signal_indices.get(&assign.target) {
                            let expr_code = expr_to_rust_with_name(&assign.expr, signal_indices, "$signals");
                            code.push_str(&format!("        $signals[{}] = {};\n", sig_idx, expr_code));
                        }
                    }
                }
            } else {
                // Remainder - use scalar code
                for &idx in chunk {
                    let assign = &ir.assigns[idx];
                    if let Some(&sig_idx) = signal_indices.get(&assign.target) {
                        let expr_code = expr_to_rust_with_name(&assign.expr, signal_indices, "$signals");
                        code.push_str(&format!("        $signals[{}] = {};\n", sig_idx, expr_code));
                    }
                }
            }
        }
    }
    code.push_str("    }};\n}\n\n");

    // Build clock domain info for multi-clock support
    // Group processes by their clock signal
    let mut clock_domains: HashMap<usize, Vec<(usize, &Process)>> = HashMap::new();
    let mut clock_indices_set: HashSet<usize> = HashSet::new();
    for (proc_idx, process) in ir.processes.iter().enumerate() {
        if process.clocked {
            let clk_idx = process.clock.as_ref()
                .and_then(|name| signal_indices.get(name))
                .cloned()
                .unwrap_or(0);
            clock_indices_set.insert(clk_idx);
            clock_domains.entry(clk_idx).or_default().push((proc_idx, process));
        }
    }
    let clock_indices_vec: Vec<usize> = clock_indices_set.iter().cloned().collect();
    let num_clocks = clock_indices_vec.len();

    // Generate inline tick-and-update logic as a macro with multi-clock support
    // This samples registers on rising edge and immediately updates them
    code.push_str("macro_rules! do_tick_update {\n");
    code.push_str("    ($signals:expr, $old_clocks:expr) => {{\n");

    // Check each clock domain for rising edge, sample and update immediately
    for (clock_array_idx, &clk_idx) in clock_indices_vec.iter().enumerate() {
        code.push_str(&format!("        // Clock domain: signal index {}\n", clk_idx));
        code.push_str(&format!("        let _old_clk_{} = $old_clocks[{}];\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("        let _new_clk_{} = $signals[{}];\n", clock_array_idx, clk_idx));
        code.push_str(&format!("        $old_clocks[{}] = _new_clk_{};\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("        if _old_clk_{} == 0 && _new_clk_{} != 0 {{\n", clock_array_idx, clock_array_idx));

        // Sample all registers in this clock domain, then immediately update
        if let Some(procs) = clock_domains.get(&clk_idx) {
            // Calculate register indices for processes in this domain
            let mut base_reg_idx = 0;
            for (proc_idx, proc) in ir.processes.iter().enumerate() {
                if proc.clocked {
                    // Check if this process is in current clock domain
                    if procs.iter().any(|(pi, _)| *pi == proc_idx) {
                        // First sample all registers to temps to avoid read-after-write issues
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            let expr_code = expr_to_rust_with_name(&stmt.expr, signal_indices, "$signals");
                            code.push_str(&format!("            let _next_{} = {};\n", base_reg_idx + stmt_idx, expr_code));
                        }
                        // Then update all registers
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            if let Some(&sig_idx) = signal_indices.get(&stmt.target) {
                                code.push_str(&format!("            $signals[{}] = _next_{};\n", sig_idx, base_reg_idx + stmt_idx));
                            }
                        }
                    }
                    base_reg_idx += proc.statements.len();
                }
            }
        }
        code.push_str("        }\n");
    }
    code.push_str("    }};\n}\n\n");

    // Legacy macros for compatibility (sample all, update all)
    code.push_str("macro_rules! do_tick {\n");
    code.push_str("    ($signals:expr, $next_regs:expr, $old_clocks:expr) => {{\n");
    for (clock_array_idx, &clk_idx) in clock_indices_vec.iter().enumerate() {
        code.push_str(&format!("        let _old_clk_{} = $old_clocks[{}];\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("        let _new_clk_{} = $signals[{}];\n", clock_array_idx, clk_idx));
        code.push_str(&format!("        $old_clocks[{}] = _new_clk_{};\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("        if _old_clk_{} == 0 && _new_clk_{} != 0 {{\n", clock_array_idx, clock_array_idx));
        if let Some(procs) = clock_domains.get(&clk_idx) {
            let mut base_reg_idx = 0;
            for (proc_idx, proc) in ir.processes.iter().enumerate() {
                if proc.clocked {
                    if procs.iter().any(|(pi, _)| *pi == proc_idx) {
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            let reg_idx = base_reg_idx + stmt_idx;
                            let expr_code = expr_to_rust_with_name(&stmt.expr, signal_indices, "$signals");
                            code.push_str(&format!("            $next_regs[{}] = {};\n", reg_idx, expr_code));
                        }
                    }
                    base_reg_idx += proc.statements.len();
                }
            }
        }
        code.push_str("        }\n");
    }
    code.push_str("    }};\n}\n\n");

    code.push_str("macro_rules! do_update_regs {\n");
    code.push_str("    ($signals:expr, $next_regs:expr, $old_clocks:expr, $prev_clocks:expr) => {{\n");
    for (clock_array_idx, &clk_idx) in clock_indices_vec.iter().enumerate() {
        code.push_str(&format!("        if $prev_clocks[{}] == 0 && $old_clocks[{}] != 0 {{\n", clock_array_idx, clock_array_idx));
        if let Some(procs) = clock_domains.get(&clk_idx) {
            let mut base_reg_idx = 0;
            for (proc_idx, proc) in ir.processes.iter().enumerate() {
                if proc.clocked {
                    if procs.iter().any(|(pi, _)| *pi == proc_idx) {
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            let reg_idx = base_reg_idx + stmt_idx;
                            if let Some(&sig_idx) = signal_indices.get(&stmt.target) {
                                code.push_str(&format!("            $signals[{}] = $next_regs[{}];\n", sig_idx, reg_idx));
                            }
                        }
                    }
                    base_reg_idx += proc.statements.len();
                }
            }
        }
        code.push_str("        }\n");
    }
    code.push_str("    }};\n}\n\n");

    // Generate evaluate function (for compatibility)
    code.push_str("#[no_mangle]\npub extern \"C\" fn evaluate(signals: &mut [u64]) {\n");
    code.push_str("    do_evaluate!(signals);\n");
    code.push_str("}\n\n");

    // Generate tick function with proper multi-clock domain support using static state
    code.push_str("use std::sync::Mutex;\n");
    code.push_str(&format!("static TICK_OLD_CLOCKS: Mutex<[u64; {}]> = Mutex::new([0u64; {}]);\n\n",
        num_clocks.max(1), num_clocks.max(1)));

    code.push_str("#[no_mangle]\npub extern \"C\" fn tick(signals: &mut [u64], next_regs: &mut [u64]) {\n");
    code.push_str("    let mut old_clocks = TICK_OLD_CLOCKS.lock().unwrap();\n");

    // Generate multi-clock domain tick logic with proper edge detection
    code.push_str("    // Detect rising edges and sample/update registers\n");
    for (clock_array_idx, &clk_idx) in clock_indices_vec.iter().enumerate() {
        code.push_str(&format!("    let _old_clk_{} = old_clocks[{}];\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("    let _new_clk_{} = signals[{}];\n", clock_array_idx, clk_idx));
        code.push_str(&format!("    old_clocks[{}] = _new_clk_{};\n", clock_array_idx, clock_array_idx));
        code.push_str(&format!("    if _old_clk_{} == 0 && _new_clk_{} != 0 {{\n", clock_array_idx, clock_array_idx));

        // Sample and update registers in this clock domain
        if let Some(procs) = clock_domains.get(&clk_idx) {
            let mut base_reg_idx = 0;
            for (proc_idx, proc) in ir.processes.iter().enumerate() {
                if proc.clocked {
                    if procs.iter().any(|(pi, _)| *pi == proc_idx) {
                        // Sample all registers first
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            let expr_code = expr_to_rust_with_name(&stmt.expr, signal_indices, "signals");
                            code.push_str(&format!("        next_regs[{}] = {};\n", base_reg_idx + stmt_idx, expr_code));
                        }
                    }
                    base_reg_idx += proc.statements.len();
                }
            }

            // Update all registers
            base_reg_idx = 0;
            for (proc_idx, proc) in ir.processes.iter().enumerate() {
                if proc.clocked {
                    if procs.iter().any(|(pi, _)| *pi == proc_idx) {
                        for (stmt_idx, stmt) in proc.statements.iter().enumerate() {
                            if let Some(&sig_idx) = signal_indices.get(&stmt.target) {
                                code.push_str(&format!("        signals[{}] = next_regs[{}];\n", sig_idx, base_reg_idx + stmt_idx));
                            }
                        }
                    }
                    base_reg_idx += proc.statements.len();
                }
            }
        }
        code.push_str("    }\n");
    }
    code.push_str("}\n\n");

    // Generate update_regs function (for compatibility - unconditional update)
    code.push_str("#[no_mangle]\npub extern \"C\" fn update_regs(signals: &mut [u64], next_regs: &[u64]) {\n");
    let mut reg_idx = 0;
    for process in &ir.processes {
        if process.clocked {
            for stmt in &process.statements {
                if let Some(&sig_idx) = signal_indices.get(&stmt.target) {
                    code.push_str(&format!("    signals[{}] = next_regs[{}];\n", sig_idx, reg_idx));
                }
                reg_idx += 1;
            }
        }
    }
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
    let cpu_addr_idx = signal_indices
        .get("cpu__addr_reg")
        .cloned()
        .unwrap_or(0);
    let reg_count = count_regs(ir);
    // Generate initialization for old_clocks based on current signal values
    let mut old_clocks_init = String::new();
    for (i, &clk_idx_val) in clock_indices_vec.iter().enumerate() {
        old_clocks_init.push_str(&format!("    old_clocks[{}] = signals[{}]; // clock signal {}\n", i, clk_idx_val, clk_idx_val));
    }
    if clock_indices_vec.is_empty() {
        old_clocks_init.push_str("    // No clocked processes\n");
    }
    let old_clocks_sync = old_clocks_init.clone();

    // Generate run_cpu_cycles with loop unrolling and optimized evaluate sequence
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
    let mut next_regs = [0u64; {reg_count}];
    let mut text_dirty = false;
    let mut key_cleared = false;
    let mut key_is_ready = key_ready;

    // Initialize tick's static old_clocks from current signal values
    {{
        let mut old_clocks = TICK_OLD_CLOCKS.lock().unwrap();
{old_clocks_init}
    }}
    // Pre-compute keyboard value (branchless)
    let key_val_base = (key_data as u64) | 0x80;

    // Macro for one 14MHz cycle with multi-clock domain support
    macro_rules! cycle_14m {{
        () => {{
            // Set keyboard state (branchless)
            *signals.get_unchecked_mut({k_idx}) = key_val_base * (key_is_ready as u64);

            // Falling edge - set clock low
            *signals.get_unchecked_mut({clk_idx}) = 0;
            do_evaluate!(signals);

            // Provide RAM/ROM data (unchecked access)
            // Use the CPU address register to avoid video-phase address contamination.
            let addr = *signals.get_unchecked({cpu_addr_idx}) as usize;
            let ram_len = ram.len();
            let rom_len = rom.len();
            *signals.get_unchecked_mut({ram_do_idx}) = if addr >= 0xD000 {{
                let rom_offset = addr.wrapping_sub(0xD000);
                if rom_offset < rom_len {{ *rom.get_unchecked(rom_offset) as u64 }} else {{ 0 }}
            }} else if addr >= 0xC000 {{
                0
            }} else if addr < ram_len {{
                *ram.get_unchecked(addr) as u64
            }} else {{
                0
            }};
            do_evaluate!(signals);

            // Sync old clock values to the current (low) state before rising edge
            {{
                let mut old_clocks = TICK_OLD_CLOCKS.lock().unwrap();
{old_clocks_sync}
            }}

            // Rising edge - set clock high
            *signals.get_unchecked_mut({clk_idx}) = 1;
            do_evaluate!(signals);
            tick(signals, &mut next_regs);

            // Handle RAM writes
            let ram_we = *signals.get_unchecked({ram_we_idx});
            if ram_we == 1 {{
                let write_addr = *signals.get_unchecked({ram_addr_idx}) as usize;
                if write_addr < 0xC000 {{
                    *ram.get_unchecked_mut(write_addr) = (*signals.get_unchecked({d_idx}) & 0xFF) as u8;
                    text_dirty |= (write_addr >= 0x0400) & (write_addr <= 0x07FF);
                }}
            }}

            // Check keyboard strobe clear (branchless)
            let strobe_clear = *signals.get_unchecked({read_key_idx}) == 1;
            key_is_ready &= !strobe_clear;
            key_cleared |= strobe_clear;
        }};
    }}

    for _ in 0..n {{
        unsafe {{
            // Partial unroll: 7 iterations of 2 cycles each
            for _ in 0..7 {{
                cycle_14m!(); cycle_14m!();
            }}
        }}
    }}

    (text_dirty, key_cleared)
}}
"#, k_idx = k_idx, clk_idx = clk_idx, ram_addr_idx = ram_addr_idx,
    ram_do_idx = ram_do_idx, ram_we_idx = ram_we_idx, d_idx = d_idx,
    read_key_idx = read_key_idx, cpu_addr_idx = cpu_addr_idx, reg_count = reg_count,
    old_clocks_init = old_clocks_init, old_clocks_sync = old_clocks_sync));

    code
}

/// Ruby wrapper using RefCell for interior mutability
#[magnus::wrap(class = "RHDL::Codegen::IR::IrCompiler")]
struct RubyRtlCompiler {
    sim: RefCell<SimulatorState>,
}

impl RubyRtlCompiler {
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
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let ir = codegen.define_module("IR")?;

    let class = ir.define_class("IrCompiler", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyRtlCompiler::new, 1))?;
    class.define_method("compile", method!(RubyRtlCompiler::compile, 0))?;
    class.define_method("compiled?", method!(RubyRtlCompiler::is_compiled, 0))?;
    class.define_method("generated_code", method!(RubyRtlCompiler::generated_code, 0))?;
    class.define_method("signal_count", method!(RubyRtlCompiler::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyRtlCompiler::reg_count, 0))?;
    class.define_method("poke", method!(RubyRtlCompiler::poke, 2))?;
    class.define_method("peek", method!(RubyRtlCompiler::peek, 1))?;
    class.define_method("evaluate", method!(RubyRtlCompiler::evaluate, 0))?;
    class.define_method("tick", method!(RubyRtlCompiler::tick, 0))?;
    class.define_method("reset", method!(RubyRtlCompiler::reset, 0))?;
    class.define_method("load_rom", method!(RubyRtlCompiler::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyRtlCompiler::load_ram, 2))?;
    class.define_method("read_ram", method!(RubyRtlCompiler::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyRtlCompiler::write_ram, 2))?;
    class.define_method("run_cpu_cycles", method!(RubyRtlCompiler::run_cpu_cycles, 3))?;
    class.define_method("input_names", method!(RubyRtlCompiler::input_names, 0))?;
    class.define_method("output_names", method!(RubyRtlCompiler::output_names, 0))?;
    class.define_method("stats", method!(RubyRtlCompiler::stats, 0))?;
    class.define_method("native?", method!(RubyRtlCompiler::native, 0))?;

    Ok(())
}
