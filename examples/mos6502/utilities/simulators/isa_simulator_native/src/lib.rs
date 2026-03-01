//! MOS 6502 ISA-Level Simulator with C ABI exports
//! High-performance instruction-level simulator for the MOS 6502 CPU
//!
//! Memory Model:
//! - Internal 64KB memory for fast CPU access
//! - Optional host callbacks for memory-mapped I/O ($C000-$CFFF on Apple II)
//! - External devices can read/write internal memory via peek/poke methods
//!
//! Performance optimizations:
//! - Keyboard and speaker state cached in Rust to avoid FFI calls
//! - CPU state copied to local variables in tight loop
//! - I/O region $C100-$CFFF served from internal memory (ROM)
//! - Only disk controller ($C0E0-$C0EF) requires host callbacks

use std::cell::RefCell;
use std::ffi::CString;
use std::os::raw::{c_char, c_int, c_uint, c_ulonglong, c_void};
use std::ptr;
use std::slice;

// Status flag bit positions
const FLAG_C: u8 = 0; // Carry
const FLAG_Z: u8 = 1; // Zero
const FLAG_I: u8 = 2; // Interrupt Disable
const FLAG_D: u8 = 3; // Decimal Mode
const FLAG_V: u8 = 6; // Overflow
const FLAG_N: u8 = 7; // Negative

// Interrupt vectors
const RESET_VECTOR: u16 = 0xFFFC;
const IRQ_VECTOR: u16 = 0xFFFE;

// Apple II I/O page (actual soft switches)
const IO_PAGE_START: u16 = 0xC000;
const IO_PAGE_END: u16 = 0xC0FF;

// Disk II controller range (slot 6)
const DISK_IO_START: u16 = 0xC0E0;
const DISK_IO_END: u16 = 0xC0EF;

type IoReadCallback = extern "C" fn(addr: c_uint, user_data: *mut c_void) -> c_uint;
type IoWriteCallback = extern "C" fn(addr: c_uint, value: c_uint, user_data: *mut c_void);

#[derive(Clone, Copy)]
struct IoCallbacks {
    read: Option<IoReadCallback>,
    write: Option<IoWriteCallback>,
    user_data: *mut c_void,
}

impl Default for IoCallbacks {
    fn default() -> Self {
        Self {
            read: None,
            write: None,
            user_data: ptr::null_mut(),
        }
    }
}

/// MOS 6502 CPU state (core without memory)
pub struct Cpu6502Core {
    // Registers
    pub a: u8,   // Accumulator
    pub x: u8,   // X index register
    pub y: u8,   // Y index register
    pub sp: u8,  // Stack pointer
    pub pc: u16, // Program counter
    pub p: u8,   // Status register

    // State
    pub cycles: u64,
    pub halted: bool,
}

impl Cpu6502Core {
    pub fn new() -> Self {
        Self {
            a: 0,
            x: 0,
            y: 0,
            sp: 0xFD,
            pc: 0,
            p: 0x24, // Unused flag set, Interrupt disable set
            cycles: 0,
            halted: false,
        }
    }

    pub fn reset(&mut self) {
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.sp = 0xFD;
        self.p = 0x24;
        self.cycles = 0;
        self.halted = false;
    }

    // Flag accessors
    #[inline]
    pub fn flag(&self, flag: u8) -> u8 {
        (self.p >> flag) & 1
    }

    #[inline]
    pub fn set_flag(&mut self, flag: u8, value: bool) {
        if value {
            self.p |= 1 << flag;
        } else {
            self.p &= !(1 << flag);
        }
    }

    #[inline]
    fn set_nz(&mut self, value: u8) -> u8 {
        self.set_flag(FLAG_Z, value == 0);
        self.set_flag(FLAG_N, value & 0x80 != 0);
        value
    }

    // ALU operations
    fn do_adc(&mut self, value: u8) {
        if self.flag(FLAG_D) == 1 {
            // Decimal mode
            let mut lo = (self.a & 0x0F) as i16 + (value & 0x0F) as i16 + self.flag(FLAG_C) as i16;
            let mut hi = (self.a >> 4) as i16 + (value >> 4) as i16;
            if lo > 9 {
                hi += 1;
                lo -= 10;
            }
            if hi > 9 {
                self.set_flag(FLAG_C, true);
                hi -= 10;
            } else {
                self.set_flag(FLAG_C, false);
            }
            let result = ((hi << 4) | (lo & 0x0F)) as u8;
            self.set_flag(FLAG_Z, result == 0);
            self.set_flag(FLAG_N, result & 0x80 != 0);
            self.a = result;
        } else {
            // Binary mode
            let sum = self.a as u16 + value as u16 + self.flag(FLAG_C) as u16;
            let overflow = (!(self.a ^ value) & (self.a ^ sum as u8) & 0x80) != 0;
            self.set_flag(FLAG_C, sum > 0xFF);
            self.set_flag(FLAG_V, overflow);
            self.a = self.set_nz(sum as u8);
        }
    }

    fn do_sbc(&mut self, value: u8) {
        if self.flag(FLAG_D) == 1 {
            // Decimal mode
            let mut lo = (self.a & 0x0F) as i16 - (value & 0x0F) as i16 - (1 - self.flag(FLAG_C)) as i16;
            let mut hi = (self.a >> 4) as i16 - (value >> 4) as i16;
            if lo < 0 {
                lo += 10;
                hi -= 1;
            }
            if hi < 0 {
                hi += 10;
                self.set_flag(FLAG_C, false);
            } else {
                self.set_flag(FLAG_C, true);
            }
            let result = ((hi << 4) | (lo & 0x0F)) as u8;
            self.set_flag(FLAG_Z, result == 0);
            self.set_flag(FLAG_N, result & 0x80 != 0);
            self.a = result;
        } else {
            // Binary mode (SBC is ADC with inverted operand)
            self.do_adc(value ^ 0xFF);
        }
    }

    #[inline]
    fn do_cmp(&mut self, reg_value: u8, mem_value: u8) {
        let result = reg_value.wrapping_sub(mem_value);
        self.set_flag(FLAG_C, reg_value >= mem_value);
        self.set_nz(result);
    }

    #[inline]
    fn do_asl(&mut self, value: u8) -> u8 {
        self.set_flag(FLAG_C, value & 0x80 != 0);
        self.set_nz(value << 1)
    }

    #[inline]
    fn do_lsr(&mut self, value: u8) -> u8 {
        self.set_flag(FLAG_C, value & 1 != 0);
        self.set_nz(value >> 1)
    }

    #[inline]
    fn do_rol(&mut self, value: u8) -> u8 {
        let carry = self.flag(FLAG_C);
        self.set_flag(FLAG_C, value & 0x80 != 0);
        self.set_nz((value << 1) | carry)
    }

    #[inline]
    fn do_ror(&mut self, value: u8) -> u8 {
        let carry = self.flag(FLAG_C);
        self.set_flag(FLAG_C, value & 1 != 0);
        self.set_nz((value >> 1) | (carry << 7))
    }
}

// ============================================================================
// Ruby bindings wrapper with hybrid memory model
// ============================================================================

/// Apple II I/O state (cached in Rust for performance)
struct AppleIIState {
    // Keyboard state
    key_value: u8,      // Last key pressed (ASCII, without high bit)
    key_ready: bool,    // Key available to read

    // Speaker state
    speaker_toggles: u64,  // Count of speaker toggles

    // Video soft switches
    video_text: bool,   // TEXT/GRAPHICS mode
    video_mixed: bool,  // MIXED mode
    video_page2: bool,  // PAGE2 select
    video_hires: bool,  // HIRES mode
}

impl Default for AppleIIState {
    fn default() -> Self {
        Self {
            key_value: 0,
            key_ready: false,
            speaker_toggles: 0,
            video_text: true,
            video_mixed: false,
            video_page2: false,
            video_hires: false,
        }
    }
}

/// Native CPU simulator with internal memory and optional host I/O callbacks
///
/// Memory access:
/// - RAM/ROM ($0000-$BFFF, $D000-$FFFF): Fast internal memory
/// - I/O page ($C000-$C0FF): Handled in Rust except disk controller
/// - Expansion ROM ($C100-$CFFF): Fast internal memory
/// - Disk controller ($C0E0-$C0EF): Calls host I/O callbacks
///
/// External devices can access internal memory via peek/poke methods.
pub struct RubyCpu {
    cpu: RefCell<Cpu6502Core>,
    memory: RefCell<Vec<u8>>,           // Internal 64KB memory
    io_callbacks: RefCell<IoCallbacks>, // Optional host callbacks for disk controller
    io_state: RefCell<AppleIIState>,    // Cached Apple II I/O state
}

impl Default for RubyCpu {
    fn default() -> Self {
        Self {
            cpu: RefCell::new(Cpu6502Core::new()),
            memory: RefCell::new(vec![0; 0x10000]),
            io_callbacks: RefCell::new(IoCallbacks::default()),
            io_state: RefCell::new(AppleIIState::default()),
        }
    }
}

impl RubyCpu {
    // Memory operations - optimized I/O handling
    // Most I/O is handled directly in Rust, only disk controller calls Ruby
    #[inline]
    fn read(&self, addr: u16) -> u8 {
        // Fast path: addresses outside I/O page use internal memory
        if addr < IO_PAGE_START || addr > IO_PAGE_END {
            return self.memory.borrow()[addr as usize];
        }

        // I/O page ($C000-$C0FF) - handle in Rust except disk controller
        self.handle_io_read(addr)
    }

    #[inline]
    fn write(&self, addr: u16, value: u8) {
        // Fast path: addresses outside I/O page use internal memory
        if addr < IO_PAGE_START || addr > IO_PAGE_END {
            self.memory.borrow_mut()[addr as usize] = value;
            return;
        }

        // I/O page ($C000-$C0FF) - handle in Rust except disk controller
        self.handle_io_write(addr, value);
    }

    // Handle I/O page reads ($C000-$C0FF)
    #[inline]
    fn handle_io_read(&self, addr: u16) -> u8 {
        // Disk controller - must call Ruby
        if addr >= DISK_IO_START && addr <= DISK_IO_END {
            return self.call_ruby_io_read(addr);
        }

        let io = self.io_state.borrow();
        match addr {
            // Keyboard data ($C000)
            0xC000 => {
                if io.key_ready {
                    io.key_value | 0x80
                } else {
                    0x00
                }
            }
            // Keyboard strobe clear ($C010)
            0xC010 => {
                drop(io);
                self.io_state.borrow_mut().key_ready = false;
                0x00
            }
            // Speaker toggle ($C030)
            0xC030 => {
                drop(io);
                self.io_state.borrow_mut().speaker_toggles += 1;
                0x00
            }
            // Video soft switches (reading also sets them)
            0xC050 => { drop(io); self.io_state.borrow_mut().video_text = false; 0x00 }
            0xC051 => { drop(io); self.io_state.borrow_mut().video_text = true; 0x00 }
            0xC052 => { drop(io); self.io_state.borrow_mut().video_mixed = false; 0x00 }
            0xC053 => { drop(io); self.io_state.borrow_mut().video_mixed = true; 0x00 }
            0xC054 => { drop(io); self.io_state.borrow_mut().video_page2 = false; 0x00 }
            0xC055 => { drop(io); self.io_state.borrow_mut().video_page2 = true; 0x00 }
            0xC056 => { drop(io); self.io_state.borrow_mut().video_hires = false; 0x00 }
            0xC057 => { drop(io); self.io_state.borrow_mut().video_hires = true; 0x00 }
            // Other I/O addresses return 0 or call Ruby handler
            _ => {
                drop(io);
                // Check if we have a handler for unknown I/O
                self.call_ruby_io_read(addr)
            }
        }
    }

    // Handle I/O page writes ($C000-$C0FF)
    #[inline]
    fn handle_io_write(&self, addr: u16, value: u8) {
        // Disk controller - must call Ruby
        if addr >= DISK_IO_START && addr <= DISK_IO_END {
            self.call_ruby_io_write(addr, value);
            return;
        }

        match addr {
            // Keyboard strobe ($C010)
            0xC010 => {
                self.io_state.borrow_mut().key_ready = false;
            }
            // Speaker toggle ($C030)
            0xC030 => {
                self.io_state.borrow_mut().speaker_toggles += 1;
            }
            // Video soft switches
            0xC050 => { self.io_state.borrow_mut().video_text = false; }
            0xC051 => { self.io_state.borrow_mut().video_text = true; }
            0xC052 => { self.io_state.borrow_mut().video_mixed = false; }
            0xC053 => { self.io_state.borrow_mut().video_mixed = true; }
            0xC054 => { self.io_state.borrow_mut().video_page2 = false; }
            0xC055 => { self.io_state.borrow_mut().video_page2 = true; }
            0xC056 => { self.io_state.borrow_mut().video_hires = false; }
            0xC057 => { self.io_state.borrow_mut().video_hires = true; }
            // Other writes may need Ruby handler
            _ => {
                self.call_ruby_io_write(addr, value);
            }
        }
    }

    // Call host I/O handler for disk access
    #[inline]
    fn call_ruby_io_read(&self, addr: u16) -> u8 {
        let callbacks = *self.io_callbacks.borrow();
        if let Some(read_cb) = callbacks.read {
            return (read_cb(addr as c_uint, callbacks.user_data) & 0xFF) as u8;
        }
        // Fall through to internal memory for expansion ROM
        self.memory.borrow()[addr as usize]
    }

    // Call host I/O handler for disk access
    #[inline]
    fn call_ruby_io_write(&self, addr: u16, value: u8) {
        let callbacks = *self.io_callbacks.borrow();
        if let Some(write_cb) = callbacks.write {
            write_cb(addr as c_uint, value as c_uint, callbacks.user_data);
        }
    }

    fn read_word(&self, addr: u16) -> u16 {
        let lo = self.read(addr) as u16;
        let hi = self.read(addr.wrapping_add(1)) as u16;
        (hi << 8) | lo
    }

    // Fetch operations
    fn fetch_byte(&self) -> u8 {
        let pc = self.cpu.borrow().pc;
        let byte = self.read(pc);
        self.cpu.borrow_mut().pc = pc.wrapping_add(1);
        byte
    }

    fn fetch_word(&self) -> u16 {
        let lo = self.fetch_byte() as u16;
        let hi = self.fetch_byte() as u16;
        (hi << 8) | lo
    }

    // Stack operations
    fn push_byte(&self, value: u8) {
        let sp = self.cpu.borrow().sp;
        self.write(0x100 + sp as u16, value);
        self.cpu.borrow_mut().sp = sp.wrapping_sub(1);
    }

    fn pull_byte(&self) -> u8 {
        let sp = self.cpu.borrow().sp.wrapping_add(1);
        self.cpu.borrow_mut().sp = sp;
        self.read(0x100 + sp as u16)
    }

    fn push_word(&self, value: u16) {
        self.push_byte((value >> 8) as u8);
        self.push_byte(value as u8);
    }

    fn pull_word(&self) -> u16 {
        let lo = self.pull_byte() as u16;
        let hi = self.pull_byte() as u16;
        (hi << 8) | lo
    }

    // Addressing modes - return address
    fn addr_immediate(&self) -> u16 {
        let pc = self.cpu.borrow().pc;
        self.cpu.borrow_mut().pc = pc.wrapping_add(1);
        pc
    }

    fn addr_zero_page(&self) -> u16 {
        self.fetch_byte() as u16
    }

    fn addr_zero_page_x(&self) -> u16 {
        let x = self.cpu.borrow().x;
        self.fetch_byte().wrapping_add(x) as u16
    }

    fn addr_zero_page_y(&self) -> u16 {
        let y = self.cpu.borrow().y;
        self.fetch_byte().wrapping_add(y) as u16
    }

    fn addr_absolute(&self) -> u16 {
        self.fetch_word()
    }

    fn addr_absolute_x(&self, check_page_cross: bool) -> u16 {
        let base = self.fetch_word();
        let x = self.cpu.borrow().x;
        let addr = base.wrapping_add(x as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cpu.borrow_mut().cycles += 1;
        }
        addr
    }

    fn addr_absolute_y(&self, check_page_cross: bool) -> u16 {
        let base = self.fetch_word();
        let y = self.cpu.borrow().y;
        let addr = base.wrapping_add(y as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cpu.borrow_mut().cycles += 1;
        }
        addr
    }

    fn addr_indirect(&self) -> u16 {
        let ptr = self.fetch_word();
        // 6502 indirect JMP bug: if ptr is at xxFF, high byte comes from xx00
        let lo = self.read(ptr);
        let hi_addr = if ptr & 0xFF == 0xFF {
            ptr & 0xFF00
        } else {
            ptr + 1
        };
        let hi = self.read(hi_addr);
        ((hi as u16) << 8) | lo as u16
    }

    fn addr_indexed_indirect(&self) -> u16 {
        // (zp,X)
        let x = self.cpu.borrow().x;
        let ptr = self.fetch_byte().wrapping_add(x);
        let lo = self.read(ptr as u16);
        let hi = self.read(ptr.wrapping_add(1) as u16);
        ((hi as u16) << 8) | lo as u16
    }

    fn addr_indirect_indexed(&self, check_page_cross: bool) -> u16 {
        // (zp),Y
        let ptr = self.fetch_byte();
        let lo = self.read(ptr as u16);
        let hi = self.read(ptr.wrapping_add(1) as u16);
        let base = ((hi as u16) << 8) | lo as u16;
        let y = self.cpu.borrow().y;
        let addr = base.wrapping_add(y as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cpu.borrow_mut().cycles += 1;
        }
        addr
    }

    fn addr_relative(&self) -> u16 {
        let offset = self.fetch_byte() as i8 as i16;
        let pc = self.cpu.borrow().pc;
        pc.wrapping_add(offset as u16)
    }

    fn branch_if(&self, condition: bool) {
        let target = self.addr_relative();
        if condition {
            let pc = self.cpu.borrow().pc;
            self.cpu.borrow_mut().cycles += 1;
            if (pc & 0xFF00) != (target & 0xFF00) {
                self.cpu.borrow_mut().cycles += 1;
            }
            self.cpu.borrow_mut().pc = target;
        }
    }

    /// Execute one instruction and return cycles taken
    fn step_internal(&self) -> u64 {
        if self.cpu.borrow().halted {
            return 0;
        }

        let opcode = self.fetch_byte();
        self.execute(opcode);
        self.cpu.borrow().cycles
    }

    fn execute(&self, opcode: u8) {
        match opcode {
            // ADC - Add with Carry
            0x69 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x65 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x75 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x6D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x7D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x79 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x61 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }
            0x71 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.cpu.borrow_mut().do_adc(v); }

            // SBC - Subtract with Carry
            0xE9 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xE5 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xF5 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xED => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xFD => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xF9 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xE1 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }
            0xF1 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.cpu.borrow_mut().do_sbc(v); }

            // AND - Logical AND
            0x29 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x25 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x35 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x2D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x3D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x39 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x21 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }
            0x31 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a & v); self.cpu.borrow_mut().a = r; }

            // ORA - Logical OR
            0x09 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x05 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x15 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x0D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x1D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x19 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x01 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }
            0x11 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a | v); self.cpu.borrow_mut().a = r; }

            // EOR - Exclusive OR
            0x49 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x45 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x55 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x4D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x5D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x59 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x41 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }
            0x51 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a ^ v); self.cpu.borrow_mut().a = r; }

            // CMP - Compare Accumulator
            0xC9 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xC5 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xD5 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xCD => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xDD => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xD9 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xC1 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }
            0xD1 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let a = self.cpu.borrow().a; self.cpu.borrow_mut().do_cmp(a, v); }

            // CPX - Compare X Register
            0xE0 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let x = self.cpu.borrow().x; self.cpu.borrow_mut().do_cmp(x, v); }
            0xE4 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let x = self.cpu.borrow().x; self.cpu.borrow_mut().do_cmp(x, v); }
            0xEC => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let x = self.cpu.borrow().x; self.cpu.borrow_mut().do_cmp(x, v); }

            // CPY - Compare Y Register
            0xC0 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let y = self.cpu.borrow().y; self.cpu.borrow_mut().do_cmp(y, v); }
            0xC4 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let y = self.cpu.borrow().y; self.cpu.borrow_mut().do_cmp(y, v); }
            0xCC => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let y = self.cpu.borrow().y; self.cpu.borrow_mut().do_cmp(y, v); }

            // BIT - Bit Test
            0x24 => {
                self.cpu.borrow_mut().cycles += 3;
                let addr = self.addr_zero_page();
                let value = self.read(addr);
                let a = self.cpu.borrow().a;
                self.cpu.borrow_mut().set_flag(FLAG_Z, (a & value) == 0);
                self.cpu.borrow_mut().set_flag(FLAG_N, value & 0x80 != 0);
                self.cpu.borrow_mut().set_flag(FLAG_V, value & 0x40 != 0);
            }
            0x2C => {
                self.cpu.borrow_mut().cycles += 4;
                let addr = self.addr_absolute();
                let value = self.read(addr);
                let a = self.cpu.borrow().a;
                self.cpu.borrow_mut().set_flag(FLAG_Z, (a & value) == 0);
                self.cpu.borrow_mut().set_flag(FLAG_N, value & 0x80 != 0);
                self.cpu.borrow_mut().set_flag(FLAG_V, value & 0x40 != 0);
            }

            // LDA - Load Accumulator
            0xA9 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xA5 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xB5 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xAD => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xBD => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xB9 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xA1 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }
            0xB1 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }

            // LDX - Load X Register
            0xA2 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }
            0xA6 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }
            0xB6 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_y(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }
            0xAE => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }
            0xBE => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }

            // LDY - Load Y Register
            0xA0 => { self.cpu.borrow_mut().cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }
            0xA4 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }
            0xB4 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }
            0xAC => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }
            0xBC => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }

            // STA - Store Accumulator
            0x85 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x95 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x8D => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x9D => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_absolute_x(false); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x99 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_absolute_y(false); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x81 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indexed_indirect(); let a = self.cpu.borrow().a; self.write(addr, a); }
            0x91 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_indirect_indexed(false); let a = self.cpu.borrow().a; self.write(addr, a); }

            // STX - Store X Register
            0x86 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let x = self.cpu.borrow().x; self.write(addr, x); }
            0x96 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_y(); let x = self.cpu.borrow().x; self.write(addr, x); }
            0x8E => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let x = self.cpu.borrow().x; self.write(addr, x); }

            // STY - Store Y Register
            0x84 => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_zero_page(); let y = self.cpu.borrow().y; self.write(addr, y); }
            0x94 => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_zero_page_x(); let y = self.cpu.borrow().y; self.write(addr, y); }
            0x8C => { self.cpu.borrow_mut().cycles += 4; let addr = self.addr_absolute(); let y = self.cpu.borrow().y; self.write(addr, y); }

            // Register Transfers
            0xAA => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a); self.cpu.borrow_mut().x = r; }       // TAX
            0x8A => { self.cpu.borrow_mut().cycles += 2; let x = self.cpu.borrow().x; let r = self.cpu.borrow_mut().set_nz(x); self.cpu.borrow_mut().a = r; }       // TXA
            0xA8 => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().set_nz(a); self.cpu.borrow_mut().y = r; }       // TAY
            0x98 => { self.cpu.borrow_mut().cycles += 2; let y = self.cpu.borrow().y; let r = self.cpu.borrow_mut().set_nz(y); self.cpu.borrow_mut().a = r; }       // TYA
            0xBA => { self.cpu.borrow_mut().cycles += 2; let sp = self.cpu.borrow().sp; let r = self.cpu.borrow_mut().set_nz(sp); self.cpu.borrow_mut().x = r; }    // TSX
            0x9A => { self.cpu.borrow_mut().cycles += 2; let x = self.cpu.borrow().x; self.cpu.borrow_mut().sp = x; }                               // TXS (no flags)

            // Increment/Decrement Register
            0xE8 => { self.cpu.borrow_mut().cycles += 2; let x = self.cpu.borrow().x; let v = x.wrapping_add(1); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }  // INX
            0xCA => { self.cpu.borrow_mut().cycles += 2; let x = self.cpu.borrow().x; let v = x.wrapping_sub(1); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().x = r; }  // DEX
            0xC8 => { self.cpu.borrow_mut().cycles += 2; let y = self.cpu.borrow().y; let v = y.wrapping_add(1); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }  // INY
            0x88 => { self.cpu.borrow_mut().cycles += 2; let y = self.cpu.borrow().y; let v = y.wrapping_sub(1); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().y = r; }  // DEY

            // Increment Memory
            0xE6 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr).wrapping_add(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xF6 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr).wrapping_add(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xEE => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr).wrapping_add(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xFE => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr).wrapping_add(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }

            // Decrement Memory
            0xC6 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr).wrapping_sub(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xD6 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr).wrapping_sub(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xCE => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr).wrapping_sub(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }
            0xDE => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr).wrapping_sub(1); self.cpu.borrow_mut().set_nz(v); self.write(addr, v); }

            // ASL - Arithmetic Shift Left
            0x0A => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().do_asl(a); self.cpu.borrow_mut().a = r; }
            0x06 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_asl(v); self.write(addr, r); }
            0x16 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_asl(v); self.write(addr, r); }
            0x0E => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_asl(v); self.write(addr, r); }
            0x1E => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.cpu.borrow_mut().do_asl(v); self.write(addr, r); }

            // LSR - Logical Shift Right
            0x4A => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().do_lsr(a); self.cpu.borrow_mut().a = r; }
            0x46 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_lsr(v); self.write(addr, r); }
            0x56 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_lsr(v); self.write(addr, r); }
            0x4E => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_lsr(v); self.write(addr, r); }
            0x5E => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.cpu.borrow_mut().do_lsr(v); self.write(addr, r); }

            // ROL - Rotate Left
            0x2A => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().do_rol(a); self.cpu.borrow_mut().a = r; }
            0x26 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_rol(v); self.write(addr, r); }
            0x36 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_rol(v); self.write(addr, r); }
            0x2E => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_rol(v); self.write(addr, r); }
            0x3E => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.cpu.borrow_mut().do_rol(v); self.write(addr, r); }

            // ROR - Rotate Right
            0x6A => { self.cpu.borrow_mut().cycles += 2; let a = self.cpu.borrow().a; let r = self.cpu.borrow_mut().do_ror(a); self.cpu.borrow_mut().a = r; }
            0x66 => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_ror(v); self.write(addr, r); }
            0x76 => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_ror(v); self.write(addr, r); }
            0x6E => { self.cpu.borrow_mut().cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.cpu.borrow_mut().do_ror(v); self.write(addr, r); }
            0x7E => { self.cpu.borrow_mut().cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.cpu.borrow_mut().do_ror(v); self.write(addr, r); }

            // Branches
            0x10 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_N) == 0; self.branch_if(cond); }  // BPL
            0x30 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_N) == 1; self.branch_if(cond); }  // BMI
            0x50 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_V) == 0; self.branch_if(cond); }  // BVC
            0x70 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_V) == 1; self.branch_if(cond); }  // BVS
            0x90 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_C) == 0; self.branch_if(cond); }  // BCC
            0xB0 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_C) == 1; self.branch_if(cond); }  // BCS
            0xD0 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_Z) == 0; self.branch_if(cond); }  // BNE
            0xF0 => { self.cpu.borrow_mut().cycles += 2; let cond = self.cpu.borrow().flag(FLAG_Z) == 1; self.branch_if(cond); }  // BEQ

            // JMP - Jump
            0x4C => { self.cpu.borrow_mut().cycles += 3; let addr = self.addr_absolute(); self.cpu.borrow_mut().pc = addr; }
            0x6C => { self.cpu.borrow_mut().cycles += 5; let addr = self.addr_indirect(); self.cpu.borrow_mut().pc = addr; }

            // JSR - Jump to Subroutine
            0x20 => {
                self.cpu.borrow_mut().cycles += 6;
                let target = self.addr_absolute();
                let pc = self.cpu.borrow().pc.wrapping_sub(1);
                self.push_word(pc);
                self.cpu.borrow_mut().pc = target;
            }

            // RTS - Return from Subroutine
            0x60 => {
                self.cpu.borrow_mut().cycles += 6;
                let addr = self.pull_word().wrapping_add(1);
                self.cpu.borrow_mut().pc = addr;
            }

            // RTI - Return from Interrupt
            0x40 => {
                self.cpu.borrow_mut().cycles += 6;
                let p = self.pull_byte() | 0x20; // Unused flag always 1
                self.cpu.borrow_mut().p = p;
                let pc = self.pull_word();
                self.cpu.borrow_mut().pc = pc;
            }

            // Stack Operations
            0x48 => { self.cpu.borrow_mut().cycles += 3; let a = self.cpu.borrow().a; self.push_byte(a); }              // PHA
            0x08 => { self.cpu.borrow_mut().cycles += 3; let p = self.cpu.borrow().p | 0x10; self.push_byte(p); }       // PHP (B flag set when pushed)
            0x68 => { self.cpu.borrow_mut().cycles += 4; let v = self.pull_byte(); let r = self.cpu.borrow_mut().set_nz(v); self.cpu.borrow_mut().a = r; }  // PLA
            0x28 => { self.cpu.borrow_mut().cycles += 4; let p = self.pull_byte() | 0x20; self.cpu.borrow_mut().p = p; }               // PLP

            // Flag Operations
            0x18 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_C, false); }  // CLC
            0x38 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_C, true); }   // SEC
            0x58 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_I, false); }  // CLI
            0x78 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_I, true); }   // SEI
            0xB8 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_V, false); }  // CLV
            0xD8 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_D, false); }  // CLD
            0xF8 => { self.cpu.borrow_mut().cycles += 2; self.cpu.borrow_mut().set_flag(FLAG_D, true); }   // SED

            // NOP
            0xEA => { self.cpu.borrow_mut().cycles += 2; }

            // BRK - Break
            0x00 => {
                self.cpu.borrow_mut().cycles += 7;
                let pc = self.cpu.borrow().pc.wrapping_add(1); // BRK skips a byte
                self.cpu.borrow_mut().pc = pc;
                let pc = self.cpu.borrow().pc;
                self.push_word(pc);
                let p = self.cpu.borrow().p | 0x10; // B flag set when pushed
                self.push_byte(p);
                self.cpu.borrow_mut().set_flag(FLAG_I, true);
                let new_pc = self.read_word(IRQ_VECTOR);
                self.cpu.borrow_mut().pc = new_pc;
            }

            // Illegal opcode - halt
            _ => {
                self.cpu.borrow_mut().halted = true;
                self.cpu.borrow_mut().cycles += 2;
            }
        }
    }

    /// Load program bytes into memory
    fn load_program_internal(&self, bytes: &[u8], addr: u16) {
        for (i, &byte) in bytes.iter().enumerate() {
            self.memory.borrow_mut()[addr.wrapping_add(i as u16) as usize] = byte;
        }
        // Set reset vector
        let mut mem = self.memory.borrow_mut();
        mem[RESET_VECTOR as usize] = (addr & 0xFF) as u8;
        mem[(RESET_VECTOR + 1) as usize] = ((addr >> 8) & 0xFF) as u8;
    }
}


// Native method implementations
impl RubyCpu {
    fn set_io_callbacks(
        &self,
        read_cb: Option<IoReadCallback>,
        write_cb: Option<IoWriteCallback>,
        user_data: *mut c_void,
    ) {
        *self.io_callbacks.borrow_mut() = IoCallbacks {
            read: read_cb,
            write: write_cb,
            user_data,
        };
    }

    fn reset(&self) {
        self.cpu.borrow_mut().reset();
        // Read reset vector from internal memory
        let pc = self.read_word(RESET_VECTOR);
        self.cpu.borrow_mut().pc = pc;
    }

    fn step(&self) -> u64 {
        self.step_internal()
    }

    fn run(&self, max_instructions: u32) -> u32 {
        let mut count = 0;
        while count < max_instructions && !self.cpu.borrow().halted {
            self.step_internal();
            count += 1;
        }
        count
    }

    fn run_cycles(&self, target_cycles: u64) -> u64 {
        let start_cycles = self.cpu.borrow().cycles;
        while (self.cpu.borrow().cycles - start_cycles) < target_cycles && !self.cpu.borrow().halted {
            self.step_internal();
        }
        self.cpu.borrow().cycles - start_cycles
    }

    fn a(&self) -> u8 {
        self.cpu.borrow().a
    }

    fn x(&self) -> u8 {
        self.cpu.borrow().x
    }

    fn y(&self) -> u8 {
        self.cpu.borrow().y
    }

    fn sp(&self) -> u8 {
        self.cpu.borrow().sp
    }

    fn pc(&self) -> u16 {
        self.cpu.borrow().pc
    }

    fn p(&self) -> u8 {
        self.cpu.borrow().p
    }

    fn cycles(&self) -> u64 {
        self.cpu.borrow().cycles
    }

    fn halted(&self) -> bool {
        self.cpu.borrow().halted
    }

    fn set_a(&self, v: u8) {
        self.cpu.borrow_mut().a = v;
    }

    fn set_x(&self, v: u8) {
        self.cpu.borrow_mut().x = v;
    }

    fn set_y(&self, v: u8) {
        self.cpu.borrow_mut().y = v;
    }

    fn set_sp(&self, v: u8) {
        self.cpu.borrow_mut().sp = v;
    }

    fn set_pc(&self, v: u16) {
        self.cpu.borrow_mut().pc = v;
    }

    fn set_p(&self, v: u8) {
        self.cpu.borrow_mut().p = v | 0x20;
    }

    fn set_cycles(&self, v: u64) {
        self.cpu.borrow_mut().cycles = v;
    }

    fn set_halted(&self, v: bool) {
        self.cpu.borrow_mut().halted = v;
    }

    fn has_io_handler(&self) -> bool {
        let callbacks = *self.io_callbacks.borrow();
        callbacks.read.is_some() || callbacks.write.is_some()
    }

    fn inject_key(&self, ascii: u8) {
        let mut io = self.io_state.borrow_mut();
        io.key_value = ascii & 0x7F;
        io.key_ready = true;
    }

    fn key_ready(&self) -> bool {
        self.io_state.borrow().key_ready
    }

    fn speaker_toggles(&self) -> u64 {
        self.io_state.borrow().speaker_toggles
    }

    fn reset_speaker_toggles(&self) {
        self.io_state.borrow_mut().speaker_toggles = 0;
    }

    fn video_state_bits(&self) -> u32 {
        let io = self.io_state.borrow();
        let mut bits = 0u32;
        if io.video_text {
            bits |= VIDEO_STATE_TEXT;
        }
        if io.video_mixed {
            bits |= VIDEO_STATE_MIXED;
        }
        if io.video_page2 {
            bits |= VIDEO_STATE_PAGE2;
        }
        if io.video_hires {
            bits |= VIDEO_STATE_HIRES;
        }
        bits
    }

    fn set_video_state_bits(&self, bits: u32) {
        let mut io = self.io_state.borrow_mut();
        io.video_text = (bits & VIDEO_STATE_TEXT) != 0;
        io.video_mixed = (bits & VIDEO_STATE_MIXED) != 0;
        io.video_page2 = (bits & VIDEO_STATE_PAGE2) != 0;
        io.video_hires = (bits & VIDEO_STATE_HIRES) != 0;
    }

    // Fast hires rendering to braille characters
    // chars_wide: target width in braille chars (default 140 for 80-column terminal)
    // invert: if true, invert pixels (white on black)
    fn render_hires_braille(&self, chars_wide: u32, invert: bool) -> String {
        const HIRES_WIDTH: u32 = 280;
        const HIRES_HEIGHT: u32 = 192;

        let mem = self.memory.borrow();
        let io = self.io_state.borrow();

        // Determine hires page base address
        let base: u16 = if io.video_page2 { 0x4000 } else { 0x2000 };

        // Braille characters are 2 dots wide × 4 dots tall
        let chars_wide = chars_wide.max(1);
        let chars_tall = (HIRES_HEIGHT + 3) / 4; // ceil division

        // Scale factors (fixed point for speed: multiply by 65536)
        let x_scale_fp = ((HIRES_WIDTH as u64) << 16) / ((chars_wide * 2) as u64);
        let y_scale_fp = ((HIRES_HEIGHT as u64) << 16) / ((chars_tall * 4) as u64);

        // Braille dot bit positions (Unicode mapping)
        // Dot 1 (0x01) Dot 4 (0x08)
        // Dot 2 (0x02) Dot 5 (0x10)
        // Dot 3 (0x04) Dot 6 (0x20)
        // Dot 7 (0x40) Dot 8 (0x80)
        const DOT_MAP: [[u8; 2]; 4] = [
            [0x01, 0x08], // row 0
            [0x02, 0x10], // row 1
            [0x04, 0x20], // row 2
            [0x40, 0x80], // row 3
        ];

        // Pre-compute line addresses for all 192 rows
        let mut line_addrs: [u16; 192] = [0; 192];
        for row in 0..192 {
            let section = row / 64;
            let row_in_section = row % 64;
            let group = row_in_section / 8;
            let line_in_group = row_in_section % 8;
            line_addrs[row] = base
                + (line_in_group as u16 * 0x400)
                + (group as u16 * 0x80)
                + (section as u16 * 0x28);
        }

        // Pre-compute which bit to extract for each x coordinate (0-279)
        // Each byte contains 7 pixels (bit 7 is palette select, bits 0-6 are pixels)
        let mut x_to_byte_bit: [(u16, u8); 280] = [(0, 0); 280];
        for x in 0..280 {
            let byte_offset = x / 7;
            let bit = x % 7;
            x_to_byte_bit[x] = (byte_offset as u16, bit as u8);
        }

        // Estimate output size: chars_tall lines, each with chars_wide chars + newline
        // Each braille char is 3 bytes UTF-8
        let estimated_size = (chars_tall as usize) * ((chars_wide as usize) * 3 + 1);
        let mut result = String::with_capacity(estimated_size);

        for char_y in 0..chars_tall {
            for char_x in 0..chars_wide {
                let mut pattern: u8 = 0;

                // Sample 2x4 grid for this braille character
                for dy in 0..4u32 {
                    for dx in 0..2u32 {
                        // Fixed-point pixel coordinates
                        let px_fp = ((char_x * 2 + dx) as u64) * x_scale_fp;
                        let py_fp = ((char_y * 4 + dy) as u64) * y_scale_fp;

                        let px = (px_fp >> 16) as usize;
                        let py = (py_fp >> 16) as usize;

                        // Clamp to valid range
                        let px = px.min(HIRES_WIDTH as usize - 1);
                        let py = py.min(HIRES_HEIGHT as usize - 1);

                        // Get line address and byte/bit position
                        let line_addr = line_addrs[py];
                        let (byte_offset, bit) = x_to_byte_bit[px];

                        // Read byte from memory and extract pixel
                        let byte = mem[(line_addr + byte_offset) as usize];
                        let pixel = (byte >> bit) & 1;

                        // Apply inversion and set dot
                        let pixel = if invert { 1 - pixel } else { pixel };
                        if pixel == 1 {
                            pattern |= DOT_MAP[dy as usize][dx as usize];
                        }
                    }
                }

                // Unicode braille starts at U+2800
                let braille_char = char::from_u32(0x2800 + pattern as u32).unwrap_or(' ');
                result.push(braille_char);
            }
            if char_y < chars_tall - 1 {
                result.push('\n');
            }
        }

        result
    }

    fn load_bytes(&self, bytes: &[u8], addr: u16) {
        let mut mem = self.memory.borrow_mut();
        for (i, &byte) in bytes.iter().enumerate() {
            mem[addr.wrapping_add(i as u16) as usize] = byte;
        }
    }
}

const VIDEO_STATE_TEXT: u32 = 1 << 0;
const VIDEO_STATE_MIXED: u32 = 1 << 1;
const VIDEO_STATE_PAGE2: u32 = 1 << 2;
const VIDEO_STATE_HIRES: u32 = 1 << 3;

const REG_A: c_int = 0;
const REG_X: c_int = 1;
const REG_Y: c_int = 2;
const REG_SP: c_int = 3;
const REG_PC: c_int = 4;
const REG_P: c_int = 5;
const REG_CYCLES: c_int = 6;
const REG_HALTED: c_int = 7;

#[no_mangle]
pub extern "C" fn sim_create() -> *mut RubyCpu {
    Box::into_raw(Box::new(RubyCpu::default()))
}

#[no_mangle]
pub unsafe extern "C" fn sim_destroy(ctx: *mut RubyCpu) {
    if !ctx.is_null() {
        drop(Box::from_raw(ctx));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_set_io_callbacks(
    ctx: *mut RubyCpu,
    read_cb: Option<IoReadCallback>,
    write_cb: Option<IoWriteCallback>,
    user_data: *mut c_void,
) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.set_io_callbacks(read_cb, write_cb, user_data);
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_reset(ctx: *mut RubyCpu) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.reset();
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_step(ctx: *mut RubyCpu) -> c_ulonglong {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.step() as c_ulonglong
}

#[no_mangle]
pub unsafe extern "C" fn sim_run(ctx: *mut RubyCpu, max_instructions: c_uint) -> c_uint {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.run(max_instructions) as c_uint
}

#[no_mangle]
pub unsafe extern "C" fn sim_run_cycles(
    ctx: *mut RubyCpu,
    target_cycles: c_ulonglong,
) -> c_ulonglong {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.run_cycles(target_cycles as u64) as c_ulonglong
}

#[no_mangle]
pub unsafe extern "C" fn sim_get_reg(ctx: *mut RubyCpu, reg: c_int) -> c_ulonglong {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };

    match reg {
        REG_A => sim.a() as c_ulonglong,
        REG_X => sim.x() as c_ulonglong,
        REG_Y => sim.y() as c_ulonglong,
        REG_SP => sim.sp() as c_ulonglong,
        REG_PC => sim.pc() as c_ulonglong,
        REG_P => sim.p() as c_ulonglong,
        REG_CYCLES => sim.cycles() as c_ulonglong,
        REG_HALTED => (sim.halted() as c_int) as c_ulonglong,
        _ => 0,
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_set_reg(ctx: *mut RubyCpu, reg: c_int, value: c_ulonglong) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };

    match reg {
        REG_A => sim.set_a((value & 0xFF) as u8),
        REG_X => sim.set_x((value & 0xFF) as u8),
        REG_Y => sim.set_y((value & 0xFF) as u8),
        REG_SP => sim.set_sp((value & 0xFF) as u8),
        REG_PC => sim.set_pc((value & 0xFFFF) as u16),
        REG_P => sim.set_p((value & 0xFF) as u8),
        REG_CYCLES => sim.set_cycles(value as u64),
        REG_HALTED => sim.set_halted(value != 0),
        _ => return 0,
    }

    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_read(ctx: *mut RubyCpu, addr: c_uint) -> c_uint {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.read((addr & 0xFFFF) as u16) as c_uint
}

#[no_mangle]
pub unsafe extern "C" fn sim_write(ctx: *mut RubyCpu, addr: c_uint, value: c_uint) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.write((addr & 0xFFFF) as u16, (value & 0xFF) as u8);
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_peek(ctx: *mut RubyCpu, addr: c_uint) -> c_uint {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.memory.borrow()[(addr & 0xFFFF) as usize] as c_uint
}

#[no_mangle]
pub unsafe extern "C" fn sim_poke(ctx: *mut RubyCpu, addr: c_uint, value: c_uint) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.memory.borrow_mut()[(addr & 0xFFFF) as usize] = (value & 0xFF) as u8;
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_load_bytes(
    ctx: *mut RubyCpu,
    data: *const u8,
    len: usize,
    addr: c_uint,
) -> usize {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };

    let bytes: &[u8] = if len == 0 {
        &[]
    } else {
        if data.is_null() {
            return 0;
        }
        slice::from_raw_parts(data, len)
    };

    sim.load_bytes(bytes, (addr & 0xFFFF) as u16);
    len
}

#[no_mangle]
pub unsafe extern "C" fn sim_read_word(ctx: *mut RubyCpu, addr: c_uint) -> c_uint {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.read_word((addr & 0xFFFF) as u16) as c_uint
}

#[no_mangle]
pub unsafe extern "C" fn sim_load_program(
    ctx: *mut RubyCpu,
    data: *const u8,
    len: usize,
    addr: c_uint,
) -> usize {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };

    let bytes: &[u8] = if len == 0 {
        &[]
    } else {
        if data.is_null() {
            return 0;
        }
        slice::from_raw_parts(data, len)
    };

    sim.load_program_internal(bytes, (addr & 0xFFFF) as u16);
    len
}

#[no_mangle]
pub unsafe extern "C" fn sim_has_io_handler(ctx: *mut RubyCpu) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.has_io_handler() as c_int
}

#[no_mangle]
pub unsafe extern "C" fn sim_inject_key(ctx: *mut RubyCpu, ascii: c_uint) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.inject_key((ascii & 0xFF) as u8);
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_key_ready(ctx: *mut RubyCpu) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.key_ready() as c_int
}

#[no_mangle]
pub unsafe extern "C" fn sim_speaker_toggles(ctx: *mut RubyCpu) -> c_ulonglong {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.speaker_toggles() as c_ulonglong
}

#[no_mangle]
pub unsafe extern "C" fn sim_reset_speaker_toggles(ctx: *mut RubyCpu) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.reset_speaker_toggles();
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_get_video_state(ctx: *mut RubyCpu) -> c_uint {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.video_state_bits() as c_uint
}

#[no_mangle]
pub unsafe extern "C" fn sim_set_video_state(ctx: *mut RubyCpu, bits: c_uint) -> c_int {
    let Some(sim) = ctx.as_ref() else {
        return 0;
    };
    sim.set_video_state_bits(bits);
    1
}

#[no_mangle]
pub unsafe extern "C" fn sim_render_hires_braille(
    ctx: *mut RubyCpu,
    chars_wide: c_uint,
    invert: c_int,
) -> *mut c_char {
    let Some(sim) = ctx.as_ref() else {
        return ptr::null_mut();
    };

    let rendered = sim.render_hires_braille(chars_wide.max(1), invert != 0);
    match CString::new(rendered) {
        Ok(cstr) => cstr.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn sim_free_string(ptr_str: *mut c_char) {
    if !ptr_str.is_null() {
        let _ = CString::from_raw(ptr_str);
    }
}
