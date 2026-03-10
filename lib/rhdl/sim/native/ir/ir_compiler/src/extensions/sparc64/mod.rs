//! SPARC64 `s1_top` native runner extension for the IR compiler.
//!
//! This bridges the imported `s1_top` Wishbone master interface to sparse
//! flash/DRAM backing stores using a deterministic one-cycle ACK response.

use std::collections::HashMap;

use crate::core::CoreSimulator;
use serde::Serialize;

const FLASH_BOOT_BASE: u64 = 0x0000_0003_FFFF_C000;
const PHYSICAL_ADDR_MASK: u64 = (1u64 << 59) - 1;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Sparc64WishboneRequest {
    pub write: bool,
    pub addr: u64,
    pub data: u64,
    pub sel: u8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Sparc64WishboneTraceEvent {
    pub cycle: u64,
    pub op: &'static str,
    pub addr: u64,
    pub sel: u8,
    pub write_data: Option<u64>,
    pub read_data: Option<u64>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct Sparc64Fault {
    pub cycle: u64,
    pub op: &'static str,
    pub addr: u64,
    pub sel: u8,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct PendingResponse {
    request: Sparc64WishboneRequest,
    read_data: u64,
    unmapped: bool,
}

pub struct Sparc64Extension {
    pub flash: HashMap<u64, u8>,
    pub memory: HashMap<u64, u8>,
    pub trace: Vec<Sparc64WishboneTraceEvent>,
    pub unmapped_accesses: Vec<Sparc64Fault>,

    clk_idx: usize,
    rst_idx: usize,
    eth_irq_idx: usize,
    ack_idx: usize,
    data_i_idx: usize,
    cycle_o_idx: usize,
    strobe_o_idx: usize,
    we_o_idx: usize,
    addr_o_idx: usize,
    data_o_idx: usize,
    sel_o_idx: usize,

    pending_response: Option<PendingResponse>,
    reset_cycles_remaining: usize,
    cycle_count: u64,
}

impl Sparc64Extension {
    pub fn new(core: &CoreSimulator) -> Self {
        let n = &core.name_to_idx;

        Self {
            flash: HashMap::new(),
            memory: HashMap::new(),
            trace: Vec::new(),
            unmapped_accesses: Vec::new(),

            clk_idx: idx(n, "sys_clock_i"),
            rst_idx: idx(n, "sys_reset_i"),
            eth_irq_idx: idx(n, "eth_irq_i"),
            ack_idx: idx(n, "wbm_ack_i"),
            data_i_idx: idx(n, "wbm_data_i"),
            cycle_o_idx: idx(n, "wbm_cycle_o"),
            strobe_o_idx: idx(n, "wbm_strobe_o"),
            we_o_idx: idx(n, "wbm_we_o"),
            addr_o_idx: idx(n, "wbm_addr_o"),
            data_o_idx: idx(n, "wbm_data_o"),
            sel_o_idx: idx(n, "wbm_sel_o"),

            pending_response: None,
            reset_cycles_remaining: 4,
            cycle_count: 0,
        }
    }

    pub fn is_sparc64_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        const REQUIRED: &[&str] = &[
            "sys_clock_i",
            "sys_reset_i",
            "eth_irq_i",
            "wbm_ack_i",
            "wbm_data_i",
            "wbm_cycle_o",
            "wbm_strobe_o",
            "wbm_we_o",
            "wbm_addr_o",
            "wbm_data_o",
            "wbm_sel_o",
        ];
        REQUIRED.iter().all(|name| name_to_idx.contains_key(*name))
    }

    pub fn reset_core(&mut self, core: &mut CoreSimulator) {
        self.pending_response = None;
        self.trace.clear();
        self.unmapped_accesses.clear();
        self.reset_cycles_remaining = 4;
        self.cycle_count = 0;

        self.apply_inputs(core, true, None);
        core.evaluate();
    }

    pub fn load_rom(&mut self, data: &[u8], offset: usize) -> usize {
        if data.is_empty() {
            return 0;
        }
        let base = canonical_bus_addr(offset as u64);
        for (index, value) in data.iter().enumerate() {
            self.flash.insert(base + index as u64, *value);
        }
        data.len()
    }

    pub fn load_memory(&mut self, data: &[u8], offset: usize) -> usize {
        if data.is_empty() {
            return 0;
        }
        let base = canonical_bus_addr(offset as u64);
        for (index, value) in data.iter().enumerate() {
            self.memory.insert(base + index as u64, *value);
        }
        data.len()
    }

    pub fn read_memory(&self, start: usize, out: &mut [u8], mapped: bool) -> usize {
        if out.is_empty() {
            return 0;
        }

        let base = canonical_bus_addr(start as u64);
        for (index, slot) in out.iter_mut().enumerate() {
            let addr = base + index as u64;
            *slot = if mapped {
                self.read_mapped_byte(addr).unwrap_or(0)
            } else {
                self.read_dram_byte(addr)
            };
        }
        out.len()
    }

    pub fn write_memory(&mut self, start: usize, data: &[u8], mapped: bool) -> usize {
        if data.is_empty() {
            return 0;
        }

        let base = canonical_bus_addr(start as u64);
        if mapped {
            for (index, value) in data.iter().enumerate() {
                let addr = base + index as u64;
                if self.is_flash_addr(addr) {
                    return index;
                }
                self.memory.insert(addr, *value);
            }
            return data.len();
        }

        for (index, value) in data.iter().enumerate() {
            self.memory.insert(base + index as u64, *value);
        }
        data.len()
    }

    pub fn read_rom(&self, start: usize, out: &mut [u8]) -> usize {
        if out.is_empty() {
            return 0;
        }

        let base = canonical_bus_addr(start as u64);
        for (index, slot) in out.iter_mut().enumerate() {
            *slot = *self.flash.get(&(base + index as u64)).unwrap_or(&0);
        }
        out.len()
    }

    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        if !core.compiled {
            return 0;
        }

        for _ in 0..n {
            let reset_active = self.reset_cycles_remaining > 0;
            let acked_response = if reset_active {
                None
            } else {
                self.pending_response
            };

            self.apply_inputs(core, reset_active, acked_response);
            core.evaluate();

            if let Some(response) = acked_response {
                self.record_acknowledged_response(response);
            }

            let next_response = if reset_active {
                None
            } else {
                self.sample_request(core).and_then(|request| {
                    if acked_response
                        .map(|response| response.request == request)
                        .unwrap_or(false)
                    {
                        None
                    } else {
                        Some(self.service_request(request))
                    }
                })
            };

            self.set_signal(core, self.clk_idx, 1);
            core.tick();

            self.pending_response = next_response;
            self.cycle_count = self.cycle_count.wrapping_add(1);
            self.reset_cycles_remaining = self.reset_cycles_remaining.saturating_sub(1);
        }

        n
    }

    pub fn trace_json(&self) -> String {
        serde_json::to_string(&self.trace).unwrap_or_else(|_| "[]".to_string())
    }

    pub fn unmapped_accesses_json(&self) -> String {
        serde_json::to_string(&self.unmapped_accesses).unwrap_or_else(|_| "[]".to_string())
    }

    fn apply_inputs(
        &mut self,
        core: &mut CoreSimulator,
        reset_active: bool,
        response: Option<PendingResponse>,
    ) {
        self.set_signal(core, self.clk_idx, 0);
        self.set_signal(core, self.rst_idx, if reset_active { 1 } else { 0 });
        self.set_signal(core, self.eth_irq_idx, 0);

        if let Some(response) = response {
            self.set_signal(core, self.ack_idx, 1);
            self.set_signal(core, self.data_i_idx, response.read_data as u128);
        } else {
            self.set_signal(core, self.ack_idx, 0);
            self.set_signal(core, self.data_i_idx, 0);
        }
    }

    fn sample_request(&self, core: &CoreSimulator) -> Option<Sparc64WishboneRequest> {
        if self.signal(core, self.cycle_o_idx) == 0 || self.signal(core, self.strobe_o_idx) == 0 {
            return None;
        }

        Some(Sparc64WishboneRequest {
            write: self.signal(core, self.we_o_idx) != 0,
            addr: canonical_bus_addr(self.signal(core, self.addr_o_idx) as u64),
            data: self.signal(core, self.data_o_idx) as u64,
            sel: (self.signal(core, self.sel_o_idx) & 0xFF) as u8,
        })
    }

    fn service_request(&mut self, request: Sparc64WishboneRequest) -> PendingResponse {
        if request.write {
            let mapped = self.write_wishbone_word(request.addr, request.data, request.sel);
            PendingResponse {
                request,
                read_data: 0,
                unmapped: !mapped,
            }
        } else {
            let (read_data, mapped) = self.read_wishbone_word(request.addr, request.sel);
            PendingResponse {
                request,
                read_data,
                unmapped: !mapped,
            }
        }
    }

    fn record_acknowledged_response(&mut self, response: PendingResponse) {
        if response.unmapped {
            self.unmapped_accesses.push(Sparc64Fault {
                cycle: self.cycle_count,
                op: if response.request.write { "write" } else { "read" },
                addr: response.request.addr,
                sel: response.request.sel,
            });
        }

        self.trace.push(Sparc64WishboneTraceEvent {
            cycle: self.cycle_count,
            op: if response.request.write { "write" } else { "read" },
            addr: response.request.addr,
            sel: response.request.sel,
            write_data: if response.request.write {
                Some(response.request.data)
            } else {
                None
            },
            read_data: if response.request.write {
                None
            } else {
                Some(response.read_data)
            },
        });
    }

    fn read_wishbone_word(&self, addr: u64, sel: u8) -> (u64, bool) {
        let mut value = 0u64;
        let mut mapped = false;

        for lane in 0..8 {
            if !lane_selected(sel, lane) {
                continue;
            }
            let byte_addr = addr.wrapping_add(lane as u64);
            let Some(byte) = self.read_mapped_byte(byte_addr) else {
                return (0, false);
            };
            value |= (byte as u64) << ((7 - lane) * 8);
            mapped = true;
        }

        (value, mapped)
    }

    fn write_wishbone_word(&mut self, addr: u64, data: u64, sel: u8) -> bool {
        let mut mapped = false;

        for lane in 0..8 {
            if !lane_selected(sel, lane) {
                continue;
            }

            let byte_addr = canonical_bus_addr(addr.wrapping_add(lane as u64));
            if self.is_flash_addr(byte_addr) {
                return false;
            }

            let byte = ((data >> ((7 - lane) * 8)) & 0xFF) as u8;
            self.memory.insert(byte_addr, byte);
            mapped = true;
        }

        mapped
    }

    fn read_mapped_byte(&self, addr: u64) -> Option<u8> {
        let physical = canonical_bus_addr(addr);
        if self.is_flash_addr(physical) {
            return Some(*self.flash.get(&physical).unwrap_or(&0));
        }

        if self.is_dram_addr(physical) {
            return Some(self.read_dram_byte(physical));
        }

        None
    }

    fn read_dram_byte(&self, addr: u64) -> u8 {
        *self.memory.get(&addr).unwrap_or(&0)
    }

    fn is_flash_addr(&self, addr: u64) -> bool {
        canonical_bus_addr(addr) >= FLASH_BOOT_BASE
    }

    fn is_dram_addr(&self, addr: u64) -> bool {
        canonical_bus_addr(addr) < FLASH_BOOT_BASE
    }

    fn signal(&self, core: &CoreSimulator, idx: usize) -> u128 {
        core.signals.get(idx).copied().unwrap_or(0)
    }

    fn set_signal(&self, core: &mut CoreSimulator, idx: usize, value: u128) {
        if idx < core.signals.len() {
            core.signals[idx] = value;
        }
    }
}

fn idx(name_to_idx: &HashMap<String, usize>, name: &str) -> usize {
    *name_to_idx.get(name).unwrap_or(&0)
}

fn lane_selected(sel: u8, lane: usize) -> bool {
    (sel & (0x80 >> lane)) != 0
}

fn canonical_bus_addr(addr: u64) -> u64 {
    addr & PHYSICAL_ADDR_MASK
}
