//! Apple II full system simulation extension
//!
//! Provides batched CPU cycle execution with memory bridging for Apple II
//! including Disk II controller emulation for disk boot support.

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

/// Track size in nibbles (6656 bytes per track)
pub const TRACK_SIZE: usize = 6656;

/// Number of tracks on a disk
pub const NUM_TRACKS: usize = 35;

/// Cycles between disk bytes (~32 CPU cycles at 1MHz, ~430 at 14MHz)
pub const DISK_BYTE_CYCLES: usize = 430;

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
    /// ROM (12KB) - main ROM at $D000-$FFFF
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

    // Disk II controller state
    /// Slot ROM (256 bytes) at $C600-$C6FF for slot 6
    pub disk_slot_rom: Vec<u8>,
    /// Track data for all 35 tracks (each 6656 bytes)
    pub disk_tracks: Vec<Vec<u8>>,
    /// Current track number (0-34)
    pub disk_current_track: usize,
    /// Current byte position within track
    pub disk_byte_pos: usize,
    /// Cycle counter for disk byte timing
    pub disk_cycle_counter: usize,
    /// Motor on flag
    pub disk_motor_on: bool,
    /// Stepper motor phases (4 bits)
    pub disk_phases: u8,
    /// Q6 latch state
    pub disk_q6: bool,
    /// Q7 latch state
    pub disk_q7: bool,
    /// Drive select (false = drive 1, true = drive 2)
    pub disk_drive2: bool,
    /// Data latch for read operations
    pub disk_data_latch: u8,
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
            // Initialize disk controller state
            disk_slot_rom: vec![0u8; 256],
            disk_tracks: (0..NUM_TRACKS).map(|_| vec![0u8; TRACK_SIZE]).collect(),
            disk_current_track: 0,
            disk_byte_pos: 0,
            disk_cycle_counter: 0,
            disk_motor_on: false,
            disk_phases: 0,
            disk_q6: false,
            disk_q7: false,
            disk_drive2: false,
            disk_data_latch: 0,
        }
    }

    /// Load disk slot ROM (P5 PROM boot code at $C600)
    pub fn load_disk_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.disk_slot_rom.len());
        self.disk_slot_rom[..len].copy_from_slice(&data[..len]);
    }

    /// Load track nibble data
    pub fn load_track(&mut self, track: usize, data: &[u8]) {
        if track < NUM_TRACKS {
            let len = data.len().min(TRACK_SIZE);
            self.disk_tracks[track][..len].copy_from_slice(&data[..len]);
        }
    }

    /// Get current track number
    pub fn get_track(&self) -> usize {
        self.disk_current_track
    }

    /// Check if motor is on
    pub fn is_motor_on(&self) -> bool {
        self.disk_motor_on
    }

    /// Handle disk I/O access ($C0E0-$C0EF for slot 6)
    /// Returns (read_data, is_read)
    pub fn handle_disk_io(&mut self, addr: u16) -> (u8, bool) {
        let reg = addr & 0x0F;

        match reg {
            // Phase control (C0E0-C0E7)
            0x0 => { self.disk_phases &= !0x01; self.update_track_from_phases(); }
            0x1 => { self.disk_phases |= 0x01; self.update_track_from_phases(); }
            0x2 => { self.disk_phases &= !0x02; self.update_track_from_phases(); }
            0x3 => { self.disk_phases |= 0x02; self.update_track_from_phases(); }
            0x4 => { self.disk_phases &= !0x04; self.update_track_from_phases(); }
            0x5 => { self.disk_phases |= 0x04; self.update_track_from_phases(); }
            0x6 => { self.disk_phases &= !0x08; self.update_track_from_phases(); }
            0x7 => { self.disk_phases |= 0x08; self.update_track_from_phases(); }
            // Motor control
            0x8 => { self.disk_motor_on = false; }
            0x9 => { self.disk_motor_on = true; }
            // Drive select
            0xA => { self.disk_drive2 = false; }
            0xB => { self.disk_drive2 = true; }
            // Q6/Q7 latches
            0xC => { self.disk_q6 = false; }
            0xD => { self.disk_q6 = true; }
            0xE => { self.disk_q7 = false; }
            0xF => { self.disk_q7 = true; }
            _ => {}
        }

        // Read mode: Q6=0, Q7=0 reads data at $C0EC
        if reg == 0xC && !self.disk_q7 {
            // Read data from disk
            let data = self.read_disk_byte();
            return (data, true);
        }

        (0, false)
    }

    /// Read next byte from disk (advances position based on timing)
    fn read_disk_byte(&mut self) -> u8 {
        if !self.disk_motor_on {
            return 0;
        }

        let track = self.disk_current_track;
        if track >= NUM_TRACKS {
            return 0;
        }

        let byte = self.disk_tracks[track][self.disk_byte_pos];
        self.disk_data_latch = byte;
        byte
    }

    /// Advance disk byte position (called based on cycle timing)
    pub fn advance_disk_position(&mut self) {
        if self.disk_motor_on {
            self.disk_cycle_counter += 1;
            if self.disk_cycle_counter >= DISK_BYTE_CYCLES {
                self.disk_cycle_counter = 0;
                self.disk_byte_pos = (self.disk_byte_pos + 1) % TRACK_SIZE;
            }
        }
    }

    /// Update track position based on stepper phases
    fn update_track_from_phases(&mut self) {
        // Simple stepper motor emulation
        // Each track has 4 phases, phases are at 90 degree intervals
        // The stepper moves based on which adjacent phase is activated

        // Count set phases
        let phase_count = self.disk_phases.count_ones();
        if phase_count != 1 {
            return; // Need exactly one phase active for movement
        }

        // Find the active phase (0-3)
        let active_phase = match self.disk_phases {
            0x01 => 0,
            0x02 => 1,
            0x04 => 2,
            0x08 => 3,
            _ => return,
        };

        // Current track maps to phase: track 0 = phase 0, track 1 = phase 2, etc.
        // Half-tracks: even tracks use phases 0,2, odd use 1,3
        let current_phase = (self.disk_current_track * 2) % 4;

        // Calculate phase difference
        let diff = (active_phase as i32 - current_phase as i32 + 4) % 4;

        match diff {
            1 => {
                // Step in (towards center)
                if self.disk_current_track < NUM_TRACKS - 1 {
                    self.disk_current_track += 1;
                }
            }
            3 => {
                // Step out (towards edge)
                if self.disk_current_track > 0 {
                    self.disk_current_track -= 1;
                }
            }
            _ => {}
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

    /// Run batched CPU cycles with memory bridging and disk I/O
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
            // Extended function signature with disk support
            type RunCpuCyclesFn = unsafe extern "C" fn(
                signals: *mut u64, signals_len: usize,
                ram: *mut u8, ram_len: usize,
                rom: *const u8, rom_len: usize,
                slot_rom: *const u8, slot_rom_len: usize,
                track_data: *const u8, track_len: usize,
                disk_byte_pos: *mut usize,
                disk_cycle_counter: *mut usize,
                disk_motor_on: *mut bool,
                disk_phases: *mut u8,
                disk_q6: *mut bool,
                disk_q7: *mut bool,
                disk_current_track: *mut usize,
                n: usize,
                key_data: u8,
                key_ready: bool,
                prev_speaker_ptr: *mut u64,
                text_dirty_out: *mut bool,
                key_cleared_out: *mut bool,
                speaker_toggles_out: *mut u32,
            ) -> usize;

            let func: libloading::Symbol<RunCpuCyclesFn> = lib.get(b"run_cpu_cycles")
                .expect("run_cpu_cycles function not found - is this an Apple II IR?");

            let mut text_dirty = false;
            let mut key_cleared = false;
            let mut speaker_toggles: u32 = 0;

            // Get current track data pointer
            let track_data = if self.disk_current_track < NUM_TRACKS {
                self.disk_tracks[self.disk_current_track].as_ptr()
            } else {
                std::ptr::null()
            };
            let track_len = if self.disk_current_track < NUM_TRACKS {
                self.disk_tracks[self.disk_current_track].len()
            } else {
                0
            };

            let cycles_run = func(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.ram.as_mut_ptr(),
                self.ram.len(),
                self.rom.as_ptr(),
                self.rom.len(),
                self.disk_slot_rom.as_ptr(),
                self.disk_slot_rom.len(),
                track_data,
                track_len,
                &mut self.disk_byte_pos,
                &mut self.disk_cycle_counter,
                &mut self.disk_motor_on,
                &mut self.disk_phases,
                &mut self.disk_q6,
                &mut self.disk_q7,
                &mut self.disk_current_track,
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

    /// Generate Apple II specific batched execution code with disk I/O support
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
        code.push_str("// Apple II Extension: Batched CPU Cycle Execution with Disk I/O\n");
        code.push_str("// ============================================================================\n\n");

        // Constants for disk timing
        code.push_str("const DISK_BYTE_CYCLES: usize = 430;\n");
        code.push_str("const TRACK_SIZE: usize = 6656;\n");
        code.push_str("const NUM_TRACKS: usize = 35;\n\n");

        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_cpu_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    ram: *mut u8,\n");
        code.push_str("    ram_len: usize,\n");
        code.push_str("    rom: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    slot_rom: *const u8,\n");
        code.push_str("    slot_rom_len: usize,\n");
        code.push_str("    track_data: *const u8,\n");
        code.push_str("    track_len: usize,\n");
        code.push_str("    disk_byte_pos: *mut usize,\n");
        code.push_str("    disk_cycle_counter: *mut usize,\n");
        code.push_str("    disk_motor_on: *mut bool,\n");
        code.push_str("    disk_phases: *mut u8,\n");
        code.push_str("    disk_q6: *mut bool,\n");
        code.push_str("    disk_q7: *mut bool,\n");
        code.push_str("    disk_current_track: *mut usize,\n");
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
        code.push_str("    let slot_rom = if slot_rom.is_null() { &[] as &[u8] } else { std::slice::from_raw_parts(slot_rom, slot_rom_len) };\n");
        code.push_str("    let track_data = if track_data.is_null() { &[] as &[u8] } else { std::slice::from_raw_parts(track_data, track_len) };\n");
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

        // Provide RAM/ROM/disk data based on CPU address (AFTER falling edge, like interpreter)
        code.push_str(&format!("        let cpu_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("        let ram_data = if cpu_addr >= 0xD000 {\n");
        code.push_str("            // Main ROM ($D000-$FFFF)\n");
        code.push_str("            let rom_idx = cpu_addr - 0xD000;\n");
        code.push_str("            if rom_idx < rom_len { rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC600 && cpu_addr < 0xC700 {\n");
        code.push_str("            // Slot 6 ROM ($C600-$C6FF) - Disk II boot ROM\n");
        code.push_str("            let rom_idx = cpu_addr - 0xC600;\n");
        code.push_str("            if rom_idx < slot_rom.len() { slot_rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC0E0 && cpu_addr < 0xC0F0 {\n");
        code.push_str("            // Disk II I/O ($C0E0-$C0EF for slot 6)\n");
        code.push_str("            let reg = cpu_addr & 0x0F;\n");
        code.push_str("            match reg {\n");
        code.push_str("                // Phase control\n");
        code.push_str("                0x0 => { *disk_phases &= !0x01; }\n");
        code.push_str("                0x1 => { *disk_phases |= 0x01; }\n");
        code.push_str("                0x2 => { *disk_phases &= !0x02; }\n");
        code.push_str("                0x3 => { *disk_phases |= 0x02; }\n");
        code.push_str("                0x4 => { *disk_phases &= !0x04; }\n");
        code.push_str("                0x5 => { *disk_phases |= 0x04; }\n");
        code.push_str("                0x6 => { *disk_phases &= !0x08; }\n");
        code.push_str("                0x7 => { *disk_phases |= 0x08; }\n");
        code.push_str("                // Motor control\n");
        code.push_str("                0x8 => { *disk_motor_on = false; }\n");
        code.push_str("                0x9 => { *disk_motor_on = true; }\n");
        code.push_str("                // Q6/Q7 latches\n");
        code.push_str("                0xC => { *disk_q6 = false; }\n");
        code.push_str("                0xD => { *disk_q6 = true; }\n");
        code.push_str("                0xE => { *disk_q7 = false; }\n");
        code.push_str("                0xF => { *disk_q7 = true; }\n");
        code.push_str("                _ => {}\n");
        code.push_str("            }\n");
        code.push_str("            // Read data register ($C0EC with Q6=0, Q7=0)\n");
        code.push_str("            if reg == 0xC && !*disk_q7 && *disk_motor_on && !track_data.is_empty() {\n");
        code.push_str("                let pos = *disk_byte_pos;\n");
        code.push_str("                if pos < track_data.len() { track_data[pos] as u64 } else { 0 }\n");
        code.push_str("            } else {\n");
        code.push_str("                0\n");
        code.push_str("            }\n");
        code.push_str("        } else if cpu_addr >= 0xC000 {\n");
        code.push_str("            // Other I/O space\n");
        code.push_str("            0\n");
        code.push_str("        } else if cpu_addr < ram_len {\n");
        code.push_str("            ram[cpu_addr] as u64\n");
        code.push_str("        } else {\n");
        code.push_str("            0\n");
        code.push_str("        };\n");
        // Write to ram_do signal (NOT d - that's the write data bus)
        code.push_str(&format!("        signals[{}] = ram_data;\n\n", ram_do_idx));

        // Advance disk position based on timing
        code.push_str("        if *disk_motor_on {\n");
        code.push_str("            *disk_cycle_counter += 1;\n");
        code.push_str("            if *disk_cycle_counter >= DISK_BYTE_CYCLES {\n");
        code.push_str("                *disk_cycle_counter = 0;\n");
        code.push_str("                *disk_byte_pos = (*disk_byte_pos + 1) % TRACK_SIZE;\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

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
