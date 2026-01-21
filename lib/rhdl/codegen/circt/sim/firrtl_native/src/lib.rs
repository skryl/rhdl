//! High-performance RTL simulator for FIRRTL/Behavior IR with Ruby bindings
//!
//! Optimizations:
//! - Bytecode compilation for expressions (no recursion, minimal branching)
//! - Vec<u64> indexing instead of HashMap<String, u64> for O(1) signal access
//! - Batched cycle execution to minimize Ruby-Rust FFI overhead
//! - Internalized RAM/ROM for zero-copy memory access
//! - Unsafe unchecked array access in hot loops

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;

/// Port direction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Direction {
    In,
    Out,
}

/// Port definition
#[derive(Debug, Clone, Deserialize)]
struct PortDef {
    name: String,
    direction: Direction,
    width: usize,
}

/// Wire/net definition
#[derive(Debug, Clone, Deserialize)]
struct NetDef {
    name: String,
    width: usize,
}

/// Register definition
#[derive(Debug, Clone, Deserialize)]
struct RegDef {
    name: String,
    width: usize,
}

/// Expression types (JSON deserialization)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ExprDef {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
    UnaryOp { op: String, operand: Box<ExprDef>, width: usize },
    BinaryOp { op: String, left: Box<ExprDef>, right: Box<ExprDef>, width: usize },
    Mux { condition: Box<ExprDef>, when_true: Box<ExprDef>, when_false: Box<ExprDef>, width: usize },
    #[allow(dead_code)]
    Slice { base: Box<ExprDef>, low: usize, high: usize, width: usize },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
}

/// Assignment (combinational)
#[derive(Debug, Clone, Deserialize)]
struct AssignDef {
    target: String,
    expr: ExprDef,
}

/// Sequential assignment
#[derive(Debug, Clone, Deserialize)]
struct SeqAssignDef {
    target: String,
    expr: ExprDef,
}

/// Process (sequential block)
#[derive(Debug, Clone, Deserialize)]
struct ProcessDef {
    #[allow(dead_code)]
    name: String,
    #[allow(dead_code)]
    clock: Option<String>,
    clocked: bool,
    statements: Vec<SeqAssignDef>,
}

/// Memory definition
#[allow(dead_code)]
#[derive(Debug, Clone, Deserialize)]
struct MemoryDef {
    name: String,
    depth: usize,
    width: usize,
}

/// Complete module IR
#[derive(Debug, Clone, Deserialize)]
struct ModuleIR {
    #[allow(dead_code)]
    name: String,
    ports: Vec<PortDef>,
    nets: Vec<NetDef>,
    regs: Vec<RegDef>,
    assigns: Vec<AssignDef>,
    processes: Vec<ProcessDef>,
    #[allow(dead_code)]
    #[serde(default)]
    memories: Vec<MemoryDef>,
}

// ============================================================================
// Bytecode-based expression evaluator for maximum performance
// ============================================================================

/// Bytecode instructions for expression evaluation
#[derive(Debug, Clone, Copy)]
enum Opcode {
    // Load operations
    LoadSignal(usize, u64),      // (signal_idx, mask)
    LoadLiteral(u64),            // value

    // Unary operations
    Not(u64),                    // mask
    ReduceAnd(u64),              // operand_mask
    ReduceOr,
    ReduceXor,

    // Binary operations
    And,
    Or,
    Xor,
    Add(u64),                    // mask
    Sub(u64),                    // mask
    Mul(u64),                    // mask
    Div,
    Mod,
    Shl(u64),                    // mask
    Shr,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,

    // Mux - pops condition, true_val, false_val
    Mux(u64),                    // mask

    // Slice - pops value, shifts and masks
    Slice(u32, u64),             // (shift, mask)

    // Concat - pops N values and combines them
    ConcatStart,
    ConcatPart(usize),           // width
    ConcatEnd(u64),              // final mask

    // Resize
    Resize(u64),                 // mask
}

/// Compiled bytecode program for an expression
#[derive(Debug, Clone)]
struct BytecodeProgram {
    ops: Vec<Opcode>,
}

/// Compiled assignment using bytecode
#[derive(Debug, Clone)]
struct CompiledAssign {
    target_idx: usize,
    program: BytecodeProgram,
    mask: u64,
}

// ============================================================================
// High-performance RTL simulator
// ============================================================================

struct RtlSimulator {
    /// Signal values (Vec for O(1) access)
    signals: Vec<u64>,
    /// Signal widths
    widths: Vec<usize>,
    /// Signal name to index mapping (for external access)
    name_to_idx: HashMap<String, usize>,
    /// Input names (for Ruby API)
    input_names: Vec<String>,
    /// Output names (for Ruby API)
    output_names: Vec<String>,
    /// Compiled combinational assignments
    assigns: Vec<CompiledAssign>,
    /// Compiled sequential assignments
    seq_assigns: Vec<CompiledAssign>,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Evaluation stack (pre-allocated)
    eval_stack: Vec<u64>,
    /// Next register values buffer
    next_regs: Vec<u64>,
    /// Sequential assignment target indices
    seq_targets: Vec<usize>,

    // Apple II specific: internalized memory for batched execution
    /// RAM (48KB)
    ram: Vec<u8>,
    /// ROM (12KB)
    rom: Vec<u8>,
    /// RAM address signal index
    ram_addr_idx: usize,
    /// RAM data out signal index (input to CPU)
    ram_do_idx: usize,
    /// RAM write enable signal index
    ram_we_idx: usize,
    /// Data bus signal index (for writes)
    d_idx: usize,
    /// Clock signal index
    clk_idx: usize,
    /// Keyboard input index
    k_idx: usize,
    /// Read key strobe index
    read_key_idx: usize,
}

impl RtlSimulator {
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
                Direction::In => {
                    input_names.push(port.name.clone());
                }
                Direction::Out => {
                    output_names.push(port.name.clone());
                }
            }
        }

        // Wires
        for net in &ir.nets {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(net.width);
            name_to_idx.insert(net.name.clone(), idx);
        }

        // Registers
        let reg_count = ir.regs.len();
        for reg in &ir.regs {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(reg.width);
            name_to_idx.insert(reg.name.clone(), idx);
        }

        let signal_count = signals.len();

        // Compile combinational assignments to bytecode
        let assigns: Vec<CompiledAssign> = ir.assigns.iter().map(|a| {
            let target_idx = *name_to_idx.get(&a.target).unwrap_or(&0);
            let width = widths.get(target_idx).copied().unwrap_or(64);
            let mask = Self::compute_mask(width);
            let program = Self::compile_to_bytecode(&a.expr, &name_to_idx, &widths);
            CompiledAssign { target_idx, program, mask }
        }).collect();

        // Compile sequential assignments to bytecode
        let mut seq_assigns = Vec::new();
        let mut seq_targets = Vec::new();
        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                let width = widths.get(target_idx).copied().unwrap_or(64);
                let mask = Self::compute_mask(width);
                let program = Self::compile_to_bytecode(&stmt.expr, &name_to_idx, &widths);
                seq_assigns.push(CompiledAssign { target_idx, program, mask });
                seq_targets.push(target_idx);
            }
        }

        // Pre-allocate buffers
        let eval_stack = Vec::with_capacity(64);
        let next_regs = vec![0u64; seq_targets.len()];

        // Get Apple II specific signal indices
        let ram_addr_idx = *name_to_idx.get("ram_addr").unwrap_or(&0);
        let ram_do_idx = *name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *name_to_idx.get("read_key").unwrap_or(&0);

        Ok(Self {
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            assigns,
            seq_assigns,
            signal_count,
            reg_count,
            eval_stack,
            next_regs,
            seq_targets,
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx,
            ram_do_idx,
            ram_we_idx,
            d_idx,
            clk_idx,
            k_idx,
            read_key_idx,
        })
    }

    #[inline(always)]
    fn compute_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    /// Compile expression to bytecode
    fn compile_to_bytecode(expr: &ExprDef, name_to_idx: &HashMap<String, usize>, widths: &[usize]) -> BytecodeProgram {
        let mut ops = Vec::new();
        Self::compile_expr_to_ops(expr, name_to_idx, widths, &mut ops);
        BytecodeProgram { ops }
    }

    fn compile_expr_to_ops(expr: &ExprDef, name_to_idx: &HashMap<String, usize>, widths: &[usize], ops: &mut Vec<Opcode>) {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = *name_to_idx.get(name).unwrap_or(&0);
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::LoadSignal(idx, mask));
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::LoadLiteral((*value as u64) & mask));
            }
            ExprDef::UnaryOp { op, operand, width } => {
                Self::compile_expr_to_ops(operand, name_to_idx, widths, ops);
                let mask = Self::compute_mask(*width);
                let op_width = Self::expr_width(operand, widths, name_to_idx);
                let op_mask = Self::compute_mask(op_width);
                match op.as_str() {
                    "~" | "not" => ops.push(Opcode::Not(mask)),
                    "&" | "reduce_and" => ops.push(Opcode::ReduceAnd(op_mask)),
                    "|" | "reduce_or" => ops.push(Opcode::ReduceOr),
                    "^" | "reduce_xor" => ops.push(Opcode::ReduceXor),
                    _ => ops.push(Opcode::Not(mask)),
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                // Evaluate left, then right, then apply op
                Self::compile_expr_to_ops(left, name_to_idx, widths, ops);
                Self::compile_expr_to_ops(right, name_to_idx, widths, ops);
                let mask = Self::compute_mask(*width);
                match op.as_str() {
                    "&" => ops.push(Opcode::And),
                    "|" => ops.push(Opcode::Or),
                    "^" => ops.push(Opcode::Xor),
                    "+" => ops.push(Opcode::Add(mask)),
                    "-" => ops.push(Opcode::Sub(mask)),
                    "*" => ops.push(Opcode::Mul(mask)),
                    "/" => ops.push(Opcode::Div),
                    "%" => ops.push(Opcode::Mod),
                    "<<" => ops.push(Opcode::Shl(mask)),
                    ">>" => ops.push(Opcode::Shr),
                    "==" => ops.push(Opcode::Eq),
                    "!=" => ops.push(Opcode::Ne),
                    "<" => ops.push(Opcode::Lt),
                    ">" => ops.push(Opcode::Gt),
                    "<=" | "le" => ops.push(Opcode::Le),
                    ">=" => ops.push(Opcode::Ge),
                    _ => ops.push(Opcode::And),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                // Evaluate: condition, when_false, when_true (reverse order for stack)
                Self::compile_expr_to_ops(condition, name_to_idx, widths, ops);
                Self::compile_expr_to_ops(when_false, name_to_idx, widths, ops);
                Self::compile_expr_to_ops(when_true, name_to_idx, widths, ops);
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::Mux(mask));
            }
            ExprDef::Slice { base, low, width, .. } => {
                Self::compile_expr_to_ops(base, name_to_idx, widths, ops);
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::Slice(*low as u32, mask));
            }
            ExprDef::Concat { parts, width } => {
                ops.push(Opcode::ConcatStart);
                for part in parts {
                    Self::compile_expr_to_ops(part, name_to_idx, widths, ops);
                    let part_width = Self::expr_width(part, widths, name_to_idx);
                    ops.push(Opcode::ConcatPart(part_width));
                }
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::ConcatEnd(mask));
            }
            ExprDef::Resize { expr, width } => {
                Self::compile_expr_to_ops(expr, name_to_idx, widths, ops);
                let mask = Self::compute_mask(*width);
                ops.push(Opcode::Resize(mask));
            }
        }
    }

    fn expr_width(expr: &ExprDef, widths: &[usize], name_to_idx: &HashMap<String, usize>) -> usize {
        match expr {
            ExprDef::Signal { name, width } => {
                name_to_idx.get(name).and_then(|&idx| widths.get(idx).copied()).unwrap_or(*width)
            }
            ExprDef::Literal { width, .. } => *width,
            ExprDef::UnaryOp { width, .. } => *width,
            ExprDef::BinaryOp { width, .. } => *width,
            ExprDef::Mux { width, .. } => *width,
            ExprDef::Slice { width, .. } => *width,
            ExprDef::Concat { width, .. } => *width,
            ExprDef::Resize { width, .. } => *width,
        }
    }

    /// Execute bytecode program and return result (static version for borrow checker)
    #[inline(always)]
    fn execute_bytecode_static(signals: &[u64], program: &BytecodeProgram, stack: &mut Vec<u64>) -> u64 {
        stack.clear();
        let mut concat_result = 0u64;
        let mut concat_shift = 0usize;

        for op in &program.ops {
            match *op {
                Opcode::LoadSignal(idx, mask) => {
                    let val = unsafe { *signals.get_unchecked(idx) } & mask;
                    stack.push(val);
                }
                Opcode::LoadLiteral(val) => {
                    stack.push(val);
                }
                Opcode::Not(mask) => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push((!val) & mask);
                }
                Opcode::ReduceAnd(op_mask) => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push(if (val & op_mask) == op_mask { 1 } else { 0 });
                }
                Opcode::ReduceOr => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push(if val != 0 { 1 } else { 0 });
                }
                Opcode::ReduceXor => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push((val.count_ones() & 1) as u64);
                }
                Opcode::And => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l & r);
                }
                Opcode::Or => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l | r);
                }
                Opcode::Xor => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l ^ r);
                }
                Opcode::Add(mask) => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l.wrapping_add(r) & mask);
                }
                Opcode::Sub(mask) => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l.wrapping_sub(r) & mask);
                }
                Opcode::Mul(mask) => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l.wrapping_mul(r) & mask);
                }
                Opcode::Div => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if r != 0 { l / r } else { 0 });
                }
                Opcode::Mod => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if r != 0 { l % r } else { 0 });
                }
                Opcode::Shl(mask) => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push((l << (r as u32).min(63)) & mask);
                }
                Opcode::Shr => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(l >> (r as u32).min(63));
                }
                Opcode::Eq => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l == r { 1 } else { 0 });
                }
                Opcode::Ne => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l != r { 1 } else { 0 });
                }
                Opcode::Lt => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l < r { 1 } else { 0 });
                }
                Opcode::Gt => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l > r { 1 } else { 0 });
                }
                Opcode::Le => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l <= r { 1 } else { 0 });
                }
                Opcode::Ge => {
                    let r = stack.pop().unwrap_or(0);
                    let l = stack.pop().unwrap_or(0);
                    stack.push(if l >= r { 1 } else { 0 });
                }
                Opcode::Mux(mask) => {
                    let when_true = stack.pop().unwrap_or(0);
                    let when_false = stack.pop().unwrap_or(0);
                    let cond = stack.pop().unwrap_or(0);
                    let result = if cond != 0 { when_true } else { when_false };
                    stack.push(result & mask);
                }
                Opcode::Slice(shift, mask) => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push((val >> shift) & mask);
                }
                Opcode::ConcatStart => {
                    concat_result = 0;
                    concat_shift = 0;
                }
                Opcode::ConcatPart(width) => {
                    let val = stack.pop().unwrap_or(0);
                    concat_result |= (val & Self::compute_mask(width)) << concat_shift;
                    concat_shift += width;
                }
                Opcode::ConcatEnd(mask) => {
                    stack.push(concat_result & mask);
                }
                Opcode::Resize(mask) => {
                    let val = stack.pop().unwrap_or(0);
                    stack.push(val & mask);
                }
            }
        }

        stack.pop().unwrap_or(0)
    }

    fn poke_by_name(&mut self, name: &str, value: u64) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let mask = Self::compute_mask(self.widths[idx]);
        self.signals[idx] = value & mask;
        Ok(())
    }

    fn peek_by_name(&self, name: &str) -> Result<u64, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        Ok(self.signals[idx])
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        // Single pass - assignments should be topologically sorted
        let mut stack = std::mem::take(&mut self.eval_stack);
        for i in 0..self.assigns.len() {
            let assign = &self.assigns[i];
            let target_idx = assign.target_idx;
            let mask = assign.mask;
            let new_val = Self::execute_bytecode_static(&self.signals, &assign.program, &mut stack) & mask;
            unsafe { *self.signals.get_unchecked_mut(target_idx) = new_val; }
        }
        self.eval_stack = stack;
    }

    #[inline(always)]
    fn tick(&mut self) {
        // Evaluate combinational logic
        self.evaluate();

        // Sample all register inputs into pre-allocated buffer
        let mut stack = std::mem::take(&mut self.eval_stack);
        for i in 0..self.seq_assigns.len() {
            let assign = &self.seq_assigns[i];
            let new_val = Self::execute_bytecode_static(&self.signals, &assign.program, &mut stack) & assign.mask;
            self.next_regs[i] = new_val;
        }
        self.eval_stack = stack;

        // Update all registers
        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
            unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[i]; }
        }

        // Re-evaluate combinational logic
        self.evaluate();
    }

    /// Load ROM data
    fn load_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.rom.len());
        self.rom[..len].copy_from_slice(&data[..len]);
    }

    /// Load RAM data at offset
    fn load_ram(&mut self, data: &[u8], offset: usize) {
        let end = (offset + data.len()).min(self.ram.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.ram[offset..end].copy_from_slice(&data[..len]);
        }
    }

    /// Run a single 14MHz cycle with integrated memory handling (optimized)
    #[inline(always)]
    fn run_14m_cycle_internal(&mut self, key_data: u8, key_ready: bool) -> (bool, bool) {
        // Set keyboard input
        let k_val = if key_ready { (key_data as u64) | 0x80 } else { 0 };
        unsafe { *self.signals.get_unchecked_mut(self.k_idx) = k_val; }

        // Falling edge - set clock and provide memory data in one go
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 0; }

        // Evaluate once to get current ram_addr
        self.evaluate();

        // Provide RAM/ROM data based on address
        let ram_addr = unsafe { *self.signals.get_unchecked(self.ram_addr_idx) } as usize;
        let ram_data = if ram_addr >= 0xD000 && ram_addr <= 0xFFFF {
            let rom_offset = ram_addr - 0xD000;
            unsafe { *self.rom.get_unchecked(rom_offset.min(self.rom.len() - 1)) }
        } else {
            unsafe { *self.ram.get_unchecked(ram_addr.min(self.ram.len() - 1)) }
        };
        unsafe { *self.signals.get_unchecked_mut(self.ram_do_idx) = ram_data as u64; }

        // Rising edge - clock transition triggers register update
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 1; }
        self.tick_fast();

        // Handle RAM writes
        let mut text_dirty = false;
        let ram_we = unsafe { *self.signals.get_unchecked(self.ram_we_idx) };
        if ram_we == 1 {
            let write_addr = unsafe { *self.signals.get_unchecked(self.ram_addr_idx) } as usize;
            if write_addr < self.ram.len() {
                let data = unsafe { (*self.signals.get_unchecked(self.d_idx) & 0xFF) as u8 };
                unsafe { *self.ram.get_unchecked_mut(write_addr) = data; }
                if write_addr >= 0x0400 && write_addr <= 0x07FF {
                    text_dirty = true;
                }
            }
        }

        // Check keyboard strobe
        let key_cleared = unsafe { *self.signals.get_unchecked(self.read_key_idx) } == 1;

        (text_dirty, key_cleared)
    }

    /// Optimized tick - only evaluate once after register update
    #[inline(always)]
    fn tick_fast(&mut self) {
        // Evaluate to sample register inputs
        self.evaluate();

        // Sample all register inputs into pre-allocated buffer
        let mut stack = std::mem::take(&mut self.eval_stack);
        for i in 0..self.seq_assigns.len() {
            let assign = &self.seq_assigns[i];
            let new_val = Self::execute_bytecode_static(&self.signals, &assign.program, &mut stack) & assign.mask;
            self.next_regs[i] = new_val;
        }
        self.eval_stack = stack;

        // Update all registers
        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
            unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[i]; }
        }

        // Final evaluate with new register values
        self.evaluate();
    }

    /// Run N CPU cycles (each = 14 x 14MHz cycles) - main batched execution entry point
    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> BatchResult {
        let mut result = BatchResult {
            text_dirty: false,
            key_cleared: false,
            cycles_run: n,
        };

        let mut current_key_ready = key_ready;

        for _ in 0..n {
            for _ in 0..14 {
                let (text_dirty, key_cleared) = self.run_14m_cycle_internal(key_data, current_key_ready);
                if text_dirty {
                    result.text_dirty = true;
                }
                if key_cleared {
                    current_key_ready = false;
                    result.key_cleared = true;
                }
            }
        }

        result
    }

    fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        // Don't clear RAM/ROM on reset
    }

    fn signal_count(&self) -> usize {
        self.signal_count
    }

    fn reg_count(&self) -> usize {
        self.reg_count
    }
}

/// Result of batched cycle execution
struct BatchResult {
    text_dirty: bool,
    key_cleared: bool,
    cycles_run: usize,
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

#[magnus::wrap(class = "RHDL::Codegen::CIRCT::FirrtlNative")]
struct RubyRtlSim {
    sim: RefCell<RtlSimulator>,
}

impl RubyRtlSim {
    fn new(json: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = RtlSimulator::new(&json)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self {
            sim: RefCell::new(sim),
        })
    }

    fn poke(&self, name: String, value: Value) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let v = ruby_to_u64(value)?;
        self.sim.borrow_mut().poke_by_name(&name, v)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn peek(&self, name: String) -> Result<Value, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let val = self.sim.borrow().peek_by_name(&name)
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

    /// Load ROM data (bytes as array of integers)
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

    /// Load RAM data at offset
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

    /// Run N CPU cycles with batched execution (key optimization!)
    fn run_cpu_cycles(&self, n: usize, key_data: i64, key_ready: bool) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let result = self.sim.borrow_mut().run_cpu_cycles(n, key_data as u8, key_ready);

        let hash = ruby.hash_new();
        hash.aset(ruby.sym_new("text_dirty"), result.text_dirty)?;
        hash.aset(ruby.sym_new("key_cleared"), result.key_cleared)?;
        hash.aset(ruby.sym_new("cycles_run"), result.cycles_run as i64)?;
        Ok(hash)
    }

    /// Read RAM range (for screen reading)
    fn read_ram(&self, start: usize, length: usize) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let end = (start + length).min(sim.ram.len());
        let data: Vec<i64> = sim.ram[start..end].iter().map(|&b| b as i64).collect();
        Ok(ruby.ary_from_vec(data))
    }

    /// Write RAM (for initial loading)
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
        hash.aset(ruby.sym_new("assign_count"), sim.assigns.len() as i64)?;
        hash.aset(ruby.sym_new("seq_assign_count"), sim.seq_assigns.len() as i64)?;

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
    let circt = codegen.define_module("CIRCT")?;

    let class = circt.define_class("FirrtlNative", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyRtlSim::new, 1))?;
    class.define_method("poke", method!(RubyRtlSim::poke, 2))?;
    class.define_method("peek", method!(RubyRtlSim::peek, 1))?;
    class.define_method("evaluate", method!(RubyRtlSim::evaluate, 0))?;
    class.define_method("tick", method!(RubyRtlSim::tick, 0))?;
    class.define_method("reset", method!(RubyRtlSim::reset, 0))?;
    class.define_method("signal_count", method!(RubyRtlSim::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyRtlSim::reg_count, 0))?;
    class.define_method("input_names", method!(RubyRtlSim::input_names, 0))?;
    class.define_method("output_names", method!(RubyRtlSim::output_names, 0))?;
    class.define_method("load_rom", method!(RubyRtlSim::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyRtlSim::load_ram, 2))?;
    class.define_method("run_cpu_cycles", method!(RubyRtlSim::run_cpu_cycles, 3))?;
    class.define_method("read_ram", method!(RubyRtlSim::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyRtlSim::write_ram, 2))?;
    class.define_method("stats", method!(RubyRtlSim::stats, 0))?;
    class.define_method("native?", method!(RubyRtlSim::native, 0))?;

    circt.const_set("FIRRTL_NATIVE_AVAILABLE", true)?;

    Ok(())
}
