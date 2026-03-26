//! Core Cranelift JIT compiler for IR simulation
//!
//! This module contains the generic JIT compiler and simulator without
//! any example-specific code. Extensions for Apple II and MOS6502
//! are in separate modules.

use serde::Deserialize;
use serde_json::{Map, Value};
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::mem;

use cranelift::prelude::*;
use cranelift_jit::{JITBuilder, JITModule};
use cranelift_module::{Linkage, Module};

use crate::signal_value::{
    deserialize_optional_signal_value,
    deserialize_signal_values,
    deserialize_signed_signal_value,
    SignalValue,
    SignedSignalValue,
};
use crate::runtime_value::RuntimeValue;

type SimValue = u128;

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
    #[serde(deserialize_with = "deserialize_optional_signal_value")]
    pub reset_value: Option<SignalValue>,
}

/// Expression types (JSON deserialization)
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
    #[allow(dead_code)]
    Slice {
        base: Box<ExprDef>,
        #[serde(alias = "range_begin")]
        low: usize,
        #[serde(alias = "range_end")]
        high: usize,
        width: usize,
    },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
    #[serde(alias = "memory_read")]
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
    #[serde(deserialize_with = "deserialize_signal_values")]
    pub initial_data: Vec<SignalValue>,
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
    let expr_pool = array_field(&module_obj, "exprs");
    let mut synthesized_exprs = Vec::new();
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
                .map(|v| assign_to_normalized_value(&v, &expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "processes".to_string(),
        Value::Array(
            array_field(&module_obj, "processes")
                .into_iter()
                .map(|v| process_to_normalized_value(&v, &expr_pool, &mut synthesized_exprs))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert("exprs".to_string(), Value::Array(synthesized_exprs));
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
                .map(|v| write_port_to_normalized_value(&v, &expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "sync_read_ports".to_string(),
        Value::Array(
            array_field(&module_obj, "sync_read_ports")
                .into_iter()
                .map(|v| sync_read_port_to_normalized_value(&v, &expr_pool))
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

fn assign_to_normalized_value(value: &Value, expr_pool: &[Value]) -> Result<Value, String> {
    let obj = as_object(value, "assign")?;
    let mut out = Map::new();
    out.insert("target".to_string(), Value::String(value_to_string(obj.get("target"))));
    out.insert("expr".to_string(), expr_to_normalized_value(obj.get("expr"), expr_pool)?);
    Ok(Value::Object(out))
}

fn process_to_normalized_value(
    value: &Value,
    expr_pool: &[Value],
    synthesized_exprs: &mut Vec<Value>,
) -> Result<Value, String> {
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
        Value::Array(flatten_statements(
            array_field(obj, "statements"),
            expr_pool,
            synthesized_exprs,
        )?),
    );
    Ok(Value::Object(out))
}

fn flatten_statements(
    statements: Vec<Value>,
    expr_pool: &[Value],
    synthesized_exprs: &mut Vec<Value>,
) -> Result<Vec<Value>, String> {
    let mut out = Vec::new();
    let mut effective_targets = HashMap::new();
    flatten_statements_with_guard(
        statements,
        None,
        &mut out,
        expr_pool,
        &mut effective_targets,
        synthesized_exprs,
    )?;
    Ok(out)
}

fn flatten_statements_with_guard(
    statements: Vec<Value>,
    guard: Option<Value>,
    out: &mut Vec<Value>,
    expr_pool: &[Value],
    effective_targets: &mut HashMap<String, Value>,
    synthesized_exprs: &mut Vec<Value>,
) -> Result<(), String> {
    for stmt in statements {
        let stmt_obj = as_object(&stmt, "statement")?;
        match stmt_obj.get("kind").and_then(Value::as_str).unwrap_or("") {
            "seq_assign" => {
                let target = value_to_string(stmt_obj.get("target"));
                let assigned_expr = expr_to_normalized_value(stmt_obj.get("expr"), expr_pool)?;
                let width = expr_width(Some(&assigned_expr)).unwrap_or(8);
                let prior_expr = effective_targets
                    .get(&target)
                    .cloned()
                    .unwrap_or_else(|| signal_expr(target.clone(), width));
                let expr = match &guard {
                    Some(path_guard) => mux_expr(
                        path_guard.clone(),
                        assigned_expr,
                        prior_expr,
                        width,
                    ),
                    None => assigned_expr,
                };
                let pooled_expr = intern_expr(expr, synthesized_exprs);
                effective_targets.insert(target.clone(), pooled_expr.clone());
                let mut seq = Map::new();
                seq.insert("target".to_string(), Value::String(target));
                seq.insert("expr".to_string(), pooled_expr);
                out.push(Value::Object(seq));
            }
            "if" => flatten_if(
                stmt_obj,
                guard.clone(),
                out,
                expr_pool,
                effective_targets,
                synthesized_exprs,
            )?,
            _ => {}
        }
    }
    Ok(())
}

fn combine_path_guard(guard: Option<Value>, cond: Value, synthesized_exprs: &mut Vec<Value>) -> Value {
    let combined = match guard {
        Some(path_guard) => binary_expr("&", path_guard, cond, 1),
        None => cond,
    };
    intern_expr(combined, synthesized_exprs)
}

fn flatten_if(
    if_obj: &Map<String, Value>,
    guard: Option<Value>,
    out: &mut Vec<Value>,
    expr_pool: &[Value],
    effective_targets: &mut HashMap<String, Value>,
    synthesized_exprs: &mut Vec<Value>,
) -> Result<(), String> {
    let cond = expr_to_normalized_value(if_obj.get("condition"), expr_pool)?;
    let then_guard = combine_path_guard(guard.clone(), cond.clone(), synthesized_exprs);
    flatten_statements_with_guard(
        array_field(if_obj, "then_statements"),
        Some(then_guard),
        out,
        expr_pool,
        effective_targets,
        synthesized_exprs,
    )?;

    let else_cond = intern_expr(binary_expr("^", cond, literal_expr(1, 1), 1), synthesized_exprs);
    let else_guard = combine_path_guard(guard, else_cond, synthesized_exprs);
    flatten_statements_with_guard(
        array_field(if_obj, "else_statements"),
        Some(else_guard),
        out,
        expr_pool,
        effective_targets,
        synthesized_exprs,
    )?;

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

fn write_port_to_normalized_value(value: &Value, expr_pool: &[Value]) -> Result<Value, String> {
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
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"), expr_pool)?);
    out.insert("data".to_string(), expr_to_normalized_value(obj.get("data"), expr_pool)?);
    out.insert("enable".to_string(), expr_to_normalized_value(obj.get("enable"), expr_pool)?);
    Ok(Value::Object(out))
}

fn sync_read_port_to_normalized_value(value: &Value, expr_pool: &[Value]) -> Result<Value, String> {
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
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"), expr_pool)?);
    out.insert(
        "data".to_string(),
        Value::String(value_to_string(obj.get("data"))),
    );
    if let Some(enable) = obj.get("enable") {
        if !enable.is_null() {
            out.insert("enable".to_string(), expr_to_normalized_value(Some(enable), expr_pool)?);
        }
    }
    Ok(Value::Object(out))
}

fn expr_to_normalized_value(expr: Option<&Value>, expr_pool: &[Value]) -> Result<Value, String> {
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
            let id = value_to_usize(obj.get("id"));
            let referenced = expr_pool
                .get(id)
                .ok_or_else(|| format!("Expression ref id {} out of range", id))?;
            expr_to_normalized_value(Some(referenced), expr_pool)
        }
        "unary" => Ok(unary_expr(
            &value_to_string(obj.get("op")),
            expr_to_normalized_value(obj.get("operand"), expr_pool)?,
            value_to_usize(obj.get("width")),
        )),
        "binary" => Ok(binary_expr(
            &value_to_string(obj.get("op")),
            expr_to_normalized_value(obj.get("left"), expr_pool)?,
            expr_to_normalized_value(obj.get("right"), expr_pool)?,
            value_to_usize(obj.get("width")),
        )),
        "mux" => Ok(mux_expr(
            expr_to_normalized_value(obj.get("condition"), expr_pool)?,
            expr_to_normalized_value(obj.get("when_true"), expr_pool)?,
            expr_to_normalized_value(obj.get("when_false"), expr_pool)?,
            value_to_usize(obj.get("width")),
        )),
        "slice" => {
            let begin = value_to_i64(obj.get("range_begin"));
            let end = value_to_i64(obj.get("range_end"));
            let low = begin.min(end);
            let high = begin.max(end);
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("slice".to_string()));
            out.insert("base".to_string(), expr_to_normalized_value(obj.get("base"), expr_pool)?);
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
                        .map(|part| expr_to_normalized_value(Some(&part), expr_pool))
                        .collect::<Result<Vec<_>, _>>()?,
                ),
            );
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "resize" => {
            let mut out = Map::new();
            out.insert("kind".to_string(), Value::String("resize".to_string()));
            out.insert("expr".to_string(), expr_to_normalized_value(obj.get("expr"), expr_pool)?);
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
            out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"), expr_pool)?);
            out.insert("width".to_string(), Value::from(value_to_u64(obj.get("width"))));
            Ok(Value::Object(out))
        }
        "case" => lower_case_expr(obj, expr_pool),
        _ => Ok(literal_expr(0, 1)),
    }
}

fn lower_case_expr(case_obj: &Map<String, Value>, expr_pool: &[Value]) -> Result<Value, String> {
    let selector = expr_to_normalized_value(case_obj.get("selector"), expr_pool)?;
    let width = value_to_usize(case_obj.get("width"));
    let default_expr = if let Some(default_value) = case_obj.get("default") {
        if !default_value.is_null() {
            expr_to_normalized_value(Some(default_value), expr_pool)?
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
                    expr_to_normalized_value(Some(raw_expr), expr_pool)?,
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

fn expr_ref_expr(id: usize, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("expr_ref".to_string()));
    out.insert("id".to_string(), Value::from(id as u64));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn intern_expr(expr: Value, synthesized_exprs: &mut Vec<Value>) -> Value {
    let width = expr_width(Some(&expr)).unwrap_or(1);
    let expr_ref = expr_ref_expr(synthesized_exprs.len(), width);
    synthesized_exprs.push(expr);
    expr_ref
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

/// Function signature for evaluate: fn(signals: *mut u128, mem_ptrs: *const *const u128) -> ()
pub type EvaluateFn = unsafe extern "C" fn(*mut SimValue, *const *const SimValue);

/// Function signature for tick: fn(signals: *mut u128, next_regs: *mut u128, mem_ptrs: *const *const u128) -> ()
pub type TickFn = unsafe extern "C" fn(*mut SimValue, *mut SimValue, *const *const SimValue);

unsafe extern "C" fn noop_evaluate_fn(_signals: *mut SimValue, _mem_ptrs: *const *const SimValue) {}

unsafe extern "C" fn noop_tick_fn(_signals: *mut SimValue, _next_regs: *mut SimValue, _mem_ptrs: *const *const SimValue) {}

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

    fn compile_mask(width: usize) -> SimValue {
        if width == 0 {
            0
        } else if width >= 128 {
            SimValue::MAX
        } else {
            (1u128 << width) - 1
        }
    }

    fn emit_const(builder: &mut FunctionBuilder, value: SimValue) -> cranelift::prelude::Value {
        let low = builder.ins().iconst(types::I64, value as u64 as i64);
        let high = builder.ins().iconst(types::I64, (value >> 64) as u64 as i64);
        builder.ins().iconcat(low, high)
    }

    /// Compile an expression, returning the Cranelift value
    fn compile_expr(
        &self,
        builder: &mut FunctionBuilder,
        expr: &ExprDef,
        signals_ptr: cranelift::prelude::Value,
        mem_ptrs: &[cranelift::prelude::Value],
    ) -> cranelift::prelude::Value {
        let pointer_type = builder.func.dfg.value_type(signals_ptr);
        match expr {
            ExprDef::Signal { name, .. } => {
                let idx = *self.name_to_idx.get(name).unwrap_or(&0);
                let offset = (idx * std::mem::size_of::<SimValue>()) as i32;
                builder.ins().load(types::I128, MemFlags::trusted(), signals_ptr, offset)
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compile_mask(*width);
                let masked = (*value as i128 as SimValue) & mask;
                Self::emit_const(builder, masked)
            }
            ExprDef::ExprRef { .. } => builder.ins().iconst(types::I128, 0),
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.compile_expr(builder, operand, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = Self::emit_const(builder, mask);

                match op.as_str() {
                    "~" | "not" => {
                        let not_val = builder.ins().bnot(src);
                        builder.ins().band(not_val, mask_val)
                    }
                    "&" | "reduce_and" => {
                        let op_width = Self::expr_width(operand, &self.widths, &self.name_to_idx);
                        let op_mask = Self::compile_mask(op_width);
                        let op_mask_val = Self::emit_const(builder, op_mask);
                        let masked = builder.ins().band(src, op_mask_val);
                        let cmp = builder.ins().icmp(IntCC::Equal, masked, op_mask_val);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    "|" | "reduce_or" => {
                        let zero = builder.ins().iconst(types::I128, 0);
                        let cmp = builder.ins().icmp(IntCC::NotEqual, src, zero);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    "^" | "reduce_xor" => {
                        let popcnt = builder.ins().popcnt(src);
                        let one = builder.ins().iconst(types::I128, 1);
                        builder.ins().band(popcnt, one)
                    }
                    _ => src,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.compile_expr(builder, left, signals_ptr, mem_ptrs);
                let r = self.compile_expr(builder, right, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = Self::emit_const(builder, mask);

                let result = match op.as_str() {
                    "&" => builder.ins().band(l, r),
                    "|" => builder.ins().bor(l, r),
                    "^" => builder.ins().bxor(l, r),
                    "+" => builder.ins().iadd(l, r),
                    "-" => builder.ins().isub(l, r),
                    "*" => builder.ins().imul(l, r),
                    "/" => {
                        let zero = builder.ins().iconst(types::I128, 0);
                        let one = builder.ins().iconst(types::I128, 1);
                        let is_zero = builder.ins().icmp(IntCC::Equal, r, zero);
                        let safe_r = builder.ins().select(is_zero, one, r);
                        let div_result = builder.ins().udiv(l, safe_r);
                        builder.ins().select(is_zero, zero, div_result)
                    }
                    "%" => {
                        let zero = builder.ins().iconst(types::I128, 0);
                        let one = builder.ins().iconst(types::I128, 1);
                        let is_zero = builder.ins().icmp(IntCC::Equal, r, zero);
                        let safe_r = builder.ins().select(is_zero, one, r);
                        let mod_result = builder.ins().urem(l, safe_r);
                        builder.ins().select(is_zero, zero, mod_result)
                    }
                    "<<" => {
                        let shift = builder.ins().ireduce(types::I8, r);
                        builder.ins().ishl(l, shift)
                    }
                    ">>" => {
                        let shift = builder.ins().ireduce(types::I8, r);
                        builder.ins().ushr(l, shift)
                    }
                    "==" => {
                        let cmp = builder.ins().icmp(IntCC::Equal, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    "!=" => {
                        let cmp = builder.ins().icmp(IntCC::NotEqual, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    "<" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedLessThan, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    ">" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedGreaterThan, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    "<=" | "le" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedLessThanOrEqual, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    ">=" => {
                        let cmp = builder.ins().icmp(IntCC::UnsignedGreaterThanOrEqual, l, r);
                        builder.ins().uextend(types::I128, cmp)
                    }
                    _ => l,
                };

                builder.ins().band(result, mask_val)
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.compile_expr(builder, condition, signals_ptr, mem_ptrs);
                let t = self.compile_expr(builder, when_true, signals_ptr, mem_ptrs);
                let f = self.compile_expr(builder, when_false, signals_ptr, mem_ptrs);

                let zero = builder.ins().iconst(types::I128, 0);
                let cond_bool = builder.ins().icmp(IntCC::NotEqual, cond, zero);
                let result = builder.ins().select(cond_bool, t, f);

                let mask = Self::compile_mask(*width);
                let mask_val = Self::emit_const(builder, mask);
                builder.ins().band(result, mask_val)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = self.compile_expr(builder, base, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = Self::emit_const(builder, mask);
                let shift = builder.ins().iconst(types::I8, *low as i64);
                let shifted = builder.ins().ushr(src, shift);
                builder.ins().band(shifted, mask_val)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = builder.ins().iconst(types::I128, 0);
                let mut shift_acc = 0u8;

                for part in parts.iter().rev() {
                    let part_val = self.compile_expr(builder, part, signals_ptr, mem_ptrs);
                    let part_width = Self::expr_width(part, &self.widths, &self.name_to_idx);
                    let part_mask = Self::compile_mask(part_width);
                    let mask_val = Self::emit_const(builder, part_mask);
                    let masked = builder.ins().band(part_val, mask_val);

                    if shift_acc > 0 {
                        let shift = builder.ins().iconst(types::I8, shift_acc as i64);
                        let shifted = builder.ins().ishl(masked, shift);
                        result = builder.ins().bor(result, shifted);
                    } else {
                        result = builder.ins().bor(result, masked);
                    }

                    shift_acc = shift_acc.saturating_add(part_width.min(128) as u8);
                }

                let final_mask = Self::compile_mask(*width);
                let final_mask_val = Self::emit_const(builder, final_mask);
                builder.ins().band(result, final_mask_val)
            }
            ExprDef::Resize { expr, width } => {
                let src = self.compile_expr(builder, expr, signals_ptr, mem_ptrs);
                let mask = Self::compile_mask(*width);
                let mask_val = Self::emit_const(builder, mask);
                builder.ins().band(src, mask_val)
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = *self.mem_name_to_idx.get(memory).unwrap_or(&0);
                let depth = self.mem_depths.get(mem_idx).copied().unwrap_or(256);

                let addr_val = self.compile_expr(builder, addr, signals_ptr, mem_ptrs);

                if mem_idx < mem_ptrs.len() {
                    let mem_ptr = mem_ptrs[mem_idx];

                    let depth_val = Self::emit_const(builder, depth as SimValue);
                    let bounded_addr = builder.ins().urem(addr_val, depth_val);

                    let elem_size = Self::emit_const(builder, std::mem::size_of::<SimValue>() as SimValue);
                    let byte_offset = builder.ins().imul(bounded_addr, elem_size);
                    let byte_offset_ptr = builder.ins().ireduce(pointer_type, byte_offset);

                    let elem_ptr = builder.ins().iadd(mem_ptr, byte_offset_ptr);

                    let loaded = builder.ins().load(types::I128, MemFlags::trusted(), elem_ptr, 0);

                    let mask = Self::compile_mask(*width);
                    let mask_val = Self::emit_const(builder, mask);
                    builder.ins().band(loaded, mask_val)
                } else {
                    builder.ins().iconst(types::I128, 0)
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

    /// Group assignments into levels based on dependencies (topological sort)
    fn compute_assignment_levels(&self, assigns: &[AssignDef]) -> Vec<Vec<usize>> {
        let n = assigns.len();

        let mut target_to_assigns: HashMap<usize, Vec<usize>> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                target_to_assigns.entry(idx).or_insert_with(Vec::new).push(i);
            }
        }

        let mut assign_deps: Vec<HashSet<usize>> = Vec::with_capacity(n);
        for assign in assigns {
            let signal_deps = self.expr_dependencies(&assign.expr);
            let mut deps = HashSet::new();
            for sig_idx in signal_deps {
                if let Some(assign_indices) = target_to_assigns.get(&sig_idx) {
                    for &assign_idx in assign_indices {
                        deps.insert(assign_idx);
                    }
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
            let offset = (i * std::mem::size_of::<*const SimValue>()) as i32;
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

                let offset = (target_idx * std::mem::size_of::<SimValue>()) as i32;
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
            let offset = (i * std::mem::size_of::<*const SimValue>()) as i32;
            let mem_ptr = builder.ins().load(pointer_type, MemFlags::trusted(), mem_ptrs_base, offset);
            mem_ptrs.push(mem_ptr);
        }

        for (i, (_target, expr)) in seq_assigns.iter().enumerate() {
            let value = self.compile_expr(&mut builder, expr, signals_ptr, &mem_ptrs);
            let offset = (i * std::mem::size_of::<SimValue>()) as i32;
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
    /// Full-width signal values used by the runtime evaluator
    wide_signals: Vec<RuntimeValue>,
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
    pub next_regs: Vec<RuntimeValue>,
    /// Original combinational assignments for runtime evaluation
    comb_assigns: Vec<(usize, ExprDef)>,
    /// Sequential assignment target indices
    pub seq_targets: Vec<usize>,
    /// Original sequential assignment expressions for runtime sampling
    seq_exprs: Vec<ExprDef>,
    /// Shared expression pool for compact sequential expressions
    exprs: Vec<ExprDef>,
    /// Direct incoming reference count for each compact expr id
    expr_ref_use_counts: Vec<usize>,
    /// Per-pass memoization for compact expr evaluation on the runtime path
    runtime_expr_cache: RefCell<RuntimeExprEvalCache>,
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
    /// Declared memory widths
    memory_widths: Vec<usize>,
    /// Full-width memory arrays used by the runtime evaluator
    wide_memory_arrays: Vec<Vec<RuntimeValue>>,
    /// Memory reset snapshots
    memory_reset_arrays: Vec<Vec<u64>>,
    /// Full-width memory reset snapshots
    wide_memory_reset_arrays: Vec<Vec<RuntimeValue>>,
    /// Memory name to index mapping
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Memory write ports
    write_ports: Vec<ResolvedWritePort>,
    /// Memory synchronous read ports
    sync_read_ports: Vec<ResolvedSyncReadPort>,

    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, RuntimeValue)>,
}

impl CoreSimulator {
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
            ExprDef::Signal { .. } | ExprDef::Literal { .. } => {}
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

    pub fn new(json: &str) -> Result<Self, String> {
        let ir = parse_module_ir(json)?;
        let expr_ref_use_counts = Self::compute_expr_ref_use_counts(&ir);
        let expr_count = ir.exprs.len();

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
        let mut reset_values: Vec<(usize, RuntimeValue)> = Vec::new();
        for reg in &ir.regs {
            let idx = signals.len();
            let reset_val = reg.reset_value.unwrap_or(0) as SimValue;
            signals.push(reset_val as u64);
            widths.push(reg.width);
            name_to_idx.insert(reg.name.clone(), idx);
            if reset_val != 0 {
                reset_values.push((idx, RuntimeValue::from_u128(reset_val, reg.width)));
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

        let seq_exprs: Vec<ExprDef> = seq_assigns.iter().map(|(_, expr)| expr.clone()).collect();
        let next_regs = seq_targets
            .iter()
            .map(|&target_idx| RuntimeValue::zero(widths.get(target_idx).copied().unwrap_or(0)))
            .collect();

        // Build memory arrays
        let mut memory_arrays: Vec<Vec<u64>> = Vec::new();
        let mut mem_name_to_idx: HashMap<String, usize> = HashMap::new();
        let mut mem_depths: Vec<usize> = Vec::new();
        let mut mem_widths: Vec<usize> = Vec::new();

        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val as u64;
                }
            }
            memory_arrays.push(data);
            mem_name_to_idx.insert(mem.name.clone(), idx);
            mem_depths.push(mem.depth);
            mem_widths.push(mem.width);
        }

        let wide_signals: Vec<RuntimeValue> = signals.iter().enumerate()
            .map(|(idx, &value)| RuntimeValue::from_u128(value as SimValue, widths.get(idx).copied().unwrap_or(0)))
            .collect();
        let wide_memory_arrays: Vec<Vec<RuntimeValue>> = memory_arrays.iter().enumerate()
            .map(|(mem_idx, mem)| {
                let width = *mem_widths.get(mem_idx).unwrap_or(&64);
                mem.iter().map(|&value| RuntimeValue::from_u128(value as SimValue, width)).collect()
            })
            .collect();
        let memory_reset_arrays = memory_arrays.clone();
        let wide_memory_reset_arrays = wide_memory_arrays.clone();
        let mut compiler = JitCompiler::new()?;
        compiler.set_mappings(name_to_idx.clone(), widths.clone(), mem_name_to_idx.clone(), mem_depths.clone());
        let comb_assigns: Vec<(usize, ExprDef)> = compiler.compute_assignment_levels(&ir.assigns)
            .into_iter()
            .flatten()
            .filter_map(|assign_idx| {
                let assign = ir.assigns.get(assign_idx)?;
                name_to_idx.get(&assign.target).copied().map(|idx| (idx, assign.expr.clone()))
            })
            .collect();

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

        let evaluate_fn = noop_evaluate_fn as EvaluateFn;
        let seq_sample_fn = noop_tick_fn as TickFn;

        Ok(Self {
            signals,
            wide_signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            signal_count,
            reg_count,
            next_regs,
            comb_assigns,
            seq_targets,
            seq_exprs,
            exprs: ir.exprs.clone(),
            expr_ref_use_counts,
            runtime_expr_cache: RefCell::new(RuntimeExprEvalCache::new(expr_count)),
            seq_clocks,
            clock_indices,
            prev_clock_values,
            evaluate_fn,
            seq_sample_fn,
            memory_arrays,
            memory_widths: mem_widths,
            wide_memory_arrays,
            memory_reset_arrays,
            wide_memory_reset_arrays,
            memory_name_to_idx: mem_name_to_idx,
            write_ports,
            sync_read_ports,
            reset_values,
        })
    }

    pub fn compute_mask(width: usize) -> SimValue {
        if width == 0 {
            0
        } else if width >= 128 {
            SimValue::MAX
        } else {
            (1u128 << width) - 1
        }
    }

    #[inline(always)]
    fn low_word(value: SimValue) -> u64 {
        (value & 0xFFFF_FFFF_FFFF_FFFF) as u64
    }

    fn signal_runtime_value(&self, idx: usize, width: usize) -> RuntimeValue {
        self.wide_signals
            .get(idx)
            .cloned()
            .unwrap_or_else(|| RuntimeValue::zero(width))
            .mask(width)
    }

    fn store_signal_runtime_value(&mut self, idx: usize, width: usize, value: RuntimeValue) {
        let masked = value.mask(width);
        if idx < self.wide_signals.len() {
            self.wide_signals[idx] = masked.clone();
        }
        if idx < self.signals.len() {
            self.signals[idx] = Self::low_word(masked.low_u128());
        }
    }

    fn memory_runtime_value(&self, memory_idx: usize, width: usize, addr: usize) -> RuntimeValue {
        self.wide_memory_arrays
            .get(memory_idx)
            .and_then(|mem| mem.get(addr))
            .cloned()
            .unwrap_or_else(|| RuntimeValue::zero(width))
            .mask(width)
    }

    fn store_memory_runtime_value(&mut self, memory_idx: usize, width: usize, addr: usize, value: RuntimeValue) {
        let masked = value.mask(width);
        if let Some(mem) = self.wide_memory_arrays.get_mut(memory_idx) {
            if addr < mem.len() {
                mem[addr] = masked.clone();
            }
        }
        if let Some(mem) = self.memory_arrays.get_mut(memory_idx) {
            if addr < mem.len() {
                mem[addr] = Self::low_word(masked.low_u128());
            }
        }
    }

    #[inline(always)]
    pub fn peek_word_by_idx(&self, idx: usize, word_idx: usize) -> u64 {
        if idx >= self.wide_signals.len() {
            return 0;
        }
        let width = self.widths.get(idx).copied().unwrap_or(0);
        self.signal_runtime_value(idx, width).word(width, word_idx)
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

    fn sample_next_regs(&mut self) {
        // Keep the JIT-compiled combinational evaluator, but use the proven
        // runtime evaluator for next-state sampling. Imported CIRCT packages can
        // generate very large nested mux trees that the compiled seq-sample path
        // does not yet handle reliably.
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for (idx, expr) in self.seq_exprs.iter().enumerate() {
                self.next_regs[idx] = self.eval_expr_runtime_with_cache(expr, &mut *cache);
            }
        }
    }

    fn runtime_expr_width(expr: &ExprDef, widths: &[usize], name_to_idx: &HashMap<String, usize>) -> usize {
        match expr {
            ExprDef::Signal { name, width } => {
                name_to_idx.get(name).and_then(|&idx| widths.get(idx).copied()).unwrap_or(*width)
            }
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

    fn eval_expr_runtime_with_cache(
        &self,
        expr: &ExprDef,
        cache: &mut RuntimeExprEvalCache,
    ) -> RuntimeValue {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                self.signal_runtime_value(idx, *width)
            }
            ExprDef::Literal { value, width } => RuntimeValue::from_signed_i128(*value, *width),
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
                let Some(expr) = self.exprs.get(*id) else {
                    return RuntimeValue::zero(*width);
                };
                let value = self.eval_expr_runtime_with_cache(expr, cache).resize(*width);
                if should_cache {
                    cache.store(*id, value.clone());
                }
                value
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.eval_expr_runtime_with_cache(operand, cache);
                match op.as_str() {
                    "~" | "not" => RuntimeValue::from_u128(Self::compute_mask(*width), *width)
                        .bitxor(&src, *width),
                    "&" | "reduce_and" => {
                        let op_width = Self::runtime_expr_width(operand, &self.widths, &self.name_to_idx);
                        RuntimeValue::from_u128(if src.reduce_and(op_width) { 1 } else { 0 }, *width)
                    }
                    "|" | "reduce_or" => RuntimeValue::from_u128(if src.is_zero() { 0 } else { 1 }, *width),
                    "^" | "reduce_xor" => RuntimeValue::from_u128(src.reduce_xor(), *width),
                    _ => src.mask(*width),
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.eval_expr_runtime_with_cache(left, cache);
                let r = self.eval_expr_runtime_with_cache(right, cache);
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
                        let shift = Self::runtime_shift_amount(&r, Self::runtime_expr_width(right, &self.widths, &self.name_to_idx));
                        if shift == usize::MAX { RuntimeValue::zero(*width) } else { l.shl(shift, *width) }
                    }
                    ">>" => {
                        let shift = Self::runtime_shift_amount(&r, Self::runtime_expr_width(right, &self.widths, &self.name_to_idx));
                        if shift == usize::MAX { RuntimeValue::zero(*width) } else { l.shr(shift, *width) }
                    }
                    "==" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) == std::cmp::Ordering::Equal) as u128, *width),
                    "!=" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) != std::cmp::Ordering::Equal) as u128, *width),
                    "<" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) == std::cmp::Ordering::Less) as u128, *width),
                    ">" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) == std::cmp::Ordering::Greater) as u128, *width),
                    "<=" | "le" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) != std::cmp::Ordering::Greater) as u128, *width),
                    ">=" => RuntimeValue::from_u128((l.cmp_unsigned(&r, Self::runtime_expr_width(left, &self.widths, &self.name_to_idx).max(Self::runtime_expr_width(right, &self.widths, &self.name_to_idx))) != std::cmp::Ordering::Less) as u128, *width),
                    _ => l.mask(*width),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.eval_expr_runtime_with_cache(condition, cache);
                let selected = if cond.is_zero() {
                    self.eval_expr_runtime_with_cache(when_false, cache)
                } else {
                    self.eval_expr_runtime_with_cache(when_true, cache)
                };
                selected.mask(*width)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_val = self.eval_expr_runtime_with_cache(base, cache);
                base_val.slice(*low, *width)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = RuntimeValue::zero(*width);
                for part in parts {
                    let part_width = Self::runtime_expr_width(part, &self.widths, &self.name_to_idx);
                    let value = self.eval_expr_runtime_with_cache(part, cache);
                    result = result.shl(part_width, *width);
                    result = result.bitor(&value.mask(part_width), *width);
                }
                result.mask(*width)
            }
            ExprDef::Resize { expr, width } => self.eval_expr_runtime_with_cache(expr, cache).resize(*width),
            ExprDef::MemRead { memory, addr, width } => {
                let Some(&memory_idx) = self.memory_name_to_idx.get(memory) else {
                    return RuntimeValue::zero(*width);
                };
                let Some(mem) = self.wide_memory_arrays.get(memory_idx) else {
                    return RuntimeValue::zero(*width);
                };
                if mem.is_empty() {
                    return RuntimeValue::zero(*width);
                }
                let addr_val = self.eval_expr_runtime_with_cache(addr, cache).low_u128() as usize % mem.len();
                self.memory_runtime_value(memory_idx, *width, addr_val)
            }
        }
    }

    fn eval_expr_runtime(&self, expr: &ExprDef) -> RuntimeValue {
        let mut cache = RuntimeExprEvalCache::new(self.exprs.len());
        cache.next_epoch();
        self.eval_expr_runtime_with_cache(expr, &mut cache)
    }

    fn apply_write_ports_level(&mut self) {
        if self.write_ports.is_empty() {
            return;
        }

        let mut writes: Vec<(usize, usize, usize, RuntimeValue)> = Vec::new();
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for wp in &self.write_ports {
                if self.signal_runtime_value(wp.clock_idx, self.widths.get(wp.clock_idx).copied().unwrap_or(0)).is_zero() {
                    continue;
                }
                if (self.eval_expr_runtime_with_cache(&wp.enable, &mut *cache).low_u128() & 1) == 0 {
                    continue;
                }
                if wp.memory_depth == 0 {
                    continue;
                }

                let addr = (self.eval_expr_runtime_with_cache(&wp.addr, &mut *cache).low_u128() as usize) % wp.memory_depth;
                let data = self.eval_expr_runtime_with_cache(&wp.data, &mut *cache).mask(wp.memory_width);
                writes.push((wp.memory_idx, addr, wp.memory_width, data));
            }
        }

        for (memory_idx, addr, width, value) in writes {
            self.store_memory_runtime_value(memory_idx, width, addr, value);
        }
    }

    fn apply_sync_read_ports_level(&mut self) {
        if self.sync_read_ports.is_empty() {
            return;
        }

        let mut updates: Vec<(usize, RuntimeValue)> = Vec::new();
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for rp in &self.sync_read_ports {
                if self.signal_runtime_value(rp.clock_idx, self.widths.get(rp.clock_idx).copied().unwrap_or(0)).is_zero() {
                    continue;
                }
                if let Some(enable) = &rp.enable {
                    if (self.eval_expr_runtime_with_cache(enable, &mut *cache).low_u128() & 1) == 0 {
                        continue;
                    }
                }

                let Some(mem) = self.wide_memory_arrays.get(rp.memory_idx) else {
                    continue;
                };
                if mem.is_empty() {
                    continue;
                }

                let addr = (self.eval_expr_runtime_with_cache(&rp.addr, &mut *cache).low_u128() as usize) % mem.len();
                let data = self.memory_runtime_value(rp.memory_idx, rp.memory_width, addr).resize(rp.data_width);
                updates.push((rp.data_idx, data));
            }
        }

        for (idx, value) in updates {
            if idx < self.wide_signals.len() {
                let width = self.widths.get(idx).copied().unwrap_or(0);
                self.store_signal_runtime_value(idx, width, value);
            }
        }
    }

    pub fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        self.poke_wide(name, value as SimValue)
    }

    pub fn poke_wide(&mut self, name: &str, value: SimValue) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let width = self.widths.get(idx).copied().unwrap_or(0);
        self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(value, width));
        Ok(())
    }

    pub fn poke_word_by_name(&mut self, name: &str, word_idx: usize, value: u64) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        self.poke_word_by_idx(idx, word_idx, value);
        Ok(())
    }

    pub fn peek(&self, name: &str) -> Result<u64, String> {
        Ok(Self::low_word(self.peek_wide(name)?))
    }

    pub fn peek_wide(&self, name: &str) -> Result<SimValue, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let width = self.widths.get(idx).copied().unwrap_or(0);
        Ok(self.signal_runtime_value(idx, width).low_u128())
    }

    pub fn peek_word_by_name(&self, name: &str, word_idx: usize) -> Result<u64, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        Ok(self.peek_word_by_idx(idx, word_idx))
    }

    #[inline(always)]
    pub fn poke_by_idx(&mut self, idx: usize, value: u64) {
        self.poke_wide_by_idx(idx, value as SimValue);
    }

    #[inline(always)]
    pub fn poke_wide_by_idx(&mut self, idx: usize, value: SimValue) {
        if idx < self.wide_signals.len() {
            let width = self.widths.get(idx).copied().unwrap_or(0);
            self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(value, width));
        }
    }

    #[inline(always)]
    pub fn peek_by_idx(&self, idx: usize) -> u64 {
        Self::low_word(self.peek_wide_by_idx(idx))
    }

    #[inline(always)]
    pub fn peek_wide_by_idx(&self, idx: usize) -> SimValue {
        if idx < self.signals.len() {
            let width = self.widths.get(idx).copied().unwrap_or(0);
            self.signal_runtime_value(idx, width).low_u128()
        } else {
            0
        }
    }

    pub fn get_signal_idx(&self, name: &str) -> Option<usize> {
        self.name_to_idx.get(name).copied()
    }

    fn sync_wide_from_low_views(&mut self) {
        for (idx, &value) in self.signals.iter().enumerate() {
            if idx < self.wide_signals.len() && self.widths.get(idx).copied().unwrap_or(0) <= 64 {
                self.wide_signals[idx] = RuntimeValue::from_u128(value as SimValue, self.widths[idx]);
            }
        }

        for ((low_mem, wide_mem), &width) in self
            .memory_arrays
            .iter()
            .zip(self.wide_memory_arrays.iter_mut())
            .zip(self.memory_widths.iter())
        {
            for (idx, &value) in low_mem.iter().enumerate() {
                if idx < wide_mem.len() {
                    wide_mem[idx] = RuntimeValue::from_u128(value as SimValue, width);
                }
            }
        }
    }

    fn sync_low_views_from_wide(&mut self) {
        for (idx, value) in self.wide_signals.iter().enumerate() {
            if idx < self.signals.len() {
                self.signals[idx] = Self::low_word(value.low_u128());
            }
        }

        for (wide_mem, low_mem) in self.wide_memory_arrays.iter().zip(self.memory_arrays.iter_mut()) {
            for (idx, value) in wide_mem.iter().enumerate() {
                if idx < low_mem.len() {
                    low_mem[idx] = Self::low_word(value.low_u128());
                }
            }
        }
    }

    #[inline(always)]
    fn evaluate_no_clock_capture(&mut self) {
        self.sync_wide_from_low_views();
        let comb_assigns = self.comb_assigns.clone();
        let cache = self.runtime_expr_cache.get_mut() as *mut RuntimeExprEvalCache;
        unsafe {
            (*cache).next_epoch();
            for (target_idx, expr) in comb_assigns {
                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                let value = self.eval_expr_runtime_with_cache(&expr, &mut *cache);
                self.store_signal_runtime_value(target_idx, width, value);
            }
        }
    }

    #[inline(always)]
    pub fn evaluate(&mut self) {
        self.evaluate_no_clock_capture();
        self.sync_low_views_from_wide();

        // Mirror compiler semantics so direct low-phase evaluate() calls record
        // the current clock levels for the next tick() edge check.
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }
    }

    #[inline(always)]
    pub fn tick(&mut self) {
        // Use prev_clock_values captured by the previous evaluate()/tick() call
        // as the "before" side of edge detection.
        self.evaluate_no_clock_capture();
        self.sync_low_views_from_wide();
        self.apply_write_ports_level();
        self.sync_low_views_from_wide();

        // Sample ALL register input expressions ONCE
        self.sample_next_regs();

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
        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
            let clk_idx = self.seq_clocks[i];
            if rising_clocks[clk_idx] && !updated[i] {
                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                self.store_signal_runtime_value(target_idx, width, self.next_regs[i].clone());
                updated[i] = true;
            }
        }
        self.sync_low_views_from_wide();

        // Iterate for derived clocks
        for _iteration in 0..max_iterations {
            let mut clock_before: Vec<u64> = Vec::with_capacity(self.clock_indices.len());
            for &clk_idx in &self.clock_indices {
                clock_before.push(self.signals[clk_idx]);
            }

            self.evaluate_no_clock_capture();
            self.sync_low_views_from_wide();

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

            for i in 0..self.seq_targets.len() {
                let target_idx = self.seq_targets[i];
                let clk_idx = self.seq_clocks[i];
                if rising_clocks[clk_idx] && !updated[i] {
                    let width = self.widths.get(target_idx).copied().unwrap_or(0);
                    self.store_signal_runtime_value(target_idx, width, self.next_regs[i].clone());
                    updated[i] = true;
                }
            }
            self.sync_low_views_from_wide();
        }

        self.apply_sync_read_ports_level();
        self.sync_low_views_from_wide();
        self.evaluate_no_clock_capture();
        self.sync_low_views_from_wide();

        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }
    }

    /// Tick with forced edge detection using prev_clock_values
    /// This is used by extensions that manually control the clock sequence
    /// and set prev_clock_values before calling this function.
    #[inline(always)]
    pub fn tick_forced(&mut self) {
        // Use prev_clock_values as "before" values (set by caller)
        // instead of sampling from signals

        // Evaluate to propagate external input changes
        self.evaluate_no_clock_capture();
        self.sync_low_views_from_wide();
        self.apply_write_ports_level();
        self.sync_low_views_from_wide();

        // Sample ALL register input expressions ONCE
        self.sample_next_regs();

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
        for i in 0..self.seq_targets.len() {
            let target_idx = self.seq_targets[i];
            let clk_idx = self.seq_clocks[i];
            if rising_clocks[clk_idx] && !updated[i] {
                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                self.store_signal_runtime_value(target_idx, width, self.next_regs[i].clone());
                updated[i] = true;
            }
        }
        self.sync_low_views_from_wide();

        // Iterate for derived clocks
        for _iteration in 0..max_iterations {
            let mut clock_before: Vec<u64> = Vec::with_capacity(self.clock_indices.len());
            for &clk_idx in &self.clock_indices {
                clock_before.push(self.signals[clk_idx]);
            }

            self.evaluate_no_clock_capture();
            self.sync_low_views_from_wide();

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

            for i in 0..self.seq_targets.len() {
                let target_idx = self.seq_targets[i];
                let clk_idx = self.seq_clocks[i];
                if rising_clocks[clk_idx] && !updated[i] {
                    let width = self.widths.get(target_idx).copied().unwrap_or(0);
                    self.store_signal_runtime_value(target_idx, width, self.next_regs[i].clone());
                    updated[i] = true;
                }
            }
            self.sync_low_views_from_wide();
        }

        self.apply_sync_read_ports_level();
        self.sync_low_views_from_wide();
        self.evaluate_no_clock_capture();
        self.sync_low_views_from_wide();

        // Update prev_clock_values to current values for next cycle
        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }
    }

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for (idx, val) in self.wide_signals.iter_mut().enumerate() {
            *val = RuntimeValue::zero(self.widths.get(idx).copied().unwrap_or(0));
        }
        for (idx, reset_val) in self.reset_values.clone() {
            self.wide_signals[idx] = reset_val;
        }
        for val in self.prev_clock_values.iter_mut() {
            *val = 0;
        }
        for (mem, initial) in self.memory_arrays.iter_mut().zip(self.memory_reset_arrays.iter()) {
            mem.clone_from(initial);
        }
        for (mem, initial) in self.wide_memory_arrays.iter_mut().zip(self.wide_memory_reset_arrays.iter()) {
            mem.clone_from(initial);
        }
        self.sync_low_views_from_wide();
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn counter_noncompact_payload() -> String {
        json!({
            "circt_json_version": 1,
            "modules": [{
                "name": "ir_input_format_counter",
                "ports": [
                    { "name": "clk", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "rst", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "en", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "q", "direction": "out", "width": 4, "default": serde_json::Value::Null }
                ],
                "nets": [],
                "regs": [{ "name": "q", "width": 4, "reset_value": 0 }],
                "assigns": [],
                "processes": [{
                    "name": "seq_logic",
                    "clocked": true,
                    "clock": "clk",
                    "sensitivity_list": [],
                    "statements": [{
                        "kind": "if",
                        "condition": { "kind": "signal", "name": "rst", "width": 1 },
                        "then_statements": [{
                            "kind": "seq_assign",
                            "target": "q",
                            "expr": { "kind": "literal", "value": 0, "width": 4 }
                        }],
                        "else_statements": [{
                            "kind": "seq_assign",
                            "target": "q",
                            "expr": {
                                "kind": "mux",
                                "condition": { "kind": "signal", "name": "en", "width": 1 },
                                "when_true": {
                                    "kind": "binary",
                                    "op": "+",
                                    "left": { "kind": "signal", "name": "q", "width": 4 },
                                    "right": {
                                        "kind": "resize",
                                        "expr": { "kind": "literal", "value": 1, "width": 1 },
                                        "width": 4
                                    },
                                    "width": 5
                                },
                                "when_false": { "kind": "signal", "name": "q", "width": 4 },
                                "width": 5
                            }
                        }]
                    }]
                }],
                "instances": [],
                "memories": [],
                "write_ports": [],
                "sync_read_ports": [],
                "parameters": {}
            }]
        }).to_string()
    }

    fn counter_compact_payload() -> String {
        json!({
            "circt_json_version": 1,
            "modules": [{
                "name": "ir_input_format_counter",
                "ports": [
                    { "name": "clk", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "rst", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "en", "direction": "in", "width": 1, "default": serde_json::Value::Null },
                    { "name": "q", "direction": "out", "width": 4, "default": serde_json::Value::Null }
                ],
                "nets": [],
                "regs": [{ "name": "q", "width": 4, "reset_value": 0 }],
                "assigns": [],
                "processes": [{
                    "name": "seq_logic",
                    "clocked": true,
                    "clock": "clk",
                    "sensitivity_list": [],
                    "statements": [{
                        "kind": "if",
                        "condition": { "kind": "signal", "name": "rst", "width": 1 },
                        "then_statements": [{
                            "kind": "seq_assign",
                            "target": "q",
                            "expr": { "kind": "literal", "value": 0, "width": 4 }
                        }],
                        "else_statements": [{
                            "kind": "seq_assign",
                            "target": "q",
                            "expr": { "kind": "expr_ref", "id": 0, "width": 5 }
                        }]
                    }]
                }],
                "instances": [],
                "memories": [],
                "write_ports": [],
                "sync_read_ports": [],
                "parameters": {},
                "exprs": [
                    {
                        "kind": "mux",
                        "condition": { "kind": "signal", "name": "en", "width": 1 },
                        "when_true": { "kind": "expr_ref", "id": 1, "width": 5 },
                        "when_false": { "kind": "signal", "name": "q", "width": 4 },
                        "width": 5
                    },
                    {
                        "kind": "binary",
                        "op": "+",
                        "left": { "kind": "signal", "name": "q", "width": 4 },
                        "right": { "kind": "expr_ref", "id": 2, "width": 4 },
                        "width": 5
                    },
                    {
                        "kind": "resize",
                        "expr": { "kind": "literal", "value": 1, "width": 1 },
                        "width": 4
                    }
                ]
            }]
        }).to_string()
    }

    fn drive_counter(sim: &mut CoreSimulator) -> Vec<u64> {
        let sequence = [
            (true, false),
            (false, true),
            (false, true),
            (false, false),
            (false, true),
        ];

        let mut values = Vec::new();
        for (rst, en) in sequence {
            sim.poke("rst", if rst { 1 } else { 0 }).unwrap();
            sim.poke("en", if en { 1 } else { 0 }).unwrap();
            sim.poke("clk", 0).unwrap();
            sim.evaluate();
            sim.poke("clk", 1).unwrap();
            sim.tick();
            values.push(sim.peek("q").unwrap());
        }
        values
    }

    #[test]
    fn compact_counter_payload_parses_to_expected_seq_expr() {
        let compact_payload = counter_compact_payload();
        let sim = CoreSimulator::new(&compact_payload).unwrap();
        assert_eq!(sim.seq_exprs.len(), 1);

        match &sim.seq_exprs[0] {
            ExprDef::Mux { condition, when_true, when_false, width } => {
                assert_eq!(*width, 4);
                assert!(matches!(condition.as_ref(), ExprDef::Signal { name, width: 1 } if name == "rst"));
                assert!(matches!(when_true.as_ref(), ExprDef::Literal { width: 4, .. }));
                assert!(matches!(when_false.as_ref(), ExprDef::Mux { width: 5, .. }));
            }
            other => panic!("unexpected compact seq expr: {other:?}"),
        }
    }

    #[test]
    fn compact_counter_payload_matches_noncompact_behavior() {
        let expected = vec![0, 1, 2, 2, 3];

        let noncompact_payload = counter_noncompact_payload();
        let mut noncompact = CoreSimulator::new(&noncompact_payload).unwrap();
        assert_eq!(drive_counter(&mut noncompact), expected);

        let compact_payload = counter_compact_payload();
        let mut compact = CoreSimulator::new(&compact_payload).unwrap();
        assert_eq!(drive_counter(&mut compact), expected);
    }
}
