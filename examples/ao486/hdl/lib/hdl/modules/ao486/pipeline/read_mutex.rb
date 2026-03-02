# frozen_string_literal: true

class ReadMutex < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read_mutex

  def self._import_decl_kinds
    {
      __VdfgRegularize_h5d6336af_0_0: :logic,
      __VdfgRegularize_h5d6336af_0_1: :logic,
      __VdfgRegularize_h5d6336af_0_10: :logic,
      __VdfgRegularize_h5d6336af_0_11: :logic,
      __VdfgRegularize_h5d6336af_0_12: :logic,
      __VdfgRegularize_h5d6336af_0_13: :logic,
      __VdfgRegularize_h5d6336af_0_14: :logic,
      __VdfgRegularize_h5d6336af_0_15: :logic,
      __VdfgRegularize_h5d6336af_0_16: :logic,
      __VdfgRegularize_h5d6336af_0_17: :logic,
      __VdfgRegularize_h5d6336af_0_18: :logic,
      __VdfgRegularize_h5d6336af_0_19: :logic,
      __VdfgRegularize_h5d6336af_0_2: :logic,
      __VdfgRegularize_h5d6336af_0_20: :logic,
      __VdfgRegularize_h5d6336af_0_21: :logic,
      __VdfgRegularize_h5d6336af_0_22: :logic,
      __VdfgRegularize_h5d6336af_0_23: :logic,
      __VdfgRegularize_h5d6336af_0_24: :logic,
      __VdfgRegularize_h5d6336af_0_25: :logic,
      __VdfgRegularize_h5d6336af_0_26: :logic,
      __VdfgRegularize_h5d6336af_0_27: :logic,
      __VdfgRegularize_h5d6336af_0_28: :logic,
      __VdfgRegularize_h5d6336af_0_29: :logic,
      __VdfgRegularize_h5d6336af_0_3: :logic,
      __VdfgRegularize_h5d6336af_0_30: :logic,
      __VdfgRegularize_h5d6336af_0_31: :logic,
      __VdfgRegularize_h5d6336af_0_32: :logic,
      __VdfgRegularize_h5d6336af_0_33: :logic,
      __VdfgRegularize_h5d6336af_0_34: :logic,
      __VdfgRegularize_h5d6336af_0_35: :logic,
      __VdfgRegularize_h5d6336af_0_4: :logic,
      __VdfgRegularize_h5d6336af_0_5: :logic,
      __VdfgRegularize_h5d6336af_0_6: :logic,
      __VdfgRegularize_h5d6336af_0_7: :logic,
      __VdfgRegularize_h5d6336af_0_8: :logic,
      __VdfgRegularize_h5d6336af_0_9: :logic,
      _unused_ok: :wire,
      rd_mutex_current: :wire
    }
  end

  # Ports

  input :rd_req_memory
  input :rd_req_eflags
  input :rd_req_all
  input :rd_req_reg
  input :rd_req_rm
  input :rd_req_implicit_reg
  input :rd_req_reg_not_8bit
  input :rd_req_edi
  input :rd_req_esi
  input :rd_req_ebp
  input :rd_req_esp
  input :rd_req_ebx
  input :rd_req_edx_eax
  input :rd_req_edx
  input :rd_req_ecx
  input :rd_req_eax
  input :rd_decoder, width: 88
  input :rd_is_8bit
  input :rd_modregrm_mod, width: 2
  input :rd_modregrm_reg, width: 3
  input :rd_modregrm_rm, width: 3
  input :rd_address_16bit
  input :rd_address_32bit
  input :rd_sib, width: 8
  input :exe_mutex, width: 11
  input :wr_mutex, width: 11
  input :address_bits_transform
  input :address_xlat_transform
  input :address_stack_pop
  input :address_stack_pop_next
  input :address_enter
  input :address_enter_last
  input :address_leave
  input :address_esi
  input :address_edi
  output :rd_mutex_next, width: 11
  output :rd_mutex_busy_active
  output :rd_mutex_busy_memory
  output :rd_mutex_busy_eflags
  output :rd_mutex_busy_ebp
  output :rd_mutex_busy_esp
  output :rd_mutex_busy_edx
  output :rd_mutex_busy_ecx
  output :rd_mutex_busy_eax
  output :rd_mutex_busy_modregrm_reg
  output :rd_mutex_busy_modregrm_rm
  output :rd_mutex_busy_implicit_reg
  output :rd_address_waiting

  # Signals

  signal :__VdfgRegularize_h5d6336af_0_0
  signal :__VdfgRegularize_h5d6336af_0_1
  signal :__VdfgRegularize_h5d6336af_0_10
  signal :__VdfgRegularize_h5d6336af_0_11
  signal :__VdfgRegularize_h5d6336af_0_12
  signal :__VdfgRegularize_h5d6336af_0_13
  signal :__VdfgRegularize_h5d6336af_0_14
  signal :__VdfgRegularize_h5d6336af_0_15
  signal :__VdfgRegularize_h5d6336af_0_16
  signal :__VdfgRegularize_h5d6336af_0_17
  signal :__VdfgRegularize_h5d6336af_0_18
  signal :__VdfgRegularize_h5d6336af_0_19
  signal :__VdfgRegularize_h5d6336af_0_2
  signal :__VdfgRegularize_h5d6336af_0_20
  signal :__VdfgRegularize_h5d6336af_0_21
  signal :__VdfgRegularize_h5d6336af_0_22
  signal :__VdfgRegularize_h5d6336af_0_23
  signal :__VdfgRegularize_h5d6336af_0_24
  signal :__VdfgRegularize_h5d6336af_0_25
  signal :__VdfgRegularize_h5d6336af_0_26
  signal :__VdfgRegularize_h5d6336af_0_27
  signal :__VdfgRegularize_h5d6336af_0_28
  signal :__VdfgRegularize_h5d6336af_0_29
  signal :__VdfgRegularize_h5d6336af_0_3
  signal :__VdfgRegularize_h5d6336af_0_30
  signal :__VdfgRegularize_h5d6336af_0_31
  signal :__VdfgRegularize_h5d6336af_0_32
  signal :__VdfgRegularize_h5d6336af_0_33
  signal :__VdfgRegularize_h5d6336af_0_34
  signal :__VdfgRegularize_h5d6336af_0_35
  signal :__VdfgRegularize_h5d6336af_0_4
  signal :__VdfgRegularize_h5d6336af_0_5
  signal :__VdfgRegularize_h5d6336af_0_6
  signal :__VdfgRegularize_h5d6336af_0_7
  signal :__VdfgRegularize_h5d6336af_0_8
  signal :__VdfgRegularize_h5d6336af_0_9
  signal :_unused_ok
  signal :rd_mutex_current, width: 11

  # Assignments

  assign :rd_mutex_next,
    lit(1, width: 1, base: "h", signed: false).concat(
      sig(:rd_req_memory, width: 1).concat(
        sig(:rd_req_eflags, width: 1).concat(
          (
              (
                  sig(:rd_req_reg, width: 1) &
                  (
                      sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                      sig(:__VdfgRegularize_h5d6336af_0_0, width: 1)
                  )
              ) |
              (
                  (
                      sig(:rd_req_rm, width: 1) &
                      (
                          sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                          sig(:__VdfgRegularize_h5d6336af_0_2, width: 1)
                      )
                  ) |
                  (
                      (
                          sig(:rd_req_implicit_reg, width: 1) &
                          (
                              sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                              sig(:__VdfgRegularize_h5d6336af_0_3, width: 1)
                          )
                      ) |
                      (
                          sig(:rd_req_all, width: 1) |
                          (
                              sig(:rd_req_edi, width: 1) |
                              (
                                  sig(:rd_req_reg_not_8bit, width: 1) &
                                  sig(:__VdfgRegularize_h5d6336af_0_0, width: 1)
                              )
                          )
                      )
                  )
              )
          ).concat(
            (
                (
                    sig(:rd_req_reg, width: 1) &
                    (
                        sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                        sig(:__VdfgRegularize_h5d6336af_0_4, width: 1)
                    )
                ) |
                (
                    (
                        sig(:rd_req_rm, width: 1) &
                        (
                            sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                            sig(:__VdfgRegularize_h5d6336af_0_5, width: 1)
                        )
                    ) |
                    (
                        (
                            sig(:rd_req_implicit_reg, width: 1) &
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                                sig(:__VdfgRegularize_h5d6336af_0_6, width: 1)
                            )
                        ) |
                        (
                            sig(:rd_req_all, width: 1) |
                            (
                                sig(:rd_req_esi, width: 1) |
                                (
                                    sig(:rd_req_reg_not_8bit, width: 1) &
                                    sig(:__VdfgRegularize_h5d6336af_0_4, width: 1)
                                )
                            )
                        )
                    )
                )
            ).concat(
              (
                  (
                      sig(:rd_req_reg, width: 1) &
                      (
                          sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                          sig(:__VdfgRegularize_h5d6336af_0_7, width: 1)
                      )
                  ) |
                  (
                      (
                          sig(:rd_req_rm, width: 1) &
                          (
                              sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                              sig(:__VdfgRegularize_h5d6336af_0_8, width: 1)
                          )
                      ) |
                      (
                          (
                              sig(:rd_req_implicit_reg, width: 1) &
                              (
                                  sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                                  sig(:__VdfgRegularize_h5d6336af_0_9, width: 1)
                              )
                          ) |
                          (
                              sig(:rd_req_all, width: 1) |
                              (
                                  sig(:rd_req_ebp, width: 1) |
                                  (
                                      sig(:rd_req_reg_not_8bit, width: 1) &
                                      sig(:__VdfgRegularize_h5d6336af_0_7, width: 1)
                                  )
                              )
                          )
                      )
                  )
              ).concat(
                (
                    (
                        sig(:rd_req_reg, width: 1) &
                        (
                            sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                            sig(:__VdfgRegularize_h5d6336af_0_10, width: 1)
                        )
                    ) |
                    (
                        (
                            sig(:rd_req_rm, width: 1) &
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                                sig(:__VdfgRegularize_h5d6336af_0_11, width: 1)
                            )
                        ) |
                        (
                            (
                                sig(:rd_req_implicit_reg, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                                    sig(:__VdfgRegularize_h5d6336af_0_12, width: 1)
                                )
                            ) |
                            (
                                sig(:rd_req_esp, width: 1) |
                                (
                                    sig(:rd_req_all, width: 1) |
                                    (
                                        sig(:rd_req_reg_not_8bit, width: 1) &
                                        sig(:__VdfgRegularize_h5d6336af_0_10, width: 1)
                                    )
                                )
                            )
                        )
                    )
                ).concat(
                  (
                      (
                          sig(:rd_req_reg, width: 1) &
                          (
                              sig(:__VdfgRegularize_h5d6336af_0_13, width: 1) |
                              (
                                  sig(:__VdfgRegularize_h5d6336af_0_0, width: 1) &
                                  sig(:rd_is_8bit, width: 1)
                              )
                          )
                      ) |
                      (
                          (
                              sig(:rd_req_rm, width: 1) &
                              (
                                  sig(:__VdfgRegularize_h5d6336af_0_14, width: 1) |
                                  (
                                      sig(:__VdfgRegularize_h5d6336af_0_2, width: 1) &
                                      sig(:rd_is_8bit, width: 1)
                                  )
                              )
                          ) |
                          (
                              (
                                  sig(:rd_req_implicit_reg, width: 1) &
                                  (
                                      sig(:__VdfgRegularize_h5d6336af_0_15, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h5d6336af_0_3, width: 1) &
                                          sig(:rd_is_8bit, width: 1)
                                      )
                                  )
                              ) |
                              (
                                  sig(:rd_req_ebx, width: 1) |
                                  (
                                      sig(:rd_req_all, width: 1) |
                                      (
                                          sig(:rd_req_reg_not_8bit, width: 1) &
                                          sig(:__VdfgRegularize_h5d6336af_0_13, width: 1)
                                      )
                                  )
                              )
                          )
                      )
                  ).concat(
                    (
                        (
                            sig(:rd_req_reg, width: 1) &
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_16, width: 1) |
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_4, width: 1) &
                                    sig(:rd_is_8bit, width: 1)
                                )
                            )
                        ) |
                        (
                            (
                                sig(:rd_req_rm, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_17, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h5d6336af_0_5, width: 1) &
                                        sig(:rd_is_8bit, width: 1)
                                    )
                                )
                            ) |
                            (
                                sig(:rd_req_edx, width: 1) |
                                (
                                    sig(:rd_req_edx_eax, width: 1) |
                                    (
                                        (
                                            sig(:rd_req_implicit_reg, width: 1) &
                                            (
                                                sig(:__VdfgRegularize_h5d6336af_0_18, width: 1) |
                                                (
                                                    sig(:__VdfgRegularize_h5d6336af_0_6, width: 1) &
                                                    sig(:rd_is_8bit, width: 1)
                                                )
                                            )
                                        ) |
                                        (
                                            sig(:rd_req_all, width: 1) |
                                            (
                                                sig(:rd_req_reg_not_8bit, width: 1) &
                                                sig(:__VdfgRegularize_h5d6336af_0_16, width: 1)
                                            )
                                        )
                                    )
                                )
                            )
                        )
                    ).concat(
                      (
                          (
                              sig(:rd_req_reg, width: 1) &
                              (
                                  sig(:__VdfgRegularize_h5d6336af_0_19, width: 1) |
                                  (
                                      sig(:__VdfgRegularize_h5d6336af_0_7, width: 1) &
                                      sig(:rd_is_8bit, width: 1)
                                  )
                              )
                          ) |
                          (
                              (
                                  sig(:rd_req_rm, width: 1) &
                                  (
                                      sig(:__VdfgRegularize_h5d6336af_0_20, width: 1) |
                                      (
                                          sig(:__VdfgRegularize_h5d6336af_0_8, width: 1) &
                                          sig(:rd_is_8bit, width: 1)
                                      )
                                  )
                              ) |
                              (
                                  (
                                      sig(:rd_req_implicit_reg, width: 1) &
                                      (
                                          sig(:__VdfgRegularize_h5d6336af_0_21, width: 1) |
                                          (
                                              sig(:__VdfgRegularize_h5d6336af_0_9, width: 1) &
                                              sig(:rd_is_8bit, width: 1)
                                          )
                                      )
                                  ) |
                                  (
                                      sig(:rd_req_ecx, width: 1) |
                                      (
                                          sig(:rd_req_all, width: 1) |
                                          (
                                              sig(:rd_req_reg_not_8bit, width: 1) &
                                              sig(:__VdfgRegularize_h5d6336af_0_19, width: 1)
                                          )
                                      )
                                  )
                              )
                          )
                      ).concat(
                        (
                            (
                                sig(:rd_req_reg, width: 1) &
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_22, width: 1) |
                                    (
                                        sig(:__VdfgRegularize_h5d6336af_0_10, width: 1) &
                                        sig(:rd_is_8bit, width: 1)
                                    )
                                )
                            ) |
                            (
                                (
                                    sig(:rd_req_rm, width: 1) &
                                    (
                                        sig(:__VdfgRegularize_h5d6336af_0_23, width: 1) |
                                        (
                                            sig(:__VdfgRegularize_h5d6336af_0_11, width: 1) &
                                            sig(:rd_is_8bit, width: 1)
                                        )
                                    )
                                ) |
                                (
                                    sig(:rd_req_eax, width: 1) |
                                    (
                                        sig(:rd_req_edx_eax, width: 1) |
                                        (
                                            (
                                                sig(:rd_req_implicit_reg, width: 1) &
                                                (
                                                    sig(:__VdfgRegularize_h5d6336af_0_24, width: 1) |
                                                    (
                                                        sig(:__VdfgRegularize_h5d6336af_0_12, width: 1) &
                                                        sig(:rd_is_8bit, width: 1)
                                                    )
                                                )
                                            ) |
                                            (
                                                sig(:rd_req_all, width: 1) |
                                                (
                                                    sig(:rd_req_reg_not_8bit, width: 1) &
                                                    sig(:__VdfgRegularize_h5d6336af_0_22, width: 1)
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
  assign :__VdfgRegularize_h5d6336af_0_1,
    (
      ~sig(:rd_is_8bit, width: 1)
    )
  assign :__VdfgRegularize_h5d6336af_0_0,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_2,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_3,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_4,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_5,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_6,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_7,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_8,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_9,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_10,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_11,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_12,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_13,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_14,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_15,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_16,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_17,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_18,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_19,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_20,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_21,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :__VdfgRegularize_h5d6336af_0_22,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_reg, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_23,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h5d6336af_0_24,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:rd_decoder, width: 88)[2..0]
    )
  assign :rd_mutex_current,
    (
        sig(:exe_mutex, width: 11) |
        sig(:wr_mutex, width: 11)
    )
  assign :rd_mutex_busy_active,
    sig(:rd_mutex_current, width: 11)[10]
  assign :rd_mutex_busy_memory,
    sig(:rd_mutex_current, width: 11)[9]
  assign :rd_mutex_busy_eflags,
    sig(:rd_mutex_current, width: 11)[8]
  assign :rd_mutex_busy_ebp,
    sig(:rd_mutex_current, width: 11)[5]
  assign :rd_mutex_busy_esp,
    sig(:rd_mutex_current, width: 11)[4]
  assign :rd_mutex_busy_edx,
    sig(:rd_mutex_current, width: 11)[2]
  assign :rd_mutex_busy_ecx,
    sig(:rd_mutex_current, width: 11)[1]
  assign :rd_mutex_busy_eax,
    sig(:rd_mutex_current, width: 11)[0]
  assign :rd_mutex_busy_modregrm_reg,
    (
        sig(:__VdfgRegularize_h5d6336af_0_35, width: 1) |
        (
            (
                sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                sig(:__VdfgRegularize_h5d6336af_0_29, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                    sig(:__VdfgRegularize_h5d6336af_0_28, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_h5d6336af_0_10, width: 1) &
                        sig(:__VdfgRegularize_h5d6336af_0_33, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h5d6336af_0_7, width: 1) &
                            sig(:__VdfgRegularize_h5d6336af_0_32, width: 1)
                        ) |
                        (
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_4, width: 1) &
                                sig(:__VdfgRegularize_h5d6336af_0_31, width: 1)
                            ) |
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_0, width: 1) &
                                (
                                    sig(:rd_mutex_current, width: 11)[3] &
                                    sig(:rd_is_8bit, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_35,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_22, width: 1) &
            sig(:rd_mutex_busy_eax, width: 1)
        ) |
        (
            (
                sig(:__VdfgRegularize_h5d6336af_0_19, width: 1) &
                sig(:rd_mutex_busy_ecx, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_h5d6336af_0_16, width: 1) &
                    sig(:rd_mutex_busy_edx, width: 1)
                ) |
                (
                    sig(:__VdfgRegularize_h5d6336af_0_13, width: 1) &
                    sig(:rd_mutex_current, width: 11)[3]
                )
            )
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_29,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_10, width: 1) &
            sig(:rd_mutex_busy_esp, width: 1)
        ) |
        (
            sig(:__VdfgRegularize_h5d6336af_0_7, width: 1) &
            sig(:rd_mutex_busy_ebp, width: 1)
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_28,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_4, width: 1) &
            sig(:rd_mutex_current, width: 11)[6]
        ) |
        (
            sig(:__VdfgRegularize_h5d6336af_0_0, width: 1) &
            sig(:rd_mutex_current, width: 11)[7]
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_33,
    (
        sig(:rd_mutex_busy_eax, width: 1) &
        sig(:rd_is_8bit, width: 1)
    )
  assign :__VdfgRegularize_h5d6336af_0_32,
    (
        sig(:rd_mutex_busy_ecx, width: 1) &
        sig(:rd_is_8bit, width: 1)
    )
  assign :__VdfgRegularize_h5d6336af_0_31,
    (
        sig(:rd_mutex_busy_edx, width: 1) &
        sig(:rd_is_8bit, width: 1)
    )
  assign :rd_mutex_busy_modregrm_rm,
    (
        sig(:__VdfgRegularize_h5d6336af_0_34, width: 1) |
        (
            (
                sig(:__VdfgRegularize_h5d6336af_0_11, width: 1) &
                (
                    sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                    sig(:rd_mutex_busy_esp, width: 1)
                )
            ) |
            (
                (
                    sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                    sig(:__VdfgRegularize_h5d6336af_0_25, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_h5d6336af_0_1, width: 1) &
                        sig(:__VdfgRegularize_h5d6336af_0_30, width: 1)
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h5d6336af_0_11, width: 1) &
                            sig(:__VdfgRegularize_h5d6336af_0_33, width: 1)
                        ) |
                        (
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_8, width: 1) &
                                sig(:__VdfgRegularize_h5d6336af_0_32, width: 1)
                            ) |
                            (
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_5, width: 1) &
                                    sig(:__VdfgRegularize_h5d6336af_0_31, width: 1)
                                ) |
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_26, width: 1) &
                                    sig(:rd_is_8bit, width: 1)
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_34,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_23, width: 1) &
            sig(:rd_mutex_busy_eax, width: 1)
        ) |
        (
            (
                sig(:__VdfgRegularize_h5d6336af_0_20, width: 1) &
                sig(:rd_mutex_busy_ecx, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_h5d6336af_0_17, width: 1) &
                    sig(:rd_mutex_busy_edx, width: 1)
                ) |
                (
                    sig(:__VdfgRegularize_h5d6336af_0_14, width: 1) &
                    sig(:rd_mutex_current, width: 11)[3]
                )
            )
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_25,
    (
        sig(:__VdfgRegularize_h5d6336af_0_8, width: 1) &
        sig(:rd_mutex_busy_ebp, width: 1)
    )
  assign :__VdfgRegularize_h5d6336af_0_30,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_5, width: 1) &
            sig(:rd_mutex_current, width: 11)[6]
        ) |
        (
            sig(:__VdfgRegularize_h5d6336af_0_2, width: 1) &
            sig(:rd_mutex_current, width: 11)[7]
        )
    )
  assign :__VdfgRegularize_h5d6336af_0_26,
    (
        sig(:__VdfgRegularize_h5d6336af_0_2, width: 1) &
        sig(:rd_mutex_current, width: 11)[3]
    )
  assign :rd_mutex_busy_implicit_reg,
    (
        (
            sig(:__VdfgRegularize_h5d6336af_0_24, width: 1) &
            sig(:rd_mutex_busy_eax, width: 1)
        ) |
        (
            (
                sig(:__VdfgRegularize_h5d6336af_0_21, width: 1) &
                sig(:rd_mutex_busy_ecx, width: 1)
            ) |
            (
                (
                    sig(:__VdfgRegularize_h5d6336af_0_18, width: 1) &
                    sig(:rd_mutex_busy_edx, width: 1)
                ) |
                (
                    (
                        sig(:__VdfgRegularize_h5d6336af_0_15, width: 1) &
                        sig(:rd_mutex_current, width: 11)[3]
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h5d6336af_0_12, width: 1) &
                            sig(:rd_mutex_busy_esp, width: 1)
                        ) |
                        (
                            (
                                sig(:__VdfgRegularize_h5d6336af_0_9, width: 1) &
                                sig(:rd_mutex_busy_ebp, width: 1)
                            ) |
                            (
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_6, width: 1) &
                                    sig(:rd_mutex_current, width: 11)[6]
                                ) |
                                (
                                    sig(:__VdfgRegularize_h5d6336af_0_3, width: 1) &
                                    sig(:rd_mutex_current, width: 11)[7]
                                )
                            )
                        )
                    )
                )
            )
        )
    )
  assign :rd_address_waiting,
    (
        (
            sig(:address_bits_transform, width: 1) &
            (
                sig(:__VdfgRegularize_h5d6336af_0_35, width: 1) |
                (
                    sig(:__VdfgRegularize_h5d6336af_0_29, width: 1) |
                    sig(:__VdfgRegularize_h5d6336af_0_28, width: 1)
                )
            )
        ) |
        (
            (
                sig(:address_xlat_transform, width: 1) &
                (
                    sig(:rd_mutex_busy_eax, width: 1) |
                    sig(:rd_mutex_current, width: 11)[3]
                )
            ) |
            (
                (
                    sig(:address_stack_pop, width: 1) &
                    sig(:rd_mutex_busy_esp, width: 1)
                ) |
                (
                    (
                        sig(:address_stack_pop_next, width: 1) &
                        sig(:rd_mutex_busy_esp, width: 1)
                    ) |
                    (
                        (
                            sig(:address_enter_last, width: 1) &
                            sig(:rd_mutex_busy_esp, width: 1)
                        ) |
                        (
                            (
                                sig(:address_enter, width: 1) &
                                sig(:rd_mutex_busy_ebp, width: 1)
                            ) |
                            (
                                (
                                    sig(:address_leave, width: 1) &
                                    sig(:rd_mutex_busy_ebp, width: 1)
                                ) |
                                (
                                    (
                                        sig(:address_esi, width: 1) &
                                        sig(:rd_mutex_current, width: 11)[6]
                                    ) |
                                    (
                                        (
                                            sig(:address_edi, width: 1) &
                                            sig(:rd_mutex_current, width: 11)[7]
                                        ) |
                                        (
                                            (
                                                sig(:rd_address_16bit, width: 1) &
                                                (
                                                    (
                                                      ~(
                                                          sig(:__VdfgRegularize_h5d6336af_0_27, width: 1) &
                                                          sig(:__VdfgRegularize_h5d6336af_0_5, width: 1)
                                                      )
                                                    ) &
                                                    (
                                                        (
                                                            sig(:__VdfgRegularize_h5d6336af_0_23, width: 1) &
                                                            (
                                                                sig(:rd_mutex_current, width: 11)[3] |
                                                                sig(:rd_mutex_current, width: 11)[6]
                                                            )
                                                        ) |
                                                        (
                                                            (
                                                                sig(:__VdfgRegularize_h5d6336af_0_20, width: 1) &
                                                                (
                                                                    sig(:rd_mutex_current, width: 11)[3] |
                                                                    sig(:rd_mutex_current, width: 11)[7]
                                                                )
                                                            ) |
                                                            (
                                                                (
                                                                    sig(:__VdfgRegularize_h5d6336af_0_17, width: 1) &
                                                                    (
                                                                        sig(:rd_mutex_busy_ebp, width: 1) |
                                                                        sig(:rd_mutex_current, width: 11)[6]
                                                                    )
                                                                ) |
                                                                (
                                                                    (
                                                                        sig(:__VdfgRegularize_h5d6336af_0_14, width: 1) &
                                                                        (
                                                                            sig(:rd_mutex_busy_ebp, width: 1) |
                                                                            sig(:rd_mutex_current, width: 11)[7]
                                                                        )
                                                                    ) |
                                                                    (
                                                                        (
                                                                            sig(:__VdfgRegularize_h5d6336af_0_11, width: 1) &
                                                                            sig(:rd_mutex_current, width: 11)[6]
                                                                        ) |
                                                                        (
                                                                            (
                                                                                sig(:__VdfgRegularize_h5d6336af_0_8, width: 1) &
                                                                                sig(:rd_mutex_current, width: 11)[7]
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    sig(:__VdfgRegularize_h5d6336af_0_5, width: 1) &
                                                                                    sig(:rd_mutex_busy_ebp, width: 1)
                                                                                ) |
                                                                                sig(:__VdfgRegularize_h5d6336af_0_26, width: 1)
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            )
                                                        )
                                                    )
                                                )
                                            ) |
                                            (
                                                sig(:rd_address_32bit, width: 1) &
                                                (
                                                    (
                                                      ~(
                                                          sig(:__VdfgRegularize_h5d6336af_0_27, width: 1) &
                                                          sig(:__VdfgRegularize_h5d6336af_0_8, width: 1)
                                                      )
                                                    ) &
                                                    (
                                                        sig(:__VdfgRegularize_h5d6336af_0_34, width: 1) |
                                                        (
                                                            (
                                                                sig(:__VdfgRegularize_h5d6336af_0_11, width: 1) &
                                                                (
                                                                    (
                                                                        (
                                                                            (
                                                                                lit(0, width: 3, base: "h", signed: false) ==
                                                                                sig(:rd_sib, width: 8)[5..3]
                                                                            ) |
                                                                            (
                                                                                lit(0, width: 3, base: "h", signed: false) ==
                                                                                sig(:rd_sib, width: 8)[2..0]
                                                                            )
                                                                        ) &
                                                                        sig(:rd_mutex_busy_eax, width: 1)
                                                                    ) |
                                                                    (
                                                                        (
                                                                            (
                                                                                (
                                                                                    lit(1, width: 3, base: "h", signed: false) ==
                                                                                    sig(:rd_sib, width: 8)[5..3]
                                                                                ) |
                                                                                (
                                                                                    lit(1, width: 3, base: "h", signed: false) ==
                                                                                    sig(:rd_sib, width: 8)[2..0]
                                                                                )
                                                                            ) &
                                                                            sig(:rd_mutex_busy_ecx, width: 1)
                                                                        ) |
                                                                        (
                                                                            (
                                                                                (
                                                                                    (
                                                                                        lit(2, width: 3, base: "h", signed: false) ==
                                                                                        sig(:rd_sib, width: 8)[5..3]
                                                                                    ) |
                                                                                    (
                                                                                        lit(2, width: 3, base: "h", signed: false) ==
                                                                                        sig(:rd_sib, width: 8)[2..0]
                                                                                    )
                                                                                ) &
                                                                                sig(:rd_mutex_busy_edx, width: 1)
                                                                            ) |
                                                                            (
                                                                                (
                                                                                    (
                                                                                        (
                                                                                            lit(3, width: 3, base: "h", signed: false) ==
                                                                                            sig(:rd_sib, width: 8)[5..3]
                                                                                        ) |
                                                                                        (
                                                                                            lit(3, width: 3, base: "h", signed: false) ==
                                                                                            sig(:rd_sib, width: 8)[2..0]
                                                                                        )
                                                                                    ) &
                                                                                    sig(:rd_mutex_current, width: 11)[3]
                                                                                ) |
                                                                                (
                                                                                    (
                                                                                        (
                                                                                            lit(4, width: 3, base: "h", signed: false) ==
                                                                                            sig(:rd_sib, width: 8)[2..0]
                                                                                        ) &
                                                                                        sig(:rd_mutex_busy_esp, width: 1)
                                                                                    ) |
                                                                                    (
                                                                                        (
                                                                                            (
                                                                                                (
                                                                                                    lit(5, width: 3, base: "h", signed: false) ==
                                                                                                    sig(:rd_sib, width: 8)[5..3]
                                                                                                ) |
                                                                                                (
                                                                                                    (
                                                                                                        lit(5, width: 3, base: "h", signed: false) ==
                                                                                                        sig(:rd_sib, width: 8)[2..0]
                                                                                                    ) &
                                                                                                    (
                                                                                                        lit(0, width: 2, base: "h", signed: false) !=
                                                                                                        sig(:rd_modregrm_mod, width: 2)
                                                                                                    )
                                                                                                )
                                                                                            ) &
                                                                                            sig(:rd_mutex_busy_ebp, width: 1)
                                                                                        ) |
                                                                                        (
                                                                                            (
                                                                                                (
                                                                                                    (
                                                                                                        lit(6, width: 3, base: "h", signed: false) ==
                                                                                                        sig(:rd_sib, width: 8)[5..3]
                                                                                                    ) |
                                                                                                    (
                                                                                                        lit(6, width: 3, base: "h", signed: false) ==
                                                                                                        sig(:rd_sib, width: 8)[2..0]
                                                                                                    )
                                                                                                ) &
                                                                                                sig(:rd_mutex_current, width: 11)[6]
                                                                                            ) |
                                                                                            (
                                                                                                (
                                                                                                    (
                                                                                                        lit(7, width: 3, base: "h", signed: false) ==
                                                                                                        sig(:rd_sib, width: 8)[5..3]
                                                                                                    ) |
                                                                                                    (
                                                                                                        lit(7, width: 3, base: "h", signed: false) ==
                                                                                                        sig(:rd_sib, width: 8)[2..0]
                                                                                                    )
                                                                                                ) &
                                                                                                sig(:rd_mutex_current, width: 11)[7]
                                                                                            )
                                                                                        )
                                                                                    )
                                                                                )
                                                                            )
                                                                        )
                                                                    )
                                                                )
                                                            ) |
                                                            (
                                                                sig(:__VdfgRegularize_h5d6336af_0_25, width: 1) |
                                                                sig(:__VdfgRegularize_h5d6336af_0_30, width: 1)
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
  assign :__VdfgRegularize_h5d6336af_0_27,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:rd_modregrm_mod, width: 2)
    )

  # Processes

  process :initial_block_0,
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
