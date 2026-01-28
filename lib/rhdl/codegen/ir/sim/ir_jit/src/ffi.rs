//! Core C ABI function exports for the JIT simulator
//!
//! These functions are called via Fiddle from Ruby.

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
pub struct JitSimContext {
    pub core: CoreSimulator,
    pub apple2: Option<Apple2Extension>,
    pub mos6502: Option<Mos6502Extension>,
}

impl JitSimContext {
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

/// Create a new JIT simulator from JSON
#[no_mangle]
pub unsafe extern "C" fn jit_sim_create(
    json: *const c_char,
    json_len: usize,
    sub_cycles: c_uint,
    error_out: *mut *mut c_char,
) -> *mut JitSimContext {
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

    match JitSimContext::new(json_str, sub_cycles as usize) {
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

/// Destroy a JIT simulator
#[no_mangle]
pub unsafe extern "C" fn jit_sim_destroy(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

/// Free an error string
#[no_mangle]
pub unsafe extern "C" fn jit_sim_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

/// Free a string returned by jit_sim functions
#[no_mangle]
pub unsafe extern "C" fn jit_sim_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Poke a signal value
#[no_mangle]
pub unsafe extern "C" fn jit_sim_poke(
    ctx: *mut JitSimContext,
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
#[no_mangle]
pub unsafe extern "C" fn jit_sim_peek(
    ctx: *const JitSimContext,
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
pub unsafe extern "C" fn jit_sim_has_signal(
    ctx: *const JitSimContext,
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

/// Get signal index by name
#[no_mangle]
pub unsafe extern "C" fn jit_sim_get_signal_idx(
    ctx: *const JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &*ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.core.get_signal_idx(name).map(|i| i as c_int).unwrap_or(-1)
}

/// Poke by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_poke_by_idx(
    ctx: *mut JitSimContext,
    idx: c_uint,
    value: c_ulong,
) {
    if !ctx.is_null() {
        (*ctx).core.poke_by_idx(idx as usize, value as u64);
    }
}

/// Peek by index
#[no_mangle]
pub unsafe extern "C" fn jit_sim_peek_by_idx(
    ctx: *const JitSimContext,
    idx: c_uint,
) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.peek_by_idx(idx as usize) as c_ulong
}

/// Evaluate combinational logic
#[no_mangle]
pub unsafe extern "C" fn jit_sim_evaluate(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.evaluate();
    }
}

/// Tick (evaluate + clock edge detection + register update)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_tick(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick();
    }
}

/// Run N ticks
#[no_mangle]
pub unsafe extern "C" fn jit_sim_run_ticks(ctx: *mut JitSimContext, n: c_uint) {
    if !ctx.is_null() {
        (*ctx).core.run_ticks(n as usize);
    }
}

/// Reset all signals to initial values
#[no_mangle]
pub unsafe extern "C" fn jit_sim_reset(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.reset();
    }
}

/// Get signal count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_signal_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.signal_count() as c_uint
}

/// Get register count
#[no_mangle]
pub unsafe extern "C" fn jit_sim_reg_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.reg_count() as c_uint
}

/// Get input names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_input_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.input_names.join(",");
    CString::new(names).unwrap().into_raw()
}

/// Get output names (comma-separated, caller must free)
#[no_mangle]
pub unsafe extern "C" fn jit_sim_output_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.output_names.join(",");
    CString::new(names).unwrap().into_raw()
}

// ============================================================================
// MOS6502 Extension FFI Functions
// ============================================================================

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

// ============================================================================
// Apple II Extension FFI Functions
// ============================================================================

/// Check if Apple II mode is active
#[no_mangle]
pub unsafe extern "C" fn jit_sim_is_apple2_mode(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).apple2.is_some() { 1 } else { 0 }
}

/// Load Apple II ROM
#[no_mangle]
pub unsafe extern "C" fn jit_sim_apple2_load_rom(
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
pub unsafe extern "C" fn jit_sim_apple2_load_ram(
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

/// Result struct for Apple II run_cpu_cycles
#[repr(C)]
pub struct Apple2CycleResult {
    pub text_dirty: c_int,
    pub key_cleared: c_int,
    pub cycles_run: c_uint,
    pub speaker_toggles: c_uint,
}

/// Run Apple II CPU cycles
#[no_mangle]
pub unsafe extern "C" fn jit_sim_apple2_run_cpu_cycles(
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
pub unsafe extern "C" fn jit_sim_apple2_read_ram(
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

/// Write Apple II RAM
#[no_mangle]
pub unsafe extern "C" fn jit_sim_apple2_write_ram(
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
