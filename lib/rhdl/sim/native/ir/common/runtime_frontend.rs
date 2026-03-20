use serde_json::{Map, Value};
use std::collections::{HashMap, HashSet};

#[derive(Clone, Debug)]
struct FrontendPort {
    name: String,
    direction: String,
    width: usize,
}

#[derive(Clone, Debug)]
struct FrontendNet {
    name: String,
    width: usize,
}

#[derive(Clone, Debug)]
struct FrontendReg {
    name: String,
    width: usize,
    reset_value: Option<Value>,
}

#[derive(Clone, Debug)]
struct FrontendAssign {
    target: String,
    expr: Value,
}

#[derive(Clone, Debug)]
struct FrontendSeqAssign {
    target: String,
    expr: Value,
}

#[derive(Clone, Debug)]
struct FrontendProcess {
    name: String,
    clock: Option<String>,
    clocked: bool,
    statements: Vec<FrontendSeqAssign>,
}

#[derive(Clone, Debug)]
struct FrontendMemory {
    name: String,
    depth: usize,
    width: usize,
    initial_data: Vec<Value>,
}

#[derive(Clone, Debug)]
struct FrontendWritePort {
    memory: String,
    clock: String,
    addr: Value,
    data: Value,
    enable: Value,
}

#[derive(Clone, Debug)]
struct FrontendSyncReadPort {
    memory: String,
    clock: String,
    addr: Value,
    data: String,
    enable: Option<Value>,
}

#[derive(Clone, Debug)]
struct FrontendInstanceConnection {
    port_name: String,
    direction: String,
    signal_name: String,
    expr: Option<Value>,
    width: usize,
}

#[derive(Clone, Debug)]
struct FrontendInstance {
    name: String,
    module_name: String,
    connections: Vec<FrontendInstanceConnection>,
}

#[derive(Clone, Debug)]
struct FrontendModule {
    name: String,
    ports: Vec<FrontendPort>,
    nets: Vec<FrontendNet>,
    regs: Vec<FrontendReg>,
    assigns: Vec<FrontendAssign>,
    processes: Vec<FrontendProcess>,
    instances: Vec<FrontendInstance>,
    memories: Vec<FrontendMemory>,
    write_ports: Vec<FrontendWritePort>,
    sync_read_ports: Vec<FrontendSyncReadPort>,
}

struct FlatState {
    ports: Vec<FrontendPort>,
    nets: Vec<FrontendNet>,
    net_names: HashSet<String>,
    regs: Vec<FrontendReg>,
    reg_names: HashSet<String>,
    assigns: Vec<FrontendAssign>,
    processes: Vec<FrontendProcess>,
    memories: Vec<FrontendMemory>,
    memory_names: HashSet<String>,
    write_ports: Vec<FrontendWritePort>,
    sync_read_ports: Vec<FrontendSyncReadPort>,
}

pub fn parse_normalized_module(payload: &str) -> Result<Value, String> {
    if let Ok(value) = deserialize_unbounded::<Value>(payload) {
        if is_circt_runtime_payload(&value) {
            return normalize_circt_runtime_payload(value)
                .map_err(|e| format!("Failed to parse IR input: CIRCT normalization failed: {}", e));
        }

        if payload.trim_start().starts_with('{') || payload.trim_start().starts_with('[') {
            return Err("Failed to parse IR input: expected CIRCT runtime JSON payload or supported hw/comb/seq MLIR".to_string());
        }
    }

    normalize_mlir_payload(payload)
        .map_err(|e| format!("Failed to parse IR input: MLIR normalization failed: {}", e))
}

pub fn looks_like_mlir_payload(text: &str) -> bool {
    let trimmed = text.trim_start();
    trimmed.starts_with("hw.module ")
      || trimmed.starts_with("module {")
      || trimmed.contains("hw.instance ")
      || trimmed.contains("seq.firreg ")
      || trimmed.contains("seq.compreg ")
      || trimmed.contains("comb.")
}

fn deserialize_unbounded<T>(json: &str) -> Result<T, serde_json::Error>
where
    T: for<'de> serde::Deserialize<'de>,
{
    let mut deserializer = serde_json::Deserializer::from_str(json);
    deserializer.disable_recursion_limit();
    T::deserialize(&mut deserializer)
}

pub fn normalize_mlir_payload(text: &str) -> Result<Value, String> {
    let modules = extract_hw_modules(text)?;
    if modules.is_empty() {
        return Err("No hw.module definitions found".to_string());
    }

    let parsed = modules
        .iter()
        .map(|module_text| parse_mlir_module(module_text))
        .collect::<Result<Vec<_>, _>>()?;
    let top_name = parsed
        .last()
        .map(|module| module.name.clone())
        .ok_or_else(|| "No top module found in MLIR".to_string())?;
    let flattened = flatten_modules(&parsed, &top_name)?;
    Ok(module_to_value(&flattened))
}

fn extract_hw_modules(text: &str) -> Result<Vec<String>, String> {
    let lines: Vec<&str> = text.lines().collect();
    let mut modules = Vec::new();
    let mut idx = 0usize;

    while idx < lines.len() {
        let code = code_for(lines[idx]);
        if !code.starts_with("hw.module ") {
            idx += 1;
            continue;
        }

        let start = idx;
        let mut depth = brace_delta(lines[idx]);
        idx += 1;
        while idx < lines.len() && depth > 0 {
            depth += brace_delta(lines[idx]);
            idx += 1;
        }

        if depth != 0 {
            return Err(format!("Unterminated hw.module starting at line {}", start + 1));
        }

        modules.push(lines[start..idx].join("\n"));
    }

    Ok(modules)
}

fn parse_mlir_module(module_text: &str) -> Result<FrontendModule, String> {
    let lines: Vec<&str> = module_text.lines().collect();
    let header_line = lines
        .iter()
        .map(|line| code_for(line))
        .find(|line| !line.is_empty())
        .ok_or_else(|| "Empty hw.module block".to_string())?;

    let (module_name, ports) = parse_module_header(&header_line)?;
    let output_ports: Vec<FrontendPort> = ports
        .iter()
        .filter(|port| port.direction == "out")
        .cloned()
        .collect();

    let mut module = FrontendModule {
        name: module_name.clone(),
        ports: ports.clone(),
        nets: Vec::new(),
        regs: Vec::new(),
        assigns: Vec::new(),
        processes: Vec::new(),
        instances: Vec::new(),
        memories: Vec::new(),
        write_ports: Vec::new(),
        sync_read_ports: Vec::new(),
    };

    let mut widths = ports
        .iter()
        .map(|port| (port.name.clone(), port.width))
        .collect::<HashMap<_, _>>();
    let mut clock_aliases = HashMap::<String, String>::new();
    let mut constant_values = HashMap::<String, Value>::new();
    let mut output_exprs = Vec::<Value>::new();

    for raw_line in lines.iter().skip(1) {
        let line = code_for(raw_line);
        if line.is_empty() || line == "}" {
            continue;
        }

        if line.starts_with("hw.output") {
            output_exprs = parse_hw_output(&line, &output_ports, &widths, &clock_aliases)?;
            continue;
        }

        if line.starts_with("seq.firmem.write_port ") {
            parse_memory_write_port(&line, &mut module, &widths, &clock_aliases)?;
            continue;
        }

        let (lhs_raw, rhs) = line
            .split_once('=')
            .map(|(lhs, rhs)| (lhs.trim(), rhs.trim()))
            .ok_or_else(|| format!("Unsupported MLIR operation in module {}: {}", module_name, line))?;
        let lhs_values = split_top_level(lhs_raw, ',')
            .into_iter()
            .map(|entry| normalize_value_name(&entry))
            .filter(|entry| !entry.is_empty())
            .collect::<Vec<_>>();

        if rhs.starts_with("seq.to_clock ") {
            let source = normalize_value_name(rhs.trim_start_matches("seq.to_clock ").trim());
            if let Some(lhs) = lhs_values.first() {
                clock_aliases.insert(lhs.clone(), resolve_clock_name(&source, &clock_aliases));
                widths.insert(lhs.clone(), 1);
            }
            continue;
        }

        if rhs.starts_with("hw.constant ") {
            let lhs = expect_single_lhs(&lhs_values, "hw.constant")?;
            let (value_text, ty) = split_once_required(rhs.trim_start_matches("hw.constant ").trim(), ':', "hw.constant")?;
            let width = parse_scalar_width(ty.trim())?;
            let literal = literal_expr(value_text.trim(), width);
            widths.insert(lhs.clone(), width);
            constant_values.insert(lhs.clone(), literal_value_only(value_text.trim()));
            append_net(&mut module.nets, &lhs, width);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: literal,
                },
            );
            continue;
        }

        if rhs.starts_with("comb.mux ") {
            let lhs = expect_single_lhs(&lhs_values, "comb.mux")?;
            let (args_text, ty_text) = split_once_required(rhs.trim_start_matches("comb.mux ").trim(), ':', "comb.mux")?;
            reject_aggregate_type(ty_text.trim(), "comb.mux")?;
            let width = parse_scalar_width(ty_text.trim())?;
            let args = split_top_level(args_text, ',');
            if args.len() != 3 {
                return Err(format!("Invalid comb.mux arity in module {}: {}", module_name, rhs));
            }
            append_net(&mut module.nets, &lhs, width);
            widths.insert(lhs.clone(), width);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: mux_expr(
                        operand_expr(&args[0], &widths, Some(1), &clock_aliases)?,
                        operand_expr(&args[1], &widths, Some(width), &clock_aliases)?,
                        operand_expr(&args[2], &widths, Some(width), &clock_aliases)?,
                        width,
                    ),
                },
            );
            continue;
        }

        if rhs.starts_with("comb.concat ") {
            let lhs = expect_single_lhs(&lhs_values, "comb.concat")?;
            let (parts_text, types_text) = split_once_required(rhs.trim_start_matches("comb.concat ").trim(), ':', "comb.concat")?;
            let part_types = split_top_level(types_text, ',');
            let parts = split_top_level(parts_text, ',');
            if parts.len() != part_types.len() {
                return Err(format!("comb.concat argument/type mismatch in module {}: {}", module_name, rhs));
            }
            let mut exprs = Vec::new();
            let mut width = 0usize;
            for (part, ty) in parts.iter().zip(part_types.iter()) {
                reject_aggregate_type(ty.trim(), "comb.concat")?;
                let part_width = parse_scalar_width(ty.trim())?;
                width += part_width;
                exprs.push(operand_expr(part, &widths, Some(part_width), &clock_aliases)?);
            }
            append_net(&mut module.nets, &lhs, width);
            widths.insert(lhs.clone(), width);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: concat_expr(exprs, width),
                },
            );
            continue;
        }

        if rhs.starts_with("comb.extract ") {
            let lhs = expect_single_lhs(&lhs_values, "comb.extract")?;
            let rest = rhs.trim_start_matches("comb.extract ").trim();
            let (before_colon, after_colon) = split_once_required(rest, ':', "comb.extract")?;
            let (base_text, low_text) = before_colon
                .rsplit_once(" from ")
                .ok_or_else(|| format!("Invalid comb.extract syntax in module {}: {}", module_name, rhs))?;
            let (_, result_ty) = after_colon
                .split_once("->")
                .ok_or_else(|| format!("Invalid comb.extract result type in module {}: {}", module_name, rhs))?;
            reject_aggregate_type(result_ty.trim(), "comb.extract")?;
            let width = parse_scalar_width(result_ty.trim())?;
            let low = low_text
                .trim()
                .parse::<usize>()
                .map_err(|e| format!("Invalid comb.extract offset {}: {}", low_text.trim(), e))?;
            append_net(&mut module.nets, &lhs, width);
            widths.insert(lhs.clone(), width);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: slice_expr(
                        operand_expr(base_text, &widths, None, &clock_aliases)?,
                        low,
                        width,
                    ),
                },
            );
            continue;
        }

        if rhs.starts_with("comb.icmp ") {
            let lhs = expect_single_lhs(&lhs_values, "comb.icmp")?;
            let rest = rhs.trim_start_matches("comb.icmp ").trim();
            let (pred_and_args, ty_text) = split_once_required(rest, ':', "comb.icmp")?;
            reject_aggregate_type(ty_text.trim(), "comb.icmp")?;
            let mut pred_split = pred_and_args.splitn(2, char::is_whitespace);
            let pred = pred_split.next().unwrap_or("").trim();
            let args_text = pred_split.next().unwrap_or("").trim();
            let args = split_top_level(args_text, ',');
            if args.len() != 2 {
                return Err(format!("Invalid comb.icmp arity in module {}: {}", module_name, rhs));
            }
            append_net(&mut module.nets, &lhs, 1);
            widths.insert(lhs.clone(), 1);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: binary_expr(
                        icmp_predicate_to_op(pred)?,
                        operand_expr(&args[0], &widths, None, &clock_aliases)?,
                        operand_expr(&args[1], &widths, None, &clock_aliases)?,
                        1,
                    ),
                },
            );
            continue;
        }

        if rhs.starts_with("comb.") {
            let lhs = expect_single_lhs(&lhs_values, "comb")?;
            let without_prefix = rhs.trim_start_matches("comb.");
            let mut op_split = without_prefix.splitn(2, char::is_whitespace);
            let mlir_op = op_split.next().unwrap_or("").trim();
            let rest = op_split.next().unwrap_or("").trim();
            let (args_text, ty_text) = split_once_required(rest, ':', mlir_op)?;
            reject_aggregate_type(ty_text.trim(), mlir_op)?;
            let width = parse_scalar_width(ty_text.trim())?;
            let args = split_top_level(args_text, ',');
            if args.len() != 2 {
                return Err(format!("Invalid comb op arity for {} in module {}: {}", mlir_op, module_name, rhs));
            }
            append_net(&mut module.nets, &lhs, width);
            widths.insert(lhs.clone(), width);
            append_assign(
                &mut module.assigns,
                FrontendAssign {
                    target: lhs,
                    expr: binary_expr(
                        comb_binary_op_to_runtime_op(mlir_op)?,
                        operand_expr(&args[0], &widths, None, &clock_aliases)?,
                        operand_expr(&args[1], &widths, None, &clock_aliases)?,
                        width,
                    ),
                },
            );
            continue;
        }

        if rhs.starts_with("seq.firreg ") {
            let lhs = expect_single_lhs(&lhs_values, "seq.firreg")?;
            parse_seq_firreg(
                &lhs,
                rhs,
                &mut module,
                &mut widths,
                &clock_aliases,
                &constant_values,
            )?;
            continue;
        }

        if rhs.starts_with("seq.compreg ") {
            let lhs = expect_single_lhs(&lhs_values, "seq.compreg")?;
            parse_seq_compreg(
                &lhs,
                rhs,
                &mut module,
                &mut widths,
                &clock_aliases,
                &constant_values,
            )?;
            continue;
        }

        if rhs.starts_with("seq.firmem ") {
            let lhs = expect_single_lhs(&lhs_values, "seq.firmem")?;
            parse_memory_decl(&lhs, rhs, &mut module)?;
            continue;
        }

        if rhs.starts_with("seq.firmem.read_port ") {
            let lhs = expect_single_lhs(&lhs_values, "seq.firmem.read_port")?;
            parse_memory_read_port(&lhs, rhs, &mut module, &mut widths, &clock_aliases)?;
            continue;
        }

        if rhs.starts_with("hw.instance ") {
            parse_hw_instance(
                &lhs_values,
                rhs,
                &mut module,
                &mut widths,
                &clock_aliases,
            )?;
            continue;
        }

        if rhs.starts_with("hw.array_")
            || rhs.starts_with("hw.aggregate_constant ")
            || rhs.starts_with("hw.bitcast ")
        {
            return Err(format!("Unsupported MLIR operation for native runtime frontend: {}", rhs));
        }

        return Err(format!("Unsupported MLIR operation for native runtime frontend: {}", rhs));
    }

    if output_exprs.len() != output_ports.len() {
        return Err(format!(
            "hw.output arity mismatch in module {}: expected {} values, got {}",
            module_name,
            output_ports.len(),
            output_exprs.len()
        ));
    }

    for (port, expr) in output_ports.iter().zip(output_exprs.into_iter()) {
        module.assigns.push(FrontendAssign {
            target: port.name.clone(),
            expr,
        });
    }

    Ok(module)
}

fn parse_module_header(header: &str) -> Result<(String, Vec<FrontendPort>), String> {
    let trimmed = header.trim();
    let after_prefix = trimmed
        .strip_prefix("hw.module ")
        .ok_or_else(|| format!("Invalid hw.module header: {}", trimmed))?;
    let after_name_prefix = after_prefix
        .strip_prefix('@')
        .ok_or_else(|| format!("Invalid hw.module name in header: {}", trimmed))?;
    let open_paren = after_name_prefix
        .find('(')
        .ok_or_else(|| format!("Missing port list in hw.module header: {}", trimmed))?;
    let name_and_params = after_name_prefix[..open_paren].trim();
    let module_name = name_and_params
        .split('<')
        .next()
        .unwrap_or("")
        .trim()
        .to_string();
    if module_name.is_empty() {
        return Err(format!("Missing module name in header: {}", trimmed));
    }

    let close_paren = matching_delimiter(after_name_prefix, open_paren, '(', ')')
        .ok_or_else(|| format!("Unterminated port list in hw.module header: {}", trimmed))?;
    let ports_text = &after_name_prefix[open_paren + 1..close_paren];

    let ports = split_top_level(ports_text, ',')
        .into_iter()
        .filter(|entry| !entry.trim().is_empty())
        .map(|entry| parse_port_entry(&entry))
        .collect::<Result<Vec<_>, _>>()?;

    Ok((module_name, ports))
}

fn parse_port_entry(entry: &str) -> Result<FrontendPort, String> {
    let trimmed = entry.trim();
    let (direction, rest) = trimmed
        .split_once(' ')
        .ok_or_else(|| format!("Invalid port entry: {}", trimmed))?;
    let (name_text, type_text) = split_once_required(rest.trim(), ':', "port")?;
    reject_aggregate_type(type_text.trim(), "port")?;
    Ok(FrontendPort {
        name: normalize_value_name(name_text),
        direction: direction.trim().to_string(),
        width: parse_scalar_width(type_text.trim())?,
    })
}

fn parse_hw_output(
    line: &str,
    output_ports: &[FrontendPort],
    widths: &HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
) -> Result<Vec<Value>, String> {
    let rest = line.trim_start_matches("hw.output").trim();
    if rest.is_empty() {
        return Ok(Vec::new());
    }
    let (values_text, _) = split_once_required(rest, ':', "hw.output")?;
    split_top_level(values_text, ',')
        .into_iter()
        .enumerate()
        .map(|(idx, token)| {
            let width_hint = output_ports.get(idx).map(|port| port.width).or(Some(1));
            operand_expr(&token, widths, width_hint, clock_aliases)
        })
        .collect()
}

fn parse_seq_firreg(
    lhs: &str,
    rhs: &str,
    module: &mut FrontendModule,
    widths: &mut HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
    constant_values: &HashMap<String, Value>,
) -> Result<(), String> {
    let rest = rhs.trim_start_matches("seq.firreg ").trim();
    let (before_type, type_text) = split_once_required(rest, ':', "seq.firreg")?;
    reject_aggregate_type(type_text.trim(), "seq.firreg")?;
    let width = parse_scalar_width(type_text.trim())?;
    let (input_text, after_clock) = before_type
        .split_once(" clock ")
        .ok_or_else(|| format!("Invalid seq.firreg syntax: {}", rhs))?;
    let (clock_text, reset_value) = if let Some((clock_part, reset_part)) = after_clock.split_once(" reset async ") {
        let (_, value_text) = split_once_required(reset_part, ',', "seq.firreg reset")?;
        let reset_name = normalize_value_name(value_text.trim());
        (
            clock_part.trim(),
            constant_values.get(&reset_name).cloned(),
        )
    } else {
        (after_clock.trim(), None)
    };

    widths.insert(lhs.to_string(), width);
    append_reg(&mut module.regs, lhs, width, reset_value.clone());
    module.processes.push(FrontendProcess {
        name: format!("seq__{}", lhs),
        clock: Some(resolve_clock_name(&normalize_value_name(clock_text), clock_aliases)),
        clocked: true,
        statements: vec![FrontendSeqAssign {
            target: lhs.to_string(),
            expr: operand_expr(input_text, widths, Some(width), clock_aliases)?,
        }],
    });
    Ok(())
}

fn parse_seq_compreg(
    lhs: &str,
    rhs: &str,
    module: &mut FrontendModule,
    widths: &mut HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
    constant_values: &HashMap<String, Value>,
) -> Result<(), String> {
    let rest = rhs.trim_start_matches("seq.compreg ").trim();
    let (before_type, type_text) = split_once_required(rest, ':', "seq.compreg")?;
    reject_aggregate_type(type_text.trim(), "seq.compreg")?;
    let width = parse_scalar_width(type_text.trim())?;

    let (data_text, after_data) = split_once_required(before_type, ',', "seq.compreg")?;
    let (clock_text, reset_value) = if let Some((clock_part, reset_part)) = after_data.trim().split_once(" reset ") {
        let (_, value_text) = split_once_required(reset_part, ',', "seq.compreg reset")?;
        let reset_name = normalize_value_name(value_text.trim());
        (
            clock_part.trim(),
            constant_values.get(&reset_name).cloned(),
        )
    } else {
        (after_data.trim(), None)
    };

    widths.insert(lhs.to_string(), width);
    append_reg(&mut module.regs, lhs, width, reset_value.clone());
    module.processes.push(FrontendProcess {
        name: format!("seq__{}", lhs),
        clock: Some(resolve_clock_name(&normalize_value_name(clock_text), clock_aliases)),
        clocked: true,
        statements: vec![FrontendSeqAssign {
            target: lhs.to_string(),
            expr: operand_expr(data_text, widths, Some(width), clock_aliases)?,
        }],
    });
    Ok(())
}

fn parse_memory_decl(lhs: &str, rhs: &str, module: &mut FrontendModule) -> Result<(), String> {
    let rest = rhs.trim_start_matches("seq.firmem ").trim();
    let (_, type_text) = split_once_required(rest, ':', "seq.firmem")?;
    let (depth, width) = parse_firmem_type(type_text.trim())?;
    module.memories.push(FrontendMemory {
        name: lhs.to_string(),
        depth,
        width,
        initial_data: Vec::new(),
    });
    Ok(())
}

fn parse_memory_write_port(
    line: &str,
    module: &mut FrontendModule,
    widths: &HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
) -> Result<(), String> {
    let rest = line.trim_start_matches("seq.firmem.write_port ").trim();
    let (before_type, _) = split_once_required(rest, ':', "seq.firmem.write_port")?;
    let (target_text, rhs_text) = split_once_required(before_type, '=', "seq.firmem.write_port")?;
    let (memory_name, addr_text) = parse_memory_access_target(target_text.trim())?;
    let (data_text, clock_and_enable) = rhs_text
        .split_once(", clock ")
        .ok_or_else(|| format!("Invalid seq.firmem.write_port syntax: {}", line))?;
    let (clock_text, enable_text) = clock_and_enable
        .split_once(" enable ")
        .ok_or_else(|| format!("Missing seq.firmem.write_port enable clause: {}", line))?;

    let memory = module
        .memories
        .iter()
        .find(|memory| memory.name == memory_name)
        .ok_or_else(|| format!("Unknown memory {} referenced by write port", memory_name))?;

    module.write_ports.push(FrontendWritePort {
        memory: memory_name,
        clock: resolve_clock_name(&normalize_value_name(clock_text.trim()), clock_aliases),
        addr: operand_expr(&addr_text, widths, Some(memory_addr_width(memory.depth)), clock_aliases)?,
        data: operand_expr(data_text, widths, Some(memory.width), clock_aliases)?,
        enable: operand_expr(enable_text, widths, Some(1), clock_aliases)?,
    });
    Ok(())
}

fn parse_memory_read_port(
    lhs: &str,
    rhs: &str,
    module: &mut FrontendModule,
    widths: &mut HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
) -> Result<(), String> {
    let rest = rhs.trim_start_matches("seq.firmem.read_port ").trim();
    let (before_type, _) = split_once_required(rest, ':', "seq.firmem.read_port")?;
    let (target_text, clock_text) = before_type
        .split_once(", clock ")
        .ok_or_else(|| format!("Invalid seq.firmem.read_port syntax: {}", rhs))?;
    let (memory_name, addr_text) = parse_memory_access_target(target_text.trim())?;
    let memory = module
        .memories
        .iter()
        .find(|memory| memory.name == memory_name)
        .ok_or_else(|| format!("Unknown memory {} referenced by read port", memory_name))?;

    append_net(&mut module.nets, lhs, memory.width);
    widths.insert(lhs.to_string(), memory.width);
    module.sync_read_ports.push(FrontendSyncReadPort {
        memory: memory_name,
        clock: resolve_clock_name(&normalize_value_name(clock_text.trim()), clock_aliases),
        addr: operand_expr(&addr_text, widths, Some(memory_addr_width(memory.depth)), clock_aliases)?,
        data: lhs.to_string(),
        enable: None,
    });
    Ok(())
}

fn parse_hw_instance(
    lhs_values: &[String],
    rhs: &str,
    module: &mut FrontendModule,
    widths: &mut HashMap<String, usize>,
    clock_aliases: &HashMap<String, String>,
) -> Result<(), String> {
    let rest = rhs.trim_start_matches("hw.instance ").trim();
    let (instance_name, after_name) = parse_quoted_string(rest)?;
    let after_name = after_name.trim();
    let at_pos = after_name
        .find('@')
        .ok_or_else(|| format!("Missing instance target in {}", rhs))?;
    let after_at = &after_name[at_pos + 1..];
    let open_paren = after_at
        .find('(')
        .ok_or_else(|| format!("Missing instance inputs in {}", rhs))?;
    let module_and_params = after_at[..open_paren].trim();
    let module_name = module_and_params
        .split('<')
        .next()
        .unwrap_or("")
        .trim()
        .to_string();
    if module_name.is_empty() {
        return Err(format!("Missing instance module name in {}", rhs));
    }

    let input_close = matching_delimiter(after_at, open_paren, '(', ')')
        .ok_or_else(|| format!("Unterminated instance input list in {}", rhs))?;
    let inputs_text = &after_at[open_paren + 1..input_close];
    let after_inputs = after_at[input_close + 1..].trim();
    let outputs_open = after_inputs
        .find('(')
        .ok_or_else(|| format!("Missing instance outputs in {}", rhs))?;
    let outputs_close = matching_delimiter(after_inputs, outputs_open, '(', ')')
        .ok_or_else(|| format!("Unterminated instance output list in {}", rhs))?;
    let outputs_text = &after_inputs[outputs_open + 1..outputs_close];

    let mut connections = Vec::new();

    for input in split_top_level(inputs_text, ',') {
        if input.trim().is_empty() {
            continue;
        }
        let (first_colon, last_colon) = first_and_last_colon(&input)
            .ok_or_else(|| format!("Invalid instance input entry {}", input))?;
        let port_name = input[..first_colon].trim().to_string();
        let value_text = input[first_colon + 1..last_colon].trim();
        let type_text = input[last_colon + 1..].trim();
        reject_aggregate_type(type_text, "hw.instance input")?;
        let width = parse_scalar_width(type_text)?;
        connections.push(FrontendInstanceConnection {
            port_name,
            direction: "in".to_string(),
            signal_name: String::new(),
            expr: Some(operand_expr(value_text, widths, Some(width), clock_aliases)?),
            width,
        });
    }

    let outputs = split_top_level(outputs_text, ',');
    if !lhs_values.is_empty() && lhs_values.len() != outputs.len() {
        return Err(format!(
            "Instance output/result count mismatch for {}: {} outputs, {} values",
            instance_name,
            outputs.len(),
            lhs_values.len()
        ));
    }

    for (idx, output) in outputs.into_iter().enumerate() {
        if output.trim().is_empty() {
            continue;
        }
        let (port_name, type_text) = split_once_required(output.trim(), ':', "hw.instance output")?;
        reject_aggregate_type(type_text.trim(), "hw.instance output")?;
        let width = parse_scalar_width(type_text.trim())?;
        let signal_name = lhs_values
            .get(idx)
            .cloned()
            .unwrap_or_else(|| format!("{}_{}", instance_name, port_name.trim()));
        append_net(&mut module.nets, &signal_name, width);
        widths.insert(signal_name.clone(), width);
        connections.push(FrontendInstanceConnection {
            port_name: port_name.trim().to_string(),
            direction: "out".to_string(),
            signal_name,
            expr: None,
            width,
        });
    }

    module.instances.push(FrontendInstance {
        name: instance_name,
        module_name,
        connections,
    });
    Ok(())
}

fn flatten_modules(modules: &[FrontendModule], top_name: &str) -> Result<FrontendModule, String> {
    let module_index = modules
        .iter()
        .cloned()
        .map(|module| (module.name.clone(), module))
        .collect::<HashMap<_, _>>();
    let top_module = module_index
        .get(top_name)
        .cloned()
        .ok_or_else(|| format!("Top module '{}' not found in MLIR package", top_name))?;

    let mut state = FlatState {
        ports: top_module.ports.clone(),
        nets: Vec::new(),
        net_names: HashSet::new(),
        regs: Vec::new(),
        reg_names: HashSet::new(),
        assigns: Vec::new(),
        processes: Vec::new(),
        memories: Vec::new(),
        memory_names: HashSet::new(),
        write_ports: Vec::new(),
        sync_read_ports: Vec::new(),
    };

    flatten_into(&top_module, "", &module_index, &mut state)?;

    Ok(FrontendModule {
        name: top_module.name,
        ports: state.ports,
        nets: state.nets,
        regs: state.regs,
        assigns: state.assigns,
        processes: state.processes,
        instances: Vec::new(),
        memories: state.memories,
        write_ports: state.write_ports,
        sync_read_ports: state.sync_read_ports,
    })
}

fn flatten_into(
    module: &FrontendModule,
    prefix: &str,
    module_index: &HashMap<String, FrontendModule>,
    state: &mut FlatState,
) -> Result<(), String> {
    for net in &module.nets {
        append_flat_net(state, prefix_net(net, prefix));
    }
    for reg in &module.regs {
        append_flat_reg(state, prefix_reg(reg, prefix));
    }
    for assign in &module.assigns {
        append_flat_assign(state, prefix_assign(assign, prefix));
    }
    for process in &module.processes {
        state.processes.push(prefix_process(process, prefix));
    }
    for memory in &module.memories {
        append_flat_memory(state, prefix_memory(memory, prefix));
    }
    for write_port in &module.write_ports {
        state.write_ports.push(prefix_write_port(write_port, prefix));
    }
    for read_port in &module.sync_read_ports {
        state.sync_read_ports.push(prefix_sync_read_port(read_port, prefix));
    }

    if !prefix.is_empty() {
        for port in module.ports.iter().filter(|port| port.direction == "out") {
            ensure_net_present(state, &format!("{}__{}", prefix, port.name), port.width);
        }
    }

    let child_ports_by_module = module_index
        .iter()
        .map(|(name, module)| {
            (
                name.clone(),
                module
                    .ports
                    .iter()
                    .cloned()
                    .map(|port| (port.name.clone(), port))
                    .collect::<HashMap<_, _>>(),
            )
        })
        .collect::<HashMap<_, _>>();

    for instance in &module.instances {
        let child = module_index
            .get(&instance.module_name)
            .cloned()
            .ok_or_else(|| format!("Missing MLIR module definition for instance target '{}'", instance.module_name))?;
        let inst_prefix = if prefix.is_empty() {
            instance.name.clone()
        } else {
            format!("{}__{}", prefix, instance.name)
        };

        flatten_into(&child, &inst_prefix, module_index, state)?;

        let child_ports = child_ports_by_module
            .get(&child.name)
            .ok_or_else(|| format!("Missing port metadata for child module {}", child.name))?;
        let mut connected_ports = HashSet::<String>::new();

        for connection in &instance.connections {
            connected_ports.insert(connection.port_name.clone());
            let port_width = child_ports
                .get(&connection.port_name)
                .map(|port| port.width)
                .unwrap_or(connection.width);
            let child_signal = format!("{}__{}", inst_prefix, connection.port_name);

            if connection.direction == "out" {
                let parent_target = prefixed_target_name(&connection.signal_name, prefix);
                if let Some(target) = parent_target {
                    append_flat_assign(
                        state,
                        FrontendAssign {
                            target,
                            expr: signal_expr(&child_signal, port_width),
                        },
                    );
                }
            } else if let Some(expr) = &connection.expr {
                append_flat_assign(
                    state,
                    FrontendAssign {
                        target: child_signal.clone(),
                        expr: prefix_expr(expr, prefix),
                    },
                );
            }

            ensure_net_present(state, &child_signal, port_width);
        }
    }

    Ok(())
}

fn prefix_net(net: &FrontendNet, prefix: &str) -> FrontendNet {
    if prefix.is_empty() {
        return net.clone();
    }

    FrontendNet {
        name: format!("{}__{}", prefix, net.name),
        width: net.width,
    }
}

fn prefix_reg(reg: &FrontendReg, prefix: &str) -> FrontendReg {
    if prefix.is_empty() {
        return reg.clone();
    }

    FrontendReg {
        name: format!("{}__{}", prefix, reg.name),
        width: reg.width,
        reset_value: reg.reset_value.clone(),
    }
}

fn prefix_assign(assign: &FrontendAssign, prefix: &str) -> FrontendAssign {
    if prefix.is_empty() {
        return assign.clone();
    }

    FrontendAssign {
        target: format!("{}__{}", prefix, assign.target),
        expr: prefix_expr(&assign.expr, prefix),
    }
}

fn prefix_process(process: &FrontendProcess, prefix: &str) -> FrontendProcess {
    if prefix.is_empty() {
        return process.clone();
    }

    FrontendProcess {
        name: format!("{}__{}", prefix, process.name),
        clock: process
            .clock
            .as_ref()
            .map(|clock| format!("{}__{}", prefix, clock)),
        clocked: process.clocked,
        statements: process
            .statements
            .iter()
            .map(|statement| FrontendSeqAssign {
                target: format!("{}__{}", prefix, statement.target),
                expr: prefix_expr(&statement.expr, prefix),
            })
            .collect(),
    }
}

fn prefix_memory(memory: &FrontendMemory, prefix: &str) -> FrontendMemory {
    if prefix.is_empty() {
        return memory.clone();
    }

    FrontendMemory {
        name: format!("{}__{}", prefix, memory.name),
        depth: memory.depth,
        width: memory.width,
        initial_data: memory.initial_data.clone(),
    }
}

fn prefix_write_port(port: &FrontendWritePort, prefix: &str) -> FrontendWritePort {
    if prefix.is_empty() {
        return port.clone();
    }

    FrontendWritePort {
        memory: format!("{}__{}", prefix, port.memory),
        clock: format!("{}__{}", prefix, port.clock),
        addr: prefix_expr(&port.addr, prefix),
        data: prefix_expr(&port.data, prefix),
        enable: prefix_expr(&port.enable, prefix),
    }
}

fn prefix_sync_read_port(port: &FrontendSyncReadPort, prefix: &str) -> FrontendSyncReadPort {
    if prefix.is_empty() {
        return port.clone();
    }

    FrontendSyncReadPort {
        memory: format!("{}__{}", prefix, port.memory),
        clock: format!("{}__{}", prefix, port.clock),
        addr: prefix_expr(&port.addr, prefix),
        data: format!("{}__{}", prefix, port.data),
        enable: port.enable.as_ref().map(|enable| prefix_expr(enable, prefix)),
    }
}

fn prefixed_target_name(signal_name: &str, prefix: &str) -> Option<String> {
    if signal_name.is_empty() {
        return None;
    }
    Some(if prefix.is_empty() {
        signal_name.to_string()
    } else {
        format!("{}__{}", prefix, signal_name)
    })
}

fn append_flat_net(state: &mut FlatState, net: FrontendNet) {
    if state.net_names.insert(net.name.clone()) {
        state.nets.push(net);
    }
}

fn append_flat_reg(state: &mut FlatState, reg: FrontendReg) {
    if state.reg_names.insert(reg.name.clone()) {
        state.regs.push(reg);
    }
}

fn append_flat_memory(state: &mut FlatState, memory: FrontendMemory) {
    if state.memory_names.insert(memory.name.clone()) {
        state.memories.push(memory);
    }
}

fn append_flat_assign(state: &mut FlatState, assign: FrontendAssign) {
    append_assign(&mut state.assigns, assign);
}

fn ensure_net_present(state: &mut FlatState, name: &str, width: usize) {
    if state.net_names.contains(name) || state.reg_names.contains(name) {
        return;
    }
    state.net_names.insert(name.to_string());
    state.nets.push(FrontendNet {
        name: name.to_string(),
        width,
    });
}

fn prefix_expr(expr: &Value, prefix: &str) -> Value {
    if prefix.is_empty() {
        return expr.clone();
    }

    let Some(obj) = expr.as_object() else {
        return expr.clone();
    };

    match obj.get("kind").and_then(Value::as_str).unwrap_or("") {
        "signal" => signal_expr(&format!("{}__{}", prefix, value_to_string(obj.get("name"))), value_to_usize(obj.get("width"))),
        "literal" => expr.clone(),
        "unary" => unary_expr(
            &value_to_string(obj.get("op")),
            prefix_expr(obj.get("operand").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("width")),
        ),
        "binary" => binary_expr(
            &value_to_string(obj.get("op")),
            prefix_expr(obj.get("left").unwrap_or(&Value::Null), prefix),
            prefix_expr(obj.get("right").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("width")),
        ),
        "mux" => mux_expr(
            prefix_expr(obj.get("condition").unwrap_or(&Value::Null), prefix),
            prefix_expr(obj.get("when_true").unwrap_or(&Value::Null), prefix),
            prefix_expr(obj.get("when_false").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("width")),
        ),
        "slice" => slice_expr(
            prefix_expr(obj.get("base").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("range_begin")),
            value_to_usize(obj.get("width")),
        ),
        "concat" => concat_expr(
            array_field(obj, "parts")
                .into_iter()
                .map(|part| prefix_expr(&part, prefix))
                .collect(),
            value_to_usize(obj.get("width")),
        ),
        "resize" => resize_expr(
            prefix_expr(obj.get("expr").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("width")),
        ),
        "memory_read" => memory_read_expr(
            &format!("{}__{}", prefix, value_to_string(obj.get("memory"))),
            prefix_expr(obj.get("addr").unwrap_or(&Value::Null), prefix),
            value_to_usize(obj.get("width")),
        ),
        _ => expr.clone(),
    }
}

fn module_to_value(module: &FrontendModule) -> Value {
    let mut out = Map::new();
    out.insert("name".to_string(), Value::String(module.name.clone()));
    out.insert(
        "ports".to_string(),
        Value::Array(
            module
                .ports
                .iter()
                .map(|port| {
                    let mut value = Map::new();
                    value.insert("name".to_string(), Value::String(port.name.clone()));
                    value.insert("direction".to_string(), Value::String(port.direction.clone()));
                    value.insert("width".to_string(), Value::from(port.width as u64));
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "nets".to_string(),
        Value::Array(
            module
                .nets
                .iter()
                .map(|net| {
                    let mut value = Map::new();
                    value.insert("name".to_string(), Value::String(net.name.clone()));
                    value.insert("width".to_string(), Value::from(net.width as u64));
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "regs".to_string(),
        Value::Array(
            module
                .regs
                .iter()
                .map(|reg| {
                    let mut value = Map::new();
                    value.insert("name".to_string(), Value::String(reg.name.clone()));
                    value.insert("width".to_string(), Value::from(reg.width as u64));
                    if let Some(reset_value) = &reg.reset_value {
                        value.insert("reset_value".to_string(), reset_value.clone());
                    }
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "assigns".to_string(),
        Value::Array(
            module
                .assigns
                .iter()
                .map(|assign| {
                    let mut value = Map::new();
                    value.insert("target".to_string(), Value::String(assign.target.clone()));
                    value.insert("expr".to_string(), assign.expr.clone());
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "processes".to_string(),
        Value::Array(
            module
                .processes
                .iter()
                .map(|process| {
                    let mut value = Map::new();
                    value.insert("name".to_string(), Value::String(process.name.clone()));
                    value.insert(
                        "clock".to_string(),
                        process
                            .clock
                            .as_ref()
                            .map(|clock| Value::String(clock.clone()))
                            .unwrap_or(Value::Null),
                    );
                    value.insert("clocked".to_string(), Value::Bool(process.clocked));
                    value.insert(
                        "statements".to_string(),
                        Value::Array(
                            process
                                .statements
                                .iter()
                                .map(|statement| {
                                    let mut statement_value = Map::new();
                                    statement_value.insert("target".to_string(), Value::String(statement.target.clone()));
                                    statement_value.insert("expr".to_string(), statement.expr.clone());
                                    Value::Object(statement_value)
                                })
                                .collect(),
                        ),
                    );
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "memories".to_string(),
        Value::Array(
            module
                .memories
                .iter()
                .map(|memory| {
                    let mut value = Map::new();
                    value.insert("name".to_string(), Value::String(memory.name.clone()));
                    value.insert("depth".to_string(), Value::from(memory.depth as u64));
                    value.insert("width".to_string(), Value::from(memory.width as u64));
                    if !memory.initial_data.is_empty() {
                        value.insert("initial_data".to_string(), Value::Array(memory.initial_data.clone()));
                    }
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "write_ports".to_string(),
        Value::Array(
            module
                .write_ports
                .iter()
                .map(|port| {
                    let mut value = Map::new();
                    value.insert("memory".to_string(), Value::String(port.memory.clone()));
                    value.insert("clock".to_string(), Value::String(port.clock.clone()));
                    value.insert("addr".to_string(), port.addr.clone());
                    value.insert("data".to_string(), port.data.clone());
                    value.insert("enable".to_string(), port.enable.clone());
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    out.insert(
        "sync_read_ports".to_string(),
        Value::Array(
            module
                .sync_read_ports
                .iter()
                .map(|port| {
                    let mut value = Map::new();
                    value.insert("memory".to_string(), Value::String(port.memory.clone()));
                    value.insert("clock".to_string(), Value::String(port.clock.clone()));
                    value.insert("addr".to_string(), port.addr.clone());
                    value.insert("data".to_string(), Value::String(port.data.clone()));
                    if let Some(enable) = &port.enable {
                        value.insert("enable".to_string(), enable.clone());
                    }
                    Value::Object(value)
                })
                .collect(),
        ),
    );
    Value::Object(out)
}

fn append_net(nets: &mut Vec<FrontendNet>, name: &str, width: usize) {
    if nets.iter().any(|net| net.name == name) {
        return;
    }
    nets.push(FrontendNet {
        name: name.to_string(),
        width,
    });
}

fn append_reg(regs: &mut Vec<FrontendReg>, name: &str, width: usize, reset_value: Option<Value>) {
    if regs.iter().any(|reg| reg.name == name) {
        return;
    }
    regs.push(FrontendReg {
        name: name.to_string(),
        width,
        reset_value,
    });
}

fn append_assign(assigns: &mut Vec<FrontendAssign>, assign: FrontendAssign) {
    if assign
        .expr
        .as_object()
        .and_then(|expr| expr.get("kind"))
        .and_then(Value::as_str)
        == Some("signal")
        && assign
            .expr
            .as_object()
            .and_then(|expr| expr.get("name"))
            .and_then(Value::as_str)
            == Some(assign.target.as_str())
    {
        return;
    }
    assigns.push(assign);
}

fn operand_expr(
    token: &str,
    widths: &HashMap<String, usize>,
    width_hint: Option<usize>,
    clock_aliases: &HashMap<String, String>,
) -> Result<Value, String> {
    let name = normalize_value_name(token);
    if name.is_empty() {
        return Err("Expected SSA value token".to_string());
    }
    let resolved_name = resolve_clock_name(&name, clock_aliases);
    let width = widths
        .get(&name)
        .copied()
        .or_else(|| widths.get(&resolved_name).copied())
        .or(width_hint)
        .unwrap_or(1);
    Ok(signal_expr(&resolved_name, width))
}

fn comb_binary_op_to_runtime_op(mlir_op: &str) -> Result<&'static str, String> {
    match mlir_op {
        "add" => Ok("+"),
        "sub" => Ok("-"),
        "mul" => Ok("*"),
        "divu" | "divs" => Ok("/"),
        "modu" | "mods" => Ok("%"),
        "and" => Ok("&"),
        "or" => Ok("|"),
        "xor" => Ok("^"),
        "shl" => Ok("<<"),
        "shru" | "shrs" => Ok(">>"),
        _ => Err(format!("Unsupported comb op {}", mlir_op)),
    }
}

fn icmp_predicate_to_op(pred: &str) -> Result<&'static str, String> {
    match pred {
        "eq" => Ok("=="),
        "ne" => Ok("!="),
        "ult" | "slt" => Ok("<"),
        "ugt" | "sgt" => Ok(">"),
        "ule" | "sle" => Ok("<="),
        "uge" | "sge" => Ok(">="),
        _ => Err(format!("Unsupported comb.icmp predicate {}", pred)),
    }
}

fn parse_scalar_width(ty: &str) -> Result<usize, String> {
    let trimmed = ty.trim();
    reject_aggregate_type(trimmed, "scalar type")?;
    let width_text = trimmed
        .strip_prefix('i')
        .ok_or_else(|| format!("Unsupported scalar type {}", trimmed))?;
    width_text
        .trim()
        .parse::<usize>()
        .map_err(|e| format!("Invalid scalar width {}: {}", width_text.trim(), e))
}

fn reject_aggregate_type(ty: &str, context: &str) -> Result<(), String> {
    if ty.trim().starts_with("!hw.array") {
        return Err(format!("Unsupported aggregate type in {}: {}", context, ty.trim()));
    }
    Ok(())
}

fn parse_firmem_type(ty: &str) -> Result<(usize, usize), String> {
    let trimmed = ty.trim();
    let inner = trimmed
        .strip_prefix('<')
        .and_then(|value| value.strip_suffix('>'))
        .ok_or_else(|| format!("Invalid seq.firmem type {}", trimmed))?;
    let (depth_text, width_text) = inner
        .split_once('x')
        .ok_or_else(|| format!("Invalid seq.firmem shape {}", trimmed))?;
    let width = width_text
        .trim()
        .parse::<usize>()
        .map_err(|e| format!("Invalid firmem width {}: {}", width_text.trim(), e))?;
    let depth = depth_text
        .trim()
        .parse::<usize>()
        .map_err(|e| format!("Invalid firmem depth {}: {}", depth_text.trim(), e))?;
    Ok((depth, width))
}

fn parse_memory_access_target(text: &str) -> Result<(String, String), String> {
    let open = text
        .find('[')
        .ok_or_else(|| format!("Invalid memory access target {}", text))?;
    let close = matching_delimiter(text, open, '[', ']')
        .ok_or_else(|| format!("Unterminated memory access target {}", text))?;
    Ok((
        normalize_value_name(&text[..open]),
        text[open + 1..close].trim().to_string(),
    ))
}

fn parse_quoted_string(text: &str) -> Result<(String, &str), String> {
    let trimmed = text.trim();
    let remainder = trimmed
        .strip_prefix('"')
        .ok_or_else(|| format!("Expected quoted string in {}", text))?;
    let end = remainder
        .find('"')
        .ok_or_else(|| format!("Unterminated quoted string in {}", text))?;
    Ok((remainder[..end].to_string(), &remainder[end + 1..]))
}

fn split_once_required<'a>(text: &'a str, delimiter: char, context: &str) -> Result<(&'a str, &'a str), String> {
    split_once_top_level(text, delimiter)
        .ok_or_else(|| format!("Missing '{}' separator in {}", delimiter, context))
}

fn split_once_top_level(text: &str, delimiter: char) -> Option<(&str, &str)> {
    let mut paren_depth = 0i32;
    let mut bracket_depth = 0i32;
    let mut angle_depth = 0i32;
    let mut in_string = false;

    for (idx, ch) in text.char_indices() {
        match ch {
            '"' => in_string = !in_string,
            '(' if !in_string => paren_depth += 1,
            ')' if !in_string => paren_depth -= 1,
            '[' if !in_string => bracket_depth += 1,
            ']' if !in_string => bracket_depth -= 1,
            '<' if !in_string => angle_depth += 1,
            '>' if !in_string => angle_depth -= 1,
            _ => {}
        }

        if ch == delimiter && !in_string && paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 {
            return Some((&text[..idx], &text[idx + ch.len_utf8()..]));
        }
    }

    None
}

fn split_top_level(text: &str, delimiter: char) -> Vec<String> {
    let mut out = Vec::new();
    let mut start = 0usize;
    let mut paren_depth = 0i32;
    let mut bracket_depth = 0i32;
    let mut angle_depth = 0i32;
    let mut in_string = false;

    for (idx, ch) in text.char_indices() {
        match ch {
            '"' => in_string = !in_string,
            '(' if !in_string => paren_depth += 1,
            ')' if !in_string => paren_depth -= 1,
            '[' if !in_string => bracket_depth += 1,
            ']' if !in_string => bracket_depth -= 1,
            '<' if !in_string => angle_depth += 1,
            '>' if !in_string => angle_depth -= 1,
            _ => {}
        }

        if ch == delimiter && !in_string && paren_depth == 0 && bracket_depth == 0 && angle_depth == 0 {
            out.push(text[start..idx].trim().to_string());
            start = idx + ch.len_utf8();
        }
    }

    if start <= text.len() {
        out.push(text[start..].trim().to_string());
    }

    out
}

fn matching_delimiter(text: &str, open_idx: usize, open: char, close: char) -> Option<usize> {
    let mut depth = 0i32;
    let mut in_string = false;

    for (idx, ch) in text.char_indices().skip_while(|(idx, _)| *idx < open_idx) {
        if ch == '"' {
            in_string = !in_string;
            continue;
        }
        if in_string {
            continue;
        }
        if ch == open {
            depth += 1;
        } else if ch == close {
            depth -= 1;
            if depth == 0 {
                return Some(idx);
            }
        }
    }

    None
}

fn brace_delta(line: &str) -> i32 {
    let code = code_for(line);
    code.chars().fold(0, |acc, ch| match ch {
        '{' => acc + 1,
        '}' => acc - 1,
        _ => acc,
    })
}

fn code_for(line: &str) -> String {
    line.split("//").next().unwrap_or("").trim().to_string()
}

fn normalize_value_name(token: &str) -> String {
    token.trim().trim_start_matches('%').to_string()
}

fn resolve_clock_name(token: &str, clock_aliases: &HashMap<String, String>) -> String {
    let mut current = token.to_string();
    let mut guard = 0usize;
    while let Some(next) = clock_aliases.get(&current) {
        if *next == current {
            break;
        }
        current = next.clone();
        guard += 1;
        if guard > 64 {
            break;
        }
    }
    current
}

fn first_and_last_colon(text: &str) -> Option<(usize, usize)> {
    let first = text.find(':')?;
    let last = text.rfind(':')?;
    Some((first, last))
}

fn expect_single_lhs(lhs_values: &[String], op: &str) -> Result<String, String> {
    if lhs_values.len() != 1 {
        return Err(format!("Expected single result for {}, got {}", op, lhs_values.len()));
    }
    Ok(lhs_values[0].clone())
}

fn memory_addr_width(depth: usize) -> usize {
    if depth <= 1 {
        return 1;
    }
    (usize::BITS - (depth.saturating_sub(1)).leading_zeros()) as usize
}

fn literal_value_only(value: &str) -> Value {
    Value::String(value.trim().to_string())
}

fn signal_expr(name: &str, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("signal".to_string()));
    out.insert("name".to_string(), Value::String(name.to_string()));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn literal_expr(value: &str, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("literal".to_string()));
    out.insert("value".to_string(), Value::String(value.trim().to_string()));
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

fn slice_expr(base: Value, low: usize, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("slice".to_string()));
    out.insert("base".to_string(), base);
    out.insert("range_begin".to_string(), Value::from(low as u64));
    out.insert("range_end".to_string(), Value::from((low + width) as u64));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn concat_expr(parts: Vec<Value>, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("concat".to_string()));
    out.insert("parts".to_string(), Value::Array(parts));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn resize_expr(expr: Value, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("resize".to_string()));
    out.insert("expr".to_string(), expr);
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn memory_read_expr(memory: &str, addr: Value, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("memory_read".to_string()));
    out.insert("memory".to_string(), Value::String(memory.to_string()));
    out.insert("addr".to_string(), addr);
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
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
                .map(|value| port_to_normalized_value(&value))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "nets".to_string(),
        Value::Array(
            array_field(&module_obj, "nets")
                .into_iter()
                .map(|value| net_to_normalized_value(&value))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "regs".to_string(),
        Value::Array(
            array_field(&module_obj, "regs")
                .into_iter()
                .map(|value| reg_to_normalized_value(&value))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "assigns".to_string(),
        Value::Array(
            array_field(&module_obj, "assigns")
                .into_iter()
                .map(|value| assign_to_normalized_value(&value, &expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "processes".to_string(),
        Value::Array(
            array_field(&module_obj, "processes")
                .into_iter()
                .map(|value| process_to_normalized_value(&value, &expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "memories".to_string(),
        Value::Array(
            array_field(&module_obj, "memories")
                .into_iter()
                .map(|value| memory_to_normalized_value(&value))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "write_ports".to_string(),
        Value::Array(
            array_field(&module_obj, "write_ports")
                .into_iter()
                .map(|value| write_port_to_normalized_value(&value, &expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
        ),
    );
    out.insert(
        "sync_read_ports".to_string(),
        Value::Array(
            array_field(&module_obj, "sync_read_ports")
                .into_iter()
                .map(|value| sync_read_port_to_normalized_value(&value, &expr_pool))
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
            .map(|value| {
                if value.is_null() {
                    Value::Null
                } else {
                    Value::String(value_to_string(Some(value)))
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
            (Some(t), None) => mux_expr(cond.clone(), t, signal_expr(&target, width), width),
            (None, Some(f)) => mux_expr(
                unary_expr("~", cond.clone(), 1),
                f,
                signal_expr(&target, width),
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
    out.insert("memory".to_string(), Value::String(value_to_string(obj.get("memory"))));
    out.insert("clock".to_string(), Value::String(value_to_string(obj.get("clock"))));
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"), expr_pool)?);
    out.insert("data".to_string(), expr_to_normalized_value(obj.get("data"), expr_pool)?);
    out.insert("enable".to_string(), expr_to_normalized_value(obj.get("enable"), expr_pool)?);
    Ok(Value::Object(out))
}

fn sync_read_port_to_normalized_value(value: &Value, expr_pool: &[Value]) -> Result<Value, String> {
    let obj = as_object(value, "sync_read_port")?;
    let mut out = Map::new();
    out.insert("memory".to_string(), Value::String(value_to_string(obj.get("memory"))));
    out.insert("clock".to_string(), Value::String(value_to_string(obj.get("clock"))));
    out.insert("addr".to_string(), expr_to_normalized_value(obj.get("addr"), expr_pool)?);
    out.insert("data".to_string(), Value::String(value_to_string(obj.get("data"))));
    if let Some(enable) = obj.get("enable") {
        if !enable.is_null() {
            out.insert("enable".to_string(), expr_to_normalized_value(Some(enable), expr_pool)?);
        }
    }
    Ok(Value::Object(out))
}

fn expr_to_normalized_value(expr: Option<&Value>, expr_pool: &[Value]) -> Result<Value, String> {
    let Some(value) = expr else {
        return Ok(literal_expr("0", 1));
    };
    let obj = as_object(value, "expression")?;

    let expr_kind = obj.get("kind").and_then(Value::as_str).unwrap_or("");

    match expr_kind {
        "signal" => Ok(signal_expr(
            &value_to_string(obj.get("name")),
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
        "slice" => Ok(slice_expr(
            expr_to_normalized_value(obj.get("base"), expr_pool)?,
            value_to_usize(obj.get("range_begin")),
            value_to_usize(obj.get("width")),
        )),
        "concat" => Ok(concat_expr(
            array_field(obj, "parts")
                .into_iter()
                .map(|part| expr_to_normalized_value(Some(&part), expr_pool))
                .collect::<Result<Vec<_>, _>>()?,
            value_to_usize(obj.get("width")),
        )),
        "resize" => Ok(resize_expr(
            expr_to_normalized_value(obj.get("expr"), expr_pool)?,
            value_to_usize(obj.get("width")),
        )),
        "memory_read" => Ok(memory_read_expr(
            &value_to_string(obj.get("memory")),
            expr_to_normalized_value(obj.get("addr"), expr_pool)?,
            value_to_usize(obj.get("width")),
        )),
        "case" => lower_case_expr(obj, expr_pool),
        _ => Ok(literal_expr("0", 1)),
    }
}

fn lower_case_expr(case_obj: &Map<String, Value>, expr_pool: &[Value]) -> Result<Value, String> {
    let selector = expr_to_normalized_value(case_obj.get("selector"), expr_pool)?;
    let width = value_to_usize(case_obj.get("width"));
    let default_expr = if let Some(default_value) = case_obj.get("default") {
        if !default_value.is_null() {
            expr_to_normalized_value(Some(default_value), expr_pool)?
        } else {
            literal_expr("0", width.max(1))
        }
    } else {
        literal_expr("0", width.max(1))
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
                    literal_expr(&value.to_string(), expr_width(Some(&selector)).unwrap_or(1)),
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
            .filter_map(|value| value.trim().parse::<i64>().ok())
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
        Some(Value::String(text)) => text.clone(),
        Some(Value::Number(number)) => number.to_string(),
        Some(Value::Bool(flag)) => {
            if *flag {
                "true".to_string()
            } else {
                "false".to_string()
            }
        }
        _ => String::new(),
    }
}

fn value_to_bool(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::Number(number)) => number.as_u64().unwrap_or(0) != 0,
        Some(Value::String(text)) => text == "true" || text == "1",
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
        Some(Value::Number(number)) => number
            .as_i64()
            .unwrap_or_else(|| number.as_u64().unwrap_or(0) as i64),
        Some(Value::String(text)) => text.parse::<i64>().unwrap_or(0),
        Some(Value::Bool(flag)) => {
            if *flag {
                1
            } else {
                0
            }
        }
        _ => 0,
    }
}

fn literal_expr_from_json(value: Option<&Value>, width: usize) -> Value {
    let mut out = Map::new();
    out.insert("kind".to_string(), Value::String("literal".to_string()));
    out.insert("value".to_string(), value.cloned().unwrap_or_else(|| Value::String("0".to_string())));
    out.insert("width".to_string(), Value::from(width as u64));
    Value::Object(out)
}

fn expr_width(expr: Option<&Value>) -> Option<usize> {
    let obj = expr?.as_object()?;
    obj.get("width").map(|width| value_to_usize(Some(width)))
}
