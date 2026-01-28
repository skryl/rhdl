//! Core C ABI function exports for the IR Compiler
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
pub struct IrSimContext {
    pub core: CoreSimulator,
    pub apple2: Option<Apple2Extension>,
    pub mos6502: Option<Mos6502Extension>,
}

impl IrSimContext {
    fn new(json: &str, sub_cycles: usize) -> Result<Self, String> {
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

    fn generate_code(&self) -> String {
        let mut code = self.core.generate_core_code();

        if self.apple2.is_some() {
            code.push_str(&Apple2Extension::generate_code(&self.core));
        }

        if self.mos6502.is_some() {
            code.push_str(&Mos6502Extension::generate_code(&self.core));
        }

        code
    }

    fn compile(&mut self) -> Result<bool, String> {
        let code = self.generate_code();
        self.core.compile_code(&code)
    }
}

// ============================================================================
// Core FFI Functions
// ============================================================================

/// Create a new IR simulator from JSON
/// Returns null on error, error message written to error_out if provided
#[no_mangle]
pub unsafe extern "C" fn ir_sim_create(
    json: *const c_char,
    json_len: usize,
    sub_cycles: c_uint,
    error_out: *mut *mut c_char,
) -> *mut IrSimContext {
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

    match IrSimContext::new(json_str, sub_cycles as usize) {
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

/// Destroy an IR simulator
#[no_mangle]
pub unsafe extern "C" fn ir_sim_destroy(ctx: *mut IrSimContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

/// Free an error string returned by ir_sim_create
#[no_mangle]
pub unsafe extern "C" fn ir_sim_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

/// Compile the IR simulator
/// Returns 1 on success (cached), 0 on success (compiled), -1 on error
#[no_mangle]
pub unsafe extern "C" fn ir_sim_compile(
    ctx: *mut IrSimContext,
    error_out: *mut *mut c_char,
) -> c_int {
    if ctx.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;

    match ctx.compile() {
        Ok(cached) => if cached { 1 } else { 0 },
        Err(e) => {
            if !error_out.is_null() {
                let msg = CString::new(e).unwrap();
                *error_out = msg.into_raw();
            }
            -1
        }
    }
}

/// Check if simulator is compiled
#[no_mangle]
pub unsafe extern "C" fn ir_sim_is_compiled(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).core.compiled { 1 } else { 0 }
}

/// Get generated code (caller must free with ir_sim_free_string)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_generated_code(ctx: *const IrSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let code = (*ctx).generate_code();
    CString::new(code).unwrap().into_raw()
}

/// Free a string returned by ir_sim functions
#[no_mangle]
pub unsafe extern "C" fn ir_sim_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Poke a signal value
/// Returns 0 on success, -1 on error (unknown signal)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_poke(
    ctx: *mut IrSimContext,
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
/// Returns the value, or 0 on error (check return value of ir_sim_has_signal)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_peek(
    ctx: *const IrSimContext,
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
pub unsafe extern "C" fn ir_sim_has_signal(
    ctx: *const IrSimContext,
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

/// Evaluate combinational logic
#[no_mangle]
pub unsafe extern "C" fn ir_sim_evaluate(ctx: *mut IrSimContext) {
    if !ctx.is_null() {
        (*ctx).core.evaluate();
    }
}

/// Tick (evaluate + clock edge detection + register update)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_tick(ctx: *mut IrSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick();
    }
}

/// Reset all signals to initial values
#[no_mangle]
pub unsafe extern "C" fn ir_sim_reset(ctx: *mut IrSimContext) {
    if !ctx.is_null() {
        (*ctx).core.reset();
    }
}

/// Get signal count
#[no_mangle]
pub unsafe extern "C" fn ir_sim_signal_count(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.signal_count() as c_uint
}

/// Get register count
#[no_mangle]
pub unsafe extern "C" fn ir_sim_reg_count(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.reg_count() as c_uint
}

/// Get input names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_input_names(ctx: *const IrSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.input_names.join(",");
    CString::new(names).unwrap().into_raw()
}

/// Get output names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn ir_sim_output_names(ctx: *const IrSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.output_names.join(",");
    CString::new(names).unwrap().into_raw()
}
