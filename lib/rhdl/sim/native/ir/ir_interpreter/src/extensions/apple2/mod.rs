//! Apple II system simulation extension for IR Interpreter
//!
//! Provides internalized RAM/ROM and batched cycle execution for Apple II.

use std::collections::HashMap;
use crate::core::CoreSimulator;
use crate::signal_value::SignalValue;

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

    /// Read RAM slice
    pub fn read_ram(&self, start: usize, length: usize) -> &[u8] {
        let end = (start + length).min(self.ram.len());
        &self.ram[start..end]
    }

    /// Read a single byte from the Apple II CPU-visible address space.
    #[inline(always)]
    pub fn read_mapped_byte(&self, addr: usize) -> u8 {
        let addr = addr & 0xFFFF;
        if addr >= 0xD000 {
            let rom_offset = addr - 0xD000;
            if rom_offset < self.rom.len() {
                self.rom[rom_offset]
            } else {
                0
            }
        } else if addr >= 0xC000 {
            0
        } else {
            self.ram[addr]
        }
    }

    /// Read from the full 64KB mapped address space into `out`.
    pub fn read_memory(&self, start: usize, out: &mut [u8]) -> usize {
        let mut addr = start & 0xFFFF;
        for slot in out.iter_mut() {
            *slot = self.read_mapped_byte(addr);
            addr = (addr + 1) & 0xFFFF;
        }
        out.len()
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
        let k_val = ((key_data as SignalValue) | 0x80) * (key_ready as SignalValue);
        unsafe { *core.signals.get_unchecked_mut(self.k_idx) = k_val; }

        // Falling edge
        unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 0; }
        core.evaluate();

        // Provide RAM/ROM data
        let ram_addr = unsafe { *core.signals.get_unchecked(self.cpu_addr_idx) } as usize;
        let ram_data = self.read_mapped_byte(ram_addr);
        unsafe { *core.signals.get_unchecked_mut(self.ram_do_idx) = ram_data as SignalValue; }

        // Rising edge
        unsafe { *core.signals.get_unchecked_mut(self.clk_idx) = 1; }
        core.tick();

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
        let speaker_toggled = speaker != (self.prev_speaker as SignalValue);
        self.prev_speaker = speaker as u64;

        (text_dirty, key_cleared, speaker_toggled)
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
