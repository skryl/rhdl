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
    /// Current track number (0-34) - computed from half_track
    pub disk_current_track: usize,
    /// Half-track position (0-69) - the actual stepper position
    pub disk_half_track: usize,
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
    /// Data latch valid (high bit set when new data ready)
    pub disk_latch_valid: bool,
    /// Last byte actually returned to CPU (for tracking new bytes)
    pub disk_last_read: u8,
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
            disk_half_track: 0,
            disk_byte_pos: 0,
            disk_cycle_counter: 0,
            disk_motor_on: false,
            disk_phases: 0,
            disk_q6: false,
            disk_q7: false,
            disk_drive2: false,
            disk_data_latch: 0,
            disk_latch_valid: true,  // Start valid so first read works
            disk_last_read: 0x00,  // Initialize to 0 (never a valid disk nibble, since all valid nibbles have bit 7 set)
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
            // Extended function signature with disk support - all tracks passed
            type RunCpuCyclesFn = unsafe extern "C" fn(
                signals: *mut u64, signals_len: usize,
                ram: *mut u8, ram_len: usize,
                rom: *const u8, rom_len: usize,
                slot_rom: *const u8, slot_rom_len: usize,
                all_tracks: *const u8, num_tracks: usize, track_size: usize,
                disk_byte_pos: *mut usize,
                disk_cycle_counter: *mut usize,
                disk_motor_on: *mut bool,
                disk_phases: *mut u8,
                disk_q6: *mut bool,
                disk_q7: *mut bool,
                disk_current_track: *mut usize,
                disk_half_track: *mut usize,
                disk_latch_valid: *mut bool,
                disk_data_latch: *mut u8,
                disk_last_read: *mut u8,
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

            // Flatten all track data into a single contiguous array for the generated code
            // This allows track switching during execution
            let all_tracks_flat: Vec<u8> = self.disk_tracks.iter()
                .flat_map(|t| t.iter().copied())
                .collect();

            let cycles_run = func(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.ram.as_mut_ptr(),
                self.ram.len(),
                self.rom.as_ptr(),
                self.rom.len(),
                self.disk_slot_rom.as_ptr(),
                self.disk_slot_rom.len(),
                all_tracks_flat.as_ptr(),
                NUM_TRACKS,
                TRACK_SIZE,
                &mut self.disk_byte_pos,
                &mut self.disk_cycle_counter,
                &mut self.disk_motor_on,
                &mut self.disk_phases,
                &mut self.disk_q6,
                &mut self.disk_q7,
                &mut self.disk_current_track,
                &mut self.disk_half_track,
                &mut self.disk_latch_valid,
                &mut self.disk_data_latch,
                &mut self.disk_last_read,
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

        let ram_do_idx = *core.name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *core.name_to_idx.get("ram_we").unwrap_or(&0);
        let cpu_we_idx = core.name_to_idx.get("cpu_we").copied().unwrap_or(0);
        let d_idx = *core.name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *core.name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *core.name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *core.name_to_idx.get("read_key").unwrap_or(&0);
        let speaker_idx = *core.name_to_idx.get("speaker").unwrap_or(&0);
        let cpu_addr_idx = *core.name_to_idx.get("cpu__addr_reg").unwrap_or(&0);

        // Disk controller output - we inject disk data here instead of into cpu__di
        // This preserves the HDL mux architecture: cpu_din = mux(disk_select, disk_dout, ram_do, ...)
        // By injecting into disk__d_out, the mux correctly routes our data when disk_select is true
        let disk_d_out_idx = core.name_to_idx.get("disk__d_out")
            .copied()
            .unwrap_or(0);

        // CPU data input - for debug tracing only (HDL mux computes this from disk_dout and ram_do)
        let cpu_di_idx = core.name_to_idx.get("cpu__di")
            .or_else(|| core.name_to_idx.get("cpu_di"))
            .copied()
            .unwrap_or(0);

        // CPU debug registers
        let cpu_y_reg_idx = core.name_to_idx.get("cpu__y_reg").copied().unwrap_or(0);
        let cpu_a_reg_idx = core.name_to_idx.get("cpu__a_reg").copied().unwrap_or(0);
        let cpu_flag_n_idx = core.name_to_idx.get("cpu__flag_n").copied().unwrap_or(0);
        let cpu_opcode_idx = core.name_to_idx.get("cpu__opcode").copied().unwrap_or(0);

        eprintln!("Apple2 generate_code: cpu_addr_idx={}, ram_do_idx={}, disk_d_out_idx={}",
                  cpu_addr_idx, ram_do_idx, disk_d_out_idx);
        eprintln!("Apple2 generate_code: cpu_y_reg_idx={}, cpu_a_reg_idx={}, cpu_flag_n_idx={}, cpu_opcode_idx={}",
                  cpu_y_reg_idx, cpu_a_reg_idx, cpu_flag_n_idx, cpu_opcode_idx);

        let clock_indices: Vec<usize> = core.clock_indices.clone();

        // Print clock domain info
        eprintln!("Apple2 generate_code: {} clock domains", clock_indices.len());
        for (i, &clk_idx) in clock_indices.iter().enumerate() {
            // Find signal name for this clock
            let clk_name = core.name_to_idx.iter()
                .find(|(_, &v)| v == clk_idx)
                .map(|(k, _)| k.as_str())
                .unwrap_or("unknown");
            eprintln!("  Clock domain {}: signal {} ({})", i, clk_idx, clk_name);
        }
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        code.push_str("\n// ============================================================================\n");
        code.push_str("// Apple II Extension: Batched CPU Cycle Execution with Disk I/O\n");
        code.push_str("// ============================================================================\n\n");

        // Constants for disk timing
        code.push_str("const DISK_BYTE_CYCLES: usize = 430;\n");
        code.push_str("const TRACK_SIZE: usize = 6656;\n");
        code.push_str("const NUM_TRACKS: usize = 35;\n\n");

        // Generate a custom evaluate function that SKIPS disk__d_out
        // This is the architectural fix: instead of skipping cpu__di (which breaks the HDL mux),
        // we skip disk__d_out and inject disk data there. The HDL mux then correctly routes
        // disk data to cpu_din when disk_select is true, or ram_do when disk_select is false.
        code.push_str("/// Custom evaluate function that skips disk__d_out assignment\n");
        code.push_str("/// disk__d_out is injected from Rust-side disk emulation\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("unsafe fn evaluate_apple2_inline(signals: &mut [u64]) {\n");
        let skip_signals = vec![disk_d_out_idx];
        let eval_body = core.generate_evaluate_with_skips(&skip_signals);
        code.push_str(&eval_body);
        code.push_str("}\n\n");

        // Generate custom Apple2 tick function
        // Injects disk data into disk__d_out, letting the HDL mux compute cpu__di correctly
        code.push_str("/// Custom Apple2 tick function that injects disk data into disk__d_out\n");
        code.push_str("/// The HDL mux then correctly routes disk_dout or ram_do to cpu_din.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("unsafe fn tick_apple2_inline(\n"));
        code.push_str("    signals: &mut [u64],\n");
        code.push_str(&format!("    old_clocks: &mut [u64; {}],\n", num_clocks));
        code.push_str(&format!("    next_regs: &mut [u64; {}],\n", num_regs.max(1)));
        code.push_str("    disk_data: u64,\n");
        code.push_str(") {\n");

        // Step 1: Inject disk_data into disk__d_out FIRST
        // This is the data that will be used when the CPU accesses disk I/O or slot ROM
        code.push_str(&format!("    // Inject disk data into disk__d_out BEFORE evaluate\n"));
        code.push_str(&format!("    signals[{}] = disk_data;\n\n", disk_d_out_idx));

        // Step 2: Evaluate combinational logic (skips disk__d_out, so our value is preserved)
        // The HDL mux will now correctly compute cpu__di from disk__d_out when disk_select is true
        code.push_str("    evaluate_apple2_inline(signals);\n\n");

        // Step 4: Compute next values for all registers (copied from CoreSimulator)
        let mut seq_idx = 0;
        for process in &core.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                if let Some(&target_idx) = core.name_to_idx.get(&stmt.target) {
                    let width = core.widths.get(target_idx).copied().unwrap_or(64);
                    let expr_code = core.expr_to_rust(&stmt.expr);
                    code.push_str(&format!("    next_regs[{}] = ({}) & {};\n",
                                           seq_idx, expr_code, CoreSimulator::mask_const(width)));
                    seq_idx += 1;
                }
            }
        }
        code.push_str("\n");

        // Step 4: Track which registers have been updated
        code.push_str(&format!("    let mut updated = [false; {}];\n\n", num_regs.max(1)));

        // Step 5: Check for rising edges
        for (domain_idx, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    // Clock domain {} (signal {})\n", domain_idx, clk));
            code.push_str(&format!("    if old_clocks[{}] == 0 && signals[{}] == 1 {{\n", domain_idx, clk));

            for &(seq_idx, target_idx) in &core.clock_domain_assigns[domain_idx] {
                code.push_str(&format!("        if !updated[{}] {{ signals[{}] = next_regs[{}]; updated[{}] = true; }}\n",
                                       seq_idx, target_idx, seq_idx, seq_idx));
            }

            code.push_str("    }\n");
        }
        code.push_str("\n");

        // Step 6: Loop for derived clock propagation
        code.push_str("    // Loop for derived clock propagation\n");
        code.push_str("    for _iter in 0..10 {\n");
        code.push_str(&format!("        let mut clock_before = [0u64; {}];\n", num_clocks));
        for (domain_idx, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        clock_before[{}] = signals[{}];\n", domain_idx, clk));
        }
        code.push_str("\n");
        code.push_str("        evaluate_apple2_inline(signals);\n");

        // Check for NEW rising edges
        code.push_str("        let mut any_rising = false;\n");
        for (domain_idx, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        if clock_before[{}] == 0 && signals[{}] == 1 {{\n", domain_idx, clk));
            code.push_str("            any_rising = true;\n");
            for &(seq_idx, target_idx) in &core.clock_domain_assigns[domain_idx] {
                code.push_str(&format!("            if !updated[{}] {{ signals[{}] = next_regs[{}]; updated[{}] = true; }}\n",
                                       seq_idx, target_idx, seq_idx, seq_idx));
            }
            code.push_str("        }\n");
        }
        code.push_str("\n");
        code.push_str("        if !any_rising { break; }\n");
        code.push_str("    }\n\n");

        // Step 7: Final evaluate (disk__d_out is preserved since we use evaluate_apple2_inline)
        code.push_str("    evaluate_apple2_inline(signals);\n");
        code.push_str("}\n\n");

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
        code.push_str("    all_tracks: *const u8,\n");
        code.push_str("    num_tracks: usize,\n");
        code.push_str("    track_size: usize,\n");
        code.push_str("    disk_byte_pos: *mut usize,\n");
        code.push_str("    disk_cycle_counter: *mut usize,\n");
        code.push_str("    disk_motor_on: *mut bool,\n");
        code.push_str("    disk_phases: *mut u8,\n");
        code.push_str("    disk_q6: *mut bool,\n");
        code.push_str("    disk_q7: *mut bool,\n");
        code.push_str("    disk_current_track: *mut usize,\n");
        code.push_str("    disk_half_track: *mut usize,\n");
        code.push_str("    disk_latch_valid: *mut bool,\n");
        code.push_str("    disk_data_latch: *mut u8,\n");
        code.push_str("    disk_last_read: *mut u8,\n");
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
        code.push_str("    let all_tracks_len = num_tracks * track_size;\n");
        code.push_str("    let all_tracks = if all_tracks.is_null() { &[] as &[u8] } else { std::slice::from_raw_parts(all_tracks, all_tracks_len) };\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut text_dirty = false;\n");
        code.push_str("    let mut key_cleared = false;\n");
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("    let mut prev_speaker = *prev_speaker_ptr;\n");
        code.push_str("    let mut sub_cycle_counter: usize = 0;  // Track sub-cycles within CPU cycle\n\n");

        // Initialize old_clocks from current signal values
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for cycle_num in 0..n {\n");

        // Set keyboard input
        code.push_str(&format!("        signals[{}] = if key_ready {{ (key_data as u64) | 0x80 }} else {{ key_data as u64 }};\n\n", k_idx));

        // Read CPU address BEFORE clock edge (it's a register, so stable value from previous cycle)
        code.push_str(&format!("        let cpu_addr = (signals[{}] as usize) & 0xFFFF;\n\n", cpu_addr_idx));

        // Minimal debug: track cycle count every 100K cycles and key boot ROM addresses
        code.push_str("        {\n");
        code.push_str("            static CYCLE_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let cycle_count = CYCLE_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("            if cycle_count % 100000 == 0 {\n");
        code.push_str("                eprintln!(\"CYCLE#{}: cpu_addr=${:04X} motor={} track={}\", cycle_count, cpu_addr, *disk_motor_on, *disk_current_track);\n");
        code.push_str("            }\n");
        // Track key boot ROM addresses on sub_cycle 0
        code.push_str("            if sub_cycle_counter == 0 {\n");
        code.push_str("                // Track D5 search loop and key addresses\n");
        code.push_str(&format!("                let cpu_x = signals[{}];\n",
            core.name_to_idx.get("cpu__x").copied().unwrap_or(202)));
        // Track key boot ROM addresses
        code.push_str("                let _ = cpu_x;  // Suppress unused warning\n");
        // Trace when CPU A register changes (any value)
        code.push_str(&format!("                let cpu_a = signals[{}];\n", cpu_a_reg_idx));
        code.push_str(&format!("                let cpu_di = signals[{}];\n", cpu_di_idx));
        code.push_str(&format!("                let disk_dout = signals[{}];\n", disk_d_out_idx));
        code.push_str("                static LAST_A: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);\n");
        code.push_str("                let last_a = LAST_A.load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if cpu_a != last_a {\n");
        code.push_str("                    static A_CHANGE_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                    let change_cnt = A_CHANGE_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    // Log first 30 A register changes to see what values it receives\n");
        code.push_str("                    if change_cnt < 30 {\n");
        code.push_str("                        eprintln!(\"A_CHANGE#{}: A=${:02X} -> ${:02X} addr=${:04X} cpu_di=${:02X} disk_dout=${:02X}\", change_cnt, last_a, cpu_a, cpu_addr, cpu_di, disk_dout);\n");
        code.push_str("                    }\n");
        code.push_str("                    LAST_A.store(cpu_a, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if cpu_a == 0xD5 || cpu_a == 0xAA || cpu_a == 0x96 || cpu_a == 0xAD {\n");
        code.push_str("                        static KEY_A_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                        let cnt = KEY_A_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if cnt < 20 {\n");
        code.push_str("                            eprintln!(\"CPU_A#{}: A=${:02X} at addr=${:04X}\", cnt, cpu_a, cpu_addr);\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("                // $C69A: sector comparison, $C6A4: branch after sector match, $C6A6: data reading start\n");
        code.push_str("                if cpu_addr == 0xC69A || cpu_addr == 0xC6A4 || cpu_addr == 0xC6A6 {\n");
        code.push_str("                    static BOOT_ADDR_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                    let cnt = BOOT_ADDR_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if cnt < 20 {\n");
        code.push_str(&format!("                        let cpu_a = signals[{}];\n", cpu_a_reg_idx));
        code.push_str(&format!("                        let cpu_p = signals[{}] | (signals[{}] << 1) | (signals[{}] << 6) | (signals[{}] << 7);\n",
            core.name_to_idx.get("cpu__flag_c").copied().unwrap_or(0),
            core.name_to_idx.get("cpu__flag_z").copied().unwrap_or(0),
            core.name_to_idx.get("cpu__flag_v").copied().unwrap_or(0),
            core.name_to_idx.get("cpu__flag_n").copied().unwrap_or(0)));
        code.push_str("                        eprintln!(\"BOOT_ROM#{}: addr=${:04X} A=${:02X} P=${:02X}\", cnt, cpu_addr, cpu_a, cpu_p);\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Advance disk position on sub-cycle 0 only (before computing ram_data)
        // We advance by 14 sub-cycles per CPU cycle to match the simulation rate
        code.push_str("        if sub_cycle_counter == 0 && *disk_motor_on && !all_tracks.is_empty() {\n");
        code.push_str("            let old_byte_pos = *disk_byte_pos;\n");
        code.push_str("            let old_cycle = *disk_cycle_counter;\n");
        code.push_str("            *disk_cycle_counter += 14;  // One CPU cycle worth of sub-cycles\n");
        // Debug: track disk advance timing
        code.push_str("            static DISK_ADVANCE_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let advance_cnt = DISK_ADVANCE_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("            if advance_cnt < 5 || advance_cnt % 100000 == 0 {\n");
        code.push_str("                eprintln!(\"DISK_ADVANCE#{}: old_cycle={} new_cycle={} pos={}\", advance_cnt, old_cycle, *disk_cycle_counter, *disk_byte_pos);\n");
        code.push_str("            }\n");
        code.push_str("            while *disk_cycle_counter >= DISK_BYTE_CYCLES {\n");
        code.push_str("                *disk_cycle_counter -= DISK_BYTE_CYCLES;  // Preserve fractional timing\n");
        code.push_str("                *disk_byte_pos = (*disk_byte_pos + 1) % TRACK_SIZE;\n");
        // Debug: track when position actually changes
        code.push_str("                static POS_CHANGE_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let pos_cnt = POS_CHANGE_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if pos_cnt < 10 || pos_cnt % 10000 == 0 {\n");
        code.push_str("                    eprintln!(\"POS_CHANGE#{}: new_pos={} track={}\", pos_cnt, *disk_byte_pos, *disk_current_track);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("            // If byte position changed, latch new byte and set latch_valid\n");
        code.push_str("            if *disk_byte_pos != old_byte_pos {\n");
        code.push_str("                let track = *disk_current_track;\n");
        code.push_str("                let pos = *disk_byte_pos;\n");
        code.push_str("                if track < num_tracks && pos < track_size {\n");
        code.push_str("                    let new_byte = all_tracks[track * track_size + pos];\n");
        code.push_str("                    *disk_data_latch = new_byte;\n");
        code.push_str("                    *disk_latch_valid = true;  // New byte is ready\n");
        // BYTE_LATCH debug disabled
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Compute disk_data and ram_data separately for proper HDL mux routing
        // - disk_data: for disk addresses ($C600-$C6FF slot ROM, $C0E0-$C0EF disk I/O) -> disk__d_out
        // - ram_data: for everything else (RAM, main ROM, other I/O) -> ram_do
        // The HDL mux then correctly selects: cpu_din = mux(disk_select, disk_dout, ram_do, ...)

        // First compute disk_data for disk addresses
        code.push_str("        let disk_data = if cpu_addr >= 0xC600 && cpu_addr < 0xC700 {\n");
        code.push_str("            // Slot 6 ROM ($C600-$C6FF) - Disk II boot ROM\n");
        code.push_str("            let rom_idx = cpu_addr - 0xC600;\n");
        code.push_str("            if rom_idx < slot_rom.len() { slot_rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC0E0 && cpu_addr < 0xC0F0 {\n");
        code.push_str("            // Disk II I/O ($C0E0-$C0EF for slot 6)\n");
        code.push_str("            let reg = cpu_addr & 0x0F;\n");
        code.push_str("            // Q6/Q7 and motor latches update on EVERY access (address-triggered)\n");
        code.push_str("            match reg {\n");
        code.push_str("                0x8 => { *disk_motor_on = false; }\n");
        code.push_str("                0x9 => {\n");
        code.push_str("                    if !*disk_motor_on && !all_tracks.is_empty() {\n");
        code.push_str("                        // Motor just turned on - latch current byte and set valid\n");
        code.push_str("                        let track = *disk_current_track;\n");
        code.push_str("                        let pos = *disk_byte_pos;\n");
        code.push_str("                        if track < num_tracks && pos < track_size {\n");
        code.push_str("                            *disk_data_latch = all_tracks[track * track_size + pos];\n");
        code.push_str("                            *disk_latch_valid = true;  // First byte is ready\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                    *disk_motor_on = true;\n");
        code.push_str("                }\n");
        code.push_str("                0xC => { *disk_q6 = false; }\n");
        code.push_str("                0xD => { *disk_q6 = true; }\n");
        code.push_str("                0xE => { *disk_q7 = false; }\n");
        code.push_str("                0xF => { *disk_q7 = true; }\n");
        code.push_str("                _ => {}\n");
        code.push_str("            }\n");
        code.push_str("            // Handle phase changes only on sub-cycle 0 to avoid repeated updates\n");
        code.push_str("            if sub_cycle_counter == 0 {\n");
        code.push_str("                let old_phases = *disk_phases;\n");
        code.push_str("                match reg {\n");
        code.push_str("                    // Phase control\n");
        code.push_str("                    0x0 => { *disk_phases &= !0x01; }\n");
        code.push_str("                    0x1 => { *disk_phases |= 0x01; }\n");
        code.push_str("                    0x2 => { *disk_phases &= !0x02; }\n");
        code.push_str("                    0x3 => { *disk_phases |= 0x02; }\n");
        code.push_str("                    0x4 => { *disk_phases &= !0x04; }\n");
        code.push_str("                    0x5 => { *disk_phases |= 0x04; }\n");
        code.push_str("                    0x6 => { *disk_phases &= !0x08; }\n");
        code.push_str("                    0x7 => { *disk_phases |= 0x08; }\n");
        code.push_str("                    _ => {}\n");
        code.push_str("                }\n");
        code.push_str("                // Handle stepper motor track stepping\n");
        code.push_str("                let newly_on = *disk_phases & !old_phases;\n");
        // Stepper motor logic using half-tracks (matching HDL implementation)
        // Half-track position: 0-69 for 35 tracks (2 half-tracks per track)
        // Current quadrant = half_track / 2 % 4
        code.push_str("                if newly_on != 0 {\n");
        code.push_str("                    let new_phase = newly_on.trailing_zeros() as i32;\n");
        code.push_str("                    if new_phase < 4 {\n");
        code.push_str("                        let half_track = *disk_half_track as i32;\n");
        code.push_str("                        let current_quadrant = (half_track / 2) % 4;\n");
        code.push_str("                        let next_quadrant = (current_quadrant + 1) % 4;\n");
        code.push_str("                        let prev_quadrant = (current_quadrant + 3) % 4;\n");
        code.push_str("                        let old_track = *disk_current_track;\n");
        // Step inward if active phase matches next quadrant
        code.push_str("                        if new_phase == next_quadrant && half_track < 69 {\n");
        code.push_str("                            *disk_half_track = (half_track + 1) as usize;\n");
        code.push_str("                            *disk_current_track = *disk_half_track / 2;\n");
        code.push_str("                        } else if new_phase == prev_quadrant && half_track > 0 {\n");
        // Step outward if active phase matches prev quadrant
        code.push_str("                            *disk_half_track = (half_track - 1) as usize;\n");
        code.push_str("                            *disk_current_track = *disk_half_track / 2;\n");
        code.push_str("                        }\n");
        // Only log when actual track changes (not half-track)
        code.push_str("                        if old_track != *disk_current_track {\n");
        code.push_str("                            eprintln!(\"TRACK_CHANGE: {} -> {}\", old_track, *disk_current_track);\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("            // Read data register ($C0EC with Q6=0, Q7=0)\n");
        code.push_str("            if reg == 0xC && !*disk_q7 && *disk_motor_on {\n");
        code.push_str("                let latched = *disk_data_latch;\n");
        code.push_str("                let is_valid = *disk_latch_valid;\n");
        // Debug: log when CPU reads $C0EC with latch_valid status
        code.push_str("                static READ_DEBUG_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let read_cnt = READ_DEBUG_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        // KEY_READ debug disabled
        code.push_str("                // Real Disk II: byte stays valid until NEXT byte arrives\n");
        code.push_str("                // The latch holds the byte with bit 7 set until replaced by the next byte\n");
        code.push_str("                // Don't clear latch_valid on read - it's cleared implicitly when next byte arrives\n");
        code.push_str("                // (by setting latch_valid=true for the new byte)\n");
        code.push_str("                let result = if is_valid {\n");
        code.push_str("                    latched as u64\n");
        code.push_str("                } else {\n");
        code.push_str("                    // Motor just started - first few bytes may not be valid yet\n");
        code.push_str("                    (latched & 0x7F) as u64\n");
        code.push_str("                };\n");
        // Minimal debug: track sector address headers found
        // Only process state machine when byte position changes (new byte arrived)
        code.push_str("                static D5_STATE: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);\n");
        code.push_str("                static SECTOR_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                static LAST_BYTE_POS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(usize::MAX);\n");
        code.push_str("                let current_pos = *disk_byte_pos;\n");
        code.push_str("                let last_pos = LAST_BYTE_POS.load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                let new_byte = current_pos != last_pos;\n");
        code.push_str("                if new_byte {\n");
        code.push_str("                    LAST_BYTE_POS.store(current_pos, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                }\n");
        code.push_str("                if new_byte && is_valid {\n");
        code.push_str("                    let d5_state = D5_STATE.load(std::sync::atomic::Ordering::Relaxed);\n");
        // State machine: 0=idle, 1=saw D5, 2=saw D5 AA, 3-10=reading address field
        code.push_str("                    if latched == 0xD5 && d5_state == 0 {\n");
        code.push_str("                        D5_STATE.store(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    } else if d5_state == 1 {\n");
        code.push_str("                        D5_STATE.store(if latched == 0xAA { 2 } else { 0 }, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    } else if d5_state == 2 {\n");
        code.push_str("                        if latched == 0x96 {\n");
        code.push_str("                            D5_STATE.store(3, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else if latched == 0xAD {\n");
        // Data prologue found - log it
        code.push_str("                            static DATA_PROLOGUE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                            let dp_cnt = DATA_PROLOGUE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            if dp_cnt < 20 {\n");
        code.push_str("                                eprintln!(\"DATA_PROLOGUE#{}: D5 AA AD found\", dp_cnt);\n");
        code.push_str("                            }\n");
        code.push_str("                            D5_STATE.store(20, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    } else if d5_state >= 3 && d5_state <= 10 {\n");
        // Read address field bytes
        code.push_str("                        static ADDR_BYTES: [std::sync::atomic::AtomicU8; 8] = [\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0), std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0), std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0), std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0), std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                        ];\n");
        code.push_str("                        let idx = (d5_state - 3) as usize;\n");
        code.push_str("                        ADDR_BYTES[idx].store(latched as u8, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if d5_state == 10 {\n");
        // Decode and log address field
        code.push_str("                            let trk_odd = ADDR_BYTES[2].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let trk_even = ADDR_BYTES[3].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let sec_odd = ADDR_BYTES[4].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let sec_even = ADDR_BYTES[5].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let trk = ((trk_odd << 1) | 1) & trk_even;\n");
        code.push_str("                            let sec = ((sec_odd << 1) | 1) & sec_even;\n");
        code.push_str("                            let cnt = SECTOR_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            if cnt < 20 {\n");
        code.push_str("                                eprintln!(\"SECTOR#{}: trk={} sec={}\", cnt, trk, sec);\n");
        code.push_str("                            }\n");
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        code.push_str("                            D5_STATE.store(d5_state + 1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    } else if d5_state >= 20 {\n");
        code.push_str("                        let data_idx = d5_state as usize - 20;\n");
        code.push_str("                        if data_idx < 343 {\n");
        code.push_str("                            D5_STATE.store((d5_state + 1) as u8, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        // Done reading data field
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("                result\n");
        code.push_str("            } else if reg == 0xC && !*disk_q7 {\n");
        code.push_str("                // Motor is off - return 0\n");
        code.push_str("                0\n");
        code.push_str("            } else {\n");
        code.push_str("                // Q7=1 (write mode) or other register - return 0\n");
        code.push_str("                0\n");
        code.push_str("            }\n");
        code.push_str("        } else {\n");
        code.push_str("            // Not a disk address - return 0 for disk_data\n");
        code.push_str("            0u64\n");
        code.push_str("        };\n\n");

        // Now compute ram_data for non-disk addresses (RAM, main ROM, other I/O)
        code.push_str("        let ram_data = if cpu_addr >= 0xD000 {\n");
        code.push_str("            // Main ROM ($D000-$FFFF)\n");
        code.push_str("            let rom_idx = cpu_addr - 0xD000;\n");
        code.push_str("            if rom_idx < rom_len { rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC000 {\n");
        code.push_str("            // I/O space - return 0 (keyboard etc. handled by HDL)\n");
        code.push_str("            0u64\n");
        code.push_str("        } else if cpu_addr < ram_len {\n");
        code.push_str("            // RAM ($0000-$BFFF)\n");
        code.push_str("            ram[cpu_addr] as u64\n");
        code.push_str("        } else {\n");
        code.push_str("            0u64\n");
        code.push_str("        };\n\n");

        // Inject disk_data into disk__d_out for disk controller output
        // The HDL mux will route this to cpu_din when disk_select is true
        code.push_str(&format!("        signals[{}] = disk_data;  // disk__d_out\n", disk_d_out_idx));
        // Inject ram_data into ram_do for RAM/ROM accesses
        // The HDL mux will route this to cpu_din when disk_select is false
        code.push_str(&format!("        signals[{}] = ram_data;  // ram_do\n", ram_do_idx));
        // Debug: track what cpu__di receives when reading disk data
        code.push_str(&format!("        let cpu_di = signals[{}];\n", cpu_di_idx));
        code.push_str("        if cpu_addr == 0xC0EC && disk_data == 0xD5 {\n");
        code.push_str("            static DI_DEBUG_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let cnt = DI_DEBUG_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("            if cnt < 10 {\n");
        code.push_str(&format!("                let disk_dout = signals[{}];\n", disk_d_out_idx));
        code.push_str(&format!("                let ram_do = signals[{}];\n", ram_do_idx));
        code.push_str("                eprintln!(\"DI_DEBUG#{}: disk_data=$D5 disk__d_out=${:02X} ram_do=${:02X} cpu__di=${:02X}\", cnt, disk_dout, ram_do, cpu_di);\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        // Debug: track when latch has D5 vs when CPU reads
        code.push_str("        {\n");
        code.push_str("            static D5_LATCH_CYCLES: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            static CPU_READ_DURING_D5: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let latch = *disk_data_latch;\n");
        code.push_str("            if latch == 0xD5 && *disk_motor_on {\n");
        code.push_str("                let d5_cycles = D5_LATCH_CYCLES.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if cpu_addr == 0xC0EC {\n");
        code.push_str("                    let reads = CPU_READ_DURING_D5.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if reads < 10 {\n");
        code.push_str("                        eprintln!(\"D5_READ#{}: latch=D5 cpu_addr=C0EC disk_data=${:02X}\", reads, disk_data);\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("                if d5_cycles % 10000 == 0 {\n");
        code.push_str("                    eprintln!(\"D5_LATCH: {} cycles with D5, {} CPU reads, cpu_addr=${:04X}\", d5_cycles, CPU_READ_DURING_D5.load(std::sync::atomic::Ordering::Relaxed), cpu_addr);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n");

        // Clock falling edge - evaluate to settle combinational logic
        // evaluate_apple2_inline skips disk__d_out so our injected value is preserved
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_apple2_inline(signals);\n\n");

        // Clock rising edge - tick function injects disk_data into disk__d_out
        // The HDL mux will then compute cpu__di from disk_dout or ram_do
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        code.push_str("        tick_apple2_inline(signals, &mut old_clocks, &mut next_regs, disk_data);\n\n");
        // Find cpu__clk signal index
        let cpu_clk_idx = core.name_to_idx.get("cpu__clk").copied().unwrap_or(138);
        // Debug: track cpu__clk rising edges and A register updates
        code.push_str(&format!("        let cpu_clk = signals[{}];\n", cpu_clk_idx));
        code.push_str(&format!("        static PREV_CPU_CLK: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);\n"));
        code.push_str("        let prev_cpu_clk = PREV_CPU_CLK.load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("        if prev_cpu_clk == 0 && cpu_clk == 1 {\n");
        code.push_str("            // cpu__clk just rose\n");
        code.push_str("            static CPU_CLK_RISE_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let rise_cnt = CPU_CLK_RISE_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str(&format!("            let cpu_di = signals[{}];\n", cpu_di_idx));
        code.push_str(&format!("            let cpu_a = signals[{}];\n", cpu_a_reg_idx));
        code.push_str(&format!("            let disk_dout = signals[{}];\n", disk_d_out_idx));
        code.push_str("            // Print periodically when motor is on and in disk search area\n");
        code.push_str("            let in_disk_search = cpu_addr >= 0xC65D && cpu_addr <= 0xC670;\n");
        code.push_str("            let show_msg = rise_cnt < 10 || (rise_cnt % 100000 == 0) || (rise_cnt < 300 && disk_data == 0xD5);\n");
        code.push_str("            if show_msg {\n");
        code.push_str("                eprintln!(\"CPU_CLK_RISE#{}: cpu_addr=${:04X} disk_data=${:02X} disk_dout=${:02X} cpu_di=${:02X} cpu_a=${:02X} sub_cycle={} motor={}\", rise_cnt, cpu_addr, disk_data, disk_dout, cpu_di, cpu_a, sub_cycle_counter, *disk_motor_on);\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        code.push_str(&format!("        PREV_CPU_CLK.store(cpu_clk, std::sync::atomic::Ordering::Relaxed);\n\n"));

        // Handle RAM write
        let cpu_we_idx = core.name_to_idx.get("cpu_we").copied().unwrap_or(0);
        code.push_str(&format!("        let ram_we = signals[{}];\n", ram_we_idx));
        code.push_str("        if ram_we == 1 {\n");
        code.push_str(&format!("            let write_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("            if write_addr < 0xC000 && write_addr < ram_len {\n");
        code.push_str(&format!("                ram[write_addr] = (signals[{}] & 0xFF) as u8;\n", d_idx));
        // Check for text page write ($0400-$07FF)
        code.push_str("                if write_addr >= 0x0400 && write_addr <= 0x07FF {\n");
        code.push_str("                    text_dirty = true;\n");
        code.push_str("                }\n");
        // Debug: track boot sector writes ($0800-$08FF)
        code.push_str("                if write_addr >= 0x0800 && write_addr <= 0x08FF {\n");
        code.push_str("                    static BOOT_WRITE_CNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str(&format!("                    let val = signals[{}] & 0xFF;\n", d_idx));
        code.push_str("                    let cnt = BOOT_WRITE_CNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if cnt < 10 {\n");
        code.push_str("                        eprintln!(\"BOOT_WRITE#{}: addr=${:04X} val=${:02X}\", cnt, write_addr, val);\n");
        code.push_str("                    }\n");
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
        code.push_str("        }\n\n");

        // Increment sub-cycle counter (wraps every 14 sub-cycles = 1 CPU cycle)
        code.push_str("        sub_cycle_counter = (sub_cycle_counter + 1) % 14;\n");

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
