# frozen_string_literal: true

class ImportedException < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: exception

  def self._import_decl_kinds
    {
      __VdfgRegularize_h6465c90e_0_0: :logic,
      __VdfgRegularize_h6465c90e_0_1: :logic,
      __VdfgRegularize_h6465c90e_0_10: :logic,
      __VdfgRegularize_h6465c90e_0_11: :logic,
      __VdfgRegularize_h6465c90e_0_12: :logic,
      __VdfgRegularize_h6465c90e_0_13: :logic,
      __VdfgRegularize_h6465c90e_0_2: :logic,
      __VdfgRegularize_h6465c90e_0_3: :logic,
      __VdfgRegularize_h6465c90e_0_4: :logic,
      __VdfgRegularize_h6465c90e_0_6: :logic,
      __VdfgRegularize_h6465c90e_0_7: :logic,
      __VdfgRegularize_h6465c90e_0_8: :logic,
      __VdfgRegularize_h6465c90e_0_9: :logic,
      active_dec: :wire,
      active_exe: :wire,
      active_rd: :wire,
      active_wr: :wire,
      cond_0: :wire,
      cond_4: :wire,
      cond_7: :wire,
      cond_8: :wire,
      count: :reg,
      count_to_reg: :wire,
      exc_eip_to_reg: :wire,
      exc_error_code_to_reg: :wire,
      exc_push_error_to_reg: :wire,
      exc_soft_int_ib_to_reg: :wire,
      exc_soft_int_to_reg: :wire,
      exc_vector_full: :reg,
      exc_vector_full_to_reg: :wire,
      exception_eip_from_wr: :wire,
      exception_init: :wire,
      exception_start: :wire,
      exception_type: :wire,
      external: :reg,
      external_to_reg: :wire,
      interrupt_load: :reg,
      interrupt_string_in_progress: :reg,
      last_type: :reg,
      last_type_to_reg: :wire,
      shutdown: :reg,
      shutdown_start: :wire,
      shutdown_to_reg: :wire,
      trap_eip: :reg,
      vector: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :dec_gp_fault
  input :dec_ud_fault
  input :dec_pf_fault
  input :rd_seg_gp_fault
  input :rd_descriptor_gp_fault
  input :rd_seg_ss_fault
  input :rd_io_allow_fault
  input :rd_ss_esp_from_tss_fault
  input :exe_div_exception
  input :exe_trigger_gp_fault
  input :exe_trigger_ts_fault
  input :exe_trigger_ss_fault
  input :exe_trigger_np_fault
  input :exe_trigger_nm_fault
  input :exe_trigger_db_fault
  input :exe_trigger_pf_fault
  input :exe_bound_fault
  input :exe_load_seg_gp_fault
  input :exe_load_seg_ss_fault
  input :exe_load_seg_np_fault
  input :wr_debug_init
  input :wr_new_push_ss_fault
  input :wr_string_es_fault
  input :wr_push_ss_fault
  input :read_ac_fault
  input :read_page_fault
  input :write_ac_fault
  input :write_page_fault
  input :tlb_code_pf_error_code, width: 16
  input :tlb_check_pf_error_code, width: 16
  input :tlb_write_pf_error_code, width: 16
  input :tlb_read_pf_error_code, width: 16
  input :wr_int
  input :wr_int_soft_int
  input :wr_int_soft_int_ib
  input :wr_int_vector, width: 8
  input :wr_exception_external_set
  input :wr_exception_finished
  input :eip, width: 32
  input :dec_eip, width: 32
  input :rd_eip, width: 32
  input :exe_eip, width: 32
  input :wr_eip, width: 32
  input :rd_consumed, width: 4
  input :exe_consumed, width: 4
  input :wr_consumed, width: 4
  input :rd_dec_is_front
  input :rd_is_front
  input :exe_is_front
  input :wr_is_front
  input :interrupt_vector, width: 8
  output :interrupt_done
  input :wr_interrupt_possible
  input :wr_string_in_progress_final
  input :wr_is_esp_speculative
  input :real_mode
  input :rd_error_code, width: 16
  input :exe_error_code, width: 16
  input :wr_error_code, width: 16
  output :exc_dec_reset
  output :exc_micro_reset
  output :exc_rd_reset
  output :exc_exe_reset
  output :exc_wr_reset
  output :exc_restore_esp
  output :exc_set_rflag
  output :exc_debug_start
  output :exc_init
  output :exc_load
  output :exc_eip, width: 32
  output :exc_vector, width: 8
  output :exc_error_code, width: 16
  output :exc_push_error
  output :exc_soft_int
  output :exc_soft_int_ib
  output :exc_pf_read
  output :exc_pf_write
  output :exc_pf_code
  output :exc_pf_check

  # Signals

  signal :__VdfgRegularize_h6465c90e_0_0
  signal :__VdfgRegularize_h6465c90e_0_1
  signal :__VdfgRegularize_h6465c90e_0_10
  signal :__VdfgRegularize_h6465c90e_0_11, width: 9
  signal :__VdfgRegularize_h6465c90e_0_12
  signal :__VdfgRegularize_h6465c90e_0_13
  signal :__VdfgRegularize_h6465c90e_0_2
  signal :__VdfgRegularize_h6465c90e_0_3
  signal :__VdfgRegularize_h6465c90e_0_4
  signal :__VdfgRegularize_h6465c90e_0_6
  signal :__VdfgRegularize_h6465c90e_0_7
  signal :__VdfgRegularize_h6465c90e_0_8
  signal :__VdfgRegularize_h6465c90e_0_9
  signal :active_dec
  signal :active_exe
  signal :active_rd
  signal :active_wr
  signal :cond_0
  signal :cond_4
  signal :cond_7
  signal :cond_8
  signal :count, width: 2
  signal :count_to_reg, width: 2
  signal :exc_eip_to_reg, width: 32
  signal :exc_error_code_to_reg, width: 16
  signal :exc_push_error_to_reg
  signal :exc_soft_int_ib_to_reg
  signal :exc_soft_int_to_reg
  signal :exc_vector_full, width: 9
  signal :exc_vector_full_to_reg, width: 9
  signal :exception_eip_from_wr, width: 32
  signal :exception_init
  signal :exception_start
  signal :exception_type, width: 2
  signal :external
  signal :external_to_reg
  signal :interrupt_load
  signal :interrupt_string_in_progress
  signal :last_type, width: 2
  signal :last_type_to_reg, width: 2
  signal :shutdown
  signal :shutdown_start
  signal :shutdown_to_reg
  signal :trap_eip, width: 32
  signal :vector, width: 8

  # Assignments

  assign :exc_vector,
    sig(:exc_vector_full, width: 9)[7..0]
  assign :exception_init,
    sig(:exc_vector_full, width: 9)[8]
  assign :exc_init,
    (
        sig(:exception_init, width: 1) |
        (
            sig(:wr_interrupt_possible, width: 1) |
            (
                sig(:interrupt_done, width: 1) |
                sig(:wr_debug_init, width: 1)
            )
        )
    )
  assign :active_dec,
    (
        (
            sig(:dec_gp_fault, width: 1) |
            (
                sig(:dec_pf_fault, width: 1) |
                sig(:dec_ud_fault, width: 1)
            )
        ) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_0, width: 1) &
            sig(:rd_dec_is_front, width: 1)
        )
    )
  assign :__VdfgRegularize_h6465c90e_0_0,
    (
      ~sig(:exc_init, width: 1)
    )
  assign :active_rd,
    (
        (
            sig(:rd_seg_gp_fault, width: 1) |
            (
                sig(:rd_descriptor_gp_fault, width: 1) |
                (
                    sig(:rd_seg_ss_fault, width: 1) |
                    (
                        sig(:rd_io_allow_fault, width: 1) |
                        (
                            sig(:rd_ss_esp_from_tss_fault, width: 1) |
                            (
                                sig(:read_ac_fault, width: 1) |
                                sig(:read_page_fault, width: 1)
                            )
                        )
                    )
                )
            )
        ) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_0, width: 1) &
            sig(:rd_is_front, width: 1)
        )
    )
  assign :active_exe,
    (
        (
            sig(:exe_div_exception, width: 1) |
            (
                sig(:exe_trigger_gp_fault, width: 1) |
                (
                    sig(:exe_trigger_ss_fault, width: 1) |
                    (
                        sig(:exe_trigger_ts_fault, width: 1) |
                        (
                            sig(:exe_trigger_nm_fault, width: 1) |
                            (
                                sig(:exe_trigger_np_fault, width: 1) |
                                (
                                    sig(:exe_trigger_db_fault, width: 1) |
                                    (
                                        sig(:exe_trigger_pf_fault, width: 1) |
                                        (
                                            sig(:exe_bound_fault, width: 1) |
                                            (
                                                sig(:exe_load_seg_gp_fault, width: 1) |
                                                (
                                                    sig(:exe_load_seg_np_fault, width: 1) |
                                                    sig(:exe_load_seg_ss_fault, width: 1)
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
        ) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_0, width: 1) &
            sig(:exe_is_front, width: 1)
        )
    )
  assign :active_wr,
    (
        (
            sig(:wr_new_push_ss_fault, width: 1) |
            (
                sig(:wr_string_es_fault, width: 1) |
                (
                    sig(:wr_push_ss_fault, width: 1) |
                    (
                        sig(:write_ac_fault, width: 1) |
                        (
                            sig(:wr_int, width: 1) |
                            sig(:write_page_fault, width: 1)
                        )
                    )
                )
            )
        ) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_0, width: 1) &
            sig(:wr_is_front, width: 1)
        )
    )
  assign :exc_pf_read,
    (
        sig(:active_rd, width: 1) &
        sig(:read_page_fault, width: 1)
    )
  assign :exc_pf_write,
    (
        sig(:active_wr, width: 1) &
        sig(:write_page_fault, width: 1)
    )
  assign :exc_pf_code,
    (
        sig(:active_dec, width: 1) &
        sig(:dec_pf_fault, width: 1)
    )
  assign :exc_pf_check,
    (
        sig(:active_exe, width: 1) &
        sig(:exe_trigger_pf_fault, width: 1)
    )
  assign :exception_eip_from_wr,
    (
        sig(:wr_eip, width: 32) -
        lit(0, width: 28, base: "d", signed: false).concat(
        sig(:wr_consumed, width: 4)
      )
    )
  assign :vector,
    mux(
      sig(:wr_debug_init, width: 1),
      lit(1, width: 8, base: "h", signed: false),
      sig(:exc_vector, width: 8)
    )
  assign :exception_type,
    mux(
      (
          (
              lit(0, width: 8, base: "h", signed: false) ==
              sig(:vector, width: 8)
          ) |
          (
              (
                  lit(10, width: 8, base: "h", signed: false) <=
                  sig(:vector, width: 8)
              ) &
              (
                  lit(13, width: 8, base: "h", signed: false) >=
                  sig(:vector, width: 8)
              )
          )
      ),
      lit(1, width: 2, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h6465c90e_0_1, width: 1),
        lit(3, width: 2, base: "h", signed: false),
        mux(
          sig(:__VdfgRegularize_h6465c90e_0_2, width: 1),
          lit(2, width: 2, base: "h", signed: false),
          lit(0, width: 2, base: "h", signed: false)
        )
      )
    )
  assign :__VdfgRegularize_h6465c90e_0_1,
    (
        lit(8, width: 8, base: "h", signed: false) ==
        sig(:vector, width: 8)
    )
  assign :__VdfgRegularize_h6465c90e_0_2,
    (
        lit(14, width: 8, base: "h", signed: false) ==
        sig(:vector, width: 8)
    )
  assign :shutdown_start,
    (
        (
            lit(2, width: 2, base: "h", signed: false) <
            sig(:count, width: 2)
        ) |
        (
            sig(:__VdfgRegularize_h6465c90e_0_3, width: 1) &
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:last_type, width: 2)
            )
        )
    )
  assign :__VdfgRegularize_h6465c90e_0_3,
    (
        lit(0, width: 2, base: "h", signed: false) <
        sig(:count, width: 2)
    )
  assign :exc_debug_start,
    (
        sig(:exc_load, width: 1) &
        (
            (
              ~sig(:interrupt_load, width: 1)
            ) &
            sig(:cond_4, width: 1)
        )
    )
  assign :cond_4,
    (
        lit(1, width: 8, base: "h", signed: false) ==
        sig(:vector, width: 8)
    )
  assign :cond_0,
    (
        sig(:exception_init, width: 1) |
        sig(:wr_debug_init, width: 1)
    )
  assign :cond_7,
    (
        sig(:cond_8, width: 1) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_3, width: 1) &
            (
                (
                    lit(3, width: 2, base: "h", signed: false) !=
                    sig(:exception_type, width: 2)
                ) &
                (
                    (
                        (
                            lit(1, width: 2, base: "h", signed: false) ==
                            sig(:last_type, width: 2)
                        ) &
                        sig(:__VdfgRegularize_h6465c90e_0_4, width: 1)
                    ) |
                    (
                        (
                            lit(2, width: 2, base: "h", signed: false) ==
                            sig(:last_type, width: 2)
                        ) &
                        (
                            sig(:__VdfgRegularize_h6465c90e_0_4, width: 1) |
                            (
                                lit(2, width: 2, base: "h", signed: false) ==
                                sig(:exception_type, width: 2)
                            )
                        )
                    )
                )
            )
        )
    )
  assign :cond_8,
    (
      ~sig(:shutdown_start, width: 1)
    )
  assign :__VdfgRegularize_h6465c90e_0_4,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:exception_type, width: 2)
    )
  assign :exc_soft_int_to_reg,
    (
        sig(:__VdfgRegularize_h6465c90e_0_6, width: 1) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_7, width: 1) &
            sig(:exc_soft_int, width: 1)
        )
    )
  assign :__VdfgRegularize_h6465c90e_0_6,
    (
      ~sig(:exception_start, width: 1)
    )
  assign :__VdfgRegularize_h6465c90e_0_7,
    (
      ~sig(:interrupt_done, width: 1)
    )
  assign :exc_push_error_to_reg,
    mux(
      sig(:exception_start, width: 1),
      (
          (
            ~sig(:real_mode, width: 1)
          ) &
          (
              sig(:__VdfgRegularize_h6465c90e_0_1, width: 1) |
              (
                  (
                      lit(10, width: 8, base: "h", signed: false) ==
                      sig(:vector, width: 8)
                  ) |
                  (
                      (
                          lit(11, width: 8, base: "h", signed: false) ==
                          sig(:vector, width: 8)
                      ) |
                      (
                          (
                              lit(12, width: 8, base: "h", signed: false) ==
                              sig(:vector, width: 8)
                          ) |
                          (
                              (
                                  lit(13, width: 8, base: "h", signed: false) ==
                                  sig(:vector, width: 8)
                              ) |
                              (
                                  sig(:__VdfgRegularize_h6465c90e_0_2, width: 1) |
                                  (
                                      lit(17, width: 8, base: "h", signed: false) ==
                                      sig(:vector, width: 8)
                                  )
                              )
                          )
                      )
                  )
              )
          )
      ),
      (
          sig(:__VdfgRegularize_h6465c90e_0_7, width: 1) &
          sig(:exc_push_error, width: 1)
      )
    )
  assign :exception_start,
    (
        sig(:cond_0, width: 1) &
        (
            (
              ~sig(:cond_7, width: 1)
            ) &
            sig(:cond_8, width: 1)
        )
    )
  assign :count_to_reg,
    (
        sig(:count, width: 2) +
        sig(:exception_start, width: 1)
    )
  assign :exc_eip_to_reg,
    mux(
      (
          sig(:__VdfgRegularize_h6465c90e_0_12, width: 1) &
          sig(:cond_0, width: 1)
      ),
      sig(:trap_eip, width: 32),
      mux(
        (
            sig(:__VdfgRegularize_h6465c90e_0_8, width: 1) &
            (
                (
                  ~sig(:wr_string_in_progress_final, width: 1)
                ) &
                sig(:wr_debug_init, width: 1)
            )
        ),
        sig(:wr_eip, width: 32),
        mux(
          (
              sig(:__VdfgRegularize_h6465c90e_0_8, width: 1) &
              (
                  sig(:wr_debug_init, width: 1) &
                  sig(:wr_string_in_progress_final, width: 1)
              )
          ),
          sig(:exception_eip_from_wr, width: 32),
          mux(
            sig(:interrupt_done, width: 1),
            mux(
              sig(:interrupt_string_in_progress, width: 1),
              sig(:exception_eip_from_wr, width: 32),
              sig(:wr_eip, width: 32)
            ),
            sig(:exc_eip, width: 32)
          )
        )
      )
    )
  assign :__VdfgRegularize_h6465c90e_0_12,
    (
        (
            lit(3, width: 8, base: "h", signed: false) ==
            sig(:vector, width: 8)
        ) |
        (
            (
                lit(4, width: 8, base: "h", signed: false) ==
                sig(:vector, width: 8)
            ) |
            (
                lit(18, width: 8, base: "h", signed: false) ==
                sig(:vector, width: 8)
            )
        )
    )
  assign :__VdfgRegularize_h6465c90e_0_8,
    (
        sig(:cond_0, width: 1) &
        sig(:cond_4, width: 1)
    )
  assign :external_to_reg,
    (
        sig(:cond_0, width: 1) |
        (
            sig(:external, width: 1) |
            sig(:interrupt_done, width: 1)
        )
    )
  assign :last_type_to_reg,
    mux(
      sig(:exception_start, width: 1),
      sig(:exception_type, width: 2),
      sig(:last_type, width: 2)
    )
  assign :exc_vector_full_to_reg,
    mux(
      sig(:__VdfgRegularize_h6465c90e_0_9, width: 1),
      lit(264, width: 9, base: "h", signed: false),
      mux(
        sig(:exception_start, width: 1),
        sig(:__VdfgRegularize_h6465c90e_0_11, width: 9),
        mux(
          sig(:__VdfgRegularize_h6465c90e_0_10, width: 1),
          sig(:__VdfgRegularize_h6465c90e_0_11, width: 9),
          mux(
            sig(:interrupt_done, width: 1),
            lit(0, width: 1, base: "d", signed: false).concat(
              sig(:interrupt_vector, width: 8)
            ),
            sig(:exc_vector_full, width: 9)
          )
        )
      )
    )
  assign :__VdfgRegularize_h6465c90e_0_9,
    (
        sig(:cond_0, width: 1) &
        sig(:cond_7, width: 1)
    )
  assign :__VdfgRegularize_h6465c90e_0_11,
    lit(0, width: 1, base: "d", signed: false).concat(
      sig(:vector, width: 8)
    )
  assign :__VdfgRegularize_h6465c90e_0_10,
    (
        sig(:cond_0, width: 1) &
        sig(:shutdown_start, width: 1)
    )
  assign :exc_error_code_to_reg,
    mux(
      sig(:__VdfgRegularize_h6465c90e_0_9, width: 1),
      lit(0, width: 16, base: "h", signed: false),
      mux(
        sig(:exception_start, width: 1),
        mux(
          sig(:real_mode, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                (
                    lit(14, width: 8, base: "h", signed: false) !=
                    sig(:vector, width: 8)
                ) &
                (
                    lit(8, width: 8, base: "h", signed: false) !=
                    sig(:vector, width: 8)
                )
            ),
            sig(:exc_error_code, width: 16)[15..1].concat(
              sig(:external, width: 1)
            ),
            sig(:exc_error_code, width: 16)
          )
        ),
        mux(
          sig(:interrupt_done, width: 1),
          lit(0, width: 16, base: "h", signed: false),
          sig(:exc_error_code, width: 16)
        )
      )
    )
  assign :exc_soft_int_ib_to_reg,
    (
        sig(:__VdfgRegularize_h6465c90e_0_6, width: 1) &
        (
            sig(:__VdfgRegularize_h6465c90e_0_7, width: 1) &
            sig(:exc_soft_int_ib, width: 1)
        )
    )
  assign :shutdown_to_reg,
    (
        sig(:__VdfgRegularize_h6465c90e_0_10, width: 1) |
        sig(:shutdown, width: 1)
    )
  assign :exc_set_rflag,
    (
        sig(:__VdfgRegularize_h6465c90e_0_13, width: 1) &
        (
            lit(1, width: 8, base: "h", signed: false) !=
            sig(:vector, width: 8)
        )
    )
  assign :__VdfgRegularize_h6465c90e_0_13,
    (
        (
          ~sig(:__VdfgRegularize_h6465c90e_0_12, width: 1)
        ) &
        sig(:cond_0, width: 1)
    )
  assign :exc_dec_reset,
    (
        sig(:cond_0, width: 1) |
        (
            sig(:interrupt_done, width: 1) |
            sig(:shutdown, width: 1)
        )
    )
  assign :exc_restore_esp,
    (
        sig(:__VdfgRegularize_h6465c90e_0_13, width: 1) &
        sig(:wr_is_esp_speculative, width: 1)
    )
  assign :exc_micro_reset,
    sig(:exc_dec_reset, width: 1)
  assign :exc_wr_reset,
    sig(:exc_dec_reset, width: 1)
  assign :exc_rd_reset,
    sig(:exc_dec_reset, width: 1)
  assign :exc_exe_reset,
    sig(:exc_dec_reset, width: 1)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :exc_vector_full,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:active_wr, width: 1) &
              sig(:wr_new_push_ss_fault, width: 1)
          ),
          lit(268, width: 9, base: "h", signed: false),
          mux(
            (
                sig(:active_wr, width: 1) &
                sig(:wr_string_es_fault, width: 1)
            ),
            lit(269, width: 9, base: "h", signed: false),
            mux(
              (
                  sig(:active_wr, width: 1) &
                  sig(:wr_push_ss_fault, width: 1)
              ),
              lit(268, width: 9, base: "h", signed: false),
              mux(
                (
                    sig(:active_wr, width: 1) &
                    sig(:write_ac_fault, width: 1)
                ),
                lit(273, width: 9, base: "h", signed: false),
                mux(
                  (
                      sig(:active_wr, width: 1) &
                      sig(:write_page_fault, width: 1)
                  ),
                  lit(270, width: 9, base: "h", signed: false),
                  mux(
                    (
                        sig(:active_wr, width: 1) &
                        sig(:wr_int, width: 1)
                    ),
                    lit(0, width: 1, base: "d", signed: false).concat(
                      sig(:wr_int_vector, width: 8)
                    ),
                    mux(
                      (
                          sig(:active_exe, width: 1) &
                          sig(:exe_div_exception, width: 1)
                      ),
                      lit(256, width: 9, base: "h", signed: false),
                      mux(
                        (
                            sig(:active_exe, width: 1) &
                            sig(:exe_trigger_gp_fault, width: 1)
                        ),
                        lit(269, width: 9, base: "h", signed: false),
                        mux(
                          (
                              sig(:active_exe, width: 1) &
                              sig(:exe_trigger_ts_fault, width: 1)
                          ),
                          lit(266, width: 9, base: "h", signed: false),
                          mux(
                            (
                                sig(:active_exe, width: 1) &
                                sig(:exe_trigger_ss_fault, width: 1)
                            ),
                            lit(268, width: 9, base: "h", signed: false),
                            mux(
                              (
                                  sig(:active_exe, width: 1) &
                                  sig(:exe_trigger_np_fault, width: 1)
                              ),
                              lit(267, width: 9, base: "h", signed: false),
                              mux(
                                (
                                    sig(:active_exe, width: 1) &
                                    sig(:exe_trigger_nm_fault, width: 1)
                                ),
                                lit(263, width: 9, base: "h", signed: false),
                                mux(
                                  (
                                      sig(:active_exe, width: 1) &
                                      sig(:exe_trigger_db_fault, width: 1)
                                  ),
                                  lit(257, width: 9, base: "h", signed: false),
                                  mux(
                                    (
                                        sig(:active_exe, width: 1) &
                                        sig(:exe_trigger_pf_fault, width: 1)
                                    ),
                                    lit(270, width: 9, base: "h", signed: false),
                                    mux(
                                      (
                                          sig(:active_exe, width: 1) &
                                          sig(:exe_bound_fault, width: 1)
                                      ),
                                      lit(261, width: 9, base: "h", signed: false),
                                      mux(
                                        (
                                            sig(:active_exe, width: 1) &
                                            sig(:exe_load_seg_gp_fault, width: 1)
                                        ),
                                        lit(269, width: 9, base: "h", signed: false),
                                        mux(
                                          (
                                              sig(:active_exe, width: 1) &
                                              sig(:exe_load_seg_ss_fault, width: 1)
                                          ),
                                          lit(268, width: 9, base: "h", signed: false),
                                          mux(
                                            (
                                                sig(:active_exe, width: 1) &
                                                sig(:exe_load_seg_np_fault, width: 1)
                                            ),
                                            lit(267, width: 9, base: "h", signed: false),
                                            mux(
                                              (
                                                  sig(:active_rd, width: 1) &
                                                  sig(:rd_seg_gp_fault, width: 1)
                                              ),
                                              lit(269, width: 9, base: "h", signed: false),
                                              mux(
                                                (
                                                    sig(:active_rd, width: 1) &
                                                    sig(:rd_descriptor_gp_fault, width: 1)
                                                ),
                                                lit(269, width: 9, base: "h", signed: false),
                                                mux(
                                                  (
                                                      sig(:active_rd, width: 1) &
                                                      sig(:rd_seg_ss_fault, width: 1)
                                                  ),
                                                  lit(268, width: 9, base: "h", signed: false),
                                                  mux(
                                                    (
                                                        sig(:active_rd, width: 1) &
                                                        sig(:rd_io_allow_fault, width: 1)
                                                    ),
                                                    lit(269, width: 9, base: "h", signed: false),
                                                    mux(
                                                      (
                                                          sig(:active_rd, width: 1) &
                                                          sig(:rd_ss_esp_from_tss_fault, width: 1)
                                                      ),
                                                      lit(266, width: 9, base: "h", signed: false),
                                                      mux(
                                                        (
                                                            sig(:active_rd, width: 1) &
                                                            sig(:read_ac_fault, width: 1)
                                                        ),
                                                        lit(273, width: 9, base: "h", signed: false),
                                                        mux(
                                                          (
                                                              sig(:active_rd, width: 1) &
                                                              sig(:read_page_fault, width: 1)
                                                          ),
                                                          lit(270, width: 9, base: "h", signed: false),
                                                          mux(
                                                            (
                                                                sig(:active_dec, width: 1) &
                                                                sig(:dec_gp_fault, width: 1)
                                                            ),
                                                            lit(269, width: 9, base: "h", signed: false),
                                                            mux(
                                                              (
                                                                  sig(:active_dec, width: 1) &
                                                                  sig(:dec_ud_fault, width: 1)
                                                              ),
                                                              lit(262, width: 9, base: "h", signed: false),
                                                              mux(
                                                                (
                                                                    sig(:active_dec, width: 1) &
                                                                    sig(:dec_pf_fault, width: 1)
                                                                ),
                                                                lit(270, width: 9, base: "h", signed: false),
                                                                sig(:exc_vector_full_to_reg, width: 9)
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
                      )
                    )
                  )
                )
              )
            )
          )
        ),
        lit(0, width: 9, base: "h", signed: false)
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
      :exc_error_code,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:active_wr, width: 1) &
              sig(:write_ac_fault, width: 1)
          ),
          lit(0, width: 16, base: "h", signed: false),
          mux(
            (
                sig(:active_wr, width: 1) &
                sig(:write_page_fault, width: 1)
            ),
            sig(:tlb_write_pf_error_code, width: 16),
            mux(
              sig(:active_wr, width: 1),
              sig(:wr_error_code, width: 16),
              mux(
                (
                    sig(:active_exe, width: 1) &
                    sig(:exe_trigger_pf_fault, width: 1)
                ),
                sig(:tlb_check_pf_error_code, width: 16),
                mux(
                  sig(:active_exe, width: 1),
                  sig(:exe_error_code, width: 16),
                  mux(
                    (
                        sig(:active_rd, width: 1) &
                        sig(:read_ac_fault, width: 1)
                    ),
                    lit(0, width: 16, base: "h", signed: false),
                    mux(
                      (
                          sig(:active_rd, width: 1) &
                          sig(:read_page_fault, width: 1)
                      ),
                      sig(:tlb_read_pf_error_code, width: 16),
                      mux(
                        sig(:active_rd, width: 1),
                        sig(:rd_error_code, width: 16),
                        mux(
                          (
                              sig(:active_dec, width: 1) &
                              sig(:dec_pf_fault, width: 1)
                          ),
                          sig(:tlb_code_pf_error_code, width: 16),
                          mux(
                            sig(:active_dec, width: 1),
                            lit(0, width: 16, base: "h", signed: false),
                            sig(:exc_error_code_to_reg, width: 16)
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        ),
        lit(0, width: 16, base: "h", signed: false)
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
      :exc_push_error,
      (
          sig(:rst_n, width: 1) &
          (
              (
                ~(
                    sig(:active_wr, width: 1) &
                    sig(:wr_int, width: 1)
                )
              ) &
              sig(:exc_push_error_to_reg, width: 1)
          )
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
      :exc_soft_int,
      (
          sig(:rst_n, width: 1) &
          mux(
            (
                sig(:active_wr, width: 1) &
                sig(:wr_int, width: 1)
            ),
            sig(:wr_int_soft_int, width: 1),
            sig(:exc_soft_int_to_reg, width: 1)
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
    assign(
      :exc_soft_int_ib,
      (
          sig(:rst_n, width: 1) &
          mux(
            (
                sig(:active_wr, width: 1) &
                sig(:wr_int, width: 1)
            ),
            sig(:wr_int_soft_int_ib, width: 1),
            sig(:exc_soft_int_ib_to_reg, width: 1)
          )
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
      :exc_load,
      (
          sig(:rst_n, width: 1) &
          (
              sig(:exception_start, width: 1) |
              sig(:interrupt_done, width: 1)
          )
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
      :external,
      (
          sig(:rst_n, width: 1) &
          (
              sig(:wr_exception_external_set, width: 1) |
              (
                  (
                    ~sig(:wr_exception_finished, width: 1)
                  ) &
                  sig(:external_to_reg, width: 1)
              )
          )
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
      :count,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:wr_exception_finished, width: 1),
          lit(0, width: 2, base: "h", signed: false),
          sig(:count_to_reg, width: 2)
        ),
        lit(0, width: 2, base: "h", signed: false)
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
      :last_type,
      mux(
        sig(:rst_n, width: 1),
        sig(:last_type_to_reg, width: 2),
        lit(0, width: 2, base: "h", signed: false)
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
      :exc_eip,
      mux(
        sig(:rst_n, width: 1),
        mux(
          sig(:active_wr, width: 1),
          sig(:exception_eip_from_wr, width: 32),
          mux(
            sig(:active_exe, width: 1),
            (
                sig(:exe_eip, width: 32) -
                lit(0, width: 28, base: "d", signed: false).concat(
                sig(:exe_consumed, width: 4)
              )
            ),
            mux(
              sig(:active_rd, width: 1),
              (
                  sig(:rd_eip, width: 32) -
                  lit(0, width: 28, base: "d", signed: false).concat(
                  sig(:rd_consumed, width: 4)
                )
              ),
              mux(
                sig(:active_dec, width: 1),
                sig(:eip, width: 32),
                sig(:exc_eip_to_reg, width: 32)
              )
            )
          )
        ),
        lit(0, width: 32, base: "h", signed: false)
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:active_wr, width: 1)) do
        assign(
          :trap_eip,
          sig(:wr_eip, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:active_exe, width: 1)) do
            assign(
              :trap_eip,
              sig(:exe_eip, width: 32),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:active_rd, width: 1)) do
                assign(
                  :trap_eip,
                  sig(:rd_eip, width: 32),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt(sig(:active_dec, width: 1)) do
                    assign(
                      :trap_eip,
                      sig(:dec_eip, width: 32),
                      kind: :nonblocking
                    )
                  end
                end
              end
            end
          end
        end
      end
      else_block do
        assign(
          :trap_eip,
          lit(0, width: 32, base: "h", signed: false),
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
    assign(
      :shutdown,
      (
          sig(:rst_n, width: 1) &
          sig(:shutdown_to_reg, width: 1)
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
      :interrupt_done,
      (
          sig(:rst_n, width: 1) &
          sig(:wr_interrupt_possible, width: 1)
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
      :interrupt_load,
      (
          sig(:rst_n, width: 1) &
          sig(:interrupt_done, width: 1)
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:wr_interrupt_possible, width: 1) & sig(:wr_string_in_progress_final, width: 1))) do
        assign(
          :interrupt_string_in_progress,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:wr_interrupt_possible, width: 1)) do
            assign(
              :interrupt_string_in_progress,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :interrupt_string_in_progress,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

end
