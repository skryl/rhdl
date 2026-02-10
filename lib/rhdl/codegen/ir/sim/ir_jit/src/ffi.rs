//! Core C ABI function exports for the JIT simulator
//!
//! These functions are called via Fiddle from Ruby.
//! All functions use C-compatible types and follow a consistent naming convention.
//!
//! Runner and core C ABI functions are exported from this module.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uint, c_ulong};
use std::ptr;
use std::slice;

use crate::core::CoreSimulator;
use crate::extensions::{Apple2Extension, GameBoyExtension, Mos6502Extension};
use crate::vcd::{TraceMode, VcdTracer};

// ============================================================================
// Simulator Context
// ============================================================================

/// Opaque simulator context passed to all FFI functions
pub struct JitSimContext {
    pub core: CoreSimulator,
    pub apple2: Option<Apple2Extension>,
    pub gameboy: Option<GameBoyExtension>,
    pub mos6502: Option<Mos6502Extension>,
    pub tracer: VcdTracer,
}

impl JitSimContext {
    pub fn new(json: &str, sub_cycles: usize) -> Result<Self, String> {
        let core = CoreSimulator::new(json)?;

        // Detect and create extensions based on signal names
        let apple2 = if Apple2Extension::is_apple2_ir(&core.name_to_idx) {
            Some(Apple2Extension::new(&core, sub_cycles))
        } else {
            None
        };

        let gameboy = if GameBoyExtension::is_gameboy_ir(&core.name_to_idx) {
            Some(GameBoyExtension::new(&core))
        } else {
            None
        };

        let mos6502 = if Mos6502Extension::is_mos6502_ir(&core.name_to_idx) {
            Some(Mos6502Extension::new(&core))
        } else {
            None
        };

        let signal_count = core.signal_count();
        let mut signal_names = vec![String::new(); signal_count];
        for (name, &idx) in core.name_to_idx.iter() {
            if idx < signal_count && signal_names[idx].is_empty() {
                signal_names[idx] = name.clone();
            }
        }
        for (idx, name) in signal_names.iter_mut().enumerate() {
            if name.is_empty() {
                *name = format!("_sig_{}", idx);
            }
        }
        let signal_widths: Vec<usize> = (0..signal_count)
            .map(|idx| core.widths.get(idx).copied().unwrap_or(1))
            .collect();

        let mut tracer = VcdTracer::new();
        tracer.init(signal_names, signal_widths);

        Ok(Self {
            core,
            apple2,
            gameboy,
            mos6502,
            tracer,
        })
    }
}

// ============================================================================
// Normalized Runner Extension FFI
// ============================================================================

/// No extension runner detected
pub const RUNNER_KIND_NONE: c_int = 0;
/// Apple II system extension
pub const RUNNER_KIND_APPLE2: c_int = 1;
/// MOS6502 CPU extension
pub const RUNNER_KIND_MOS6502: c_int = 2;
/// Game Boy system extension
pub const RUNNER_KIND_GAMEBOY: c_int = 3;

pub const RUNNER_MEM_OP_LOAD: c_uint = 0;
pub const RUNNER_MEM_OP_READ: c_uint = 1;
pub const RUNNER_MEM_OP_WRITE: c_uint = 2;

pub const RUNNER_MEM_SPACE_MAIN: c_uint = 0;
pub const RUNNER_MEM_SPACE_ROM: c_uint = 1;
pub const RUNNER_MEM_SPACE_BOOT_ROM: c_uint = 2;
pub const RUNNER_MEM_SPACE_VRAM: c_uint = 3;
pub const RUNNER_MEM_SPACE_ZPRAM: c_uint = 4;
pub const RUNNER_MEM_SPACE_WRAM: c_uint = 5;
pub const RUNNER_MEM_SPACE_FRAMEBUFFER: c_uint = 6;

pub const RUNNER_MEM_FLAG_MAPPED: c_uint = 1;

pub const RUNNER_RUN_MODE_BASIC: c_uint = 0;
pub const RUNNER_RUN_MODE_FULL: c_uint = 1;

pub const RUNNER_CONTROL_SET_RESET_VECTOR: c_uint = 0;
pub const RUNNER_CONTROL_RESET_SPEAKER_TOGGLES: c_uint = 1;
pub const RUNNER_CONTROL_RESET_LCD: c_uint = 2;

pub const RUNNER_PROBE_KIND: c_uint = 0;
pub const RUNNER_PROBE_IS_MODE: c_uint = 1;
pub const RUNNER_PROBE_SPEAKER_TOGGLES: c_uint = 2;
pub const RUNNER_PROBE_FRAMEBUFFER_LEN: c_uint = 3;
pub const RUNNER_PROBE_FRAME_COUNT: c_uint = 4;
pub const RUNNER_PROBE_V_CNT: c_uint = 5;
pub const RUNNER_PROBE_H_CNT: c_uint = 6;
pub const RUNNER_PROBE_VBLANK_IRQ: c_uint = 7;
pub const RUNNER_PROBE_IF_R: c_uint = 8;
pub const RUNNER_PROBE_SIGNAL: c_uint = 9;
pub const RUNNER_PROBE_LCDC_ON: c_uint = 10;
pub const RUNNER_PROBE_H_DIV_CNT: c_uint = 11;
pub const RUNNER_PROBE_LCD_X: c_uint = 12;
pub const RUNNER_PROBE_LCD_Y: c_uint = 13;
pub const RUNNER_PROBE_LCD_PREV_CLKENA: c_uint = 14;
pub const RUNNER_PROBE_LCD_PREV_VSYNC: c_uint = 15;
pub const RUNNER_PROBE_LCD_FRAME_COUNT: c_uint = 16;

#[repr(C)]
pub struct RunnerCaps {
    pub kind: c_int,
    pub mem_spaces: c_uint,
    pub control_ops: c_uint,
    pub probe_ops: c_uint,
}

#[repr(C)]
pub struct RunnerRunResult {
    pub text_dirty: c_int,
    pub key_cleared: c_int,
    pub cycles_run: c_uint,
    pub speaker_toggles: c_uint,
    pub frames_completed: c_uint,
}

#[inline]
fn to_c_uint(value: usize) -> c_uint {
    value.min(u32::MAX as usize) as c_uint
}

#[inline]
const fn bit(value: c_uint) -> c_uint {
    1u32 << (value as u32)
}

#[inline]
unsafe fn write_runner_run_result(
    out: *mut RunnerRunResult,
    text_dirty: bool,
    key_cleared: bool,
    cycles_run: usize,
    speaker_toggles: u32,
    frames_completed: u32,
) {
    if out.is_null() {
        return;
    }
    (*out).text_dirty = if text_dirty { 1 } else { 0 };
    (*out).key_cleared = if key_cleared { 1 } else { 0 };
    (*out).cycles_run = to_c_uint(cycles_run);
    (*out).speaker_toggles = speaker_toggles as c_uint;
    (*out).frames_completed = frames_completed as c_uint;
}

unsafe fn runner_kind_impl(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return RUNNER_KIND_NONE;
    }
    let ctx = &*ctx;
    if ctx.apple2.is_some() {
        RUNNER_KIND_APPLE2
    } else if ctx.mos6502.is_some() {
        RUNNER_KIND_MOS6502
    } else if ctx.gameboy.is_some() {
        RUNNER_KIND_GAMEBOY
    } else {
        RUNNER_KIND_NONE
    }
}

unsafe fn runner_load_main_impl(
    ctx: *mut JitSimContext,
    data: *const u8,
    len: usize,
    offset: usize,
    is_rom: bool,
) -> usize {
    if ctx.is_null() || data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &mut *ctx;
    let bytes = slice::from_raw_parts(data, len);

    if let Some(ref mut apple2) = ctx.apple2 {
        if is_rom {
            if offset >= apple2.rom.len() {
                return 0;
            }
            let end = (offset + len).min(apple2.rom.len());
            let copy_len = end.saturating_sub(offset);
            if copy_len == 0 {
                return 0;
            }
            apple2.rom[offset..end].copy_from_slice(&bytes[..copy_len]);
            return copy_len;
        }

        if offset >= apple2.ram.len() {
            return 0;
        }
        let end = (offset + len).min(apple2.ram.len());
        let copy_len = end.saturating_sub(offset);
        if copy_len == 0 {
            return 0;
        }
        apple2.ram[offset..end].copy_from_slice(&bytes[..copy_len]);
        return copy_len;
    }

    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.load_memory(bytes, offset, is_rom);
        return len;
    }

    if let Some(ref mut gameboy) = ctx.gameboy {
        if !is_rom || offset >= gameboy.rom.len() {
            return 0;
        }
        let end = (offset + len).min(gameboy.rom.len());
        let copy_len = end.saturating_sub(offset);
        if copy_len == 0 {
            return 0;
        }
        gameboy.rom[offset..end].copy_from_slice(&bytes[..copy_len]);
        return copy_len;
    }

    0
}

unsafe fn runner_read_main_impl(
    ctx: *const JitSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
    mapped: bool,
) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;

    if let Some(ref apple2) = ctx.apple2 {
        if mapped {
            let out = slice::from_raw_parts_mut(out_data, len);
            let mut copied = 0usize;
            let mut addr = start & 0xFFFF;
            for slot in out.iter_mut() {
                *slot = if (0xD000..=0xFFFF).contains(&addr) {
                    let rom_offset = addr.wrapping_sub(0xD000);
                    if rom_offset < apple2.rom.len() {
                        apple2.rom[rom_offset]
                    } else {
                        0
                    }
                } else if addr >= 0xC000 {
                    0
                } else if addr < apple2.ram.len() {
                    apple2.ram[addr]
                } else {
                    0
                };
                addr = (addr + 1) & 0xFFFF;
                copied += 1;
            }
            return copied;
        }

        if start >= apple2.ram.len() {
            return 0;
        }
        let end = (start + len).min(apple2.ram.len());
        let copy_len = end.saturating_sub(start);
        if copy_len == 0 {
            return 0;
        }
        ptr::copy_nonoverlapping(apple2.ram[start..].as_ptr(), out_data, copy_len);
        return copy_len;
    }

    if let Some(ref mos6502) = ctx.mos6502 {
        let out = slice::from_raw_parts_mut(out_data, len);
        let mut addr = start & 0xFFFF;
        for byte in out.iter_mut() {
            *byte = mos6502.read_memory(addr);
            addr = (addr + 1) & 0xFFFF;
        }
        return len;
    }

    0
}

unsafe fn runner_write_main_impl(
    ctx: *mut JitSimContext,
    start: usize,
    data: *const u8,
    len: usize,
    mapped: bool,
) -> usize {
    if ctx.is_null() || data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &mut *ctx;
    let bytes = slice::from_raw_parts(data, len);

    if let Some(ref mut apple2) = ctx.apple2 {
        if !mapped {
            if start >= apple2.ram.len() {
                return 0;
            }
            let end = (start + len).min(apple2.ram.len());
            let copy_len = end.saturating_sub(start);
            if copy_len == 0 {
                return 0;
            }
            apple2.ram[start..end].copy_from_slice(&bytes[..copy_len]);
            return copy_len;
        }

        let mut addr = start & 0xFFFF;
        let mut written = 0usize;
        for &value in bytes.iter() {
            if addr < apple2.ram.len() && addr < 0xC000 {
                apple2.ram[addr] = value;
                written += 1;
            }
            addr = (addr + 1) & 0xFFFF;
        }
        return written;
    }

    if let Some(ref mut mos6502) = ctx.mos6502 {
        let mut addr = start & 0xFFFF;
        for &value in bytes.iter() {
            mos6502.write_memory(addr, value);
            addr = (addr + 1) & 0xFFFF;
        }
        return len;
    }

    0
}

unsafe fn runner_read_rom_impl(
    ctx: *const JitSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;

    if let Some(ref apple2) = ctx.apple2 {
        if start >= apple2.rom.len() {
            return 0;
        }
        let end = (start + len).min(apple2.rom.len());
        let copy_len = end.saturating_sub(start);
        if copy_len == 0 {
            return 0;
        }
        ptr::copy_nonoverlapping(apple2.rom[start..].as_ptr(), out_data, copy_len);
        return copy_len;
    }

    if let Some(ref gameboy) = ctx.gameboy {
        if start >= gameboy.rom.len() {
            return 0;
        }
        let end = (start + len).min(gameboy.rom.len());
        let copy_len = end.saturating_sub(start);
        if copy_len == 0 {
            return 0;
        }
        ptr::copy_nonoverlapping(gameboy.rom[start..].as_ptr(), out_data, copy_len);
        return copy_len;
    }

    0
}

unsafe fn runner_read_boot_rom_impl(
    ctx: *const JitSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref gameboy) = ctx.gameboy {
        if start >= gameboy.boot_rom.len() {
            return 0;
        }
        let end = (start + len).min(gameboy.boot_rom.len());
        let copy_len = end.saturating_sub(start);
        if copy_len == 0 {
            return 0;
        }
        ptr::copy_nonoverlapping(gameboy.boot_rom[start..].as_ptr(), out_data, copy_len);
        return copy_len;
    }
    0
}

unsafe fn runner_load_boot_rom_impl(ctx: *mut JitSimContext, data: *const u8, len: usize) -> usize {
    if ctx.is_null() || data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let bytes = slice::from_raw_parts(data, len);
        ext.load_boot_rom(bytes);
        return len;
    }
    0
}

unsafe fn runner_read_vram_impl(ctx: *const JitSimContext, start: usize, out_data: *mut u8, len: usize) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref ext) = ctx.gameboy {
        let mut copied = 0usize;
        for i in 0..len {
            let addr = start + i;
            if addr >= ext.vram.len() {
                break;
            }
            *out_data.add(i) = ext.read_vram(addr);
            copied += 1;
        }
        return copied;
    }
    0
}

unsafe fn runner_write_vram_impl(ctx: *mut JitSimContext, start: usize, data: *const u8, len: usize) -> usize {
    if ctx.is_null() || data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let bytes = slice::from_raw_parts(data, len);
        let mut written = 0usize;
        for (i, value) in bytes.iter().enumerate() {
            let addr = start + i;
            if addr >= ext.vram.len() {
                break;
            }
            ext.write_vram(addr, *value);
            written += 1;
        }
        return written;
    }
    0
}

unsafe fn runner_read_zpram_impl(
    ctx: *const JitSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref ext) = ctx.gameboy {
        let mut copied = 0usize;
        for i in 0..len {
            let addr = start + i;
            if addr >= ext.zpram.len() {
                break;
            }
            *out_data.add(i) = ext.read_zpram(addr);
            copied += 1;
        }
        return copied;
    }
    0
}

unsafe fn runner_write_zpram_impl(
    ctx: *mut JitSimContext,
    start: usize,
    data: *const u8,
    len: usize,
) -> usize {
    if ctx.is_null() || data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut ext) = ctx.gameboy {
        let bytes = slice::from_raw_parts(data, len);
        let mut written = 0usize;
        for (i, value) in bytes.iter().enumerate() {
            let addr = start + i;
            if addr >= ext.zpram.len() {
                break;
            }
            ext.write_zpram(addr, *value);
            written += 1;
        }
        return written;
    }
    0
}

unsafe fn runner_read_wram_impl(
    _ctx: *const JitSimContext,
    _start: usize,
    _out_data: *mut u8,
    _len: usize,
) -> usize {
    0
}

unsafe fn runner_write_wram_impl(
    _ctx: *mut JitSimContext,
    _start: usize,
    _data: *const u8,
    _len: usize,
) -> usize {
    0
}

unsafe fn runner_read_framebuffer_impl(
    ctx: *const JitSimContext,
    start: usize,
    out_data: *mut u8,
    len: usize,
) -> usize {
    if ctx.is_null() || out_data.is_null() || len == 0 {
        return 0;
    }
    let ctx = &*ctx;
    if let Some(ref ext) = ctx.gameboy {
        if start >= ext.framebuffer.len() {
            return 0;
        }
        let end = (start + len).min(ext.framebuffer.len());
        let copy_len = end.saturating_sub(start);
        if copy_len == 0 {
            return 0;
        }
        ptr::copy_nonoverlapping(ext.framebuffer[start..].as_ptr(), out_data, copy_len);
        return copy_len;
    }
    0
}

unsafe fn runner_set_reset_vector_impl(ctx: *mut JitSimContext, addr: c_uint) {
    if ctx.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    let vector = (addr as usize) & 0xFFFF;
    let lo = (vector & 0xFF) as u8;
    let hi = ((vector >> 8) & 0xFF) as u8;

    if let Some(ref mut mos6502) = ctx.mos6502 {
        mos6502.load_memory(&[lo, hi], 0xFFFC, true);
        return;
    }

    if let Some(ref mut apple2) = ctx.apple2 {
        if apple2.rom.len() > 0x2FFD {
            apple2.rom[0x2FFC] = lo;
            apple2.rom[0x2FFD] = hi;
        }
    }
}

unsafe fn runner_speaker_toggles_impl(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    if let Some(ref mos6502) = (*ctx).mos6502 {
        mos6502.speaker_toggles() as c_uint
    } else {
        0
    }
}

unsafe fn runner_reset_speaker_toggles_impl(ctx: *mut JitSimContext) {
    if ctx.is_null() {
        return;
    }
    if let Some(ref mut mos6502) = (*ctx).mos6502 {
        mos6502.reset_speaker_toggles();
    }
}

unsafe fn runner_run_impl(
    ctx: *mut JitSimContext,
    cycles: usize,
    key_data: u8,
    key_ready: bool,
    full_mode: bool,
    result_out: *mut RunnerRunResult,
) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    if let Some(ref mut apple2) = ctx.apple2 {
        let result = apple2.run_cpu_cycles(&mut ctx.core, cycles, key_data, key_ready);
        write_runner_run_result(
            result_out,
            result.text_dirty,
            result.key_cleared,
            result.cycles_run,
            result.speaker_toggles,
            0,
        );
        return 1;
    }

    if let Some(ref mut mos6502) = ctx.mos6502 {
        let before = mos6502.speaker_toggles();
        let cycles_run = mos6502.run_cycles(&mut ctx.core, cycles);
        let after = mos6502.speaker_toggles();
        write_runner_run_result(
            result_out,
            false,
            false,
            cycles_run,
            after.saturating_sub(before),
            0,
        );
        return 1;
    }

    if let Some(ref mut gameboy) = ctx.gameboy {
        let result = gameboy.run_gb_cycles(&mut ctx.core, cycles);
        write_runner_run_result(
            result_out,
            false,
            false,
            result.cycles_run,
            0,
            if full_mode { result.frames_completed } else { 0 },
        );
        return 1;
    }

    for _ in 0..cycles {
        ctx.core.tick();
    }
    write_runner_run_result(result_out, false, false, cycles, 0, 0);
    1
}

#[no_mangle]
pub unsafe extern "C" fn runner_get_caps(
    ctx: *const JitSimContext,
    caps_out: *mut RunnerCaps,
) -> c_int {
    if ctx.is_null() || caps_out.is_null() {
        return 0;
    }

    let kind = runner_kind_impl(ctx);
    let mut mem_spaces = 0u32;
    if kind == RUNNER_KIND_APPLE2 || kind == RUNNER_KIND_MOS6502 || kind == RUNNER_KIND_GAMEBOY {
        mem_spaces |= bit(RUNNER_MEM_SPACE_MAIN) | bit(RUNNER_MEM_SPACE_ROM);
    }
    if kind == RUNNER_KIND_GAMEBOY {
        mem_spaces |= bit(RUNNER_MEM_SPACE_BOOT_ROM)
            | bit(RUNNER_MEM_SPACE_VRAM)
            | bit(RUNNER_MEM_SPACE_ZPRAM)
            | bit(RUNNER_MEM_SPACE_FRAMEBUFFER);
    }

    let control_ops = bit(RUNNER_CONTROL_SET_RESET_VECTOR)
        | bit(RUNNER_CONTROL_RESET_SPEAKER_TOGGLES)
        | bit(RUNNER_CONTROL_RESET_LCD);

    let probe_ops = bit(RUNNER_PROBE_KIND)
        | bit(RUNNER_PROBE_IS_MODE)
        | bit(RUNNER_PROBE_SPEAKER_TOGGLES)
        | bit(RUNNER_PROBE_FRAMEBUFFER_LEN)
        | bit(RUNNER_PROBE_FRAME_COUNT)
        | bit(RUNNER_PROBE_V_CNT)
        | bit(RUNNER_PROBE_H_CNT)
        | bit(RUNNER_PROBE_VBLANK_IRQ)
        | bit(RUNNER_PROBE_IF_R)
        | bit(RUNNER_PROBE_SIGNAL)
        | bit(RUNNER_PROBE_LCDC_ON)
        | bit(RUNNER_PROBE_H_DIV_CNT)
        | bit(RUNNER_PROBE_LCD_X)
        | bit(RUNNER_PROBE_LCD_Y)
        | bit(RUNNER_PROBE_LCD_PREV_CLKENA)
        | bit(RUNNER_PROBE_LCD_PREV_VSYNC)
        | bit(RUNNER_PROBE_LCD_FRAME_COUNT);

    *caps_out = RunnerCaps {
        kind,
        mem_spaces,
        control_ops,
        probe_ops,
    };
    1
}

#[no_mangle]
pub unsafe extern "C" fn runner_mem(
    ctx: *mut JitSimContext,
    op: c_uint,
    space: c_uint,
    offset: usize,
    data: *mut u8,
    len: usize,
    flags: c_uint,
) -> usize {
    if data.is_null() || len == 0 {
        return 0;
    }

    match (op, space) {
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_MAIN) => {
            runner_load_main_impl(ctx, data as *const u8, len, offset, false)
        }
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM) => {
            runner_load_main_impl(ctx, data as *const u8, len, offset, true)
        }
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_BOOT_ROM) => {
            runner_load_boot_rom_impl(ctx, data as *const u8, len)
        }
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_VRAM) | (RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_VRAM) => {
            runner_write_vram_impl(ctx, offset, data as *const u8, len)
        }
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ZPRAM)
        | (RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_ZPRAM) => {
            runner_write_zpram_impl(ctx, offset, data as *const u8, len)
        }
        (RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_WRAM) | (RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_WRAM) => {
            runner_write_wram_impl(ctx, offset, data as *const u8, len)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_MAIN) => {
            runner_read_main_impl(ctx as *const JitSimContext, offset, data, len, (flags & RUNNER_MEM_FLAG_MAPPED) != 0)
        }
        (RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_MAIN) => {
            runner_write_main_impl(ctx, offset, data as *const u8, len, (flags & RUNNER_MEM_FLAG_MAPPED) != 0)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_ROM) => {
            runner_read_rom_impl(ctx as *const JitSimContext, offset, data, len)
        }
        (RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_ROM) => {
            runner_load_main_impl(ctx, data as *const u8, len, offset, true)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_BOOT_ROM) => {
            runner_read_boot_rom_impl(ctx as *const JitSimContext, offset, data, len)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_VRAM) => {
            runner_read_vram_impl(ctx as *const JitSimContext, offset, data, len)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_ZPRAM) => {
            runner_read_zpram_impl(ctx as *const JitSimContext, offset, data, len)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_WRAM) => {
            runner_read_wram_impl(ctx as *const JitSimContext, offset, data, len)
        }
        (RUNNER_MEM_OP_READ, RUNNER_MEM_SPACE_FRAMEBUFFER) => {
            runner_read_framebuffer_impl(ctx as *const JitSimContext, offset, data, len)
        }
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn runner_run(
    ctx: *mut JitSimContext,
    cycles: c_uint,
    key_data: u8,
    key_ready: c_int,
    mode: c_uint,
    result_out: *mut RunnerRunResult,
) -> c_int {
    runner_run_impl(
        ctx,
        cycles as usize,
        key_data,
        key_ready != 0,
        mode == RUNNER_RUN_MODE_FULL,
        result_out,
    )
}

#[no_mangle]
pub unsafe extern "C" fn runner_control(
    ctx: *mut JitSimContext,
    op: c_uint,
    arg0: c_uint,
    _arg1: c_uint,
) -> c_int {
    if ctx.is_null() {
        return 0;
    }

    match op {
        RUNNER_CONTROL_SET_RESET_VECTOR => {
            runner_set_reset_vector_impl(ctx, arg0);
            1
        }
        RUNNER_CONTROL_RESET_SPEAKER_TOGGLES => {
            runner_reset_speaker_toggles_impl(ctx);
            1
        }
        RUNNER_CONTROL_RESET_LCD => {
            let ctx = &mut *ctx;
            if let Some(ref mut ext) = ctx.gameboy {
                ext.reset_lcd_state();
            }
            1
        }
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn runner_probe(ctx: *const JitSimContext, op: c_uint, arg0: c_uint) -> u64 {
    if ctx.is_null() {
        return 0;
    }
    let ctx_ref = &*ctx;

    match op {
        RUNNER_PROBE_KIND => runner_kind_impl(ctx) as u64,
        RUNNER_PROBE_IS_MODE => {
            if runner_kind_impl(ctx) == RUNNER_KIND_NONE {
                0
            } else {
                1
            }
        }
        RUNNER_PROBE_SPEAKER_TOGGLES => runner_speaker_toggles_impl(ctx) as u64,
        RUNNER_PROBE_FRAMEBUFFER_LEN => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.framebuffer.len() as u64)
            .unwrap_or(0),
        RUNNER_PROBE_FRAME_COUNT => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.frame_count() as u64)
            .unwrap_or(0),
        RUNNER_PROBE_V_CNT => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.ppu_v_cnt_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.ppu_v_cnt_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_H_CNT => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.ppu_h_cnt_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.ppu_h_cnt_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_VBLANK_IRQ => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.ppu_vblank_irq_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.ppu_vblank_irq_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_IF_R => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.if_r_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.if_r_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_SIGNAL => {
            let idx = arg0 as usize;
            if idx < ctx_ref.core.signals.len() {
                ctx_ref.core.signals[idx]
            } else {
                0
            }
        }
        RUNNER_PROBE_LCDC_ON => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.ppu_lcdc_on_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.ppu_lcdc_on_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_H_DIV_CNT => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| {
                if ext.ppu_h_div_cnt_idx < ctx_ref.core.signals.len() {
                    ctx_ref.core.signals[ext.ppu_h_div_cnt_idx]
                } else {
                    0
                }
            })
            .unwrap_or(0),
        RUNNER_PROBE_LCD_X => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.lcd_state.x as u64)
            .unwrap_or(0),
        RUNNER_PROBE_LCD_Y => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.lcd_state.y as u64)
            .unwrap_or(0),
        RUNNER_PROBE_LCD_PREV_CLKENA => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.lcd_state.prev_clkena as u64)
            .unwrap_or(0),
        RUNNER_PROBE_LCD_PREV_VSYNC => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.lcd_state.prev_vsync as u64)
            .unwrap_or(0),
        RUNNER_PROBE_LCD_FRAME_COUNT => ctx_ref
            .gameboy
            .as_ref()
            .map(|ext| ext.lcd_state.frame_count)
            .unwrap_or(0),
        _ => 0,
    }
}

// ============================================================================
// Core FFI Functions
// ============================================================================

/// Create a new JIT simulator from JSON
unsafe fn ir_sim_create(
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
unsafe fn ir_sim_destroy(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

/// Free an error string
unsafe fn ir_sim_free_error(error: *mut c_char) {
    if !error.is_null() {
        drop(CString::from_raw(error));
    }
}

/// Free a string returned by jit_sim functions
unsafe fn ir_sim_free_string(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Allocate memory in the simulator WASM heap for JS interop
unsafe fn ir_sim_wasm_alloc(size: usize) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(size.max(1));
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

/// Free memory previously allocated with ir_sim_wasm_alloc
unsafe fn ir_sim_wasm_dealloc(ptr: *mut u8, size: usize) {
    if ptr.is_null() {
        return;
    }
    let cap = size.max(1);
    drop(Vec::<u8>::from_raw_parts(ptr, 0, cap));
}

/// Poke a signal value
unsafe fn ir_sim_poke(
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
unsafe fn ir_sim_peek(ctx: *const JitSimContext, name: *const c_char) -> c_ulong {
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
unsafe fn ir_sim_has_signal(
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

    if ctx.core.name_to_idx.contains_key(name) {
        1
    } else {
        0
    }
}

/// Get signal index by name
unsafe fn ir_sim_get_signal_idx(
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

    ctx.core
        .get_signal_idx(name)
        .map(|i| i as c_int)
        .unwrap_or(-1)
}

/// Get memory index by name
#[no_mangle]
pub unsafe extern "C" fn jit_sim_get_memory_idx(
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

    ctx.core.memory_name_to_idx.get(name).map(|&i| i as c_int).unwrap_or(-1)
}

/// Bulk write bytes into a memory array by index
/// Values are stored as u64 (byte value in low 8 bits).
#[no_mangle]
pub unsafe extern "C" fn jit_sim_mem_write_bytes(
    ctx: *mut JitSimContext,
    mem_idx: c_uint,
    offset: c_uint,
    data: *const u8,
    data_len: usize,
) {
    if ctx.is_null() || data.is_null() {
        return;
    }
    let ctx = &mut *ctx;
    let mem_idx = mem_idx as usize;
    if mem_idx >= ctx.core.memory_arrays.len() {
        return;
    }

    let mem = &mut ctx.core.memory_arrays[mem_idx];
    if mem.is_empty() {
        return;
    }

    let start = offset as usize;
    let depth = mem.len();
    let data = slice::from_raw_parts(data, data_len);

    for (i, &b) in data.iter().enumerate() {
        let addr = (start + i) % depth;
        mem[addr] = b as u64;
    }
}

/// Poke by index
unsafe fn ir_sim_poke_by_idx(ctx: *mut JitSimContext, idx: c_uint, value: c_ulong) {
    if !ctx.is_null() {
        (*ctx).core.poke_by_idx(idx as usize, value as u64);
    }
}

/// Peek by index
unsafe fn ir_sim_peek_by_idx(ctx: *const JitSimContext, idx: c_uint) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.peek_by_idx(idx as usize) as c_ulong
}

/// Evaluate combinational logic
unsafe fn ir_sim_evaluate(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.evaluate();
    }
}

/// Tick (evaluate + clock edge detection + register update)
unsafe fn ir_sim_tick(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick();
    }
}

/// Tick with forced edge detection using prev_clock_values set by caller
/// Use set_prev_clock before calling this to control edge detection
unsafe fn ir_sim_tick_forced(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.tick_forced();
    }
}

/// Set previous clock value for a clock index (for forced edge detection)
unsafe fn ir_sim_set_prev_clock(
    ctx: *mut JitSimContext,
    clock_list_idx: c_uint,
    value: c_ulong,
) {
    if !ctx.is_null() {
        let ctx = &mut *ctx;
        let idx = clock_list_idx as usize;
        if idx < ctx.core.prev_clock_values.len() {
            ctx.core.prev_clock_values[idx] = value;
        }
    }
}

/// Get clock list index for a signal index
unsafe fn ir_sim_get_clock_list_idx(
    ctx: *const JitSimContext,
    signal_idx: c_uint,
) -> c_int {
    if ctx.is_null() {
        return -1;
    }
    let sig_idx = signal_idx as usize;
    match (*ctx)
        .core
        .clock_indices
        .iter()
        .position(|&ci| ci == sig_idx)
    {
        Some(pos) => pos as c_int,
        None => -1,
    }
}

/// Run N ticks
unsafe fn ir_sim_run_ticks(ctx: *mut JitSimContext, n: c_uint) {
    if !ctx.is_null() {
        (*ctx).core.run_ticks(n as usize);
    }
}

/// Reset all signals to initial values
unsafe fn ir_sim_reset(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).core.reset();
    }
}

/// Get signal count
unsafe fn ir_sim_signal_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.signal_count() as c_uint
}

/// Get register count
unsafe fn ir_sim_reg_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).core.reg_count() as c_uint
}

/// Get input names (comma-separated, caller must free)
unsafe fn ir_sim_input_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.input_names.join(",");
    CString::new(names).unwrap().into_raw()
}

/// Get output names (comma-separated, caller must free)
unsafe fn ir_sim_output_names(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let names = (*ctx).core.output_names.join(",");
    CString::new(names).unwrap().into_raw()
}

// ============================================================================
// VCD Tracing FFI Functions
// ============================================================================

/// Start VCD tracing in buffer mode
/// Returns 0 on success, -1 on error
unsafe fn ir_sim_trace_start(ctx: *mut JitSimContext) -> c_int {
    if ctx.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    ctx.tracer.set_mode(TraceMode::Buffer);
    ctx.tracer.start();
    0
}

/// Start VCD tracing in streaming mode to a file
/// Returns 0 on success, -1 on error
unsafe fn ir_sim_trace_start_streaming(
    ctx: *mut JitSimContext,
    path: *const c_char,
) -> c_int {
    if ctx.is_null() || path.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let path = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    if ctx.tracer.open_file(path).is_err() {
        return -1;
    }
    ctx.tracer.start();
    0
}

/// Stop VCD tracing
unsafe fn ir_sim_trace_stop(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.stop();
    }
}

/// Check if tracing is enabled
unsafe fn ir_sim_trace_enabled(ctx: *const JitSimContext) -> c_int {
    if ctx.is_null() {
        return 0;
    }
    if (*ctx).tracer.is_enabled() {
        1
    } else {
        0
    }
}

/// Capture current signal values (call each simulation step)
unsafe fn ir_sim_trace_capture(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        let ctx = &mut *ctx;
        ctx.tracer.capture(&ctx.core.signals);
    }
}

/// Add a signal to trace by name
/// Returns 0 if signal found and added, -1 if not found
unsafe fn ir_sim_trace_add_signal(
    ctx: *mut JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    if ctx.tracer.add_signal_by_name(name) {
        0
    } else {
        -1
    }
}

/// Add signals matching a pattern (substring match)
/// Returns the number of signals added
unsafe fn ir_sim_trace_add_signals_matching(
    ctx: *mut JitSimContext,
    pattern: *const c_char,
) -> c_int {
    if ctx.is_null() || pattern.is_null() {
        return 0;
    }
    let ctx = &mut *ctx;
    let pattern = match CStr::from_ptr(pattern).to_str() {
        Ok(s) => s,
        Err(_) => return 0,
    };

    ctx.tracer.add_signals_matching(pattern) as c_int
}

/// Trace all signals
unsafe fn ir_sim_trace_all_signals(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.trace_all_signals();
    }
}

/// Clear the set of traced signals
unsafe fn ir_sim_trace_clear_signals(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.clear_signals();
    }
}

/// Get VCD output as string (caller must free with ir_sim_free_string)
unsafe fn ir_sim_trace_to_vcd(ctx: *const JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let vcd = (*ctx).tracer.to_vcd();
    CString::new(vcd).unwrap().into_raw()
}

/// Get only new live VCD chunk since the last call (caller must free with ir_sim_free_string)
unsafe fn ir_sim_trace_take_live_vcd(ctx: *mut JitSimContext) -> *mut c_char {
    if ctx.is_null() {
        return ptr::null_mut();
    }
    let chunk = (*ctx).tracer.take_live_chunk();
    CString::new(chunk).unwrap().into_raw()
}

/// Save VCD output to a file
/// Returns 0 on success, -1 on error
unsafe fn ir_sim_trace_save_vcd(
    ctx: *const JitSimContext,
    path: *const c_char,
) -> c_int {
    if ctx.is_null() || path.is_null() {
        return -1;
    }
    let path = match CStr::from_ptr(path).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    match (*ctx).tracer.save_vcd(path) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Clear all buffered trace data
unsafe fn ir_sim_trace_clear(ctx: *mut JitSimContext) {
    if !ctx.is_null() {
        (*ctx).tracer.clear();
    }
}

/// Get the number of recorded changes
unsafe fn ir_sim_trace_change_count(ctx: *const JitSimContext) -> c_ulong {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).tracer.change_count() as c_ulong
}

/// Get the number of traced signals
unsafe fn ir_sim_trace_signal_count(ctx: *const JitSimContext) -> c_uint {
    if ctx.is_null() {
        return 0;
    }
    (*ctx).tracer.stats().traced_signals as c_uint
}

/// Set the VCD timescale (e.g., "1ns", "1ps")
unsafe fn ir_sim_trace_set_timescale(
    ctx: *mut JitSimContext,
    timescale: *const c_char,
) -> c_int {
    if ctx.is_null() || timescale.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let timescale = match CStr::from_ptr(timescale).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.tracer.set_timescale(timescale);
    0
}

/// Set the VCD module name
unsafe fn ir_sim_trace_set_module_name(
    ctx: *mut JitSimContext,
    name: *const c_char,
) -> c_int {
    if ctx.is_null() || name.is_null() {
        return -1;
    }
    let ctx = &mut *ctx;
    let name = match CStr::from_ptr(name).to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };

    ctx.tracer.set_module_name(name);
    0
}

// ============================================================================
// Consolidated Core ABI (sim_*)
// ============================================================================

pub const SIM_CAP_SIGNAL_INDEX: c_uint = 1 << 0;
pub const SIM_CAP_FORCED_CLOCK: c_uint = 1 << 1;
pub const SIM_CAP_TRACE: c_uint = 1 << 2;
pub const SIM_CAP_TRACE_STREAMING: c_uint = 1 << 3;
pub const SIM_CAP_RUNNER: c_uint = 1 << 4;

#[repr(C)]
pub struct SimCaps {
    pub flags: c_uint,
}

pub const SIM_SIGNAL_HAS: c_uint = 0;
pub const SIM_SIGNAL_GET_INDEX: c_uint = 1;
pub const SIM_SIGNAL_PEEK: c_uint = 2;
pub const SIM_SIGNAL_POKE: c_uint = 3;
pub const SIM_SIGNAL_PEEK_INDEX: c_uint = 4;
pub const SIM_SIGNAL_POKE_INDEX: c_uint = 5;

pub const SIM_EXEC_EVALUATE: c_uint = 0;
pub const SIM_EXEC_TICK: c_uint = 1;
pub const SIM_EXEC_TICK_FORCED: c_uint = 2;
pub const SIM_EXEC_SET_PREV_CLOCK: c_uint = 3;
pub const SIM_EXEC_GET_CLOCK_LIST_IDX: c_uint = 4;
pub const SIM_EXEC_RESET: c_uint = 5;
pub const SIM_EXEC_RUN_TICKS: c_uint = 6;
pub const SIM_EXEC_SIGNAL_COUNT: c_uint = 7;
pub const SIM_EXEC_REG_COUNT: c_uint = 8;
pub const SIM_EXEC_COMPILE: c_uint = 9;
pub const SIM_EXEC_IS_COMPILED: c_uint = 10;

pub const SIM_TRACE_START: c_uint = 0;
pub const SIM_TRACE_START_STREAMING: c_uint = 1;
pub const SIM_TRACE_STOP: c_uint = 2;
pub const SIM_TRACE_ENABLED: c_uint = 3;
pub const SIM_TRACE_CAPTURE: c_uint = 4;
pub const SIM_TRACE_ADD_SIGNAL: c_uint = 5;
pub const SIM_TRACE_ADD_SIGNALS_MATCHING: c_uint = 6;
pub const SIM_TRACE_ALL_SIGNALS: c_uint = 7;
pub const SIM_TRACE_CLEAR_SIGNALS: c_uint = 8;
pub const SIM_TRACE_CLEAR: c_uint = 9;
pub const SIM_TRACE_CHANGE_COUNT: c_uint = 10;
pub const SIM_TRACE_SIGNAL_COUNT: c_uint = 11;
pub const SIM_TRACE_SET_TIMESCALE: c_uint = 12;
pub const SIM_TRACE_SET_MODULE_NAME: c_uint = 13;
pub const SIM_TRACE_SAVE_VCD: c_uint = 14;

pub const SIM_BLOB_INPUT_NAMES: c_uint = 0;
pub const SIM_BLOB_OUTPUT_NAMES: c_uint = 1;
pub const SIM_BLOB_TRACE_TO_VCD: c_uint = 2;
pub const SIM_BLOB_TRACE_TAKE_LIVE_VCD: c_uint = 3;
pub const SIM_BLOB_GENERATED_CODE: c_uint = 4;

#[inline]
unsafe fn write_out_ulong(out: *mut c_ulong, value: c_ulong) {
    if !out.is_null() {
        *out = value;
    }
}

#[inline]
unsafe fn copy_blob(out_ptr: *mut u8, out_len: usize, bytes: &[u8]) -> usize {
    let required = bytes.len();
    if !out_ptr.is_null() && out_len != 0 && required != 0 {
        let copy_len = required.min(out_len);
        ptr::copy_nonoverlapping(bytes.as_ptr(), out_ptr, copy_len);
    }
    required
}

#[inline]
unsafe fn take_owned_c_string(ptr: *mut c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    let text = CStr::from_ptr(ptr).to_string_lossy().into_owned();
    ir_sim_free_string(ptr);
    Some(text)
}

#[no_mangle]
pub unsafe extern "C" fn sim_create(
    json: *const c_char,
    json_len: usize,
    sub_cycles: c_uint,
    error_out: *mut *mut c_char,
) -> *mut JitSimContext {
    ir_sim_create(json, json_len, sub_cycles, error_out)
}

#[no_mangle]
pub unsafe extern "C" fn sim_destroy(ctx: *mut JitSimContext) {
    ir_sim_destroy(ctx);
}

#[no_mangle]
pub unsafe extern "C" fn sim_free_error(error: *mut c_char) {
    ir_sim_free_error(error);
}

#[no_mangle]
pub unsafe extern "C" fn sim_wasm_alloc(size: usize) -> *mut u8 {
    ir_sim_wasm_alloc(size)
}

#[no_mangle]
pub unsafe extern "C" fn sim_wasm_dealloc(ptr: *mut u8, size: usize) {
    ir_sim_wasm_dealloc(ptr, size);
}

#[no_mangle]
pub unsafe extern "C" fn sim_get_caps(ctx: *const JitSimContext, caps_out: *mut SimCaps) -> c_int {
    if ctx.is_null() || caps_out.is_null() {
        return 0;
    }
    *caps_out = SimCaps {
        flags: SIM_CAP_SIGNAL_INDEX
            | SIM_CAP_FORCED_CLOCK
            | SIM_CAP_TRACE
            | SIM_CAP_TRACE_STREAMING
            | SIM_CAP_RUNNER,
    };
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_signal(
    ctx: *mut JitSimContext,
    op: c_uint,
    name: *const c_char,
    idx: c_uint,
    value: c_ulong,
    out_value: *mut c_ulong,
) -> c_int {
    if ctx.is_null() {
        return 0;
    }

    match op {
        SIM_SIGNAL_HAS => {
            write_out_ulong(out_value, if ir_sim_has_signal(ctx as *const JitSimContext, name) != 0 { 1 } else { 0 });
            1
        }
        SIM_SIGNAL_GET_INDEX => {
            let index = ir_sim_get_signal_idx(ctx as *const JitSimContext, name);
            if index < 0 {
                0
            } else {
                write_out_ulong(out_value, index as c_ulong);
                1
            }
        }
        SIM_SIGNAL_PEEK => {
            write_out_ulong(out_value, ir_sim_peek(ctx as *const JitSimContext, name));
            1
        }
        SIM_SIGNAL_POKE => {
            if ir_sim_poke(ctx, name, value) == 0 {
                1
            } else {
                0
            }
        }
        SIM_SIGNAL_PEEK_INDEX => {
            write_out_ulong(out_value, ir_sim_peek_by_idx(ctx as *const JitSimContext, idx));
            1
        }
        SIM_SIGNAL_POKE_INDEX => {
            ir_sim_poke_by_idx(ctx, idx, value);
            1
        }
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_exec(
    ctx: *mut JitSimContext,
    op: c_uint,
    arg0: c_ulong,
    arg1: c_ulong,
    out_value: *mut c_ulong,
    _error_out: *mut *mut c_char,
) -> c_int {
    if ctx.is_null() {
        return 0;
    }

    match op {
        SIM_EXEC_EVALUATE => {
            ir_sim_evaluate(ctx);
            1
        }
        SIM_EXEC_TICK => {
            ir_sim_tick(ctx);
            1
        }
        SIM_EXEC_TICK_FORCED => {
            ir_sim_tick_forced(ctx);
            1
        }
        SIM_EXEC_SET_PREV_CLOCK => {
            ir_sim_set_prev_clock(ctx, arg0 as c_uint, arg1);
            1
        }
        SIM_EXEC_GET_CLOCK_LIST_IDX => {
            let idx = ir_sim_get_clock_list_idx(ctx as *const JitSimContext, arg0 as c_uint);
            if idx < 0 {
                0
            } else {
                write_out_ulong(out_value, idx as c_ulong);
                1
            }
        }
        SIM_EXEC_RESET => {
            ir_sim_reset(ctx);
            1
        }
        SIM_EXEC_RUN_TICKS => {
            ir_sim_run_ticks(ctx, arg0 as c_uint);
            1
        }
        SIM_EXEC_SIGNAL_COUNT => {
            write_out_ulong(out_value, ir_sim_signal_count(ctx as *const JitSimContext) as c_ulong);
            1
        }
        SIM_EXEC_REG_COUNT => {
            write_out_ulong(out_value, ir_sim_reg_count(ctx as *const JitSimContext) as c_ulong);
            1
        }
        SIM_EXEC_COMPILE => 0,
        SIM_EXEC_IS_COMPILED => {
            write_out_ulong(out_value, 0);
            1
        }
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_trace(
    ctx: *mut JitSimContext,
    op: c_uint,
    str_arg: *const c_char,
    out_value: *mut c_ulong,
) -> c_int {
    if ctx.is_null() {
        return 0;
    }

    match op {
        SIM_TRACE_START => (ir_sim_trace_start(ctx) == 0) as c_int,
        SIM_TRACE_START_STREAMING => (ir_sim_trace_start_streaming(ctx, str_arg) == 0) as c_int,
        SIM_TRACE_STOP => {
            ir_sim_trace_stop(ctx);
            1
        }
        SIM_TRACE_ENABLED => {
            write_out_ulong(out_value, if ir_sim_trace_enabled(ctx as *const JitSimContext) != 0 { 1 } else { 0 });
            1
        }
        SIM_TRACE_CAPTURE => {
            ir_sim_trace_capture(ctx);
            1
        }
        SIM_TRACE_ADD_SIGNAL => (ir_sim_trace_add_signal(ctx, str_arg) == 0) as c_int,
        SIM_TRACE_ADD_SIGNALS_MATCHING => {
            write_out_ulong(out_value, ir_sim_trace_add_signals_matching(ctx, str_arg) as c_ulong);
            1
        }
        SIM_TRACE_ALL_SIGNALS => {
            ir_sim_trace_all_signals(ctx);
            1
        }
        SIM_TRACE_CLEAR_SIGNALS => {
            ir_sim_trace_clear_signals(ctx);
            1
        }
        SIM_TRACE_CLEAR => {
            ir_sim_trace_clear(ctx);
            1
        }
        SIM_TRACE_CHANGE_COUNT => {
            write_out_ulong(out_value, ir_sim_trace_change_count(ctx as *const JitSimContext));
            1
        }
        SIM_TRACE_SIGNAL_COUNT => {
            write_out_ulong(out_value, ir_sim_trace_signal_count(ctx as *const JitSimContext) as c_ulong);
            1
        }
        SIM_TRACE_SET_TIMESCALE => (ir_sim_trace_set_timescale(ctx, str_arg) == 0) as c_int,
        SIM_TRACE_SET_MODULE_NAME => (ir_sim_trace_set_module_name(ctx, str_arg) == 0) as c_int,
        SIM_TRACE_SAVE_VCD => (ir_sim_trace_save_vcd(ctx as *const JitSimContext, str_arg) == 0) as c_int,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_blob(
    ctx: *mut JitSimContext,
    op: c_uint,
    out_ptr: *mut u8,
    out_len: usize,
) -> usize {
    if ctx.is_null() {
        return 0;
    }

    let text = match op {
        SIM_BLOB_INPUT_NAMES => take_owned_c_string(ir_sim_input_names(ctx as *const JitSimContext)),
        SIM_BLOB_OUTPUT_NAMES => take_owned_c_string(ir_sim_output_names(ctx as *const JitSimContext)),
        SIM_BLOB_TRACE_TO_VCD => take_owned_c_string(ir_sim_trace_to_vcd(ctx as *const JitSimContext)),
        SIM_BLOB_TRACE_TAKE_LIVE_VCD => take_owned_c_string(ir_sim_trace_take_live_vcd(ctx)),
        SIM_BLOB_GENERATED_CODE => None,
        _ => None,
    };

    match text {
        Some(s) => copy_blob(out_ptr, out_len, s.as_bytes()),
        None => 0,
    }
}
