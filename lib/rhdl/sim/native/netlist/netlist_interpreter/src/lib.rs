//! Gate-level netlist interpreter with C ABI exports
//!
//! This simulator evaluates gate-level netlists exported from RHDL's
//! Structure::Lower. It is consumed from Ruby via Fiddle.

use serde::Deserialize;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int};
use std::ptr;
use std::slice;

/// Gate types matching RHDL::Codegen::Netlist::Primitives
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

/// SR Latch definition from JSON netlist
#[derive(Debug, Clone, Deserialize)]
struct SrLatchDef {
    s: usize,
    r: usize,
    en: usize,
    q: usize,
    qn: usize,
}

/// Complete netlist IR from JSON
#[derive(Debug, Clone, Deserialize)]
struct NetlistIR {
    #[allow(dead_code)]
    name: String,
    net_count: usize,
    gates: Vec<GateDef>,
    dffs: Vec<DffDef>,
    #[serde(default)]
    sr_latches: Vec<SrLatchDef>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    schedule: Vec<usize>,
}

/// Internal gate representation optimized for evaluation
#[derive(Debug, Clone)]
enum Gate {
    And { in1: usize, in2: usize, out: usize },
    Or { in1: usize, in2: usize, out: usize },
    Xor { in1: usize, in2: usize, out: usize },
    Not { input: usize, out: usize },
    Mux { a: usize, b: usize, sel: usize, out: usize },
    Buf { input: usize, out: usize },
    Const { out: usize, value: u64 },
}

/// Internal DFF representation
#[derive(Debug, Clone)]
struct Dff {
    d: usize,
    q: usize,
    rst: Option<usize>,
    en: Option<usize>,
    reset_value: i64,
}

/// Internal SR Latch representation
#[derive(Debug, Clone)]
struct SrLatch {
    s: usize,
    r: usize,
    en: usize,
    q: usize,
    qn: usize,
}

/// The native netlist simulator
struct NetlistSimulator {
    nets: Vec<u64>,
    gates: Vec<Gate>,
    dffs: Vec<Dff>,
    sr_latches: Vec<SrLatch>,
    schedule: Vec<usize>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    lanes: usize,
    lane_mask: u64,
}

impl NetlistSimulator {
    fn new(json: &str, lanes: usize) -> Result<Self, String> {
        let ir: NetlistIR =
            serde_json::from_str(json).map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let lane_mask = if lanes >= 64 {
            u64::MAX
        } else {
            (1u64 << lanes) - 1
        };

        let gates: Vec<Gate> = ir
            .gates
            .iter()
            .map(|g| match g.gate_type {
                GateType::And => Gate::And {
                    in1: g.inputs[0],
                    in2: g.inputs[1],
                    out: g.output,
                },
                GateType::Or => Gate::Or {
                    in1: g.inputs[0],
                    in2: g.inputs[1],
                    out: g.output,
                },
                GateType::Xor => Gate::Xor {
                    in1: g.inputs[0],
                    in2: g.inputs[1],
                    out: g.output,
                },
                GateType::Not => Gate::Not {
                    input: g.inputs[0],
                    out: g.output,
                },
                GateType::Mux => Gate::Mux {
                    a: g.inputs[0],
                    b: g.inputs[1],
                    sel: g.inputs[2],
                    out: g.output,
                },
                GateType::Buf => Gate::Buf {
                    input: g.inputs[0],
                    out: g.output,
                },
                GateType::Const => Gate::Const {
                    out: g.output,
                    value: if g.value.unwrap_or(0) == 0 { 0 } else { lane_mask },
                },
            })
            .collect();

        let dffs: Vec<Dff> = ir
            .dffs
            .iter()
            .map(|d| Dff {
                d: d.d,
                q: d.q,
                rst: d.rst,
                en: d.en,
                reset_value: d.reset_value,
            })
            .collect();

        let sr_latches: Vec<SrLatch> = ir
            .sr_latches
            .iter()
            .map(|l| SrLatch {
                s: l.s,
                r: l.r,
                en: l.en,
                q: l.q,
                qn: l.qn,
            })
            .collect();

        Ok(Self {
            nets: vec![0; ir.net_count],
            gates,
            dffs,
            sr_latches,
            schedule: ir.schedule,
            inputs: ir.inputs,
            outputs: ir.outputs,
            lanes,
            lane_mask,
        })
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let nets = self
            .inputs
            .get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;

        if nets.len() == 1 {
            self.nets[nets[0]] = value & self.lane_mask;
        } else {
            for &net in nets {
                self.nets[net] = value & self.lane_mask;
            }
        }
        Ok(())
    }

    fn poke_bus(&mut self, name: &str, values: &[u64]) -> Result<(), String> {
        let nets = self
            .inputs
            .get(name)
            .ok_or_else(|| format!("Unknown input: {}", name))?;

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

    #[inline]
    fn evaluate(&mut self) {
        for &gate_idx in &self.schedule {
            let gate = &self.gates[gate_idx];
            match *gate {
                Gate::And { in1, in2, out } => {
                    self.nets[out] = self.nets[in1] & self.nets[in2];
                }
                Gate::Or { in1, in2, out } => {
                    self.nets[out] = self.nets[in1] | self.nets[in2];
                }
                Gate::Xor { in1, in2, out } => {
                    self.nets[out] = self.nets[in1] ^ self.nets[in2];
                }
                Gate::Not { input, out } => {
                    self.nets[out] = (!self.nets[input]) & self.lane_mask;
                }
                Gate::Mux { a, b, sel, out } => {
                    let s = self.nets[sel];
                    self.nets[out] = (self.nets[a] & !s) | (self.nets[b] & s);
                }
                Gate::Buf { input, out } => {
                    self.nets[out] = self.nets[input];
                }
                Gate::Const { out, value } => {
                    self.nets[out] = value;
                }
            }
        }

        // Update SR latches (level-sensitive, iterate for stability).
        for _ in 0..10 {
            let mut changed = false;
            for latch in &self.sr_latches {
                let s = self.nets[latch.s];
                let r = self.nets[latch.r];
                let en = self.nets[latch.en];
                let q_old = self.nets[latch.q];
                let q_next = ((!en) & q_old) | (en & (!r) & (s | q_old)) & self.lane_mask;

                if q_next != q_old {
                    self.nets[latch.q] = q_next;
                    self.nets[latch.qn] = (!q_next) & self.lane_mask;
                    changed = true;
                }
            }
            if !changed {
                break;
            }
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
    sim: NetlistSimulator,
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

    match NetlistSimulator::new(&json, lanes) {
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
        SIM_QUERY_GATE_COUNT => (*ctx).sim.gates.len(),
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
        SIM_BLOB_SIMD_MODE => "scalar".to_string(),
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
