//! High-performance RTL simulator for FIRRTL/Behavior IR with Ruby bindings
//!
//! Optimizations:
//! - Flat operation model with pre-resolved indices (no string lookups at runtime)
//! - Vec<u64> indexing for O(1) signal access
//! - Batched cycle execution to minimize Ruby-Rust FFI overhead
//! - Internalized RAM/ROM for zero-copy memory access
//! - Unsafe unchecked array access in hot loops
//! - Contiguous operation storage for cache efficiency

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
// Flat Operation Model - Direct Indexing, No Dispatch
// ============================================================================
//
// Key insight: The circuit topology is static. At load time, we compile each
// expression into a flat sequence of primitive operations. Each operation is
// represented as a struct with:
//   - op_type: u8 encoding the operation kind
//   - args: pre-computed indices and constants
//
// At runtime, we iterate through operations and use a single match statement
// that the compiler optimizes to a jump table. The indices are pre-resolved,
// so no string lookups or hash maps are needed.
//
// This approach minimizes:
//   1. Memory allocations (no Box, no trait objects)
//   2. Indirect calls (no vtables)
//   3. Cache misses (operations stored contiguously)

/// Operand source - either a signal index or an immediate value
#[derive(Debug, Clone, Copy)]
enum Operand {
    Signal(usize),      // Index into signals array
    Immediate(u64),     // Literal value
    Temp(usize),        // Index into temp array
}

/// Flattened operation with all arguments pre-resolved
/// Stored contiguously for cache-friendly access
#[derive(Clone, Copy)]
struct FlatOp {
    /// Operation type (0-31, fits in one byte for compact storage)
    op_type: u8,
    /// Destination (temp index for intermediate, signal index for final)
    dst: usize,
    /// Pre-resolved argument values (meaning depends on op_type)
    arg0: u64,  // First operand: signal idx, immediate val, or temp idx (encoded with type tag)
    arg1: u64,  // Second operand (for binary ops, mux)
    arg2: u64,  // Third operand (for mux), mask, or shift amount
}

// Operation type constants
const OP_COPY_SIG: u8 = 0;   // dst = signals[arg0] & arg2
const OP_COPY_IMM: u8 = 1;   // dst = arg0 & arg2
const OP_COPY_TMP: u8 = 2;   // dst = temps[arg0] & arg2
const OP_NOT: u8 = 3;
const OP_REDUCE_AND: u8 = 4;
const OP_REDUCE_OR: u8 = 5;
const OP_REDUCE_XOR: u8 = 6;
const OP_AND: u8 = 7;
const OP_OR: u8 = 8;
const OP_XOR: u8 = 9;
const OP_ADD: u8 = 10;
const OP_SUB: u8 = 11;
const OP_MUL: u8 = 12;
const OP_DIV: u8 = 13;
const OP_MOD: u8 = 14;
const OP_SHL: u8 = 15;
const OP_SHR: u8 = 16;
const OP_EQ: u8 = 17;
const OP_NE: u8 = 18;
const OP_LT: u8 = 19;
const OP_GT: u8 = 20;
const OP_LE: u8 = 21;
const OP_GE: u8 = 22;
const OP_MUX: u8 = 23;
const OP_SLICE: u8 = 24;
const OP_CONCAT_INIT: u8 = 25;
const OP_CONCAT_ACCUM: u8 = 26;
const OP_CONCAT_FINISH: u8 = 27;
const OP_RESIZE: u8 = 28;
const OP_COPY_TO_SIG: u8 = 29; // signals[dst] = get_operand(arg0) & arg2

// Operand type tags (stored in high bits of arg values)
const TAG_SIGNAL: u64 = 0;
const TAG_IMMEDIATE: u64 = 1 << 62;
const TAG_TEMP: u64 = 2 << 62;
const TAG_MASK: u64 = 3 << 62;
const VAL_MASK: u64 = !(3u64 << 62);

impl FlatOp {
    #[inline(always)]
    fn encode_operand(op: Operand) -> u64 {
        match op {
            Operand::Signal(idx) => TAG_SIGNAL | (idx as u64),
            Operand::Immediate(val) => TAG_IMMEDIATE | (val & VAL_MASK),
            Operand::Temp(idx) => TAG_TEMP | (idx as u64),
        }
    }

    #[inline(always)]
    fn get_operand(signals: &[u64], temps: &[u64], encoded: u64) -> u64 {
        let tag = encoded & TAG_MASK;
        let val = encoded & VAL_MASK;
        if tag == TAG_SIGNAL {
            unsafe { *signals.get_unchecked(val as usize) }
        } else if tag == TAG_IMMEDIATE {
            val
        } else {
            unsafe { *temps.get_unchecked(val as usize) }
        }
    }
}

/// Compiled assignment - sequence of flat ops ending with final target write
struct CompiledAssign {
    /// Flat operations to execute (cache-friendly, contiguous storage)
    ops: Vec<FlatOp>,
    /// Final target signal index (for sequential assignment sampling)
    final_target: usize,
}

// ============================================================================
// High-performance RTL simulator
// ============================================================================

struct RtlSimulator {
    /// Signal values (Vec for O(1) access)
    signals: Vec<u64>,
    /// Temp values for intermediate computations
    temps: Vec<u64>,
    /// Signal widths
    widths: Vec<usize>,
    /// Signal name to index mapping (for external access)
    name_to_idx: HashMap<String, usize>,
    /// Input names (for Ruby API)
    input_names: Vec<String>,
    /// Output names (for Ruby API)
    output_names: Vec<String>,
    /// Compiled sequential assignments (needed for register sampling)
    seq_assigns: Vec<CompiledAssign>,
    /// All combinational ops flattened into one contiguous array
    all_comb_ops: Vec<FlatOp>,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
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

        // Compile combinational assignments to flat ops
        let mut max_temps = 0usize;
        let mut all_comb_ops: Vec<FlatOp> = Vec::new();

        for assign in &ir.assigns {
            let target_idx = *name_to_idx.get(&assign.target).unwrap_or(&0);
            let (ops, temps_used) = Self::compile_to_flat_ops(&assign.expr, target_idx, &name_to_idx, &widths);
            max_temps = max_temps.max(temps_used);
            all_comb_ops.extend(ops);
        }

        // Compile sequential assignments (kept separate for register sampling)
        let mut seq_assigns = Vec::new();
        let mut seq_targets = Vec::new();
        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                let (ops, temps_used) = Self::compile_to_flat_ops(&stmt.expr, target_idx, &name_to_idx, &widths);
                max_temps = max_temps.max(temps_used);
                seq_assigns.push(CompiledAssign { ops, final_target: target_idx });
                seq_targets.push(target_idx);
            }
        }

        // Pre-allocate temp buffer
        let temps = vec![0u64; max_temps + 1];
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
            temps,
            widths,
            name_to_idx,
            input_names,
            output_names,
            seq_assigns,
            all_comb_ops,
            signal_count,
            reg_count,
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

    /// Compile expression to flat ops
    /// Returns (ops, max_temp_used)
    fn compile_to_flat_ops(
        expr: &ExprDef,
        final_target: usize,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> (Vec<FlatOp>, usize) {
        let mut ops: Vec<FlatOp> = Vec::new();
        let mut temp_counter = 0usize;

        let result = Self::compile_expr_to_flat(expr, name_to_idx, widths, &mut ops, &mut temp_counter);

        // Final copy to target signal if needed
        let width = widths.get(final_target).copied().unwrap_or(64);
        let mask = Self::compute_mask(width);
        match result {
            Operand::Signal(idx) if idx == final_target => {
                // Already in place
            }
            _ => {
                ops.push(FlatOp {
                    op_type: OP_COPY_TO_SIG,
                    dst: final_target,
                    arg0: FlatOp::encode_operand(result),
                    arg1: 0,
                    arg2: mask,
                });
            }
        }

        (ops, temp_counter)
    }

    /// Recursively compile expression to flat ops, returning operand for the result
    fn compile_expr_to_flat(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize],
        ops: &mut Vec<FlatOp>,
        temp_counter: &mut usize,
    ) -> Operand {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = *name_to_idx.get(name).unwrap_or(&0);
                Operand::Signal(idx)
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compute_mask(*width);
                Operand::Immediate((*value as u64) & mask)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = Self::compile_expr_to_flat(operand, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                let op_width = Self::expr_width(operand, widths, name_to_idx);
                let op_mask = Self::compute_mask(op_width);

                let op_type = match op.as_str() {
                    "~" | "not" => OP_NOT,
                    "&" | "reduce_and" => OP_REDUCE_AND,
                    "|" | "reduce_or" => OP_REDUCE_OR,
                    "^" | "reduce_xor" => OP_REDUCE_XOR,
                    _ => OP_COPY_TMP,
                };

                ops.push(FlatOp {
                    op_type,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: op_mask,  // For reduce_and
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = Self::compile_expr_to_flat(left, name_to_idx, widths, ops, temp_counter);
                let r = Self::compile_expr_to_flat(right, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                let op_type = match op.as_str() {
                    "&" => OP_AND,
                    "|" => OP_OR,
                    "^" => OP_XOR,
                    "+" => OP_ADD,
                    "-" => OP_SUB,
                    "*" => OP_MUL,
                    "/" => OP_DIV,
                    "%" => OP_MOD,
                    "<<" => OP_SHL,
                    ">>" => OP_SHR,
                    "==" => OP_EQ,
                    "!=" => OP_NE,
                    "<" => OP_LT,
                    ">" => OP_GT,
                    "<=" | "le" => OP_LE,
                    ">=" => OP_GE,
                    _ => OP_AND,
                };

                ops.push(FlatOp {
                    op_type,
                    dst,
                    arg0: FlatOp::encode_operand(l),
                    arg1: FlatOp::encode_operand(r),
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                let cond = Self::compile_expr_to_flat(condition, name_to_idx, widths, ops, temp_counter);
                let t = Self::compile_expr_to_flat(when_true, name_to_idx, widths, ops, temp_counter);
                let f = Self::compile_expr_to_flat(when_false, name_to_idx, widths, ops, temp_counter);
                let dst = *temp_counter;
                *temp_counter += 1;

                // Mux uses all 3 arg slots: cond, true_val, false_val
                ops.push(FlatOp {
                    op_type: OP_MUX,
                    dst,
                    arg0: FlatOp::encode_operand(cond),
                    arg1: FlatOp::encode_operand(t),
                    arg2: FlatOp::encode_operand(f),
                });
                Operand::Temp(dst)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = Self::compile_expr_to_flat(base, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_SLICE,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: *low as u64,  // shift amount
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Concat { parts, width } => {
                let dst = *temp_counter;
                *temp_counter += 1;

                // Initialize temp to 0
                ops.push(FlatOp {
                    op_type: OP_CONCAT_INIT,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: 0,
                });

                let mut shift_acc = 0u64;
                for part in parts {
                    let src = Self::compile_expr_to_flat(part, name_to_idx, widths, ops, temp_counter);
                    let part_width = Self::expr_width(part, widths, name_to_idx);
                    let part_mask = Self::compute_mask(part_width);

                    ops.push(FlatOp {
                        op_type: OP_CONCAT_ACCUM,
                        dst,
                        arg0: FlatOp::encode_operand(src),
                        arg1: shift_acc,
                        arg2: part_mask,
                    });
                    shift_acc += part_width as u64;
                }

                let final_mask = Self::compute_mask(*width);
                ops.push(FlatOp {
                    op_type: OP_CONCAT_FINISH,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: final_mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Resize { expr, width } => {
                let src = Self::compile_expr_to_flat(expr, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_RESIZE,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: 0,
                    arg2: mask,
                });
                Operand::Temp(dst)
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

    /// Execute a single flat operation
    #[inline(always)]
    fn execute_flat_op(signals: &mut [u64], temps: &mut [u64], op: &FlatOp) {
        match op.op_type {
            OP_COPY_TO_SIG => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_COPY_SIG | OP_COPY_IMM | OP_COPY_TMP => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_NOT => {
                let val = (!FlatOp::get_operand(signals, temps, op.arg0)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_REDUCE_AND => {
                let val = FlatOp::get_operand(signals, temps, op.arg0);
                let mask = op.arg1;
                let result = ((val & mask) == mask) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_OR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != 0) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_XOR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0).count_ones() & 1) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_AND => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) | FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) ^ FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_ADD => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_add(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SUB => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_sub(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUL => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_mul(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_DIV => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) / r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MOD => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) % r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHL => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(63) as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) << shift) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHR => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(63) as u32;
                let result = FlatOp::get_operand(signals, temps, op.arg0) >> shift;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) == FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_NE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) < FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) > FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) <= FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >= FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX => {
                // Branchless mux: arg0=cond, arg1=true, arg2=false
                let c = FlatOp::get_operand(signals, temps, op.arg0);
                let t = FlatOp::get_operand(signals, temps, op.arg1);
                let f = FlatOp::get_operand(signals, temps, op.arg2);
                let select = (c != 0) as u64;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SLICE => {
                let shift = op.arg1 as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >> shift) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_CONCAT_INIT => {
                unsafe { *temps.get_unchecked_mut(op.dst) = 0; }
            }
            OP_CONCAT_ACCUM => {
                let part = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                let shift = op.arg1 as usize;
                unsafe {
                    let current = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = current | (part << shift);
                }
            }
            OP_CONCAT_FINISH => {
                unsafe {
                    let val = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = val & op.arg2;
                }
            }
            OP_RESIZE => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            _ => {}
        }
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        // Execute all ops from single contiguous array (optimal cache access)
        for op in &self.all_comb_ops {
            Self::execute_flat_op(&mut self.signals, &mut self.temps, op);
        }
    }

    #[inline(always)]
    fn tick(&mut self) {
        // Evaluate combinational logic
        self.evaluate();

        // Sample all register inputs
        for (i, seq_assign) in self.seq_assigns.iter().enumerate() {
            for op in &seq_assign.ops {
                Self::execute_flat_op(&mut self.signals, &mut self.temps, op);
            }
            let target = seq_assign.final_target;
            self.next_regs[i] = unsafe { *self.signals.get_unchecked(target) };
        }

        // Update all registers
        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
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
        // Set keyboard input (branchless)
        let k_val = ((key_data as u64) | 0x80) * (key_ready as u64);
        unsafe { *self.signals.get_unchecked_mut(self.k_idx) = k_val; }

        // Falling edge
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 0; }
        self.evaluate();

        // Provide RAM/ROM data
        let ram_addr = unsafe { *self.signals.get_unchecked(self.ram_addr_idx) } as usize;
        let ram_data = if ram_addr >= 0xD000 {
            let rom_offset = ram_addr.wrapping_sub(0xD000);
            if rom_offset < self.rom.len() {
                unsafe { *self.rom.get_unchecked(rom_offset) }
            } else {
                0
            }
        } else {
            unsafe { *self.ram.get_unchecked(ram_addr & 0xFFFF) }
        };
        unsafe { *self.signals.get_unchecked_mut(self.ram_do_idx) = ram_data as u64; }

        // Rising edge
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 1; }
        self.tick_fast();

        // Handle RAM writes
        let mut text_dirty = false;
        let ram_we = unsafe { *self.signals.get_unchecked(self.ram_we_idx) };
        if ram_we == 1 {
            let write_addr = unsafe { *self.signals.get_unchecked(self.ram_addr_idx) } as usize;
            if write_addr < 0xC000 {
                let data = unsafe { (*self.signals.get_unchecked(self.d_idx) & 0xFF) as u8 };
                unsafe { *self.ram.get_unchecked_mut(write_addr) = data; }
                text_dirty = (write_addr >= 0x0400) & (write_addr <= 0x07FF);
            }
        }

        // Check keyboard strobe
        let key_cleared = unsafe { *self.signals.get_unchecked(self.read_key_idx) } == 1;

        (text_dirty, key_cleared)
    }

    /// Optimized tick - only evaluate once after register update
    #[inline(always)]
    fn tick_fast(&mut self) {
        self.evaluate();

        // Sample register inputs
        for (i, seq_assign) in self.seq_assigns.iter().enumerate() {
            for op in &seq_assign.ops {
                Self::execute_flat_op(&mut self.signals, &mut self.temps, op);
            }
            let target = seq_assign.final_target;
            self.next_regs[i] = unsafe { *self.signals.get_unchecked(target) };
        }

        // Update registers
        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
            unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[i]; }
        }

        self.evaluate();
    }

    /// Run N CPU cycles
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
                result.text_dirty |= text_dirty;
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
        for val in self.temps.iter_mut() {
            *val = 0;
        }
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

#[magnus::wrap(class = "RHDL::Codegen::CIRCT::FirrtlInterpreter")]
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
        hash.aset(ruby.sym_new("comb_op_count"), sim.all_comb_ops.len() as i64)?;
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

    let class = circt.define_class("FirrtlInterpreter", ruby.class_object())?;

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

    circt.const_set("FIRRTL_INTERPRETER_AVAILABLE", true)?;

    Ok(())
}
