# frozen_string_literal: true

class Memory < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: memory

  def self._import_decl_kinds
    {
      delivered_eip: :wire,
      icacheread_address: :wire,
      icacheread_do: :wire,
      icacheread_length: :wire,
      prefetch_address: :wire,
      prefetch_length: :wire,
      prefetch_su: :wire,
      prefetched_do: :wire,
      prefetched_length: :wire,
      prefetchfifo_signal_limit_do: :wire,
      prefetchfifo_signal_pf_do: :wire,
      prefetchfifo_used: :wire,
      prefetchfifo_write_data: :wire,
      prefetchfifo_write_do: :wire,
      req_dcacheread_address: :wire,
      req_dcacheread_cache_disable: :wire,
      req_dcacheread_data: :wire,
      req_dcacheread_do: :wire,
      req_dcacheread_done: :wire,
      req_dcacheread_length: :wire,
      req_dcachewrite_address: :wire,
      req_dcachewrite_cache_disable: :wire,
      req_dcachewrite_data: :wire,
      req_dcachewrite_do: :wire,
      req_dcachewrite_done: :wire,
      req_dcachewrite_length: :wire,
      req_dcachewrite_write_through: :wire,
      req_readcode_address: :wire,
      req_readcode_do: :wire,
      req_readcode_done: :wire,
      req_readcode_partial: :wire,
      reset_prefetch: :wire,
      resp_dcacheread_address: :wire,
      resp_dcacheread_cache_disable: :wire,
      resp_dcacheread_data: :wire,
      resp_dcacheread_do: :wire,
      resp_dcacheread_done: :wire,
      resp_dcacheread_length: :wire,
      resp_dcachewrite_address: :wire,
      resp_dcachewrite_cache_disable: :wire,
      resp_dcachewrite_data: :wire,
      resp_dcachewrite_do: :wire,
      resp_dcachewrite_done: :wire,
      resp_dcachewrite_length: :wire,
      resp_dcachewrite_write_through: :wire,
      snoop_addr: :wire,
      snoop_be: :wire,
      snoop_data: :wire,
      snoop_we: :wire,
      tlbcode_cache_disable: :wire,
      tlbcode_do: :wire,
      tlbcode_linear: :wire,
      tlbcode_physical: :wire,
      tlbcoderequest_address: :wire,
      tlbcoderequest_do: :wire,
      tlbcoderequest_su: :wire,
      tlbread_ac_fault: :wire,
      tlbread_address: :wire,
      tlbread_cpl: :wire,
      tlbread_data: :wire,
      tlbread_do: :wire,
      tlbread_done: :wire,
      tlbread_length: :wire,
      tlbread_length_full: :wire,
      tlbread_lock: :wire,
      tlbread_page_fault: :wire,
      tlbread_retry: :wire,
      tlbread_rmw: :wire,
      tlbwrite_ac_fault: :wire,
      tlbwrite_address: :wire,
      tlbwrite_cpl: :wire,
      tlbwrite_data: :wire,
      tlbwrite_do: :wire,
      tlbwrite_done: :wire,
      tlbwrite_length: :wire,
      tlbwrite_length_full: :wire,
      tlbwrite_lock: :wire,
      tlbwrite_page_fault: :wire,
      tlbwrite_rmw: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :cache_disable
  input :read_do
  output :read_done
  output :read_page_fault
  output :read_ac_fault
  input :read_cpl, width: 2
  input :read_address, width: 32
  input :read_length, width: 4
  input :read_lock
  input :read_rmw
  output :read_data, width: 64
  input :write_do
  output :write_done
  output :write_page_fault
  output :write_ac_fault
  input :write_cpl, width: 2
  input :write_address, width: 32
  input :write_length, width: 3
  input :write_lock
  input :write_rmw
  input :write_data, width: 32
  input :tlbcheck_do
  output :tlbcheck_done
  output :tlbcheck_page_fault
  input :tlbcheck_address, width: 32
  input :tlbcheck_rw
  input :tlbflushsingle_do
  output :tlbflushsingle_done
  input :tlbflushsingle_address, width: 32
  input :tlbflushall_do
  input :invdcode_do
  output :invdcode_done
  input :invddata_do
  output :invddata_done
  input :wbinvddata_do
  output :wbinvddata_done
  input :prefetch_cpl, width: 2
  input :prefetch_eip, width: 32
  input :cs_cache, width: 64
  input :cr0_pg
  input :cr0_wp
  input :cr0_am
  input :cr0_cd
  input :cr0_nw
  input :acflag
  input :cr3, width: 32
  input :prefetchfifo_accept_do
  output :prefetchfifo_accept_data, width: 68
  output :prefetchfifo_accept_empty
  input :pipeline_after_read_empty
  input :pipeline_after_prefetch_empty
  output :tlb_code_pf_cr2, width: 32
  output :tlb_code_pf_error_code, width: 16
  output :tlb_check_pf_cr2, width: 32
  output :tlb_check_pf_error_code, width: 16
  output :tlb_write_pf_cr2, width: 32
  output :tlb_write_pf_error_code, width: 16
  output :tlb_read_pf_cr2, width: 32
  output :tlb_read_pf_error_code, width: 16
  input :pr_reset
  input :rd_reset
  input :exe_reset
  input :wr_reset
  output :avm_address, width: (31..2)
  output :avm_writedata, width: 32
  output :avm_byteenable, width: 4
  output :avm_burstcount, width: 4
  output :avm_write
  output :avm_read
  input :avm_waitrequest
  input :avm_readdatavalid
  input :avm_readdata, width: 32
  input :dma_address, width: 24
  input :dma_16bit
  input :dma_write
  input :dma_writedata, width: 16
  input :dma_read
  output :dma_readdata, width: 16
  output :dma_readdatavalid
  output :dma_waitrequest

  # Signals

  signal :delivered_eip, width: 32
  signal :icacheread_address, width: 32
  signal :icacheread_do
  signal :icacheread_length, width: 5
  signal :prefetch_address, width: 32
  signal :prefetch_length, width: 5
  signal :prefetch_su
  signal :prefetched_do
  signal :prefetched_length, width: 5
  signal :prefetchfifo_signal_limit_do
  signal :prefetchfifo_signal_pf_do
  signal :prefetchfifo_used, width: 5
  signal :prefetchfifo_write_data, width: 36
  signal :prefetchfifo_write_do
  signal :req_dcacheread_address, width: 32
  signal :req_dcacheread_cache_disable
  signal :req_dcacheread_data, width: 64
  signal :req_dcacheread_do
  signal :req_dcacheread_done
  signal :req_dcacheread_length, width: 4
  signal :req_dcachewrite_address, width: 32
  signal :req_dcachewrite_cache_disable
  signal :req_dcachewrite_data, width: 32
  signal :req_dcachewrite_do
  signal :req_dcachewrite_done
  signal :req_dcachewrite_length, width: 3
  signal :req_dcachewrite_write_through
  signal :req_readcode_address, width: 32
  signal :req_readcode_do
  signal :req_readcode_done
  signal :req_readcode_partial, width: 32
  signal :reset_prefetch
  signal :resp_dcacheread_address, width: 32
  signal :resp_dcacheread_cache_disable
  signal :resp_dcacheread_data, width: 64
  signal :resp_dcacheread_do
  signal :resp_dcacheread_done
  signal :resp_dcacheread_length, width: 4
  signal :resp_dcachewrite_address, width: 32
  signal :resp_dcachewrite_cache_disable
  signal :resp_dcachewrite_data, width: 32
  signal :resp_dcachewrite_do
  signal :resp_dcachewrite_done
  signal :resp_dcachewrite_length, width: 3
  signal :resp_dcachewrite_write_through
  signal :snoop_addr, width: (27..2)
  signal :snoop_be, width: 4
  signal :snoop_data, width: 32
  signal :snoop_we
  signal :tlbcode_cache_disable
  signal :tlbcode_do
  signal :tlbcode_linear, width: 32
  signal :tlbcode_physical, width: 32
  signal :tlbcoderequest_address, width: 32
  signal :tlbcoderequest_do
  signal :tlbcoderequest_su
  signal :tlbread_ac_fault
  signal :tlbread_address, width: 32
  signal :tlbread_cpl, width: 2
  signal :tlbread_data, width: 64
  signal :tlbread_do
  signal :tlbread_done
  signal :tlbread_length, width: 4
  signal :tlbread_length_full, width: 4
  signal :tlbread_lock
  signal :tlbread_page_fault
  signal :tlbread_retry
  signal :tlbread_rmw
  signal :tlbwrite_ac_fault
  signal :tlbwrite_address, width: 32
  signal :tlbwrite_cpl, width: 2
  signal :tlbwrite_data, width: 32
  signal :tlbwrite_do
  signal :tlbwrite_done
  signal :tlbwrite_length, width: 3
  signal :tlbwrite_length_full, width: 3
  signal :tlbwrite_lock
  signal :tlbwrite_page_fault
  signal :tlbwrite_rmw

  # Processes

  process :initial_block_0,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :invddata_done,
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :initial_block_1,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :wbinvddata_done,
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  process :initial_block_2,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :invdcode_done,
      lit(1, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  # Instances

  instance :link_dcacheread_inst, "link_dcacheread"
  instance :link_dcachewrite_inst, "link_dcachewrite"
  instance :avalon_mem_inst, "avalon_mem",
    ports: {
      writeburst_do: :resp_dcachewrite_do,
      writeburst_done: :resp_dcachewrite_done,
      writeburst_address: :resp_dcachewrite_address,
      writeburst_length: :resp_dcachewrite_length,
      writeburst_data_in: :resp_dcachewrite_data,
      readburst_do: :resp_dcacheread_do,
      readburst_done: :resp_dcacheread_done,
      readburst_address: :resp_dcacheread_address,
      readburst_length: :resp_dcacheread_length,
      readburst_data_out: :resp_dcacheread_data,
      readcode_do: :req_readcode_do,
      readcode_done: :req_readcode_done,
      readcode_address: :req_readcode_address,
      readcode_partial: :req_readcode_partial
    }
  instance :icache_inst, "icache",
    ports: {
      readcode_do: :req_readcode_do,
      readcode_done: :req_readcode_done,
      readcode_address: :req_readcode_address,
      readcode_partial: :req_readcode_partial
    }
  instance :memory_read_inst, "memory_read"
  instance :memory_write_inst, "memory_write"
  instance :prefetch_inst, "prefetch",
    ports: {
      prefetched_accept_do: :prefetchfifo_accept_do,
      prefetched_accept_length: sig(:prefetchfifo_accept_data, width: 68)[67..64]
    }
  instance :prefetch_fifo_inst, "prefetch_fifo",
    ports: {
      pr_reset: (sig(:pr_reset, width: 1) | sig(:reset_prefetch, width: 1))
    }
  instance :prefetch_control_inst, "prefetch_control",
    ports: {
      pr_reset: (sig(:pr_reset, width: 1) | sig(:reset_prefetch, width: 1)),
      icacheread_cache_disable: :__rhdl_unconnected
    }
  instance :tlb_inst, "tlb",
    ports: {
      dcacheread_do: :req_dcacheread_do,
      dcacheread_done: :req_dcacheread_done,
      dcacheread_length: :req_dcacheread_length,
      dcacheread_cache_disable: :req_dcacheread_cache_disable,
      dcacheread_address: :req_dcacheread_address,
      dcacheread_data: :req_dcacheread_data,
      dcachewrite_do: :req_dcachewrite_do,
      dcachewrite_done: :req_dcachewrite_done,
      dcachewrite_length: :req_dcachewrite_length,
      dcachewrite_cache_disable: :req_dcachewrite_cache_disable,
      dcachewrite_address: :req_dcachewrite_address,
      dcachewrite_write_through: :req_dcachewrite_write_through,
      dcachewrite_data: :req_dcachewrite_data
    }

end
