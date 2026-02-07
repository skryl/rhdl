//! Game Boy full system simulation extension
//!
//! Provides batched cycle execution with memory bridging for Game Boy (DMG)

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

fn cart_ram_size_from_header(ram_size_code: u8) -> usize {
    match ram_size_code {
        0x00 => 0,
        0x01 => 2 * 1024,
        0x02 => 8 * 1024,
        0x03 => 32 * 1024,
        0x04 => 128 * 1024,
        0x05 => 64 * 1024,
        _ => 0,
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct GbMbcState {
    pub cart_type: u8,
    pub mbc1_rom_bank_low5: u8,
    pub mbc1_bank_high2: u8,
    pub mbc1_mode: u8,
    pub mbc1_ram_enable: u8,
    pub open_bus_data: u8,
    pub open_bus_cnt: u8,
}

impl Default for GbMbcState {
    fn default() -> Self {
        Self {
            cart_type: 0,
            mbc1_rom_bank_low5: 1,
            mbc1_bank_high2: 0,
            mbc1_mode: 0,
            mbc1_ram_enable: 0,
            open_bus_data: 0,
            open_bus_cnt: 0,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct GbMemReadLatches {
    pub vram_q_a: u8,
    pub vram_q_b: u8,
    pub zpram_q_a: u8,
    pub wram_q_a: u8,
    pub prev_vram_wren: u8,
    pub prev_zpram_wren: u8,
    pub prev_wram_wren: u8,
}

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
    /// Actual loaded ROM size in bytes
    pub rom_len: usize,
    /// Game Boy VRAM (8KB)
    pub vram: Vec<u8>,
    /// Game Boy WRAM (32KB for GBC, 8KB for DMG)
    pub wram: Vec<u8>,
    /// Cartridge RAM (MBC/external RAM, up to 128KB)
    pub cart_ram: Vec<u8>,
    /// Actual mapped cart RAM size from ROM header (0x149)
    pub cart_ram_len: usize,
    /// Game Boy boot ROM (256 bytes for DMG)
    pub boot_rom: Vec<u8>,
    /// Game Boy ZPRAM/HRAM (127 bytes, $FF80-$FFFE)
    pub zpram: Vec<u8>,
    /// Game Boy OAM (160 bytes, $FE00-$FE9F)
    pub oam: Vec<u8>,
    /// Framebuffer (160x144 pixels, 2-bit grayscale stored as u8)
    pub framebuffer: Vec<u8>,
    /// Latched synchronous DPRAM/SPRAM read outputs (updated on clock edge)
    pub mem_latches: GbMemReadLatches,

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
    pub ppu_h_cnt_idx: usize,
    pub ppu_v_cnt_idx: usize,
    pub ppu_vblank_irq_idx: usize,

    // Interrupt signals
    pub if_r_idx: usize,

    // Cart/ROM signals
    pub cart_rd_idx: usize,
    pub cart_wr_idx: usize,
    pub cart_di_idx: usize,
    pub cart_do_idx: usize,
    pub ext_bus_addr_idx: usize,
    pub ext_bus_a15_idx: usize,
    pub cpu_addr_idx: usize,
    pub cpu_wr_n_idx: usize,
    pub cpu_mreq_n_idx: usize,

    // VRAM signals
    pub vram_addr_cpu_idx: usize,
    pub vram_wren_cpu_idx: usize,
    pub vram_data_cpu_idx: usize,
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
    pub zpram_data_idx: usize,
    pub zpram_do_idx: usize,
    pub zpram_q_a_idx: usize,

    // WRAM signals
    pub wram_addr_idx: usize,
    pub wram_wren_idx: usize,
    pub wram_data_idx: usize,
    pub wram_do_idx: usize,
    pub wram_q_a_idx: usize,

    // Mapper state
    pub mbc_state: GbMbcState,

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
            usize::MAX
        };

        Self {
            rom: vec![0u8; 1024 * 1024],  // 1MB for Game Boy ROMs
            rom_len: 0,
            vram: vec![0u8; 8192],         // 8KB VRAM
            wram: vec![0u8; 32768],        // 32KB WRAM (8KB for DMG, up to 32KB for GBC)
            cart_ram: vec![0u8; 128 * 1024],
            cart_ram_len: 0,
            boot_rom: vec![0u8; 256],      // 256 bytes for DMG boot ROM
            zpram: vec![0u8; 127],         // 127 bytes for HRAM ($FF80-$FFFE)
            oam: vec![0u8; 160],           // 160 bytes for OAM ($FE00-$FE9F)
            framebuffer: vec![0u8; 160 * 144],
            mem_latches: GbMemReadLatches::default(),

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
            ppu_h_cnt_idx: find(&["gb_core__video_unit__h_cnt", "video_unit__h_cnt"]),
            ppu_v_cnt_idx: find(&["gb_core__video_unit__v_cnt", "video_unit__v_cnt"]),
            ppu_vblank_irq_idx: find(&["gb_core__vblank_irq", "vblank_irq", "gb_core__video_unit__vblank_irq", "video_unit__vblank_irq"]),

            if_r_idx: find(&["gb_core__if_r", "if_r"]),

            cart_rd_idx: find(&["cart_rd"]),
            cart_wr_idx: find(&["cart_wr"]),
            cart_di_idx: find(&["cart_di"]),
            cart_do_idx: find(&["cart_do"]),
            ext_bus_addr_idx: find(&["ext_bus_addr"]),
            ext_bus_a15_idx: find(&["ext_bus_a15"]),
            cpu_addr_idx: find(&["gb_core__cpu_addr", "cpu_addr"]),
            cpu_wr_n_idx: find(&["gb_core__cpu__wr_n", "cpu__wr_n"]),
            cpu_mreq_n_idx: find(&["gb_core__cpu__mreq_n", "cpu__mreq_n"]),

            vram_addr_cpu_idx: find(&["gb_core__vram_addr_cpu", "vram_addr_cpu"]),
            vram_wren_cpu_idx: find(&["gb_core__vram_wren_cpu", "vram_wren_cpu"]),
            vram_data_cpu_idx: find(&["gb_core__vram0__data_a", "vram0__data_a", "gb_core__cpu_do", "cpu_do"]),
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
            zpram_data_idx: find(&["gb_core__zpram__data_a", "zpram__data_a", "gb_core__cpu_do", "cpu_do"]),
            zpram_do_idx: find(&["gb_core__zpram_do", "zpram_do"]),
            zpram_q_a_idx: find(&["gb_core__zpram__q_a", "zpram__q_a"]),

            wram_addr_idx: find(&["gb_core__wram_addr", "wram_addr"]),
            wram_wren_idx: find(&["gb_core__wram_wren", "wram_wren"]),
            wram_data_idx: find(&["gb_core__wram__data_a", "wram__data_a", "gb_core__cpu_do", "cpu_do"]),
            wram_do_idx: find(&["gb_core__wram_do", "wram_do"]),
            wram_q_a_idx: find(&["gb_core__wram__q_a", "wram__q_a"]),

            mbc_state: GbMbcState::default(),
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
        self.rom.fill(0);
        let len = data.len().min(self.rom.len());
        self.rom[..len].copy_from_slice(&data[..len]);
        self.rom_len = len;

        let cart_type = if len > 0x147 { data[0x147] } else { 0x00 };
        let ram_size_code = if len > 0x149 { data[0x149] } else { 0x00 };
        self.cart_ram.fill(0xFF);
        self.cart_ram_len = cart_ram_size_from_header(ram_size_code).min(self.cart_ram.len());
        self.mbc_state = GbMbcState::default();
        self.mbc_state.cart_type = cart_type;
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

    /// Read from WRAM
    pub fn read_wram(&self, addr: usize) -> u8 {
        if addr < self.wram.len() {
            self.wram[addr]
        } else {
            0
        }
    }

    /// Write to WRAM
    pub fn write_wram(&mut self, addr: usize, data: u8) {
        if addr < self.wram.len() {
            self.wram[addr] = data;
        }
    }

    /// Read from OAM
    pub fn read_oam(&self, addr: usize) -> u8 {
        if addr < self.oam.len() {
            self.oam[addr]
        } else {
            0
        }
    }

    /// Write to OAM
    pub fn write_oam(&mut self, addr: usize, data: u8) {
        if addr < self.oam.len() {
            self.oam[addr] = data;
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
        self.oam.fill(0);
        self.mem_latches = GbMemReadLatches::default();
    }

    /// Run batched Game Boy cycles
    pub fn run_gb_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> GbCycleResult {
        if !core.compiled {
            return GbCycleResult::default();
        }

        #[cfg(feature = "aot")]
        unsafe {
            let result = crate::aot_generated::run_gb_cycles(
                core.signals.as_mut_ptr(),
                core.signals.len(),
                n,
                core.old_clocks.as_mut_ptr(),
                core.next_regs.as_mut_ptr(),
                self.framebuffer.as_mut_ptr(),
                (&mut self.lcd_state as *mut GbLcdState).cast::<crate::aot_generated::GbLcdState>(),
                self.rom.as_ptr(),
                self.rom.len(),
                self.vram.as_mut_ptr(),
                self.vram.len(),
                self.boot_rom.as_ptr(),
                self.boot_rom.len(),
                self.zpram.as_mut_ptr(),
                self.zpram.len(),
                self.wram.as_mut_ptr(),
                self.wram.len(),
            );
            GbCycleResult {
                cycles_run: result.cycles_run,
                frames_completed: result.frames_completed,
            }
        }

        #[cfg(not(feature = "aot"))]
        unsafe {
            let lib = core.compiled_lib.as_ref().unwrap();
            type RunGbCyclesFn = unsafe extern "C" fn(
                signals: *mut u64,
                signals_len: usize,
                n: usize,
                old_clocks: *mut u64,
                next_regs: *mut u64,
                framebuffer: *mut u8,
                lcd_state: *mut GbLcdState,
                mem_latches: *mut GbMemReadLatches,
                rom: *const u8,
                rom_len: usize,
                mbc_state: *mut GbMbcState,
                cart_ram: *mut u8,
                cart_ram_len: usize,
                vram: *mut u8,
                vram_len: usize,
                boot_rom: *const u8,
                boot_rom_len: usize,
                zpram: *mut u8,
                zpram_len: usize,
                wram: *mut u8,
                wram_len: usize,
                oam: *mut u8,
                oam_len: usize,
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
                &mut self.mem_latches,
                self.rom.as_ptr(),
                self.rom_len,
                &mut self.mbc_state,
                self.cart_ram.as_mut_ptr(),
                self.cart_ram_len,
                self.vram.as_mut_ptr(),
                self.vram.len(),
                self.boot_rom.as_ptr(),
                self.boot_rom.len(),
                self.zpram.as_mut_ptr(),
                self.zpram.len(),
                self.wram.as_mut_ptr(),
                self.wram.len(),
                self.oam.as_mut_ptr(),
                self.oam.len(),
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
            usize::MAX
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
        let ppu_pcnt_idx = find(&["gb_core__video_unit__pcnt", "video_unit__pcnt"]);
        let ppu_v_cnt_idx = find(&["gb_core__video_unit__v_cnt", "video_unit__v_cnt"]);

        let cart_rd_idx = find(&["cart_rd"]);
        let cart_wr_idx = find(&["cart_wr"]);
        let cart_di_idx = find(&["cart_di"]);
        let cart_do_idx = find(&["cart_do"]);
        let ext_bus_addr_idx = find(&["ext_bus_addr"]);
        let ext_bus_a15_idx = find(&["ext_bus_a15"]);
        let cpu_addr_idx = find(&["gb_core__cpu_addr", "cpu_addr"]);
        let cpu_wr_n_idx = find(&["gb_core__cpu__wr_n", "cpu__wr_n"]);
        let cpu_mreq_n_idx = find(&["gb_core__cpu__mreq_n", "cpu__mreq_n"]);

        // Sample direct memory-port signals for accurate write timing.
        let vram_addr_cpu_idx = find(&["gb_core__vram0__address_a", "vram0__address_a", "gb_core__vram_addr_mux", "vram_addr_mux", "gb_core__vram_addr_cpu", "vram_addr_cpu"]);
        let vram_wren_cpu_idx = find(&["gb_core__vram0__wren_a", "vram0__wren_a", "gb_core__vram_wren", "vram_wren", "gb_core__vram_wren_cpu", "vram_wren_cpu"]);
        let vram_data_cpu_idx = find(&["gb_core__vram0__data_a", "vram0__data_a", "gb_core__cpu_do", "cpu_do"]);
        let cpu_do_idx = find(&["gb_core__cpu_do", "cpu_do"]);
        let vram0_q_a_idx = find(&["gb_core__vram0__q_a", "gb_core__vram0__q_a_reg", "vram0__q_a"]);
        let vram0_q_b_idx = find(&["gb_core__vram0__q_b", "gb_core__vram0__q_b_reg", "vram0__q_b"]);
        let vram_addr_ppu_idx = find(&["gb_core__vram_addr_ppu", "vram_addr_ppu"]);
        let video_unit_vram_data_idx = find(&["gb_core__video_unit__vram_data", "video_unit__vram_data"]);

        let sel_boot_rom_idx = find(&["gb_core__sel_boot_rom", "sel_boot_rom"]);
        let boot_rom_addr_idx = find(&["gb_core__boot_rom_addr", "boot_rom_addr"]);
        // IMPORTANT: Write to top-level INPUT port, not internal net (which gets overwritten by evaluate)
        let boot_do_idx = find(&["boot_rom_do", "gb_core__boot_rom_do"]);

        let zpram_addr_idx = find(&["gb_core__zpram__address_a", "zpram__address_a", "gb_core__zpram_addr", "zpram_addr"]);
        let zpram_wren_idx = find(&["gb_core__zpram__wren_a", "zpram__wren_a", "gb_core__zpram_wren", "zpram_wren"]);
        let zpram_data_idx = find(&["gb_core__zpram__data_a", "zpram__data_a", "gb_core__cpu_do", "cpu_do"]);
        let zpram_q_a_idx = find(&["gb_core__zpram__q_a", "zpram__q_a"]);

        let wram_addr_idx = find(&["gb_core__wram__address_a", "wram__address_a", "gb_core__wram_addr", "wram_addr"]);
        let wram_wren_idx = find(&["gb_core__wram__wren_a", "wram__wren_a", "gb_core__wram_wren", "wram_wren"]);
        let wram_data_idx = find(&["gb_core__wram__data_a", "wram__data_a", "gb_core__cpu_do", "cpu_do"]);
        let wram_q_a_idx = find(&["gb_core__wram__q_a", "wram__q_a"]);
        let mem_vram0_idx = core.memory_name_to_idx.get("gb_core__vram0__mem").copied();
        let mem_zpram_idx = core.memory_name_to_idx.get("gb_core__zpram__mem").copied();
        let mem_wram_idx = core.memory_name_to_idx.get("gb_core__wram__mem").copied();
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

        code.push_str("const ROM_BANK_SIZE: usize = 0x4000;\n");
        code.push_str("const CART_RAM_BANK_SIZE: usize = 0x2000;\n\n");

        code.push_str("#[repr(C)]\n");
        code.push_str("#[derive(Clone, Copy, Default)]\n");
        code.push_str("pub struct GbMbcState {\n");
        code.push_str("    pub cart_type: u8,\n");
        code.push_str("    pub mbc1_rom_bank_low5: u8,\n");
        code.push_str("    pub mbc1_bank_high2: u8,\n");
        code.push_str("    pub mbc1_mode: u8,\n");
        code.push_str("    pub mbc1_ram_enable: u8,\n");
        code.push_str("    pub open_bus_data: u8,\n");
        code.push_str("    pub open_bus_cnt: u8,\n");
        code.push_str("}\n\n");

        code.push_str("#[repr(C)]\n");
        code.push_str("#[derive(Clone, Copy, Default)]\n");
        code.push_str("pub struct GbMemReadLatches {\n");
        code.push_str("    pub vram_q_a: u8,\n");
        code.push_str("    pub vram_q_b: u8,\n");
        code.push_str("    pub zpram_q_a: u8,\n");
        code.push_str("    pub wram_q_a: u8,\n");
        code.push_str("    pub prev_vram_wren: u8,\n");
        code.push_str("    pub prev_zpram_wren: u8,\n");
        code.push_str("    pub prev_wram_wren: u8,\n");
        code.push_str("}\n\n");

        code.push_str("#[inline(always)]\n");
        code.push_str("fn gb_is_mbc1(cart_type: u8) -> bool {\n");
        code.push_str("    matches!(cart_type, 0x01 | 0x02 | 0x03)\n");
        code.push_str("}\n\n");

        code.push_str("#[inline(always)]\n");
        code.push_str("fn gb_apply_mbc_write(mbc: &mut GbMbcState, full_addr: usize, data: u8) {\n");
        code.push_str("    if !gb_is_mbc1(mbc.cart_type) {\n");
        code.push_str("        return;\n");
        code.push_str("    }\n");
        code.push_str("    match full_addr & 0x7FFF {\n");
        code.push_str("        0x0000..=0x1FFF => {\n");
        code.push_str("            mbc.mbc1_ram_enable = ((data & 0x0F) == 0x0A) as u8;\n");
        code.push_str("        }\n");
        code.push_str("        0x2000..=0x3FFF => {\n");
        code.push_str("            let mut bank = data & 0x1F;\n");
        code.push_str("            if bank == 0 {\n");
        code.push_str("                bank = 1;\n");
        code.push_str("            }\n");
        code.push_str("            mbc.mbc1_rom_bank_low5 = bank;\n");
        code.push_str("        }\n");
        code.push_str("        0x4000..=0x5FFF => {\n");
        code.push_str("            mbc.mbc1_bank_high2 = data & 0x03;\n");
        code.push_str("        }\n");
        code.push_str("        0x6000..=0x7FFF => {\n");
        code.push_str("            mbc.mbc1_mode = data & 0x01;\n");
        code.push_str("        }\n");
        code.push_str("        _ => {}\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");

        code.push_str("#[inline(always)]\n");
        code.push_str("fn gb_map_cart_addr(mbc: &GbMbcState, full_addr: usize, rom_len: usize) -> usize {\n");
        code.push_str("    if rom_len == 0 {\n");
        code.push_str("        return 0;\n");
        code.push_str("    }\n");
        code.push_str("    let base_addr = full_addr & 0x7FFF;\n");
        code.push_str("    if !gb_is_mbc1(mbc.cart_type) {\n");
        code.push_str("        return base_addr % rom_len;\n");
        code.push_str("    }\n");
        code.push_str("    let rom_banks = (rom_len / ROM_BANK_SIZE).max(1);\n");
        code.push_str("    let bank_off = base_addr & 0x3FFF;\n");
        code.push_str("    let upper_window = (base_addr & 0x4000) != 0;\n");
        code.push_str("    let mut bank = if upper_window {\n");
        code.push_str("        let low5 = if mbc.mbc1_rom_bank_low5 == 0 { 1usize } else { mbc.mbc1_rom_bank_low5 as usize };\n");
        code.push_str("        let high2 = (mbc.mbc1_bank_high2 as usize) << 5;\n");
        code.push_str("        (low5 | high2) & 0x7F\n");
        code.push_str("    } else if mbc.mbc1_mode != 0 {\n");
        code.push_str("        ((mbc.mbc1_bank_high2 as usize) << 5) & 0x7F\n");
        code.push_str("    } else {\n");
        code.push_str("        0\n");
        code.push_str("    };\n");
        code.push_str("    bank %= rom_banks;\n");
        code.push_str("    if upper_window && rom_banks > 1 && bank == 0 {\n");
        code.push_str("        bank = 1;\n");
        code.push_str("    }\n");
        code.push_str("    ((bank * ROM_BANK_SIZE) + bank_off) % rom_len\n");
        code.push_str("}\n\n");

        code.push_str("#[inline(always)]\n");
        code.push_str("fn gb_map_cart_ram_addr(mbc: &GbMbcState, full_addr: usize, cart_ram_len: usize) -> Option<usize> {\n");
        code.push_str("    if cart_ram_len == 0 {\n");
        code.push_str("        return None;\n");
        code.push_str("    }\n");
        code.push_str("    let a = full_addr & 0xFFFF;\n");
        code.push_str("    if !(0xA000..=0xBFFF).contains(&a) {\n");
        code.push_str("        return None;\n");
        code.push_str("    }\n");
        code.push_str("    let bank_off = a & 0x1FFF;\n");
        code.push_str("    if gb_is_mbc1(mbc.cart_type) {\n");
        code.push_str("        if mbc.mbc1_ram_enable == 0 {\n");
        code.push_str("            return None;\n");
        code.push_str("        }\n");
        code.push_str("        let ram_banks = (cart_ram_len / CART_RAM_BANK_SIZE).max(1);\n");
        code.push_str("        let bank = if mbc.mbc1_mode != 0 { (mbc.mbc1_bank_high2 as usize) & 0x03 } else { 0 };\n");
        code.push_str("        let bank = bank % ram_banks;\n");
        code.push_str("        Some(((bank * CART_RAM_BANK_SIZE) + bank_off) % cart_ram_len)\n");
        code.push_str("    } else {\n");
        code.push_str("        Some(bank_off % cart_ram_len)\n");
        code.push_str("    }\n");
        code.push_str("}\n\n");

        code.push_str("#[inline(always)]\n");
        code.push_str("fn gb_read_dma_source(\n");
        code.push_str("    addr: usize,\n");
        code.push_str("    rom: &[u8],\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    mbc: &GbMbcState,\n");
        code.push_str("    cart_ram: &[u8],\n");
        code.push_str("    cart_ram_len: usize,\n");
        code.push_str("    vram: &[u8],\n");
        code.push_str("    vram_len: usize,\n");
        code.push_str("    wram: &[u8],\n");
        code.push_str("    wram_len: usize,\n");
        code.push_str("    zpram: &[u8],\n");
        code.push_str("    zpram_len: usize,\n");
        code.push_str(") -> u8 {\n");
        code.push_str("    let a = addr & 0xFFFF;\n");
        code.push_str("    match a {\n");
        code.push_str("        0x0000..=0x7FFF => {\n");
        code.push_str("            if rom_len == 0 { 0xFF } else { rom[gb_map_cart_addr(mbc, a, rom_len)] }\n");
        code.push_str("        }\n");
        code.push_str("        0xA000..=0xBFFF => {\n");
        code.push_str("            if let Some(idx) = gb_map_cart_ram_addr(mbc, a, cart_ram_len) {\n");
        code.push_str("                cart_ram[idx]\n");
        code.push_str("            } else {\n");
        code.push_str("                0xFF\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        code.push_str("        0x8000..=0x9FFF => {\n");
        code.push_str("            let idx = a - 0x8000;\n");
        code.push_str("            if idx < vram_len { vram[idx] } else { 0xFF }\n");
        code.push_str("        }\n");
        code.push_str("        0xC000..=0xDFFF => {\n");
        code.push_str("            let idx = a - 0xC000;\n");
        code.push_str("            if idx < wram_len { wram[idx] } else { 0xFF }\n");
        code.push_str("        }\n");
        code.push_str("        0xE000..=0xFDFF => {\n");
        code.push_str("            let idx = a - 0xE000;\n");
        code.push_str("            if idx < wram_len { wram[idx] } else { 0xFF }\n");
        code.push_str("        }\n");
        code.push_str("        0xFE00..=0xFE9F => 0xFF,\n");
        code.push_str("        0xFF80..=0xFFFE => {\n");
        code.push_str("            let idx = a - 0xFF80;\n");
        code.push_str("            if idx < zpram_len { zpram[idx] } else { 0xFF }\n");
        code.push_str("        }\n");
        code.push_str("        _ => 0xFF,\n");
        code.push_str("    }\n");
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
        code.push_str("    mem_latches: *mut GbMemReadLatches,\n");
        code.push_str("    rom: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    mbc_state: *mut GbMbcState,\n");
        code.push_str("    cart_ram: *mut u8,\n");
        code.push_str("    cart_ram_len: usize,\n");
        code.push_str("    vram: *mut u8,\n");
        code.push_str("    vram_len: usize,\n");
        code.push_str("    boot_rom: *const u8,\n");
        code.push_str("    boot_rom_len: usize,\n");
        code.push_str("    zpram: *mut u8,\n");
        code.push_str("    zpram_len: usize,\n");
        code.push_str("    wram: *mut u8,\n");
        code.push_str("    wram_len: usize,\n");
        code.push_str("    oam: *mut u8,\n");
        code.push_str("    oam_len: usize,\n");
        code.push_str(") -> GbCycleResult {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let framebuffer = std::slice::from_raw_parts_mut(framebuffer, 160 * 144);\n");
        code.push_str("    let lcd = &mut *lcd_state;\n");
        code.push_str("    let mem_l = &mut *mem_latches;\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom, rom_len);\n");
        code.push_str("    let mbc = &mut *mbc_state;\n");
        code.push_str("    let cart_ram = std::slice::from_raw_parts_mut(cart_ram, cart_ram_len);\n");
        code.push_str("    let vram = std::slice::from_raw_parts_mut(vram, vram_len);\n");
        code.push_str("    let boot_rom = std::slice::from_raw_parts(boot_rom, boot_rom_len);\n");
        code.push_str("    let zpram = std::slice::from_raw_parts_mut(zpram, zpram_len);\n");
        code.push_str("    let wram = std::slice::from_raw_parts_mut(wram, wram_len);\n");
        code.push_str("    let oam = std::slice::from_raw_parts_mut(oam, oam_len);\n");
        code.push_str("    let mut frames_completed: u32 = 0;\n\n");

        // Initialize old_clocks from current signal values
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");

        // Clock falling edge
        code.push_str(&format!("        signals[{}] = 0; // clk_sys low\n", clk_sys_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // Cartridge mapper writes/reads
        code.push_str(&format!("        let ext_addr = signals[{}] as usize;\n", ext_bus_addr_idx));
        code.push_str(&format!("        let a15 = signals[{}] as usize;\n", ext_bus_a15_idx));
        code.push_str("        let full_addr = ext_addr | (a15 << 15);\n");
        code.push_str(&format!("        let cart_wr = signals[{}];\n", cart_wr_idx));
        code.push_str("        if cart_wr != 0 {\n");
        code.push_str(&format!("            let cart_di = (signals[{}] & 0xFF) as u8;\n", cart_di_idx));
        code.push_str("            if full_addr <= 0x7FFF {\n");
        code.push_str("                gb_apply_mbc_write(mbc, full_addr, cart_di);\n");
        code.push_str("            } else if let Some(ram_addr) = gb_map_cart_ram_addr(mbc, full_addr, cart_ram_len) {\n");
        code.push_str("                cart_ram[ram_addr] = cart_di;\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        code.push_str(&format!("        let cart_rd = signals[{}];\n", cart_rd_idx));
        code.push_str("        let cart_ram_mapped = gb_map_cart_ram_addr(mbc, full_addr, cart_ram_len);\n");
        code.push_str("        let cart_oe = (full_addr <= 0x7FFF) || cart_ram_mapped.is_some();\n");
        code.push_str("        if cart_oe {\n");
        code.push_str("            mbc.open_bus_cnt = 0;\n");
        code.push_str("        } else if mbc.open_bus_cnt != 0xFF {\n");
        code.push_str("            mbc.open_bus_cnt = mbc.open_bus_cnt.wrapping_add(1);\n");
        code.push_str("            if mbc.open_bus_cnt == 4 {\n");
        code.push_str("                mbc.open_bus_data = 0xFF;\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        code.push_str("        let data = if full_addr <= 0x7FFF {\n");
        code.push_str("            let mapped_addr = gb_map_cart_addr(mbc, full_addr, rom_len);\n");
        code.push_str("            if mapped_addr < rom_len { rom[mapped_addr] } else { 0xFF }\n");
        code.push_str("        } else if let Some(ram_addr) = cart_ram_mapped {\n");
        code.push_str("            cart_ram[ram_addr]\n");
        code.push_str("        } else {\n");
        code.push_str("            mbc.open_bus_data\n");
        code.push_str("        };\n");
        code.push_str("        if cart_rd != 0 {\n");
        code.push_str("            mbc.open_bus_data = data;\n");
        code.push_str("        }\n");
        code.push_str(&format!("        signals[{}] = data as u64;\n\n", cart_do_idx));

        // Boot ROM handling
        code.push_str(&format!("        let sel_boot_rom = signals[{}];\n", sel_boot_rom_idx));
        code.push_str("        if sel_boot_rom != 0 {\n");
        code.push_str(&format!("            let boot_addr = (signals[{}] as usize) & 0xFF;\n", boot_rom_addr_idx));
        code.push_str("            if boot_addr < boot_rom_len {\n");
        code.push_str(&format!("                signals[{}] = boot_rom[boot_addr] as u64;\n", boot_do_idx));
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // OAM mirror updates:
        // - direct CPU writes to FE00-FE9F
        // - FF46 DMA trigger (bulk copy xx00-xx9F)
        if cpu_addr_idx != usize::MAX && cpu_wr_n_idx != usize::MAX && cpu_mreq_n_idx != usize::MAX {
            code.push_str(&format!("        let cpu_addr_full = (signals[{}] as usize) & 0xFFFF;\n", cpu_addr_idx));
            code.push_str(&format!("        let cpu_wr_n = signals[{}];\n", cpu_wr_n_idx));
            code.push_str(&format!("        let cpu_mreq_n = signals[{}];\n", cpu_mreq_n_idx));
            code.push_str("        let cpu_write = (cpu_wr_n == 0) && (cpu_mreq_n == 0);\n");
            code.push_str("        if cpu_write {\n");
            code.push_str(&format!("            let cpu_data = (signals[{}] & 0xFF) as u8;\n", cpu_do_idx));
            code.push_str("            if cpu_addr_full >= 0xFE00 && cpu_addr_full <= 0xFE9F {\n");
            code.push_str("                let oam_idx = cpu_addr_full - 0xFE00;\n");
            code.push_str("                if oam_idx < oam_len {\n");
            code.push_str("                    oam[oam_idx] = cpu_data;\n");
            code.push_str("                }\n");
            code.push_str("            }\n");
            code.push_str("            if cpu_addr_full == 0xFF46 {\n");
            code.push_str("                let page = (cpu_data as usize) << 8;\n");
            code.push_str("                let copy_len = oam_len.min(160);\n");
            code.push_str("                for i in 0..copy_len {\n");
            code.push_str("                    let src = (page + i) & 0xFFFF;\n");
            code.push_str("                    oam[i] = gb_read_dma_source(src, rom, rom_len, mbc, cart_ram, cart_ram_len, vram, vram_len, wram, wram_len, zpram, zpram_len);\n");
            code.push_str("                }\n");
            code.push_str("            }\n");
            code.push_str("        }\n\n");
        }

        // Re-evaluate combinational logic after cart/boot inputs are updated.
        // Internal RAM blocks (VRAM/WRAM/ZPRAM) are modeled by the core IR memories.
        code.push_str("        evaluate_inline(signals);\n");
        code.push_str("\n");

        // Track internal RAM writes only for external debug/FFI mirror reads.
        code.push_str(&format!("        let vram_addr_cpu = (signals[{}] as usize) & 0x1FFF;\n", vram_addr_cpu_idx));
        code.push_str(&format!("        let zpram_addr = (signals[{}] as usize) & 0x7F;\n", zpram_addr_idx));
        code.push_str(&format!("        let wram_addr = (signals[{}] as usize) & 0x7FFF;\n", wram_addr_idx));
        code.push_str(&format!("        let vram_wren_active = signals[{}] != 0;\n", vram_wren_cpu_idx));
        code.push_str("        let vram_wr_addr = vram_addr_cpu;\n");
        code.push_str(&format!("        let vram_wr_data = (signals[{}] & 0xFF) as u8;\n", vram_data_cpu_idx));
        code.push_str(&format!("        let zpram_wren_active = signals[{}] != 0;\n", zpram_wren_idx));
        code.push_str("        let zpram_wr_addr = zpram_addr;\n");
        code.push_str(&format!("        let zpram_wr_data = (signals[{}] & 0xFF) as u8;\n", zpram_data_idx));
        code.push_str(&format!("        let wram_wren_active = signals[{}] != 0;\n", wram_wren_idx));
        code.push_str("        let wram_wr_addr = wram_addr;\n");
        code.push_str(&format!("        let wram_wr_data = (signals[{}] & 0xFF) as u8;\n", wram_data_idx));
        code.push_str("\n");

        // Clock rising edge
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str(&format!("        signals[{}] = 1; // clk_sys high\n", clk_sys_idx));
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n\n");

        // Commit sampled synchronous memory writes
        code.push_str("        if vram_wren_active && vram_wr_addr < vram_len {\n");
        code.push_str("            vram[vram_wr_addr] = vram_wr_data;\n");
        if let Some(mem_idx) = mem_vram0_idx {
            code.push_str(&format!(
                "            if vram_wr_addr < MEM_{}.len() {{ MEM_{}[vram_wr_addr] = vram_wr_data as u64; }}\n",
                mem_idx, mem_idx
            ));
        }
        code.push_str("        }\n");
        code.push_str("        if zpram_wren_active && zpram_wr_addr < zpram_len {\n");
        code.push_str("            zpram[zpram_wr_addr] = zpram_wr_data;\n");
        if let Some(mem_idx) = mem_zpram_idx {
            code.push_str(&format!(
                "            if zpram_wr_addr < MEM_{}.len() {{ MEM_{}[zpram_wr_addr] = zpram_wr_data as u64; }}\n",
                mem_idx, mem_idx
            ));
        }
        code.push_str("        }\n");
        code.push_str("        if wram_wren_active && wram_wr_addr < wram_len {\n");
        code.push_str("            wram[wram_wr_addr] = wram_wr_data;\n");
        if let Some(mem_idx) = mem_wram_idx {
            code.push_str(&format!(
                "            if wram_wr_addr < MEM_{}.len() {{ MEM_{}[wram_wr_addr] = wram_wr_data as u64; }}\n",
                mem_idx, mem_idx
            ));
        }
        code.push_str("        }\n");
        code.push_str("        // Maintain mirror-latch snapshots for debug APIs.\n");
        code.push_str("        mem_l.vram_q_a = if vram_wr_addr < vram_len { vram[vram_wr_addr] } else { 0 };\n");
        code.push_str("        mem_l.vram_q_b = mem_l.vram_q_a;\n");
        code.push_str("        mem_l.zpram_q_a = if zpram_wr_addr < zpram_len { zpram[zpram_wr_addr] } else { 0 };\n");
        code.push_str("        mem_l.wram_q_a = if wram_wr_addr < wram_len { wram[wram_wr_addr] } else { 0 };\n\n");
        code.push_str("\n");

        // Reflect synchronous RAM commits in combinational consumers in the same cycle.
        code.push_str("        evaluate_inline(signals);\n\n");

        // LCD capture
        code.push_str(&format!("        let lcd_clkena = signals[{}];\n", lcd_clkena_idx));
        code.push_str(&format!("        let lcd_vsync = signals[{}];\n", lcd_vsync_idx));
        code.push_str(&format!("        let lcd_data = (signals[{}] & 0x3) as u8;\n", lcd_data_gb_idx));
        if ppu_pcnt_idx != usize::MAX && ppu_v_cnt_idx != usize::MAX {
            code.push_str(&format!("        let ppu_pcnt = signals[{}] as usize;\n", ppu_pcnt_idx));
            code.push_str(&format!("        let ppu_v_cnt = signals[{}] as usize;\n", ppu_v_cnt_idx));
            code.push_str("\n");
            code.push_str("        // Capture pixels by hardware counters to prevent raster drift.\n");
            code.push_str("        if lcd_clkena != 0 {\n");
            code.push_str("            if ppu_v_cnt < 144 && ppu_pcnt < 160 {\n");
            code.push_str("                let x = ppu_pcnt;\n");
            code.push_str("                let idx = ppu_v_cnt * 160 + x;\n");
            code.push_str("                framebuffer[idx] = lcd_data;\n");
            code.push_str("                lcd.x = x as u32;\n");
            code.push_str("                lcd.y = ppu_v_cnt as u32;\n");
            code.push_str("            }\n");
            code.push_str("        }\n\n");
        } else {
            code.push_str("        // Fallback raster capture when PPU counters are unavailable.\n");
            code.push_str("        if lcd_clkena != 0 {\n");
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
        }

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
