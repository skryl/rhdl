//! IR Compiler - generates specialized Rust code from Behavior IR
//!
//! This compiler generates Rust source code that directly implements the circuit
//! evaluation logic, then compiles it with rustc at runtime for maximum performance.
//!
//! The generated code uses the exact same evaluation semantics as the ir_interpreter,
//! making it easy to verify correctness via PC progression comparison.

use magnus::{method, prelude::*, Error, RArray, RHash, Ruby, TryConvert, Value};
use serde::Deserialize;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::process::Command;

// ============================================================================
// IR Data Structures (matching JSON format from Ruby's IRToJson)
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Direction {
    In,
    Out,
}

#[derive(Debug, Clone, Deserialize)]
struct PortDef {
    name: String,
    direction: Direction,
    width: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct NetDef {
    name: String,
    width: usize,
}

#[derive(Debug, Clone, Deserialize)]
struct RegDef {
    name: String,
    width: usize,
    #[serde(default)]
    reset_value: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ExprDef {
    Signal { name: String, width: usize },
    Literal { value: i64, width: usize },
    UnaryOp { op: String, operand: Box<ExprDef>, width: usize },
    BinaryOp { op: String, left: Box<ExprDef>, right: Box<ExprDef>, width: usize },
    Mux { condition: Box<ExprDef>, when_true: Box<ExprDef>, when_false: Box<ExprDef>, width: usize },
    Slice { base: Box<ExprDef>, low: usize, #[allow(dead_code)] high: usize, width: usize },
    Concat { parts: Vec<ExprDef>, width: usize },
    Resize { expr: Box<ExprDef>, width: usize },
    MemRead { memory: String, addr: Box<ExprDef>, width: usize },
}

#[derive(Debug, Clone, Deserialize)]
struct AssignDef {
    target: String,
    expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
struct SeqAssignDef {
    target: String,
    expr: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
struct ProcessDef {
    #[allow(dead_code)]
    name: String,
    clock: Option<String>,
    clocked: bool,
    statements: Vec<SeqAssignDef>,
}

#[derive(Debug, Clone, Deserialize)]
struct MemoryDef {
    name: String,
    depth: usize,
    #[allow(dead_code)]
    width: usize,
    #[serde(default)]
    initial_data: Vec<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct WritePortDef {
    memory: String,
    clock: String,
    addr: ExprDef,
    data: ExprDef,
    enable: ExprDef,
}

#[derive(Debug, Clone, Deserialize)]
struct SyncReadPortDef {
    memory: String,
    clock: String,
    addr: ExprDef,
    data: String,
    #[serde(default)]
    enable: Option<ExprDef>,
}

#[derive(Debug, Clone, Deserialize)]
struct ModuleIR {
    #[allow(dead_code)]
    name: String,
    ports: Vec<PortDef>,
    nets: Vec<NetDef>,
    regs: Vec<RegDef>,
    assigns: Vec<AssignDef>,
    processes: Vec<ProcessDef>,
    #[serde(default)]
    memories: Vec<MemoryDef>,
    #[serde(default)]
    write_ports: Vec<WritePortDef>,
    #[serde(default)]
    sync_read_ports: Vec<SyncReadPortDef>,
}

// ============================================================================
// Simulator State
// ============================================================================

struct IrSimulator {
    /// IR definition
    ir: ModuleIR,
    /// Signal values (Vec for O(1) access)
    signals: Vec<u64>,
    /// Signal widths
    widths: Vec<usize>,
    /// Signal name to index mapping
    name_to_idx: HashMap<String, usize>,
    /// Input names
    input_names: Vec<String>,
    /// Output names
    output_names: Vec<String>,
    /// Reset values for registers (signal index -> reset value)
    reset_values: Vec<(usize, u64)>,
    /// Next register values buffer
    next_regs: Vec<u64>,
    /// Sequential assignment target indices
    seq_targets: Vec<usize>,
    /// Clock signal index for each sequential assignment
    seq_clocks: Vec<usize>,
    /// All unique clock signal indices
    clock_indices: Vec<usize>,
    /// Old clock values for edge detection
    old_clocks: Vec<u64>,
    /// Pre-grouped: for each clock domain, list of (seq_assign_idx, target_idx)
    clock_domain_assigns: Vec<Vec<(usize, usize)>>,
    /// Memory arrays
    memory_arrays: Vec<Vec<u64>>,
    /// Memory name to index
    memory_name_to_idx: HashMap<String, usize>,
    /// Compiled library (if compilation succeeded)
    compiled_lib: Option<libloading::Library>,
    /// Whether compilation succeeded
    compiled: bool,
    /// Apple II specific: RAM
    ram: Vec<u8>,
    /// Apple II specific: ROM
    rom: Vec<u8>,
    /// Apple II specific signal indices
    ram_addr_idx: usize,
    ram_do_idx: usize,
    ram_we_idx: usize,
    d_idx: usize,
    clk_idx: usize,
    k_idx: usize,
    read_key_idx: usize,
    speaker_idx: usize,
    prev_speaker: u64,
    cpu_addr_idx: usize,
    /// Number of sub-cycles per CPU cycle (default: 14 for full accuracy)
    sub_cycles: usize,

    // MOS6502 CPU-only mode: memory bridging internalized
    /// True if this is a MOS6502 CPU IR (has addr, data_in, data_out, rw signals)
    mos6502_mode: bool,
    /// MOS6502 memory (64KB unified)
    mos6502_memory: Vec<u8>,
    /// MOS6502 ROM mask (true = ROM protected)
    mos6502_rom_mask: Vec<bool>,
    /// MOS6502 address output signal index
    mos6502_addr_idx: usize,
    /// MOS6502 data input signal index
    mos6502_data_in_idx: usize,
    /// MOS6502 data output signal index
    mos6502_data_out_idx: usize,
    /// MOS6502 read/write signal index (1=read, 0=write)
    mos6502_rw_idx: usize,
    /// MOS6502 clock signal index
    mos6502_clk_idx: usize,
    /// MOS6502 speaker toggle counter (incremented on $C030 access)
    mos6502_speaker_toggles: u32,

    // Game Boy LCD framebuffer capture
    /// Game Boy mode flag
    gameboy_mode: bool,
    /// CLK_SYS signal index for Game Boy
    gb_clk_sys_idx: usize,
    /// CE (clock enable) signal index for Game Boy
    gb_ce_idx: usize,
    /// LCD clock enable signal index
    lcd_clkena_idx: usize,
    /// LCD data (2-bit grayscale) signal index
    lcd_data_gb_idx: usize,
    /// LCD hsync signal index
    lcd_hsync_idx: usize,
    /// LCD vsync signal index
    lcd_vsync_idx: usize,
    /// LCD on signal index
    lcd_on_idx: usize,
    /// Cart read signal index
    gb_cart_rd_idx: usize,
    /// Cart data out signal index (cart provides data to CPU)
    gb_cart_do_idx: usize,
    /// External bus address (lower 15 bits)
    gb_ext_bus_addr_idx: usize,
    /// External bus A15 (upper address bit)
    gb_ext_bus_a15_idx: usize,
    /// Game Boy ROM (up to 1MB)
    gb_rom: Vec<u8>,
    /// Game Boy VRAM (8KB)
    gb_vram: Vec<u8>,
    /// VRAM CPU address signal index
    gb_vram_addr_cpu_idx: usize,
    /// VRAM CPU write enable signal index
    gb_vram_wren_cpu_idx: usize,
    /// CPU data output signal index
    gb_cpu_do_idx: usize,
    /// VRAM DPRAM port A register (CPU read result)
    gb_vram0_q_a_reg_idx: usize,
    /// VRAM DPRAM port B register (PPU read result)
    gb_vram0_q_b_reg_idx: usize,
    /// VRAM PPU address signal index
    gb_vram_addr_ppu_idx: usize,
    /// VRAM data output (to CPU) signal index (for compatibility)
    gb_vram_do_idx: usize,
    /// VRAM PPU data signal index (for compatibility)
    gb_vram_data_ppu_idx: usize,
    /// Game Boy boot ROM (256 bytes for DMG)
    gb_boot_rom: Vec<u8>,
    /// Boot ROM enabled signal index
    gb_sel_boot_rom_idx: usize,
    /// Boot ROM address signal index (8 bits)
    gb_boot_rom_addr_idx: usize,
    /// Boot ROM data output signal index
    gb_boot_do_idx: usize,
    /// Previous lcd_clkena value for edge detection
    prev_lcd_clkena: u64,
    /// Previous lcd_vsync value for edge detection
    prev_lcd_vsync: u64,
    /// Framebuffer (160x144 pixels, 2-bit grayscale stored as u8)
    framebuffer: Vec<u8>,
    /// Current pixel X position
    lcd_x: usize,
    /// Current pixel Y position
    lcd_y: usize,
    /// Frame count
    frame_count: u64,
}

impl IrSimulator {
    fn new(json: &str, sub_cycles: usize) -> Result<Self, String> {
        // Use deserializer with disabled recursion limit for deeply nested IR
        let mut deserializer = serde_json::Deserializer::from_str(json);
        deserializer.disable_recursion_limit();
        let ir: ModuleIR = serde::Deserialize::deserialize(&mut deserializer)
            .map_err(|e| format!("Failed to parse IR JSON: {}", e))?;

        let mut signals = Vec::new();
        let mut widths = Vec::new();
        let mut name_to_idx = HashMap::new();
        let mut input_names = Vec::new();
        let mut output_names = Vec::new();

        // Build signal table - ports first
        for port in &ir.ports {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(port.width);
            name_to_idx.insert(port.name.clone(), idx);
            match port.direction {
                Direction::In => input_names.push(port.name.clone()),
                Direction::Out => output_names.push(port.name.clone()),
            }
        }

        // Wires
        for net in &ir.nets {
            let idx = signals.len();
            signals.push(0u64);
            widths.push(net.width);
            name_to_idx.insert(net.name.clone(), idx);
        }

        // Registers with reset values
        let mut reset_values: Vec<(usize, u64)> = Vec::new();
        for reg in &ir.regs {
            let idx = signals.len();
            let reset_val = reg.reset_value.unwrap_or(0);
            signals.push(reset_val);
            widths.push(reg.width);
            name_to_idx.insert(reg.name.clone(), idx);
            if reset_val != 0 {
                reset_values.push((idx, reset_val));
            }
        }

        // Build memory arrays
        let mut memory_arrays = Vec::new();
        let mut memory_name_to_idx = HashMap::new();
        for (idx, mem) in ir.memories.iter().enumerate() {
            let mut data = vec![0u64; mem.depth];
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i < data.len() {
                    data[i] = val;
                }
            }
            memory_arrays.push(data);
            memory_name_to_idx.insert(mem.name.clone(), idx);
        }

        // Build sequential assignment tracking
        let mut seq_targets = Vec::new();
        let mut seq_clocks = Vec::new();
        let mut clock_set = std::collections::HashSet::new();

        for process in &ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| name_to_idx.get(c).copied())
                .unwrap_or_else(|| *name_to_idx.get("clk_14m").unwrap_or(&0));
            clock_set.insert(clock_idx);

            for stmt in &process.statements {
                let target_idx = *name_to_idx.get(&stmt.target).unwrap_or(&0);
                seq_targets.push(target_idx);
                seq_clocks.push(clock_idx);
            }
        }

        // Sort clock indices for deterministic order (HashSet iteration is non-deterministic)
        let mut clock_indices: Vec<usize> = clock_set.into_iter().collect();
        clock_indices.sort();
        let old_clocks = vec![0u64; clock_indices.len()];
        let next_regs = vec![0u64; seq_targets.len()];

        // Build clock_domain_assigns: for each clock domain, list of (seq_assign_idx, target_idx)
        let mut clock_domain_assigns: Vec<Vec<(usize, usize)>> = vec![Vec::new(); clock_indices.len()];
        for (seq_idx, &clk_idx) in seq_clocks.iter().enumerate() {
            if let Some(clock_list_idx) = clock_indices.iter().position(|&ci| ci == clk_idx) {
                let target_idx = seq_targets[seq_idx];
                clock_domain_assigns[clock_list_idx].push((seq_idx, target_idx));
            }
        }

        // Apple II signal indices
        let ram_addr_idx = *name_to_idx.get("ram_addr").unwrap_or(&0);
        let ram_do_idx = *name_to_idx.get("ram_do").unwrap_or(&0);
        let ram_we_idx = *name_to_idx.get("ram_we").unwrap_or(&0);
        let d_idx = *name_to_idx.get("d").unwrap_or(&0);
        let clk_idx = *name_to_idx.get("clk_14m").unwrap_or(&0);
        let k_idx = *name_to_idx.get("k").unwrap_or(&0);
        let read_key_idx = *name_to_idx.get("read_key").unwrap_or(&0);
        let speaker_idx = *name_to_idx.get("speaker").unwrap_or(&0);
        // Use CPU's address register for memory reads (not ram_addr which may show video address)
        let cpu_addr_idx = *name_to_idx.get("cpu__addr_reg").unwrap_or(&0);

        // Detect MOS6502 CPU-only mode (has addr, data_in, data_out, rw, clk signals)
        let mos6502_addr_idx = *name_to_idx.get("addr").unwrap_or(&0);
        let mos6502_data_in_idx = *name_to_idx.get("data_in").unwrap_or(&0);
        let mos6502_data_out_idx = *name_to_idx.get("data_out").unwrap_or(&0);
        let mos6502_rw_idx = *name_to_idx.get("rw").unwrap_or(&0);
        let mos6502_clk_idx = *name_to_idx.get("clk").unwrap_or(&0);
        let mos6502_mode = name_to_idx.contains_key("addr")
            && name_to_idx.contains_key("data_in")
            && name_to_idx.contains_key("data_out")
            && name_to_idx.contains_key("rw")
            && name_to_idx.contains_key("clk");

        // Detect Game Boy mode (has lcd_clkena, lcd_data_gb signals)
        let gb_clk_sys_idx = *name_to_idx.get("clk_sys").unwrap_or(&0);
        let gb_ce_idx = *name_to_idx.get("ce").unwrap_or(&0);
        let lcd_clkena_idx = *name_to_idx.get("lcd_clkena").unwrap_or(&0);
        let lcd_data_gb_idx = *name_to_idx.get("lcd_data_gb").unwrap_or(&0);
        let lcd_hsync_idx = *name_to_idx.get("lcd_hsync").unwrap_or(&0);
        let lcd_vsync_idx = *name_to_idx.get("lcd_vsync").unwrap_or(&0);
        let lcd_on_idx = *name_to_idx.get("lcd_on").unwrap_or(&0);
        let gb_cart_rd_idx = *name_to_idx.get("cart_rd").unwrap_or(&0);
        let gb_cart_do_idx = *name_to_idx.get("cart_do").unwrap_or(&0);
        let gb_ext_bus_addr_idx = *name_to_idx.get("ext_bus_addr").unwrap_or(&0);
        let gb_ext_bus_a15_idx = *name_to_idx.get("ext_bus_a15").unwrap_or(&0);
        // VRAM signal indices (try prefixed names first, then unprefixed)
        let gb_vram_addr_cpu_idx = *name_to_idx.get("gb_core__vram_addr_cpu")
            .or_else(|| name_to_idx.get("vram_addr_cpu"))
            .unwrap_or(&0);
        let gb_vram_wren_cpu_idx = *name_to_idx.get("gb_core__vram_wren_cpu")
            .or_else(|| name_to_idx.get("vram_wren_cpu"))
            .unwrap_or(&0);
        let gb_cpu_do_idx = *name_to_idx.get("gb_core__cpu_do")
            .or_else(|| name_to_idx.get("cpu_do"))
            .unwrap_or(&0);
        // For VRAM reads, inject into the DPRAM output signals directly
        // The outputs are q_a and q_b (not q_a_reg - those don't exist in flattened IR)
        let gb_vram0_q_a_reg_idx = *name_to_idx.get("gb_core__vram0__q_a")
            .or_else(|| name_to_idx.get("gb_core__vram0__q_a_reg"))
            .or_else(|| name_to_idx.get("vram0__q_a"))
            .unwrap_or(&0);
        let gb_vram0_q_b_reg_idx = *name_to_idx.get("gb_core__vram0__q_b")
            .or_else(|| name_to_idx.get("gb_core__vram0__q_b_reg"))
            .or_else(|| name_to_idx.get("vram0__q_b"))
            .unwrap_or(&0);
        let gb_vram_addr_ppu_idx = *name_to_idx.get("gb_core__vram_addr_ppu")
            .or_else(|| name_to_idx.get("vram_addr_ppu"))
            .unwrap_or(&0);
        // Keep these for write address
        let gb_vram_do_idx = *name_to_idx.get("gb_core__vram_do")
            .or_else(|| name_to_idx.get("vram_do"))
            .unwrap_or(&0);
        let gb_vram_data_ppu_idx = *name_to_idx.get("gb_core__vram_data_ppu")
            .or_else(|| name_to_idx.get("vram_data_ppu"))
            .unwrap_or(&0);
        // Boot ROM signal indices
        let gb_sel_boot_rom_idx = *name_to_idx.get("gb_core__sel_boot_rom")
            .or_else(|| name_to_idx.get("sel_boot_rom"))
            .unwrap_or(&0);
        let gb_boot_rom_addr_idx = *name_to_idx.get("gb_core__boot_rom_addr")
            .or_else(|| name_to_idx.get("boot_rom_addr"))
            .unwrap_or(&0);
        let gb_boot_do_idx = *name_to_idx.get("gb_core__boot_do")
            .or_else(|| name_to_idx.get("boot_do"))
            .unwrap_or(&0);
        let gameboy_mode = name_to_idx.contains_key("lcd_clkena")
            && name_to_idx.contains_key("lcd_data_gb")
            && name_to_idx.contains_key("ce");

        Ok(Self {
            ir,
            signals,
            widths,
            name_to_idx,
            input_names,
            output_names,
            reset_values,
            next_regs,
            seq_targets,
            seq_clocks,
            clock_indices,
            old_clocks,
            clock_domain_assigns,
            memory_arrays,
            memory_name_to_idx,
            compiled_lib: None,
            compiled: false,
            ram: vec![0u8; 48 * 1024],
            rom: vec![0u8; 12 * 1024],
            ram_addr_idx,
            ram_do_idx,
            ram_we_idx,
            d_idx,
            clk_idx,
            k_idx,
            read_key_idx,
            speaker_idx,
            prev_speaker: 0,
            cpu_addr_idx,
            sub_cycles: sub_cycles.max(1).min(14),  // Clamp to 1-14
            mos6502_mode,
            mos6502_memory: vec![0u8; 64 * 1024],
            mos6502_rom_mask: vec![false; 64 * 1024],
            mos6502_addr_idx,
            mos6502_data_in_idx,
            mos6502_data_out_idx,
            mos6502_rw_idx,
            mos6502_clk_idx,
            mos6502_speaker_toggles: 0,
            // Game Boy LCD
            gameboy_mode,
            gb_clk_sys_idx,
            gb_ce_idx,
            lcd_clkena_idx,
            lcd_data_gb_idx,
            lcd_hsync_idx,
            lcd_vsync_idx,
            lcd_on_idx,
            gb_cart_rd_idx,
            gb_cart_do_idx,
            gb_ext_bus_addr_idx,
            gb_ext_bus_a15_idx,
            gb_rom: vec![0u8; 1024 * 1024],  // 1MB for Game Boy ROMs
            gb_vram: vec![0u8; 8192],  // 8KB VRAM for Game Boy
            gb_vram_addr_cpu_idx,
            gb_vram_wren_cpu_idx,
            gb_cpu_do_idx,
            gb_vram0_q_a_reg_idx,
            gb_vram0_q_b_reg_idx,
            gb_vram_addr_ppu_idx,
            gb_vram_do_idx,
            gb_vram_data_ppu_idx,
            gb_boot_rom: vec![0u8; 256],  // 256 bytes for DMG boot ROM
            gb_sel_boot_rom_idx,
            gb_boot_rom_addr_idx,
            gb_boot_do_idx,
            prev_lcd_clkena: 0,
            prev_lcd_vsync: 0,
            framebuffer: vec![0u8; 160 * 144],  // 160x144 Game Boy screen
            lcd_x: 0,
            lcd_y: 0,
            frame_count: 0,
        })
    }

    #[inline(always)]
    fn mask(width: usize) -> u64 {
        if width >= 64 { u64::MAX } else { (1u64 << width) - 1 }
    }

    fn expr_width(&self, expr: &ExprDef) -> usize {
        match expr {
            ExprDef::Signal { name, width } => {
                self.name_to_idx.get(name)
                    .and_then(|&idx| self.widths.get(idx).copied())
                    .unwrap_or(*width)
            }
            ExprDef::Literal { width, .. } => *width,
            ExprDef::UnaryOp { width, .. } => *width,
            ExprDef::BinaryOp { width, .. } => *width,
            ExprDef::Mux { width, .. } => *width,
            ExprDef::Slice { width, .. } => *width,
            ExprDef::Concat { width, .. } => *width,
            ExprDef::Resize { width, .. } => *width,
            ExprDef::MemRead { width, .. } => *width,
        }
    }

    /// Evaluate all combinational assignments (requires compilation)
    fn evaluate(&mut self) {
        let lib = self.compiled_lib.as_ref()
            .expect("IR Compiler: evaluate() called but code not compiled. Call compile() first.");
        unsafe {
            let func: libloading::Symbol<unsafe extern "C" fn(*mut u64, usize)> =
                lib.get(b"evaluate").expect("evaluate function not found");
            func(self.signals.as_mut_ptr(), self.signals.len());
        }
    }

    fn poke(&mut self, name: &str, value: u64) -> Result<(), String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        let mask = Self::mask(self.widths[idx]);
        self.signals[idx] = value & mask;
        Ok(())
    }

    fn peek(&self, name: &str) -> Result<u64, String> {
        let idx = *self.name_to_idx.get(name)
            .ok_or_else(|| format!("Unknown signal: {}", name))?;
        Ok(self.signals[idx])
    }

    /// Clock tick - sample registers on rising edges (requires compilation)
    fn tick(&mut self) {
        let lib = self.compiled_lib.as_ref()
            .expect("IR Compiler: tick() called but code not compiled. Call compile() first.");
        unsafe {
            type TickFn = unsafe extern "C" fn(*mut u64, usize, *mut u64, *mut u64);
            let func: libloading::Symbol<TickFn> =
                lib.get(b"tick").expect("tick function not found");
            func(
                self.signals.as_mut_ptr(),
                self.signals.len(),
                self.old_clocks.as_mut_ptr(),
                self.next_regs.as_mut_ptr(),
            );
        }
    }

    fn reset(&mut self) {
        for val in self.signals.iter_mut() {
            *val = 0;
        }
        for &(idx, reset_val) in &self.reset_values {
            self.signals[idx] = reset_val;
        }
    }

    fn signal_count(&self) -> usize {
        self.signals.len()
    }

    fn reg_count(&self) -> usize {
        self.seq_targets.len()
    }

    // ========================================================================
    // Code Generation
    // ========================================================================

    /// Generate inline mask constant (e.g., 0xFF for width 8)
    fn mask_const(width: usize) -> String {
        if width >= 64 {
            "0xFFFFFFFFFFFFFFFFu64".to_string()
        } else {
            format!("0x{:X}u64", (1u64 << width) - 1)
        }
    }

    /// Extract signal indices that an expression depends on
    fn expr_dependencies(&self, expr: &ExprDef) -> HashSet<usize> {
        let mut deps = HashSet::new();
        self.collect_expr_deps(expr, &mut deps);
        deps
    }

    fn collect_expr_deps(&self, expr: &ExprDef, deps: &mut HashSet<usize>) {
        match expr {
            ExprDef::Signal { name, .. } => {
                if let Some(&idx) = self.name_to_idx.get(name) {
                    deps.insert(idx);
                }
            }
            ExprDef::Literal { .. } => {}
            ExprDef::UnaryOp { operand, .. } => {
                self.collect_expr_deps(operand, deps);
            }
            ExprDef::BinaryOp { left, right, .. } => {
                self.collect_expr_deps(left, deps);
                self.collect_expr_deps(right, deps);
            }
            ExprDef::Mux { condition, when_true, when_false, .. } => {
                self.collect_expr_deps(condition, deps);
                self.collect_expr_deps(when_true, deps);
                self.collect_expr_deps(when_false, deps);
            }
            ExprDef::Slice { base, .. } => {
                self.collect_expr_deps(base, deps);
            }
            ExprDef::Concat { parts, .. } => {
                for part in parts {
                    self.collect_expr_deps(part, deps);
                }
            }
            ExprDef::Resize { expr, .. } => {
                self.collect_expr_deps(expr, deps);
            }
            ExprDef::MemRead { addr, .. } => {
                self.collect_expr_deps(addr, deps);
            }
        }
    }

    /// Group assignments into levels based on dependencies
    /// Each level contains assignments that can be computed in parallel
    fn compute_assignment_levels(&self) -> Vec<Vec<usize>> {
        let assigns = &self.ir.assigns;
        let n = assigns.len();

        // Map: target signal idx -> list of assignment indices (in order)
        // This handles cascading assignments where the same signal is assigned multiple times
        let mut target_to_assigns: HashMap<usize, Vec<usize>> = HashMap::new();
        for (i, assign) in assigns.iter().enumerate() {
            if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                target_to_assigns.entry(idx).or_insert_with(Vec::new).push(i);
            }
        }

        // Compute dependencies for each assignment (in terms of other assignment indices)
        // For each signal referenced in the expression, we depend on any assignment to that signal.
        // For multiple assignments to the same signal, prefer the most recent one before current_idx.
        // If none exists before, depend on the first assignment regardless of index.
        let mut assign_deps: Vec<HashSet<usize>> = Vec::with_capacity(n);
        for (current_idx, assign) in assigns.iter().enumerate() {
            let signal_deps = self.expr_dependencies(&assign.expr);
            let mut deps = HashSet::new();
            for sig_idx in signal_deps {
                if let Some(assign_indices) = target_to_assigns.get(&sig_idx) {
                    if assign_indices.is_empty() {
                        continue;
                    }

                    // First, try to find the most recent assignment BEFORE current_idx
                    let mut found_before = false;
                    for &prev_assign_idx in assign_indices.iter().rev() {
                        if prev_assign_idx < current_idx && prev_assign_idx != current_idx {
                            deps.insert(prev_assign_idx);
                            found_before = true;
                            break;  // Only depend on the most recent previous assignment
                        }
                    }

                    // If no assignment before current_idx, depend on the first assignment
                    // (which must come after current_idx in list order, but we still need
                    // to ensure it's evaluated first via topological sort)
                    if !found_before {
                        let first_assign_idx = assign_indices[0];
                        if first_assign_idx != current_idx {
                            deps.insert(first_assign_idx);
                        }
                    }
                }
            }
            assign_deps.push(deps);
        }

        // Assign levels (topological sort into levels)
        let mut levels: Vec<Vec<usize>> = Vec::new();
        let mut assigned_level: Vec<Option<usize>> = vec![None; n];

        loop {
            let mut made_progress = false;
            for i in 0..n {
                if assigned_level[i].is_some() {
                    continue;
                }
                // Check if all dependencies have been assigned
                let mut max_dep_level = None;
                let mut all_deps_ready = true;
                for &dep_idx in &assign_deps[i] {
                    if dep_idx == i {
                        // Self-dependency, ignore
                        continue;
                    }
                    match assigned_level[dep_idx] {
                        Some(lvl) => {
                            max_dep_level = Some(max_dep_level.map_or(lvl, |m: usize| m.max(lvl)));
                        }
                        None => {
                            all_deps_ready = false;
                            break;
                        }
                    }
                }
                if all_deps_ready {
                    let my_level = max_dep_level.map_or(0, |l| l + 1);
                    assigned_level[i] = Some(my_level);
                    while levels.len() <= my_level {
                        levels.push(Vec::new());
                    }
                    levels[my_level].push(i);
                    made_progress = true;
                }
            }
            if !made_progress {
                // Handle remaining (cycles or orphans) - put them at the end
                let last_level = levels.len();
                for i in 0..n {
                    if assigned_level[i].is_none() {
                        if levels.len() <= last_level {
                            levels.push(Vec::new());
                        }
                        levels[last_level].push(i);
                    }
                }
                break;
            }
            if assigned_level.iter().all(|l| l.is_some()) {
                break;
            }
        }

        levels
    }

    fn generate_code(&self) -> String {
        let mut code = String::new();

        code.push_str("//! Auto-generated circuit simulation code\n");
        code.push_str("//! Generated by RHDL IR Compiler (LTO optimized)\n\n");

        // Generate memory arrays if any
        for (idx, mem) in self.ir.memories.iter().enumerate() {
            code.push_str(&format!("static MEM_{}: &[u64] = &[\n", idx));
            for (i, &val) in mem.initial_data.iter().enumerate() {
                if i > 0 && i % 8 == 0 {
                    code.push_str("\n");
                }
                code.push_str(&format!("    {},", val));
            }
            if mem.initial_data.is_empty() {
                for i in 0..mem.depth.min(256) {
                    if i > 0 && i % 8 == 0 {
                        code.push_str("\n");
                    }
                    code.push_str("    0,");
                }
            }
            code.push_str("\n];\n\n");
        }

        // Generate evaluate function (inline for performance)
        // Use topologically sorted levels to ensure dependencies are evaluated before dependents
        code.push_str("/// Evaluate all combinational assignments (topologically sorted)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str("unsafe fn evaluate_inline(signals: &mut [u64]) {\n");

        let levels = self.compute_assignment_levels();
        for level in &levels {
            for &assign_idx in level {
                let assign = &self.ir.assigns[assign_idx];
                if let Some(&idx) = self.name_to_idx.get(&assign.target) {
                    let width = self.widths.get(idx).copied().unwrap_or(64);
                    let expr_code = self.expr_to_rust(&assign.expr);
                    code.push_str(&format!("    signals[{}] = ({}) & {};\n", idx, expr_code, Self::mask_const(width)));
                }
            }
        }

        code.push_str("}\n\n");

        // Generate extern "C" wrapper for evaluate (for external callers)
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn evaluate(signals: *mut u64, len: usize) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str("    evaluate_inline(signals);\n");
        code.push_str("}\n\n");

        // Generate tick function
        self.generate_tick_function(&mut code);

        // Generate Game Boy tick function (doesn't overwrite old_clocks)
        if self.gameboy_mode {
            self.generate_tick_gb_function(&mut code);
        }

        // Generate run_cpu_cycles function
        self.generate_run_cpu_cycles(&mut code);

        // Generate run_mos6502_cycles function (if in MOS6502 mode)
        if self.mos6502_mode {
            self.generate_run_mos6502_cycles(&mut code);
        }

        // Generate run_gb_cycles function (if in Game Boy mode)
        if self.gameboy_mode {
            self.generate_run_gb_cycles(&mut code);
        }

        code
    }

    fn expr_to_rust(&self, expr: &ExprDef) -> String {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                format!("(signals[{}] & {})", idx, Self::mask_const(*width))
            }
            ExprDef::Literal { value, width } => {
                // For literals, just compute the masked value directly
                let masked = (*value as u64) & Self::mask(*width);
                format!("{}u64", masked)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code = self.expr_to_rust(operand);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        format!("(if ({} & {}) == {} {{ 1u64 }} else {{ 0u64 }})",
                                operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("(if {} != 0 {{ 1u64 }} else {{ 0u64 }})", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u64 & 1)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust(left);
                let r = self.expr_to_rust(right);
                let m = Self::mask_const(*width);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & {})", l, r, m),
                    "-" => format!("({}.wrapping_sub({}) & {})", l, r, m),
                    "*" => format!("({}.wrapping_mul({}) & {})", l, r, m),
                    "/" => format!("(if {} != 0 {{ {} / {} }} else {{ 0u64 }})", r, l, r),
                    "%" => format!("(if {} != 0 {{ {} % {} }} else {{ 0u64 }})", r, l, r),
                    "<<" => format!("(({} << {}.min(63)) & {})", l, r, m),
                    ">>" => format!("({} >> {}.min(63))", l, r),
                    "==" => format!("(if {} == {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "!=" => format!("(if {} != {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<" => format!("(if {} < {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">" => format!("(if {} > {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    "<=" | "le" => format!("(if {} <= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    ">=" => format!("(if {} >= {} {{ 1u64 }} else {{ 0u64 }})", l, r),
                    _ => "0u64".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                let cond = self.expr_to_rust(condition);
                let t = self.expr_to_rust(when_true);
                let f = self.expr_to_rust(when_false);
                format!("(if {} != 0 {{ {} }} else {{ {} }} & {})", cond, t, f, Self::mask_const(*width))
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust(base);
                format!("(({} >> {}) & {})", base_code, low, Self::mask_const(*width))
            }
            ExprDef::Concat { parts, width } => {
                let mut result = String::from("((");
                let mut shift = 0usize;
                let mut first = true;
                for part in parts.iter().rev() {
                    let part_code = self.expr_to_rust(part);
                    let part_width = self.expr_width(part);
                    if !first {
                        result.push_str(" | ");
                    }
                    first = false;
                    if shift > 0 {
                        result.push_str(&format!("(({} & {}) << {})", part_code, Self::mask_const(part_width), shift));
                    } else {
                        result.push_str(&format!("({} & {})", part_code, Self::mask_const(part_width)));
                    }
                    shift += part_width;
                }
                result.push_str(&format!(") & {})", Self::mask_const(*width)));
                result
            }
            ExprDef::Resize { expr, width } => {
                let expr_code = self.expr_to_rust(expr);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust(addr);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & {})",
                        mem_idx, addr_code, Self::mask_const(*width))
            }
        }
    }

    /// Generate branchless Rust code for an expression (uses mux64 for conditionals)
    fn expr_to_rust_branchless(&self, expr: &ExprDef) -> String {
        match expr {
            ExprDef::Signal { name, width } => {
                let idx = self.name_to_idx.get(name).copied().unwrap_or(0);
                format!("(signals[{}] & {})", idx, Self::mask_const(*width))
            }
            ExprDef::Literal { value, width } => {
                let masked = (*value as u64) & Self::mask(*width);
                format!("{}u64", masked)
            }
            ExprDef::UnaryOp { op, operand, width } => {
                let operand_code = self.expr_to_rust_branchless(operand);
                match op.as_str() {
                    "~" | "not" => format!("((!{}) & {})", operand_code, Self::mask_const(*width)),
                    "&" | "reduce_and" => {
                        let op_width = self.expr_width(operand);
                        let m = Self::mask_const(op_width);
                        // Branchless reduce_and
                        format!("(((({} & {}) == {}) as u64))", operand_code, m, m)
                    }
                    "|" | "reduce_or" => format!("((({} != 0) as u64))", operand_code),
                    "^" | "reduce_xor" => format!("(({}).count_ones() as u64 & 1)", operand_code),
                    _ => operand_code,
                }
            }
            ExprDef::BinaryOp { op, left, right, width } => {
                let l = self.expr_to_rust_branchless(left);
                let r = self.expr_to_rust_branchless(right);
                let m = Self::mask_const(*width);
                match op.as_str() {
                    "&" => format!("({} & {})", l, r),
                    "|" => format!("({} | {})", l, r),
                    "^" => format!("({} ^ {})", l, r),
                    "+" => format!("({}.wrapping_add({}) & {})", l, r, m),
                    "-" => format!("({}.wrapping_sub({}) & {})", l, r, m),
                    "*" => format!("({}.wrapping_mul({}) & {})", l, r, m),
                    "/" => {
                        // Branchless division (avoid divide by zero)
                        format!("({{ let d = {}; if d != 0 {{ {} / d }} else {{ 0u64 }} }})", r, l)
                    }
                    "%" => {
                        format!("({{ let d = {}; if d != 0 {{ {} % d }} else {{ 0u64 }} }})", r, l)
                    }
                    "<<" => format!("(({} << {}.min(63)) & {})", l, r, m),
                    ">>" => format!("({} >> {}.min(63))", l, r),
                    // Branchless comparisons
                    "==" => format!("((({} == {}) as u64))", l, r),
                    "!=" => format!("((({} != {}) as u64))", l, r),
                    "<" => format!("((({} < {}) as u64))", l, r),
                    ">" => format!("((({} > {}) as u64))", l, r),
                    "<=" | "le" => format!("((({} <= {}) as u64))", l, r),
                    ">=" => format!("((({} >= {}) as u64))", l, r),
                    _ => "0u64".to_string(),
                }
            }
            ExprDef::Mux { condition, when_true, when_false, width } => {
                // Use branchless mux function
                let cond = self.expr_to_rust_branchless(condition);
                let t = self.expr_to_rust_branchless(when_true);
                let f = self.expr_to_rust_branchless(when_false);
                format!("(mux64({}, {}, {}) & {})", cond, t, f, Self::mask_const(*width))
            }
            ExprDef::Slice { base, low, width, .. } => {
                let base_code = self.expr_to_rust_branchless(base);
                format!("(({} >> {}) & {})", base_code, low, Self::mask_const(*width))
            }
            ExprDef::Concat { parts, width } => {
                let mut result = String::from("((");
                let mut shift = 0usize;
                let mut first = true;
                for part in parts.iter().rev() {
                    let part_code = self.expr_to_rust_branchless(part);
                    let part_width = self.expr_width(part);
                    if !first {
                        result.push_str(" | ");
                    }
                    first = false;
                    if shift > 0 {
                        result.push_str(&format!("(({} & {}) << {})", part_code, Self::mask_const(part_width), shift));
                    } else {
                        result.push_str(&format!("({} & {})", part_code, Self::mask_const(part_width)));
                    }
                    shift += part_width;
                }
                result.push_str(&format!(") & {})", Self::mask_const(*width)));
                result
            }
            ExprDef::Resize { expr, width } => {
                let expr_code = self.expr_to_rust_branchless(expr);
                format!("({} & {})", expr_code, Self::mask_const(*width))
            }
            ExprDef::MemRead { memory, addr, width } => {
                let mem_idx = self.memory_name_to_idx.get(memory).copied().unwrap_or(0);
                let addr_code = self.expr_to_rust_branchless(addr);
                format!("(MEM_{}.get({} as usize).copied().unwrap_or(0) & {})",
                        mem_idx, addr_code, Self::mask_const(*width))
            }
        }
    }

    fn generate_tick_function(&self, code: &mut String) {
        // Build clock domain info
        let mut clock_domains: std::collections::HashMap<usize, Vec<usize>> = std::collections::HashMap::new();
        let mut seq_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| self.name_to_idx.get(c).copied())
                .unwrap_or_else(|| *self.name_to_idx.get("clk_14m").unwrap_or(&0));

            for _ in &process.statements {
                clock_domains.entry(clock_idx).or_default().push(seq_idx);
                seq_idx += 1;
            }
        }

        // IMPORTANT: Use self.clock_indices for consistent ordering (HashMaps have non-deterministic order)
        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        code.push_str("/// Clock tick - sample registers on rising edges (inline for performance)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("unsafe fn tick_inline(signals: &mut [u64], old_clocks: &mut [u64; {}], next_regs: &mut [u64; {}]) {{\n", num_clocks, num_regs.max(1)));
        code.push_str("\n");

        // DON'T save old_clocks at start - they persist from last tick
        // This allows proper edge detection when user pokes clock before calling tick

        // Call evaluate (propagates clock to derived clocks)
        code.push_str("    evaluate_inline(signals);\n\n");

        // Sample all register inputs
        code.push_str("    // Sample register inputs\n");
        let mut reg_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let expr_code = self.expr_to_rust(&stmt.expr);
                let target_idx = self.seq_targets[reg_idx];
                let width = self.widths.get(target_idx).copied().unwrap_or(64);
                code.push_str(&format!("    next_regs[{}] = ({}) & {};\n", reg_idx, expr_code, Self::mask_const(width)));
                reg_idx += 1;
            }
        }
        code.push_str("\n");

        // Iterate for derived clock domains (2 iterations sufficient for Apple II)
        code.push_str("    // Iterate for derived clock domains\n");
        code.push_str("    for _ in 0..2 {\n");
        code.push_str("        let mut any_edge = false;\n\n");

        // Check for rising edges and update registers
        for (clock_list_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        if old_clocks[{}] == 0 && signals[{}] == 1 {{\n", clock_list_idx, clk_idx));
            code.push_str("            any_edge = true;\n");

            if let Some(reg_indices) = clock_domains.get(&clk_idx) {
                for &ri in reg_indices {
                    let target_idx = self.seq_targets[ri];
                    code.push_str(&format!("            signals[{}] = next_regs[{}];\n", target_idx, ri));
                }
            }

            // Don't update old_clocks[i] = 1 here - we'll update all clocks at the end
            code.push_str("        }\n");
        }

        code.push_str("\n        if !any_edge { break; }\n");
        code.push_str("        evaluate_inline(signals);\n");
        code.push_str("    }\n\n");

        // Update old_clocks to current values for next tick's edge detection
        for (i, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk_idx));
        }
        code.push_str("}\n\n");

        // Generate extern "C" wrapper for tick (for external callers)
        code.push_str("#[no_mangle]\n");
        code.push_str(&format!("pub unsafe extern \"C\" fn tick(signals: *mut u64, len: usize, old_clocks: *mut u64, next_regs: *mut u64) {{\n"));
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, len);\n");
        code.push_str(&format!("    let old_clocks: &mut [u64; {}] = &mut *(old_clocks as *mut [u64; {}]);\n", num_clocks, num_clocks));
        code.push_str(&format!("    let next_regs: &mut [u64; {}] = &mut *(next_regs as *mut [u64; {}]);\n", num_regs.max(1), num_regs.max(1)));
        code.push_str("    tick_inline(signals, old_clocks, next_regs);\n");
        code.push_str("}\n\n");
    }

    /// Generate tick_gb_inline - like tick_inline but doesn't overwrite old_clocks
    /// This allows the caller to save old_clocks before clock transitions
    fn generate_tick_gb_function(&self, code: &mut String) {
        // Build clock domain info
        let mut clock_domains: std::collections::HashMap<usize, Vec<usize>> = std::collections::HashMap::new();
        let mut seq_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            let clock_idx = process.clock.as_ref()
                .and_then(|c| self.name_to_idx.get(c).copied())
                .unwrap_or_else(|| *self.name_to_idx.get("clk_sys").unwrap_or(&0));

            for _ in &process.statements {
                clock_domains.entry(clock_idx).or_default().push(seq_idx);
                seq_idx += 1;
            }
        }

        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        code.push_str("/// Game Boy tick - sample registers on rising edges (old_clocks pre-saved by caller)\n");
        code.push_str("#[inline(always)]\n");
        code.push_str(&format!("unsafe fn tick_gb_inline(signals: &mut [u64], old_clocks: &mut [u64; {}], next_regs: &mut [u64; {}]) {{\n", num_clocks, num_regs.max(1)));
        code.push_str("\n");

        // NOTE: We do NOT save old_clocks here - the caller has already done it before the rising edge
        // Just call evaluate to propagate clock changes to derived clocks
        code.push_str("    evaluate_inline(signals);\n\n");

        // Sample all register inputs
        code.push_str("    // Sample register inputs\n");
        let mut reg_idx = 0;
        for process in &self.ir.processes {
            if !process.clocked {
                continue;
            }
            for stmt in &process.statements {
                let expr_code = self.expr_to_rust(&stmt.expr);
                let target_idx = self.seq_targets[reg_idx];
                let width = self.widths.get(target_idx).copied().unwrap_or(64);
                code.push_str(&format!("    next_regs[{}] = ({}) & {};\n", reg_idx, expr_code, Self::mask_const(width)));
                reg_idx += 1;
            }
        }
        code.push_str("\n");

        // Iterate for derived clock domains
        code.push_str("    // Iterate for derived clock domains\n");
        code.push_str("    for _ in 0..2 {\n");
        code.push_str("        let mut any_edge = false;\n\n");

        // Check for rising edges and update registers
        for (clock_list_idx, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        if old_clocks[{}] == 0 && signals[{}] == 1 {{\n", clock_list_idx, clk_idx));
            code.push_str("            any_edge = true;\n");

            if let Some(reg_indices) = clock_domains.get(&clk_idx) {
                for &ri in reg_indices {
                    let target_idx = self.seq_targets[ri];
                    code.push_str(&format!("            signals[{}] = next_regs[{}];\n", target_idx, ri));
                }
            }

            // Don't update old_clocks[i] = 1 here - we'll update all clocks at the end
            code.push_str("        }\n");
        }

        code.push_str("\n        if !any_edge { break; }\n");
        code.push_str("        evaluate_inline(signals);\n");
        code.push_str("    }\n\n");

        // Update old_clocks to current values for next tick's edge detection
        for (i, &clk_idx) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk_idx));
        }
        code.push_str("}\n\n");
    }

    fn generate_run_cpu_cycles(&self, code: &mut String) {
        let clk_idx = self.clk_idx;
        let k_idx = self.k_idx;
        let ram_addr_idx = self.ram_addr_idx;
        let ram_do_idx = self.ram_do_idx;
        let ram_we_idx = self.ram_we_idx;
        let d_idx = self.d_idx;
        let read_key_idx = self.read_key_idx;
        let speaker_idx = self.speaker_idx;

        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        code.push_str("/// Run N CPU cycles\n");
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
        code.push_str(") -> (bool, bool, u32) {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let ram = std::slice::from_raw_parts_mut(ram, ram_len);\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom, rom_len);\n");
        code.push_str(&format!("    let mut old_clocks = [0u64; {}];\n", num_clocks));
        code.push_str(&format!("    let mut next_regs = [0u64; {}];\n", num_regs.max(1)));
        code.push_str("    let mut text_dirty = false;\n");
        code.push_str("    let mut key_cleared = false;\n");
        code.push_str("    let mut key_is_ready = key_ready;\n");
        code.push_str("    let mut speaker_toggles: u32 = 0;\n");
        code.push_str("    let mut prev_speaker = *prev_speaker_ptr;\n\n");

        // Initialize old_clocks
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        // Run sub-cycles per CPU cycle (configurable for speed vs accuracy trade-off)
        // 14 = full accuracy, 7 = ~2x speed, 2 = ~7x speed
        code.push_str("    for _ in 0..n {\n");
        code.push_str(&format!("        for _ in 0..{} {{\n", self.sub_cycles));

        // Set keyboard input
        code.push_str(&format!("            signals[{}] = if key_is_ready {{ (key_data as u64) | 0x80 }} else {{ 0 }};\n\n", k_idx));

        // Falling edge
        code.push_str(&format!("            signals[{}] = 0;\n", clk_idx));
        code.push_str("            evaluate_inline(signals);\n\n");

        // Provide RAM/ROM data based on CPU address (not muxed ram_addr which may be video address)
        let cpu_addr_idx = self.cpu_addr_idx;
        code.push_str(&format!("            let addr = signals[{}] as usize;\n", cpu_addr_idx));
        code.push_str(&format!("            signals[{}] = if addr >= 0xD000 {{\n", ram_do_idx));
        code.push_str("                let rom_offset = addr.wrapping_sub(0xD000);\n");
        code.push_str("                if rom_offset < rom.len() { rom[rom_offset] as u64 } else { 0 }\n");
        code.push_str("            } else if addr >= 0xC000 { 0 }\n");
        code.push_str("            else if addr < ram.len() { ram[addr] as u64 }\n");
        code.push_str("            else { 0 };\n\n");

        // Rising edge
        code.push_str(&format!("            signals[{}] = 1;\n", clk_idx));
        code.push_str("            tick_inline(signals, &mut old_clocks, &mut next_regs);\n\n");

        // Handle RAM writes (use CPU address, not muxed ram_addr which may be video address)
        code.push_str(&format!("            if signals[{}] == 1 {{\n", ram_we_idx));
        code.push_str(&format!("                let wa = signals[{}] as usize;\n", cpu_addr_idx));
        code.push_str("                if wa < 0xC000 && wa < ram.len() {\n");
        code.push_str(&format!("                    ram[wa] = (signals[{}] & 0xFF) as u8;\n", d_idx));
        code.push_str("                    if wa >= 0x0400 && wa <= 0x07FF { text_dirty = true; }\n");
        code.push_str("                }\n");
        code.push_str("            }\n\n");

        // Check keyboard strobe
        code.push_str(&format!("            if signals[{}] == 1 {{ key_is_ready = false; key_cleared = true; }}\n\n", read_key_idx));

        // Check speaker toggle
        code.push_str(&format!("            let spk = signals[{}];\n", speaker_idx));
        code.push_str("            if spk != prev_speaker { speaker_toggles += 1; prev_speaker = spk; }\n");

        code.push_str("        }\n");
        code.push_str("    }\n\n");
        code.push_str("    *prev_speaker_ptr = prev_speaker;\n");
        code.push_str("    (text_dirty, key_cleared, speaker_toggles)\n");
        code.push_str("}\n");
    }

    fn generate_run_mos6502_cycles(&self, code: &mut String) {
        let addr_idx = self.mos6502_addr_idx;
        let data_in_idx = self.mos6502_data_in_idx;
        let data_out_idx = self.mos6502_data_out_idx;
        let rw_idx = self.mos6502_rw_idx;
        let clk_idx = self.mos6502_clk_idx;

        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        // Find clock list index for the MOS6502 clock
        let clk_list_idx = clock_indices.iter().position(|&ci| ci == clk_idx);

        code.push_str("\n/// Run N MOS6502 CPU cycles with internalized memory bridging\n");
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

        // Clock falling edge
        if let Some(idx) = clk_list_idx {
            code.push_str(&format!("        old_clocks[{}] = 1; // Previous state was high\n", idx));
        }
        code.push_str(&format!("        signals[{}] = 0;\n", clk_idx));
        code.push_str("        evaluate_inline(signals);\n\n");

        // Memory bridging (after evaluate, addr is valid)
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

        // Clock rising edge
        if let Some(idx) = clk_list_idx {
            code.push_str(&format!("        old_clocks[{}] = 0; // Previous state was low\n", idx));
        }
        code.push_str(&format!("        signals[{}] = 1;\n", clk_idx));
        code.push_str("        tick_inline(signals, &mut old_clocks, &mut next_regs);\n");
        code.push_str("    }\n\n");
        code.push_str("    // Write speaker toggles to out parameter\n");
        code.push_str("    if !speaker_toggles_out.is_null() {\n");
        code.push_str("        *speaker_toggles_out = speaker_toggles;\n");
        code.push_str("    }\n");
        code.push_str("    n\n");
        code.push_str("}\n");
    }

    fn generate_run_gb_cycles(&self, code: &mut String) {
        let gb_clk_sys_idx = self.gb_clk_sys_idx;
        // Note: CE is now generated by SpeedControl, not set manually
        let lcd_clkena_idx = self.lcd_clkena_idx;
        let lcd_data_gb_idx = self.lcd_data_gb_idx;
        let lcd_vsync_idx = self.lcd_vsync_idx;
        // Cart interface indices
        let gb_cart_rd_idx = self.gb_cart_rd_idx;
        let gb_cart_do_idx = self.gb_cart_do_idx;
        let gb_ext_bus_addr_idx = self.gb_ext_bus_addr_idx;
        let gb_ext_bus_a15_idx = self.gb_ext_bus_a15_idx;
        // VRAM interface indices
        let gb_vram_addr_cpu_idx = self.gb_vram_addr_cpu_idx;
        let gb_vram_wren_cpu_idx = self.gb_vram_wren_cpu_idx;
        let gb_cpu_do_idx = self.gb_cpu_do_idx;
        let gb_vram0_q_a_reg_idx = self.gb_vram0_q_a_reg_idx;
        let gb_vram0_q_b_reg_idx = self.gb_vram0_q_b_reg_idx;
        let gb_vram_addr_ppu_idx = self.gb_vram_addr_ppu_idx;
        // Boot ROM interface indices
        let gb_sel_boot_rom_idx = self.gb_sel_boot_rom_idx;
        let gb_boot_rom_addr_idx = self.gb_boot_rom_addr_idx;
        let gb_boot_do_idx = self.gb_boot_do_idx;

        let clock_indices: Vec<usize> = self.clock_indices.clone();
        let num_clocks = clock_indices.len().max(1);
        let num_regs = self.seq_targets.len();

        // Add LCD state struct to generated code
        code.push_str("\n/// LCD state for Game Boy simulation\n");
        code.push_str("#[repr(C)]\n");
        code.push_str("struct GbLcdState {\n");
        code.push_str("    x: u32,\n");
        code.push_str("    y: u32,\n");
        code.push_str("    prev_clkena: u32,\n");
        code.push_str("    prev_vsync: u32,\n");
        code.push_str("    frame_count: u64,\n");
        code.push_str("}\n\n");

        code.push_str("/// Result from running Game Boy cycles\n");
        code.push_str("#[repr(C)]\n");
        code.push_str("struct GbCycleResult {\n");
        code.push_str("    cycles_run: usize,\n");
        code.push_str("    frames_completed: u32,\n");
        code.push_str("}\n\n");

        code.push_str("/// Run N Game Boy cycles with LCD framebuffer capture and ROM access\n");
        code.push_str("#[no_mangle]\n");
        code.push_str("pub unsafe extern \"C\" fn run_gb_cycles(\n");
        code.push_str("    signals: *mut u64,\n");
        code.push_str("    signals_len: usize,\n");
        code.push_str("    n: usize,\n");
        code.push_str("    old_clocks_ptr: *mut u64,\n");
        code.push_str("    next_regs_ptr: *mut u64,\n");
        code.push_str("    framebuffer: *mut u8,\n");
        code.push_str("    lcd_state: *mut GbLcdState,\n");
        code.push_str("    rom_ptr: *const u8,\n");
        code.push_str("    rom_len: usize,\n");
        code.push_str("    vram_ptr: *mut u8,\n");
        code.push_str("    vram_len: usize,\n");
        code.push_str("    boot_rom_ptr: *const u8,\n");
        code.push_str("    boot_rom_len: usize,\n");
        code.push_str(") -> GbCycleResult {\n");
        code.push_str("    let signals = std::slice::from_raw_parts_mut(signals, signals_len);\n");
        code.push_str("    let framebuffer = std::slice::from_raw_parts_mut(framebuffer, 160 * 144);\n");
        code.push_str("    let rom = std::slice::from_raw_parts(rom_ptr, rom_len);\n");
        code.push_str("    let vram = std::slice::from_raw_parts_mut(vram_ptr, vram_len);\n");
        code.push_str("    let boot_rom = std::slice::from_raw_parts(boot_rom_ptr, boot_rom_len);\n");
        code.push_str(&format!("    let old_clocks: &mut [u64; {}] = &mut *(old_clocks_ptr as *mut [u64; {}]);\n", num_clocks, num_clocks));
        code.push_str(&format!("    let next_regs: &mut [u64; {}] = &mut *(next_regs_ptr as *mut [u64; {}]);\n", num_regs.max(1), num_regs.max(1)));
        code.push_str("    let state = &mut *lcd_state;\n");
        code.push_str("    let mut frames_completed: u32 = 0;\n\n");

        // Initialize old_clocks from signals
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("    old_clocks[{}] = signals[{}];\n", i, clk));
        }
        code.push_str("\n");

        code.push_str("    for _ in 0..n {\n");
        code.push_str("        // Run one cycle: toggle clk_sys, let SpeedControl generate CE\n");
        // Falling edge
        code.push_str(&format!("        signals[{}] = 0; // clk_sys = 0\n", gb_clk_sys_idx));
        code.push_str("        evaluate_inline(signals);\n");

        // Handle ROM read on falling edge (cart_rd may be asserted)
        code.push_str("        // Handle ROM read - check cart_rd and provide data\n");
        code.push_str(&format!("        if signals[{}] != 0 {{ // cart_rd\n", gb_cart_rd_idx));
        code.push_str(&format!("            let addr_lo = signals[{}] as usize; // ext_bus_addr (15 bits)\n", gb_ext_bus_addr_idx));
        code.push_str(&format!("            let addr_hi = signals[{}] as usize; // ext_bus_a15\n", gb_ext_bus_a15_idx));
        code.push_str("            let addr = (addr_hi << 15) | addr_lo;\n");
        code.push_str("            let data = if addr < rom_len { rom[addr] } else { 0xFF };\n");
        code.push_str(&format!("            signals[{}] = data as u64; // cart_do\n", gb_cart_do_idx));
        code.push_str("            evaluate_inline(signals); // Re-evaluate with ROM data\n");
        code.push_str("        }\n\n");

        // Handle boot ROM read (when sel_boot_rom is active)
        code.push_str("        // Boot ROM read - check sel_boot_rom and provide data\n");
        code.push_str(&format!("        if signals[{}] != 0 && boot_rom_len > 0 {{ // sel_boot_rom\n", gb_sel_boot_rom_idx));
        code.push_str(&format!("            let addr = (signals[{}] & 0xFF) as usize; // boot_rom_addr (8 bits)\n", gb_boot_rom_addr_idx));
        code.push_str("            let data = if addr < boot_rom_len { boot_rom[addr] } else { 0xFF };\n");
        code.push_str(&format!("            signals[{}] = data as u64; // boot_do\n", gb_boot_do_idx));
        code.push_str("            evaluate_inline(signals); // Re-evaluate with boot ROM data\n");
        code.push_str("        }\n\n");

        // Save old clock values BEFORE the rising edge (so we can detect the edge)
        for (i, &clk) in clock_indices.iter().enumerate() {
            code.push_str(&format!("        old_clocks[{}] = signals[{}];\n", i, clk));
        }
        // Rising edge - triggers sequential logic (including SpeedControl's clkdiv)
        code.push_str(&format!("        signals[{}] = 1; // clk_sys = 1\n", gb_clk_sys_idx));
        code.push_str("        evaluate_inline(signals);\n");

        // Handle ROM read on rising edge too
        code.push_str("        // Handle ROM read on rising edge\n");
        code.push_str(&format!("        if signals[{}] != 0 {{ // cart_rd\n", gb_cart_rd_idx));
        code.push_str(&format!("            let addr_lo = signals[{}] as usize;\n", gb_ext_bus_addr_idx));
        code.push_str(&format!("            let addr_hi = signals[{}] as usize;\n", gb_ext_bus_a15_idx));
        code.push_str("            let addr = (addr_hi << 15) | addr_lo;\n");
        code.push_str("            let data = if addr < rom_len { rom[addr] } else { 0xFF };\n");
        code.push_str(&format!("            signals[{}] = data as u64;\n", gb_cart_do_idx));
        code.push_str("            evaluate_inline(signals);\n");
        code.push_str("        }\n\n");

        // Handle boot ROM read on rising edge
        code.push_str("        // Boot ROM read on rising edge\n");
        code.push_str(&format!("        if signals[{}] != 0 && boot_rom_len > 0 {{ // sel_boot_rom\n", gb_sel_boot_rom_idx));
        code.push_str(&format!("            let addr = (signals[{}] & 0xFF) as usize;\n", gb_boot_rom_addr_idx));
        code.push_str("            let data = if addr < boot_rom_len { boot_rom[addr] } else { 0xFF };\n");
        code.push_str(&format!("            signals[{}] = data as u64;\n", gb_boot_do_idx));
        code.push_str("            evaluate_inline(signals);\n");
        code.push_str("        }\n\n");

        // VRAM handling BEFORE tick - check vram_wren_cpu while ce is still high
        code.push_str("        // VRAM write check (before tick, while ce may be high)\n");
        code.push_str(&format!("        if signals[{}] != 0 {{ // vram_wren_cpu\n", gb_vram_wren_cpu_idx));
        code.push_str(&format!("            let addr = (signals[{}] & 0x1FFF) as usize;\n", gb_vram_addr_cpu_idx));
        code.push_str(&format!("            let data = (signals[{}] & 0xFF) as u8;\n", gb_cpu_do_idx));
        code.push_str("            if addr < vram_len {\n");
        code.push_str("                vram[addr] = data;\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Inject VRAM data for reads (so PPU can see it)
        code.push_str("        // VRAM read injection (before tick)\n");
        code.push_str(&format!("        let va_cpu = (signals[{}] & 0x1FFF) as usize;\n", gb_vram_addr_cpu_idx));
        code.push_str(&format!("        let va_ppu = (signals[{}] & 0x1FFF) as usize;\n", gb_vram_addr_ppu_idx));
        code.push_str("        if va_cpu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[va_cpu] as u64;\n", gb_vram0_q_a_reg_idx));
        code.push_str("        }\n");
        code.push_str("        if va_ppu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[va_ppu] as u64;\n", gb_vram0_q_b_reg_idx));
        code.push_str("        }\n");
        code.push_str("        evaluate_inline(signals);\n\n");

        // Inline tick logic (sample registers and apply on rising edge)
        code.push_str("        tick_gb_inline(signals, old_clocks, next_regs);\n");
        // Evaluate again to propagate CE from SpeedControl to other components
        code.push_str("        evaluate_inline(signals);\n");

        // Handle ROM read after tick too
        code.push_str("        // Handle ROM read after tick\n");
        code.push_str(&format!("        if signals[{}] != 0 {{ // cart_rd\n", gb_cart_rd_idx));
        code.push_str(&format!("            let addr_lo = signals[{}] as usize;\n", gb_ext_bus_addr_idx));
        code.push_str(&format!("            let addr_hi = signals[{}] as usize;\n", gb_ext_bus_a15_idx));
        code.push_str("            let addr = (addr_hi << 15) | addr_lo;\n");
        code.push_str("            let data = if addr < rom_len { rom[addr] } else { 0xFF };\n");
        code.push_str(&format!("            signals[{}] = data as u64;\n", gb_cart_do_idx));
        code.push_str("            evaluate_inline(signals);\n");
        code.push_str("        }\n\n");

        // VRAM handling - inject read data into DPRAM register outputs
        // This is done after tick so the new values are available for next cycle's behavior
        code.push_str("        // VRAM handling - inject into DPRAM register outputs\n");
        code.push_str(&format!("        let vram_addr_cpu = (signals[{}] & 0x1FFF) as usize; // 13-bit address\n", gb_vram_addr_cpu_idx));
        code.push_str(&format!("        let vram_addr_ppu = (signals[{}] & 0x1FFF) as usize; // 13-bit address\n", gb_vram_addr_ppu_idx));
        code.push_str("        // CPU VRAM write\n");
        code.push_str(&format!("        if signals[{}] != 0 {{ // vram_wren_cpu\n", gb_vram_wren_cpu_idx));
        code.push_str(&format!("            let data = (signals[{}] & 0xFF) as u8;\n", gb_cpu_do_idx));
        code.push_str("            if vram_addr_cpu < vram_len {\n");
        code.push_str("                vram[vram_addr_cpu] = data;\n");
        code.push_str("            }\n");
        code.push_str("        }\n");
        code.push_str("        // Inject VRAM read data into DPRAM register outputs\n");
        code.push_str("        // q_a_reg: CPU side (port A)\n");
        code.push_str("        if vram_addr_cpu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[vram_addr_cpu] as u64;\n", gb_vram0_q_a_reg_idx));
        code.push_str("        }\n");
        code.push_str("        // q_b_reg: PPU side (port B)\n");
        code.push_str("        if vram_addr_ppu < vram_len {\n");
        code.push_str(&format!("            signals[{}] = vram[vram_addr_ppu] as u64;\n", gb_vram0_q_b_reg_idx));
        code.push_str("        }\n");
        code.push_str("        evaluate_inline(signals); // Propagate VRAM data through assignments\n\n");

        // LCD pixel capture logic
        code.push_str("        // LCD pixel capture\n");
        code.push_str(&format!("        let clkena = signals[{}];\n", lcd_clkena_idx));
        code.push_str(&format!("        let vsync = signals[{}];\n", lcd_vsync_idx));
        code.push_str("\n");

        // Detect vsync rising edge (new frame)
        code.push_str("        // Detect vsync rising edge (new frame)\n");
        code.push_str("        if vsync == 1 && state.prev_vsync == 0 {\n");
        code.push_str("            state.x = 0;\n");
        code.push_str("            state.y = 0;\n");
        code.push_str("            state.frame_count += 1;\n");
        code.push_str("            frames_completed += 1;\n");
        code.push_str("        }\n\n");

        // Detect lcd_clkena rising edge (pixel output)
        // We track lines by pixel count: every 160 pixels is a new line
        code.push_str("        // Detect lcd_clkena rising edge (pixel output)\n");
        code.push_str("        if clkena == 1 && state.prev_clkena == 0 {\n");
        code.push_str(&format!("            let pixel = (signals[{}] & 0x3) as u8;\n", lcd_data_gb_idx));
        code.push_str("            if state.x < 160 && state.y < 144 {\n");
        code.push_str("                let idx = (state.y as usize) * 160 + (state.x as usize);\n");
        code.push_str("                framebuffer[idx] = pixel;\n");
        code.push_str("            }\n");
        code.push_str("            state.x += 1;\n");
        code.push_str("            // New line when x reaches 160\n");
        code.push_str("            if state.x >= 160 {\n");
        code.push_str("                state.x = 0;\n");
        code.push_str("                state.y += 1;\n");
        code.push_str("            }\n");
        code.push_str("        }\n\n");

        // Save previous values
        code.push_str("        state.prev_clkena = clkena as u32;\n");
        code.push_str("        state.prev_vsync = vsync as u32;\n");
        // CE is now controlled by SpeedControl, not manually
        code.push_str("    }\n\n");

        code.push_str("    GbCycleResult { cycles_run: n, frames_completed }\n");
        code.push_str("}\n");
    }

    fn compile(&mut self) -> Result<bool, String> {
        let code = self.generate_code();

        // Compute hash for caching
        let code_hash = {
            let mut hash: u64 = 0xcbf29ce484222325;
            for byte in code.bytes() {
                hash ^= byte as u64;
                hash = hash.wrapping_mul(0x100000001b3);
            }
            hash
        };

        // Cache paths
        let cache_dir = std::env::temp_dir().join("rhdl_cache");
        let _ = fs::create_dir_all(&cache_dir);

        let lib_ext = if cfg!(target_os = "macos") {
            "dylib"
        } else if cfg!(target_os = "windows") {
            "dll"
        } else {
            "so"
        };
        let lib_name = format!("rhdl_ir_{:016x}.{}", code_hash, lib_ext);
        let lib_path = cache_dir.join(&lib_name);
        let src_path = cache_dir.join(format!("rhdl_ir_{:016x}.rs", code_hash));

        // Check cache
        if lib_path.exists() {
            unsafe {
                let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
                self.compiled_lib = Some(lib);
            }
            self.compiled = true;
            return Ok(true);
        }

        // Write source and compile
        fs::write(&src_path, &code).map_err(|e| e.to_string())?;

        let output = Command::new("rustc")
            .args(&[
                "--crate-type=cdylib",
                "-C", "opt-level=3",
                "-C", "target-cpu=native",
                "-C", "panic=abort",
                "-C", "lto=thin",
                "-C", "codegen-units=1",
                "-A", "warnings",
                "-o",
                lib_path.to_str().unwrap(),
                src_path.to_str().unwrap(),
            ])
            .output()
            .map_err(|e| e.to_string())?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("Compilation failed: {}", stderr));
        }

        // Load compiled library
        unsafe {
            let lib = libloading::Library::new(&lib_path).map_err(|e| e.to_string())?;
            self.compiled_lib = Some(lib);
        }

        self.compiled = true;
        Ok(true)
    }

    fn run_cpu_cycles(&mut self, n: usize, key_data: u8, key_ready: bool) -> BatchResult {
        let lib = self.compiled_lib.as_ref()
            .expect("IR Compiler: run_cpu_cycles() called but code not compiled. Call compile() first.");
        unsafe {
            #[allow(improper_ctypes_definitions)]
            type RunCpuCyclesFn = unsafe extern "C" fn(
                *mut u64, usize, *mut u8, usize, *const u8, usize, usize, u8, bool, *mut u64
            ) -> (bool, bool, u32);
            let func: libloading::Symbol<RunCpuCyclesFn> =
                lib.get(b"run_cpu_cycles").expect("run_cpu_cycles not found");
            let (text_dirty, key_cleared, speaker_toggles) = func(
                self.signals.as_mut_ptr(),
                self.signals.len(),
                self.ram.as_mut_ptr(),
                self.ram.len(),
                self.rom.as_ptr(),
                self.rom.len(),
                n,
                key_data,
                key_ready,
                &mut self.prev_speaker,
            );
            BatchResult { cycles_run: n, text_dirty, key_cleared, speaker_toggles }
        }
    }

    fn load_rom(&mut self, data: &[u8]) {
        if self.gameboy_mode {
            // Load into Game Boy ROM (up to 1MB)
            let len = data.len().min(self.gb_rom.len());
            self.gb_rom[..len].copy_from_slice(&data[..len]);
        } else {
            // Original ROM for other modes
            let len = data.len().min(self.rom.len());
            self.rom[..len].copy_from_slice(&data[..len]);
        }
    }

    /// Load Game Boy boot ROM (256 bytes for DMG)
    fn load_boot_rom(&mut self, data: &[u8]) {
        let len = data.len().min(self.gb_boot_rom.len());
        self.gb_boot_rom[..len].copy_from_slice(&data[..len]);
    }

    fn load_ram(&mut self, data: &[u8], offset: usize) {
        let end = (offset + data.len()).min(self.ram.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.ram[offset..end].copy_from_slice(&data[..len]);
        }
    }

    // ========================================================================
    // MOS6502 CPU-only mode methods
    // ========================================================================

    /// Check if this simulator is in MOS6502 CPU-only mode
    fn is_mos6502_mode(&self) -> bool {
        self.mos6502_mode
    }

    /// Load memory for MOS6502 mode
    /// If rom is true, memory is marked as ROM (writes blocked)
    fn load_mos6502_memory(&mut self, data: &[u8], offset: usize, rom: bool) {
        let end = (offset + data.len()).min(self.mos6502_memory.len());
        let len = end.saturating_sub(offset);
        if len > 0 {
            self.mos6502_memory[offset..end].copy_from_slice(&data[..len]);
            if rom {
                for i in offset..end {
                    self.mos6502_rom_mask[i] = true;
                }
            }
        }
    }

    /// Set reset vector directly (bypasses ROM protection)
    fn set_mos6502_reset_vector(&mut self, addr: u16) {
        self.mos6502_memory[0xFFFC] = (addr & 0xFF) as u8;
        self.mos6502_memory[0xFFFD] = ((addr >> 8) & 0xFF) as u8;
    }

    /// Run N CPU cycles with internalized memory bridging for MOS6502 (requires compilation)
    /// Returns the number of cycles actually run
    ///
    /// Timing matches the JIT and Ruby fallback (IRSimulatorRunner::clock_tick):
    /// 1. Clock falling edge - combinational logic updates (addr becomes valid)
    /// 2. Sample address and do memory bridging
    /// 3. Clock rising edge - registers capture values
    fn run_mos6502_cycles(&mut self, n: usize) -> usize {
        if !self.mos6502_mode {
            return 0;
        }

        let lib = self.compiled_lib.as_ref()
            .expect("IR Compiler: run_mos6502_cycles() called but code not compiled. Call compile() first.");
        unsafe {
            type RunMos6502CyclesFn = unsafe extern "C" fn(
                *mut u64, usize, *mut u8, *const bool, usize, *mut u32
            ) -> usize;
            let func: libloading::Symbol<RunMos6502CyclesFn> = lib.get(b"run_mos6502_cycles")
                .expect("run_mos6502_cycles function not found in compiled library");
            let mut speaker_toggles: u32 = 0;
            let result = func(
                self.signals.as_mut_ptr(),
                self.signals.len(),
                self.mos6502_memory.as_mut_ptr(),
                self.mos6502_rom_mask.as_ptr(),
                n,
                &mut speaker_toggles,
            );
            self.mos6502_speaker_toggles += speaker_toggles;
            result
        }
    }

    /// Read from MOS6502 memory
    fn read_mos6502_memory(&self, addr: usize) -> u8 {
        if addr < self.mos6502_memory.len() {
            self.mos6502_memory[addr]
        } else {
            0
        }
    }

    /// Write to MOS6502 memory (respects ROM protection)
    fn write_mos6502_memory(&mut self, addr: usize, data: u8) {
        if addr < self.mos6502_memory.len() && !self.mos6502_rom_mask[addr] {
            self.mos6502_memory[addr] = data;
        }
    }

    /// Get MOS6502 speaker toggle count (for audio generation)
    fn mos6502_speaker_toggles(&self) -> u32 {
        self.mos6502_speaker_toggles
    }

    /// Reset MOS6502 speaker toggle count (call after syncing to audio system)
    fn reset_mos6502_speaker_toggles(&mut self) {
        self.mos6502_speaker_toggles = 0;
    }

    // ========================================================================
    // Game Boy LCD Framebuffer Capture
    // ========================================================================

    /// Check if this simulator is in Game Boy mode
    fn is_gameboy_mode(&self) -> bool {
        self.gameboy_mode
    }

    /// Run N Game Boy cycles with LCD framebuffer capture (requires compilation)
    /// Captures pixels when lcd_clkena rises
    fn run_gb_cycles(&mut self, n: usize) -> GbCycleResult {
        if !self.gameboy_mode {
            return GbCycleResult { cycles_run: 0, frames_completed: 0 };
        }

        let lib = self.compiled_lib.as_ref()
            .expect("IR Compiler: run_gb_cycles() called but code not compiled. Call compile() first.");

        unsafe {
            type RunGbCyclesFn = unsafe extern "C" fn(
                signals: *mut u64,
                signals_len: usize,
                n: usize,
                old_clocks: *mut u64,
                next_regs: *mut u64,
                framebuffer: *mut u8,
                lcd_state: *mut GbLcdState,
                rom_ptr: *const u8,
                rom_len: usize,
                vram_ptr: *mut u8,
                vram_len: usize,
                boot_rom_ptr: *const u8,
                boot_rom_len: usize,
            ) -> GbCycleResult;

            let func: libloading::Symbol<RunGbCyclesFn> = lib.get(b"run_gb_cycles")
                .expect("run_gb_cycles function not found in compiled library");

            let mut lcd_state = GbLcdState {
                x: self.lcd_x as u32,
                y: self.lcd_y as u32,
                prev_clkena: self.prev_lcd_clkena as u32,
                prev_vsync: self.prev_lcd_vsync as u32,
                frame_count: self.frame_count,
            };

            let result = func(
                self.signals.as_mut_ptr(),
                self.signals.len(),
                n,
                self.old_clocks.as_mut_ptr(),
                self.next_regs.as_mut_ptr(),
                self.framebuffer.as_mut_ptr(),
                &mut lcd_state,
                self.gb_rom.as_ptr(),
                self.gb_rom.len(),
                self.gb_vram.as_mut_ptr(),
                self.gb_vram.len(),
                self.gb_boot_rom.as_ptr(),
                self.gb_boot_rom.len(),
            );

            // Update state from result
            self.lcd_x = lcd_state.x as usize;
            self.lcd_y = lcd_state.y as usize;
            self.prev_lcd_clkena = lcd_state.prev_clkena as u64;
            self.prev_lcd_vsync = lcd_state.prev_vsync as u64;
            self.frame_count = lcd_state.frame_count;

            result
        }
    }

    /// Read the framebuffer (160x144 2-bit pixels)
    fn read_framebuffer(&self) -> &[u8] {
        &self.framebuffer
    }

    /// Get current frame count
    fn gb_frame_count(&self) -> u64 {
        self.frame_count
    }

    /// Reset LCD state
    fn reset_lcd_state(&mut self) {
        self.lcd_x = 0;
        self.lcd_y = 0;
        self.prev_lcd_clkena = 0;
        self.prev_lcd_vsync = 0;
        self.frame_count = 0;
        self.framebuffer.fill(0);
    }
}

/// LCD state for Game Boy simulation
#[repr(C)]
struct GbLcdState {
    x: u32,
    y: u32,
    prev_clkena: u32,
    prev_vsync: u32,
    frame_count: u64,
}

/// Result from running Game Boy cycles
#[repr(C)]
#[derive(Clone, Copy)]
struct GbCycleResult {
    cycles_run: usize,
    frames_completed: u32,
}

struct BatchResult {
    text_dirty: bool,
    key_cleared: bool,
    cycles_run: usize,
    speaker_toggles: u32,
}

// ============================================================================
// Ruby Bindings
// ============================================================================

fn ruby_to_u64(value: Value) -> Result<u64, Error> {
    if let Ok(i) = <i64 as TryConvert>::try_convert(value) {
        return Ok(i as u64);
    }
    let ruby = unsafe { Ruby::get_unchecked() };
    let str_val: String = value.funcall("to_s", (16i32,))?;
    u64::from_str_radix(&str_val, 16)
        .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid integer: {}", e)))
}

fn u64_to_ruby(ruby: &Ruby, value: u64) -> Value {
    if value <= i64::MAX as u64 {
        ruby.into_value(value as i64)
    } else {
        let hex_str = format!("{:x}", value);
        ruby.eval(&format!("0x{}", hex_str)).unwrap_or_else(|_| ruby.into_value(0i64))
    }
}

#[magnus::wrap(class = "RHDL::Codegen::IR::IrCompiler")]
struct RubyIrCompiler {
    sim: RefCell<IrSimulator>,
}

impl RubyIrCompiler {
    fn new(json: String, sub_cycles: Option<i64>) -> Result<Self, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        // Default to 14 sub-cycles for full accuracy
        let cycles = sub_cycles.unwrap_or(14) as usize;
        let sim = IrSimulator::new(&json, cycles)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(Self { sim: RefCell::new(sim) })
    }

    fn compile(&self) -> Result<bool, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        self.sim.borrow_mut().compile()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn is_compiled(&self) -> bool {
        self.sim.borrow().compiled
    }

    fn generated_code(&self) -> String {
        self.sim.borrow().generate_code()
    }

    fn poke(&self, name: String, value: Value) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let v = ruby_to_u64(value)?;
        self.sim.borrow_mut().poke(&name, v)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))
    }

    fn peek(&self, name: String) -> Result<Value, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let val = self.sim.borrow().peek(&name)
            .map_err(|e| Error::new(ruby.exception_runtime_error(), e))?;
        Ok(u64_to_ruby(&ruby, val))
    }

    fn evaluate(&self) {
        self.sim.borrow_mut().evaluate();
    }

    fn tick(&self) {
        self.sim.borrow_mut().tick();
    }

    fn reset(&self) {
        self.sim.borrow_mut().reset();
    }

    fn signal_count(&self) -> usize {
        self.sim.borrow().signal_count()
    }

    fn reg_count(&self) -> usize {
        self.sim.borrow().reg_count()
    }

    fn input_names(&self) -> Vec<String> {
        self.sim.borrow().input_names.clone()
    }

    fn output_names(&self) -> Vec<String> {
        self.sim.borrow().output_names.clone()
    }

    fn load_rom(&self, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid ROM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_rom(&bytes);
        Ok(())
    }

    fn load_ram(&self, data: RArray, offset: usize) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid RAM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_ram(&bytes, offset);
        Ok(())
    }

    fn load_boot_rom(&self, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid boot ROM data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_boot_rom(&bytes);
        Ok(())
    }

    fn run_cpu_cycles(&self, n: usize, key_data: i64, key_ready: bool) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let result = self.sim.borrow_mut().run_cpu_cycles(n, key_data as u8, key_ready);

        let hash = ruby.hash_new();
        hash.aset(ruby.sym_new("text_dirty"), result.text_dirty)?;
        hash.aset(ruby.sym_new("key_cleared"), result.key_cleared)?;
        hash.aset(ruby.sym_new("cycles_run"), result.cycles_run as i64)?;
        hash.aset(ruby.sym_new("speaker_toggles"), result.speaker_toggles as i64)?;
        Ok(hash)
    }

    fn read_ram(&self, start: usize, length: usize) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let end = (start + length).min(sim.ram.len());
        let data: Vec<i64> = sim.ram[start..end].iter().map(|&b| b as i64).collect();
        Ok(ruby.ary_from_vec(data))
    }

    fn write_ram(&self, start: usize, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        let mut sim = self.sim.borrow_mut();
        let end = (start + bytes.len()).min(sim.ram.len());
        let len = end - start;
        sim.ram[start..end].copy_from_slice(&bytes[..len]);
        Ok(())
    }

    fn stats(&self) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let hash = ruby.hash_new();
        let sim = self.sim.borrow();

        hash.aset(ruby.sym_new("signal_count"), sim.signal_count() as i64)?;
        hash.aset(ruby.sym_new("reg_count"), sim.reg_count() as i64)?;
        hash.aset(ruby.sym_new("input_count"), sim.input_names.len() as i64)?;
        hash.aset(ruby.sym_new("output_count"), sim.output_names.len() as i64)?;
        hash.aset(ruby.sym_new("assign_count"), sim.ir.assigns.len() as i64)?;
        hash.aset(ruby.sym_new("process_count"), sim.ir.processes.len() as i64)?;
        hash.aset(ruby.sym_new("compiled"), sim.compiled)?;

        Ok(hash)
    }

    fn native(&self) -> bool {
        true
    }

    // MOS6502 CPU-only mode methods

    fn is_mos6502_mode(&self) -> bool {
        self.sim.borrow().is_mos6502_mode()
    }

    fn load_mos6502_memory(&self, data: RArray, offset: usize, rom: bool) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid memory data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        self.sim.borrow_mut().load_mos6502_memory(&bytes, offset, rom);
        Ok(())
    }

    fn set_mos6502_reset_vector(&self, addr: i64) -> Result<(), Error> {
        self.sim.borrow_mut().set_mos6502_reset_vector(addr as u16);
        Ok(())
    }

    fn run_mos6502_cycles(&self, n: usize) -> usize {
        self.sim.borrow_mut().run_mos6502_cycles(n)
    }

    fn read_mos6502_memory(&self, addr: usize) -> u8 {
        self.sim.borrow().read_mos6502_memory(addr)
    }

    fn write_mos6502_memory(&self, addr: usize, data: i64) {
        self.sim.borrow_mut().write_mos6502_memory(addr, data as u8);
    }

    fn mos6502_speaker_toggles(&self) -> u32 {
        self.sim.borrow().mos6502_speaker_toggles()
    }

    fn reset_mos6502_speaker_toggles(&self) {
        self.sim.borrow_mut().reset_mos6502_speaker_toggles();
    }

    // Game Boy LCD framebuffer methods

    fn is_gameboy_mode(&self) -> bool {
        self.sim.borrow().is_gameboy_mode()
    }

    fn run_gb_cycles(&self, n: usize) -> Result<RHash, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let result = self.sim.borrow_mut().run_gb_cycles(n);

        let hash = ruby.hash_new();
        hash.aset(ruby.sym_new("cycles_run"), result.cycles_run as i64)?;
        hash.aset(ruby.sym_new("frames_completed"), result.frames_completed as i64)?;
        Ok(hash)
    }

    fn read_framebuffer(&self) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let fb = sim.read_framebuffer();
        let data: Vec<i64> = fb.iter().map(|&b| b as i64).collect();
        Ok(ruby.ary_from_vec(data))
    }

    fn gb_frame_count(&self) -> u64 {
        self.sim.borrow().gb_frame_count()
    }

    fn reset_lcd_state(&self) {
        self.sim.borrow_mut().reset_lcd_state();
    }

    fn read_vram(&self, start: usize, length: usize) -> Result<RArray, Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let sim = self.sim.borrow();
        let end = (start + length).min(sim.gb_vram.len());
        let data: Vec<i64> = sim.gb_vram[start..end].iter().map(|&b| b as i64).collect();
        Ok(ruby.ary_from_vec(data))
    }

    fn write_vram(&self, start: usize, data: RArray) -> Result<(), Error> {
        let ruby = unsafe { Ruby::get_unchecked() };
        let bytes: Vec<u8> = data.to_vec::<i64>()
            .map_err(|e| Error::new(ruby.exception_runtime_error(), format!("Invalid data: {}", e)))?
            .into_iter()
            .map(|v| v as u8)
            .collect();
        let mut sim = self.sim.borrow_mut();
        let end = (start + bytes.len()).min(sim.gb_vram.len());
        let len = end - start;
        sim.gb_vram[start..end].copy_from_slice(&bytes[..len]);
        Ok(())
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let rhdl = ruby.define_module("RHDL")?;
    let codegen = rhdl.define_module("Codegen")?;
    let ir = codegen.define_module("IR")?;

    let class = ir.define_class("IrCompiler", ruby.class_object())?;

    class.define_singleton_method("new", magnus::function!(RubyIrCompiler::new, 2))?;
    class.define_method("compile", method!(RubyIrCompiler::compile, 0))?;
    class.define_method("compiled?", method!(RubyIrCompiler::is_compiled, 0))?;
    class.define_method("generated_code", method!(RubyIrCompiler::generated_code, 0))?;
    class.define_method("poke", method!(RubyIrCompiler::poke, 2))?;
    class.define_method("peek", method!(RubyIrCompiler::peek, 1))?;
    class.define_method("evaluate", method!(RubyIrCompiler::evaluate, 0))?;
    class.define_method("tick", method!(RubyIrCompiler::tick, 0))?;
    class.define_method("reset", method!(RubyIrCompiler::reset, 0))?;
    class.define_method("signal_count", method!(RubyIrCompiler::signal_count, 0))?;
    class.define_method("reg_count", method!(RubyIrCompiler::reg_count, 0))?;
    class.define_method("input_names", method!(RubyIrCompiler::input_names, 0))?;
    class.define_method("output_names", method!(RubyIrCompiler::output_names, 0))?;
    class.define_method("load_rom", method!(RubyIrCompiler::load_rom, 1))?;
    class.define_method("load_ram", method!(RubyIrCompiler::load_ram, 2))?;
    class.define_method("load_boot_rom", method!(RubyIrCompiler::load_boot_rom, 1))?;
    class.define_method("run_cpu_cycles", method!(RubyIrCompiler::run_cpu_cycles, 3))?;
    class.define_method("read_ram", method!(RubyIrCompiler::read_ram, 2))?;
    class.define_method("write_ram", method!(RubyIrCompiler::write_ram, 2))?;
    class.define_method("stats", method!(RubyIrCompiler::stats, 0))?;
    class.define_method("native?", method!(RubyIrCompiler::native, 0))?;

    // MOS6502 CPU-only mode methods
    class.define_method("mos6502_mode?", method!(RubyIrCompiler::is_mos6502_mode, 0))?;
    class.define_method("load_mos6502_memory", method!(RubyIrCompiler::load_mos6502_memory, 3))?;
    class.define_method("set_mos6502_reset_vector", method!(RubyIrCompiler::set_mos6502_reset_vector, 1))?;
    class.define_method("run_mos6502_cycles", method!(RubyIrCompiler::run_mos6502_cycles, 1))?;
    class.define_method("read_mos6502_memory", method!(RubyIrCompiler::read_mos6502_memory, 1))?;
    class.define_method("write_mos6502_memory", method!(RubyIrCompiler::write_mos6502_memory, 2))?;
    class.define_method("mos6502_speaker_toggles", method!(RubyIrCompiler::mos6502_speaker_toggles, 0))?;
    class.define_method("reset_mos6502_speaker_toggles", method!(RubyIrCompiler::reset_mos6502_speaker_toggles, 0))?;

    // Game Boy LCD framebuffer methods
    class.define_method("gameboy_mode?", method!(RubyIrCompiler::is_gameboy_mode, 0))?;
    class.define_method("run_gb_cycles", method!(RubyIrCompiler::run_gb_cycles, 1))?;
    class.define_method("read_framebuffer", method!(RubyIrCompiler::read_framebuffer, 0))?;
    class.define_method("gb_frame_count", method!(RubyIrCompiler::gb_frame_count, 0))?;
    class.define_method("reset_lcd_state", method!(RubyIrCompiler::reset_lcd_state, 0))?;
    class.define_method("read_vram", method!(RubyIrCompiler::read_vram, 2))?;
    class.define_method("write_vram", method!(RubyIrCompiler::write_vram, 2))?;

    Ok(())
}
