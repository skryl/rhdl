//! Core Cranelift JIT compiler for IR simulation
//!
//! This module contains the generic JIT compiler and simulator without
//! any example-specific code. Extensions for Apple II and MOS6502
//! are in separate modules.

use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::mem;

use cranelift::prelude::*;
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

// ============================================================================
// IR Data Structures
// ============================================================================

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
    pub clock: Option<String>,
    pub clocked: bool,
    pub statements: Vec<SeqAssignDef>,
}

/// Memory definition
#[derive(Debug, Clone, Deserialize)]
pub struct MemoryDef {
    pub name: String,
    pub depth: usize,
    #[allow(dead_code)]
    pub width: usize,
    #[serde(default)]
    pub initial_data: Vec<u64>,
}

/// Memory write port definition (synchronous)
#[derive(Debug, Clone, Deserialize)]
pub struct WritePortDef {
    pub memory: String,
    pub clock: String,
    pub addr: ExprDef,
    pub data: ExprDef,
    pub enable: ExprDef,
}

/// Memory synchronous read port definition
#[derive(Debug, Clone, Deserialize)]
pub struct SyncReadPortDef {
    pub memory: String,
    pub clock: String,
    pub addr: ExprDef,
    pub data: String,
    #[serde(default)]
    pub enable: Option<ExprDef>,
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
    #[serde(default)]
    pub memories: Vec<MemoryDef>,
    #[serde(default)]
    pub write_ports: Vec<WritePortDef>,
    #[serde(default)]
    pub sync_read_ports: Vec<SyncReadPortDef>,
}

#[derive(Debug, Clone)]
struct ResolvedWritePort {
    memory_idx: usize,
    memory_depth: usize,
    memory_width: usize,
    clock_idx: usize,
    addr: ExprDef,
    data: ExprDef,
    enable: ExprDef,
}

#[derive(Debug, Clone)]
struct ResolvedSyncReadPort {
    memory_idx: usize,
    memory_width: usize,
    clock_idx: usize,
    addr: ExprDef,
    data_idx: usize,
    data_width: usize,
    enable: Option<ExprDef>,
}

// ============================================================================
// JIT-compiled function types
// ============================================================================

/// Function signature for evaluate: fn(signals: *mut u64, mem_ptrs: *const *const u64) -> ()
pub type EvaluateFn = unsafe extern "C" fn(*mut u64, *const *const u64);

/// Function signature for tick: fn(signals: *mut u64, next_regs: *mut u64, mem_ptrs: *const *const u64) -> ()
pub type TickFn = unsafe extern "C" fn(*mut u64, *mut u64, *const *const u64);

// ============================================================================
// Cranelift JIT Compiler
// ============================================================================

pub struct JitCompiler {
    /// Cranelift JIT module
    module: JITModule,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Memory name to index mapping
    mem_name_to_idx: HashMap<String, usize>,
    /// Memory depths (for bounds checking)
    mem_depths: Vec<usize>,
}

impl JitCompiler {
    pub fn new() -> Result<Self, String> {
        let mut flag_builder = settings::builder();
        flag_builder.set("opt_level", "speed").map_err(|e| e.to_string())?;
        flag_builder.set("is_pic", "false").map_err(|e| e.to_string())?;

        let isa_builder = cranelift_native::builder()
            .map_err(|e| format!("Failed to create ISA builder: {}", e))?;
        let isa = isa_builder
            .finish(settings::Flags::new(flag_builder))
            .map_err(|e| format!("Failed to create ISA: {}", e))?;

        let builder = JITBuilder::with_isa(isa, cranelift_module::default_libcall_names());
        let module = JITModule::new(builder);

        Ok(Self {
            module,
            name_to_idx: HashMap::new(),
            widths: Vec::new(),
            mem_name_to_idx: HashMap::new(),
            mem_depths: Vec::new(),
        })
    }

    pub fn set_mappings(
        &mut self,
        name_to_idx: HashMap<String, usize>,
        widths: Vec<usize>,
        mem_name_to_idx: HashMap<String, usize>,
        mem_depths: Vec<usize>,
    ) {
        self.name_to_idx = name_to_idx;
        self.widths = widths;
        self.mem_name_to_idx = mem_name_to_idx;
        self.mem_depths = mem_depths;
    }

    fn compile_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    /// Compile an expression, returning the Cranelift value
    fn compile_expr(
        &self,
        builder: &mut FunctionBuilder,
        expr: &ExprDef,
        signals_ptr: cranelift::prelude::Value,
        mem_ptrs: &[cranelift::prelude::Value],
    ) -> cranelift::prelude::Value {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = *self.name_to_idx.get(name).unwrap_or(&0);
                let offset = (idx * 8) as i32;
                builder.ins().load(types::I64, MemFlags::trusted(), signals_ptr, offset)
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compile_mask(*width);
                let masked = (*value as u64) & mask;
                builder.ins().iconst(types::I64, masked as i64)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.compile_expr(builder, operand, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);

                match op.as_str() {
                    "~" | "not" => {
                        let not_val = builder.ins().bnot(src);
                        builder.ins().band(not_val, mask_val)
                    }
                    "&" | "reduce_and" => {
                        let op_width = Self::expr_width(operand, &self.widths, &self.name_to_idx);
                        let op_mask = Self::compile_mask(op_width);
                        let op_mask_val = builder.ins().iconst(types::I64, op_mask as i64);
                        let masked = builder.ins().band(src, op_mask_val);
                        let cmp = builder.ins().icmp(IntCC::Equal, masked, op_mask_val);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    "|" | "reduce_or" => {
                        let zero = builder.ins().iconst(types::I64, 0);
                        let cmp = builder.ins().icmp(IntCC::NotEqual, src, zero);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    "^" | "reduce_xor" => {
                        let popcnt = builder.ins().popcnt(src);
                        let one = builder.ins().iconst(types::I64, 1);
                        builder.ins().band(popcnt, one)
                    }
                    _ => src,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.compile_expr(builder, left, signals_ptr, mem_ptrs);
                let r = self.compile_expr(builder, right, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);

                let result = match op.as_str() {
                    "&" => builder.ins().band(l, r),
                    "|" => builder.ins().bor(l, r),
                    "^" => builder.ins().bxor(l, r),
                    "+" => builder.ins().iadd(l, r),
                    "-" => builder.ins().isub(l, r),
                    "*" => builder.ins().imul(l, r),
                    "/" => {
                        let zero = builder.ins().iconst(types::I64, 0);
                        let one = builder.ins().iconst(types::I64, 1);
                        let is_zero = builder.ins().icmp(IntCC::Equal, r, zero);
                        let safe_r = builder.ins().select(is_zero, one, r);
                        let div_result = builder.ins().udiv(l, safe_r);
                        builder.ins().select(is_zero, zero, div_result)
                    }
                    "%" => {
                        let zero = builder.ins().iconst(types::I64, 0);
                        let one = builder.ins().iconst(types::I64, 1);
                        let is_zero = builder.ins().icmp(IntCC::Equal, r, zero);
                        let safe_r = builder.ins().select(is_zero, one, r);
                        let mod_result = builder.ins().urem(l, safe_r);
                        builder.ins().select(is_zero, zero, mod_result)
                    }
                    "<<" => {
                        let shift = builder.ins().ireduce(types::I32, r);
                        builder.ins().ishl(l, shift)
                    }
                    ">>" => {
                        let shift = builder.ins().ireduce(types::I32, r);
                        builder.ins().ushr(l, shift)
                    }
                    "==" => {
                        let cmp = builder.ins().icmp(IntCC::Equal, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    "!=" => {
                        let cmp = builder.ins().icmp(IntCC::NotEqual, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    "<" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedLessThan, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    ">" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedGreaterThan, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    "<=" | "le" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedLessThanOrEqual, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    ">=" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedGreaterThanOrEqual, l, r);
                        builder.ins().uextend(types::I64, cmp)
                    }
                    _ => l,
                };

                builder.ins().band(result, mask_val)
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.compile_expr(builder, condition, signals_ptr, mem_ptrs);
                let t = self.compile_expr(builder, when_true, signals_ptr, mem_ptrs);
                let f = self.compile_expr(builder, when_false, signals_ptr, mem_ptrs);

                let zero = builder.ins().iconst(types::I64, 0);
                let cond_bool = builder.ins().icmp(IntCC::NotEqual, cond, zero);
                let result = builder.ins().select(cond_bool, t, f);

                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);
                builder.ins().band(result, mask_val)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = self.compile_expr(builder, base, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);
                let shift = builder.ins().iconst(types::I32, *low as i64);
                let shifted = builder.ins().ushr(src, shift);
                builder.ins().band(shifted, mask_val)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = builder.ins().iconst(types::I64, 0);
                let mut shift_acc = 0u64;

                for part in parts.iter().rev() {
                    let part_val = self.compile_expr(builder, part, signals_ptr, mem_ptrs);
                    let part_width = Self::expr_width(part, &self.widths, &self.name_to_idx);
                    let part_mask = Self::compile_mask(part_width);
                    let mask_val = builder.ins().iconst(types::I64, part_mask as i64);
                    let masked = builder.ins().band(part_val, mask_val);

                    if shift_acc > 0 {
                        let shift = builder.ins().iconst(types::I32, shift_acc as i64);
                        let shifted = builder.ins().ishl(masked, shift);
                        result = builder.ins().bor(result, shifted);
                    } else {
                        result = builder.ins().bor(result, masked);
                    }

                    shift_acc += part_width as u64;
                }

                let final_mask = Self::compile_mask(*width);
                let final_mask_val = builder.ins().iconst(types::I64, final_mask as i64);
                builder.ins().band(result, final_mask_val)
            }
            ExprDef::Resize { expr, width } => {
                let src = self.compile_expr(builder, expr, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);
                builder.ins().band(src, mask_val)
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = *self.mem_name_to_idx.get(memory).unwrap_or(&0);
                let depth = self.mem_depths.get(mem_idx).copied().unwrap_or(256);

                let addr_val = self.compile_expr(builder, addr, signals_ptr, mem_ptrs);

                if mem_idx < mem_ptrs.len() {
                    let mem_ptr = mem_ptrs[mem_idx];

                    let depth_val = builder.ins().iconst(types::I64, depth as i64);
                    let bounded_addr = builder.ins().urem(addr_val, depth_val);

                    let eight = builder.ins().iconst(types::I64, 8);
                    let byte_offset = builder.ins().imul(bounded_addr, eight);

                    let elem_ptr = builder.ins().iadd(mem_ptr, byte_offset);

                    let loaded = builder.ins().load(types::I64, MemFlags::trusted(), elem_ptr, 0);

                    let mask = Self::compile_mask(*width);
                    let mask_val = builder.ins().iconst(types::I64, mask as i64);
                    builder.ins().band(loaded, mask_val)
                } else {
                    builder.ins().iconst(types::I64, 0)
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

    /// Extract signal indices that an expression depends on
    fn expr_dependencies(&self, expr: &ExprDef) -> HashSet<usize> {
        let mut deps = HashSet::new();
        self.collect_expr_deps(expr, &mut deps);
        deps
    }

    fn collect_expr_deps(&self, expr: &ExprDef, deps: &mut HashSet<usize>) {
        match expr {
            ExprDef::Signal { name, .. } => {
                if let Some(&idx) = self.name_to_idx.get(name) {
                    deps.insert(idx);
                }
            }
            ExprDef::Literal { .. } => {}
            ExprDef::UnaryOp { operand, .. } => {
                self.collect_expr_deps(operand, deps);
            }
            ExprDef::BinaryOp { left, right, .. } => {
                self.collect_expr_deps(left, deps);
                self.collect_expr_deps(right, deps);
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                self.collect_expr_deps(condition, deps);
                self.collect_expr_deps(when_true, deps);
                self.collect_expr_deps(when_false, deps);
            }
            ExprDef::Slice { base, .. } => {
                self.collect_expr_deps(base, deps);
            }
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    self.collect_expr_deps(part, deps);
                }
            }
            ExprDef::Resize { expr, .. } => {
                self.collect_expr_deps(expr, deps);
            }
            ExprDef::MemRead { addr, .. } => {
                self.collect_expr_deps(addr, deps);
            }
        }
    }

    /// Group assignments into levels based on dependencies (topological sort)
    fn compute_assignment_levels(&self, assigns: &[AssignDef]) -> Vec<Vec<usize>> {
        let n = assigns.len();

        let mut target_to_assign: HashMap<usize, usize> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                target_to_assign.insert(idx, i);
            }
        }

        let mut assign_deps: Vec<HashSet<usize>> = Vec::with_capacity(n);
        for assign in assigns {
            let signal_deps = self.expr_dependencies(&assign.expr);
            let mut deps = HashSet::new();
            for sig_idx in signal_deps {
                if let Some(&assign_idx) = target_to_assign.get(&sig_idx) {
                    deps.insert(assign_idx);
                }
            }
            assign_deps.push(deps);
        }

        let mut levels: Vec<Vec<usize>> = Vec::new();
        let mut assigned_level: Vec<Option<usize>> = vec![None; n];

        loop {
            let mut made_progress = false;
            for i in 0..n {
                if assigned_level[i].is_some() {
                    continue;
                }
                let mut max_dep_level = None;
                let mut all_deps_ready = true;
                for &dep_idx in &assign_deps[i] {
                    if dep_idx == i {
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

        levels
    }

    /// Compile the evaluate function
    pub fn compile_evaluate(&mut self, assigns: &[AssignDef], num_memories: usize) -> Result<EvaluateFn, String> {
        let mut ctx = self.module.make_context();
        let pointer_type = self.module.target_config().pointer_type();

        let mut sig = self.module.make_signature();
        sig.params.push(AbiParam::new(pointer_type));
        sig.params.push(AbiParam::new(pointer_type));

        ctx.func.signature = sig;

        let func_id = self.module
            .declare_function("evaluate", Linkage::Export, &ctx.func.signature)
            .map_err(|e| e.to_string())?;

        let mut builder_ctx = FunctionBuilderContext::new();
        let mut builder = FunctionBuilder::new(&mut ctx.func, &mut builder_ctx);

        let entry_block = builder.create_block();
        builder.append_block_params_for_function_params(entry_block);
        builder.switch_to_block(entry_block);
        builder.seal_block(entry_block);

        let signals_ptr = builder.block_params(entry_block)[0];
        let mem_ptrs_base = builder.block_params(entry_block)[1];

        let mut mem_ptrs: Vec<cranelift::prelude::Value> = Vec::new();
        for i in 0..num_memories {
            let offset = (i * 8) as i32;
            let mem_ptr = builder.ins().load(pointer_type, MemFlags::trusted(), mem_ptrs_base, offset);
            mem_ptrs.push(mem_ptr);
        }

        let levels = self.compute_assignment_levels(assigns);
        for level in &levels {
            for &assign_idx in level {
                let assign = &assigns[assign_idx];
                let target_idx = match self.name_to_idx.get(&assign.target) {
                    Some(&idx) => idx,
                    None => continue,
                };
                let value = self.compile_expr(&mut builder, &assign.expr, signals_ptr, &mem_ptrs);

                let offset = (target_idx * 8) as i32;
                builder.ins().store(MemFlags::trusted(), value, signals_ptr, offset);
            }
        }

        builder.ins().return_(&[]);
        builder.finalize();

        self.module.define_function(func_id, &mut ctx)
            .map_err(|e| e.to_string())?;
        self.module.clear_context(&mut ctx);
        self.module.finalize_definitions()
            .map_err(|e| e.to_string())?;

        let code_ptr = self.module.get_finalized_function(func_id);
        Ok(unsafe { mem::transmute::<*const u8, EvaluateFn>(code_ptr) })
    }

    /// Compile sequential assignment sampling function
    pub fn compile_seq_sample(&mut self, seq_assigns: &[(String, ExprDef)], num_memories: usize) -> Result<TickFn, String> {
        let mut ctx = self.module.make_context();
        let pointer_type = self.module.target_config().pointer_type();

        let mut sig = self.module.make_signature();
        sig.params.push(AbiParam::new(pointer_type));
        sig.params.push(AbiParam::new(pointer_type));
        sig.params.push(AbiParam::new(pointer_type));

        ctx.func.signature = sig;

        let func_id = self.module
            .declare_function("seq_sample", Linkage::Export, &ctx.func.signature)
            .map_err(|e| e.to_string())?;

        let mut builder_ctx = FunctionBuilderContext::new();
        let mut builder = FunctionBuilder::new(&mut ctx.func, &mut builder_ctx);

        let entry_block = builder.create_block();
        builder.append_block_params_for_function_params(entry_block);
        builder.switch_to_block(entry_block);
        builder.seal_block(entry_block);

        let signals_ptr = builder.block_params(entry_block)[0];
        let next_regs_ptr = builder.block_params(entry_block)[1];
        let mem_ptrs_base = builder.block_params(entry_block)[2];

        let mut mem_ptrs: Vec<cranelift::prelude::Value> = Vec::new();
        for i in 0..num_memories {
            let offset = (i * 8) as i32;
            let mem_ptr = builder.ins().load(pointer_type, MemFlags::trusted(), mem_ptrs_base, offset);
            mem_ptrs.push(mem_ptr);
        }

        for (i, (_target, expr)) in seq_assigns.iter().enumerate() {
            let value = self.compile_expr(&mut builder, expr, signals_ptr, &mem_ptrs);
            let offset = (i * 8) as i32;
            builder.ins().store(MemFlags::trusted(), value, next_regs_ptr, offset);
        }

        builder.ins().return_(&[]);
        builder.finalize();

        self.module.define_function(func_id, &mut ctx)
            .map_err(|e| e.to_string())?;
        self.module.clear_context(&mut ctx);
        self.module.finalize_definitions()
            .map_err(|e| e.to_string())?;

        let code_ptr = self.module.get_finalized_function(func_id);
        Ok(unsafe { mem::transmute::<*const u8, TickFn>(code_ptr) })
    }
}

// ============================================================================
// Core JIT Simulator
// ============================================================================

pub struct CoreSimulator {
    /// Signal values
    pub signals: Vec<u64>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Next register values buffer
    pub next_regs: Vec<u64>,
    /// Sequential assignment target indices
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// Unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Previous clock values (for edge detection)
    pub prev_clock_values: Vec<u64>,

    /// JIT-compiled evaluate function
    evaluate_fn: EvaluateFn,
    /// JIT-compiled sequential sample function
    seq_sample_fn: TickFn,

    /// Memory arrays (for mem_read operations)
    pub memory_arrays: Vec<Vec<u64>>,
    /// Memory reset snapshots
    memory_reset_arrays: Vec<Vec<u64>>,
    /// Memory name to index mapping
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Memory write ports
    write_ports: Vec<ResolvedWritePort>,
    /// Memory synchronous read ports
    sync_read_ports: Vec<ResolvedSyncReadPort>,

    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
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

        // Registers (with reset values)
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

        // Collect sequential assignments with clock domain information
        let mut seq_assigns: Vec<(String, ExprDef)> = Vec::new();
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_set: std::collections::HashSet<usize> = std::collections::HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|clk_name| name_to_idx.get(clk_name).copied())
                .unwrap_or(0);
            clock_set.insert(clock_idx);

            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                seq_assigns.push((stmt.target.clone(), stmt.expr.clone()));
                seq_targets.push(target_idx);
                seq_clocks.push(clock_idx);
            }
        }

        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let prev_clock_values = vec![0u64; clock_indices.len()];

        let next_regs = vec![0u64; seq_targets.len()];

        // Build memory arrays
        let mut memory_arrays: Vec<Vec<u64>> = Vec::new();
        let mut mem_name_to_idx: HashMap<String, usize> = HashMap::new();
        let mut mem_depths: Vec<usize> = Vec::new();
        let mut mem_widths: Vec<usize> = Vec::new();

        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val;
                }
            }
            memory_arrays.push(data);
            mem_name_to_idx.insert(mem.name.clone(), idx);
            mem_depths.push(mem.depth);
            mem_widths.push(mem.width);
        }

        let memory_reset_arrays = memory_arrays.clone();
        let num_memories = memory_arrays.len();

        let mut write_ports: Vec<ResolvedWritePort> = Vec::new();
        for wp in &ir.write_ports {
            let Some(&memory_idx) = mem_name_to_idx.get(&wp.memory) else {
                continue;
            };
            let Some(&clock_idx) = name_to_idx.get(&wp.clock) else {
                continue;
            };
            write_ports.push(ResolvedWritePort {
                memory_idx,
                memory_depth: *mem_depths.get(memory_idx).unwrap_or(&0),
                memory_width: *mem_widths.get(memory_idx).unwrap_or(&64),
                clock_idx,
                addr: wp.addr.clone(),
                data: wp.data.clone(),
                enable: wp.enable.clone(),
            });
        }

        let mut sync_read_ports: Vec<ResolvedSyncReadPort> = Vec::new();
        for rp in &ir.sync_read_ports {
            let Some(&memory_idx) = mem_name_to_idx.get(&rp.memory) else {
                continue;
            };
            let Some(&clock_idx) = name_to_idx.get(&rp.clock) else {
                continue;
            };
            let Some(&data_idx) = name_to_idx.get(&rp.data) else {
                continue;
            };
            sync_read_ports.push(ResolvedSyncReadPort {
                memory_idx,
                memory_width: *mem_widths.get(memory_idx).unwrap_or(&64),
                clock_idx,
                addr: rp.addr.clone(),
                data_idx,
                data_width: *widths.get(data_idx).unwrap_or(&64),
                enable: rp.enable.clone(),
            });
        }

        // Create JIT compiler and compile functions
        let mut compiler = JitCompiler::new()?;
        compiler.set_mappings(name_to_idx.clone(), widths.clone(), mem_name_to_idx.clone(), mem_depths);

        let evaluate_fn = compiler.compile_evaluate(&ir.assigns, num_memories)?;
        let seq_sample_fn = compiler.compile_seq_sample(&seq_assigns, num_memories)?;

        Ok(Self {
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            signal_count,
            reg_count,
            next_regs,
            seq_targets,
            seq_clocks,
            clock_indices,
            prev_clock_values,
            evaluate_fn,
            seq_sample_fn,
            memory_arrays,
            memory_reset_arrays,
            memory_name_to_idx: mem_name_to_idx,
            write_ports,
            sync_read_ports,
            reset_values,
        })
    }

    fn compute_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    fn runtime_expr_width(expr: &ExprDef, widths: &[usize], name_to_idx: &HashMap<String, usize>) -> usize {
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

    fn eval_expr_runtime(&self, expr: &ExprDef) -> u64 {
        match expr {
            ExprDef::Signal { name, width } => {
                let val = self.name_to_idx.get(name)
                    .and_then(|&idx| self.signals.get(idx).copied())
                    .unwrap_or(0);
                val & Self::compute_mask(*width)
            }
            ExprDef::Literal { value, width } => (*value as u64) & Self::compute_mask(*width),
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.eval_expr_runtime(operand);
                let mask = Self::compute_mask(*width);
                match op.as_str() {
                    "~" | "not" => (!src) & mask,
                    "&" | "reduce_and" => {
                        let op_width = Self::runtime_expr_width(operand, &self.widths, &self.name_to_idx);
                        let op_mask = Self::compute_mask(op_width);
                        if (src & op_mask) == op_mask { 1 } else { 0 }
                    }
                    "|" | "reduce_or" => if src != 0 { 1 } else { 0 },
                    "^" | "reduce_xor" => (src.count_ones() as u64) & 1,
                    _ => src & mask,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr_runtime(left);
                let r = self.eval_expr_runtime(right);
                let mask = Self::compute_mask(*width);
                let result = match op.as_str() {
                    "&" => l & r,
                    "|" => l | r,
                    "^" => l ^ r,
                    "+" => l.wrapping_add(r),
                    "-" => l.wrapping_sub(r),
                    "*" => l.wrapping_mul(r),
                    "/" => if r == 0 { 0 } else { l / r },
                    "%" => if r == 0 { 0 } else { l % r },
                    "<<" => if r >= 64 { 0 } else { l << r },
                    ">>" => if r >= 64 { 0 } else { l >> r },
                    "==" => if l == r { 1 } else { 0 },
                    "!=" => if l != r { 1 } else { 0 },
                    "<" => if l < r { 1 } else { 0 },
                    ">" => if l > r { 1 } else { 0 },
                    "<=" | "le" => if l <= r { 1 } else { 0 },
                    ">=" => if l >= r { 1 } else { 0 },
                    _ => l,
                };
                result & mask
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.eval_expr_runtime(condition);
                let selected = if cond != 0 {
                    self.eval_expr_runtime(when_true)
                } else {
                    self.eval_expr_runtime(when_false)
                };
                selected & Self::compute_mask(*width)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_val = self.eval_expr_runtime(base);
                let shifted = if *low >= 64 { 0 } else { base_val >> (*low as u64) };
                shifted & Self::compute_mask(*width)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = 0u64;
                for part in parts {
                    let part_width = Self::runtime_expr_width(part, &self.widths, &self.name_to_idx);
                    let part_val = self.eval_expr_runtime(part) & Self::compute_mask(part_width);
                    result = if part_width >= 64 { 0 } else { result << part_width };
                    result |= part_val;
                    result &= Self::compute_mask(*width);
                }
                result & Self::compute_mask(*width)
            }
            ExprDef::Resize { expr, width } => self.eval_expr_runtime(expr) & Self::compute_mask(*width),
            ExprDef::MemRead { memory, addr, width } => {
                let Some(&memory_idx) = self.memory_name_to_idx.get(memory) else {
                    return 0;
                };
                let Some(mem) = self.memory_arrays.get(memory_idx) else {
                    return 0;
                };
                if mem.is_empty() {
                    return 0;
                }
                let addr_val = self.eval_expr_runtime(addr) as usize % mem.len();
                mem[addr_val] & Self::compute_mask(*width)
            }
        }
    }

    fn apply_write_ports_level(&mut self) {
        if self.write_ports.is_empty() {
            return;
        }

        let mut writes: Vec<(usize, usize, u64)> = Vec::new();
        for wp in &self.write_ports {
            if self.signals.get(wp.clock_idx).copied().unwrap_or(0) == 0 {
                continue;
            }
            if (self.eval_expr_runtime(&wp.enable) & 1) == 0 {
                continue;
            }
            if wp.memory_depth == 0 {
                continue;
            }

            let addr = (self.eval_expr_runtime(&wp.addr) as usize) % wp.memory_depth;
            let data = self.eval_expr_runtime(&wp.data) & Self::compute_mask(wp.memory_width);
            writes.push((wp.memory_idx, addr, data));
        }

        for (memory_idx, addr, data) in writes {
            if let Some(mem) = self.memory_arrays.get_mut(memory_idx) {
                if addr < mem.len() {
                    mem[addr] = data;
                }
            }
        }
    }

    fn apply_sync_read_ports_level(&mut self) {
        if self.sync_read_ports.is_empty() {
            return;
        }

        let mut updates: Vec<(usize, u64)> = Vec::new();
        for rp in &self.sync_read_ports {
            if self.signals.get(rp.clock_idx).copied().unwrap_or(0) == 0 {
                continue;
            }
            if let Some(enable) = &rp.enable {
                if (self.eval_expr_runtime(enable) & 1) == 0 {
                    continue;
                }
            }

            let Some(mem) = self.memory_arrays.get(rp.memory_idx) else {
                continue;
            };
            if mem.is_empty() {
                continue;
            }

            let addr = (self.eval_expr_runtime(&rp.addr) as usize) % mem.len();
            let data = mem[addr] & Self::compute_mask(rp.memory_width);
            updates.push((rp.data_idx, data & Self::compute_mask(rp.data_width)));
        }

        for (idx, value) in updates {
            if idx < self.signals.len() {
                self.signals[idx] = value;
            }
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
    pub fn poke_by_idx(&mut self, idx: usize, value: u64) {
        if idx < self.signals.len() {
            let mask = Self::compute_mask(self.widths[idx]);
            self.signals[idx] = value & mask;
        }
    }

    #[inline(always)]
    pub fn peek_by_idx(&self, idx: usize) -> u64 {
        if idx < self.signals.len() {
            self.signals[idx]
        } else {
            0
        }
    }

    pub fn get_signal_idx(&self, name: &str) -> Option<usize> {
        self.name_to_idx.get(name).copied()
    }

    #[inline(always)]
    pub fn evaluate(&mut self) {
        let mem_ptrs: Vec<*const u64> = self.memory_arrays.iter()
            .map(|arr| arr.as_ptr())
            .collect();
        unsafe {
            (self.evaluate_fn)(
                self.signals.as_mut_ptr(),
                mem_ptrs.as_ptr()
            );
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

        // Evaluate to propagate any external input changes (including clock)
        self.evaluate();
        self.apply_write_ports_level();

        // Sample ALL register input expressions ONCE
        let mem_ptrs: Vec<*const u64> = self.memory_arrays.iter()
            .map(|arr| arr.as_ptr())
            .collect();
        unsafe {
            (self.seq_sample_fn)(
                self.signals.as_mut_ptr(),
                self.next_regs.as_mut_ptr(),
                mem_ptrs.as_ptr()
            );
        }

        let mut updated: Vec<bool> = vec![false; self.seq_targets.len()];
        let max_iterations = 10;

        // Detect rising edges using prev_clock_values as "before"
        let mut rising_clocks: Vec<bool> = vec![false; self.signals.len()];
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            let before = self.prev_clock_values[i];
            let after = self.signals[clk_idx];
            if before == 0 && after == 1 {
                rising_clocks[clk_idx] = true;
            }
        }

        // Apply updates for clocks that rose
        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
            let clk_idx = self.seq_clocks[i];
            if rising_clocks[clk_idx] && !updated[i] {
                self.signals[target_idx] = self.next_regs[i];
                updated[i] = true;
            }
        }

        // Iterate for derived clocks
        for _iteration in 0..max_iterations {
            let mut clock_before: Vec<u64> = Vec::with_capacity(self.clock_indices.len());
            for &clk_idx in &self.clock_indices {
                clock_before.push(self.signals[clk_idx]);
            }

            self.evaluate();

            let mut rising_clocks: Vec<bool> = vec![false; self.signals.len()];
            let mut any_rising = false;
            for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
                let before = clock_before[i];
                let after = self.signals[clk_idx];
                if before == 0 && after == 1 {
                    rising_clocks[clk_idx] = true;
                    any_rising = true;
                }
            }

            if !any_rising {
                break;
            }

            for (i, &target_idx) in self.seq_targets.iter().enumerate() {
                let clk_idx = self.seq_clocks[i];
                if rising_clocks[clk_idx] && !updated[i] {
                    self.signals[target_idx] = self.next_regs[i];
                    updated[i] = true;
                }
            }
        }

        // prev_clock_values is saved at the start of tick(), not here
        // This ensures we capture the clock values BEFORE evaluate propagates them

        self.apply_sync_read_ports_level();
        self.evaluate();
    }

    /// Tick with forced edge detection using prev_clock_values
    /// This is used by extensions that manually control the clock sequence
    /// and set prev_clock_values before calling this function.
    #[inline(always)]
    pub fn tick_forced(&mut self) {
        // Use prev_clock_values as "before" values (set by caller)
        // instead of sampling from signals

        // Evaluate to propagate external input changes
        self.evaluate();
        self.apply_write_ports_level();

        // Sample ALL register input expressions ONCE
        let mem_ptrs: Vec<*const u64> = self.memory_arrays.iter()
            .map(|arr| arr.as_ptr())
            .collect();
        unsafe {
            (self.seq_sample_fn)(
                self.signals.as_mut_ptr(),
                self.next_regs.as_mut_ptr(),
                mem_ptrs.as_ptr()
            );
        }

        let mut updated: Vec<bool> = vec![false; self.seq_targets.len()];
        let max_iterations = 10;

        // Detect rising edges using prev_clock_values (set by caller)
        let mut rising_clocks: Vec<bool> = vec![false; self.signals.len()];
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            let before = self.prev_clock_values[i];
            let after = self.signals[clk_idx];
            if before == 0 && after == 1 {
                rising_clocks[clk_idx] = true;
            }
        }

        // Apply updates for clocks that rose
        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
            let clk_idx = self.seq_clocks[i];
            if rising_clocks[clk_idx] && !updated[i] {
                self.signals[target_idx] = self.next_regs[i];
                updated[i] = true;
            }
        }

        // Iterate for derived clocks
        for _iteration in 0..max_iterations {
            let mut clock_before: Vec<u64> = Vec::with_capacity(self.clock_indices.len());
            for &clk_idx in &self.clock_indices {
                clock_before.push(self.signals[clk_idx]);
            }

            self.evaluate();

            let mut rising_clocks: Vec<bool> = vec![false; self.signals.len()];
            let mut any_rising = false;
            for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
                let before = clock_before[i];
                let after = self.signals[clk_idx];
                if before == 0 && after == 1 {
                    rising_clocks[clk_idx] = true;
                    any_rising = true;
                }
            }

            if !any_rising {
                break;
            }

            for (i, &target_idx) in self.seq_targets.iter().enumerate() {
                let clk_idx = self.seq_clocks[i];
                if rising_clocks[clk_idx] && !updated[i] {
                    self.signals[target_idx] = self.next_regs[i];
                    updated[i] = true;
                }
            }
        }

        // Update prev_clock_values to current values for next cycle
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }

        self.apply_sync_read_ports_level();
        self.evaluate();
    }

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
        for val in self.prev_clock_values.iter_mut() {
            *val = 0;
        }
        for (mem, initial) in self.memory_arrays.iter_mut().zip(self.memory_reset_arrays.iter()) {
            mem.clone_from(initial);
        }
    }

    pub fn run_ticks(&mut self, n: usize) {
        for _ in 0..n {
            self.tick();
        }
    }

    pub fn signal_count(&self) -> usize {
        self.signal_count
    }

    pub fn reg_count(&self) -> usize {
        self.reg_count
    }
}
