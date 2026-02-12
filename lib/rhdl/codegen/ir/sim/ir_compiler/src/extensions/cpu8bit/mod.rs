//! 8-bit CPU standalone simulation extension for IR Compiler
//!
//! Provides batched cycle execution with internal memory bridging for the
//! examples/8bit CPU (mem_addr/mem_data_in/mem_data_out bus).

use std::collections::HashMap;

use crate::core::CoreSimulator;

/// 8-bit CPU specific extension state
pub struct Cpu8BitExtension {
    /// Unified 64KB memory
    pub memory: Vec<u8>,
    /// ROM protection mask (true = protected)
    pub rom_mask: Vec<bool>,
    /// Signal indices for memory bridging
    pub mem_addr_idx: usize,
    pub mem_data_in_idx: usize,
    pub mem_data_out_idx: usize,
    pub mem_write_en_idx: usize,
    pub clk_idx: usize,
}

impl Cpu8BitExtension {
    /// Create 8-bit CPU extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator) -> Self {
        let name_to_idx = &core.name_to_idx;

        Self {
            memory: vec![0u8; 64 * 1024],
            rom_mask: vec![false; 64 * 1024],
            mem_addr_idx: *name_to_idx.get("mem_addr").unwrap_or(&0),
            mem_data_in_idx: *name_to_idx.get("mem_data_in").unwrap_or(&0),
            mem_data_out_idx: *name_to_idx.get("mem_data_out").unwrap_or(&0),
            mem_write_en_idx: *name_to_idx.get("mem_write_en").unwrap_or(&0),
            clk_idx: *name_to_idx.get("clk").unwrap_or(&0),
        }
    }

    /// Check if the simulator has 8-bit CPU specific signals
    pub fn is_cpu8bit_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("mem_addr")
            && name_to_idx.contains_key("mem_data_in")
            && name_to_idx.contains_key("mem_data_out")
            && name_to_idx.contains_key("mem_write_en")
            && name_to_idx.contains_key("mem_read_en")
            && name_to_idx.contains_key("pc_out")
            && name_to_idx.contains_key("state_out")
            && name_to_idx.contains_key("halted")
    }

    /// Load memory data at offset, optionally marking as ROM
    pub fn load_memory(&mut self, data: &[u8], offset: usize, is_rom: bool) {
        if offset >= self.memory.len() {
            return;
        }
        let end = (offset + data.len()).min(self.memory.len());
        let len = end.saturating_sub(offset);
        if len == 0 {
            return;
        }

        self.memory[offset..end].copy_from_slice(&data[..len]);
        if is_rom {
            for addr in offset..end {
                self.rom_mask[addr] = true;
            }
        }
    }

    /// Read from memory with 16-bit wrapping
    pub fn read_memory(&self, addr: usize) -> u8 {
        self.memory[addr & 0xFFFF]
    }

    /// Write to memory (respects ROM protection)
    pub fn write_memory(&mut self, addr: usize, data: u8) {
        let idx = addr & 0xFFFF;
        if !self.rom_mask[idx] {
            self.memory[idx] = data;
        }
    }

    /// Run batched CPU cycles with internal memory bridging
    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        if !core.compiled {
            return 0;
        }

        for _ in 0..n {
            // Drive low and evaluate so bus outputs settle.
            if self.clk_idx < core.signals.len() {
                core.signals[self.clk_idx] = 0;
            }
            core.evaluate();

            // Bridge memory for this cycle.
            let addr = core
                .signals
                .get(self.mem_addr_idx)
                .copied()
                .unwrap_or(0) as usize
                & 0xFFFF;
            let write_en = core
                .signals
                .get(self.mem_write_en_idx)
                .copied()
                .unwrap_or(0)
                != 0;

            if write_en && !self.rom_mask[addr] {
                let data = (core
                    .signals
                    .get(self.mem_data_out_idx)
                    .copied()
                    .unwrap_or(0)
                    & 0xFF) as u8;
                self.memory[addr] = data;
            }

            if self.mem_data_in_idx < core.signals.len() {
                core.signals[self.mem_data_in_idx] = self.memory[addr] as u64;
            }

            // Force rising edge and tick.
            if self.clk_idx < core.signals.len() {
                core.signals[self.clk_idx] = 1;
            }
            core.tick();
        }

        n
    }
}
