//! MOS6502 CPU standalone simulation extension
//!
//! Provides batched cycle execution with internal memory bridging for MOS6502 CPU

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

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
        // MOS6502 CPU has addr, data_in, data_out, rw signals
        // But NOT ram_addr (which is Apple II full system)
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
        if !core.compiled {
            return 0;
        }

        #[cfg(feature = "aot")]
        unsafe {
            let mut speaker_toggles: u32 = 0;
            let result = crate::aot_generated::run_mos6502_cycles(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.memory.as_mut_ptr(),
                self.rom_mask.as_ptr(),
                n,
                &mut speaker_toggles,
            );
            self.speaker_toggles += speaker_toggles;
            result
        }

        #[cfg(not(feature = "aot"))]
        {
            let lib = core.compiled_lib.as_ref().unwrap();
            unsafe {
                type RunMos6502CyclesFn = unsafe extern "C" fn(
                    *mut u64, usize, *mut u8, *const bool, usize, *mut u32
                ) -> usize;

                let func: libloading::Symbol<RunMos6502CyclesFn> =
                    lib.get(b"run_mos6502_cycles")
                        .expect("run_mos6502_cycles function not found - is this a MOS6502 IR?");

                let mut speaker_toggles: u32 = 0;
                let result = func(
                    core.signals.as_mut_ptr(),
                    core.signals.len(),
                    self.memory.as_mut_ptr(),
                    self.rom_mask.as_ptr(),
                    n,
                    &mut speaker_toggles,
                );
                self.speaker_toggles += speaker_toggles;
                result
            }
        }
    }

    /// Run until n instructions complete, returning (pc, opcode, sp) for each
    /// An instruction completes when state transitions to DECODE (0x02)
    pub fn run_instructions_with_opcodes(
        &mut self,
        core: &mut CoreSimulator,
        n: usize,
        opcodes_out: &mut Vec<(u16, u8, u8)>,
    ) -> usize {
        if !core.compiled {
            return 0;
        }

        #[cfg(feature = "aot")]
        unsafe {
            // Allocate output buffer for packed opcodes
            let mut packed_out: Vec<u64> = vec![0; n];
            let mut speaker_toggles: u32 = 0;

            let count = crate::aot_generated::run_mos6502_instructions_with_opcodes(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                self.memory.as_mut_ptr(),
                self.rom_mask.as_ptr(),
                n,
                packed_out.as_mut_ptr(),
                packed_out.len(),
                &mut speaker_toggles,
            );

            self.speaker_toggles += speaker_toggles;

            // Unpack results
            for i in 0..count {
                let v = packed_out[i];
                let pc = ((v >> 16) & 0xFFFF) as u16;
                let opcode = ((v >> 8) & 0xFF) as u8;
                let sp = (v & 0xFF) as u8;
                opcodes_out.push((pc, opcode, sp));
            }

            count
        }

        #[cfg(not(feature = "aot"))]
        {
            let lib = core.compiled_lib.as_ref().unwrap();
            unsafe {
                type RunInstructionsFn = unsafe extern "C" fn(
                    *mut u64, usize, *mut u8, *const bool, usize, *mut u64, usize, *mut u32
                ) -> usize;

                let func: libloading::Symbol<RunInstructionsFn> = lib
                    .get(b"run_mos6502_instructions_with_opcodes")
                    .expect("run_mos6502_instructions_with_opcodes function not found");

                // Allocate output buffer for packed opcodes
                let mut packed_out: Vec<u64> = vec![0; n];
                let mut speaker_toggles: u32 = 0;

                let count = func(
                    core.signals.as_mut_ptr(),
                    core.signals.len(),
                    self.memory.as_mut_ptr(),
                    self.rom_mask.as_ptr(),
                    n,
                    packed_out.as_mut_ptr(),
                    packed_out.len(),
                    &mut speaker_toggles,
                );

                self.speaker_toggles += speaker_toggles;

                // Unpack results
                for i in 0..count {
                    let v = packed_out[i];
                    let pc = ((v >> 16) & 0xFFFF) as u16;
                    let opcode = ((v >> 8) & 0xFF) as u8;
                    let sp = (v & 0xFF) as u8;
                    opcodes_out.push((pc, opcode, sp));
                }

                count
            }
        }
    }

    /// Generate MOS6502 specific batched execution code
    pub fn generate_code(core: &CoreSimulator) -> String {
        let mut code = String::new();

        let addr_idx = *core.name_to_idx.get("addr").unwrap_or(&0);
        let data_in_idx = *core.name_to_idx.get("data_in").unwrap_or(&0);
        let data_out_idx = *core.name_to_idx.get("data_out").unwrap_or(&0);
        let rw_idx = *core.name_to_idx.get("rw").unwrap_or(&0);
        let clk_idx = *core.name_to_idx.get("clk").unwrap_or(&0);

        let clock_indices: Vec<usize> = core.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        // Find ALL clock domain indices derived from the MOS6502 input clock
        // All internal clock wires (registers__clk, status_reg__clk, etc.) are
        // assigned from the input clk, so we need to update all of them for proper edge detection
        let clk_domain_indices = core.find_clock_domains_for_input(clk_idx);

        code.push_str("\n// ============================================================================\n");
        code.push_str("// MOS6502 Extension: Batched CPU Cycle Execution with Internal Memory\n");
        code.push_str("// ============================================================================\n\n");

        code.push_str("/// Run N MOS6502 CPU cycles with internalized memory bridging\n");
        code.push_str("/// Returns cycles run, and writes speaker toggle count to out parameter\n");
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_mos6502_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    memory: *mut u8,\n");
        code.push_str("    rom_mask: *const bool,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    speaker_toggles_out: *mut u32,\n");
        code.push_str(") -> usize {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let memory = std::slice::from_raw_parts_mut(memory, 65536);\n");
        code.push_str("    let rom_mask = std::slice::from_raw_parts(rom_mask, 65536);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("\n");

        // Initialize old_clocks
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");

        // Clock falling edge FIRST - combinational outputs update (addr/rw become valid)
        // Set ALL clocks' old_clocks to 1 (previous state was high) for proper edge detection
        for i in 0..num_clocks {
            code.push_str(&format!("        old_clocks[{}] = 1; // Previous state was high\n", i));
        }
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // NOW do memory bridging (after evaluate, addr/rw reflect current state)
        code.push_str(&format!("        let addr = (signals[{}] as usize) & 0xFFFF;\n", addr_idx));
        code.push_str(&format!("        let rw = signals[{}];\n", rw_idx));
        code.push_str("\n");

        // Detect speaker toggle ($C030) - any access triggers toggle
        code.push_str("        if addr == 0xC030 {\n");
        code.push_str("            speaker_toggles += 1;\n");
        code.push_str("        }\n\n");

        code.push_str("        if rw == 1 {\n");
        code.push_str("            // Read: provide data from memory to CPU\n");
        code.push_str(&format!("            signals[{}] = memory[addr] as u64;\n", data_in_idx));
        code.push_str("        } else {\n");
        code.push_str("            // Write: store CPU data to memory (unless ROM protected)\n");
        code.push_str("            if !rom_mask[addr] {\n");
        code.push_str(&format!("                memory[addr] = (signals[{}] & 0xFF) as u8;\n", data_out_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Clock rising edge - registers capture values (including data_in we just set)
        // Set ALL clocks' old_clocks to 0 (previous state was low) for proper edge detection
        for i in 0..num_clocks {
            code.push_str(&format!("        old_clocks[{}] = 0; // Previous state was low\n", i));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        // IMPORTANT: Must call evaluate_inline to propagate clk to internal clock signals
        // before tick_inline checks for rising edges on those internal signals
        code.push_str("        evaluate_inline(signals);\n");
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n");
        code.push_str("    }\n\n");
        code.push_str("    // Write speaker toggles to out parameter\n");
        code.push_str("    if !speaker_toggles_out.is_null() {\n");
        code.push_str("        *speaker_toggles_out = speaker_toggles;\n");
        code.push_str("    }\n");
        code.push_str("    n\n");
        code.push_str("}\n");

        code
    }

    /// Generate MOS6502 instruction-level execution code with opcode capture
    pub fn generate_code_run_instructions_with_opcodes(core: &CoreSimulator) -> String {
        let mut code = String::new();

        let addr_idx = *core.name_to_idx.get("addr").unwrap_or(&0);
        let data_in_idx = *core.name_to_idx.get("data_in").unwrap_or(&0);
        let data_out_idx = *core.name_to_idx.get("data_out").unwrap_or(&0);
        let rw_idx = *core.name_to_idx.get("rw").unwrap_or(&0);
        let clk_idx = *core.name_to_idx.get("clk").unwrap_or(&0);
        let state_idx = *core.name_to_idx.get("state").unwrap_or(&0);
        let opcode_idx = *core.name_to_idx.get("opcode").unwrap_or(&0);
        let pc_idx = *core.name_to_idx.get("reg_pc").unwrap_or(&0);
        let sp_idx = *core.name_to_idx.get("reg_sp").unwrap_or(&0);

        let clock_indices: Vec<usize> = core.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        // Find ALL clock domain indices derived from the MOS6502 input clock
        // All internal clock wires (registers__clk, status_reg__clk, etc.) are
        // assigned from the input clk, so we need to update all of them for proper edge detection
        let clk_domain_indices = core.find_clock_domains_for_input(clk_idx);

        code.push_str("\n// ============================================================================\n");
        code.push_str("// MOS6502 Extension: Instruction-Level Execution with Opcode Capture\n");
        code.push_str("// ============================================================================\n\n");

        code.push_str("/// Run until N instructions complete, capturing (pc, opcode, sp) for each\n");
        code.push_str("/// Each opcode_tuple is packed as: (pc << 16) | (opcode << 8) | sp\n");
        code.push_str("/// Returns the number of instructions captured\n");
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_mos6502_instructions_with_opcodes(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    memory: *mut u8,\n");
        code.push_str("    rom_mask: *const bool,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    opcodes_out: *mut u64,\n");
        code.push_str("    opcodes_capacity: usize,\n");
        code.push_str("    speaker_toggles_out: *mut u32,\n");
        code.push_str(") -> usize {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let memory = std::slice::from_raw_parts_mut(memory, 65536);\n");
        code.push_str("    let rom_mask = std::slice::from_raw_parts(rom_mask, 65536);\n");
        code.push_str("    let opcodes_out = std::slice::from_raw_parts_mut(opcodes_out, opcodes_capacity);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("    let mut instruction_count: usize = 0;\n");
        code.push_str("    let max_cycles = n * 10; // Safety limit\n");
        code.push_str("    let mut cycles: usize = 0;\n");
        code.push_str(&format!("    let mut last_state = signals[{}];\n", state_idx));
        code.push_str("    const STATE_DECODE: u64 = 0x02;\n");
        code.push_str("\n");

        // Initialize old_clocks
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    while instruction_count < n && cycles < max_cycles {\n");

        // Clock falling edge FIRST - combinational outputs update (addr/rw become valid)
        // Set ALL clocks' old_clocks to 1 (previous state was high) for proper edge detection
        for i in 0..num_clocks {
            code.push_str(&format!("        old_clocks[{}] = 1; // Previous state was high\n", i));
        }
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // NOW do memory bridging (after evaluate, addr/rw reflect current state)
        code.push_str(&format!("        let addr = (signals[{}] as usize) & 0xFFFF;\n", addr_idx));
        code.push_str(&format!("        let rw = signals[{}];\n", rw_idx));
        code.push_str("\n");

        // Detect speaker toggle ($C030)
        code.push_str("        if addr == 0xC030 {\n");
        code.push_str("            speaker_toggles += 1;\n");
        code.push_str("        }\n\n");

        code.push_str("        if rw == 1 {\n");
        code.push_str("            // Read: provide data from memory to CPU\n");
        code.push_str(&format!("            signals[{}] = memory[addr] as u64;\n", data_in_idx));
        code.push_str("        } else {\n");
        code.push_str("            // Write: store CPU data to memory (unless ROM protected)\n");
        code.push_str("            if !rom_mask[addr] {\n");
        code.push_str(&format!("                memory[addr] = (signals[{}] & 0xFF) as u8;\n", data_out_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Clock rising edge - registers capture values (including data_in we just set)
        // Set ALL clocks' old_clocks to 0 (previous state was low) for proper edge detection
        for i in 0..num_clocks {
            code.push_str(&format!("        old_clocks[{}] = 0; // Previous state was low\n", i));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        // IMPORTANT: Must call evaluate_inline to propagate clk to internal clock signals
        // before tick_inline checks for rising edges on those internal signals
        code.push_str("        evaluate_inline(signals);\n");
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n");
        code.push_str("        cycles += 1;\n\n");

        // Check for state transition to DECODE
        code.push_str(&format!("        let current_state = signals[{}];\n", state_idx));
        code.push_str("        if current_state == STATE_DECODE && last_state != STATE_DECODE {\n");
        code.push_str(&format!("            let opcode = (signals[{}] & 0xFF) as u64;\n", opcode_idx));
        code.push_str(&format!("            let pc = ((signals[{}] as u64).wrapping_sub(1)) & 0xFFFF;\n", pc_idx));
        code.push_str(&format!("            let sp = (signals[{}] & 0xFF) as u64;\n", sp_idx));
        code.push_str("            opcodes_out[instruction_count] = (pc << 16) | (opcode << 8) | sp;\n");
        code.push_str("            instruction_count += 1;\n");
        code.push_str("        }\n");
        code.push_str("        last_state = current_state;\n");
        code.push_str("    }\n\n");

        code.push_str("    // Write speaker toggles to out parameter\n");
        code.push_str("    if !speaker_toggles_out.is_null() {\n");
        code.push_str("        *speaker_toggles_out = speaker_toggles;\n");
        code.push_str("    }\n");
        code.push_str("    instruction_count\n");
        code.push_str("}\n");

        code
    }
}
