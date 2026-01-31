//! Apple II system simulation extension for IR Interpreter
//!
//! Provides internalized RAM/ROM and batched cycle execution for Apple II.

mod ffi;
pub use ffi::*;

use std::collections::HashMap;
use crate::core::{CoreSimulator, FlatOp, OP_COPY_TO_SIG};

/// Result of batched cycle execution
pub struct Apple2BatchResult {
    pub text_dirty: bool,
    pub key_cleared: bool,
    pub cycles_run: usize,
    pub speaker_toggles: u32,
}

/// Apple II system-specific extension state
pub struct Apple2Extension {
    /// RAM (48KB)
    pub ram: Vec<u8>,
    /// ROM (12KB)
    pub rom: Vec<u8>,
    /// RAM address signal index (used for detection)
    #[allow(dead_code)]
    ram_addr_idx: usize,
    /// CPU address register index
    cpu_addr_idx: usize,
    /// RAM data out signal index
    ram_do_idx: usize,
    /// RAM write enable signal index
    ram_we_idx: usize,
    /// Data bus signal index
    d_idx: usize,
    /// Clock signal index
    clk_idx: usize,
    /// Keyboard input index
    k_idx: usize,
    /// Read key strobe index
    read_key_idx: usize,
    /// Speaker output index
    speaker_idx: usize,
    /// Previous speaker state for edge detection
    prev_speaker: u64,
    /// Sub-cycles per CPU cycle
    sub_cycles: usize,
}

impl Apple2Extension {
    /// Create Apple II extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator, sub_cycles: usize) -> Self {
        let name_to_idx = &core.name_to_idx;

        Self {
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx: *name_to_idx.get("ram_addr").unwrap_or(&0),
            cpu_addr_idx: *name_to_idx.get("cpu__addr_reg").unwrap_or(&0),
            ram_do_idx: *name_to_idx.get("ram_do").unwrap_or(&0),
            ram_we_idx: *name_to_idx.get("ram_we").unwrap_or(&0),
            d_idx: *name_to_idx.get("d").unwrap_or(&0),
            clk_idx: *name_to_idx.get("clk_14m").unwrap_or(&0),
            k_idx: *name_to_idx.get("k").unwrap_or(&0),
            read_key_idx: *name_to_idx.get("read_key").unwrap_or(&0),
            speaker_idx: *name_to_idx.get("speaker").unwrap_or(&0),
            prev_speaker: 0,
            sub_cycles: sub_cycles.max(1).min(14),
        }
    }

    /// Check if the simulator has Apple II specific signals
    pub fn is_apple2_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("ram_addr")
            && name_to_idx.contains_key("ram_do")
            && name_to_idx.contains_key("ram_we")
    }

    /// Load ROM data
    pub fn load_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.rom.len());
        self.rom[..len].copy_from_slice(&data[..len]);
    }

    /// Load RAM data at offset
    pub fn load_ram(&mut self, data: &[u8], offset: usize) {
        let end = (offset + data.len()).min(self.ram.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.ram[offset..end].copy_from_slice(&data[..len]);
        }
    }

    /// Read RAM slice
    pub fn read_ram(&self, start: usize, length: usize) -> &[u8] {
        let end = (start + length).min(self.ram.len());
        &self.ram[start..end]
    }

    /// Write to RAM
    pub fn write_ram(&mut self, start: usize, data: &[u8]) {
        let end = (start + data.len()).min(self.ram.len());
        let len = end - start;
        self.ram[start..end].copy_from_slice(&data[..len]);
    }

    /// Run a single 14MHz cycle with integrated memory handling
    #[inline(always)]
    fn run_14m_cycle_internal(&mut self, core: &mut CoreSimulator, key_data: u8, key_ready: bool) -> (bool, bool, bool) {
        // Set keyboard input
        let k_val = ((key_data as u64) | 0x80) * (key_ready as u64);
        unsafe { *core.signals.get_unchecked_mut(self.k_idx) = k_val; }

        // Falling edge
        unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 0; }
        core.evaluate();

        // Provide RAM/ROM data
        let ram_addr = unsafe { *core.signals.get_unchecked(self.cpu_addr_idx) } as usize;
        let ram_data = if ram_addr >= 0xD000 {
            let rom_offset = ram_addr.wrapping_sub(0xD000);
            if rom_offset < self.rom.len() {
                unsafe { *self.rom.get_unchecked(rom_offset) }
            } else {
                0
            }
        } else if ram_addr >= 0xC000 {
            0
        } else {
            unsafe { *self.ram.get_unchecked(ram_addr) }
        };
        unsafe { *core.signals.get_unchecked_mut(self.ram_do_idx) = ram_data as u64; }

        // Rising edge
        unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 1; }
        self.tick_fast(core);

        // Handle RAM writes
        let mut text_dirty = false;
        let ram_we = unsafe { *core.signals.get_unchecked(self.ram_we_idx) };
        if ram_we == 1 {
            let write_addr = unsafe { *core.signals.get_unchecked(self.cpu_addr_idx) } as usize;
            if write_addr < 0xC000 {
                let data = unsafe { (*core.signals.get_unchecked(self.d_idx) & 0xFF) as u8 };
                unsafe { *self.ram.get_unchecked_mut(write_addr) = data; }
                text_dirty = (write_addr >= 0x0400) & (write_addr <= 0x07FF);
            }
        }

        let key_cleared = unsafe { *core.signals.get_unchecked(self.read_key_idx) } == 1;

        let speaker = unsafe { *core.signals.get_unchecked(self.speaker_idx) };
        let speaker_toggled = speaker != self.prev_speaker;
        self.prev_speaker = speaker;

        (text_dirty, key_cleared, speaker_toggled)
    }

    /// Optimized tick for Apple II
    #[inline(always)]
    fn tick_fast(&mut self, core: &mut CoreSimulator) {
        for (i, &clk_idx) in core.clock_indices.iter().enumerate() {
            core.prev_clock_values[i] = core.signals[clk_idx];
        }

        core.evaluate();

        for (i, seq_assign) in core.seq_assigns.iter().enumerate() {
            if let Some((src_idx, mask)) = seq_assign.fast_source {
                let val = unsafe { *core.signals.get_unchecked(src_idx) } & mask;
                core.next_regs[i] = val;
                continue;
            }

            let ops_len = seq_assign.ops.len();
            if ops_len == 0 {
                continue;
            }

            for op in &seq_assign.ops[..ops_len.saturating_sub(1)] {
                CoreSimulator::execute_flat_op_static(&mut core.signals, &mut core.temps, &core.memory_arrays, op);
            }

            let last_op = &seq_assign.ops[ops_len - 1];
            if last_op.op_type == OP_COPY_TO_SIG {
                let val = FlatOp::get_operand(&core.signals, &core.temps, last_op.arg0) & last_op.arg2;
                core.next_regs[i] = val;
            } else {
                CoreSimulator::execute_flat_op_static(&mut core.signals, &mut core.temps, &core.memory_arrays, last_op);
                core.next_regs[i] = unsafe { *core.signals.get_unchecked(seq_assign.final_target) };
            }
        }

        const MAX_ITERATIONS: usize = 10;
        for _ in 0..MAX_ITERATIONS {
            let mut any_edge = false;
            for (clock_list_idx, &clk_idx) in core.clock_indices.iter().enumerate() {
                let old_val = core.prev_clock_values[clock_list_idx];
                let new_val = unsafe { *core.signals.get_unchecked(clk_idx) };

                if old_val == 0 && new_val == 1 {
                    any_edge = true;
                    for &(seq_idx, target_idx) in &core.clock_domain_assigns[clock_list_idx] {
                        unsafe { *core.signals.get_unchecked_mut(target_idx) = core.next_regs[seq_idx]; }
                    }
                    core.prev_clock_values[clock_list_idx] = 1;
                }
            }

            if !any_edge {
                break;
            }

            core.evaluate();
        }
    }

    /// Run N CPU cycles with batched execution
    pub fn run_cpu_cycles(&mut self, core: &mut CoreSimulator, n: usize, key_data: u8, key_ready: bool) -> Apple2BatchResult {
        let mut result = Apple2BatchResult {
            text_dirty: false,
            key_cleared: false,
            cycles_run: n,
            speaker_toggles: 0,
        };

        let mut current_key_ready = key_ready;

        for _ in 0..n {
            for _ in 0..self.sub_cycles {
                let (text_dirty, key_cleared, speaker_toggled) = self.run_14m_cycle_internal(core, key_data, current_key_ready);
                result.text_dirty |= text_dirty;
                if key_cleared {
                    current_key_ready = false;
                    result.key_cleared = true;
                }
                if speaker_toggled {
                    result.speaker_toggles += 1;
                }
            }
        }

        result
    }
}

impl CoreSimulator {
    /// Static version of execute_flat_op for use in extensions
    #[inline(always)]
    pub fn execute_flat_op_static(signals: &mut [u64], temps: &mut [u64], memories: &[Vec<u64>], op: &FlatOp) {
        use crate::core::*;

        match op.op_type {
            OP_COPY_TO_SIG => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_COPY_SIG | OP_COPY_IMM | OP_COPY_TMP => {
                let val = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_NOT => {
                let val = (!FlatOp::get_operand(signals, temps, op.arg0)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = val; }
            }
            OP_REDUCE_AND => {
                let val = FlatOp::get_operand(signals, temps, op.arg0);
                let mask = op.arg1;
                let result = ((val & mask) == mask) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_OR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != 0) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_REDUCE_XOR => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0).count_ones() & 1) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_AND => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) | FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) ^ FlatOp::get_operand(signals, temps, op.arg1);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_ADD => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_add(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SUB => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_sub(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUL => {
                let result = FlatOp::get_operand(signals, temps, op.arg0).wrapping_mul(FlatOp::get_operand(signals, temps, op.arg1)) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_DIV => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) / r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MOD => {
                let r = FlatOp::get_operand(signals, temps, op.arg1);
                let result = if r != 0 { FlatOp::get_operand(signals, temps, op.arg0) % r } else { 0 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHL => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(63) as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) << shift) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SHR => {
                let shift = FlatOp::get_operand(signals, temps, op.arg1).min(63) as u32;
                let result = FlatOp::get_operand(signals, temps, op.arg0) >> shift;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) == FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_NE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) != FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) < FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GT => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) > FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_LE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) <= FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_GE => {
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >= FlatOp::get_operand(signals, temps, op.arg1)) as u64;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX => {
                let c = FlatOp::get_operand(signals, temps, op.arg0);
                let t = FlatOp::get_operand(signals, temps, op.arg1);
                let f = FlatOp::get_operand(signals, temps, op.arg2);
                let select = (c != 0) as u64;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_SLICE => {
                let shift = op.arg1 as u32;
                let result = (FlatOp::get_operand(signals, temps, op.arg0) >> shift) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_CONCAT_INIT => {
                unsafe { *temps.get_unchecked_mut(op.dst) = 0; }
            }
            OP_CONCAT_ACCUM => {
                let part = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                let shift = op.arg1 as usize;
                unsafe {
                    let current = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = current | (part << shift);
                }
            }
            OP_CONCAT_FINISH => {
                unsafe {
                    let val = *temps.get_unchecked(op.dst);
                    *temps.get_unchecked_mut(op.dst) = val & op.arg2;
                }
            }
            OP_RESIZE => {
                let result = FlatOp::get_operand(signals, temps, op.arg0) & op.arg2;
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MEM_READ => {
                let mem_idx = op.arg0 as usize;
                let addr = FlatOp::get_operand(signals, temps, op.arg1) as usize;
                let result = if mem_idx < memories.len() {
                    let mem = &memories[mem_idx];
                    if addr < mem.len() { mem[addr] } else { 0 }
                } else {
                    0
                };
                unsafe { *temps.get_unchecked_mut(op.dst) = result & op.arg2; }
            }
            OP_COPY_SIG_TO_SIG => {
                let val = unsafe { *signals.get_unchecked(op.arg0 as usize) } & op.arg2;
                unsafe { *signals.get_unchecked_mut(op.dst) = val; }
            }
            OP_AND_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) & *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_OR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) | *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_XOR_SS => {
                let result = unsafe { *signals.get_unchecked(op.arg0 as usize) ^ *signals.get_unchecked(op.arg1 as usize) };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_EQ_SS => {
                let result = unsafe { (*signals.get_unchecked(op.arg0 as usize) == *signals.get_unchecked(op.arg1 as usize)) as u64 };
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            OP_MUX_SSS => {
                let c = unsafe { *signals.get_unchecked(op.arg0 as usize) };
                let t = unsafe { *signals.get_unchecked(op.arg1 as usize) };
                let f = unsafe { *signals.get_unchecked(op.arg2 as usize) };
                let select = (c != 0) as u64;
                let result = (select.wrapping_neg() & t) | ((!select.wrapping_neg()) & f);
                unsafe { *temps.get_unchecked_mut(op.dst) = result; }
            }
            _ => {}
        }
    }
}
