//! AO486 standalone simulation extension for IR Compiler.
//!
//! Provides batched execution with native word-addressed memory simulation for the
//! AO486 top-level AVM/IO bus interfaces.

use std::collections::{HashMap, VecDeque};

use crate::core::CoreSimulator;

/// Memory word-size for AVM accesses.
const WORD_BYTES: u64 = 4;
const IO_PORT_KBD_DATA: u16 = 0x0060;
const IO_PORT_KBD_STATUS: u16 = 0x0064;
const IO_PORT_DISK_CH: u16 = 0x00E0;
const IO_PORT_DISK_CL: u16 = 0x00E1;
const IO_PORT_DISK_DH: u16 = 0x00E2;
const IO_PORT_DISK_DL: u16 = 0x00E3;
const IO_PORT_DISK_COUNT: u16 = 0x00E4;
const IO_PORT_DISK_COMMAND_STATUS: u16 = 0x00E5;
const IO_PORT_DISK_DATA: u16 = 0x00E6;
const DISK_COMMAND_READ: u8 = 0x01;
const DISK_STATUS_READY: u8 = 0x01;
const DISK_STATUS_ERROR: u8 = 0x80;
const DISK_IMAGE_BASE: u32 = 0x0020_0000;
const DISK_SECTOR_BYTES: usize = 512;
const DISK_CYLINDERS: u32 = 80;
const DISK_HEADS: u32 = 2;
const DISK_SECTORS_PER_TRACK: u32 = 18;
const DISK_IMAGE_BYTES: usize =
    (DISK_CYLINDERS as usize) * (DISK_HEADS as usize) * (DISK_SECTORS_PER_TRACK as usize) * DISK_SECTOR_BYTES;

/// AO486-specific memory extension.
pub struct Ao486Extension {
    pub memory: HashMap<u32, u8>,

    clk_idx: Option<usize>,
    rst_n_idx: Option<usize>,

    a20_enable_idx: Option<usize>,
    cache_disable_idx: Option<usize>,

    interrupt_do_idx: Option<usize>,
    interrupt_vector_idx: Option<usize>,
    interrupt_done_idx: Option<usize>,

    avm_address_idx: Option<usize>,
    avm_writedata_idx: Option<usize>,
    avm_byteenable_idx: Option<usize>,
    avm_burstcount_idx: Option<usize>,
    avm_write_idx: Option<usize>,
    avm_read_idx: Option<usize>,
    avm_waitrequest_idx: Option<usize>,
    avm_readdatavalid_idx: Option<usize>,
    avm_readdata_idx: Option<usize>,

    dma_address_idx: Option<usize>,
    dma_readdata_idx: Option<usize>,
    dma_readdatavalid_idx: Option<usize>,
    dma_waitrequest_idx: Option<usize>,

    dma_16bit_idx: Option<usize>,
    dma_write_idx: Option<usize>,
    dma_writedata_idx: Option<usize>,
    dma_read_idx: Option<usize>,

    io_read_do_idx: Option<usize>,
    io_read_address_idx: Option<usize>,
    io_read_length_idx: Option<usize>,
    io_read_data_idx: Option<usize>,
    io_read_done_idx: Option<usize>,

    io_write_do_idx: Option<usize>,
    io_write_address_idx: Option<usize>,
    io_write_length_idx: Option<usize>,
    io_write_data_idx: Option<usize>,
    io_write_done_idx: Option<usize>,

    pending_read_words: u32,
    pending_read_address: u32,
    pending_read_skip_first: bool,
    io_read_done_pending: bool,
    io_write_done_pending: bool,
    cycle_counter: u32,
    event_lines: Vec<String>,
    keyboard_queue: VecDeque<u8>,
    disk_ch: u8,
    disk_cl: u8,
    disk_dh: u8,
    disk_dl: u8,
    disk_count: u8,
    disk_status: u8,
    disk_stream_offset: usize,
    disk_stream_remaining: usize,
}

impl Ao486Extension {
    /// Create AO486 extension by resolving signal indices.
    pub fn new(core: &CoreSimulator) -> Self {
        let name_to_idx = &core.name_to_idx;
        Self {
            memory: HashMap::new(),

            clk_idx: name_to_idx.get("clk").copied(),
            rst_n_idx: name_to_idx.get("rst_n").copied(),

            a20_enable_idx: name_to_idx.get("a20_enable").copied(),
            cache_disable_idx: name_to_idx.get("cache_disable").copied(),

            interrupt_do_idx: name_to_idx.get("interrupt_do").copied(),
            interrupt_vector_idx: name_to_idx.get("interrupt_vector").copied(),
            interrupt_done_idx: name_to_idx.get("interrupt_done").copied(),

            avm_address_idx: name_to_idx.get("avm_address").copied(),
            avm_writedata_idx: name_to_idx.get("avm_writedata").copied(),
            avm_byteenable_idx: name_to_idx.get("avm_byteenable").copied(),
            avm_burstcount_idx: name_to_idx.get("avm_burstcount").copied(),
            avm_write_idx: name_to_idx.get("avm_write").copied(),
            avm_read_idx: name_to_idx.get("avm_read").copied(),
            avm_waitrequest_idx: name_to_idx.get("avm_waitrequest").copied(),
            avm_readdatavalid_idx: name_to_idx.get("avm_readdatavalid").copied(),
            avm_readdata_idx: name_to_idx.get("avm_readdata").copied(),

            dma_address_idx: name_to_idx.get("dma_address").copied(),
            dma_16bit_idx: name_to_idx.get("dma_16bit").copied(),
            dma_write_idx: name_to_idx.get("dma_write").copied(),
            dma_writedata_idx: name_to_idx.get("dma_writedata").copied(),
            dma_read_idx: name_to_idx.get("dma_read").copied(),
            dma_readdata_idx: name_to_idx.get("dma_readdata").copied(),
            dma_readdatavalid_idx: name_to_idx.get("dma_readdatavalid").copied(),
            dma_waitrequest_idx: name_to_idx.get("dma_waitrequest").copied(),

            io_read_do_idx: name_to_idx.get("io_read_do").copied(),
            io_read_address_idx: name_to_idx.get("io_read_address").copied(),
            io_read_length_idx: name_to_idx.get("io_read_length").copied(),
            io_read_data_idx: name_to_idx.get("io_read_data").copied(),
            io_read_done_idx: name_to_idx.get("io_read_done").copied(),

            io_write_do_idx: name_to_idx.get("io_write_do").copied(),
            io_write_address_idx: name_to_idx.get("io_write_address").copied(),
            io_write_length_idx: name_to_idx.get("io_write_length").copied(),
            io_write_data_idx: name_to_idx.get("io_write_data").copied(),
            io_write_done_idx: name_to_idx.get("io_write_done").copied(),

            pending_read_words: 0,
            pending_read_address: 0,
            pending_read_skip_first: false,
            io_read_done_pending: false,
            io_write_done_pending: false,
            cycle_counter: 0,
            event_lines: Vec::new(),
            keyboard_queue: VecDeque::new(),
            disk_ch: 0,
            disk_cl: 0,
            disk_dh: 0,
            disk_dl: 0,
            disk_count: 0,
            disk_status: 0,
            disk_stream_offset: 0,
            disk_stream_remaining: 0,
        }
    }

    /// Detect AO486-style IR by requiring the key bus and reset signals.
    pub fn is_ao486_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        const REQUIRED: &[&str] = &[
            "clk",
            "rst_n",
            "avm_address",
            "avm_writedata",
            "avm_byteenable",
            "avm_burstcount",
            "avm_write",
            "avm_read",
            "avm_waitrequest",
            "avm_readdatavalid",
            "avm_readdata",
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
        REQUIRED.iter().all(|name| name_to_idx.contains_key(*name))
    }

    /// Load bytes into emulated memory and return bytes written.
    pub fn load_main(&mut self, data: &[u8], offset: usize, _is_rom: bool) -> usize {
        if data.is_empty() {
            return 0;
        }
        let base = offset as u32;
        for (idx, byte) in data.iter().copied().enumerate() {
            let address = base.wrapping_add(idx as u32);
            self.memory.insert(address, byte);
        }
        data.len()
    }

    /// Read memory bytes from emulated AVM data space.
    pub fn read_main(&self, start: usize, out: &mut [u8], _mapped: bool) -> usize {
        if out.is_empty() {
            return 0;
        }
        let base = start as u32;
        for (idx, slot) in out.iter_mut().enumerate() {
            let address = base.wrapping_add(idx as u32);
            *slot = self.memory.get(&address).copied().unwrap_or(0);
        }
        out.len()
    }

    /// Write bytes into emulated AVM data space and return bytes written.
    pub fn write_main(&mut self, start: usize, data: &[u8], _mapped: bool) -> usize {
        if data.is_empty() {
            return 0;
        }
        let base = start as u32;
        for (idx, byte) in data.iter().copied().enumerate() {
            let address = base.wrapping_add(idx as u32);
            self.memory.insert(address, byte);
        }
        data.len()
    }

    /// Read ROM bytes in AO486 terms. AO486 does not have a separate ROM region in this extension.
    pub fn read_rom(&self, start: usize, out: &mut [u8]) -> usize {
        self.read_main(start, out, false)
    }

    /// Reset runtime-only AO486 bridge state (does not clear memory).
    pub fn reset_runtime_state(&mut self) {
        self.pending_read_words = 0;
        self.pending_read_address = 0;
        self.pending_read_skip_first = false;
        self.io_read_done_pending = false;
        self.io_write_done_pending = false;
        self.cycle_counter = 0;
        self.event_lines.clear();
        self.keyboard_queue.clear();
        self.disk_ch = 0;
        self.disk_cl = 0;
        self.disk_dh = 0;
        self.disk_dl = 0;
        self.disk_count = 0;
        self.disk_status = 0;
        self.disk_stream_offset = 0;
        self.disk_stream_remaining = 0;
    }

    /// Queue one keyboard byte for AO486 IO port reads.
    pub fn enqueue_keyboard_byte(&mut self, byte: u8) {
        if self.keyboard_queue.len() < 1024 {
            self.keyboard_queue.push_back(byte);
        }
    }

    /// Drain buffered AO486 event lines and clear the buffer.
    pub fn take_event_lines(&mut self) -> String {
        if self.event_lines.is_empty() {
            return String::new();
        }

        let mut text = self.event_lines.join("\n");
        text.push('\n');
        self.event_lines.clear();
        text
    }

    /// Current byte length of buffered AO486 events as emitted by `take_event_lines`.
    pub fn event_lines_len(&self) -> usize {
        if self.event_lines.is_empty() {
            return 0;
        }

        // Joined with '\n' plus trailing newline in `take_event_lines`.
        let content_bytes = self.event_lines.iter().map(|line| line.len()).sum::<usize>();
        let separators = self.event_lines.len().saturating_sub(1);
        content_bytes + separators + 1
    }

    /// Advance the core `n` cycles with AO486 bus bridging.
    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        for _ in 0..n {
            self.set_signal(core, self.clk_idx, 0);
            self.apply_platform_inputs(core);
            self.drive_cycle_inputs(core);
            core.evaluate();

            self.tick_rising_edge(core);

            let avm_wait = self.signal(core, self.avm_waitrequest_idx) != 0;
            let avm_read = self.signal(core, self.avm_read_idx) & 1;
            let avm_write = self.signal(core, self.avm_write_idx) & 1;
            let io_read_do = self.signal(core, self.io_read_do_idx) & 1;
            let io_write_do = self.signal(core, self.io_write_do_idx) & 1;

            let avm_address = (self.signal(core, self.avm_address_idx) & 0xFFFF_FFFF) as u32;
            let avm_writedata = (self.signal(core, self.avm_writedata_idx) & 0xFFFF_FFFF) as u32;
            let avm_byteenable = (self.signal(core, self.avm_byteenable_idx) & 0xF) as u32;
            let avm_burstcount = (self.signal(core, self.avm_burstcount_idx) & 0xF) as u32;

            if self.pending_read_words == 0 && avm_read != 0 && !avm_wait {
                let address = (avm_address << 2).wrapping_add(0);
                let burst_words = if avm_burstcount == 0 { 1 } else { avm_burstcount };
                self.pending_read_words = burst_words.saturating_add(1);
                self.pending_read_address = address.wrapping_sub(WORD_BYTES as u32);
                self.pending_read_skip_first = true;
                self.event_lines.push(format!(
                    "EV RD {} {:08x} {:01x} {:01x}",
                    self.cycle_counter, address, avm_burstcount, avm_byteenable
                ));
            }

            if avm_write != 0 && !avm_wait {
                let address = (avm_address << 2).wrapping_add(0);
                self.write_u32(address, avm_writedata, avm_byteenable);
                self.event_lines.push(format!(
                    "EV WR {} {:08x} {:08x} {:01x}",
                    self.cycle_counter, address, avm_writedata, avm_byteenable
                ));
            }

            if io_read_do != 0 {
                self.io_read_done_pending = true;
                let io_address = (self.signal(core, self.io_read_address_idx) & 0xFFFF) as u16;
                let io_value = self.io_read(io_address);
                self.set_signal(core, self.io_read_data_idx, u64::from(io_value));
            }

            if io_write_do != 0 {
                self.io_write_done_pending = true;
                let io_address = (self.signal(core, self.io_write_address_idx) & 0xFFFF) as u16;
                let io_length = (self.signal(core, self.io_write_length_idx) & 0x7) as u8;
                let io_data = (self.signal(core, self.io_write_data_idx) & 0xFFFF_FFFF) as u32;
                self.io_write(io_address, io_data, io_length);
                self.event_lines.push(format!(
                    "EV IO_WR {} {:04x} {:08x} {:01x}",
                    self.cycle_counter, io_address, io_data, io_length
                ));
            }

            self.set_signal(core, self.clk_idx, 0);
            core.evaluate();
            self.cycle_counter = self.cycle_counter.wrapping_add(1);
        }

        n
    }

    fn tick_rising_edge(&self, core: &mut CoreSimulator) {
        for (list_idx, &clk_idx) in core.clock_indices.iter().enumerate() {
            if list_idx < core.prev_clock_values.len() && clk_idx < core.signals.len() {
                core.prev_clock_values[list_idx] = core.signals[clk_idx];
            }
        }

        self.set_signal(core, self.clk_idx, 1);

        if let Some(clk_idx_target) = self.clk_idx {
            for (list_idx, &clk_idx) in core.clock_indices.iter().enumerate() {
                if list_idx < core.prev_clock_values.len() && clk_idx == clk_idx_target {
                    core.prev_clock_values[list_idx] = 0;
                }
            }
        }

        core.tick_forced();
    }

    fn apply_platform_inputs(&self, core: &mut CoreSimulator) {
        let rst_n = if self.cycle_counter >= 4 { 1 } else { 0 };
        self.set_signal(core, self.rst_n_idx, rst_n);
        self.set_signal(core, self.a20_enable_idx, 1);
        self.set_signal(core, self.cache_disable_idx, 1);
        self.set_signal(core, self.interrupt_do_idx, 0);
        self.set_signal(core, self.interrupt_vector_idx, 0);
        self.set_signal(core, self.avm_waitrequest_idx, 0);
        self.set_signal(core, self.dma_address_idx, 0);
        self.set_signal(core, self.dma_16bit_idx, 0);
        self.set_signal(core, self.dma_write_idx, 0);
        self.set_signal(core, self.dma_writedata_idx, 0);
        self.set_signal(core, self.dma_read_idx, 0);
        self.set_signal(core, self.io_read_data_idx, 0);
    }

    fn drive_cycle_inputs(&mut self, core: &mut CoreSimulator) {
        self.set_signal(core, self.avm_readdatavalid_idx, 0);
        self.set_signal(core, self.avm_readdata_idx, 0);
        self.set_signal(core, self.io_read_done_idx, 0);
        self.set_signal(core, self.io_write_done_idx, 0);
        if self.io_read_done_pending {
            self.set_signal(core, self.io_read_done_idx, 1);
            self.io_read_done_pending = false;
        }
        if self.io_write_done_pending {
            self.set_signal(core, self.io_write_done_idx, 1);
            self.io_write_done_pending = false;
        }

        if self.pending_read_words == 0 {
            return;
        }

        let address = self.pending_read_address;
        let value = self.read_u32(address);
        self.set_signal(core, self.avm_readdata_idx, u64::from(value));
        self.set_signal(core, self.avm_readdatavalid_idx, 1);
        if self.pending_read_skip_first {
            self.pending_read_skip_first = false;
        } else {
            self.event_lines.push(format!(
                "EV IF {} {:08x} {:08x}",
                self.cycle_counter, address, value
            ));
        }
        self.pending_read_address = self.pending_read_address.wrapping_add(WORD_BYTES as u32);
        self.pending_read_words = self.pending_read_words.saturating_sub(1);
    }

    fn write_u32(&mut self, address: u32, value: u32, byteenable: u32) {
        if (byteenable & 0x1) != 0 {
            self.memory.insert(address, (value & 0xFF) as u8);
        }
        if (byteenable & 0x2) != 0 {
            self.memory.insert(address.wrapping_add(1), ((value >> 8) & 0xFF) as u8);
        }
        if (byteenable & 0x4) != 0 {
            self.memory.insert(address.wrapping_add(2), ((value >> 16) & 0xFF) as u8);
        }
        if (byteenable & 0x8) != 0 {
            self.memory.insert(address.wrapping_add(3), (value >> 24) as u8);
        }
    }

    fn read_u32(&self, address: u32) -> u32 {
        let b0 = u32::from(self.memory.get(&address).copied().unwrap_or(0));
        let b1 = u32::from(self.memory.get(&address.wrapping_add(1)).copied().unwrap_or(0));
        let b2 = u32::from(self.memory.get(&address.wrapping_add(2)).copied().unwrap_or(0));
        let b3 = u32::from(self.memory.get(&address.wrapping_add(3)).copied().unwrap_or(0));
        b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    fn io_read(&mut self, address: u16) -> u32 {
        match address {
            IO_PORT_KBD_DATA => u32::from(self.keyboard_queue.pop_front().unwrap_or(0)),
            IO_PORT_KBD_STATUS => {
                if self.keyboard_queue.is_empty() {
                    0
                } else {
                    1
                }
            }
            IO_PORT_DISK_COMMAND_STATUS => {
                let ready = if self.disk_stream_remaining > 0 {
                    DISK_STATUS_READY
                } else {
                    0
                };
                u32::from(self.disk_status | ready)
            }
            IO_PORT_DISK_DATA => {
                if self.disk_stream_remaining == 0 {
                    0
                } else {
                    let byte = self.disk_byte_at(self.disk_stream_offset);
                    self.disk_stream_offset = self.disk_stream_offset.saturating_add(1);
                    self.disk_stream_remaining = self.disk_stream_remaining.saturating_sub(1);
                    u32::from(byte)
                }
            }
            _ => 0,
        }
    }

    fn io_write(&mut self, address: u16, value: u32, _length: u8) {
        let byte = (value & 0xFF) as u8;
        match address {
            IO_PORT_DISK_CH => self.disk_ch = byte,
            IO_PORT_DISK_CL => self.disk_cl = byte,
            IO_PORT_DISK_DH => self.disk_dh = byte,
            IO_PORT_DISK_DL => self.disk_dl = byte,
            IO_PORT_DISK_COUNT => self.disk_count = byte,
            IO_PORT_DISK_COMMAND_STATUS => {
                if byte == DISK_COMMAND_READ {
                    self.start_disk_read();
                } else {
                    self.disk_status = DISK_STATUS_ERROR;
                    self.disk_stream_offset = 0;
                    self.disk_stream_remaining = 0;
                }
            }
            _ => {}
        }
    }

    fn start_disk_read(&mut self) {
        let count = usize::from(self.disk_count);
        let sector = u32::from(self.disk_cl & 0x3F);
        let cylinder = u32::from(self.disk_ch) | (u32::from(self.disk_cl & 0xC0) << 2);
        let head = u32::from(self.disk_dh);

        if self.disk_dl != 0 || count == 0 {
            self.disk_status = DISK_STATUS_ERROR;
            self.disk_stream_offset = 0;
            self.disk_stream_remaining = 0;
            return;
        }

        if sector == 0 || sector > DISK_SECTORS_PER_TRACK || head >= DISK_HEADS || cylinder >= DISK_CYLINDERS {
            self.disk_status = DISK_STATUS_ERROR;
            self.disk_stream_offset = 0;
            self.disk_stream_remaining = 0;
            return;
        }

        let lba = ((cylinder * DISK_HEADS + head) * DISK_SECTORS_PER_TRACK) + (sector - 1);
        let start = (lba as usize).saturating_mul(DISK_SECTOR_BYTES);
        let bytes = count.saturating_mul(DISK_SECTOR_BYTES);

        if start.saturating_add(bytes) > DISK_IMAGE_BYTES {
            self.disk_status = DISK_STATUS_ERROR;
            self.disk_stream_offset = 0;
            self.disk_stream_remaining = 0;
            return;
        }

        self.disk_status = 0;
        self.disk_stream_offset = start;
        self.disk_stream_remaining = bytes;
    }

    fn disk_byte_at(&self, offset: usize) -> u8 {
        let address = DISK_IMAGE_BASE.wrapping_add(offset as u32);
        self.memory.get(&address).copied().unwrap_or(0)
    }

    fn signal(&self, core: &CoreSimulator, idx: Option<usize>) -> u64 {
        match idx {
            Some(index) if index < core.signals.len() => core.signals[index],
            _ => 0,
        }
    }

    fn set_signal(&self, core: &mut CoreSimulator, idx: Option<usize>, value: u64) {
        if let Some(index) = idx {
            if index < core.signals.len() {
                core.signals[index] = value;
            }
        }
    }
}
