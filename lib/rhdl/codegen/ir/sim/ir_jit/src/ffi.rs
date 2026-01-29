//! Core C ABI function exports for the JIT simulator
//!
//! These functions are called via Fiddle from Ruby.
//! All functions use C-compatible types and follow a consistent naming convention.
//!
//! Extension-specific FFI functions are in their respective modules:
//! - extensions/apple2/ffi.rs
//! - extensions/mos6502/ffi.rs

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_ulong};
use std::ptr;
use std::slice;

use crate::core::CoreSimulator;
use crate::extensions::{Apple2Extension, Mos6502Extension};

// ============================================================================
// Simulator Context
// ============================================================================

/// Opaque simulator context passed to all FFI functions
pub struct JitSimContext {
    pub core: CoreSimulator,
    pub apple2: Option<Apple2Extension>,
    pub mos6502: Option<Mos6502Extension>,
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

        let mos6502 = if Mos6502Extension::is_mos6502_ir(&core.name_to_idx) {
            Some(Mos6502Extension::new(&core))
        } else {
            None
        };

        Ok(Self { core, apple2, mos6502 })
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
pub unsafe extern "C" fn jit_sim_peek(
    ctx: *const JitSimContext,
    name: *const c_char,
) -> c_ulong {
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

    if ctx.core.name_to_idx.contains_key(name) { 1 } else { 0 }
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

    ctx.core.get_signal_idx(name).map(|i| i as c_int).unwrap_or(-1)
}

/// Poke by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_poke_by_idx(
    ctx: *mut JitSimContext,
    idx: c_uint,
    value: c_ulong,
) {
    if !ctx.is_null() {
        (*ctx).core.poke_by_idx(idx as usize, value as u64);
    }
}

/// Peek by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_peek_by_idx(
    ctx: *const JitSimContext,
    idx: c_uint,
) -> c_ulong {
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
