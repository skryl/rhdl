//! MOS6502 extension FFI functions for IR Interpreter
//!
//! C ABI exports for MOS6502-specific functionality.

use std::os::raw::c_int;
use std::slice;

use crate::ffi::IrSimContext;

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
