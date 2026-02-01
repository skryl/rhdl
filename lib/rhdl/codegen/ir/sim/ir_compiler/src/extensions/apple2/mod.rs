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

        // CPU data input - we need to write directly to cpu__di after evaluate_inline
        // because the HDL mux computes disk_dout from an unloaded ROM component
        let cpu_di_idx = core.name_to_idx.get("cpu__di")
            .or_else(|| core.name_to_idx.get("cpu_di"))
            .copied()
            .unwrap_or(0);

        // CPU debug registers
        let cpu_y_reg_idx = core.name_to_idx.get("cpu__y_reg").copied().unwrap_or(0);
        let cpu_a_reg_idx = core.name_to_idx.get("cpu__a_reg").copied().unwrap_or(0);
        let cpu_flag_n_idx = core.name_to_idx.get("cpu__flag_n").copied().unwrap_or(0);
        let cpu_opcode_idx = core.name_to_idx.get("cpu__opcode").copied().unwrap_or(0);

        eprintln!("Apple2 generate_code: cpu_addr_idx={}, ram_do_idx={}, cpu_di_idx={}",
                  cpu_addr_idx, ram_do_idx, cpu_di_idx);
        eprintln!("Apple2 generate_code: cpu_y_reg_idx={}, cpu_a_reg_idx={}, cpu_flag_n_idx={}, cpu_opcode_idx={}",
                  cpu_y_reg_idx, cpu_a_reg_idx, cpu_flag_n_idx, cpu_opcode_idx);

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

        // Generate a custom evaluate function that SKIPS cpu__di
        // This is critical: the HDL mux computes cpu__di from disk_dout which reads
        // from an unloaded ROM. We need to inject ram_data into cpu__di manually,
        // and prevent evaluate from overwriting it.
        code.push_str("/// Custom evaluate function that skips cpu__di assignment\n");
        code.push_str("/// cpu__di is injected manually from ram_data\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("unsafe fn evaluate_apple2_inline(signals: &mut [u64]) {\n");
        let skip_signals = vec![cpu_di_idx];
        let eval_body = core.generate_evaluate_with_skips(&skip_signals);
        code.push_str(&eval_body);
        code.push_str("}\n\n");

        // Generate custom Apple2 tick function that takes ram_data as parameter
        // This is needed because the HDL disk controller computes d_out from an
        // unloaded ROM component. We need to write the correct value to cpu__di
        // after evaluate_inline but before the register sampling.
        code.push_str("/// Custom Apple2 tick function that injects ram_data into cpu__di\n");
        code.push_str("/// Uses evaluate_apple2_inline which skips cpu__di computation.\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("unsafe fn tick_apple2_inline(\n"));
        code.push_str("    signals: &mut [u64],\n");
        code.push_str(&format!("    old_clocks: &mut [u64; {}],\n", num_clocks));
        code.push_str(&format!("    next_regs: &mut [u64; {}],\n", num_regs.max(1)));
        code.push_str("    ram_data: u64,\n");
        code.push_str(") {\n");

        // Step 1: Inject ram_data into cpu__di FIRST
        code.push_str(&format!("    // Inject ram_data into cpu__di BEFORE evaluate\n"));
        code.push_str(&format!("    signals[{}] = ram_data;\n\n", cpu_di_idx));

        // Step 2: Evaluate combinational logic (skips cpu__di, so our value is preserved)
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
                    // Debug: print y_reg computation with full dependency chain
                    if stmt.target == "cpu__y_reg" {
                        eprintln!("Y_REG EXPRESSION: {}", expr_code);
                        // Get signal indices for alu_input (130) and alu_reg_out (133)
                        let alu_input_idx = core.name_to_idx.get("cpu__alu_input").copied().unwrap_or(130);
                        let alu_reg_out_idx = core.name_to_idx.get("cpu__alu_reg_out").copied().unwrap_or(133);
                        code.push_str(&format!("    // Debug: Y reg next value with dependency chain\n"));
                        code.push_str(&format!("    {{\n"));
                        code.push_str(&format!("        static Y_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n"));
                        code.push_str(&format!("        let y_cnt = Y_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n"));
                        code.push_str(&format!("        let y_next_val = ({}) & {};\n", expr_code, CoreSimulator::mask_const(width)));
                        code.push_str(&format!("        let cpu_di_val = signals[{}];\n", cpu_di_idx));
                        code.push_str(&format!("        let alu_input_val = signals[{}];\n", alu_input_idx));
                        code.push_str(&format!("        let alu_reg_out_val = signals[{}];\n", alu_reg_out_idx));
                        code.push_str(&format!("        if y_cnt < 500 || (cpu_di_val == 0x50 || cpu_di_val == 0xA0) {{\n"));
                        code.push_str(&format!("            eprintln!(\"Y_NEXT#{{}} = ${{:02X}}, di=${{:02X}}, alu_in=${{:02X}}, alu_out=${{:02X}}, ram=${{:02X}}\", y_cnt, y_next_val, cpu_di_val, alu_input_val, alu_reg_out_val, ram_data);\n"));
                        code.push_str(&format!("        }}\n"));
                        code.push_str(&format!("    }}\n"));
                    }
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

        // Step 7: Final evaluate (cpu__di is preserved since we use evaluate_apple2_inline)
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

        // Debug: trace CPU address every 5000 cycles
        code.push_str("        {\n");
        code.push_str("            static CYCLE_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let cycle_count = CYCLE_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("            if cycle_count < 10 || cycle_count % 5000 == 0 {\n");
        code.push_str("                eprintln!(\"CYCLE#{}: cpu_addr=${:04X} motor={}\", cycle_count, cpu_addr, *disk_motor_on);\n");
        code.push_str("            }\n");
        // Trace when CPU accesses key boot ROM addresses - trace delay loop
        code.push_str("            if cpu_addr >= 0xC638 && cpu_addr <= 0xC656 && sub_cycle_counter == 0 {\n");
        code.push_str("                static BOOT_TRACE: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let trace_cnt = BOOT_TRACE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if trace_cnt < 500 {\n");
        code.push_str(&format!("                    let cpu_di = signals[{}];\n", cpu_di_idx));
        code.push_str(&format!("                    let cpu_y = signals[{}];\n", cpu_y_reg_idx));
        code.push_str(&format!("                    let cpu_a = signals[{}];\n", cpu_a_reg_idx));
        code.push_str(&format!("                    let cpu_n = signals[{}];\n", cpu_flag_n_idx));
        code.push_str("                    eprintln!(\"BOOT_ADDR#{}: addr=${:04X} di=${:02X} A=${:02X} Y=${:02X} N={}\", trace_cnt, cpu_addr, cpu_di, cpu_a, cpu_y, cpu_n);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        // Trace zero page accesses during boot - specifically $26-$2B and $3D, $41
        code.push_str(&format!("            let cpu_we = signals[{}];\n", cpu_we_idx));
        code.push_str(&format!("            let ram_we = signals[{}];\n", ram_we_idx));
        code.push_str(&format!("            let d_val = signals[{}] & 0xFF;\n", d_idx));
        code.push_str("            if (cpu_addr >= 0x0026 && cpu_addr <= 0x002B) || cpu_addr == 0x003D || cpu_addr == 0x0041 {\n");
        code.push_str("                static ZP_TRACE: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let zp_cnt = ZP_TRACE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str(&format!("                if zp_cnt < 200 && ram_we == 1 {{\n"));
        code.push_str("                    eprintln!(\"ZP_WRITE#{}: addr=${:04X} d=${:02X} sub={}\", zp_cnt, cpu_addr, d_val, sub_cycle_counter);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Advance disk position on sub-cycle 0 only (before computing ram_data)
        // We advance by 14 sub-cycles per CPU cycle to match the simulation rate
        code.push_str("        if sub_cycle_counter == 0 && *disk_motor_on && !all_tracks.is_empty() {\n");
        code.push_str("            let old_byte_pos = *disk_byte_pos;\n");
        // Debug: trace position advancement
        code.push_str("            static POS_DEBUG_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            let pos_count = POS_DEBUG_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("            if pos_count < 10 {\n");
        code.push_str("                eprintln!(\"POS_ADV#{}: cycle_counter={} byte_pos={}\", pos_count, *disk_cycle_counter, *disk_byte_pos);\n");
        code.push_str("            }\n");
        code.push_str("            *disk_cycle_counter += 14;  // One CPU cycle worth of sub-cycles\n");
        code.push_str("            while *disk_cycle_counter >= DISK_BYTE_CYCLES {\n");
        code.push_str("                *disk_cycle_counter -= DISK_BYTE_CYCLES;  // Preserve fractional timing\n");
        code.push_str("                let old_pos = *disk_byte_pos;\n");
        code.push_str("                *disk_byte_pos = (*disk_byte_pos + 1) % TRACK_SIZE;\n");
        code.push_str("                static ADV_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let adv = ADV_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if adv < 5 || adv % 1000 == 0 {\n");
        code.push_str("                    eprintln!(\"BYTE_ADV#{}: {} -> {}\", adv, old_pos, *disk_byte_pos);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("            // If byte position changed, latch new byte and set latch_valid\n");
        code.push_str("            if *disk_byte_pos != old_byte_pos {\n");
        code.push_str("                let track = *disk_current_track;\n");
        code.push_str("                let pos = *disk_byte_pos;\n");
        code.push_str("                if track < num_tracks && pos < track_size {\n");
        code.push_str("                    *disk_data_latch = all_tracks[track * track_size + pos];\n");
        code.push_str("                    *disk_latch_valid = true;  // New byte is ready\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Compute RAM/ROM/disk data BEFORE evaluate_inline
        // Compute on every sub-cycle so the CPU always sees correct data for the current address
        // But only clear latch_valid on sub-cycle 0 so we only "consume" the [HI] once per CPU cycle
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
        code.push_str("                if newly_on != 0 {\n");
        code.push_str("                    let new_phase = newly_on.trailing_zeros() as i32;\n");
        code.push_str("                    if new_phase < 4 {\n");
        code.push_str("                        let current_track = *disk_current_track as i32;\n");
        code.push_str("                        let current_phase = if old_phases != 0 {\n");
        code.push_str("                            old_phases.trailing_zeros() as i32\n");
        code.push_str("                        } else {\n");
        code.push_str("                            (current_track % 4) as i32\n");
        code.push_str("                        };\n");
        code.push_str("                        let diff = (new_phase - current_phase).rem_euclid(4);\n");
        code.push_str("                        if diff == 1 && current_track < (NUM_TRACKS as i32 - 1) {\n");
        code.push_str("                            *disk_current_track = (current_track + 1) as usize;\n");
        code.push_str("                        } else if diff == 3 && current_track > 0 {\n");
        code.push_str("                            *disk_current_track = (current_track - 1) as usize;\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("            // Read data register ($C0EC with Q6=0, Q7=0)\n");
        code.push_str("            // Real Disk II: bit 7 is set when data is valid (byte ready)\n");
        code.push_str("            // Bit 7 stays set for ALL reads of the same byte - it's part of the data!\n");
        code.push_str("            // Valid disk nibbles already have bit 7 set (range $96-$FF)\n");
        code.push_str("            // We clear bit 7 only when no new data is ready yet (latch_valid=false)\n");
        // Debug: trace ALL reads from $C0EC with state info
        code.push_str("            if reg == 0xC && sub_cycle_counter == 0 {\n");
        code.push_str("                static READ_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                let read_cnt = READ_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if read_cnt < 20 || (read_cnt >= 1000 && read_cnt < 1010) {\n");
        code.push_str("                    eprintln!(\"DISKRD#{}: q7={} motor={} latch={:02X} valid={}\", read_cnt, *disk_q7, *disk_motor_on, *disk_data_latch, *disk_latch_valid);\n");
        code.push_str("                }\n");
        code.push_str("            }\n");
        code.push_str("            if reg == 0xC && !*disk_q7 && *disk_motor_on {\n");
        code.push_str("                let latched = *disk_data_latch;\n");
        code.push_str("                // latch_valid indicates a new byte is ready\n");
        code.push_str("                // On sub_cycle 0 (CPU cycle boundary), we consume the valid byte\n");
        code.push_str("                // This gives the CPU one full cycle to sample the valid byte\n");
        code.push_str("                let is_valid = *disk_latch_valid;\n");
        code.push_str("                let result = if is_valid {\n");
        code.push_str("                    // Data valid - return latch (bit 7 naturally set for valid nibbles)\n");
        code.push_str("                    // Clear latch_valid only on sub_cycle 0 to ensure CPU sees valid byte\n");
        code.push_str("                    if sub_cycle_counter == 0 {\n");
        code.push_str("                        *disk_latch_valid = false;  // Consumed the byte\n");
        code.push_str("                    }\n");
        code.push_str("                    latched as u64\n");
        code.push_str("                } else {\n");
        code.push_str("                    // Data not ready - return with bit 7 clear\n");
        code.push_str("                    (latched & 0x7F) as u64\n");
        code.push_str("                };\n");
        // Debug: track sequential reads after D5 is found - ONLY on sub_cycle 0 when byte is consumed
        code.push_str("                static D5_STATE: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);\n");
        code.push_str("                static SEQ_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                if is_valid && sub_cycle_counter == 0 {\n");
        code.push_str("                    let seq = SEQ_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    let d5_state = D5_STATE.load(std::sync::atomic::Ordering::Relaxed);\n");
        // State machine: 0=idle, 1=saw D5, 2=saw D5 AA, 3-10=reading address field
        code.push_str("                    if latched == 0xD5 && d5_state == 0 {\n");
        code.push_str("                        static D5_FOUND: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                        let d5cnt = D5_FOUND.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if d5cnt < 20 {\n");
        code.push_str("                            eprintln!(\"D5_FOUND#{}: pos={}\", d5cnt, *disk_byte_pos);\n");
        code.push_str("                        }\n");
        code.push_str("                        D5_STATE.store(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    } else if d5_state == 1 {\n");
        code.push_str("                        static D5_AA_CHECK: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                        let chk = D5_AA_CHECK.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if chk < 20 {\n");
        code.push_str("                            eprintln!(\"D5_AA_CHECK#{}: latched={:02X} pos={} (expect AA)\", chk, latched, *disk_byte_pos);\n");
        code.push_str("                        }\n");
        code.push_str("                        if latched == 0xAA {\n");
        code.push_str("                            D5_STATE.store(2, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    } else if d5_state == 2 {\n");
        code.push_str("                        static D5_AA_TYPE: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                        let typecnt = D5_AA_TYPE.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if typecnt < 20 {\n");
        code.push_str("                            eprintln!(\"D5_AA_TYPE#{}: latched={:02X} pos={} (expect 96 or AD)\", typecnt, latched, *disk_byte_pos);\n");
        code.push_str("                        }\n");
        code.push_str("                        if latched == 0x96 {\n");
        // Start reading address field: vol_odd, vol_even, trk_odd, trk_even, sec_odd, sec_even, chk_odd, chk_even
        code.push_str("                            D5_STATE.store(3, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else if latched == 0xAD {\n");
        // Data prologue found! D5 AA AD - start tracking data field
        code.push_str("                            static DATA_PROLOGUE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                            let dp_cnt = DATA_PROLOGUE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            if dp_cnt < 5 {\n");
        code.push_str("                                eprintln!(\"DATA_PROLOGUE#{}: D5 AA AD found at pos={}\", dp_cnt, *disk_byte_pos);\n");
        code.push_str("                            }\n");
        // Start reading data field (343 bytes: 342 data + 1 checksum)
        code.push_str("                            D5_STATE.store(20, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    } else if d5_state >= 3 && d5_state <= 10 {\n");
        // Read address field bytes and decode 4-and-4
        code.push_str("                        static ADDR_BYTES: [std::sync::atomic::AtomicU8; 8] = [\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                            std::sync::atomic::AtomicU8::new(0),\n");
        code.push_str("                        ];\n");
        code.push_str("                        let idx = (d5_state - 3) as usize;\n");
        code.push_str("                        ADDR_BYTES[idx].store(latched as u8, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if d5_state == 10 {\n");
        // Decode and print address field
        code.push_str("                            let vol_odd = ADDR_BYTES[0].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let vol_even = ADDR_BYTES[1].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let trk_odd = ADDR_BYTES[2].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let trk_even = ADDR_BYTES[3].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let sec_odd = ADDR_BYTES[4].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let sec_even = ADDR_BYTES[5].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let chk_odd = ADDR_BYTES[6].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let chk_even = ADDR_BYTES[7].load(std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            let vol = ((vol_odd << 1) | 1) & vol_even;\n");
        code.push_str("                            let trk = ((trk_odd << 1) | 1) & trk_even;\n");
        code.push_str("                            let sec = ((sec_odd << 1) | 1) & sec_even;\n");
        code.push_str("                            let chk = ((chk_odd << 1) | 1) & chk_even;\n");
        code.push_str("                            let expected_chk = vol ^ trk ^ sec;\n");
        code.push_str("                            static ADDR_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                            let addr_cnt = ADDR_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                            if addr_cnt < 30 {\n");
        code.push_str("                                eprintln!(\"ADDR#{}: vol={:02X} trk={} sec={} chk={:02X} (expected {:02X}) pos={}\", addr_cnt, vol, trk, sec, chk, expected_chk, *disk_byte_pos);\n");
        code.push_str("                            }\n");
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        code.push_str("                            D5_STATE.store(d5_state + 1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    } else if d5_state >= 20 {\n");
        // Reading data field bytes (state 20 = first byte, state 362 = checksum, state 363 = done)
        code.push_str("                        static DATA_BYTES_READ: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                        static DATA_CHECKSUM: std::sync::atomic::AtomicU8 = std::sync::atomic::AtomicU8::new(0);\n");
        code.push_str("                        let data_idx = d5_state as usize - 20;\n");
        code.push_str("                        if data_idx == 0 {\n");
        code.push_str("                            DATA_CHECKSUM.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        // Print first few data bytes
        code.push_str("                        let total_data_read = DATA_BYTES_READ.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        if total_data_read < 10 {\n");
        code.push_str("                            eprintln!(\"DATA_BYTE#{}: idx={} val={:02X} pos={}\", total_data_read, data_idx, latched, *disk_byte_pos);\n");
        code.push_str("                        }\n");
        code.push_str("                        if data_idx < 343 {\n");
        code.push_str("                            D5_STATE.store((d5_state + 1) as u8, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        } else {\n");
        // Done reading data field
        code.push_str("                            D5_STATE.store(0, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                        }\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        // Debug: show what's actually returned (limited) - only on sub_cycle 0
        code.push_str("                static RET_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                if sub_cycle_counter == 0 {\n");
        code.push_str("                    let ret_cnt = RET_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if ret_cnt < 5 {\n");
        code.push_str("                        eprintln!(\"RET#{}: valid={} latch={:02X} result={:02X} pos={}\", ret_cnt, is_valid, latched, result, *disk_byte_pos);\n");
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
        code.push_str("        } else if cpu_addr >= 0xC000 {\n");
        code.push_str("            // Other I/O space\n");
        code.push_str("            0u64\n");
        code.push_str("        } else if cpu_addr < ram_len {\n");
        code.push_str("            ram[cpu_addr] as u64\n");
        code.push_str("        } else {\n");
        code.push_str("            0u64\n");
        code.push_str("        };\n\n");

        // Write data to ram_do for non-disk addresses
        // For RAM/ROM, the HDL mux will route ram_do to cpu_din
        code.push_str(&format!("        signals[{}] = ram_data;  // ram_do\n", ram_do_idx));
        // Also write directly to cpu__di so combinational logic sees correct value
        code.push_str(&format!("        signals[{}] = ram_data;  // cpu__di direct\n", cpu_di_idx));

        // Clock falling edge - evaluate to settle combinational logic
        // Use evaluate_apple2_inline which skips cpu__di (preserving our injected value)
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_apple2_inline(signals);\n\n");

        // Clock rising edge - use custom tick that injects ram_data into cpu__di
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        code.push_str("        tick_apple2_inline(signals, &mut old_clocks, &mut next_regs, ram_data);\n");
        // Debug: verify cpu__di after tick for disk accesses
        code.push_str(&format!("        static TICK_DEBUG: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n"));
        code.push_str(&format!("        if cpu_addr == 0xC0EC {{\n"));
        code.push_str(&format!("            let tick_count = TICK_DEBUG.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n"));
        code.push_str(&format!("            if tick_count < 5 {{\n"));
        code.push_str(&format!("                let cpu_di_val = signals[{}];\n", cpu_di_idx));
        code.push_str(&format!("                eprintln!(\"TICK#{{}} addr=${{:04X}} ram_data=${{:02X}} cpu_di=${{:02X}}\", tick_count, cpu_addr, ram_data, cpu_di_val);\n"));
        code.push_str(&format!("            }}\n"));
        code.push_str(&format!("        }}\n\n"));

        // Handle RAM write (read from d signal, NOT ram_do)
        // Debug: Get signal indices for ram_we components
        let cpu_we_idx = core.name_to_idx.get("cpu_we").copied().unwrap_or(0);
        let ras_n_idx = core.name_to_idx.get("ras_n").copied().unwrap_or(0);
        let phi0_idx = core.name_to_idx.get("phi0").copied().unwrap_or(0);
        eprintln!("CODEGEN: ram_we_idx={}, cpu_we_idx={}, ras_n_idx={}, phi0_idx={}",
                  ram_we_idx, cpu_we_idx, ras_n_idx, phi0_idx);
        code.push_str(&format!("        let ram_we = signals[{}];\n", ram_we_idx));
        code.push_str(&format!("        let cpu_we = signals[{}];\n", cpu_we_idx));
        code.push_str(&format!("        let ras_n = signals[{}];\n", ras_n_idx));
        code.push_str(&format!("        let phi0 = signals[{}];\n", phi0_idx));
        code.push_str("        {{\n");
        code.push_str("            static CPU_WE_EVER_SET: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);\n");
        code.push_str("            static CPU_WE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("            if cpu_we == 1 && !CPU_WE_EVER_SET.swap(true, std::sync::atomic::Ordering::Relaxed) {\n");
        code.push_str("                eprintln!(\"CPU_WE first set at cycle {}\", CPU_WE_COUNT.load(std::sync::atomic::Ordering::Relaxed));\n");
        code.push_str("            }\n");
        code.push_str("            if ram_we == 1 {\n");
        code.push_str(&format!("                eprintln!(\"RAM_WE=1: addr=${{:04X}} cpu_we={{}} ras_n={{}} phi0={{}}\", (signals[{}] as usize) & 0xFFFF, cpu_we, ras_n, phi0);\n", cpu_addr_idx));
        code.push_str("            }\n");
        code.push_str("            CPU_WE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("        }}\n");
        code.push_str("        if ram_we == 1 {\n");
        code.push_str(&format!("            let write_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("            if write_addr < 0xC000 && write_addr < ram_len {\n");
        code.push_str(&format!("                ram[write_addr] = (signals[{}] & 0xFF) as u8;\n", d_idx));
        // Debug: track writes to boot sector region and aux/table region
        code.push_str("                static BOOT_WRITE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                static AUX_WRITE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str("                static RAM_WRITE_COUNT: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);\n");
        code.push_str(&format!("                let val = signals[{}] & 0xFF;\n", d_idx));
        code.push_str("                let ram_wr_cnt = RAM_WRITE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                if ram_wr_cnt < 10 {\n");
        code.push_str("                    eprintln!(\"RAM_WRITE#{}: addr=${:04X} val=${:02X}\", ram_wr_cnt, write_addr, val);\n");
        code.push_str("                }\n");
        code.push_str("                if write_addr >= 0x0800 && write_addr <= 0x08FF {\n");
        code.push_str("                    let wr_cnt = BOOT_WRITE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if wr_cnt < 20 {\n");
        code.push_str("                        eprintln!(\"BOOT_WRITE#{}: addr=${:04X} val=${:02X}\", wr_cnt, write_addr, val);\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
        code.push_str("                if write_addr >= 0x0300 && write_addr <= 0x03FF {\n");
        code.push_str("                    let aux_cnt = AUX_WRITE_COUNT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);\n");
        code.push_str("                    if aux_cnt < 20 {\n");
        code.push_str("                        eprintln!(\"AUX_WRITE#{}: addr=${:04X} val=${:02X}\", aux_cnt, write_addr, val);\n");
        code.push_str("                    }\n");
        code.push_str("                }\n");
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
