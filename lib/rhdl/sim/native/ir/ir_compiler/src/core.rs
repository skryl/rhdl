//! Core IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This module contains the generic IR simulation infrastructure without
//! any example-specific code (Apple II, MOS6502, etc.)

use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
#[cfg(not(feature = "aot"))]
use std::fs;
#[cfg(not(feature = "aot"))]
use std::process::Command;
#[cfg(not(feature = "aot"))]
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use serde_json::{Map, Value};

use crate::runtime_value::RuntimeValue;
use crate::signal_value::{
    compute_mask as wide_mask,
    deserialize_integer_text,
    deserialize_optional_signal_value,
    deserialize_signal_values,
    mask_signed_value,
    SignalValue,
    SignedSignalValue,
};

#[cfg(feature = "aot")]
type CompiledLibrary = ();
#[cfg(not(feature = "aot"))]
type CompiledLibrary = libloading::Library;
#[cfg(not(feature = "aot"))]
type CompiledEvalFn = unsafe extern "C" fn(*mut SignalValue, *const u64, *const *const u64, usize);
#[cfg(not(feature = "aot"))]
type CompiledTickFn = unsafe extern "C" fn(*mut SignalValue, usize, *mut SignalValue, *mut SignalValue);

const CHUNKED_EVALUATE_ASSIGN_THRESHOLD: usize = 256;
const CHUNKED_EVALUATE_ASSIGNS_PER_FN: usize = 32;
const LARGE_NON_TICK_CHUNKED_EVALUATE_ASSIGN_THRESHOLD: usize = 8_192;
const LARGE_NON_TICK_CHUNKED_EVALUATE_ASSIGNS_PER_FN: usize = 1_024;
const LARGE_RUSTC_SOURCE_BYTES_THRESHOLD: usize = 8 * 1024 * 1024;
const RUNTIME_RUSTC_OPT_LEVEL: &str = "2";
const RUNTIME_RUSTC_CODEGEN_UNITS: &str = "64";
const LARGE_RUNTIME_RUSTC_OPT_LEVEL: &str = "0";
const LARGE_RUNTIME_RUSTC_CODEGEN_UNITS: &str = "256";
const RUNTIME_RUSTC_TARGET_CPU: &str = "native";
const COMPILED_WIDE_SIGNAL_WORDS: usize = 2;
const LARGE_NARROW_CONCAT_PART_THRESHOLD: usize = 16;
const SINGLE_USE_EXPR_MATERIALIZE_COMPLEXITY_THRESHOLD: u32 = 131_072;
const SINGLE_USE_EXPR_MATERIALIZE_COMPLEXITY_THRESHOLD_BIT1: u32 = 8_192;
const SINGLE_USE_EXPR_MATERIALIZE_MAX_WIDTH: usize = 8;

#[derive(Default)]
struct ExprCodegenState {
    emitted: HashSet<usize>,
    emitting: HashSet<usize>,
    temp_counter: usize,
    wide_expr_ref_temps: HashMap<usize, String>,
    wide_signal_temps: HashMap<usize, String>,
    wide_slice_temps: HashMap<(usize, usize, usize), String>,
}

impl ExprCodegenState {
    fn fresh_temp(&mut self, prefix: &str) -> String {
        let name = format!("{}_{}", prefix, self.temp_counter);
        self.temp_counter += 1;
        name
    }

    fn cached_wide_signal_load(
        &mut self,
        idx: usize,
        signals_ptr: &str,
        wide_words_ptr: &str,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        if let Some(name) = self.wide_signal_temps.get(&idx) {
            return name.clone();
        }

        let name = self.fresh_temp("wide_signal");
        emitted_lines.push(format!(
            "let {} = wide_load_signal({}, {}, {});",
            name, signals_ptr, wide_words_ptr, idx
        ));
        self.wide_signal_temps.insert(idx, name.clone());
        name
    }

    fn cached_wide_signal_slice(
        &mut self,
        idx: usize,
        low: usize,
        width: usize,
        signals_ptr: &str,
        wide_words_ptr: &str,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        let key = (idx, low, width);
        if let Some(name) = self.wide_slice_temps.get(&key) {
            return name.clone();
        }

        let base = self.cached_wide_signal_load(idx, signals_ptr, wide_words_ptr, emitted_lines);
        let name = self.fresh_temp("wide_slice");
        emitted_lines.push(format!(
            "let {} = wide_slice_u128({}, {}, {});",
            name, base, low, width
        ));
        self.wide_slice_temps.insert(key, name.clone());
        name
    }
}

// ============================================================================
// IR data structures for normalized CIRCT runtime JSON.
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Direction {
    In,
    Out,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PortDef {
    pub name: String,
    pub direction: Direction,
    pub width: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct NetDef {
    pub name: String,
    pub width: usize,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RegDef {
    pub name: String,
    pub width: usize,
    #[serde(default)]
    #[serde(deserialize_with = "deserialize_optional_signal_value")]
    pub reset_value: Option<SignalValue>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ExprDef {
    Signal { name: String, width: usize },
    #[serde(rename = "signal_index")]
    SignalIndex { idx: usize, width: usize },
    Literal {
        #[serde(deserialize_with = "deserialize_integer_text")]
        value: String,
        width: usize,
        #[serde(skip, default)]
        parsed: Option<RuntimeValue>,
    },
    ExprRef { id: usize, width: usize },
    #[serde(alias = "unary")]
    UnaryOp { op: String, operand: Box<ExprDef>, width: usize },
    #[serde(alias = "binary")]
    BinaryOp { op: String, left: Box<ExprDef>, right: Box<ExprDef>, width: usize },
    Mux { condition: Box<ExprDef>, when_true: Box<ExprDef>, when_false: Box<ExprDef>, width: usize },
    Slice {
        base: Box<ExprDef>,
        #[serde(alias = "range_begin")]
        low: usize,
        #[allow(dead_code)]
        #[serde(alias = "range_end")]
        high: usize,
        width: usize,
    },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
    #[serde(alias = "memory_read")]
    MemRead { memory: String, addr: Box<ExprDef>, width: usize },
}

#[derive(Debug, Clone, Deserialize)]
pub struct AssignDef {
    pub target: String,
    pub expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SeqAssignDef {
    pub target: String,
    pub expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProcessDef {
    #[allow(dead_code)]
    pub name: String,
    pub clock: Option<String>,
    pub clocked: bool,
    pub statements: Vec<SeqAssignDef>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct MemoryDef {
    pub name: String,
    pub depth: usize,
    #[allow(dead_code)]
    pub width: usize,
    #[serde(default)]
    #[serde(deserialize_with = "deserialize_signal_values")]
    pub initial_data: Vec<SignalValue>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct WritePortDef {
    pub memory: String,
    pub clock: String,
    pub addr: ExprDef,
    pub data: ExprDef,
    pub enable: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SyncReadPortDef {
    pub memory: String,
    pub clock: String,
    pub addr: ExprDef,
    pub data: String,
    #[serde(default)]
    pub enable: Option<ExprDef>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ModuleIR {
    #[allow(dead_code)]
    pub name: String,
    pub ports: Vec<PortDef>,
    pub nets: Vec<NetDef>,
    pub regs: Vec<RegDef>,
    #[serde(default)]
    pub exprs: Vec<ExprDef>,
    pub assigns: Vec<AssignDef>,
    pub processes: Vec<ProcessDef>,
    #[serde(default)]
    pub memories: Vec<MemoryDef>,
    #[serde(default)]
    pub write_ports: Vec<WritePortDef>,
    #[serde(default)]
    pub sync_read_ports: Vec<SyncReadPortDef>,
}

fn deserialize_unbounded<T>(json: &str) -> Result<T, serde_json::Error>
where
    T: for<'de> serde::Deserialize<'de>,
{
    let mut deserializer = serde_json::Deserializer::from_str(json);
    deserializer.disable_recursion_limit();
    T::deserialize(&mut deserializer)
}

fn parse_module_ir(json: &str) -> Result<ModuleIR, String> {
    if crate::runtime_frontend::looks_like_mlir_payload(json) {
        let normalized = crate::runtime_frontend::normalize_mlir_payload(json)
            .map_err(|e| format!("Failed to parse IR MLIR: {}", e))?;

        return serde_json::from_value::<ModuleIR>(normalized)
            .map_err(|e| format!("Failed to parse normalized MLIR payload: {}", e));
    }

    let value = deserialize_unbounded::<Value>(json)
        .map_err(|e| format!("Failed to parse IR JSON: {}", e))?;

    if !is_circt_runtime_payload(&value) {
        return Err("Failed to parse IR JSON: expected CIRCT runtime JSON payload".to_string());
    }

    let normalized = normalize_circt_runtime_payload(value)
        .map_err(|e| format!("Failed to parse IR JSON: CIRCT normalization failed: {}", e))?;

    serde_json::from_value::<ModuleIR>(normalized)
        .map_err(|e| format!("Failed to parse IR JSON: normalized CIRCT parse failed: {}", e))
}

fn is_circt_runtime_payload(value: &Value) -> bool {
    let Some(obj) = value.as_object() else {
        return false;
    };

    obj.contains_key("circt_json_version") && obj.contains_key("modules")
}

fn normalize_circt_runtime_payload(payload: Value) -> Result<Value, String> {
    let module_obj = extract_runtime_module(payload)?;
    module_to_normalized_value(module_obj)
}

fn extract_runtime_module(payload: Value) -> Result<Map<String, Value>, String> {
    let obj = payload
        .as_object()
        .ok_or_else(|| "Expected top-level JSON object".to_string())?;

    if !(obj.contains_key("circt_json_version") && obj.contains_key("modules")) {
        return Err("CIRCT payload missing wrapper metadata".to_string());
    }

    let modules = obj
        .get("modules")
        .and_then(Value::as_array)
        .ok_or_else(|| "CIRCT payload is missing modules array".to_string())?;
    let first = modules
        .first()
        .ok_or_else(|| "CIRCT payload has no modules".to_string())?;
    first
        .as_object()
        .cloned()
        .ok_or_else(|| "First CIRCT module is not an object".to_string())
}

fn module_to_normalized_value(module_obj: Map<String, Value>) -> Result<Value, String> {
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(module_obj.get("name"))));
    out.insert(
        "ports".to_string(),
        Value::Array(
            array_field(&module_obj, "ports")
                .into_iter()
                .map(|v| port_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "nets".to_string(),
        Value::Array(
            array_field(&module_obj, "nets")
                .into_iter()
                .map(|v| net_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "regs".to_string(),
        Value::Array(
            array_field(&module_obj, "regs")
                .into_iter()
                .map(|v| reg_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "exprs".to_string(),
        Value::Array(
            array_field(&module_obj, "exprs")
                .into_iter()
                .map(|v| expr_to_normalized_value(Some(&v)))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "assigns".to_string(),
        Value::Array(
            array_field(&module_obj, "assigns")
                .into_iter()
                .map(|v| assign_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "processes".to_string(),
        Value::Array(
            array_field(&module_obj, "processes")
                .into_iter()
                .map(|v| process_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "memories".to_string(),
        Value::Array(
            array_field(&module_obj, "memories")
                .into_iter()
                .map(|v| memory_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "write_ports".to_string(),
        Value::Array(
            array_field(&module_obj, "write_ports")
                .into_iter()
                .map(|v| write_port_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "sync_read_ports".to_string(),
        Value::Array(
            array_field(&module_obj, "sync_read_ports")
                .into_iter()
                .map(|v| sync_read_port_to_normalized_value(&v))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    Ok(Value::Object(out))
}

fn port_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "port")?;
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(obj.get("name"))));
    out.insert(
        "direction".to_string(),
        Value::String(value_to_string(obj.get("direction"))),
    );
    out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
    Ok(Value::Object(out))
}

fn net_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "net")?;
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(obj.get("name"))));
    out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
    Ok(Value::Object(out))
}

fn reg_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "reg")?;
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(obj.get("name"))));
    out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
    if let Some(reset_value) = obj.get("reset_value") {
        if !reset_value.is_null() {
            out.insert("reset_value".to_string(), reset_value.clone());
        }
    }
    Ok(Value::Object(out))
}

fn assign_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "assign")?;
    let mut out = Map::new();
    out.insert("target".to_string(), Value::String(value_to_string(obj.get("target"))));
    out.insert("expr".to_string(), expr_to_normalized_value(obj.get("expr"))?);
    Ok(Value::Object(out))
}

fn process_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "process")?;
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(obj.get("name"))));
    out.insert(
        "clock".to_string(),
        obj.get("clock")
            .map(|v| {
                if v.is_null() {
                    Value::Null
                } else {
                    Value::String(value_to_string(Some(v)))
                }
            })
            .unwrap_or(Value::Null),
    );
    out.insert("clocked".to_string(), Value::Bool(value_to_bool(obj.get("clocked"))));
    out.insert(
        "statements".to_string(),
        Value::Array(flatten_statements(array_field(obj, "statements"))?),
    );
    Ok(Value::Object(out))
}

fn flatten_statements(statements: Vec<Value>) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    for stmt in statements {
        let stmt_obj = as_object(&stmt, "statement")?;
        match stmt_obj.get("kind").and_then(Value::as_str).unwrap_or("") {
            "seq_assign" => {
                let mut seq = Map::new();
                seq.insert(
                    "target".to_string(),
                    Value::String(value_to_string(stmt_obj.get("target"))),
                );
                seq.insert("expr".to_string(), expr_to_normalized_value(stmt_obj.get("expr"))?);
                out.push(Value::Object(seq));
            }
            "if" => flatten_if(stmt_obj, &mut out)?,
            _ => {}
        }
    }
    Ok(out)
}

fn flatten_if(if_obj: &Map<String, Value>, out: &mut Vec<Value>) -> Result<(), String> {
    let cond = expr_to_normalized_value(if_obj.get("condition"))?;

    let mut then_assigns: HashMap<String, Value> = HashMap::new();
    for stmt in array_field(if_obj, "then_statements") {
        let obj = as_object(&stmt, "if.then statement")?;
        match obj.get("kind").and_then(Value::as_str).unwrap_or("") {
            "seq_assign" => {
                then_assigns.insert(
                    value_to_string(obj.get("target")),
                    expr_to_normalized_value(obj.get("expr"))?,
                );
            }
            "if" => flatten_if(obj, out)?,
            _ => {}
        }
    }

    let mut else_assigns: HashMap<String, Value> = HashMap::new();
    for stmt in array_field(if_obj, "else_statements") {
        let obj = as_object(&stmt, "if.else statement")?;
        match obj.get("kind").and_then(Value::as_str).unwrap_or("") {
            "seq_assign" => {
                else_assigns.insert(
                    value_to_string(obj.get("target")),
                    expr_to_normalized_value(obj.get("expr"))?,
                );
            }
            "if" => flatten_if(obj, out)?,
            _ => {}
        }
    }

    let mut all_targets: Vec<String> = then_assigns
        .keys()
        .chain(else_assigns.keys())
        .cloned()
        .collect();
    all_targets.sort();
    all_targets.dedup();

    for target in all_targets {
        let then_expr = then_assigns.get(&target).cloned();
        let else_expr = else_assigns.get(&target).cloned();
        let width = expr_width(then_expr.as_ref().or(else_expr.as_ref())).unwrap_or(8);

        let mux_expr = match (then_expr, else_expr) {
            (Some(t), Some(f)) => mux_expr(cond.clone(), t, f, width),
            (Some(t), None) => mux_expr(
                cond.clone(),
                t,
                signal_expr(target.clone(), width),
                width,
            ),
            (None, Some(f)) => mux_expr(
                unary_expr("~", cond.clone(), 1),
                f,
                signal_expr(target.clone(), width),
                width,
            ),
            (None, None) => continue,
        };

        let mut seq = Map::new();
        seq.insert("target".to_string(), Value::String(target));
        seq.insert("expr".to_string(), mux_expr);
        out.push(Value::Object(seq));
    }

    Ok(())
}

fn memory_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "memory")?;
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(value_to_string(obj.get("name"))));
    out.insert("depth".to_string(), Value::from(value_to_u64(obj.get("depth"))));
    out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
    if let Some(initial_data) = obj.get("initial_data") {
        if !initial_data.is_null() {
            out.insert("initial_data".to_string(), initial_data.clone());
        }
    }
    Ok(Value::Object(out))
}

fn write_port_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "write_port")?;
    let mut out = Map::new();
    out.insert(
        "memory".to_string(),
        Value::String(value_to_string(obj.get("memory"))),
    );
    out.insert(
        "clock".to_string(),
        Value::String(value_to_string(obj.get("clock"))),
    );
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"))?);
    out.insert("data".to_string(), expr_to_normalized_value(obj.get("data"))?);
    out.insert("enable".to_string(), expr_to_normalized_value(obj.get("enable"))?);
    Ok(Value::Object(out))
}

fn sync_read_port_to_normalized_value(value: &Value) -> Result<Value, String> {
    let obj = as_object(value, "sync_read_port")?;
    let mut out = Map::new();
    out.insert(
        "memory".to_string(),
        Value::String(value_to_string(obj.get("memory"))),
    );
    out.insert(
        "clock".to_string(),
        Value::String(value_to_string(obj.get("clock"))),
    );
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"))?);
    out.insert(
        "data".to_string(),
        Value::String(value_to_string(obj.get("data"))),
    );
    if let Some(enable) = obj.get("enable") {
        if !enable.is_null() {
            out.insert("enable".to_string(), expr_to_normalized_value(Some(enable))?);
        }
    }
    Ok(Value::Object(out))
}

fn expr_to_normalized_value(expr: Option<&Value>) -> Result<Value, String> {
    let Some(value) = expr else {
        return Ok(literal_expr(0, 1));
    };
    let obj = as_object(value, "expression")?;

    let expr_kind = obj
        .get("kind")
        .and_then(Value::as_str)
        .unwrap_or("");

    match expr_kind {
        "signal" => Ok(signal_expr(
            value_to_string(obj.get("name")),
            value_to_usize(obj.get("width")),
        )),
        "literal" => Ok(literal_expr_from_json(obj.get("value"), value_to_usize(obj.get("width")))),
        "expr_ref" => {
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("expr_ref".to_string()));
            out.insert("id".to_string(), Value::from(value_to_u64(obj.get("id"))));
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "unary" => Ok(unary_expr(
            &value_to_string(obj.get("op")),
            expr_to_normalized_value(obj.get("operand"))?,
            value_to_usize(obj.get("width")),
        )),
        "binary" => Ok(binary_expr(
            &value_to_string(obj.get("op")),
            expr_to_normalized_value(obj.get("left"))?,
            expr_to_normalized_value(obj.get("right"))?,
            value_to_usize(obj.get("width")),
        )),
        "mux" => Ok(mux_expr(
            expr_to_normalized_value(obj.get("condition"))?,
            expr_to_normalized_value(obj.get("when_true"))?,
            expr_to_normalized_value(obj.get("when_false"))?,
            value_to_usize(obj.get("width")),
        )),
        "slice" => {
            let begin = value_to_i64(obj.get("range_begin"));
            let end = value_to_i64(obj.get("range_end"));
            let low = begin.min(end);
            let high = begin.max(end);
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("slice".to_string()));
            out.insert("base".to_string(), expr_to_normalized_value(obj.get("base"))?);
            out.insert("range_begin".to_string(), Value::from(low));
            out.insert("range_end".to_string(), Value::from(high));
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "concat" => {
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("concat".to_string()));
            out.insert(
                "parts".to_string(),
                Value::Array(
                    array_field(obj, "parts")
                        .into_iter()
                        .map(|part| expr_to_normalized_value(Some(&part)))
                        .collect::<Result<Vec<_>, _>>()?,
                ),
            );
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "resize" => {
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("resize".to_string()));
            out.insert("expr".to_string(), expr_to_normalized_value(obj.get("expr"))?);
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "memory_read" => {
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("memory_read".to_string()));
            out.insert(
                "memory".to_string(),
                Value::String(value_to_string(obj.get("memory"))),
            );
            out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"))?);
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "case" => lower_case_expr(obj),
        _ => Ok(literal_expr(0, 1)),
    }
}

fn lower_case_expr(case_obj: &Map<String, Value>) -> Result<Value, String> {
    let selector = expr_to_normalized_value(case_obj.get("selector"))?;
    let width = value_to_usize(case_obj.get("width"));
    let default_expr = if let Some(default_value) = case_obj.get("default") {
        if !default_value.is_null() {
            expr_to_normalized_value(Some(default_value))?
        } else {
            literal_expr(0, width.max(1))
        }
    } else {
        literal_expr(0, width.max(1))
    };

    let mut result = default_expr;

    if let Some(cases_obj) = case_obj.get("cases").and_then(Value::as_object) {
        for (raw_values, raw_expr) in cases_obj {
            let values = parse_case_values(raw_values);
            if values.is_empty() {
                continue;
            }
            for value in values {
                let cond = binary_expr(
                    "==",
                    selector.clone(),
                    literal_expr(value, expr_width(Some(&selector)).unwrap_or(1)),
                    1,
                );
                result = mux_expr(
                    cond,
                    expr_to_normalized_value(Some(raw_expr))?,
                    result,
                    width.max(1),
                );
            }
        }
    }

    Ok(result)
}

fn parse_case_values(raw: &str) -> Vec<SignedSignalValue> {
    let text = raw.trim();
    if text.is_empty() {
        return Vec::new();
    }

    if text.starts_with('[') && text.ends_with(']') {
        let inner = &text[1..text.len() - 1];
        return inner
            .split(',')
            .filter_map(|v| v.trim().parse::<SignedSignalValue>().ok())
            .collect();
    }

    text.parse::<SignedSignalValue>().ok().into_iter().collect()
}

fn as_object<'a>(value: &'a Value, what: &str) -> Result<&'a Map<String, Value>, String> {
    value
        .as_object()
        .ok_or_else(|| format!("Expected {} object", what))
}

fn array_field(obj: &Map<String, Value>, key: &str) -> Vec<Value> {
    obj.get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

fn value_to_string(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(s)) => s.clone(),
        Some(v) => match v {
            Value::Null => String::new(),
            Value::Number(n) => n.to_string(),
            Value::Bool(b) => {
                if *b {
                    "true".to_string()
                } else {
                    "false".to_string()
                }
            }
            _ => String::new(),
        },
        None => String::new(),
    }
}

fn value_to_bool(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_u64().unwrap_or(0) != 0,
        Some(Value::String(s)) => s == "true" || s == "1",
        _ => false,
    }
}

fn value_to_u64(value: Option<&Value>) -> u64 {
    value_to_i64(value).max(0) as u64
}

fn value_to_usize(value: Option<&Value>) -> usize {
    value_to_u64(value) as usize
}

fn value_to_i64(value: Option<&Value>) -> i64 {
    match value {
        Some(Value::Number(n)) => n.as_i64().unwrap_or_else(|| n.as_u64().unwrap_or(0) as i64),
        Some(Value::String(s)) => s.parse::<i64>().unwrap_or(0),
        Some(Value::Bool(b)) => {
            if *b {
                1
            } else {
                0
            }
        }
        _ => 0,
    }
}

fn literal_expr(value: SignedSignalValue, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("literal".to_string()));
    out.insert("value".to_string(), Value::String(value.to_string()));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn literal_expr_from_json(value: Option<&Value>, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("literal".to_string()));
    out.insert("value".to_string(), value.cloned().unwrap_or(Value::from(0)));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn signal_expr(name: String, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("signal".to_string()));
    out.insert("name".to_string(), Value::String(name));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn unary_expr(op: &str, operand: Value, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("unary".to_string()));
    out.insert("op".to_string(), Value::String(op.to_string()));
    out.insert("operand".to_string(), operand);
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn binary_expr(op: &str, left: Value, right: Value, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("binary".to_string()));
    out.insert("op".to_string(), Value::String(op.to_string()));
    out.insert("left".to_string(), left);
    out.insert("right".to_string(), right);
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn mux_expr(condition: Value, when_true: Value, when_false: Value, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("mux".to_string()));
    out.insert("condition".to_string(), condition);
    out.insert("when_true".to_string(), when_true);
    out.insert("when_false".to_string(), when_false);
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn expr_width(expr: Option<&Value>) -> Option<usize> {
    let obj = expr?.as_object()?;
    obj.get("width").map(|w| value_to_usize(Some(w)))
}

#[derive(Default)]
struct RuntimeExprEvalCache {
    epoch: u32,
    marks: Vec<u32>,
    values: Vec<RuntimeValue>,
}

impl RuntimeExprEvalCache {
    fn new(expr_count: usize) -> Self {
        Self {
            epoch: 1,
            marks: vec![0; expr_count],
            values: vec![RuntimeValue::Narrow(0); expr_count],
        }
    }

    fn next_epoch(&mut self) {
        self.epoch = self.epoch.wrapping_add(1);
        if self.epoch == 0 {
            self.marks.fill(0);
            self.epoch = 1;
        }
    }

    fn get(&self, id: usize) -> Option<RuntimeValue> {
        if self.marks.get(id).copied() == Some(self.epoch) {
            self.values.get(id).cloned()
        } else {
            None
        }
    }

    fn store(&mut self, id: usize, value: RuntimeValue) {
        if let Some(mark) = self.marks.get_mut(id) {
            *mark = self.epoch;
        }
        if let Some(slot) = self.values.get_mut(id) {
            *slot = value;
        }
    }
}

// ============================================================================
// Core Simulator State
// ============================================================================

/// Core IR simulator - generic circuit simulation without example-specific features
pub struct CoreSimulator {
    /// IR definition
    pub ir: ModuleIR,
    /// Signal values (Vec for O(1) access)
    pub signals: Vec<SignalValue>,
    /// Overwide signal words above bit 127, little-endian 64-bit limbs.
    pub wide_signal_words: Vec<Vec<u64>>,
    /// Fixed transport view for compiled evaluate (bits 128..255).
    pub compiled_wide_signal_words: Vec<[u64; COMPILED_WIDE_SIGNAL_WORDS]>,
    /// Stable pointers to signal high-word storage for signals wider than 256 bits.
    pub compiled_overwide_signal_ptrs: Vec<*const u64>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Direct incoming reference count for each compact expr id
    pub expr_ref_use_counts: Vec<usize>,
    /// Approximate compact expr complexity, capped for selective materialization.
    pub expr_ref_complexities: Vec<u32>,
    /// Per-root memoization for compact expr evaluation on the runtime-only path.
    runtime_expr_cache: RefCell<RuntimeExprEvalCache>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Reset values for registers (signal index -> reset value)
    pub reset_values: Vec<(usize, SignalValue)>,
    /// Topologically sorted combinational assignments for full runtime fallback
    pub comb_assigns: Vec<(usize, usize)>,
    /// Topologically sorted combinational assignments that still require
    /// runtime evaluation even when the core is compiled.
    pub runtime_comb_assigns: Vec<(usize, usize)>,
    /// Topologically sorted combinational assignment indices that are safe to
    /// lower into generated Rust.
    pub compiled_comb_assign_indices: Vec<usize>,
    /// Next register values buffer
    pub next_regs: Vec<SignalValue>,
    /// Overwide next-register words above bit 127, little-endian 64-bit limbs.
    pub wide_next_reg_words: Vec<Vec<u64>>,
    /// Sequential assignment expressions
    pub seq_exprs: Vec<(usize, usize)>,
    /// Sequential assignment target indices
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// Clock-domain slot for each sequential assignment
    pub seq_clock_slots: Vec<usize>,
    /// All unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    pub old_clocks: Vec<SignalValue>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    pub clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Reused tick scratch: updated sequential assignments
    tick_updated: Vec<bool>,
    /// Reused tick scratch: prior clock values for iterative settle
    tick_clock_before: Vec<SignalValue>,
    /// Reused tick scratch: rising edges on clock domains
    tick_rising_clocks: Vec<bool>,
    /// Reused tick scratch: iterative derived rising edges on clock domains
    tick_derived_rising: Vec<bool>,
    /// Memory arrays
    pub memory_arrays: Vec<Vec<SignalValue>>,
    /// Overwide memory words above bit 127, little-endian 64-bit limbs.
    pub wide_memory_words: Vec<Vec<Vec<u64>>>,
    /// Memory name to index
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Compiled library (if compilation succeeded)
    pub compiled_lib: Option<CompiledLibrary>,
    #[cfg(not(feature = "aot"))]
    /// Cached compiled evaluate entry point
    pub compiled_eval_fn: Option<CompiledEvalFn>,
    #[cfg(not(feature = "aot"))]
    /// Cached compiled tick entry point when generated tick helpers are available
    pub compiled_tick_fn: Option<CompiledTickFn>,
    /// Whether compilation succeeded
    pub compiled: bool,
    /// Design contains over-128-bit state that the generated tick-helper path
    /// cannot yet compile directly.
    pub has_overwide_tick_helper_state: bool,
}

impl CoreSimulator {
    fn rustc_profile_for_generated_code(code: &str) -> (&'static str, &'static str, &'static str) {
        if code.len() > LARGE_RUSTC_SOURCE_BYTES_THRESHOLD {
            (
                LARGE_RUNTIME_RUSTC_OPT_LEVEL,
                LARGE_RUNTIME_RUSTC_CODEGEN_UNITS,
                RUNTIME_RUSTC_TARGET_CPU,
            )
        } else {
            (
                RUNTIME_RUSTC_OPT_LEVEL,
                RUNTIME_RUSTC_CODEGEN_UNITS,
                RUNTIME_RUSTC_TARGET_CPU,
            )
        }
    }

    fn resolve_signal_indices_in_ir(ir: &mut ModuleIR, name_to_idx: &HashMap<String, usize>) {
        for expr in &mut ir.exprs {
            Self::resolve_signal_indices_in_expr(expr, name_to_idx);
        }
        for assign in &mut ir.assigns {
            Self::resolve_signal_indices_in_expr(&mut assign.expr, name_to_idx);
        }
        for process in &mut ir.processes {
            for stmt in &mut process.statements {
                Self::resolve_signal_indices_in_expr(&mut stmt.expr, name_to_idx);
            }
        }
        for port in &mut ir.write_ports {
            Self::resolve_signal_indices_in_expr(&mut port.addr, name_to_idx);
            Self::resolve_signal_indices_in_expr(&mut port.data, name_to_idx);
            Self::resolve_signal_indices_in_expr(&mut port.enable, name_to_idx);
        }
        for port in &mut ir.sync_read_ports {
            Self::resolve_signal_indices_in_expr(&mut port.addr, name_to_idx);
            if let Some(enable) = &mut port.enable {
                Self::resolve_signal_indices_in_expr(enable, name_to_idx);
            }
        }
    }

    fn resolve_signal_indices_in_expr(expr: &mut ExprDef, name_to_idx: &HashMap<String, usize>) {
        match expr {
            ExprDef::Signal { name, width } => {
                if let Some(&idx) = name_to_idx.get(name) {
                    *expr = ExprDef::SignalIndex { idx, width: *width };
                }
            }
            ExprDef::SignalIndex { .. } | ExprDef::Literal { .. } | ExprDef::ExprRef { .. } => {}
            ExprDef::UnaryOp { operand, .. } => {
                Self::resolve_signal_indices_in_expr(operand, name_to_idx);
            }
            ExprDef::BinaryOp { left, right, .. } => {
                Self::resolve_signal_indices_in_expr(left, name_to_idx);
                Self::resolve_signal_indices_in_expr(right, name_to_idx);
            }
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                ..
            } => {
                Self::resolve_signal_indices_in_expr(condition, name_to_idx);
                Self::resolve_signal_indices_in_expr(when_true, name_to_idx);
                Self::resolve_signal_indices_in_expr(when_false, name_to_idx);
            }
            ExprDef::Slice { base, .. } => {
                Self::resolve_signal_indices_in_expr(base, name_to_idx);
            }
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::resolve_signal_indices_in_expr(part, name_to_idx);
                }
            }
            ExprDef::Resize { expr, .. } => {
                Self::resolve_signal_indices_in_expr(expr, name_to_idx);
            }
            ExprDef::MemRead { addr, .. } => {
                Self::resolve_signal_indices_in_expr(addr, name_to_idx);
            }
        }
    }

    fn prime_literal_runtime_values_in_ir(ir: &mut ModuleIR) {
        for expr in &mut ir.exprs {
            Self::prime_literal_runtime_values_in_expr(expr);
        }
        for assign in &mut ir.assigns {
            Self::prime_literal_runtime_values_in_expr(&mut assign.expr);
        }
        for process in &mut ir.processes {
            for stmt in &mut process.statements {
                Self::prime_literal_runtime_values_in_expr(&mut stmt.expr);
            }
        }
        for port in &mut ir.write_ports {
            Self::prime_literal_runtime_values_in_expr(&mut port.addr);
            Self::prime_literal_runtime_values_in_expr(&mut port.data);
            Self::prime_literal_runtime_values_in_expr(&mut port.enable);
        }
        for port in &mut ir.sync_read_ports {
            Self::prime_literal_runtime_values_in_expr(&mut port.addr);
            if let Some(enable) = &mut port.enable {
                Self::prime_literal_runtime_values_in_expr(enable);
            }
        }
    }

    fn prime_literal_runtime_values_in_expr(expr: &mut ExprDef) {
        match expr {
            ExprDef::Literal { value, width, parsed } => {
                if parsed.is_none() {
                    *parsed = Some(RuntimeValue::from_signed_text(value, *width));
                }
            }
            ExprDef::UnaryOp { operand, .. } => Self::prime_literal_runtime_values_in_expr(operand),
            ExprDef::BinaryOp { left, right, .. } => {
                Self::prime_literal_runtime_values_in_expr(left);
                Self::prime_literal_runtime_values_in_expr(right);
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                Self::prime_literal_runtime_values_in_expr(condition);
                Self::prime_literal_runtime_values_in_expr(when_true);
                Self::prime_literal_runtime_values_in_expr(when_false);
            }
            ExprDef::Slice { base, .. } => Self::prime_literal_runtime_values_in_expr(base),
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::prime_literal_runtime_values_in_expr(part);
                }
            }
            ExprDef::Resize { expr, .. } => Self::prime_literal_runtime_values_in_expr(expr),
            ExprDef::MemRead { addr, .. } => Self::prime_literal_runtime_values_in_expr(addr),
            ExprDef::Signal { .. } | ExprDef::SignalIndex { .. } | ExprDef::ExprRef { .. } => {}
        }
    }

    pub fn new(json: &str) -> Result<Self, String> {
        let mut ir = parse_module_ir(json)?;
        let expr_count = ir.exprs.len();

        let mut signals = Vec::new();
        let mut widths = Vec::new();
        let mut name_to_idx = HashMap::new();
        let mut input_names = Vec::new();
        let mut output_names = Vec::new();

        // Build signal table - ports first
        for port in &ir.ports {
            let idx = signals.len();
            signals.push(0u128);
            widths.push(port.width);
            name_to_idx.insert(port.name.clone(), idx);
            match port.direction {
                Direction::In => input_names.push(port.name.clone()),
                Direction::Out => output_names.push(port.name.clone()),
            }
        }

        // Then nets
        for net in &ir.nets {
            let idx = signals.len();
            signals.push(0u128);
            widths.push(net.width);
            name_to_idx.insert(net.name.clone(), idx);
        }

        // Then regs (with optional reset values)
        // Initialize signals with reset values directly (like monolithic version)
        let mut reset_values = Vec::new();
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

        // Build sequential assignment info
        let mut seq_exprs = Vec::new();
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_indices_set = HashSet::new();

        for (process_idx, process) in ir.processes.iter().enumerate() {
            if !process.clocked {
                continue;
            }
            let clk_name = process.clock.as_deref().unwrap_or("clk");
            let clk_idx = *name_to_idx.get(clk_name).unwrap_or(&0);
            clock_indices_set.insert(clk_idx);

            for (stmt_idx, stmt) in process.statements.iter().enumerate() {
                if let Some(&idx) = name_to_idx.get(&stmt.target) {
                    seq_exprs.push((process_idx, stmt_idx));
                    seq_targets.push(idx);
                    seq_clocks.push(clk_idx);
                }
            }
        }

        // Sort clock indices for deterministic ordering (HashSet iteration order is undefined)
        let mut clock_indices: Vec<usize> = clock_indices_set.into_iter().collect();
        clock_indices.sort();
        let clock_index_to_slot: HashMap<usize, usize> = clock_indices
            .iter()
            .enumerate()
            .map(|(slot, &clk_idx)| (clk_idx, slot))
            .collect();
        let old_clocks = vec![0u128; clock_indices.len()];
        let clock_domain_count = old_clocks.len();
        let next_regs = vec![0u128; seq_targets.len()];
        let seq_assign_count = next_regs.len();
        let wide_next_reg_words = seq_targets
            .iter()
            .map(|&target_idx| {
                let width = widths.get(target_idx).copied().unwrap_or(0);
                if width > 128 {
                    RuntimeValue::zero(width).high_words(width)
                } else {
                    Vec::new()
                }
            })
            .collect();
        let seq_clock_slots: Vec<usize> = seq_clocks
            .iter()
            .map(|clk_idx| clock_index_to_slot.get(clk_idx).copied().unwrap_or(0))
            .collect();

        // Pre-group assignments by clock domain
        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &domain_idx) in seq_clock_slots.iter().enumerate() {
            if domain_idx < clock_domain_assigns.len() {
                clock_domain_assigns[domain_idx].push((seq_idx, seq_targets[seq_idx]));
            }
        }

        // Initialize memory arrays
        let mut memory_arrays = Vec::new();
        let mut wide_memory_words = Vec::new();
        let mut memory_name_to_idx = HashMap::new();
        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut arr = vec![0u128; mem.depth];
            let high_word_template = RuntimeValue::zero(mem.width).high_words(mem.width);
            let mut high_arr = vec![high_word_template.clone(); mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < arr.len() {
                    arr[i] = val;
                    if mem.width > 128 {
                        high_arr[i] = RuntimeValue::from_u128(val, mem.width).high_words(mem.width);
                    }
                }
            }
            memory_arrays.push(arr);
            wide_memory_words.push(high_arr);
            memory_name_to_idx.insert(mem.name.clone(), idx);
        }

        Self::resolve_signal_indices_in_ir(&mut ir, &name_to_idx);
        Self::prime_literal_runtime_values_in_ir(&mut ir);
        let expr_ref_use_counts = Self::compute_expr_ref_use_counts(&ir);
        let expr_ref_complexities = Self::compute_expr_ref_complexities(&ir);

        let wide_signal_words: Vec<Vec<u64>> = widths
            .iter()
            .enumerate()
            .map(|(idx, &width)| {
                if width > 128 {
                    RuntimeValue::from_u128(signals[idx], width).high_words(width)
                } else {
                    Vec::new()
                }
            })
            .collect();
        let compiled_wide_signal_words = widths
            .iter()
            .enumerate()
            .map(|(idx, &width)| {
                if width > 128 {
                    let value = RuntimeValue::from_split_words(signals[idx], &wide_signal_words[idx], width);
                    Self::compiled_high_words_for_runtime_value(&value, width)
                } else {
                    [0; COMPILED_WIDE_SIGNAL_WORDS]
                }
            })
            .collect();
        let compiled_overwide_signal_ptrs = widths
            .iter()
            .enumerate()
            .map(|(idx, &width)| {
                if width > 256 {
                    wide_signal_words[idx].as_ptr()
                } else {
                    std::ptr::null()
                }
            })
            .collect();
        let has_overwide_tick_helper_state =
            widths.iter().any(|&width| width > 128) || ir.memories.iter().any(|memory| memory.width > 128);

        let mut sim = Self {
            ir,
            signals,
            wide_signal_words,
            compiled_wide_signal_words,
            compiled_overwide_signal_ptrs,
            widths,
            name_to_idx,
            expr_ref_use_counts,
            expr_ref_complexities,
            runtime_expr_cache: RefCell::new(RuntimeExprEvalCache::new(expr_count)),
            input_names,
            output_names,
            reset_values,
            comb_assigns: Vec::new(),
            runtime_comb_assigns: Vec::new(),
            compiled_comb_assign_indices: Vec::new(),
            next_regs,
            wide_next_reg_words,
            seq_exprs,
            seq_targets,
            seq_clocks,
            seq_clock_slots,
            clock_indices,
            old_clocks,
            clock_domain_assigns,
            tick_updated: vec![false; seq_assign_count],
            tick_clock_before: vec![0u128; clock_domain_count],
            tick_rising_clocks: vec![false; clock_domain_count],
            tick_derived_rising: vec![false; clock_domain_count],
            memory_arrays,
            wide_memory_words,
            memory_name_to_idx,
            compiled_lib: None,
            #[cfg(not(feature = "aot"))]
            compiled_eval_fn: None,
            #[cfg(not(feature = "aot"))]
            compiled_tick_fn: None,
            compiled: cfg!(feature = "aot"),
            has_overwide_tick_helper_state,
        };

        let levels = sim.compute_assignment_levels();
        let flat_assign_indices: Vec<usize> = levels
            .iter()
            .flat_map(|level| level.iter().copied())
            .collect();
        sim.comb_assigns = flat_assign_indices
            .iter()
            .filter_map(|&assign_idx| {
                let assign = sim.ir.assigns.get(assign_idx)?;
                sim.name_to_idx
                    .get(&assign.target)
                    .copied()
                    .map(|target_idx| (target_idx, assign_idx))
            })
            .collect();
        let (compiled_comb_assign_indices, runtime_comb_assigns) =
            sim.partition_compiled_comb_assigns(&flat_assign_indices);
        sim.compiled_comb_assign_indices = compiled_comb_assign_indices;
        sim.runtime_comb_assigns = runtime_comb_assigns;

        Ok(sim)
    }

    pub fn compute_mask(width: usize) -> SignalValue {
        wide_mask(width)
    }

    pub fn compile_fast_path_tick_helper_blocked(&self, include_tick_helpers: bool) -> bool {
        include_tick_helpers && self.has_overwide_tick_helper_state
    }

    fn supports_compiled_wide_width(width: usize) -> bool {
        width > 128 && width <= 256
    }

    fn expr_requires_runtime_eval(
        &self,
        expr: &ExprDef,
        runtime_signals: &HashSet<usize>,
    ) -> bool {
        match self.resolve_expr(expr) {
            ExprDef::Signal { name, width } => {
                if *width > 256 {
                    return true;
                }

                self.name_to_idx
                    .get(name)
                    .copied()
                    .map(|idx| runtime_signals.contains(&idx))
                    .unwrap_or(false)
            }
            ExprDef::SignalIndex { idx, width } => *width > 256 || runtime_signals.contains(idx),
            ExprDef::Literal { width, .. } => *width > 256,
            ExprDef::ExprRef { .. } => false,
            ExprDef::UnaryOp { operand, width, .. } => {
                *width > 256 || self.expr_requires_runtime_eval(operand, runtime_signals)
            }
            ExprDef::BinaryOp {
                op,
                left,
                right,
                width,
                ..
            } => {
                if *width > 256 {
                    return true;
                }
                if Self::supports_compiled_wide_width(*width) {
                    !matches!(op.as_str(), "|" | "&" | "^" | "<<" | ">>")
                        || self.expr_requires_runtime_eval(left, runtime_signals)
                        || self.expr_requires_runtime_eval(right, runtime_signals)
                } else {
                    self.expr_requires_runtime_eval(left, runtime_signals)
                        || self.expr_requires_runtime_eval(right, runtime_signals)
                }
            }
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                width,
            } => {
                *width > 256
                    || self.expr_requires_runtime_eval(condition, runtime_signals)
                    || self.expr_requires_runtime_eval(when_true, runtime_signals)
                    || self.expr_requires_runtime_eval(when_false, runtime_signals)
            }
            ExprDef::Slice { base, width, .. } => {
                if *width > 256 {
                    true
                } else {
                    match self.resolve_expr(base) {
                    ExprDef::Signal { width: base_width, .. }
                    | ExprDef::SignalIndex { width: base_width, .. }
                        if *base_width > 256 =>
                    {
                        false
                    }
                    _ => self.expr_requires_runtime_eval(base, runtime_signals),
                    }
                }
            }
            ExprDef::Concat { parts, width } => {
                *width > 256
                    || parts
                        .iter()
                        .any(|part| self.expr_requires_runtime_eval(part, runtime_signals))
            }
            ExprDef::Resize { expr, width } => {
                *width > 256 || self.expr_requires_runtime_eval(expr, runtime_signals)
            }
            ExprDef::MemRead {
                memory,
                addr,
                width,
            } => {
                *width > 128
                    || self
                        .memory_name_to_idx
                        .get(memory)
                        .and_then(|&idx| self.ir.memories.get(idx))
                        .map(|memory| memory.width > 128)
                        .unwrap_or(false)
                    || self.expr_requires_runtime_eval(addr, runtime_signals)
            }
        }
    }

    fn partition_compiled_comb_assigns(
        &self,
        assign_indices: &[usize],
    ) -> (Vec<usize>, Vec<(usize, usize)>) {
        let mut runtime_signals: HashSet<usize> = self
            .widths
            .iter()
            .enumerate()
            .filter_map(|(idx, &width)| if width > 256 { Some(idx) } else { None })
            .collect();

        loop {
            let mut changed = false;

            for &assign_idx in assign_indices {
                let Some(assign) = self.ir.assigns.get(assign_idx) else {
                    continue;
                };
                let Some(&target_idx) = self.name_to_idx.get(&assign.target) else {
                    continue;
                };

                let target_width = self.widths.get(target_idx).copied().unwrap_or(0);
                if target_width > 256
                    || runtime_signals.contains(&target_idx)
                    || self.expr_requires_runtime_eval(&assign.expr, &runtime_signals)
                {
                    changed |= runtime_signals.insert(target_idx);
                }
            }

            if !changed {
                break;
            }
        }

        let mut compiled_comb_assign_indices = Vec::new();
        let mut runtime_comb_assigns = Vec::new();

        for &assign_idx in assign_indices {
            let Some(assign) = self.ir.assigns.get(assign_idx) else {
                continue;
            };
            let Some(&target_idx) = self.name_to_idx.get(&assign.target) else {
                continue;
            };

            if runtime_signals.contains(&target_idx)
                || self.expr_requires_runtime_eval(&assign.expr, &runtime_signals)
            {
                runtime_comb_assigns.push((target_idx, assign_idx));
            } else {
                compiled_comb_assign_indices.push(assign_idx);
            }
        }

        (compiled_comb_assign_indices, runtime_comb_assigns)
    }

    fn signal_runtime_value(&self, idx: usize, width: usize) -> RuntimeValue {
        if width <= 128 {
            let low = self.signals.get(idx).copied().unwrap_or(0);
            return RuntimeValue::Narrow(low & Self::compute_mask(width));
        }
        let low = self.signals.get(idx).copied().unwrap_or(0);
        let high_words = self.wide_signal_words.get(idx).map(Vec::as_slice).unwrap_or(&[]);
        RuntimeValue::from_split_words(low, high_words, width).mask(width)
    }

    fn refresh_compiled_overwide_signal_ptr(&mut self, idx: usize, width: usize) {
        if idx >= self.compiled_overwide_signal_ptrs.len() {
            return;
        }

        self.compiled_overwide_signal_ptrs[idx] = if width > 256 {
            self.wide_signal_words
                .get(idx)
                .map(|words| words.as_ptr())
                .unwrap_or(std::ptr::null())
        } else {
            std::ptr::null()
        };
    }

    fn store_signal_runtime_value(&mut self, idx: usize, width: usize, value: RuntimeValue) {
        let masked = value.mask(width);
        self.signals[idx] = masked.low_u128() & Self::compute_mask(width.min(128));
        if width > 128 {
            self.wide_signal_words[idx] = masked.high_words(width);
            self.compiled_wide_signal_words[idx] =
                Self::compiled_high_words_for_runtime_value(&masked, width);
            self.refresh_compiled_overwide_signal_ptr(idx, width);
        } else if idx < self.compiled_wide_signal_words.len() {
            self.compiled_wide_signal_words[idx] = [0; COMPILED_WIDE_SIGNAL_WORDS];
            self.refresh_compiled_overwide_signal_ptr(idx, width);
        }
    }

    fn store_next_reg_runtime_value(&mut self, idx: usize, target_width: usize, value: RuntimeValue) {
        let masked = value.mask(target_width);
        self.next_regs[idx] = masked.low_u128() & Self::compute_mask(target_width.min(128));
        if target_width > 128 {
            self.wide_next_reg_words[idx] = masked.high_words(target_width);
        }
    }

    fn next_reg_runtime_value(&self, idx: usize, width: usize) -> RuntimeValue {
        if width <= 128 {
            let low = self.next_regs.get(idx).copied().unwrap_or(0);
            return RuntimeValue::Narrow(low & Self::compute_mask(width));
        }
        let low = self.next_regs.get(idx).copied().unwrap_or(0);
        let high_words = self.wide_next_reg_words.get(idx).map(Vec::as_slice).unwrap_or(&[]);
        RuntimeValue::from_split_words(low, high_words, width).mask(width)
    }

    fn compiled_high_words_for_runtime_value(
        value: &RuntimeValue,
        width: usize,
    ) -> [u64; COMPILED_WIDE_SIGNAL_WORDS] {
        let mut out = [0u64; COMPILED_WIDE_SIGNAL_WORDS];
        if width <= 128 {
            return out;
        }

        for (index, word) in value
            .high_words(width)
            .into_iter()
            .take(COMPILED_WIDE_SIGNAL_WORDS)
            .enumerate()
        {
            out[index] = word;
        }

        out
    }

    fn sync_compiled_wide_signal_words_from_fast_path(&mut self) {
        for idx in 0..self.widths.len() {
            let width = self.widths[idx];
            if width <= 128 || width > 256 {
                continue;
            }

            let word_count = width.div_ceil(64).saturating_sub(2);
            let Some(words) = self.wide_signal_words.get_mut(idx) else {
                continue;
            };
            words.resize(word_count, 0);
            for word_idx in 0..word_count.min(COMPILED_WIDE_SIGNAL_WORDS) {
                words[word_idx] = self.compiled_wide_signal_words[idx][word_idx];
            }
            for word_idx in COMPILED_WIDE_SIGNAL_WORDS..word_count {
                words[word_idx] = 0;
            }
            self.refresh_compiled_overwide_signal_ptr(idx, width);
        }
    }

    fn memory_runtime_value(&self, memory_idx: usize, width: usize, addr: usize) -> RuntimeValue {
        if width <= 128 {
            let low = self
                .memory_arrays
                .get(memory_idx)
                .and_then(|mem| mem.get(addr))
                .copied()
                .unwrap_or(0);
            return RuntimeValue::Narrow(low & Self::compute_mask(width));
        }
        let low = self
            .memory_arrays
            .get(memory_idx)
            .and_then(|mem| mem.get(addr))
            .copied()
            .unwrap_or(0);
        let high_words = self
            .wide_memory_words
            .get(memory_idx)
            .and_then(|mem| mem.get(addr))
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        RuntimeValue::from_split_words(low, high_words, width).mask(width)
    }

    fn store_memory_runtime_value(&mut self, memory_idx: usize, width: usize, addr: usize, value: RuntimeValue) {
        let masked = value.mask(width);
        let low = masked.low_u128() & Self::compute_mask(width.min(128));

        {
            let Some(mem) = self.memory_arrays.get_mut(memory_idx) else {
                return;
            };
            if addr >= mem.len() {
                return;
            }
            mem[addr] = low;
        }

        if width > 128 {
            if let Some(words) = self
                .wide_memory_words
                .get_mut(memory_idx)
                .and_then(|mem| mem.get_mut(addr))
            {
                *words = masked.high_words(width);
            }
        }

        if width <= 128 {
            self.write_compiled_memory_word(memory_idx, addr, low);
        }
    }

    fn runtime_shift_amount(value: &RuntimeValue, width: usize) -> usize {
        if width > 128 && !value.high_words(width).iter().all(|word| *word == 0) {
            return usize::MAX;
        }

        let low = value.low_u128();
        if low > usize::MAX as u128 {
            usize::MAX
        } else {
            low as usize
        }
    }

    fn compute_expr_ref_use_counts(ir: &ModuleIR) -> Vec<usize> {
        let mut counts = vec![0usize; ir.exprs.len()];

        for expr in &ir.exprs {
            Self::accumulate_direct_expr_ref_uses(expr, &mut counts);
        }
        for assign in &ir.assigns {
            Self::accumulate_direct_expr_ref_uses(&assign.expr, &mut counts);
        }
        for process in &ir.processes {
            for stmt in &process.statements {
                Self::accumulate_direct_expr_ref_uses(&stmt.expr, &mut counts);
            }
        }
        for port in &ir.write_ports {
            Self::accumulate_direct_expr_ref_uses(&port.addr, &mut counts);
            Self::accumulate_direct_expr_ref_uses(&port.data, &mut counts);
            Self::accumulate_direct_expr_ref_uses(&port.enable, &mut counts);
        }
        for port in &ir.sync_read_ports {
            Self::accumulate_direct_expr_ref_uses(&port.addr, &mut counts);
            if let Some(enable) = &port.enable {
                Self::accumulate_direct_expr_ref_uses(enable, &mut counts);
            }
        }

        counts
    }

    fn accumulate_direct_expr_ref_uses(expr: &ExprDef, counts: &mut [usize]) {
        match expr {
            ExprDef::Signal { .. } | ExprDef::SignalIndex { .. } | ExprDef::Literal { .. } => {}
            ExprDef::ExprRef { id, .. } => {
                if let Some(count) = counts.get_mut(*id) {
                    *count += 1;
                }
            }
            ExprDef::UnaryOp { operand, .. } => Self::accumulate_direct_expr_ref_uses(operand, counts),
            ExprDef::BinaryOp { left, right, .. } => {
                Self::accumulate_direct_expr_ref_uses(left, counts);
                Self::accumulate_direct_expr_ref_uses(right, counts);
            }
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                ..
            } => {
                Self::accumulate_direct_expr_ref_uses(condition, counts);
                Self::accumulate_direct_expr_ref_uses(when_true, counts);
                Self::accumulate_direct_expr_ref_uses(when_false, counts);
            }
            ExprDef::Slice { base, .. } => Self::accumulate_direct_expr_ref_uses(base, counts),
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::accumulate_direct_expr_ref_uses(part, counts);
                }
            }
            ExprDef::Resize { expr, .. } => Self::accumulate_direct_expr_ref_uses(expr, counts),
            ExprDef::MemRead { addr, .. } => Self::accumulate_direct_expr_ref_uses(addr, counts),
        }
    }

    pub fn mask_const(width: usize) -> String {
        if width == 0 {
            "0u128".to_string()
        } else if width >= 128 {
            "u128::MAX".to_string()
        } else {
            format!("0x{:X}u128", (1u128 << width) - 1)
        }
    }

    pub fn value_const(value: SignalValue) -> String {
        format!("0x{:X}u128", value)
    }

    fn expr_complexity_cap() -> u32 {
        SINGLE_USE_EXPR_MATERIALIZE_COMPLEXITY_THRESHOLD.saturating_add(1)
    }

    fn capped_expr_complexity_add(lhs: u32, rhs: u32) -> u32 {
        lhs.saturating_add(rhs).min(Self::expr_complexity_cap())
    }

    fn expr_inline_complexity(expr: &ExprDef, expr_ref_complexities: &[u32]) -> u32 {
        match expr {
            ExprDef::Signal { .. } | ExprDef::SignalIndex { .. } | ExprDef::Literal { .. } => 1,
            ExprDef::ExprRef { id, .. } => expr_ref_complexities
                .get(*id)
                .copied()
                .unwrap_or(1)
                .max(1),
            ExprDef::UnaryOp { operand, .. } => {
                Self::capped_expr_complexity_add(1, Self::expr_inline_complexity(operand, expr_ref_complexities))
            }
            ExprDef::BinaryOp { left, right, .. } => {
                let left_score = Self::expr_inline_complexity(left, expr_ref_complexities);
                let right_score = Self::expr_inline_complexity(right, expr_ref_complexities);
                Self::capped_expr_complexity_add(1, Self::capped_expr_complexity_add(left_score, right_score))
            }
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                ..
            } => {
                let cond = Self::expr_inline_complexity(condition, expr_ref_complexities);
                let when_true = Self::expr_inline_complexity(when_true, expr_ref_complexities);
                let when_false = Self::expr_inline_complexity(when_false, expr_ref_complexities);
                Self::capped_expr_complexity_add(
                    1,
                    Self::capped_expr_complexity_add(cond, Self::capped_expr_complexity_add(when_true, when_false)),
                )
            }
            ExprDef::Slice { base, .. } => {
                Self::capped_expr_complexity_add(1, Self::expr_inline_complexity(base, expr_ref_complexities))
            }
            ExprDef::Concat { parts, .. } => {
                let mut total = 1u32;
                for part in parts {
                    total = Self::capped_expr_complexity_add(
                        total,
                        Self::expr_inline_complexity(part, expr_ref_complexities),
                    );
                    if total >= Self::expr_complexity_cap() {
                        break;
                    }
                }
                total
            }
            ExprDef::Resize { expr, .. } => {
                Self::capped_expr_complexity_add(1, Self::expr_inline_complexity(expr, expr_ref_complexities))
            }
            ExprDef::MemRead { addr, .. } => {
                Self::capped_expr_complexity_add(1, Self::expr_inline_complexity(addr, expr_ref_complexities))
            }
        }
    }

    fn collect_expr_ref_ids(expr: &ExprDef, out: &mut Vec<usize>) {
        match expr {
            ExprDef::Signal { .. } | ExprDef::SignalIndex { .. } | ExprDef::Literal { .. } => {}
            ExprDef::ExprRef { id, .. } => out.push(*id),
            ExprDef::UnaryOp { operand, .. } => Self::collect_expr_ref_ids(operand, out),
            ExprDef::BinaryOp { left, right, .. } => {
                Self::collect_expr_ref_ids(left, out);
                Self::collect_expr_ref_ids(right, out);
            }
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                ..
            } => {
                Self::collect_expr_ref_ids(condition, out);
                Self::collect_expr_ref_ids(when_true, out);
                Self::collect_expr_ref_ids(when_false, out);
            }
            ExprDef::Slice { base, .. } => Self::collect_expr_ref_ids(base, out),
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::collect_expr_ref_ids(part, out);
                }
            }
            ExprDef::Resize { expr, .. } => Self::collect_expr_ref_ids(expr, out),
            ExprDef::MemRead { addr, .. } => Self::collect_expr_ref_ids(addr, out),
        }
    }

    fn compute_expr_ref_complexities(ir: &ModuleIR) -> Vec<u32> {
        let mut scores = vec![1u32; ir.exprs.len()];
        let mut state = vec![0u8; ir.exprs.len()];
        let mut deps = Vec::new();

        for start in 0..ir.exprs.len() {
            if state[start] == 2 {
                continue;
            }

            let mut stack = vec![(start, false)];
            while let Some((id, expanded)) = stack.pop() {
                if id >= ir.exprs.len() || state[id] == 2 {
                    continue;
                }

                if expanded {
                    scores[id] = Self::expr_inline_complexity(&ir.exprs[id], &scores);
                    state[id] = 2;
                    continue;
                }

                if state[id] == 1 {
                    continue;
                }

                state[id] = 1;
                stack.push((id, true));
                deps.clear();
                Self::collect_expr_ref_ids(&ir.exprs[id], &mut deps);
                for dep in deps.iter().rev() {
                    if *dep < ir.exprs.len() && state[*dep] == 0 {
                        stack.push((*dep, false));
                    }
                }
            }
        }

        scores
    }

    fn resolve_expr<'a>(&'a self, expr: &'a ExprDef) -> &'a ExprDef {
        match expr {
            ExprDef::ExprRef { id, .. } => self
                .ir
                .exprs
                .get(*id)
                .map(|inner| self.resolve_expr(inner))
                .unwrap_or(expr),
            _ => expr,
        }
    }

    pub fn expr_width(&self, expr: &ExprDef) -> usize {
        match self.resolve_expr(expr) {
            ExprDef::Signal { width, .. } => *width,
            ExprDef::SignalIndex { width, .. } => *width,
            ExprDef::Literal { width, .. } => *width,
            ExprDef::ExprRef { width, .. } => *width,
            ExprDef::UnaryOp { width, .. } => *width,
            ExprDef::BinaryOp { width, .. } => *width,
            ExprDef::Mux { width, .. } => *width,
            ExprDef::Slice { width, .. } => *width,
            ExprDef::Concat { width, .. } => *width,
            ExprDef::Resize { width, .. } => *width,
            ExprDef::MemRead { width, .. } => *width,
        }
    }

    fn same_repeatable_concat_expr(&self, lhs: &ExprDef, rhs: &ExprDef) -> bool {
        match (self.resolve_expr(lhs), self.resolve_expr(rhs)) {
            (
                ExprDef::Signal { name: lhs_name, width: lhs_width },
                ExprDef::Signal { name: rhs_name, width: rhs_width },
            ) => lhs_name == rhs_name && lhs_width == rhs_width,
            (
                ExprDef::SignalIndex { idx: lhs_idx, width: lhs_width },
                ExprDef::SignalIndex { idx: rhs_idx, width: rhs_width },
            ) => lhs_idx == rhs_idx && lhs_width == rhs_width,
            (
                ExprDef::Literal { value: lhs_value, width: lhs_width, .. },
                ExprDef::Literal { value: rhs_value, width: rhs_width, .. },
            ) => lhs_value == rhs_value && lhs_width == rhs_width,
            (
                ExprDef::Slice { base: lhs_base, low: lhs_low, width: lhs_width, .. },
                ExprDef::Slice { base: rhs_base, low: rhs_low, width: rhs_width, .. },
            ) => lhs_low == rhs_low && lhs_width == rhs_width && self.same_repeatable_concat_expr(lhs_base, rhs_base),
            _ => false,
        }
    }

    fn repeated_concat_part<'a>(&self, parts: &'a [ExprDef], total_width: usize) -> Option<(&'a ExprDef, usize, usize)> {
        let first = parts.first()?;
        let part_width = self.expr_width(first);
        if part_width == 0 {
            return None;
        }

        let repeat_count = parts.len();
        if part_width.saturating_mul(repeat_count) != total_width {
            return None;
        }

        if !parts
            .iter()
            .all(|part| self.expr_width(part) == part_width && self.same_repeatable_concat_expr(first, part))
        {
            return None;
        }

        Some((first, part_width, repeat_count))
    }

    pub fn compile_fast_path_blocker(&self, include_tick_helpers: bool) -> Option<String> {
        if self.compile_fast_path_tick_helper_blocked(include_tick_helpers) {
            return Some(
                "compiled fast path does not support overwide (>128-bit) runtime signals when tick helpers are required"
                    .to_string(),
            );
        }

        if !self.runtime_comb_assigns.is_empty() {
            let samples = self
                .runtime_comb_assigns
                .iter()
                .take(8)
                .filter_map(|(_, assign_idx)| self.ir.assigns.get(*assign_idx))
                .map(|assign| assign.target.clone())
                .collect::<Vec<_>>();
            let sample_text = if samples.is_empty() {
                String::new()
            } else {
                format!("; first targets: {}", samples.join(", "))
            };
            return Some(format!(
                "compiled fast path requires runtime fallback for {} combinational assigns{}",
                self.runtime_comb_assigns.len(),
                sample_text
            ));
        }

        None
    }

    fn shed_compiled_ir_state(&mut self) {
        if !self.runtime_comb_assigns.is_empty() {
            return;
        }

        self.comb_assigns.clear();
        self.comb_assigns.shrink_to_fit();
        self.clock_domain_assigns.clear();
        self.clock_domain_assigns.shrink_to_fit();

        self.ir.name.clear();
        self.ir.ports.clear();
        self.ir.ports.shrink_to_fit();
        self.ir.nets.clear();
        self.ir.nets.shrink_to_fit();
        self.ir.regs.clear();
        self.ir.regs.shrink_to_fit();
        self.ir.assigns.clear();
        self.ir.assigns.shrink_to_fit();
        self.expr_ref_use_counts.clear();
        self.expr_ref_use_counts.shrink_to_fit();
        self.expr_ref_complexities.clear();
        self.expr_ref_complexities.shrink_to_fit();

        for process in &mut self.ir.processes {
            process.name.clear();
            process.clock = None;
            for stmt in &mut process.statements {
                stmt.target.clear();
            }
        }
    }

    pub fn shed_batched_gameboy_state(&mut self) {
        if !self.runtime_comb_assigns.is_empty() {
            return;
        }

        self.shed_compiled_ir_state();

        self.reset_values.clear();
        self.reset_values.shrink_to_fit();
        self.next_regs.clear();
        self.next_regs.shrink_to_fit();
        self.seq_exprs.clear();
        self.seq_exprs.shrink_to_fit();
        self.seq_targets.clear();
        self.seq_targets.shrink_to_fit();
        self.seq_clocks.clear();
        self.seq_clocks.shrink_to_fit();
        self.clock_indices.clear();
        self.clock_indices.shrink_to_fit();
        self.old_clocks.clear();
        self.old_clocks.shrink_to_fit();

        self.ir.exprs.clear();
        self.ir.exprs.shrink_to_fit();
        self.ir.processes.clear();
        self.ir.processes.shrink_to_fit();
        self.ir.write_ports.clear();
        self.ir.write_ports.shrink_to_fit();
        self.ir.sync_read_ports.clear();
        self.ir.sync_read_ports.shrink_to_fit();
        for memory in &mut self.ir.memories {
            memory.initial_data.clear();
            memory.initial_data.shrink_to_fit();
        }

        self.memory_arrays.clear();
        self.memory_arrays.shrink_to_fit();
        self.wide_memory_words.clear();
        self.wide_memory_words.shrink_to_fit();
    }

    #[inline(always)]
    fn evaluate_compiled_without_clock_capture(&mut self) {
        if !self.compiled {
            return;
        }
        #[cfg(feature = "aot")]
        unsafe {
            crate::aot_generated::evaluate(
                self.signals.as_mut_ptr(),
                self.compiled_wide_signal_words.as_ptr() as *const u64,
                self.compiled_overwide_signal_ptrs.as_ptr(),
                self.signals.len(),
            );
        }
        #[cfg(not(feature = "aot"))]
        {
            let func = self
                .compiled_eval_fn
                .expect("compiled evaluate function not bound");
            unsafe {
                func(
                    self.signals.as_mut_ptr(),
                    self.compiled_wide_signal_words.as_ptr() as *const u64,
                    self.compiled_overwide_signal_ptrs.as_ptr(),
                    self.signals.len(),
                );
            }
        }

        self.sync_compiled_wide_signal_words_from_fast_path();

        if self.runtime_comb_assigns.is_empty() {
            return;
        }

        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for assign_pos in 0..self.runtime_comb_assigns.len() {
                let (target_idx, assign_idx) = self.runtime_comb_assigns[assign_pos];
                let Some(assign) = self.ir.assigns.get(assign_idx) else {
                    continue;
                };
                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                let value = self.eval_expr_runtime_value_with_cache(&assign.expr, &mut *cache);
                self.store_signal_runtime_value(target_idx, width, value);
            }
        }
    }

    fn runtime_expr_width(&self, expr: &ExprDef) -> usize {
        match expr {
            ExprDef::Signal { width, .. }
            | ExprDef::SignalIndex { width, .. }
            | ExprDef::Literal { width, .. }
            | ExprDef::ExprRef { width, .. }
            | ExprDef::UnaryOp { width, .. }
            | ExprDef::BinaryOp { width, .. }
            | ExprDef::Mux { width, .. }
            | ExprDef::Slice { width, .. }
            | ExprDef::Concat { width, .. }
            | ExprDef::Resize { width, .. }
            | ExprDef::MemRead { width, .. } => *width,
        }
    }

    fn eval_expr_runtime_value_with_cache(
        &self,
        expr: &ExprDef,
        cache: &mut RuntimeExprEvalCache,
    ) -> RuntimeValue {
        match expr {
            ExprDef::ExprRef { id, width } => {
                let should_cache = self
                    .expr_ref_use_counts
                    .get(*id)
                    .copied()
                    .unwrap_or(0)
                    > 1;
                if should_cache {
                    if let Some(value) = cache.get(*id) {
                        return value;
                    }
                }
                let value = self
                    .ir
                    .exprs
                    .get(*id)
                    .map(|inner| self.eval_expr_runtime_value_with_cache(inner, cache))
                    .unwrap_or_else(|| RuntimeValue::zero(*width));
                if should_cache {
                    cache.store(*id, value.clone());
                }
                value
            }
            _ => match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                self.signal_runtime_value(idx, *width)
            }
            ExprDef::SignalIndex { idx, width } => self.signal_runtime_value(*idx, *width),
            ExprDef::Literal { value, width, parsed } => {
                parsed.clone().unwrap_or_else(|| RuntimeValue::from_signed_text(value, *width))
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.eval_expr_runtime_value_with_cache(operand, cache);
                match op.as_str() {
                    "~" | "not" => RuntimeValue::from_u128(Self::compute_mask(*width), *width)
                        .bitxor(&src, *width),
                    "&" | "reduce_and" => {
                        let op_width = self.runtime_expr_width(operand);
                        RuntimeValue::from_u128(if src.reduce_and(op_width) { 1 } else { 0 }, *width)
                    }
                    "|" | "reduce_or" => RuntimeValue::from_u128(if src.is_zero() { 0 } else { 1 }, *width),
                    "^" | "reduce_xor" => RuntimeValue::from_u128(src.reduce_xor(), *width),
                    _ => src.mask(*width),
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr_runtime_value_with_cache(left, cache);
                let r = self.eval_expr_runtime_value_with_cache(right, cache);
                match op.as_str() {
                    "&" => l.bitand(&r, *width),
                    "|" => l.bitor(&r, *width),
                    "^" => l.bitxor(&r, *width),
                    "+" => l.add(&r, *width),
                    "-" => l.sub(&r, *width),
                    "*" => l.mul(&r, *width),
                    "/" => {
                        let lhs = l.low_u128();
                        let rhs = r.low_u128();
                        RuntimeValue::from_u128(if rhs == 0 { 0 } else { lhs / rhs }, *width)
                    }
                    "%" => {
                        let lhs = l.low_u128();
                        let rhs = r.low_u128();
                        RuntimeValue::from_u128(if rhs == 0 { 0 } else { lhs % rhs }, *width)
                    }
                    "<<" => {
                        let shift = Self::runtime_shift_amount(&r, self.runtime_expr_width(right));
                        if shift == usize::MAX { RuntimeValue::zero(*width) } else { l.shl(shift, *width) }
                    }
                    ">>" => {
                        let shift = Self::runtime_shift_amount(&r, self.runtime_expr_width(right));
                        if shift == usize::MAX { RuntimeValue::zero(*width) } else { l.shr(shift, *width) }
                    }
                    "==" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) == std::cmp::Ordering::Equal) as u128, *width),
                    "!=" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) != std::cmp::Ordering::Equal) as u128, *width),
                    "<" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) == std::cmp::Ordering::Less) as u128, *width),
                    ">" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) == std::cmp::Ordering::Greater) as u128, *width),
                    "<=" | "le" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) != std::cmp::Ordering::Greater) as u128, *width),
                    ">=" => RuntimeValue::from_u128((l.cmp_unsigned(&r, self.runtime_expr_width(left).max(self.runtime_expr_width(right))) != std::cmp::Ordering::Less) as u128, *width),
                    _ => l.mask(*width),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.eval_expr_runtime_value_with_cache(condition, cache);
                let selected = if cond.is_zero() {
                    self.eval_expr_runtime_value_with_cache(when_false, cache)
                } else {
                    self.eval_expr_runtime_value_with_cache(when_true, cache)
                };
                selected.mask(*width)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_val = self.eval_expr_runtime_value_with_cache(base, cache);
                base_val.slice(*low, *width)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = RuntimeValue::zero(*width);
                for part in parts {
                    let part_width = self.runtime_expr_width(part);
                    let value = self.eval_expr_runtime_value_with_cache(part, cache);
                    result = result.shl(part_width, *width);
                    result = result.bitor(&value.mask(part_width), *width);
                }
                result.mask(*width)
            }
            ExprDef::Resize { expr, width } => self
                .eval_expr_runtime_value_with_cache(expr, cache)
                .resize(*width),
            ExprDef::MemRead { memory, addr, width } => {
                let Some(&memory_idx) = self.memory_name_to_idx.get(memory) else {
                    return RuntimeValue::zero(*width);
                };
                let Some(mem) = self.memory_arrays.get(memory_idx) else {
                    return RuntimeValue::zero(*width);
                };
                if mem.is_empty() {
                    return RuntimeValue::zero(*width);
                }
                let addr_val =
                    self.eval_expr_runtime_value_with_cache(addr, cache).low_u128() as usize % mem.len();
                let memory_width = self.ir.memories.get(memory_idx).map(|mem| mem.width).unwrap_or(*width);
                self.memory_runtime_value(memory_idx, memory_width, addr_val).resize(*width)
            }
            ExprDef::ExprRef { .. } => RuntimeValue::zero(1),
        },
        }
    }

    fn sample_next_regs_runtime(&mut self) {
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for idx in 0..self.seq_exprs.len() {
                let (process_idx, stmt_idx) = self.seq_exprs[idx];
                let Some(process) = self.ir.processes.get(process_idx) else {
                    continue;
                };
                let Some(stmt) = process.statements.get(stmt_idx) else {
                    continue;
                };
                let target_idx = self.seq_targets.get(idx).copied().unwrap_or(0);
                let target_width = self.widths.get(target_idx).copied().unwrap_or(0);
                let value = self.eval_expr_runtime_value_with_cache(&stmt.expr, &mut *cache);
                self.store_next_reg_runtime_value(idx, target_width, value);
            }
        }
    }

    fn write_compiled_memory_word(&self, memory_idx: usize, addr: usize, value: SignalValue) {
        if !self.compiled {
            return;
        }

        #[cfg(feature = "aot")]
        unsafe {
            crate::aot_generated::mem_write_word(memory_idx as u32, addr as u32, value);
        }

        #[cfg(not(feature = "aot"))]
        if let Some(ref lib) = self.compiled_lib {
            unsafe {
                type MemWriteWordFn = unsafe extern "C" fn(u32, u32, SignalValue);
                if let Ok(func) = lib.get::<MemWriteWordFn>(b"mem_write_word") {
                    func(memory_idx as u32, addr as u32, value);
                }
            }
        }
    }

    fn apply_write_ports_runtime(&mut self) {
        if self.ir.write_ports.is_empty() {
            return;
        }

        let mut writes: Vec<(usize, usize, usize, RuntimeValue)> = Vec::new();
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for wp in &self.ir.write_ports {
                let Some(&memory_idx) = self.memory_name_to_idx.get(&wp.memory) else {
                    continue;
                };
                let Some(memory) = self.ir.memories.get(memory_idx) else {
                    continue;
                };
                if memory.depth == 0 {
                    continue;
                }
                let Some(&clock_idx) = self.name_to_idx.get(&wp.clock) else {
                    continue;
                };
                if self.signals.get(clock_idx).copied().unwrap_or(0) == 0 {
                    continue;
                }
                if (self.eval_expr_runtime_value_with_cache(&wp.enable, &mut *cache).low_u128() & 1) == 0 {
                    continue;
                }

                let addr = (self.eval_expr_runtime_value_with_cache(&wp.addr, &mut *cache).low_u128() as usize) % memory.depth;
                let data = self.eval_expr_runtime_value_with_cache(&wp.data, &mut *cache).mask(memory.width);
                writes.push((memory_idx, addr, memory.width, data));
            }
        }

        for (memory_idx, addr, width, value) in writes {
            self.store_memory_runtime_value(memory_idx, width, addr, value);
        }
    }

    fn apply_sync_read_ports_runtime(&mut self) {
        if self.ir.sync_read_ports.is_empty() {
            return;
        }

        let mut updates: Vec<(usize, usize, RuntimeValue)> = Vec::new();
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for rp in &self.ir.sync_read_ports {
                let Some(&memory_idx) = self.memory_name_to_idx.get(&rp.memory) else {
                    continue;
                };
                let Some(mem) = self.memory_arrays.get(memory_idx) else {
                    continue;
                };
                if mem.is_empty() {
                    continue;
                }
                let Some(&clock_idx) = self.name_to_idx.get(&rp.clock) else {
                    continue;
                };
                if self.signals.get(clock_idx).copied().unwrap_or(0) == 0 {
                    continue;
                }
                if let Some(enable) = &rp.enable {
                    if (self.eval_expr_runtime_value_with_cache(enable, &mut *cache).low_u128() & 1) == 0 {
                        continue;
                    }
                }
                let Some(&data_idx) = self.name_to_idx.get(&rp.data) else {
                    continue;
                };
                let data_width = self.widths.get(data_idx).copied().unwrap_or(64);
                let addr = (self.eval_expr_runtime_value_with_cache(&rp.addr, &mut *cache).low_u128() as usize) % mem.len();
                let memory_width = self.ir.memories.get(memory_idx).map(|memory| memory.width).unwrap_or(data_width);
                let data = self.memory_runtime_value(memory_idx, memory_width, addr).resize(data_width);
                updates.push((data_idx, data_width, data));
            }
        }

        for (idx, width, value) in updates {
            if idx < self.signals.len() {
                self.store_signal_runtime_value(idx, width, value);
            }
        }
    }

    pub fn evaluate(&mut self) {
        self.evaluate_compiled_without_clock_capture();

        // Update old_clocks to current clock values after evaluation
        // This ensures that after poke('clk', 0); evaluate(), old_clocks will be 0,
        // so the subsequent tick() will properly detect the rising edge (0->1)
        for (list_idx, &clk_idx) in self.clock_indices.iter().enumerate() {
            if list_idx < self.old_clocks.len() {
                self.old_clocks[list_idx] = self.signals[clk_idx];
            }
        }
    }

    pub fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        self.poke_wide(name, value as SignalValue)
    }

    pub fn poke_wide(&mut self, name: &str, value: SignalValue) -> Result<(), String> {
        if let Some(&idx) = self.name_to_idx.get(name) {
            let width = self.widths.get(idx).copied().unwrap_or(64);
            self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(value, width));
            Ok(())
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    pub fn peek(&self, name: &str) -> Result<u64, String> {
        Ok(self.peek_wide(name)? as u64)
    }

    pub fn peek_wide(&self, name: &str) -> Result<SignalValue, String> {
        if let Some(&idx) = self.name_to_idx.get(name) {
            let width = self.widths.get(idx).copied().unwrap_or(64);
            Ok(self.signal_runtime_value(idx, width).low_u128())
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    pub fn poke_word_by_name(&mut self, name: &str, word_idx: usize, value: u64) -> Result<(), String> {
        if let Some(&idx) = self.name_to_idx.get(name) {
            self.poke_word_by_idx(idx, word_idx, value);
            Ok(())
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    pub fn peek_word_by_name(&self, name: &str, word_idx: usize) -> Result<u64, String> {
        if let Some(&idx) = self.name_to_idx.get(name) {
            Ok(self.peek_word_by_idx(idx, word_idx))
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    #[inline(always)]
    pub fn poke_by_idx(&mut self, idx: usize, value: u64) {
        self.poke_wide_by_idx(idx, value as SignalValue);
    }

    #[inline(always)]
    pub fn poke_wide_by_idx(&mut self, idx: usize, value: SignalValue) {
        if idx < self.signals.len() {
            let width = self.widths.get(idx).copied().unwrap_or(64);
            self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(value, width));
        }
    }

    #[inline(always)]
    pub fn poke_word_by_idx(&mut self, idx: usize, word_idx: usize, value: u64) {
        if idx >= self.signals.len() {
            return;
        }
        let width = self.widths.get(idx).copied().unwrap_or(0);
        let current = self.signal_runtime_value(idx, width);
        let updated = current.with_word(width, word_idx, value);
        self.store_signal_runtime_value(idx, width, updated);
    }

    #[inline(always)]
    pub fn peek_by_idx(&self, idx: usize) -> u64 {
        self.peek_wide_by_idx(idx) as u64
    }

    #[inline(always)]
    pub fn peek_wide_by_idx(&self, idx: usize) -> SignalValue {
        if idx < self.signals.len() {
            let width = self.widths.get(idx).copied().unwrap_or(64);
            self.signal_runtime_value(idx, width).low_u128()
        } else {
            0
        }
    }

    #[inline(always)]
    pub fn peek_word_by_idx(&self, idx: usize, word_idx: usize) -> u64 {
        if idx < self.signals.len() {
            let width = self.widths.get(idx).copied().unwrap_or(0);
            self.signal_runtime_value(idx, width).word(width, word_idx)
        } else {
            0
        }
    }

    pub fn get_signal_idx(&self, name: &str) -> Option<usize> {
        self.name_to_idx.get(name).copied()
    }

    pub fn tick(&mut self) {
        if !self.compiled {
            return;
        }

        #[cfg(not(feature = "aot"))]
        if let Some(func) = self.compiled_tick_fn {
            unsafe {
                func(
                    self.signals.as_mut_ptr(),
                    self.signals.len(),
                    self.old_clocks.as_mut_ptr(),
                    self.next_regs.as_mut_ptr(),
                );
            }
            return;
        }

        // Mirror the JIT runtime semantics for sequential sampling and memory
        // ports. AO486 import trees exercise nested mux chains that the fully
        // generated tick path does not currently handle reliably.
        self.evaluate_compiled_without_clock_capture();
        self.apply_write_ports_runtime();
        self.sample_next_regs_runtime();

        self.tick_updated.fill(false);
        self.tick_rising_clocks.fill(false);
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            let before = self.old_clocks.get(i).copied().unwrap_or(0);
            let after = self.signals.get(clk_idx).copied().unwrap_or(0);
            if before == 0 && after == 1 {
                self.tick_rising_clocks[i] = true;
            }
        }

        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
            let clock_slot = self.seq_clock_slots.get(i).copied().unwrap_or(0);
            if self.tick_rising_clocks.get(clock_slot).copied().unwrap_or(false) && !self.tick_updated[i] {
                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                let value = self.next_reg_runtime_value(i, width);
                self.store_signal_runtime_value(target_idx, width, value);
                self.tick_updated[i] = true;
            }
        }

        for _iteration in 0..10 {
            for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
                self.tick_clock_before[i] = self.signals.get(clk_idx).copied().unwrap_or(0);
            }
            self.tick_derived_rising.fill(false);

            self.evaluate_compiled_without_clock_capture();
            self.apply_write_ports_runtime();
            self.sample_next_regs_runtime();

            let mut any_rising = false;
            for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
                let before = self.tick_clock_before[i];
                let after = self.signals.get(clk_idx).copied().unwrap_or(0);
                if before == 0 && after == 1 {
                    self.tick_derived_rising[i] = true;
                    any_rising = true;
                }
            }

            if !any_rising {
                break;
            }

            for i in 0..self.seq_targets.len() {
                let target_idx = self.seq_targets[i];
                let clock_slot = self.seq_clock_slots.get(i).copied().unwrap_or(0);
                if self.tick_derived_rising.get(clock_slot).copied().unwrap_or(false) && !self.tick_updated[i] {
                    let width = self.widths.get(target_idx).copied().unwrap_or(0);
                    let value = self.next_reg_runtime_value(i, width);
                    self.store_signal_runtime_value(target_idx, width, value);
                    self.tick_updated[i] = true;
                }
            }
        }

        self.apply_sync_read_ports_runtime();
        self.evaluate_compiled_without_clock_capture();

        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            if i < self.old_clocks.len() {
                self.old_clocks[i] = self.signals.get(clk_idx).copied().unwrap_or(0);
            }
        }
    }

    #[inline(always)]
    pub fn tick_forced(&mut self) {
        // The compiler core already uses old_clocks from the previous phase as
        // the "before" edge values and updates them at the end of tick().
        // That matches the forced two-phase runner usage in the other backends.
        self.tick();
    }

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for words in self.wide_signal_words.iter_mut() {
            words.fill(0);
        }
        for reset_idx in 0..self.reset_values.len() {
            let (idx, reset_val) = self.reset_values[reset_idx];
            let width = self.widths.get(idx).copied().unwrap_or(0);
            self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(reset_val, width));
        }
        for val in self.next_regs.iter_mut() {
            *val = 0;
        }
        for words in self.wide_next_reg_words.iter_mut() {
            words.fill(0);
        }
        for val in self.old_clocks.iter_mut() {
            *val = 0;
        }

        // Reset IR memory arrays to their declared initial contents.
        // This mirrors interpreter/JIT reset behavior so compiled runs
        // do not leak register/memory state across resets.
        for (mem_idx, mem_def) in self.ir.memories.iter().enumerate() {
            let Some(mem_len) = self.memory_arrays.get(mem_idx).map(|mem| mem.len()) else {
                continue;
            };
            if let Some(mem) = self.memory_arrays.get_mut(mem_idx) {
                mem.fill(0);
            }
            if let Some(high_words) = self.wide_memory_words.get_mut(mem_idx) {
                for words in high_words.iter_mut() {
                    words.fill(0);
                }
            }
            for (i, &val) in mem_def.initial_data.iter().enumerate() {
                if i < mem_len {
                    if let Some(mem) = self.memory_arrays.get_mut(mem_idx) {
                        mem[i] = val;
                    }
                    if mem_def.width > 128 {
                        if let Some(words) = self
                            .wide_memory_words
                            .get_mut(mem_idx)
                            .and_then(|high_words| high_words.get_mut(i))
                        {
                            *words = RuntimeValue::from_u128(val, mem_def.width).high_words(mem_def.width);
                        }
                    }
                }
            }
        }

        // For compiled cores, memory state lives in generated `static mut`
        // arrays, so we must also run the compiled memory initializer.
        let _ = self.init_compiled_memories();
    }

    pub fn signal_count(&self) -> usize {
        self.signals.len()
    }

    pub fn reg_count(&self) -> usize {
        self.seq_targets.len()
    }

    // ========================================================================
    // Dependency Analysis
    // ========================================================================

    /// Extract signal indices that an expression depends on
    pub fn expr_dependencies(&self, expr: &ExprDef) -> HashSet<usize> {
        let mut deps = HashSet::new();
        self.collect_expr_deps(expr, &mut deps);
        deps
    }

    fn collect_expr_deps(&self, expr: &ExprDef, deps: &mut HashSet<usize>) {
        match self.resolve_expr(expr) {
            ExprDef::Signal { name, .. } => {
                if let Some(&idx) = self.name_to_idx.get(name) {
                    deps.insert(idx);
                }
            }
            ExprDef::SignalIndex { idx, .. } => {
                deps.insert(*idx);
            }
            ExprDef::Literal { .. } => {}
            ExprDef::ExprRef { .. } => {}
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

    /// Group assignments into levels based on dependencies
    /// Each level contains assignments that can be computed in parallel
    pub fn compute_assignment_levels(&self) -> Vec<Vec<usize>> {
        let assigns = &self.ir.assigns;
        let n = assigns.len();

        // Map: target signal idx -> ALL assignment indices that write to it
        // This is needed because signals like set_addr_to may have many conditional
        // mux assignments, and any reader needs to depend on ALL of them
        let mut target_to_assigns: HashMap<usize, Vec<usize>> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                target_to_assigns.entry(idx).or_insert_with(Vec::new).push(i);
            }
        }

        // Compute dependencies for each assignment (in terms of other assignment indices)
        let mut assign_deps: Vec<HashSet<usize>> = Vec::with_capacity(n);
        for assign in assigns {
            let signal_deps = self.expr_dependencies(&assign.expr);
            let mut deps = HashSet::new();
            for sig_idx in signal_deps {
                // Add dependencies on ALL assignments to this signal
                if let Some(assign_indices) = target_to_assigns.get(&sig_idx) {
                    for &assign_idx in assign_indices {
                        deps.insert(assign_idx);
                    }
                }
            }
            assign_deps.push(deps);
        }

        // Assign levels (topological sort into levels)
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

        levels
    }

    /// Find ALL clock domain indices that are derived from a given input clock signal
    /// This traces signal propagation to find which clocks in clock_indices
    /// are derived from the input clock (either directly or via assignment)
    pub fn find_clock_domains_for_input(&self, input_clk_idx: usize) -> Vec<usize> {
        let mut domains = Vec::new();

        // First check if input clock is directly in clock_indices
        if let Some(pos) = self.clock_indices.iter().position(|&ci| ci == input_clk_idx) {
            domains.push(pos);
        }

        // Find all signals that are direct copies of the input clock
        // These are assignments of the form: signals[X] = signals[input_clk_idx]
        for assign in &self.ir.assigns {
            let source_idx = match self.resolve_expr(&assign.expr) {
                ExprDef::Signal { name, .. } => self.name_to_idx.get(name).copied(),
                ExprDef::SignalIndex { idx, .. } => Some(*idx),
                _ => None,
            };
            if source_idx == Some(input_clk_idx) {
                // Found an assignment that copies from input clock
                if let Some(&target_idx) = self.name_to_idx.get(&assign.target) {
                    // Check if this target is in clock_indices
                    if let Some(pos) = self.clock_indices.iter().position(|&ci| ci == target_idx) {
                        if !domains.contains(&pos) {
                            domains.push(pos);
                        }
                    }
                }
            }
        }

        // If no domains found, try all domains as fallback (single-clock design assumption)
        if domains.is_empty() && !self.clock_indices.is_empty() {
            domains.extend(0..self.clock_indices.len());
        }

        domains
    }

    // ========================================================================
    // Code Generation
    // ========================================================================

    /// Generate core evaluation and tick code (without example-specific extensions)
    pub fn generate_core_code(&self, include_tick_helpers: bool) -> String {
        let mut code = String::new();

        code.push_str("//! Auto-generated circuit simulation code\n");
        code.push_str("//! Generated by RHDL IR Compiler (Core)\n\n");

        // Generate mutable memory arrays.
        //
        // The compiled backend needs to support runtime memory loading (e.g. Disk II ROM/track data),
        // so we generate `static mut` arrays and expose a C ABI to write them.
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!("const MEM_{}_DEPTH: usize = {};\n", idx, mem.depth));
            code.push_str(&format!(
                "static mut MEM_{}: [u128; MEM_{}_DEPTH] = [0u128; MEM_{}_DEPTH];\n\n",
                idx, idx, idx
            ));
        }

        // Initialize memories with non-zero initial data (ROMs).
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn init_memories() {\n");
        for (idx, _mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!(
                "    for i in 0..MEM_{}_DEPTH {{ MEM_{}[i] = 0u128; }}\n",
                idx, idx
            ));
        }
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if val != 0 {
                    code.push_str(&format!(
                        "    MEM_{}[{}] = {};\n",
                        idx,
                        i,
                        Self::value_const(val)
                    ));
                }
            }
        }
        code.push_str("}\n\n");

        // Bulk memory write (byte-wise) for runtime loading.
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn mem_write_bytes(mem_idx: u32, offset: u32, data: *const u8, data_len: usize) {\n");
        code.push_str("    if data.is_null() { return; }\n");
        code.push_str("    let data = std::slice::from_raw_parts(data, data_len);\n");
        code.push_str("    match mem_idx {\n");
        for (idx, _mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!(
                "        {} => {{ let depth = MEM_{}_DEPTH; for (i, &b) in data.iter().enumerate() {{ MEM_{}[(offset as usize + i) % depth] = b as u128; }} }},\n",
                idx, idx, idx
            ));
        }
        code.push_str("        _ => {}\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");

        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn mem_write_word(mem_idx: u32, offset: u32, value: u128) {\n");
        code.push_str("    match mem_idx {\n");
        for (idx, _mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!(
                "        {} => {{ let depth = MEM_{}_DEPTH; if depth != 0 {{ MEM_{}[(offset as usize) % depth] = value; }} }},\n",
                idx, idx, idx
            ));
        }
        code.push_str("        _ => {}\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");

        code.push_str("#[derive(Clone, Copy)]\n");
        code.push_str("struct WideValue256 { words: [u64; 4] }\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_zero() -> WideValue256 { WideValue256 { words: [0u64; 4] } }\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_from_u128(value: u128) -> WideValue256 {\n");
        code.push_str("    WideValue256 { words: [value as u64, (value >> 64) as u64, 0u64, 0u64] }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_word_mask(width: usize) -> u64 {\n");
        code.push_str("    let rem = width % 64;\n");
        code.push_str("    if rem == 0 { u64::MAX } else { (1u64 << rem) - 1 }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_mask(mut value: WideValue256, width: usize) -> WideValue256 {\n");
        code.push_str("    if width <= 128 { value.words[2] = 0; value.words[3] = 0; }\n");
        code.push_str("    let count = width.div_ceil(64).max(1).min(4);\n");
        code.push_str("    for idx in count..4 { value.words[idx] = 0; }\n");
        code.push_str("    value.words[count - 1] &= wide_word_mask(width);\n");
        code.push_str("    value\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_load_signal(signals: *mut u128, wide_hi: *const u64, idx: usize) -> WideValue256 {\n");
        code.push_str("    let low = unsafe { *signals.add(idx) };\n");
        code.push_str("    let base = idx * 2;\n");
        code.push_str("    WideValue256 {\n");
        code.push_str("        words: [\n");
        code.push_str("            low as u64,\n");
        code.push_str("            (low >> 64) as u64,\n");
        code.push_str("            unsafe { *wide_hi.add(base) },\n");
        code.push_str("            unsafe { *wide_hi.add(base + 1) },\n");
        code.push_str("        ]\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_store_signal(signals: *mut u128, wide_hi: *const u64, idx: usize, width: usize, value: WideValue256) {\n");
        code.push_str("    let masked = wide_mask(value, width);\n");
        code.push_str("    let low = (masked.words[0] as u128) | ((masked.words[1] as u128) << 64);\n");
        code.push_str("    unsafe {\n");
        code.push_str("        *signals.add(idx) = low;\n");
        code.push_str("        let base = idx * 2;\n");
        code.push_str("        *(wide_hi as *mut u64).add(base) = masked.words[2];\n");
        code.push_str("        *(wide_hi as *mut u64).add(base + 1) = masked.words[3];\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_or(lhs: WideValue256, rhs: WideValue256) -> WideValue256 {\n");
        code.push_str("    WideValue256 { words: [lhs.words[0] | rhs.words[0], lhs.words[1] | rhs.words[1], lhs.words[2] | rhs.words[2], lhs.words[3] | rhs.words[3]] }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_and(lhs: WideValue256, rhs: WideValue256) -> WideValue256 {\n");
        code.push_str("    WideValue256 { words: [lhs.words[0] & rhs.words[0], lhs.words[1] & rhs.words[1], lhs.words[2] & rhs.words[2], lhs.words[3] & rhs.words[3]] }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_xor(lhs: WideValue256, rhs: WideValue256) -> WideValue256 {\n");
        code.push_str("    WideValue256 { words: [lhs.words[0] ^ rhs.words[0], lhs.words[1] ^ rhs.words[1], lhs.words[2] ^ rhs.words[2], lhs.words[3] ^ rhs.words[3]] }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_shift_left(value: WideValue256, shift: usize) -> WideValue256 {\n");
        code.push_str("    if shift == 0 { return value; }\n");
        code.push_str("    if shift >= 256 { return wide_zero(); }\n");
        code.push_str("    let word_shift = shift / 64;\n");
        code.push_str("    let bit_shift = shift % 64;\n");
        code.push_str("    let mut out = [0u64; 4];\n");
        code.push_str("    for idx in (0..4).rev() {\n");
        code.push_str("        if idx < word_shift { continue; }\n");
        code.push_str("        let src = idx - word_shift;\n");
        code.push_str("        out[idx] |= value.words[src] << bit_shift;\n");
        code.push_str("        if bit_shift != 0 && src > 0 { out[idx] |= value.words[src - 1] >> (64 - bit_shift); }\n");
        code.push_str("    }\n");
        code.push_str("    WideValue256 { words: out }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_shift_right(value: WideValue256, shift: usize) -> WideValue256 {\n");
        code.push_str("    if shift == 0 { return value; }\n");
        code.push_str("    if shift >= 256 { return wide_zero(); }\n");
        code.push_str("    let word_shift = shift / 64;\n");
        code.push_str("    let bit_shift = shift % 64;\n");
        code.push_str("    let mut out = [0u64; 4];\n");
        code.push_str("    for idx in 0..4 {\n");
        code.push_str("        let src = idx + word_shift;\n");
        code.push_str("        if src >= 4 { break; }\n");
        code.push_str("        out[idx] |= value.words[src] >> bit_shift;\n");
        code.push_str("        if bit_shift != 0 && src + 1 < 4 { out[idx] |= value.words[src + 1] << (64 - bit_shift); }\n");
        code.push_str("    }\n");
        code.push_str("    WideValue256 { words: out }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_read_word(value: WideValue256, bit_low: usize) -> u64 {\n");
        code.push_str("    let src_word = bit_low / 64;\n");
        code.push_str("    let bit_off = bit_low % 64;\n");
        code.push_str("    if src_word >= 4 { return 0; }\n");
        code.push_str("    let mut out = value.words[src_word] >> bit_off;\n");
        code.push_str("    if bit_off != 0 && src_word + 1 < 4 { out |= value.words[src_word + 1] << (64 - bit_off); }\n");
        code.push_str("    out\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_slice(value: WideValue256, low: usize, width: usize) -> WideValue256 {\n");
        code.push_str("    let mut out = WideValue256 { words: [0u64; 4] };\n");
        code.push_str("    if width == 0 { return out; }\n");
        code.push_str("    out.words[0] = wide_read_word(value, low);\n");
        code.push_str("    if width > 64 { out.words[1] = wide_read_word(value, low + 64); }\n");
        code.push_str("    if width > 128 { out.words[2] = wide_read_word(value, low + 128); }\n");
        code.push_str("    if width > 192 { out.words[3] = wide_read_word(value, low + 192); }\n");
        code.push_str("    wide_mask(out, width)\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_slice_u128(value: WideValue256, low: usize, width: usize) -> u128 {\n");
        code.push_str("    let sliced = wide_slice(value, low, width);\n");
        code.push_str("    ((sliced.words[0] as u128) | ((sliced.words[1] as u128) << 64)) & ");
        code.push_str(&Self::mask_const(128));
        code.push_str("\n}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn overwide_signal_word(signals: *mut u128, overwide_ptrs: *const *const u64, idx: usize, word_idx: usize) -> u64 {\n");
        code.push_str("    let low = unsafe { *signals.add(idx) };\n");
        code.push_str("    match word_idx {\n");
        code.push_str("        0 => low as u64,\n");
        code.push_str("        1 => (low >> 64) as u64,\n");
        code.push_str("        _ => {\n");
        code.push_str("            let ptr = unsafe { *overwide_ptrs.add(idx) };\n");
        code.push_str("            if ptr.is_null() { 0 } else { unsafe { *ptr.add(word_idx - 2) } }\n");
        code.push_str("        }\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn overwide_signal_slice_u128(signals: *mut u128, overwide_ptrs: *const *const u64, idx: usize, low: usize, width: usize) -> u128 {\n");
        code.push_str("    if width == 0 { return 0; }\n");
        code.push_str("    let mut out = 0u128;\n");
        code.push_str("    let mut bit = low;\n");
        code.push_str("    let mut written = 0usize;\n");
        code.push_str("    while written < width {\n");
        code.push_str("        let bit_off = bit % 64;\n");
        code.push_str("        let chunk = (64 - bit_off).min(width - written);\n");
        code.push_str("        let word = overwide_signal_word(signals, overwide_ptrs, idx, bit / 64);\n");
        code.push_str("        let part = if chunk == 64 { word } else { (word >> bit_off) & ((1u64 << chunk) - 1) };\n");
        code.push_str("        out |= (part as u128) << written;\n");
        code.push_str("        bit += chunk;\n");
        code.push_str("        written += chunk;\n");
        code.push_str("    }\n");
        code.push_str("    out & ");
        code.push_str(&Self::mask_const(128));
        code.push_str("\n}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn dynamic_mask_u128(width: usize) -> u128 {\n");
        code.push_str("    if width == 0 { 0u128 } else if width >= 128 { u128::MAX } else { (1u128 << width) - 1 }\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn slice_u128(value: u128, low: usize, width: usize) -> u128 {\n");
        code.push_str("    (value >> low) & dynamic_mask_u128(width)\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn signal_slice_u128(signals: *mut u128, idx: usize, low: usize, width: usize) -> u128 {\n");
        code.push_str("    slice_u128(unsafe { *signals.add(idx) }, low, width)\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn bool_to_u128(value: bool) -> u128 {\n");
        code.push_str("    value as u8 as u128\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn mux_u128(cond: u128, when_true: u128, when_false: u128, mask: u128) -> u128 {\n");
        code.push_str("    (if cond != 0 { when_true } else { when_false }) & mask\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn repeat_pattern_u128(value: u128, part_width: usize, repeat_count: usize) -> u128 {\n");
        code.push_str("    let masked = value & dynamic_mask_u128(part_width);\n");
        code.push_str("    let mut out = 0u128;\n");
        code.push_str("    for _ in 0..repeat_count {\n");
        code.push_str("        out = (out << part_width) | masked;\n");
        code.push_str("    }\n");
        code.push_str("    out\n");
        code.push_str("}\n\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("fn wide_repeat_pattern(value: WideValue256, part_width: usize, repeat_count: usize) -> WideValue256 {\n");
        code.push_str("    if part_width == 0 || repeat_count == 0 { return wide_zero(); }\n");
        code.push_str("    let masked = wide_mask(value, part_width);\n");
        code.push_str("    let mut out = wide_zero();\n");
        code.push_str("    for _ in 0..repeat_count {\n");
        code.push_str("        out = wide_shift_left(out, part_width);\n");
        code.push_str("        out = wide_or(out, masked);\n");
        code.push_str("    }\n");
        code.push_str("    out\n");
        code.push_str("}\n\n");

        let flat_assign_indices = &self.compiled_comb_assign_indices;
        // Compact CIRCT payloads already carry an explicit shared-expression
        // pool. Fine-grained chunking duplicates those expr-ref definitions
        // across helper functions and explodes the emitted Rust source for
        // large imports.
        //
        // Cores that need generated tick helpers still use the existing small
        // chunks. For very large plain cores, emit coarser chunks so rustc
        // does not have to optimize one giant evaluate function.
        if include_tick_helpers && flat_assign_indices.len() > CHUNKED_EVALUATE_ASSIGN_THRESHOLD {
            self.generate_chunked_evaluate_inline(
                &mut code,
                flat_assign_indices,
                CHUNKED_EVALUATE_ASSIGNS_PER_FN,
            );
        } else if !include_tick_helpers
            && flat_assign_indices.len() > LARGE_NON_TICK_CHUNKED_EVALUATE_ASSIGN_THRESHOLD
        {
            self.generate_chunked_evaluate_inline(
                &mut code,
                flat_assign_indices,
                LARGE_NON_TICK_CHUNKED_EVALUATE_ASSIGNS_PER_FN,
            );
        } else {
            // Generate evaluate function (inline for performance)
            code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
            code.push_str("#[inline(always)]\n");
            code.push_str("pub unsafe fn evaluate_inline(signals: &mut [u128], wide_hi: *const u64, overwide_ptrs: *const *const u64) {\n");
            code.push_str("    let s = signals.as_mut_ptr();\n");
            code.push_str("    let wh = wide_hi;\n");
            code.push_str("    let ow = overwide_ptrs;\n");

            // Cache frequently-used signals to reduce pointer loads in hot evaluate loop.
            // We cache:
            // - stable signals (not assigned by combinational assigns) when used many times
            // - combinational targets when used multiple times downstream
            let mut comb_use_counts: HashMap<usize, usize> = HashMap::new();
            for &assign_idx in flat_assign_indices {
                let Some(assign) = self.ir.assigns.get(assign_idx) else {
                    continue;
                };
                let deps = self.expr_dependencies(&assign.expr);
                for sig_idx in deps {
                    *comb_use_counts.entry(sig_idx).or_insert(0) += 1;
                }
            }
            let mut comb_targets: HashSet<usize> = HashSet::new();
            for &assign_idx in flat_assign_indices {
                let Some(assign) = self.ir.assigns.get(assign_idx) else {
                    continue;
                };
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    comb_targets.insert(idx);
                }
            }

            let stable_cache_threshold = 5usize;
            let max_stable_cached = 32usize;
            let max_target_cached = 128usize;

            let mut stable_cached: Vec<(usize, usize)> = comb_use_counts
                .iter()
                .filter_map(|(&idx, &count)| {
                    if count > stable_cache_threshold && !comb_targets.contains(&idx) {
                        Some((idx, count))
                    } else {
                        None
                    }
                })
                .collect();
            stable_cached.sort_by(|(a_idx, a_count), (b_idx, b_count)| {
                b_count.cmp(a_count).then(a_idx.cmp(b_idx))
            });
            stable_cached.truncate(max_stable_cached);

            let mut cached_targets: Vec<(usize, usize)> = comb_use_counts
                .iter()
                .filter_map(|(&idx, &count)| {
                    if count > 1 && comb_targets.contains(&idx) {
                        Some((idx, count))
                    } else {
                        None
                    }
                })
                .collect();
            cached_targets.sort_by(|(a_idx, a_count), (b_idx, b_count)| {
                b_count.cmp(a_count).then(a_idx.cmp(b_idx))
            });
            cached_targets.truncate(max_target_cached);
            let cached_target_set: HashSet<usize> = cached_targets.iter().map(|(idx, _)| *idx).collect();

            let mut comb_cache_names: HashMap<usize, String> = HashMap::new();
            let mut comb_cache_counter: usize = 0;
            for (idx, _count) in &stable_cached {
                let name = format!("c{}", comb_cache_counter);
                comb_cache_counter += 1;
                code.push_str(&format!("    let {} = *s.add({});\n", name, idx));
                comb_cache_names.insert(*idx, name);
            }
            if !stable_cached.is_empty() {
                code.push_str("\n");
            }

            let mut expr_state = ExprCodegenState::default();
            for &assign_idx in flat_assign_indices {
                let Some(assign) = self.ir.assigns.get(assign_idx) else {
                    continue;
                };
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    let width = self.widths.get(idx).copied().unwrap_or(64);
                    let expr_width = self.expr_width(&assign.expr);
                    let mut expr_lines = Vec::new();
                    if width > 128 {
                        let expr_code = self.expr_to_rust_wide_cached_emitting(
                            &assign.expr,
                            "s",
                            "wh",
                            "ow",
                            Some(&comb_cache_names),
                            &mut expr_state,
                            &mut expr_lines,
                        );
                        self.append_indented_lines(&mut code, "    ", &expr_lines);
                        code.push_str(&format!(
                            "    wide_store_signal(s, wh, {}, {}, {});\n",
                            idx, width, expr_code
                        ));
                        continue;
                    }
                    let expr_code = self.expr_to_rust_ptr_cached_emitting(
                        &assign.expr,
                        "s",
                        Some("wh"),
                        Some("ow"),
                        Some(&comb_cache_names),
                        &mut expr_state,
                        &mut expr_lines,
                    );
                    self.append_indented_lines(&mut code, "    ", &expr_lines);
                    if expr_width == width {
                        if cached_target_set.contains(&idx) {
                            let name = format!("c{}", comb_cache_counter);
                            comb_cache_counter += 1;
                            code.push_str(&format!("    let {} = {};\n", name, expr_code));
                            code.push_str(&format!("    *s.add({}) = {};\n", idx, name));
                            comb_cache_names.insert(idx, name);
                        } else {
                            code.push_str(&format!("    *s.add({}) = {};\n", idx, expr_code));
                        }
                    } else {
                        if cached_target_set.contains(&idx) {
                            let name = format!("c{}", comb_cache_counter);
                            comb_cache_counter += 1;
                            code.push_str(&format!(
                                "    let {} = ({}) & {};\n",
                                name,
                                expr_code,
                                Self::mask_const(width)
                            ));
                            code.push_str(&format!("    *s.add({}) = {};\n", idx, name));
                            comb_cache_names.insert(idx, name);
                        } else {
                            code.push_str(&format!(
                                "    *s.add({}) = ({}) & {};\n",
                                idx,
                                expr_code,
                                Self::mask_const(width)
                            ));
                        }
                    }
                }
            }

            code.push_str("}\n\n");
        }

        // Generate extern "C" wrapper for evaluate
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(signals: *mut u128, wide_hi: *const u64, overwide_ptrs: *const *const u64, len: usize) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str("    evaluate_inline(signals, wide_hi, overwide_ptrs);\n");
        code.push_str("}\n\n");

        if include_tick_helpers {
            self.generate_tick_function(&mut code);
        }

        code
    }

    fn generate_chunked_evaluate_inline(
        &self,
        code: &mut String,
        assign_indices: &[usize],
        assigns_per_fn: usize,
    ) {
        let chunk_count = assign_indices.chunks(assigns_per_fn).len();
        for (chunk_idx, chunk) in assign_indices.chunks(assigns_per_fn).enumerate() {
            code.push_str("/// Evaluate a chunk of combinational assignments\n");
            code.push_str("#[inline(never)]\n");
            code.push_str(&format!("unsafe fn evaluate_chunk_{}(s: *mut u128, wh: *const u64, ow: *const *const u64) {{\n", chunk_idx));
            let mut expr_state = ExprCodegenState::default();
            for &assign_idx in chunk {
                let assign = &self.ir.assigns[assign_idx];
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    self.generate_direct_assign_store(code, assign, idx, "s", Some("wh"), Some("ow"), &mut expr_state);
                }
            }
            code.push_str("}\n\n");
        }

        code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn evaluate_inline(signals: &mut [u128], wide_hi: *const u64, overwide_ptrs: *const *const u64) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str("    let wh = wide_hi;\n");
        code.push_str("    let ow = overwide_ptrs;\n");
        for chunk_idx in 0..chunk_count {
            code.push_str(&format!("    evaluate_chunk_{}(s, wh, ow);\n", chunk_idx));
        }
        code.push_str("}\n\n");
    }

    fn append_indented_lines(&self, code: &mut String, indent: &str, lines: &[String]) {
        for line in lines {
            code.push_str(indent);
            code.push_str(line);
            code.push('\n');
        }
    }

    fn generate_direct_assign_store(
        &self,
        code: &mut String,
        assign: &AssignDef,
        target_idx: usize,
        signals_ptr: &str,
        wide_words_ptr: Option<&str>,
        overwide_ptrs: Option<&str>,
        expr_state: &mut ExprCodegenState,
    ) {
        let width = self.widths.get(target_idx).copied().unwrap_or(64);
        if width > 128 {
            let mut expr_lines = Vec::new();
            let expr_code = self.expr_to_rust_wide_cached_emitting(
                &assign.expr,
                signals_ptr,
                wide_words_ptr.unwrap_or("wh"),
                overwide_ptrs.unwrap_or("ow"),
                None,
                expr_state,
                &mut expr_lines,
            );
            self.append_indented_lines(code, "    ", &expr_lines);
            code.push_str(&format!(
                "    wide_store_signal({}, {}, {}, {}, {});\n",
                signals_ptr,
                wide_words_ptr.unwrap_or("wh"),
                target_idx,
                width,
                expr_code
            ));
            return;
        }

        let expr_width = self.expr_width(&assign.expr);
        let mut expr_lines = Vec::new();
        let expr_code = self.expr_to_rust_ptr_emitting(
            &assign.expr,
            signals_ptr,
            wide_words_ptr,
            overwide_ptrs,
            expr_state,
            &mut expr_lines
        );
        self.append_indented_lines(code, "    ", &expr_lines);
        if expr_width == width {
            code.push_str(&format!("    *{}.add({}) = {};\n", signals_ptr, target_idx, expr_code));
        } else {
            code.push_str(&format!(
                "    *{}.add({}) = ({}) & {};\n",
                signals_ptr,
                target_idx,
                expr_code,
                Self::mask_const(width)
            ));
        }
    }

    fn emit_wide_expr_ref_value(
        &self,
        id: usize,
        signals_ptr: &str,
        wide_words_ptr: &str,
        overwide_ptrs: &str,
        cache: Option<&HashMap<usize, String>>,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        if let Some(name) = state.wide_expr_ref_temps.get(&id) {
            return name.clone();
        }

        if state.emitting.contains(&id) {
            return "wide_zero()".to_string();
        }

        let Some(expr) = self.ir.exprs.get(id) else {
            return "wide_zero()".to_string();
        };

        state.emitting.insert(id);
        let expr_code = self.expr_to_rust_wide_cached_emitting(
            expr,
            signals_ptr,
            wide_words_ptr,
            overwide_ptrs,
            cache,
            state,
            emitted_lines,
        );
        state.emitting.remove(&id);

        let use_count = self.expr_ref_use_counts.get(id).copied().unwrap_or(0);
        if use_count <= 1 {
            return expr_code;
        }

        let var_name = format!("ew{}", id);
        emitted_lines.push(format!("let {} = {};", var_name, expr_code));
        state.wide_expr_ref_temps.insert(id, var_name.clone());
        var_name
    }

    fn emit_expr_ref_value(
        &self,
        id: usize,
        signals_ptr: &str,
        wide_words_ptr: Option<&str>,
        overwide_ptrs: Option<&str>,
        cache: Option<&HashMap<usize, String>>,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        let var_name = format!("e{}", id);
        if state.emitted.contains(&id) {
            return var_name;
        }
        if state.emitting.contains(&id) {
            return "0u128".to_string();
        }

        let Some(expr) = self.ir.exprs.get(id) else {
            return "0u128".to_string();
        };

        state.emitting.insert(id);
        let expr_code = self.expr_to_rust_ptr_cached_emitting(
            expr,
            signals_ptr,
            wide_words_ptr,
            overwide_ptrs,
            cache,
            state,
            emitted_lines
        );
        state.emitting.remove(&id);

        let use_count = self.expr_ref_use_counts.get(id).copied().unwrap_or(0);
        let complexity = self.expr_ref_complexities.get(id).copied().unwrap_or(1);
        let width = self.expr_width(expr);
        let single_use_threshold = if width <= 1 {
            SINGLE_USE_EXPR_MATERIALIZE_COMPLEXITY_THRESHOLD_BIT1
        } else {
            SINGLE_USE_EXPR_MATERIALIZE_COMPLEXITY_THRESHOLD
        };
        let should_materialize_single_use =
            width <= SINGLE_USE_EXPR_MATERIALIZE_MAX_WIDTH && complexity > single_use_threshold;
        if use_count <= 1 && !should_materialize_single_use {
            expr_code
        } else {
            state.emitted.insert(id);
            emitted_lines.push(format!("let {} = {};", var_name, expr_code));
            var_name
        }
    }

    fn expr_to_rust_ptr_emitting(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
        wide_words_ptr: Option<&str>,
        overwide_ptrs: Option<&str>,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        self.expr_to_rust_ptr_cached_emitting(
            expr,
            signals_ptr,
            wide_words_ptr,
            overwide_ptrs,
            None,
            state,
            emitted_lines
        )
    }

    fn expr_to_rust_ptr_cached_emitting(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
        wide_words_ptr: Option<&str>,
        overwide_ptrs: Option<&str>,
        cache: Option<&HashMap<usize, String>>,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
        ) -> String {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                if let Some(cache) = cache {
                    if let Some(temp) = cache.get(&idx) {
                        return temp.clone();
                    }
                }
                format!("(*{}.add({}))", signals_ptr, idx)
            }
            ExprDef::SignalIndex { idx, .. } => {
                if let Some(cache) = cache {
                    if let Some(temp) = cache.get(idx) {
                        return temp.clone();
                    }
                }
                format!("(*{}.add({}))", signals_ptr, idx)
            }
            ExprDef::Literal { value, width, .. } => {
                let parsed = value.parse::<i128>().unwrap_or(0);
                let masked = mask_signed_value(parsed, *width);
                Self::value_const(masked)
            }
            ExprDef::ExprRef { id, .. } => {
                self.emit_expr_ref_value(*id, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code =
                    self.expr_to_rust_ptr_cached_emitting(operand, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        format!("bool_to_u128(({} & {}) == {})", operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("bool_to_u128({} != 0)", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u128 & 1u128)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust_ptr_cached_emitting(left, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                let r = self.expr_to_rust_ptr_cached_emitting(right, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                let m = Self::mask_const(*width);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & {})", l, r, m),
                    "-" => format!("({}.wrapping_sub({}) & {})", l, r, m),
                    "*" => format!("({}.wrapping_mul({}) & {})", l, r, m),
                    "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0u128 }})", r, l, r),
                    "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0u128 }})", r, l, r),
                    "<<" => format!("(({} << (({}).min(127u128) as u32)) & {})", l, r, m),
                    ">>" => format!("({} >> (({}).min(127u128) as u32))", l, r),
                    "==" => format!("bool_to_u128({} == {})", l, r),
                    "!=" => format!("bool_to_u128({} != {})", l, r),
                    "<" => format!("bool_to_u128({} < {})", l, r),
                    ">" => format!("bool_to_u128({} > {})", l, r),
                    "<=" | "le" => format!("bool_to_u128({} <= {})", l, r),
                    ">=" => format!("bool_to_u128({} >= {})", l, r),
                    _ => "0u128".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond =
                    self.expr_to_rust_ptr_cached_emitting(condition, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                let t =
                    self.expr_to_rust_ptr_cached_emitting(when_true, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                let f =
                    self.expr_to_rust_ptr_cached_emitting(when_false, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                format!("mux_u128({}, {}, {}, {})", cond, t, f, Self::mask_const(*width))
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_width = self.expr_width(base);
                if base_width > 256 {
                    match self.resolve_expr(base) {
                        ExprDef::Signal { name, .. } => {
                            let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                            format!(
                                "overwide_signal_slice_u128({}, {}, {}, {}, {})",
                                signals_ptr,
                                overwide_ptrs.unwrap_or("ow"),
                                idx,
                                low,
                                width
                            )
                        }
                        ExprDef::SignalIndex { idx, .. } => {
                            format!(
                                "overwide_signal_slice_u128({}, {}, {}, {}, {})",
                                signals_ptr,
                                overwide_ptrs.unwrap_or("ow"),
                                idx,
                                low,
                                width
                            )
                        }
                        _ => "0u128".to_string(),
                    }
                } else if base_width > 128 {
                    match self.resolve_expr(base) {
                        ExprDef::Signal { name, .. } => {
                            let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                            state.cached_wide_signal_slice(
                                idx,
                                *low,
                                *width,
                                signals_ptr,
                                wide_words_ptr.unwrap_or("wh"),
                                emitted_lines,
                            )
                        }
                        ExprDef::SignalIndex { idx, .. } => state.cached_wide_signal_slice(
                            *idx,
                            *low,
                            *width,
                            signals_ptr,
                            wide_words_ptr.unwrap_or("wh"),
                            emitted_lines,
                        ),
                        _ => {
                            let wide_base = self.expr_to_rust_wide_cached_emitting(
                                base,
                                signals_ptr,
                                wide_words_ptr.unwrap_or("wh"),
                                overwide_ptrs.unwrap_or("ow"),
                                cache,
                                state,
                                emitted_lines,
                            );
                            format!("wide_slice_u128({}, {}, {})", wide_base, low, width)
                        }
                    }
                } else if *low >= 128 {
                    "0u128".to_string()
                } else {
                    match self.resolve_expr(base) {
                        ExprDef::Signal { name, .. } => {
                            let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                            if let Some(cache) = cache {
                                if let Some(temp) = cache.get(&idx) {
                                    format!("slice_u128({}, {}, {})", temp, low, width)
                                } else {
                                    format!("signal_slice_u128({}, {}, {}, {})", signals_ptr, idx, low, width)
                                }
                            } else {
                                format!("signal_slice_u128({}, {}, {}, {})", signals_ptr, idx, low, width)
                            }
                        }
                        ExprDef::SignalIndex { idx, .. } => {
                            if let Some(cache) = cache {
                                if let Some(temp) = cache.get(idx) {
                                    format!("slice_u128({}, {}, {})", temp, low, width)
                                } else {
                                    format!("signal_slice_u128({}, {}, {}, {})", signals_ptr, idx, low, width)
                                }
                            } else {
                                format!("signal_slice_u128({}, {}, {}, {})", signals_ptr, idx, low, width)
                            }
                        }
                        _ => {
                            let base_code = self.expr_to_rust_ptr_cached_emitting(
                                base,
                                signals_ptr,
                                wide_words_ptr,
                                overwide_ptrs,
                                cache,
                                state,
                                emitted_lines,
                            );
                            format!("slice_u128({}, {}, {})", base_code, low, width)
                        }
                    }
                }
            }
            ExprDef::Concat { parts, width } => {
                if let Some((repeat_part, part_width, repeat_count)) =
                    self.repeated_concat_part(parts, *width)
                {
                    let part_code = self.expr_to_rust_ptr_cached_emitting(
                        repeat_part,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    );
                    return format!(
                        "(repeat_pattern_u128(({} & {}), {}, {}) & {})",
                        part_code,
                        Self::mask_const(part_width),
                        part_width,
                        repeat_count,
                        Self::mask_const(*width)
                    );
                }

                if parts.len() >= LARGE_NARROW_CONCAT_PART_THRESHOLD {
                    let temp_name = state.fresh_temp("concat");
                    emitted_lines.push(format!("let mut {} = 0u128;", temp_name));
                    let mut shift = 0usize;
                    for part in parts.iter().rev() {
                        let part_width = self.expr_width(part);
                        if part_width == 0 {
                            continue;
                        }
                        if shift >= 128 {
                            shift += part_width;
                            continue;
                        }
                        let part_code = self.expr_to_rust_ptr_cached_emitting(
                            part,
                            signals_ptr,
                            wide_words_ptr,
                            overwide_ptrs,
                            cache,
                            state,
                            emitted_lines,
                        );
                        if shift > 0 {
                            emitted_lines.push(format!(
                                "{} |= ({} & {}) << {};",
                                temp_name,
                                part_code,
                                Self::mask_const(part_width),
                                shift
                            ));
                        } else {
                            emitted_lines.push(format!(
                                "{} |= {} & {};",
                                temp_name,
                                part_code,
                                Self::mask_const(part_width)
                            ));
                        }
                        shift += part_width;
                    }
                    emitted_lines.push(format!(
                        "{} &= {};",
                        temp_name,
                        Self::mask_const(*width)
                    ));
                    return temp_name;
                }

                let mut result = String::from("((");
                let mut shift = 0usize;
                let mut first = true;
                for part in parts.iter().rev() {
                    let part_code =
                        self.expr_to_rust_ptr_cached_emitting(part, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                    let part_width = self.expr_width(part);
                    if shift >= 128 {
                        shift += part_width;
                        continue;
                    }
                    if !first {
                        result.push_str(" | ");
                    }
                    first = false;
                    if shift > 0 {
                        result.push_str(&format!("(({} & {}) << {})", part_code, Self::mask_const(part_width), shift));
                    } else {
                        result.push_str(&format!("({} & {})", part_code, Self::mask_const(part_width)));
                    }
                    shift += part_width;
                }
                result.push_str(&format!(") & {})", Self::mask_const(*width)));
                result
            }
            ExprDef::Resize { expr, width } => {
                let expr_code = self.expr_to_rust_ptr_cached_emitting(expr, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust_ptr_cached_emitting(addr, signals_ptr, wide_words_ptr, overwide_ptrs, cache, state, emitted_lines);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & {})",
                        mem_idx, addr_code, Self::mask_const(*width))
            }
        }
    }

    fn wide_literal_const(&self, value: &str, width: usize) -> String {
        let runtime_value = RuntimeValue::from_signed_text(value, width);
        format!(
            "WideValue256 {{ words: [0x{:X}u64, 0x{:X}u64, 0x{:X}u64, 0x{:X}u64] }}",
            runtime_value.word(width, 0),
            runtime_value.word(width, 1),
            runtime_value.word(width, 2),
            runtime_value.word(width, 3)
        )
    }

    fn expr_to_rust_wide_cached_emitting(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
        wide_words_ptr: &str,
        overwide_ptrs: &str,
        cache: Option<&HashMap<usize, String>>,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                if *width <= 128 {
                    format!("wide_from_u128(*{}.add({}))", signals_ptr, idx)
                } else {
                    state.cached_wide_signal_load(idx, signals_ptr, wide_words_ptr, emitted_lines)
                }
            }
            ExprDef::SignalIndex { idx, width } => {
                if *width <= 128 {
                    format!("wide_from_u128(*{}.add({}))", signals_ptr, idx)
                } else {
                    state.cached_wide_signal_load(*idx, signals_ptr, wide_words_ptr, emitted_lines)
                }
            }
            ExprDef::Literal { value, width, .. } => self.wide_literal_const(value, *width),
            ExprDef::ExprRef { id, .. } => self.emit_wide_expr_ref_value(
                *id,
                signals_ptr,
                wide_words_ptr,
                overwide_ptrs,
                cache,
                state,
                emitted_lines,
            ),
            ExprDef::Mux {
                condition,
                when_true,
                when_false,
                width,
            } => {
                let cond = self.expr_to_rust_ptr_cached_emitting(
                    condition,
                    signals_ptr,
                    Some(wide_words_ptr),
                    Some(overwide_ptrs),
                    cache,
                    state,
                    emitted_lines,
                );
                let when_true_code = self.expr_to_rust_wide_cached_emitting(
                    when_true,
                    signals_ptr,
                    wide_words_ptr,
                    overwide_ptrs,
                    cache,
                    state,
                    emitted_lines,
                );
                let when_false_code = self.expr_to_rust_wide_cached_emitting(
                    when_false,
                    signals_ptr,
                    wide_words_ptr,
                    overwide_ptrs,
                    cache,
                    state,
                    emitted_lines,
                );
                let temp = state.fresh_temp("wide_mux");
                emitted_lines.push(format!(
                    "let {} = wide_mask(if {} != 0 {{ {} }} else {{ {} }}, {});",
                    temp, cond, when_true_code, when_false_code, width
                ));
                temp
            }
            ExprDef::Concat { parts, width } => {
                if let Some((repeat_part, part_width, repeat_count)) =
                    self.repeated_concat_part(parts, *width)
                {
                    let part_code = if part_width > 128 {
                        self.expr_to_rust_wide_cached_emitting(
                            repeat_part,
                            signals_ptr,
                            wide_words_ptr,
                            overwide_ptrs,
                            cache,
                            state,
                            emitted_lines,
                        )
                    } else {
                        let narrow_part = self.expr_to_rust_ptr_cached_emitting(
                            repeat_part,
                            signals_ptr,
                            Some(wide_words_ptr),
                            Some(overwide_ptrs),
                            cache,
                            state,
                            emitted_lines,
                        );
                        format!(
                            "wide_from_u128(({}) & {})",
                            narrow_part,
                            Self::mask_const(part_width)
                        )
                    };
                    let temp = state.fresh_temp("wide_repeat");
                    emitted_lines.push(format!(
                        "let {} = wide_mask(wide_repeat_pattern({}, {}, {}), {});",
                        temp, part_code, part_width, repeat_count, width
                    ));
                    return temp;
                }

                let temp = state.fresh_temp("wide_concat");
                emitted_lines.push(format!("let mut {} = wide_zero();", temp));
                for part in parts {
                    let part_width = self.expr_width(part);
                    let part_code = if part_width > 128 {
                        self.expr_to_rust_wide_cached_emitting(
                            part,
                            signals_ptr,
                            wide_words_ptr,
                            overwide_ptrs,
                            cache,
                            state,
                            emitted_lines,
                        )
                    } else {
                        let narrow_part = self.expr_to_rust_ptr_cached_emitting(
                            part,
                            signals_ptr,
                            Some(wide_words_ptr),
                            Some(overwide_ptrs),
                            cache,
                            state,
                            emitted_lines,
                        );
                        format!("wide_from_u128(({}) & {})", narrow_part, Self::mask_const(part_width))
                    };
                    emitted_lines.push(format!(
                        "{} = wide_shift_left({}, {});",
                        temp, temp, part_width
                    ));
                    emitted_lines.push(format!(
                        "{} = wide_or({}, wide_mask({}, {}));",
                        temp, temp, part_code, part_width
                    ));
                }
                emitted_lines.push(format!("{} = wide_mask({}, {});", temp, temp, width));
                temp
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let temp = state.fresh_temp("wide_bin");
                if matches!(op.as_str(), "<<" | ">>") {
                    let lhs = self.expr_to_rust_wide_cached_emitting(
                        left,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    );
                    let rhs = self.expr_to_rust_ptr_cached_emitting(
                        right,
                        signals_ptr,
                        Some(wide_words_ptr),
                        Some(overwide_ptrs),
                        cache,
                        state,
                        emitted_lines,
                    );
                    let helper = if op.as_str() == "<<" { "wide_shift_left" } else { "wide_shift_right" };
                    emitted_lines.push(format!(
                        "let {} = wide_mask({}({}, (({}).min(255u128) as usize)), {});",
                        temp, helper, lhs, rhs, width
                    ));
                } else {
                    let lhs = self.expr_to_rust_wide_cached_emitting(
                        left,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    );
                    let rhs = self.expr_to_rust_wide_cached_emitting(
                        right,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    );
                    let helper = match op.as_str() {
                        "|" => "wide_or",
                        "&" => "wide_and",
                        "^" => "wide_xor",
                        _ => "wide_zero",
                    };
                    if helper == "wide_zero" {
                        emitted_lines.push(format!("let {} = wide_zero();", temp));
                    } else {
                        emitted_lines.push(format!(
                            "let {} = wide_mask({}({}, {}), {});",
                            temp, helper, lhs, rhs, width
                        ));
                    }
                }
                temp
            }
            ExprDef::Resize { expr, width } => {
                let inner = if self.expr_width(expr) > 128 {
                    self.expr_to_rust_wide_cached_emitting(
                        expr,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    )
                } else {
                    let narrow = self.expr_to_rust_ptr_cached_emitting(
                        expr,
                        signals_ptr,
                        Some(wide_words_ptr),
                        Some(overwide_ptrs),
                        cache,
                        state,
                        emitted_lines,
                    );
                    format!("wide_from_u128({})", narrow)
                };
                let temp = state.fresh_temp("wide_resize");
                emitted_lines.push(format!("let {} = wide_mask({}, {});", temp, inner, width));
                temp
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust_wide_cached_emitting(
                    base,
                    signals_ptr,
                    wide_words_ptr,
                    overwide_ptrs,
                    cache,
                    state,
                    emitted_lines,
                );
                let temp = state.fresh_temp("wide_slice");
                emitted_lines.push(format!(
                    "let {} = wide_slice({}, {}, {});",
                    temp, base_code, low, width
                ));
                temp
            }
            ExprDef::UnaryOp { operand, width, .. } => {
                let operand_code = if self.expr_width(operand) > 128 {
                    self.expr_to_rust_wide_cached_emitting(
                        operand,
                        signals_ptr,
                        wide_words_ptr,
                        overwide_ptrs,
                        cache,
                        state,
                        emitted_lines,
                    )
                } else {
                    let narrow = self.expr_to_rust_ptr_cached_emitting(
                        operand,
                        signals_ptr,
                        Some(wide_words_ptr),
                        Some(overwide_ptrs),
                        cache,
                        state,
                        emitted_lines,
                    );
                    format!("wide_from_u128({})", narrow)
                };
                let temp = state.fresh_temp("wide_unary");
                emitted_lines.push(format!("let {} = wide_mask({}, {});", temp, operand_code, width));
                temp
            }
            ExprDef::MemRead { .. } => "wide_zero()".to_string(),
        }
    }

    fn generate_tick_function(&self, code: &mut String) {
        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        // Pre-generate sequential sampling code once so both generic and forced
        // tick paths share identical register update semantics.
        let mut seq_use_counts: HashMap<usize, usize> = HashMap::new();
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let deps = self.expr_dependencies(&stmt.expr);
                for sig_idx in deps {
                    *seq_use_counts.entry(sig_idx).or_insert(0) += 1;
                }
            }
        }
        let mut seq_cached: Vec<usize> = seq_use_counts
            .iter()
            .filter_map(|(&sig_idx, &count)| if count > 1 { Some(sig_idx) } else { None })
            .collect();
        seq_cached.sort_unstable();

        let mut seq_cache_names: HashMap<usize, String> = HashMap::new();
        let mut seq_sample_code = String::new();
        for (i, sig_idx) in seq_cached.iter().enumerate() {
            let name = format!("r{}", i);
            seq_sample_code.push_str(&format!("    let {} = *s.add({});\n", name, sig_idx));
            seq_cache_names.insert(*sig_idx, name);
        }

        let mut seq_targets_order: Vec<usize> = Vec::new();
        let mut seq_idx = 0usize;
        let mut seq_expr_state = ExprCodegenState::default();
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                if let Some(&target_idx) = self.name_to_idx.get(&stmt.target) {
                    let width = self.widths.get(target_idx).copied().unwrap_or(64);
                    let expr_width = self.expr_width(&stmt.expr);
                    let mut expr_lines = Vec::new();
                    let expr_code = self.expr_to_rust_ptr_cached_emitting(
                        &stmt.expr,
                        "s",
                        None,
                        None,
                        Some(&seq_cache_names),
                        &mut seq_expr_state,
                        &mut expr_lines,
                    );
                    self.append_indented_lines(&mut seq_sample_code, "    ", &expr_lines);
                    if expr_width == width {
                        seq_sample_code.push_str(&format!("    next_regs[{}] = {};\n", seq_idx, expr_code));
                    } else {
                        seq_sample_code.push_str(&format!(
                            "    next_regs[{}] = ({}) & {};\n",
                            seq_idx,
                            expr_code,
                            Self::mask_const(width)
                        ));
                    }
                    seq_targets_order.push(target_idx);
                    seq_idx += 1;
                }
            }
        }

        let mut seq_apply_code = String::new();
        for (i, &target_idx) in seq_targets_order.iter().enumerate() {
            seq_apply_code.push_str(&format!("    *s.add({}) = next_regs[{}];\n", target_idx, i));
        }

        let mut write_port_code = String::new();
        for (wp_idx, wp) in self.ir.write_ports.iter().enumerate() {
            let Some(&memory_idx) = self.memory_name_to_idx.get(&wp.memory) else {
                continue;
            };
            let Some(&clock_idx) = self.name_to_idx.get(&wp.clock) else {
                continue;
            };
            let Some(memory) = self.ir.memories.get(memory_idx) else {
                continue;
            };
            if memory.depth == 0 {
                continue;
            }

            let mut port_expr_state = ExprCodegenState::default();
            let mut enable_lines = Vec::new();
            let enable_code = self.expr_to_rust_ptr_emitting(&wp.enable, "s", None, None, &mut port_expr_state, &mut enable_lines);
            let mut data_lines = Vec::new();
            let addr_code = self.expr_to_rust_ptr_emitting(&wp.addr, "s", None, None, &mut port_expr_state, &mut data_lines);
            let data_code = self.expr_to_rust_ptr_emitting(&wp.data, "s", None, None, &mut port_expr_state, &mut data_lines);
            write_port_code.push_str(&format!("    if *s.add({}) != 0 {{\n", clock_idx));
            self.append_indented_lines(&mut write_port_code, "        ", &enable_lines);
            write_port_code.push_str(&format!("        if (({}) & 1) != 0 {{\n", enable_code));
            self.append_indented_lines(&mut write_port_code, "            ", &data_lines);
            write_port_code.push_str(&format!(
                "            let wp_addr_{} = (({}) as usize) % {};\n",
                wp_idx, addr_code, memory.depth
            ));
            write_port_code.push_str(&format!(
                "            let wp_data_{} = ({}) & {};\n",
                wp_idx,
                data_code,
                Self::mask_const(memory.width)
            ));
            write_port_code.push_str(&format!(
                "            MEM_{}[wp_addr_{}] = wp_data_{};\n",
                memory_idx, wp_idx, wp_idx
            ));
            write_port_code.push_str("        }\n");
            write_port_code.push_str("    }\n");
        }

        let mut sync_read_port_code = String::new();
        for (rp_idx, rp) in self.ir.sync_read_ports.iter().enumerate() {
            let Some(&memory_idx) = self.memory_name_to_idx.get(&rp.memory) else {
                continue;
            };
            let Some(&clock_idx) = self.name_to_idx.get(&rp.clock) else {
                continue;
            };
            let Some(&data_idx) = self.name_to_idx.get(&rp.data) else {
                continue;
            };
            let Some(memory) = self.ir.memories.get(memory_idx) else {
                continue;
            };
            if memory.depth == 0 {
                continue;
            }
            let data_width = self.widths.get(data_idx).copied().unwrap_or(64);
            let mut port_expr_state = ExprCodegenState::default();
            let mut addr_lines = Vec::new();
            let addr_code = self.expr_to_rust_ptr_emitting(&rp.addr, "s", None, None, &mut port_expr_state, &mut addr_lines);
            sync_read_port_code.push_str(&format!("    if *s.add({}) != 0 {{\n", clock_idx));
            if let Some(enable) = &rp.enable {
                let mut enable_lines = Vec::new();
                let enable_code =
                    self.expr_to_rust_ptr_emitting(enable, "s", None, None, &mut port_expr_state, &mut enable_lines);
                self.append_indented_lines(&mut sync_read_port_code, "        ", &enable_lines);
                sync_read_port_code.push_str(&format!("        if (({}) & 1) != 0 {{\n", enable_code));
                self.append_indented_lines(&mut sync_read_port_code, "            ", &addr_lines);
                sync_read_port_code.push_str(&format!(
                    "            let rp_addr_{} = (({}) as usize) % {};\n",
                    rp_idx, addr_code, memory.depth
                ));
                sync_read_port_code.push_str(&format!(
                    "            let rp_data_{} = MEM_{}[rp_addr_{}] & {};\n",
                    rp_idx,
                    memory_idx,
                    rp_idx,
                    Self::mask_const(memory.width)
                ));
                sync_read_port_code.push_str(&format!(
                    "            *s.add({}) = rp_data_{} & {};\n",
                    data_idx,
                    rp_idx,
                    Self::mask_const(data_width)
                ));
                sync_read_port_code.push_str("        }\n");
            } else {
                self.append_indented_lines(&mut sync_read_port_code, "        ", &addr_lines);
                sync_read_port_code.push_str(&format!(
                    "        let rp_addr_{} = (({}) as usize) % {};\n",
                    rp_idx, addr_code, memory.depth
                ));
                sync_read_port_code.push_str(&format!(
                    "        let rp_data_{} = MEM_{}[rp_addr_{}] & {};\n",
                    rp_idx,
                    memory_idx,
                    rp_idx,
                    Self::mask_const(memory.width)
                ));
                sync_read_port_code.push_str(&format!(
                    "        *s.add({}) = rp_data_{} & {};\n",
                    data_idx,
                    rp_idx,
                    Self::mask_const(data_width)
                ));
            }
            sync_read_port_code.push_str("    }\n");
        }

        code.push_str("/// Sample next values for all sequential targets\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn sample_next_regs_inline(signals: &mut [u128], next_regs: &mut [u128; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str(&seq_sample_code);
        code.push_str("}\n\n");

        code.push_str("/// Apply sampled sequential values to target registers\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn apply_next_regs_inline(signals: &mut [u128], next_regs: &[u128; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str(&seq_apply_code);
        code.push_str("}\n\n");

        code.push_str("/// Apply synchronous memory write ports for the current level\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn apply_write_ports_inline(signals: &mut [u128]) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        if write_port_code.is_empty() {
            code.push_str("    let _ = s;\n");
        } else {
            code.push_str(&write_port_code);
        }
        code.push_str("}\n\n");

        code.push_str("/// Apply synchronous memory read ports for the current level\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn apply_sync_read_ports_inline(signals: &mut [u128]) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        if sync_read_port_code.is_empty() {
            code.push_str("    let _ = s;\n");
        } else {
            code.push_str(&sync_read_port_code);
        }
        code.push_str("}\n\n");

        code.push_str("/// Forced-edge tick for specialized batched runners.\n");
        code.push_str("/// Evaluates combinational logic, samples sequential inputs, and applies all\n");
        code.push_str("/// sequential updates unconditionally (one edge per call).\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn tick_forced_inline(signals: &mut [u128], next_regs: &mut [u128; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("    apply_write_ports_inline(signals);\n\n");
        code.push_str("    sample_next_regs_inline(signals, next_regs);\n");
        code.push_str("    apply_next_regs_inline(signals, next_regs);\n");
        code.push_str("    apply_sync_read_ports_inline(signals);\n");
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("}\n\n");

        code.push_str("/// Drive a specific clock low and evaluate combinational logic.\n");
        code.push_str("/// Reusable falling-edge helper for extension batched loops.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn drive_clock_low_inline(signals: &mut [u128], clk_idx: usize) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str("    *s.add(clk_idx) = 0;\n");
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("}\n\n");

        code.push_str("/// Drive a specific clock high and execute edge-triggered updates.\n");
        code.push_str("/// Reusable rising-edge helper for extension batched loops using generic tick.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn drive_clock_high_tick_inline(signals: &mut [u128], clk_idx: usize, old_clocks: &mut [u128; {}], next_regs: &mut [u128; {}]) {{\n",
            num_clocks,
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        for (domain_idx, &clk_idx_domain) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = *s.add({});\n", domain_idx, clk_idx_domain));
        }
        code.push_str("    *s.add(clk_idx) = 1;\n");
        code.push_str("    tick_inline(signals, old_clocks, next_regs);\n");
        code.push_str("}\n\n");

        code.push_str("/// Emit one full forced pulse: high edge update, then return low.\n");
        code.push_str("/// Reusable helper for single-clock forced stepping loops.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn pulse_clock_forced_inline(signals: &mut [u128], clk_idx: usize, next_regs: &mut [u128; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str("    *s.add(clk_idx) = 1;\n");
        code.push_str("    tick_forced_inline(signals, next_regs);\n");
        code.push_str("    *s.add(clk_idx) = 0;\n");
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("}\n\n");

        code.push_str("/// Combined tick: evaluate + edge-triggered register update\n");
        code.push_str("/// Uses old_clocks (set by caller) for edge detection, not current signal values.\n");
        code.push_str("/// This allows the caller to control exactly what \"previous\" clock state means.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("pub unsafe fn tick_inline(signals: &mut [u128], old_clocks: &mut [u128; {}], next_regs: &mut [u128; {}]) {{\n",
                               num_clocks, num_regs.max(1)));
        code.push_str("    let s = signals.as_mut_ptr();\n");

        // Evaluate combinational logic (this propagates clock changes to derived clocks)
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("    apply_write_ports_inline(signals);\n\n");

        // Compute next values for all registers ONCE (like JIT's seq_sample)
        code.push_str("    sample_next_regs_inline(signals, next_regs);\n\n");

        // Track which registers have been updated (like JIT)
        code.push_str(&format!("    let mut updated = [false; {}];\n\n", num_regs.max(1)));

        // Check for rising edges using old_clocks (set by caller) vs current signals
        for (domain_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    // Clock domain {} (signal {})\n", domain_idx, clk_idx));
            code.push_str(&format!("    if old_clocks[{}] == 0 && *s.add({}) == 1 {{\n", domain_idx, clk_idx));

            for &(seq_idx, target_idx) in &self.clock_domain_assigns[domain_idx] {
                code.push_str(&format!("        if !updated[{}] {{ *s.add({}) = next_regs[{}]; updated[{}] = true; }}\n",
                                       seq_idx, target_idx, seq_idx, seq_idx));
            }
            code.push_str("    }\n");
        }
        code.push_str("\n");

        // Loop to handle derived clocks (like JIT's iteration loop)
        // After updating registers, re-evaluate to propagate changes that might cause
        // additional clock edges in derived/gated clocks
        code.push_str("    // Loop for derived clock propagation (like JIT)\n");
        code.push_str("    for _iter in 0..10 {\n");
        code.push_str(&format!("        let mut clock_before = [0u128; {}];\n", num_clocks));
        for (domain_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        clock_before[{}] = *s.add({});\n", domain_idx, clk_idx));
        }
        code.push_str("\n");
        code.push_str("        evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n");
        code.push_str("        apply_write_ports_inline(signals);\n");
        code.push_str("        sample_next_regs_inline(signals, next_regs);\n\n");

        // Check for NEW rising edges
        code.push_str("        let mut any_rising = false;\n");
            for (domain_idx, &clk_idx) in clock_indices.iter().enumerate() {
                code.push_str(&format!("        if clock_before[{}] == 0 && *s.add({}) == 1 {{\n", domain_idx, clk_idx));
                code.push_str("            any_rising = true;\n");
                for &(seq_idx, target_idx) in &self.clock_domain_assigns[domain_idx] {
                code.push_str(&format!("            if !updated[{}] {{ *s.add({}) = next_regs[{}]; updated[{}] = true; }}\n",
                                       seq_idx, target_idx, seq_idx, seq_idx));
                }
                code.push_str("        }\n");
            }
        code.push_str("\n");
        code.push_str("        if !any_rising { break; }\n");
        code.push_str("    }\n\n");

        code.push_str("    apply_sync_read_ports_inline(signals);\n");
        // Final evaluate (like JIT)
        code.push_str("    evaluate_inline(signals, std::ptr::null(), std::ptr::null());\n\n");

        // Note: Do NOT update old_clocks here - caller manages it
        // This is consistent with interpreter's tick_forced behavior
        // The MOS6502 extension manages old_clocks explicitly before each tick_inline call

        code.push_str("}\n\n");

        // Generate extern "C" wrapper
        // This wrapper updates old_clocks AFTER tick_inline for the regular tick() path
        // (MOS6502 extension calls tick_inline directly and manages old_clocks itself)
        code.push_str("#[no_mangle]\n");
        code.push_str(&format!("pub unsafe extern \"C\" fn tick(signals: *mut u128, len: usize, old_clocks: *mut u128, next_regs: *mut u128) {{\n"));
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str(&format!("    let old_clocks = &mut *(old_clocks as *mut [u128; {}]);\n", num_clocks));
        code.push_str(&format!("    let next_regs = &mut *(next_regs as *mut [u128; {}]);\n", num_regs.max(1)));
        code.push_str("    tick_inline(signals, old_clocks, next_regs);\n");

        // Update old_clocks to current clock signal values for next tick() call
        for (domain_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = *signals.get_unchecked({});\n", domain_idx, clk_idx));
        }

        code.push_str("}\n");

    }

    // ========================================================================
    // Compilation
    // ========================================================================

    pub fn compile_code(&mut self, code: &str) -> Result<bool, String> {
        #[cfg(feature = "aot")]
        {
            let _ = code;
            self.compiled = true;
            return Ok(true);
        }

        #[cfg(not(feature = "aot"))]
        {
        let (opt_level, codegen_units, target_cpu) = Self::rustc_profile_for_generated_code(code);
        // Compute hash for caching
        let code_hash = {
            let mut hash: u64 = 0xcbf29ce484222325;
            let cache_profile = format!(
                "opt={};cgu={};cpu={}",
                opt_level,
                codegen_units,
                target_cpu
            );
            for byte in cache_profile.bytes() {
                hash ^= byte as u64;
                hash = hash.wrapping_mul(0x100000001b3);
            }
            for byte in code.bytes() {
                hash ^= byte as u64;
                hash = hash.wrapping_mul(0x100000001b3);
            }
            hash
        };

        // Cache paths
        let cache_dir = std::env::temp_dir().join("rhdl_cache");
        let _ = fs::create_dir_all(&cache_dir);

        let lib_ext = if cfg!(target_os = "macos") {
            "dylib"
        } else if cfg!(target_os = "windows") {
            "dll"
        } else {
            "so"
        };
        let lib_name = format!("rhdl_ir_{:016x}.{}", code_hash, lib_ext);
        let lib_path = cache_dir.join(&lib_name);

        // Use process-unique temp filenames to avoid cross-process clobbering
        // when multiple test workers compile the same hash concurrently.
        let (pid, ts) = {
            let pid = std::process::id();
            let ts = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0);
            (pid, ts)
        };
        let unique = format!("{}_{}", pid, ts);
        let crate_name = format!("rhdl_ir_{:016x}_{}", code_hash, unique);
        let tmp_lib_path = cache_dir.join(format!("rhdl_ir_{:016x}.{}.{}", code_hash, unique, lib_ext));
        let tmp_src_path = cache_dir.join(format!("rhdl_ir_{:016x}.{}.rs", code_hash, unique));

        // Check cache
        if lib_path.exists() {
            unsafe {
                let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
                self.bind_compiled_library(lib)?;
            }
            self.compiled = true;
            self.init_compiled_memories()?;
            self.shed_compiled_ir_state();
            return Ok(true);
        }

        // Write source and compile into a unique temporary output file.
        fs::write(&tmp_src_path, code).map_err(|e| e.to_string())?;
        let opt_level_flag = format!("opt-level={}", opt_level);
        let codegen_units_flag = format!("codegen-units={}", codegen_units);
        let target_cpu_flag = format!("target-cpu={}", target_cpu);

        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "--crate-name",
                crate_name.as_str(),
                // The SPARC64 integration cores are compiled once and then
                // run for millions of cycles, so favor steady-state runtime
                // throughput over minimum cold compile latency.
                "-C", opt_level_flag.as_str(),
                "-C", "debuginfo=0",
                "-C", "embed-bitcode=no",
                "-C", "panic=abort",
                "-C", codegen_units_flag.as_str(),
                "-C", target_cpu_flag.as_str(),
                "-A", "warnings",
                "-o",
                tmp_lib_path.to_str().unwrap(),
                tmp_src_path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| e.to_string())?;

        let _ = fs::remove_file(&tmp_src_path);

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Compilation failed: {}", stderr));
        }

        // Promote compiled artifact into the shared cache path.
        // If another process already populated the cache, keep the cached file.
        if lib_path.exists() {
            let _ = fs::remove_file(&tmp_lib_path);
        } else if let Err(e) = fs::rename(&tmp_lib_path, &lib_path) {
            if lib_path.exists() {
                let _ = fs::remove_file(&tmp_lib_path);
            } else {
                return Err(format!("Failed to move compiled library into cache: {}", e));
            }
        }

        // Load compiled library
        unsafe {
            let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
            self.bind_compiled_library(lib)?;
        }
        self.compiled = true;
        self.init_compiled_memories()?;
        self.shed_compiled_ir_state();
        Ok(false)
        }
    }

    #[cfg(not(feature = "aot"))]
    fn init_compiled_memories(&mut self) -> Result<(), String> {
        if !self.compiled {
            return Ok(());
        }
        let lib = self.compiled_lib.as_ref().ok_or_else(|| "Compiled library not loaded".to_string())?;
        unsafe {
            type InitFn = unsafe extern "C" fn();
            let func: libloading::Symbol<InitFn> = lib.get(b"init_memories").map_err(|e| e.to_string())?;
            func();
        }
        Ok(())
    }

    #[cfg(feature = "aot")]
    fn init_compiled_memories(&mut self) -> Result<(), String> {
        Ok(())
    }

    #[cfg(not(feature = "aot"))]
    fn bind_compiled_library(&mut self, lib: CompiledLibrary) -> Result<(), String> {
        unsafe {
            let eval_fn = {
                let symbol: libloading::Symbol<CompiledEvalFn> =
                    lib.get(b"evaluate").map_err(|e| e.to_string())?;
                *symbol
            };
            let tick_fn = {
                let symbol = lib.get::<CompiledTickFn>(b"tick");
                symbol.ok().map(|loaded| *loaded)
            };
            self.compiled_eval_fn = Some(eval_fn);
            self.compiled_tick_fn = tick_fn;
        }
        self.compiled_lib = Some(lib);
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uses_default_rustc_profile_for_small_generated_units() {
        let code = "fn evaluate() {}\n";
        let profile = CoreSimulator::rustc_profile_for_generated_code(code);
        assert_eq!(
            profile,
            (
                RUNTIME_RUSTC_OPT_LEVEL,
                RUNTIME_RUSTC_CODEGEN_UNITS,
                RUNTIME_RUSTC_TARGET_CPU,
            )
        );
    }

    #[test]
    fn uses_large_design_rustc_profile_for_huge_generated_units() {
        let code = "x".repeat(LARGE_RUSTC_SOURCE_BYTES_THRESHOLD + 1);
        let profile = CoreSimulator::rustc_profile_for_generated_code(&code);
        assert_eq!(
            profile,
            (
                LARGE_RUNTIME_RUSTC_OPT_LEVEL,
                LARGE_RUNTIME_RUSTC_CODEGEN_UNITS,
                RUNTIME_RUSTC_TARGET_CPU,
            )
        );
    }

    #[test]
    fn reports_fast_path_blockers_for_runtime_fallback_assigns() {
        let json = serde_json::json!({
            "circt_json_version": 1,
            "modules": [{
                "name": "top",
                "ports": [
                    { "name": "a", "direction": "in", "width": 64 },
                    { "name": "b", "direction": "in", "width": 64 },
                    { "name": "wide_out", "direction": "out", "width": 145 }
                ],
                "nets": [],
                "regs": [],
                "assigns": [
                    {
                        "target": "wide_out",
                        "expr": {
                            "kind": "concat",
                            "parts": [
                                { "kind": "literal", "value": 1, "width": 17 },
                                { "kind": "signal", "name": "a", "width": 64 },
                                { "kind": "signal", "name": "b", "width": 64 }
                            ],
                            "width": 145
                        }
                    }
                ],
                "processes": [],
                "memories": [],
                "write_ports": [],
                "sync_read_ports": []
            }]
        })
        .to_string();

        let sim = CoreSimulator::new(&json).expect("parse overwide compile blocker payload");
        let blocker = sim
            .compile_fast_path_blocker(false)
            .expect("runtime fallback should be rejected");

        assert!(blocker.contains("runtime fallback"));
        assert!(blocker.contains("wide_out"));
    }
}
