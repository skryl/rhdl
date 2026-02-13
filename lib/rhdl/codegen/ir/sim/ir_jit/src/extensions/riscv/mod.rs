//! RISC-V standalone simulation extension for JIT.
//!
//! Provides batched cycle execution with native instruction/data memory,
//! CLINT/PLIC/UART/VirtIO MMIO handling, and interrupt wiring for both
//! single-cycle and pipelined RV32 cores.

use std::collections::{HashMap, VecDeque};

use crate::core::CoreSimulator;

const FUNCT3_BYTE: u8 = 0b000;
const FUNCT3_HALF: u8 = 0b001;
const FUNCT3_WORD: u8 = 0b010;
const FUNCT3_BYTE_U: u8 = 0b100;
const FUNCT3_HALF_U: u8 = 0b101;

const MASK64: u64 = 0xFFFF_FFFF_FFFF_FFFF;

const CLINT_BASE: u32 = 0x0200_0000;
const CLINT_MSIP_ADDR: u32 = CLINT_BASE + 0x0000;
const CLINT_MTIMECMP_LOW_ADDR: u32 = CLINT_BASE + 0x4000;
const CLINT_MTIMECMP_HIGH_ADDR: u32 = CLINT_BASE + 0x4004;
const CLINT_MTIME_LOW_ADDR: u32 = CLINT_BASE + 0xBFF8;
const CLINT_MTIME_HIGH_ADDR: u32 = CLINT_BASE + 0xBFFC;

const PLIC_BASE: u32 = 0x0C00_0000;
const PLIC_PRIORITY_1_ADDR: u32 = PLIC_BASE + 0x0004;
const PLIC_PRIORITY_10_ADDR: u32 = PLIC_BASE + 0x0028;
const PLIC_PENDING_ADDR: u32 = PLIC_BASE + 0x1000;
const PLIC_ENABLE_ADDR: u32 = PLIC_BASE + 0x2000;
const PLIC_SENABLE_ADDR: u32 = PLIC_BASE + 0x2080;
const PLIC_THRESHOLD_ADDR: u32 = PLIC_BASE + 0x200000;
const PLIC_STHRESHOLD_ADDR: u32 = PLIC_BASE + 0x201000;
const PLIC_CLAIM_COMPLETE_ADDR: u32 = PLIC_BASE + 0x200004;
const PLIC_SCLAIM_COMPLETE_ADDR: u32 = PLIC_BASE + 0x201004;

const UART_BASE: u32 = 0x1000_0000;
const UART_REG_THR_RBR_DLL: u32 = 0x0;
const UART_REG_IER_DLM: u32 = 0x1;
const UART_REG_IIR_FCR: u32 = 0x2;
const UART_REG_LCR: u32 = 0x3;
const UART_REG_MCR: u32 = 0x4;
const UART_REG_LSR: u32 = 0x5;
const UART_REG_MSR: u32 = 0x6;
const UART_REG_SCR: u32 = 0x7;

const VIRTIO_BASE: u32 = 0x1000_1000;
const VIRTIO_MAGIC_VALUE_ADDR: u32 = VIRTIO_BASE + 0x000;
const VIRTIO_VERSION_ADDR: u32 = VIRTIO_BASE + 0x004;
const VIRTIO_DEVICE_ID_ADDR: u32 = VIRTIO_BASE + 0x008;
const VIRTIO_VENDOR_ID_ADDR: u32 = VIRTIO_BASE + 0x00C;
const VIRTIO_DEVICE_FEATURES_ADDR: u32 = VIRTIO_BASE + 0x010;
const VIRTIO_DEVICE_FEATURES_SEL_ADDR: u32 = VIRTIO_BASE + 0x014;
const VIRTIO_DRIVER_FEATURES_ADDR: u32 = VIRTIO_BASE + 0x020;
const VIRTIO_DRIVER_FEATURES_SEL_ADDR: u32 = VIRTIO_BASE + 0x024;
const VIRTIO_GUEST_PAGE_SIZE_ADDR: u32 = VIRTIO_BASE + 0x028;
const VIRTIO_QUEUE_SEL_ADDR: u32 = VIRTIO_BASE + 0x030;
const VIRTIO_QUEUE_NUM_MAX_ADDR: u32 = VIRTIO_BASE + 0x034;
const VIRTIO_QUEUE_NUM_ADDR: u32 = VIRTIO_BASE + 0x038;
const VIRTIO_QUEUE_ALIGN_ADDR: u32 = VIRTIO_BASE + 0x03C;
const VIRTIO_QUEUE_PFN_ADDR: u32 = VIRTIO_BASE + 0x040;
const VIRTIO_QUEUE_READY_ADDR: u32 = VIRTIO_BASE + 0x044;
const VIRTIO_QUEUE_NOTIFY_ADDR: u32 = VIRTIO_BASE + 0x050;
const VIRTIO_INTERRUPT_STATUS_ADDR: u32 = VIRTIO_BASE + 0x060;
const VIRTIO_INTERRUPT_ACK_ADDR: u32 = VIRTIO_BASE + 0x064;
const VIRTIO_STATUS_ADDR: u32 = VIRTIO_BASE + 0x070;
const VIRTIO_QUEUE_DESC_LOW_ADDR: u32 = VIRTIO_BASE + 0x080;
const VIRTIO_QUEUE_DESC_HIGH_ADDR: u32 = VIRTIO_BASE + 0x084;
const VIRTIO_QUEUE_DRIVER_LOW_ADDR: u32 = VIRTIO_BASE + 0x090;
const VIRTIO_QUEUE_DRIVER_HIGH_ADDR: u32 = VIRTIO_BASE + 0x094;
const VIRTIO_QUEUE_DEVICE_LOW_ADDR: u32 = VIRTIO_BASE + 0x0A0;
const VIRTIO_QUEUE_DEVICE_HIGH_ADDR: u32 = VIRTIO_BASE + 0x0A4;
const VIRTIO_CONFIG_GENERATION_ADDR: u32 = VIRTIO_BASE + 0x0FC;
const VIRTIO_CONFIG_CAPACITY_LOW_ADDR: u32 = VIRTIO_BASE + 0x100;
const VIRTIO_CONFIG_CAPACITY_HIGH_ADDR: u32 = VIRTIO_BASE + 0x104;

const VIRTIO_MAGIC: u32 = 0x7472_6976;
const VIRTIO_VENDOR_ID: u32 = 0x554D_4551;
const VIRTIO_STATUS_DRIVER_OK: u32 = 0x04;
const VIRTIO_INTERRUPT_USED_BUFFER: u32 = 0x01;
const VIRTIO_DESC_F_NEXT: u16 = 0x0001;
const VIRTIO_REQ_T_IN: u32 = 0;
const VIRTIO_REQ_T_OUT: u32 = 1;
const VIRTIO_SECTOR_BYTES: u64 = 512;

const DEFAULT_INST_MEM_BYTES: usize = 8 * 1024 * 1024;
const DEFAULT_DATA_MEM_BYTES: usize = 128 * 1024 * 1024;
const DEFAULT_DISK_BYTES: usize = 8 * 1024 * 1024;
const VIRTIO_QUEUE_NUM_MAX: u16 = 8;

#[derive(Clone, Copy)]
struct UartStepResult {
    read_data: u32,
    irq: bool,
    tx_valid: bool,
    tx_data: u8,
    rx_accept: bool,
}

#[derive(Clone, Copy)]
struct VirtioDesc {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
}

pub struct RiscvExtension {
    pub inst_mem: Vec<u8>,
    pub data_mem: Vec<u8>,
    pub disk: Vec<u8>,
    pub uart_tx_bytes: Vec<u8>,

    uart_rx_queue: VecDeque<u8>,

    clk_idx: usize,
    rst_idx: usize,
    irq_software_idx: usize,
    irq_timer_idx: usize,
    irq_external_idx: usize,

    inst_addr_idx: usize,
    inst_data_idx: usize,
    inst_ptw_addr1_idx: usize,
    inst_ptw_addr0_idx: usize,
    inst_ptw_pte1_idx: usize,
    inst_ptw_pte0_idx: usize,

    data_addr_idx: usize,
    data_wdata_idx: usize,
    data_rdata_idx: usize,
    data_we_idx: usize,
    data_re_idx: usize,
    data_funct3_idx: usize,
    data_ptw_addr1_idx: usize,
    data_ptw_addr0_idx: usize,
    data_ptw_pte1_idx: usize,
    data_ptw_pte0_idx: usize,

    ext_irq_software: bool,
    ext_irq_timer: bool,
    ext_irq_external: bool,

    ext_plic_source1: bool,
    ext_plic_source10: bool,

    clint_prev_clk: u64,
    clint_msip: u32,
    clint_mtime: u64,
    clint_mtimecmp: u64,
    clint_irq_software: bool,
    clint_irq_timer: bool,

    plic_prev_clk: u64,
    plic_priority1: u32,
    plic_priority10: u32,
    plic_pending1: u32,
    plic_pending10: u32,
    plic_enable1: u32,
    plic_enable10: u32,
    plic_threshold: u32,
    plic_in_service_id: u32,
    plic_irq_external: bool,

    uart_prev_clk: u64,
    uart_rbr: u8,
    uart_ier: u8,
    uart_lcr: u8,
    uart_mcr: u8,
    uart_dll: u8,
    uart_dlm: u8,
    uart_scr: u8,
    uart_rx_ready: bool,
    uart_tx_data_reg: u8,
    uart_irq: bool,

    virtio_prev_clk: u64,
    virtio_device_features_sel: u32,
    virtio_driver_features_sel: u32,
    virtio_driver_features_0: u32,
    virtio_driver_features_1: u32,
    virtio_guest_page_size: u32,
    virtio_queue_sel: u32,
    virtio_queue_num: u16,
    virtio_queue_ready: u32,
    virtio_queue_desc: u64,
    virtio_queue_driver: u64,
    virtio_queue_device: u64,
    virtio_queue_pfn: u32,
    virtio_queue_align: u32,
    virtio_status: u32,
    virtio_interrupt_status: u32,
    virtio_notify_pending: bool,
    virtio_last_avail_idx: u16,
    virtio_irq: bool,

    data_mem_prev_clk: u64,
}

impl RiscvExtension {
    pub fn new(core: &CoreSimulator) -> Self {
        let n = &core.name_to_idx;

        Self {
            inst_mem: vec![0u8; DEFAULT_INST_MEM_BYTES],
            data_mem: vec![0u8; DEFAULT_DATA_MEM_BYTES],
            disk: vec![0u8; DEFAULT_DISK_BYTES],
            uart_tx_bytes: Vec::new(),
            uart_rx_queue: VecDeque::new(),

            clk_idx: idx(n, "clk"),
            rst_idx: idx(n, "rst"),
            irq_software_idx: idx(n, "irq_software"),
            irq_timer_idx: idx(n, "irq_timer"),
            irq_external_idx: idx(n, "irq_external"),

            inst_addr_idx: idx(n, "inst_addr"),
            inst_data_idx: idx(n, "inst_data"),
            inst_ptw_addr1_idx: idx(n, "inst_ptw_addr1"),
            inst_ptw_addr0_idx: idx(n, "inst_ptw_addr0"),
            inst_ptw_pte1_idx: idx(n, "inst_ptw_pte1"),
            inst_ptw_pte0_idx: idx(n, "inst_ptw_pte0"),

            data_addr_idx: idx(n, "data_addr"),
            data_wdata_idx: idx(n, "data_wdata"),
            data_rdata_idx: idx(n, "data_rdata"),
            data_we_idx: idx(n, "data_we"),
            data_re_idx: idx(n, "data_re"),
            data_funct3_idx: idx(n, "data_funct3"),
            data_ptw_addr1_idx: idx(n, "data_ptw_addr1"),
            data_ptw_addr0_idx: idx(n, "data_ptw_addr0"),
            data_ptw_pte1_idx: idx(n, "data_ptw_pte1"),
            data_ptw_pte0_idx: idx(n, "data_ptw_pte0"),

            ext_irq_software: false,
            ext_irq_timer: false,
            ext_irq_external: false,
            ext_plic_source1: false,
            ext_plic_source10: false,

            clint_prev_clk: 0,
            clint_msip: 0,
            clint_mtime: 0,
            clint_mtimecmp: MASK64,
            clint_irq_software: false,
            clint_irq_timer: false,

            plic_prev_clk: 0,
            plic_priority1: 0,
            plic_priority10: 0,
            plic_pending1: 0,
            plic_pending10: 0,
            plic_enable1: 0,
            plic_enable10: 0,
            plic_threshold: 0,
            plic_in_service_id: 0,
            plic_irq_external: false,

            uart_prev_clk: 0,
            uart_rbr: 0,
            uart_ier: 0,
            uart_lcr: 0,
            uart_mcr: 0,
            uart_dll: 0,
            uart_dlm: 0,
            uart_scr: 0,
            uart_rx_ready: false,
            uart_tx_data_reg: 0,
            uart_irq: false,

            virtio_prev_clk: 0,
            virtio_device_features_sel: 0,
            virtio_driver_features_sel: 0,
            virtio_driver_features_0: 0,
            virtio_driver_features_1: 0,
            virtio_guest_page_size: 0,
            virtio_queue_sel: 0,
            virtio_queue_num: 0,
            virtio_queue_ready: 0,
            virtio_queue_desc: 0,
            virtio_queue_driver: 0,
            virtio_queue_device: 0,
            virtio_queue_pfn: 0,
            virtio_queue_align: 0,
            virtio_status: 0,
            virtio_interrupt_status: 0,
            virtio_notify_pending: false,
            virtio_last_avail_idx: 0,
            virtio_irq: false,

            data_mem_prev_clk: 0,
        }
    }

    pub fn is_riscv_ir(name_to_idx: &HashMap<String, usize>) -> bool {
        const REQUIRED: &[&str] = &[
            "clk",
            "rst",
            "irq_software",
            "irq_timer",
            "irq_external",
            "inst_addr",
            "inst_data",
            "inst_ptw_addr1",
            "inst_ptw_addr0",
            "inst_ptw_pte1",
            "inst_ptw_pte0",
            "data_addr",
            "data_wdata",
            "data_rdata",
            "data_we",
            "data_re",
            "data_funct3",
            "data_ptw_addr1",
            "data_ptw_addr0",
            "data_ptw_pte1",
            "data_ptw_pte0",
            "debug_reg_addr",
            "debug_reg_data",
            "debug_pc",
        ];
        REQUIRED.iter().all(|name| name_to_idx.contains_key(*name))
    }

    pub fn reset_core(&mut self, core: &mut CoreSimulator) {
        self.reset_state();

        self.set_clk_rst(core, 0, 1);
        self.propagate_all(core, true);

        self.set_clk_rst(core, 1, 1);
        self.propagate_all(core, false);
        self.tick_core_rising(core);

        self.set_clk_rst(core, 0, 1);
        self.propagate_all(core, true);

        self.set_clk_rst(core, 0, 0);
        self.propagate_all(core, true);
    }

    pub fn set_irq_bits(&mut self, software: bool, timer: bool, external: bool) {
        self.ext_irq_software = software;
        self.ext_irq_timer = timer;
        self.ext_irq_external = external;
    }

    pub fn set_plic_sources(&mut self, source1: bool, source10: bool) {
        self.ext_plic_source1 = source1;
        self.ext_plic_source10 = source10;
    }

    pub fn enqueue_uart_rx(&mut self, value: u8) {
        self.uart_rx_queue.push_back(value);
    }

    pub fn enqueue_uart_rx_bytes(&mut self, bytes: &[u8]) -> usize {
        if bytes.is_empty() {
            return 0;
        }
        self.uart_rx_queue.extend(bytes.iter().copied());
        bytes.len()
    }

    pub fn clear_uart_tx_bytes(&mut self) {
        self.uart_tx_bytes.clear();
    }

    pub fn uart_tx_len(&self) -> usize {
        self.uart_tx_bytes.len()
    }

    pub fn read_uart_tx(&self, start: usize, out: &mut [u8]) -> usize {
        if out.is_empty() || start >= self.uart_tx_bytes.len() {
            return 0;
        }
        let end = (start + out.len()).min(self.uart_tx_bytes.len());
        let len = end.saturating_sub(start);
        out[..len].copy_from_slice(&self.uart_tx_bytes[start..end]);
        len
    }

    pub fn load_main(&mut self, data: &[u8], offset: usize, is_rom: bool) -> usize {
        if is_rom {
            let loaded = load_wrapped(&mut self.inst_mem, offset, data);
            load_wrapped(&mut self.data_mem, offset, data);
            loaded
        } else {
            let loaded = load_wrapped(&mut self.data_mem, offset, data);
            load_wrapped(&mut self.inst_mem, offset, data);
            loaded
        }
    }

    pub fn read_main(&self, start: usize, out: &mut [u8], _mapped: bool) -> usize {
        read_wrapped(&self.data_mem, start, out)
    }

    pub fn write_main(&mut self, start: usize, data: &[u8], _mapped: bool) -> usize {
        let written = load_wrapped(&mut self.data_mem, start, data);
        load_wrapped(&mut self.inst_mem, start, data);
        written
    }

    pub fn read_rom(&self, start: usize, out: &mut [u8]) -> usize {
        read_wrapped(&self.inst_mem, start, out)
    }

    pub fn load_disk(&mut self, data: &[u8], offset: usize) -> usize {
        load_wrapped(&mut self.disk, offset, data)
    }

    pub fn read_disk(&self, start: usize, out: &mut [u8]) -> usize {
        read_wrapped(&self.disk, start, out)
    }

    pub fn write_disk(&mut self, start: usize, data: &[u8]) -> usize {
        load_wrapped(&mut self.disk, start, data)
    }

    pub fn run_cycles(&mut self, core: &mut CoreSimulator, n: usize) -> usize {
        for _ in 0..n {
            self.set_clk_rst(core, 0, 0);
            self.propagate_all(core, true);

            self.set_clk_rst(core, 1, 0);
            self.propagate_all(core, false);
            self.tick_core_rising(core);

            self.set_clk_rst(core, 0, 0);
            self.propagate_all(core, true);
        }

        n
    }

    fn reset_state(&mut self) {
        self.ext_irq_software = false;
        self.ext_irq_timer = false;
        self.ext_irq_external = false;
        self.ext_plic_source1 = false;
        self.ext_plic_source10 = false;

        self.uart_rx_queue.clear();
        self.uart_tx_bytes.clear();

        self.clint_prev_clk = 0;
        self.clint_msip = 0;
        self.clint_mtime = 0;
        self.clint_mtimecmp = MASK64;
        self.clint_irq_software = false;
        self.clint_irq_timer = false;

        self.plic_prev_clk = 0;
        self.plic_priority1 = 0;
        self.plic_priority10 = 0;
        self.plic_pending1 = 0;
        self.plic_pending10 = 0;
        self.plic_enable1 = 0;
        self.plic_enable10 = 0;
        self.plic_threshold = 0;
        self.plic_in_service_id = 0;
        self.plic_irq_external = false;

        self.uart_prev_clk = 0;
        self.uart_rbr = 0;
        self.uart_ier = 0;
        self.uart_lcr = 0;
        self.uart_mcr = 0;
        self.uart_dll = 0;
        self.uart_dlm = 0;
        self.uart_scr = 0;
        self.uart_rx_ready = false;
        self.uart_tx_data_reg = 0;
        self.uart_irq = false;

        self.virtio_prev_clk = 0;
        self.virtio_device_features_sel = 0;
        self.virtio_driver_features_sel = 0;
        self.virtio_driver_features_0 = 0;
        self.virtio_driver_features_1 = 0;
        self.virtio_guest_page_size = 0;
        self.virtio_queue_sel = 0;
        self.virtio_queue_num = 0;
        self.virtio_queue_ready = 0;
        self.virtio_queue_desc = 0;
        self.virtio_queue_driver = 0;
        self.virtio_queue_device = 0;
        self.virtio_queue_pfn = 0;
        self.virtio_queue_align = 0;
        self.virtio_status = 0;
        self.virtio_interrupt_status = 0;
        self.virtio_notify_pending = false;
        self.virtio_last_avail_idx = 0;
        self.virtio_irq = false;

        self.data_mem_prev_clk = 0;
    }

    fn set_clk_rst(&mut self, core: &mut CoreSimulator, clk: u64, rst: u64) {
        if self.clk_idx < core.signals.len() {
            core.signals[self.clk_idx] = clk;
        }
        if self.rst_idx < core.signals.len() {
            core.signals[self.rst_idx] = rst;
        }
        self.apply_irq_inputs(core);
    }

    fn tick_core_rising(&mut self, core: &mut CoreSimulator) {
        for value in core.prev_clock_values.iter_mut() {
            *value = 0;
        }
        if self.clk_idx < core.signals.len() {
            core.signals[self.clk_idx] = 1;
        }
        core.tick_forced();
    }

    fn apply_irq_inputs(&self, core: &mut CoreSimulator) {
        let irq_software = self.ext_irq_software || self.clint_irq_software;
        let irq_timer = self.ext_irq_timer || self.clint_irq_timer;
        let irq_external = self.ext_irq_external || self.plic_irq_external;

        if self.irq_software_idx < core.signals.len() {
            core.signals[self.irq_software_idx] = if irq_software { 1 } else { 0 };
        }
        if self.irq_timer_idx < core.signals.len() {
            core.signals[self.irq_timer_idx] = if irq_timer { 1 } else { 0 };
        }
        if self.irq_external_idx < core.signals.len() {
            core.signals[self.irq_external_idx] = if irq_external { 1 } else { 0 };
        }
    }

    fn propagate_all(&mut self, core: &mut CoreSimulator, evaluate_cpu: bool) {
        self.apply_irq_inputs(core);
        if evaluate_cpu {
            core.evaluate();

            let inst_ptw_addr1 = self.signal(core, self.inst_ptw_addr1_idx) as u32;
            self.set_signal(core, self.inst_ptw_pte1_idx, self.read_data_word_raw(inst_ptw_addr1) as u64);
            core.evaluate();

            let inst_ptw_addr0 = self.signal(core, self.inst_ptw_addr0_idx) as u32;
            self.set_signal(core, self.inst_ptw_pte0_idx, self.read_data_word_raw(inst_ptw_addr0) as u64);
            core.evaluate();
        }

        let inst_addr = self.signal(core, self.inst_addr_idx) as u32;
        let inst_data = self.read_inst_word_raw(inst_addr);

        if evaluate_cpu {
            self.set_signal(core, self.inst_data_idx, inst_data as u64);
            core.evaluate();
        }

        if evaluate_cpu {
            let data_ptw_addr1 = self.signal(core, self.data_ptw_addr1_idx) as u32;
            self.set_signal(core, self.data_ptw_pte1_idx, self.read_data_word_raw(data_ptw_addr1) as u64);
            core.evaluate();

            let data_ptw_addr0 = self.signal(core, self.data_ptw_addr0_idx) as u32;
            self.set_signal(core, self.data_ptw_pte0_idx, self.read_data_word_raw(data_ptw_addr0) as u64);
            core.evaluate();
        }

        let clk = self.signal(core, self.clk_idx);
        let rst = self.signal(core, self.rst_idx);

        let data_addr = self.signal(core, self.data_addr_idx) as u32;
        let data_wdata = self.signal(core, self.data_wdata_idx) as u32;
        let data_we = self.signal(core, self.data_we_idx) != 0;
        let data_re = self.signal(core, self.data_re_idx) != 0;
        let data_funct3 = (self.signal(core, self.data_funct3_idx) & 0x7) as u8;

        let clint_selected = clint_access(data_addr);
        let plic_selected = plic_access(data_addr);
        let uart_selected = uart_access(data_addr);
        let virtio_selected = virtio_access(data_addr);

        let clint_read_data = self.clint_step(
            clk,
            rst,
            data_addr,
            data_wdata,
            clint_selected && data_re,
            clint_selected && data_we,
            data_funct3,
        );

        let virtio_read_data = self.virtio_step(
            clk,
            rst,
            data_addr,
            data_wdata,
            virtio_selected && data_re,
            virtio_selected && data_we,
            data_funct3,
        );
        self.virtio_service_queues();

        let plic_source1 = self.ext_plic_source1 || self.virtio_irq;
        let plic_source10 = self.ext_plic_source10 || self.uart_irq;
        let plic_read_data = self.plic_step(
            clk,
            rst,
            data_addr,
            data_wdata,
            plic_selected && data_re,
            plic_selected && data_we,
            data_funct3,
            plic_source1,
            plic_source10,
        );

        let uart_rx_valid = !self.uart_rx_queue.is_empty();
        let uart_rx_data = self.uart_rx_queue.front().copied().unwrap_or(0);
        let uart_result = self.uart_step(
            clk,
            rst,
            data_addr,
            data_wdata,
            uart_selected && data_re,
            uart_selected && data_we,
            data_funct3,
            uart_rx_valid,
            uart_rx_data,
        );
        if uart_result.rx_accept {
            self.uart_rx_queue.pop_front();
        }
        if uart_result.tx_valid {
            self.uart_tx_bytes.push(uart_result.tx_data);
        }

        let memory_selected = clint_selected || plic_selected || uart_selected || virtio_selected;
        let data_mem_read_data = self.data_mem_step(
            clk,
            rst,
            data_addr,
            data_wdata,
            (!memory_selected) && data_re,
            (!memory_selected) && data_we,
            data_funct3,
        );

        let data_rdata = if clint_selected {
            clint_read_data
        } else if plic_selected {
            plic_read_data
        } else if uart_selected {
            uart_result.read_data
        } else if virtio_selected {
            virtio_read_data
        } else {
            data_mem_read_data
        };

        if evaluate_cpu {
            self.set_signal(core, self.data_rdata_idx, data_rdata as u64);
            self.apply_irq_inputs(core);
            core.evaluate();
        }
    }

    fn clint_step(
        &mut self,
        clk: u64,
        rst: u64,
        addr: u32,
        write_data: u32,
        mem_read: bool,
        mem_write: bool,
        funct3: u8,
    ) -> u32 {
        if rst == 1 {
            self.clint_msip = 0;
            self.clint_mtime = 0;
            self.clint_mtimecmp = MASK64;
            self.clint_irq_software = false;
            self.clint_irq_timer = false;
            self.clint_prev_clk = clk;
            return 0;
        }

        if self.clint_prev_clk == 0 && clk == 1 {
            self.clint_mtime = self.clint_mtime.wrapping_add(1);

            if mem_write && funct3 == FUNCT3_WORD {
                match addr {
                    CLINT_MSIP_ADDR => {
                        self.clint_msip = write_data & 0x1;
                    }
                    CLINT_MTIMECMP_LOW_ADDR => {
                        self.clint_mtimecmp = (self.clint_mtimecmp & 0xFFFF_FFFF_0000_0000) | (write_data as u64);
                    }
                    CLINT_MTIMECMP_HIGH_ADDR => {
                        self.clint_mtimecmp = ((write_data as u64) << 32) | (self.clint_mtimecmp & 0xFFFF_FFFF);
                    }
                    CLINT_MTIME_LOW_ADDR => {
                        self.clint_mtime = (self.clint_mtime & 0xFFFF_FFFF_0000_0000) | (write_data as u64);
                    }
                    CLINT_MTIME_HIGH_ADDR => {
                        self.clint_mtime = ((write_data as u64) << 32) | (self.clint_mtime & 0xFFFF_FFFF);
                    }
                    _ => {}
                }
            }
        }

        self.clint_prev_clk = clk;

        self.clint_irq_software = self.clint_msip != 0;
        self.clint_irq_timer = self.clint_mtime >= self.clint_mtimecmp;

        if !mem_read {
            return 0;
        }

        match addr {
            CLINT_MSIP_ADDR => self.clint_msip,
            CLINT_MTIMECMP_LOW_ADDR => self.clint_mtimecmp as u32,
            CLINT_MTIMECMP_HIGH_ADDR => (self.clint_mtimecmp >> 32) as u32,
            CLINT_MTIME_LOW_ADDR => self.clint_mtime as u32,
            CLINT_MTIME_HIGH_ADDR => (self.clint_mtime >> 32) as u32,
            _ => 0,
        }
    }

    fn plic_step(
        &mut self,
        clk: u64,
        rst: u64,
        addr: u32,
        write_data: u32,
        mem_read: bool,
        mem_write: bool,
        funct3: u8,
        source1: bool,
        source10: bool,
    ) -> u32 {
        let claim_id = self.plic_select_claim_id();
        let claim_grant = mem_read
            && matches!(addr, PLIC_CLAIM_COMPLETE_ADDR | PLIC_SCLAIM_COMPLETE_ADDR)
            && claim_id != 0;

        if rst == 1 {
            self.plic_priority1 = 0;
            self.plic_priority10 = 0;
            self.plic_pending1 = 0;
            self.plic_pending10 = 0;
            self.plic_enable1 = 0;
            self.plic_enable10 = 0;
            self.plic_threshold = 0;
            self.plic_in_service_id = 0;
            self.plic_irq_external = false;
            self.plic_prev_clk = clk;
            return 0;
        }

        if self.plic_prev_clk == 0 && clk == 1 {
            if source1 {
                self.plic_pending1 = 1;
            }
            if source10 {
                self.plic_pending10 = 1;
            }

            if mem_write && funct3 == FUNCT3_WORD {
                match addr {
                    PLIC_PRIORITY_1_ADDR => {
                        self.plic_priority1 = write_data & 0x7;
                    }
                    PLIC_PRIORITY_10_ADDR => {
                        self.plic_priority10 = write_data & 0x7;
                    }
                    PLIC_ENABLE_ADDR | PLIC_SENABLE_ADDR => {
                        self.plic_enable1 = (write_data >> 1) & 0x1;
                        self.plic_enable10 = (write_data >> 10) & 0x1;
                    }
                    PLIC_THRESHOLD_ADDR | PLIC_STHRESHOLD_ADDR => {
                        self.plic_threshold = write_data & 0x7;
                    }
                    PLIC_CLAIM_COMPLETE_ADDR | PLIC_SCLAIM_COMPLETE_ADDR => {
                        let complete_id = write_data & 0x3FF;
                        if complete_id == self.plic_in_service_id {
                            self.plic_in_service_id = 0;
                        }
                    }
                    _ => {}
                }
            }

            let claim_id_rise = self.plic_select_claim_id();
            if mem_read
                && matches!(addr, PLIC_CLAIM_COMPLETE_ADDR | PLIC_SCLAIM_COMPLETE_ADDR)
                && claim_id_rise != 0
            {
                self.plic_clear_pending(claim_id_rise);
                self.plic_in_service_id = claim_id_rise;
                if claim_id_rise == 1 {
                    self.virtio_interrupt_status &= !VIRTIO_INTERRUPT_USED_BUFFER;
                    self.virtio_irq = self.virtio_irq_asserted();
                }
            }
        }

        self.plic_prev_clk = clk;
        self.plic_irq_external = self.plic_select_claim_id() != 0;

        if !mem_read {
            return 0;
        }

        match addr {
            PLIC_PRIORITY_1_ADDR => self.plic_priority1,
            PLIC_PRIORITY_10_ADDR => self.plic_priority10,
            PLIC_PENDING_ADDR => (self.plic_pending1 << 1) | (self.plic_pending10 << 10),
            PLIC_ENABLE_ADDR | PLIC_SENABLE_ADDR => (self.plic_enable1 << 1) | (self.plic_enable10 << 10),
            PLIC_THRESHOLD_ADDR | PLIC_STHRESHOLD_ADDR => self.plic_threshold,
            PLIC_CLAIM_COMPLETE_ADDR | PLIC_SCLAIM_COMPLETE_ADDR => {
                if claim_grant {
                    claim_id
                } else {
                    self.plic_select_claim_id()
                }
            }
            _ => 0,
        }
    }

    fn plic_clear_pending(&mut self, id: u32) {
        match id {
            1 => self.plic_pending1 = 0,
            10 => self.plic_pending10 = 0,
            _ => {}
        }
    }

    fn plic_select_claim_id(&self) -> u32 {
        if self.plic_in_service_id != 0 {
            return 0;
        }

        let source1 = self.plic_pending1 == 1 && self.plic_enable1 == 1 && self.plic_priority1 > self.plic_threshold;
        let source10 = self.plic_pending10 == 1 && self.plic_enable10 == 1 && self.plic_priority10 > self.plic_threshold;

        if !source1 && !source10 {
            return 0;
        }
        if source1 && !source10 {
            return 1;
        }
        if source10 && !source1 {
            return 10;
        }
        if self.plic_priority10 > self.plic_priority1 {
            10
        } else {
            1
        }
    }

    fn uart_step(
        &mut self,
        clk: u64,
        rst: u64,
        addr: u32,
        write_data: u32,
        mem_read: bool,
        mem_write: bool,
        funct3: u8,
        rx_valid: bool,
        rx_data: u8,
    ) -> UartStepResult {
        let mut tx_valid_now = false;
        let mut rx_accept_now = false;

        if rst == 1 {
            self.uart_rbr = 0;
            self.uart_ier = 0;
            self.uart_lcr = 0;
            self.uart_mcr = 0;
            self.uart_dll = 0;
            self.uart_dlm = 0;
            self.uart_scr = 0;
            self.uart_rx_ready = false;
            self.uart_tx_data_reg = 0;
            self.uart_irq = false;
            self.uart_prev_clk = clk;
            return UartStepResult {
                read_data: 0,
                irq: false,
                tx_valid: false,
                tx_data: 0,
                rx_accept: false,
            };
        }

        let reg_offset = addr & 0x7;
        let byte_access = funct3 == FUNCT3_BYTE || funct3 == FUNCT3_BYTE_U;
        let word_access = funct3 == FUNCT3_WORD;
        let access_ok = byte_access || word_access;
        let dlab = (self.uart_lcr & 0x80) != 0;

        let rbr_pop = mem_read && access_ok && reg_offset == UART_REG_THR_RBR_DLL && !dlab && self.uart_rx_ready;
        let rbr_pop_value = self.uart_rbr;

        if self.uart_prev_clk == 0 && clk == 1 {
            if rx_valid && !self.uart_rx_ready {
                self.uart_rbr = rx_data;
                self.uart_rx_ready = true;
                rx_accept_now = true;
            }

            if mem_write && access_ok {
                let write_byte = (write_data & 0xFF) as u8;
                match reg_offset {
                    UART_REG_THR_RBR_DLL => {
                        if dlab {
                            self.uart_dll = write_byte;
                        } else {
                            self.uart_tx_data_reg = write_byte;
                            tx_valid_now = true;
                        }
                    }
                    UART_REG_IER_DLM => {
                        if dlab {
                            self.uart_dlm = write_byte;
                        } else {
                            self.uart_ier = write_byte & 0x0F;
                        }
                    }
                    UART_REG_IIR_FCR => {
                        if (write_byte & 0x2) != 0 {
                            self.uart_rx_ready = false;
                        }
                    }
                    UART_REG_LCR => self.uart_lcr = write_byte,
                    UART_REG_MCR => self.uart_mcr = write_byte,
                    UART_REG_SCR => self.uart_scr = write_byte,
                    _ => {}
                }
            }

            if rbr_pop {
                self.uart_rx_ready = false;
            }
        }

        self.uart_prev_clk = clk;

        let rx_irq_pending = (self.uart_ier & 0x1) != 0 && self.uart_rx_ready;
        let iir: u8 = if rx_irq_pending { 0x04 } else { 0x01 };
        let lsr: u8 = 0x60 | if self.uart_rx_ready { 0x01 } else { 0x00 };

        let read_data = if mem_read && access_ok {
            let read_byte = match reg_offset {
                UART_REG_THR_RBR_DLL => {
                    if dlab {
                        self.uart_dll
                    } else if rbr_pop {
                        rbr_pop_value
                    } else {
                        self.uart_rbr
                    }
                }
                UART_REG_IER_DLM => {
                    if dlab {
                        self.uart_dlm
                    } else {
                        self.uart_ier
                    }
                }
                UART_REG_IIR_FCR => iir,
                UART_REG_LCR => self.uart_lcr,
                UART_REG_MCR => self.uart_mcr,
                UART_REG_LSR => lsr,
                UART_REG_MSR => 0,
                UART_REG_SCR => self.uart_scr,
                _ => 0,
            };

            if funct3 == FUNCT3_BYTE {
                ((read_byte as i8) as i32) as u32
            } else {
                read_byte as u32
            }
        } else {
            0
        };

        self.uart_irq = rx_irq_pending;

        UartStepResult {
            read_data,
            irq: self.uart_irq,
            tx_valid: tx_valid_now,
            tx_data: self.uart_tx_data_reg,
            rx_accept: rx_accept_now,
        }
    }

    fn virtio_step(
        &mut self,
        clk: u64,
        rst: u64,
        addr: u32,
        write_data: u32,
        mem_read: bool,
        mem_write: bool,
        funct3: u8,
    ) -> u32 {
        if rst == 1 {
            self.virtio_reset_state();
            self.virtio_prev_clk = clk;
            self.virtio_irq = false;
            return 0;
        }

        let word_access = funct3 == FUNCT3_WORD;

        if self.virtio_prev_clk == 0 && clk == 1 && mem_write && word_access {
            self.virtio_write_register(addr, write_data);
        }
        self.virtio_prev_clk = clk;

        self.virtio_irq = self.virtio_irq_asserted();

        if mem_read && word_access {
            self.virtio_read_register(addr)
        } else {
            0
        }
    }

    fn virtio_reset_state(&mut self) {
        self.virtio_device_features_sel = 0;
        self.virtio_driver_features_sel = 0;
        self.virtio_driver_features_0 = 0;
        self.virtio_driver_features_1 = 0;
        self.virtio_guest_page_size = 0;
        self.virtio_queue_sel = 0;
        self.virtio_queue_num = 0;
        self.virtio_queue_ready = 0;
        self.virtio_queue_desc = 0;
        self.virtio_queue_driver = 0;
        self.virtio_queue_device = 0;
        self.virtio_queue_pfn = 0;
        self.virtio_queue_align = 0;
        self.virtio_status = 0;
        self.virtio_interrupt_status = 0;
        self.virtio_notify_pending = false;
        self.virtio_last_avail_idx = 0;
    }

    fn virtio_queue_operational(&self) -> bool {
        let modern_queue_ready = self.virtio_queue_ready == 1
            && self.virtio_queue_desc != 0
            && self.virtio_queue_driver != 0
            && self.virtio_queue_device != 0;
        let legacy_queue_ready = self.virtio_queue_pfn != 0;
        self.virtio_queue_sel == 0
            && self.virtio_queue_num > 0
            && (self.virtio_status & VIRTIO_STATUS_DRIVER_OK) != 0
            && (modern_queue_ready || legacy_queue_ready)
    }

    fn virtio_irq_asserted(&self) -> bool {
        (self.virtio_interrupt_status & 0x3) != 0
    }

    fn virtio_capacity_sectors(&self) -> u64 {
        (self.disk.len() as u64) / VIRTIO_SECTOR_BYTES
    }

    fn virtio_device_features_for_sel(&self, _sel: u32) -> u32 {
        0
    }

    fn virtio_legacy_page_size(&self) -> u64 {
        if self.virtio_guest_page_size == 0 {
            4096
        } else {
            self.virtio_guest_page_size as u64
        }
    }

    fn virtio_legacy_queue_desc(&self) -> u64 {
        (self.virtio_queue_pfn as u64).wrapping_mul(self.virtio_legacy_page_size())
    }

    fn virtio_legacy_queue_driver(&self) -> u64 {
        self.virtio_legacy_queue_desc()
            .wrapping_add((self.virtio_queue_num as u64).wrapping_mul(16))
    }

    fn virtio_legacy_queue_device(&self) -> u64 {
        let avail_base = self.virtio_legacy_queue_driver();
        let avail_bytes = 6u64.wrapping_add((self.virtio_queue_num as u64).wrapping_mul(2));
        let align = if self.virtio_queue_align == 0 {
            4096
        } else {
            self.virtio_queue_align as u64
        };
        Self::virtio_align_up(avail_base.wrapping_add(avail_bytes), align)
    }

    fn virtio_queue_desc_addr(&self) -> u64 {
        if self.virtio_queue_desc != 0 {
            self.virtio_queue_desc
        } else if self.virtio_queue_pfn != 0 {
            self.virtio_legacy_queue_desc()
        } else {
            0
        }
    }

    fn virtio_queue_driver_addr(&self) -> u64 {
        if self.virtio_queue_driver != 0 {
            self.virtio_queue_driver
        } else if self.virtio_queue_pfn != 0 {
            self.virtio_legacy_queue_driver()
        } else {
            0
        }
    }

    fn virtio_queue_device_addr(&self) -> u64 {
        if self.virtio_queue_device != 0 {
            self.virtio_queue_device
        } else if self.virtio_queue_pfn != 0 {
            self.virtio_legacy_queue_device()
        } else {
            0
        }
    }

    fn virtio_align_up(value: u64, align: u64) -> u64 {
        if align <= 1 {
            return value;
        }
        if align.is_power_of_two() {
            let mask = align - 1;
            value.wrapping_add(mask) & !mask
        } else {
            let rem = value % align;
            if rem == 0 {
                value
            } else {
                value.wrapping_add(align - rem)
            }
        }
    }

    fn virtio_read_register(&self, addr: u32) -> u32 {
        match addr {
            VIRTIO_MAGIC_VALUE_ADDR => VIRTIO_MAGIC,
            VIRTIO_VERSION_ADDR => 1,
            VIRTIO_DEVICE_ID_ADDR => 2,
            VIRTIO_VENDOR_ID_ADDR => VIRTIO_VENDOR_ID,
            VIRTIO_DEVICE_FEATURES_ADDR => self.virtio_device_features_for_sel(self.virtio_device_features_sel),
            VIRTIO_DEVICE_FEATURES_SEL_ADDR => self.virtio_device_features_sel,
            VIRTIO_DRIVER_FEATURES_ADDR => {
                if self.virtio_driver_features_sel == 0 {
                    self.virtio_driver_features_0
                } else {
                    self.virtio_driver_features_1
                }
            }
            VIRTIO_DRIVER_FEATURES_SEL_ADDR => self.virtio_driver_features_sel,
            VIRTIO_GUEST_PAGE_SIZE_ADDR => self.virtio_guest_page_size,
            VIRTIO_QUEUE_SEL_ADDR => self.virtio_queue_sel,
            VIRTIO_QUEUE_NUM_MAX_ADDR => {
                if self.virtio_queue_sel == 0 {
                    VIRTIO_QUEUE_NUM_MAX as u32
                } else {
                    0
                }
            }
            VIRTIO_QUEUE_NUM_ADDR => {
                if self.virtio_queue_sel == 0 {
                    self.virtio_queue_num as u32
                } else {
                    0
                }
            }
            VIRTIO_QUEUE_ALIGN_ADDR => self.virtio_queue_align,
            VIRTIO_QUEUE_PFN_ADDR => self.virtio_queue_pfn,
            VIRTIO_QUEUE_READY_ADDR => {
                if self.virtio_queue_sel == 0 {
                    self.virtio_queue_ready
                } else {
                    0
                }
            }
            VIRTIO_INTERRUPT_STATUS_ADDR => self.virtio_interrupt_status & 0x3,
            VIRTIO_STATUS_ADDR => self.virtio_status & 0xFF,
            VIRTIO_QUEUE_DESC_LOW_ADDR => self.virtio_queue_desc as u32,
            VIRTIO_QUEUE_DESC_HIGH_ADDR => (self.virtio_queue_desc >> 32) as u32,
            VIRTIO_QUEUE_DRIVER_LOW_ADDR => self.virtio_queue_driver as u32,
            VIRTIO_QUEUE_DRIVER_HIGH_ADDR => (self.virtio_queue_driver >> 32) as u32,
            VIRTIO_QUEUE_DEVICE_LOW_ADDR => self.virtio_queue_device as u32,
            VIRTIO_QUEUE_DEVICE_HIGH_ADDR => (self.virtio_queue_device >> 32) as u32,
            VIRTIO_CONFIG_GENERATION_ADDR => 0,
            VIRTIO_CONFIG_CAPACITY_LOW_ADDR => self.virtio_capacity_sectors() as u32,
            VIRTIO_CONFIG_CAPACITY_HIGH_ADDR => (self.virtio_capacity_sectors() >> 32) as u32,
            _ => 0,
        }
    }

    fn virtio_write_register(&mut self, addr: u32, value: u32) {
        match addr {
            VIRTIO_DEVICE_FEATURES_SEL_ADDR => {
                self.virtio_device_features_sel = value & 0x1;
            }
            VIRTIO_DRIVER_FEATURES_SEL_ADDR => {
                self.virtio_driver_features_sel = value & 0x1;
            }
            VIRTIO_DRIVER_FEATURES_ADDR => {
                if self.virtio_driver_features_sel == 0 {
                    self.virtio_driver_features_0 = value;
                } else {
                    self.virtio_driver_features_1 = value;
                }
            }
            VIRTIO_GUEST_PAGE_SIZE_ADDR => {
                self.virtio_guest_page_size = value;
            }
            VIRTIO_QUEUE_SEL_ADDR => {
                self.virtio_queue_sel = value;
                if self.virtio_queue_sel != 0 {
                    self.virtio_last_avail_idx = 0;
                }
            }
            VIRTIO_QUEUE_NUM_ADDR => {
                if self.virtio_queue_sel == 0 {
                    let num = (value & 0xFFFF) as u16;
                    self.virtio_queue_num = num.max(1).min(VIRTIO_QUEUE_NUM_MAX);
                } else {
                    self.virtio_queue_num = 0;
                }
            }
            VIRTIO_QUEUE_ALIGN_ADDR => {
                self.virtio_queue_align = value;
            }
            VIRTIO_QUEUE_PFN_ADDR => {
                self.virtio_queue_pfn = value;
            }
            VIRTIO_QUEUE_READY_ADDR => {
                self.virtio_queue_ready = if self.virtio_queue_sel == 0 { value & 0x1 } else { 0 };
                if self.virtio_queue_ready == 0 {
                    self.virtio_last_avail_idx = 0;
                }
            }
            VIRTIO_QUEUE_NOTIFY_ADDR => {
                if (value & 0xFFFF) == 0 {
                    self.virtio_notify_pending = true;
                }
            }
            VIRTIO_INTERRUPT_ACK_ADDR => {
                self.virtio_interrupt_status &= !(value & 0x3);
            }
            VIRTIO_STATUS_ADDR => {
                if (value & 0xFF) == 0 {
                    self.virtio_reset_state();
                } else {
                    self.virtio_status = value & 0xFF;
                }
            }
            VIRTIO_QUEUE_DESC_LOW_ADDR => {
                self.virtio_queue_desc = (self.virtio_queue_desc & 0xFFFF_FFFF_0000_0000) | (value as u64);
            }
            VIRTIO_QUEUE_DESC_HIGH_ADDR => {
                self.virtio_queue_desc = ((value as u64) << 32) | (self.virtio_queue_desc & 0xFFFF_FFFF);
            }
            VIRTIO_QUEUE_DRIVER_LOW_ADDR => {
                self.virtio_queue_driver = (self.virtio_queue_driver & 0xFFFF_FFFF_0000_0000) | (value as u64);
            }
            VIRTIO_QUEUE_DRIVER_HIGH_ADDR => {
                self.virtio_queue_driver = ((value as u64) << 32) | (self.virtio_queue_driver & 0xFFFF_FFFF);
            }
            VIRTIO_QUEUE_DEVICE_LOW_ADDR => {
                self.virtio_queue_device = (self.virtio_queue_device & 0xFFFF_FFFF_0000_0000) | (value as u64);
            }
            VIRTIO_QUEUE_DEVICE_HIGH_ADDR => {
                self.virtio_queue_device = ((value as u64) << 32) | (self.virtio_queue_device & 0xFFFF_FFFF);
            }
            _ => {}
        }
    }

    fn virtio_service_queues(&mut self) {
        if !self.virtio_notify_pending {
            self.virtio_irq = self.virtio_irq_asserted();
            return;
        }

        self.virtio_notify_pending = false;
        if !self.virtio_queue_operational() {
            self.virtio_irq = self.virtio_irq_asserted();
            return;
        }

        let _ = self.virtio_process_available();
        self.virtio_irq = self.virtio_irq_asserted();
    }

    fn virtio_process_available(&mut self) -> bool {
        if self.virtio_queue_num == 0 {
            return false;
        }
        let queue_driver = self.virtio_queue_driver_addr();
        if queue_driver == 0 {
            return false;
        }

        let mut processed_any = false;
        let mut guard = 0usize;
        let max_guard = ((self.virtio_queue_num as usize) * 4).max(16);

        let mut avail_idx = self.virtio_mem_read_u16(queue_driver.wrapping_add(2));
        while self.virtio_last_avail_idx != avail_idx && guard < max_guard {
            let ring_slot = (self.virtio_last_avail_idx % self.virtio_queue_num) as u64;
            let head_idx = self.virtio_mem_read_u16(queue_driver.wrapping_add(4 + ring_slot * 2));
            self.virtio_process_one_request(head_idx);
            self.virtio_last_avail_idx = self.virtio_last_avail_idx.wrapping_add(1);
            processed_any = true;
            guard += 1;
            avail_idx = self.virtio_mem_read_u16(queue_driver.wrapping_add(2));
        }

        processed_any
    }

    fn virtio_process_one_request(&mut self, head_idx: u16) {
        let Some(desc0) = self.virtio_read_desc(head_idx) else {
            return;
        };
        if (desc0.flags & VIRTIO_DESC_F_NEXT) == 0 {
            return;
        }

        let Some(desc1) = self.virtio_read_desc(desc0.next) else {
            return;
        };
        if (desc1.flags & VIRTIO_DESC_F_NEXT) == 0 {
            return;
        }

        let Some(desc2) = self.virtio_read_desc(desc1.next) else {
            return;
        };

        let req_addr = desc0.addr;
        let req_type = self.virtio_mem_read_u32(req_addr);
        let sector = self.virtio_mem_read_u64(req_addr.wrapping_add(8));

        let success = self.virtio_transfer_data(req_type, sector, desc1.addr, desc1.len);
        self.virtio_mem_write_u8(desc2.addr, if success { 0 } else { 1 });
        self.virtio_push_used(head_idx, if success { desc1.len } else { 0 });
        self.virtio_interrupt_status |= VIRTIO_INTERRUPT_USED_BUFFER;
    }

    fn virtio_transfer_data(&mut self, req_type: u32, sector: u64, data_addr: u64, data_len: u32) -> bool {
        let disk_offset = sector.wrapping_mul(VIRTIO_SECTOR_BYTES);
        if disk_offset >= self.disk.len() as u64 {
            return false;
        }

        let len = data_len as usize;

        match req_type {
            VIRTIO_REQ_T_IN => {
                for idx in 0..len {
                    let src = disk_offset.wrapping_add(idx as u64) as usize;
                    let byte = if src < self.disk.len() { self.disk[src] } else { 0 };
                    self.virtio_mem_write_u8(data_addr.wrapping_add(idx as u64), byte);
                }
                true
            }
            VIRTIO_REQ_T_OUT => {
                for idx in 0..len {
                    let dst = disk_offset.wrapping_add(idx as u64) as usize;
                    if dst >= self.disk.len() {
                        break;
                    }
                    self.disk[dst] = self.virtio_mem_read_u8(data_addr.wrapping_add(idx as u64));
                }
                true
            }
            _ => false,
        }
    }

    fn virtio_push_used(&mut self, head_idx: u16, used_len: u32) {
        if self.virtio_queue_num == 0 {
            return;
        }
        let queue_device = self.virtio_queue_device_addr();
        if queue_device == 0 {
            return;
        }

        let used_idx = self.virtio_mem_read_u16(queue_device.wrapping_add(2));
        let slot = (used_idx % self.virtio_queue_num) as u64;
        let elem_addr = queue_device.wrapping_add(4 + slot * 8);
        self.virtio_mem_write_u32(elem_addr, head_idx as u32);
        self.virtio_mem_write_u32(elem_addr.wrapping_add(4), used_len);
        self.virtio_mem_write_u16(queue_device.wrapping_add(2), used_idx.wrapping_add(1));
    }

    fn virtio_read_desc(&self, desc_idx: u16) -> Option<VirtioDesc> {
        if self.virtio_queue_num == 0 || desc_idx >= self.virtio_queue_num {
            return None;
        }
        let queue_desc = self.virtio_queue_desc_addr();
        if queue_desc == 0 {
            return None;
        }

        let base = queue_desc.wrapping_add((desc_idx as u64) * 16);
        Some(VirtioDesc {
            addr: self.virtio_mem_read_u64(base),
            len: self.virtio_mem_read_u32(base.wrapping_add(8)),
            flags: self.virtio_mem_read_u16(base.wrapping_add(12)),
            next: self.virtio_mem_read_u16(base.wrapping_add(14)),
        })
    }

    fn virtio_mem_read_u8(&self, addr: u64) -> u8 {
        self.read_data_byte_raw(addr as u32)
    }

    fn virtio_mem_write_u8(&mut self, addr: u64, value: u8) {
        self.write_data_byte_raw(addr as u32, value);
    }

    fn virtio_mem_read_u16(&self, addr: u64) -> u16 {
        let lo = self.virtio_mem_read_u8(addr) as u16;
        let hi = self.virtio_mem_read_u8(addr.wrapping_add(1)) as u16;
        (hi << 8) | lo
    }

    fn virtio_mem_write_u16(&mut self, addr: u64, value: u16) {
        self.virtio_mem_write_u8(addr, (value & 0xFF) as u8);
        self.virtio_mem_write_u8(addr.wrapping_add(1), ((value >> 8) & 0xFF) as u8);
    }

    fn virtio_mem_read_u32(&self, addr: u64) -> u32 {
        self.read_data_word_raw(addr as u32)
    }

    fn virtio_mem_write_u32(&mut self, addr: u64, value: u32) {
        self.write_data_word_raw(addr as u32, value);
    }

    fn virtio_mem_read_u64(&self, addr: u64) -> u64 {
        let lo = self.virtio_mem_read_u32(addr) as u64;
        let hi = self.virtio_mem_read_u32(addr.wrapping_add(4)) as u64;
        (hi << 32) | lo
    }

    fn data_mem_step(
        &mut self,
        clk: u64,
        rst: u64,
        addr: u32,
        write_data: u32,
        mem_read: bool,
        mem_write: bool,
        funct3: u8,
    ) -> u32 {
        if rst == 1 {
            self.data_mem_prev_clk = clk;
            return 0;
        }

        let read_before_write = if mem_read {
            self.read_data_by_funct3(addr, funct3)
        } else {
            0
        };

        let mut write_happened = false;
        if self.data_mem_prev_clk == 0 && clk == 1 && mem_write {
            write_happened = true;
            self.write_data_by_funct3(addr, write_data, funct3);
        }
        self.data_mem_prev_clk = clk;

        if mem_read {
            if write_happened {
                read_before_write
            } else {
                self.read_data_by_funct3(addr, funct3)
            }
        } else {
            0
        }
    }

    fn read_data_by_funct3(&self, addr: u32, funct3: u8) -> u32 {
        match funct3 {
            FUNCT3_BYTE => (self.read_data_byte_raw(addr) as i8 as i32) as u32,
            FUNCT3_BYTE_U => self.read_data_byte_raw(addr) as u32,
            FUNCT3_HALF => (self.read_data_half_raw(addr) as i16 as i32) as u32,
            FUNCT3_HALF_U => self.read_data_half_raw(addr) as u32,
            FUNCT3_WORD => self.read_data_word_raw(addr),
            _ => 0,
        }
    }

    fn write_data_by_funct3(&mut self, addr: u32, value: u32, funct3: u8) {
        match funct3 {
            FUNCT3_BYTE | FUNCT3_BYTE_U => {
                self.write_data_byte_raw(addr, (value & 0xFF) as u8);
            }
            FUNCT3_HALF | FUNCT3_HALF_U => {
                self.write_data_byte_raw(addr, (value & 0xFF) as u8);
                self.write_data_byte_raw(addr.wrapping_add(1), ((value >> 8) & 0xFF) as u8);
            }
            FUNCT3_WORD => {
                self.write_data_word_raw(addr, value);
            }
            _ => {}
        }
    }

    fn read_inst_word_raw(&self, addr: u32) -> u32 {
        let b0 = self.read_inst_byte_raw(addr) as u32;
        let b1 = self.read_inst_byte_raw(addr.wrapping_add(1)) as u32;
        let b2 = self.read_inst_byte_raw(addr.wrapping_add(2)) as u32;
        let b3 = self.read_inst_byte_raw(addr.wrapping_add(3)) as u32;
        b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    fn read_data_word_raw(&self, addr: u32) -> u32 {
        let b0 = self.read_data_byte_raw(addr) as u32;
        let b1 = self.read_data_byte_raw(addr.wrapping_add(1)) as u32;
        let b2 = self.read_data_byte_raw(addr.wrapping_add(2)) as u32;
        let b3 = self.read_data_byte_raw(addr.wrapping_add(3)) as u32;
        b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    fn write_data_word_raw(&mut self, addr: u32, value: u32) {
        self.write_data_byte_raw(addr, (value & 0xFF) as u8);
        self.write_data_byte_raw(addr.wrapping_add(1), ((value >> 8) & 0xFF) as u8);
        self.write_data_byte_raw(addr.wrapping_add(2), ((value >> 16) & 0xFF) as u8);
        self.write_data_byte_raw(addr.wrapping_add(3), ((value >> 24) & 0xFF) as u8);
    }

    fn read_data_half_raw(&self, addr: u32) -> u16 {
        let lo = self.read_data_byte_raw(addr) as u16;
        let hi = self.read_data_byte_raw(addr.wrapping_add(1)) as u16;
        (hi << 8) | lo
    }

    fn read_inst_byte_raw(&self, addr: u32) -> u8 {
        if self.inst_mem.is_empty() {
            return 0;
        }
        let idx = wrap_index(self.inst_mem.len(), addr as usize);
        self.inst_mem[idx]
    }

    fn read_data_byte_raw(&self, addr: u32) -> u8 {
        if self.data_mem.is_empty() {
            return 0;
        }
        let idx = wrap_index(self.data_mem.len(), addr as usize);
        self.data_mem[idx]
    }

    fn write_data_byte_raw(&mut self, addr: u32, value: u8) {
        if self.data_mem.is_empty() {
            return;
        }
        let idx = wrap_index(self.data_mem.len(), addr as usize);
        self.data_mem[idx] = value;
        if !self.inst_mem.is_empty() {
            let inst_idx = wrap_index(self.inst_mem.len(), addr as usize);
            self.inst_mem[inst_idx] = value;
        }
    }

    fn signal(&self, core: &CoreSimulator, idx: usize) -> u64 {
        if idx < core.signals.len() {
            core.signals[idx]
        } else {
            0
        }
    }

    fn set_signal(&self, core: &mut CoreSimulator, idx: usize, value: u64) {
        if idx < core.signals.len() {
            core.signals[idx] = value;
        }
    }
}

fn idx(name_to_idx: &HashMap<String, usize>, name: &str) -> usize {
    *name_to_idx.get(name).unwrap_or(&0)
}

fn wrap_index(len: usize, addr: usize) -> usize {
    if len == 0 {
        return 0;
    }
    if len.is_power_of_two() {
        addr & (len - 1)
    } else {
        addr % len
    }
}

fn load_wrapped(mem: &mut [u8], offset: usize, data: &[u8]) -> usize {
    if mem.is_empty() || data.is_empty() {
        return 0;
    }
    let len = mem.len();
    for (i, byte) in data.iter().enumerate() {
        let idx = wrap_index(len, offset.wrapping_add(i));
        mem[idx] = *byte;
    }
    data.len()
}

fn read_wrapped(mem: &[u8], start: usize, out: &mut [u8]) -> usize {
    if mem.is_empty() || out.is_empty() {
        return 0;
    }
    let len = mem.len();
    for (i, slot) in out.iter_mut().enumerate() {
        let idx = wrap_index(len, start.wrapping_add(i));
        *slot = mem[idx];
    }
    out.len()
}

fn clint_access(addr: u32) -> bool {
    matches!(
        addr,
        CLINT_MSIP_ADDR
            | CLINT_MTIMECMP_LOW_ADDR
            | CLINT_MTIMECMP_HIGH_ADDR
            | CLINT_MTIME_LOW_ADDR
            | CLINT_MTIME_HIGH_ADDR
    )
}

fn plic_access(addr: u32) -> bool {
    matches!(
        addr,
        PLIC_PRIORITY_1_ADDR
            | PLIC_PRIORITY_10_ADDR
            | PLIC_PENDING_ADDR
            | PLIC_ENABLE_ADDR
            | PLIC_SENABLE_ADDR
            | PLIC_THRESHOLD_ADDR
            | PLIC_STHRESHOLD_ADDR
            | PLIC_CLAIM_COMPLETE_ADDR
            | PLIC_SCLAIM_COMPLETE_ADDR
    )
}

fn uart_access(addr: u32) -> bool {
    if addr < UART_BASE {
        return false;
    }
    let offset = addr - UART_BASE;
    matches!(
        offset,
        UART_REG_THR_RBR_DLL
            | UART_REG_IER_DLM
            | UART_REG_IIR_FCR
            | UART_REG_LCR
            | UART_REG_MCR
            | UART_REG_LSR
            | UART_REG_MSR
            | UART_REG_SCR
    )
}

fn virtio_access(addr: u32) -> bool {
    matches!(
        addr,
        VIRTIO_MAGIC_VALUE_ADDR
            | VIRTIO_VERSION_ADDR
            | VIRTIO_DEVICE_ID_ADDR
            | VIRTIO_VENDOR_ID_ADDR
            | VIRTIO_DEVICE_FEATURES_ADDR
            | VIRTIO_DEVICE_FEATURES_SEL_ADDR
            | VIRTIO_DRIVER_FEATURES_ADDR
            | VIRTIO_DRIVER_FEATURES_SEL_ADDR
            | VIRTIO_GUEST_PAGE_SIZE_ADDR
            | VIRTIO_QUEUE_SEL_ADDR
            | VIRTIO_QUEUE_NUM_MAX_ADDR
            | VIRTIO_QUEUE_NUM_ADDR
            | VIRTIO_QUEUE_ALIGN_ADDR
            | VIRTIO_QUEUE_PFN_ADDR
            | VIRTIO_QUEUE_READY_ADDR
            | VIRTIO_QUEUE_NOTIFY_ADDR
            | VIRTIO_INTERRUPT_STATUS_ADDR
            | VIRTIO_INTERRUPT_ACK_ADDR
            | VIRTIO_STATUS_ADDR
            | VIRTIO_QUEUE_DESC_LOW_ADDR
            | VIRTIO_QUEUE_DESC_HIGH_ADDR
            | VIRTIO_QUEUE_DRIVER_LOW_ADDR
            | VIRTIO_QUEUE_DRIVER_HIGH_ADDR
            | VIRTIO_QUEUE_DEVICE_LOW_ADDR
            | VIRTIO_QUEUE_DEVICE_HIGH_ADDR
            | VIRTIO_CONFIG_GENERATION_ADDR
            | VIRTIO_CONFIG_CAPACITY_LOW_ADDR
            | VIRTIO_CONFIG_CAPACITY_HIGH_ADDR
    )
}
