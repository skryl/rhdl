//! Game Boy full system simulation extension
//!
//! Provides batched cycle execution with memory bridging for Game Boy (DMG)

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

/// Result from running Game Boy cycles
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct GbCycleResult {
    pub cycles_run: usize,
    pub frames_completed: u32,
}

/// LCD state for Game Boy simulation
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct GbLcdState {
    pub x: u32,
    pub y: u32,
    pub prev_clkena: u32,
    pub prev_vsync: u32,
    pub frame_count: u64,
}

/// Game Boy specific extension state
pub struct GameBoyExtension {
    /// Game Boy ROM (up to 1MB)
    pub rom: Vec<u8>,
    /// Game Boy VRAM (8KB)
    pub vram: Vec<u8>,
    /// Game Boy boot ROM (256 bytes for DMG)
    pub boot_rom: Vec<u8>,
    /// Game Boy ZPRAM/HRAM (127 bytes, $FF80-$FFFE)
    pub zpram: Vec<u8>,
    /// Framebuffer (160x144 pixels, 2-bit grayscale stored as u8)
    pub framebuffer: Vec<u8>,

    // Signal indices
    pub clk_sys_idx: usize,
    pub ce_idx: usize,
    pub speed_ctrl_ce_idx: usize,
    pub gb_core_ce_idx: usize,
    pub video_unit_ce_idx: usize,
    pub cpu_clken_idx: usize,
    pub sm83_clken_idx: usize,

    // LCD signals
    pub lcd_clkena_idx: usize,
    pub lcd_data_gb_idx: usize,
    pub lcd_hsync_idx: usize,
    pub lcd_vsync_idx: usize,
    pub lcd_on_idx: usize,

    // PPU signals
    pub ppu_mode3_idx: usize,
    pub ppu_lcdc_on_idx: usize,
    pub ppu_h_div_cnt_idx: usize,
    pub ppu_pcnt_idx: usize,

    // Cart/ROM signals
    pub cart_rd_idx: usize,
    pub cart_do_idx: usize,
    pub ext_bus_addr_idx: usize,
    pub ext_bus_a15_idx: usize,

    // VRAM signals
    pub vram_addr_cpu_idx: usize,
    pub vram_wren_cpu_idx: usize,
    pub cpu_do_idx: usize,
    pub vram0_q_a_idx: usize,
    pub vram0_q_b_idx: usize,
    pub vram_addr_ppu_idx: usize,
    pub vram_do_idx: usize,
    pub vram_data_ppu_idx: usize,
    pub video_unit_vram_data_idx: usize,

    // Boot ROM signals
    pub sel_boot_rom_idx: usize,
    pub boot_rom_addr_idx: usize,
    pub boot_do_idx: usize,

    // ZPRAM signals
    pub zpram_addr_idx: usize,
    pub zpram_wren_idx: usize,
    pub zpram_do_idx: usize,
    pub zpram_q_a_idx: usize,

    // LCD state
    pub lcd_state: GbLcdState,
}

impl GameBoyExtension {
    /// Create Game Boy extension by detecting signal indices from the simulator
    pub fn new(core: &CoreSimulator) -> Self {
        let n = &core.name_to_idx;

        // Helper to find signal with optional prefixes
        let find = |names: &[&str]| -> usize {
            for name in names {
                if let Some(&idx) = n.get(*name) {
                    return idx;
                }
            }
            0
        };

        Self {
            rom: vec![0u8; 1024 * 1024],  // 1MB for Game Boy ROMs
            vram: vec![0u8; 8192],         // 8KB VRAM
            boot_rom: vec![0u8; 256],      // 256 bytes for DMG boot ROM
            zpram: vec![0u8; 127],         // 127 bytes for HRAM ($FF80-$FFFE)
            framebuffer: vec![0u8; 160 * 144],

            clk_sys_idx: find(&["clk_sys", "gb_core__clk_sys"]),
            ce_idx: find(&["ce", "gb_core__ce"]),
            speed_ctrl_ce_idx: find(&["speed_ctrl__ce"]),
            gb_core_ce_idx: find(&["gb_core__ce"]),
            video_unit_ce_idx: find(&["gb_core__video_unit__ce"]),
            cpu_clken_idx: find(&["gb_core__cpu_clken", "cpu_clken"]),
            sm83_clken_idx: find(&["gb_core__cpu__clken", "cpu__clken"]),

            lcd_clkena_idx: find(&["lcd_clkena"]),
            lcd_data_gb_idx: find(&["lcd_data_gb"]),
            lcd_hsync_idx: find(&["lcd_hsync"]),
            lcd_vsync_idx: find(&["lcd_vsync"]),
            lcd_on_idx: find(&["lcd_on"]),

            ppu_mode3_idx: find(&["gb_core__video_unit__mode3", "video_unit__mode3"]),
            ppu_lcdc_on_idx: find(&["gb_core__video_unit__lcdc_on", "video_unit__lcdc_on"]),
            ppu_h_div_cnt_idx: find(&["gb_core__video_unit__h_div_cnt", "video_unit__h_div_cnt"]),
            ppu_pcnt_idx: find(&["gb_core__video_unit__pcnt", "video_unit__pcnt"]),

            cart_rd_idx: find(&["cart_rd"]),
            cart_do_idx: find(&["cart_do"]),
            ext_bus_addr_idx: find(&["ext_bus_addr"]),
            ext_bus_a15_idx: find(&["ext_bus_a15"]),

            vram_addr_cpu_idx: find(&["gb_core__vram_addr_cpu", "vram_addr_cpu"]),
            vram_wren_cpu_idx: find(&["gb_core__vram_wren_cpu", "vram_wren_cpu"]),
            cpu_do_idx: find(&["gb_core__cpu_do", "cpu_do"]),
            vram0_q_a_idx: find(&["gb_core__vram0__q_a", "gb_core__vram0__q_a_reg", "vram0__q_a"]),
            vram0_q_b_idx: find(&["gb_core__vram0__q_b", "gb_core__vram0__q_b_reg", "vram0__q_b"]),
            vram_addr_ppu_idx: find(&["gb_core__vram_addr_ppu", "vram_addr_ppu"]),
            vram_do_idx: find(&["gb_core__vram_do", "vram_do"]),
            vram_data_ppu_idx: find(&["gb_core__vram_data_ppu", "vram_data_ppu"]),
            video_unit_vram_data_idx: find(&["gb_core__video_unit__vram_data", "video_unit__vram_data"]),

            sel_boot_rom_idx: find(&["gb_core__sel_boot_rom", "sel_boot_rom"]),
            boot_rom_addr_idx: find(&["gb_core__boot_rom_addr", "boot_rom_addr"]),
            // IMPORTANT: Write to top-level INPUT port, not internal net (which gets overwritten by evaluate)
            boot_do_idx: find(&["boot_rom_do", "gb_core__boot_rom_do"]),

            zpram_addr_idx: find(&["gb_core__zpram_addr", "zpram_addr"]),
            zpram_wren_idx: find(&["gb_core__zpram_wren", "zpram_wren"]),
            zpram_do_idx: find(&["gb_core__zpram_do", "zpram_do"]),
            zpram_q_a_idx: find(&["gb_core__zpram__q_a", "zpram__q_a"]),

            lcd_state: GbLcdState::default(),
        }
    }

    /// Check if the simulator has Game Boy specific signals
    pub fn is_gameboy_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        name_to_idx.contains_key("lcd_clkena")
            && name_to_idx.contains_key("lcd_data_gb")
            && name_to_idx.contains_key("ce")
    }

    /// Load ROM data
    pub fn load_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.rom.len());
        self.rom[..len].copy_from_slice(&data[..len]);
    }

    /// Load boot ROM data
    pub fn load_boot_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.boot_rom.len());
        self.boot_rom[..len].copy_from_slice(&data[..len]);
    }

    /// Read from VRAM
    pub fn read_vram(&self, addr: usize) -> u8 {
        if addr < self.vram.len() {
            self.vram[addr]
        } else {
            0
        }
    }

    /// Write to VRAM
    pub fn write_vram(&mut self, addr: usize, data: u8) {
        if addr < self.vram.len() {
            self.vram[addr] = data;
        }
    }

    /// Read from ZPRAM
    pub fn read_zpram(&self, addr: usize) -> u8 {
        if addr < self.zpram.len() {
            self.zpram[addr]
        } else {
            0
        }
    }

    /// Write to ZPRAM
    pub fn write_zpram(&mut self, addr: usize, data: u8) {
        if addr < self.zpram.len() {
            self.zpram[addr] = data;
        }
    }

    /// Get framebuffer reference
    pub fn framebuffer(&self) -> &[u8] {
        &self.framebuffer
    }

    /// Get current frame count
    pub fn frame_count(&self) -> u64 {
        self.lcd_state.frame_count
    }

    /// Reset LCD state
    pub fn reset_lcd_state(&mut self) {
        self.lcd_state = GbLcdState::default();
        self.framebuffer.fill(0);
    }

    /// Run batched Game Boy cycles
    pub fn run_gb_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> GbCycleResult {
        if !core.compiled {
            return GbCycleResult::default();
        }

        let lib = core.compiled_lib.as_ref().unwrap();
        unsafe {
            type RunGbCyclesFn = unsafe extern "C" fn(
                signals: *mut u64,
                signals_len: usize,
                n: usize,
                old_clocks: *mut u64,
                next_regs: *mut u64,
                framebuffer: *mut u8,
                lcd_state: *mut GbLcdState,
                rom: *const u8,
                rom_len: usize,
                vram: *mut u8,
                vram_len: usize,
                boot_rom: *const u8,
                boot_rom_len: usize,
                zpram: *mut u8,
                zpram_len: usize,
            ) -> GbCycleResult;

            let func: libloading::Symbol<RunGbCyclesFn> = lib.get(b"run_gb_cycles")
                .expect("run_gb_cycles function not found - is this a Game Boy IR?");

            let result = func(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                n,
                core.old_clocks.as_mut_ptr(),
                core.next_regs.as_mut_ptr(),
                self.framebuffer.as_mut_ptr(),
                &mut self.lcd_state,
                self.rom.as_ptr(),
                self.rom.len(),
                self.vram.as_mut_ptr(),
                self.vram.len(),
                self.boot_rom.as_ptr(),
                self.boot_rom.len(),
                self.zpram.as_mut_ptr(),
                self.zpram.len(),
            );

            result
        }
    }

    /// Generate Game Boy specific batched execution code
    pub fn generate_code(core: &CoreSimulator) -> String {
        let mut code = String::new();
        let n = &core.name_to_idx;

        // Helper to find signal with optional prefixes
        let find = |names: &[&str]| -> usize {
            for name in names {
                if let Some(&idx) = n.get(*name) {
                    return idx;
                }
            }
            0
        };

        // Get signal indices
        let clk_sys_idx = find(&["clk_sys", "gb_core__clk_sys"]);
        let ce_idx = find(&["ce", "gb_core__ce"]);
        let speed_ctrl_ce_idx = find(&["speed_ctrl__ce"]);
        let gb_core_ce_idx = find(&["gb_core__ce"]);
        let video_unit_ce_idx = find(&["gb_core__video_unit__ce"]);
        let cpu_clken_idx = find(&["gb_core__cpu_clken", "cpu_clken"]);
        let sm83_clken_idx = find(&["gb_core__cpu__clken", "cpu__clken"]);

        let lcd_clkena_idx = find(&["lcd_clkena"]);
        let lcd_data_gb_idx = find(&["lcd_data_gb"]);
        let lcd_vsync_idx = find(&["lcd_vsync"]);

        let cart_rd_idx = find(&["cart_rd"]);
        let cart_do_idx = find(&["cart_do"]);
        let ext_bus_addr_idx = find(&["ext_bus_addr"]);
        let ext_bus_a15_idx = find(&["ext_bus_a15"]);

        let vram_addr_cpu_idx = find(&["gb_core__vram_addr_cpu", "vram_addr_cpu"]);
        let vram_wren_cpu_idx = find(&["gb_core__vram_wren_cpu", "vram_wren_cpu"]);
        let cpu_do_idx = find(&["gb_core__cpu_do", "cpu_do"]);
        let vram0_q_a_idx = find(&["gb_core__vram0__q_a", "gb_core__vram0__q_a_reg", "vram0__q_a"]);
        let vram0_q_b_idx = find(&["gb_core__vram0__q_b", "gb_core__vram0__q_b_reg", "vram0__q_b"]);
        let vram_addr_ppu_idx = find(&["gb_core__vram_addr_ppu", "vram_addr_ppu"]);
        let video_unit_vram_data_idx = find(&["gb_core__video_unit__vram_data", "video_unit__vram_data"]);

        let sel_boot_rom_idx = find(&["gb_core__sel_boot_rom", "sel_boot_rom"]);
        let boot_rom_addr_idx = find(&["gb_core__boot_rom_addr", "boot_rom_addr"]);
        // IMPORTANT: Write to top-level INPUT port, not internal net (which gets overwritten by evaluate)
        let boot_do_idx = find(&["boot_rom_do", "gb_core__boot_rom_do"]);

        let zpram_addr_idx = find(&["gb_core__zpram_addr", "zpram_addr"]);
        let zpram_wren_idx = find(&["gb_core__zpram_wren", "zpram_wren"]);
        let zpram_q_a_idx = find(&["gb_core__zpram__q_a", "zpram__q_a"]);

        let clock_indices: Vec<usize> = core.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = core.seq_targets.len();

        code.push_str("\n// ============================================================================\n");
        code.push_str("// Game Boy Extension: Batched Cycle Execution with LCD Capture\n");
        code.push_str("// ============================================================================\n\n");

        // GbLcdState struct
        code.push_str("#[repr(C)]\n");
        code.push_str("#[derive(Clone, Copy, Default)]\n");
        code.push_str("pub struct GbLcdState {\n");
        code.push_str("    pub x: u32,\n");
        code.push_str("    pub y: u32,\n");
        code.push_str("    pub prev_clkena: u32,\n");
        code.push_str("    pub prev_vsync: u32,\n");
        code.push_str("    pub frame_count: u64,\n");
        code.push_str("}\n\n");

        // GbCycleResult struct
        code.push_str("#[repr(C)]\n");
        code.push_str("#[derive(Clone, Copy, Default)]\n");
        code.push_str("pub struct GbCycleResult {\n");
        code.push_str("    pub cycles_run: usize,\n");
        code.push_str("    pub frames_completed: u32,\n");
        code.push_str("}\n\n");

        // run_gb_cycles function
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_gb_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    _old_clocks: *mut u64,\n");
        code.push_str("    _next_regs: *mut u64,\n");
        code.push_str("    framebuffer: *mut u8,\n");
        code.push_str("    lcd_state: *mut GbLcdState,\n");
        code.push_str("    rom: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    vram: *mut u8,\n");
        code.push_str("    vram_len: usize,\n");
        code.push_str("    boot_rom: *const u8,\n");
        code.push_str("    boot_rom_len: usize,\n");
        code.push_str("    zpram: *mut u8,\n");
        code.push_str("    zpram_len: usize,\n");
        code.push_str(") -> GbCycleResult {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let framebuffer = std::slice::from_raw_parts_mut(framebuffer, 160 * 144);\n");
        code.push_str("    let lcd = &mut *lcd_state;\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom, rom_len);\n");
        code.push_str("    let vram = std::slice::from_raw_parts_mut(vram, vram_len);\n");
        code.push_str("    let boot_rom = std::slice::from_raw_parts(boot_rom, boot_rom_len);\n");
        code.push_str("    let zpram = std::slice::from_raw_parts_mut(zpram, zpram_len);\n");
        code.push_str("    let mut frames_completed: u32 = 0;\n\n");

        // Initialize old_clocks from current signal values
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");

        // Force CE and cpu_clken high for DMG mode
        if ce_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // ce\n", ce_idx));
        }
        if speed_ctrl_ce_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // speed_ctrl__ce\n", speed_ctrl_ce_idx));
        }
        if gb_core_ce_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // gb_core__ce\n", gb_core_ce_idx));
        }
        if video_unit_ce_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // video_unit__ce\n", video_unit_ce_idx));
        }
        if cpu_clken_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // cpu_clken\n", cpu_clken_idx));
        }
        if sm83_clken_idx > 0 {
            code.push_str(&format!("        signals[{}] = 1; // sm83_clken\n", sm83_clken_idx));
        }
        code.push_str("\n");

        // Clock falling edge
        code.push_str(&format!("        signals[{}] = 0; // clk_sys low\n", clk_sys_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // ROM read handling
        code.push_str(&format!("        let cart_rd = signals[{}];\n", cart_rd_idx));
        code.push_str(&format!("        let ext_addr = signals[{}] as usize;\n", ext_bus_addr_idx));
        code.push_str(&format!("        let a15 = signals[{}];\n", ext_bus_a15_idx));
        code.push_str("        if cart_rd != 0 {\n");
        code.push_str("            let full_addr = ext_addr | ((a15 as usize) << 15);\n");
        code.push_str("            if full_addr < rom_len {\n");
        code.push_str(&format!("                signals[{}] = rom[full_addr] as u64;\n", cart_do_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Boot ROM handling
        code.push_str(&format!("        let sel_boot_rom = signals[{}];\n", sel_boot_rom_idx));
        code.push_str("        if sel_boot_rom != 0 {\n");
        code.push_str(&format!("            let boot_addr = (signals[{}] as usize) & 0xFF;\n", boot_rom_addr_idx));
        code.push_str("            if boot_addr < boot_rom_len {\n");
        code.push_str(&format!("                signals[{}] = boot_rom[boot_addr] as u64;\n", boot_do_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // VRAM CPU read (inject into DPRAM output)
        code.push_str(&format!("        let vram_addr_cpu = (signals[{}] as usize) & 0x1FFF;\n", vram_addr_cpu_idx));
        code.push_str("        if vram_addr_cpu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[vram_addr_cpu] as u64;\n", vram0_q_a_idx));
        code.push_str("        }\n\n");

        // VRAM PPU read
        code.push_str(&format!("        let vram_addr_ppu = (signals[{}] as usize) & 0x1FFF;\n", vram_addr_ppu_idx));
        code.push_str("        if vram_addr_ppu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[vram_addr_ppu] as u64;\n", vram0_q_b_idx));
        code.push_str(&format!("            signals[{}] = vram[vram_addr_ppu] as u64;\n", video_unit_vram_data_idx));
        code.push_str("        }\n\n");

        // ZPRAM read
        code.push_str(&format!("        let zpram_addr = (signals[{}] as usize) & 0x7F;\n", zpram_addr_idx));
        code.push_str("        if zpram_addr < zpram_len {\n");
        code.push_str(&format!("            signals[{}] = zpram[zpram_addr] as u64;\n", zpram_q_a_idx));
        code.push_str("        }\n\n");

        // Clock rising edge
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str(&format!("        signals[{}] = 1; // clk_sys high\n", clk_sys_idx));
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n\n");

        // VRAM write
        code.push_str(&format!("        let vram_wren = signals[{}];\n", vram_wren_cpu_idx));
        code.push_str("        if vram_wren != 0 {\n");
        code.push_str(&format!("            let addr = (signals[{}] as usize) & 0x1FFF;\n", vram_addr_cpu_idx));
        code.push_str("            if addr < vram_len {\n");
        code.push_str(&format!("                vram[addr] = (signals[{}] & 0xFF) as u8;\n", cpu_do_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // ZPRAM write
        code.push_str(&format!("        let zpram_wren = signals[{}];\n", zpram_wren_idx));
        code.push_str("        if zpram_wren != 0 {\n");
        code.push_str(&format!("            let addr = (signals[{}] as usize) & 0x7F;\n", zpram_addr_idx));
        code.push_str("            if addr < zpram_len {\n");
        code.push_str(&format!("                zpram[addr] = (signals[{}] & 0xFF) as u8;\n", cpu_do_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // LCD capture
        code.push_str(&format!("        let lcd_clkena = signals[{}];\n", lcd_clkena_idx));
        code.push_str(&format!("        let lcd_vsync = signals[{}];\n", lcd_vsync_idx));
        code.push_str(&format!("        let lcd_data = (signals[{}] & 0x3) as u8;\n", lcd_data_gb_idx));
        code.push_str("\n");
        code.push_str("        // Rising edge of lcd_clkena: capture pixel\n");
        code.push_str("        if lcd_clkena != 0 && lcd.prev_clkena == 0 {\n");
        code.push_str("            if lcd.x < 160 && lcd.y < 144 {\n");
        code.push_str("                let idx = (lcd.y as usize) * 160 + (lcd.x as usize);\n");
        code.push_str("                framebuffer[idx] = lcd_data;\n");
        code.push_str("            }\n");
        code.push_str("            lcd.x += 1;\n");
        code.push_str("            if lcd.x >= 160 {\n");
        code.push_str("                lcd.x = 0;\n");
        code.push_str("                lcd.y += 1;\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        code.push_str("        // Rising edge of lcd_vsync: end of frame\n");
        code.push_str("        if lcd_vsync != 0 && lcd.prev_vsync == 0 {\n");
        code.push_str("            lcd.x = 0;\n");
        code.push_str("            lcd.y = 0;\n");
        code.push_str("            lcd.frame_count += 1;\n");
        code.push_str("            frames_completed += 1;\n");
        code.push_str("        }\n\n");

        code.push_str("        lcd.prev_clkena = lcd_clkena as u32;\n");
        code.push_str("        lcd.prev_vsync = lcd_vsync as u32;\n");

        code.push_str("    }\n\n");

        code.push_str("    GbCycleResult {\n");
        code.push_str("        cycles_run: n,\n");
        code.push_str("        frames_completed,\n");
        code.push_str("    }\n");
        code.push_str("}\n");

        code
    }
}
