//! Cranelift-based JIT compiler for gate-level netlist simulation
//!
//! This module compiles gate-level netlists to native machine code at load time
//! using Cranelift, eliminating interpretation dispatch overhead.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;
use std::mem;

use cranelift::prelude::*;
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

/// Gate types matching RHDL::Codegen::Structure::Primitives
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum GateType {
    And,
    Or,
    Xor,
    Not,
    Mux,
    Buf,
    Const,
}

/// Gate definition from JSON netlist
#[derive(Debug, Clone, Deserialize)]
struct GateDef {
    #[serde(rename = "type")]
    gate_type: GateType,
    inputs: Vec<usize>,
    output: usize,
    value: Option<i64>,
}

/// DFF definition from JSON netlist
#[derive(Debug, Clone, Deserialize)]
struct DffDef {
    d: usize,
    q: usize,
    rst: Option<usize>,
    en: Option<usize>,
    #[allow(dead_code)]
    async_reset: Option<bool>,
    #[serde(default)]
    reset_value: i64,
}

/// Complete netlist IR from JSON
#[derive(Debug, Clone, Deserialize)]
struct NetlistIR {
    #[allow(dead_code)]
    name: String,
    net_count: usize,
    gates: Vec<GateDef>,
    dffs: Vec<DffDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    schedule: Vec<usize>,
}

/// JIT-compiled function type: fn(nets: *mut u64, lane_mask: u64) -> ()
type EvaluateFn = unsafe extern "C" fn(*mut u64, u64);

/// JIT compiler for gate-level netlists
struct NetlistJitCompiler {
    module: JITModule,
}

impl NetlistJitCompiler {
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

        Ok(Self { module })
    }

    /// Compile the evaluate function for a netlist
    fn compile_evaluate(&mut self, ir: &NetlistIR) -> Result<EvaluateFn, String> {
        let mut ctx = self.module.make_context();
        let pointer_type = self.module.target_config().pointer_type();

        // Function signature: fn(nets: *mut u64, lane_mask: u64) -> ()
        let mut sig = self.module.make_signature();
        sig.params.push(AbiParam::new(pointer_type)); // nets ptr
        sig.params.push(AbiParam::new(types::I64));    // lane_mask

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

        let nets_ptr = builder.block_params(entry_block)[0];
        let lane_mask = builder.block_params(entry_block)[1];

        // Compile each gate in schedule order
        for &gate_idx in &ir.schedule {
            let gate = &ir.gates[gate_idx];
            self.compile_gate(&mut builder, gate, nets_ptr, lane_mask);
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

    fn compile_gate(
        &self,
        builder: &mut FunctionBuilder,
        gate: &GateDef,
        nets_ptr: cranelift::prelude::Value,
        lane_mask: cranelift::prelude::Value,
    ) {
        let out_offset = (gate.output * 8) as i32;

        let result = match gate.gate_type {
            GateType::And => {
                let in1 = self.load_net(builder, nets_ptr, gate.inputs[0]);
                let in2 = self.load_net(builder, nets_ptr, gate.inputs[1]);
                builder.ins().band(in1, in2)
            }
            GateType::Or => {
                let in1 = self.load_net(builder, nets_ptr, gate.inputs[0]);
                let in2 = self.load_net(builder, nets_ptr, gate.inputs[1]);
                builder.ins().bor(in1, in2)
            }
            GateType::Xor => {
                let in1 = self.load_net(builder, nets_ptr, gate.inputs[0]);
                let in2 = self.load_net(builder, nets_ptr, gate.inputs[1]);
                builder.ins().bxor(in1, in2)
            }
            GateType::Not => {
                let input = self.load_net(builder, nets_ptr, gate.inputs[0]);
                let not_val = builder.ins().bnot(input);
                builder.ins().band(not_val, lane_mask)
            }
            GateType::Mux => {
                // MUX: out = (a & ~sel) | (b & sel)
                let a = self.load_net(builder, nets_ptr, gate.inputs[0]);
                let b = self.load_net(builder, nets_ptr, gate.inputs[1]);
                let sel = self.load_net(builder, nets_ptr, gate.inputs[2]);
                let not_sel = builder.ins().bnot(sel);
                let a_part = builder.ins().band(a, not_sel);
                let b_part = builder.ins().band(b, sel);
                builder.ins().bor(a_part, b_part)
            }
            GateType::Buf => {
                self.load_net(builder, nets_ptr, gate.inputs[0])
            }
            GateType::Const => {
                if gate.value.unwrap_or(0) == 0 {
                    builder.ins().iconst(types::I64, 0)
                } else {
                    lane_mask
                }
            }
        };

        builder.ins().store(MemFlags::trusted(), result, nets_ptr, out_offset);
    }

    fn load_net(
        &self,
        builder: &mut FunctionBuilder,
        nets_ptr: cranelift::prelude::Value,
        net_idx: usize,
    ) -> cranelift::prelude::Value {
        let offset = (net_idx * 8) as i32;
        builder.ins().load(types::I64, MemFlags::trusted(), nets_ptr, offset)
    }
}

/// JIT-compiled netlist simulator
struct NetlistJitSimulator {
    nets: Vec<u64>,
    dffs: Vec<DffDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    lanes: usize,
    lane_mask: u64,
    evaluate_fn: EvaluateFn,
}

impl NetlistJitSimulator {
    fn new(json: &str, lanes: usize) -> Result<Self, String> {
        let ir: NetlistIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let lane_mask = if lanes >= 64 { u64::MAX } else { (1u64 << lanes) - 1 };

        // Compile the evaluate function
        let mut compiler = NetlistJitCompiler::new()?;
        let evaluate_fn = compiler.compile_evaluate(&ir)?;

        Ok(Self {
            nets: vec![0; ir.net_count],
            dffs: ir.dffs,
            inputs: ir.inputs,
            outputs: ir.outputs,
            lanes,
            lane_mask,
            evaluate_fn,
        })
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let nets = self.inputs.get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;
        for &net in nets {
            self.nets[net] = value & self.lane_mask;
        }
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        let nets = self.outputs.get(name)
            .ok_or_else(|| format!("Unknown output: {}", name))?;
        Ok(self.nets[nets[0]])
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        unsafe { (self.evaluate_fn)(self.nets.as_mut_ptr(), self.lane_mask); }
    }

    fn tick(&mut self) {
        self.evaluate();

        // Sample DFF inputs
        let next_q: Vec<u64> = self.dffs.iter().map(|dff| {
            let q = self.nets[dff.q];
            let d = self.nets[dff.d];
            let mut q_next = d;

            if let Some(en) = dff.en {
                let en_val = self.nets[en];
                q_next = (q & !en_val) | (d & en_val);
            }

            if let Some(rst) = dff.rst {
                let rst_val = self.nets[rst];
                let reset_target = if dff.reset_value == 0 { 0 } else { self.lane_mask };
                q_next = (q_next & !rst_val) | (rst_val & reset_target);
            }

            q_next
        }).collect();

        // Update DFFs
        for (i, dff) in self.dffs.iter().enumerate() {
            self.nets[dff.q] = next_q[i];
        }

        self.evaluate();
    }

    fn run_ticks(&mut self, n: usize) {
        for _ in 0..n {
            self.tick();
        }
    }

    fn reset(&mut self) {
        self.nets.fill(0);
        for dff in &self.dffs {
            if dff.reset_value != 0 {
                self.nets[dff.q] = self.lane_mask;
            }
        }
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

#[magnus::wrap(class = "RHDL::Codegen::Structure::NetlistJit")]
struct RubyNetlistJit {
    sim: RefCell<NetlistJitSimulator>,
}

impl RubyNetlistJit {
    fn new(json: String, lanes: Option<usize>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let lanes = lanes.unwrap_or(64);
        let sim = NetlistJitSimulator::new(&json, lanes)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self { sim: RefCell::new(sim) })
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

    fn run_ticks(&self, n: usize) {
        self.sim.borrow_mut().run_ticks(n);
    }

    fn reset(&self) {
        self.sim.borrow_mut().reset();
    }

    fn net_count(&self) -> usize {
        self.sim.borrow().nets.len()
    }

    fn gate_count(&self) -> usize {
        0 // Gates are compiled away
    }

    fn dff_count(&self) -> usize {
        self.sim.borrow().dffs.len()
    }

    fn lanes(&self) -> usize {
        self.sim.borrow().lanes
    }

    fn input_names(&self) -> Vec<String> {
        self.sim.borrow().inputs.keys().cloned().collect()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().outputs.keys().cloned().collect()
    }

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("net_count"), sim.nets.len() as i64)?;
        hash.aset(ruby.sym_new("dff_count"), sim.dffs.len() as i64)?;
        hash.aset(ruby.sym_new("lanes"), sim.lanes as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.inputs.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.outputs.len() as i64)?;
        hash.aset(ruby.sym_new("backend"), "cranelift_jit")?;

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
    let netlist = codegen.define_module("Netlist")?;

    let class = netlist.define_class("NetlistJit", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyNetlistJit::new, 2))?;
    class.define_method("poke", method!(RubyNetlistJit::poke, 2))?;
    class.define_method("peek", method!(RubyNetlistJit::peek, 1))?;
    class.define_method("evaluate", method!(RubyNetlistJit::evaluate, 0))?;
    class.define_method("tick", method!(RubyNetlistJit::tick, 0))?;
    class.define_method("run_ticks", method!(RubyNetlistJit::run_ticks, 1))?;
    class.define_method("reset", method!(RubyNetlistJit::reset, 0))?;
    class.define_method("net_count", method!(RubyNetlistJit::net_count, 0))?;
    class.define_method("gate_count", method!(RubyNetlistJit::gate_count, 0))?;
    class.define_method("dff_count", method!(RubyNetlistJit::dff_count, 0))?;
    class.define_method("lanes", method!(RubyNetlistJit::lanes, 0))?;
    class.define_method("input_names", method!(RubyNetlistJit::input_names, 0))?;
    class.define_method("output_names", method!(RubyNetlistJit::output_names, 0))?;
    class.define_method("stats", method!(RubyNetlistJit::stats, 0))?;
    class.define_method("native?", method!(RubyNetlistJit::native, 0))?;

    netlist.const_set("NETLIST_JIT_AVAILABLE", true)?;

    Ok(())
}
