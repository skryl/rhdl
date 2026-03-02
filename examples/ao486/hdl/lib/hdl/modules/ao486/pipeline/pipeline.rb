# frozen_string_literal: true

class Pipeline < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: pipeline

  def self._import_decl_kinds
    {
      aflag: :wire,
      cflag: :wire,
      cpl: :wire,
      cr0_em: :wire,
      cr0_mp: :wire,
      cr0_ne: :wire,
      cr0_pe: :wire,
      cr0_ts: :wire,
      cr2: :wire,
      cs: :wire,
      cs_cache_valid: :wire,
      debug_len0: :wire,
      debug_len1: :wire,
      debug_len2: :wire,
      debug_len3: :wire,
      dec_acceptable: :wire,
      dec_address_32bit: :wire,
      dec_cmd: :wire,
      dec_cmdex: :wire,
      dec_consumed: :wire,
      dec_is_8bit: :wire,
      dec_is_complex: :wire,
      dec_modregrm_len: :wire,
      dec_operand_32bit: :wire,
      dec_prefix_2byte: :wire,
      dec_prefix_group_1_lock: :wire,
      dec_prefix_group_1_rep: :wire,
      dec_prefix_group_2_seg: :wire,
      dec_ready: :wire,
      dec_reset: :wire,
      decoder: :wire,
      dflag: :wire,
      dr0: :wire,
      dr1: :wire,
      dr2: :wire,
      dr3: :wire,
      dr6_b12: :wire,
      dr6_bd: :wire,
      dr6_bd_set: :wire,
      dr6_breakpoints: :wire,
      dr6_bs: :wire,
      dr6_bt: :wire,
      dr7: :wire,
      ds: :wire,
      ds_cache: :wire,
      ds_cache_valid: :wire,
      dst_final: :wire,
      dst_wire: :wire,
      eax: :wire,
      ebp: :wire,
      ebx: :wire,
      ecx: :wire,
      edi: :wire,
      edx: :wire,
      es: :wire,
      es_cache: :wire,
      es_cache_valid: :wire,
      esi: :wire,
      esp: :wire,
      exe_address_32bit: :wire,
      exe_arith_adc_carry: :wire,
      exe_arith_add_carry: :wire,
      exe_arith_index: :wire,
      exe_arith_sbb_carry: :wire,
      exe_arith_sub_carry: :wire,
      exe_buffer: :wire,
      exe_buffer_shifted: :wire,
      exe_busy: :wire,
      exe_cmd: :wire,
      exe_cmdex: :wire,
      exe_consumed_final: :wire,
      exe_debug_read: :wire,
      exe_decoder: :wire,
      exe_dst_is_eax: :wire,
      exe_dst_is_edx_eax: :wire,
      exe_dst_is_implicit_reg: :wire,
      exe_dst_is_memory: :wire,
      exe_dst_is_reg: :wire,
      exe_dst_is_rm: :wire,
      exe_eip_final: :wire,
      exe_glob_descriptor_2_set: :wire,
      exe_glob_descriptor_2_value: :wire,
      exe_glob_descriptor_set: :wire,
      exe_glob_descriptor_value: :wire,
      exe_glob_param_1_set: :wire,
      exe_glob_param_1_value: :wire,
      exe_glob_param_2_set: :wire,
      exe_glob_param_2_value: :wire,
      exe_glob_param_3_set: :wire,
      exe_glob_param_3_value: :wire,
      exe_is_8bit_final: :wire,
      exe_linear: :wire,
      exe_mult_overflow: :wire,
      exe_mutex: :wire,
      exe_operand_32bit: :wire,
      exe_prefix_group_1_lock: :wire,
      exe_prefix_group_1_rep: :wire,
      exe_ready: :wire,
      exe_result: :wire,
      exe_result2: :wire,
      exe_result_push: :wire,
      exe_result_signals: :wire,
      exe_stack_offset: :wire,
      fetch: :wire,
      fetch_limit: :wire,
      fetch_page_fault: :wire,
      fetch_valid: :wire,
      fs: :wire,
      fs_cache: :wire,
      fs_cache_valid: :wire,
      gdtr_base: :wire,
      gdtr_limit: :wire,
      gs: :wire,
      gs_cache: :wire,
      gs_cache_valid: :wire,
      idflag: :wire,
      idtr_base: :wire,
      idtr_limit: :wire,
      iflag: :wire,
      io_allow_check_needed: :wire,
      iopl: :wire,
      ldtr: :wire,
      ldtr_cache: :wire,
      ldtr_cache_valid: :wire,
      micro_address_32bit: :wire,
      micro_busy: :wire,
      micro_cmd: :wire,
      micro_cmdex: :wire,
      micro_consumed: :wire,
      micro_decoder: :wire,
      micro_eip: :wire,
      micro_is_8bit: :wire,
      micro_modregrm_len: :wire,
      micro_operand_32bit: :wire,
      micro_prefix_2byte: :wire,
      micro_prefix_group_1_lock: :wire,
      micro_prefix_group_1_rep: :wire,
      micro_prefix_group_2_seg: :wire,
      micro_ready: :wire,
      micro_reset: :wire,
      ntflag: :wire,
      oflag: :wire,
      pflag: :wire,
      pipeline_dec_idle: :wire,
      pipeline_dec_idle_counter: :reg,
      protected_mode: :wire,
      rd_address_32bit: :wire,
      rd_address_effective: :wire,
      rd_busy: :wire,
      rd_cmd: :wire,
      rd_cmdex: :wire,
      rd_debug_read: :wire,
      rd_decoder: :wire,
      rd_dst_is_eax: :wire,
      rd_dst_is_edx_eax: :wire,
      rd_dst_is_implicit_reg: :wire,
      rd_dst_is_memory: :wire,
      rd_dst_is_reg: :wire,
      rd_dst_is_rm: :wire,
      rd_extra_wire: :wire,
      rd_glob_descriptor_2_set: :wire,
      rd_glob_descriptor_2_value: :wire,
      rd_glob_descriptor_set: :wire,
      rd_glob_descriptor_value: :wire,
      rd_glob_param_1_set: :wire,
      rd_glob_param_1_value: :wire,
      rd_glob_param_2_set: :wire,
      rd_glob_param_2_value: :wire,
      rd_glob_param_3_set: :wire,
      rd_glob_param_3_value: :wire,
      rd_glob_param_4_set: :wire,
      rd_glob_param_4_value: :wire,
      rd_glob_param_5_set: :wire,
      rd_glob_param_5_value: :wire,
      rd_is_8bit: :wire,
      rd_linear: :wire,
      rd_modregrm_imm: :wire,
      rd_mutex_next: :wire,
      rd_operand_32bit: :wire,
      rd_prefix_2byte: :wire,
      rd_prefix_group_1_lock: :wire,
      rd_prefix_group_1_rep: :wire,
      rd_ready: :wire,
      rflag: :wire,
      sflag: :wire,
      src_final: :wire,
      src_wire: :wire,
      ss: :wire,
      ss_cache: :wire,
      ss_cache_valid: :wire,
      task_eip: :wire,
      tflag: :wire,
      tr: :wire,
      tr_cache: :wire,
      tr_cache_valid: :wire,
      v8086_mode: :wire,
      vmflag: :wire,
      wr_busy: :wire,
      wr_esp_prev: :wire,
      wr_glob_param_1_set: :wire,
      wr_glob_param_1_value: :wire,
      wr_glob_param_3_set: :wire,
      wr_glob_param_3_value: :wire,
      wr_glob_param_4_set: :wire,
      wr_glob_param_4_value: :wire,
      wr_mutex: :wire,
      wr_req_reset_dec: :wire,
      wr_req_reset_exe: :wire,
      wr_req_reset_micro: :wire,
      wr_req_reset_pr: :wire,
      wr_req_reset_rd: :wire,
      wr_stack_offset: :wire,
      wr_task_rpl: :wire,
      zflag: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  output :pr_reset
  output :rd_reset
  output :exe_reset
  output :wr_reset
  output :real_mode
  input :exc_restore_esp
  input :exc_set_rflag
  input :exc_debug_start
  input :exc_init
  input :exc_load
  input :exc_eip, width: 32
  input :exc_vector, width: 8
  input :exc_error_code, width: 16
  input :exc_push_error
  input :exc_soft_int
  input :exc_soft_int_ib
  input :exc_pf_read
  input :exc_pf_write
  input :exc_pf_code
  input :exc_pf_check
  output :eip, width: 32
  output :dec_eip, width: 32
  output :rd_eip, width: 32
  output :exe_eip, width: 32
  output :wr_eip, width: 32
  output :rd_consumed, width: 4
  output :exe_consumed, width: 4
  output :wr_consumed, width: 4
  input :exc_dec_reset
  input :exc_micro_reset
  input :exc_rd_reset
  input :exc_exe_reset
  input :exc_wr_reset
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_param_4, width: 32
  input :glob_param_5, width: 32
  input :glob_descriptor, width: 64
  input :glob_descriptor_2, width: 64
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :glob_desc_2_limit, width: 32
  output :rd_dec_is_front
  output :rd_is_front
  output :exe_is_front
  output :wr_is_front
  output :pipeline_after_read_empty
  output :pipeline_after_prefetch_empty
  output :dec_gp_fault
  output :dec_ud_fault
  output :dec_pf_fault
  output :rd_io_allow_fault
  output :rd_descriptor_gp_fault
  output :rd_seg_gp_fault
  output :rd_seg_ss_fault
  output :rd_ss_esp_from_tss_fault
  output :exe_bound_fault
  output :exe_trigger_gp_fault
  output :exe_trigger_ts_fault
  output :exe_trigger_ss_fault
  output :exe_trigger_np_fault
  output :exe_trigger_pf_fault
  output :exe_trigger_db_fault
  output :exe_trigger_nm_fault
  output :exe_load_seg_gp_fault
  output :exe_load_seg_ss_fault
  output :exe_load_seg_np_fault
  output :exe_div_exception
  output :wr_debug_init
  output :wr_new_push_ss_fault
  output :wr_string_es_fault
  output :wr_push_ss_fault
  output :rd_error_code, width: 16
  output :exe_error_code, width: 16
  output :wr_error_code, width: 16
  output :glob_descriptor_set
  output :glob_descriptor_value, width: 64
  output :glob_descriptor_2_set
  output :glob_descriptor_2_value, width: 64
  output :glob_param_1_set
  output :glob_param_1_value, width: 32
  output :glob_param_2_set
  output :glob_param_2_value, width: 32
  output :glob_param_3_set
  output :glob_param_3_value, width: 32
  output :glob_param_4_set
  output :glob_param_4_value, width: 32
  output :glob_param_5_set
  output :glob_param_5_value, width: 32
  output :prefetch_cpl, width: 2
  output :prefetch_eip, width: 32
  output :cs_cache, width: 64
  output :cr0_pg
  output :cr0_wp
  output :cr0_am
  output :cr0_cd
  output :cr0_nw
  output :acflag
  output :cr3, width: 32
  output :prefetchfifo_accept_do
  input :prefetchfifo_accept_data, width: 68
  input :prefetchfifo_accept_empty
  output :io_read_do
  output :io_read_address, width: 16
  output :io_read_length, width: 3
  input :io_read_data, width: 32
  input :io_read_done
  output :read_do
  input :read_done
  input :read_page_fault
  input :read_ac_fault
  output :read_cpl, width: 2
  output :read_address, width: 32
  output :read_length, width: 4
  output :read_lock
  output :read_rmw
  input :read_data, width: 64
  output :tlbcheck_do
  input :tlbcheck_done
  input :tlbcheck_page_fault
  output :tlbcheck_address, width: 32
  output :tlbcheck_rw
  output :tlbflushsingle_do
  input :tlbflushsingle_done
  output :tlbflushsingle_address, width: 32
  output :tlbflushall_do
  output :invdcode_do
  input :invdcode_done
  output :invddata_do
  input :invddata_done
  output :wbinvddata_do
  input :wbinvddata_done
  input :interrupt_do
  output :wr_interrupt_possible
  output :wr_string_in_progress_final
  output :wr_is_esp_speculative
  output :wr_int
  output :wr_int_soft_int
  output :wr_int_soft_int_ib
  output :wr_int_vector, width: 8
  output :wr_exception_external_set
  output :wr_exception_finished
  input :tlb_code_pf_cr2, width: 32
  input :tlb_write_pf_cr2, width: 32
  input :tlb_read_pf_cr2, width: 32
  input :tlb_check_pf_cr2, width: 32
  output :write_do
  input :write_done
  input :write_page_fault
  input :write_ac_fault
  output :write_cpl, width: 2
  output :write_address, width: 32
  output :write_length, width: 3
  output :write_lock
  output :write_rmw
  output :write_data, width: 32
  output :io_write_do
  output :io_write_address, width: 16
  output :io_write_length, width: 3
  output :io_write_data, width: 32
  input :io_write_done

  # Signals

  signal :aflag
  signal :cflag
  signal :cpl, width: 2
  signal :cr0_em
  signal :cr0_mp
  signal :cr0_ne
  signal :cr0_pe
  signal :cr0_ts
  signal :cr2, width: 32
  signal :cs, width: 16
  signal :cs_cache_valid
  signal :debug_len0, width: 3
  signal :debug_len1, width: 3
  signal :debug_len2, width: 3
  signal :debug_len3, width: 3
  signal :dec_acceptable, width: 4
  signal :dec_address_32bit
  signal :dec_cmd, width: 7
  signal :dec_cmdex, width: 4
  signal :dec_consumed, width: 4
  signal :dec_is_8bit
  signal :dec_is_complex
  signal :dec_modregrm_len, width: 3
  signal :dec_operand_32bit
  signal :dec_prefix_2byte
  signal :dec_prefix_group_1_lock
  signal :dec_prefix_group_1_rep, width: 2
  signal :dec_prefix_group_2_seg, width: 3
  signal :dec_ready
  signal :dec_reset
  signal :decoder, width: 96
  signal :dflag
  signal :dr0, width: 32
  signal :dr1, width: 32
  signal :dr2, width: 32
  signal :dr3, width: 32
  signal :dr6_b12
  signal :dr6_bd
  signal :dr6_bd_set
  signal :dr6_breakpoints, width: 4
  signal :dr6_bs
  signal :dr6_bt
  signal :dr7, width: 32
  signal :ds, width: 16
  signal :ds_cache, width: 64
  signal :ds_cache_valid
  signal :dst_final, width: 32
  signal :dst_wire, width: 32
  signal :eax, width: 32
  signal :ebp, width: 32
  signal :ebx, width: 32
  signal :ecx, width: 32
  signal :edi, width: 32
  signal :edx, width: 32
  signal :es, width: 16
  signal :es_cache, width: 64
  signal :es_cache_valid
  signal :esi, width: 32
  signal :esp, width: 32
  signal :exe_address_32bit
  signal :exe_arith_adc_carry
  signal :exe_arith_add_carry
  signal :exe_arith_index, width: 4
  signal :exe_arith_sbb_carry
  signal :exe_arith_sub_carry
  signal :exe_buffer, width: 32
  signal :exe_buffer_shifted, width: 464
  signal :exe_busy
  signal :exe_cmd, width: 7
  signal :exe_cmdex, width: 4
  signal :exe_consumed_final, width: 4
  signal :exe_debug_read, width: 4
  signal :exe_decoder, width: 40
  signal :exe_dst_is_eax
  signal :exe_dst_is_edx_eax
  signal :exe_dst_is_implicit_reg
  signal :exe_dst_is_memory
  signal :exe_dst_is_reg
  signal :exe_dst_is_rm
  signal :exe_eip_final, width: 32
  signal :exe_glob_descriptor_2_set
  signal :exe_glob_descriptor_2_value, width: 64
  signal :exe_glob_descriptor_set
  signal :exe_glob_descriptor_value, width: 64
  signal :exe_glob_param_1_set
  signal :exe_glob_param_1_value, width: 32
  signal :exe_glob_param_2_set
  signal :exe_glob_param_2_value, width: 32
  signal :exe_glob_param_3_set
  signal :exe_glob_param_3_value, width: 32
  signal :exe_is_8bit_final
  signal :exe_linear, width: 32
  signal :exe_mult_overflow
  signal :exe_mutex, width: 11
  signal :exe_operand_32bit
  signal :exe_prefix_group_1_lock
  signal :exe_prefix_group_1_rep, width: 2
  signal :exe_ready
  signal :exe_result, width: 32
  signal :exe_result2, width: 32
  signal :exe_result_push, width: 32
  signal :exe_result_signals, width: 5
  signal :exe_stack_offset, width: 32
  signal :fetch, width: 64
  signal :fetch_limit
  signal :fetch_page_fault
  signal :fetch_valid, width: 4
  signal :fs, width: 16
  signal :fs_cache, width: 64
  signal :fs_cache_valid
  signal :gdtr_base, width: 32
  signal :gdtr_limit, width: 16
  signal :gs, width: 16
  signal :gs_cache, width: 64
  signal :gs_cache_valid
  signal :idflag
  signal :idtr_base, width: 32
  signal :idtr_limit, width: 16
  signal :iflag
  signal :io_allow_check_needed
  signal :iopl, width: 2
  signal :ldtr, width: 16
  signal :ldtr_cache, width: 64
  signal :ldtr_cache_valid
  signal :micro_address_32bit
  signal :micro_busy
  signal :micro_cmd, width: 7
  signal :micro_cmdex, width: 4
  signal :micro_consumed, width: 4
  signal :micro_decoder, width: 88
  signal :micro_eip, width: 32
  signal :micro_is_8bit
  signal :micro_modregrm_len, width: 3
  signal :micro_operand_32bit
  signal :micro_prefix_2byte
  signal :micro_prefix_group_1_lock
  signal :micro_prefix_group_1_rep, width: 2
  signal :micro_prefix_group_2_seg, width: 3
  signal :micro_ready
  signal :micro_reset
  signal :ntflag
  signal :oflag
  signal :pflag
  signal :pipeline_dec_idle
  signal :pipeline_dec_idle_counter, width: 2
  signal :protected_mode
  signal :rd_address_32bit
  signal :rd_address_effective, width: 32
  signal :rd_busy
  signal :rd_cmd, width: 7
  signal :rd_cmdex, width: 4
  signal :rd_debug_read, width: 4
  signal :rd_decoder, width: 88
  signal :rd_dst_is_eax
  signal :rd_dst_is_edx_eax
  signal :rd_dst_is_implicit_reg
  signal :rd_dst_is_memory
  signal :rd_dst_is_reg
  signal :rd_dst_is_rm
  signal :rd_extra_wire, width: 32
  signal :rd_glob_descriptor_2_set
  signal :rd_glob_descriptor_2_value, width: 64
  signal :rd_glob_descriptor_set
  signal :rd_glob_descriptor_value, width: 64
  signal :rd_glob_param_1_set
  signal :rd_glob_param_1_value, width: 32
  signal :rd_glob_param_2_set
  signal :rd_glob_param_2_value, width: 32
  signal :rd_glob_param_3_set
  signal :rd_glob_param_3_value, width: 32
  signal :rd_glob_param_4_set
  signal :rd_glob_param_4_value, width: 32
  signal :rd_glob_param_5_set
  signal :rd_glob_param_5_value, width: 32
  signal :rd_is_8bit
  signal :rd_linear, width: 32
  signal :rd_modregrm_imm, width: 32
  signal :rd_mutex_next, width: 11
  signal :rd_operand_32bit
  signal :rd_prefix_2byte
  signal :rd_prefix_group_1_lock
  signal :rd_prefix_group_1_rep, width: 2
  signal :rd_ready
  signal :rflag
  signal :sflag
  signal :src_final, width: 32
  signal :src_wire, width: 32
  signal :ss, width: 16
  signal :ss_cache, width: 64
  signal :ss_cache_valid
  signal :task_eip, width: 32
  signal :tflag
  signal :tr, width: 16
  signal :tr_cache, width: 64
  signal :tr_cache_valid
  signal :v8086_mode
  signal :vmflag
  signal :wr_busy
  signal :wr_esp_prev, width: 32
  signal :wr_glob_param_1_set
  signal :wr_glob_param_1_value, width: 32
  signal :wr_glob_param_3_set
  signal :wr_glob_param_3_value, width: 32
  signal :wr_glob_param_4_set
  signal :wr_glob_param_4_value, width: 32
  signal :wr_mutex, width: 11
  signal :wr_req_reset_dec
  signal :wr_req_reset_exe
  signal :wr_req_reset_micro
  signal :wr_req_reset_pr
  signal :wr_req_reset_rd
  signal :wr_stack_offset, width: 32
  signal :wr_task_rpl, width: 2
  signal :zflag

  # Assignments

  assign :prefetch_cpl,
    sig(:cpl, width: 2)
  assign :pipeline_dec_idle,
    (
        sig(:prefetchfifo_accept_empty, width: 1) &
        sig(:rd_dec_is_front, width: 1)
    )
  assign :pipeline_after_prefetch_empty,
    (
        sig(:pipeline_dec_idle, width: 1) &
        (
            lit(3, width: 2, base: "h", signed: false) ==
            sig(:pipeline_dec_idle_counter, width: 2)
        )
    )
  assign :pipeline_after_read_empty,
    sig(:rd_is_front, width: 1)
  assign :glob_descriptor_set,
    (
        sig(:exe_glob_descriptor_set, width: 1) |
        sig(:rd_glob_descriptor_set, width: 1)
    )
  assign :glob_descriptor_value,
    mux(
      sig(:rd_glob_descriptor_set, width: 1),
      sig(:rd_glob_descriptor_value, width: 64),
      sig(:exe_glob_descriptor_value, width: 64)
    )
  assign :glob_descriptor_2_set,
    (
        sig(:exe_glob_descriptor_2_set, width: 1) |
        sig(:rd_glob_descriptor_2_set, width: 1)
    )
  assign :glob_descriptor_2_value,
    mux(
      sig(:rd_glob_descriptor_2_set, width: 1),
      sig(:rd_glob_descriptor_2_value, width: 64),
      sig(:exe_glob_descriptor_2_value, width: 64)
    )
  assign :glob_param_1_set,
    (
        sig(:rd_glob_param_1_set, width: 1) |
        (
            sig(:exe_glob_param_1_set, width: 1) |
            sig(:wr_glob_param_1_set, width: 1)
        )
    )
  assign :glob_param_1_value,
    mux(
      sig(:rd_glob_param_1_set, width: 1),
      sig(:rd_glob_param_1_value, width: 32),
      mux(
        sig(:exe_glob_param_1_set, width: 1),
        sig(:exe_glob_param_1_value, width: 32),
        sig(:wr_glob_param_1_value, width: 32)
      )
    )
  assign :glob_param_2_set,
    (
        sig(:exe_glob_param_2_set, width: 1) |
        sig(:rd_glob_param_2_set, width: 1)
    )
  assign :glob_param_2_value,
    mux(
      sig(:rd_glob_param_2_set, width: 1),
      sig(:rd_glob_param_2_value, width: 32),
      sig(:exe_glob_param_2_value, width: 32)
    )
  assign :glob_param_3_set,
    (
        sig(:rd_glob_param_3_set, width: 1) |
        (
            sig(:exe_glob_param_3_set, width: 1) |
            sig(:wr_glob_param_3_set, width: 1)
        )
    )
  assign :glob_param_3_value,
    mux(
      sig(:rd_glob_param_3_set, width: 1),
      sig(:rd_glob_param_3_value, width: 32),
      mux(
        sig(:exe_glob_param_3_set, width: 1),
        sig(:exe_glob_param_3_value, width: 32),
        sig(:wr_glob_param_3_value, width: 32)
      )
    )
  assign :glob_param_4_set,
    (
        sig(:rd_glob_param_4_set, width: 1) |
        sig(:wr_glob_param_4_set, width: 1)
    )
  assign :glob_param_4_value,
    mux(
      sig(:rd_glob_param_4_set, width: 1),
      sig(:rd_glob_param_4_value, width: 32),
      sig(:wr_glob_param_4_value, width: 32)
    )
  assign :glob_param_5_set,
    sig(:rd_glob_param_5_set, width: 1)
  assign :glob_param_5_value,
    sig(:rd_glob_param_5_value, width: 32)
  assign :pr_reset,
    sig(:wr_req_reset_pr, width: 1)
  assign :dec_reset,
    (
        sig(:exc_dec_reset, width: 1) |
        sig(:wr_req_reset_dec, width: 1)
    )
  assign :micro_reset,
    (
        sig(:exc_micro_reset, width: 1) |
        sig(:wr_req_reset_micro, width: 1)
    )
  assign :rd_reset,
    (
        sig(:exc_rd_reset, width: 1) |
        sig(:wr_req_reset_rd, width: 1)
    )
  assign :exe_reset,
    (
        sig(:exc_exe_reset, width: 1) |
        sig(:wr_req_reset_exe, width: 1)
    )
  assign :wr_reset,
    sig(:exc_wr_reset, width: 1)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:pipeline_dec_idle, width: 1) & (lit(3, width: 2, base: "h", signed: false) > sig(:pipeline_dec_idle_counter, width: 2)))) do
        assign(
          :pipeline_dec_idle_counter,
          (
              lit(1, width: 2, base: "h", signed: false) +
              sig(:pipeline_dec_idle_counter, width: 2)
          ),
          kind: :nonblocking
        )
        else_block do
          if_stmt((~sig(:pipeline_dec_idle, width: 1))) do
            assign(
              :pipeline_dec_idle_counter,
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :pipeline_dec_idle_counter,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  # Instances

  instance :fetch_inst, "fetch"
  instance :decode_inst, "decode"
  instance :microcode_inst, "microcode"
  instance :read_inst, "read"
  instance :execute_inst, "execute"
  instance :write_inst, "write"
  instance :cpu_export_inst, "cpu_export"

end
