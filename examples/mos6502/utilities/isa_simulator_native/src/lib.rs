//! MOS 6502 ISA-Level Simulator with Ruby bindings
//! High-performance instruction-level simulator for the MOS 6502 CPU

use magnus::{
    method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value,
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

/// MOS 6502 CPU state
pub struct Cpu6502 {
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

    // Memory (owned array - 64KB)
    pub memory: Vec<u8>,
}

impl Cpu6502 {
    pub fn new() -> Self {
        let mut cpu = Self {
            a: 0,
            x: 0,
            y: 0,
            sp: 0xFD,
            pc: 0,
            p: 0x24, // Unused flag set, Interrupt disable set
            cycles: 0,
            halted: false,
            memory: vec![0; 0x10000],
        };
        cpu.pc = cpu.read_word(RESET_VECTOR);
        cpu
    }

    pub fn reset(&mut self) {
        self.a = 0;
        self.x = 0;
        self.y = 0;
        self.sp = 0xFD;
        self.p = 0x24;
        self.pc = self.read_word(RESET_VECTOR);
        self.cycles = 0;
        self.halted = false;
    }

    // Memory operations
    #[inline]
    pub fn read(&self, addr: u16) -> u8 {
        self.memory[addr as usize]
    }

    #[inline]
    pub fn write(&mut self, addr: u16, value: u8) {
        self.memory[addr as usize] = value;
    }

    #[inline]
    pub fn read_word(&self, addr: u16) -> u16 {
        let lo = self.read(addr) as u16;
        let hi = self.read(addr.wrapping_add(1)) as u16;
        (hi << 8) | lo
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

    // Fetch operations
    #[inline]
    fn fetch_byte(&mut self) -> u8 {
        let byte = self.read(self.pc);
        self.pc = self.pc.wrapping_add(1);
        byte
    }

    #[inline]
    fn fetch_word(&mut self) -> u16 {
        let lo = self.fetch_byte() as u16;
        let hi = self.fetch_byte() as u16;
        (hi << 8) | lo
    }

    // Stack operations
    #[inline]
    fn push_byte(&mut self, value: u8) {
        self.write(0x100 + self.sp as u16, value);
        self.sp = self.sp.wrapping_sub(1);
    }

    #[inline]
    fn pull_byte(&mut self) -> u8 {
        self.sp = self.sp.wrapping_add(1);
        self.read(0x100 + self.sp as u16)
    }

    #[inline]
    fn push_word(&mut self, value: u16) {
        self.push_byte((value >> 8) as u8);
        self.push_byte(value as u8);
    }

    #[inline]
    fn pull_word(&mut self) -> u16 {
        let lo = self.pull_byte() as u16;
        let hi = self.pull_byte() as u16;
        (hi << 8) | lo
    }

    // Addressing modes - return address
    #[inline]
    fn addr_immediate(&mut self) -> u16 {
        let addr = self.pc;
        self.pc = self.pc.wrapping_add(1);
        addr
    }

    #[inline]
    fn addr_zero_page(&mut self) -> u16 {
        self.fetch_byte() as u16
    }

    #[inline]
    fn addr_zero_page_x(&mut self) -> u16 {
        self.fetch_byte().wrapping_add(self.x) as u16
    }

    #[inline]
    fn addr_zero_page_y(&mut self) -> u16 {
        self.fetch_byte().wrapping_add(self.y) as u16
    }

    #[inline]
    fn addr_absolute(&mut self) -> u16 {
        self.fetch_word()
    }

    #[inline]
    fn addr_absolute_x(&mut self, check_page_cross: bool) -> u16 {
        let base = self.fetch_word();
        let addr = base.wrapping_add(self.x as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cycles += 1;
        }
        addr
    }

    #[inline]
    fn addr_absolute_y(&mut self, check_page_cross: bool) -> u16 {
        let base = self.fetch_word();
        let addr = base.wrapping_add(self.y as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cycles += 1;
        }
        addr
    }

    #[inline]
    fn addr_indirect(&mut self) -> u16 {
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

    #[inline]
    fn addr_indexed_indirect(&mut self) -> u16 {
        // (zp,X)
        let ptr = self.fetch_byte().wrapping_add(self.x);
        let lo = self.read(ptr as u16);
        let hi = self.read(ptr.wrapping_add(1) as u16);
        ((hi as u16) << 8) | lo as u16
    }

    #[inline]
    fn addr_indirect_indexed(&mut self, check_page_cross: bool) -> u16 {
        // (zp),Y
        let ptr = self.fetch_byte();
        let lo = self.read(ptr as u16);
        let hi = self.read(ptr.wrapping_add(1) as u16);
        let base = ((hi as u16) << 8) | lo as u16;
        let addr = base.wrapping_add(self.y as u16);
        if check_page_cross && (base & 0xFF00) != (addr & 0xFF00) {
            self.cycles += 1;
        }
        addr
    }

    #[inline]
    fn addr_relative(&mut self) -> u16 {
        let offset = self.fetch_byte() as i8 as i16;
        self.pc.wrapping_add(offset as u16)
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

    fn branch_if(&mut self, condition: bool) {
        let target = self.addr_relative();
        if condition {
            self.cycles += 1;
            if (self.pc & 0xFF00) != (target & 0xFF00) {
                self.cycles += 1;
            }
            self.pc = target;
        }
    }

    /// Execute one instruction and return cycles taken
    pub fn step(&mut self) -> u64 {
        if self.halted {
            return 0;
        }

        let opcode = self.fetch_byte();
        self.execute(opcode);
        self.cycles
    }

    /// Execute multiple instructions
    pub fn run(&mut self, max_instructions: u32) -> u32 {
        let mut count = 0;
        while count < max_instructions && !self.halted {
            self.step();
            count += 1;
        }
        count
    }

    /// Execute for a number of cycles
    pub fn run_cycles(&mut self, target_cycles: u64) -> u64 {
        let start_cycles = self.cycles;
        while (self.cycles - start_cycles) < target_cycles && !self.halted {
            self.step();
        }
        self.cycles - start_cycles
    }

    fn execute(&mut self, opcode: u8) {
        match opcode {
            // ADC - Add with Carry
            0x69 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.do_adc(v); }
            0x65 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.do_adc(v); }
            0x75 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.do_adc(v); }
            0x6D => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.do_adc(v); }
            0x7D => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.do_adc(v); }
            0x79 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.do_adc(v); }
            0x61 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.do_adc(v); }
            0x71 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.do_adc(v); }

            // SBC - Subtract with Carry
            0xE9 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.do_sbc(v); }
            0xE5 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.do_sbc(v); }
            0xF5 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.do_sbc(v); }
            0xED => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.do_sbc(v); }
            0xFD => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.do_sbc(v); }
            0xF9 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.do_sbc(v); }
            0xE1 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.do_sbc(v); }
            0xF1 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.do_sbc(v); }

            // AND - Logical AND
            0x29 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x25 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x35 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x2D => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x3D => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x39 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x21 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.a = self.set_nz(self.a & v); }
            0x31 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.a = self.set_nz(self.a & v); }

            // ORA - Logical OR
            0x09 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x05 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x15 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x0D => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x1D => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x19 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x01 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.a = self.set_nz(self.a | v); }
            0x11 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.a = self.set_nz(self.a | v); }

            // EOR - Exclusive OR
            0x49 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x45 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x55 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x4D => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x5D => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x59 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x41 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }
            0x51 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.a = self.set_nz(self.a ^ v); }

            // CMP - Compare Accumulator
            0xC9 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xC5 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xD5 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xCD => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xDD => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xD9 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xC1 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }
            0xD1 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); let a = self.a; self.do_cmp(a, v); }

            // CPX - Compare X Register
            0xE0 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let x = self.x; self.do_cmp(x, v); }
            0xE4 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let x = self.x; self.do_cmp(x, v); }
            0xEC => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let x = self.x; self.do_cmp(x, v); }

            // CPY - Compare Y Register
            0xC0 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); let y = self.y; self.do_cmp(y, v); }
            0xC4 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); let y = self.y; self.do_cmp(y, v); }
            0xCC => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); let y = self.y; self.do_cmp(y, v); }

            // BIT - Bit Test
            0x24 => {
                self.cycles += 3;
                let addr = self.addr_zero_page();
                let value = self.read(addr);
                let a = self.a;
                self.set_flag(FLAG_Z, (a & value) == 0);
                self.set_flag(FLAG_N, value & 0x80 != 0);
                self.set_flag(FLAG_V, value & 0x40 != 0);
            }
            0x2C => {
                self.cycles += 4;
                let addr = self.addr_absolute();
                let value = self.read(addr);
                let a = self.a;
                self.set_flag(FLAG_Z, (a & value) == 0);
                self.set_flag(FLAG_N, value & 0x80 != 0);
                self.set_flag(FLAG_V, value & 0x40 != 0);
            }

            // LDA - Load Accumulator
            0xA9 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.a = self.set_nz(v); }
            0xA5 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.a = self.set_nz(v); }
            0xB5 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.a = self.set_nz(v); }
            0xAD => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.a = self.set_nz(v); }
            0xBD => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.a = self.set_nz(v); }
            0xB9 => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.a = self.set_nz(v); }
            0xA1 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let v = self.read(addr); self.a = self.set_nz(v); }
            0xB1 => { self.cycles += 5; let addr = self.addr_indirect_indexed(true); let v = self.read(addr); self.a = self.set_nz(v); }

            // LDX - Load X Register
            0xA2 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.x = self.set_nz(v); }
            0xA6 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.x = self.set_nz(v); }
            0xB6 => { self.cycles += 4; let addr = self.addr_zero_page_y(); let v = self.read(addr); self.x = self.set_nz(v); }
            0xAE => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.x = self.set_nz(v); }
            0xBE => { self.cycles += 4; let addr = self.addr_absolute_y(true); let v = self.read(addr); self.x = self.set_nz(v); }

            // LDY - Load Y Register
            0xA0 => { self.cycles += 2; let addr = self.addr_immediate(); let v = self.read(addr); self.y = self.set_nz(v); }
            0xA4 => { self.cycles += 3; let addr = self.addr_zero_page(); let v = self.read(addr); self.y = self.set_nz(v); }
            0xB4 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let v = self.read(addr); self.y = self.set_nz(v); }
            0xAC => { self.cycles += 4; let addr = self.addr_absolute(); let v = self.read(addr); self.y = self.set_nz(v); }
            0xBC => { self.cycles += 4; let addr = self.addr_absolute_x(true); let v = self.read(addr); self.y = self.set_nz(v); }

            // STA - Store Accumulator
            0x85 => { self.cycles += 3; let addr = self.addr_zero_page(); let a = self.a; self.write(addr, a); }
            0x95 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let a = self.a; self.write(addr, a); }
            0x8D => { self.cycles += 4; let addr = self.addr_absolute(); let a = self.a; self.write(addr, a); }
            0x9D => { self.cycles += 5; let addr = self.addr_absolute_x(false); let a = self.a; self.write(addr, a); }
            0x99 => { self.cycles += 5; let addr = self.addr_absolute_y(false); let a = self.a; self.write(addr, a); }
            0x81 => { self.cycles += 6; let addr = self.addr_indexed_indirect(); let a = self.a; self.write(addr, a); }
            0x91 => { self.cycles += 6; let addr = self.addr_indirect_indexed(false); let a = self.a; self.write(addr, a); }

            // STX - Store X Register
            0x86 => { self.cycles += 3; let addr = self.addr_zero_page(); let x = self.x; self.write(addr, x); }
            0x96 => { self.cycles += 4; let addr = self.addr_zero_page_y(); let x = self.x; self.write(addr, x); }
            0x8E => { self.cycles += 4; let addr = self.addr_absolute(); let x = self.x; self.write(addr, x); }

            // STY - Store Y Register
            0x84 => { self.cycles += 3; let addr = self.addr_zero_page(); let y = self.y; self.write(addr, y); }
            0x94 => { self.cycles += 4; let addr = self.addr_zero_page_x(); let y = self.y; self.write(addr, y); }
            0x8C => { self.cycles += 4; let addr = self.addr_absolute(); let y = self.y; self.write(addr, y); }

            // Register Transfers
            0xAA => { self.cycles += 2; let a = self.a; self.x = self.set_nz(a); }       // TAX
            0x8A => { self.cycles += 2; let x = self.x; self.a = self.set_nz(x); }       // TXA
            0xA8 => { self.cycles += 2; let a = self.a; self.y = self.set_nz(a); }       // TAY
            0x98 => { self.cycles += 2; let y = self.y; self.a = self.set_nz(y); }       // TYA
            0xBA => { self.cycles += 2; let sp = self.sp; self.x = self.set_nz(sp); }    // TSX
            0x9A => { self.cycles += 2; self.sp = self.x; }                               // TXS (no flags)

            // Increment/Decrement Register
            0xE8 => { self.cycles += 2; let v = self.x.wrapping_add(1); self.x = self.set_nz(v); }  // INX
            0xCA => { self.cycles += 2; let v = self.x.wrapping_sub(1); self.x = self.set_nz(v); }  // DEX
            0xC8 => { self.cycles += 2; let v = self.y.wrapping_add(1); self.y = self.set_nz(v); }  // INY
            0x88 => { self.cycles += 2; let v = self.y.wrapping_sub(1); self.y = self.set_nz(v); }  // DEY

            // Increment Memory
            0xE6 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr).wrapping_add(1); self.set_nz(v); self.write(addr, v); }
            0xF6 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr).wrapping_add(1); self.set_nz(v); self.write(addr, v); }
            0xEE => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr).wrapping_add(1); self.set_nz(v); self.write(addr, v); }
            0xFE => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr).wrapping_add(1); self.set_nz(v); self.write(addr, v); }

            // Decrement Memory
            0xC6 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr).wrapping_sub(1); self.set_nz(v); self.write(addr, v); }
            0xD6 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr).wrapping_sub(1); self.set_nz(v); self.write(addr, v); }
            0xCE => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr).wrapping_sub(1); self.set_nz(v); self.write(addr, v); }
            0xDE => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr).wrapping_sub(1); self.set_nz(v); self.write(addr, v); }

            // ASL - Arithmetic Shift Left
            0x0A => { self.cycles += 2; let v = self.a; self.a = self.do_asl(v); }
            0x06 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.do_asl(v); self.write(addr, r); }
            0x16 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.do_asl(v); self.write(addr, r); }
            0x0E => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.do_asl(v); self.write(addr, r); }
            0x1E => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.do_asl(v); self.write(addr, r); }

            // LSR - Logical Shift Right
            0x4A => { self.cycles += 2; let v = self.a; self.a = self.do_lsr(v); }
            0x46 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.do_lsr(v); self.write(addr, r); }
            0x56 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.do_lsr(v); self.write(addr, r); }
            0x4E => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.do_lsr(v); self.write(addr, r); }
            0x5E => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.do_lsr(v); self.write(addr, r); }

            // ROL - Rotate Left
            0x2A => { self.cycles += 2; let v = self.a; self.a = self.do_rol(v); }
            0x26 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.do_rol(v); self.write(addr, r); }
            0x36 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.do_rol(v); self.write(addr, r); }
            0x2E => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.do_rol(v); self.write(addr, r); }
            0x3E => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.do_rol(v); self.write(addr, r); }

            // ROR - Rotate Right
            0x6A => { self.cycles += 2; let v = self.a; self.a = self.do_ror(v); }
            0x66 => { self.cycles += 5; let addr = self.addr_zero_page(); let v = self.read(addr); let r = self.do_ror(v); self.write(addr, r); }
            0x76 => { self.cycles += 6; let addr = self.addr_zero_page_x(); let v = self.read(addr); let r = self.do_ror(v); self.write(addr, r); }
            0x6E => { self.cycles += 6; let addr = self.addr_absolute(); let v = self.read(addr); let r = self.do_ror(v); self.write(addr, r); }
            0x7E => { self.cycles += 7; let addr = self.addr_absolute_x(false); let v = self.read(addr); let r = self.do_ror(v); self.write(addr, r); }

            // Branches
            0x10 => { self.cycles += 2; let cond = self.flag(FLAG_N) == 0; self.branch_if(cond); }  // BPL
            0x30 => { self.cycles += 2; let cond = self.flag(FLAG_N) == 1; self.branch_if(cond); }  // BMI
            0x50 => { self.cycles += 2; let cond = self.flag(FLAG_V) == 0; self.branch_if(cond); }  // BVC
            0x70 => { self.cycles += 2; let cond = self.flag(FLAG_V) == 1; self.branch_if(cond); }  // BVS
            0x90 => { self.cycles += 2; let cond = self.flag(FLAG_C) == 0; self.branch_if(cond); }  // BCC
            0xB0 => { self.cycles += 2; let cond = self.flag(FLAG_C) == 1; self.branch_if(cond); }  // BCS
            0xD0 => { self.cycles += 2; let cond = self.flag(FLAG_Z) == 0; self.branch_if(cond); }  // BNE
            0xF0 => { self.cycles += 2; let cond = self.flag(FLAG_Z) == 1; self.branch_if(cond); }  // BEQ

            // JMP - Jump
            0x4C => { self.cycles += 3; self.pc = self.addr_absolute(); }
            0x6C => { self.cycles += 5; self.pc = self.addr_indirect(); }

            // JSR - Jump to Subroutine
            0x20 => {
                self.cycles += 6;
                let target = self.addr_absolute();
                let pc = self.pc.wrapping_sub(1);
                self.push_word(pc);
                self.pc = target;
            }

            // RTS - Return from Subroutine
            0x60 => {
                self.cycles += 6;
                self.pc = self.pull_word().wrapping_add(1);
            }

            // RTI - Return from Interrupt
            0x40 => {
                self.cycles += 6;
                self.p = self.pull_byte() | 0x20; // Unused flag always 1
                self.pc = self.pull_word();
            }

            // Stack Operations
            0x48 => { self.cycles += 3; let a = self.a; self.push_byte(a); }              // PHA
            0x08 => { self.cycles += 3; let p = self.p | 0x10; self.push_byte(p); }       // PHP (B flag set when pushed)
            0x68 => { self.cycles += 4; let v = self.pull_byte(); self.a = self.set_nz(v); }  // PLA
            0x28 => { self.cycles += 4; self.p = self.pull_byte() | 0x20; }               // PLP

            // Flag Operations
            0x18 => { self.cycles += 2; self.set_flag(FLAG_C, false); }  // CLC
            0x38 => { self.cycles += 2; self.set_flag(FLAG_C, true); }   // SEC
            0x58 => { self.cycles += 2; self.set_flag(FLAG_I, false); }  // CLI
            0x78 => { self.cycles += 2; self.set_flag(FLAG_I, true); }   // SEI
            0xB8 => { self.cycles += 2; self.set_flag(FLAG_V, false); }  // CLV
            0xD8 => { self.cycles += 2; self.set_flag(FLAG_D, false); }  // CLD
            0xF8 => { self.cycles += 2; self.set_flag(FLAG_D, true); }   // SED

            // NOP
            0xEA => { self.cycles += 2; }

            // BRK - Break
            0x00 => {
                self.cycles += 7;
                self.pc = self.pc.wrapping_add(1); // BRK skips a byte
                let pc = self.pc;
                self.push_word(pc);
                let p = self.p | 0x10; // B flag set when pushed
                self.push_byte(p);
                self.set_flag(FLAG_I, true);
                self.pc = self.read_word(IRQ_VECTOR);
            }

            // Illegal opcode - halt
            _ => {
                self.halted = true;
                self.cycles += 2;
            }
        }
    }

    /// Load program bytes into memory
    pub fn load_program(&mut self, bytes: &[u8], addr: u16) {
        for (i, &byte) in bytes.iter().enumerate() {
            self.write(addr.wrapping_add(i as u16), byte);
        }
        // Set reset vector
        self.write(RESET_VECTOR, (addr & 0xFF) as u8);
        self.write(RESET_VECTOR + 1, ((addr >> 8) & 0xFF) as u8);
    }
}

// ============================================================================
// Ruby bindings wrapper - simplified version without external memory
// For external memory support, use the pure Ruby implementation
// ============================================================================

/// Ruby-wrapped CPU simulator using internal memory only
/// For high-performance applications that don't need memory-mapped I/O
#[magnus::wrap(class = "MOS6502::ISASimulatorNative")]
struct RubyCpu {
    cpu: RefCell<Cpu6502>,
}

impl Default for RubyCpu {
    fn default() -> Self {
        Self {
            cpu: RefCell::new(Cpu6502::new()),
        }
    }
}

impl RubyCpu {
    fn new() -> Self {
        Self::default()
    }
}

// Ruby method implementations
impl RubyCpu {
    fn rb_initialize(&self, _memory: Option<Value>) {
        // Memory argument is ignored - we use internal memory only
        // This signature is for compatibility with ISASimulator.new(memory)
    }

    fn rb_reset(&self) {
        self.cpu.borrow_mut().reset();
    }

    fn rb_step(&self) -> u64 {
        self.cpu.borrow_mut().step()
    }

    fn rb_run(&self, max_instructions: u32) -> u32 {
        self.cpu.borrow_mut().run(max_instructions)
    }

    fn rb_run_cycles(&self, target_cycles: u64) -> u64 {
        self.cpu.borrow_mut().run_cycles(target_cycles)
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

    // Flag accessors
    fn rb_flag_c(&self) -> u8 { self.cpu.borrow().flag(FLAG_C) }
    fn rb_flag_z(&self) -> u8 { self.cpu.borrow().flag(FLAG_Z) }
    fn rb_flag_i(&self) -> u8 { self.cpu.borrow().flag(FLAG_I) }
    fn rb_flag_d(&self) -> u8 { self.cpu.borrow().flag(FLAG_D) }
    fn rb_flag_b(&self) -> u8 { self.cpu.borrow().flag(FLAG_B) }
    fn rb_flag_v(&self) -> u8 { self.cpu.borrow().flag(FLAG_V) }
    fn rb_flag_n(&self) -> u8 { self.cpu.borrow().flag(FLAG_N) }

    fn rb_halted_q(&self) -> bool { self.cpu.borrow().halted }

    fn rb_read(&self, addr: u16) -> u8 {
        self.cpu.borrow().read(addr)
    }

    fn rb_write(&self, addr: u16, value: u8) {
        self.cpu.borrow_mut().write(addr, value);
    }

    fn rb_read_word(&self, addr: u16) -> u16 {
        self.cpu.borrow().read_word(addr)
    }

    fn rb_load_program(&self, bytes: RArray, addr: u16) -> Result<(), Error> {
        let mut bytes_vec: Vec<u8> = Vec::new();
        for item in bytes.into_iter() {
            let v: i64 = TryConvert::try_convert(item)?;
            bytes_vec.push(v as u8);
        }

        self.cpu.borrow_mut().load_program(&bytes_vec, addr);
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

    // Flag accessors
    class.define_method("flag_c", method!(RubyCpu::rb_flag_c, 0))?;
    class.define_method("flag_z", method!(RubyCpu::rb_flag_z, 0))?;
    class.define_method("flag_i", method!(RubyCpu::rb_flag_i, 0))?;
    class.define_method("flag_d", method!(RubyCpu::rb_flag_d, 0))?;
    class.define_method("flag_b", method!(RubyCpu::rb_flag_b, 0))?;
    class.define_method("flag_v", method!(RubyCpu::rb_flag_v, 0))?;
    class.define_method("flag_n", method!(RubyCpu::rb_flag_n, 0))?;

    // Memory operations
    class.define_method("read", method!(RubyCpu::rb_read, 1))?;
    class.define_method("write", method!(RubyCpu::rb_write, 2))?;
    class.define_method("read_word", method!(RubyCpu::rb_read_word, 1))?;
    class.define_method("load_program", method!(RubyCpu::rb_load_program, 2))?;

    // State
    class.define_method("state", method!(RubyCpu::rb_state, 0))?;
    class.define_method("native?", method!(RubyCpu::rb_native, 0))?;

    // Constants
    module.const_set("NMI_VECTOR", NMI_VECTOR as i64)?;
    module.const_set("RESET_VECTOR", RESET_VECTOR as i64)?;
    module.const_set("IRQ_VECTOR", IRQ_VECTOR as i64)?;

    Ok(())
}
