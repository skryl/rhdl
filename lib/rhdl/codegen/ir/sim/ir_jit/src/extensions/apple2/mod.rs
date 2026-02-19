//! Apple II full system simulation extension for JIT
//!
//! Provides batched CPU cycle execution with memory bridging for Apple II

use std::collections::HashMap;
use crate::core::CoreSimulator;

/// Apple II specific extension state
pub struct Apple2Extension {
    /// RAM (48KB)
    pub ram: Vec<u8>,
    /// ROM (12KB)
    pub rom: Vec<u8>,
    /// Signal indices for memory bridging
    pub ram_addr_idx: usize,
    pub ram_do_idx: usize,
    pub ram_we_idx: usize,
    pub d_idx: usize,
    pub clk_idx: usize,
    pub k_idx: usize,
    pub read_key_idx: usize,
    pub speaker_idx: usize,
    pub cpu_addr_idx: usize,
    /// Previous speaker state for edge detection
    pub prev_speaker: u64,
    /// Number of sub-cycles per CPU cycle (default: 14)
    pub sub_cycles: usize,
}

/// Result from batched Apple II CPU cycle execution
pub struct Apple2BatchResult {
    pub text_dirty: bool,
    pub key_cleared: bool,
    pub cycles_run: usize,
    pub speaker_toggles: u32,
}

impl Apple2Extension {
    /// Create Apple II extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator, sub_cycles: usize) -> Self {
        let name_to_idx = &core.name_to_idx;

        Self {
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx: *name_to_idx.get("ram_addr").unwrap_or(&0),
            ram_do_idx: *name_to_idx.get("ram_do").unwrap_or(&0),
            ram_we_idx: *name_to_idx.get("ram_we").unwrap_or(&0),
            d_idx: *name_to_idx.get("d").unwrap_or(&0),
            clk_idx: *name_to_idx.get("clk_14m").unwrap_or(&0),
            k_idx: *name_to_idx.get("k").unwrap_or(&0),
            read_key_idx: *name_to_idx.get("read_key").unwrap_or(&0),
            speaker_idx: *name_to_idx.get("speaker").unwrap_or(&0),
            cpu_addr_idx: *name_to_idx.get("cpu__addr_reg").unwrap_or(&0),
            prev_speaker: 0,
            sub_cycles: sub_cycles.max(1).min(14),
        }
    }

    /// Check if the simulator has Apple II specific signals
    pub fn is_apple2_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("clk_14m")
            && name_to_idx.contains_key("cpu__addr_reg")
            && name_to_idx.contains_key("ram_addr")
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

    /// Run a single 14MHz cycle with integrated memory handling
    #[inline(always)]
    fn run_14m_cycle_internal(&mut self, core: &mut CoreSimulator, key_data: u8, key_ready: bool) -> (bool, bool, bool) {
        // Set keyboard input
        let k_val = if key_ready { (key_data as u64) | 0x80 } else { 0 };
        core.signals[self.k_idx] = k_val;

        // Falling edge
        core.signals[self.clk_idx] = 0;
        core.evaluate();

        // Provide RAM/ROM data based on Apple II memory map
        let ram_addr = core.signals[self.cpu_addr_idx] as usize;
        let ram_data = if ram_addr >= 0xD000 && ram_addr <= 0xFFFF {
            let rom_offset = ram_addr.wrapping_sub(0xD000);
            if rom_offset < self.rom.len() { self.rom[rom_offset] } else { 0 }
        } else if ram_addr >= 0xC000 {
            0 // I/O space
        } else if ram_addr < self.ram.len() {
            self.ram[ram_addr]
        } else {
            0
        };
        core.signals[self.ram_do_idx] = ram_data as u64;

        // Rising edge
        core.signals[self.clk_idx] = 1;
        core.tick();

        // Handle RAM writes
        let mut text_dirty = false;
        if core.signals[self.ram_we_idx] == 1 {
            let write_addr = core.signals[self.cpu_addr_idx] as usize;
            if write_addr < 0xC000 {
                let data = (core.signals[self.d_idx] & 0xFF) as u8;
                self.ram[write_addr] = data;
                text_dirty = (0x0400..=0x07FF).contains(&write_addr);
            }
        }

        let key_cleared = core.signals[self.read_key_idx] == 1;

        // Check speaker toggle (edge detection)
        let speaker = core.signals[self.speaker_idx];
        let speaker_toggled = speaker != self.prev_speaker;
        self.prev_speaker = speaker;

        (text_dirty, key_cleared, speaker_toggled)
    }

    /// Run batched CPU cycles with memory bridging
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
