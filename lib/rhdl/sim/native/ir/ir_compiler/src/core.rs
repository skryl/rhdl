//! Core IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This module contains the generic IR simulation infrastructure without
//! any example-specific code (Apple II, MOS6502, etc.)

use std::collections::{HashMap, HashSet};
#[cfg(not(feature = "aot"))]
use std::fs;
#[cfg(not(feature = "aot"))]
use std::process::Command;
#[cfg(not(feature = "aot"))]
use std::time::{SystemTime, UNIX_EPOCH};

use serde::Deserialize;
use serde_json::{Map, Value};

use crate::signal_value::{
    compute_mask as wide_mask,
    deserialize_optional_signal_value,
    deserialize_signal_values,
    deserialize_signed_signal_value,
    mask_signed_value,
    SignalValue,
    SignedSignalValue,
};

#[cfg(feature = "aot")]
type CompiledLibrary = ();
#[cfg(not(feature = "aot"))]
type CompiledLibrary = libloading::Library;

const CHUNKED_EVALUATE_ASSIGN_THRESHOLD: usize = 256;
const CHUNKED_EVALUATE_ASSIGNS_PER_FN: usize = 32;
const RUNTIME_ONLY_EXPR_THRESHOLD: usize = 100_000;

#[derive(Default)]
struct ExprCodegenState {
    emitted: HashSet<usize>,
    emitting: HashSet<usize>,
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
    Literal {
        #[serde(deserialize_with = "deserialize_signed_signal_value")]
        value: SignedSignalValue,
        width: usize
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

// ============================================================================
// Core Simulator State
// ============================================================================

/// Core IR simulator - generic circuit simulation without example-specific features
pub struct CoreSimulator {
    /// IR definition
    pub ir: ModuleIR,
    /// Signal values (Vec for O(1) access)
    pub signals: Vec<SignalValue>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Reset values for registers (signal index -> reset value)
    pub reset_values: Vec<(usize, SignalValue)>,
    /// Topologically sorted combinational assignments for runtime fallback
    pub comb_assigns: Vec<(usize, usize)>,
    /// Next register values buffer
    pub next_regs: Vec<SignalValue>,
    /// Sequential assignment expressions
    pub seq_exprs: Vec<(usize, usize)>,
    /// Sequential assignment target indices
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    pub old_clocks: Vec<SignalValue>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    pub clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Memory arrays
    pub memory_arrays: Vec<Vec<SignalValue>>,
    /// Memory name to index
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Compiled library (if compilation succeeded)
    pub compiled_lib: Option<CompiledLibrary>,
    /// Whether compilation succeeded
    pub compiled: bool,
    /// Adaptive pure-core fallback that skips per-module rustc and uses the
    /// native runtime evaluator in this crate instead.
    pub runtime_only: bool,
}

impl CoreSimulator {
    pub fn new(json: &str) -> Result<Self, String> {
        let ir = parse_module_ir(json)?;

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
        let old_clocks = vec![0u128; clock_indices.len()];
        let next_regs = vec![0u128; seq_targets.len()];

        // Pre-group assignments by clock domain
        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(domain_idx) = clock_indices.iter().position(|&c| c == clk_idx) {
                clock_domain_assigns[domain_idx].push((seq_idx, seq_targets[seq_idx]));
            }
        }

        // Initialize memory arrays
        let mut memory_arrays = Vec::new();
        let mut memory_name_to_idx = HashMap::new();
        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut arr = vec![0u128; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < arr.len() {
                    arr[i] = val;
                }
            }
            memory_arrays.push(arr);
            memory_name_to_idx.insert(mem.name.clone(), idx);
        }

        let mut sim = Self {
            ir,
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            reset_values,
            comb_assigns: Vec::new(),
            next_regs,
            seq_exprs,
            seq_targets,
            seq_clocks,
            clock_indices,
            old_clocks,
            clock_domain_assigns,
            memory_arrays,
            memory_name_to_idx,
            compiled_lib: None,
            compiled: cfg!(feature = "aot"),
            runtime_only: false,
        };

        let levels = sim.compute_assignment_levels();
        sim.comb_assigns = levels
            .iter()
            .flat_map(|level| level.iter().copied())
            .filter_map(|assign_idx| {
                let assign = sim.ir.assigns.get(assign_idx)?;
                sim.name_to_idx
                    .get(&assign.target)
                    .copied()
                    .map(|target_idx| (target_idx, assign_idx))
            })
            .collect();

        Ok(sim)
    }

    pub fn compute_mask(width: usize) -> SignalValue {
        wide_mask(width)
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

    pub fn should_use_runtime_only_compile(&self, include_tick_helpers: bool) -> bool {
        !include_tick_helpers && self.ir.exprs.len() > RUNTIME_ONLY_EXPR_THRESHOLD
    }

    pub fn enable_runtime_only_compile(&mut self) {
        self.compiled_lib = None;
        self.compiled = true;
        self.runtime_only = true;
    }

    fn shed_compiled_ir_state(&mut self) {
        if self.runtime_only {
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

        for process in &mut self.ir.processes {
            process.name.clear();
            process.clock = None;
            for stmt in &mut process.statements {
                stmt.target.clear();
            }
        }
    }

    pub fn shed_batched_gameboy_state(&mut self) {
        if self.runtime_only {
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
    }

    #[inline(always)]
    fn evaluate_compiled_without_clock_capture(&mut self) {
        if self.runtime_only {
            for (target_idx, assign_idx) in &self.comb_assigns {
                let Some(assign) = self.ir.assigns.get(*assign_idx) else {
                    continue;
                };
                self.signals[*target_idx] =
                    self.eval_expr_runtime(&assign.expr) & Self::compute_mask(self.widths[*target_idx]);
            }
            return;
        }
        if !self.compiled {
            return;
        }
        #[cfg(feature = "aot")]
        unsafe {
            crate::aot_generated::evaluate(self.signals.as_mut_ptr(), self.signals.len());
        }
        #[cfg(not(feature = "aot"))]
        {
            let lib = self.compiled_lib.as_ref().unwrap();
            unsafe {
                type EvalFn = unsafe extern "C" fn(*mut SignalValue, usize);
                let func: libloading::Symbol<EvalFn> =
                    lib.get(b"evaluate").expect("evaluate function not found");
                func(self.signals.as_mut_ptr(), self.signals.len());
            }
        }
    }

    fn runtime_expr_width(&self, expr: &ExprDef) -> usize {
        self.expr_width(expr)
    }

    fn eval_expr_runtime(&self, expr: &ExprDef) -> SignalValue {
        match self.resolve_expr(expr) {
            ExprDef::Signal { name, width } => {
                let val = self.name_to_idx.get(name)
                    .and_then(|&idx| self.signals.get(idx).copied())
                    .unwrap_or(0);
                val & Self::compute_mask(*width)
            }
            ExprDef::Literal { value, width } => mask_signed_value(*value, *width),
            ExprDef::ExprRef { .. } => 0,
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.eval_expr_runtime(operand);
                let mask = Self::compute_mask(*width);
                match op.as_str() {
                    "~" | "not" => (!src) & mask,
                    "&" | "reduce_and" => {
                        let op_width = self.runtime_expr_width(operand);
                        let op_mask = Self::compute_mask(op_width);
                        if (src & op_mask) == op_mask { 1 } else { 0 }
                    }
                    "|" | "reduce_or" => if src != 0 { 1 } else { 0 },
                    "^" | "reduce_xor" => (src.count_ones() as SignalValue) & 1,
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
                    "<<" => if r >= 128 { 0 } else { l << (r as u32) },
                    ">>" => if r >= 128 { 0 } else { l >> (r as u32) },
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
                let shifted = if *low >= 128 { 0 } else { base_val >> (*low as u32) };
                shifted & Self::compute_mask(*width)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = 0u128;
                for part in parts {
                    let part_width = self.runtime_expr_width(part);
                    let part_val = self.eval_expr_runtime(part) & Self::compute_mask(part_width);
                    result = if part_width >= 128 { 0 } else { result << part_width };
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

    fn sample_next_regs_runtime(&mut self) {
        for (idx, &(process_idx, stmt_idx)) in self.seq_exprs.iter().enumerate() {
            let Some(process) = self.ir.processes.get(process_idx) else {
                continue;
            };
            let Some(stmt) = process.statements.get(stmt_idx) else {
                continue;
            };
            self.next_regs[idx] = self.eval_expr_runtime(&stmt.expr);
        }
    }

    fn write_compiled_memory_word(&self, memory_idx: usize, addr: usize, value: SignalValue) {
        if !self.compiled || self.runtime_only {
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

    fn store_memory_word(&mut self, memory_idx: usize, addr: usize, value: SignalValue) {
        let Some(mem) = self.memory_arrays.get_mut(memory_idx) else {
            return;
        };
        if addr >= mem.len() {
            return;
        }

        mem[addr] = value;
        self.write_compiled_memory_word(memory_idx, addr, value);
    }

    fn apply_write_ports_runtime(&mut self) {
        if self.ir.write_ports.is_empty() {
            return;
        }

        let mut writes: Vec<(usize, usize, SignalValue)> = Vec::new();
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
            if (self.eval_expr_runtime(&wp.enable) & 1) == 0 {
                continue;
            }

            let addr = (self.eval_expr_runtime(&wp.addr) as usize) % memory.depth;
            let data = self.eval_expr_runtime(&wp.data) & Self::compute_mask(memory.width);
            writes.push((memory_idx, addr, data));
        }

        for (memory_idx, addr, value) in writes {
            self.store_memory_word(memory_idx, addr, value);
        }
    }

    fn apply_sync_read_ports_runtime(&mut self) {
        if self.ir.sync_read_ports.is_empty() {
            return;
        }

        let mut updates: Vec<(usize, SignalValue)> = Vec::new();
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
                if (self.eval_expr_runtime(enable) & 1) == 0 {
                    continue;
                }
            }
            let Some(&data_idx) = self.name_to_idx.get(&rp.data) else {
                continue;
            };
            let data_width = self.widths.get(data_idx).copied().unwrap_or(64);
            let addr = (self.eval_expr_runtime(&rp.addr) as usize) % mem.len();
            let data = mem[addr] & Self::compute_mask(self.ir.memories[memory_idx].width);
            updates.push((data_idx, data & Self::compute_mask(data_width)));
        }

        for (idx, value) in updates {
            if idx < self.signals.len() {
                self.signals[idx] = value;
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
            self.signals[idx] = value & Self::compute_mask(width);
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
            Ok(self.signals[idx])
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    pub fn tick(&mut self) {
        if !self.compiled {
            return;
        }

        // Mirror the JIT runtime semantics for sequential sampling and memory
        // ports. AO486 import trees exercise nested mux chains that the fully
        // generated tick path does not currently handle reliably.
        self.evaluate_compiled_without_clock_capture();
        self.apply_write_ports_runtime();
        self.sample_next_regs_runtime();

        let mut updated: Vec<bool> = vec![false; self.seq_targets.len()];
        let mut rising_clocks: Vec<bool> = vec![false; self.signals.len()];
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            let before = self.old_clocks.get(i).copied().unwrap_or(0);
            let after = self.signals.get(clk_idx).copied().unwrap_or(0);
            if before == 0 && after == 1 {
                rising_clocks[clk_idx] = true;
            }
        }

        for (i, &target_idx) in self.seq_targets.iter().enumerate() {
            let clk_idx = self.seq_clocks[i];
            if rising_clocks.get(clk_idx).copied().unwrap_or(false) && !updated[i] {
                self.signals[target_idx] = self.next_regs[i] & Self::compute_mask(self.widths[target_idx]);
                updated[i] = true;
            }
        }

        for _iteration in 0..10 {
            let clock_before: Vec<SignalValue> = self.clock_indices
                .iter()
                .map(|&clk_idx| self.signals.get(clk_idx).copied().unwrap_or(0))
                .collect();

            self.evaluate_compiled_without_clock_capture();

            let mut any_rising = false;
            let mut derived_rising: Vec<bool> = vec![false; self.signals.len()];
            for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
                let before = clock_before[i];
                let after = self.signals.get(clk_idx).copied().unwrap_or(0);
                if before == 0 && after == 1 {
                    derived_rising[clk_idx] = true;
                    any_rising = true;
                }
            }

            if !any_rising {
                break;
            }

            for (i, &target_idx) in self.seq_targets.iter().enumerate() {
                let clk_idx = self.seq_clocks[i];
                if derived_rising.get(clk_idx).copied().unwrap_or(false) && !updated[i] {
                    self.signals[target_idx] = self.next_regs[i] & Self::compute_mask(self.widths[target_idx]);
                    updated[i] = true;
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

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
        for val in self.next_regs.iter_mut() {
            *val = 0;
        }
        for val in self.old_clocks.iter_mut() {
            *val = 0;
        }

        // Reset IR memory arrays to their declared initial contents.
        // This mirrors interpreter/JIT reset behavior so compiled runs
        // do not leak register/memory state across resets.
        for (mem_idx, mem_def) in self.ir.memories.iter().enumerate() {
            let Some(mem) = self.memory_arrays.get_mut(mem_idx) else {
                continue;
            };
            mem.fill(0);
            for (i, &val) in mem_def.initial_data.iter().enumerate() {
                if i < mem.len() {
                    mem[i] = val;
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
            if let ExprDef::Signal { name, .. } = self.resolve_expr(&assign.expr) {
                // Check if this assignment copies from the input clock
                if let Some(&source_idx) = self.name_to_idx.get(name) {
                    if source_idx == input_clk_idx {
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

        let levels = self.compute_assignment_levels();
        let flat_assign_indices: Vec<usize> = levels.iter().flat_map(|level| level.iter().copied()).collect();
        // Compact CIRCT payloads already carry an explicit shared-expression
        // pool. Splitting large evaluate blocks into chunks duplicates those
        // expr-ref definitions across chunk functions and explodes the emitted
        // Rust source for large imports like AO486.
        if flat_assign_indices.len() > CHUNKED_EVALUATE_ASSIGN_THRESHOLD {
            self.generate_chunked_evaluate_inline(&mut code, &flat_assign_indices);
        } else {
            // Generate evaluate function (inline for performance)
            code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
            code.push_str("#[inline(always)]\n");
            code.push_str("pub unsafe fn evaluate_inline(signals: &mut [u128]) {\n");
            code.push_str("    let s = signals.as_mut_ptr();\n");

            // Cache frequently-used signals to reduce pointer loads in hot evaluate loop.
            // We cache:
            // - stable signals (not assigned by combinational assigns) when used many times
            // - combinational targets when used multiple times downstream
            let mut comb_use_counts: HashMap<usize, usize> = HashMap::new();
            for assign in &self.ir.assigns {
                let deps = self.expr_dependencies(&assign.expr);
                for sig_idx in deps {
                    *comb_use_counts.entry(sig_idx).or_insert(0) += 1;
                }
            }
            let mut comb_targets: HashSet<usize> = HashSet::new();
            for assign in &self.ir.assigns {
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
            for level in &levels {
                for &assign_idx in level {
                    let assign = &self.ir.assigns[assign_idx];
                    if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                        let width = self.widths.get(idx).copied().unwrap_or(64);
                        let expr_width = self.expr_width(&assign.expr);
                        let mut expr_lines = Vec::new();
                        let expr_code = self.expr_to_rust_ptr_cached_emitting(
                            &assign.expr,
                            "s",
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
            }

            code.push_str("}\n\n");
        }

        // Generate extern "C" wrapper for evaluate
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(signals: *mut u128, len: usize) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        if include_tick_helpers {
            self.generate_tick_function(&mut code);
        }

        code
    }

    fn generate_chunked_evaluate_inline(&self, code: &mut String, assign_indices: &[usize]) {
        for (chunk_idx, chunk) in assign_indices.chunks(CHUNKED_EVALUATE_ASSIGNS_PER_FN).enumerate() {
            code.push_str("/// Evaluate a chunk of combinational assignments\n");
            code.push_str("#[inline(never)]\n");
            code.push_str(&format!("unsafe fn evaluate_chunk_{}(s: *mut u128) {{\n", chunk_idx));
            let mut expr_state = ExprCodegenState::default();
            for &assign_idx in chunk {
                let assign = &self.ir.assigns[assign_idx];
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    self.generate_direct_assign_store(code, assign, idx, "s", &mut expr_state);
                }
            }
            code.push_str("}\n\n");
        }

        code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn evaluate_inline(signals: &mut [u128]) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        for chunk_idx in 0..assign_indices.chunks(CHUNKED_EVALUATE_ASSIGNS_PER_FN).len() {
            code.push_str(&format!("    evaluate_chunk_{}(s);\n", chunk_idx));
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
        expr_state: &mut ExprCodegenState,
    ) {
        let width = self.widths.get(target_idx).copied().unwrap_or(64);
        let expr_width = self.expr_width(&assign.expr);
        let mut expr_lines = Vec::new();
        let expr_code = self.expr_to_rust_ptr_emitting(&assign.expr, signals_ptr, expr_state, &mut expr_lines);
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

    fn emit_expr_ref_value(
        &self,
        id: usize,
        signals_ptr: &str,
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
        let expr_code = self.expr_to_rust_ptr_cached_emitting(expr, signals_ptr, cache, state, emitted_lines);
        state.emitting.remove(&id);
        state.emitted.insert(id);
        emitted_lines.push(format!("let {} = {};", var_name, expr_code));
        var_name
    }

    fn expr_to_rust_ptr_emitting(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
        state: &mut ExprCodegenState,
        emitted_lines: &mut Vec<String>,
    ) -> String {
        self.expr_to_rust_ptr_cached_emitting(expr, signals_ptr, None, state, emitted_lines)
    }

    fn expr_to_rust_ptr_cached_emitting(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
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
            ExprDef::Literal { value, width } => {
                let masked = mask_signed_value(*value, *width);
                Self::value_const(masked)
            }
            ExprDef::ExprRef { id, .. } => {
                self.emit_expr_ref_value(*id, signals_ptr, cache, state, emitted_lines)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code =
                    self.expr_to_rust_ptr_cached_emitting(operand, signals_ptr, cache, state, emitted_lines);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        format!("(if ({} & {}) == {} {{ 1u128 }} else {{ 0u128 }})",
                                operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("(if {} != 0 {{ 1u128 }} else {{ 0u128 }})", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u128 & 1u128)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust_ptr_cached_emitting(left, signals_ptr, cache, state, emitted_lines);
                let r = self.expr_to_rust_ptr_cached_emitting(right, signals_ptr, cache, state, emitted_lines);
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
                    "==" => format!("(if {} == {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    "!=" => format!("(if {} != {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    "<" => format!("(if {} < {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    ">" => format!("(if {} > {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    "<=" | "le" => format!("(if {} <= {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    ">=" => format!("(if {} >= {} {{ 1u128 }} else {{ 0u128 }})", l, r),
                    _ => "0u128".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond =
                    self.expr_to_rust_ptr_cached_emitting(condition, signals_ptr, cache, state, emitted_lines);
                let t =
                    self.expr_to_rust_ptr_cached_emitting(when_true, signals_ptr, cache, state, emitted_lines);
                let f =
                    self.expr_to_rust_ptr_cached_emitting(when_false, signals_ptr, cache, state, emitted_lines);
                format!(
                    "((if {} != 0 {{ {} }} else {{ {} }}) & {})",
                    cond,
                    t,
                    f,
                    Self::mask_const(*width)
                )
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust_ptr_cached_emitting(base, signals_ptr, cache, state, emitted_lines);
                format!(
                    "(({} >> ({}usize).min(127)) & {})",
                    base_code,
                    low,
                    Self::mask_const(*width)
                )
            }
            ExprDef::Concat { parts, width } => {
                let mut result = String::from("((");
                let mut shift = 0usize;
                let mut first = true;
                for part in parts.iter().rev() {
                    let part_code =
                        self.expr_to_rust_ptr_cached_emitting(part, signals_ptr, cache, state, emitted_lines);
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
                let expr_code = self.expr_to_rust_ptr_cached_emitting(expr, signals_ptr, cache, state, emitted_lines);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust_ptr_cached_emitting(addr, signals_ptr, cache, state, emitted_lines);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & {})",
                        mem_idx, addr_code, Self::mask_const(*width))
            }
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
            let enable_code = self.expr_to_rust_ptr_emitting(&wp.enable, "s", &mut port_expr_state, &mut enable_lines);
            let mut data_lines = Vec::new();
            let addr_code = self.expr_to_rust_ptr_emitting(&wp.addr, "s", &mut port_expr_state, &mut data_lines);
            let data_code = self.expr_to_rust_ptr_emitting(&wp.data, "s", &mut port_expr_state, &mut data_lines);
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
            let addr_code = self.expr_to_rust_ptr_emitting(&rp.addr, "s", &mut port_expr_state, &mut addr_lines);
            sync_read_port_code.push_str(&format!("    if *s.add({}) != 0 {{\n", clock_idx));
            if let Some(enable) = &rp.enable {
                let mut enable_lines = Vec::new();
                let enable_code =
                    self.expr_to_rust_ptr_emitting(enable, "s", &mut port_expr_state, &mut enable_lines);
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
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("    apply_write_ports_inline(signals);\n\n");
        code.push_str("    sample_next_regs_inline(signals, next_regs);\n");
        code.push_str("    apply_next_regs_inline(signals, next_regs);\n");
        code.push_str("    apply_sync_read_ports_inline(signals);\n");
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        code.push_str("/// Drive a specific clock low and evaluate combinational logic.\n");
        code.push_str("/// Reusable falling-edge helper for extension batched loops.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn drive_clock_low_inline(signals: &mut [u128], clk_idx: usize) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str("    *s.add(clk_idx) = 0;\n");
        code.push_str("    evaluate_inline(signals);\n");
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
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        code.push_str("/// Combined tick: evaluate + edge-triggered register update\n");
        code.push_str("/// Uses old_clocks (set by caller) for edge detection, not current signal values.\n");
        code.push_str("/// This allows the caller to control exactly what \"previous\" clock state means.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("pub unsafe fn tick_inline(signals: &mut [u128], old_clocks: &mut [u128; {}], next_regs: &mut [u128; {}]) {{\n",
                               num_clocks, num_regs.max(1)));
        code.push_str("    let s = signals.as_mut_ptr();\n");

        // Evaluate combinational logic (this propagates clock changes to derived clocks)
        code.push_str("    evaluate_inline(signals);\n");
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
        code.push_str("        evaluate_inline(signals);\n\n");

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
        code.push_str("    evaluate_inline(signals);\n\n");

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
        if self.runtime_only {
            self.compiled = true;
            return Ok(true);
        }
        #[cfg(feature = "aot")]
        {
            let _ = code;
            self.compiled = true;
            return Ok(true);
        }

        #[cfg(not(feature = "aot"))]
        {
        // Compute hash for caching
        let code_hash = {
            let mut hash: u64 = 0xcbf29ce484222325;
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
                self.compiled_lib = Some(lib);
            }
            self.compiled = true;
            self.init_compiled_memories()?;
            self.shed_compiled_ir_state();
            return Ok(true);
        }

        // Write source and compile into a unique temporary output file.
        fs::write(&tmp_src_path, code).map_err(|e| e.to_string())?;

        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "--crate-name",
                crate_name.as_str(),
                // Favor compile latency and memory over peak throughput for
                // per-module runtime compilation during test execution.
                "-C", "opt-level=0",
                "-C", "debuginfo=0",
                "-C", "embed-bitcode=no",
                "-C", "panic=abort",
                "-C", "codegen-units=8",
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
            self.compiled_lib = Some(lib);
        }
        self.compiled = true;
        self.init_compiled_memories()?;
        self.shed_compiled_ir_state();
        Ok(false)
        }
    }

    #[cfg(not(feature = "aot"))]
    fn init_compiled_memories(&mut self) -> Result<(), String> {
        if !self.compiled || self.runtime_only {
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
}
