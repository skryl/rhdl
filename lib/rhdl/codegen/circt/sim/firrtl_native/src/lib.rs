//! RTL-level FIRRTL/Behavior IR simulator with Ruby bindings
//!
//! This simulator evaluates Behavior IR at the RTL level, providing faster
//! simulation than gate-level netlist simulation by operating on whole words
//! instead of individual bits.
//!
//! Supports:
//! - Combinational assignments (wires)
//! - Sequential processes (registers with clock/reset)
//! - Binary operations (+, -, *, /, %, &, |, ^, ==, !=, <, >, <=, >=, <<, >>)
//! - Unary operations (~, reduction AND/OR/XOR)
//! - Mux expressions
//! - Slice/concat operations
//! - Memory arrays

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

/// Expression types
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum Expr {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
    UnaryOp { op: String, operand: Box<Expr>, width: usize },
    BinaryOp { op: String, left: Box<Expr>, right: Box<Expr>, width: usize },
    Mux { condition: Box<Expr>, when_true: Box<Expr>, when_false: Box<Expr>, width: usize },
    Slice { base: Box<Expr>, low: usize, high: usize, width: usize },
    Concat { parts: Vec<Expr>, width: usize },
    Resize { expr: Box<Expr>, width: usize },
}

/// Assignment (combinational)
#[derive(Debug, Clone, Deserialize)]
struct AssignDef {
    target: String,
    expr: Expr,
}

/// Sequential assignment
#[derive(Debug, Clone, Deserialize)]
struct SeqAssignDef {
    target: String,
    expr: Expr,
}

/// Process (sequential block)
#[derive(Debug, Clone, Deserialize)]
struct ProcessDef {
    name: String,
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
}

/// Complete module IR
#[derive(Debug, Clone, Deserialize)]
struct ModuleIR {
    name: String,
    ports: Vec<PortDef>,
    nets: Vec<NetDef>,
    regs: Vec<RegDef>,
    assigns: Vec<AssignDef>,
    processes: Vec<ProcessDef>,
    #[serde(default)]
    memories: Vec<MemoryDef>,
}

/// The RTL simulator
struct RtlSimulator {
    /// Signal values (ports, wires, registers)
    signals: HashMap<String, u64>,
    /// Signal widths
    widths: HashMap<String, usize>,
    /// Input port names
    inputs: Vec<String>,
    /// Output port names
    outputs: Vec<String>,
    /// Combinational assignments (in dependency order)
    assigns: Vec<AssignDef>,
    /// Sequential processes
    processes: Vec<ProcessDef>,
    /// Memories
    memories: HashMap<String, Vec<u64>>,
    /// Memory widths
    memory_widths: HashMap<String, usize>,
    /// Next register values (computed during tick)
    next_regs: HashMap<String, u64>,
}

impl RtlSimulator {
    fn new(json: &str) -> Result<Self, String> {
        let ir: ModuleIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse IR JSON: {}", e))?;

        let mut signals = HashMap::new();
        let mut widths = HashMap::new();
        let mut inputs = Vec::new();
        let mut outputs = Vec::new();

        // Initialize ports
        for port in &ir.ports {
            signals.insert(port.name.clone(), 0);
            widths.insert(port.name.clone(), port.width);
            match port.direction {
                Direction::In => inputs.push(port.name.clone()),
                Direction::Out => outputs.push(port.name.clone()),
            }
        }

        // Initialize wires
        for net in &ir.nets {
            signals.insert(net.name.clone(), 0);
            widths.insert(net.name.clone(), net.width);
        }

        // Initialize registers
        for reg in &ir.regs {
            signals.insert(reg.name.clone(), 0);
            widths.insert(reg.name.clone(), reg.width);
        }

        // Initialize memories
        let mut memories = HashMap::new();
        let mut memory_widths = HashMap::new();
        for mem in &ir.memories {
            memories.insert(mem.name.clone(), vec![0u64; mem.depth]);
            memory_widths.insert(mem.name.clone(), mem.width);
        }

        Ok(Self {
            signals,
            widths,
            inputs,
            outputs,
            assigns: ir.assigns,
            processes: ir.processes,
            memories,
            memory_widths,
            next_regs: HashMap::new(),
        })
    }

    fn mask(&self, width: usize) -> u64 {
        if width >= 64 {
            u64::MAX
        } else {
            (1u64 << width) - 1
        }
    }

    fn eval_expr(&self, expr: &Expr) -> u64 {
        match expr {
            Expr::Signal { name, width } => {
                self.signals.get(name).copied().unwrap_or(0) & self.mask(*width)
            }
            Expr::Literal { value, width } => {
                (*value as u64) & self.mask(*width)
            }
            Expr::UnaryOp { op, operand, width } => {
                let val = self.eval_expr(operand);
                let mask = self.mask(*width);
                match op.as_str() {
                    "~" | "not" => (!val) & mask,
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let op_mask = self.mask(op_width);
                        if (val & op_mask) == op_mask { 1 } else { 0 }
                    }
                    "|" | "reduce_or" => {
                        if val != 0 { 1 } else { 0 }
                    }
                    "^" | "reduce_xor" => {
                        (val.count_ones() & 1) as u64
                    }
                    _ => val,
                }
            }
            Expr::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr(left);
                let r = self.eval_expr(right);
                let mask = self.mask(*width);
                match op.as_str() {
                    "&" => l & r,
                    "|" => l | r,
                    "^" => l ^ r,
                    "+" => l.wrapping_add(r) & mask,
                    "-" => l.wrapping_sub(r) & mask,
                    "*" => l.wrapping_mul(r) & mask,
                    "/" => if r != 0 { l / r } else { 0 },
                    "%" => if r != 0 { l % r } else { 0 },
                    "<<" => (l << (r as u32).min(63)) & mask,
                    ">>" => l >> (r as u32).min(63),
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
                let mask = self.mask(*width);
                if cond != 0 {
                    self.eval_expr(when_true) & mask
                } else {
                    self.eval_expr(when_false) & mask
                }
            }
            Expr::Slice { base, low, high, width } => {
                let val = self.eval_expr(base);
                let mask = self.mask(*width);
                ((val >> low) & mask)
            }
            Expr::Concat { parts, width } => {
                let mut result = 0u64;
                let mut shift = 0;
                for part in parts {
                    let part_width = self.expr_width(part);
                    let part_val = self.eval_expr(part);
                    result |= (part_val & self.mask(part_width)) << shift;
                    shift += part_width;
                }
                result & self.mask(*width)
            }
            Expr::Resize { expr, width } => {
                self.eval_expr(expr) & self.mask(*width)
            }
        }
    }

    fn expr_width(&self, expr: &Expr) -> usize {
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

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        if !self.inputs.contains(&name.to_string()) {
            return Err(format!("Unknown input: {}", name));
        }
        let width = self.widths.get(name).copied().unwrap_or(64);
        self.signals.insert(name.to_string(), value & self.mask(width));
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        self.signals.get(name)
            .copied()
            .ok_or_else(|| format!("Unknown signal: {}", name))
    }

    fn evaluate(&mut self) {
        // Evaluate combinational assignments
        // TODO: Proper dependency ordering
        for _ in 0..10 {
            let mut changed = false;
            for assign in &self.assigns {
                let new_val = self.eval_expr(&assign.expr);
                let width = self.widths.get(&assign.target).copied().unwrap_or(64);
                let masked = new_val & self.mask(width);
                if self.signals.get(&assign.target) != Some(&masked) {
                    self.signals.insert(assign.target.clone(), masked);
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
    }

    fn tick(&mut self) {
        // First evaluate combinational logic
        self.evaluate();

        // Sample all register inputs
        self.next_regs.clear();
        for process in &self.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let new_val = self.eval_expr(&stmt.expr);
                let width = self.widths.get(&stmt.target).copied().unwrap_or(64);
                self.next_regs.insert(stmt.target.clone(), new_val & self.mask(width));
            }
        }

        // Update all registers
        for (name, val) in &self.next_regs {
            self.signals.insert(name.clone(), *val);
        }

        // Re-evaluate combinational logic with new register values
        self.evaluate();
    }

    fn reset(&mut self) {
        for (_, val) in self.signals.iter_mut() {
            *val = 0;
        }
        for mem in self.memories.values_mut() {
            mem.fill(0);
        }
    }

    fn signal_count(&self) -> usize {
        self.signals.len()
    }

    fn reg_count(&self) -> usize {
        self.processes.iter()
            .flat_map(|p| &p.statements)
            .count()
    }
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
        self.sim.borrow().inputs.clone()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().outputs.clone()
    }

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("signal_count"), sim.signal_count() as i64)?;
        hash.aset(ruby.sym_new("reg_count"), sim.reg_count() as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.inputs.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.outputs.len() as i64)?;
        hash.aset(ruby.sym_new("assign_count"), sim.assigns.len() as i64)?;
        hash.aset(ruby.sym_new("process_count"), sim.processes.len() as i64)?;

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
    class.define_method("stats", method!(RubyRtlSim::stats, 0))?;
    class.define_method("native?", method!(RubyRtlSim::native, 0))?;

    circt.const_set("FIRRTL_NATIVE_AVAILABLE", true)?;

    Ok(())
}
