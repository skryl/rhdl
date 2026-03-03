# frozen_string_literal: true

class Execute < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute

  def self._import_decl_kinds
    {
      __VdfgRegularize_hc8813098_0_0: :logic,
      _unused_ok: :wire,
      cs_limit: :wire,
      div_busy: :wire,
      div_result_quotient: :wire,
      div_result_remainder: :wire,
      dst: :reg,
      e_shift_cf_of_update: :wire,
      e_shift_cflag: :wire,
      e_shift_no_write: :wire,
      e_shift_oflag: :wire,
      e_shift_oszapc_update: :wire,
      e_shift_result: :wire,
      exe_address_16bit: :wire,
      exe_address_effective: :reg,
      exe_branch: :wire,
      exe_branch_eip: :wire,
      exe_cmpxchg_switch: :wire,
      exe_eip_from_glob_param_2: :wire,
      exe_eip_from_glob_param_2_16bit: :wire,
      exe_eip_next_sum: :reg,
      exe_enter_offset: :wire,
      exe_extra: :reg,
      exe_is_8bit: :reg,
      exe_is_8bit_clear: :wire,
      exe_modregrm_imm: :reg,
      exe_modregrm_reg: :wire,
      exe_operand_16bit: :wire,
      exe_prefix_2byte: :reg,
      exe_task_switch_finished: :wire,
      exe_waiting: :wire,
      mult_busy: :wire,
      mult_result: :wire,
      offset_call: :wire,
      offset_call_int_same_first: :wire,
      offset_call_int_same_next: :wire,
      offset_call_keep: :wire,
      offset_enter_last: :wire,
      offset_esp: :wire,
      offset_int_real: :wire,
      offset_int_real_next: :wire,
      offset_iret: :wire,
      offset_iret_glob_param_4: :wire,
      offset_leave: :wire,
      offset_new_stack: :wire,
      offset_new_stack_continue: :wire,
      offset_new_stack_minus: :wire,
      offset_pop: :wire,
      offset_ret: :wire,
      offset_ret_far_se: :wire,
      offset_ret_imm: :wire,
      offset_task: :wire,
      rd_eip_next_sum: :wire,
      src: :reg,
      tr_base: :wire,
      tr_limit: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :exe_reset
  input :eax, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :ebp, width: 32
  input :esp, width: 32
  input :cs_cache, width: 64
  input :tr_cache, width: 64
  input :ss_cache, width: 64
  input :es, width: 16
  input :cs, width: 16
  input :ss, width: 16
  input :ds, width: 16
  input :fs, width: 16
  input :gs, width: 16
  input :ldtr, width: 16
  input :tr, width: 16
  input :cr2, width: 32
  input :cr3, width: 32
  input :dr0, width: 32
  input :dr1, width: 32
  input :dr2, width: 32
  input :dr3, width: 32
  input :dr6_bt
  input :dr6_bs
  input :dr6_bd
  input :dr6_b12
  input :dr6_breakpoints, width: 4
  input :dr7, width: 32
  input :cpl, width: 2
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :idflag
  input :acflag
  input :vmflag
  input :rflag
  input :ntflag
  input :iopl, width: 2
  input :oflag
  input :dflag
  input :iflag
  input :tflag
  input :sflag
  input :zflag
  input :aflag
  input :pflag
  input :cflag
  input :cr0_pg
  input :cr0_cd
  input :cr0_nw
  input :cr0_am
  input :cr0_wp
  input :cr0_ne
  input :cr0_ts
  input :cr0_em
  input :cr0_mp
  input :cr0_pe
  input :idtr_limit, width: 16
  input :idtr_base, width: 32
  input :gdtr_limit, width: 16
  input :gdtr_base, width: 32
  input :exc_push_error
  input :exc_error_code, width: 16
  input :exc_soft_int_ib
  input :exc_soft_int
  input :exc_vector, width: 8
  output :tlbcheck_do
  input :tlbcheck_done
  input :tlbcheck_page_fault
  output :tlbcheck_address, width: 32
  output :tlbcheck_rw
  output :tlbflushsingle_do
  input :tlbflushsingle_done
  output :tlbflushsingle_address, width: 32
  output :invdcode_do
  input :invdcode_done
  output :invddata_do
  input :invddata_done
  output :wbinvddata_do
  input :wbinvddata_done
  input :wr_esp_prev, width: 32
  input :wr_stack_offset, width: 32
  input :wr_mutex, width: 11
  output :exe_is_front
  input :glob_descriptor, width: 64
  input :glob_descriptor_2, width: 64
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_param_4, width: 32
  input :glob_param_5, width: 32
  input :wr_task_rpl, width: 2
  input :glob_desc_base, width: 32
  input :glob_desc_limit, width: 32
  input :glob_desc_2_limit, width: 32
  output :exe_glob_descriptor_set
  output :exe_glob_descriptor_value, width: 64
  output :exe_glob_descriptor_2_set
  output :exe_glob_descriptor_2_value, width: 64
  output :exe_glob_param_1_set
  output :exe_glob_param_1_value, width: 32
  output :exe_glob_param_2_set
  output :exe_glob_param_2_value, width: 32
  output :exe_glob_param_3_set
  output :exe_glob_param_3_value, width: 32
  output :dr6_bd_set
  output :task_eip, width: 32
  output :exe_buffer, width: 32
  output :exe_buffer_shifted, width: 464
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
  output :exe_error_code, width: 16
  output :exe_eip, width: 32
  output :exe_consumed, width: 4
  output :exe_busy
  input :rd_ready
  input :rd_decoder, width: 88
  input :rd_eip, width: 32
  input :rd_operand_32bit
  input :rd_address_32bit
  input :rd_prefix_group_1_rep, width: 2
  input :rd_prefix_group_1_lock
  input :rd_prefix_2byte
  input :rd_consumed, width: 4
  input :rd_is_8bit
  input :rd_cmd, width: 7
  input :rd_cmdex, width: 4
  input :rd_modregrm_imm, width: 32
  input :rd_mutex_next, width: 11
  input :rd_dst_is_reg
  input :rd_dst_is_rm
  input :rd_dst_is_memory
  input :rd_dst_is_eax
  input :rd_dst_is_edx_eax
  input :rd_dst_is_implicit_reg
  input :rd_extra_wire, width: 32
  input :rd_linear, width: 32
  input :rd_debug_read, width: 4
  input :src_wire, width: 32
  input :dst_wire, width: 32
  input :rd_address_effective, width: 32
  input :wr_busy
  output :exe_ready
  output :exe_decoder, width: 40
  output :exe_eip_final, width: 32
  output :exe_operand_32bit
  output :exe_address_32bit
  output :exe_prefix_group_1_rep, width: 2
  output :exe_prefix_group_1_lock
  output :exe_consumed_final, width: 4
  output :exe_is_8bit_final
  output :exe_cmd, width: 7
  output :exe_cmdex, width: 4
  output :exe_mutex, width: 11
  output :exe_dst_is_reg
  output :exe_dst_is_rm
  output :exe_dst_is_memory
  output :exe_dst_is_eax
  output :exe_dst_is_edx_eax
  output :exe_dst_is_implicit_reg
  output :exe_linear, width: 32
  output :exe_debug_read, width: 4
  output :exe_result, width: 32
  output :exe_result2, width: 32
  output :exe_result_push, width: 32
  output :exe_result_signals, width: 5
  output :exe_arith_index, width: 4
  output :exe_arith_sub_carry
  output :exe_arith_add_carry
  output :exe_arith_adc_carry
  output :exe_arith_sbb_carry
  output :src_final, width: 32
  output :dst_final, width: 32
  output :exe_mult_overflow
  output :exe_stack_offset, width: 32

  # Signals

  signal :__VdfgRegularize_hc8813098_0_0
  signal :_unused_ok
  signal :cs_limit, width: 32
  signal :div_busy
  signal :div_result_quotient, width: 32
  signal :div_result_remainder, width: 32
  signal :dst, width: 32
  signal :e_shift_cf_of_update
  signal :e_shift_cflag
  signal :e_shift_no_write
  signal :e_shift_oflag
  signal :e_shift_oszapc_update
  signal :e_shift_result, width: 32
  signal :exe_address_16bit
  signal :exe_address_effective, width: 32
  signal :exe_branch
  signal :exe_branch_eip, width: 32
  signal :exe_cmpxchg_switch
  signal :exe_eip_from_glob_param_2
  signal :exe_eip_from_glob_param_2_16bit
  signal :exe_eip_next_sum, width: 32
  signal :exe_enter_offset, width: 32
  signal :exe_extra, width: 32
  signal :exe_is_8bit
  signal :exe_is_8bit_clear
  signal :exe_modregrm_imm, width: 8
  signal :exe_modregrm_reg, width: 3
  signal :exe_operand_16bit
  signal :exe_prefix_2byte
  signal :exe_task_switch_finished
  signal :exe_waiting
  signal :mult_busy
  signal :mult_result, width: 66
  signal :offset_call
  signal :offset_call_int_same_first
  signal :offset_call_int_same_next
  signal :offset_call_keep
  signal :offset_enter_last
  signal :offset_esp
  signal :offset_int_real
  signal :offset_int_real_next
  signal :offset_iret
  signal :offset_iret_glob_param_4
  signal :offset_leave
  signal :offset_new_stack
  signal :offset_new_stack_continue
  signal :offset_new_stack_minus
  signal :offset_pop
  signal :offset_ret
  signal :offset_ret_far_se
  signal :offset_ret_imm
  signal :offset_task
  signal :rd_eip_next_sum, width: 32
  signal :src, width: 32
  signal :tr_base, width: 32
  signal :tr_limit, width: 32

  # Assignments

  assign :tr_base,
    sig(:tr_cache, width: 64)[63..56].concat(
      sig(:tr_cache, width: 64)[39..16]
    )
  assign :tr_limit,
    mux(
      sig(:tr_cache, width: 64)[55],
      sig(:tr_cache, width: 64)[51..48].concat(
        sig(:tr_cache, width: 64)[15..0].concat(
          lit(4095, width: 12, base: "h", signed: false)
        )
      ),
      lit(0, width: 12, base: "d", signed: false).concat(
        sig(:tr_cache, width: 64)[51..48].concat(
          sig(:tr_cache, width: 64)[15..0]
        )
      )
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
  assign :exe_ready,
    (
        (
          ~(
              sig(:exe_reset, width: 1) |
              sig(:exe_waiting, width: 1)
          )
        ) &
        (
            (
              ~sig(:wr_busy, width: 1)
            ) &
            sig(:__VdfgRegularize_hc8813098_0_0, width: 1)
        )
    )
  assign :__VdfgRegularize_hc8813098_0_0,
    (
        lit(0, width: 7, base: "h", signed: false) !=
        sig(:exe_cmd, width: 7)
    )
  assign :exe_busy,
    (
        sig(:exe_waiting, width: 1) |
        (
            (
              ~sig(:exe_ready, width: 1)
            ) &
            sig(:__VdfgRegularize_hc8813098_0_0, width: 1)
        )
    )
  assign :exe_is_front,
    (
        (
          ~sig(:wr_mutex, width: 11)[10]
        ) &
        sig(:__VdfgRegularize_hc8813098_0_0, width: 1)
    )
  assign :rd_eip_next_sum,
    mux(
      sig(:rd_is_8bit, width: 1),
      (
          sig(:rd_eip, width: 32) +
          sig(:rd_decoder, width: 88)[15].replicate(
          lit(24, width: 32, base: "h", signed: true)
        ).concat(
          sig(:rd_decoder, width: 88)[15..8]
        )
      ),
      mux(
        sig(:rd_operand_32bit, width: 1),
        (
            sig(:rd_eip, width: 32) +
            sig(:rd_decoder, width: 88)[39..8]
        ),
        (
            sig(:rd_eip, width: 32) +
            sig(:rd_decoder, width: 88)[23].replicate(
            lit(16, width: 32, base: "h", signed: true)
          ).concat(
            sig(:rd_decoder, width: 88)[23..8]
          )
        )
      )
    )
  assign :exe_operand_16bit,
    (
      ~sig(:exe_operand_32bit, width: 1)
    )
  assign :exe_address_16bit,
    (
      ~sig(:exe_address_32bit, width: 1)
    )
  assign :exe_modregrm_reg,
    sig(:exe_decoder, width: 40)[13..11]
  assign :exe_is_8bit_final,
    (
        (
          ~sig(:exe_is_8bit_clear, width: 1)
        ) &
        sig(:exe_is_8bit, width: 1)
    )
  assign :dst_final,
    mux(
      sig(:exe_cmpxchg_switch, width: 1),
      sig(:eax, width: 32),
      sig(:dst, width: 32)
    )
  assign :src_final,
    mux(
      sig(:exe_cmpxchg_switch, width: 1),
      sig(:dst, width: 32),
      sig(:src, width: 32)
    )
  assign :exe_consumed_final,
    mux(
      sig(:exe_task_switch_finished, width: 1),
      sig(:glob_param_3, width: 32)[21..18],
      sig(:exe_consumed, width: 4)
    )
  assign :exe_eip_final,
    mux(
      (
          (
            ~sig(:exe_task_switch_finished, width: 1)
          ) &
          sig(:exe_eip_from_glob_param_2, width: 1)
      ),
      sig(:glob_param_2, width: 32),
      mux(
        sig(:exe_eip_from_glob_param_2_16bit, width: 1),
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:glob_param_2, width: 32)[15..0]
        ),
        mux(
          sig(:exe_branch, width: 1),
          sig(:exe_branch_eip, width: 32),
          sig(:exe_eip, width: 32)
        )
      )
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_decoder,
          sig(:rd_decoder, width: 88)[39..0],
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_decoder,
          lit(0, width: 40, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_eip,
          sig(:rd_eip, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_eip,
          lit(0, width: 32, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_3,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_operand_32bit,
          sig(:rd_operand_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_operand_32bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_address_32bit,
          sig(:rd_address_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_address_32bit,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :sequential_posedge_clk_5,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_prefix_group_1_rep,
          sig(:rd_prefix_group_1_rep, width: 2),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_prefix_group_1_rep,
          lit(0, width: 2, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_prefix_group_1_lock,
          sig(:rd_prefix_group_1_lock, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_prefix_group_1_lock,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_prefix_2byte,
          sig(:rd_prefix_2byte, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_prefix_2byte,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_consumed,
          sig(:rd_consumed, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_consumed,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_is_8bit,
          sig(:rd_is_8bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_is_8bit,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_cmdex,
          sig(:rd_cmdex, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_cmdex,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_modregrm_imm,
          sig(:rd_modregrm_imm, width: 32)[7..0],
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_modregrm_imm,
          lit(0, width: 8, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_reg,
          sig(:rd_dst_is_reg, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_reg,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_rm,
          sig(:rd_dst_is_rm, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_rm,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_memory,
          sig(:rd_dst_is_memory, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_memory,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_eax,
          sig(:rd_dst_is_eax, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_eax,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_edx_eax,
          sig(:rd_dst_is_edx_eax, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_edx_eax,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_dst_is_implicit_reg,
          sig(:rd_dst_is_implicit_reg, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_dst_is_implicit_reg,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_extra,
          sig(:rd_extra_wire, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_extra,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_linear,
          sig(:rd_linear, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_linear,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_debug_read,
          sig(:rd_debug_read, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_debug_read,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :src,
          sig(:src_wire, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :src,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :dst,
          sig(:dst_wire, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :dst,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_address_effective,
          sig(:rd_address_effective, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_address_effective,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :exe_eip_next_sum,
          sig(:rd_eip_next_sum, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :exe_eip_next_sum,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :exe_mutex,
          lit(0, width: 11, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:rd_ready, width: 1)) do
          assign(
            :exe_mutex,
            sig(:rd_mutex_next, width: 11),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :exe_mutex,
            lit(0, width: 11, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :exe_mutex,
          lit(0, width: 11, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :exe_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:rd_ready, width: 1)) do
          assign(
            :exe_cmd,
            sig(:rd_cmd, width: 7),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:exe_ready, width: 1)) do
          assign(
            :exe_cmd,
            lit(0, width: 7, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :exe_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_26,
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

  instance :execute_offset_inst, "execute_offset"
  instance :execute_shift_inst, "execute_shift"
  instance :execute_multiply_inst, "execute_multiply"
  instance :execute_divide_inst, "execute_divide"
  instance :execute_commands_inst, "execute_commands",
    ports: {
      exe_mutex_current: :wr_mutex,
      e_eip_next_sum: :exe_eip_next_sum
    }

end
