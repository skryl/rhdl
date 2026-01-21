//! High-performance RTL simulator for FIRRTL/Behavior IR with Ruby bindings
//!
//! Optimizations:
//! - Direct operation sequence (no stack, no VM dispatch)
//! - Vec<u64> indexing instead of HashMap<String, u64> for O(1) signal access
//! - Batched cycle execution to minimize Ruby-Rust FFI overhead
//! - Internalized RAM/ROM for zero-copy memory access
//! - Unsafe unchecked array access in hot loops
//! - Operations flattened at load time - circuit is "baked in"

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
// Direct Operation Model - No Stack, No VM
// ============================================================================

/// Operand source - either a signal index or an immediate value
#[derive(Debug, Clone, Copy)]
enum Operand {
    Signal(usize),      // Index into signals array
    Immediate(u64),     // Literal value
    Temp(usize),        // Index into temp array
}

/// Direct operation - reads from operands, writes to target
#[derive(Debug, Clone, Copy)]
enum DirectOp {
    // Simple copy/load
    Copy { dst: usize, src: Operand, mask: u64 },

    // Unary operations
    Not { dst: usize, src: Operand, mask: u64 },
    ReduceAnd { dst: usize, src: Operand, src_mask: u64 },
    ReduceOr { dst: usize, src: Operand },
    ReduceXor { dst: usize, src: Operand },

    // Binary operations
    And { dst: usize, left: Operand, right: Operand },
    Or { dst: usize, left: Operand, right: Operand },
    Xor { dst: usize, left: Operand, right: Operand },
    Add { dst: usize, left: Operand, right: Operand, mask: u64 },
    Sub { dst: usize, left: Operand, right: Operand, mask: u64 },
    Mul { dst: usize, left: Operand, right: Operand, mask: u64 },
    Div { dst: usize, left: Operand, right: Operand },
    Mod { dst: usize, left: Operand, right: Operand },
    Shl { dst: usize, left: Operand, right: Operand, mask: u64 },
    Shr { dst: usize, left: Operand, right: Operand },
    Eq { dst: usize, left: Operand, right: Operand },
    Ne { dst: usize, left: Operand, right: Operand },
    Lt { dst: usize, left: Operand, right: Operand },
    Gt { dst: usize, left: Operand, right: Operand },
    Le { dst: usize, left: Operand, right: Operand },
    Ge { dst: usize, left: Operand, right: Operand },

    // Mux - branchless select
    Mux { dst: usize, cond: Operand, when_true: Operand, when_false: Operand, mask: u64 },

    // Slice
    Slice { dst: usize, src: Operand, shift: u32, mask: u64 },

    // Concat operations
    ConcatInit { dst: usize },
    ConcatAccum { dst: usize, src: Operand, shift: usize, part_mask: u64 },
    ConcatFinish { dst: usize, mask: u64 },

    // Resize
    Resize { dst: usize, src: Operand, mask: u64 },
}

/// Compiled assignment - sequence of direct ops ending with final target
#[derive(Debug, Clone)]
struct CompiledAssign {
    ops: Vec<DirectOp>,
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
    /// Compiled combinational assignments
    assigns: Vec<CompiledAssign>,
    /// Compiled sequential assignments
    seq_assigns: Vec<CompiledAssign>,
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

        // Compile combinational assignments to direct ops
        let mut max_temps = 0usize;
        let assigns: Vec<CompiledAssign> = ir.assigns.iter().map(|a| {
            let target_idx = *name_to_idx.get(&a.target).unwrap_or(&0);
            let width = widths.get(target_idx).copied().unwrap_or(64);
            let (ops, temps_used) = Self::compile_to_direct_ops(&a.expr, target_idx, &name_to_idx, &widths);
            max_temps = max_temps.max(temps_used);
            CompiledAssign { ops, final_target: target_idx }
        }).collect();

        // Compile sequential assignments to direct ops
        let mut seq_assigns = Vec::new();
        let mut seq_targets = Vec::new();
        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                let (ops, temps_used) = Self::compile_to_direct_ops(&stmt.expr, target_idx, &name_to_idx, &widths);
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
            assigns,
            seq_assigns,
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

    /// Compile expression to direct operations
    /// Returns (ops, max_temp_used)
    fn compile_to_direct_ops(
        expr: &ExprDef,
        final_target: usize,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> (Vec<DirectOp>, usize) {
        let mut ops = Vec::new();
        let mut temp_counter = 0usize;

        let result = Self::compile_expr_recursive(expr, name_to_idx, widths, &mut ops, &mut temp_counter);

        // Final copy to target if needed
        let width = widths.get(final_target).copied().unwrap_or(64);
        let mask = Self::compute_mask(width);
        match result {
            Operand::Signal(idx) if idx == final_target => {
                // Already in place
            }
            _ => {
                ops.push(DirectOp::Copy { dst: final_target, src: result, mask });
            }
        }

        (ops, temp_counter)
    }

    /// Recursively compile expression, returning operand for the result
    fn compile_expr_recursive(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize],
        ops: &mut Vec<DirectOp>,
        temp_counter: &mut usize,
    ) -> Operand {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = *name_to_idx.get(name).unwrap_or(&0);
                Operand::Signal(idx)
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compute_mask(*width);
                Operand::Immediate((*value as u64) & mask)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = Self::compile_expr_recursive(operand, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                let op_width = Self::expr_width(operand, widths, name_to_idx);
                let op_mask = Self::compute_mask(op_width);

                match op.as_str() {
                    "~" | "not" => ops.push(DirectOp::Not { dst, src, mask }),
                    "&" | "reduce_and" => ops.push(DirectOp::ReduceAnd { dst, src, src_mask: op_mask }),
                    "|" | "reduce_or" => ops.push(DirectOp::ReduceOr { dst, src }),
                    "^" | "reduce_xor" => ops.push(DirectOp::ReduceXor { dst, src }),
                    _ => ops.push(DirectOp::Copy { dst, src, mask }),
                }
                Operand::Temp(dst)
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = Self::compile_expr_recursive(left, name_to_idx, widths, ops, temp_counter);
                let r = Self::compile_expr_recursive(right, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                match op.as_str() {
                    "&" => ops.push(DirectOp::And { dst, left: l, right: r }),
                    "|" => ops.push(DirectOp::Or { dst, left: l, right: r }),
                    "^" => ops.push(DirectOp::Xor { dst, left: l, right: r }),
                    "+" => ops.push(DirectOp::Add { dst, left: l, right: r, mask }),
                    "-" => ops.push(DirectOp::Sub { dst, left: l, right: r, mask }),
                    "*" => ops.push(DirectOp::Mul { dst, left: l, right: r, mask }),
                    "/" => ops.push(DirectOp::Div { dst, left: l, right: r }),
                    "%" => ops.push(DirectOp::Mod { dst, left: l, right: r }),
                    "<<" => ops.push(DirectOp::Shl { dst, left: l, right: r, mask }),
                    ">>" => ops.push(DirectOp::Shr { dst, left: l, right: r }),
                    "==" => ops.push(DirectOp::Eq { dst, left: l, right: r }),
                    "!=" => ops.push(DirectOp::Ne { dst, left: l, right: r }),
                    "<" => ops.push(DirectOp::Lt { dst, left: l, right: r }),
                    ">" => ops.push(DirectOp::Gt { dst, left: l, right: r }),
                    "<=" | "le" => ops.push(DirectOp::Le { dst, left: l, right: r }),
                    ">=" => ops.push(DirectOp::Ge { dst, left: l, right: r }),
                    _ => ops.push(DirectOp::And { dst, left: l, right: r }),
                }
                Operand::Temp(dst)
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = Self::compile_expr_recursive(condition, name_to_idx, widths, ops, temp_counter);
                let t = Self::compile_expr_recursive(when_true, name_to_idx, widths, ops, temp_counter);
                let f = Self::compile_expr_recursive(when_false, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(DirectOp::Mux { dst, cond, when_true: t, when_false: f, mask });
                Operand::Temp(dst)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = Self::compile_expr_recursive(base, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(DirectOp::Slice { dst, src, shift: *low as u32, mask });
                Operand::Temp(dst)
            }
            ExprDef::Concat { parts, width } => {
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(DirectOp::ConcatInit { dst });
                let mut shift = 0usize;
                for part in parts {
                    let src = Self::compile_expr_recursive(part, name_to_idx, widths, ops, temp_counter);
                    let part_width = Self::expr_width(part, widths, name_to_idx);
                    let part_mask = Self::compute_mask(part_width);
                    ops.push(DirectOp::ConcatAccum { dst, src, shift, part_mask });
                    shift += part_width;
                }
                let mask = Self::compute_mask(*width);
                ops.push(DirectOp::ConcatFinish { dst, mask });
                Operand::Temp(dst)
            }
            ExprDef::Resize { expr, width } => {
                let src = Self::compile_expr_recursive(expr, name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(DirectOp::Resize { dst, src, mask });
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

    /// Get operand value (static function to avoid borrow issues)
    #[inline(always)]
    fn get_operand_static(signals: &[u64], temps: &[u64], op: Operand) -> u64 {
        match op {
            Operand::Signal(idx) => unsafe { *signals.get_unchecked(idx) },
            Operand::Immediate(val) => val,
            Operand::Temp(idx) => unsafe { *temps.get_unchecked(idx) },
        }
    }

    /// Execute a single direct operation (static to avoid borrow issues)
    #[inline(always)]
    fn execute_op_static(signals: &mut [u64], temps: &mut [u64], op: &DirectOp) {
        match *op {
            DirectOp::Copy { dst, src, mask } => {
                let val = Self::get_operand_static(signals, temps, src) & mask;
                unsafe { *signals.get_unchecked_mut(dst) = val; }
            }
            DirectOp::Not { dst, src, mask } => {
                let val = (!Self::get_operand_static(signals, temps, src)) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = val; }
            }
            DirectOp::ReduceAnd { dst, src, src_mask } => {
                let val = Self::get_operand_static(signals, temps, src);
                let result = ((val & src_mask) == src_mask) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::ReduceOr { dst, src } => {
                let result = (Self::get_operand_static(signals, temps, src) != 0) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::ReduceXor { dst, src } => {
                let result = (Self::get_operand_static(signals, temps, src).count_ones() & 1) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::And { dst, left, right } => {
                let result = Self::get_operand_static(signals, temps, left) & Self::get_operand_static(signals, temps, right);
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Or { dst, left, right } => {
                let result = Self::get_operand_static(signals, temps, left) | Self::get_operand_static(signals, temps, right);
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Xor { dst, left, right } => {
                let result = Self::get_operand_static(signals, temps, left) ^ Self::get_operand_static(signals, temps, right);
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Add { dst, left, right, mask } => {
                let result = Self::get_operand_static(signals, temps, left).wrapping_add(Self::get_operand_static(signals, temps, right)) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Sub { dst, left, right, mask } => {
                let result = Self::get_operand_static(signals, temps, left).wrapping_sub(Self::get_operand_static(signals, temps, right)) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Mul { dst, left, right, mask } => {
                let result = Self::get_operand_static(signals, temps, left).wrapping_mul(Self::get_operand_static(signals, temps, right)) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Div { dst, left, right } => {
                let r = Self::get_operand_static(signals, temps, right);
                let result = if r != 0 { Self::get_operand_static(signals, temps, left) / r } else { 0 };
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Mod { dst, left, right } => {
                let r = Self::get_operand_static(signals, temps, right);
                let result = if r != 0 { Self::get_operand_static(signals, temps, left) % r } else { 0 };
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Shl { dst, left, right, mask } => {
                let shift = Self::get_operand_static(signals, temps, right).min(63) as u32;
                let result = (Self::get_operand_static(signals, temps, left) << shift) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Shr { dst, left, right } => {
                let shift = Self::get_operand_static(signals, temps, right).min(63) as u32;
                let result = Self::get_operand_static(signals, temps, left) >> shift;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Eq { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) == Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Ne { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) != Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Lt { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) < Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Gt { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) > Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Le { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) <= Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Ge { dst, left, right } => {
                let result = (Self::get_operand_static(signals, temps, left) >= Self::get_operand_static(signals, temps, right)) as u64;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::Mux { dst, cond, when_true, when_false, mask } => {
                // Branchless mux
                let c = Self::get_operand_static(signals, temps, cond);
                let t = Self::get_operand_static(signals, temps, when_true);
                let f = Self::get_operand_static(signals, temps, when_false);
                let select = (c != 0) as u64;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(dst) = result & mask; }
            }
            DirectOp::Slice { dst, src, shift, mask } => {
                let result = (Self::get_operand_static(signals, temps, src) >> shift) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
            DirectOp::ConcatInit { dst } => {
                unsafe { *temps.get_unchecked_mut(dst) = 0; }
            }
            DirectOp::ConcatAccum { dst, src, shift, part_mask } => {
                let part = Self::get_operand_static(signals, temps, src) & part_mask;
                unsafe {
                    let current = *temps.get_unchecked(dst);
                    *temps.get_unchecked_mut(dst) = current | (part << shift);
                }
            }
            DirectOp::ConcatFinish { dst, mask } => {
                unsafe {
                    let val = *temps.get_unchecked(dst);
                    *temps.get_unchecked_mut(dst) = val & mask;
                }
            }
            DirectOp::Resize { dst, src, mask } => {
                let result = Self::get_operand_static(signals, temps, src) & mask;
                unsafe { *temps.get_unchecked_mut(dst) = result; }
            }
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

    #[inline(always)]
    fn evaluate(&mut self) {
        // Execute all assignments in order
        for i in 0..self.assigns.len() {
            for j in 0..self.assigns[i].ops.len() {
                let op = self.assigns[i].ops[j];
                Self::execute_op_static(&mut self.signals, &mut self.temps, &op);
            }
        }
    }

    #[inline(always)]
    fn tick(&mut self) {
        // Evaluate combinational logic
        self.evaluate();

        // Sample all register inputs
        for i in 0..self.seq_assigns.len() {
            for j in 0..self.seq_assigns[i].ops.len() {
                let op = self.seq_assigns[i].ops[j];
                Self::execute_op_static(&mut self.signals, &mut self.temps, &op);
            }
            let target = self.seq_assigns[i].final_target;
            self.next_regs[i] = unsafe { *self.signals.get_unchecked(target) };
        }

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
        for i in 0..self.seq_assigns.len() {
            for j in 0..self.seq_assigns[i].ops.len() {
                let op = self.seq_assigns[i].ops[j];
                Self::execute_op_static(&mut self.signals, &mut self.temps, &op);
            }
            let target = self.seq_assigns[i].final_target;
            self.next_regs[i] = unsafe { *self.signals.get_unchecked(target) };
        }

        // Update registers
        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
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
