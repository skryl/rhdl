//! MOS6502 CPU standalone simulation extension for IR Interpreter
//!
//! Provides batched cycle execution with internal memory bridging for MOS6502 CPU.

mod ffi;
pub use ffi::*;

use std::collections::HashMap;
use crate::core::CoreSimulator;

/// MOS6502 CPU specific extension state
pub struct Mos6502Extension {
    /// Unified 64KB memory
    pub memory: Vec<u8>,
    /// ROM protection mask (true = protected)
    pub rom_mask: Vec<bool>,
    /// Signal indices for memory bridging
    pub addr_idx: usize,
    pub data_in_idx: usize,
    pub data_out_idx: usize,
    pub rw_idx: usize,
    pub clk_idx: usize,
    /// Speaker toggle counter (for $C030 access)
    pub speaker_toggles: u32,
}

impl Mos6502Extension {
    /// Create MOS6502 extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator) -> Self {
        let name_to_idx = &core.name_to_idx;

        Self {
            memory: vec![0u8; 64 * 1024],
            rom_mask: vec![false; 64 * 1024],
            addr_idx: *name_to_idx.get("addr").unwrap_or(&0),
            data_in_idx: *name_to_idx.get("data_in").unwrap_or(&0),
            data_out_idx: *name_to_idx.get("data_out").unwrap_or(&0),
            rw_idx: *name_to_idx.get("rw").unwrap_or(&0),
            clk_idx: *name_to_idx.get("clk").unwrap_or(&0),
            speaker_toggles: 0,
        }
    }

    /// Check if the simulator has MOS6502 CPU specific signals (standalone CPU, not full system)
    pub fn is_mos6502_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("addr")
            && name_to_idx.contains_key("data_in")
            && name_to_idx.contains_key("data_out")
            && name_to_idx.contains_key("rw")
            && !name_to_idx.contains_key("ram_addr")
    }

    /// Load memory data at offset, optionally marking as ROM
    pub fn load_memory(&mut self, data: &[u8], offset: usize, is_rom: bool) {
        let end = (offset + data.len()).min(self.memory.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.memory[offset..end].copy_from_slice(&data[..len]);
            if is_rom {
                for addr in offset..end {
                    self.rom_mask[addr] = true;
                }
            }
        }
    }

    /// Set the reset vector ($FFFC-$FFFD)
    pub fn set_reset_vector(&mut self, addr: u16) {
        self.memory[0xFFFC] = (addr & 0xFF) as u8;
        self.memory[0xFFFD] = ((addr >> 8) & 0xFF) as u8;
    }

    /// Read from memory
    pub fn read_memory(&self, addr: usize) -> u8 {
        if addr < self.memory.len() {
            self.memory[addr]
        } else {
            0
        }
    }

    /// Write to memory (respects ROM protection)
    pub fn write_memory(&mut self, addr: usize, data: u8) {
        if addr < self.memory.len() && !self.rom_mask[addr] {
            self.memory[addr] = data;
        }
    }

    /// Get speaker toggle count
    pub fn speaker_toggles(&self) -> u32 {
        self.speaker_toggles
    }

    /// Reset speaker toggle count
    pub fn reset_speaker_toggles(&mut self) {
        self.speaker_toggles = 0;
    }

    /// Run batched CPU cycles with internal memory bridging
    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        // Find clock index in clock_indices array for proper edge detection
        let clk_list_idx = core.clock_indices.iter().position(|&ci| ci == self.clk_idx);

        for _ in 0..n {
            // Get address and R/W from CPU
            let addr = unsafe { *core.signals.get_unchecked(self.addr_idx) } as usize & 0xFFFF;
            let rw = unsafe { *core.signals.get_unchecked(self.rw_idx) };

            // Detect speaker toggle ($C030) - any access triggers toggle
            if addr == 0xC030 {
                self.speaker_toggles += 1;
            }

            if rw == 1 {
                // Read: provide data from memory to CPU
                let data = unsafe { *self.memory.get_unchecked(addr) } as u64;
                unsafe { *core.signals.get_unchecked_mut(self.data_in_idx) = data; }
            } else {
                // Write: store CPU data to memory (unless ROM protected)
                if !unsafe { *self.rom_mask.get_unchecked(addr) } {
                    let data = unsafe { *core.signals.get_unchecked(self.data_out_idx) } as u8;
                    unsafe { *self.memory.get_unchecked_mut(addr) = data; }
                }
            }

            // Clock falling edge
            if let Some(idx) = clk_list_idx {
                core.prev_clock_values[idx] = 1; // Previous state was high
            }
            unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 0; }
            core.evaluate();

            // Clock rising edge
            if let Some(idx) = clk_list_idx {
                core.prev_clock_values[idx] = 0; // Previous state was low
            }
            unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 1; }
            core.tick();
        }

        n
    }
}
