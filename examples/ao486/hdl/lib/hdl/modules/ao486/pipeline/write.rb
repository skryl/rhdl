# frozen_string_literal: true

class Write < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write

  def self._import_decl_kinds
    {
      __VdfgRegularize_hc955b938_0_0: :logic,
      __VdfgRegularize_hc955b938_0_1: :logic,
      __VdfgRegularize_hc955b938_0_2: :logic,
      __VdfgRegularize_hc955b938_0_3: :logic,
      __VdfgRegularize_hc955b938_0_4: :logic,
      __VdfgRegularize_hc955b938_0_5: :logic,
      __VdfgRegularize_hc955b938_0_6: :logic,
      __VdfgRegularize_hc955b938_0_7: :logic,
      _unused_ok: :wire,
      acflag_to_reg: :wire,
      aflag_to_reg: :wire,
      cflag_to_reg: :wire,
      cr0_am_to_reg: :wire,
      cr0_cd_to_reg: :wire,
      cr0_em_to_reg: :wire,
      cr0_mp_to_reg: :wire,
      cr0_ne_to_reg: :wire,
      cr0_nw_to_reg: :wire,
      cr0_pe_to_reg: :wire,
      cr0_pg_to_reg: :wire,
      cr0_ts_to_reg: :wire,
      cr0_wp_to_reg: :wire,
      cr2_to_reg: :wire,
      cr3_to_reg: :wire,
      cs_base: :wire,
      cs_cache_to_reg: :wire,
      cs_cache_valid_to_reg: :wire,
      cs_limit: :wire,
      cs_rpl: :wire,
      cs_rpl_to_reg: :wire,
      cs_to_reg: :wire,
      dflag_to_reg: :wire,
      dr0_to_reg: :wire,
      dr1_to_reg: :wire,
      dr2_to_reg: :wire,
      dr3_to_reg: :wire,
      dr6_b12_to_reg: :wire,
      dr6_bd_to_reg: :wire,
      dr6_breakpoints_to_reg: :wire,
      dr6_bs_to_reg: :wire,
      dr6_bt_to_reg: :wire,
      dr7_to_reg: :wire,
      ds_cache_to_reg: :wire,
      ds_cache_valid_to_reg: :wire,
      ds_rpl: :wire,
      ds_rpl_to_reg: :wire,
      ds_to_reg: :wire,
      eax_to_reg: :wire,
      ebp_to_reg: :wire,
      ebx_to_reg: :wire,
      ecx_to_reg: :wire,
      edi_to_reg: :wire,
      edx_to_reg: :wire,
      es_base: :wire,
      es_cache_to_reg: :wire,
      es_cache_valid_to_reg: :wire,
      es_limit: :wire,
      es_rpl: :wire,
      es_rpl_to_reg: :wire,
      es_to_reg: :wire,
      esi_to_reg: :wire,
      esp_to_reg: :wire,
      fs_cache_to_reg: :wire,
      fs_cache_valid_to_reg: :wire,
      fs_rpl: :wire,
      fs_rpl_to_reg: :wire,
      fs_to_reg: :wire,
      gdtr_base_to_reg: :wire,
      gdtr_limit_to_reg: :wire,
      gs_cache_to_reg: :wire,
      gs_cache_valid_to_reg: :wire,
      gs_rpl: :wire,
      gs_rpl_to_reg: :wire,
      gs_to_reg: :wire,
      idflag_to_reg: :wire,
      idtr_base_to_reg: :wire,
      idtr_limit_to_reg: :wire,
      iflag_to_reg: :wire,
      iopl_to_reg: :wire,
      ldtr_cache_to_reg: :wire,
      ldtr_cache_valid_to_reg: :wire,
      ldtr_rpl: :wire,
      ldtr_rpl_to_reg: :wire,
      ldtr_to_reg: :wire,
      memory_write_system: :wire,
      ntflag_to_reg: :wire,
      oflag_to_reg: :wire,
      pflag_to_reg: :wire,
      result: :reg,
      result2: :reg,
      result_push: :reg,
      result_signals: :reg,
      rflag_to_reg: :wire,
      sflag_to_reg: :wire,
      ss_base: :wire,
      ss_cache_to_reg: :wire,
      ss_cache_valid_to_reg: :wire,
      ss_limit: :wire,
      ss_rpl: :wire,
      ss_rpl_to_reg: :wire,
      ss_to_reg: :wire,
      tflag_to_reg: :wire,
      tr_base: :wire,
      tr_cache_to_reg: :wire,
      tr_rpl: :wire,
      tr_rpl_to_reg: :wire,
      tr_to_reg: :wire,
      vmflag_to_reg: :wire,
      wr_address_16bit: :wire,
      wr_address_32bit: :reg,
      wr_arith_adc_carry: :reg,
      wr_arith_add_carry: :reg,
      wr_arith_index: :reg,
      wr_arith_sbb_carry: :reg,
      wr_arith_sub_carry: :reg,
      wr_clear_rflag: :wire,
      wr_cmd: :reg,
      wr_cmdex: :reg,
      wr_debug_code_reg: :wire,
      wr_debug_prepare: :wire,
      wr_debug_read_reg: :wire,
      wr_debug_step_reg: :wire,
      wr_debug_task_reg: :wire,
      wr_debug_task_trigger: :wire,
      wr_debug_trap_clear: :wire,
      wr_debug_write_reg: :wire,
      wr_decoder: :reg,
      wr_dst: :reg,
      wr_dst_is_eax: :reg,
      wr_dst_is_edx_eax: :reg,
      wr_dst_is_implicit_reg: :reg,
      wr_dst_is_memory: :reg,
      wr_dst_is_reg: :reg,
      wr_dst_is_rm: :reg,
      wr_ecx_final: :wire,
      wr_edi_final: :wire,
      wr_esi_final: :wire,
      wr_finished: :wire,
      wr_first_cycle: :reg,
      wr_hlt_in_progress: :wire,
      wr_inhibit_interrupts: :wire,
      wr_inhibit_interrupts_and_debug: :wire,
      wr_interrupt_possible_prepare: :wire,
      wr_is_8bit: :reg,
      wr_linear: :reg,
      wr_make_esp_commit: :wire,
      wr_make_esp_speculative: :wire,
      wr_modregrm_mod: :wire,
      wr_modregrm_reg: :wire,
      wr_modregrm_rm: :wire,
      wr_mult_overflow: :reg,
      wr_new_push_linear: :wire,
      wr_new_push_ss_fault_check: :wire,
      wr_new_stack_esp: :wire,
      wr_not_finished: :wire,
      wr_one_cycle_wait: :wire,
      wr_operand_16bit: :wire,
      wr_operand_32bit: :reg,
      wr_prefix_group_1_lock: :reg,
      wr_prefix_group_1_rep: :reg,
      wr_push_length: :wire,
      wr_push_length_dword: :wire,
      wr_push_length_word: :wire,
      wr_push_linear: :wire,
      wr_push_ss_fault_check: :wire,
      wr_ready: :wire,
      wr_regrm_dword: :wire,
      wr_regrm_word: :wire,
      wr_seg_cache_mask: :wire,
      wr_seg_cache_valid: :wire,
      wr_seg_rpl: :wire,
      wr_seg_sel: :wire,
      wr_src: :reg,
      wr_stack_esp: :wire,
      wr_string_es_linear: :wire,
      wr_string_finish: :wire,
      wr_string_gp_fault_check: :wire,
      wr_string_ignore: :wire,
      wr_string_in_progress: :wire,
      wr_string_in_progress_last: :reg,
      wr_string_zf_finish: :wire,
      wr_system_dword: :wire,
      wr_system_linear: :wire,
      wr_validate_seg_regs: :wire,
      wr_waiting: :wire,
      wr_zflag_result: :wire,
      write_eax: :wire,
      write_for_wr_ready: :wire,
      write_io: :wire,
      write_length_dword: :wire,
      write_length_word: :wire,
      write_new_stack_virtual: :wire,
      write_regrm: :wire,
      write_rmw_system_dword: :wire,
      write_rmw_virtual: :wire,
      write_seg_cache: :wire,
      write_seg_cache_valid: :wire,
      write_seg_rpl: :wire,
      write_seg_sel: :wire,
      write_stack_virtual: :wire,
      write_string_es_virtual: :wire,
      write_system_busy_tss: :wire,
      write_system_dword: :wire,
      write_system_touch: :wire,
      write_system_word: :wire,
      write_virtual: :wire,
      zflag_to_reg: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :exe_reset
  input :wr_reset
  input :glob_descriptor, width: 64
  input :glob_descriptor_2, width: 64
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_param_4, width: 32
  input :glob_param_5, width: 32
  input :eip, width: 32
  output :gdtr_base, width: 32
  output :gdtr_limit, width: 16
  output :idtr_base, width: 32
  output :idtr_limit, width: 16
  input :exe_buffer, width: 32
  input :exe_buffer_shifted, width: 464
  input :dr6_bd_set
  input :interrupt_do
  input :exc_init
  input :exc_set_rflag
  input :exc_debug_start
  input :exc_pf_read
  input :exc_pf_write
  input :exc_pf_code
  input :exc_pf_check
  input :exc_restore_esp
  input :exc_push_error
  input :exc_eip, width: 32
  output :real_mode
  output :v8086_mode
  output :protected_mode
  output :cpl, width: 2
  output :io_allow_check_needed
  output :debug_len0, width: 3
  output :debug_len1, width: 3
  output :debug_len2, width: 3
  output :debug_len3, width: 3
  output :wr_is_front
  output :wr_interrupt_possible
  output :wr_string_in_progress_final
  output :wr_is_esp_speculative
  output :wr_mutex, width: 11
  output :wr_stack_offset, width: 32
  output :wr_esp_prev, width: 32
  output :wr_task_rpl, width: 2
  output :wr_consumed, width: 4
  output :wr_int
  output :wr_int_soft_int
  output :wr_int_soft_int_ib
  output :wr_int_vector, width: 8
  output :wr_exception_external_set
  output :wr_exception_finished
  output :wr_error_code, width: 16
  output :wr_debug_init
  output :wr_new_push_ss_fault
  output :wr_string_es_fault
  output :wr_push_ss_fault
  output :wr_eip, width: 32
  output :wr_req_reset_pr
  output :wr_req_reset_dec
  output :wr_req_reset_micro
  output :wr_req_reset_rd
  output :wr_req_reset_exe
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
  output :tlbflushall_do
  output :io_write_do
  output :io_write_address, width: 16
  output :io_write_length, width: 3
  output :io_write_data, width: 32
  input :io_write_done
  output :wr_glob_param_1_set
  output :wr_glob_param_1_value, width: 32
  output :wr_glob_param_3_set
  output :wr_glob_param_3_value, width: 32
  output :wr_glob_param_4_set
  output :wr_glob_param_4_value, width: 32
  output :eax, width: 32
  output :ebx, width: 32
  output :ecx, width: 32
  output :edx, width: 32
  output :esi, width: 32
  output :edi, width: 32
  output :ebp, width: 32
  output :esp, width: 32
  output :cr0_pe
  output :cr0_mp
  output :cr0_em
  output :cr0_ts
  output :cr0_ne
  output :cr0_wp
  output :cr0_am
  output :cr0_nw
  output :cr0_cd
  output :cr0_pg
  output :cr2, width: 32
  output :cr3, width: 32
  output :cflag
  output :pflag
  output :aflag
  output :zflag
  output :sflag
  output :oflag
  output :tflag
  output :iflag
  output :dflag
  output :iopl, width: 2
  output :ntflag
  output :rflag
  output :vmflag
  output :acflag
  output :idflag
  output :dr0, width: 32
  output :dr1, width: 32
  output :dr2, width: 32
  output :dr3, width: 32
  output :dr6_breakpoints, width: 4
  output :dr6_b12
  output :dr6_bd
  output :dr6_bs
  output :dr6_bt
  output :dr7, width: 32
  output :es, width: 16
  output :ds, width: 16
  output :ss, width: 16
  output :fs, width: 16
  output :gs, width: 16
  output :cs, width: 16
  output :ldtr, width: 16
  output :tr, width: 16
  output :es_cache, width: 64
  output :ds_cache, width: 64
  output :ss_cache, width: 64
  output :fs_cache, width: 64
  output :gs_cache, width: 64
  output :cs_cache, width: 64
  output :ldtr_cache, width: 64
  output :tr_cache, width: 64
  output :es_cache_valid
  output :ds_cache_valid
  output :ss_cache_valid
  output :fs_cache_valid
  output :gs_cache_valid
  output :cs_cache_valid
  output :ldtr_cache_valid
  output :tr_cache_valid
  output :wr_busy
  input :exe_ready
  input :exe_decoder, width: 40
  input :exe_eip_final, width: 32
  input :exe_operand_32bit
  input :exe_address_32bit
  input :exe_prefix_group_1_rep, width: 2
  input :exe_prefix_group_1_lock
  input :exe_consumed_final, width: 4
  input :exe_is_8bit_final
  input :exe_cmd, width: 7
  input :exe_cmdex, width: 4
  input :exe_mutex, width: 11
  input :exe_dst_is_reg
  input :exe_dst_is_rm
  input :exe_dst_is_memory
  input :exe_dst_is_eax
  input :exe_dst_is_edx_eax
  input :exe_dst_is_implicit_reg
  input :exe_linear, width: 32
  input :exe_debug_read, width: 4
  input :exe_result, width: 32
  input :exe_result2, width: 32
  input :exe_result_push, width: 32
  input :exe_result_signals, width: 5
  input :exe_arith_index, width: 4
  input :exe_arith_sub_carry
  input :exe_arith_add_carry
  input :exe_arith_adc_carry
  input :exe_arith_sbb_carry
  input :src_final, width: 32
  input :dst_final, width: 32
  input :exe_mult_overflow
  input :exe_stack_offset, width: 32

  # Signals

  signal :__VdfgRegularize_hc955b938_0_0
  signal :__VdfgRegularize_hc955b938_0_1
  signal :__VdfgRegularize_hc955b938_0_2, width: 32
  signal :__VdfgRegularize_hc955b938_0_3
  signal :__VdfgRegularize_hc955b938_0_4
  signal :__VdfgRegularize_hc955b938_0_5
  signal :__VdfgRegularize_hc955b938_0_6
  signal :__VdfgRegularize_hc955b938_0_7, width: 32
  signal :_unused_ok
  signal :acflag_to_reg
  signal :aflag_to_reg
  signal :cflag_to_reg
  signal :cr0_am_to_reg
  signal :cr0_cd_to_reg
  signal :cr0_em_to_reg
  signal :cr0_mp_to_reg
  signal :cr0_ne_to_reg
  signal :cr0_nw_to_reg
  signal :cr0_pe_to_reg
  signal :cr0_pg_to_reg
  signal :cr0_ts_to_reg
  signal :cr0_wp_to_reg
  signal :cr2_to_reg, width: 32
  signal :cr3_to_reg, width: 32
  signal :cs_base, width: 32
  signal :cs_cache_to_reg, width: 64
  signal :cs_cache_valid_to_reg
  signal :cs_limit, width: 32
  signal :cs_rpl, width: 2
  signal :cs_rpl_to_reg, width: 2
  signal :cs_to_reg, width: 16
  signal :dflag_to_reg
  signal :dr0_to_reg, width: 32
  signal :dr1_to_reg, width: 32
  signal :dr2_to_reg, width: 32
  signal :dr3_to_reg, width: 32
  signal :dr6_b12_to_reg
  signal :dr6_bd_to_reg
  signal :dr6_breakpoints_to_reg, width: 4
  signal :dr6_bs_to_reg
  signal :dr6_bt_to_reg
  signal :dr7_to_reg, width: 32
  signal :ds_cache_to_reg, width: 64
  signal :ds_cache_valid_to_reg
  signal :ds_rpl, width: 2
  signal :ds_rpl_to_reg, width: 2
  signal :ds_to_reg, width: 16
  signal :eax_to_reg, width: 32
  signal :ebp_to_reg, width: 32
  signal :ebx_to_reg, width: 32
  signal :ecx_to_reg, width: 32
  signal :edi_to_reg, width: 32
  signal :edx_to_reg, width: 32
  signal :es_base, width: 32
  signal :es_cache_to_reg, width: 64
  signal :es_cache_valid_to_reg
  signal :es_limit, width: 32
  signal :es_rpl, width: 2
  signal :es_rpl_to_reg, width: 2
  signal :es_to_reg, width: 16
  signal :esi_to_reg, width: 32
  signal :esp_to_reg, width: 32
  signal :fs_cache_to_reg, width: 64
  signal :fs_cache_valid_to_reg
  signal :fs_rpl, width: 2
  signal :fs_rpl_to_reg, width: 2
  signal :fs_to_reg, width: 16
  signal :gdtr_base_to_reg, width: 32
  signal :gdtr_limit_to_reg, width: 16
  signal :gs_cache_to_reg, width: 64
  signal :gs_cache_valid_to_reg
  signal :gs_rpl, width: 2
  signal :gs_rpl_to_reg, width: 2
  signal :gs_to_reg, width: 16
  signal :idflag_to_reg
  signal :idtr_base_to_reg, width: 32
  signal :idtr_limit_to_reg, width: 16
  signal :iflag_to_reg
  signal :iopl_to_reg, width: 2
  signal :ldtr_cache_to_reg, width: 64
  signal :ldtr_cache_valid_to_reg
  signal :ldtr_rpl, width: 2
  signal :ldtr_rpl_to_reg, width: 2
  signal :ldtr_to_reg, width: 16
  signal :memory_write_system
  signal :ntflag_to_reg
  signal :oflag_to_reg
  signal :pflag_to_reg
  signal :result, width: 32
  signal :result2, width: 32
  signal :result_push, width: 32
  signal :result_signals, width: 5
  signal :rflag_to_reg
  signal :sflag_to_reg
  signal :ss_base, width: 32
  signal :ss_cache_to_reg, width: 64
  signal :ss_cache_valid_to_reg
  signal :ss_limit, width: 32
  signal :ss_rpl, width: 2
  signal :ss_rpl_to_reg, width: 2
  signal :ss_to_reg, width: 16
  signal :tflag_to_reg
  signal :tr_base, width: 32
  signal :tr_cache_to_reg, width: 64
  signal :tr_rpl, width: 2
  signal :tr_rpl_to_reg, width: 2
  signal :tr_to_reg, width: 16
  signal :vmflag_to_reg
  signal :wr_address_16bit
  signal :wr_address_32bit
  signal :wr_arith_adc_carry
  signal :wr_arith_add_carry
  signal :wr_arith_index, width: 4
  signal :wr_arith_sbb_carry
  signal :wr_arith_sub_carry
  signal :wr_clear_rflag
  signal :wr_cmd, width: 7
  signal :wr_cmdex, width: 4
  signal :wr_debug_code_reg, width: 4
  signal :wr_debug_prepare
  signal :wr_debug_read_reg, width: 4
  signal :wr_debug_step_reg
  signal :wr_debug_task_reg
  signal :wr_debug_task_trigger
  signal :wr_debug_trap_clear
  signal :wr_debug_write_reg, width: 4
  signal :wr_decoder, width: 16
  signal :wr_dst, width: 32
  signal :wr_dst_is_eax
  signal :wr_dst_is_edx_eax
  signal :wr_dst_is_implicit_reg
  signal :wr_dst_is_memory
  signal :wr_dst_is_reg
  signal :wr_dst_is_rm
  signal :wr_ecx_final, width: 32
  signal :wr_edi_final, width: 32
  signal :wr_esi_final, width: 32
  signal :wr_finished
  signal :wr_first_cycle
  signal :wr_hlt_in_progress
  signal :wr_inhibit_interrupts
  signal :wr_inhibit_interrupts_and_debug
  signal :wr_interrupt_possible_prepare
  signal :wr_is_8bit
  signal :wr_linear, width: 32
  signal :wr_make_esp_commit
  signal :wr_make_esp_speculative
  signal :wr_modregrm_mod, width: 2
  signal :wr_modregrm_reg, width: 3
  signal :wr_modregrm_rm, width: 3
  signal :wr_mult_overflow
  signal :wr_new_push_linear, width: 32
  signal :wr_new_push_ss_fault_check
  signal :wr_new_stack_esp, width: 32
  signal :wr_not_finished
  signal :wr_one_cycle_wait
  signal :wr_operand_16bit
  signal :wr_operand_32bit
  signal :wr_prefix_group_1_lock
  signal :wr_prefix_group_1_rep, width: 2
  signal :wr_push_length, width: 3
  signal :wr_push_length_dword
  signal :wr_push_length_word
  signal :wr_push_linear, width: 32
  signal :wr_push_ss_fault_check
  signal :wr_ready
  signal :wr_regrm_dword
  signal :wr_regrm_word
  signal :wr_seg_cache_mask, width: 64
  signal :wr_seg_cache_valid
  signal :wr_seg_rpl, width: 2
  signal :wr_seg_sel, width: 16
  signal :wr_src, width: 32
  signal :wr_stack_esp, width: 32
  signal :wr_string_es_linear, width: 32
  signal :wr_string_finish
  signal :wr_string_gp_fault_check
  signal :wr_string_ignore
  signal :wr_string_in_progress
  signal :wr_string_in_progress_last
  signal :wr_string_zf_finish
  signal :wr_system_dword, width: 32
  signal :wr_system_linear, width: 32
  signal :wr_validate_seg_regs
  signal :wr_waiting
  signal :wr_zflag_result
  signal :write_eax
  signal :write_for_wr_ready
  signal :write_io
  signal :write_length_dword
  signal :write_length_word
  signal :write_new_stack_virtual
  signal :write_regrm
  signal :write_rmw_system_dword
  signal :write_rmw_virtual
  signal :write_seg_cache
  signal :write_seg_cache_valid
  signal :write_seg_rpl
  signal :write_seg_sel
  signal :write_stack_virtual
  signal :write_string_es_virtual
  signal :write_system_busy_tss
  signal :write_system_dword
  signal :write_system_touch
  signal :write_system_word
  signal :write_virtual
  signal :zflag_to_reg

  # Assignments

  assign :tr_base,
    sig(:tr_cache, width: 64)[63..56].concat(
      sig(:tr_cache, width: 64)[39..16]
    )
  assign :cs_base,
    sig(:cs_cache, width: 64)[63..56].concat(
      sig(:cs_cache, width: 64)[39..16]
    )
  assign :cs_limit,
    mux(
      sig(:cs_cache, width: 64)[55],
      sig(:cs_cache, width: 64)[51..48].concat(
        sig(:cs_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:cs_cache, width: 64)[51..48].concat(
          sig(:cs_cache, width: 64)[15..0]
        )
      )
    )
  assign :wr_ready,
    (
        (
          ~sig(:wr_waiting, width: 1)
        ) &
        sig(:wr_is_front, width: 1)
    )
  assign :wr_is_front,
    (
        lit(0, width: 7, base: "h", signed: false) !=
        sig(:wr_cmd, width: 7)
    )
  assign :wr_busy,
    (
        sig(:wr_waiting, width: 1) |
        (
            sig(:exc_init, width: 1) |
            (
                sig(:wr_debug_prepare, width: 1) |
                (
                    sig(:wr_interrupt_possible_prepare, width: 1) |
                    (
                        sig(:wr_first_cycle, width: 1) &
                        sig(:wr_one_cycle_wait, width: 1)
                    )
                )
            )
        )
    )
  assign :wr_interrupt_possible_prepare,
    (
        sig(:interrupt_do, width: 1) &
        (
            sig(:wr_ready, width: 1) &
            (
                (
                    sig(:__VdfgRegularize_hc955b938_0_0, width: 1) |
                    (
                        sig(:wr_hlt_in_progress, width: 1) |
                        sig(:wr_string_in_progress, width: 1)
                    )
                ) &
                (
                    sig(:__VdfgRegularize_hc955b938_0_1, width: 1) &
                    (
                        (
                          ~sig(:wr_inhibit_interrupts_and_debug, width: 1)
                        ) &
                        (
                            (
                              ~sig(:wr_inhibit_interrupts, width: 1)
                            ) &
                            sig(:iflag_to_reg, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hc955b938_0_0,
    (
      ~sig(:wr_not_finished, width: 1)
    )
  assign :__VdfgRegularize_hc955b938_0_1,
    (
      ~sig(:wr_debug_prepare, width: 1)
    )
  assign :wr_finished,
    (
        sig(:wr_ready, width: 1) &
        (
            sig(:__VdfgRegularize_hc955b938_0_0, width: 1) |
            (
                (
                    sig(:wr_hlt_in_progress, width: 1) &
                    (
                        sig(:iflag_to_reg, width: 1) &
                        sig(:interrupt_do, width: 1)
                    )
                ) |
                sig(:wr_string_in_progress, width: 1)
            )
        )
    )
  assign :wr_clear_rflag,
    (
        sig(:wr_finished, width: 1) &
        (
            (
              ~sig(:exc_init, width: 1)
            ) &
            (
                (
                    sig(:wr_eip, width: 32) <=
                    sig(:cs_limit, width: 32)
                ) &
                (
                    sig(:__VdfgRegularize_hc955b938_0_1, width: 1) &
                    (
                      ~sig(:wr_interrupt_possible_prepare, width: 1)
                    )
                )
            )
        )
    )
  assign :wr_string_in_progress_final,
    (
        sig(:wr_string_in_progress, width: 1) |
        (
            (
                sig(:wr_debug_init, width: 1) |
                sig(:wr_interrupt_possible, width: 1)
            ) &
            sig(:wr_string_in_progress_last, width: 1)
        )
    )
  assign :es_base,
    sig(:es_cache, width: 64)[63..56].concat(
      sig(:es_cache, width: 64)[39..16]
    )
  assign :es_limit,
    mux(
      sig(:es_cache, width: 64)[55],
      sig(:es_cache, width: 64)[51..48].concat(
        sig(:es_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:es_cache, width: 64)[51..48].concat(
          sig(:es_cache, width: 64)[15..0]
        )
      )
    )
  assign :ss_base,
    sig(:ss_cache, width: 64)[63..56].concat(
      sig(:ss_cache, width: 64)[39..16]
    )
  assign :ss_limit,
    mux(
      sig(:ss_cache, width: 64)[55],
      sig(:ss_cache, width: 64)[51..48].concat(
        sig(:ss_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:ss_cache, width: 64)[51..48].concat(
          sig(:ss_cache, width: 64)[15..0]
        )
      )
    )
  assign :wr_operand_16bit,
    (
      ~sig(:wr_operand_32bit, width: 1)
    )
  assign :memory_write_system,
    (
        sig(:write_system_touch, width: 1) |
        (
            sig(:write_system_busy_tss, width: 1) |
            (
                sig(:write_system_dword, width: 1) |
                (
                    sig(:write_rmw_system_dword, width: 1) |
                    sig(:write_system_word, width: 1)
                )
            )
        )
    )
  assign :write_cpl,
    mux(
      sig(:write_new_stack_virtual, width: 1),
      sig(:glob_descriptor_2, width: 64)[46..45],
      mux(
        sig(:memory_write_system, width: 1),
        lit(0, width: 2, base: "h", signed: false),
        sig(:cpl, width: 2)
      )
    )
  assign :write_rmw,
    (
        sig(:write_rmw_system_dword, width: 1) |
        sig(:write_rmw_virtual, width: 1)
    )
  assign :write_address,
    mux(
      sig(:write_string_es_virtual, width: 1),
      sig(:wr_string_es_linear, width: 32),
      mux(
        sig(:write_stack_virtual, width: 1),
        sig(:wr_push_linear, width: 32),
        mux(
          sig(:write_new_stack_virtual, width: 1),
          sig(:wr_new_push_linear, width: 32),
          mux(
            sig(:write_system_touch, width: 1),
            mux(
              sig(:glob_param_1, width: 32)[2],
              (
                  lit(5, width: 32, base: "h", signed: false) +
                  (
                      sig(:ldtr_cache, width: 64)[63..56].concat(
                        sig(:ldtr_cache, width: 64)[39..16]
                      ) +
                      sig(:__VdfgRegularize_hc955b938_0_7, width: 32)
                  )
              ),
              (
                  lit(5, width: 32, base: "h", signed: false) +
                  sig(:__VdfgRegularize_hc955b938_0_2, width: 32)
              )
            ),
            mux(
              sig(:write_system_busy_tss, width: 1),
              (
                  lit(4, width: 32, base: "h", signed: false) +
                  sig(:__VdfgRegularize_hc955b938_0_2, width: 32)
              ),
              mux(
                sig(:__VdfgRegularize_hc955b938_0_3, width: 1),
                sig(:wr_system_linear, width: 32),
                sig(:wr_linear, width: 32)
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hc955b938_0_7,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:glob_param_1, width: 32)[15..3].concat(
        lit(0, width: 3, base: "h", signed: false)
      )
    )
  assign :__VdfgRegularize_hc955b938_0_2,
    (
        sig(:gdtr_base, width: 32) +
        sig(:__VdfgRegularize_hc955b938_0_7, width: 32)
    )
  assign :__VdfgRegularize_hc955b938_0_3,
    (
        sig(:write_system_dword, width: 1) |
        sig(:write_system_word, width: 1)
    )
  assign :write_data,
    mux(
      (
          sig(:write_stack_virtual, width: 1) |
          (
              sig(:write_new_stack_virtual, width: 1) |
              sig(:write_string_es_virtual, width: 1)
          )
      ),
      sig(:result_push, width: 32),
      mux(
        sig(:write_system_touch, width: 1),
        lit(0, width: 24, base: "d", signed: false).concat(
          sig(:glob_descriptor, width: 64)[47..41].concat(
            lit(1, width: 1, base: "h", signed: false)
          )
        ),
        mux(
          sig(:write_system_busy_tss, width: 1),
          (
              lit(512, width: 32, base: "h", signed: false) |
              sig(:glob_descriptor, width: 64)[63..32]
          ),
          mux(
            (
                sig(:write_rmw_system_dword, width: 1) |
                sig(:__VdfgRegularize_hc955b938_0_3, width: 1)
            ),
            sig(:wr_system_dword, width: 32),
            sig(:result, width: 32)
          )
        )
      )
    )
  assign :write_length,
    mux(
      sig(:__VdfgRegularize_hc955b938_0_6, width: 1),
      sig(:wr_push_length, width: 3),
      mux(
        sig(:write_system_touch, width: 1),
        lit(1, width: 3, base: "h", signed: false),
        mux(
          sig(:write_system_busy_tss, width: 1),
          lit(4, width: 3, base: "h", signed: false),
          mux(
            sig(:write_length_word, width: 1),
            lit(2, width: 3, base: "h", signed: false),
            mux(
              sig(:write_rmw_system_dword, width: 1),
              lit(4, width: 3, base: "h", signed: false),
              mux(
                sig(:write_system_dword, width: 1),
                lit(4, width: 3, base: "h", signed: false),
                mux(
                  sig(:write_system_word, width: 1),
                  lit(2, width: 3, base: "h", signed: false),
                  mux(
                    sig(:write_length_dword, width: 1),
                    lit(4, width: 3, base: "h", signed: false),
                    sig(:io_write_length, width: 3)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hc955b938_0_6,
    (
        sig(:write_new_stack_virtual, width: 1) |
        sig(:write_stack_virtual, width: 1)
    )
  assign :io_write_length,
    mux(
      sig(:wr_is_8bit, width: 1),
      lit(1, width: 3, base: "h", signed: false),
      mux(
        sig(:wr_operand_32bit, width: 1),
        lit(4, width: 3, base: "h", signed: false),
        lit(2, width: 3, base: "h", signed: false)
      )
    )
  assign :write_do,
    (
        (
          ~sig(:wr_reset, width: 1)
        ) &
        (
            sig(:__VdfgRegularize_hc955b938_0_4, width: 1) &
            (
                sig(:__VdfgRegularize_hc955b938_0_5, width: 1) &
                (
                    sig(:write_rmw_virtual, width: 1) |
                    (
                        sig(:write_virtual, width: 1) |
                        (
                            sig(:__VdfgRegularize_hc955b938_0_6, width: 1) |
                            (
                                sig(:write_string_es_virtual, width: 1) |
                                sig(:memory_write_system, width: 1)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hc955b938_0_4,
    (
      ~sig(:write_page_fault, width: 1)
    )
  assign :__VdfgRegularize_hc955b938_0_5,
    (
      ~sig(:write_ac_fault, width: 1)
    )
  assign :write_for_wr_ready,
    (
        sig(:write_done, width: 1) &
        (
            sig(:__VdfgRegularize_hc955b938_0_4, width: 1) &
            sig(:__VdfgRegularize_hc955b938_0_5, width: 1)
        )
    )
  assign :io_write_address,
    sig(:glob_param_1, width: 32)[15..0]
  assign :io_write_data,
    sig(:result_push, width: 32)
  assign :wr_address_16bit,
    (
      ~sig(:wr_address_32bit, width: 1)
    )
  assign :wr_modregrm_mod,
    sig(:wr_decoder, width: 16)[15..14]
  assign :wr_modregrm_reg,
    sig(:wr_decoder, width: 16)[13..11]
  assign :wr_modregrm_rm,
    sig(:wr_decoder, width: 16)[10..8]
  assign :write_lock,
    sig(:wr_prefix_group_1_lock, width: 1)
  assign :io_write_do,
    (
        (
          ~sig(:io_write_done, width: 1)
        ) &
        sig(:write_io, width: 1)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :wr_interrupt_possible,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:wr_reset, width: 1)
              ) &
              sig(:wr_interrupt_possible_prepare, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :wr_debug_init,
      (
          sig(:rst_n, width: 1) &
          sig(:wr_debug_prepare, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :wr_string_in_progress_last,
      (
          sig(:rst_n, width: 1) &
          sig(:wr_string_in_progress, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :wr_first_cycle,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:wr_reset, width: 1)
              ) &
              sig(:exe_ready, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_decoder,
          sig(:exe_decoder, width: 40)[15..0],
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_decoder,
          lit(0, width: 16, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_eip,
          sig(:exe_eip_final, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_eip,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_7,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_operand_32bit,
          sig(:exe_operand_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_operand_32bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_8,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_address_32bit,
          sig(:exe_address_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_address_32bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_9,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_prefix_group_1_rep,
          sig(:exe_prefix_group_1_rep, width: 2),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_prefix_group_1_rep,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_10,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_prefix_group_1_lock,
          sig(:exe_prefix_group_1_lock, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_prefix_group_1_lock,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_11,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_consumed,
          sig(:exe_consumed_final, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_consumed,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_12,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_is_8bit,
          sig(:exe_is_8bit_final, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_is_8bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_13,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_cmdex,
          sig(:exe_cmdex, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_cmdex,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_reg,
          sig(:exe_dst_is_reg, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_15,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_rm,
          sig(:exe_dst_is_rm, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_rm,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_16,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_memory,
          sig(:exe_dst_is_memory, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_memory,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_17,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_eax,
          sig(:exe_dst_is_eax, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_eax,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_18,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_edx_eax,
          sig(:exe_dst_is_edx_eax, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_edx_eax,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_19,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst_is_implicit_reg,
          sig(:exe_dst_is_implicit_reg, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst_is_implicit_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_20,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_linear,
          sig(:exe_linear, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_linear,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_21,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :result,
          sig(:exe_result, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :result,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_22,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :result2,
          sig(:exe_result2, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :result2,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_23,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :result_push,
          sig(:exe_result_push, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :result_push,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_24,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :result_signals,
          sig(:exe_result_signals, width: 5),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :result_signals,
          lit(0, width: 5, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_25,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_arith_index,
          sig(:exe_arith_index, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_arith_index,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_26,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_src,
          sig(:src_final, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_src,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_27,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_dst,
          sig(:dst_final, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_dst,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_28,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_arith_sub_carry,
          sig(:exe_arith_sub_carry, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_arith_sub_carry,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_29,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_arith_add_carry,
          sig(:exe_arith_add_carry, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_arith_add_carry,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_30,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_arith_adc_carry,
          sig(:exe_arith_adc_carry, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_arith_adc_carry,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_31,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_arith_sbb_carry,
          sig(:exe_arith_sbb_carry, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_arith_sbb_carry,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_32,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_mult_overflow,
          sig(:exe_mult_overflow, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_mult_overflow,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_33,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_ready, width: 1)) do
        assign(
          :wr_stack_offset,
          sig(:exe_stack_offset, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_stack_offset,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_34,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:wr_reset, width: 1)) do
        assign(
          :wr_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :wr_cmd,
            sig(:exe_cmd, width: 7),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:wr_ready, width: 1)) do
          assign(
            :wr_cmd,
            lit(0, width: 7, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :wr_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_35,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:wr_reset, width: 1)) do
        assign(
          :wr_mutex,
          lit(0, width: 11, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :wr_mutex,
            sig(:exe_mutex, width: 11),
            kind: :nonblocking
          )
        end
        elsif_block((sig(:wr_ready, width: 1) & (~sig(:wr_interrupt_possible_prepare, width: 1)))) do
          assign(
            :wr_mutex,
            lit(0, width: 11, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :wr_mutex,
          lit(0, width: 11, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_36,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:wr_make_esp_speculative, width: 1) & (~sig(:wr_is_esp_speculative, width: 1)))) do
        assign(
          :wr_esp_prev,
          sig(:esp, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_esp_prev,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_37,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:wr_reset, width: 1) | sig(:exe_reset, width: 1))) do
        assign(
          :wr_is_esp_speculative,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:wr_make_esp_commit, width: 1)) do
          assign(
            :wr_is_esp_speculative,
            lit(0, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:wr_make_esp_speculative, width: 1)) do
          assign(
            :wr_is_esp_speculative,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :wr_is_esp_speculative,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_37,
    sensitivity: [
    ],
    clocked: false,
    initial: true do
    assign(
      :_unused_ok,
      lit(0, width: 1, base: "h", signed: false),
      kind: :blocking
    )
  end

  # Instances

  instance :write_commands_inst, "write_commands",
    ports: {
      write_io_for_wr_ready: :io_write_done
    }
  instance :write_debug_inst, "write_debug",
    ports: {
      w_load: :exe_ready
    }
  instance :write_register_inst, "write_register"
  instance :write_stack_inst, "write_stack"
  instance :write_string_inst, "write_string"

end
