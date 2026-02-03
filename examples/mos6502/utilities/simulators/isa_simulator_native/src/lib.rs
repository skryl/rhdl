//! MOS 6502 ISA-Level Simulator with Ruby bindings
//! High-performance instruction-level simulator for the MOS 6502 CPU
//!
//! Memory Model:
//! - Internal 64KB memory for fast CPU access
//! - Optional I/O handler for memory-mapped I/O ($C000-$CFFF on Apple II)
//! - External devices can read/write internal memory via peek/poke methods
//!
//! Performance optimizations:
//! - Keyboard and speaker state cached in Rust to avoid FFI calls
//! - CPU state copied to local variables in tight loop
//! - I/O region $C100-$CFFF served from internal memory (ROM)
//! - Only disk controller ($C0E0-$C0EF) requires FFI callbacks

use magnus::{
    method, prelude::*, value::Opaque, Error, RArray, RHash, Ruby, TryConvert, Value,
};
use std::cell::RefCell;

// Status flag bit positions
const FLAG_C: u8 = 0; // Carry
const FLAG_Z: u8 = 1; // Zero
const FLAG_I: u8 = 2; // Interrupt Disable
const FLAG_D: u8 = 3; // Decimal Mode
const FLAG_B: u8 = 4; // Break
const FLAG_V: u8 = 6; // Overflow
const FLAG_N: u8 = 7; // Negative

// Interrupt vectors
const NMI_VECTOR: u16 = 0xFFFA;
const RESET_VECTOR: u16 = 0xFFFC;
const IRQ_VECTOR: u16 = 0xFFFE;

// Apple II I/O region
const IO_START: u16 = 0xC000;
const IO_END: u16 = 0xCFFF;

// Apple II I/O page (actual soft switches)
const IO_PAGE_START: u16 = 0xC000;
const IO_PAGE_END: u16 = 0xC0FF;

// Disk II controller range (slot 6)
const DISK_IO_START: u16 = 0xC0E0;
const DISK_IO_END: u16 = 0xC0EF;

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

/// Ruby-wrapped CPU simulator with internal memory and optional I/O handler
///
/// Memory access:
/// - RAM/ROM ($0000-$BFFF, $D000-$FFFF): Fast internal memory
/// - I/O page ($C000-$C0FF): Handled in Rust except disk controller
/// - Expansion ROM ($C100-$CFFF): Fast internal memory
/// - Disk controller ($C0E0-$C0EF): Calls Ruby I/O handler
///
/// External devices can access internal memory via peek/poke methods.
#[magnus::wrap(class = "MOS6502::ISASimulatorNative")]
struct RubyCpu {
    cpu: RefCell<Cpu6502Core>,
    memory: RefCell<Vec<u8>>,           // Internal 64KB memory
    io_handler: RefCell<Option<Opaque<Value>>>,  // Optional I/O handler for disk controller
    io_state: RefCell<AppleIIState>,    // Cached Apple II I/O state
}

impl Default for RubyCpu {
    fn default() -> Self {
        Self {
            cpu: RefCell::new(Cpu6502Core::new()),
            memory: RefCell::new(vec![0; 0x10000]),
            io_handler: RefCell::new(None),
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

    // Call Ruby I/O handler for disk access
    #[inline]
    fn call_ruby_io_read(&self, addr: u16) -> u8 {
        let handler = self.io_handler.borrow();
        if let Some(ref opaque) = *handler {
            let ruby = unsafe { Ruby::get_unchecked() };
            let io: Value = ruby.get_inner(*opaque);
            match io.funcall::<_, _, i64>("io_read", (addr as i64,)) {
                Ok(v) => return v as u8,
                Err(_) => {}
            }
        }
        // Fall through to internal memory for expansion ROM
        self.memory.borrow()[addr as usize]
    }

    // Call Ruby I/O handler for disk access
    #[inline]
    fn call_ruby_io_write(&self, addr: u16, value: u8) {
        let handler = self.io_handler.borrow();
        if let Some(ref opaque) = *handler {
            let ruby = unsafe { Ruby::get_unchecked() };
            let io: Value = ruby.get_inner(*opaque);
            let _ = io.funcall::<_, _, Value>("io_write", (addr as i64, value as i64));
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

// Ruby method implementations
impl RubyCpu {
    fn rb_initialize(&self, io_handler: Option<Value>) {
        // If an I/O handler is provided and is not nil, store it
        if let Some(handler) = io_handler {
            if !handler.is_nil() {
                let opaque = Opaque::from(handler);
                *self.io_handler.borrow_mut() = Some(opaque);
            }
        }
    }

    fn rb_reset(&self) {
        self.cpu.borrow_mut().reset();
        // Read reset vector from internal memory
        let pc = self.read_word(RESET_VECTOR);
        self.cpu.borrow_mut().pc = pc;
    }

    fn rb_step(&self) -> u64 {
        self.step_internal()
    }

    fn rb_run(&self, max_instructions: u32) -> u32 {
        let mut count = 0;
        while count < max_instructions && !self.cpu.borrow().halted {
            self.step_internal();
            count += 1;
        }
        count
    }

    fn rb_run_cycles(&self, target_cycles: u64) -> u64 {
        let start_cycles = self.cpu.borrow().cycles;
        while (self.cpu.borrow().cycles - start_cycles) < target_cycles && !self.cpu.borrow().halted {
            self.step_internal();
        }
        self.cpu.borrow().cycles - start_cycles
    }

    // Register getters
    fn rb_a(&self) -> u8 { self.cpu.borrow().a }
    fn rb_x(&self) -> u8 { self.cpu.borrow().x }
    fn rb_y(&self) -> u8 { self.cpu.borrow().y }
    fn rb_sp(&self) -> u8 { self.cpu.borrow().sp }
    fn rb_pc(&self) -> u16 { self.cpu.borrow().pc }
    fn rb_p(&self) -> u8 { self.cpu.borrow().p }
    fn rb_cycles(&self) -> u64 { self.cpu.borrow().cycles }
    fn rb_halted(&self) -> bool { self.cpu.borrow().halted }

    // Register setters
    fn rb_set_a(&self, v: u8) { self.cpu.borrow_mut().a = v; }
    fn rb_set_x(&self, v: u8) { self.cpu.borrow_mut().x = v; }
    fn rb_set_y(&self, v: u8) { self.cpu.borrow_mut().y = v; }
    fn rb_set_sp(&self, v: u8) { self.cpu.borrow_mut().sp = v; }
    fn rb_set_pc(&self, v: u16) { self.cpu.borrow_mut().pc = v; }
    fn rb_set_p(&self, v: u8) { self.cpu.borrow_mut().p = (v & 0xFF) | 0x20; }
    fn rb_set_cycles(&self, v: u64) { self.cpu.borrow_mut().cycles = v; }
    fn rb_set_halted(&self, v: bool) { self.cpu.borrow_mut().halted = v; }

    // Flag accessors
    fn rb_flag_c(&self) -> u8 { self.cpu.borrow().flag(FLAG_C) }
    fn rb_flag_z(&self) -> u8 { self.cpu.borrow().flag(FLAG_Z) }
    fn rb_flag_i(&self) -> u8 { self.cpu.borrow().flag(FLAG_I) }
    fn rb_flag_d(&self) -> u8 { self.cpu.borrow().flag(FLAG_D) }
    fn rb_flag_b(&self) -> u8 { self.cpu.borrow().flag(FLAG_B) }
    fn rb_flag_v(&self) -> u8 { self.cpu.borrow().flag(FLAG_V) }
    fn rb_flag_n(&self) -> u8 { self.cpu.borrow().flag(FLAG_N) }

    fn rb_halted_q(&self) -> bool { self.cpu.borrow().halted }

    // CPU memory access (uses I/O handler for $C000-$CFFF)
    fn rb_read(&self, addr: u16) -> u8 {
        self.read(addr)
    }

    fn rb_write(&self, addr: u16, value: u8) {
        self.write(addr, value);
    }

    // Direct memory access (bypasses I/O handler - for external devices)
    fn rb_peek(&self, addr: u16) -> u8 {
        self.memory.borrow()[addr as usize]
    }

    fn rb_poke(&self, addr: u16, value: u8) {
        self.memory.borrow_mut()[addr as usize] = value;
    }

    // Bulk memory operations for loading ROM/RAM
    fn rb_load_bytes(&self, bytes: RArray, addr: u16) -> Result<(), Error> {
        let mut mem = self.memory.borrow_mut();
        for (i, item) in bytes.into_iter().enumerate() {
            let v: i64 = TryConvert::try_convert(item)?;
            mem[addr.wrapping_add(i as u16) as usize] = v as u8;
        }
        Ok(())
    }

    fn rb_read_word(&self, addr: u16) -> u16 {
        self.read_word(addr)
    }

    fn rb_load_program(&self, bytes: RArray, addr: u16) -> Result<(), Error> {
        let mut bytes_vec: Vec<u8> = Vec::new();
        for item in bytes.into_iter() {
            let v: i64 = TryConvert::try_convert(item)?;
            bytes_vec.push(v as u8);
        }

        self.load_program_internal(&bytes_vec, addr);
        Ok(())
    }

    fn rb_state(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let cpu = self.cpu.borrow();

        hash.aset(ruby.sym_new("a"), cpu.a as i64)?;
        hash.aset(ruby.sym_new("x"), cpu.x as i64)?;
        hash.aset(ruby.sym_new("y"), cpu.y as i64)?;
        hash.aset(ruby.sym_new("sp"), cpu.sp as i64)?;
        hash.aset(ruby.sym_new("pc"), cpu.pc as i64)?;
        hash.aset(ruby.sym_new("p"), cpu.p as i64)?;
        hash.aset(ruby.sym_new("n"), cpu.flag(FLAG_N) as i64)?;
        hash.aset(ruby.sym_new("v"), cpu.flag(FLAG_V) as i64)?;
        hash.aset(ruby.sym_new("b"), cpu.flag(FLAG_B) as i64)?;
        hash.aset(ruby.sym_new("d"), cpu.flag(FLAG_D) as i64)?;
        hash.aset(ruby.sym_new("i"), cpu.flag(FLAG_I) as i64)?;
        hash.aset(ruby.sym_new("z"), cpu.flag(FLAG_Z) as i64)?;
        hash.aset(ruby.sym_new("c"), cpu.flag(FLAG_C) as i64)?;
        hash.aset(ruby.sym_new("cycles"), cpu.cycles as i64)?;
        hash.aset(ruby.sym_new("halted"), cpu.halted)?;

        Ok(hash)
    }

    fn rb_native(&self) -> bool {
        true
    }

    fn rb_has_io_handler(&self) -> bool {
        self.io_handler.borrow().is_some()
    }

    // Apple II I/O state accessors (for integration with Ruby bus)

    // Inject a key press (called from Ruby when key is pressed)
    fn rb_inject_key(&self, ascii: u8) {
        let mut io = self.io_state.borrow_mut();
        io.key_value = ascii & 0x7F;
        io.key_ready = true;
    }

    // Check if key is ready
    fn rb_key_ready(&self) -> bool {
        self.io_state.borrow().key_ready
    }

    // Get speaker toggle count and reset
    fn rb_speaker_toggles(&self) -> u64 {
        self.io_state.borrow().speaker_toggles
    }

    // Reset speaker toggle count
    fn rb_reset_speaker_toggles(&self) {
        self.io_state.borrow_mut().speaker_toggles = 0;
    }

    // Get video state as hash
    fn rb_video_state(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let io = self.io_state.borrow();

        hash.aset(ruby.sym_new("text"), io.video_text)?;
        hash.aset(ruby.sym_new("mixed"), io.video_mixed)?;
        hash.aset(ruby.sym_new("page2"), io.video_page2)?;
        hash.aset(ruby.sym_new("hires"), io.video_hires)?;

        Ok(hash)
    }

    // Set video state (for synchronization from Ruby)
    fn rb_set_video_state(&self, text: bool, mixed: bool, page2: bool, hires: bool) {
        let mut io = self.io_state.borrow_mut();
        io.video_text = text;
        io.video_mixed = mixed;
        io.video_page2 = page2;
        io.video_hires = hires;
    }

    // Fast hires rendering to braille characters
    // chars_wide: target width in braille chars (default 140 for 80-column terminal)
    // invert: if true, invert pixels (white on black)
    fn rb_render_hires_braille(&self, chars_wide: u32, invert: bool) -> String {
        const HIRES_WIDTH: u32 = 280;
        const HIRES_HEIGHT: u32 = 192;
        const HIRES_BYTES_PER_LINE: u32 = 40;

        let mem = self.memory.borrow();
        let io = self.io_state.borrow();

        // Determine hires page base address
        let base: u16 = if io.video_page2 { 0x4000 } else { 0x2000 };

        // Braille characters are 2 dots wide × 4 dots tall
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
            line_addrs[row] = base + (line_in_group as u16 * 0x400)
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
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    // Define module MOS6502
    let module = ruby.define_module("MOS6502")?;

    // Define class MOS6502::ISASimulatorNative
    let class = module.define_class("ISASimulatorNative", ruby.class_object())?;

    class.define_alloc_func::<RubyCpu>();
    class.define_method("initialize", method!(RubyCpu::rb_initialize, 1))?;
    class.define_method("reset", method!(RubyCpu::rb_reset, 0))?;
    class.define_method("step", method!(RubyCpu::rb_step, 0))?;
    class.define_method("run", method!(RubyCpu::rb_run, 1))?;
    class.define_method("run_cycles", method!(RubyCpu::rb_run_cycles, 1))?;

    // Register getters
    class.define_method("a", method!(RubyCpu::rb_a, 0))?;
    class.define_method("x", method!(RubyCpu::rb_x, 0))?;
    class.define_method("y", method!(RubyCpu::rb_y, 0))?;
    class.define_method("sp", method!(RubyCpu::rb_sp, 0))?;
    class.define_method("pc", method!(RubyCpu::rb_pc, 0))?;
    class.define_method("p", method!(RubyCpu::rb_p, 0))?;
    class.define_method("cycles", method!(RubyCpu::rb_cycles, 0))?;
    class.define_method("halted", method!(RubyCpu::rb_halted, 0))?;
    class.define_method("halted?", method!(RubyCpu::rb_halted_q, 0))?;

    // Register setters
    class.define_method("a=", method!(RubyCpu::rb_set_a, 1))?;
    class.define_method("x=", method!(RubyCpu::rb_set_x, 1))?;
    class.define_method("y=", method!(RubyCpu::rb_set_y, 1))?;
    class.define_method("sp=", method!(RubyCpu::rb_set_sp, 1))?;
    class.define_method("pc=", method!(RubyCpu::rb_set_pc, 1))?;
    class.define_method("p=", method!(RubyCpu::rb_set_p, 1))?;
    class.define_method("cycles=", method!(RubyCpu::rb_set_cycles, 1))?;
    class.define_method("halted=", method!(RubyCpu::rb_set_halted, 1))?;

    // Flag accessors
    class.define_method("flag_c", method!(RubyCpu::rb_flag_c, 0))?;
    class.define_method("flag_z", method!(RubyCpu::rb_flag_z, 0))?;
    class.define_method("flag_i", method!(RubyCpu::rb_flag_i, 0))?;
    class.define_method("flag_d", method!(RubyCpu::rb_flag_d, 0))?;
    class.define_method("flag_b", method!(RubyCpu::rb_flag_b, 0))?;
    class.define_method("flag_v", method!(RubyCpu::rb_flag_v, 0))?;
    class.define_method("flag_n", method!(RubyCpu::rb_flag_n, 0))?;

    // Memory operations
    class.define_method("read", method!(RubyCpu::rb_read, 1))?;       // CPU access (I/O aware)
    class.define_method("write", method!(RubyCpu::rb_write, 2))?;     // CPU access (I/O aware)
    class.define_method("peek", method!(RubyCpu::rb_peek, 1))?;       // Direct memory access
    class.define_method("poke", method!(RubyCpu::rb_poke, 2))?;       // Direct memory access
    class.define_method("load_bytes", method!(RubyCpu::rb_load_bytes, 2))?;  // Bulk load
    class.define_method("read_word", method!(RubyCpu::rb_read_word, 1))?;
    class.define_method("load_program", method!(RubyCpu::rb_load_program, 2))?;

    // State
    class.define_method("state", method!(RubyCpu::rb_state, 0))?;
    class.define_method("native?", method!(RubyCpu::rb_native, 0))?;
    class.define_method("has_io_handler?", method!(RubyCpu::rb_has_io_handler, 0))?;

    // Apple II I/O state (for fast keyboard/video/speaker handling)
    class.define_method("inject_key", method!(RubyCpu::rb_inject_key, 1))?;
    class.define_method("key_ready?", method!(RubyCpu::rb_key_ready, 0))?;
    class.define_method("speaker_toggles", method!(RubyCpu::rb_speaker_toggles, 0))?;
    class.define_method("reset_speaker_toggles", method!(RubyCpu::rb_reset_speaker_toggles, 0))?;
    class.define_method("video_state", method!(RubyCpu::rb_video_state, 0))?;
    class.define_method("set_video_state", method!(RubyCpu::rb_set_video_state, 4))?;
    class.define_method("render_hires_braille", method!(RubyCpu::rb_render_hires_braille, 2))?;

    // Constants
    module.const_set("NMI_VECTOR", NMI_VECTOR as i64)?;
    module.const_set("RESET_VECTOR", RESET_VECTOR as i64)?;
    module.const_set("IRQ_VECTOR", IRQ_VECTOR as i64)?;
    module.const_set("IO_START", IO_START as i64)?;
    module.const_set("IO_END", IO_END as i64)?;

    Ok(())
}
