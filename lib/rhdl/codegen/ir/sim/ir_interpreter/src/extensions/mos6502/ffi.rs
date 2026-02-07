//! MOS6502 extension FFI functions for IR Interpreter
//!
//! C ABI exports for MOS6502-specific functionality.

use std::os::raw::{c_int, c_uint, c_ulong};
use std::slice;

use crate::ffi::IrSimContext;

/// Check if MOS6502 mode is enabled
#[no_mangle]
pub unsafe extern "C" fn mos6502_interp_sim_is_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).mos6502.is_some() {
        1
    } else {
        0
    }
}

/// Load memory for MOS6502
#[no_mangle]
pub unsafe extern "C" fn mos6502_interp_sim_load_memory(
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
pub unsafe extern "C" fn mos6502_interp_sim_set_reset_vector(ctx: *mut IrSimContext, addr: u16) {
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
pub unsafe extern "C" fn mos6502_interp_sim_run_cycles(ctx: *mut IrSimContext, n: usize) -> usize {
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
pub unsafe extern "C" fn mos6502_interp_sim_read_memory(
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
pub unsafe extern "C" fn mos6502_interp_sim_write_memory(
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
pub unsafe extern "C" fn mos6502_interp_sim_speaker_toggles(ctx: *const IrSimContext) -> u32 {
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
pub unsafe extern "C" fn mos6502_interp_sim_reset_speaker_toggles(ctx: *mut IrSimContext) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.reset_speaker_toggles();
    }
}

/// Run MOS6502 instructions and capture (pc, opcode, sp) tuples
/// Each opcode_tuple is packed as: (pc << 16) | (opcode << 8) | sp
/// Returns the number of instructions captured
#[no_mangle]
pub unsafe extern "C" fn mos6502_interp_sim_run_instructions_with_opcodes(
    ctx: *mut IrSimContext,
    n: c_uint,
    opcodes_out: *mut c_ulong,
    opcodes_capacity: c_uint,
) -> c_uint {
    if ctx.is_null() || opcodes_out.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        let mut opcodes: Vec<(u16, u8, u8)> = Vec::with_capacity(n as usize);
        let count = ext.run_instructions_with_opcodes(&mut ctx.core, n as usize, &mut opcodes);

        // Pack results into output buffer
        let out_slice = slice::from_raw_parts_mut(opcodes_out, opcodes_capacity as usize);
        for (i, (pc, opcode, sp)) in opcodes.iter().enumerate() {
            if i >= opcodes_capacity as usize {
                break;
            }
            out_slice[i] =
                (((*pc as u32) << 16) | ((*opcode as u32) << 8) | (*sp as u32)) as c_ulong;
        }
        count as c_uint
    } else {
        0
    }
}
