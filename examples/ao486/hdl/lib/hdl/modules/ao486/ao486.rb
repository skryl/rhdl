# frozen_string_literal: true

class Ao486 < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: ao486

  def self._import_decl_kinds
    {
      acflag: :wire,
      avm_address_pre: :wire,
      cr0_am: :wire,
      cr0_cd: :wire,
      cr0_nw: :wire,
      cr0_pg: :wire,
      cr0_wp: :wire,
      cr3: :wire,
      cs_cache: :wire,
      dec_eip: :wire,
      dec_gp_fault: :wire,
      dec_pf_fault: :wire,
      dec_ud_fault: :wire,
      eip: :wire,
      exc_debug_start: :wire,
      exc_dec_reset: :wire,
      exc_eip: :wire,
      exc_error_code: :wire,
      exc_exe_reset: :wire,
      exc_init: :wire,
      exc_load: :wire,
      exc_micro_reset: :wire,
      exc_pf_check: :wire,
      exc_pf_code: :wire,
      exc_pf_read: :wire,
      exc_pf_write: :wire,
      exc_push_error: :wire,
      exc_rd_reset: :wire,
      exc_restore_esp: :wire,
      exc_set_rflag: :wire,
      exc_soft_int: :wire,
      exc_soft_int_ib: :wire,
      exc_vector: :wire,
      exc_wr_reset: :wire,
      exe_bound_fault: :wire,
      exe_consumed: :wire,
      exe_div_exception: :wire,
      exe_eip: :wire,
      exe_error_code: :wire,
      exe_is_front: :wire,
      exe_load_seg_gp_fault: :wire,
      exe_load_seg_np_fault: :wire,
      exe_load_seg_ss_fault: :wire,
      exe_reset: :wire,
      exe_trigger_db_fault: :wire,
      exe_trigger_gp_fault: :wire,
      exe_trigger_nm_fault: :wire,
      exe_trigger_np_fault: :wire,
      exe_trigger_pf_fault: :wire,
      exe_trigger_ss_fault: :wire,
      exe_trigger_ts_fault: :wire,
      glob_desc_2_limit: :wire,
      glob_desc_base: :wire,
      glob_desc_limit: :wire,
      glob_descriptor: :wire,
      glob_descriptor_2: :wire,
      glob_descriptor_2_set: :wire,
      glob_descriptor_2_value: :wire,
      glob_descriptor_set: :wire,
      glob_descriptor_value: :wire,
      glob_param_1: :wire,
      glob_param_1_set: :wire,
      glob_param_1_value: :wire,
      glob_param_2: :wire,
      glob_param_2_set: :wire,
      glob_param_2_value: :wire,
      glob_param_3: :wire,
      glob_param_3_set: :wire,
      glob_param_3_value: :wire,
      glob_param_4: :wire,
      glob_param_4_set: :wire,
      glob_param_4_value: :wire,
      glob_param_5: :wire,
      glob_param_5_set: :wire,
      glob_param_5_value: :wire,
      invdcode_do: :wire,
      invdcode_done: :wire,
      invddata_do: :wire,
      invddata_done: :wire,
      pipeline_after_prefetch_empty: :wire,
      pipeline_after_read_empty: :wire,
      pr_reset: :wire,
      prefetch_cpl: :wire,
      prefetch_eip: :wire,
      prefetchfifo_accept_data: :wire,
      prefetchfifo_accept_do: :wire,
      prefetchfifo_accept_empty: :wire,
      rd_consumed: :wire,
      rd_dec_is_front: :wire,
      rd_descriptor_gp_fault: :wire,
      rd_eip: :wire,
      rd_error_code: :wire,
      rd_io_allow_fault: :wire,
      rd_is_front: :wire,
      rd_reset: :wire,
      rd_seg_gp_fault: :wire,
      rd_seg_ss_fault: :wire,
      rd_ss_esp_from_tss_fault: :wire,
      read_ac_fault: :wire,
      read_address: :wire,
      read_cpl: :wire,
      read_data: :wire,
      read_do: :wire,
      read_done: :wire,
      read_length: :wire,
      read_lock: :wire,
      read_page_fault: :wire,
      read_rmw: :wire,
      real_mode: :wire,
      tlb_check_pf_cr2: :wire,
      tlb_check_pf_error_code: :wire,
      tlb_code_pf_cr2: :wire,
      tlb_code_pf_error_code: :wire,
      tlb_read_pf_cr2: :wire,
      tlb_read_pf_error_code: :wire,
      tlb_write_pf_cr2: :wire,
      tlb_write_pf_error_code: :wire,
      tlbcheck_address: :wire,
      tlbcheck_do: :wire,
      tlbcheck_done: :wire,
      tlbcheck_page_fault: :wire,
      tlbcheck_rw: :wire,
      tlbflushall_do: :wire,
      tlbflushsingle_address: :wire,
      tlbflushsingle_do: :wire,
      tlbflushsingle_done: :wire,
      wbinvddata_do: :wire,
      wbinvddata_done: :wire,
      wr_consumed: :wire,
      wr_debug_init: :wire,
      wr_eip: :wire,
      wr_error_code: :wire,
      wr_exception_external_set: :wire,
      wr_exception_finished: :wire,
      wr_int: :wire,
      wr_int_soft_int: :wire,
      wr_int_soft_int_ib: :wire,
      wr_int_vector: :wire,
      wr_interrupt_possible: :wire,
      wr_is_esp_speculative: :wire,
      wr_is_front: :wire,
      wr_new_push_ss_fault: :wire,
      wr_push_ss_fault: :wire,
      wr_reset: :wire,
      wr_string_es_fault: :wire,
      wr_string_in_progress_final: :wire,
      write_ac_fault: :wire,
      write_address: :wire,
      write_cpl: :wire,
      write_data: :wire,
      write_do: :wire,
      write_done: :wire,
      write_length: :wire,
      write_lock: :wire,
      write_page_fault: :wire,
      write_rmw: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :a20_enable
  input :cache_disable
  input :interrupt_do
  input :interrupt_vector, width: 8
  output :interrupt_done
  output :avm_address, width: 30
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
  output :io_read_do
  output :io_read_address, width: 16
  output :io_read_length, width: 3
  input :io_read_data, width: 32
  input :io_read_done
  output :io_write_do
  output :io_write_address, width: 16
  output :io_write_length, width: 3
  output :io_write_data, width: 32
  input :io_write_done

  # Signals

  signal :acflag
  signal :avm_address_pre, width: (31..2)
  signal :cr0_am
  signal :cr0_cd
  signal :cr0_nw
  signal :cr0_pg
  signal :cr0_wp
  signal :cr3, width: 32
  signal :cs_cache, width: 64
  signal :dec_eip, width: 32
  signal :dec_gp_fault
  signal :dec_pf_fault
  signal :dec_ud_fault
  signal :eip, width: 32
  signal :exc_debug_start
  signal :exc_dec_reset
  signal :exc_eip, width: 32
  signal :exc_error_code, width: 16
  signal :exc_exe_reset
  signal :exc_init
  signal :exc_load
  signal :exc_micro_reset
  signal :exc_pf_check
  signal :exc_pf_code
  signal :exc_pf_read
  signal :exc_pf_write
  signal :exc_push_error
  signal :exc_rd_reset
  signal :exc_restore_esp
  signal :exc_set_rflag
  signal :exc_soft_int
  signal :exc_soft_int_ib
  signal :exc_vector, width: 8
  signal :exc_wr_reset
  signal :exe_bound_fault
  signal :exe_consumed, width: 4
  signal :exe_div_exception
  signal :exe_eip, width: 32
  signal :exe_error_code, width: 16
  signal :exe_is_front
  signal :exe_load_seg_gp_fault
  signal :exe_load_seg_np_fault
  signal :exe_load_seg_ss_fault
  signal :exe_reset
  signal :exe_trigger_db_fault
  signal :exe_trigger_gp_fault
  signal :exe_trigger_nm_fault
  signal :exe_trigger_np_fault
  signal :exe_trigger_pf_fault
  signal :exe_trigger_ss_fault
  signal :exe_trigger_ts_fault
  signal :glob_desc_2_limit, width: 32
  signal :glob_desc_base, width: 32
  signal :glob_desc_limit, width: 32
  signal :glob_descriptor, width: 64
  signal :glob_descriptor_2, width: 64
  signal :glob_descriptor_2_set
  signal :glob_descriptor_2_value, width: 64
  signal :glob_descriptor_set
  signal :glob_descriptor_value, width: 64
  signal :glob_param_1, width: 32
  signal :glob_param_1_set
  signal :glob_param_1_value, width: 32
  signal :glob_param_2, width: 32
  signal :glob_param_2_set
  signal :glob_param_2_value, width: 32
  signal :glob_param_3, width: 32
  signal :glob_param_3_set
  signal :glob_param_3_value, width: 32
  signal :glob_param_4, width: 32
  signal :glob_param_4_set
  signal :glob_param_4_value, width: 32
  signal :glob_param_5, width: 32
  signal :glob_param_5_set
  signal :glob_param_5_value, width: 32
  signal :invdcode_do
  signal :invdcode_done
  signal :invddata_do
  signal :invddata_done
  signal :pipeline_after_prefetch_empty
  signal :pipeline_after_read_empty
  signal :pr_reset
  signal :prefetch_cpl, width: 2
  signal :prefetch_eip, width: 32
  signal :prefetchfifo_accept_data, width: 68
  signal :prefetchfifo_accept_do
  signal :prefetchfifo_accept_empty
  signal :rd_consumed, width: 4
  signal :rd_dec_is_front
  signal :rd_descriptor_gp_fault
  signal :rd_eip, width: 32
  signal :rd_error_code, width: 16
  signal :rd_io_allow_fault
  signal :rd_is_front
  signal :rd_reset
  signal :rd_seg_gp_fault
  signal :rd_seg_ss_fault
  signal :rd_ss_esp_from_tss_fault
  signal :read_ac_fault
  signal :read_address, width: 32
  signal :read_cpl, width: 2
  signal :read_data, width: 64
  signal :read_do
  signal :read_done
  signal :read_length, width: 4
  signal :read_lock
  signal :read_page_fault
  signal :read_rmw
  signal :real_mode
  signal :tlb_check_pf_cr2, width: 32
  signal :tlb_check_pf_error_code, width: 16
  signal :tlb_code_pf_cr2, width: 32
  signal :tlb_code_pf_error_code, width: 16
  signal :tlb_read_pf_cr2, width: 32
  signal :tlb_read_pf_error_code, width: 16
  signal :tlb_write_pf_cr2, width: 32
  signal :tlb_write_pf_error_code, width: 16
  signal :tlbcheck_address, width: 32
  signal :tlbcheck_do
  signal :tlbcheck_done
  signal :tlbcheck_page_fault
  signal :tlbcheck_rw
  signal :tlbflushall_do
  signal :tlbflushsingle_address, width: 32
  signal :tlbflushsingle_do
  signal :tlbflushsingle_done
  signal :wbinvddata_do
  signal :wbinvddata_done
  signal :wr_consumed, width: 4
  signal :wr_debug_init
  signal :wr_eip, width: 32
  signal :wr_error_code, width: 16
  signal :wr_exception_external_set
  signal :wr_exception_finished
  signal :wr_int
  signal :wr_int_soft_int
  signal :wr_int_soft_int_ib
  signal :wr_int_vector, width: 8
  signal :wr_interrupt_possible
  signal :wr_is_esp_speculative
  signal :wr_is_front
  signal :wr_new_push_ss_fault
  signal :wr_push_ss_fault
  signal :wr_reset
  signal :wr_string_es_fault
  signal :wr_string_in_progress_final
  signal :write_ac_fault
  signal :write_address, width: 32
  signal :write_cpl, width: 2
  signal :write_data, width: 32
  signal :write_do
  signal :write_done
  signal :write_length, width: 3
  signal :write_lock
  signal :write_page_fault
  signal :write_rmw

  # Assignments

  assign :avm_address,
    sig(:avm_address_pre, width: 30)[29..19].concat(
      (
          sig(:avm_address_pre, width: 30)[18] &
          sig(:a20_enable, width: 1)
      ).concat(
        sig(:avm_address_pre, width: 30)[17..0]
      )
    )

  # Instances

  instance :exception_inst, "exception"
  instance :global_regs_inst, "global_regs"
  instance :memory_inst, "memory",
    ports: {
      avm_address: :avm_address_pre
    }
  instance :pipeline_inst, "pipeline"

end
