//! Game Boy full system simulation extension for Interpreter backend
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
    pub ppu_h_cnt_idx: usize,
    pub ppu_v_cnt_idx: usize,
    pub ppu_vblank_irq_idx: usize,

    // Interrupt signals
    pub if_r_idx: usize,

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
            ppu_h_cnt_idx: find(&["gb_core__video_unit__h_cnt", "video_unit__h_cnt"]),
            ppu_v_cnt_idx: find(&["gb_core__video_unit__v_cnt", "video_unit__v_cnt"]),
            ppu_vblank_irq_idx: find(&["gb_core__vblank_irq", "vblank_irq", "gb_core__video_unit__vblank_irq", "video_unit__vblank_irq"]),

            if_r_idx: find(&["gb_core__if_r", "if_r"]),

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

    /// Helper to poke a signal by index
    #[inline(always)]
    fn poke(core: &mut CoreSimulator, idx: usize, value: u64) {
        if idx < core.signals.len() {
            core.signals[idx] = value;
        }
    }

    /// Helper to peek a signal by index
    #[inline(always)]
    fn peek(core: &CoreSimulator, idx: usize) -> u64 {
        if idx < core.signals.len() {
            core.signals[idx]
        } else {
            0
        }
    }

    /// Run batched Game Boy cycles using interpreter evaluate/tick
    pub fn run_gb_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> GbCycleResult {
        let mut frames_completed: u32 = 0;

        for _ in 0..n {
            // Force CE signals for DMG mode
            if self.ce_idx > 0 {
                Self::poke(core, self.ce_idx, 1);
            }
            if self.speed_ctrl_ce_idx > 0 {
                Self::poke(core, self.speed_ctrl_ce_idx, 1);
            }
            if self.gb_core_ce_idx > 0 {
                Self::poke(core, self.gb_core_ce_idx, 1);
            }
            if self.video_unit_ce_idx > 0 {
                Self::poke(core, self.video_unit_ce_idx, 1);
            }
            if self.cpu_clken_idx > 0 {
                Self::poke(core, self.cpu_clken_idx, 1);
            }
            if self.sm83_clken_idx > 0 {
                Self::poke(core, self.sm83_clken_idx, 1);
            }

            // Clock falling edge
            Self::poke(core, self.clk_sys_idx, 0);
            core.evaluate();

            // Force CE signals after evaluate
            if self.ce_idx > 0 {
                Self::poke(core, self.ce_idx, 1);
            }
            if self.speed_ctrl_ce_idx > 0 {
                Self::poke(core, self.speed_ctrl_ce_idx, 1);
            }
            if self.gb_core_ce_idx > 0 {
                Self::poke(core, self.gb_core_ce_idx, 1);
            }
            if self.video_unit_ce_idx > 0 {
                Self::poke(core, self.video_unit_ce_idx, 1);
            }
            if self.cpu_clken_idx > 0 {
                Self::poke(core, self.cpu_clken_idx, 1);
            }
            if self.sm83_clken_idx > 0 {
                Self::poke(core, self.sm83_clken_idx, 1);
            }

            // ROM read handling
            let cart_rd = Self::peek(core, self.cart_rd_idx);
            let ext_addr = Self::peek(core, self.ext_bus_addr_idx) as usize;
            let a15 = Self::peek(core, self.ext_bus_a15_idx);
            if cart_rd != 0 {
                let full_addr = ext_addr | ((a15 as usize) << 15);
                if full_addr < self.rom.len() {
                    Self::poke(core, self.cart_do_idx, self.rom[full_addr] as u64);
                }
            }

            // Boot ROM handling
            let sel_boot_rom = Self::peek(core, self.sel_boot_rom_idx);
            if sel_boot_rom != 0 {
                let boot_addr = (Self::peek(core, self.boot_rom_addr_idx) as usize) & 0xFF;
                if boot_addr < self.boot_rom.len() {
                    Self::poke(core, self.boot_do_idx, self.boot_rom[boot_addr] as u64);
                }
            }

            // VRAM CPU read
            let vram_addr_cpu = (Self::peek(core, self.vram_addr_cpu_idx) as usize) & 0x1FFF;
            if vram_addr_cpu < self.vram.len() {
                Self::poke(core, self.vram0_q_a_idx, self.vram[vram_addr_cpu] as u64);
            }

            // VRAM PPU read
            let vram_addr_ppu = (Self::peek(core, self.vram_addr_ppu_idx) as usize) & 0x1FFF;
            if vram_addr_ppu < self.vram.len() {
                Self::poke(core, self.vram0_q_b_idx, self.vram[vram_addr_ppu] as u64);
                Self::poke(core, self.video_unit_vram_data_idx, self.vram[vram_addr_ppu] as u64);
            }

            // ZPRAM read
            let zpram_addr = (Self::peek(core, self.zpram_addr_idx) as usize) & 0x7F;
            if zpram_addr < self.zpram.len() {
                Self::poke(core, self.zpram_q_a_idx, self.zpram[zpram_addr] as u64);
            }

            // Clock rising edge - save all clock values BEFORE raising clk_sys
            // This is critical: we need to capture old clock values of derived clocks
            // (like gb_core__cpu__clk) which are 0 right now, so that after evaluate
            // propagates clk_sys=1 through the assign chain, we detect rising edges
            for (i, &clk_idx) in core.clock_indices.iter().enumerate() {
                core.prev_clock_values[i] = core.signals[clk_idx];
            }
            Self::poke(core, self.clk_sys_idx, 1);
            core.tick_forced();

            // VRAM write
            let vram_wren = Self::peek(core, self.vram_wren_cpu_idx);
            if vram_wren != 0 {
                let addr = (Self::peek(core, self.vram_addr_cpu_idx) as usize) & 0x1FFF;
                if addr < self.vram.len() {
                    self.vram[addr] = (Self::peek(core, self.cpu_do_idx) & 0xFF) as u8;
                }
            }

            // ZPRAM write
            let zpram_wren = Self::peek(core, self.zpram_wren_idx);
            if zpram_wren != 0 {
                let addr = (Self::peek(core, self.zpram_addr_idx) as usize) & 0x7F;
                if addr < self.zpram.len() {
                    self.zpram[addr] = (Self::peek(core, self.cpu_do_idx) & 0xFF) as u8;
                }
            }

            // LCD capture
            let lcd_clkena = Self::peek(core, self.lcd_clkena_idx);
            let lcd_vsync = Self::peek(core, self.lcd_vsync_idx);
            let lcd_data = (Self::peek(core, self.lcd_data_gb_idx) & 0x3) as u8;

            // Rising edge of lcd_clkena: capture pixel
            if lcd_clkena != 0 && self.lcd_state.prev_clkena == 0 {
                if self.lcd_state.x < 160 && self.lcd_state.y < 144 {
                    let idx = (self.lcd_state.y as usize) * 160 + (self.lcd_state.x as usize);
                    self.framebuffer[idx] = lcd_data;
                }
                self.lcd_state.x += 1;
                if self.lcd_state.x >= 160 {
                    self.lcd_state.x = 0;
                    self.lcd_state.y += 1;
                }
            }

            // Rising edge of lcd_vsync: end of frame
            if lcd_vsync != 0 && self.lcd_state.prev_vsync == 0 {
                self.lcd_state.x = 0;
                self.lcd_state.y = 0;
                self.lcd_state.frame_count += 1;
                frames_completed += 1;
            }

            self.lcd_state.prev_clkena = lcd_clkena as u32;
            self.lcd_state.prev_vsync = lcd_vsync as u32;
        }

        GbCycleResult {
            cycles_run: n,
            frames_completed,
        }
    }
}
