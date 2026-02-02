//! Apple II full system simulation extension
//!
//! Provides batched CPU cycle execution with memory bridging for Apple II.
//! The disk controller is fully HDL-driven - this extension only provides
//! RAM/ROM bridging and track data loading into HDL memory.

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

/// Track size in nibbles (6656 bytes per track)
pub const TRACK_SIZE: usize = 6656;

/// Number of tracks on a disk
pub const NUM_TRACKS: usize = 35;

/// Result from batched Apple II CPU cycle execution
pub struct Apple2BatchResult {
    pub text_dirty: bool,
    pub key_cleared: bool,
    pub cycles_run: usize,
    pub speaker_toggles: u32,
}

/// Apple II specific extension state
///
/// This extension provides:
/// - RAM (48KB) bridging between HDL and external memory
/// - ROM (12KB) bridging for main ROM at $D000-$FFFF
/// - Track data storage for disk (loaded into HDL memory)
/// - Slot ROM storage for disk boot ROM
///
/// The disk controller is FULLY HDL-driven. This extension does NOT
/// implement disk controller logic - it only loads track data into
/// the HDL's track_memory.
pub struct Apple2Extension {
    /// RAM (48KB)
    pub ram: Vec<u8>,
    /// ROM (12KB) - main ROM at $D000-$FFFF
    pub rom: Vec<u8>,
    /// Signal indices for memory bridging
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

    // Disk data storage (for loading into HDL memory)
    /// Slot ROM (256 bytes) at $C600-$C6FF for slot 6
    pub disk_slot_rom: Vec<u8>,
    /// Track data for all 35 tracks (each 6656 bytes)
    pub disk_tracks: Vec<Vec<u8>>,
    /// Index of track_memory in memory_arrays
    pub track_memory_idx: Option<usize>,
    /// Index of disk ROM in memory_arrays
    pub disk_rom_idx: Option<usize>,
    /// Last track loaded into HDL memory
    pub last_loaded_track: Option<usize>,
    /// Signal index for HDL track output
    pub disk_track_idx: usize,
    /// Signal index for HDL motor status
    pub disk_motor_idx: usize,
}

impl Apple2Extension {
    /// Create Apple II extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator, sub_cycles: usize) -> Self {
        let name_to_idx = &core.name_to_idx;

        // Find memory indices for disk
        let track_memory_idx = core.memory_name_to_idx.get("disk__track_memory").copied();
        let disk_rom_idx = core.memory_name_to_idx.get("disk__rom__rom").copied();

        if track_memory_idx.is_some() {
            eprintln!("Apple2Extension: Found disk__track_memory at index {:?}", track_memory_idx);
        } else {
            eprintln!("Apple2Extension: WARNING - disk__track_memory not found in IR");
        }

        Self {
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
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
            disk_slot_rom: vec![0u8; 256],
            disk_tracks: (0..NUM_TRACKS).map(|_| vec![0u8; TRACK_SIZE]).collect(),
            track_memory_idx,
            disk_rom_idx,
            last_loaded_track: None,
            disk_track_idx: *name_to_idx.get("disk__track").unwrap_or(&0),
            disk_motor_idx: *name_to_idx.get("disk__d1_active").unwrap_or(&0),
        }
    }

    /// Load disk slot ROM (P5 PROM boot code at $C600)
    pub fn load_disk_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.disk_slot_rom.len());
        self.disk_slot_rom[..len].copy_from_slice(&data[..len]);
    }

    /// Load track nibble data into extension storage
    pub fn load_track(&mut self, track: usize, data: &[u8]) {
        if track < NUM_TRACKS {
            let len = data.len().min(TRACK_SIZE);
            self.disk_tracks[track][..len].copy_from_slice(&data[..len]);
        }
    }

    /// Load track data into HDL's track_memory
    /// This should be called to sync track data into the HDL memory array
    pub fn load_track_into_hdl(&mut self, core: &mut CoreSimulator, track: usize) {
        if track >= NUM_TRACKS {
            return;
        }

        if let Some(mem_idx) = self.track_memory_idx {
            if mem_idx < core.memory_arrays.len() {
                let track_data = &self.disk_tracks[track];
                let mem = &mut core.memory_arrays[mem_idx];
                for (i, &byte) in track_data.iter().enumerate() {
                    if i < mem.len() {
                        mem[i] = byte as u64;
                    }
                }
                self.last_loaded_track = Some(track);
                eprintln!("Loaded track {} into HDL track_memory", track);
            }
        }
    }

    /// Load disk ROM into HDL's disk ROM memory
    pub fn load_disk_rom_into_hdl(&self, core: &mut CoreSimulator) {
        if let Some(mem_idx) = self.disk_rom_idx {
            if mem_idx < core.memory_arrays.len() {
                let mem = &mut core.memory_arrays[mem_idx];
                for (i, &byte) in self.disk_slot_rom.iter().enumerate() {
                    if i < mem.len() {
                        mem[i] = byte as u64;
                    }
                }
                // Debug: verify the load
                eprintln!("Loaded disk ROM into HDL disk__rom__rom (mem_idx={})", mem_idx);
                eprintln!("  First 8 bytes: {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X} {:02X}",
                    mem.get(0).copied().unwrap_or(0),
                    mem.get(1).copied().unwrap_or(0),
                    mem.get(2).copied().unwrap_or(0),
                    mem.get(3).copied().unwrap_or(0),
                    mem.get(4).copied().unwrap_or(0),
                    mem.get(5).copied().unwrap_or(0),
                    mem.get(6).copied().unwrap_or(0),
                    mem.get(7).copied().unwrap_or(0));
            }
        }
    }

    /// Get current track from HDL
    pub fn get_hdl_track(&self, core: &CoreSimulator) -> usize {
        (core.signals[self.disk_track_idx] as usize) & 0x3F
    }

    /// Check if motor is on from HDL
    pub fn is_motor_on(&self, core: &CoreSimulator) -> bool {
        core.signals[self.disk_motor_idx] != 0
    }

    /// Check if the simulator has Apple II specific signals
    pub fn is_apple2_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("ram_do")
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
    ///
    /// This function:
    /// - Bridges RAM reads/writes between HDL and external memory
    /// - Bridges ROM reads
    /// - Passes memory arrays for dynamic HDL memory access (disk ROM, track memory)
    /// - Lets the HDL disk controller run naturally
    /// - Monitors HDL track changes and reloads track data as needed
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
            // Function signature with memory array pointers for dynamic HDL memory access
            type RunCpuCyclesFn = unsafe extern "C" fn(
                signals: *mut u64, signals_len: usize,
                ram: *mut u8, ram_len: usize,
                rom: *const u8, rom_len: usize,
                slot_rom: *const u8, slot_rom_len: usize,
                mem_ptrs: *const *const u64, mem_lens: *const usize,
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

            // Build arrays of memory pointers and lengths
            let mem_ptrs: Vec<*const u64> = core.memory_arrays.iter()
                .map(|arr| arr.as_ptr())
                .collect();
            let mem_lens: Vec<usize> = core.memory_arrays.iter()
                .map(|arr| arr.len())
                .collect();

            // Debug: verify disk ROM memory is being passed (index 4 is disk__rom__rom)
            if n == self.sub_cycles && core.memory_arrays.len() > 4 {
                let disk_rom = &core.memory_arrays[4];
                if !disk_rom.is_empty() {
                    eprintln!("run_cpu_cycles: disk_rom[0..4] = {:02X} {:02X} {:02X} {:02X}",
                        disk_rom[0], disk_rom[1], disk_rom[2], disk_rom[3]);
                }
            }

            let cycles_run = func(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.ram.as_mut_ptr(),
                self.ram.len(),
                self.rom.as_ptr(),
                self.rom.len(),
                self.disk_slot_rom.as_ptr(),
                self.disk_slot_rom.len(),
                mem_ptrs.as_ptr(),
                mem_lens.as_ptr(),
                n * self.sub_cycles,
                key_data,
                key_ready,
                &mut self.prev_speaker,
                &mut text_dirty,
                &mut key_cleared,
                &mut speaker_toggles,
            );

            // Check if HDL track changed and reload if needed
            let hdl_track = self.get_hdl_track(core);
            if self.last_loaded_track != Some(hdl_track) {
                self.load_track_into_hdl(core, hdl_track);
            }

            Apple2BatchResult {
                text_dirty,
                key_cleared,
                cycles_run: cycles_run / self.sub_cycles,
                speaker_toggles,
            }
        }
    }

    /// Run CPU cycles with VCD tracing - captures signals after each CPU cycle
    pub fn run_cpu_cycles_traced(
        &mut self,
        core: &mut CoreSimulator,
        tracer: &mut crate::vcd::VcdTracer,
        n: usize,
        key_data: u8,
        key_ready: bool,
    ) -> Apple2BatchResult {
        let mut total_result = Apple2BatchResult {
            text_dirty: false,
            key_cleared: false,
            cycles_run: 0,
            speaker_toggles: 0,
        };

        // Run one CPU cycle at a time, capturing after each
        for _ in 0..n {
            let result = self.run_cpu_cycles(core, 1, key_data, key_ready);

            // Capture signal state for this cycle
            if tracer.is_enabled() {
                tracer.capture(&core.signals);
            }

            total_result.text_dirty |= result.text_dirty;
            total_result.key_cleared |= result.key_cleared;
            total_result.cycles_run += result.cycles_run;
            total_result.speaker_toggles += result.speaker_toggles;
        }

        total_result
    }

    /// Generate Apple II specific batched execution code
    ///
    /// This generates code that:
    /// - Bridges RAM reads/writes
    /// - Bridges ROM reads
    /// - Lets HDL handle ALL disk controller logic
    /// - Uses evaluate_inline_mem for dynamic memory access (disk ROM, track memory)
    pub fn generate_code(core: &CoreSimulator) -> String {
        let mut code = String::new();

        let ram_do_idx = *core.name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *core.name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *core.name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *core.name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *core.name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *core.name_to_idx.get("read_key").unwrap_or(&0);
        let speaker_idx = *core.name_to_idx.get("speaker").unwrap_or(&0);
        let cpu_addr_idx = *core.name_to_idx.get("cpu__addr_reg").unwrap_or(&0);

        let num_mems = core.ir.memories.len();

        eprintln!("Apple2 generate_code (HDL-driven): cpu_addr_idx={}, ram_do_idx={}, clk_idx={}, num_mems={}",
                  cpu_addr_idx, ram_do_idx, clk_idx, num_mems);

        // Debug: print if clk_14m was found
        if core.name_to_idx.get("clk_14m").is_none() {
            eprintln!("WARNING: clk_14m not found in signals! Disk controller won't work.");
        }

        let clock_indices: Vec<usize> = core.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        code.push_str("\n// ============================================================================\n");
        code.push_str("// Apple II Extension: HDL-Driven Simulation with Memory Bridging\n");
        code.push_str("// Disk controller is fully HDL-driven - this only bridges RAM/ROM\n");
        code.push_str("// Uses evaluate_inline_mem for dynamic memory (disk ROM, track memory)\n");
        code.push_str("// ============================================================================\n\n");

        // Generate the main run_cpu_cycles function with memory arrays
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
        // Add memory array pointers and lengths
        code.push_str("    mem_ptrs: *const *const u64,\n");
        code.push_str("    mem_lens: *const usize,\n");
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
        code.push_str("    let _slot_rom = if slot_rom.is_null() { &[] as &[u8] } else { std::slice::from_raw_parts(slot_rom, slot_rom_len) };\n");

        // Convert memory pointers to slices
        code.push_str(&format!("    let mem_ptrs = std::slice::from_raw_parts(mem_ptrs, {});\n", num_mems));
        code.push_str(&format!("    let mem_lens = std::slice::from_raw_parts(mem_lens, {});\n", num_mems));

        // Create the mems array for evaluate_inline_mem
        code.push_str(&format!("    let mems: [&[u64]; {}] = [\n", num_mems));
        for i in 0..num_mems {
            code.push_str(&format!("        std::slice::from_raw_parts(mem_ptrs[{}], mem_lens[{}]),\n", i, i));
        }
        code.push_str("    ];\n\n");

        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut text_dirty = false;\n");
        code.push_str("    let mut key_cleared = false;\n");
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("    let mut prev_speaker = *prev_speaker_ptr;\n\n");

        // Initialize old_clocks
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _cycle_num in 0..n {\n");

        // Set keyboard input
        code.push_str(&format!("        signals[{}] = if key_ready {{ (key_data as u64) | 0x80 }} else {{ key_data as u64 }};\n\n", k_idx));

        // Read CPU address
        code.push_str(&format!("        let cpu_addr = (signals[{}] as usize) & 0xFFFF;\n\n", cpu_addr_idx));

        // Compute ram_data for RAM/ROM addresses
        // The HDL disk controller handles $C0E0-$C0EF and $C600-$C6FF
        code.push_str("        let ram_data = if cpu_addr >= 0xD000 {\n");
        code.push_str("            // Main ROM ($D000-$FFFF)\n");
        code.push_str("            let rom_idx = cpu_addr - 0xD000;\n");
        code.push_str("            if rom_idx < rom_len { rom[rom_idx] as u64 } else { 0 }\n");
        code.push_str("        } else if cpu_addr >= 0xC000 {\n");
        code.push_str("            // I/O space - handled by HDL\n");
        code.push_str("            0u64\n");
        code.push_str("        } else if cpu_addr < ram_len {\n");
        code.push_str("            // RAM ($0000-$BFFF)\n");
        code.push_str("            ram[cpu_addr] as u64\n");
        code.push_str("        } else {\n");
        code.push_str("            0u64\n");
        code.push_str("        };\n\n");

        // Inject ram_data into ram_do
        code.push_str(&format!("        signals[{}] = ram_data;  // ram_do\n\n", ram_do_idx));

        // Clock falling edge - set input clock low and propagate using dynamic memory
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_inline_mem(signals, &mems);  // Propagate clock with dynamic memory\n\n");

        // Capture old clock values AFTER propagation
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        // Clock rising edge - set input clock high, propagate, THEN tick (using dynamic memory)
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        code.push_str("        tick_inline_mem(signals, &mut old_clocks, &mut next_regs, &mems);\n\n");

        // Handle RAM write
        code.push_str(&format!("        let ram_we = signals[{}];\n", ram_we_idx));
        code.push_str("        if ram_we == 1 {\n");
        code.push_str(&format!("            let write_addr = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
        code.push_str("            if write_addr < 0xC000 && write_addr < ram_len {\n");
        code.push_str(&format!("                ram[write_addr] = (signals[{}] & 0xFF) as u8;\n", d_idx));
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
