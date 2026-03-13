//! Core interpreter simulator for IR simulation
//!
//! This is the generic simulation infrastructure without example-specific code.
//! Extension modules add specialized functionality for specific use cases.

use serde::Deserialize;
use serde_json::{Map, Value};
use std::collections::HashMap;

use crate::signal_value::{
    compute_mask as wide_mask,
    deserialize_optional_signal_value,
    deserialize_signal_values,
    deserialize_signed_signal_value,
    mask_signed_value,
    SignalValue,
    SignedSignalValue,
};
use crate::runtime_value::RuntimeValue;

const EXTENDED_RUNTIME_MAX_SIGNAL_WIDTH: usize = 256;

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
    #[allow(dead_code)]
    pub clock: Option<String>,
    pub clocked: bool,
    pub statements: Vec<SeqAssignDef>,
}

/// Memory definition
#[derive(Debug, Clone, Deserialize)]
pub struct MemoryDef {
    pub name: String,
    pub depth: usize,
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
    pub assigns: Vec<AssignDef>,
    pub processes: Vec<ProcessDef>,
    #[allow(dead_code)]
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
    let expr_pool = array_field(&module_obj, "exprs");
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
                .map(|v| process_to_normalized_value(&v, &expr_pool))
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

fn process_to_normalized_value(value: &Value, expr_pool: &[Value]) -> Result<Value, String> {
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
        Value::Array(flatten_statements(array_field(obj, "statements"), expr_pool)?),
    );
    Ok(Value::Object(out))
}

fn flatten_statements(statements: Vec<Value>, expr_pool: &[Value]) -> Result<Vec<Value>, String> {
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
                seq.insert("expr".to_string(), expr_to_normalized_value(stmt_obj.get("expr"), expr_pool)?);
                out.push(Value::Object(seq));
            }
            "if" => flatten_if(stmt_obj, &mut out, expr_pool)?,
            _ => {}
        }
    }
    Ok(out)
}

fn flatten_if(if_obj: &Map<String, Value>, out: &mut Vec<Value>, expr_pool: &[Value]) -> Result<(), String> {
    let cond = expr_to_normalized_value(if_obj.get("condition"), expr_pool)?;

    let mut then_assigns: HashMap<String, Value> = HashMap::new();
    for stmt in array_field(if_obj, "then_statements") {
        let obj = as_object(&stmt, "if.then statement")?;
        match obj.get("kind").and_then(Value::as_str).unwrap_or("") {
            "seq_assign" => {
                then_assigns.insert(
                    value_to_string(obj.get("target")),
                    expr_to_normalized_value(obj.get("expr"), expr_pool)?,
                );
            }
            "if" => flatten_if(obj, out, expr_pool)?,
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
                    expr_to_normalized_value(obj.get("expr"), expr_pool)?,
                );
            }
            "if" => flatten_if(obj, out, expr_pool)?,
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

fn expr_width(expr: Option<&Value>) -> Option<usize> {
    let obj = expr?.as_object()?;
    obj.get("width").map(|w| value_to_usize(Some(w)))
}

// ============================================================================
// Flat Operation Model - Direct Indexing, No Dispatch
// ============================================================================

/// Operand source - either a signal index or an immediate value
#[derive(Debug, Clone, Copy)]
pub enum Operand {
    Signal(usize),
    Immediate(u64),
    Temp(usize),
}

/// Flattened operation with all arguments pre-resolved
#[derive(Clone, Copy)]
pub struct FlatOp {
    pub op_type: u8,
    pub dst: usize,
    pub arg0: u64,
    pub arg1: u64,
    pub arg2: u64,
}

// Operation type constants
pub const OP_COPY_SIG: u8 = 0;
pub const OP_COPY_IMM: u8 = 1;
pub const OP_COPY_TMP: u8 = 2;
pub const OP_NOT: u8 = 3;
pub const OP_REDUCE_AND: u8 = 4;
pub const OP_REDUCE_OR: u8 = 5;
pub const OP_REDUCE_XOR: u8 = 6;
pub const OP_AND: u8 = 7;
pub const OP_OR: u8 = 8;
pub const OP_XOR: u8 = 9;
pub const OP_ADD: u8 = 10;
pub const OP_SUB: u8 = 11;
pub const OP_MUL: u8 = 12;
pub const OP_DIV: u8 = 13;
pub const OP_MOD: u8 = 14;
pub const OP_SHL: u8 = 15;
pub const OP_SHR: u8 = 16;
pub const OP_EQ: u8 = 17;
pub const OP_NE: u8 = 18;
pub const OP_LT: u8 = 19;
pub const OP_GT: u8 = 20;
pub const OP_LE: u8 = 21;
pub const OP_GE: u8 = 22;
pub const OP_MUX: u8 = 23;
pub const OP_SLICE: u8 = 24;
pub const OP_CONCAT_INIT: u8 = 25;
pub const OP_CONCAT_ACCUM: u8 = 26;
pub const OP_CONCAT_FINISH: u8 = 27;
pub const OP_RESIZE: u8 = 28;
pub const OP_COPY_TO_SIG: u8 = 29;
pub const OP_MEM_READ: u8 = 30;
pub const OP_AND_SS: u8 = 32;
pub const OP_OR_SS: u8 = 33;
pub const OP_XOR_SS: u8 = 34;
pub const OP_EQ_SS: u8 = 35;
pub const OP_MUX_SSS: u8 = 36;
pub const OP_COPY_SIG_TO_SIG: u8 = 37;
pub const OP_AND_SI: u8 = 38;
pub const OP_OR_SI: u8 = 39;
pub const OP_SLICE_S: u8 = 40;
pub const OP_NOT_S: u8 = 41;
pub const OP_STORE_NEXT_REG: u8 = 42;

// Operand type tags
const TAG_SIGNAL: u64 = 0;
const TAG_IMMEDIATE: u64 = 1 << 62;
const TAG_TEMP: u64 = 2 << 62;
const TAG_MASK: u64 = 3 << 62;
const VAL_MASK: u64 = !(3u64 << 62);

impl FlatOp {
    #[inline(always)]
    pub fn encode_operand(op: Operand) -> u64 {
        match op {
            Operand::Signal(idx) => TAG_SIGNAL | (idx as u64),
            Operand::Immediate(val) => TAG_IMMEDIATE | (val & VAL_MASK),
            Operand::Temp(idx) => TAG_TEMP | (idx as u64),
        }
    }

    #[inline(always)]
    pub fn get_operand(signals: &[SignalValue], temps: &[SignalValue], encoded: u64) -> SignalValue {
        let tag = encoded & TAG_MASK;
        let val = encoded & VAL_MASK;
        if tag == TAG_SIGNAL {
            unsafe { *signals.get_unchecked(val as usize) }
        } else if tag == TAG_IMMEDIATE {
            val as SignalValue
        } else {
            unsafe { *temps.get_unchecked(val as usize) }
        }
    }
}

/// Compiled assignment - sequence of flat ops
pub struct CompiledAssign {
    pub ops: Vec<FlatOp>,
    pub final_target: usize,
    pub fast_source: Option<(usize, u64)>,
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
// Core Interpreter Simulator
// ============================================================================

pub struct CoreSimulator {
    /// Signal values
    pub signals: Vec<SignalValue>,
    /// Temp values for intermediate computations
    pub temps: Vec<SignalValue>,
    /// Signal widths
    pub widths: Vec<usize>,
    /// Signal name to index mapping
    pub name_to_idx: HashMap<String, usize>,
    /// Input names
    pub input_names: Vec<String>,
    /// Output names
    pub output_names: Vec<String>,
    /// Compiled sequential assignments
    pub seq_assigns: Vec<CompiledAssign>,
    /// All combinational ops
    pub all_comb_ops: Vec<FlatOp>,
    /// All sequential ops
    pub all_seq_ops: Vec<FlatOp>,
    /// Fast paths for sequential assigns
    pub seq_fast_paths: Vec<Option<(usize, u64)>>,
    /// Runtime combinational assignments used for wide modules
    runtime_comb_assigns: Vec<(usize, ExprDef)>,
    /// Runtime sequential expressions used for wide modules
    seq_exprs: Vec<ExprDef>,
    /// Whether the fast 64-bit flat-op path is valid for this module
    use_flat_ops: bool,
    /// Total signal count
    signal_count: usize,
    /// Register count
    reg_count: usize,
    /// Next register values buffer
    pub next_regs: Vec<SignalValue>,
    /// High words for next register values wider than 128 bits
    wide_next_reg_words: Vec<Vec<u64>>,
    /// Sequential assignment targets
    pub seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    pub seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    pub clock_indices: Vec<usize>,
    /// Previous clock values for edge detection
    pub prev_clock_values: Vec<SignalValue>,
    /// Pre-grouped clock domain assignments
    pub clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Reset values for registers
    pub reset_values: Vec<(usize, SignalValue)>,
    /// High words for signal values wider than 128 bits
    wide_signal_words: Vec<Vec<u64>>,
    /// Memory arrays
    pub memory_arrays: Vec<Vec<SignalValue>>,
    /// High words for memory entries wider than 128 bits
    wide_memory_words: Vec<Vec<Vec<u64>>>,
    /// Memory name to index mapping
    pub memory_name_to_idx: HashMap<String, usize>,
    /// Memory write ports
    write_ports: Vec<ResolvedWritePort>,
    /// Memory synchronous read ports
    sync_read_ports: Vec<ResolvedSyncReadPort>,
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

        // Wires
        for net in &ir.nets {
            let idx = signals.len();
            signals.push(0u128);
            widths.push(net.width);
            name_to_idx.insert(net.name.clone(), idx);
        }

        // Registers
        let reg_count = ir.regs.len();
        let mut reset_values: Vec<(usize, SignalValue)> = Vec::new();
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

        let signal_count = signals.len();

        // Build memory arrays
        let (memory_arrays, mem_name_to_idx) = Self::build_memory_arrays(&ir.memories);
        let mem_depths: Vec<usize> = ir.memories.iter().map(|m| m.depth).collect();
        let mem_widths: Vec<usize> = ir.memories.iter().map(|m| m.width).collect();

        if widths.iter().any(|&width| width > EXTENDED_RUNTIME_MAX_SIGNAL_WIDTH) ||
           mem_widths.iter().any(|&width| width > EXTENDED_RUNTIME_MAX_SIGNAL_WIDTH) {
            return Err(format!(
                "IR native runtime supports signal and memory widths up to {} bits",
                EXTENDED_RUNTIME_MAX_SIGNAL_WIDTH
            ));
        }

        let use_flat_ops = widths.iter().all(|&width| width <= 64) && mem_widths.iter().all(|&width| width <= 64);

        // Topologically sort combinational assignments
        let sorted_assign_indices = Self::topological_sort_assigns(&ir.assigns, &name_to_idx);
        let runtime_comb_assigns: Vec<(usize, ExprDef)> = sorted_assign_indices
            .iter()
            .filter_map(|&assign_idx| {
                let assign = &ir.assigns[assign_idx];
                name_to_idx.get(&assign.target).copied().map(|target_idx| (target_idx, assign.expr.clone()))
            })
            .collect();

        // Compile combinational assignments in topological order
        let mut max_temps = 0usize;
        let mut all_comb_ops: Vec<FlatOp> = Vec::new();
        if use_flat_ops {
            for assign_idx in sorted_assign_indices {
                let assign = &ir.assigns[assign_idx];
                // Skip assigns with unknown targets (same as compiler behavior)
                if let Some(&target_idx) = name_to_idx.get(&assign.target) {
                    let (ops, temps_used) = Self::compile_to_flat_ops(&assign.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
                    max_temps = max_temps.max(temps_used);
                    all_comb_ops.extend(ops);
                }
            }
        }

        // Compile sequential assignments
        let mut seq_assigns = Vec::new();
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut seq_exprs = Vec::new();
        let mut clock_set = std::collections::HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| name_to_idx.get(c).copied())
                .unwrap_or_else(|| *name_to_idx.get("clk_14m").unwrap_or(&0));
            clock_set.insert(clock_idx);

            for stmt in &process.statements {
                // Skip sequential statements with unknown targets (same as compiler behavior)
                if let Some(&target_idx) = name_to_idx.get(&stmt.target) {
                    let (ops, fast_source) = if use_flat_ops {
                        let (ops, temps_used) = Self::compile_to_flat_ops(&stmt.expr, target_idx, &name_to_idx, &mem_name_to_idx, &widths);
                        max_temps = max_temps.max(temps_used);
                        (ops, Self::detect_fast_source(&stmt.expr, &name_to_idx, &widths))
                    } else {
                        (Vec::new(), None)
                    };
                    seq_assigns.push(CompiledAssign { ops, final_target: target_idx, fast_source });
                    seq_targets.push(target_idx);
                    seq_clocks.push(clock_idx);
                    seq_exprs.push(stmt.expr.clone());
                }
            }
        }

        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let prev_clock_values = vec![0u128; clock_indices.len()];

        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(clock_list_idx) = clock_indices.iter().position(|&c| c == clk_idx) {
                clock_domain_assigns[clock_list_idx].push((seq_idx, seq_targets[seq_idx]));
            }
        }

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

        // Flatten sequential ops
        let mut all_seq_ops = Vec::new();
        let mut seq_fast_paths = Vec::new();

        for (i, seq_assign) in seq_assigns.iter().enumerate() {
            if let Some((src_idx, mask)) = seq_assign.fast_source {
                seq_fast_paths.push(Some((src_idx, mask)));
            } else if seq_assign.ops.is_empty() {
                seq_fast_paths.push(None);
            } else {
                seq_fast_paths.push(None);
                let ops_len = seq_assign.ops.len();
                for op in &seq_assign.ops[..ops_len.saturating_sub(1)] {
                    all_seq_ops.push(*op);
                }

                let last_op = &seq_assign.ops[ops_len - 1];
                if last_op.op_type == OP_COPY_TO_SIG {
                    all_seq_ops.push(FlatOp {
                        op_type: OP_STORE_NEXT_REG,
                        dst: i,
                        arg0: last_op.arg0,
                        arg1: 0,
                        arg2: last_op.arg2,
                    });
                } else {
                    all_seq_ops.push(*last_op);
                    all_seq_ops.push(FlatOp {
                        op_type: OP_STORE_NEXT_REG,
                        dst: i,
                        arg0: FlatOp::encode_operand(Operand::Signal(seq_assign.final_target)),
                        arg1: 0,
                        arg2: u64::MAX,
                    });
                }
            }
        }

        let temps = vec![0u128; max_temps + 1];
        let next_regs = vec![0u128; seq_targets.len()];
        let wide_next_reg_words = seq_targets
            .iter()
            .map(|&target_idx| {
                let width = widths.get(target_idx).copied().unwrap_or(0);
                if width > 128 {
                    vec![0u64; width.div_ceil(64).saturating_sub(2)]
                } else {
                    Vec::new()
                }
            })
            .collect();
        let wide_signal_words = widths
            .iter()
            .map(|&width| {
                if width > 128 {
                    vec![0u64; width.div_ceil(64).saturating_sub(2)]
                } else {
                    Vec::new()
                }
            })
            .collect();
        let mut wide_memory_words = Vec::new();
        for mem in &ir.memories {
            let mut high_arr = Vec::new();
            for _ in 0..mem.depth {
                if mem.width > 128 {
                    high_arr.push(vec![0u64; mem.width.div_ceil(64).saturating_sub(2)]);
                } else {
                    high_arr.push(Vec::new());
                }
            }
            wide_memory_words.push(high_arr);
        }

        Ok(Self {
            signals,
            temps,
            widths,
            name_to_idx,
            input_names,
            output_names,
            seq_assigns,
            all_comb_ops,
            all_seq_ops,
            seq_fast_paths,
            runtime_comb_assigns,
            seq_exprs,
            use_flat_ops,
            signal_count,
            reg_count,
            next_regs,
            wide_next_reg_words,
            seq_targets,
            seq_clocks,
            clock_indices,
            prev_clock_values,
            clock_domain_assigns,
            reset_values,
            wide_signal_words,
            memory_arrays,
            wide_memory_words,
            memory_name_to_idx: mem_name_to_idx,
            write_ports,
            sync_read_ports,
        })
    }

    #[inline(always)]
    pub fn compute_mask(width: usize) -> SignalValue {
        wide_mask(width)
    }

    fn signal_runtime_value(&self, idx: usize, width: usize) -> RuntimeValue {
        let low = self.signals.get(idx).copied().unwrap_or(0);
        let high_words = self.wide_signal_words.get(idx).map(Vec::as_slice).unwrap_or(&[]);
        RuntimeValue::from_split_words(low, high_words, width).mask(width)
    }

    fn store_signal_runtime_value(&mut self, idx: usize, width: usize, value: RuntimeValue) {
        let masked = value.mask(width);
        self.signals[idx] = masked.low_u128() & Self::compute_mask(width.min(128));
        if width > 128 {
            self.wide_signal_words[idx] = masked.high_words(width);
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
        let low = self.next_regs.get(idx).copied().unwrap_or(0);
        let high_words = self.wide_next_reg_words.get(idx).map(Vec::as_slice).unwrap_or(&[]);
        RuntimeValue::from_split_words(low, high_words, width).mask(width)
    }

    fn memory_runtime_value(&self, memory_idx: usize, width: usize, addr: usize) -> RuntimeValue {
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
    }

    fn runtime_expr_width(expr: &ExprDef, widths: &[usize], name_to_idx: &HashMap<String, usize>) -> usize {
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

    fn eval_expr_runtime(&self, expr: &ExprDef) -> RuntimeValue {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                self.signal_runtime_value(idx, *width)
            }
            ExprDef::Literal { value, width } => RuntimeValue::from_signed_i128(*value, *width),
            ExprDef::UnaryOp { op, operand, width } => {
                let src = self.eval_expr_runtime(operand);
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
                let l = self.eval_expr_runtime(left);
                let r = self.eval_expr_runtime(right);
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
                let cond = self.eval_expr_runtime(condition);
                let selected = if cond.is_zero() {
                    self.eval_expr_runtime(when_false)
                } else {
                    self.eval_expr_runtime(when_true)
                };
                selected.mask(*width)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_val = self.eval_expr_runtime(base);
                base_val.slice(*low, *width)
            }
            ExprDef::Concat { parts, width } => {
                let mut result = RuntimeValue::zero(*width);
                for part in parts {
                    let part_width = Self::runtime_expr_width(part, &self.widths, &self.name_to_idx);
                    let value = self.eval_expr_runtime(part);
                    result = result.shl(part_width, *width);
                    result = result.bitor(&value.mask(part_width), *width);
                }
                result.mask(*width)
            }
            ExprDef::Resize { expr, width } => self.eval_expr_runtime(expr).resize(*width),
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
                let addr_val = self.eval_expr_runtime(addr).low_u128() as usize % mem.len();
                self.memory_runtime_value(memory_idx, *width, addr_val)
            }
        }
    }

    fn apply_write_ports_level(&mut self) {
        if self.write_ports.is_empty() {
            return;
        }

        let mut writes: Vec<(usize, usize, usize, RuntimeValue)> = Vec::new();
        for wp in &self.write_ports {
            if self.signals.get(wp.clock_idx).copied().unwrap_or(0) == 0 {
                continue;
            }
            if (self.eval_expr_runtime(&wp.enable).low_u128() & 1) == 0 {
                continue;
            }
            if wp.memory_depth == 0 {
                continue;
            }

            let addr = (self.eval_expr_runtime(&wp.addr).low_u128() as usize) % wp.memory_depth;
            let data = self.eval_expr_runtime(&wp.data).mask(wp.memory_width);
            writes.push((wp.memory_idx, addr, wp.memory_width, data));
        }

        for (memory_idx, addr, width, value) in writes {
            self.store_memory_runtime_value(memory_idx, width, addr, value);
        }
    }

    fn sample_next_regs_runtime(&mut self) {
        for idx in 0..self.seq_exprs.len() {
            let target_idx = self.seq_targets.get(idx).copied().unwrap_or(0);
            let target_width = self.widths.get(target_idx).copied().unwrap_or(0);
            let expr = self.seq_exprs[idx].clone();
            let value = self.eval_expr_runtime(&expr);
            self.store_next_reg_runtime_value(idx, target_width, value);
        }
    }

    fn apply_sync_read_ports_level(&mut self) {
        if self.sync_read_ports.is_empty() {
            return;
        }

        let mut updates: Vec<(usize, RuntimeValue)> = Vec::new();
        for rp in &self.sync_read_ports {
            if self.signals.get(rp.clock_idx).copied().unwrap_or(0) == 0 {
                continue;
            }
            if let Some(enable) = &rp.enable {
                if (self.eval_expr_runtime(enable).low_u128() & 1) == 0 {
                    continue;
                }
            }

            let Some(mem) = self.memory_arrays.get(rp.memory_idx) else {
                continue;
            };
            if mem.is_empty() {
                continue;
            }

            let addr = (self.eval_expr_runtime(&rp.addr).low_u128() as usize) % mem.len();
            let data = self.memory_runtime_value(rp.memory_idx, rp.memory_width, addr).resize(rp.data_width);
            updates.push((rp.data_idx, data));
        }

        for (idx, value) in updates {
            if idx < self.signals.len() {
                let width = self.widths.get(idx).copied().unwrap_or(0);
                self.store_signal_runtime_value(idx, width, value);
            }
        }
    }

    fn build_memory_arrays(memories: &[MemoryDef]) -> (Vec<Vec<SignalValue>>, HashMap<String, usize>) {
        let mut arrays = Vec::new();
        let mut name_to_idx = HashMap::new();
        for (idx, mem) in memories.iter().enumerate() {
            let mut data = vec![0u128; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val;
                }
            }
            arrays.push(data);
            name_to_idx.insert(mem.name.clone(), idx);
        }
        (arrays, name_to_idx)
    }

    /// Extract signal dependencies from an expression
    fn expr_dependencies(expr: &ExprDef, name_to_idx: &HashMap<String, usize>, deps: &mut std::collections::HashSet<usize>) {
        match expr {
            ExprDef::Signal { name, .. } => {
                if let Some(&idx) = name_to_idx.get(name) {
                    deps.insert(idx);
                }
            }
            ExprDef::Literal { .. } => {}
            ExprDef::UnaryOp { operand, .. } => {
                Self::expr_dependencies(operand, name_to_idx, deps);
            }
            ExprDef::BinaryOp { left, right, .. } => {
                Self::expr_dependencies(left, name_to_idx, deps);
                Self::expr_dependencies(right, name_to_idx, deps);
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                Self::expr_dependencies(condition, name_to_idx, deps);
                Self::expr_dependencies(when_true, name_to_idx, deps);
                Self::expr_dependencies(when_false, name_to_idx, deps);
            }
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    Self::expr_dependencies(part, name_to_idx, deps);
                }
            }
            ExprDef::Slice { base, .. } => {
                Self::expr_dependencies(base, name_to_idx, deps);
            }
            ExprDef::Resize { expr, .. } => {
                Self::expr_dependencies(expr, name_to_idx, deps);
            }
            ExprDef::MemRead { addr, .. } => {
                Self::expr_dependencies(addr, name_to_idx, deps);
            }
        }
    }

    /// Topologically sort assigns based on signal dependencies
    fn topological_sort_assigns(assigns: &[AssignDef], name_to_idx: &HashMap<String, usize>) -> Vec<usize> {
        let n = assigns.len();
        if n == 0 {
            return Vec::new();
        }

        // Map: target signal idx -> ALL assignment indices that write to it
        let mut target_to_assigns: HashMap<usize, Vec<usize>> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = name_to_idx.get(&assign.target) {
                target_to_assigns.entry(idx).or_insert_with(Vec::new).push(i);
            }
        }

        // Compute dependencies for each assignment
        let mut assign_deps: Vec<std::collections::HashSet<usize>> = Vec::with_capacity(n);
        for assign in assigns {
            let mut signal_deps = std::collections::HashSet::new();
            Self::expr_dependencies(&assign.expr, name_to_idx, &mut signal_deps);

            // Convert signal dependencies to assignment dependencies
            let mut deps = std::collections::HashSet::new();
            for sig_idx in signal_deps {
                if let Some(assign_indices) = target_to_assigns.get(&sig_idx) {
                    for &assign_idx in assign_indices {
                        deps.insert(assign_idx);
                    }
                }
            }
            assign_deps.push(deps);
        }

        // Topological sort using level-based approach
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

        // Flatten levels into single sorted list
        levels.into_iter().flatten().collect()
    }

    fn compile_to_flat_ops(
        expr: &ExprDef,
        final_target: usize,
        name_to_idx: &HashMap<String, usize>,
        mem_name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> (Vec<FlatOp>, usize) {
        let mut ops: Vec<FlatOp> = Vec::new();
        let mut temp_counter = 0usize;

        let result = Self::compile_expr_to_flat(expr, name_to_idx, mem_name_to_idx, widths, &mut ops, &mut temp_counter);

        let width = widths.get(final_target).copied().unwrap_or(64);
        let mask = Self::compute_mask(width) as u64;
        match result {
            Operand::Signal(idx) if idx == final_target => {}
            Operand::Signal(src_idx) => {
                ops.push(FlatOp {
                    op_type: OP_COPY_SIG_TO_SIG,
                    dst: final_target,
                    arg0: src_idx as u64,
                    arg1: 0,
                    arg2: mask,
                });
            }
            _ => {
                ops.push(FlatOp {
                    op_type: OP_COPY_TO_SIG,
                    dst: final_target,
                    arg0: FlatOp::encode_operand(result),
                    arg1: 0,
                    arg2: mask,
                });
            }
        }

        (ops, temp_counter)
    }

    fn compile_expr_to_flat(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        mem_name_to_idx: &HashMap<String, usize>,
        widths: &[usize],
        ops: &mut Vec<FlatOp>,
        temp_counter: &mut usize,
    ) -> Operand {
        match expr {
            ExprDef::Signal { name, .. } => {
                // Unknown signals evaluate to 0 (not index 0 which is reset)
                if let Some(&idx) = name_to_idx.get(name) {
                    Operand::Signal(idx)
                } else {
                    Operand::Immediate(0)
                }
            }
            ExprDef::Literal { value, width } => {
                let mask = Self::compute_mask(*width) as u64;
                Operand::Immediate(mask_signed_value(*value, *width) as u64 & mask)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let src = Self::compile_expr_to_flat(operand, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width) as u64;
                let dst = *temp_counter;
                *temp_counter += 1;

                let op_width = Self::expr_width(operand, widths, name_to_idx);
                let op_mask = Self::compute_mask(op_width) as u64;

                let op_type = match op.as_str() {
                    "~" | "not" => OP_NOT,
                    "&" | "reduce_and" => OP_REDUCE_AND,
                    "|" | "reduce_or" => OP_REDUCE_OR,
                    "^" | "reduce_xor" => OP_REDUCE_XOR,
                    _ => OP_COPY_TMP,
                };

                ops.push(FlatOp {
                    op_type,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: op_mask,
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = Self::compile_expr_to_flat(left, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let r = Self::compile_expr_to_flat(right, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width) as u64;
                let dst = *temp_counter;
                *temp_counter += 1;

                let emitted_specialized = match (&l, &r, op.as_str()) {
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "&") => {
                        ops.push(FlatOp { op_type: OP_AND_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "|") => {
                        ops.push(FlatOp { op_type: OP_OR_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    (Operand::Signal(l_idx), Operand::Signal(r_idx), "==") => {
                        ops.push(FlatOp { op_type: OP_EQ_SS, dst, arg0: *l_idx as u64, arg1: *r_idx as u64, arg2: mask });
                        true
                    }
                    _ => false,
                };

                if !emitted_specialized {
                    let op_type = match op.as_str() {
                        "&" => OP_AND,
                        "|" => OP_OR,
                        "^" => OP_XOR,
                        "+" => OP_ADD,
                        "-" => OP_SUB,
                        "*" => OP_MUL,
                        "/" => OP_DIV,
                        "%" => OP_MOD,
                        "<<" => OP_SHL,
                        ">>" => OP_SHR,
                        "==" => OP_EQ,
                        "!=" => OP_NE,
                        "<" => OP_LT,
                        ">" => OP_GT,
                        "<=" | "le" => OP_LE,
                        ">=" => OP_GE,
                        _ => OP_AND,
                    };

                    ops.push(FlatOp {
                        op_type,
                        dst,
                        arg0: FlatOp::encode_operand(l),
                        arg1: FlatOp::encode_operand(r),
                        arg2: mask,
                    });
                }
                Operand::Temp(dst)
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = Self::compile_expr_to_flat(condition, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let t = Self::compile_expr_to_flat(when_true, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let f = Self::compile_expr_to_flat(when_false, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_MUX,
                    dst,
                    arg0: FlatOp::encode_operand(cond),
                    arg1: FlatOp::encode_operand(t),
                    arg2: FlatOp::encode_operand(f),
                });

                let mask = Self::compute_mask(*width) as u64;
                let masked_dst = *temp_counter;
                *temp_counter += 1;
                ops.push(FlatOp {
                    op_type: OP_RESIZE,
                    dst: masked_dst,
                    arg0: FlatOp::encode_operand(Operand::Temp(dst)),
                    arg1: 0,
                    arg2: mask,
                });
                Operand::Temp(masked_dst)
            }
            ExprDef::Slice { base, low, width, .. } => {
                let src = Self::compile_expr_to_flat(base, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width) as u64;
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_SLICE,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: *low as u64,
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Concat { parts, width } => {
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_CONCAT_INIT,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: 0,
                });

                let mut shift_acc = 0u64;
                for part in parts.iter().rev() {
                    let src = Self::compile_expr_to_flat(part, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                    let part_width = Self::expr_width(part, widths, name_to_idx);
                    let part_mask = Self::compute_mask(part_width) as u64;

                    ops.push(FlatOp {
                        op_type: OP_CONCAT_ACCUM,
                        dst,
                        arg0: FlatOp::encode_operand(src),
                        arg1: shift_acc,
                        arg2: part_mask,
                    });
                    shift_acc += part_width as u64;
                }

                let final_mask = Self::compute_mask(*width) as u64;
                ops.push(FlatOp {
                    op_type: OP_CONCAT_FINISH,
                    dst,
                    arg0: 0,
                    arg1: 0,
                    arg2: final_mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::Resize { expr, width } => {
                let src = Self::compile_expr_to_flat(expr, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                let mask = Self::compute_mask(*width) as u64;
                let dst = *temp_counter;
                *temp_counter += 1;

                ops.push(FlatOp {
                    op_type: OP_RESIZE,
                    dst,
                    arg0: FlatOp::encode_operand(src),
                    arg1: 0,
                    arg2: mask,
                });
                Operand::Temp(dst)
            }
            ExprDef::MemRead { memory, addr, width } => {
                // Unknown memories return 0
                if let Some(&mem_idx) = mem_name_to_idx.get(memory) {
                    let addr_op = Self::compile_expr_to_flat(addr, name_to_idx, mem_name_to_idx, widths, ops, temp_counter);
                    let mask = Self::compute_mask(*width) as u64;
                    let dst = *temp_counter;
                    *temp_counter += 1;

                    ops.push(FlatOp {
                        op_type: OP_MEM_READ,
                        dst,
                        arg0: mem_idx as u64,
                        arg1: FlatOp::encode_operand(addr_op),
                        arg2: mask,
                    });
                    Operand::Temp(dst)
                } else {
                    Operand::Immediate(0)
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
            ExprDef::UnaryOp { width, .. } => *width,
            ExprDef::BinaryOp { width, .. } => *width,
            ExprDef::Mux { width, .. } => *width,
            ExprDef::Slice { width, .. } => *width,
            ExprDef::Concat { width, .. } => *width,
            ExprDef::Resize { width, .. } => *width,
            ExprDef::MemRead { width, .. } => *width,
        }
    }

    fn detect_fast_source(
        expr: &ExprDef,
        name_to_idx: &HashMap<String, usize>,
        widths: &[usize]
    ) -> Option<(usize, u64)> {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = *name_to_idx.get(name)?;
                let actual_width = widths.get(idx).copied().unwrap_or(*width);
                let mask = Self::compute_mask(actual_width) as u64;
                Some((idx, mask))
            }
            ExprDef::Resize { expr: inner, width } => {
                if let ExprDef::Signal { name, .. } = inner.as_ref() {
                    let idx = *name_to_idx.get(name)?;
                    let mask = Self::compute_mask(*width) as u64;
                    Some((idx, mask))
                } else {
                    None
                }
            }
            _ => None,
        }
    }

    pub fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        self.poke_wide(name, value as SignalValue)
    }

    pub fn poke_wide(&mut self, name: &str, value: SignalValue) -> Result<(), String> {
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
        Ok(self.peek_wide(name)? as u64)
    }

    pub fn peek_wide(&self, name: &str) -> Result<SignalValue, String> {
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
        self.poke_wide_by_idx(idx, value as SignalValue);
    }

    #[inline(always)]
    pub fn poke_wide_by_idx(&mut self, idx: usize, value: SignalValue) {
        if idx >= self.signals.len() {
            return;
        }
        let width = self.widths.get(idx).copied().unwrap_or(0);
        self.store_signal_runtime_value(idx, width, RuntimeValue::from_u128(value, width));
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
    pub fn peek_word_by_idx(&self, idx: usize, word_idx: usize) -> u64 {
        if idx >= self.signals.len() {
            return 0;
        }
        let width = self.widths.get(idx).copied().unwrap_or(0);
        self.signal_runtime_value(idx, width).word(width, word_idx)
    }

    #[inline(always)]
    pub fn peek_by_idx(&self, idx: usize) -> u64 {
        self.peek_wide_by_idx(idx) as u64
    }

    #[inline(always)]
    pub fn peek_wide_by_idx(&self, idx: usize) -> SignalValue {
        if idx >= self.signals.len() {
            return 0;
        }
        let width = self.widths.get(idx).copied().unwrap_or(0);
        self.signal_runtime_value(idx, width).low_u128()
    }

    pub fn get_signal_idx(&self, name: &str) -> Option<usize> {
        self.name_to_idx.get(name).copied()
    }

    #[inline(always)]
    fn execute_flat_op(signals: &mut [SignalValue], temps: &mut [SignalValue], memories: &[Vec<SignalValue>], op: &FlatOp) {
        match op.op_type {
            OP_COPY_TO_SIG => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_COPY_SIG | OP_COPY_IMM | OP_COPY_TMP => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_NOT => {
                let val = (!FlatOp::get_operand(signals, temps, op.arg0)) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_REDUCE_AND => {
                let val = FlatOp::get_operand(signals, temps, op.arg0);
                let mask = op.arg1 as SignalValue;
                let result = ((val & mask) == mask) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_OR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != 0) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_XOR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0).count_ones() as SignalValue) & 1;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_AND => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) | FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) ^ FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_ADD => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_add(FlatOp::get_operand(signals, temps, op.arg1)) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SUB => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_sub(FlatOp::get_operand(signals, temps, op.arg1)) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUL => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_mul(FlatOp::get_operand(signals, temps, op.arg1)) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_DIV => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) / r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MOD => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) % r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHL => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(127) as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) << shift) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHR => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(127) as u32;
                let result = FlatOp::get_operand(signals, temps, op.arg0) >> shift;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) == FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_NE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) < FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) > FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) <= FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >= FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX => {
                let c = FlatOp::get_operand(signals, temps, op.arg0);
                let t = FlatOp::get_operand(signals, temps, op.arg1);
                let f = FlatOp::get_operand(signals, temps, op.arg2);
                let select = (c != 0) as SignalValue;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SLICE => {
                let shift = op.arg1 as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >> shift) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_CONCAT_INIT => {
                unsafe { *temps.get_unchecked_mut(op.dst) = 0; }
            }
            OP_CONCAT_ACCUM => {
                let part = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                let shift = op.arg1 as usize;
                unsafe {
                    let current = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = current | (part << shift);
                }
            }
            OP_CONCAT_FINISH => {
                unsafe {
                    let val = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = val & (op.arg2 as SignalValue);
                }
            }
            OP_RESIZE => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MEM_READ => {
                let mem_idx = op.arg0 as usize;
                let addr = FlatOp::get_operand(signals, temps, op.arg1) as usize;
                let result = if mem_idx < memories.len() {
                    let mem = &memories[mem_idx];
                    if addr < mem.len() { mem[addr] } else { 0 }
                } else {
                    0
                };
                unsafe { *temps.get_unchecked_mut(op.dst) = result & (op.arg2 as SignalValue); }
            }
            // Specialized signal-signal operations (must be in execute_flat_op, not just evaluate)
            OP_AND_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) & *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) | *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) ^ *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ_SS => {
                let result = unsafe { (*signals.get_unchecked(op.arg0 as usize) == *signals.get_unchecked(op.arg1 as usize)) as SignalValue };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX_SSS => {
                let c = unsafe { *signals.get_unchecked(op.arg0 as usize) };
                let t = unsafe { *signals.get_unchecked(op.arg1 as usize) };
                let f = unsafe { *signals.get_unchecked(op.arg2 as usize) };
                let select = (c != 0) as SignalValue;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_COPY_SIG_TO_SIG => {
                let val = unsafe { *signals.get_unchecked(op.arg0 as usize) } & (op.arg2 as SignalValue);
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_AND_SI => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } & (op.arg1 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR_SI => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } | (op.arg1 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SLICE_S => {
                let result = (unsafe { *signals.get_unchecked(op.arg0 as usize) } >> op.arg1 as u32) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_NOT_S => {
                let result = (!unsafe { *signals.get_unchecked(op.arg0 as usize) }) & (op.arg2 as SignalValue);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            _ => {}
        }
    }

    #[inline(always)]
    fn evaluate_no_clock_capture(&mut self) {
        if !self.use_flat_ops {
            let runtime_comb_assigns = self.runtime_comb_assigns.clone();
            for (target_idx, expr) in runtime_comb_assigns {
                let value = self.eval_expr_runtime(&expr);
                self.store_signal_runtime_value(target_idx, self.widths[target_idx], value);
            }
            return;
        }

        let signals = &mut self.signals;
        let temps = &mut self.temps;
        let memories = &self.memory_arrays;

        for op in &self.all_comb_ops {
                match op.op_type {
                    OP_COPY_TO_SIG => {
                        let val = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                        unsafe { *signals.get_unchecked_mut(op.dst) = val; }
                    }
                OP_AND => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) & FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) | FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_MUX => {
                    let c = FlatOp::get_operand(signals, temps, op.arg0);
                    let t = FlatOp::get_operand(signals, temps, op.arg1);
                    let f = FlatOp::get_operand(signals, temps, op.arg2);
                    let select = (c != 0) as SignalValue;
                    let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_RESIZE => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_EQ => {
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) == FlatOp::get_operand(signals, temps, op.arg1)) as SignalValue;
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_NOT => {
                    let val = (!FlatOp::get_operand(signals, temps, op.arg0)) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = val; }
                }
                OP_XOR => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0) ^ FlatOp::get_operand(signals, temps, op.arg1);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SLICE => {
                    let shift = op.arg1 as u32;
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) >> shift) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SHL => {
                    let shift = FlatOp::get_operand(signals, temps, op.arg1).min(127) as u32;
                    let result = (FlatOp::get_operand(signals, temps, op.arg0) << shift) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_ADD => {
                    let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_add(FlatOp::get_operand(signals, temps, op.arg1)) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_AND_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) & *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) | *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_XOR_SS => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) ^ *signals.get_unchecked(op.arg1 as usize) };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_EQ_SS => {
                    let result = unsafe { (*signals.get_unchecked(op.arg0 as usize) == *signals.get_unchecked(op.arg1 as usize)) as SignalValue };
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_MUX_SSS => {
                    let c = unsafe { *signals.get_unchecked(op.arg0 as usize) };
                    let t = unsafe { *signals.get_unchecked(op.arg1 as usize) };
                    let f = unsafe { *signals.get_unchecked(op.arg2 as usize) };
                    let select = (c != 0) as SignalValue;
                    let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                    OP_COPY_SIG_TO_SIG => {
                        let val = unsafe { *signals.get_unchecked(op.arg0 as usize) } & (op.arg2 as SignalValue);
                        unsafe { *signals.get_unchecked_mut(op.dst) = val; }
                    }
                OP_AND_SI => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } & (op.arg1 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_OR_SI => {
                    let result = unsafe { *signals.get_unchecked(op.arg0 as usize) } | (op.arg1 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_SLICE_S => {
                    let result = (unsafe { *signals.get_unchecked(op.arg0 as usize) } >> op.arg1 as u32) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                OP_NOT_S => {
                    let result = (!unsafe { *signals.get_unchecked(op.arg0 as usize) }) & (op.arg2 as SignalValue);
                    unsafe { *temps.get_unchecked_mut(op.dst) = result; }
                }
                    _ => Self::execute_flat_op(signals, temps, memories, op),
                }
        }

    }

    #[inline(always)]
    pub fn evaluate(&mut self) {
        self.evaluate_no_clock_capture();

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
        self.apply_write_ports_level();

        if self.use_flat_ops {
            for (i, fast_path) in self.seq_fast_paths.iter().enumerate() {
                if let Some((src_idx, mask)) = fast_path {
                    let val = unsafe { *self.signals.get_unchecked(*src_idx) } & (*mask as SignalValue);
                    unsafe { *self.next_regs.get_unchecked_mut(i) = val; }
                }
            }

            for op in &self.all_seq_ops {
                match op.op_type {
                    OP_STORE_NEXT_REG => {
                        let val = FlatOp::get_operand(&self.signals, &self.temps, op.arg0) & (op.arg2 as SignalValue);
                        unsafe { *self.next_regs.get_unchecked_mut(op.dst) = val; }
                    }
                    _ => {
                        Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
                    }
                }
            }
        } else {
            self.sample_next_regs_runtime();
        }

        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for clock_list_idx in 0..self.clock_indices.len() {
                let clk_idx = self.clock_indices[clock_list_idx];
                let old_val = self.prev_clock_values[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    let clock_domain_assigns = self.clock_domain_assigns[clock_list_idx].clone();
                    for (seq_idx, target_idx) in clock_domain_assigns {
                        if self.use_flat_ops {
                            unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
                        } else {
                            let width = self.widths.get(target_idx).copied().unwrap_or(0);
                            let value = self.next_reg_runtime_value(seq_idx, width);
                            self.store_signal_runtime_value(target_idx, width, value);
                        }
                    }
                    self.prev_clock_values[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            self.evaluate_no_clock_capture();
        }

        self.apply_sync_read_ports_level();
        self.evaluate_no_clock_capture();

        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }
    }

    /// Tick with forced edge detection using prev_clock_values set by caller
    /// This skips the initial save of clock values, allowing extensions
    /// to manually control edge detection by setting prev_clock_values first.
    #[inline(always)]
    pub fn tick_forced(&mut self) {
        // Skip saving current clock values - use prev_clock_values set by caller

        // Assigns are now topologically sorted, so a single evaluate pass is sufficient
        self.evaluate_no_clock_capture();
        self.apply_write_ports_level();

        if self.use_flat_ops {
            for (i, fast_path) in self.seq_fast_paths.iter().enumerate() {
                if let Some((src_idx, mask)) = fast_path {
                    let val = unsafe { *self.signals.get_unchecked(*src_idx) } & (*mask as SignalValue);
                    unsafe { *self.next_regs.get_unchecked_mut(i) = val; }
                }
            }

            for op in self.all_seq_ops.iter() {
                match op.op_type {
                    OP_STORE_NEXT_REG => {
                        let val = FlatOp::get_operand(&self.signals, &self.temps, op.arg0) & (op.arg2 as SignalValue);
                        unsafe { *self.next_regs.get_unchecked_mut(op.dst) = val; }
                    }
                    _ => {
                        Self::execute_flat_op(&mut self.signals, &mut self.temps, &self.memory_arrays, op);
                    }
                }
            }
        } else {
            self.sample_next_regs_runtime();
        }

        // Track which registers have been updated to prevent double updates
        let num_seq = self.next_regs.len();
        let mut updated = vec![false; num_seq];

        const MAX_ITERATIONS: usize = 10;
        for _iter in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for clock_list_idx in 0..self.clock_indices.len() {
                let clk_idx = self.clock_indices[clock_list_idx];
                let old_val = self.prev_clock_values[clock_list_idx];
                let new_val = unsafe { *self.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    let clock_domain_assigns = self.clock_domain_assigns[clock_list_idx].clone();
                    for (seq_idx, target_idx) in clock_domain_assigns {
                        // Only update if not already updated (prevents double updates)
                        if !updated[seq_idx] {
                            if self.use_flat_ops {
                                unsafe { *self.signals.get_unchecked_mut(target_idx) = self.next_regs[seq_idx]; }
                            } else {
                                let width = self.widths.get(target_idx).copied().unwrap_or(0);
                                let value = self.next_reg_runtime_value(seq_idx, width);
                                self.store_signal_runtime_value(target_idx, width, value);
                            }
                            updated[seq_idx] = true;
                        }
                    }
                    // Update prev_clock_values to prevent re-triggering in this iteration
                    self.prev_clock_values[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            self.evaluate_no_clock_capture();
        }

        self.apply_sync_read_ports_level();
        self.evaluate_no_clock_capture();

        for (i, &clk_idx) in self.clock_indices.iter().enumerate() {
            self.prev_clock_values[i] = self.signals[clk_idx];
        }
    }

    pub fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for words in self.wide_signal_words.iter_mut() {
            words.fill(0);
        }
        for val in self.temps.iter_mut() {
            *val = 0;
        }
        for words in self.wide_next_reg_words.iter_mut() {
            words.fill(0);
        }
        for val in self.prev_clock_values.iter_mut() {
            *val = 0;
        }
        for idx in 0..self.reset_values.len() {
            let (signal_idx, reset_val) = self.reset_values[idx];
            let width = self.widths.get(signal_idx).copied().unwrap_or(0);
            self.store_signal_runtime_value(signal_idx, width, RuntimeValue::from_u128(reset_val, width));
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
