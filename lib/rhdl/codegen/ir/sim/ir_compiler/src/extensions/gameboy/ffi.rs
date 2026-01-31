//! Game Boy extension FFI functions
//!
//! C ABI exports for Game Boy specific functionality

use std::os::raw::{c_int, c_uint, c_ulong};
use std::slice;

use crate::ffi::IrSimContext;
use super::{GbCycleResult, GbLcdState};

/// Check if Game Boy mode is active
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_is_mode(ctx: *const IrSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).gameboy.is_some() { 1 } else { 0 }
}

/// Load Game Boy ROM
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_load_rom(
    ctx: *mut IrSimContext,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_rom(data);
    }
}

/// Load Game Boy boot ROM
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_load_boot_rom(
    ctx: *mut IrSimContext,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let data = slice::from_raw_parts(data, data_len);
        ext.load_boot_rom(data);
    }
}

/// Run Game Boy cycles (returns cycles run)
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_run_cycles(
    ctx: *mut IrSimContext,
    n: c_uint,
) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let result = ext.run_gb_cycles(&mut ctx.core, n as usize);
        result.cycles_run as c_uint
    } else {
        0
    }
}

/// Run Game Boy cycles and return full result
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_run_cycles_full(
    ctx: *mut IrSimContext,
    n: c_uint,
    result_out: *mut GbCycleResult,
) {
    if ctx.is_null() || result_out.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        *result_out = ext.run_gb_cycles(&mut ctx.core, n as usize);
    }
}

/// Read from VRAM
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_read_vram(
    ctx: *const IrSimContext,
    addr: c_uint,
) -> u8 {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).gameboy {
        ext.read_vram(addr as usize)
    } else {
        0
    }
}

/// Write to VRAM
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_write_vram(
    ctx: *mut IrSimContext,
    addr: c_uint,
    data: u8,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        ext.write_vram(addr as usize, data);
    }
}

/// Read from ZPRAM (HRAM)
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_read_zpram(
    ctx: *const IrSimContext,
    addr: c_uint,
) -> u8 {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).gameboy {
        ext.read_zpram(addr as usize)
    } else {
        0
    }
}

/// Write to ZPRAM (HRAM)
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_write_zpram(
    ctx: *mut IrSimContext,
    addr: c_uint,
    data: u8,
) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        ext.write_zpram(addr as usize, data);
    }
}

/// Get framebuffer pointer
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_framebuffer(
    ctx: *const IrSimContext,
) -> *const u8 {
    if ctx.is_null() {
        return std::ptr::null();
    }
    if let Some(ref ext) = (*ctx).gameboy {
        ext.framebuffer.as_ptr()
    } else {
        std::ptr::null()
    }
}

/// Get framebuffer length
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_framebuffer_len(
    ctx: *const IrSimContext,
) -> usize {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).gameboy {
        ext.framebuffer.len()
    } else {
        0
    }
}

/// Get frame count
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_frame_count(
    ctx: *const IrSimContext,
) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref ext) = (*ctx).gameboy {
        ext.frame_count() as c_ulong
    } else {
        0
    }
}

/// Reset LCD state
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_reset_lcd(ctx: *mut IrSimContext) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        ext.reset_lcd_state();
    }
}

/// Get LCD state
#[no_mangle]
pub unsafe extern "C" fn gameboy_ir_sim_lcd_state(
    ctx: *const IrSimContext,
    state_out: *mut GbLcdState,
) {
    if ctx.is_null() || state_out.is_null() {
        return;
    }
    if let Some(ref ext) = (*ctx).gameboy {
        *state_out = ext.lcd_state;
    }
}
