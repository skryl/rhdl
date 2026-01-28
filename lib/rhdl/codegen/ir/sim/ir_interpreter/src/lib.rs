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
    #[serde(default)]
    reset_value: Option<u64>,
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
    MemRead { memory: String, addr: Box<ExprDef>, width: usize },
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
#[derive(Debug, Clone, Deserialize)]
struct MemoryDef {
    name: String,
    depth: usize,
    width: usize,
    #[serde(default)]
    initial_data: Vec<u64>,
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
const OP_MEM_READ: u8 = 30;    // temps[dst] = memories[arg0][get_operand(arg1)] & arg2

// Specialized ops with pre-decoded signal operands (no tag checking at runtime)
// These store raw signal indices in arg0/arg1 instead of tagged operands
const OP_AND_SS: u8 = 32;      // temps[dst] = signals[arg0] & signals[arg1]
const OP_OR_SS: u8 = 33;       // temps[dst] = signals[arg0] | signals[arg1]
const OP_XOR_SS: u8 = 34;      // temps[dst] = signals[arg0] ^ signals[arg1]
const OP_EQ_SS: u8 = 35;       // temps[dst] = (signals[arg0] == signals[arg1]) as u64
const OP_MUX_SSS: u8 = 36;     // temps[dst] = mux(signals[arg0], signals[arg1], signals[arg2])
const OP_COPY_SIG_TO_SIG: u8 = 37;  // signals[dst] = signals[arg0] & arg2
const OP_AND_SI: u8 = 38;      // temps[dst] = signals[arg0] & arg1 (immediate in arg1)
const OP_OR_SI: u8 = 39;       // temps[dst] = signals[arg0] | arg1
const OP_SLICE_S: u8 = 40;     // temps[dst] = (signals[arg0] >> arg1) & arg2
const OP_NOT_S: u8 = 41;       // temps[dst] = (!signals[arg0]) & arg2
const OP_STORE_NEXT_REG: u8 = 42;  // next_regs[dst] = get_operand(arg0) & arg2

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
    /// Fast path: if the assignment is just reading a signal (optionally masked),
    /// store the source signal index and mask directly to skip op execution
    fast_source: Option<(usize, u64)>,  // (signal_idx, mask)
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
    /// All sequential ops flattened for cache-friendly sampling
    /// Each op sequence ends with a special marker op that stores result in next_regs
    all_seq_ops: Vec<FlatOp>,
    /// For each sequential assign: (start_idx, fast_source option)
    /// If fast_source is Some, skip ops and just read signal directly
    seq_fast_paths: Vec<Option<(usize, u64)>>,  // (signal_idx, mask)
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Next register values buffer
    next_regs: Vec<u64>,
    /// Sequential assignment target indices
    seq_targets: Vec<usize>,

    // Multi-clock domain support
    /// Clock signal index for each sequential assignment
    seq_clocks: Vec<usize>,
    /// All unique clock signal indices used by processes
    clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    old_clocks: Vec<u64>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    /// This avoids O(n) scan of seq_clocks for each clock edge
    clock_domain_assigns: Vec<Vec<(usize, usize)>>,

    // Apple II specific: internalized memory for batched execution
    /// RAM (48KB)
    ram: Vec<u8>,
    /// ROM (12KB)
    rom: Vec<u8>,
    /// RAM address signal index
    ram_addr_idx: usize,
    /// CPU address register index (for memory access, not muxed with video)
    cpu_addr_idx: usize,
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
    /// Speaker output index
    speaker_idx: usize,
    /// Previous speaker state for edge detection
    prev_speaker: u64,
    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
    /// Memory arrays (indexed by memory index)
    memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index mapping
    memory_name_to_idx: HashMap<String, usize>,
    /// Sub-cycles per CPU cycle (1-14, default 14 for full timing accuracy)
    sub_cycles: usize,

    // MOS6502 CPU-only mode: memory bridging internalized
    /// True if this is a MOS6502 CPU IR (has addr, data_in, data_out, rw signals)
    mos6502_mode: bool,
    /// MOS6502 memory (64KB unified)
    mos6502_memory: Vec<u8>,
    /// MOS6502 ROM mask (true = ROM protected)
    mos6502_rom_mask: Vec<bool>,
    /// MOS6502 address output signal index
    mos6502_addr_idx: usize,
    /// MOS6502 data input signal index
    mos6502_data_in_idx: usize,
    /// MOS6502 data output signal index
    mos6502_data_out_idx: usize,
    /// MOS6502 read/write signal index (1=read, 0=write)
    mos6502_rw_idx: usize,
    /// MOS6502 clock signal index
    mos6502_clk_idx: usize,
}

impl RtlSimulator {
    fn new(json: &str, sub_cycles: usize) -> Result<Self, String> {
        // Clamp sub_cycles to valid range (1-14)
        let sub_cycles = sub_cycles.max(1).min(14);
        // Use deserializer with disabled recursion limit for deeply nested IR
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

        // Registers (with reset values)
        let reg_count = ir.regs.len();
        let mut reset_values: Vec<(usize, u64)> = Vec::new();
        for reg in &ir.regs {
            let idx = signals.len();
            let reset_val = reg.reset_value.unwrap_or(0);
            signals.push(reset_val);  // Initialize with reset value
            widths.push(reg.width);
            name_to_idx.insert(reg.name.clone(), idx);
            if reset_val != 0 {
                reset_values.push((idx, reset_val));
            }
        }

        let signal_count = signals.len();

        // Build memory arrays (needed early for expression compilation)
        let (memory_arrays, mem_name_to_idx) = Self::build_memory_arrays(&ir.memories);

        // Compile combinational assignments to flat ops
        let mut max_temps = 0usize;
        let mut all_comb_ops: Vec<FlatOp> = Vec::new();

        for assign in &ir.assigns {
            let target_idx = *name_to_idx.get(&assign.target).unwrap_or(&0);
            let (ops, temps_used) = Self::compile_to_flat_ops(&assign.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
            max_temps = max_temps.max(temps_used);
            all_comb_ops.extend(ops);
        }

        // Compile sequential assignments (kept separate for register sampling)
        // Track clock domain for each sequential assignment
        let mut seq_assigns = Vec::new();
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_set = std::collections::HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            // Get clock index for this process (default to clk_14m if not specified)
            let clock_idx = process.clock.as_ref()
                .and_then(|c| name_to_idx.get(c).copied())
                .unwrap_or_else(|| *name_to_idx.get("clk_14m").unwrap_or(&0));
            clock_set.insert(clock_idx);

            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                let (ops, temps_used) = Self::compile_to_flat_ops(&stmt.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
                max_temps = max_temps.max(temps_used);

                // Detect fast path: if expr is a simple signal read (optionally with mux/resize)
                let fast_source = Self::detect_fast_source(&stmt.expr, &name_to_idx, &widths);

                seq_assigns.push(CompiledAssign { ops, final_target: target_idx, fast_source });
                seq_targets.push(target_idx);
                seq_clocks.push(clock_idx);
            }
        }

        // Collect all unique clock indices and sort for deterministic order
        // (HashSet iteration is non-deterministic)
        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let old_clocks = vec![0u64; clock_indices.len()];

        // Pre-group sequential assignments by clock domain
        // Maps clock_list_idx -> Vec<(seq_assign_idx, target_idx)>
        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(clock_list_idx) = clock_indices.iter().position(|&c| c == clk_idx) {
                clock_domain_assigns[clock_list_idx].push((seq_idx, seq_targets[seq_idx]));
            }
        }

        // Flatten sequential ops for cache-friendly sampling
        // Each sequence ends with a marker that stores result to next_regs[i]
        let mut all_seq_ops = Vec::new();
        let mut seq_fast_paths = Vec::new();

        for (i, seq_assign) in seq_assigns.iter().enumerate() {
            if let Some((src_idx, mask)) = seq_assign.fast_source {
                // Fast path: just record the source, no ops needed
                seq_fast_paths.push(Some((src_idx, mask)));
            } else if seq_assign.ops.is_empty() {
                // No ops - skip
                seq_fast_paths.push(None);
            } else {
                // Add all ops except the last (which writes to signal)
                seq_fast_paths.push(None);
                let ops_len = seq_assign.ops.len();
                for op in &seq_assign.ops[..ops_len.saturating_sub(1)] {
                    all_seq_ops.push(*op);
                }

                // For the last op, if it's COPY_TO_SIG, convert to store in next_regs
                // We use a special marker: OP_COPY_TO_SIG with dst = i (next_regs index)
                // But we need to differentiate from regular COPY_TO_SIG...
                // Actually, just store the final op info and handle in sampling
                let last_op = &seq_assign.ops[ops_len - 1];
                if last_op.op_type == OP_COPY_TO_SIG {
                    // Store a modified op that writes to next_regs instead
                    // We'll use a new op type for this
                    all_seq_ops.push(FlatOp {
                        op_type: OP_STORE_NEXT_REG,  // New op type
                        dst: i,  // next_regs index
                        arg0: last_op.arg0,
                        arg1: 0,
                        arg2: last_op.arg2,
                    });
                } else {
                    // Fallback: execute the op and store from final_target
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

        // Pre-allocate temp buffer
        let temps = vec![0u64; max_temps + 1];
        let next_regs = vec![0u64; seq_targets.len()];

        // Get Apple II specific signal indices
        let ram_addr_idx = *name_to_idx.get("ram_addr").unwrap_or(&0);
        let cpu_addr_idx = *name_to_idx.get("cpu__addr_reg").unwrap_or(&0);
        let ram_do_idx = *name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *name_to_idx.get("read_key").unwrap_or(&0);
        let speaker_idx = *name_to_idx.get("speaker").unwrap_or(&0);

        // Detect MOS6502 CPU-only mode (has addr, data_in, data_out, rw, clk signals)
        let mos6502_addr_idx = *name_to_idx.get("addr").unwrap_or(&0);
        let mos6502_data_in_idx = *name_to_idx.get("data_in").unwrap_or(&0);
        let mos6502_data_out_idx = *name_to_idx.get("data_out").unwrap_or(&0);
        let mos6502_rw_idx = *name_to_idx.get("rw").unwrap_or(&0);
        let mos6502_clk_idx = *name_to_idx.get("clk").unwrap_or(&0);
        let mos6502_mode = name_to_idx.contains_key("addr")
            && name_to_idx.contains_key("data_in")
            && name_to_idx.contains_key("data_out")
            && name_to_idx.contains_key("rw")
            && name_to_idx.contains_key("clk");

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
            old_clocks,
            clock_domain_assigns,
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx,
            cpu_addr_idx,
            ram_do_idx,
            ram_we_idx,
            d_idx,
            clk_idx,
            k_idx,
            read_key_idx,
            speaker_idx,
            prev_speaker: 0,
            reset_values,
            memory_arrays,
            memory_name_to_idx: mem_name_to_idx,
            sub_cycles,
            mos6502_mode,
            mos6502_memory: vec![0u8; 64 * 1024],
            mos6502_rom_mask: vec![false; 64 * 1024],
            mos6502_addr_idx,
            mos6502_data_in_idx,
            mos6502_data_out_idx,
            mos6502_rw_idx,
            mos6502_clk_idx,
        })
    }

    #[inline(always)]
    fn compute_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    /// Build memory arrays from IR definitions
    fn build_memory_arrays(memories: &[MemoryDef]) -> (Vec<Vec<u64>>, HashMap<String, usize>) {
        let mut arrays = Vec::new();
        let mut name_to_idx = HashMap::new();
        for (idx, mem) in memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            // Copy initial data if present
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

    /// Compile expression to flat ops
    /// Returns (ops, max_temp_used)
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

        // Final copy to target signal if needed
        let width = widths.get(final_target).copied().unwrap_or(64);
        let mask = Self::compute_mask(width);
        match result {
            Operand::Signal(idx) if idx == final_target => {
                // Already in place
            }
            Operand::Signal(src_idx) => {
                // Specialized signal-to-signal copy (re-enabled)
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

    /// Recursively compile expression to flat ops, returning operand for the result
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
                let idx = *name_to_idx.get(name).unwrap_or(&0);
                Operand::Signal(idx)
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

                // NOT_S disabled for testing
                let emitted_specialized = false;

                if !emitted_specialized {
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
                }
                Operand::Temp(dst)
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = Self::compile_expr_to_flat(left, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let r = Self::compile_expr_to_flat(right, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width);
                let dst = *temp_counter;
                *temp_counter += 1;

                // AND_SS, OR_SS, EQ_SS - testing
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

                // MUX_SSS disabled - correctness issue
                {
                    // Mux uses all 3 arg slots: cond, true_val, false_val
                    ops.push(FlatOp {
                        op_type: OP_MUX,
                        dst,
                        arg0: FlatOp::encode_operand(cond),
                        arg1: FlatOp::encode_operand(t),
                        arg2: FlatOp::encode_operand(f),
                    });
                }

                // Mask result to specified width (prevents overflow issues)
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

                // SLICE_S disabled for testing - use generic
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

                // Initialize temp to 0
                ops.push(FlatOp {
                    op_type: OP_CONCAT_INIT,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: 0,
                });

                // Concat in HDL: cat(high, low) puts first arg in high bits
                // Parts are ordered [high, ..., low], so we process in REVERSE
                // to build up from low bits (shift_acc = 0) to high bits
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
                let addr_op = Self::compile_expr_to_flat(addr, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mem_idx = *mem_name_to_idx.get(memory).unwrap_or(&0);
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

    /// Detect if an expression is a "fast path" - just reading a signal with optional masking.
    /// Returns Some((signal_idx, mask)) if fast path is possible, None otherwise.
    fn detect_fast_source(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> Option<(usize, u64)> {
        match expr {
            // Direct signal read
            ExprDef::Signal { name, width } => {
                let idx = *name_to_idx.get(name)?;
                let actual_width = widths.get(idx).copied().unwrap_or(*width);
                let mask = Self::compute_mask(actual_width);
                Some((idx, mask))
            }
            // Resize of a signal
            ExprDef::Resize { expr: inner, width } => {
                if let ExprDef::Signal { name, .. } = inner.as_ref() {
                    let idx = *name_to_idx.get(name)?;
                    let mask = Self::compute_mask(*width);
                    Some((idx, mask))
                } else {
                    None
                }
            }
            // Slice of a signal - can be optimized but requires shift
            // For now, skip this case
            _ => None,
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
            OP_MEM_READ => {
                // arg0 = memory index, arg1 = encoded address operand, arg2 = mask
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
            _ => {}
        }
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        // Execute all ops from single contiguous array (optimal cache access)
        // Inline hot ops for better performance
        let signals = &mut self.signals;
        let temps = &mut self.temps;
        let memories = &self.memory_arrays;

        for op in &self.all_comb_ops {
            // Inline the most common ops to avoid match dispatch overhead
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
                // Specialized signal-signal ops (no tag decoding overhead)
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
                // Fall through to generic handler for less common ops
                _ => Self::execute_flat_op(signals, temps, memories, op),
            }
        }
    }

    #[inline(always)]
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

        // Sample ALL register inputs using flattened ops for cache efficiency
        // First handle fast paths (direct signal reads)
        for (i, fast_path) in self.seq_fast_paths.iter().enumerate() {
            if let Some((src_idx, mask)) = fast_path {
                let val = unsafe { *self.signals.get_unchecked(*src_idx) } & mask;
                unsafe { *self.next_regs.get_unchecked_mut(i) = val; }
            }
        }

        // Execute all sequential ops in one contiguous loop (cache-friendly)
        // The flattened array includes OP_STORE_NEXT_REG ops that write to next_regs
        for op in &self.all_seq_ops {
            match op.op_type {
                OP_STORE_NEXT_REG => {
                    // Store result in next_regs[dst]
                    let val = FlatOp::get_operand(&self.signals, &self.temps, op.arg0) & op.arg2;
                    unsafe { *self.next_regs.get_unchecked_mut(op.dst) = val; }
                }
                _ => {
                    // Execute the op normally (stores in temps or signals)
                    Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
                }
            }
        }

        // Iterate for derived clock domains
        // Each iteration may cause new clock edges as registers update
        // Use pre-grouped assignments to avoid O(n) scan per clock
        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            // Detect rising edges on all clock signals
            let mut any_edge = false;
            for (clock_list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
                let old_val = self.old_clocks[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                // Check for rising edge (0 -> 1)
                if old_val == 0 && new_val == 1 {
                    any_edge = true;

                    // Update only registers clocked by this signal (pre-grouped)
                    for &(seq_idx, target_idx) in &self.clock_domain_assigns[clock_list_idx] {
                        unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
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
        // Note: Removed redundant final evaluate() - not needed after loop exits with no edges
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
    fn run_14m_cycle_internal(&mut self, key_data: u8, key_ready: bool) -> (bool, bool, bool) {
        // Set keyboard input (branchless)
        let k_val = ((key_data as u64) | 0x80) * (key_ready as u64);
        unsafe { *self.signals.get_unchecked_mut(self.k_idx) = k_val; }

        // Falling edge
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 0; }
        self.evaluate();

        // Provide RAM/ROM data based on Apple II memory map:
        // $0000-$BFFF: RAM (48KB)
        // $C000-$CFFF: I/O space (soft switches, slot ROMs)
        // $D000-$FFFF: ROM (12KB)
        // Use cpu_addr (not ram_addr which may be video address when phi0=0)
        let ram_addr = unsafe { *self.signals.get_unchecked(self.cpu_addr_idx) } as usize;
        let ram_data = if ram_addr >= 0xD000 {
            // ROM space
            let rom_offset = ram_addr.wrapping_sub(0xD000);
            if rom_offset < self.rom.len() {
                unsafe { *self.rom.get_unchecked(rom_offset) }
            } else {
                0
            }
        } else if ram_addr >= 0xC000 {
            // I/O space - return 0 (soft switches handled by HDL logic)
            0
        } else {
            // RAM space
            unsafe { *self.ram.get_unchecked(ram_addr) }
        };
        unsafe { *self.signals.get_unchecked_mut(self.ram_do_idx) = ram_data as u64; }

        // Rising edge
        unsafe { *self.signals.get_unchecked_mut(self.clk_idx) = 1; }
        self.tick_fast();

        // Handle RAM writes (use cpu_addr, not ram_addr which may be video address)
        let mut text_dirty = false;
        let ram_we = unsafe { *self.signals.get_unchecked(self.ram_we_idx) };
        if ram_we == 1 {
            let write_addr = unsafe { *self.signals.get_unchecked(self.cpu_addr_idx) } as usize;
            if write_addr < 0xC000 {
                let data = unsafe { (*self.signals.get_unchecked(self.d_idx) & 0xFF) as u8 };
                unsafe { *self.ram.get_unchecked_mut(write_addr) = data; }
                text_dirty = (write_addr >= 0x0400) & (write_addr <= 0x07FF);
            }
        }

        // Check keyboard strobe
        let key_cleared = unsafe { *self.signals.get_unchecked(self.read_key_idx) } == 1;

        // Check speaker toggle (edge detection)
        let speaker = unsafe { *self.signals.get_unchecked(self.speaker_idx) };
        let speaker_toggled = speaker != self.prev_speaker;
        self.prev_speaker = speaker;

        (text_dirty, key_cleared, speaker_toggled)
    }

    /// Optimized tick with multi-clock domain support
    #[inline(always)]
    fn tick_fast(&mut self) {
        // Save old clock values FIRST
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.old_clocks[i] = self.signals[clk_idx];
        }

        self.evaluate();

        // Sample ALL register inputs at this point (before any register updates)
        // IMPORTANT: Don't write to signals during sampling - only store results in next_regs
        for (i, seq_assign) in self.seq_assigns.iter().enumerate() {
            // Fast path: if this is a simple signal read, just read directly
            if let Some((src_idx, mask)) = seq_assign.fast_source {
                let val = unsafe { *self.signals.get_unchecked(src_idx) } & mask;
                self.next_regs[i] = val;
                continue;
            }

            // Slow path: execute ops
            let ops_len = seq_assign.ops.len();
            if ops_len == 0 {
                continue;
            }

            // Execute all ops except the last (which writes to signals)
            for op in &seq_assign.ops[..ops_len.saturating_sub(1)] {
                Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
            }

            // For the last op, get the result without writing to signals
            let last_op = &seq_assign.ops[ops_len - 1];
            if last_op.op_type == OP_COPY_TO_SIG {
                let val = FlatOp::get_operand(&self.signals, &self.temps, last_op.arg0) & last_op.arg2;
                self.next_regs[i] = val;
            } else {
                Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, last_op);
                self.next_regs[i] = unsafe { *self.signals.get_unchecked(seq_assign.final_target) };
            }
        }

        // Iterate for derived clock domains
        // Use pre-grouped assignments to avoid O(n) scan per clock
        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for (clock_list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
                let old_val = self.old_clocks[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    // Use pre-grouped assignments for this clock domain
                    for &(seq_idx, target_idx) in &self.clock_domain_assigns[clock_list_idx] {
                        unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
                    }
                    self.old_clocks[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            self.evaluate();
        }
        // Note: Removed redundant final evaluate() - not needed after loop exits with no edges
    }

    /// Run N CPU cycles
    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> BatchResult {
        let mut result = BatchResult {
            text_dirty: false,
            key_cleared: false,
            cycles_run: n,
            speaker_toggles: 0,
        };

        let mut current_key_ready = key_ready;

        for _ in 0..n {
            for _ in 0..self.sub_cycles {
                let (text_dirty, key_cleared, speaker_toggled) = self.run_14m_cycle_internal(key_data, current_key_ready);
                result.text_dirty |= text_dirty;
                if key_cleared {
                    current_key_ready = false;
                    result.key_cleared = true;
                }
                if speaker_toggled {
                    result.speaker_toggles += 1;
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
        // Apply register reset values
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
    }

    fn signal_count(&self) -> usize {
        self.signal_count
    }

    fn reg_count(&self) -> usize {
        self.reg_count
    }

    // ========================================================================
    // MOS6502 CPU-only mode methods
    // ========================================================================

    /// Check if this simulator is in MOS6502 CPU-only mode
    fn is_mos6502_mode(&self) -> bool {
        self.mos6502_mode
    }

    /// Load memory for MOS6502 mode
    /// If rom is true, memory is marked as ROM (writes blocked)
    fn load_mos6502_memory(&mut self, data: &[u8], offset: usize, rom: bool) {
        let end = (offset + data.len()).min(self.mos6502_memory.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.mos6502_memory[offset..end].copy_from_slice(&data[..len]);
            if rom {
                for i in offset..end {
                    self.mos6502_rom_mask[i] = true;
                }
            }
        }
    }

    /// Set reset vector directly (bypasses ROM protection)
    fn set_mos6502_reset_vector(&mut self, addr: u16) {
        self.mos6502_memory[0xFFFC] = (addr & 0xFF) as u8;
        self.mos6502_memory[0xFFFD] = ((addr >> 8) & 0xFF) as u8;
    }

    /// Run N CPU cycles with internalized memory bridging for MOS6502
    /// Returns the number of cycles actually run
    fn run_mos6502_cycles(&mut self, n: usize) -> usize {
        if !self.mos6502_mode {
            return 0;
        }

        // Find clock index in our clock_indices array for proper edge detection
        let clk_list_idx = self.clock_indices.iter().position(|&ci| ci == self.mos6502_clk_idx);

        for _ in 0..n {
            // Get address and R/W from CPU
            let addr = unsafe { *self.signals.get_unchecked(self.mos6502_addr_idx) } as usize & 0xFFFF;
            let rw = unsafe { *self.signals.get_unchecked(self.mos6502_rw_idx) };

            if rw == 1 {
                // Read: provide data from memory to CPU
                let data = unsafe { *self.mos6502_memory.get_unchecked(addr) } as u64;
                unsafe { *self.signals.get_unchecked_mut(self.mos6502_data_in_idx) = data; }
            } else {
                // Write: store CPU data to memory (unless ROM protected)
                if !unsafe { *self.mos6502_rom_mask.get_unchecked(addr) } {
                    let data = unsafe { *self.signals.get_unchecked(self.mos6502_data_out_idx) } as u8;
                    unsafe { *self.mos6502_memory.get_unchecked_mut(addr) = data; }
                }
            }

            // Clock falling edge
            // First save current clock state, then set to 0, then tick
            if let Some(idx) = clk_list_idx {
                self.old_clocks[idx] = 1; // Previous state was high
            }
            unsafe { *self.signals.get_unchecked_mut(self.mos6502_clk_idx) = 0; }
            self.evaluate();

            // Clock rising edge - this is where registers update
            // Save current clock state (0), then set to 1, then full tick for register sampling
            if let Some(idx) = clk_list_idx {
                self.old_clocks[idx] = 0; // Previous state was low
            }
            unsafe { *self.signals.get_unchecked_mut(self.mos6502_clk_idx) = 1; }
            self.tick();
        }

        n
    }

    /// Read from MOS6502 memory
    fn read_mos6502_memory(&self, addr: usize) -> u8 {
        if addr < self.mos6502_memory.len() {
            self.mos6502_memory[addr]
        } else {
            0
        }
    }
}

/// Result of batched cycle execution
struct BatchResult {
    text_dirty: bool,
    key_cleared: bool,
    cycles_run: usize,
    speaker_toggles: u32,
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

#[magnus::wrap(class = "RHDL::Codegen::IR::IrInterpreter")]
struct RubyRtlSim {
    sim: RefCell<RtlSimulator>,
}

impl RubyRtlSim {
    fn new(json: String, sub_cycles: Option<i64>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let cycles = sub_cycles.unwrap_or(14) as usize;
        let sim = RtlSimulator::new(&json, cycles)
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
        hash.aset(ruby.sym_new("speaker_toggles"), result.speaker_toggles as i64)?;
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
        let fast_count = sim.seq_assigns.iter().filter(|a| a.fast_source.is_some()).count();
        hash.aset(ruby.sym_new("seq_fast_count"), fast_count as i64)?;
        hash.aset(ruby.sym_new("mos6502_mode"), sim.is_mos6502_mode())?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }

    // MOS6502 CPU-only mode methods

    fn is_mos6502_mode(&self) -> bool {
        self.sim.borrow().is_mos6502_mode()
    }

    fn load_mos6502_memory(&self, data: RArray, offset: usize, rom: bool) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid memory data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_mos6502_memory(&bytes, offset, rom);
        Ok(())
    }

    fn set_mos6502_reset_vector(&self, addr: i64) -> Result<(), Error> {
        self.sim.borrow_mut().set_mos6502_reset_vector(addr as u16);
        Ok(())
    }

    fn run_mos6502_cycles(&self, n: usize) -> usize {
        self.sim.borrow_mut().run_mos6502_cycles(n)
    }

    fn read_mos6502_memory(&self, addr: usize) -> u8 {
        self.sim.borrow().read_mos6502_memory(addr)
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let ir = codegen.define_module("IR")?;

    let class = ir.define_class("IrInterpreter", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyRtlSim::new, 2))?;
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

    // MOS6502 CPU-only mode methods
    class.define_method("mos6502_mode?", method!(RubyRtlSim::is_mos6502_mode, 0))?;
    class.define_method("load_mos6502_memory", method!(RubyRtlSim::load_mos6502_memory, 3))?;
    class.define_method("set_mos6502_reset_vector", method!(RubyRtlSim::set_mos6502_reset_vector, 1))?;
    class.define_method("run_mos6502_cycles", method!(RubyRtlSim::run_mos6502_cycles, 1))?;
    class.define_method("read_mos6502_memory", method!(RubyRtlSim::read_mos6502_memory, 1))?;

    Ok(())
}
