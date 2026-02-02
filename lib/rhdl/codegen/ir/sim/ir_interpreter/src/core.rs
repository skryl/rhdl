//! Core interpreter simulator for IR simulation
//!
//! This is the generic simulation infrastructure without example-specific code.
//! Extension modules add specialized functionality for specific use cases.

use serde::Deserialize;
use std::collections::HashMap;

/// Port direction
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    In,
    Out,
}

/// Port definition
#[derive(Debug, Clone, Deserialize)]
pub struct PortDef {
    pub name: String,
    pub direction: Direction,
    pub width: usize,
}

/// Wire/net definition
#[derive(Debug, Clone, Deserialize)]
pub struct NetDef {
    pub name: String,
    pub width: usize,
}

/// Register definition
#[derive(Debug, Clone, Deserialize)]
pub struct RegDef {
    pub name: String,
    pub width: usize,
    #[serde(default)]
    pub reset_value: Option<u64>,
}

/// Expression types (JSON deserialization)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ExprDef {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
    UnaryOp { op: String, operand: Box<ExprDef>, width: usize },
    BinaryOp { op: String, left: Box<ExprDef>, right: Box<ExprDef>, width: usize },
    Mux { condition: Box<ExprDef>, when_true: Box<ExprDef>, when_false: Box<ExprDef>, width: usize },
    #[allow(dead_code)]
    Slice { base: Box<ExprDef>, low: usize, high: usize, width: usize },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
    MemRead { memory: String, addr: Box<ExprDef>, width: usize },
}

/// Assignment (combinational)
#[derive(Debug, Clone, Deserialize)]
pub struct AssignDef {
    pub target: String,
    pub expr: ExprDef,
}

/// Sequential assignment
#[derive(Debug, Clone, Deserialize)]
pub struct SeqAssignDef {
    pub target: String,
    pub expr: ExprDef,
}

/// Process (sequential block)
#[derive(Debug, Clone, Deserialize)]
pub struct ProcessDef {
    #[allow(dead_code)]
    pub name: String,
    #[allow(dead_code)]
    pub clock: Option<String>,
    pub clocked: bool,
    pub statements: Vec<SeqAssignDef>,
}

/// Memory definition
#[derive(Debug, Clone, Deserialize)]
pub struct MemoryDef {
    pub name: String,
    pub depth: usize,
    pub width: usize,
    #[serde(default)]
    pub initial_data: Vec<u64>,
}

/// Complete module IR
#[derive(Debug, Clone, Deserialize)]
pub struct ModuleIR {
    #[allow(dead_code)]
    pub name: String,
    pub ports: Vec<PortDef>,
    pub nets: Vec<NetDef>,
    pub regs: Vec<RegDef>,
    pub assigns: Vec<AssignDef>,
    pub processes: Vec<ProcessDef>,
    #[allow(dead_code)]
    #[serde(default)]
    pub memories: Vec<MemoryDef>,
}

// ============================================================================
// Flat Operation Model - Direct Indexing, No Dispatch
// ============================================================================

/// Operand source - either a signal index or an immediate value
#[derive(Debug, Clone, Copy)]
pub enum Operand {
    Signal(usize),
    Immediate(u64),
    Temp(usize),
}

/// Flattened operation with all arguments pre-resolved
#[derive(Clone, Copy)]
pub struct FlatOp {
    pub op_type: u8,
    pub dst: usize,
    pub arg0: u64,
    pub arg1: u64,
    pub arg2: u64,
}

// Operation type constants
pub const OP_COPY_SIG: u8 = 0;
pub const OP_COPY_IMM: u8 = 1;
pub const OP_COPY_TMP: u8 = 2;
pub const OP_NOT: u8 = 3;
pub const OP_REDUCE_AND: u8 = 4;
pub const OP_REDUCE_OR: u8 = 5;
pub const OP_REDUCE_XOR: u8 = 6;
pub const OP_AND: u8 = 7;
pub const OP_OR: u8 = 8;
pub const OP_XOR: u8 = 9;
pub const OP_ADD: u8 = 10;
pub const OP_SUB: u8 = 11;
pub const OP_MUL: u8 = 12;
pub const OP_DIV: u8 = 13;
pub const OP_MOD: u8 = 14;
pub const OP_SHL: u8 = 15;
pub const OP_SHR: u8 = 16;
pub const OP_EQ: u8 = 17;
pub const OP_NE: u8 = 18;
pub const OP_LT: u8 = 19;
pub const OP_GT: u8 = 20;
pub const OP_LE: u8 = 21;
pub const OP_GE: u8 = 22;
pub const OP_MUX: u8 = 23;
pub const OP_SLICE: u8 = 24;
pub const OP_CONCAT_INIT: u8 = 25;
pub const OP_CONCAT_ACCUM: u8 = 26;
pub const OP_CONCAT_FINISH: u8 = 27;
pub const OP_RESIZE: u8 = 28;
pub const OP_COPY_TO_SIG: u8 = 29;
pub const OP_MEM_READ: u8 = 30;
pub const OP_AND_SS: u8 = 32;
pub const OP_OR_SS: u8 = 33;
pub const OP_XOR_SS: u8 = 34;
pub const OP_EQ_SS: u8 = 35;
pub const OP_MUX_SSS: u8 = 36;
pub const OP_COPY_SIG_TO_SIG: u8 = 37;
pub const OP_AND_SI: u8 = 38;
pub const OP_OR_SI: u8 = 39;
pub const OP_SLICE_S: u8 = 40;
pub const OP_NOT_S: u8 = 41;
pub const OP_STORE_NEXT_REG: u8 = 42;

// Operand type tags
const TAG_SIGNAL: u64 = 0;
const TAG_IMMEDIATE: u64 = 1 << 62;
const TAG_TEMP: u64 = 2 << 62;
const TAG_MASK: u64 = 3 << 62;
const VAL_MASK: u64 = !(3u64 << 62);

impl FlatOp {
    #[inline(always)]
    pub fn encode_operand(op: Operand) -> u64 {
        match op {
            Operand::Signal(idx) => TAG_SIGNAL | (idx as u64),
            Operand::Immediate(val) => TAG_IMMEDIATE | (val & VAL_MASK),
            Operand::Temp(idx) => TAG_TEMP | (idx as u64),
        }
    }

    #[inline(always)]
    pub fn get_operand(signals: &[u64], temps: &[u64], encoded: u64) -> u64 {
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

/// Compiled assignment - sequence of flat ops
pub struct CompiledAssign {
    pub ops: Vec<FlatOp>,
    pub final_target: usize,
    pub fast_source: Option<(usize, u64)>,
}

// ============================================================================
// Core Interpreter Simulator
// ============================================================================

pub struct CoreSimulator {
    /// Signal values
    pub signals: Vec<u64>,
    /// Temp values for intermediate computations
    pub temps: Vec<u64>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Compiled sequential assignments
    pub seq_assigns: Vec<CompiledAssign>,
    /// All combinational ops
    pub all_comb_ops: Vec<FlatOp>,
    /// All sequential ops
    pub all_seq_ops: Vec<FlatOp>,
    /// Fast paths for sequential assigns
    pub seq_fast_paths: Vec<Option<(usize, u64)>>,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Next register values buffer
    pub next_regs: Vec<u64>,
    /// Sequential assignment targets
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Previous clock values for edge detection
    pub prev_clock_values: Vec<u64>,
    /// Pre-grouped clock domain assignments
    pub clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Reset values for registers
    pub reset_values: Vec<(usize, u64)>,
    /// Memory arrays
    pub memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index mapping
    pub memory_name_to_idx: HashMap<String, usize>,
}

impl CoreSimulator {
    pub fn new(json: &str) -> Result<Self, String> {
        let mut deserializer = serde_json::Deserializer::from_str(json);
        deserializer.disable_recursion_limit();
        let ir: ModuleIR = serde::Deserialize::deserialize(&mut deserializer)
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

        // Registers
        let reg_count = ir.regs.len();
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

        let signal_count = signals.len();

        // Build memory arrays
        let (memory_arrays, mem_name_to_idx) = Self::build_memory_arrays(&ir.memories);

        // Topologically sort combinational assignments
        let sorted_assign_indices = Self::topological_sort_assigns(&ir.assigns, &name_to_idx);

        // Compile combinational assignments in topological order
        let mut max_temps = 0usize;
        let mut all_comb_ops: Vec<FlatOp> = Vec::new();

        for assign_idx in sorted_assign_indices {
            let assign = &ir.assigns[assign_idx];
            // Skip assigns with unknown targets (same as compiler behavior)
            if let Some(&target_idx) = name_to_idx.get(&assign.target) {
                let (ops, temps_used) = Self::compile_to_flat_ops(&assign.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
                max_temps = max_temps.max(temps_used);
                all_comb_ops.extend(ops);
            }
        }

        // Compile sequential assignments
        let mut seq_assigns = Vec::new();
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
                // Skip sequential statements with unknown targets (same as compiler behavior)
                if let Some(&target_idx) = name_to_idx.get(&stmt.target) {
                    let (ops, temps_used) = Self::compile_to_flat_ops(&stmt.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
                    max_temps = max_temps.max(temps_used);

                    let fast_source = Self::detect_fast_source(&stmt.expr, &name_to_idx, &widths);
                    seq_assigns.push(CompiledAssign { ops, final_target: target_idx, fast_source });
                    seq_targets.push(target_idx);
                    seq_clocks.push(clock_idx);
                }
            }
        }

        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let prev_clock_values = vec![0u64; clock_indices.len()];

        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(clock_list_idx) = clock_indices.iter().position(|&c| c == clk_idx) {
                clock_domain_assigns[clock_list_idx].push((seq_idx, seq_targets[seq_idx]));
            }
        }

        // Flatten sequential ops
        let mut all_seq_ops = Vec::new();
        let mut seq_fast_paths = Vec::new();

        for (i, seq_assign) in seq_assigns.iter().enumerate() {
            if let Some((src_idx, mask)) = seq_assign.fast_source {
                seq_fast_paths.push(Some((src_idx, mask)));
            } else if seq_assign.ops.is_empty() {
                seq_fast_paths.push(None);
            } else {
                seq_fast_paths.push(None);
                let ops_len = seq_assign.ops.len();
                for op in &seq_assign.ops[..ops_len.saturating_sub(1)] {
                    all_seq_ops.push(*op);
                }

                let last_op = &seq_assign.ops[ops_len - 1];
                if last_op.op_type == OP_COPY_TO_SIG {
                    all_seq_ops.push(FlatOp {
                        op_type: OP_STORE_NEXT_REG,
                        dst: i,
                        arg0: last_op.arg0,
                        arg1: 0,
                        arg2: last_op.arg2,
                    });
                } else {
                    all_seq_ops.push(*last_op);
                    all_seq_ops.push(FlatOp {
                        op_type: OP_STORE_NEXT_REG,
                        dst: i,
                        arg0: FlatOp::encode_operand(Operand::Signal(seq_assign.final_target)),
                        arg1: 0,
                        arg2: u64::MAX,
                    });
                }
            }
        }

        let temps = vec![0u64; max_temps + 1];
        let next_regs = vec![0u64; seq_targets.len()];

        Ok(Self {
            signals,
            temps,
            widths,
            name_to_idx,
            input_names,
            output_names,
            seq_assigns,
            all_comb_ops,
            all_seq_ops,
            seq_fast_paths,
            signal_count,
            reg_count,
            next_regs,
            seq_targets,
            seq_clocks,
            clock_indices,
            prev_clock_values,
            clock_domain_assigns,
            reset_values,
            memory_arrays,
            memory_name_to_idx: mem_name_to_idx,
        })
    }

    #[inline(always)]
    pub fn compute_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    fn build_memory_arrays(memories: &[MemoryDef]) -> (Vec<Vec<u64>>, HashMap<String, usize>) {
        let mut arrays = Vec::new();
        let mut name_to_idx = HashMap::new();
        for (idx, mem) in memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val;
                }
            }
            arrays.push(data);
            name_to_idx.insert(mem.name.clone(), idx);
        }
        (arrays, name_to_idx)
    }

    /// Extract signal dependencies from an expression
    fn expr_dependencies(expr: &ExprDef, name_to_idx: &HashMap<String, usize>, deps: &mut std::collections::HashSet<usize>) {
        match expr {
            ExprDef::Signal { name, .. } => {
                if let Some(&idx) = name_to_idx.get(name) {
                    deps.insert(idx);
                }
            }
            ExprDef::Literal { .. } => {}
            ExprDef::UnaryOp { operand, .. } => {
                Self::expr_dependencies(operand, name_to_idx, deps);
            }
            ExprDef::BinaryOp { left, right, .. } => {
                Self::expr_dependencies(left, name_to_idx, deps);
                Self::expr_dependencies(right, name_to_idx, deps);
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                Self::expr_dependencies(condition, name_to_idx, deps);
                Self::expr_dependencies(when_true, name_to_idx, deps);
                Self::expr_dependencies(when_false, name_to_idx, deps);
            }
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::expr_dependencies(part, name_to_idx, deps);
                }
            }
            ExprDef::Slice { base, .. } => {
                Self::expr_dependencies(base, name_to_idx, deps);
            }
            ExprDef::Resize { expr, .. } => {
                Self::expr_dependencies(expr, name_to_idx, deps);
            }
            ExprDef::MemRead { addr, .. } => {
                Self::expr_dependencies(addr, name_to_idx, deps);
            }
        }
    }

    /// Topologically sort assigns based on signal dependencies
    fn topological_sort_assigns(assigns: &[AssignDef], name_to_idx: &HashMap<String, usize>) -> Vec<usize> {
        let n = assigns.len();
        if n == 0 {
            return Vec::new();
        }

        // Map: target signal idx -> ALL assignment indices that write to it
        let mut target_to_assigns: HashMap<usize, Vec<usize>> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = name_to_idx.get(&assign.target) {
                target_to_assigns.entry(idx).or_insert_with(Vec::new).push(i);
            }
        }

        // Compute dependencies for each assignment
        let mut assign_deps: Vec<std::collections::HashSet<usize>> = Vec::with_capacity(n);
        for assign in assigns {
            let mut signal_deps = std::collections::HashSet::new();
            Self::expr_dependencies(&assign.expr, name_to_idx, &mut signal_deps);

            // Convert signal dependencies to assignment dependencies
            let mut deps = std::collections::HashSet::new();
            for sig_idx in signal_deps {
                if let Some(assign_indices) = target_to_assigns.get(&sig_idx) {
                    for &assign_idx in assign_indices {
                        deps.insert(assign_idx);
                    }
                }
            }
            assign_deps.push(deps);
        }

        // Topological sort using level-based approach
        let mut levels: Vec<Vec<usize>> = Vec::new();
        let mut assigned_level: Vec<Option<usize>> = vec![None; n];

        loop {
            let mut made_progress = false;
            for i in 0..n {
                if assigned_level[i].is_some() {
                    continue;
                }
                // Check if all dependencies have been assigned
                let mut max_dep_level = None;
                let mut all_deps_ready = true;
                for &dep_idx in &assign_deps[i] {
                    if dep_idx == i {
                        // Self-dependency, ignore
                        continue;
                    }
                    match assigned_level[dep_idx] {
                        Some(lvl) => {
                            max_dep_level = Some(max_dep_level.map_or(lvl, |m: usize| m.max(lvl)));
                        }
                        None => {
                            all_deps_ready = false;
                            break;
                        }
                    }
                }
                if all_deps_ready {
                    let my_level = max_dep_level.map_or(0, |l| l + 1);
                    assigned_level[i] = Some(my_level);
                    while levels.len() <= my_level {
                        levels.push(Vec::new());
                    }
                    levels[my_level].push(i);
                    made_progress = true;
                }
            }
            if !made_progress {
                // Handle remaining (cycles or orphans) - put them at the end
                let last_level = levels.len();
                for i in 0..n {
                    if assigned_level[i].is_none() {
                        if levels.len() <= last_level {
                            levels.push(Vec::new());
                        }
                        levels[last_level].push(i);
                    }
                }
                break;
            }
            if assigned_level.iter().all(|l| l.is_some()) {
                break;
            }
        }

        // Flatten levels into single sorted list
        levels.into_iter().flatten().collect()
    }

    fn compile_to_flat_ops(
        expr: &ExprDef,
        final_target: usize,
        name_to_idx: &HashMap<String, usize>,
        mem_name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> (Vec<FlatOp>, usize) {
        let mut ops: Vec<FlatOp> = Vec::new();
        let mut temp_counter = 0usize;

        let result = Self::compile_expr_to_flat(expr, name_to_idx, mem_name_to_idx, widths, &mut ops, &mut temp_counter);

        let width = widths.get(final_target).copied().unwrap_or(64);
        let mask = Self::compute_mask(width);
        match result {
            Operand::Signal(idx) if idx == final_target => {}
            Operand::Signal(src_idx) => {
                ops.push(FlatOp {
                    op_type: OP_COPY_SIG_TO_SIG,
                    dst: final_target,
                    arg0: src_idx as u64,
                    arg1: 0,
                    arg2: mask,
                });
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

    fn compile_expr_to_flat(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        mem_name_to_idx: &HashMap<String, usize>,
        widths: &[usize],
        ops: &mut Vec<FlatOp>,
        temp_counter: &mut usize,
    ) -> Operand {
        match expr {
            ExprDef::Signal { name, .. } => {
                // Unknown signals evaluate to 0 (not index 0 which is reset)
                if let Some(&idx) = name_to_idx.get(name) {
                    Operand::Signal(idx)
                } else {
                    Operand::Immediate(0)
                }
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compute_mask(*width);
                Operand::Immediate((*value as u64) & mask)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = Self::compile_expr_to_flat(operand, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
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
                    arg1: op_mask,
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = Self::compile_expr_to_flat(left, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let r = Self::compile_expr_to_flat(right, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                let emitted_specialized = match (&l, &r, op.as_str()) {
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "&") => {
                        ops.push(FlatOp { op_type: OP_AND_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "|") => {
                        ops.push(FlatOp { op_type: OP_OR_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "==") => {
                        ops.push(FlatOp { op_type: OP_EQ_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    _ => false,
                };

                if !emitted_specialized {
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
                }
                Operand::Temp(dst)
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = Self::compile_expr_to_flat(condition, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let t = Self::compile_expr_to_flat(when_true, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let f = Self::compile_expr_to_flat(when_false, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_MUX,
                    dst,
                    arg0: FlatOp::encode_operand(cond),
                    arg1: FlatOp::encode_operand(t),
                    arg2: FlatOp::encode_operand(f),
                });

                let mask = Self::compute_mask(*width);
                let masked_dst = *temp_counter;
                *temp_counter += 1;
                ops.push(FlatOp {
                    op_type: OP_RESIZE,
                    dst: masked_dst,
                    arg0: FlatOp::encode_operand(Operand::Temp(dst)),
                    arg1: 0,
                    arg2: mask,
                });
                Operand::Temp(masked_dst)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = Self::compile_expr_to_flat(base, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_SLICE,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: *low as u64,
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Concat { parts, width } => {
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_CONCAT_INIT,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: 0,
                });

                let mut shift_acc = 0u64;
                for part in parts.iter().rev() {
                    let src = Self::compile_expr_to_flat(part, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
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
                let src = Self::compile_expr_to_flat(expr, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
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
            ExprDef::MemRead { memory, addr, width } => {
                // Unknown memories return 0
                if let Some(&mem_idx) = mem_name_to_idx.get(memory) {
                    let addr_op = Self::compile_expr_to_flat(addr, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                    let mask = Self::compute_mask(*width);
                    let dst = *temp_counter;
                    *temp_counter += 1;

                    ops.push(FlatOp {
                        op_type: OP_MEM_READ,
                        dst,
                        arg0: mem_idx as u64,
                        arg1: FlatOp::encode_operand(addr_op),
                        arg2: mask,
                    });
                    Operand::Temp(dst)
                } else {
                    Operand::Immediate(0)
                }
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
            ExprDef::MemRead { width, .. } => *width,
        }
    }

    fn detect_fast_source(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> Option<(usize, u64)> {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = *name_to_idx.get(name)?;
                let actual_width = widths.get(idx).copied().unwrap_or(*width);
                let mask = Self::compute_mask(actual_width);
                Some((idx, mask))
            }
            ExprDef::Resize { expr: inner, width } => {
                if let ExprDef::Signal { name, .. } = inner.as_ref() {
                    let idx = *name_to_idx.get(name)?;
                    let mask = Self::compute_mask(*width);
                    Some((idx, mask))
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    pub fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let mask = Self::compute_mask(self.widths[idx]);
        self.signals[idx] = value & mask;
        Ok(())
    }

    pub fn peek(&self, name: &str) -> Result<u64, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        Ok(self.signals[idx])
    }

    #[inline(always)]
    fn execute_flat_op(signals: &mut [u64], temps: &mut [u64], memories: &[Vec<u64>], op: &FlatOp) {
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
            OP_MEM_READ => {
                let mem_idx = op.arg0 as usize;
                let addr = FlatOp::get_operand(signals, temps, op.arg1) as usize;
                let result = if mem_idx < memories.len() {
                    let mem = &memories[mem_idx];
                    if addr < mem.len() { mem[addr] } else { 0 }
                } else {
                    0
                };
                unsafe { *temps.get_unchecked_mut(op.dst) = result & op.arg2; }
            }
            // Specialized signal-signal operations (must be in execute_flat_op, not just evaluate)
            OP_AND_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) & *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) | *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) ^ *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ_SS => {
                let result = unsafe { (*signals.get_unchecked(op.arg0 as usize) == *signals.get_unchecked(op.arg1 as usize)) as u64 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX_SSS => {
                let c = unsafe { *signals.get_unchecked(op.arg0 as usize) };
                let t = unsafe { *signals.get_unchecked(op.arg1 as usize) };
                let f = unsafe { *signals.get_unchecked(op.arg2 as usize) };
                let select = (c != 0) as u64;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_COPY_SIG_TO_SIG => {
                let val = unsafe { *signals.get_unchecked(op.arg0 as usize) } & op.arg2;
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_AND_SI => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } & op.arg1;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR_SI => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } | op.arg1;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SLICE_S => {
                let result = (unsafe { *signals.get_unchecked(op.arg0 as usize) } >> op.arg1 as u32) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_NOT_S => {
                let result = (!unsafe { *signals.get_unchecked(op.arg0 as usize) }) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            _ => {}
        }
    }

    #[inline(always)]
    pub fn evaluate(&mut self) {
        let signals = &mut self.signals;
        let temps = &mut self.temps;
        let memories = &self.memory_arrays;

        for op in &self.all_comb_ops {
                match op.op_type {
                    OP_COPY_TO_SIG => {
                        let val = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                        unsafe { *signals.get_unchecked_mut(op.dst) = val; }
                    }
                OP_AND => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) & FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) | FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_MUX => {
                    let c = FlatOp::get_operand(signals, temps, op.arg0);
                    let t = FlatOp::get_operand(signals, temps, op.arg1);
                    let f = FlatOp::get_operand(signals, temps, op.arg2);
                    let select = (c != 0) as u64;
                    let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_RESIZE => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_EQ => {
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) == FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_NOT => {
                    let val = (!FlatOp::get_operand(signals, temps, op.arg0)) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = val; }
                }
                OP_XOR => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) ^ FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SLICE => {
                    let shift = op.arg1 as u32;
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) >> shift) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SHL => {
                    let shift = FlatOp::get_operand(signals, temps, op.arg1).min(63) as u32;
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) << shift) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_ADD => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_add(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_AND_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) & *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) | *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_XOR_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) ^ *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_EQ_SS => {
                    let result = unsafe { (*signals.get_unchecked(op.arg0 as usize) == *signals.get_unchecked(op.arg1 as usize)) as u64 };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_MUX_SSS => {
                    let c = unsafe { *signals.get_unchecked(op.arg0 as usize) };
                    let t = unsafe { *signals.get_unchecked(op.arg1 as usize) };
                    let f = unsafe { *signals.get_unchecked(op.arg2 as usize) };
                    let select = (c != 0) as u64;
                    let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                    OP_COPY_SIG_TO_SIG => {
                        let val = unsafe { *signals.get_unchecked(op.arg0 as usize) } & op.arg2;
                        unsafe { *signals.get_unchecked_mut(op.dst) = val; }
                    }
                OP_AND_SI => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } & op.arg1;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR_SI => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } | op.arg1;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SLICE_S => {
                    let result = (unsafe { *signals.get_unchecked(op.arg0 as usize) } >> op.arg1 as u32) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_NOT_S => {
                    let result = (!unsafe { *signals.get_unchecked(op.arg0 as usize) }) & op.arg2;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                    _ => Self::execute_flat_op(signals, temps, memories, op),
                }
        }
    }

    #[inline(always)]
    pub fn tick(&mut self) {
        // Save current clock values BEFORE evaluate so we can detect edges correctly
        // At this point, the user has poked clk=1 but not evaluated yet, so derived
        // clocks are still at their previous (low) values from the falling edge.
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }

        self.evaluate();

        for (i, fast_path) in self.seq_fast_paths.iter().enumerate() {
            if let Some((src_idx, mask)) = fast_path {
                let val = unsafe { *self.signals.get_unchecked(*src_idx) } & mask;
                unsafe { *self.next_regs.get_unchecked_mut(i) = val; }
            }
        }

        for op in &self.all_seq_ops {
            match op.op_type {
                OP_STORE_NEXT_REG => {
                    let val = FlatOp::get_operand(&self.signals, &self.temps, op.arg0) & op.arg2;
                    unsafe { *self.next_regs.get_unchecked_mut(op.dst) = val; }
                }
                _ => {
                    Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
                }
            }
        }

        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for (clock_list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
                let old_val = self.prev_clock_values[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    for &(seq_idx, target_idx) in &self.clock_domain_assigns[clock_list_idx] {
                        unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
                    }
                    self.prev_clock_values[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            self.evaluate();
        }

        // prev_clock_values is saved at the start of tick(), not here
        // This ensures we capture the clock values BEFORE evaluate propagates them
    }

    /// Tick with forced edge detection using prev_clock_values set by caller
    /// This skips the initial save of clock values, allowing extensions
    /// to manually control edge detection by setting prev_clock_values first.
    #[inline(always)]
    pub fn tick_forced(&mut self) {
        // Skip saving current clock values - use prev_clock_values set by caller

        // Assigns are now topologically sorted, so a single evaluate pass is sufficient
        self.evaluate();

        for (i, fast_path) in self.seq_fast_paths.iter().enumerate() {
            if let Some((src_idx, mask)) = fast_path {
                let val = unsafe { *self.signals.get_unchecked(*src_idx) } & mask;
                unsafe { *self.next_regs.get_unchecked_mut(i) = val; }
            }
        }

        for op in self.all_seq_ops.iter() {
            match op.op_type {
                OP_STORE_NEXT_REG => {
                    let val = FlatOp::get_operand(&self.signals, &self.temps, op.arg0) & op.arg2;
                    unsafe { *self.next_regs.get_unchecked_mut(op.dst) = val; }
                }
                _ => {
                    Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
                }
            }
        }

        // Track which registers have been updated to prevent double updates
        let num_seq = self.next_regs.len();
        let mut updated = vec![false; num_seq];

        const MAX_ITERATIONS: usize = 10;
        for _iter in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for (clock_list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
                let old_val = self.prev_clock_values[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    for &(seq_idx, target_idx) in &self.clock_domain_assigns[clock_list_idx] {
                        // Only update if not already updated (prevents double updates)
                        if !updated[seq_idx] {
                            unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
                            updated[seq_idx] = true;
                        }
                    }
                    // Update prev_clock_values to prevent re-triggering in this iteration
                    self.prev_clock_values[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            self.evaluate();
        }
    }

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for val in self.temps.iter_mut() {
            *val = 0;
        }
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
    }

    pub fn signal_count(&self) -> usize {
        self.signal_count
    }

    pub fn reg_count(&self) -> usize {
        self.reg_count
    }

}
