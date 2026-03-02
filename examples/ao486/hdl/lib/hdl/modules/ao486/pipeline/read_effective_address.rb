# frozen_string_literal: true

class ReadEffectiveAddress < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read_effective_address

  def self._import_decl_kinds
    {
      __VdfgRegularize_h55c2305b_0_0: :logic,
      __VdfgRegularize_h55c2305b_0_1: :logic,
      __VdfgRegularize_h55c2305b_0_10: :logic,
      __VdfgRegularize_h55c2305b_0_11: :logic,
      __VdfgRegularize_h55c2305b_0_12: :logic,
      __VdfgRegularize_h55c2305b_0_13: :logic,
      __VdfgRegularize_h55c2305b_0_14: :logic,
      __VdfgRegularize_h55c2305b_0_15: :logic,
      __VdfgRegularize_h55c2305b_0_2: :logic,
      __VdfgRegularize_h55c2305b_0_3: :logic,
      __VdfgRegularize_h55c2305b_0_4: :logic,
      __VdfgRegularize_h55c2305b_0_5: :logic,
      __VdfgRegularize_h55c2305b_0_6: :logic,
      __VdfgRegularize_h55c2305b_0_7: :logic,
      __VdfgRegularize_h55c2305b_0_8: :logic,
      __VdfgRegularize_h55c2305b_0_9: :logic,
      _unused_ok: :wire,
      address_bits_transform_reg: :wire,
      address_bits_transform_sum: :wire,
      address_disp16: :wire,
      address_disp32: :wire,
      address_disp32_no_sib: :wire,
      address_disp32_sib: :wire,
      address_effective_modrm: :wire,
      call_gate_param: :wire,
      ea_buffer: :reg,
      ea_buffer_next: :wire,
      ea_buffer_sum: :wire,
      ebp_for_enter: :reg,
      ebp_for_enter_next: :wire,
      ebp_for_enter_offset: :wire,
      ebp_for_leave_offset: :wire,
      edi_offset: :wire,
      esi_offset: :wire,
      esp_for_enter_next: :wire,
      esp_for_enter_offset: :wire,
      pop_next: :wire,
      pop_offset: :wire,
      pop_offset_speedup: :reg,
      pop_offset_speedup_next: :wire,
      sib_index32: :wire,
      stack: :wire,
      stack_for_iret_to_v86: :wire,
      stack_initial: :wire,
      stack_next: :wire,
      stack_offset: :wire,
      stack_saved: :reg,
      xlat_offset: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :rd_reset
  input :rd_address_effective_do
  input :rd_ready
  input :eax, width: 32
  input :ebx, width: 32
  input :ecx, width: 32
  input :edx, width: 32
  input :esp, width: 32
  input :ebp, width: 32
  input :esi, width: 32
  input :edi, width: 32
  input :ss_cache, width: 64
  input :glob_param_3, width: 32
  input :wr_esp_prev, width: 32
  input :rd_address_16bit
  input :rd_address_32bit
  input :rd_operand_16bit
  input :rd_operand_32bit
  input :rd_decoder, width: 88
  input :rd_modregrm_rm, width: 3
  input :rd_modregrm_reg, width: 3
  input :rd_modregrm_mod, width: 2
  input :rd_sib, width: 8
  input :address_enter_init
  input :address_enter
  input :address_enter_last
  input :address_leave
  input :address_esi
  input :address_edi
  input :address_xlat_transform
  input :address_bits_transform
  input :address_stack_pop
  input :address_stack_pop_speedup
  input :address_stack_pop_next
  input :address_stack_pop_esp_prev
  input :address_stack_pop_for_call
  input :address_stack_save
  input :address_stack_add_4_to_saved
  input :address_stack_for_ret_first
  input :address_stack_for_ret_second
  input :address_stack_for_iret_first
  input :address_stack_for_iret_second
  input :address_stack_for_iret_third
  input :address_stack_for_iret_last
  input :address_stack_for_iret_to_v86
  input :address_stack_for_call_param_first
  input :address_ea_buffer
  input :address_ea_buffer_plus_2
  input :address_memoffset
  output :rd_address_effective_ready
  output :rd_address_effective, width: 32

  # Signals

  signal :__VdfgRegularize_h55c2305b_0_0
  signal :__VdfgRegularize_h55c2305b_0_1
  signal :__VdfgRegularize_h55c2305b_0_10
  signal :__VdfgRegularize_h55c2305b_0_11, width: 32
  signal :__VdfgRegularize_h55c2305b_0_12, width: 32
  signal :__VdfgRegularize_h55c2305b_0_13, width: 32
  signal :__VdfgRegularize_h55c2305b_0_14, width: 32
  signal :__VdfgRegularize_h55c2305b_0_15, width: 32
  signal :__VdfgRegularize_h55c2305b_0_2
  signal :__VdfgRegularize_h55c2305b_0_3
  signal :__VdfgRegularize_h55c2305b_0_4
  signal :__VdfgRegularize_h55c2305b_0_5
  signal :__VdfgRegularize_h55c2305b_0_6
  signal :__VdfgRegularize_h55c2305b_0_7
  signal :__VdfgRegularize_h55c2305b_0_8
  signal :__VdfgRegularize_h55c2305b_0_9
  signal :_unused_ok
  signal :address_bits_transform_reg, width: 32
  signal :address_bits_transform_sum, width: 32
  signal :address_disp16, width: 16
  signal :address_disp32, width: 32
  signal :address_disp32_no_sib, width: 32
  signal :address_disp32_sib, width: 32
  signal :address_effective_modrm, width: 32
  signal :call_gate_param, width: 5
  signal :ea_buffer, width: 32
  signal :ea_buffer_next, width: 32
  signal :ea_buffer_sum, width: 32
  signal :ebp_for_enter, width: 32
  signal :ebp_for_enter_next, width: 32
  signal :ebp_for_enter_offset, width: 32
  signal :ebp_for_leave_offset, width: 32
  signal :edi_offset, width: 32
  signal :esi_offset, width: 32
  signal :esp_for_enter_next, width: 32
  signal :esp_for_enter_offset, width: 32
  signal :pop_next, width: 32
  signal :pop_offset, width: 32
  signal :pop_offset_speedup, width: 32
  signal :pop_offset_speedup_next, width: 32
  signal :sib_index32, width: 32
  signal :stack, width: 32
  signal :stack_for_iret_to_v86, width: 32
  signal :stack_initial, width: 32
  signal :stack_next, width: 32
  signal :stack_offset, width: 32
  signal :stack_saved, width: 32
  signal :xlat_offset, width: 32

  # Assignments

  assign :address_disp16,
    sig(:rd_decoder, width: 88)[31..16]
  assign :address_disp32_no_sib,
    sig(:rd_decoder, width: 88)[47..16]
  assign :address_disp32_sib,
    sig(:rd_decoder, width: 88)[55..24]
  assign :address_disp32,
    mux(
      sig(:__VdfgRegularize_h55c2305b_0_4, width: 1),
      sig(:address_disp32_sib, width: 32),
      sig(:address_disp32_no_sib, width: 32)
    )
  assign :__VdfgRegularize_h55c2305b_0_4,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :sib_index32,
    case_select(
      sig(:rd_sib, width: 8)[5..3],
      cases: {
        0 => sig(:eax, width: 32),
        1 => sig(:ecx, width: 32),
        2 => sig(:edx, width: 32),
        3 => sig(:ebx, width: 32),
        4 => lit(0, width: 32, base: "h", signed: false),
        5 => sig(:ebp, width: 32),
        6 => sig(:esi, width: 32)
      },
      default: sig(:edi, width: 32)
    )
  assign :address_effective_modrm,
    mux(
      (
          sig(:rd_address_16bit, width: 1) &
          (
              sig(:__VdfgRegularize_h55c2305b_0_10, width: 1) &
              sig(:__VdfgRegularize_h55c2305b_0_6, width: 1)
          )
      ),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:address_disp16, width: 16)
      ),
      mux(
        (
            sig(:rd_address_32bit, width: 1) &
            (
                sig(:__VdfgRegularize_h55c2305b_0_10, width: 1) &
                sig(:__VdfgRegularize_h55c2305b_0_5, width: 1)
            )
        ),
        sig(:address_disp32_no_sib, width: 32),
        mux(
          sig(:rd_address_16bit, width: 1),
          lit(0, width: 16, base: "d", signed: false).concat(
            (
                (
                    (
                        mux(
                          sig(:__VdfgRegularize_h55c2305b_0_0, width: 1),
                          (
                              sig(:ebx, width: 32)[15..0] +
                              sig(:esi, width: 32)[15..0]
                          ),
                          mux(
                            sig(:__VdfgRegularize_h55c2305b_0_1, width: 1),
                            (
                                sig(:ebx, width: 32)[15..0] +
                                sig(:edi, width: 32)[15..0]
                            ),
                            mux(
                              sig(:__VdfgRegularize_h55c2305b_0_2, width: 1),
                              (
                                  sig(:ebp, width: 32)[15..0] +
                                  sig(:esi, width: 32)[15..0]
                              ),
                              mux(
                                sig(:__VdfgRegularize_h55c2305b_0_3, width: 1),
                                (
                                    sig(:ebp, width: 32)[15..0] +
                                    sig(:edi, width: 32)[15..0]
                                ),
                                mux(
                                  sig(:__VdfgRegularize_h55c2305b_0_4, width: 1),
                                  sig(:esi, width: 32)[15..0],
                                  mux(
                                    sig(:__VdfgRegularize_h55c2305b_0_5, width: 1),
                                    sig(:edi, width: 32)[15..0],
                                    mux(
                                      sig(:__VdfgRegularize_h55c2305b_0_6, width: 1),
                                      sig(:ebp, width: 32)[15..0],
                                      sig(:ebx, width: 32)[15..0]
                                    )
                                  )
                                )
                              )
                            )
                          )
                        ) +
                        mux(
                          sig(:__VdfgRegularize_h55c2305b_0_7, width: 1),
                          sig(:address_disp16, width: 16),
                          mux(
                            sig(:__VdfgRegularize_h55c2305b_0_8, width: 1),
                            sig(:rd_decoder, width: 88)[23].replicate(
                              lit(8, width: 32, base: "h", signed: true)
                            ).concat(
                              sig(:rd_decoder, width: 88)[23..16]
                            ),
                            lit(0, width: 16, base: "h", signed: false)
                          )
                        )
                    ) >>
                    lit(0, width: nil, base: "d", signed: false)
                ) &
                (
                    (
                        lit(1, width: 32, base: "d") <<
                        (
                              (
                                lit(15, width: nil, base: "d", signed: false)
                              ) -
                              (
                                lit(0, width: nil, base: "d", signed: false)
                              ) +
                            lit(1, width: 32, base: "d")
                        )
                    ) -
                    lit(1, width: 32, base: "d")
                )
            )
          ),
          (
              mux(
                sig(:__VdfgRegularize_h55c2305b_0_0, width: 1),
                sig(:eax, width: 32),
                mux(
                  sig(:__VdfgRegularize_h55c2305b_0_1, width: 1),
                  sig(:ecx, width: 32),
                  mux(
                    sig(:__VdfgRegularize_h55c2305b_0_2, width: 1),
                    sig(:edx, width: 32),
                    mux(
                      sig(:__VdfgRegularize_h55c2305b_0_3, width: 1),
                      sig(:ebx, width: 32),
                      mux(
                        sig(:__VdfgRegularize_h55c2305b_0_4, width: 1),
                        (
                            mux(
                              (
                                  lit(0, width: 3, base: "h", signed: false) ==
                                  sig(:rd_sib, width: 8)[2..0]
                              ),
                              sig(:eax, width: 32),
                              mux(
                                (
                                    lit(1, width: 3, base: "h", signed: false) ==
                                    sig(:rd_sib, width: 8)[2..0]
                                ),
                                sig(:ecx, width: 32),
                                mux(
                                  (
                                      lit(2, width: 3, base: "h", signed: false) ==
                                      sig(:rd_sib, width: 8)[2..0]
                                  ),
                                  sig(:edx, width: 32),
                                  mux(
                                    (
                                        lit(3, width: 3, base: "h", signed: false) ==
                                        sig(:rd_sib, width: 8)[2..0]
                                    ),
                                    sig(:ebx, width: 32),
                                    mux(
                                      (
                                          lit(4, width: 3, base: "h", signed: false) ==
                                          sig(:rd_sib, width: 8)[2..0]
                                      ),
                                      sig(:esp, width: 32),
                                      mux(
                                        (
                                            sig(:__VdfgRegularize_h55c2305b_0_9, width: 1) &
                                            sig(:__VdfgRegularize_h55c2305b_0_10, width: 1)
                                        ),
                                        sig(:address_disp32_sib, width: 32),
                                        mux(
                                          sig(:__VdfgRegularize_h55c2305b_0_9, width: 1),
                                          sig(:ebp, width: 32),
                                          mux(
                                            (
                                                lit(6, width: 3, base: "h", signed: false) ==
                                                sig(:rd_sib, width: 8)[2..0]
                                            ),
                                            sig(:esi, width: 32),
                                            sig(:edi, width: 32)
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            ) +
                            case_select(
                              sig(:rd_sib, width: 8)[7..6],
                              cases: {
                                0 => sig(:sib_index32, width: 32),
                                1 => (sig(:sib_index32, width: 32) << lit(1, width: 32, base: "h", signed: false)),
                                2 => (sig(:sib_index32, width: 32) << lit(2, width: 32, base: "h", signed: false))
                              },
                              default: (sig(:sib_index32, width: 32) << lit(3, width: 32, base: "h", signed: false))
                            )
                        ),
                        mux(
                          sig(:__VdfgRegularize_h55c2305b_0_5, width: 1),
                          sig(:ebp, width: 32),
                          mux(
                            sig(:__VdfgRegularize_h55c2305b_0_6, width: 1),
                            sig(:esi, width: 32),
                            sig(:edi, width: 32)
                          )
                        )
                      )
                    )
                  )
                )
              ) +
              mux(
                sig(:__VdfgRegularize_h55c2305b_0_7, width: 1),
                sig(:address_disp32, width: 32),
                mux(
                  sig(:__VdfgRegularize_h55c2305b_0_8, width: 1),
                  sig(:address_disp32, width: 32)[7].replicate(
                    lit(24, width: 32, base: "h", signed: true)
                  ).concat(
                    sig(:address_disp32, width: 32)[7..0]
                  ),
                  lit(0, width: 32, base: "h", signed: false)
                )
              )
          )
        )
      )
    )
  assign :__VdfgRegularize_h55c2305b_0_10,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:rd_modregrm_mod, width: 2)
    )
  assign :__VdfgRegularize_h55c2305b_0_6,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_5,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_0,
    (
        lit(0, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_1,
    (
        lit(1, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_2,
    (
        lit(2, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_3,
    (
        lit(3, width: 3, base: "h", signed: false) ==
        sig(:rd_modregrm_rm, width: 3)
    )
  assign :__VdfgRegularize_h55c2305b_0_7,
    (
        lit(2, width: 2, base: "h", signed: false) ==
        sig(:rd_modregrm_mod, width: 2)
    )
  assign :__VdfgRegularize_h55c2305b_0_8,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:rd_modregrm_mod, width: 2)
    )
  assign :__VdfgRegularize_h55c2305b_0_9,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:rd_sib, width: 8)[2..0]
    )
  assign :esi_offset,
    mux(
      sig(:rd_address_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:esi, width: 32)[15..0]
      ),
      sig(:esi, width: 32)
    )
  assign :edi_offset,
    mux(
      sig(:rd_address_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:edi, width: 32)[15..0]
      ),
      sig(:edi, width: 32)
    )
  assign :pop_next,
    mux(
      (
          sig(:address_stack_pop_speedup, width: 1) &
          sig(:rd_operand_16bit, width: 1)
      ),
      (
          lit(2, width: 32, base: "h", signed: false) +
          sig(:pop_offset_speedup, width: 32)
      ),
      mux(
        sig(:address_stack_pop_speedup, width: 1),
        (
            lit(4, width: 32, base: "h", signed: false) +
            sig(:pop_offset_speedup, width: 32)
        ),
        mux(
          sig(:rd_operand_16bit, width: 1),
          (
              lit(2, width: 32, base: "h", signed: false) +
              sig(:esp, width: 32)
          ),
          (
              lit(4, width: 32, base: "h", signed: false) +
              sig(:esp, width: 32)
          )
        )
      )
    )
  assign :pop_offset_speedup_next,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:pop_next, width: 32),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:pop_next, width: 32)[15..0]
      )
    )
  assign :pop_offset,
    mux(
      sig(:address_stack_pop_speedup, width: 1),
      sig(:pop_offset_speedup, width: 32),
      mux(
        sig(:ss_cache, width: 64)[54],
        sig(:esp, width: 32),
        lit(0, width: 16, base: "d", signed: false).concat(
          sig(:esp, width: 32)[15..0]
        )
      )
    )
  assign :stack_initial,
    mux(
      sig(:address_stack_pop_esp_prev, width: 1),
      sig(:wr_esp_prev, width: 32),
      sig(:esp, width: 32)
    )
  assign :stack,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:stack_initial, width: 32),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:stack_initial, width: 32)[15..0]
      )
    )
  assign :stack_for_iret_to_v86,
    (
        lit(12, width: 32, base: "h", signed: false) +
        sig(:stack, width: 32)
    )
  assign :call_gate_param,
    (
        sig(:glob_param_3, width: 32)[24..20] -
        lit(1, width: 5, base: "h", signed: false)
    )
  assign :stack_next,
    mux(
      (
          (
            ~sig(:glob_param_3, width: 32)[19]
          ) &
          sig(:address_stack_pop_for_call, width: 1)
      ),
      sig(:__VdfgRegularize_h55c2305b_0_14, width: 32),
      mux(
        sig(:address_stack_pop_for_call, width: 1),
        sig(:__VdfgRegularize_h55c2305b_0_15, width: 32),
        mux(
          sig(:rd_operand_16bit, width: 1),
          sig(:__VdfgRegularize_h55c2305b_0_14, width: 32),
          sig(:__VdfgRegularize_h55c2305b_0_15, width: 32)
        )
      )
    )
  assign :__VdfgRegularize_h55c2305b_0_14,
    (
        sig(:stack_saved, width: 32) -
        lit(2, width: 32, base: "h", signed: false)
    )
  assign :__VdfgRegularize_h55c2305b_0_15,
    (
        sig(:stack_saved, width: 32) -
        lit(4, width: 32, base: "h", signed: false)
    )
  assign :stack_offset,
    mux(
      sig(:address_stack_for_ret_first, width: 1),
      mux(
        sig(:rd_operand_16bit, width: 1),
        (
            lit(2, width: 32, base: "h", signed: false) +
            sig(:stack, width: 32)
        ),
        sig(:__VdfgRegularize_h55c2305b_0_11, width: 32)
      ),
      mux(
        sig(:address_stack_for_ret_second, width: 1),
        mux(
          sig(:rd_operand_16bit, width: 1),
          (
              lit(6, width: 32, base: "h", signed: false) +
              sig(:__VdfgRegularize_h55c2305b_0_12, width: 32)
          ),
          (
              lit(12, width: 32, base: "h", signed: false) +
              sig(:__VdfgRegularize_h55c2305b_0_12, width: 32)
          )
        ),
        mux(
          sig(:address_stack_for_iret_first, width: 1),
          mux(
            sig(:rd_operand_16bit, width: 1),
            sig(:__VdfgRegularize_h55c2305b_0_11, width: 32),
            sig(:__VdfgRegularize_h55c2305b_0_13, width: 32)
          ),
          mux(
            sig(:address_stack_for_iret_second, width: 1),
            mux(
              sig(:rd_operand_16bit, width: 1),
              sig(:__VdfgRegularize_h55c2305b_0_13, width: 32),
              (
                  lit(16, width: 32, base: "h", signed: false) +
                  sig(:stack, width: 32)
              )
            ),
            mux(
              sig(:address_stack_for_iret_third, width: 1),
              mux(
                sig(:rd_operand_16bit, width: 1),
                (
                    lit(6, width: 32, base: "h", signed: false) +
                    sig(:stack, width: 32)
                ),
                sig(:stack_for_iret_to_v86, width: 32)
              ),
              mux(
                sig(:address_stack_for_iret_last, width: 1),
                sig(:stack, width: 32),
                mux(
                  sig(:address_stack_for_iret_to_v86, width: 1),
                  sig(:stack_for_iret_to_v86, width: 32),
                  mux(
                    sig(:address_stack_for_call_param_first, width: 1),
                    mux(
                      sig(:glob_param_3, width: 32)[19],
                      (
                          sig(:stack, width: 32) +
                          lit(0, width: 25, base: "d", signed: false).concat(
                          sig(:call_gate_param, width: 5).concat(
                            lit(0, width: 2, base: "h", signed: false)
                          )
                        )
                      ),
                      (
                          sig(:stack, width: 32) +
                          lit(0, width: 26, base: "d", signed: false).concat(
                          sig(:call_gate_param, width: 5).concat(
                            lit(0, width: 1, base: "h", signed: false)
                          )
                        )
                      )
                    ),
                    sig(:stack_saved, width: 32)
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h55c2305b_0_11,
    (
        lit(4, width: 32, base: "h", signed: false) +
        sig(:stack, width: 32)
    )
  assign :__VdfgRegularize_h55c2305b_0_12,
    (
        sig(:stack, width: 32) +
        mux(
          sig(:rd_decoder, width: 88)[0],
          lit(0, width: 32, base: "h", signed: false),
          lit(0, width: 16, base: "d", signed: false).concat(
            sig(:rd_decoder, width: 88)[23..8]
          )
        )
    )
  assign :__VdfgRegularize_h55c2305b_0_13,
    (
        lit(8, width: 32, base: "h", signed: false) +
        sig(:stack, width: 32)
    )
  assign :xlat_offset,
    (
        sig(:ebx, width: 32) +
        lit(0, width: 24, base: "d", signed: false).concat(
        sig(:eax, width: 32)[7..0]
      )
    )
  assign :ebp_for_leave_offset,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:ebp, width: 32),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:ebp, width: 32)[15..0]
      )
    )
  assign :address_bits_transform_reg,
    case_select(
      sig(:rd_modregrm_reg, width: 3),
      cases: {
        0 => sig(:eax, width: 32),
        1 => sig(:ecx, width: 32),
        2 => sig(:edx, width: 32),
        3 => sig(:ebx, width: 32),
        4 => sig(:esp, width: 32),
        5 => sig(:ebp, width: 32),
        6 => sig(:esi, width: 32)
      },
      default: sig(:edi, width: 32)
    )
  assign :address_bits_transform_sum,
    mux(
      sig(:rd_operand_32bit, width: 1),
      (
          sig(:address_effective_modrm, width: 32) +
          sig(:address_bits_transform_reg, width: 32)[31].replicate(
          lit(3, width: 32, base: "h", signed: true)
        ).concat(
          sig(:address_bits_transform_reg, width: 32)[31..5].concat(
            lit(0, width: 2, base: "h", signed: false)
          )
        )
      ),
      (
          sig(:address_effective_modrm, width: 32) +
          sig(:address_bits_transform_reg, width: 32)[15].replicate(
          lit(19, width: 32, base: "h", signed: true)
        ).concat(
          sig(:address_bits_transform_reg, width: 32)[15..4].concat(
            lit(0, width: 1, base: "h", signed: false)
          )
        )
      )
    )
  assign :ebp_for_enter_next,
    mux(
      sig(:rd_operand_16bit, width: 1),
      (
          sig(:ebp_for_enter, width: 32) -
          lit(2, width: 32, base: "h", signed: false)
      ),
      (
          sig(:ebp_for_enter, width: 32) -
          lit(4, width: 32, base: "h", signed: false)
      )
    )
  assign :ebp_for_enter_offset,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:ebp_for_enter_next, width: 32),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:ebp_for_enter_next, width: 32)[15..0]
      )
    )
  assign :esp_for_enter_next,
    (
        sig(:esp, width: 32) -
        lit(0, width: 16, base: "d", signed: false).concat(
        sig(:rd_decoder, width: 88)[23..8]
      )
    )
  assign :esp_for_enter_offset,
    mux(
      sig(:ss_cache, width: 64)[54],
      sig(:esp_for_enter_next, width: 32),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:esp_for_enter_next, width: 32)[15..0]
      )
    )
  assign :ea_buffer_sum,
    mux(
      (
          sig(:address_ea_buffer_plus_2, width: 1) |
          sig(:rd_operand_16bit, width: 1)
      ),
      (
          lit(2, width: 32, base: "h", signed: false) +
          sig(:rd_address_effective, width: 32)
      ),
      (
          lit(4, width: 32, base: "h", signed: false) +
          sig(:rd_address_effective, width: 32)
      )
    )
  assign :ea_buffer_next,
    mux(
      sig(:rd_address_16bit, width: 1),
      lit(0, width: 16, base: "d", signed: false).concat(
        sig(:ea_buffer_sum, width: 32)[15..0]
      ),
      sig(:ea_buffer_sum, width: 32)
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
          :pop_offset_speedup,
          sig(:pop_offset_speedup_next, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :pop_offset_speedup,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt((sig(:rd_ready, width: 1) & sig(:address_stack_add_4_to_saved, width: 1))) do
        assign(
          :stack_saved,
          (
              lit(4, width: 32, base: "h", signed: false) +
              sig(:stack_saved, width: 32)
          ),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_ready, width: 1)) do
            assign(
              :stack_saved,
              sig(:stack_next, width: 32),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:address_stack_save, width: 1)) do
                assign(
                  :stack_saved,
                  sig(:stack_offset, width: 32),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :stack_saved,
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
      if_stmt(sig(:address_enter_init, width: 1)) do
        assign(
          :ebp_for_enter,
          sig(:ebp, width: 32),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_ready, width: 1)) do
            assign(
              :ebp_for_enter,
              sig(:ebp_for_enter_offset, width: 32),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :ebp_for_enter,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt((sig(:rd_ready, width: 1) & sig(:rd_address_effective_ready, width: 1))) do
        assign(
          :ea_buffer,
          sig(:ea_buffer_next, width: 32),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :ea_buffer,
          lit(0, width: 32, base: "h", signed: false),
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
      if_stmt((sig(:rd_ready, width: 1) | sig(:rd_reset, width: 1))) do
        assign(
          :rd_address_effective_ready,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_address_effective_do, width: 1)) do
            assign(
              :rd_address_effective_ready,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_address_effective_ready,
          lit(0, width: 1, base: "h", signed: false),
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
    assign(
      :rd_address_effective,
      mux(
        sig(:rst_n, width: 1),
        mux(
          (
              sig(:address_memoffset, width: 1) &
              sig(:rd_address_16bit, width: 1)
          ),
          lit(0, width: 16, base: "d", signed: false).concat(
            sig(:rd_decoder, width: 88)[23..8]
          ),
          mux(
            (
                sig(:address_memoffset, width: 1) &
                sig(:rd_address_32bit, width: 1)
            ),
            sig(:rd_decoder, width: 88)[39..8],
            mux(
              sig(:address_ea_buffer, width: 1),
              sig(:ea_buffer, width: 32),
              mux(
                sig(:address_enter, width: 1),
                sig(:ebp_for_enter_offset, width: 32),
                mux(
                  sig(:address_enter_last, width: 1),
                  sig(:esp_for_enter_offset, width: 32),
                  mux(
                    sig(:address_leave, width: 1),
                    sig(:ebp_for_leave_offset, width: 32),
                    mux(
                      sig(:address_esi, width: 1),
                      sig(:esi_offset, width: 32),
                      mux(
                        sig(:address_edi, width: 1),
                        sig(:edi_offset, width: 32),
                        mux(
                          sig(:address_stack_pop, width: 1),
                          sig(:pop_offset, width: 32),
                          mux(
                            sig(:address_stack_pop_next, width: 1),
                            sig(:stack_offset, width: 32),
                            mux(
                              sig(:address_xlat_transform, width: 1),
                              (
                                  sig(:rd_address_32bit, width: 1).replicate(
                                    lit(16, width: 32, base: "h", signed: true)
                                  ) &
                                  sig(:xlat_offset, width: 32)[31..16]
                              ).concat(
                                sig(:xlat_offset, width: 32)[15..0]
                              ),
                              mux(
                                sig(:address_bits_transform, width: 1),
                                (
                                    sig(:rd_address_32bit, width: 1).replicate(
                                      lit(16, width: 32, base: "h", signed: true)
                                    ) &
                                    sig(:address_bits_transform_sum, width: 32)[31..16]
                                ).concat(
                                  sig(:address_bits_transform_sum, width: 32)[15..0]
                                ),
                                sig(:address_effective_modrm, width: 32)
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
        lit(0, width: 32, base: "h", signed: false)
      ),
      kind: :nonblocking
    )
  end

  process :initial_block_6,
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
