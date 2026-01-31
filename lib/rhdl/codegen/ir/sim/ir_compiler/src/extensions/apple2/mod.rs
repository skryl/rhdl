//! Apple II full system simulation extension
//!
//! Provides batched CPU cycle execution with memory bridging for Apple II

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

/// Result from batched Apple II CPU cycle execution
pub struct Apple2BatchResult {
    pub text_dirty: bool,
    pub key_cleared: bool,
    pub cycles_run: usize,
    pub speaker_toggles: u32,
}

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
            sub_cycles,
        }
    }

    /// Check if the simulator has Apple II specific signals
    pub fn is_apple2_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("ram_addr") && name_to_idx.contains_key("ram_do")
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

    /// Run batched CPU cycles with memory bridging
    pub fn run_cpu_cycles(&mut self, core: &mut CoreSimulator, n: usize, key_data: u8, key_ready: bool) -> Apple2BatchResult {
        if !core.compiled {
            return Apple2BatchResult {
                text_dirty: false,
                key_cleared: false,
                cycles_run: 0,
                speaker_toggles: 0,
            };
        }

        let lib = core.compiled_lib.as_ref().unwrap();
        unsafe {
            type RunCpuCyclesFn = unsafe extern "C" fn(
                *mut u64, usize, *mut u8, usize, *const u8, usize,
                usize, u8, bool, *mut u64, *mut bool, *mut bool, *mut u32
            ) -> usize;

            let func: libloading::Symbol<RunCpuCyclesFn> = lib.get(b"run_cpu_cycles")
                .expect("run_cpu_cycles function not found - is this an Apple II IR?");

            let mut text_dirty = false;
            let mut key_cleared = false;
            let mut speaker_toggles: u32 = 0;

            let cycles_run = func(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.ram.as_mut_ptr(),
                self.ram.len(),
                self.rom.as_ptr(),
                self.rom.len(),
                n * self.sub_cycles,
                key_data,
                key_ready,
                &mut self.prev_speaker,
                &mut text_dirty,
                &mut key_cleared,
                &mut speaker_toggles,
            );

            Apple2BatchResult {
                text_dirty,
                key_cleared,
                cycles_run: cycles_run / self.sub_cycles,
                speaker_toggles,
            }
        }
    }

    /// Generate Apple II specific batched execution code
    pub fn generate_code(core: &CoreSimulator) -> String {
        let mut code = String::new();

        let ram_addr_idx = *core.name_to_idx.get("ram_addr").unwrap_or(&0);
        let ram_do_idx = *core.name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *core.name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *core.name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *core.name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *core.name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *core.name_to_idx.get("read_key").unwrap_or(&0);
        let speaker_idx = *core.name_to_idx.get("speaker").unwrap_or(&0);
        let cpu_addr_idx = *core.name_to_idx.get("cpu__addr_reg").unwrap_or(&0);

        let clock_indices: Vec<usize> = core.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        code.push_str("\n// ============================================================================\n");
        code.push_str("// Apple II Extension: Batched CPU Cycle Execution\n");
        code.push_str("// ============================================================================\n\n");

        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_cpu_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    ram: *mut u8,\n");
        code.push_str("    ram_len: usize,\n");
        code.push_str("    rom: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    key_data: u8,\n");
        code.push_str("    key_ready: bool,\n");
        code.push_str("    prev_speaker_ptr: *mut u64,\n");
        code.push_str("    text_dirty_out: *mut bool,\n");
        code.push_str("    key_cleared_out: *mut bool,\n");
        code.push_str("    speaker_toggles_out: *mut u32,\n");
        code.push_str(") -> usize {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let ram = std::slice::from_raw_parts_mut(ram, ram_len);\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom, rom_len);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut text_dirty = false;\n");
        code.push_str("    let mut key_cleared = false;\n");
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("    let mut prev_speaker = *prev_speaker_ptr;\n\n");

        // Initialize old_clocks from current signal values
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");

        // Set keyboard input
        code.push_str(&format!("        signals[{}] = if key_ready {{ (key_data as u64) | 0x80 }} else {{ key_data as u64 }};\n\n", k_idx));

        // Clock falling edge
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // Provide RAM/ROM data based on CPU address (AFTER falling edge, like interpreter)
        code.push_str(&format!("        let cpu_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("        let ram_data = if cpu_addr >= 0xD000 {\n");
        code.push_str("            let rom_idx = cpu_addr - 0xD000;\n");
        code.push_str("            if rom_idx < rom_len { rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC000 {\n");
        code.push_str("            0\n");
        code.push_str("        } else if cpu_addr < ram_len {\n");
        code.push_str("            ram[cpu_addr] as u64\n");
        code.push_str("        } else {\n");
        code.push_str("            0\n");
        code.push_str("        };\n");
        // Write to ram_do signal (NOT d - that's the write data bus)
        code.push_str(&format!("        signals[{}] = ram_data;\n\n", ram_do_idx));

        // Clock rising edge
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n\n");

        // Handle RAM write (read from d signal, NOT ram_do)
        code.push_str(&format!("        let ram_we = signals[{}];\n", ram_we_idx));
        code.push_str("        if ram_we == 1 {\n");
        code.push_str(&format!("            let write_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("            if write_addr < 0xC000 && write_addr < ram_len {\n");
        code.push_str(&format!("                ram[write_addr] = (signals[{}] & 0xFF) as u8;\n", d_idx));
        code.push_str("                // Check for text page write ($0400-$07FF)\n");
        code.push_str("                if write_addr >= 0x0400 && write_addr <= 0x07FF {\n");
        code.push_str("                    text_dirty = true;\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Check for keyboard strobe clear
        code.push_str(&format!("        if signals[{}] == 1 {{\n", read_key_idx));
        code.push_str("            key_cleared = true;\n");
        code.push_str("        }\n\n");

        // Check for speaker toggle
        code.push_str(&format!("        let speaker = signals[{}];\n", speaker_idx));
        code.push_str("        if speaker != prev_speaker {\n");
        code.push_str("            speaker_toggles += 1;\n");
        code.push_str("            prev_speaker = speaker;\n");
        code.push_str("        }\n");

        code.push_str("    }\n\n");

        code.push_str("    *prev_speaker_ptr = prev_speaker;\n");
        code.push_str("    *text_dirty_out = text_dirty;\n");
        code.push_str("    *key_cleared_out = key_cleared;\n");
        code.push_str("    *speaker_toggles_out = speaker_toggles;\n");
        code.push_str("    n\n");
        code.push_str("}\n");

        code
    }
}
