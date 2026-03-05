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

#[cfg(feature = "aot")]
type CompiledLibrary = ();
#[cfg(not(feature = "aot"))]
type CompiledLibrary = libloading::Library;

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
    pub reset_value: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum ExprDef {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
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
    pub initial_data: Vec<u64>,
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
            out.insert("reset_value".to_string(), Value::from(value_to_i64(Some(reset_value))));
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
        "literal" => Ok(literal_expr(
            value_to_i64(obj.get("value")),
            value_to_usize(obj.get("width")),
        )),
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

fn parse_case_values(raw: &str) -> Vec<i64> {
    let text = raw.trim();
    if text.is_empty() {
        return Vec::new();
    }

    if text.starts_with('[') && text.ends_with(']') {
        let inner = &text[1..text.len() - 1];
        return inner
            .split(',')
            .filter_map(|v| v.trim().parse::<i64>().ok())
            .collect();
    }

    text.parse::<i64>().ok().into_iter().collect()
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

fn literal_expr(value: i64, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("literal".to_string()));
    out.insert("value".to_string(), Value::from(value));
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
    pub signals: Vec<u64>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Reset values for registers (signal index -> reset value)
    pub reset_values: Vec<(usize, u64)>,
    /// Next register values buffer
    pub next_regs: Vec<u64>,
    /// Sequential assignment target indices
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    pub old_clocks: Vec<u64>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    pub clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Memory arrays
    pub memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Compiled library (if compilation succeeded)
    pub compiled_lib: Option<CompiledLibrary>,
    /// Whether compilation succeeded
    pub compiled: bool,
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
            signals.push(0u64);
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
            signals.push(0u64);
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
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_indices_set = HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            let clk_name = process.clock.as_deref().unwrap_or("clk");
            let clk_idx = *name_to_idx.get(clk_name).unwrap_or(&0);
            clock_indices_set.insert(clk_idx);

            for stmt in &process.statements {
                if let Some(&idx) = name_to_idx.get(&stmt.target) {
                    seq_targets.push(idx);
                    seq_clocks.push(clk_idx);
                }
            }
        }

        // Sort clock indices for deterministic ordering (HashSet iteration order is undefined)
        let mut clock_indices: Vec<usize> = clock_indices_set.into_iter().collect();
        clock_indices.sort();
        let old_clocks = vec![0u64; clock_indices.len()];
        let next_regs = vec![0u64; seq_targets.len()];

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
            let mut arr = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < arr.len() {
                    arr[i] = val;
                }
            }
            memory_arrays.push(arr);
            memory_name_to_idx.insert(mem.name.clone(), idx);
        }

        Ok(Self {
            ir,
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            reset_values,
            next_regs,
            seq_targets,
            seq_clocks,
            clock_indices,
            old_clocks,
            clock_domain_assigns,
            memory_arrays,
            memory_name_to_idx,
            compiled_lib: None,
            compiled: cfg!(feature = "aot"),
        })
    }

    pub fn mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    pub fn mask_const(width: usize) -> String {
        if width >= 64 {
            "0xFFFFFFFFFFFFFFFFu64".to_string()
        } else {
            format!("0x{:X}u64", (1u64 << width) - 1)
        }
    }

    pub fn expr_width(&self, expr: &ExprDef) -> usize {
        match expr {
            ExprDef::Signal { width, .. } => *width,
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

    pub fn evaluate(&mut self) {
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
                type EvalFn = unsafe extern "C" fn(*mut u64, usize);
                let func: libloading::Symbol<EvalFn> =
                    lib.get(b"evaluate").expect("evaluate function not found");
                func(self.signals.as_mut_ptr(), self.signals.len());
            }
        }

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
        if let Some(&idx) = self.name_to_idx.get(name) {
            let width = self.widths.get(idx).copied().unwrap_or(64);
            self.signals[idx] = value & Self::mask(width);
            Ok(())
        } else {
            Err(format!("Unknown signal: {}", name))
        }
    }

    pub fn peek(&self, name: &str) -> Result<u64, String> {
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
        #[cfg(feature = "aot")]
        unsafe {
            crate::aot_generated::tick(
                self.signals.as_mut_ptr(),
                self.signals.len(),
                self.old_clocks.as_mut_ptr(),
                self.next_regs.as_mut_ptr(),
            );
        }
        #[cfg(not(feature = "aot"))]
        {
            let lib = self.compiled_lib.as_ref().unwrap();
            unsafe {
                type TickFn = unsafe extern "C" fn(*mut u64, usize, *mut u64, *mut u64);
                let func: libloading::Symbol<TickFn> =
                    lib.get(b"tick").expect("tick function not found");
                func(
                    self.signals.as_mut_ptr(),
                    self.signals.len(),
                    self.old_clocks.as_mut_ptr(),
                    self.next_regs.as_mut_ptr(),
                );
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
            if let ExprDef::Signal { name, .. } = &assign.expr {
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
    pub fn generate_core_code(&self) -> String {
        let mut code = String::new();

        code.push_str("//! Auto-generated circuit simulation code\n");
        code.push_str("//! Generated by RHDL IR Compiler (Core)\n\n");

        // Generate mutable memory arrays.
        //
        // The compiled backend needs to support runtime memory loading (e.g. Disk II ROM/track data),
        // so we generate `static mut` arrays and expose a C ABI to write them.
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!("const MEM_{}_DEPTH: usize = {};\n", idx, mem.depth));
            code.push_str(&format!("static mut MEM_{}: [u64; MEM_{}_DEPTH] = [0u64; MEM_{}_DEPTH];\n\n", idx, idx, idx));
        }

        // Initialize memories with non-zero initial data (ROMs).
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn init_memories() {\n");
        for (idx, _mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!(
                "    for i in 0..MEM_{}_DEPTH {{ MEM_{}[i] = 0u64; }}\n",
                idx, idx
            ));
        }
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if val != 0 {
                    code.push_str(&format!("    MEM_{}[{}] = {}u64;\n", idx, i, val));
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
                "        {} => {{ let depth = MEM_{}_DEPTH; for (i, &b) in data.iter().enumerate() {{ MEM_{}[(offset as usize + i) % depth] = b as u64; }} }},\n",
                idx, idx, idx
            ));
        }
        code.push_str("        _ => {}\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");

        // Generate evaluate function (inline for performance)
        code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn evaluate_inline(signals: &mut [u64]) {\n");
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

        let levels = self.compute_assignment_levels();
        for level in &levels {
            for &assign_idx in level {
                let assign = &self.ir.assigns[assign_idx];
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    let width = self.widths.get(idx).copied().unwrap_or(64);
                    let expr_width = self.expr_width(&assign.expr);
                    let expr_code = self.expr_to_rust_ptr_cached(&assign.expr, "s", &comb_cache_names);
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

        // Generate extern "C" wrapper for evaluate
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(signals: *mut u64, len: usize) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        // Generate tick function
        self.generate_tick_function(&mut code);

        code
    }

    pub fn expr_to_rust_ptr(&self, expr: &ExprDef, signals_ptr: &str) -> String {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                format!("(*{}.add({}))", signals_ptr, idx)
            }
            ExprDef::Literal { value, width } => {
                let masked = (*value as u64) & Self::mask(*width);
                format!("{}u64", masked)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code = self.expr_to_rust_ptr(operand, signals_ptr);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        format!("(if ({} & {}) == {} {{ 1u64 }} else {{ 0u64 }})",
                                operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("(if {} != 0 {{ 1u64 }} else {{ 0u64 }})", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u64 & 1)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust_ptr(left, signals_ptr);
                let r = self.expr_to_rust_ptr(right, signals_ptr);
                let m = Self::mask_const(*width);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & {})", l, r, m),
                    "-" => format!("({}.wrapping_sub({}) & {})", l, r, m),
                    "*" => format!("({}.wrapping_mul({}) & {})", l, r, m),
                    "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0u64 }})", r, l, r),
                    "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0u64 }})", r, l, r),
                    "<<" => format!("(({} << {}.min(63)) & {})", l, r, m),
                    ">>" => format!("({} >> {}.min(63))", l, r),
                    "==" => format!("(if {} == {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "!=" => format!("(if {} != {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<" => format!("(if {} < {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">" => format!("(if {} > {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<=" | "le" => format!("(if {} <= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">=" => format!("(if {} >= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    _ => "0u64".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.expr_to_rust_ptr(condition, signals_ptr);
                let t = self.expr_to_rust_ptr(when_true, signals_ptr);
                let f = self.expr_to_rust_ptr(when_false, signals_ptr);
                format!(
                    "((if {} != 0 {{ {} }} else {{ {} }}) & {})",
                    cond,
                    t,
                    f,
                    Self::mask_const(*width)
                )
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust_ptr(base, signals_ptr);
                format!(
                    "(({} >> ({}usize).min(63)) & {})",
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
                    let part_code = self.expr_to_rust_ptr(part, signals_ptr);
                    let part_width = self.expr_width(part);
                    if shift >= 64 {
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
                let expr_code = self.expr_to_rust_ptr(expr, signals_ptr);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust_ptr(addr, signals_ptr);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & {})",
                        mem_idx, addr_code, Self::mask_const(*width))
            }
        }
    }

    pub fn expr_to_rust_ptr_cached(
        &self,
        expr: &ExprDef,
        signals_ptr: &str,
        cache: &HashMap<usize, String>,
    ) -> String {
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                if let Some(temp) = cache.get(&idx) {
                    temp.clone()
                } else {
                    format!("(*{}.add({}))", signals_ptr, idx)
                }
            }
            ExprDef::Literal { value, width } => {
                let masked = (*value as u64) & Self::mask(*width);
                format!("{}u64", masked)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code = self.expr_to_rust_ptr_cached(operand, signals_ptr, cache);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        format!("(if ({} & {}) == {} {{ 1u64 }} else {{ 0u64 }})",
                                operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("(if {} != 0 {{ 1u64 }} else {{ 0u64 }})", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u64 & 1)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust_ptr_cached(left, signals_ptr, cache);
                let r = self.expr_to_rust_ptr_cached(right, signals_ptr, cache);
                let m = Self::mask_const(*width);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & {})", l, r, m),
                    "-" => format!("({}.wrapping_sub({}) & {})", l, r, m),
                    "*" => format!("({}.wrapping_mul({}) & {})", l, r, m),
                    "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0u64 }})", r, l, r),
                    "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0u64 }})", r, l, r),
                    "<<" => format!("(({} << {}.min(63)) & {})", l, r, m),
                    ">>" => format!("({} >> {}.min(63))", l, r),
                    "==" => format!("(if {} == {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "!=" => format!("(if {} != {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<" => format!("(if {} < {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">" => format!("(if {} > {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<=" | "le" => format!("(if {} <= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">=" => format!("(if {} >= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    _ => "0u64".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.expr_to_rust_ptr_cached(condition, signals_ptr, cache);
                let t = self.expr_to_rust_ptr_cached(when_true, signals_ptr, cache);
                let f = self.expr_to_rust_ptr_cached(when_false, signals_ptr, cache);
                format!(
                    "((if {} != 0 {{ {} }} else {{ {} }}) & {})",
                    cond,
                    t,
                    f,
                    Self::mask_const(*width)
                )
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust_ptr_cached(base, signals_ptr, cache);
                format!(
                    "(({} >> ({}usize).min(63)) & {})",
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
                    let part_code = self.expr_to_rust_ptr_cached(part, signals_ptr, cache);
                    let part_width = self.expr_width(part);
                    if shift >= 64 {
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
                let expr_code = self.expr_to_rust_ptr_cached(expr, signals_ptr, cache);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust_ptr_cached(addr, signals_ptr, cache);
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
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                if let Some(&target_idx) = self.name_to_idx.get(&stmt.target) {
                    let width = self.widths.get(target_idx).copied().unwrap_or(64);
                    let expr_width = self.expr_width(&stmt.expr);
                    let expr_code = self.expr_to_rust_ptr_cached(&stmt.expr, "s", &seq_cache_names);
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

            let enable_code = self.expr_to_rust_ptr(&wp.enable, "s");
            let addr_code = self.expr_to_rust_ptr(&wp.addr, "s");
            let data_code = self.expr_to_rust_ptr(&wp.data, "s");
            write_port_code.push_str(&format!("    if *s.add({}) != 0 {{\n", clock_idx));
            write_port_code.push_str(&format!("        if (({}) & 1) != 0 {{\n", enable_code));
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
            let addr_code = self.expr_to_rust_ptr(&rp.addr, "s");
            sync_read_port_code.push_str(&format!("    if *s.add({}) != 0 {{\n", clock_idx));
            if let Some(enable) = &rp.enable {
                let enable_code = self.expr_to_rust_ptr(enable, "s");
                sync_read_port_code.push_str(&format!("        if (({}) & 1) != 0 {{\n", enable_code));
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
            "pub unsafe fn sample_next_regs_inline(signals: &mut [u64], next_regs: &mut [u64; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str(&seq_sample_code);
        code.push_str("}\n\n");

        code.push_str("/// Apply sampled sequential values to target registers\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn apply_next_regs_inline(signals: &mut [u64], next_regs: &[u64; {}]) {{\n",
            num_regs.max(1)
        ));
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str(&seq_apply_code);
        code.push_str("}\n\n");

        code.push_str("/// Apply synchronous memory write ports for the current level\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn apply_write_ports_inline(signals: &mut [u64]) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        if write_port_code.is_empty() {
            code.push_str("    let _ = s;\n");
        } else {
            code.push_str(&write_port_code);
        }
        code.push_str("}\n\n");

        code.push_str("/// Apply synchronous memory read ports for the current level\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("pub unsafe fn apply_sync_read_ports_inline(signals: &mut [u64]) {\n");
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
            "pub unsafe fn tick_forced_inline(signals: &mut [u64], next_regs: &mut [u64; {}]) {{\n",
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
        code.push_str("pub unsafe fn drive_clock_low_inline(signals: &mut [u64], clk_idx: usize) {\n");
        code.push_str("    let s = signals.as_mut_ptr();\n");
        code.push_str("    *s.add(clk_idx) = 0;\n");
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        code.push_str("/// Drive a specific clock high and execute edge-triggered updates.\n");
        code.push_str("/// Reusable rising-edge helper for extension batched loops using generic tick.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!(
            "pub unsafe fn drive_clock_high_tick_inline(signals: &mut [u64], clk_idx: usize, old_clocks: &mut [u64; {}], next_regs: &mut [u64; {}]) {{\n",
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
            "pub unsafe fn pulse_clock_forced_inline(signals: &mut [u64], clk_idx: usize, next_regs: &mut [u64; {}]) {{\n",
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
        code.push_str(&format!("pub unsafe fn tick_inline(signals: &mut [u64], old_clocks: &mut [u64; {}], next_regs: &mut [u64; {}]) {{\n",
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
        code.push_str(&format!("        let mut clock_before = [0u64; {}];\n", num_clocks));
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
        code.push_str(&format!("pub unsafe extern \"C\" fn tick(signals: *mut u64, len: usize, old_clocks: *mut u64, next_regs: *mut u64) {{\n"));
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str(&format!("    let old_clocks = &mut *(old_clocks as *mut [u64; {}]);\n", num_clocks));
        code.push_str(&format!("    let next_regs = &mut *(next_regs as *mut [u64; {}]);\n", num_regs.max(1)));
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
            return Ok(true);
        }

        // Write source and compile into a unique temporary output file.
        fs::write(&tmp_src_path, code).map_err(|e| e.to_string())?;

        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "--crate-name",
                crate_name.as_str(),
                "-C", "opt-level=3",
                "-C", "target-cpu=native",
                "-C", "panic=abort",
                "-C", "lto=thin",
                "-C", "codegen-units=1",
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
}
