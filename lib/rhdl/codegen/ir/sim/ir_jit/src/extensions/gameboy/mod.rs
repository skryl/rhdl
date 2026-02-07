//! Game Boy full system simulation extension for JIT backend
//!
//! Provides batched cycle execution with memory bridging for Game Boy (DMG)

mod ffi;

use std::collections::HashMap;
use crate::core::CoreSimulator;

pub use ffi::*;

const ROM_BANK_SIZE: usize = 0x4000;
const CART_RAM_BANK_SIZE: usize = 0x2000;

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
    /// Cartridge RAM (MBC/external RAM, up to 128KB)
    pub cart_ram: Vec<u8>,
    /// Actual mapped cart RAM size from ROM header (0x149)
    pub cart_ram_len: usize,
    /// Game Boy boot ROM (256 bytes for DMG)
    pub boot_rom: Vec<u8>,
    /// Game Boy ZPRAM/HRAM (127 bytes, $FF80-$FFFE)
    pub zpram: Vec<u8>,
    /// Framebuffer (160x144 pixels, 2-bit grayscale stored as u8)
    pub framebuffer: Vec<u8>,
    /// Latched synchronous DPRAM/SPRAM read outputs (updated on clock edge)
    pub vram_q_a_latched: u8,
    pub vram_q_b_latched: u8,
    pub zpram_q_a_latched: u8,
    /// Core IR memory indices for bridged RAM blocks
    pub mem_vram0_idx: usize,
    pub mem_zpram_idx: usize,
    pub mem_wram_idx: usize,

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

    // WRAM signals
    pub wram_addr_idx: usize,
    pub wram_wren_idx: usize,

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
            cart_ram: vec![0xFFu8; 128 * 1024],
            cart_ram_len: 0,
            boot_rom: vec![0u8; 256],      // 256 bytes for DMG boot ROM
            zpram: vec![0u8; 127],         // 127 bytes for HRAM ($FF80-$FFFE)
            framebuffer: vec![0u8; 160 * 144],
            vram_q_a_latched: 0,
            vram_q_b_latched: 0,
            zpram_q_a_latched: 0,
            mem_vram0_idx: core.memory_name_to_idx.get("gb_core__vram0__mem").copied().unwrap_or(usize::MAX),
            mem_zpram_idx: core.memory_name_to_idx.get("gb_core__zpram__mem").copied().unwrap_or(usize::MAX),
            mem_wram_idx: core.memory_name_to_idx.get("gb_core__wram__mem").copied().unwrap_or(usize::MAX),

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

            wram_addr_idx: find(&["gb_core__wram_addr", "wram_addr"]),
            wram_wren_idx: find(&["gb_core__wram_wren", "wram_wren"]),

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
        self.vram_q_a_latched = 0;
        self.vram_q_b_latched = 0;
        self.zpram_q_a_latched = 0;
    }

    #[inline(always)]
    fn is_mbc1_cart(cart_type: u8) -> bool {
        matches!(cart_type, 0x01 | 0x02 | 0x03)
    }

    #[inline(always)]
    fn apply_cart_write(mbc: &mut GbMbcState, full_addr: usize, data: u8) {
        if !Self::is_mbc1_cart(mbc.cart_type) {
            return;
        }

        match full_addr & 0x7FFF {
            0x0000..=0x1FFF => {
                mbc.mbc1_ram_enable = ((data & 0x0F) == 0x0A) as u8;
            }
            0x2000..=0x3FFF => {
                let mut bank = data & 0x1F;
                if bank == 0 {
                    bank = 1;
                }
                mbc.mbc1_rom_bank_low5 = bank;
            }
            0x4000..=0x5FFF => {
                mbc.mbc1_bank_high2 = data & 0x03;
            }
            0x6000..=0x7FFF => {
                mbc.mbc1_mode = data & 0x01;
            }
            _ => {}
        }
    }

    #[inline(always)]
    fn map_cart_addr(mbc: &GbMbcState, full_addr: usize, rom_len: usize) -> usize {
        if rom_len == 0 {
            return 0;
        }

        let base_addr = full_addr & 0x7FFF;
        if !Self::is_mbc1_cart(mbc.cart_type) {
            return base_addr % rom_len;
        }

        let rom_banks = (rom_len / ROM_BANK_SIZE).max(1);
        let bank_off = base_addr & 0x3FFF;
        let upper_window = (base_addr & 0x4000) != 0;

        let mut bank = if upper_window {
            let low5 = if mbc.mbc1_rom_bank_low5 == 0 {
                1usize
            } else {
                mbc.mbc1_rom_bank_low5 as usize
            };
            // MBC1 upper 16KB bank always includes the high bank bits.
            let high2 = (mbc.mbc1_bank_high2 as usize) << 5;
            (low5 | high2) & 0x7F
        } else if mbc.mbc1_mode != 0 {
            ((mbc.mbc1_bank_high2 as usize) << 5) & 0x7F
        } else {
            0
        };

        bank %= rom_banks;
        if upper_window && rom_banks > 1 && bank == 0 {
            bank = 1;
        }

        ((bank * ROM_BANK_SIZE) + bank_off) % rom_len
    }

    #[inline(always)]
    fn map_cart_ram_addr(mbc: &GbMbcState, full_addr: usize, cart_ram_len: usize) -> Option<usize> {
        if cart_ram_len == 0 {
            return None;
        }

        let a = full_addr & 0xFFFF;
        if !(0xA000..=0xBFFF).contains(&a) {
            return None;
        }

        let bank_off = a & 0x1FFF;
        if Self::is_mbc1_cart(mbc.cart_type) {
            if mbc.mbc1_ram_enable == 0 {
                return None;
            }
            let ram_banks = (cart_ram_len / CART_RAM_BANK_SIZE).max(1);
            let bank = if mbc.mbc1_mode != 0 {
                (mbc.mbc1_bank_high2 as usize) & 0x03
            } else {
                0
            };
            Some(((bank % ram_banks) * CART_RAM_BANK_SIZE + bank_off) % cart_ram_len)
        } else {
            Some(bank_off % cart_ram_len)
        }
    }

    /// Run batched Game Boy cycles using JIT-compiled evaluate/tick
    pub fn run_gb_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> GbCycleResult {
        let mut frames_completed: u32 = 0;

        for _ in 0..n {
            // Clock falling edge
            core.poke_by_idx(self.clk_sys_idx, 0);
            core.evaluate();

            // Cartridge mapper writes/reads
            let ext_addr = core.peek_by_idx(self.ext_bus_addr_idx) as usize;
            let a15 = core.peek_by_idx(self.ext_bus_a15_idx) as usize;
            let full_addr = ext_addr | (a15 << 15);

            let cart_wr = core.peek_by_idx(self.cart_wr_idx);
            if cart_wr != 0 {
                let cart_di = (core.peek_by_idx(self.cart_di_idx) & 0xFF) as u8;
                if full_addr <= 0x7FFF {
                    Self::apply_cart_write(&mut self.mbc_state, full_addr, cart_di);
                } else if let Some(ram_addr) = Self::map_cart_ram_addr(&self.mbc_state, full_addr, self.cart_ram_len) {
                    self.cart_ram[ram_addr] = cart_di;
                }
            }

            let cart_rd = core.peek_by_idx(self.cart_rd_idx);
            let cart_ram_mapped = Self::map_cart_ram_addr(&self.mbc_state, full_addr, self.cart_ram_len);
            let cart_oe = (full_addr <= 0x7FFF) || cart_ram_mapped.is_some();
            if cart_oe {
                self.mbc_state.open_bus_cnt = 0;
            } else if self.mbc_state.open_bus_cnt != u8::MAX {
                self.mbc_state.open_bus_cnt = self.mbc_state.open_bus_cnt.wrapping_add(1);
                if self.mbc_state.open_bus_cnt == 4 {
                    self.mbc_state.open_bus_data = 0xFF;
                }
            }
            let value = if full_addr <= 0x7FFF {
                let mapped_addr = Self::map_cart_addr(&self.mbc_state, full_addr, self.rom_len);
                if mapped_addr < self.rom_len { self.rom[mapped_addr] } else { 0xFF }
            } else if let Some(ram_addr) = cart_ram_mapped {
                self.cart_ram[ram_addr]
            } else {
                self.mbc_state.open_bus_data
            };
            if cart_rd != 0 {
                self.mbc_state.open_bus_data = value;
            }
            core.poke_by_idx(self.cart_do_idx, value as u64);

            // Boot ROM handling
            let sel_boot_rom = core.peek_by_idx(self.sel_boot_rom_idx);
            if sel_boot_rom != 0 {
                let boot_addr = (core.peek_by_idx(self.boot_rom_addr_idx) as usize) & 0xFF;
                if boot_addr < self.boot_rom.len() {
                    core.poke_by_idx(self.boot_do_idx, self.boot_rom[boot_addr] as u64);
                }
            }

            // Internal RAM blocks are modeled by the core memory system.
            // We only keep mirror arrays for optional debug/FFI reads.
            let vram_addr_cpu = (core.peek_by_idx(self.vram_addr_cpu_idx) as usize) & 0x1FFF;
            let _vram_addr_ppu = (core.peek_by_idx(self.vram_addr_ppu_idx) as usize) & 0x1FFF;
            let zpram_addr = (core.peek_by_idx(self.zpram_addr_idx) as usize) & 0x7F;
            let wram_addr = (core.peek_by_idx(self.wram_addr_idx) as usize) & 0x7FFF;

            // Re-evaluate combinational logic after memory/cart/boot inputs are updated.
            core.evaluate();

            // Sample synchronous memory writes/reads that occur on this rising edge.
            let vram_wren_edge = core.peek_by_idx(self.vram_wren_cpu_idx) != 0;
            let vram_wr_addr = vram_addr_cpu;
            let vram_wr_data = (core.peek_by_idx(self.cpu_do_idx) & 0xFF) as u8;

            let zpram_wren_edge = core.peek_by_idx(self.zpram_wren_idx) != 0;
            let zpram_wr_addr = zpram_addr;
            let zpram_wr_data = (core.peek_by_idx(self.cpu_do_idx) & 0xFF) as u8;

            let wram_wren_edge = core.peek_by_idx(self.wram_wren_idx) != 0;
            let wram_wr_addr = wram_addr;
            let wram_wr_data = (core.peek_by_idx(self.cpu_do_idx) & 0xFF) as u8;

            // Clock rising edge - save all clock values BEFORE raising clk_sys
            // This is critical: we need to capture old clock values of derived clocks
            // (like gb_core__cpu__clk) which are 0 right now, so that after evaluate
            // propagates clk_sys=1 through the assign chain, we detect rising edges
            for (i, &clk_idx) in core.clock_indices.iter().enumerate() {
                core.prev_clock_values[i] = core.signals[clk_idx];
            }
            core.poke_by_idx(self.clk_sys_idx, 1);
            core.tick_forced();

            // Commit sampled synchronous memory writes.
            if vram_wren_edge && vram_wr_addr < self.vram.len() {
                self.vram[vram_wr_addr] = vram_wr_data;
                if self.mem_vram0_idx != usize::MAX {
                    if let Some(mem) = core.memory_arrays.get_mut(self.mem_vram0_idx) {
                        if vram_wr_addr < mem.len() {
                            mem[vram_wr_addr] = vram_wr_data as u64;
                        }
                    }
                }
            }
            if zpram_wren_edge && zpram_wr_addr < self.zpram.len() {
                self.zpram[zpram_wr_addr] = zpram_wr_data;
                if self.mem_zpram_idx != usize::MAX {
                    if let Some(mem) = core.memory_arrays.get_mut(self.mem_zpram_idx) {
                        if zpram_wr_addr < mem.len() {
                            mem[zpram_wr_addr] = zpram_wr_data as u64;
                        }
                    }
                }
            }
            if wram_wren_edge {
                if self.mem_wram_idx != usize::MAX {
                    if let Some(mem) = core.memory_arrays.get_mut(self.mem_wram_idx) {
                        if wram_wr_addr < mem.len() {
                            mem[wram_wr_addr] = wram_wr_data as u64;
                        }
                    }
                }
            }

            // Refresh local latches after the edge from shadow RAM.
            let vram_addr_cpu_next = (core.peek_by_idx(self.vram_addr_cpu_idx) as usize) & 0x1FFF;
            let vram_addr_ppu_next = (core.peek_by_idx(self.vram_addr_ppu_idx) as usize) & 0x1FFF;
            let zpram_addr_next = (core.peek_by_idx(self.zpram_addr_idx) as usize) & 0x7F;
            let vram_q_a_next = if vram_addr_cpu_next < self.vram.len() {
                self.vram[vram_addr_cpu_next]
            } else {
                0
            };
            let vram_q_b_next = if vram_addr_ppu_next < self.vram.len() {
                self.vram[vram_addr_ppu_next]
            } else {
                0
            };
            let zpram_q_a_next = if zpram_addr_next < self.zpram.len() {
                self.zpram[zpram_addr_next]
            } else {
                0
            };
            self.vram_q_a_latched = vram_q_a_next;
            self.vram_q_b_latched = vram_q_b_next;
            self.zpram_q_a_latched = zpram_q_a_next;

            // LCD capture
            let lcd_clkena = core.peek_by_idx(self.lcd_clkena_idx);
            let lcd_vsync = core.peek_by_idx(self.lcd_vsync_idx);
            let lcd_data = (core.peek_by_idx(self.lcd_data_gb_idx) & 0x3) as u8;

            // Capture pixels by hardware counters to prevent software raster drift.
            if lcd_clkena != 0 {
                if self.ppu_pcnt_idx != usize::MAX && self.ppu_v_cnt_idx != usize::MAX {
                    let pcnt = core.peek_by_idx(self.ppu_pcnt_idx) as usize;
                    let v_cnt = core.peek_by_idx(self.ppu_v_cnt_idx) as usize;
                    if v_cnt < 144 && pcnt < 160 {
                        let x = pcnt;
                        let idx = v_cnt * 160 + x;
                        self.framebuffer[idx] = lcd_data;
                        self.lcd_state.x = x as u32;
                        self.lcd_state.y = v_cnt as u32;
                    }
                } else {
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
