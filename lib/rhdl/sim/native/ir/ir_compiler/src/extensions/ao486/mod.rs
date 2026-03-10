//! AO486 CPU-top runner scaffold for the IR compiler.
//!
//! This extension intentionally keeps the first slice small: it identifies the
//! imported `ao486` CPU-top signature, provides sparse backing stores for main
//! memory and ROM, and applies safe top-level reset defaults so higher-level
//! runtimes can build on a stable native runner shape.

use std::collections::HashMap;

use crate::core::CoreSimulator;

const REQUIRED_PORTS: &[&str] = &[
    "clk",
    "rst_n",
    "a20_enable",
    "cache_disable",
    "interrupt_do",
    "interrupt_vector",
    "interrupt_done",
    "avm_address",
    "avm_writedata",
    "avm_byteenable",
    "avm_burstcount",
    "avm_write",
    "avm_read",
    "avm_waitrequest",
    "avm_readdatavalid",
    "avm_readdata",
    "dma_address",
    "dma_16bit",
    "dma_write",
    "dma_writedata",
    "dma_read",
    "dma_readdata",
    "dma_readdatavalid",
    "dma_waitrequest",
    "io_read_do",
    "io_read_address",
    "io_read_length",
    "io_read_data",
    "io_read_done",
    "io_write_do",
    "io_write_address",
    "io_write_length",
    "io_write_data",
    "io_write_done",
];

const POST_INIT_IVT_START_EIP: u64 = 0x8BF3;
const POST_INIT_IVT_END_EIP: u64 = 0x8C03;
const POST_INIT_IVT_VECTOR_COUNT: usize = 120;
const POST_INIT_IVT_ENTRY: [u8; 4] = [0x53, 0xFF, 0x00, 0xF0];

#[derive(Clone, Copy)]
struct ReadBurst {
    base: u64,
    beat_index: usize,
    beats_total: usize,
    started: bool,
}

pub struct Ao486Extension {
    pub memory: HashMap<u64, u8>,
    pub rom: HashMap<u64, u8>,
    pub disk: HashMap<u64, u8>,
    cmos: [u8; 128],
    cmos_index: u8,
    pic_master_mask: u8,
    pic_slave_mask: u8,
    pic_master_pending: u8,
    pic_master_in_service: u8,
    pic_master_base: u8,
    pic_slave_base: u8,
    pit_control: u8,
    pit_reload: u32,
    pit_counter: u32,
    pit_low_byte: Option<u8>,
    reset_cycles_remaining: usize,
    pending_read_burst: Option<ReadBurst>,
    pending_io_read_data: Option<u32>,
    pending_io_write_ack: bool,
    post_init_ivt_seeded: bool,
    prev_io_read_do: bool,
    prev_io_write_do: bool,
    clk_idx: usize,
    rst_n_idx: usize,
    a20_enable_idx: usize,
    cache_disable_idx: usize,
    interrupt_do_idx: usize,
    interrupt_vector_idx: usize,
    interrupt_done_idx: usize,
    avm_waitrequest_idx: usize,
    avm_readdatavalid_idx: usize,
    avm_readdata_idx: usize,
    avm_address_idx: usize,
    avm_writedata_idx: usize,
    avm_byteenable_idx: usize,
    avm_burstcount_idx: usize,
    avm_write_idx: usize,
    avm_read_idx: usize,
    dma_address_idx: usize,
    dma_16bit_idx: usize,
    dma_write_idx: usize,
    dma_writedata_idx: usize,
    dma_read_idx: usize,
    io_read_do_idx: usize,
    io_read_address_idx: usize,
    io_read_length_idx: usize,
    io_read_data_idx: usize,
    io_read_done_idx: usize,
    io_write_do_idx: usize,
    io_write_address_idx: usize,
    io_write_length_idx: usize,
    io_write_data_idx: usize,
    io_write_done_idx: usize,
    trace_wr_eip_idx: Option<usize>,
    decode_eip_idx: Option<usize>,
    code_read_do_idx: Option<usize>,
    code_read_address_idx: Option<usize>,
}

impl Ao486Extension {
    pub fn new(core: &CoreSimulator) -> Self {
        let n = &core.name_to_idx;

        Self {
            memory: HashMap::new(),
            rom: HashMap::new(),
            disk: HashMap::new(),
            cmos: default_cmos(),
            cmos_index: 0,
            pic_master_mask: 0xFF,
            pic_slave_mask: 0xFF,
            pic_master_pending: 0,
            pic_master_in_service: 0,
            pic_master_base: 0x08,
            pic_slave_base: 0x70,
            pit_control: 0,
            pit_reload: 0,
            pit_counter: 0,
            pit_low_byte: None,
            reset_cycles_remaining: 1,
            pending_read_burst: None,
            pending_io_read_data: None,
            pending_io_write_ack: false,
            post_init_ivt_seeded: false,
            prev_io_read_do: false,
            prev_io_write_do: false,
            clk_idx: idx(n, "clk"),
            rst_n_idx: idx(n, "rst_n"),
            a20_enable_idx: idx(n, "a20_enable"),
            cache_disable_idx: idx(n, "cache_disable"),
            interrupt_do_idx: idx(n, "interrupt_do"),
            interrupt_vector_idx: idx(n, "interrupt_vector"),
            interrupt_done_idx: idx(n, "interrupt_done"),
            avm_waitrequest_idx: idx(n, "avm_waitrequest"),
            avm_readdatavalid_idx: idx(n, "avm_readdatavalid"),
            avm_readdata_idx: idx(n, "avm_readdata"),
            avm_address_idx: idx(n, "avm_address"),
            avm_writedata_idx: idx(n, "avm_writedata"),
            avm_byteenable_idx: idx(n, "avm_byteenable"),
            avm_burstcount_idx: idx(n, "avm_burstcount"),
            avm_write_idx: idx(n, "avm_write"),
            avm_read_idx: idx(n, "avm_read"),
            dma_address_idx: idx(n, "dma_address"),
            dma_16bit_idx: idx(n, "dma_16bit"),
            dma_write_idx: idx(n, "dma_write"),
            dma_writedata_idx: idx(n, "dma_writedata"),
            dma_read_idx: idx(n, "dma_read"),
            io_read_do_idx: idx(n, "io_read_do"),
            io_read_address_idx: idx(n, "io_read_address"),
            io_read_length_idx: idx(n, "io_read_length"),
            io_read_data_idx: idx(n, "io_read_data"),
            io_read_done_idx: idx(n, "io_read_done"),
            io_write_do_idx: idx(n, "io_write_do"),
            io_write_address_idx: idx(n, "io_write_address"),
            io_write_length_idx: idx(n, "io_write_length"),
            io_write_data_idx: idx(n, "io_write_data"),
            io_write_done_idx: idx(n, "io_write_done"),
            trace_wr_eip_idx: idx_opt(n, "trace_wr_eip"),
            decode_eip_idx: idx_opt(n, "pipeline_inst__decode_inst__eip"),
            code_read_do_idx: idx_opt(n, "memory_inst__icache_inst__readcode_do"),
            code_read_address_idx: idx_opt(n, "memory_inst__icache_inst__readcode_address"),
        }
    }

    pub fn is_ao486_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        REQUIRED_PORTS
            .iter()
            .all(|name| name_to_idx.contains_key(*name))
    }

    pub fn reset_core(&mut self, core: &mut CoreSimulator) {
        self.pic_master_mask = 0xFF;
        self.pic_slave_mask = 0xFF;
        self.pic_master_pending = 0;
        self.pic_master_in_service = 0;
        self.pic_master_base = 0x08;
        self.pic_slave_base = 0x70;
        self.pit_control = 0;
        self.pit_reload = 0;
        self.pit_counter = 0;
        self.pit_low_byte = None;
        self.pending_read_burst = None;
        self.pending_io_read_data = None;
        self.pending_io_write_ack = false;
        self.post_init_ivt_seeded = false;
        self.prev_io_read_do = false;
        self.prev_io_write_do = false;
        self.reset_cycles_remaining = 1;
        self.apply_default_inputs(core, true, None);
        core.evaluate();
    }

    pub fn load_rom(&mut self, data: &[u8], offset: usize) -> usize {
        load_bytes(&mut self.rom, data, offset)
    }

    pub fn load_memory(&mut self, data: &[u8], offset: usize) -> usize {
        load_bytes(&mut self.memory, data, offset)
    }

    pub fn read_memory(&self, start: usize, out: &mut [u8], mapped: bool) -> usize {
        if out.is_empty() {
            return 0;
        }

        let base = start as u64;
        for (index, slot) in out.iter_mut().enumerate() {
            let addr = base + index as u64;
            *slot = if mapped {
                self.read_mapped_byte(addr).unwrap_or(0)
            } else {
                *self.memory.get(&addr).unwrap_or(&0)
            };
        }
        out.len()
    }

    pub fn write_memory(&mut self, start: usize, data: &[u8], mapped: bool) -> usize {
        if data.is_empty() {
            return 0;
        }

        let base = start as u64;
        let mut written = 0usize;
        for (index, value) in data.iter().enumerate() {
            let addr = base + index as u64;
            if mapped && self.rom.contains_key(&addr) {
                break;
            }
            self.memory.insert(addr, *value);
            written += 1;
        }
        written
    }

    pub fn read_rom(&self, start: usize, out: &mut [u8]) -> usize {
        if out.is_empty() {
            return 0;
        }

        let base = start as u64;
        for (index, slot) in out.iter_mut().enumerate() {
            *slot = *self.rom.get(&(base + index as u64)).unwrap_or(&0);
        }
        out.len()
    }

    pub fn load_disk(&mut self, data: &[u8], offset: usize) -> usize {
        load_bytes(&mut self.disk, data, offset)
    }

    pub fn read_disk(&self, start: usize, out: &mut [u8]) -> usize {
        if out.is_empty() {
            return 0;
        }

        let base = start as u64;
        for (index, slot) in out.iter_mut().enumerate() {
            *slot = *self.disk.get(&(base + index as u64)).unwrap_or(&0);
        }
        out.len()
    }

    pub fn write_disk(&mut self, start: usize, data: &[u8]) -> usize {
        if data.is_empty() {
            return 0;
        }

        load_bytes(&mut self.disk, data, start)
    }

    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        if !core.compiled {
            return 0;
        }

        for _ in 0..n {
            let reset_active = self.reset_cycles_remaining > 0;
            let irq_vector = if reset_active {
                None
            } else {
                self.active_irq_vector()
            };
            let read_response = if reset_active {
                None
            } else {
                self.pending_read_burst.filter(|burst| burst.started).map(|burst| {
                    let addr = burst.base + ((burst.beat_index as u64) * 4);
                    little_endian_word(self, addr)
                })
            };
            let io_read_response = if reset_active {
                None
            } else {
                self.pending_io_read_data.take()
            };
            let io_write_done = if reset_active {
                false
            } else {
                let done = self.pending_io_write_ack;
                self.pending_io_write_ack = false;
                done
            };

            self.apply_default_inputs(core, reset_active, irq_vector);
            if let Some(word) = read_response {
                self.set_signal(core, self.avm_readdatavalid_idx, 1);
                self.set_signal(core, self.avm_readdata_idx, word as u128);
            }
            if let Some(value) = io_read_response {
                self.set_signal(core, self.io_read_data_idx, value as u128);
                self.set_signal(core, self.io_read_done_idx, 1);
            }
            if io_write_done {
                self.set_signal(core, self.io_write_done_idx, 1);
            }

            core.evaluate();
            if self.retarget_code_burst_if_needed(core) {
                self.set_signal(core, self.avm_readdatavalid_idx, 0);
                self.set_signal(core, self.avm_readdata_idx, 0);
                core.evaluate();
            }
            let current_io_read_do = !reset_active && self.signal(core, self.io_read_do_idx) != 0;
            let current_io_write_do = !reset_active && self.signal(core, self.io_write_do_idx) != 0;

            if !reset_active {
                self.arm_read_burst_if_needed(core);
                self.queue_io_requests_if_needed(core, current_io_read_do, current_io_write_do);
            }

            self.set_signal(core, self.clk_idx, 1);
            core.tick();

            if !reset_active {
                // Match the existing AO486 parity runtimes and Verilator harness:
                // memory writes become visible from the post-tick outputs, not the
                // pre-tick evaluate phase.
                self.commit_memory_write_if_needed(core);
                self.maybe_seed_post_init_ivt(core);
                self.handle_interrupt_ack(core);
                self.advance_timers();
            }
            self.advance_read_burst(read_response.is_some());
            self.reset_cycles_remaining = self.reset_cycles_remaining.saturating_sub(1);
            self.prev_io_read_do = current_io_read_do;
            self.prev_io_write_do = current_io_write_do;
        }

        n
    }

    fn apply_default_inputs(
        &self,
        core: &mut CoreSimulator,
        reset_active: bool,
        irq_vector: Option<u8>,
    ) {
        self.set_signal(core, self.clk_idx, 0);
        self.set_signal(core, self.rst_n_idx, if reset_active { 0 } else { 1 });
        self.set_signal(core, self.a20_enable_idx, 1);
        self.set_signal(core, self.cache_disable_idx, 1);
        self.set_signal(core, self.interrupt_do_idx, if irq_vector.is_some() { 1 } else { 0 });
        self.set_signal(core, self.interrupt_vector_idx, irq_vector.unwrap_or(0) as u128);
        self.set_signal(core, self.avm_waitrequest_idx, 0);
        self.set_signal(core, self.avm_readdatavalid_idx, 0);
        self.set_signal(core, self.avm_readdata_idx, 0);
        self.set_signal(core, self.dma_address_idx, 0);
        self.set_signal(core, self.dma_16bit_idx, 0);
        self.set_signal(core, self.dma_write_idx, 0);
        self.set_signal(core, self.dma_writedata_idx, 0);
        self.set_signal(core, self.dma_read_idx, 0);
        self.set_signal(core, self.io_read_data_idx, 0);
        self.set_signal(core, self.io_read_done_idx, 0);
        self.set_signal(core, self.io_write_done_idx, 0);
    }

    fn commit_memory_write_if_needed(&mut self, core: &CoreSimulator) {
        if self.signal(core, self.avm_write_idx) == 0 {
            return;
        }

        let addr = (self.signal(core, self.avm_address_idx) as u64) << 2;
        let data = (self.signal(core, self.avm_writedata_idx) & 0xFFFF_FFFF) as u32;
        let byteenable = (self.signal(core, self.avm_byteenable_idx) & 0xF) as u8;

        for index in 0..4 {
            if ((byteenable >> index) & 1) == 0 {
                continue;
            }
            self.memory
                .insert(addr + index as u64, ((data >> (index * 8)) & 0xFF) as u8);
        }
    }

    fn arm_read_burst_if_needed(&mut self, core: &CoreSimulator) {
        if self.pending_read_burst.is_some() || self.signal(core, self.avm_read_idx) == 0 {
            return;
        }

        let beats_total = (self.signal(core, self.avm_burstcount_idx) as usize).max(1);
        self.pending_read_burst = Some(ReadBurst {
            base: (self.signal(core, self.avm_address_idx) as u64) << 2,
            beat_index: 0,
            beats_total,
            started: false,
        });
    }

    fn retarget_code_burst_if_needed(&mut self, core: &CoreSimulator) -> bool {
        let Some(code_read_do_idx) = self.code_read_do_idx else {
            return false;
        };
        let Some(code_read_address_idx) = self.code_read_address_idx else {
            return false;
        };
        if self.signal(core, code_read_do_idx) == 0 {
            return false;
        }

        let target = self.signal(core, code_read_address_idx) as u64 & !0x3;
        let Some(read_burst) = self.pending_read_burst.as_mut() else {
            return false;
        };
        if read_burst.base == target {
            return false;
        }

        read_burst.base = target;
        read_burst.beat_index = 0;
        read_burst.started = false;
        true
    }

    fn advance_read_burst(&mut self, delivered: bool) {
        let Some(mut burst) = self.pending_read_burst else {
            return;
        };
        if !delivered {
            burst.started = true;
            self.pending_read_burst = Some(burst);
            return;
        }

        burst.beat_index += 1;
        self.pending_read_burst = if burst.beat_index >= burst.beats_total {
            None
        } else {
            burst.started = true;
            Some(burst)
        };
    }

    fn queue_io_requests_if_needed(
        &mut self,
        core: &CoreSimulator,
        current_io_read_do: bool,
        current_io_write_do: bool,
    ) {
        if current_io_read_do && !self.prev_io_read_do && self.pending_io_read_data.is_none() {
            let addr = (self.signal(core, self.io_read_address_idx) & 0xFFFF) as u16;
            let len = ((self.signal(core, self.io_read_length_idx) & 0x7) as usize).max(1);
            self.pending_io_read_data = Some(self.read_io_value(addr, len));
        }

        if current_io_write_do && !self.prev_io_write_do && !self.pending_io_write_ack {
            let addr = (self.signal(core, self.io_write_address_idx) & 0xFFFF) as u16;
            let len = ((self.signal(core, self.io_write_length_idx) & 0x7) as usize).max(1);
            let data = (self.signal(core, self.io_write_data_idx) & 0xFFFF_FFFF) as u32;
            self.write_io_value(addr, len, data);
            self.pending_io_write_ack = true;
        }
    }

    fn active_irq_vector(&self) -> Option<u8> {
        let ready = self.pic_master_pending & !self.pic_master_mask & !self.pic_master_in_service;
        if ready == 0 {
            None
        } else {
            Some(self.pic_master_base.wrapping_add(ready.trailing_zeros() as u8))
        }
    }

    fn handle_interrupt_ack(&mut self, core: &CoreSimulator) {
        if self.signal(core, self.interrupt_done_idx) == 0 {
            return;
        }

        let ready = self.pic_master_pending & !self.pic_master_mask & !self.pic_master_in_service;
        if ready == 0 {
            return;
        }

        let irq_bit = ready.trailing_zeros() as u8;
        let mask = 1u8 << irq_bit;
        self.pic_master_pending &= !mask;
        self.pic_master_in_service |= mask;
    }

    fn advance_timers(&mut self) {
        if self.pit_counter == 0 {
            return;
        }

        self.pit_counter -= 1;
        if self.pit_counter == 0 {
            self.pic_master_pending |= 1;
            self.pit_counter = self.pit_reload;
        }
    }

    fn maybe_seed_post_init_ivt(&mut self, core: &CoreSimulator) {
        if self.post_init_ivt_seeded {
            return;
        }

        let helper_active = self
            .trace_wr_eip_idx
            .and_then(|idx| {
                let value = self.signal(core, idx) as u64;
                if (POST_INIT_IVT_START_EIP..=POST_INIT_IVT_END_EIP).contains(&value) {
                    Some(value)
                } else {
                    None
                }
            })
            .or_else(|| {
                self.decode_eip_idx.and_then(|idx| {
                    let value = self.signal(core, idx) as u64;
                    if (POST_INIT_IVT_START_EIP..=POST_INIT_IVT_END_EIP).contains(&value) {
                        Some(value)
                    } else {
                        None
                    }
                })
            });

        if helper_active.is_none() {
            return;
        }

        for vector in 0..POST_INIT_IVT_VECTOR_COUNT {
            let base = (vector * POST_INIT_IVT_ENTRY.len()) as u64;
            for (offset, byte) in POST_INIT_IVT_ENTRY.iter().enumerate() {
                self.memory.insert(base + offset as u64, *byte);
            }
        }
        self.post_init_ivt_seeded = true;
    }

    fn read_io_value(&self, address: u16, length: usize) -> u32 {
        let mut value = 0u32;
        for offset in 0..length.min(4) {
            let byte = self.read_io_byte(address.wrapping_add(offset as u16)) as u32;
            value |= byte << (offset * 8);
        }
        value
    }

    fn read_io_byte(&self, address: u16) -> u8 {
        match address {
            0x0060 => 0x00,
            0x0061 => 0x20,
            0x0064 => 0x1C,
            0x0070 => self.cmos_index & 0x7F,
            0x0071 => self.cmos[(self.cmos_index & 0x7F) as usize],
            0x0020 => self.pic_master_pending,
            0x0021 => self.pic_master_mask,
            0x00A0 => 0x00,
            0x00A1 => self.pic_slave_mask,
            0x0040 => (self.pit_counter & 0xFF) as u8,
            0x0041 | 0x0042 => 0x00,
            0x0043 => self.pit_control,
            0x03F0..=0x03F7 => {
                if address == 0x03F4 {
                    0x80
                } else {
                    0x00
                }
            }
            0x03D4 | 0x03D5 | 0x03DA => {
                if address == 0x03DA { 0x08 } else { 0x00 }
            }
            0x03B4 | 0x03B5 | 0x03C0..=0x03CF => 0x00,
            _ => 0xFF,
        }
    }

    fn write_io_value(&mut self, address: u16, length: usize, data: u32) {
        for offset in 0..length.min(4) {
            let addr = address.wrapping_add(offset as u16);
            let byte = ((data >> (offset * 8)) & 0xFF) as u8;
            match addr {
                0x0020 => {
                    if byte & 0x20 != 0 {
                        self.pic_master_in_service = clear_lowest_set_bit(self.pic_master_in_service);
                    }
                }
                0x0021 => self.pic_master_mask = byte,
                0x00A0 => {}
                0x00A1 => self.pic_slave_mask = byte,
                0x0040 => self.write_pit_counter_byte(byte),
                0x0043 => self.write_pit_control(byte),
                0x0070 => self.cmos_index = byte & 0x7F,
                0x0071 => self.cmos[(self.cmos_index & 0x7F) as usize] = byte,
                _ => {}
            }
        }
    }

    fn write_pit_control(&mut self, byte: u8) {
        self.pit_control = byte;
        if (byte >> 6) == 0 {
            self.pit_low_byte = None;
        }
    }

    fn write_pit_counter_byte(&mut self, byte: u8) {
        let access_mode = (self.pit_control >> 4) & 0x3;
        match access_mode {
            1 => self.set_pit_reload(byte as u16),
            2 => self.set_pit_reload((byte as u16) << 8),
            3 => {
                if let Some(low) = self.pit_low_byte.take() {
                    self.set_pit_reload(u16::from(low) | ((byte as u16) << 8));
                } else {
                    self.pit_low_byte = Some(byte);
                }
            }
            _ => {}
        }
    }

    fn set_pit_reload(&mut self, value: u16) {
        let reload = if value == 0 { 65_536 } else { value as u32 };
        self.pit_reload = reload;
        self.pit_counter = reload;
    }

    fn read_mapped_byte(&self, addr: u64) -> Option<u8> {
        self.rom
            .get(&addr)
            .copied()
            .or_else(|| self.memory.get(&addr).copied())
    }

    fn signal(&self, core: &CoreSimulator, idx: usize) -> u128 {
        if idx < core.signals.len() {
            core.signals[idx]
        } else {
            0
        }
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

fn idx_opt(name_to_idx: &HashMap<String, usize>, name: &str) -> Option<usize> {
    name_to_idx.get(name).copied()
}

fn load_bytes(target: &mut HashMap<u64, u8>, data: &[u8], offset: usize) -> usize {
    if data.is_empty() {
        return 0;
    }

    let base = offset as u64;
    for (index, value) in data.iter().enumerate() {
        target.insert(base + index as u64, *value);
    }
    data.len()
}

fn clear_lowest_set_bit(value: u8) -> u8 {
    if value == 0 {
        0
    } else {
        value & value.wrapping_sub(1)
    }
}

fn little_endian_word(ext: &Ao486Extension, addr: u64) -> u32 {
    let mut word = 0u32;
    for index in 0..4 {
        let byte = ext.read_mapped_byte(addr + index as u64).unwrap_or(0) as u32;
        word |= byte << (index * 8);
    }
    word
}

fn default_cmos() -> [u8; 128] {
    let mut cmos = [0u8; 128];
    cmos[0x0A] = 0x26;
    cmos[0x0B] = 0x02;
    cmos[0x0D] = 0x80;
    cmos[0x10] = 0x40;
    cmos[0x12] = 0xF0;
    cmos[0x14] = 0x0D;
    cmos[0x15] = 0x80;
    cmos[0x16] = 0x02;
    cmos[0x17] = 0x00;
    cmos[0x18] = 0xFC;
    cmos[0x19] = 0x2F;
    cmos[0x1B] = 0x00;
    cmos[0x1C] = 0x04;
    cmos[0x1D] = 0x10;
    cmos[0x20] = 0xC8;
    cmos[0x21] = 0x00;
    cmos[0x22] = 0x04;
    cmos[0x23] = 0x3F;
    cmos[0x2D] = 0x20;
    cmos[0x30] = 0x00;
    cmos[0x31] = 0xFC;
    cmos[0x32] = 0x20;
    cmos[0x34] = 0x00;
    cmos[0x35] = 0x07;
    cmos[0x37] = 0x20;
    cmos[0x38] = 0x20;
    cmos[0x3D] = 0x2F;
    cmos[0x5B] = 0x00;
    cmos[0x5C] = 0x07;
    cmos
}
