//! MOS6502 extension FFI functions
//!
//! C ABI exports for MOS6502 CPU specific functionality

use std::os::raw::{c_int, c_uint, c_ulong};
use std::slice;

use crate::ffi::IrSimContext;

/// Check if MOS6502 mode is active
#[no_mangle]
pub unsafe extern "C" fn mos6502_ir_sim_is_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).mos6502.is_some() { 1 } else { 0 }
}

/// Load MOS6502 memory
#[no_mangle]
pub unsafe extern "C" fn mos6502_ir_sim_load_memory(
    ctx: *mut IrSimContext,
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
pub unsafe extern "C" fn mos6502_ir_sim_set_reset_vector(
    ctx: *mut IrSimContext,
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
pub unsafe extern "C" fn mos6502_ir_sim_run_cycles(
    ctx: *mut IrSimContext,
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
pub unsafe extern "C" fn mos6502_ir_sim_read_memory(
    ctx: *const IrSimContext,
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
pub unsafe extern "C" fn mos6502_ir_sim_write_memory(
    ctx: *mut IrSimContext,
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
pub unsafe extern "C" fn mos6502_ir_sim_speaker_toggles(ctx: *const IrSimContext) -> c_uint {
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
pub unsafe extern "C" fn mos6502_ir_sim_reset_speaker_toggles(ctx: *mut IrSimContext) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.mos6502 {
        ext.reset_speaker_toggles();
    }
}

/// Run MOS6502 instructions and capture (pc, opcode, sp) tuples
/// Each opcode_tuple is packed as: (pc << 16) | (opcode << 8) | sp
/// Returns the number of instructions captured
#[no_mangle]
pub unsafe extern "C" fn mos6502_ir_sim_run_instructions_with_opcodes(
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
            out_slice[i] = ((*pc as u64) << 16) | ((*opcode as u64) << 8) | (*sp as u64);
        }
        count as c_uint
    } else {
        0
    }
}
