//! Cranelift-based JIT compiler for RTL simulation
//!
//! This module generates native machine code at load time using Cranelift,
//! eliminating all interpretation dispatch overhead. The generated code
//! directly computes signal values with no runtime type checking or
//! indirect calls.
//!
//! Performance target: ~4M cycles/sec (80x faster than interpreter)

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::mem;

use cranelift::prelude::*;
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

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
// JIT-compiled function types
// ============================================================================

/// Function signature for evaluate: fn(signals: *mut u64) -> ()
type EvaluateFn = unsafe extern "C" fn(*mut u64);

/// Function signature for tick: fn(signals: *mut u64, next_regs: *mut u64) -> ()
type TickFn = unsafe extern "C" fn(*mut u64, *mut u64);

// ============================================================================
// Cranelift JIT Compiler
// ============================================================================

struct JitCompiler {
    /// Cranelift JIT module
    module: JITModule,
    /// Signal name to index mapping
    name_to_idx: HashMap<String, usize>,
    /// Signal widths
    widths: Vec<usize>,
}

impl JitCompiler {
    fn new() -> Result<Self, String> {
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
        })
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
    ) -> cranelift::prelude::Value {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = *self.name_to_idx.get(name).unwrap_or(&0);
                // Load signals[idx]
                let offset = (idx * 8) as i32;
                builder.ins().load(types::I64, MemFlags::trusted(), signals_ptr, offset)
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compile_mask(*width);
                let masked = (*value as u64) & mask;
                builder.ins().iconst(types::I64, masked as i64)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.compile_expr(builder, operand, signals_ptr);
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
                let l = self.compile_expr(builder, left, signals_ptr);
                let r = self.compile_expr(builder, right, signals_ptr);
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
                        // Check for zero divisor
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

                // Mask the result
                builder.ins().band(result, mask_val)
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                let cond = self.compile_expr(builder, condition, signals_ptr);
                let t = self.compile_expr(builder, when_true, signals_ptr);
                let f = self.compile_expr(builder, when_false, signals_ptr);

                let zero = builder.ins().iconst(types::I64, 0);
                let cond_bool = builder.ins().icmp(IntCC::NotEqual, cond, zero);
                builder.ins().select(cond_bool, t, f)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = self.compile_expr(builder, base, signals_ptr);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);
                let shift = builder.ins().iconst(types::I32, *low as i64);
                let shifted = builder.ins().ushr(src, shift);
                builder.ins().band(shifted, mask_val)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = builder.ins().iconst(types::I64, 0);
                let mut shift_acc = 0u64;

                for part in parts {
                    let part_val = self.compile_expr(builder, part, signals_ptr);
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
                let src = self.compile_expr(builder, expr, signals_ptr);
                let mask = Self::compile_mask(*width);
                let mask_val = builder.ins().iconst(types::I64, mask as i64);
                builder.ins().band(src, mask_val)
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

    /// Compile the evaluate function that runs all combinational logic
    fn compile_evaluate(&mut self, assigns: &[AssignDef]) -> Result<EvaluateFn, String> {
        let mut ctx = self.module.make_context();
        let pointer_type = self.module.target_config().pointer_type();

        // Function signature: fn(signals: *mut u64) -> ()
        let mut sig = self.module.make_signature();
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

        // Compile each assignment
        for assign in assigns {
            let target_idx = *self.name_to_idx.get(&assign.target).unwrap_or(&0);
            let value = self.compile_expr(&mut builder, &assign.expr, signals_ptr);

            // Store to signals[target_idx]
            let offset = (target_idx * 8) as i32;
            builder.ins().store(MemFlags::trusted(), value, signals_ptr, offset);
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
    fn compile_seq_sample(&mut self, seq_assigns: &[(String, ExprDef)]) -> Result<TickFn, String> {
        let mut ctx = self.module.make_context();
        let pointer_type = self.module.target_config().pointer_type();

        // Function signature: fn(signals: *mut u64, next_regs: *mut u64) -> ()
        let mut sig = self.module.make_signature();
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

        // Sample each sequential assignment
        for (i, (_target, expr)) in seq_assigns.iter().enumerate() {
            let value = self.compile_expr(&mut builder, expr, signals_ptr);
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
// JIT RTL Simulator
// ============================================================================

struct JitRtlSimulator {
    /// Signal values
    signals: Vec<u64>,
    /// Signal widths
    widths: Vec<usize>,
    /// Signal name to index mapping
    name_to_idx: HashMap<String, usize>,
    /// Input names
    input_names: Vec<String>,
    /// Output names
    output_names: Vec<String>,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Next register values buffer
    next_regs: Vec<u64>,
    /// Sequential assignment target indices
    seq_targets: Vec<usize>,

    /// JIT-compiled evaluate function
    evaluate_fn: EvaluateFn,
    /// JIT-compiled sequential sample function
    seq_sample_fn: TickFn,

    // Apple II specific: internalized memory
    ram: Vec<u8>,
    rom: Vec<u8>,
    ram_addr_idx: usize,
    ram_do_idx: usize,
    ram_we_idx: usize,
    d_idx: usize,
    clk_idx: usize,
    k_idx: usize,
    read_key_idx: usize,
    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
}

impl JitRtlSimulator {
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

        // Collect sequential assignments
        let mut seq_assigns: Vec<(String, ExprDef)> = Vec::new();
        let mut seq_targets = Vec::new();
        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                seq_assigns.push((stmt.target.clone(), stmt.expr.clone()));
                seq_targets.push(target_idx);
            }
        }

        let next_regs = vec![0u64; seq_targets.len()];

        // Create JIT compiler and compile functions
        let mut compiler = JitCompiler::new()?;
        compiler.name_to_idx = name_to_idx.clone();
        compiler.widths = widths.clone();

        let evaluate_fn = compiler.compile_evaluate(&ir.assigns)?;
        let seq_sample_fn = compiler.compile_seq_sample(&seq_assigns)?;

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
            signal_count,
            reg_count,
            next_regs,
            seq_targets,
            evaluate_fn,
            seq_sample_fn,
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx,
            ram_do_idx,
            ram_we_idx,
            d_idx,
            clk_idx,
            k_idx,
            read_key_idx,
            reset_values,
        })
    }

    fn compute_mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
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
        unsafe { (self.evaluate_fn)(self.signals.as_mut_ptr()); }
    }

    #[inline(always)]
    fn tick(&mut self) {
        // Evaluate combinational logic
        self.evaluate();

        // Sample register inputs using JIT function
        unsafe { (self.seq_sample_fn)(self.signals.as_mut_ptr(), self.next_regs.as_mut_ptr()); }

        // Update all registers
        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
            self.signals[target_idx] = self.next_regs[i];
        }

        // Re-evaluate combinational logic
        self.evaluate();
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

    /// Run a single 14MHz cycle with integrated memory handling
    #[inline(always)]
    fn run_14m_cycle_internal(&mut self, key_data: u8, key_ready: bool) -> (bool, bool) {
        // Set keyboard input
        let k_val = if key_ready { (key_data as u64) | 0x80 } else { 0 };
        self.signals[self.k_idx] = k_val;

        // Falling edge
        self.signals[self.clk_idx] = 0;
        self.evaluate();

        // Provide RAM/ROM data based on Apple II memory map:
        // $0000-$BFFF: RAM (48KB)
        // $C000-$CFFF: I/O space (soft switches, slot ROMs)
        // $D000-$FFFF: ROM (12KB)
        let ram_addr = self.signals[self.ram_addr_idx] as usize;
        let ram_data = if ram_addr >= 0xD000 {
            // ROM space
            let rom_offset = ram_addr.wrapping_sub(0xD000);
            if rom_offset < self.rom.len() { self.rom[rom_offset] } else { 0 }
        } else if ram_addr >= 0xC000 {
            // I/O space - return 0 (soft switches handled by HDL logic)
            0
        } else {
            // RAM space
            self.ram[ram_addr]
        };
        self.signals[self.ram_do_idx] = ram_data as u64;

        // Rising edge
        self.signals[self.clk_idx] = 1;
        self.tick();

        // Handle RAM writes
        let mut text_dirty = false;
        if self.signals[self.ram_we_idx] == 1 {
            let write_addr = self.signals[self.ram_addr_idx] as usize;
            if write_addr < 0xC000 {
                let data = (self.signals[self.d_idx] & 0xFF) as u8;
                self.ram[write_addr] = data;
                text_dirty = (0x0400..=0x07FF).contains(&write_addr);
            }
        }

        let key_cleared = self.signals[self.read_key_idx] == 1;
        (text_dirty, key_cleared)
    }

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

    /// Run N ticks with a single FFI call (general-purpose batched execution)
    #[inline(never)]
    fn run_ticks(&mut self, n: usize) {
        for _ in 0..n {
            self.tick();
        }
    }

    /// Poke by index - faster than by name for hot paths
    #[inline(always)]
    fn poke_by_idx(&mut self, idx: usize, value: u64) {
        if idx < self.signals.len() {
            let mask = Self::compute_mask(self.widths[idx]);
            self.signals[idx] = value & mask;
        }
    }

    /// Peek by index - faster than by name for hot paths
    #[inline(always)]
    fn peek_by_idx(&self, idx: usize) -> u64 {
        if idx < self.signals.len() {
            self.signals[idx]
        } else {
            0
        }
    }

    /// Get signal index by name (for caching)
    fn get_signal_idx(&self, name: &str) -> Option<usize> {
        self.name_to_idx.get(name).copied()
    }

    fn reset(&mut self) {
        for val in self.signals.iter_mut() {
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
}

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

#[magnus::wrap(class = "RHDL::Codegen::IR::IrJit")]
struct RubyJitSim {
    sim: RefCell<JitRtlSimulator>,
}

impl RubyJitSim {
    fn new(json: String) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = JitRtlSimulator::new(&json)
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
        hash.aset(ruby.sym_new("seq_assign_count"), sim.seq_targets.len() as i64)?;
        hash.aset(ruby.sym_new("backend"), "cranelift_jit")?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }

    /// Run N ticks with a single FFI call
    fn run_ticks(&self, n: usize) {
        self.sim.borrow_mut().run_ticks(n);
    }

    /// Get signal index by name (for caching indices)
    fn get_signal_idx(&self, name: String) -> Option<usize> {
        self.sim.borrow().get_signal_idx(&name)
    }

    /// Poke by index - faster than by name
    fn poke_by_idx(&self, idx: usize, value: Value) -> Result<(), Error> {
        let v = ruby_to_u64(value)?;
        self.sim.borrow_mut().poke_by_idx(idx, v);
        Ok(())
    }

    /// Peek by index - faster than by name
    fn peek_by_idx(&self, idx: usize) -> Result<Value, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let val = self.sim.borrow().peek_by_idx(idx);
        Ok(u64_to_ruby(&ruby, val))
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let ir = codegen.define_module("IR")?;

    let class = ir.define_class("IrJit", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyJitSim::new, 1))?;
    class.define_method("poke", method!(RubyJitSim::poke, 2))?;
    class.define_method("peek", method!(RubyJitSim::peek, 1))?;
    class.define_method("evaluate", method!(RubyJitSim::evaluate, 0))?;
    class.define_method("tick", method!(RubyJitSim::tick, 0))?;
    class.define_method("reset", method!(RubyJitSim::reset, 0))?;
    class.define_method("signal_count", method!(RubyJitSim::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyJitSim::reg_count, 0))?;
    class.define_method("input_names", method!(RubyJitSim::input_names, 0))?;
    class.define_method("output_names", method!(RubyJitSim::output_names, 0))?;
    class.define_method("load_rom", method!(RubyJitSim::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyJitSim::load_ram, 2))?;
    class.define_method("run_cpu_cycles", method!(RubyJitSim::run_cpu_cycles, 3))?;
    class.define_method("read_ram", method!(RubyJitSim::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyJitSim::write_ram, 2))?;
    class.define_method("stats", method!(RubyJitSim::stats, 0))?;
    class.define_method("native?", method!(RubyJitSim::native, 0))?;
    class.define_method("run_ticks", method!(RubyJitSim::run_ticks, 1))?;
    class.define_method("get_signal_idx", method!(RubyJitSim::get_signal_idx, 1))?;
    class.define_method("poke_by_idx", method!(RubyJitSim::poke_by_idx, 2))?;
    class.define_method("peek_by_idx", method!(RubyJitSim::peek_by_idx, 1))?;

    Ok(())
}
