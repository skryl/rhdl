# frozen_string_literal: true

class Read < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read

  def self._import_decl_kinds
    {
      __VdfgRegularize_h801f30e3_0_0: :logic,
      __VdfgRegularize_h801f30e3_0_1: :logic,
      __VdfgRegularize_h801f30e3_0_10: :logic,
      __VdfgRegularize_h801f30e3_0_11: :logic,
      __VdfgRegularize_h801f30e3_0_12: :logic,
      __VdfgRegularize_h801f30e3_0_13: :logic,
      __VdfgRegularize_h801f30e3_0_14: :logic,
      __VdfgRegularize_h801f30e3_0_15: :logic,
      __VdfgRegularize_h801f30e3_0_16: :logic,
      __VdfgRegularize_h801f30e3_0_17: :logic,
      __VdfgRegularize_h801f30e3_0_2: :logic,
      __VdfgRegularize_h801f30e3_0_3: :logic,
      __VdfgRegularize_h801f30e3_0_4: :logic,
      __VdfgRegularize_h801f30e3_0_5: :logic,
      __VdfgRegularize_h801f30e3_0_6: :logic,
      __VdfgRegularize_h801f30e3_0_7: :logic,
      __VdfgRegularize_h801f30e3_0_8: :logic,
      __VdfgRegularize_h801f30e3_0_9: :logic,
      __VdfgRegularize_h801f30e3_1_0: :logic,
      _unused_ok: :wire,
      address_bits_transform: :wire,
      address_ea_buffer: :wire,
      address_ea_buffer_plus_2: :wire,
      address_edi: :wire,
      address_enter: :wire,
      address_enter_init: :wire,
      address_enter_last: :wire,
      address_esi: :wire,
      address_leave: :wire,
      address_memoffset: :wire,
      address_stack_add_4_to_saved: :wire,
      address_stack_for_call_param_first: :wire,
      address_stack_for_iret_first: :wire,
      address_stack_for_iret_last: :wire,
      address_stack_for_iret_second: :wire,
      address_stack_for_iret_third: :wire,
      address_stack_for_iret_to_v86: :wire,
      address_stack_for_ret_first: :wire,
      address_stack_for_ret_second: :wire,
      address_stack_pop: :wire,
      address_stack_pop_esp_prev: :wire,
      address_stack_pop_for_call: :wire,
      address_stack_pop_next: :wire,
      address_stack_pop_speedup: :wire,
      address_stack_save: :wire,
      address_xlat_transform: :wire,
      dst_reg_index: :wire,
      io_read: :wire,
      ldtr_base: :wire,
      ldtr_limit: :wire,
      memory_read_system: :wire,
      rd_address_16bit: :wire,
      rd_address_effective_do: :wire,
      rd_address_effective_ready: :wire,
      rd_address_effective_ready_delayed: :reg,
      rd_address_waiting: :wire,
      rd_descriptor_not_in_limits: :wire,
      rd_dst_is_0: :wire,
      rd_dst_is_eip: :wire,
      rd_dst_is_memory_last: :wire,
      rd_dst_is_modregrm_imm: :wire,
      rd_dst_is_modregrm_imm_se: :wire,
      rd_io_ready: :wire,
      rd_memory_last: :reg,
      rd_modregrm_len: :reg,
      rd_modregrm_mod: :wire,
      rd_modregrm_reg: :wire,
      rd_modregrm_rm: :wire,
      rd_mutex_busy_active: :wire,
      rd_mutex_busy_eax: :wire,
      rd_mutex_busy_ebp: :wire,
      rd_mutex_busy_ecx: :wire,
      rd_mutex_busy_edx: :wire,
      rd_mutex_busy_eflags: :wire,
      rd_mutex_busy_esp: :wire,
      rd_mutex_busy_implicit_reg: :wire,
      rd_mutex_busy_memory: :wire,
      rd_mutex_busy_modregrm_reg: :wire,
      rd_mutex_busy_modregrm_rm: :wire,
      rd_one_io_read: :reg,
      rd_one_mem_read: :reg,
      rd_operand_16bit: :wire,
      rd_prefix_group_2_seg: :reg,
      rd_req_all: :wire,
      rd_req_eax: :wire,
      rd_req_ebp: :wire,
      rd_req_ebx: :wire,
      rd_req_ecx: :wire,
      rd_req_edi: :wire,
      rd_req_edx: :wire,
      rd_req_edx_eax: :wire,
      rd_req_eflags: :wire,
      rd_req_esi: :wire,
      rd_req_esp: :wire,
      rd_req_implicit_reg: :wire,
      rd_req_memory: :wire,
      rd_req_reg: :wire,
      rd_req_reg_not_8bit: :wire,
      rd_req_rm: :wire,
      rd_seg_gp_fault_init: :wire,
      rd_seg_linear: :wire,
      rd_seg_ss_fault_init: :wire,
      rd_sib: :wire,
      rd_src_is_1: :wire,
      rd_src_is_cmdex: :wire,
      rd_src_is_eax: :wire,
      rd_src_is_ecx: :wire,
      rd_src_is_imm: :wire,
      rd_src_is_imm_se: :wire,
      rd_src_is_implicit_reg: :wire,
      rd_src_is_io: :wire,
      rd_src_is_memory: :wire,
      rd_src_is_modregrm_imm: :wire,
      rd_src_is_modregrm_imm_se: :wire,
      rd_src_is_reg: :wire,
      rd_src_is_rm: :wire,
      rd_system_linear: :wire,
      rd_waiting: :wire,
      read_4: :wire,
      read_for_rd_ready: :wire,
      read_length_dword: :wire,
      read_length_word: :wire,
      read_rmw_system_dword: :wire,
      read_rmw_virtual: :wire,
      read_system_descriptor: :wire,
      read_system_dword: :wire,
      read_system_qword: :wire,
      read_system_word: :wire,
      read_virtual: :wire,
      src_reg_index: :wire,
      tr_base: :wire,
      tr_limit: :wire,
      write_virtual_check: :wire,
      write_virtual_check_ready: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :rd_reset
  input :dr0, width: 32
  input :dr1, width: 32
  input :dr2, width: 32
  input :dr3, width: 32
  input :dr7, width: 32
  input :debug_len0, width: 3
  input :debug_len1, width: 3
  input :debug_len2, width: 3
  input :debug_len3, width: 3
  input :glob_descriptor, width: 64
  input :glob_param_1, width: 32
  input :glob_param_2, width: 32
  input :glob_param_3, width: 32
  input :glob_desc_limit, width: 32
  input :glob_desc_base, width: 32
  input :gdtr_limit, width: 16
  input :gdtr_base, width: 32
  input :idtr_base, width: 32
  input :es_cache_valid
  input :es_cache, width: 64
  input :cs_cache_valid
  input :cs_cache, width: 64
  input :ss_cache_valid
  input :ss_cache, width: 64
  input :ds_cache_valid
  input :ds_cache, width: 64
  input :fs_cache_valid
  input :fs_cache, width: 64
  input :gs_cache_valid
  input :gs_cache, width: 64
  input :tr_cache_valid
  input :tr_cache, width: 64
  input :tr, width: 16
  input :ldtr_cache_valid
  input :ldtr_cache, width: 64
  input :cpl, width: 2
  input :iopl, width: 2
  input :cr0_pg
  input :real_mode
  input :v8086_mode
  input :protected_mode
  input :io_allow_check_needed
  input :eax, width: 32
  input :ebx, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :esp, width: 32
  input :ebp, width: 32
  input :esi, width: 32
  input :edi, width: 32
  input :exe_trigger_gp_fault
  input :exe_mutex, width: 11
  input :wr_mutex, width: 11
  input :wr_esp_prev, width: 32
  input :exc_vector, width: 8
  output :rd_io_allow_fault
  output :rd_error_code, width: 16
  output :rd_descriptor_gp_fault
  output :rd_seg_gp_fault
  output :rd_seg_ss_fault
  output :rd_ss_esp_from_tss_fault
  output :rd_dec_is_front
  output :rd_is_front
  output :rd_glob_descriptor_set
  output :rd_glob_descriptor_value, width: 64
  output :rd_glob_descriptor_2_set
  output :rd_glob_descriptor_2_value, width: 64
  output :rd_glob_param_1_set
  output :rd_glob_param_1_value, width: 32
  output :rd_glob_param_2_set
  output :rd_glob_param_2_value, width: 32
  output :rd_glob_param_3_set
  output :rd_glob_param_3_value, width: 32
  output :rd_glob_param_4_set
  output :rd_glob_param_4_value, width: 32
  output :rd_glob_param_5_set
  output :rd_glob_param_5_value, width: 32
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
  output :rd_busy
  input :micro_ready
  input :micro_decoder, width: 88
  input :micro_eip, width: 32
  input :micro_operand_32bit
  input :micro_address_32bit
  input :micro_prefix_group_1_rep, width: 2
  input :micro_prefix_group_1_lock
  input :micro_prefix_group_2_seg, width: 3
  input :micro_prefix_2byte
  input :micro_consumed, width: 4
  input :micro_modregrm_len, width: 3
  input :micro_is_8bit
  input :micro_cmd, width: 7
  input :micro_cmdex, width: 4
  input :exe_busy
  output :rd_ready
  output :rd_decoder, width: 88
  output :rd_eip, width: 32
  output :rd_operand_32bit
  output :rd_address_32bit
  output :rd_prefix_group_1_rep, width: 2
  output :rd_prefix_group_1_lock
  output :rd_prefix_2byte
  output :rd_consumed, width: 4
  output :rd_is_8bit
  output :rd_cmd, width: 7
  output :rd_cmdex, width: 4
  output :rd_modregrm_imm, width: 32
  output :rd_mutex_next, width: 11
  output :rd_dst_is_reg
  output :rd_dst_is_rm
  output :rd_dst_is_memory
  output :rd_dst_is_eax
  output :rd_dst_is_edx_eax
  output :rd_dst_is_implicit_reg
  output :rd_extra_wire, width: 32
  output :rd_linear, width: 32
  output :rd_debug_read, width: 4
  output :src_wire, width: 32
  output :dst_wire, width: 32
  output :rd_address_effective, width: 32

  # Signals

  signal :__VdfgRegularize_h801f30e3_0_0
  signal :__VdfgRegularize_h801f30e3_0_1
  signal :__VdfgRegularize_h801f30e3_0_10
  signal :__VdfgRegularize_h801f30e3_0_11
  signal :__VdfgRegularize_h801f30e3_0_12
  signal :__VdfgRegularize_h801f30e3_0_13
  signal :__VdfgRegularize_h801f30e3_0_14
  signal :__VdfgRegularize_h801f30e3_0_15
  signal :__VdfgRegularize_h801f30e3_0_16, width: 32
  signal :__VdfgRegularize_h801f30e3_0_17
  signal :__VdfgRegularize_h801f30e3_0_2, width: 32
  signal :__VdfgRegularize_h801f30e3_0_3
  signal :__VdfgRegularize_h801f30e3_0_4
  signal :__VdfgRegularize_h801f30e3_0_5
  signal :__VdfgRegularize_h801f30e3_0_6
  signal :__VdfgRegularize_h801f30e3_0_7
  signal :__VdfgRegularize_h801f30e3_0_8
  signal :__VdfgRegularize_h801f30e3_0_9
  signal :__VdfgRegularize_h801f30e3_1_0, width: 16
  signal :_unused_ok
  signal :address_bits_transform
  signal :address_ea_buffer
  signal :address_ea_buffer_plus_2
  signal :address_edi
  signal :address_enter
  signal :address_enter_init
  signal :address_enter_last
  signal :address_esi
  signal :address_leave
  signal :address_memoffset
  signal :address_stack_add_4_to_saved
  signal :address_stack_for_call_param_first
  signal :address_stack_for_iret_first
  signal :address_stack_for_iret_last
  signal :address_stack_for_iret_second
  signal :address_stack_for_iret_third
  signal :address_stack_for_iret_to_v86
  signal :address_stack_for_ret_first
  signal :address_stack_for_ret_second
  signal :address_stack_pop
  signal :address_stack_pop_esp_prev
  signal :address_stack_pop_for_call
  signal :address_stack_pop_next
  signal :address_stack_pop_speedup
  signal :address_stack_save
  signal :address_xlat_transform
  signal :dst_reg_index, width: 3
  signal :io_read
  signal :ldtr_base, width: 32
  signal :ldtr_limit, width: 32
  signal :memory_read_system
  signal :rd_address_16bit
  signal :rd_address_effective_do
  signal :rd_address_effective_ready
  signal :rd_address_effective_ready_delayed
  signal :rd_address_waiting
  signal :rd_descriptor_not_in_limits
  signal :rd_dst_is_0
  signal :rd_dst_is_eip
  signal :rd_dst_is_memory_last
  signal :rd_dst_is_modregrm_imm
  signal :rd_dst_is_modregrm_imm_se
  signal :rd_io_ready
  signal :rd_memory_last, width: 32
  signal :rd_modregrm_len, width: 3
  signal :rd_modregrm_mod, width: 2
  signal :rd_modregrm_reg, width: 3
  signal :rd_modregrm_rm, width: 3
  signal :rd_mutex_busy_active
  signal :rd_mutex_busy_eax
  signal :rd_mutex_busy_ebp
  signal :rd_mutex_busy_ecx
  signal :rd_mutex_busy_edx
  signal :rd_mutex_busy_eflags
  signal :rd_mutex_busy_esp
  signal :rd_mutex_busy_implicit_reg
  signal :rd_mutex_busy_memory
  signal :rd_mutex_busy_modregrm_reg
  signal :rd_mutex_busy_modregrm_rm
  signal :rd_one_io_read
  signal :rd_one_mem_read
  signal :rd_operand_16bit
  signal :rd_prefix_group_2_seg, width: 3
  signal :rd_req_all
  signal :rd_req_eax
  signal :rd_req_ebp
  signal :rd_req_ebx
  signal :rd_req_ecx
  signal :rd_req_edi
  signal :rd_req_edx
  signal :rd_req_edx_eax
  signal :rd_req_eflags
  signal :rd_req_esi
  signal :rd_req_esp
  signal :rd_req_implicit_reg
  signal :rd_req_memory
  signal :rd_req_reg
  signal :rd_req_reg_not_8bit
  signal :rd_req_rm
  signal :rd_seg_gp_fault_init
  signal :rd_seg_linear, width: 32
  signal :rd_seg_ss_fault_init
  signal :rd_sib, width: 8
  signal :rd_src_is_1
  signal :rd_src_is_cmdex
  signal :rd_src_is_eax
  signal :rd_src_is_ecx
  signal :rd_src_is_imm
  signal :rd_src_is_imm_se
  signal :rd_src_is_implicit_reg
  signal :rd_src_is_io
  signal :rd_src_is_memory
  signal :rd_src_is_modregrm_imm
  signal :rd_src_is_modregrm_imm_se
  signal :rd_src_is_reg
  signal :rd_src_is_rm
  signal :rd_system_linear, width: 32
  signal :rd_waiting
  signal :read_4, width: 32
  signal :read_for_rd_ready
  signal :read_length_dword
  signal :read_length_word
  signal :read_rmw_system_dword
  signal :read_rmw_virtual
  signal :read_system_descriptor
  signal :read_system_dword
  signal :read_system_qword
  signal :read_system_word
  signal :read_virtual
  signal :src_reg_index, width: 3
  signal :tr_base, width: 32
  signal :tr_limit, width: 32
  signal :write_virtual_check
  signal :write_virtual_check_ready

  # Assignments

  assign :rd_ready,
    (
        sig(:__VdfgRegularize_h801f30e3_0_0, width: 1) &
        (
            (
              ~sig(:rd_waiting, width: 1)
            ) &
            (
                (
                  ~sig(:exe_busy, width: 1)
                ) &
                sig(:__VdfgRegularize_h801f30e3_0_1, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h801f30e3_0_0,
    (
      ~sig(:rd_reset, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_1,
    (
        lit(0, width: 7, base: "h", signed: false) !=
        sig(:rd_cmd, width: 7)
    )
  assign :rd_busy,
    (
        sig(:rd_waiting, width: 1) |
        (
            (
              ~sig(:rd_ready, width: 1)
            ) &
            sig(:__VdfgRegularize_h801f30e3_0_1, width: 1)
        )
    )
  assign :rd_modregrm_mod,
    sig(:rd_decoder, width: 88)[15..14]
  assign :rd_modregrm_reg,
    sig(:rd_decoder, width: 88)[13..11]
  assign :rd_modregrm_rm,
    sig(:rd_decoder, width: 88)[10..8]
  assign :rd_sib,
    sig(:rd_decoder, width: 88)[23..16]
  assign :rd_operand_16bit,
    (
      ~sig(:rd_operand_32bit, width: 1)
    )
  assign :rd_modregrm_imm,
    case_select(
      sig(:rd_modregrm_len, width: 3),
      cases: {
        2 => sig(:rd_decoder, width: 88)[47..16],
        3 => sig(:rd_decoder, width: 88)[55..24],
        4 => sig(:rd_decoder, width: 88)[63..32],
        6 => sig(:rd_decoder, width: 88)[79..48]
      },
      default: sig(:rd_decoder, width: 88)[87..56]
    )
  assign :src_reg_index,
    mux(
      sig(:rd_src_is_cmdex, width: 1),
      sig(:rd_cmdex, width: 4)[2..0],
      mux(
        sig(:rd_src_is_implicit_reg, width: 1),
        sig(:rd_decoder, width: 88)[2..0],
        mux(
          sig(:rd_src_is_rm, width: 1),
          sig(:rd_modregrm_rm, width: 3),
          sig(:rd_modregrm_reg, width: 3)
        )
      )
    )
  assign :dst_reg_index,
    mux(
      sig(:rd_dst_is_implicit_reg, width: 1),
      sig(:rd_decoder, width: 88)[2..0],
      mux(
        sig(:rd_dst_is_rm, width: 1),
        sig(:rd_modregrm_rm, width: 3),
        sig(:rd_modregrm_reg, width: 3)
      )
    )
  assign :src_wire,
    mux(
      sig(:rd_src_is_memory, width: 1),
      sig(:read_4, width: 32),
      mux(
        sig(:rd_src_is_io, width: 1),
        sig(:io_read_data, width: 32),
        mux(
          sig(:rd_src_is_modregrm_imm, width: 1),
          sig(:rd_modregrm_imm, width: 32),
          mux(
            sig(:rd_src_is_modregrm_imm_se, width: 1),
            sig(:__VdfgRegularize_h801f30e3_0_2, width: 32),
            mux(
              (
                  sig(:rd_src_is_imm, width: 1) |
                  (
                      (
                        ~sig(:rd_is_8bit, width: 1)
                      ) &
                      sig(:rd_src_is_imm_se, width: 1)
                  )
              ),
              sig(:rd_decoder, width: 88)[39..8],
              mux(
                sig(:rd_src_is_imm_se, width: 1),
                sig(:rd_decoder, width: 88)[15].replicate(
                  lit(24, width: 32, base: "h", signed: true)
                ).concat(
                  sig(:rd_decoder, width: 88)[15..8]
                ),
                mux(
                  sig(:rd_src_is_1, width: 1),
                  lit(1, width: 32, base: "h", signed: false),
                  mux(
                    sig(:rd_src_is_eax, width: 1),
                    sig(:eax, width: 32),
                    mux(
                      sig(:rd_src_is_ecx, width: 1),
                      sig(:ecx, width: 32),
                      mux(
                        (
                            lit(0, width: 3, base: "h", signed: false) ==
                            sig(:src_reg_index, width: 3)
                        ),
                        sig(:eax, width: 32),
                        mux(
                          (
                              lit(1, width: 3, base: "h", signed: false) ==
                              sig(:src_reg_index, width: 3)
                          ),
                          sig(:ecx, width: 32),
                          mux(
                            (
                                lit(2, width: 3, base: "h", signed: false) ==
                                sig(:src_reg_index, width: 3)
                            ),
                            sig(:edx, width: 32),
                            mux(
                              (
                                  lit(3, width: 3, base: "h", signed: false) ==
                                  sig(:src_reg_index, width: 3)
                              ),
                              sig(:ebx, width: 32),
                              mux(
                                (
                                    sig(:__VdfgRegularize_h801f30e3_0_3, width: 1) &
                                    sig(:rd_is_8bit, width: 1)
                                ),
                                lit(0, width: 24, base: "d", signed: false).concat(
                                  sig(:eax, width: 32)[15..8]
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h801f30e3_0_3, width: 1),
                                  sig(:esp, width: 32),
                                  mux(
                                    (
                                        sig(:__VdfgRegularize_h801f30e3_0_4, width: 1) &
                                        sig(:rd_is_8bit, width: 1)
                                    ),
                                    lit(0, width: 24, base: "d", signed: false).concat(
                                      sig(:ecx, width: 32)[15..8]
                                    ),
                                    mux(
                                      sig(:__VdfgRegularize_h801f30e3_0_4, width: 1),
                                      sig(:ebp, width: 32),
                                      mux(
                                        (
                                            sig(:__VdfgRegularize_h801f30e3_0_5, width: 1) &
                                            sig(:rd_is_8bit, width: 1)
                                        ),
                                        lit(0, width: 24, base: "d", signed: false).concat(
                                          sig(:edx, width: 32)[15..8]
                                        ),
                                        mux(
                                          sig(:__VdfgRegularize_h801f30e3_0_5, width: 1),
                                          sig(:esi, width: 32),
                                          mux(
                                            (
                                                (
                                                    lit(7, width: 3, base: "h", signed: false) ==
                                                    sig(:src_reg_index, width: 3)
                                                ) &
                                                sig(:rd_is_8bit, width: 1)
                                            ),
                                            lit(0, width: 24, base: "d", signed: false).concat(
                                              sig(:ebx, width: 32)[15..8]
                                            ),
                                            sig(:edi, width: 32)
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :read_4,
    sig(:read_data, width: 64)[31..0]
  assign :__VdfgRegularize_h801f30e3_0_2,
    sig(:rd_modregrm_imm, width: 32)[7].replicate(
      lit(24, width: 32, base: "h", signed: true)
    ).concat(
      sig(:rd_modregrm_imm, width: 32)[7..0]
    )
  assign :__VdfgRegularize_h801f30e3_0_3,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:src_reg_index, width: 3)
    )
  assign :__VdfgRegularize_h801f30e3_0_4,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:src_reg_index, width: 3)
    )
  assign :__VdfgRegularize_h801f30e3_0_5,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:src_reg_index, width: 3)
    )
  assign :dst_wire,
    mux(
      sig(:rd_dst_is_0, width: 1),
      lit(0, width: 32, base: "h", signed: false),
      mux(
        sig(:rd_dst_is_modregrm_imm_se, width: 1),
        sig(:__VdfgRegularize_h801f30e3_0_2, width: 32),
        mux(
          sig(:rd_dst_is_modregrm_imm, width: 1),
          sig(:rd_modregrm_imm, width: 32),
          mux(
            sig(:rd_dst_is_memory, width: 1),
            sig(:read_4, width: 32),
            mux(
              sig(:rd_dst_is_memory_last, width: 1),
              sig(:rd_memory_last, width: 32),
              mux(
                sig(:rd_dst_is_eip, width: 1),
                sig(:rd_eip, width: 32),
                mux(
                  (
                      sig(:rd_dst_is_eax, width: 1) |
                      sig(:rd_dst_is_edx_eax, width: 1)
                  ),
                  sig(:eax, width: 32),
                  mux(
                    (
                        lit(0, width: 3, base: "h", signed: false) ==
                        sig(:dst_reg_index, width: 3)
                    ),
                    sig(:eax, width: 32),
                    mux(
                      (
                          lit(1, width: 3, base: "h", signed: false) ==
                          sig(:dst_reg_index, width: 3)
                      ),
                      sig(:ecx, width: 32),
                      mux(
                        (
                            lit(2, width: 3, base: "h", signed: false) ==
                            sig(:dst_reg_index, width: 3)
                        ),
                        sig(:edx, width: 32),
                        mux(
                          (
                              lit(3, width: 3, base: "h", signed: false) ==
                              sig(:dst_reg_index, width: 3)
                          ),
                          sig(:ebx, width: 32),
                          mux(
                            (
                                sig(:__VdfgRegularize_h801f30e3_0_6, width: 1) &
                                sig(:rd_is_8bit, width: 1)
                            ),
                            lit(0, width: 24, base: "d", signed: false).concat(
                              sig(:eax, width: 32)[15..8]
                            ),
                            mux(
                              sig(:__VdfgRegularize_h801f30e3_0_6, width: 1),
                              sig(:esp, width: 32),
                              mux(
                                (
                                    sig(:__VdfgRegularize_h801f30e3_0_7, width: 1) &
                                    sig(:rd_is_8bit, width: 1)
                                ),
                                lit(0, width: 24, base: "d", signed: false).concat(
                                  sig(:ecx, width: 32)[15..8]
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h801f30e3_0_7, width: 1),
                                  sig(:ebp, width: 32),
                                  mux(
                                    (
                                        sig(:__VdfgRegularize_h801f30e3_0_8, width: 1) &
                                        sig(:rd_is_8bit, width: 1)
                                    ),
                                    lit(0, width: 24, base: "d", signed: false).concat(
                                      sig(:edx, width: 32)[15..8]
                                    ),
                                    mux(
                                      sig(:__VdfgRegularize_h801f30e3_0_8, width: 1),
                                      sig(:esi, width: 32),
                                      mux(
                                        (
                                            (
                                                lit(7, width: 3, base: "h", signed: false) ==
                                                sig(:dst_reg_index, width: 3)
                                            ) &
                                            sig(:rd_is_8bit, width: 1)
                                        ),
                                        lit(0, width: 24, base: "d", signed: false).concat(
                                          sig(:ebx, width: 32)[15..8]
                                        ),
                                        sig(:edi, width: 32)
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h801f30e3_0_6,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:dst_reg_index, width: 3)
    )
  assign :__VdfgRegularize_h801f30e3_0_7,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:dst_reg_index, width: 3)
    )
  assign :__VdfgRegularize_h801f30e3_0_8,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:dst_reg_index, width: 3)
    )
  assign :io_read_length,
    mux(
      sig(:rd_is_8bit, width: 1),
      lit(1, width: 3, base: "h", signed: false),
      mux(
        sig(:rd_operand_32bit, width: 1),
        lit(4, width: 3, base: "h", signed: false),
        lit(2, width: 3, base: "h", signed: false)
      )
    )
  assign :io_read_do,
    (
        sig(:io_read, width: 1) &
        (
            (
              ~sig(:io_read_done, width: 1)
            ) &
            (
                (
                  ~sig(:rd_one_io_read, width: 1)
                ) &
                (
                    sig(:__VdfgRegularize_h801f30e3_0_0, width: 1) &
                    (
                      ~sig(:exe_trigger_gp_fault, width: 1)
                    )
                )
            )
        )
    )
  assign :rd_io_ready,
    (
        sig(:io_read_done, width: 1) |
        sig(:rd_one_io_read, width: 1)
    )
  assign :memory_read_system,
    (
        sig(:read_system_descriptor, width: 1) |
        (
            sig(:read_system_dword, width: 1) |
            (
                sig(:read_system_word, width: 1) |
                (
                    sig(:read_rmw_system_dword, width: 1) |
                    sig(:read_system_qword, width: 1)
                )
            )
        )
    )
  assign :read_cpl,
    mux(
      sig(:memory_read_system, width: 1),
      lit(0, width: 2, base: "h", signed: false),
      sig(:cpl, width: 2)
    )
  assign :read_rmw,
    (
        sig(:read_rmw_system_dword, width: 1) |
        sig(:read_rmw_virtual, width: 1)
    )
  assign :read_address,
    mux(
      sig(:__VdfgRegularize_h801f30e3_0_9, width: 1),
      sig(:rd_seg_linear, width: 32),
      mux(
        sig(:read_system_descriptor, width: 1),
        mux(
          sig(:glob_param_1, width: 32)[2],
          (
              sig(:ldtr_base, width: 32) +
              sig(:__VdfgRegularize_h801f30e3_0_16, width: 32)
          ),
          (
              sig(:gdtr_base, width: 32) +
              sig(:__VdfgRegularize_h801f30e3_0_16, width: 32)
          )
        ),
        sig(:rd_system_linear, width: 32)
      )
    )
  assign :__VdfgRegularize_h801f30e3_0_9,
    (
        sig(:read_rmw_virtual, width: 1) |
        sig(:read_virtual, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_16,
    lit(0, width: 16, base: "d", signed: false).concat(
      sig(:glob_param_1, width: 32)[15..3].concat(
        lit(0, width: 3, base: "h", signed: false)
      )
    )
  assign :read_length,
    mux(
      sig(:read_system_word, width: 1),
      lit(2, width: 4, base: "h", signed: false),
      mux(
        sig(:read_system_dword, width: 1),
        lit(4, width: 4, base: "h", signed: false),
        mux(
          sig(:read_system_qword, width: 1),
          lit(8, width: 4, base: "h", signed: false),
          mux(
            sig(:read_rmw_system_dword, width: 1),
            lit(4, width: 4, base: "h", signed: false),
            mux(
              sig(:read_system_descriptor, width: 1),
              lit(8, width: 4, base: "h", signed: false),
              mux(
                sig(:rd_is_8bit, width: 1),
                lit(1, width: 4, base: "h", signed: false),
                mux(
                  sig(:read_length_word, width: 1),
                  lit(2, width: 4, base: "h", signed: false),
                  mux(
                    sig(:read_length_dword, width: 1),
                    lit(4, width: 4, base: "h", signed: false),
                    mux(
                      sig(:rd_operand_32bit, width: 1),
                      lit(4, width: 4, base: "h", signed: false),
                      lit(2, width: 4, base: "h", signed: false)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :read_do,
    (
        sig(:__VdfgRegularize_h801f30e3_0_0, width: 1) &
        (
            (
                (
                    sig(:rd_address_effective_ready, width: 1) &
                    sig(:__VdfgRegularize_h801f30e3_0_9, width: 1)
                ) |
                sig(:memory_read_system, width: 1)
            ) &
            (
                (
                  ~sig(:rd_one_mem_read, width: 1)
                ) &
                (
                    sig(:__VdfgRegularize_h801f30e3_0_10, width: 1) &
                    (
                        sig(:__VdfgRegularize_h801f30e3_0_11, width: 1) &
                        (
                            (
                              ~sig(:rd_seg_gp_fault_init, width: 1)
                            ) &
                            (
                                sig(:__VdfgRegularize_h801f30e3_0_12, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h801f30e3_0_13, width: 1) &
                                    (
                                        sig(:__VdfgRegularize_h801f30e3_0_17, width: 1) &
                                        (
                                            (
                                              ~sig(:rd_seg_ss_fault_init, width: 1)
                                            ) &
                                            sig(:__VdfgRegularize_h801f30e3_0_14, width: 1)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h801f30e3_0_10,
    (
      ~sig(:read_page_fault, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_11,
    (
      ~sig(:read_ac_fault, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_12,
    (
      ~sig(:rd_seg_gp_fault, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_13,
    (
      ~sig(:rd_descriptor_gp_fault, width: 1)
    )
  assign :__VdfgRegularize_h801f30e3_0_17,
    (
      ~(
          sig(:rd_io_allow_fault, width: 1) |
          sig(:rd_ss_esp_from_tss_fault, width: 1)
      )
    )
  assign :__VdfgRegularize_h801f30e3_0_14,
    (
      ~sig(:rd_seg_ss_fault, width: 1)
    )
  assign :rd_descriptor_gp_fault,
    (
        sig(:read_system_descriptor, width: 1) &
        sig(:rd_descriptor_not_in_limits, width: 1)
    )
  assign :rd_descriptor_not_in_limits,
    (
        (
            (
              ~sig(:glob_param_1, width: 32)[2]
            ) &
            (
                sig(:__VdfgRegularize_h801f30e3_1_0, width: 16) >
                sig(:gdtr_limit, width: 16)
            )
        ) |
        (
            sig(:glob_param_1, width: 32)[2] &
            (
                (
                  ~sig(:ldtr_cache_valid, width: 1)
                ) |
                (
                    lit(0, width: 16, base: "d", signed: false).concat(
                      sig(:__VdfgRegularize_h801f30e3_1_0, width: 16)
                    ) >
                    sig(:ldtr_limit, width: 32)
                )
            )
        )
    )
  assign :read_for_rd_ready,
    (
        sig(:rd_one_mem_read, width: 1) |
        (
            sig(:read_done, width: 1) &
            (
                sig(:__VdfgRegularize_h801f30e3_0_10, width: 1) &
                sig(:__VdfgRegularize_h801f30e3_0_11, width: 1)
            )
        )
    )
  assign :write_virtual_check_ready,
    (
        sig(:__VdfgRegularize_h801f30e3_0_0, width: 1) &
        (
            sig(:__VdfgRegularize_h801f30e3_0_12, width: 1) &
            (
                sig(:rd_address_effective_ready_delayed, width: 1) &
                (
                    sig(:__VdfgRegularize_h801f30e3_0_13, width: 1) &
                    (
                        sig(:__VdfgRegularize_h801f30e3_0_14, width: 1) &
                        sig(:__VdfgRegularize_h801f30e3_0_17, width: 1)
                    )
                )
            )
        )
    )
  assign :rd_address_effective_do,
    (
        (
          ~sig(:rd_address_waiting, width: 1)
        ) &
        sig(:__VdfgRegularize_h801f30e3_0_1, width: 1)
    )
  assign :rd_linear,
    mux(
      sig(:read_rmw_system_dword, width: 1),
      sig(:rd_system_linear, width: 32),
      sig(:rd_seg_linear, width: 32)
    )
  assign :rd_dec_is_front,
    (
        sig(:__VdfgRegularize_h801f30e3_0_15, width: 1) &
        (
            lit(0, width: 7, base: "h", signed: false) ==
            sig(:rd_cmd, width: 7)
        )
    )
  assign :__VdfgRegularize_h801f30e3_0_15,
    (
      ~sig(:rd_mutex_busy_active, width: 1)
    )
  assign :rd_is_front,
    (
        sig(:__VdfgRegularize_h801f30e3_0_15, width: 1) &
        sig(:__VdfgRegularize_h801f30e3_0_1, width: 1)
    )
  assign :rd_address_16bit,
    (
      ~sig(:rd_address_32bit, width: 1)
    )
  assign :read_lock,
    sig(:rd_prefix_group_1_lock, width: 1)
  assign :__VdfgRegularize_h801f30e3_1_0,
    sig(:glob_param_1, width: 32)[15..3].concat(
      lit(7, width: 3, base: "h", signed: false)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_decoder,
          sig(:micro_decoder, width: 88),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_decoder,
          lit(0, width: 88, base: "h", signed: false),
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_eip,
          sig(:micro_eip, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_eip,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_operand_32bit,
          sig(:micro_operand_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_operand_32bit,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_address_32bit,
          sig(:micro_address_32bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_address_32bit,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_prefix_group_1_rep,
          sig(:micro_prefix_group_1_rep, width: 2),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_prefix_group_1_rep,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_prefix_group_1_lock,
          sig(:micro_prefix_group_1_lock, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_prefix_group_1_lock,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_prefix_group_2_seg,
          sig(:micro_prefix_group_2_seg, width: 3),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_prefix_group_2_seg,
          lit(3, width: 3, base: "h", signed: false),
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_prefix_2byte,
          sig(:micro_prefix_2byte, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_prefix_2byte,
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_consumed,
          sig(:micro_consumed, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_consumed,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_modregrm_len,
          sig(:micro_modregrm_len, width: 3),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_modregrm_len,
          lit(0, width: 3, base: "h", signed: false),
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_is_8bit,
          sig(:micro_is_8bit, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_is_8bit,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:micro_ready, width: 1)) do
        assign(
          :rd_cmdex,
          sig(:micro_cmdex, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_cmdex,
          lit(0, width: 4, base: "h", signed: false),
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
      if_stmt(sig(:rd_reset, width: 1)) do
        assign(
          :rd_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:micro_ready, width: 1)) do
          assign(
            :rd_cmd,
            sig(:micro_cmd, width: 7),
            kind: :nonblocking
          )
        end
        elsif_block(sig(:rd_ready, width: 1)) do
          assign(
            :rd_cmd,
            lit(0, width: 7, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :rd_cmd,
          lit(0, width: 7, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_13,
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

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:read_for_rd_ready, width: 1) & sig(:rd_ready, width: 1))) do
        assign(
          :rd_memory_last,
          sig(:read_4, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :rd_memory_last,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt((sig(:rd_ready, width: 1) | sig(:rd_reset, width: 1))) do
        assign(
          :rd_one_io_read,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(sig(:io_read_done, width: 1)) do
          assign(
            :rd_one_io_read,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :rd_one_io_read,
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
    assign(
      :rd_seg_gp_fault,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~(
                    sig(:rd_ready, width: 1) |
                    sig(:rd_reset, width: 1)
                )
              ) &
              sig(:rd_seg_gp_fault_init, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_17,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :rd_seg_ss_fault,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~(
                    sig(:rd_ready, width: 1) |
                    sig(:rd_reset, width: 1)
                )
              ) &
              sig(:rd_seg_ss_fault_init, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_18,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:rd_ready, width: 1) | sig(:rd_reset, width: 1))) do
        assign(
          :rd_one_mem_read,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        elsif_block(((sig(:read_done, width: 1) & (~sig(:read_page_fault, width: 1))) & (~sig(:read_ac_fault, width: 1)))) do
          assign(
            :rd_one_mem_read,
            lit(1, width: 1, base: "h", signed: false),
            kind: :nonblocking
          )
        end
      end
      else_block do
        assign(
          :rd_one_mem_read,
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
    assign(
      :rd_address_effective_ready_delayed,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~(
                    (
                        sig(:rd_ready, width: 1) |
                        sig(:rd_reset, width: 1)
                    ) |
                    (
                      ~sig(:write_virtual_check, width: 1)
                    )
                )
              ) &
              sig(:rd_address_effective_ready, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  # Instances

  instance :read_segment_inst, "read_segment"
  instance :read_effective_address_inst, "read_effective_address"
  instance :read_debug_inst, "read_debug"
  instance :read_commands_inst, "read_commands",
    ports: {
      read_8: :read_data
    }
  instance :read_mutex_inst, "read_mutex"

end
