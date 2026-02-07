//! Apple II extension FFI functions for IR Interpreter
//!
//! C ABI exports for Apple II-specific functionality.

use std::os::raw::{c_int, c_uint};
use std::ptr;
use std::slice;

use crate::ffi::IrSimContext;

/// Result struct for Apple II run_cpu_cycles
#[repr(C)]
pub struct Apple2CycleResult {
    pub text_dirty: c_int,
    pub key_cleared: c_int,
    pub cycles_run: c_uint,
    pub speaker_toggles: c_uint,
}

/// Check if Apple II mode is enabled
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_is_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).apple2.is_some() { 1 } else { 0 }
}

/// Load ROM data for Apple II
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_load_rom(
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
pub unsafe extern "C" fn apple2_interp_sim_load_ram(
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
/// Result is written to result struct pointer
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_run_cpu_cycles(
    ctx: *mut IrSimContext,
    n: c_uint,
    key_data: u8,
    key_ready: c_int,
    result_out: *mut Apple2CycleResult,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let result = apple2.run_cpu_cycles(&mut ctx.core, n as usize, key_data, key_ready != 0);
        if !result_out.is_null() {
            (*result_out).text_dirty = if result.text_dirty { 1 } else { 0 };
            (*result_out).key_cleared = if result.key_cleared { 1 } else { 0 };
            (*result_out).cycles_run = result.cycles_run as c_uint;
            (*result_out).speaker_toggles = result.speaker_toggles;
        }
    }
}

/// Read RAM for Apple II
/// Returns bytes read into provided buffer
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_read_ram(
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

/// Read mapped Apple II memory (full 64KB CPU-visible address space)
/// Returns bytes read into provided buffer
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_read_memory(
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
        let out = slice::from_raw_parts_mut(out_data, len);
        return apple2.read_memory(start, out);
    }
    0
}

/// Write RAM for Apple II
#[no_mangle]
pub unsafe extern "C" fn apple2_interp_sim_write_ram(
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
