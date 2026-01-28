//! Core C ABI function exports for the IR Interpreter
//!
//! These functions are called via Fiddle from Ruby.
//! All functions use C-compatible types and follow a consistent naming convention.

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

/// Get combinational op count
#[no_mangle]
pub unsafe extern "C" fn ir_sim_comb_op_count(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.all_comb_ops.len() as c_uint
}

/// Get sequential assign count
#[no_mangle]
pub unsafe extern "C" fn ir_sim_seq_assign_count(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.seq_assigns.len() as c_uint
}

/// Get sequential fast path count
#[no_mangle]
pub unsafe extern "C" fn ir_sim_seq_fast_count(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.seq_assigns.iter().filter(|a| a.fast_source.is_some()).count() as c_uint
}

// ============================================================================
// Apple II Extension FFI Functions
// ============================================================================

/// Check if Apple II mode is enabled
#[no_mangle]
pub unsafe extern "C" fn ir_sim_is_apple2_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).apple2.is_some() { 1 } else { 0 }
}

/// Load ROM data for Apple II
#[no_mangle]
pub unsafe extern "C" fn ir_sim_apple2_load_rom(
    ctx: *mut IrSimContext,
    data: *const u8,
    len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let bytes = slice::from_raw_parts(data, len);
        apple2.load_rom(bytes);
    }
}

/// Load RAM data for Apple II
#[no_mangle]
pub unsafe extern "C" fn ir_sim_apple2_load_ram(
    ctx: *mut IrSimContext,
    data: *const u8,
    len: usize,
    offset: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let bytes = slice::from_raw_parts(data, len);
        apple2.load_ram(bytes, offset);
    }
}

/// Run CPU cycles for Apple II, returns batch result
/// Result is written to output parameters
#[no_mangle]
pub unsafe extern "C" fn ir_sim_apple2_run_cpu_cycles(
    ctx: *mut IrSimContext,
    n: usize,
    key_data: u8,
    key_ready: c_int,
    out_text_dirty: *mut c_int,
    out_key_cleared: *mut c_int,
    out_cycles_run: *mut usize,
    out_speaker_toggles: *mut u32,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let result = apple2.run_cpu_cycles(&mut ctx.core, n, key_data, key_ready != 0);
        if !out_text_dirty.is_null() {
            *out_text_dirty = result.text_dirty as c_int;
        }
        if !out_key_cleared.is_null() {
            *out_key_cleared = result.key_cleared as c_int;
        }
        if !out_cycles_run.is_null() {
            *out_cycles_run = result.cycles_run;
        }
        if !out_speaker_toggles.is_null() {
            *out_speaker_toggles = result.speaker_toggles;
        }
    }
}

/// Read RAM for Apple II
/// Returns bytes read into provided buffer
#[no_mangle]
pub unsafe extern "C" fn ir_sim_apple2_read_ram(
    ctx: *const IrSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
) -> usize {
    if ctx.is_null() || out_data.is_null() {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref apple2) = ctx.apple2 {
        let data = apple2.read_ram(start, len);
        let copy_len = data.len().min(len);
        ptr::copy_nonoverlapping(data.as_ptr(), out_data, copy_len);
        return copy_len;
    }
    0
}

/// Write RAM for Apple II
#[no_mangle]
pub unsafe extern "C" fn ir_sim_apple2_write_ram(
    ctx: *mut IrSimContext,
    start: usize,
    data: *const u8,
    len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let bytes = slice::from_raw_parts(data, len);
        apple2.write_ram(start, bytes);
    }
}

// ============================================================================
// MOS6502 Extension FFI Functions
// ============================================================================

/// Check if MOS6502 mode is enabled
#[no_mangle]
pub unsafe extern "C" fn ir_sim_is_mos6502_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).mos6502.is_some() { 1 } else { 0 }
}

/// Load memory for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_load_memory(
    ctx: *mut IrSimContext,
    data: *const u8,
    len: usize,
    offset: usize,
    is_rom: c_int,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        let bytes = slice::from_raw_parts(data, len);
        mos6502.load_memory(bytes, offset, is_rom != 0);
    }
}

/// Set reset vector for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_set_reset_vector(
    ctx: *mut IrSimContext,
    addr: u16,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.set_reset_vector(addr);
    }
}

/// Run cycles for MOS6502, returns number of cycles run
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_run_cycles(
    ctx: *mut IrSimContext,
    n: usize,
) -> usize {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        return mos6502.run_cycles(&mut ctx.core, n);
    }
    0
}

/// Read memory for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_read_memory(
    ctx: *const IrSimContext,
    addr: usize,
) -> u8 {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref mos6502) = ctx.mos6502 {
        return mos6502.read_memory(addr);
    }
    0
}

/// Write memory for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_write_memory(
    ctx: *mut IrSimContext,
    addr: usize,
    data: u8,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.write_memory(addr, data);
    }
}

/// Get speaker toggles for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_speaker_toggles(
    ctx: *const IrSimContext,
) -> u32 {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref mos6502) = ctx.mos6502 {
        return mos6502.speaker_toggles();
    }
    0
}

/// Reset speaker toggles for MOS6502
#[no_mangle]
pub unsafe extern "C" fn ir_sim_mos6502_reset_speaker_toggles(
    ctx: *mut IrSimContext,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.reset_speaker_toggles();
    }
}
