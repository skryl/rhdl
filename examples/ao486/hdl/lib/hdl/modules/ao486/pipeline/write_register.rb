# frozen_string_literal: true

class WriteRegister < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write_register

  def self._import_decl_kinds
    {
      __VdfgRegularize_h1e18ad15_0_0: :logic,
      __VdfgRegularize_h1e18ad15_0_1: :logic,
      __VdfgRegularize_h1e18ad15_0_10: :logic,
      __VdfgRegularize_h1e18ad15_0_2: :logic,
      __VdfgRegularize_h1e18ad15_0_3: :logic,
      __VdfgRegularize_h1e18ad15_0_4: :logic,
      __VdfgRegularize_h1e18ad15_0_5: :logic,
      __VdfgRegularize_h1e18ad15_0_6: :logic,
      __VdfgRegularize_h1e18ad15_0_7: :logic,
      __VdfgRegularize_h1e18ad15_0_8: :logic,
      __VdfgRegularize_h1e18ad15_0_9: :logic,
      _unused_ok: :wire,
      ds_invalidate: :wire,
      eax_value: :wire,
      ebp_value: :wire,
      ebx_value: :wire,
      ecx_value: :wire,
      edi_value: :wire,
      edx_value: :wire,
      es_invalidate: :wire,
      esi_value: :wire,
      esp_value: :wire,
      fs_invalidate: :wire,
      gs_invalidate: :wire,
      w_index: :wire,
      w_operand_16bit: :wire,
      w_operand_32bit: :wire,
      w_seg_cache: :wire,
      w_write_regrm: :wire,
      wr_seg_index: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :glob_descriptor, width: 64
  input :glob_param_1, width: 32
  input :wr_is_8bit
  input :wr_operand_32bit
  input :wr_decoder, width: 16
  input :wr_modregrm_reg, width: 3
  input :wr_modregrm_rm, width: 3
  input :wr_clear_rflag
  input :wr_seg_sel, width: 16
  input :wr_seg_rpl, width: 2
  input :wr_seg_cache_valid
  input :write_seg_sel
  input :write_seg_rpl
  input :write_seg_cache
  input :write_seg_cache_valid
  input :wr_seg_cache_mask, width: 64
  input :wr_validate_seg_regs
  input :write_system_touch
  input :write_system_busy_tss
  input :dr6_bd_set
  input :exc_set_rflag
  input :exc_debug_start
  input :exc_pf_read
  input :exc_pf_write
  input :exc_pf_code
  input :exc_pf_check
  input :exc_restore_esp
  input :wr_esp_prev, width: 32
  input :tlb_code_pf_cr2, width: 32
  input :tlb_write_pf_cr2, width: 32
  input :tlb_read_pf_cr2, width: 32
  input :tlb_check_pf_cr2, width: 32
  input :wr_debug_code_reg, width: 4
  input :wr_debug_write_reg, width: 4
  input :wr_debug_read_reg, width: 4
  input :wr_debug_step_reg
  input :wr_debug_task_reg
  input :write_eax
  input :write_regrm
  input :wr_dst_is_rm
  input :wr_dst_is_reg
  input :wr_dst_is_implicit_reg
  input :wr_regrm_word
  input :wr_regrm_dword
  input :result, width: 32
  output :cpl, width: 2
  output :protected_mode
  output :v8086_mode
  output :real_mode
  output :io_allow_check_needed
  output :debug_len0, width: 3
  output :debug_len1, width: 3
  output :debug_len2, width: 3
  output :debug_len3, width: 3
  input :eax_to_reg, width: 32
  input :ebx_to_reg, width: 32
  input :ecx_to_reg, width: 32
  input :edx_to_reg, width: 32
  input :esi_to_reg, width: 32
  input :edi_to_reg, width: 32
  input :ebp_to_reg, width: 32
  input :esp_to_reg, width: 32
  input :cr0_pe_to_reg
  input :cr0_mp_to_reg
  input :cr0_em_to_reg
  input :cr0_ts_to_reg
  input :cr0_ne_to_reg
  input :cr0_wp_to_reg
  input :cr0_am_to_reg
  input :cr0_nw_to_reg
  input :cr0_cd_to_reg
  input :cr0_pg_to_reg
  input :cr2_to_reg, width: 32
  input :cr3_to_reg, width: 32
  input :cflag_to_reg
  input :pflag_to_reg
  input :aflag_to_reg
  input :zflag_to_reg
  input :sflag_to_reg
  input :oflag_to_reg
  input :tflag_to_reg
  input :iflag_to_reg
  input :dflag_to_reg
  input :iopl_to_reg, width: 2
  input :ntflag_to_reg
  input :rflag_to_reg
  input :vmflag_to_reg
  input :acflag_to_reg
  input :idflag_to_reg
  input :gdtr_base_to_reg, width: 32
  input :gdtr_limit_to_reg, width: 16
  input :idtr_base_to_reg, width: 32
  input :idtr_limit_to_reg, width: 16
  input :dr0_to_reg, width: 32
  input :dr1_to_reg, width: 32
  input :dr2_to_reg, width: 32
  input :dr3_to_reg, width: 32
  input :dr6_breakpoints_to_reg, width: 4
  input :dr6_b12_to_reg
  input :dr6_bd_to_reg
  input :dr6_bs_to_reg
  input :dr6_bt_to_reg
  input :dr7_to_reg, width: 32
  input :es_to_reg, width: 16
  input :ds_to_reg, width: 16
  input :ss_to_reg, width: 16
  input :fs_to_reg, width: 16
  input :gs_to_reg, width: 16
  input :cs_to_reg, width: 16
  input :ldtr_to_reg, width: 16
  input :tr_to_reg, width: 16
  input :es_cache_to_reg, width: 64
  input :ds_cache_to_reg, width: 64
  input :ss_cache_to_reg, width: 64
  input :fs_cache_to_reg, width: 64
  input :gs_cache_to_reg, width: 64
  input :cs_cache_to_reg, width: 64
  input :ldtr_cache_to_reg, width: 64
  input :tr_cache_to_reg, width: 64
  input :es_cache_valid_to_reg
  input :ds_cache_valid_to_reg
  input :ss_cache_valid_to_reg
  input :fs_cache_valid_to_reg
  input :gs_cache_valid_to_reg
  input :cs_cache_valid_to_reg
  input :ldtr_cache_valid_to_reg
  input :es_rpl_to_reg, width: 2
  input :ds_rpl_to_reg, width: 2
  input :ss_rpl_to_reg, width: 2
  input :fs_rpl_to_reg, width: 2
  input :gs_rpl_to_reg, width: 2
  input :cs_rpl_to_reg, width: 2
  input :ldtr_rpl_to_reg, width: 2
  input :tr_rpl_to_reg, width: 2
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
  output :gdtr_base, width: 32
  output :gdtr_limit, width: 16
  output :idtr_base, width: 32
  output :idtr_limit, width: 16
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
  output :es_rpl, width: 2
  output :ds_rpl, width: 2
  output :ss_rpl, width: 2
  output :fs_rpl, width: 2
  output :gs_rpl, width: 2
  output :cs_rpl, width: 2
  output :ldtr_rpl, width: 2
  output :tr_rpl, width: 2

  # Signals

  signal :__VdfgRegularize_h1e18ad15_0_0
  signal :__VdfgRegularize_h1e18ad15_0_1
  signal :__VdfgRegularize_h1e18ad15_0_10
  signal :__VdfgRegularize_h1e18ad15_0_2
  signal :__VdfgRegularize_h1e18ad15_0_3
  signal :__VdfgRegularize_h1e18ad15_0_4
  signal :__VdfgRegularize_h1e18ad15_0_5
  signal :__VdfgRegularize_h1e18ad15_0_6
  signal :__VdfgRegularize_h1e18ad15_0_7
  signal :__VdfgRegularize_h1e18ad15_0_8
  signal :__VdfgRegularize_h1e18ad15_0_9
  signal :_unused_ok
  signal :ds_invalidate
  signal :eax_value, width: 32
  signal :ebp_value, width: 32
  signal :ebx_value, width: 32
  signal :ecx_value, width: 32
  signal :edi_value, width: 32
  signal :edx_value, width: 32
  signal :es_invalidate
  signal :esi_value, width: 32
  signal :esp_value, width: 32
  signal :fs_invalidate
  signal :gs_invalidate
  signal :w_index, width: 3
  signal :w_operand_16bit
  signal :w_operand_32bit
  signal :w_seg_cache, width: 64
  signal :w_write_regrm
  signal :wr_seg_index, width: 3

  # Assignments

  assign :cpl,
    sig(:cs_rpl, width: 2)
  assign :protected_mode,
    (
        (
          ~sig(:vmflag, width: 1)
        ) &
        sig(:cr0_pe, width: 1)
    )
  assign :v8086_mode,
    (
        sig(:cr0_pe, width: 1) &
        sig(:vmflag, width: 1)
    )
  assign :real_mode,
    (
      ~sig(:cr0_pe, width: 1)
    )
  assign :io_allow_check_needed,
    (
        sig(:cr0_pe, width: 1) &
        (
            sig(:vmflag, width: 1) |
            (
                sig(:cs_rpl, width: 2) >
                sig(:iopl, width: 2)
            )
        )
    )
  assign :ds_invalidate,
    (
        sig(:wr_validate_seg_regs, width: 1) &
        (
            (
                sig(:ds_cache, width: 64)[46..45] <
                sig(:cs_rpl, width: 2)
            ) &
            (
                (
                  ~(
                      sig(:ds_cache_valid, width: 1) &
                      sig(:ds_cache, width: 64)[44]
                  )
                ) |
                (
                    (
                      ~sig(:ds_cache, width: 64)[43]
                    ) |
                    (
                        (
                          ~sig(:ds_cache, width: 64)[42]
                        ) &
                        sig(:ds_cache, width: 64)[43]
                    )
                )
            )
        )
    )
  assign :es_invalidate,
    (
        sig(:wr_validate_seg_regs, width: 1) &
        (
            (
                sig(:es_cache, width: 64)[46..45] <
                sig(:cs_rpl, width: 2)
            ) &
            (
                (
                  ~(
                      sig(:es_cache_valid, width: 1) &
                      sig(:es_cache, width: 64)[44]
                  )
                ) |
                (
                    (
                      ~sig(:es_cache, width: 64)[43]
                    ) |
                    (
                        (
                          ~sig(:es_cache, width: 64)[42]
                        ) &
                        sig(:es_cache, width: 64)[43]
                    )
                )
            )
        )
    )
  assign :fs_invalidate,
    (
        sig(:wr_validate_seg_regs, width: 1) &
        (
            (
                sig(:fs_cache, width: 64)[46..45] <
                sig(:cs_rpl, width: 2)
            ) &
            (
                (
                  ~(
                      sig(:fs_cache_valid, width: 1) &
                      sig(:fs_cache, width: 64)[44]
                  )
                ) |
                (
                    (
                      ~sig(:fs_cache, width: 64)[43]
                    ) |
                    (
                        (
                          ~sig(:fs_cache, width: 64)[42]
                        ) &
                        sig(:fs_cache, width: 64)[43]
                    )
                )
            )
        )
    )
  assign :gs_invalidate,
    (
        sig(:wr_validate_seg_regs, width: 1) &
        (
            (
                sig(:gs_cache, width: 64)[46..45] <
                sig(:cs_rpl, width: 2)
            ) &
            (
                (
                  ~(
                      sig(:gs_cache_valid, width: 1) &
                      sig(:gs_cache, width: 64)[44]
                  )
                ) |
                (
                    (
                      ~sig(:gs_cache, width: 64)[43]
                    ) |
                    (
                        (
                          ~sig(:gs_cache, width: 64)[42]
                        ) &
                        sig(:gs_cache, width: 64)[43]
                    )
                )
            )
        )
    )
  assign :debug_len0,
    case_select(
      sig(:dr7, width: 32)[19..18],
      cases: {
        0 => lit(7, width: 3, base: "h", signed: false),
        1 => lit(6, width: 3, base: "h", signed: false),
        2 => lit(0, width: 3, base: "h", signed: false)
      },
      default: lit(4, width: 3, base: "h", signed: false)
    )
  assign :debug_len1,
    case_select(
      sig(:dr7, width: 32)[23..22],
      cases: {
        0 => lit(7, width: 3, base: "h", signed: false),
        1 => lit(6, width: 3, base: "h", signed: false),
        2 => lit(0, width: 3, base: "h", signed: false)
      },
      default: lit(4, width: 3, base: "h", signed: false)
    )
  assign :debug_len2,
    case_select(
      sig(:dr7, width: 32)[27..26],
      cases: {
        0 => lit(7, width: 3, base: "h", signed: false),
        1 => lit(6, width: 3, base: "h", signed: false),
        2 => lit(0, width: 3, base: "h", signed: false)
      },
      default: lit(4, width: 3, base: "h", signed: false)
    )
  assign :debug_len3,
    case_select(
      sig(:dr7, width: 32)[31..30],
      cases: {
        0 => lit(7, width: 3, base: "h", signed: false),
        1 => lit(6, width: 3, base: "h", signed: false),
        2 => lit(0, width: 3, base: "h", signed: false)
      },
      default: lit(4, width: 3, base: "h", signed: false)
    )
  assign :w_index,
    mux(
      sig(:wr_dst_is_rm, width: 1),
      sig(:wr_modregrm_rm, width: 3),
      mux(
        sig(:wr_dst_is_reg, width: 1),
        sig(:wr_modregrm_reg, width: 3),
        mux(
          sig(:wr_dst_is_implicit_reg, width: 1),
          sig(:wr_decoder, width: 16)[2..0],
          lit(0, width: 3, base: "h", signed: false)
        )
      )
    )
  assign :w_write_regrm,
    (
        sig(:write_eax, width: 1) |
        (
            sig(:write_regrm, width: 1) &
            (
                sig(:wr_dst_is_rm, width: 1) |
                (
                    sig(:wr_dst_is_implicit_reg, width: 1) |
                    sig(:wr_dst_is_reg, width: 1)
                )
            )
        )
    )
  assign :w_operand_32bit,
    (
        (
          ~sig(:wr_regrm_word, width: 1)
        ) &
        (
            sig(:wr_operand_32bit, width: 1) |
            sig(:wr_regrm_dword, width: 1)
        )
    )
  assign :w_operand_16bit,
    (
      ~sig(:w_operand_32bit, width: 1)
    )
  assign :eax_value,
    mux(
      (
          sig(:wr_is_8bit, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_0, width: 1)
      ),
      sig(:eax, width: 32)[31..8].concat(
        sig(:result, width: 32)[7..0]
      ),
      mux(
        (
            sig(:wr_is_8bit, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_1, width: 1)
        ),
        sig(:eax, width: 32)[31..16].concat(
          sig(:result, width: 32)[7..0].concat(
            sig(:eax, width: 32)[7..0]
          )
        ),
        mux(
          (
              sig(:w_operand_16bit, width: 1) &
              sig(:__VdfgRegularize_h1e18ad15_0_0, width: 1)
          ),
          sig(:eax, width: 32)[31..16].concat(
            sig(:result, width: 32)[15..0]
          ),
          mux(
            (
                sig(:w_operand_32bit, width: 1) &
                sig(:__VdfgRegularize_h1e18ad15_0_0, width: 1)
            ),
            sig(:result, width: 32),
            sig(:eax_to_reg, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_0,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :__VdfgRegularize_h1e18ad15_0_1,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :ebx_value,
    mux(
      (
          sig(:wr_is_8bit, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_2, width: 1)
      ),
      sig(:ebx, width: 32)[31..8].concat(
        sig(:result, width: 32)[7..0]
      ),
      mux(
        (
            sig(:wr_is_8bit, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_3, width: 1)
        ),
        sig(:ebx, width: 32)[31..16].concat(
          sig(:result, width: 32)[7..0].concat(
            sig(:ebx, width: 32)[7..0]
          )
        ),
        mux(
          (
              sig(:w_operand_16bit, width: 1) &
              sig(:__VdfgRegularize_h1e18ad15_0_2, width: 1)
          ),
          sig(:ebx, width: 32)[31..16].concat(
            sig(:result, width: 32)[15..0]
          ),
          mux(
            (
                sig(:w_operand_32bit, width: 1) &
                sig(:__VdfgRegularize_h1e18ad15_0_2, width: 1)
            ),
            sig(:result, width: 32),
            sig(:ebx_to_reg, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_2,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :__VdfgRegularize_h1e18ad15_0_3,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :ecx_value,
    mux(
      (
          sig(:wr_is_8bit, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_4, width: 1)
      ),
      sig(:ecx, width: 32)[31..8].concat(
        sig(:result, width: 32)[7..0]
      ),
      mux(
        (
            sig(:wr_is_8bit, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_5, width: 1)
        ),
        sig(:ecx, width: 32)[31..16].concat(
          sig(:result, width: 32)[7..0].concat(
            sig(:ecx, width: 32)[7..0]
          )
        ),
        mux(
          (
              sig(:w_operand_16bit, width: 1) &
              sig(:__VdfgRegularize_h1e18ad15_0_4, width: 1)
          ),
          sig(:ecx, width: 32)[31..16].concat(
            sig(:result, width: 32)[15..0]
          ),
          mux(
            (
                sig(:w_operand_32bit, width: 1) &
                sig(:__VdfgRegularize_h1e18ad15_0_4, width: 1)
            ),
            sig(:result, width: 32),
            sig(:ecx_to_reg, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_4,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :__VdfgRegularize_h1e18ad15_0_5,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :edx_value,
    mux(
      (
          sig(:wr_is_8bit, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_6, width: 1)
      ),
      sig(:edx, width: 32)[31..8].concat(
        sig(:result, width: 32)[7..0]
      ),
      mux(
        (
            sig(:wr_is_8bit, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_7, width: 1)
        ),
        sig(:edx, width: 32)[31..16].concat(
          sig(:result, width: 32)[7..0].concat(
            sig(:edx, width: 32)[7..0]
          )
        ),
        mux(
          (
              sig(:w_operand_16bit, width: 1) &
              sig(:__VdfgRegularize_h1e18ad15_0_6, width: 1)
          ),
          sig(:edx, width: 32)[31..16].concat(
            sig(:result, width: 32)[15..0]
          ),
          mux(
            (
                sig(:w_operand_32bit, width: 1) &
                sig(:__VdfgRegularize_h1e18ad15_0_6, width: 1)
            ),
            sig(:result, width: 32),
            sig(:edx_to_reg, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_6,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :__VdfgRegularize_h1e18ad15_0_7,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:w_index, width: 3)
    )
  assign :esi_value,
    mux(
      (
          sig(:__VdfgRegularize_h1e18ad15_0_9, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_7, width: 1)
      ),
      sig(:esi, width: 32)[31..16].concat(
        sig(:result, width: 32)[15..0]
      ),
      mux(
        (
            sig(:__VdfgRegularize_h1e18ad15_0_10, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_7, width: 1)
        ),
        sig(:result, width: 32),
        sig(:esi_to_reg, width: 32)
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_9,
    (
        sig(:__VdfgRegularize_h1e18ad15_0_8, width: 1) &
        sig(:w_operand_16bit, width: 1)
    )
  assign :__VdfgRegularize_h1e18ad15_0_10,
    (
        sig(:__VdfgRegularize_h1e18ad15_0_8, width: 1) &
        sig(:w_operand_32bit, width: 1)
    )
  assign :edi_value,
    mux(
      (
          sig(:__VdfgRegularize_h1e18ad15_0_9, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_3, width: 1)
      ),
      sig(:edi, width: 32)[31..16].concat(
        sig(:result, width: 32)[15..0]
      ),
      mux(
        (
            sig(:__VdfgRegularize_h1e18ad15_0_10, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_3, width: 1)
        ),
        sig(:result, width: 32),
        sig(:edi_to_reg, width: 32)
      )
    )
  assign :ebp_value,
    mux(
      (
          sig(:__VdfgRegularize_h1e18ad15_0_9, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_5, width: 1)
      ),
      sig(:ebp, width: 32)[31..16].concat(
        sig(:result, width: 32)[15..0]
      ),
      mux(
        (
            sig(:__VdfgRegularize_h1e18ad15_0_10, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_5, width: 1)
        ),
        sig(:result, width: 32),
        sig(:ebp_to_reg, width: 32)
      )
    )
  assign :esp_value,
    mux(
      (
          sig(:__VdfgRegularize_h1e18ad15_0_9, width: 1) &
          sig(:__VdfgRegularize_h1e18ad15_0_1, width: 1)
      ),
      sig(:esp_to_reg, width: 32)[31..16].concat(
        sig(:result, width: 32)[15..0]
      ),
      mux(
        (
            sig(:__VdfgRegularize_h1e18ad15_0_10, width: 1) &
            sig(:__VdfgRegularize_h1e18ad15_0_1, width: 1)
        ),
        sig(:result, width: 32),
        sig(:esp_to_reg, width: 32)
      )
    )
  assign :__VdfgRegularize_h1e18ad15_0_8,
    (
      ~sig(:wr_is_8bit, width: 1)
    )
  assign :wr_seg_index,
    sig(:glob_param_1, width: 32)[18..16]
  assign :w_seg_cache,
    mux(
      sig(:write_system_touch, width: 1),
      (
          lit(1099511627776, width: 64, base: "h", signed: false) |
          sig(:glob_descriptor, width: 64)
      ),
      mux(
        sig(:write_system_busy_tss, width: 1),
        (
            lit(2199023255552, width: 64, base: "h", signed: false) |
            sig(:glob_descriptor, width: 64)
        ),
        sig(:glob_descriptor, width: 64)
      )
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :eax,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:eax_value, width: 32),
          sig(:eax_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
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
      :ebx,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:ebx_value, width: 32),
          sig(:ebx_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
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
      :ecx,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:ecx_value, width: 32),
          sig(:ecx_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
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
      :edx,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:edx_value, width: 32),
          sig(:edx_to_reg, width: 32)
        ),
        lit(1115, width: 32, base: "h", signed: false)
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
    assign(
      :esi,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:esi_value, width: 32),
          sig(:esi_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_6,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :edi,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:edi_value, width: 32),
          sig(:edi_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_7,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ebp,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:ebp_value, width: 32),
          sig(:ebp_to_reg, width: 32)
        ),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_8,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :esp,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:w_write_regrm, width: 1),
          sig(:esp_value, width: 32),
          mux(
            sig(:exc_restore_esp, width: 1),
            sig(:wr_esp_prev, width: 32),
            sig(:esp_to_reg, width: 32)
          )
        ),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_9,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_pe,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_pe_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_10,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_mp,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_mp_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_11,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_em,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_em_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_12,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_ts,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_ts_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_13,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_ne,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_ne_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_14,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_wp,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_wp_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_15,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_am,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_am_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_16,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr0_nw,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          sig(:cr0_nw_to_reg, width: 1)
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
      :cr0_cd,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          sig(:cr0_cd_to_reg, width: 1)
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
    assign(
      :cr0_pg,
      (
          sig(:rst_n, width: 1) &
          sig(:cr0_pg_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_19,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr3,
      mux(
        sig(:rst_n, width: 1),
        sig(:cr3_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_20,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cr2,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:exc_pf_write, width: 1),
          sig(:tlb_write_pf_cr2, width: 32),
          mux(
            sig(:exc_pf_check, width: 1),
            sig(:tlb_check_pf_cr2, width: 32),
            mux(
              sig(:exc_pf_read, width: 1),
              sig(:tlb_read_pf_cr2, width: 32),
              mux(
                sig(:exc_pf_code, width: 1),
                sig(:tlb_code_pf_cr2, width: 32),
                sig(:cr2_to_reg, width: 32)
              )
            )
          )
        ),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_21,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cflag,
      (
          sig(:rst_n, width: 1) &
          sig(:cflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_22,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :pflag,
      (
          sig(:rst_n, width: 1) &
          sig(:pflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_23,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :aflag,
      (
          sig(:rst_n, width: 1) &
          sig(:aflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_24,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :zflag,
      (
          sig(:rst_n, width: 1) &
          sig(:zflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_25,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :sflag,
      (
          sig(:rst_n, width: 1) &
          sig(:sflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_26,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :oflag,
      (
          sig(:rst_n, width: 1) &
          sig(:oflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_27,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tflag,
      (
          sig(:rst_n, width: 1) &
          sig(:tflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_28,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :iflag,
      (
          sig(:rst_n, width: 1) &
          sig(:iflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_29,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dflag,
      (
          sig(:rst_n, width: 1) &
          sig(:dflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_30,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :iopl,
      mux(
        sig(:rst_n, width: 1),
        sig(:iopl_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_31,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ntflag,
      (
          sig(:rst_n, width: 1) &
          sig(:ntflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_32,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :vmflag,
      (
          sig(:rst_n, width: 1) &
          sig(:vmflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_33,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :acflag,
      (
          sig(:rst_n, width: 1) &
          sig(:acflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_34,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :idflag,
      (
          sig(:rst_n, width: 1) &
          sig(:idflag_to_reg, width: 1)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_35,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :rflag,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~sig(:wr_clear_rflag, width: 1)
              ) &
              (
                  sig(:exc_set_rflag, width: 1) |
                  sig(:rflag_to_reg, width: 1)
              )
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_36,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gdtr_base,
      mux(
        sig(:rst_n, width: 1),
        sig(:gdtr_base_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_37,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gdtr_limit,
      mux(
        sig(:rst_n, width: 1),
        sig(:gdtr_limit_to_reg, width: 16),
        lit(65535, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_38,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :idtr_base,
      mux(
        sig(:rst_n, width: 1),
        sig(:idtr_base_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_39,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :idtr_limit,
      mux(
        sig(:rst_n, width: 1),
        sig(:idtr_limit_to_reg, width: 16),
        lit(65535, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_40,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr0,
      mux(
        sig(:rst_n, width: 1),
        sig(:dr0_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_41,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr1,
      mux(
        sig(:rst_n, width: 1),
        sig(:dr1_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_42,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr2,
      mux(
        sig(:rst_n, width: 1),
        sig(:dr2_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_43,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr3,
      mux(
        sig(:rst_n, width: 1),
        sig(:dr3_to_reg, width: 32),
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_44,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr6_breakpoints,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:exc_debug_start, width: 1),
          (
              (
                  sig(:wr_debug_read_reg, width: 4) |
                  sig(:wr_debug_write_reg, width: 4)
              ) |
              sig(:wr_debug_code_reg, width: 4)
          ),
          sig(:dr6_breakpoints_to_reg, width: 4)
        ),
        lit(0, width: 4, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_45,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr6_b12,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          (
              (
                ~sig(:exc_debug_start, width: 1)
              ) &
              sig(:dr6_b12_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_46,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr6_bd,
      (
          sig(:rst_n, width: 1) &
          (
              sig(:dr6_bd_set, width: 1) |
              sig(:dr6_bd_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_47,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr6_bs,
      (
          sig(:rst_n, width: 1) &
          mux(
            sig(:exc_debug_start, width: 1),
            sig(:wr_debug_step_reg, width: 1),
            sig(:dr6_bs_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_48,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr6_bt,
      (
          sig(:rst_n, width: 1) &
          mux(
            sig(:exc_debug_start, width: 1),
            sig(:wr_debug_task_reg, width: 1),
            sig(:dr6_bt_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_49,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :dr7,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:exc_debug_start, width: 1),
          sig(:dr7, width: 32)[31..14].concat(
            lit(0, width: 1, base: "d", signed: false).concat(
              sig(:dr7, width: 32)[12..0]
            )
          ),
          sig(:dr7_to_reg, width: 32)
        ),
        lit(1024, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_50,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :es,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:es_invalidate, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                sig(:write_seg_sel, width: 1) &
                (
                    lit(0, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_sel, width: 16),
            sig(:es_to_reg, width: 16)
          )
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_51,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ds,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:ds_invalidate, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                sig(:write_seg_sel, width: 1) &
                (
                    lit(3, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_sel, width: 16),
            sig(:ds_to_reg, width: 16)
          )
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_52,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ss,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_sel, width: 1) &
              (
                  lit(2, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_sel, width: 16),
          sig(:ss_to_reg, width: 16)
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_53,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :fs,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:fs_invalidate, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                sig(:write_seg_sel, width: 1) &
                (
                    lit(4, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_sel, width: 16),
            sig(:fs_to_reg, width: 16)
          )
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_54,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gs,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:gs_invalidate, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                sig(:write_seg_sel, width: 1) &
                (
                    lit(5, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_sel, width: 16),
            sig(:gs_to_reg, width: 16)
          )
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_55,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cs,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_sel, width: 1) &
              (
                  lit(1, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_sel, width: 16),
          sig(:cs_to_reg, width: 16)
        ),
        lit(61440, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_56,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ldtr,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_sel, width: 1) &
              (
                  lit(6, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_sel, width: 16),
          sig(:ldtr_to_reg, width: 16)
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_57,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tr,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_sel, width: 1) &
              (
                  lit(7, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_sel, width: 16),
          sig(:tr_to_reg, width: 16)
        ),
        lit(0, width: 16, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_58,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :es_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(0, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:es_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_59,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ds_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(3, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:ds_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_60,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ss_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(2, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:ss_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_61,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :fs_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(4, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:fs_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_62,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gs_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(5, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:gs_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_63,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cs_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(1, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:cs_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_64,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ldtr_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              (
                  sig(:write_seg_rpl, width: 1) &
                  (
                      lit(6, width: 3, base: "h", signed: false) ==
                      sig(:wr_seg_index, width: 3)
                  )
              ) &
              sig(:w_seg_cache, width: 64)[47]
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:ldtr_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_65,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tr_rpl,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_rpl, width: 1) &
              (
                  lit(7, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          sig(:wr_seg_rpl, width: 2),
          sig(:tr_rpl_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_66,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :es_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(0, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:es_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:es_cache_to_reg, width: 64)
        ),
        lit(161628209348607, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_67,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ds_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(3, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:ds_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:ds_cache_to_reg, width: 64)
        ),
        lit(161628209348607, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_68,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ss_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(2, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:ss_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:ss_cache_to_reg, width: 64)
        ),
        lit(161628209348607, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_69,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :fs_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(4, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:fs_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:fs_cache_to_reg, width: 64)
        ),
        lit(161628209348607, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_70,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gs_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(5, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:gs_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:gs_cache_to_reg, width: 64)
        ),
        lit(161628209348607, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_71,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cs_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(1, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:cs_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:cs_cache_to_reg, width: 64)
        ),
        lit(18374849203097632767, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_72,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ldtr_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              (
                  sig(:write_seg_cache, width: 1) &
                  (
                      lit(6, width: 3, base: "h", signed: false) ==
                      sig(:wr_seg_index, width: 3)
                  )
              ) &
              sig(:w_seg_cache, width: 64)[47]
          ),
          (
              (
                  sig(:ldtr_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:ldtr_cache_to_reg, width: 64)
        ),
        lit(142936511676415, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_73,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :tr_cache,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:write_seg_cache, width: 1) &
              (
                  lit(7, width: 3, base: "h", signed: false) ==
                  sig(:wr_seg_index, width: 3)
              )
          ),
          (
              (
                  sig(:tr_cache, width: 64) &
                  sig(:wr_seg_cache_mask, width: 64)
              ) |
              sig(:w_seg_cache, width: 64)
          ),
          sig(:tr_cache_to_reg, width: 64)
        ),
        lit(152832116326399, width: 64, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_74,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :es_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          (
              (
                ~sig(:es_invalidate, width: 1)
              ) &
              mux(
                (
                    sig(:write_seg_cache_valid, width: 1) &
                    (
                        lit(0, width: 3, base: "h", signed: false) ==
                        sig(:wr_seg_index, width: 3)
                    )
                ),
                sig(:wr_seg_cache_valid, width: 1),
                sig(:es_cache_valid_to_reg, width: 1)
              )
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_75,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ds_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          (
              (
                ~sig(:ds_invalidate, width: 1)
              ) &
              mux(
                (
                    sig(:write_seg_cache_valid, width: 1) &
                    (
                        lit(3, width: 3, base: "h", signed: false) ==
                        sig(:wr_seg_index, width: 3)
                    )
                ),
                sig(:wr_seg_cache_valid, width: 1),
                sig(:ds_cache_valid_to_reg, width: 1)
              )
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_76,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ss_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          mux(
            (
                sig(:write_seg_cache_valid, width: 1) &
                (
                    lit(2, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_cache_valid, width: 1),
            sig(:ss_cache_valid_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_77,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :fs_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          (
              (
                ~sig(:fs_invalidate, width: 1)
              ) &
              mux(
                (
                    sig(:write_seg_cache_valid, width: 1) &
                    (
                        lit(4, width: 3, base: "h", signed: false) ==
                        sig(:wr_seg_index, width: 3)
                    )
                ),
                sig(:wr_seg_cache_valid, width: 1),
                sig(:fs_cache_valid_to_reg, width: 1)
              )
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_78,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :gs_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          (
              (
                ~sig(:gs_invalidate, width: 1)
              ) &
              mux(
                (
                    sig(:write_seg_cache_valid, width: 1) &
                    (
                        lit(5, width: 3, base: "h", signed: false) ==
                        sig(:wr_seg_index, width: 3)
                    )
                ),
                sig(:wr_seg_cache_valid, width: 1),
                sig(:gs_cache_valid_to_reg, width: 1)
              )
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_79,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :cs_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          mux(
            (
                sig(:write_seg_cache_valid, width: 1) &
                (
                    lit(1, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_cache_valid, width: 1),
            sig(:cs_cache_valid_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_80,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :ldtr_cache_valid,
      (
          (
            ~sig(:rst_n, width: 1)
          ) |
          mux(
            (
                sig(:write_seg_cache_valid, width: 1) &
                (
                    lit(6, width: 3, base: "h", signed: false) ==
                    sig(:wr_seg_index, width: 3)
                )
            ),
            sig(:wr_seg_cache_valid, width: 1),
            sig(:ldtr_cache_valid_to_reg, width: 1)
          )
      ),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_81,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:write_seg_cache_valid, width: 1) & (lit(7, width: 3, base: "h", signed: false) == sig(:wr_seg_index, width: 3)))) do
        assign(
          :tr_cache_valid,
          sig(:wr_seg_cache_valid, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :tr_cache_valid,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_81,
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

end
