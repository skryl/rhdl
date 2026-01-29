//! Apple II extension FFI functions for IR Interpreter
//!
//! C ABI exports for Apple II-specific functionality.

use std::os::raw::c_int;
use std::ptr;
use std::slice;

use crate::ffi::IrSimContext;

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
