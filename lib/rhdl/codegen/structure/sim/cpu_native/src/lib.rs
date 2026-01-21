//! Gate-level netlist simulator with Ruby bindings
//!
//! This simulator evaluates gate-level netlists exported from RHDL's
//! Structure::Lower. It supports the following gate primitives:
//! - AND, OR, XOR, NOT, MUX, BUF, CONST
//! - DFF (D flip-flop with optional enable and reset)
//!
//! The simulator uses a SIMD-style "lanes" approach where each signal
//! is represented as a u64 bitmask, allowing parallel simulation of
//! up to 64 test vectors simultaneously.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::HashMap;

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
}

/// The native netlist simulator
struct NetlistSimulator {
    nets: Vec<u64>,
    gates: Vec<Gate>,
    dffs: Vec<Dff>,
    schedule: Vec<usize>,
    inputs: HashMap<String, Vec<usize>>,
    outputs: HashMap<String, Vec<usize>>,
    lanes: usize,
    lane_mask: u64,
}

#[allow(dead_code)]
impl NetlistSimulator {
    fn new(json: &str, lanes: usize) -> Result<Self, String> {
        let ir: NetlistIR = serde_json::from_str(json)
            .map_err(|e| format!("Failed to parse netlist JSON: {}", e))?;

        let lane_mask = if lanes >= 64 {
            u64::MAX
        } else {
            (1u64 << lanes) - 1
        };

        // Convert gates to internal representation
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

        // Convert DFFs
        let dffs: Vec<Dff> = ir
            .dffs
            .iter()
            .map(|d| Dff {
                d: d.d,
                q: d.q,
                rst: d.rst,
                en: d.en,
            })
            .collect();

        Ok(Self {
            nets: vec![0; ir.net_count],
            gates,
            dffs,
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
            // For multi-bit inputs, broadcast the same mask to all bits
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

        // Convert lane values to bit masks
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

    fn peek(&self, name: &str) -> Result<u64, String> {
        let nets = self
            .outputs
            .get(name)
            .ok_or_else(|| format!("Unknown output: {}", name))?;

        if nets.len() == 1 {
            Ok(self.nets[nets[0]])
        } else {
            // For multi-bit outputs, return the first bit's mask
            // Use peek_bus for full bus values
            Ok(self.nets[nets[0]])
        }
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
    }

    fn tick(&mut self) {
        // Evaluate combinational logic
        self.evaluate();

        // Sample all DFF inputs (before any updates)
        let next_q: Vec<u64> = self
            .dffs
            .iter()
            .map(|dff| {
                let q = self.nets[dff.q];
                let d = self.nets[dff.d];
                let mut q_next = d;

                // Enable: q_next = (q & ~en) | (d & en)
                if let Some(en) = dff.en {
                    let en_val = self.nets[en];
                    q_next = (q & !en_val) | (d & en_val);
                }

                // Reset: q_next &= ~rst
                if let Some(rst) = dff.rst {
                    let rst_val = self.nets[rst];
                    q_next &= !rst_val;
                }

                q_next
            })
            .collect();

        // Update all DFF outputs
        for (i, dff) in self.dffs.iter().enumerate() {
            self.nets[dff.q] = next_q[i];
        }
    }

    fn reset(&mut self) {
        self.nets.fill(0);
    }

    fn net_count(&self) -> usize {
        self.nets.len()
    }

    fn gate_count(&self) -> usize {
        self.gates.len()
    }

    fn dff_count(&self) -> usize {
        self.dffs.len()
    }
}

// ============================================================================
// Ruby bindings
// ============================================================================

/// Convert a Ruby integer to u64, handling both positive and negative values.
/// Ruby's Bignum for 0xFFFFFFFFFFFFFFFF will be handled correctly.
fn ruby_to_u64(value: Value) -> Result<u64, Error> {
    // First try to convert as i64 (handles most cases including negative numbers)
    if let Ok(i) = <i64 as TryConvert>::try_convert(value) {
        // Negative values become their two's complement representation
        return Ok(i as u64);
    }

    // If i64 failed, try to get the value via Ruby string conversion
    // This handles Bignums that exceed i64::MAX
    let ruby = unsafe { Ruby::get_unchecked() };
    let str_val: String = value.funcall("to_s", (16i32,))?;
    u64::from_str_radix(&str_val, 16)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid integer: {}", e)))
}

/// Convert a u64 to a Ruby integer, preserving the full 64-bit unsigned value.
fn u64_to_ruby(ruby: &Ruby, value: u64) -> Value {
    // If value fits in i64's positive range, return as i64
    if value <= i64::MAX as u64 {
        ruby.into_value(value as i64)
    } else {
        // For values > i64::MAX, create via string parsing to get a Bignum
        // Format as hex and parse in Ruby
        let hex_str = format!("{:x}", value);
        let result: Result<Value, Error> = ruby
            .eval(&format!("0x{}", hex_str));
        result.unwrap_or_else(|_| ruby.into_value(0i64))
    }
}

#[magnus::wrap(class = "RHDL::Codegen::Structure::SimCPUNative")]
struct RubyNetlistSim {
    sim: RefCell<NetlistSimulator>,
}

impl RubyNetlistSim {
    fn new(json: String, lanes: Option<usize>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let lanes = lanes.unwrap_or(64);
        let sim = NetlistSimulator::new(&json, lanes)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self {
            sim: RefCell::new(sim),
        })
    }

    fn poke(&self, name: String, value: Value) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let mut sim = self.sim.borrow_mut();

        // Check if value is an array (bus values) or single value
        if let Ok(arr) = RArray::try_convert(value) {
            let values: Vec<u64> = arr
                .into_iter()
                .map(|v| ruby_to_u64(v))
                .collect::<Result<Vec<_>, Error>>()?;
            sim.poke_bus(&name, &values)
                .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
        } else {
            let v = ruby_to_u64(value)?;
            sim.poke(&name, v)
                .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
        }
    }

    fn peek(&self, name: String) -> Result<Value, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let nets = sim
            .outputs
            .get(&name)
            .ok_or_else(|| Error::new(ruby.exception_runtime_error(), format!("Unknown output: {}", name)))?;

        if nets.len() == 1 {
            Ok(u64_to_ruby(&ruby, sim.nets[nets[0]]))
        } else {
            let arr = ruby.ary_new_capa(nets.len());
            for &net in nets {
                let _ = arr.push(u64_to_ruby(&ruby, sim.nets[net]));
            }
            Ok(arr.as_value())
        }
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

    fn net_count(&self) -> usize {
        self.sim.borrow().net_count()
    }

    fn gate_count(&self) -> usize {
        self.sim.borrow().gate_count()
    }

    fn dff_count(&self) -> usize {
        self.sim.borrow().dff_count()
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

        hash.aset(ruby.sym_new("net_count"), sim.net_count() as i64)?;
        hash.aset(ruby.sym_new("gate_count"), sim.gate_count() as i64)?;
        hash.aset(ruby.sym_new("dff_count"), sim.dff_count() as i64)?;
        hash.aset(ruby.sym_new("lanes"), sim.lanes as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.inputs.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.outputs.len() as i64)?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // Define module path: RHDL::Codegen::Structure
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let structure = codegen.define_module("Structure")?;

    // Define class RHDL::Codegen::Structure::SimCPUNative
    let class = structure.define_class("SimCPUNative", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyNetlistSim::new, 2))?;
    class.define_method("poke", method!(RubyNetlistSim::poke, 2))?;
    class.define_method("peek", method!(RubyNetlistSim::peek, 1))?;
    class.define_method("evaluate", method!(RubyNetlistSim::evaluate, 0))?;
    class.define_method("tick", method!(RubyNetlistSim::tick, 0))?;
    class.define_method("reset", method!(RubyNetlistSim::reset, 0))?;
    class.define_method("net_count", method!(RubyNetlistSim::net_count, 0))?;
    class.define_method("gate_count", method!(RubyNetlistSim::gate_count, 0))?;
    class.define_method("dff_count", method!(RubyNetlistSim::dff_count, 0))?;
    class.define_method("lanes", method!(RubyNetlistSim::lanes, 0))?;
    class.define_method("input_names", method!(RubyNetlistSim::input_names, 0))?;
    class.define_method("output_names", method!(RubyNetlistSim::output_names, 0))?;
    class.define_method("stats", method!(RubyNetlistSim::stats, 0))?;
    class.define_method("native?", method!(RubyNetlistSim::native, 0))?;

    // Set constant to indicate native extension is available
    structure.const_set("NATIVE_SIM_AVAILABLE", true)?;

    Ok(())
}
