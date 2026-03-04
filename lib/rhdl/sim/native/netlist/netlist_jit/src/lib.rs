//! Cranelift-based JIT compiler for gate-level netlist simulation
//!
//! This library exposes a C ABI consumed from Ruby via Fiddle.

use serde::Deserialize;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::mem;
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::slice;

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
        flag_builder
            .set("opt_level", "speed")
            .map_err(|e| e.to_string())?;
        flag_builder
            .set("is_pic", "false")
            .map_err(|e| e.to_string())?;

        let isa_builder =
            cranelift_native::builder().map_err(|e| format!("Failed to create ISA builder: {}", e))?;
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
        sig.params.push(AbiParam::new(types::I64)); // lane_mask

        ctx.func.signature = sig;

        let func_id = self
            .module
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

        self.module
            .define_function(func_id, &mut ctx)
            .map_err(|e| e.to_string())?;
        self.module.clear_context(&mut ctx);
        self.module
            .finalize_definitions()
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
            GateType::Buf => self.load_net(builder, nets_ptr, gate.inputs[0]),
            GateType::Const => {
                if gate.value.unwrap_or(0) == 0 {
                    builder.ins().iconst(types::I64, 0)
                } else {
                    lane_mask
                }
            }
        };

        builder
            .ins()
            .store(MemFlags::trusted(), result, nets_ptr, out_offset);
    }

    fn load_net(
        &self,
        builder: &mut FunctionBuilder,
        nets_ptr: cranelift::prelude::Value,
        net_idx: usize,
    ) -> cranelift::prelude::Value {
        let offset = (net_idx * 8) as i32;
        builder
            .ins()
            .load(types::I64, MemFlags::trusted(), nets_ptr, offset)
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
        let ir: NetlistIR =
            serde_json::from_str(json).map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let lane_mask = if lanes >= 64 {
            u64::MAX
        } else {
            (1u64 << lanes) - 1
        };

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
        let nets = self
            .inputs
            .get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;
        for &net in nets {
            self.nets[net] = value & self.lane_mask;
        }
        Ok(())
    }

    fn poke_bus(&mut self, name: &str, values: &[u64]) -> Result<(), String> {
        let nets = self
            .inputs
            .get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;

        if nets.len() == 1 {
            let scalar = values.first().copied().unwrap_or(0);
            self.nets[nets[0]] = scalar & self.lane_mask;
            return Ok(());
        }

        let width = nets.len();
        let mut masks = vec![0u64; width];
        for (lane, &lane_value) in values.iter().enumerate() {
            if lane >= self.lanes {
                break;
            }
            for bit in 0..width {
                if ((lane_value >> bit) & 1) == 1 {
                    masks[bit] |= 1 << lane;
                }
            }
        }

        for (i, &net) in nets.iter().enumerate() {
            self.nets[net] = masks[i] & self.lane_mask;
        }

        Ok(())
    }

    fn peek_bus(&self, name: &str) -> Result<Vec<u64>, String> {
        let nets = self
            .outputs
            .get(name)
            .ok_or_else(|| format!("Unknown output: {}", name))?;
        Ok(nets.iter().map(|&net| self.nets[net]).collect())
    }

    #[inline(always)]
    fn evaluate(&mut self) {
        unsafe {
            (self.evaluate_fn)(self.nets.as_mut_ptr(), self.lane_mask);
        }
    }

    fn tick(&mut self) {
        self.evaluate();

        let next_q: Vec<u64> = self
            .dffs
            .iter()
            .map(|dff| {
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
            })
            .collect();

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

    fn input_names_csv(&self) -> String {
        let mut names: Vec<&str> = self.inputs.keys().map(|k| k.as_str()).collect();
        names.sort_unstable();
        names.join(",")
    }

    fn output_names_csv(&self) -> String {
        let mut names: Vec<&str> = self.outputs.keys().map(|k| k.as_str()).collect();
        names.sort_unstable();
        names.join(",")
    }
}

pub struct NetlistSimContext {
    sim: NetlistJitSimulator,
}

const SIM_EXEC_EVALUATE: c_int = 0;
const SIM_EXEC_TICK: c_int = 1;
const SIM_EXEC_RUN_TICKS: c_int = 2;
const SIM_EXEC_RESET: c_int = 3;
const SIM_EXEC_COMPILE: c_int = 4;
const SIM_EXEC_IS_COMPILED: c_int = 5;

const SIM_QUERY_NET_COUNT: c_int = 0;
const SIM_QUERY_GATE_COUNT: c_int = 1;
const SIM_QUERY_DFF_COUNT: c_int = 2;
const SIM_QUERY_LANES: c_int = 3;

const SIM_BLOB_INPUT_NAMES: c_int = 0;
const SIM_BLOB_OUTPUT_NAMES: c_int = 1;
const SIM_BLOB_GENERATED_CODE: c_int = 2;
const SIM_BLOB_SIMD_MODE: c_int = 3;

fn set_error(error_out: *mut *mut c_char, msg: String) {
    if error_out.is_null() {
        return;
    }
    let cstr = CString::new(msg).unwrap_or_else(|_| CString::new("error").unwrap());
    unsafe {
        *error_out = cstr.into_raw();
    }
}

fn clear_error(error_out: *mut *mut c_char) {
    if error_out.is_null() {
        return;
    }
    unsafe {
        *error_out = ptr::null_mut();
    }
}

unsafe fn read_cstr(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Err("null pointer".to_string());
    }
    let s = CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| format!("invalid UTF-8: {}", e))?;
    Ok(s.to_string())
}

#[no_mangle]
pub unsafe extern "C" fn sim_create(
    json: *const c_char,
    config: *const c_char,
    error_out: *mut *mut c_char,
) -> *mut NetlistSimContext {
    clear_error(error_out);

    let json = match read_cstr(json) {
        Ok(v) => v,
        Err(e) => {
            set_error(error_out, format!("invalid JSON input: {}", e));
            return ptr::null_mut();
        }
    };

    let lanes = if config.is_null() {
        64
    } else {
        match read_cstr(config)
            .ok()
            .and_then(|s| s.parse::<usize>().ok())
            .filter(|v| *v > 0)
        {
            Some(v) => v,
            None => 64,
        }
    };

    match NetlistJitSimulator::new(&json, lanes) {
        Ok(sim) => Box::into_raw(Box::new(NetlistSimContext { sim })),
        Err(e) => {
            set_error(error_out, e);
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_destroy(ctx: *mut NetlistSimContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_free_error(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_poke_scalar(
    ctx: *mut NetlistSimContext,
    name: *const c_char,
    value: u64,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);
    if ctx.is_null() {
        set_error(error_out, "simulator context is null".to_string());
        return 0;
    }

    let name = match read_cstr(name) {
        Ok(v) => v,
        Err(e) => {
            set_error(error_out, format!("invalid signal name: {}", e));
            return 0;
        }
    };

    match (*ctx).sim.poke(&name, value) {
        Ok(()) => 1,
        Err(e) => {
            set_error(error_out, e);
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_poke_bus(
    ctx: *mut NetlistSimContext,
    name: *const c_char,
    values: *const u64,
    len: usize,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);
    if ctx.is_null() {
        set_error(error_out, "simulator context is null".to_string());
        return 0;
    }
    if values.is_null() && len > 0 {
        set_error(error_out, "values pointer is null".to_string());
        return 0;
    }

    let name = match read_cstr(name) {
        Ok(v) => v,
        Err(e) => {
            set_error(error_out, format!("invalid signal name: {}", e));
            return 0;
        }
    };

    let vals = slice::from_raw_parts(values, len);
    match (*ctx).sim.poke_bus(&name, vals) {
        Ok(()) => 1,
        Err(e) => {
            set_error(error_out, e);
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_peek_bus(
    ctx: *mut NetlistSimContext,
    name: *const c_char,
    out_values: *mut u64,
    out_capacity: usize,
    out_len: *mut usize,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);

    if ctx.is_null() {
        set_error(error_out, "simulator context is null".to_string());
        return 0;
    }
    if out_len.is_null() {
        set_error(error_out, "out_len pointer is null".to_string());
        return 0;
    }

    let name = match read_cstr(name) {
        Ok(v) => v,
        Err(e) => {
            set_error(error_out, format!("invalid signal name: {}", e));
            return 0;
        }
    };

    match (*ctx).sim.peek_bus(&name) {
        Ok(values) => {
            *out_len = values.len();
            if out_values.is_null() || out_capacity == 0 {
                return 1;
            }
            if out_capacity < values.len() {
                set_error(
                    error_out,
                    format!("output buffer too small: need {}, got {}", values.len(), out_capacity),
                );
                return 0;
            }
            if !values.is_empty() {
                ptr::copy_nonoverlapping(values.as_ptr(), out_values, values.len());
            }
            1
        }
        Err(e) => {
            set_error(error_out, e);
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_exec(
    ctx: *mut NetlistSimContext,
    op: c_int,
    arg: usize,
    error_out: *mut *mut c_char,
) -> c_int {
    clear_error(error_out);

    if ctx.is_null() {
        set_error(error_out, "simulator context is null".to_string());
        return 0;
    }

    match op {
        SIM_EXEC_EVALUATE => {
            (*ctx).sim.evaluate();
            1
        }
        SIM_EXEC_TICK => {
            (*ctx).sim.tick();
            1
        }
        SIM_EXEC_RUN_TICKS => {
            (*ctx).sim.run_ticks(arg);
            1
        }
        SIM_EXEC_RESET => {
            (*ctx).sim.reset();
            1
        }
        SIM_EXEC_COMPILE => 1,
        SIM_EXEC_IS_COMPILED => 1,
        _ => {
            set_error(error_out, format!("unknown exec op: {}", op));
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_query(ctx: *const NetlistSimContext, op: c_int) -> usize {
    if ctx.is_null() {
        return 0;
    }
    match op {
        SIM_QUERY_NET_COUNT => (*ctx).sim.nets.len(),
        SIM_QUERY_GATE_COUNT => 0, // JIT compiles gates away.
        SIM_QUERY_DFF_COUNT => (*ctx).sim.dffs.len(),
        SIM_QUERY_LANES => (*ctx).sim.lanes,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_blob(
    ctx: *const NetlistSimContext,
    op: c_int,
    out_buf: *mut u8,
    out_len: usize,
) -> usize {
    if ctx.is_null() {
        return 0;
    }

    let data = match op {
        SIM_BLOB_INPUT_NAMES => (*ctx).sim.input_names_csv(),
        SIM_BLOB_OUTPUT_NAMES => (*ctx).sim.output_names_csv(),
        SIM_BLOB_GENERATED_CODE => String::new(),
        SIM_BLOB_SIMD_MODE => "jit".to_string(),
        _ => String::new(),
    };

    let bytes = data.as_bytes();
    if out_buf.is_null() || out_len == 0 {
        return bytes.len();
    }

    let n = bytes.len().min(out_len);
    ptr::copy_nonoverlapping(bytes.as_ptr(), out_buf, n);
    n
}
