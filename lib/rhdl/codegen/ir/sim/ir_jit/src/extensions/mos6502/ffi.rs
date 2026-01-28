//! MOS6502 extension FFI functions for JIT Simulator
//!
//! C ABI exports for MOS6502-specific functionality.

use std::os::raw::{c_int, c_uint};
use std::slice;

use crate::ffi::JitSimContext;

/// Check if MOS6502 mode is active
#[no_mangle]
pub unsafe extern "C" fn jit_sim_is_mos6502_mode(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).mos6502.is_some() { 1 } else { 0 }
}

/// Load MOS6502 memory
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_load_memory(
    ctx: *mut JitSimContext,
    data: *const u8,
    data_len: usize,
    offset: c_uint,
    is_rom: c_int,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_memory(data, offset as usize, is_rom != 0);
    }
}

/// Set MOS6502 reset vector
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_set_reset_vector(
    ctx: *mut JitSimContext,
    addr: c_uint,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        ext.set_reset_vector(addr as u16);
    }
}

/// Run MOS6502 cycles (returns cycles run)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_run_cycles(
    ctx: *mut JitSimContext,
    n: c_uint,
) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        ext.run_cycles(&mut ctx.core, n as usize) as c_uint
    } else {
        0
    }
}

/// Read MOS6502 memory
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_read_memory(
    ctx: *const JitSimContext,
    addr: c_uint,
) -> u8 {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).mos6502 {
        ext.read_memory(addr as usize)
    } else {
        0
    }
}

/// Write MOS6502 memory
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_write_memory(
    ctx: *mut JitSimContext,
    addr: c_uint,
    data: u8,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        ext.write_memory(addr as usize, data);
    }
}

/// Get MOS6502 speaker toggle count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_speaker_toggles(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).mos6502 {
        ext.speaker_toggles() as c_uint
    } else {
        0
    }
}

/// Reset MOS6502 speaker toggle count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mos6502_reset_speaker_toggles(ctx: *mut JitSimContext) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        ext.reset_speaker_toggles();
    }
}
