//! Apple II extension FFI functions for JIT Simulator
//!
//! C ABI exports for Apple II-specific functionality.

use std::os::raw::{c_int, c_uint};
use std::ptr;
use std::slice;

use crate::ffi::JitSimContext;

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
pub unsafe extern "C" fn apple2_jit_sim_is_mode(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).apple2.is_some() { 1 } else { 0 }
}

/// Load Apple II ROM
#[no_mangle]
pub unsafe extern "C" fn apple2_jit_sim_load_rom(
    ctx: *mut JitSimContext,
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
pub unsafe extern "C" fn apple2_jit_sim_load_ram(
    ctx: *mut JitSimContext,
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

/// Run Apple II CPU cycles
#[no_mangle]
pub unsafe extern "C" fn apple2_jit_sim_run_cpu_cycles(
    ctx: *mut JitSimContext,
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

/// Read Apple II RAM
#[no_mangle]
pub unsafe extern "C" fn apple2_jit_sim_read_ram(
    ctx: *const JitSimContext,
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

/// Read mapped Apple II memory (full 64KB CPU-visible address space)
#[no_mangle]
pub unsafe extern "C" fn apple2_jit_sim_read_memory(
    ctx: *const JitSimContext,
    offset: c_uint,
    buf: *mut u8,
    buf_len: usize,
) -> usize {
    if ctx.is_null() || buf.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).apple2 {
        let mut addr = offset as usize & 0xFFFF;
        for i in 0..buf_len {
            let byte = if addr >= 0xD000 {
                let rom_idx = addr - 0xD000;
                ext.rom.get(rom_idx).copied().unwrap_or(0)
            } else if addr >= 0xC000 {
                0
            } else {
                ext.ram.get(addr).copied().unwrap_or(0)
            };
            *buf.add(i) = byte;
            addr = (addr + 1) & 0xFFFF;
        }
        buf_len
    } else {
        0
    }
}

/// Write Apple II RAM
#[no_mangle]
pub unsafe extern "C" fn apple2_jit_sim_write_ram(
    ctx: *mut JitSimContext,
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
