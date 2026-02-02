//! Apple II extension FFI functions
//!
//! C ABI exports for Apple II specific functionality.
//! The disk controller is fully HDL-driven - these functions only provide
//! memory bridging and track data loading into HDL memory.

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

/// Check if Apple II mode is active
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_is_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).apple2.is_some() { 1 } else { 0 }
}

/// Load Apple II ROM
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_load_rom(
    ctx: *mut IrSimContext,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_rom(data);
    }
}

/// Load Apple II RAM
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_load_ram(
    ctx: *mut IrSimContext,
    data: *const u8,
    data_len: usize,
    offset: c_uint,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_ram(data, offset as usize);
    }
}

/// Run Apple II CPU cycles (HDL-driven simulation)
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_run_cpu_cycles(
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
    if let Some(ref mut ext) = ctx.apple2 {
        let result = ext.run_cpu_cycles(&mut ctx.core, n as usize, key_data, key_ready != 0);
        if !result_out.is_null() {
            (*result_out).text_dirty = if result.text_dirty { 1 } else { 0 };
            (*result_out).key_cleared = if result.key_cleared { 1 } else { 0 };
            (*result_out).cycles_run = result.cycles_run as c_uint;
            (*result_out).speaker_toggles = result.speaker_toggles;
        }
    }
}

/// Run Apple II CPU cycles with VCD tracing
/// Captures signals after each CPU cycle for full visibility
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_run_cpu_cycles_traced(
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
    if let Some(ref mut ext) = ctx.apple2 {
        let result = ext.run_cpu_cycles_traced(
            &mut ctx.core,
            &mut ctx.tracer,
            n as usize,
            key_data,
            key_ready != 0,
        );
        if !result_out.is_null() {
            (*result_out).text_dirty = if result.text_dirty { 1 } else { 0 };
            (*result_out).key_cleared = if result.key_cleared { 1 } else { 0 };
            (*result_out).cycles_run = result.cycles_run as c_uint;
            (*result_out).speaker_toggles = result.speaker_toggles;
        }
    }
}

/// Read Apple II RAM (returns bytes in buffer, up to buf_len)
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_read_ram(
    ctx: *const IrSimContext,
    offset: c_uint,
    buf: *mut u8,
    buf_len: usize,
) -> usize {
    if ctx.is_null() || buf.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).apple2 {
        let end = ((offset as usize) + buf_len).min(ext.ram.len());
        let start = (offset as usize).min(ext.ram.len());
        let len = end - start;
        if len > 0 {
            ptr::copy_nonoverlapping(ext.ram[start..].as_ptr(), buf, len);
        }
        len
    } else {
        0
    }
}

/// Write Apple II RAM
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_write_ram(
    ctx: *mut IrSimContext,
    offset: c_uint,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        let data = slice::from_raw_parts(data, data_len);
        let end = ((offset as usize) + data_len).min(ext.ram.len());
        let len = end.saturating_sub(offset as usize);
        if len > 0 {
            ext.ram[(offset as usize)..end].copy_from_slice(&data[..len]);
        }
    }
}

/// Load Disk II slot ROM (P5 PROM boot code at $C600-$C6FF)
/// Also loads into HDL disk ROM memory if available
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_load_disk_rom(
    ctx: *mut IrSimContext,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_disk_rom(data);
        // Also load into HDL memory
        ext.load_disk_rom_into_hdl(&mut ctx.core);
    }
}

/// Load track nibble data into extension storage
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_load_track(
    ctx: *mut IrSimContext,
    track: c_uint,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_track(track as usize, data);
    }
}

/// Load track data into HDL's track_memory
/// Call this after load_track to sync data into HDL
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_load_track_into_hdl(
    ctx: *mut IrSimContext,
    track: c_uint,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.apple2 {
        ext.load_track_into_hdl(&mut ctx.core, track as usize);
    }
}

/// Get current disk track number from HDL
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_get_track(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    let ctx_ref = &*ctx;
    if let Some(ref ext) = ctx_ref.apple2 {
        ext.get_hdl_track(&ctx_ref.core) as c_uint
    } else {
        0
    }
}

/// Check if disk motor is on (from HDL signal)
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_is_motor_on(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    let ctx_ref = &*ctx;
    if let Some(ref ext) = ctx_ref.apple2 {
        if ext.is_motor_on(&ctx_ref.core) { 1 } else { 0 }
    } else {
        0
    }
}

/// Get disk byte position from HDL track_addr signal
#[no_mangle]
pub unsafe extern "C" fn apple2_ir_sim_get_disk_byte_pos(ctx: *const IrSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    let ctx_ref = &*ctx;
    // Get track_addr signal from HDL
    if let Some(track_addr_idx) = ctx_ref.core.name_to_idx.get("disk__track_addr") {
        (ctx_ref.core.signals[*track_addr_idx] as c_uint) & 0x3FFF
    } else {
        0
    }
}
