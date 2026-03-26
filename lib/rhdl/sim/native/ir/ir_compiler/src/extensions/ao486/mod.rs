//! AO486 CPU-top runner scaffold for the IR compiler.
//!
//! This extension intentionally keeps the first slice small: it identifies the
//! imported `ao486` CPU-top signature, provides sparse backing stores for main
//! memory and ROM, and applies safe top-level reset defaults so higher-level
//! runtimes can build on a stable native runner shape.

use std::collections::{HashMap, VecDeque};

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
const POST_INIT_IVT_RETURN_START_EIP: u64 = 0xE0CC;
const POST_INIT_IVT_RETURN_END_EIP: u64 = 0xE0D4;
const DOS_POST_INIT_HELPER_START_EIP: u64 = 0x1080;
const DOS_POST_INIT_HELPER_END_EIP: u64 = 0x10EE;
const POST_INIT_IVT_VECTOR_COUNT: usize = 120;
const POST_INIT_IVT_DEFAULT_SEGMENT: u16 = 0xF000;
const POST_INIT_IVT_DEFAULT_HANDLER: u16 = 0xFF53;
const POST_INIT_IVT_MASTER_PIC_HANDLER: u16 = 0xE9E6;
const POST_INIT_IVT_SLAVE_PIC_HANDLER: u16 = 0xE9EC;
const POST_INIT_IVT_RUNTIME_VECTORS: &[(u8, u16)] = &[
    (0x08, 0xFEA5),
    (0x09, 0xE987),
    (0x0E, 0xEF57),
    (0x10, 0xF065),
    (0x13, 0xE3FE),
    (0x14, 0xE739),
    (0x16, 0xE82E),
    (0x1A, 0xFE6E),
    (0x40, 0xEC59),
    (0x70, 0xFE6E),
    (0x71, 0xE987),
    (0x75, 0xE2C3),
];
const POST_INIT_IVT_INT17_HANDLER: u16 = 0xEFD2;
const POST_INIT_IVT_INT18_HANDLER: u16 = 0x8666;
const POST_INIT_IVT_INT19_HANDLER: u16 = 0xE6F2;
const DOS_INT19_STUB_OFFSET: u16 = 0x0500;
const POST_INIT_IVT_INT12_HANDLER: u16 = 0xF841;
const POST_INIT_IVT_INT11_HANDLER: u16 = 0xF84D;
const POST_INIT_IVT_INT15_HANDLER: u16 = 0xF859;
const DMA_FDC_CHANNEL: u8 = 2;
const FLOPPY_HEADS: usize = 2;
const FLOPPY_SECTORS_PER_TRACK: usize = 18;
const FLOPPY_BYTES_PER_SECTOR: usize = 512;
const DOS_INT13_PORT_AX: u16 = 0x0ED0;
const DOS_INT13_PORT_AX_HI: u16 = 0x0ED1;
const DOS_INT13_PORT_BX: u16 = 0x0ED2;
const DOS_INT13_PORT_BX_HI: u16 = 0x0ED3;
const DOS_INT13_PORT_CX: u16 = 0x0ED4;
const DOS_INT13_PORT_CX_HI: u16 = 0x0ED5;
const DOS_INT13_PORT_DX: u16 = 0x0ED6;
const DOS_INT13_PORT_DX_HI: u16 = 0x0ED7;
const DOS_INT13_PORT_ES: u16 = 0x0ED8;
const DOS_INT13_PORT_ES_HI: u16 = 0x0ED9;
const DOS_INT13_PORT_TRIGGER: u16 = 0x0EDA;
const DOS_INT13_PORT_RESULT: u16 = 0x0EDC;
const DOS_INT13_PORT_RESULT_HI: u16 = 0x0EDD;
const DOS_INT13_PORT_RESULT_BX: u16 = 0x0F10;
const DOS_INT13_PORT_RESULT_BX_HI: u16 = 0x0F11;
const DOS_INT13_PORT_RESULT_CX: u16 = 0x0F12;
const DOS_INT13_PORT_RESULT_CX_HI: u16 = 0x0F13;
const DOS_INT13_PORT_RESULT_DX: u16 = 0x0F14;
const DOS_INT13_PORT_RESULT_DX_HI: u16 = 0x0F15;
const DOS_INT13_PORT_RESULT_FLAGS: u16 = 0x0F16;
const DOS_INT10_PORT_AX: u16 = 0x0EE0;
const DOS_INT10_PORT_AX_HI: u16 = 0x0EE1;
const DOS_INT10_PORT_BX: u16 = 0x0EE2;
const DOS_INT10_PORT_BX_HI: u16 = 0x0EE3;
const DOS_INT10_PORT_CX: u16 = 0x0EE4;
const DOS_INT10_PORT_CX_HI: u16 = 0x0EE5;
const DOS_INT10_PORT_DX: u16 = 0x0EE6;
const DOS_INT10_PORT_DX_HI: u16 = 0x0EE7;
const DOS_INT10_PORT_TRIGGER: u16 = 0x0EE8;
const DOS_INT10_PORT_RESULT_AX: u16 = 0x0EEA;
const DOS_INT10_PORT_RESULT_AX_HI: u16 = 0x0EEB;
const DOS_INT10_PORT_RESULT_BX: u16 = 0x0EEC;
const DOS_INT10_PORT_RESULT_BX_HI: u16 = 0x0EED;
const DOS_INT10_PORT_RESULT_CX: u16 = 0x0EEE;
const DOS_INT10_PORT_RESULT_CX_HI: u16 = 0x0EEF;
const DOS_INT10_PORT_RESULT_DX: u16 = 0x0EF0;
const DOS_INT10_PORT_RESULT_DX_HI: u16 = 0x0EF1;
const DOS_INT10_PORT_BP: u16 = 0x0EF2;
const DOS_INT10_PORT_BP_HI: u16 = 0x0EF3;
const DOS_INT10_PORT_ES: u16 = 0x0EF4;
const DOS_INT10_PORT_ES_HI: u16 = 0x0EF5;
const DOS_INT16_PORT_AX: u16 = 0x0EF8;
const DOS_INT16_PORT_AX_HI: u16 = 0x0EF9;
const DOS_INT16_PORT_TRIGGER: u16 = 0x0EFA;
const DOS_INT16_PORT_RESULT_AX: u16 = 0x0EFC;
const DOS_INT16_PORT_RESULT_AX_HI: u16 = 0x0EFD;
const DOS_INT16_PORT_RESULT_FLAGS: u16 = 0x0EFE;
const DOS_INT1A_PORT_AX: u16 = 0x0F00;
const DOS_INT1A_PORT_AX_HI: u16 = 0x0F01;
const DOS_INT1A_PORT_CX: u16 = 0x0F02;
const DOS_INT1A_PORT_CX_HI: u16 = 0x0F03;
const DOS_INT1A_PORT_DX: u16 = 0x0F04;
const DOS_INT1A_PORT_DX_HI: u16 = 0x0F05;
const DOS_INT1A_PORT_TRIGGER: u16 = 0x0F06;
const DOS_INT1A_PORT_RESULT_AX: u16 = 0x0F08;
const DOS_INT1A_PORT_RESULT_AX_HI: u16 = 0x0F09;
const DOS_INT1A_PORT_RESULT_CX: u16 = 0x0F0A;
const DOS_INT1A_PORT_RESULT_CX_HI: u16 = 0x0F0B;
const DOS_INT1A_PORT_RESULT_DX: u16 = 0x0F0C;
const DOS_INT1A_PORT_RESULT_DX_HI: u16 = 0x0F0D;
const DOS_INT1A_PORT_RESULT_FLAGS: u16 = 0x0F0E;
const TEXT_MODE_BASE: u64 = 0xB8000;
const TEXT_MODE_ROWS: usize = 25;
const TEXT_MODE_COLUMNS: usize = 80;
const TEXT_MODE_BYTES_PER_ROW: usize = TEXT_MODE_COLUMNS * 2;
const TEXT_MODE_PAGE_BYTES: usize = TEXT_MODE_ROWS * TEXT_MODE_BYTES_PER_ROW;
const TEXT_MODE_DEFAULT_ATTR: u8 = 0x07;
const CURSOR_BDA_ADDR: u64 = 0x0450;
const VIDEO_MODE_BDA_ADDR: u64 = 0x0449;
const VIDEO_COLUMNS_BDA_ADDR: u64 = 0x044A;
const VIDEO_PAGE_BDA_ADDR: u64 = 0x0462;
const BIOS_TICK_COUNT_ADDR: u64 = 0x046C;
const BIOS_MIDNIGHT_FLAG_ADDR: u64 = 0x0470;
const BIOS_TICKS_PER_DAY: u32 = 0x0018_00B0;

#[derive(Clone, Copy)]
struct ReadBurst {
    base: u64,
    beat_index: usize,
    beats_total: usize,
    started: bool,
}

pub struct Ao486RunResult {
    pub cycles_run: usize,
    pub key_cleared: bool,
    pub text_dirty: bool,
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
    dma_flip_flop_low: bool,
    dma_ch2_base_addr: u16,
    dma_ch2_current_addr: u16,
    dma_ch2_base_count: u16,
    dma_ch2_current_count: u16,
    dma_ch2_page: u8,
    dma_ch2_mode: u8,
    dma_ch2_masked: bool,
    fdc_dor: u8,
    fdc_data_rate: u8,
    fdc_current_cylinder: u8,
    fdc_last_st0: u8,
    fdc_last_pcn: u8,
    fdc_command: Vec<u8>,
    fdc_expected_len: usize,
    fdc_result: VecDeque<u8>,
    reset_cycles_remaining: usize,
    pending_read_burst: Option<ReadBurst>,
    pending_io_read_data: Option<u32>,
    pending_io_write_ack: bool,
    post_init_ivt_seeded: bool,
    dos_int13_ax: u16,
    dos_int13_bx: u16,
    dos_int13_cx: u16,
    dos_int13_dx: u16,
    dos_int13_es: u16,
    dos_int13_result_ax: u16,
    dos_int13_result_bx: u16,
    dos_int13_result_cx: u16,
    dos_int13_result_dx: u16,
    dos_int13_result_flags: u8,
    dos_int10_ax: u16,
    dos_int10_bx: u16,
    dos_int10_cx: u16,
    dos_int10_dx: u16,
    dos_int10_bp: u16,
    dos_int10_es: u16,
    dos_int10_result_ax: u16,
    dos_int10_result_bx: u16,
    dos_int10_result_cx: u16,
    dos_int10_result_dx: u16,
    dos_int16_ax: u16,
    dos_int16_result_ax: u16,
    dos_int16_result_flags: u8,
    dos_int1a_ax: u16,
    dos_int1a_cx: u16,
    dos_int1a_dx: u16,
    dos_int1a_result_ax: u16,
    dos_int1a_result_cx: u16,
    dos_int1a_result_dx: u16,
    dos_int1a_result_flags: u8,
    keyboard_queue: VecDeque<u16>,
    keyboard_scan_queue: VecDeque<u8>,
    text_dirty: bool,
    prev_io_read_do: bool,
    prev_io_write_do: bool,
    last_io_read_sig: Option<(u16, usize)>,
    last_io_write_sig: Option<(u16, usize, u32)>,
    last_io_read_meta: Option<(u16, usize)>,
    last_io_write_meta: Option<(u16, usize, u32)>,
    last_irq_vector: Option<u8>,
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
            dma_flip_flop_low: true,
            dma_ch2_base_addr: 0,
            dma_ch2_current_addr: 0,
            dma_ch2_base_count: 0,
            dma_ch2_current_count: 0,
            dma_ch2_page: 0,
            dma_ch2_mode: 0,
            dma_ch2_masked: true,
            fdc_dor: 0,
            fdc_data_rate: 0,
            fdc_current_cylinder: 0,
            fdc_last_st0: 0x80,
            fdc_last_pcn: 0,
            fdc_command: Vec::new(),
            fdc_expected_len: 0,
            fdc_result: VecDeque::new(),
            reset_cycles_remaining: 1,
            pending_read_burst: None,
            pending_io_read_data: None,
            pending_io_write_ack: false,
            post_init_ivt_seeded: false,
            dos_int13_ax: 0,
            dos_int13_bx: 0,
            dos_int13_cx: 0,
            dos_int13_dx: 0,
            dos_int13_es: 0,
            dos_int13_result_ax: 0,
            dos_int13_result_bx: 0,
            dos_int13_result_cx: 0,
            dos_int13_result_dx: 0,
            dos_int13_result_flags: 0,
            dos_int10_ax: 0,
            dos_int10_bx: 0,
            dos_int10_cx: 0,
            dos_int10_dx: 0,
            dos_int10_bp: 0,
            dos_int10_es: 0,
            dos_int10_result_ax: 0,
            dos_int10_result_bx: 0,
            dos_int10_result_cx: 0,
            dos_int10_result_dx: 0,
            dos_int16_ax: 0,
            dos_int16_result_ax: 0,
            dos_int16_result_flags: 0,
            dos_int1a_ax: 0,
            dos_int1a_cx: 0,
            dos_int1a_dx: 0,
            dos_int1a_result_ax: 0,
            dos_int1a_result_cx: 0,
            dos_int1a_result_dx: 0,
            dos_int1a_result_flags: 0,
            keyboard_queue: VecDeque::new(),
            keyboard_scan_queue: VecDeque::new(),
            text_dirty: false,
            prev_io_read_do: false,
            prev_io_write_do: false,
            last_io_read_sig: None,
            last_io_write_sig: None,
            last_io_read_meta: None,
            last_io_write_meta: None,
            last_irq_vector: None,
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
        self.dma_flip_flop_low = true;
        self.dma_ch2_base_addr = 0;
        self.dma_ch2_current_addr = 0;
        self.dma_ch2_base_count = 0;
        self.dma_ch2_current_count = 0;
        self.dma_ch2_page = 0;
        self.dma_ch2_mode = 0;
        self.dma_ch2_masked = true;
        self.fdc_dor = 0;
        self.fdc_data_rate = 0;
        self.fdc_current_cylinder = 0;
        self.fdc_last_st0 = 0x80;
        self.fdc_last_pcn = 0;
        self.fdc_command.clear();
        self.fdc_expected_len = 0;
        self.fdc_result.clear();
        self.pending_read_burst = None;
        self.pending_io_read_data = None;
        self.pending_io_write_ack = false;
        self.post_init_ivt_seeded = false;
        self.dos_int13_ax = 0;
        self.dos_int13_bx = 0;
        self.dos_int13_cx = 0;
        self.dos_int13_dx = 0;
        self.dos_int13_es = 0;
        self.dos_int13_result_ax = 0;
        self.dos_int13_result_bx = 0;
        self.dos_int13_result_cx = 0;
        self.dos_int13_result_dx = 0;
        self.dos_int13_result_flags = 0;
        self.dos_int10_ax = 0;
        self.dos_int10_bx = 0;
        self.dos_int10_cx = 0;
        self.dos_int10_dx = 0;
        self.dos_int10_bp = 0;
        self.dos_int10_es = 0;
        self.dos_int10_result_ax = 0;
        self.dos_int10_result_bx = 0;
        self.dos_int10_result_cx = 0;
        self.dos_int10_result_dx = 0;
        self.dos_int16_ax = 0;
        self.dos_int16_result_ax = 0;
        self.dos_int16_result_flags = 0;
        self.dos_int1a_ax = 0;
        self.dos_int1a_cx = 0;
        self.dos_int1a_dx = 0;
        self.dos_int1a_result_ax = 0;
        self.dos_int1a_result_cx = 0;
        self.dos_int1a_result_dx = 0;
        self.dos_int1a_result_flags = 0;
        self.keyboard_queue.clear();
        self.keyboard_scan_queue.clear();
        self.text_dirty = false;
        self.prev_io_read_do = false;
        self.prev_io_write_do = false;
        self.last_io_read_sig = None;
        self.last_io_write_sig = None;
        self.last_io_read_meta = None;
        self.last_io_write_meta = None;
        self.last_irq_vector = None;
        self.write_bios_tick_count(0);
        self.memory.insert(BIOS_MIDNIGHT_FLAG_ADDR, 0);
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

    pub fn last_io_read_probe(&self) -> u64 {
        let Some((address, length)) = self.last_io_read_meta else {
            return 0;
        };
        ((address as u64) << 8) | (length as u64 & 0xFF)
    }

    pub fn last_io_write_meta_probe(&self) -> u64 {
        let Some((address, length, _data)) = self.last_io_write_meta else {
            return 0;
        };
        ((address as u64) << 8) | (length as u64 & 0xFF)
    }

    pub fn last_io_write_data_probe(&self) -> u64 {
        self.last_io_write_meta
            .map(|(_, _, data)| data as u64)
            .unwrap_or(0)
    }

    pub fn last_irq_vector_probe(&self) -> u64 {
        self.last_irq_vector.map(|value| value as u64).unwrap_or(0)
    }

    pub fn dos_int13_state_probe(&self) -> u64 {
        (self.dos_int13_ax as u64)
            | ((self.dos_int13_result_ax as u64) << 16)
            | ((self.dos_int13_result_flags as u64) << 32)
    }

    pub fn dos_int13_bx_probe(&self) -> u64 {
        self.dos_int13_bx as u64
    }

    pub fn dos_int13_cx_probe(&self) -> u64 {
        self.dos_int13_cx as u64
    }

    pub fn dos_int13_dx_probe(&self) -> u64 {
        self.dos_int13_dx as u64
    }

    pub fn dos_int13_es_probe(&self) -> u64 {
        self.dos_int13_es as u64
    }

    pub fn dos_int10_state_probe(&self) -> u64 {
        (self.dos_int10_ax as u64) | ((self.dos_int10_result_ax as u64) << 16)
    }

    pub fn dos_int16_state_probe(&self) -> u64 {
        (self.dos_int16_ax as u64)
            | ((self.dos_int16_result_ax as u64) << 16)
            | ((self.dos_int16_result_flags as u64) << 32)
    }

    pub fn dos_int1a_state_probe(&self) -> u64 {
        (self.dos_int1a_ax as u64)
            | ((self.dos_int1a_result_ax as u64) << 16)
            | ((self.dos_int1a_result_flags as u64) << 32)
    }

    pub fn run_cycles(
        &mut self,
        core: &mut CoreSimulator,
        n: usize,
        key_data: u8,
        key_ready: bool,
    ) -> Ao486RunResult {
        if !core.compiled {
            return Ao486RunResult {
                cycles_run: 0,
                key_cleared: false,
                text_dirty: false,
            };
        }

        self.text_dirty = false;
        let key_cleared = if key_ready {
            self.enqueue_keyboard_byte(key_data)
        } else {
            false
        };

        for _ in 0..n {
            let reset_active = self.reset_cycles_remaining > 0;
            let irq_vector = if reset_active {
                None
            } else {
                self.active_irq_vector()
            };
            if let Some(vector) = irq_vector {
                self.last_irq_vector = Some(vector);
            }
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
            let retargeted_code_burst = self.retarget_code_burst_if_needed(core);
            if retargeted_code_burst {
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
            self.advance_read_burst(if retargeted_code_burst {
                false
            } else {
                read_response.is_some()
            });
            self.reset_cycles_remaining = self.reset_cycles_remaining.saturating_sub(1);
            self.prev_io_read_do = current_io_read_do;
            self.prev_io_write_do = current_io_write_do;
        }

        Ao486RunResult {
            cycles_run: n,
            key_cleared,
            text_dirty: self.text_dirty,
        }
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

        let is_code_read = self.current_avm_read_is_code_burst(core);
        let beats_total = if is_code_read {
            8
        } else {
            (self.signal(core, self.avm_burstcount_idx) as usize).max(1)
        };
        let base = if is_code_read {
            self.code_read_address_idx
                .map(|idx| self.signal(core, idx) as u64 & !0x3)
                .unwrap_or_else(|| (self.signal(core, self.avm_address_idx) as u64) << 2)
        } else {
            (self.signal(core, self.avm_address_idx) as u64) << 2
        };
        self.pending_read_burst = Some(ReadBurst {
            base,
            beat_index: 0,
            beats_total,
            started: false,
        });
    }

    fn retarget_code_burst_if_needed(&mut self, core: &CoreSimulator) -> bool {
        let Some(code_read_address_idx) = self.code_read_address_idx else {
            return false;
        };
        if !self.current_avm_read_is_code_burst(core) {
            return false;
        }

        let target = self.signal(core, code_read_address_idx) as u64 & !0x3;
        let Some(read_burst) = self.pending_read_burst.as_mut() else {
            return false;
        };
        if read_burst.beats_total != 8 {
            return false;
        }
        if read_burst.started {
            return false;
        }
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

    fn current_avm_read_is_code_burst(&self, core: &CoreSimulator) -> bool {
        self.signal(core, self.avm_read_idx) != 0 && (self.signal(core, self.avm_burstcount_idx) as usize) >= 8
    }

    fn queue_io_requests_if_needed(
        &mut self,
        core: &CoreSimulator,
        current_io_read_do: bool,
        current_io_write_do: bool,
    ) {
        if !current_io_read_do {
            self.last_io_read_sig = None;
        }

        let read_addr = (self.signal(core, self.io_read_address_idx) & 0xFFFF) as u16;
        let read_len = ((self.signal(core, self.io_read_length_idx) & 0x7) as usize).max(1);
        let read_sig = (read_addr, read_len);
        let new_read = current_io_read_do
            && self.pending_io_read_data.is_none()
            && (!self.prev_io_read_do || self.last_io_read_sig != Some(read_sig));

        if new_read {
            self.pending_io_read_data = Some(self.read_io_value(read_addr, read_len));
            self.last_io_read_sig = Some(read_sig);
            self.last_io_read_meta = Some(read_sig);
        }

        if !current_io_write_do {
            self.last_io_write_sig = None;
        }

        let write_addr = (self.signal(core, self.io_write_address_idx) & 0xFFFF) as u16;
        let write_len = ((self.signal(core, self.io_write_length_idx) & 0x7) as usize).max(1);
        let write_data = (self.signal(core, self.io_write_data_idx) & 0xFFFF_FFFF) as u32;
        let write_sig = (write_addr, write_len, write_data);
        let new_write = current_io_write_do
            && !self.pending_io_write_ack
            && (!self.prev_io_write_do || self.last_io_write_sig != Some(write_sig));

        if new_write {
            self.write_io_value(write_addr, write_len, write_data);
            self.pending_io_write_ack = true;
            self.last_io_write_sig = Some(write_sig);
            self.last_io_write_meta = Some(write_sig);
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
            self.increment_bios_tick_count();
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
                if (POST_INIT_IVT_START_EIP..=POST_INIT_IVT_END_EIP).contains(&value)
                    || (POST_INIT_IVT_RETURN_START_EIP..=POST_INIT_IVT_RETURN_END_EIP).contains(&value)
                    || (DOS_POST_INIT_HELPER_START_EIP..=DOS_POST_INIT_HELPER_END_EIP)
                        .contains(&value)
                {
                    Some(value)
                } else {
                    None
                }
            })
            .or_else(|| {
                self.decode_eip_idx.and_then(|idx| {
                    let value = self.signal(core, idx) as u64;
                    if (POST_INIT_IVT_START_EIP..=POST_INIT_IVT_END_EIP).contains(&value)
                        || (POST_INIT_IVT_RETURN_START_EIP..=POST_INIT_IVT_RETURN_END_EIP).contains(&value)
                        || (DOS_POST_INIT_HELPER_START_EIP..=DOS_POST_INIT_HELPER_END_EIP)
                            .contains(&value)
                    {
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
            self.write_interrupt_vector(
                vector as u8,
                POST_INIT_IVT_DEFAULT_SEGMENT,
                POST_INIT_IVT_DEFAULT_HANDLER,
            );
        }
        for vector in 0x08u8..=0x0Fu8 {
            self.write_interrupt_vector(
                vector,
                POST_INIT_IVT_DEFAULT_SEGMENT,
                POST_INIT_IVT_MASTER_PIC_HANDLER,
            );
        }
        for vector in 0x70u8..=0x77u8 {
            self.write_interrupt_vector(
                vector,
                POST_INIT_IVT_DEFAULT_SEGMENT,
                POST_INIT_IVT_SLAVE_PIC_HANDLER,
            );
        }
        self.write_interrupt_vector(0x11, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT11_HANDLER);
        self.write_interrupt_vector(0x12, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT12_HANDLER);
        self.write_interrupt_vector(0x15, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT15_HANDLER);
        self.write_interrupt_vector(0x17, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT17_HANDLER);
        self.write_interrupt_vector(0x18, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT18_HANDLER);
        for (vector, offset) in POST_INIT_IVT_RUNTIME_VECTORS {
            self.write_interrupt_vector(*vector, POST_INIT_IVT_DEFAULT_SEGMENT, *offset);
        }
        if self.disk.is_empty() {
            self.write_interrupt_vector(0x19, POST_INIT_IVT_DEFAULT_SEGMENT, POST_INIT_IVT_INT19_HANDLER);
        } else {
            self.write_interrupt_vector(0x19, 0x0000, DOS_INT19_STUB_OFFSET);
        }
        self.clear_interrupt_vector(0x1D);
        self.clear_interrupt_vector(0x1F);
        for vector in 0x60u8..=0x67u8 {
            self.clear_interrupt_vector(vector);
        }
        for vector in 0x78u16..=0xFFu16 {
            self.clear_interrupt_vector(vector as u8);
        }
        self.pic_master_base = 0x08;
        self.pic_slave_base = 0x70;
        self.pic_master_mask = 0xB8;
        self.pic_slave_mask = 0x9F;
        self.pic_master_pending = 0;
        self.pic_master_in_service = 0;
        self.pit_control = 0x36;
        self.pit_low_byte = None;
        self.set_pit_reload(0);
        self.post_init_ivt_seeded = true;
    }

    fn write_interrupt_vector(&mut self, vector: u8, segment: u16, offset: u16) {
        let base = vector as u64 * 4;
        self.memory.insert(base, (offset & 0x00FF) as u8);
        self.memory.insert(base + 1, ((offset >> 8) & 0x00FF) as u8);
        self.memory.insert(base + 2, (segment & 0x00FF) as u8);
        self.memory.insert(base + 3, ((segment >> 8) & 0x00FF) as u8);
    }

    fn clear_interrupt_vector(&mut self, vector: u8) {
        self.write_interrupt_vector(vector, 0, 0);
    }

    fn read_io_value(&mut self, address: u16, length: usize) -> u32 {
        let mut value = 0u32;
        for offset in 0..length.min(4) {
            let byte = self.read_io_byte(address.wrapping_add(offset as u16)) as u32;
            value |= byte << (offset * 8);
        }
        value
    }

    fn read_io_byte(&mut self, address: u16) -> u8 {
        match address {
            0x0060 => self.read_keyboard_data_port(),
            0x0061 => 0x20,
            // Match the reference ps2 RTL reset state:
            // bit4=1 (keyboard inhibit), bit3=1 (last write was command),
            // bit2=0 (system flag cleared), bit1=0 (input buffer empty),
            // bit0 reflects whether a queued key is waiting on port 0x60.
            0x0064 => self.keyboard_status_port(),
            0x0070 => self.cmos_index & 0x7F,
            0x0071 => self.cmos[(self.cmos_index & 0x7F) as usize],
            0x0020 => self.pic_master_pending,
            0x0021 => self.pic_master_mask,
            0x00A0 => 0x00,
            0x00A1 => self.pic_slave_mask,
            0x0040 => (self.pit_counter & 0xFF) as u8,
            0x0041 | 0x0042 => 0x00,
            0x0043 => self.pit_control,
            0x03F2 => self.fdc_dor,
            0x03F4 => self.fdc_main_status(),
            0x03F5 => self.fdc_result.pop_front().unwrap_or(0),
            0x03F7 => self.fdc_disk_change_status(),
            DOS_INT13_PORT_RESULT => (self.dos_int13_result_ax & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_HI => ((self.dos_int13_result_ax >> 8) & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_BX => (self.dos_int13_result_bx & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_BX_HI => ((self.dos_int13_result_bx >> 8) & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_CX => (self.dos_int13_result_cx & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_CX_HI => ((self.dos_int13_result_cx >> 8) & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_DX => (self.dos_int13_result_dx & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_DX_HI => ((self.dos_int13_result_dx >> 8) & 0x00FF) as u8,
            DOS_INT13_PORT_RESULT_FLAGS => self.dos_int13_result_flags & 0x01,
            DOS_INT10_PORT_RESULT_AX => (self.dos_int10_result_ax & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_AX_HI => ((self.dos_int10_result_ax >> 8) & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_BX => (self.dos_int10_result_bx & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_BX_HI => ((self.dos_int10_result_bx >> 8) & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_CX => (self.dos_int10_result_cx & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_CX_HI => ((self.dos_int10_result_cx >> 8) & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_DX => (self.dos_int10_result_dx & 0x00FF) as u8,
            DOS_INT10_PORT_RESULT_DX_HI => ((self.dos_int10_result_dx >> 8) & 0x00FF) as u8,
            DOS_INT16_PORT_RESULT_AX => (self.dos_int16_result_ax & 0x00FF) as u8,
            DOS_INT16_PORT_RESULT_AX_HI => ((self.dos_int16_result_ax >> 8) & 0x00FF) as u8,
            DOS_INT16_PORT_RESULT_FLAGS => self.dos_int16_result_flags,
            DOS_INT1A_PORT_RESULT_AX => (self.dos_int1a_result_ax & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_AX_HI => ((self.dos_int1a_result_ax >> 8) & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_CX => (self.dos_int1a_result_cx & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_CX_HI => ((self.dos_int1a_result_cx >> 8) & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_DX => (self.dos_int1a_result_dx & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_DX_HI => ((self.dos_int1a_result_dx >> 8) & 0x00FF) as u8,
            DOS_INT1A_PORT_RESULT_FLAGS => self.dos_int1a_result_flags,
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
                DOS_INT13_PORT_AX => self.dos_int13_ax = (self.dos_int13_ax & 0xFF00) | (byte as u16),
                DOS_INT13_PORT_AX_HI => {
                    self.dos_int13_ax = (self.dos_int13_ax & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT13_PORT_BX => self.dos_int13_bx = (self.dos_int13_bx & 0xFF00) | (byte as u16),
                DOS_INT13_PORT_BX_HI => {
                    self.dos_int13_bx = (self.dos_int13_bx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT13_PORT_CX => self.dos_int13_cx = (self.dos_int13_cx & 0xFF00) | (byte as u16),
                DOS_INT13_PORT_CX_HI => {
                    self.dos_int13_cx = (self.dos_int13_cx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT13_PORT_DX => self.dos_int13_dx = (self.dos_int13_dx & 0xFF00) | (byte as u16),
                DOS_INT13_PORT_DX_HI => {
                    self.dos_int13_dx = (self.dos_int13_dx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT13_PORT_ES => self.dos_int13_es = (self.dos_int13_es & 0xFF00) | (byte as u16),
                DOS_INT13_PORT_ES_HI => {
                    self.dos_int13_es = (self.dos_int13_es & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT13_PORT_TRIGGER => self.execute_dos_int13_request(),
                DOS_INT10_PORT_AX => self.dos_int10_ax = (self.dos_int10_ax & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_AX_HI => {
                    self.dos_int10_ax = (self.dos_int10_ax & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_BX => self.dos_int10_bx = (self.dos_int10_bx & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_BX_HI => {
                    self.dos_int10_bx = (self.dos_int10_bx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_CX => self.dos_int10_cx = (self.dos_int10_cx & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_CX_HI => {
                    self.dos_int10_cx = (self.dos_int10_cx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_DX => self.dos_int10_dx = (self.dos_int10_dx & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_DX_HI => {
                    self.dos_int10_dx = (self.dos_int10_dx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_BP => self.dos_int10_bp = (self.dos_int10_bp & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_BP_HI => {
                    self.dos_int10_bp = (self.dos_int10_bp & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_ES => self.dos_int10_es = (self.dos_int10_es & 0xFF00) | (byte as u16),
                DOS_INT10_PORT_ES_HI => {
                    self.dos_int10_es = (self.dos_int10_es & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT10_PORT_TRIGGER => self.execute_dos_int10_request(),
                DOS_INT16_PORT_AX => self.dos_int16_ax = (self.dos_int16_ax & 0xFF00) | (byte as u16),
                DOS_INT16_PORT_AX_HI => {
                    self.dos_int16_ax = (self.dos_int16_ax & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT16_PORT_TRIGGER => self.execute_dos_int16_request(),
                DOS_INT1A_PORT_AX => self.dos_int1a_ax = (self.dos_int1a_ax & 0xFF00) | (byte as u16),
                DOS_INT1A_PORT_AX_HI => {
                    self.dos_int1a_ax = (self.dos_int1a_ax & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT1A_PORT_CX => self.dos_int1a_cx = (self.dos_int1a_cx & 0xFF00) | (byte as u16),
                DOS_INT1A_PORT_CX_HI => {
                    self.dos_int1a_cx = (self.dos_int1a_cx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT1A_PORT_DX => self.dos_int1a_dx = (self.dos_int1a_dx & 0xFF00) | (byte as u16),
                DOS_INT1A_PORT_DX_HI => {
                    self.dos_int1a_dx = (self.dos_int1a_dx & 0x00FF) | ((byte as u16) << 8)
                }
                DOS_INT1A_PORT_TRIGGER => self.execute_dos_int1a_request(),
                0x0004 => self.write_dma_channel2_addr(byte),
                0x0005 => self.write_dma_channel2_count(byte),
                0x0020 => {
                    if byte & 0x20 != 0 {
                        self.pic_master_in_service = clear_lowest_set_bit(self.pic_master_in_service);
                    }
                }
                0x0021 => self.pic_master_mask = byte,
                0x00A0 => {},
                0x00A1 => self.pic_slave_mask = byte,
                0x0040 => self.write_pit_counter_byte(byte),
                0x0043 => self.write_pit_control(byte),
                0x0070 => self.cmos_index = byte & 0x7F,
                0x0071 => self.cmos[(self.cmos_index & 0x7F) as usize] = byte,
                0x0081 => self.dma_ch2_page = byte,
                0x000A => self.write_dma_mask(byte),
                0x000B => self.dma_ch2_mode = byte,
                0x000C => self.dma_flip_flop_low = true,
                0x000D => self.reset_dma_controller(),
                0x00DA => {},
                0x00D4 => {},
                0x03F2 => self.write_fdc_dor(byte),
                0x03F5 => self.write_fdc_data(byte),
                0x03F7 => self.fdc_data_rate = byte,
                _ => {}
            }
        }
    }

    fn execute_dos_int13_request(&mut self) {
        let function = ((self.dos_int13_ax >> 8) & 0x00FF) as u8;
        let drive = self.normalize_dos_floppy_drive((self.dos_int13_dx & 0x00FF) as u8);
        self.dos_int13_result_bx = self.dos_int13_bx;
        self.dos_int13_result_cx = self.dos_int13_cx;
        self.dos_int13_result_dx = self.dos_int13_dx;
        self.dos_int13_result_flags = 0;
        match function {
            0x00 => {
                let Some(drive) = drive else {
                    self.dos_int13_result_ax = 0x0100;
                    self.dos_int13_result_flags = 1;
                    self.write_bios_diskette_result_bytes(0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
                    return;
                };

                self.dos_int13_result_ax = 0;
                self.dos_int13_result_flags = 0;
                self.write_bios_diskette_result_bytes(0x00, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
                self.write_bios_floppy_current_cylinder(drive, 0);
                self.fdc_current_cylinder = 0;
                self.fdc_last_st0 = 0x20;
                self.fdc_last_pcn = 0;
            }
            0x01 => {
                self.dos_int13_result_ax = self.execute_dos_int13_read_status();
            }
            0x02 => {
                self.dos_int13_result_ax = self.execute_dos_int13_read();
            }
            0x08 => {
                self.dos_int13_result_ax = self.execute_dos_int13_get_parameters();
            }
            0x15 => {
                self.dos_int13_result_ax = self.execute_dos_int13_get_drive_type();
            }
            0x16 => {
                self.dos_int13_result_ax = self.execute_dos_int13_get_change_line_status();
            }
            _ => {
                self.dos_int13_result_ax = 0x0100;
                self.dos_int13_result_flags = 1;
                self.memory.insert(0x0441, 0x01);
            }
        }
    }

    fn execute_dos_int13_read_status(&mut self) -> u16 {
        let status = *self.memory.get(&0x0441).unwrap_or(&0) as u16;
        self.dos_int13_result_flags = if status == 0 { 0 } else { 1 };
        status << 8
    }

    fn execute_dos_int13_read(&mut self) -> u16 {
        let count = (self.dos_int13_ax & 0x00FF) as usize;
        let buffer = ((self.dos_int13_es as usize) << 4).saturating_add(self.dos_int13_bx as usize);
        let cl = (self.dos_int13_cx & 0x00FF) as u8;
        let ch = ((self.dos_int13_cx >> 8) & 0x00FF) as u8;
        let Some(drive) = self.normalize_dos_floppy_drive((self.dos_int13_dx & 0x00FF) as u8) else {
            self.write_bios_diskette_result_bytes(0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
            self.dos_int13_result_flags = 1;
            return 0x0100;
        };
        let head = ((self.dos_int13_dx >> 8) & 0x00FF) as usize;
        let sector = (cl & 0x3F) as usize;
        // The DOS floppy bootstrap trace on AO486 uses CL[7:6] as don't-care
        // bits on its private INT 13h path. Matching the existing FDC path and the
        // runner bootstrap requires treating CH as the effective floppy cylinder.
        let cylinder = ch as usize;

        // The staged DOS loader on the AO486 runner path sometimes
        // reissues later CHS reads with DL=1 even though only one mounted
        // floppy image exists. Treat A: and B: as aliases for the same image
        // on this private DOS bridge so the loader can keep walking the same
        // boot media instead of spinning on a synthetic "drive not ready"
        // error.
        if count == 0 || head >= FLOPPY_HEADS || sector == 0 || sector > FLOPPY_SECTORS_PER_TRACK {
            self.write_bios_diskette_result_bytes(0x01, 0x00, 0x00, 0x00, cylinder as u8, head as u8, sector as u8, 0);
            self.dos_int13_result_flags = 1;
            return 0x0100;
        }

        let start_lba = ((cylinder * FLOPPY_HEADS) + head) * FLOPPY_SECTORS_PER_TRACK + (sector - 1);
        let byte_count = count.saturating_mul(FLOPPY_BYTES_PER_SECTOR);
        let disk_offset = start_lba.saturating_mul(FLOPPY_BYTES_PER_SECTOR);

        for index in 0..byte_count {
            let value = *self.disk.get(&((disk_offset + index) as u64)).unwrap_or(&0);
            self.memory.insert((buffer + index) as u64, value);
        }

        let end_sector = sector.saturating_add(count.saturating_sub(1)) as u8;
        let st0 = 0x20 | ((head as u8) & 0x01);
        self.write_bios_diskette_result_bytes(0x00, st0, 0x00, 0x00, cylinder as u8, head as u8, end_sector, 0x02);
        self.write_bios_floppy_current_cylinder(drive, cylinder as u8);
        self.fdc_current_cylinder = cylinder as u8;
        self.fdc_last_st0 = st0;
        self.fdc_last_pcn = self.fdc_current_cylinder;
        self.dos_int13_result_flags = 0;
        count as u16
    }

    fn write_bios_diskette_result_bytes(
        &mut self,
        status: u8,
        st0: u8,
        st1: u8,
        st2: u8,
        cylinder: u8,
        head: u8,
        sector: u8,
        size_code: u8,
    ) {
        self.memory.insert(0x0441, status);
        self.memory.insert(0x0442, st0);
        self.memory.insert(0x0443, st1);
        self.memory.insert(0x0444, st2);
        self.memory.insert(0x0445, cylinder);
        self.memory.insert(0x0446, head);
        self.memory.insert(0x0447, sector);
        self.memory.insert(0x0448, size_code);
    }

    fn write_bios_floppy_current_cylinder(&mut self, drive: u8, cylinder: u8) {
        self.memory.insert(0x0494 + drive as u64, cylinder);
    }

    fn execute_dos_int13_get_parameters(&mut self) -> u16 {
        if self
            .normalize_dos_floppy_drive((self.dos_int13_dx & 0x00FF) as u8)
            .is_none()
        {
            self.memory.insert(0x0441, 0x01);
            self.dos_int13_result_flags = 1;
            return 0x0100;
        }

        let max_cylinder = 79u16;
        let sectors_per_track = FLOPPY_SECTORS_PER_TRACK as u16;
        let max_head = (FLOPPY_HEADS - 1) as u16;

        self.dos_int13_result_bx = 0x0400;
        self.dos_int13_result_cx =
            ((max_cylinder & 0x00FF) << 8) | (((max_cylinder >> 2) & 0x00C0) | sectors_per_track);
        self.dos_int13_result_dx = (max_head << 8) | 0x0002;

        self.memory.insert(0x0441, 0x00);
        self.dos_int13_result_flags = 0;
        0
    }

    fn execute_dos_int13_get_drive_type(&mut self) -> u16 {
        let Some(drive) = self.normalize_dos_floppy_drive((self.dos_int13_dx & 0x00FF) as u8) else {
            self.dos_int13_result_flags = 1;
            return 0;
        };

        let mut drive_type = self.cmos[0x10];
        if drive == 0 {
            drive_type >>= 4;
        } else {
            drive_type &= 0x0F;
        }

        self.dos_int13_result_flags = 0;
        if drive_type == 0 { 0 } else { 0x0100 }
    }

    fn execute_dos_int13_get_change_line_status(&mut self) -> u16 {
        if self
            .normalize_dos_floppy_drive((self.dos_int13_dx & 0x00FF) as u8)
            .is_none()
        {
            self.memory.insert(0x0441, 0x01);
            self.dos_int13_result_flags = 1;
            return 0x0100;
        }

        self.memory.insert(0x0441, 0x06);
        self.dos_int13_result_flags = 1;
        0x0600
    }

    fn execute_dos_int10_request(&mut self) {
        self.dos_int10_result_ax = self.dos_int10_ax;
        self.dos_int10_result_bx = self.dos_int10_bx;
        self.dos_int10_result_cx = self.dos_int10_cx;
        self.dos_int10_result_dx = self.dos_int10_dx;

        let function = ((self.dos_int10_ax >> 8) & 0x00FF) as u8;
        let page = ((self.dos_int10_bx >> 8) & 0x00FF) as u8;
        match function {
            0x00 => {
                self.initialize_text_mode((self.dos_int10_ax & 0x00FF) as u8);
            }
            0x01 => {}
            0x02 => {
                let row = ((self.dos_int10_dx >> 8) & 0x00FF) as u8;
                let col = (self.dos_int10_dx & 0x00FF) as u8;
                self.set_cursor_position_for_page(page, row, col);
            }
            0x03 => {
                let (row, col) = self.cursor_position_for_page(page);
                self.dos_int10_result_cx = 0x0607;
                self.dos_int10_result_dx = ((row as u16) << 8) | col as u16;
            }
            0x05 => {
                self.set_active_video_page((self.dos_int10_ax & 0x00FF) as u8);
            }
            0x06 | 0x07 => {
                if (self.dos_int10_ax & 0x00FF) == 0 {
                    let active_page = self.active_video_page();
                    self.clear_text_screen_for_page(active_page);
                    self.set_cursor_position_for_page(active_page, 0, 0);
                }
            }
            0x08 => {
                let (row, col) = self.cursor_position_for_page(page);
                let (ch, attr) = self.read_text_cell(page, row as usize, col as usize);
                self.dos_int10_result_ax = ((attr as u16) << 8) | ch as u16;
            }
            0x09 => {
                self.write_repeated_char(
                    page,
                    (self.dos_int10_ax & 0x00FF) as u8,
                    Some((self.dos_int10_bx & 0x00FF) as u8),
                    self.dos_int10_cx as usize,
                    false,
                );
            }
            0x0A => {
                self.write_repeated_char(
                    page,
                    (self.dos_int10_ax & 0x00FF) as u8,
                    None,
                    self.dos_int10_cx as usize,
                    false,
                );
            }
            0x0E => {
                self.video_teletype(page, (self.dos_int10_ax & 0x00FF) as u8);
            }
            0x0F => {
                self.dos_int10_result_ax = ((TEXT_MODE_COLUMNS as u16) << 8) | 0x03;
                self.dos_int10_result_bx =
                    (self.dos_int10_result_bx & 0x00FF) | ((self.active_video_page() as u16) << 8);
            }
            0x13 => {
                let mode = (self.dos_int10_ax & 0x00FF) as u8;
                let row = ((self.dos_int10_dx >> 8) & 0x00FF) as u8;
                let col = (self.dos_int10_dx & 0x00FF) as u8;
                self.write_string(
                    page,
                    row,
                    col,
                    self.dos_int10_cx as usize,
                    (self.dos_int10_bx & 0x00FF) as u8,
                    mode & 0x02 != 0,
                    mode & 0x01 != 0,
                    self.dos_int10_es,
                    self.dos_int10_bp,
                );
            }
            _ => {}
        }
    }

    fn execute_dos_int16_request(&mut self) {
        self.dos_int16_result_ax = 0;
        self.dos_int16_result_flags = 0;

        let function = ((self.dos_int16_ax >> 8) & 0x00FF) as u8;
        match function {
            0x00 | 0x10 => {
                if let Some(key) = self.pop_keyboard_word() {
                    self.dos_int16_result_ax = key;
                    self.dos_int16_result_flags = 1;
                }
            }
            0x01 | 0x11 => {
                if let Some(key) = self.keyboard_queue.front().copied() {
                    self.dos_int16_result_ax = key;
                    self.dos_int16_result_flags = 1;
                }
            }
            0x02 => {
                self.dos_int16_result_ax = 0;
                self.dos_int16_result_flags = 1;
            }
            _ => {}
        }
    }

    fn execute_dos_int1a_request(&mut self) {
        self.dos_int1a_result_ax = 0;
        self.dos_int1a_result_cx = 0;
        self.dos_int1a_result_dx = 0;
        self.dos_int1a_result_flags = 0;

        let function = ((self.dos_int1a_ax >> 8) & 0x00FF) as u8;
        match function {
            0x00 => {
                let ticks = self.read_bios_tick_count();
                let midnight = *self.memory.get(&BIOS_MIDNIGHT_FLAG_ADDR).unwrap_or(&0);
                self.dos_int1a_result_ax = midnight as u16;
                self.dos_int1a_result_cx = ((ticks >> 16) & 0xFFFF) as u16;
                self.dos_int1a_result_dx = (ticks & 0xFFFF) as u16;
                self.memory.insert(BIOS_MIDNIGHT_FLAG_ADDR, 0);
            }
            0x01 => {
                let ticks = ((self.dos_int1a_cx as u32) << 16) | self.dos_int1a_dx as u32;
                self.write_bios_tick_count(ticks);
                self.memory.insert(BIOS_MIDNIGHT_FLAG_ADDR, 0);
            }
            0x02 => {
                self.dos_int1a_result_cx = ((self.cmos[0x04] as u16) << 8) | self.cmos[0x02] as u16;
                self.dos_int1a_result_dx = (self.cmos[0x00] as u16) << 8;
            }
            0x04 => {
                self.dos_int1a_result_cx = ((self.cmos[0x32] as u16) << 8) | self.cmos[0x09] as u16;
                self.dos_int1a_result_dx = ((self.cmos[0x08] as u16) << 8) | self.cmos[0x07] as u16;
            }
            _ => {
                self.dos_int1a_result_ax = self.dos_int1a_ax;
                self.dos_int1a_result_cx = self.dos_int1a_cx;
                self.dos_int1a_result_dx = self.dos_int1a_dx;
            }
        }
    }

    fn initialize_text_mode(&mut self, mode: u8) {
        self.memory.insert(VIDEO_MODE_BDA_ADDR, mode);
        self.memory
            .insert(VIDEO_COLUMNS_BDA_ADDR, (TEXT_MODE_COLUMNS & 0xFF) as u8);
        self.memory
            .insert(VIDEO_COLUMNS_BDA_ADDR + 1, ((TEXT_MODE_COLUMNS >> 8) & 0xFF) as u8);
        self.set_active_video_page(0);
        self.clear_text_screen();
    }

    fn clear_text_screen(&mut self) {
        for page in 0u8..8 {
            self.clear_text_screen_for_page(page);
            self.set_cursor_position_for_page(page, 0, 0);
        }
    }

    fn clear_text_screen_for_page(&mut self, page: u8) {
        for row in 0..TEXT_MODE_ROWS {
            for col in 0..TEXT_MODE_COLUMNS {
                self.write_text_cell_for_page(page, row, col, b' ', TEXT_MODE_DEFAULT_ATTR);
            }
        }
    }

    fn active_video_page(&self) -> u8 {
        self.normalize_text_page(*self.memory.get(&VIDEO_PAGE_BDA_ADDR).unwrap_or(&0))
    }

    fn set_active_video_page(&mut self, page: u8) {
        self.memory
            .insert(VIDEO_PAGE_BDA_ADDR, self.normalize_text_page(page));
    }

    fn normalize_text_page(&self, page: u8) -> u8 {
        page & 0x07
    }

    fn read_bios_tick_count(&self) -> u32 {
        let mut value = 0u32;
        for index in 0..4 {
            let byte = *self
                .memory
                .get(&(BIOS_TICK_COUNT_ADDR + index as u64))
                .unwrap_or(&0) as u32;
            value |= byte << (index * 8);
        }
        value
    }

    fn write_bios_tick_count(&mut self, value: u32) {
        for index in 0..4 {
            self.memory.insert(
                BIOS_TICK_COUNT_ADDR + index as u64,
                ((value >> (index * 8)) & 0xFF) as u8,
            );
        }
    }

    fn increment_bios_tick_count(&mut self) {
        let next = self.read_bios_tick_count().wrapping_add(1);
        if next >= BIOS_TICKS_PER_DAY {
            self.write_bios_tick_count(next - BIOS_TICKS_PER_DAY);
            self.memory.insert(BIOS_MIDNIGHT_FLAG_ADDR, 1);
        } else {
            self.write_bios_tick_count(next);
        }
    }

    fn cursor_position(&self) -> (u8, u8) {
        self.cursor_position_for_page(self.active_video_page())
    }

    fn cursor_position_for_page(&self, page: u8) -> (u8, u8) {
        let base = CURSOR_BDA_ADDR + (self.normalize_text_page(page) as u64 * 2);
        let col = *self.memory.get(&base).unwrap_or(&0);
        let row = *self.memory.get(&(base + 1)).unwrap_or(&0);
        (row, col)
    }

    fn set_cursor_position(&mut self, row: u8, col: u8) {
        self.set_cursor_position_for_page(self.active_video_page(), row, col);
    }

    fn set_cursor_position_for_page(&mut self, page: u8, row: u8, col: u8) {
        let base = CURSOR_BDA_ADDR + (self.normalize_text_page(page) as u64 * 2);
        let clamped_row = row.min((TEXT_MODE_ROWS - 1) as u8);
        let clamped_col = col.min((TEXT_MODE_COLUMNS - 1) as u8);
        self.memory.insert(base, clamped_col);
        self.memory.insert(base + 1, clamped_row);
    }

    fn video_teletype(&mut self, page: u8, byte: u8) {
        let page = self.normalize_text_page(page);
        let (mut row, mut col) = self.cursor_position_for_page(page);
        match byte {
            b'\r' => {
                col = 0;
            }
            b'\n' => {
                row = row.saturating_add(1);
            }
            0x08 => {
                col = col.saturating_sub(1);
            }
            _ => {
                self.write_text_cell_for_page(
                    page,
                    row as usize,
                    col as usize,
                    byte,
                    TEXT_MODE_DEFAULT_ATTR,
                );
                col = col.saturating_add(1);
            }
        }

        if col as usize >= TEXT_MODE_COLUMNS {
            col = 0;
            row = row.saturating_add(1);
        }
        if row as usize >= TEXT_MODE_ROWS {
            self.scroll_text_up(page);
            row = (TEXT_MODE_ROWS - 1) as u8;
        }

        self.set_cursor_position_for_page(page, row, col);
    }

    fn scroll_text_up(&mut self, page: u8) {
        let page_base = self.text_page_base(page);
        self.text_dirty = true;
        for row in 1..TEXT_MODE_ROWS {
            for col in 0..TEXT_MODE_COLUMNS {
                let from = page_base + (row * TEXT_MODE_BYTES_PER_ROW + (col * 2)) as u64;
                let to = page_base + ((row - 1) * TEXT_MODE_BYTES_PER_ROW + (col * 2)) as u64;
                let ch = *self.memory.get(&from).unwrap_or(&b' ');
                let attr = *self
                    .memory
                    .get(&(from + 1))
                    .unwrap_or(&TEXT_MODE_DEFAULT_ATTR);
                self.memory.insert(to, ch);
                self.memory.insert(to + 1, attr);
            }
        }
        for col in 0..TEXT_MODE_COLUMNS {
            self.write_text_cell_for_page(page, TEXT_MODE_ROWS - 1, col, b' ', TEXT_MODE_DEFAULT_ATTR);
        }
    }

    fn write_text_cell(&mut self, row: usize, col: usize, ch: u8, attr: u8) {
        self.write_text_cell_for_page(self.active_video_page(), row, col, ch, attr);
    }

    fn write_text_cell_for_page(&mut self, page: u8, row: usize, col: usize, ch: u8, attr: u8) {
        if row >= TEXT_MODE_ROWS || col >= TEXT_MODE_COLUMNS {
            return;
        }

        self.text_dirty = true;
        let base = self.text_page_base(page) + (row * TEXT_MODE_BYTES_PER_ROW + (col * 2)) as u64;
        self.memory.insert(base, ch);
        self.memory.insert(base + 1, attr);
    }

    fn text_page_base(&self, page: u8) -> u64 {
        TEXT_MODE_BASE + (self.normalize_text_page(page) as usize * TEXT_MODE_PAGE_BYTES) as u64
    }

    fn read_text_cell(&self, page: u8, row: usize, col: usize) -> (u8, u8) {
        if row >= TEXT_MODE_ROWS || col >= TEXT_MODE_COLUMNS {
            return (b' ', TEXT_MODE_DEFAULT_ATTR);
        }

        let base = self.text_page_base(page) + (row * TEXT_MODE_BYTES_PER_ROW + (col * 2)) as u64;
        (
            *self.memory.get(&base).unwrap_or(&b' '),
            *self.memory.get(&(base + 1)).unwrap_or(&TEXT_MODE_DEFAULT_ATTR),
        )
    }

    fn advance_text_position(&mut self, page: u8, row: &mut u8, col: &mut u8) {
        if *col as usize >= TEXT_MODE_COLUMNS {
            *col = 0;
            *row = row.saturating_add(1);
        }
        if *row as usize >= TEXT_MODE_ROWS {
            self.scroll_text_up(page);
            *row = (TEXT_MODE_ROWS - 1) as u8;
        }
    }

    fn write_repeated_char(
        &mut self,
        page: u8,
        ch: u8,
        attr_override: Option<u8>,
        count: usize,
        update_cursor: bool,
    ) {
        let page = self.normalize_text_page(page);
        let (mut row, mut col) = self.cursor_position_for_page(page);
        let (existing_ch, existing_attr) = self.read_text_cell(page, row as usize, col as usize);
        let attr = attr_override.unwrap_or(existing_attr);
        let byte = if ch == 0 { existing_ch } else { ch };

        for _ in 0..count {
            self.write_text_cell_for_page(page, row as usize, col as usize, byte, attr);
            col = col.saturating_add(1);
            self.advance_text_position(page, &mut row, &mut col);
        }

        if update_cursor {
            self.set_cursor_position_for_page(page, row, col);
        }
    }

    fn write_string(
        &mut self,
        page: u8,
        row: u8,
        col: u8,
        count: usize,
        default_attr: u8,
        with_attr: bool,
        update_cursor: bool,
        segment: u16,
        offset: u16,
    ) {
        let page = self.normalize_text_page(page);
        let mut row = row.min((TEXT_MODE_ROWS - 1) as u8);
        let mut col = col.min((TEXT_MODE_COLUMNS - 1) as u8);
        let base = ((segment as usize) << 4).saturating_add(offset as usize);

        for index in 0..count {
            let item_offset = if with_attr { index * 2 } else { index };
            let ch = *self.memory.get(&((base + item_offset) as u64)).unwrap_or(&b' ');
            let attr = if with_attr {
                *self
                    .memory
                    .get(&((base + item_offset + 1) as u64))
                    .unwrap_or(&default_attr)
            } else {
                default_attr
            };

            self.write_text_cell_for_page(page, row as usize, col as usize, ch, attr);
            col = col.saturating_add(1);
            self.advance_text_position(page, &mut row, &mut col);
        }

        if update_cursor {
            self.set_cursor_position_for_page(page, row, col);
        }
    }

    fn enqueue_keyboard_byte(&mut self, byte: u8) -> bool {
        let Some(key) = self.ascii_to_bios_key(byte) else {
            return false;
        };
        self.keyboard_queue.push_back(key);
        self.keyboard_scan_queue.push_back((key >> 8) as u8);
        self.raise_irq(1);
        true
    }

    fn pop_keyboard_word(&mut self) -> Option<u16> {
        let word = self.keyboard_queue.pop_front()?;
        self.keyboard_scan_queue.pop_front();
        Some(word)
    }

    fn read_keyboard_data_port(&mut self) -> u8 {
        let Some(scan) = self.keyboard_scan_queue.pop_front() else {
            return 0x00;
        };
        self.keyboard_queue.pop_front();
        scan
    }

    fn keyboard_status_port(&self) -> u8 {
        if self.keyboard_scan_queue.is_empty() {
            0x18
        } else {
            0x19
        }
    }

    fn ascii_to_bios_key(&self, byte: u8) -> Option<u16> {
        let key = match byte {
            b'\n' | b'\r' => 0x1C0D,
            0x08 => 0x0E08,
            b'\t' => 0x0F09,
            b' ' => 0x3920,
            b'0' => 0x0B30,
            b'1' => 0x0231,
            b'2' => 0x0332,
            b'3' => 0x0433,
            b'4' => 0x0534,
            b'5' => 0x0635,
            b'6' => 0x0736,
            b'7' => 0x0837,
            b'8' => 0x0938,
            b'9' => 0x0A39,
            b'a' | b'A' => 0x1E00 | byte as u16,
            b'b' | b'B' => 0x3000 | byte as u16,
            b'c' | b'C' => 0x2E00 | byte as u16,
            b'd' | b'D' => 0x2000 | byte as u16,
            b'e' | b'E' => 0x1200 | byte as u16,
            b'f' | b'F' => 0x2100 | byte as u16,
            b'g' | b'G' => 0x2200 | byte as u16,
            b'h' | b'H' => 0x2300 | byte as u16,
            b'i' | b'I' => 0x1700 | byte as u16,
            b'j' | b'J' => 0x2400 | byte as u16,
            b'k' | b'K' => 0x2500 | byte as u16,
            b'l' | b'L' => 0x2600 | byte as u16,
            b'm' | b'M' => 0x3200 | byte as u16,
            b'n' | b'N' => 0x3100 | byte as u16,
            b'o' | b'O' => 0x1800 | byte as u16,
            b'p' | b'P' => 0x1900 | byte as u16,
            b'q' | b'Q' => 0x1000 | byte as u16,
            b'r' | b'R' => 0x1300 | byte as u16,
            b's' | b'S' => 0x1F00 | byte as u16,
            b't' | b'T' => 0x1400 | byte as u16,
            b'u' | b'U' => 0x1600 | byte as u16,
            b'v' | b'V' => 0x2F00 | byte as u16,
            b'w' | b'W' => 0x1100 | byte as u16,
            b'x' | b'X' => 0x2D00 | byte as u16,
            b'y' | b'Y' => 0x1500 | byte as u16,
            b'z' | b'Z' => 0x2C00 | byte as u16,
            b'-' => 0x0C2D,
            b'_' => 0x0C5F,
            b'=' => 0x0D3D,
            b'+' => 0x0D2B,
            b'[' => 0x1A5B,
            b'{' => 0x1A7B,
            b']' => 0x1B5D,
            b'}' => 0x1B7D,
            b'\\' => 0x2B5C,
            b'|' => 0x2B7C,
            b';' => 0x273B,
            b':' => 0x273A,
            b'\'' => 0x2827,
            b'"' => 0x2822,
            b',' => 0x332C,
            b'<' => 0x333C,
            b'.' => 0x342E,
            b'>' => 0x343E,
            b'/' => 0x352F,
            b'?' => 0x353F,
            b'`' => 0x2960,
            b'~' => 0x297E,
            0x20..=0x7E => byte as u16,
            _ => return None,
        };
        Some(key)
    }

    fn reset_dma_controller(&mut self) {
        self.dma_flip_flop_low = true;
        self.dma_ch2_masked = true;
        self.dma_ch2_mode = 0;
    }

    fn write_dma_mask(&mut self, byte: u8) {
        if (byte & 0x3) != DMA_FDC_CHANNEL {
            return;
        }
        self.dma_ch2_masked = (byte & 0x4) != 0;
    }

    fn write_dma_channel2_addr(&mut self, byte: u8) {
        if self.dma_flip_flop_low {
            self.dma_ch2_base_addr = (self.dma_ch2_base_addr & 0xFF00) | (byte as u16);
            self.dma_ch2_current_addr = (self.dma_ch2_current_addr & 0xFF00) | (byte as u16);
        } else {
            self.dma_ch2_base_addr = (self.dma_ch2_base_addr & 0x00FF) | ((byte as u16) << 8);
            self.dma_ch2_current_addr = (self.dma_ch2_current_addr & 0x00FF) | ((byte as u16) << 8);
        }
        self.dma_flip_flop_low = !self.dma_flip_flop_low;
    }

    fn write_dma_channel2_count(&mut self, byte: u8) {
        if self.dma_flip_flop_low {
            self.dma_ch2_base_count = (self.dma_ch2_base_count & 0xFF00) | (byte as u16);
            self.dma_ch2_current_count = (self.dma_ch2_current_count & 0xFF00) | (byte as u16);
        } else {
            self.dma_ch2_base_count = (self.dma_ch2_base_count & 0x00FF) | ((byte as u16) << 8);
            self.dma_ch2_current_count = (self.dma_ch2_current_count & 0x00FF) | ((byte as u16) << 8);
        }
        self.dma_flip_flop_low = !self.dma_flip_flop_low;
    }

    fn write_fdc_dor(&mut self, byte: u8) {
        let was_reset = (self.fdc_dor & 0x04) == 0;
        let now_enabled = (byte & 0x04) != 0;
        self.fdc_dor = byte;
        if was_reset && now_enabled {
            self.fdc_last_st0 = 0x20;
            self.fdc_last_pcn = self.fdc_current_cylinder;
            self.raise_irq(6);
        }
    }

    fn write_fdc_data(&mut self, byte: u8) {
        if self.fdc_expected_len == 0 {
            self.fdc_command.clear();
            self.fdc_result.clear();
            self.fdc_command.push(byte);
            self.fdc_expected_len = fdc_command_length(byte);
            if self.fdc_expected_len == 1 {
                self.execute_fdc_command();
            }
            return;
        }

        self.fdc_command.push(byte);
        if self.fdc_command.len() >= self.fdc_expected_len {
            self.execute_fdc_command();
        }
    }

    fn execute_fdc_command(&mut self) {
        let command = self.fdc_command.clone();
        let opcode = command.first().copied().unwrap_or(0);
        let base_opcode = opcode & 0x1F;

        match base_opcode {
            0x03 => {}
            0x07 => {
                self.fdc_current_cylinder = 0;
                self.fdc_last_st0 = 0x20;
                self.fdc_last_pcn = 0;
                self.raise_irq(6);
            }
            0x08 => {
                self.fdc_result.push_back(self.fdc_last_st0);
                self.fdc_result.push_back(self.fdc_last_pcn);
            }
            0x0F => {
                self.fdc_current_cylinder = command.get(2).copied().unwrap_or(0);
                self.fdc_last_st0 = 0x20;
                self.fdc_last_pcn = self.fdc_current_cylinder;
                self.raise_irq(6);
            }
            0x06 => self.execute_fdc_read_data(&command),
            _ => {}
        }

        self.fdc_command.clear();
        self.fdc_expected_len = 0;
    }

    fn execute_fdc_read_data(&mut self, command: &[u8]) {
        if command.len() < 9 {
            return;
        }

        let drive_head = command[1];
        let cylinder = command[2] as usize;
        let head = command[3] as usize;
        let sector = command[4].max(1) as usize;
        let sector_size_code = command[5];
        let eot = command[6].max(command[4]) as usize;
        let sector_size = 128usize << sector_size_code.min(7);
        let sectors_to_transfer = eot.saturating_sub(sector).saturating_add(1).max(1);
        let dma_capacity = (self.dma_ch2_current_count as usize).saturating_add(1);
        let requested_len = sectors_to_transfer.saturating_mul(sector_size);
        let transfer_len = requested_len.min(dma_capacity);
        let start_lba =
            ((cylinder * FLOPPY_HEADS + head) * FLOPPY_SECTORS_PER_TRACK).saturating_add(sector.saturating_sub(1));
        let disk_offset = start_lba.saturating_mul(FLOPPY_BYTES_PER_SECTOR);
        let mut dma_address = self.dma_address();

        if !self.dma_ch2_masked {
            for index in 0..transfer_len {
                let value = *self.disk.get(&(disk_offset as u64 + index as u64)).unwrap_or(&0);
                self.memory.insert(dma_address, value);
                dma_address = dma_address.wrapping_add(1);
            }

            self.dma_ch2_current_addr = self.dma_ch2_current_addr.wrapping_add(transfer_len as u16);
            self.dma_ch2_current_count = self
                .dma_ch2_current_count
                .wrapping_sub((transfer_len as u16).saturating_sub(1));
        }

        let end_sector = sector.saturating_add(sectors_to_transfer.saturating_sub(1)) as u8;
        self.fdc_current_cylinder = cylinder as u8;
        self.fdc_last_st0 = 0x20 | (drive_head & 0x03);
        self.fdc_last_pcn = self.fdc_current_cylinder;
        self.fdc_result.push_back(self.fdc_last_st0);
        self.fdc_result.push_back(0x00);
        self.fdc_result.push_back(0x00);
        self.fdc_result.push_back(cylinder as u8);
        self.fdc_result.push_back(head as u8);
        self.fdc_result.push_back(end_sector);
        self.fdc_result.push_back(sector_size_code);
        self.raise_irq(6);
    }

    fn fdc_main_status(&self) -> u8 {
        if !self.fdc_result.is_empty() {
            0xD0
        } else {
            0x80
        }
    }

    fn fdc_disk_change_status(&self) -> u8 {
        if self.disk.is_empty() {
            0x00
        } else {
            0x80
        }
    }

    fn dma_address(&self) -> u64 {
        ((self.dma_ch2_page as u64) << 16) | (self.dma_ch2_current_addr as u64)
    }

    fn normalize_dos_floppy_drive(&self, drive: u8) -> Option<u8> {
        match drive {
            0x00 | 0x01 => Some(drive),
            // Some DOS boot paths rebound DL after AH=08 geometry discovery and
            // then reuse the returned drive-count byte as the next read target.
            // Treat that count as the original mounted floppy drive.
            0x02 => Some(0x00),
            0x80 | 0x81 => Some(drive & 0x01),
            _ => None,
        }
    }

    fn raise_irq(&mut self, irq_bit: u8) {
        self.pic_master_pending |= 1u8 << irq_bit;
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

fn fdc_command_length(opcode: u8) -> usize {
    match opcode & 0x1F {
        0x03 => 3,
        0x06 => 9,
        0x07 => 2,
        0x08 => 1,
        0x0F => 3,
        _ => 1,
    }
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
