//! Core C ABI function exports for the JIT simulator
//!
//! These functions are called via Fiddle from Ruby.
//! All functions use C-compatible types and follow a consistent naming convention.
//!
//! Extension-specific FFI functions are in their respective modules:
//! - extensions/apple2/ffi.rs
//! - extensions/gameboy/ffi.rs
//! - extensions/mos6502/ffi.rs

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_ulong};
use std::ptr;
use std::slice;

use crate::core::CoreSimulator;
use crate::extensions::{Apple2Extension, GameBoyExtension, Mos6502Extension};
use crate::vcd::{TraceMode, VcdTracer};

// ============================================================================
// Simulator Context
// ============================================================================

/// Opaque simulator context passed to all FFI functions
pub struct JitSimContext {
    pub core: CoreSimulator,
    pub apple2: Option<Apple2Extension>,
    pub gameboy: Option<GameBoyExtension>,
    pub mos6502: Option<Mos6502Extension>,
    pub tracer: VcdTracer,
}

impl JitSimContext {
    pub fn new(json: &str, sub_cycles: usize) -> Result<Self, String> {
        let core = CoreSimulator::new(json)?;

        // Detect and create extensions based on signal names
        let apple2 = if Apple2Extension::is_apple2_ir(&core.name_to_idx) {
            Some(Apple2Extension::new(&core, sub_cycles))
        } else {
            None
        };

        let gameboy = if GameBoyExtension::is_gameboy_ir(&core.name_to_idx) {
            Some(GameBoyExtension::new(&core))
        } else {
            None
        };

        let mos6502 = if Mos6502Extension::is_mos6502_ir(&core.name_to_idx) {
            Some(Mos6502Extension::new(&core))
        } else {
            None
        };

        let mut signal_entries: Vec<(usize, String)> = core
            .name_to_idx
            .iter()
            .map(|(name, &idx)| (idx, name.clone()))
            .collect();
        signal_entries.sort_by_key(|(idx, _)| *idx);

        let signal_names: Vec<String> = signal_entries
            .iter()
            .map(|(_, name)| name.clone())
            .collect();
        let signal_widths: Vec<usize> = signal_entries
            .iter()
            .map(|(idx, _)| core.widths.get(*idx).copied().unwrap_or(1))
            .collect();

        let mut tracer = VcdTracer::new();
        tracer.init(signal_names, signal_widths);

        Ok(Self {
            core,
            apple2,
            gameboy,
            mos6502,
            tracer,
        })
    }
}

// ============================================================================
// Core FFI Functions
// ============================================================================

/// Create a new JIT simulator from JSON
#[no_mangle]
pub unsafe extern "C" fn jit_sim_create(
    json: *const c_char,
    json_len: usize,
    sub_cycles: c_uint,
    error_out: *mut *mut c_char,
) -> *mut JitSimContext {
    let json_slice = slice::from_raw_parts(json as *const u8, json_len);
    let json_str = match std::str::from_utf8(json_slice) {
        Ok(s) => s,
        Err(e) => {
            if !error_out.is_null() {
                let msg = CString::new(format!("Invalid UTF-8 in JSON: {}", e)).unwrap();
                *error_out = msg.into_raw();
            }
            return ptr::null_mut();
        }
    };

    match JitSimContext::new(json_str, sub_cycles as usize) {
        Ok(ctx) => Box::into_raw(Box::new(ctx)),
        Err(e) => {
            if !error_out.is_null() {
                let msg = CString::new(e).unwrap();
                *error_out = msg.into_raw();
            }
            ptr::null_mut()
        }
    }
}

/// Destroy a JIT simulator
#[no_mangle]
pub unsafe extern "C" fn jit_sim_destroy(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

/// Free an error string
#[no_mangle]
pub unsafe extern "C" fn jit_sim_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

/// Free a string returned by jit_sim functions
#[no_mangle]
pub unsafe extern "C" fn jit_sim_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Allocate memory in the simulator WASM heap for JS interop
#[no_mangle]
pub unsafe extern "C" fn jit_sim_wasm_alloc(size: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(size.max(1));
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Free memory previously allocated with jit_sim_wasm_alloc
#[no_mangle]
pub unsafe extern "C" fn jit_sim_wasm_dealloc(ptr: *mut u8, size: usize) {
    if ptr.is_null() {
        return;
    }
    let cap = size.max(1);
    drop(Vec::<u8>::from_raw_parts(ptr, 0, cap));
}

/// Poke a signal value
#[no_mangle]
pub unsafe extern "C" fn jit_sim_poke(
    ctx: *mut JitSimContext,
    name: *const c_char,
    value: c_ulong,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    match ctx.core.poke(name, value as u64) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Peek a signal value
#[no_mangle]
pub unsafe extern "C" fn jit_sim_peek(ctx: *const JitSimContext, name: *const c_char) -> c_ulong {
    if ctx.is_null() || name.is_null() {
        return 0;
    }
    let ctx = &*ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    ctx.core.peek(name).unwrap_or(0) as c_ulong
}

/// Check if a signal exists
#[no_mangle]
pub unsafe extern "C" fn jit_sim_has_signal(
    ctx: *const JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return 0;
    }
    let ctx = &*ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    if ctx.core.name_to_idx.contains_key(name) {
        1
    } else {
        0
    }
}

/// Get signal index by name
#[no_mangle]
pub unsafe extern "C" fn jit_sim_get_signal_idx(
    ctx: *const JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &*ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.core
        .get_signal_idx(name)
        .map(|i| i as c_int)
        .unwrap_or(-1)
}

/// Poke by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_poke_by_idx(ctx: *mut JitSimContext, idx: c_uint, value: c_ulong) {
    if !ctx.is_null() {
        (*ctx).core.poke_by_idx(idx as usize, value as u64);
    }
}

/// Peek by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_peek_by_idx(ctx: *const JitSimContext, idx: c_uint) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.peek_by_idx(idx as usize) as c_ulong
}

/// Evaluate combinational logic
#[no_mangle]
pub unsafe extern "C" fn jit_sim_evaluate(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.evaluate();
    }
}

/// Tick (evaluate + clock edge detection + register update)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_tick(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick();
    }
}

/// Tick with forced edge detection using prev_clock_values set by caller
/// Use set_prev_clock before calling this to control edge detection
#[no_mangle]
pub unsafe extern "C" fn jit_sim_tick_forced(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick_forced();
    }
}

/// Set previous clock value for a clock index (for forced edge detection)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_set_prev_clock(
    ctx: *mut JitSimContext,
    clock_list_idx: c_uint,
    value: c_ulong,
) {
    if !ctx.is_null() {
        let ctx = &mut *ctx;
        let idx = clock_list_idx as usize;
        if idx < ctx.core.prev_clock_values.len() {
            ctx.core.prev_clock_values[idx] = value;
        }
    }
}

/// Get clock list index for a signal index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_get_clock_list_idx(
    ctx: *const JitSimContext,
    signal_idx: c_uint,
) -> c_int {
    if ctx.is_null() {
        return -1;
    }
    let sig_idx = signal_idx as usize;
    match (*ctx)
        .core
        .clock_indices
        .iter()
        .position(|&ci| ci == sig_idx)
    {
        Some(pos) => pos as c_int,
        None => -1,
    }
}

/// Run N ticks
#[no_mangle]
pub unsafe extern "C" fn jit_sim_run_ticks(ctx: *mut JitSimContext, n: c_uint) {
    if !ctx.is_null() {
        (*ctx).core.run_ticks(n as usize);
    }
}

/// Reset all signals to initial values
#[no_mangle]
pub unsafe extern "C" fn jit_sim_reset(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.reset();
    }
}

/// Get signal count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_signal_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.signal_count() as c_uint
}

/// Get register count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_reg_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.reg_count() as c_uint
}

/// Get input names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_input_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.input_names.join(",");
    CString::new(names).unwrap().into_raw()
}

/// Get output names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_output_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.output_names.join(",");
    CString::new(names).unwrap().into_raw()
}

// ============================================================================
// VCD Tracing FFI Functions
// ============================================================================

/// Start VCD tracing in buffer mode
/// Returns 0 on success, -1 on error
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_start(ctx: *mut JitSimContext) -> c_int {
    if ctx.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    ctx.tracer.set_mode(TraceMode::Buffer);
    ctx.tracer.start();
    0
}

/// Start VCD tracing in streaming mode to a file
/// Returns 0 on success, -1 on error
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_start_streaming(
    ctx: *mut JitSimContext,
    path: *const c_char,
) -> c_int {
    if ctx.is_null() || path.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let path = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    if ctx.tracer.open_file(path).is_err() {
        return -1;
    }
    ctx.tracer.start();
    0
}

/// Stop VCD tracing
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_stop(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.stop();
    }
}

/// Check if tracing is enabled
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_enabled(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).tracer.is_enabled() {
        1
    } else {
        0
    }
}

/// Capture current signal values (call each simulation step)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_capture(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        let ctx = &mut *ctx;
        ctx.tracer.capture(&ctx.core.signals);
    }
}

/// Add a signal to trace by name
/// Returns 0 if signal found and added, -1 if not found
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_add_signal(
    ctx: *mut JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    if ctx.tracer.add_signal_by_name(name) {
        0
    } else {
        -1
    }
}

/// Add signals matching a pattern (substring match)
/// Returns the number of signals added
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_add_signals_matching(
    ctx: *mut JitSimContext,
    pattern: *const c_char,
) -> c_int {
    if ctx.is_null() || pattern.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    let pattern = match CStr::from_ptr(pattern).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    ctx.tracer.add_signals_matching(pattern) as c_int
}

/// Trace all signals
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_all_signals(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.trace_all_signals();
    }
}

/// Clear the set of traced signals
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_clear_signals(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.clear_signals();
    }
}

/// Get VCD output as string (caller must free with jit_sim_free_string)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_to_vcd(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let vcd = (*ctx).tracer.to_vcd();
    CString::new(vcd).unwrap().into_raw()
}

/// Get only new live VCD chunk since the last call (caller must free with jit_sim_free_string)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_take_live_vcd(ctx: *mut JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let chunk = (*ctx).tracer.take_live_chunk();
    CString::new(chunk).unwrap().into_raw()
}

/// Save VCD output to a file
/// Returns 0 on success, -1 on error
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_save_vcd(
    ctx: *const JitSimContext,
    path: *const c_char,
) -> c_int {
    if ctx.is_null() || path.is_null() {
        return -1;
    }
    let path = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    match (*ctx).tracer.save_vcd(path) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Clear all buffered trace data
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_clear(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.clear();
    }
}

/// Get the number of recorded changes
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_change_count(ctx: *const JitSimContext) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).tracer.change_count() as c_ulong
}

/// Get the number of traced signals
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_signal_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).tracer.stats().traced_signals as c_uint
}

/// Set the VCD timescale (e.g., "1ns", "1ps")
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_set_timescale(
    ctx: *mut JitSimContext,
    timescale: *const c_char,
) -> c_int {
    if ctx.is_null() || timescale.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let timescale = match CStr::from_ptr(timescale).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.tracer.set_timescale(timescale);
    0
}

/// Set the VCD module name
#[no_mangle]
pub unsafe extern "C" fn jit_sim_trace_set_module_name(
    ctx: *mut JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.tracer.set_module_name(name);
    0
}
