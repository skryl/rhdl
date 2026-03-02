# frozen_string_literal: true

class ExecuteShift < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute_shift

  def self._import_decl_kinds
    {
      __VdfgExtracted_h60a405ed__0: :logic,
      __VdfgExtracted_h60a4062e__0: :logic,
      __VdfgExtracted_h60a406f0__0: :logic,
      __VdfgExtracted_h60a40703__0: :logic,
      __VdfgExtracted_h60a407ac__0: :logic,
      __VdfgExtracted_h60a4086f__0: :logic,
      __VdfgExtracted_h60a40881__0: :logic,
      __VdfgExtracted_h60a40942__0: :logic,
      __VdfgExtracted_h60a40abc__0: :logic,
      __VdfgExtracted_h60a40aff__0: :logic,
      __VdfgExtracted_h60a40c18__0: :logic,
      __VdfgExtracted_h60a40c7d__0: :logic,
      __VdfgExtracted_h60a40d3e__0: :logic,
      __VdfgExtracted_h60a40fdc__0: :logic,
      __VdfgExtracted_h60a4109f__0: :logic,
      __VdfgExtracted_h60a410f1__0: :logic,
      __VdfgExtracted_h60a4111d__0: :logic,
      __VdfgExtracted_h60a4115e__0: :logic,
      __VdfgExtracted_h60a411b2__0: :logic,
      __VdfgExtracted_h60a411da__0: :logic,
      __VdfgExtracted_h60a41220__0: :logic,
      __VdfgExtracted_h60a41273__0: :logic,
      __VdfgExtracted_h60a41299__0: :logic,
      __VdfgExtracted_h60a4131b__0: :logic,
      __VdfgExtracted_h60a41368__0: :logic,
      __VdfgExtracted_h60a66432__0: :logic,
      __VdfgExtracted_h60a664dc__0: :logic,
      __VdfgExtracted_h60a6651f__0: :logic,
      __VdfgExtracted_h60a66573__0: :logic,
      __VdfgExtracted_h60a6659d__0: :logic,
      __VdfgExtracted_h60a6665e__0: :logic,
      __VdfgExtracted_h93938a0e__0: :logic,
      __VdfgExtracted_h93938a56__0: :logic,
      __VdfgExtracted_h93938a90__0: :logic,
      __VdfgExtracted_h93938acf__0: :logic,
      __VdfgExtracted_h93938b53__0: :logic,
      __VdfgExtracted_h93938b59__0: :logic,
      __VdfgExtracted_h93938b97__0: :logic,
      __VdfgExtracted_h93938d51__0: :logic,
      __VdfgExtracted_h939391f2__0: :logic,
      __VdfgExtracted_h93939474__0: :logic,
      __VdfgExtracted_h9393947e__0: :logic,
      __VdfgExtracted_h93939533__0: :logic,
      __VdfgExtracted_h939395b5__0: :logic,
      __VdfgExtracted_h9393973f__0: :logic,
      __VdfgExtracted_h939397d8__0: :logic,
      __VdfgExtracted_h93939814__0: :logic,
      __VdfgExtracted_h93939892__0: :logic,
      __VdfgExtracted_h939398d5__0: :logic,
      __VdfgExtracted_h93939de6__0: :logic,
      __VdfgExtracted_h93939e22__0: :logic,
      __VdfgExtracted_h93939ea4__0: :logic,
      __VdfgExtracted_h93939ee3__0: :logic,
      __VdfgExtracted_h9393a068__0: :logic,
      __VdfgExtracted_h9393a127__0: :logic,
      __VdfgExtracted_h9393a165__0: :logic,
      __VdfgExtracted_h9393a1a9__0: :logic,
      __VdfgExtracted_h93953bd3__0: :logic,
      __VdfgExtracted_h93953c59__0: :logic,
      __VdfgExtracted_h93953f14__0: :logic,
      __VdfgExtracted_h93953f55__0: :logic,
      __VdfgExtracted_h93953f92__0: :logic,
      __VdfgRegularize_h435de875_0_0: :logic,
      __VdfgRegularize_h435de875_0_1: :logic,
      __VdfgRegularize_h435de875_0_10: :logic,
      __VdfgRegularize_h435de875_0_11: :logic,
      __VdfgRegularize_h435de875_0_12: :logic,
      __VdfgRegularize_h435de875_0_13: :logic,
      __VdfgRegularize_h435de875_0_14: :logic,
      __VdfgRegularize_h435de875_0_15: :logic,
      __VdfgRegularize_h435de875_0_16: :logic,
      __VdfgRegularize_h435de875_0_17: :logic,
      __VdfgRegularize_h435de875_0_18: :logic,
      __VdfgRegularize_h435de875_0_19: :logic,
      __VdfgRegularize_h435de875_0_2: :logic,
      __VdfgRegularize_h435de875_0_20: :logic,
      __VdfgRegularize_h435de875_0_21: :logic,
      __VdfgRegularize_h435de875_0_22: :logic,
      __VdfgRegularize_h435de875_0_23: :logic,
      __VdfgRegularize_h435de875_0_24: :logic,
      __VdfgRegularize_h435de875_0_25: :logic,
      __VdfgRegularize_h435de875_0_26: :logic,
      __VdfgRegularize_h435de875_0_28: :logic,
      __VdfgRegularize_h435de875_0_29: :logic,
      __VdfgRegularize_h435de875_0_3: :logic,
      __VdfgRegularize_h435de875_0_4: :logic,
      __VdfgRegularize_h435de875_0_5: :logic,
      __VdfgRegularize_h435de875_0_6: :logic,
      __VdfgRegularize_h435de875_0_7: :logic,
      __VdfgRegularize_h435de875_0_8: :logic,
      __VdfgRegularize_h435de875_0_9: :logic,
      _unused_ok: :wire,
      e_shift_RCL: :wire,
      e_shift_RCR: :wire,
      e_shift_ROL: :wire,
      e_shift_ROR: :wire,
      e_shift_SAR: :wire,
      e_shift_SHL: :wire,
      e_shift_SHLD: :wire,
      e_shift_SHR: :wire,
      e_shift_SHRD: :wire,
      e_shift_cf_of_rotate_carry_16bit: :wire,
      e_shift_cf_of_rotate_carry_8bit: :wire,
      e_shift_cmd: :wire,
      e_shift_cmd_carry: :wire,
      e_shift_cmd_rot: :wire,
      e_shift_cmd_shift: :wire,
      e_shift_count: :wire,
      e_shift_dst_wire: :wire,
      e_shift_left_input: :wire,
      e_shift_left_result: :reg,
      e_shift_right_input: :wire,
      e_shift_right_result: :reg
    }
  end

  # Ports

  input :exe_is_8bit
  input :exe_operand_16bit
  input :exe_operand_32bit
  input :exe_prefix_2byte
  input :exe_cmd, width: 7
  input :exe_cmdex, width: 4
  input :exe_decoder, width: 40
  input :exe_modregrm_imm, width: 8
  input :cflag
  input :ecx, width: 32
  input :dst, width: 32
  input :src, width: 32
  output :e_shift_no_write
  output :e_shift_oszapc_update
  output :e_shift_cf_of_update
  output :e_shift_oflag
  output :e_shift_cflag
  output :e_shift_result, width: 32

  # Signals

  signal :__VdfgExtracted_h60a405ed__0, width: 33
  signal :__VdfgExtracted_h60a4062e__0, width: 33
  signal :__VdfgExtracted_h60a406f0__0, width: 33
  signal :__VdfgExtracted_h60a40703__0, width: 33
  signal :__VdfgExtracted_h60a407ac__0, width: 33
  signal :__VdfgExtracted_h60a4086f__0, width: 33
  signal :__VdfgExtracted_h60a40881__0, width: 33
  signal :__VdfgExtracted_h60a40942__0, width: 33
  signal :__VdfgExtracted_h60a40abc__0, width: 33
  signal :__VdfgExtracted_h60a40aff__0, width: 33
  signal :__VdfgExtracted_h60a40c18__0, width: 33
  signal :__VdfgExtracted_h60a40c7d__0, width: 33
  signal :__VdfgExtracted_h60a40d3e__0, width: 33
  signal :__VdfgExtracted_h60a40fdc__0, width: 33
  signal :__VdfgExtracted_h60a4109f__0, width: 33
  signal :__VdfgExtracted_h60a410f1__0, width: 33
  signal :__VdfgExtracted_h60a4111d__0, width: 33
  signal :__VdfgExtracted_h60a4115e__0, width: 33
  signal :__VdfgExtracted_h60a411b2__0, width: 33
  signal :__VdfgExtracted_h60a411da__0, width: 33
  signal :__VdfgExtracted_h60a41220__0, width: 33
  signal :__VdfgExtracted_h60a41273__0, width: 33
  signal :__VdfgExtracted_h60a41299__0, width: 33
  signal :__VdfgExtracted_h60a4131b__0, width: 33
  signal :__VdfgExtracted_h60a41368__0, width: 33
  signal :__VdfgExtracted_h60a66432__0, width: 33
  signal :__VdfgExtracted_h60a664dc__0, width: 33
  signal :__VdfgExtracted_h60a6651f__0, width: 33
  signal :__VdfgExtracted_h60a66573__0, width: 33
  signal :__VdfgExtracted_h60a6659d__0, width: 33
  signal :__VdfgExtracted_h60a6665e__0, width: 33
  signal :__VdfgExtracted_h93938a0e__0, width: 33
  signal :__VdfgExtracted_h93938a56__0, width: 33
  signal :__VdfgExtracted_h93938a90__0, width: 33
  signal :__VdfgExtracted_h93938acf__0, width: 33
  signal :__VdfgExtracted_h93938b53__0, width: 33
  signal :__VdfgExtracted_h93938b59__0, width: 33
  signal :__VdfgExtracted_h93938b97__0, width: 33
  signal :__VdfgExtracted_h93938d51__0, width: 33
  signal :__VdfgExtracted_h939391f2__0, width: 33
  signal :__VdfgExtracted_h93939474__0, width: 33
  signal :__VdfgExtracted_h9393947e__0, width: 33
  signal :__VdfgExtracted_h93939533__0, width: 33
  signal :__VdfgExtracted_h939395b5__0, width: 33
  signal :__VdfgExtracted_h9393973f__0, width: 33
  signal :__VdfgExtracted_h939397d8__0, width: 33
  signal :__VdfgExtracted_h93939814__0, width: 33
  signal :__VdfgExtracted_h93939892__0, width: 33
  signal :__VdfgExtracted_h939398d5__0, width: 33
  signal :__VdfgExtracted_h93939de6__0, width: 33
  signal :__VdfgExtracted_h93939e22__0, width: 33
  signal :__VdfgExtracted_h93939ea4__0, width: 33
  signal :__VdfgExtracted_h93939ee3__0, width: 33
  signal :__VdfgExtracted_h9393a068__0, width: 33
  signal :__VdfgExtracted_h9393a127__0, width: 33
  signal :__VdfgExtracted_h9393a165__0, width: 33
  signal :__VdfgExtracted_h9393a1a9__0, width: 33
  signal :__VdfgExtracted_h93953bd3__0, width: 33
  signal :__VdfgExtracted_h93953c59__0, width: 33
  signal :__VdfgExtracted_h93953f14__0, width: 33
  signal :__VdfgExtracted_h93953f55__0, width: 33
  signal :__VdfgExtracted_h93953f92__0, width: 33
  signal :__VdfgRegularize_h435de875_0_0
  signal :__VdfgRegularize_h435de875_0_1, width: 64
  signal :__VdfgRegularize_h435de875_0_10
  signal :__VdfgRegularize_h435de875_0_11
  signal :__VdfgRegularize_h435de875_0_12
  signal :__VdfgRegularize_h435de875_0_13
  signal :__VdfgRegularize_h435de875_0_14
  signal :__VdfgRegularize_h435de875_0_15
  signal :__VdfgRegularize_h435de875_0_16
  signal :__VdfgRegularize_h435de875_0_17
  signal :__VdfgRegularize_h435de875_0_18
  signal :__VdfgRegularize_h435de875_0_19
  signal :__VdfgRegularize_h435de875_0_2
  signal :__VdfgRegularize_h435de875_0_20
  signal :__VdfgRegularize_h435de875_0_21
  signal :__VdfgRegularize_h435de875_0_22
  signal :__VdfgRegularize_h435de875_0_23
  signal :__VdfgRegularize_h435de875_0_24
  signal :__VdfgRegularize_h435de875_0_25
  signal :__VdfgRegularize_h435de875_0_26
  signal :__VdfgRegularize_h435de875_0_28
  signal :__VdfgRegularize_h435de875_0_29
  signal :__VdfgRegularize_h435de875_0_3
  signal :__VdfgRegularize_h435de875_0_4, width: 64
  signal :__VdfgRegularize_h435de875_0_5
  signal :__VdfgRegularize_h435de875_0_6
  signal :__VdfgRegularize_h435de875_0_7
  signal :__VdfgRegularize_h435de875_0_8
  signal :__VdfgRegularize_h435de875_0_9
  signal :_unused_ok
  signal :e_shift_RCL
  signal :e_shift_RCR
  signal :e_shift_ROL
  signal :e_shift_ROR
  signal :e_shift_SAR
  signal :e_shift_SHL
  signal :e_shift_SHLD
  signal :e_shift_SHR
  signal :e_shift_SHRD
  signal :e_shift_cf_of_rotate_carry_16bit
  signal :e_shift_cf_of_rotate_carry_8bit
  signal :e_shift_cmd, width: 3
  signal :e_shift_cmd_carry
  signal :e_shift_cmd_rot
  signal :e_shift_cmd_shift
  signal :e_shift_count, width: 5
  signal :e_shift_dst_wire, width: 32
  signal :e_shift_left_input, width: 64
  signal :e_shift_left_result, width: 33
  signal :e_shift_right_input, width: 64
  signal :e_shift_right_result, width: 33

  # Assignments

  assign :e_shift_dst_wire,
    mux(
      sig(:exe_is_8bit, width: 1),
      sig(:dst, width: 32)[7..0].concat(
        sig(:dst, width: 32)[7..0].concat(
          sig(:dst, width: 32)[7..0].concat(
            sig(:dst, width: 32)[7..0]
          )
        )
      ),
      mux(
        sig(:exe_operand_16bit, width: 1),
        sig(:dst, width: 32)[15..0].concat(
          sig(:dst, width: 32)[15..0]
        ),
        sig(:dst, width: 32)
      )
    )
  assign :e_shift_count,
    mux(
      (
          sig(:exe_prefix_2byte, width: 1) &
          (
              lit(0, width: 4, base: "h", signed: false) ==
              sig(:exe_cmdex, width: 4)
          )
      ),
      sig(:ecx, width: 32)[4..0],
      mux(
        (
            sig(:exe_prefix_2byte, width: 1) &
            (
                lit(1, width: 4, base: "h", signed: false) ==
                sig(:exe_cmdex, width: 4)
            )
        ),
        sig(:exe_modregrm_imm, width: 8)[4..0],
        sig(:src, width: 32)[4..0]
      )
    )
  assign :e_shift_cmd,
    sig(:exe_decoder, width: 40)[13..11]
  assign :e_shift_ROL,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(0, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :__VdfgRegularize_h435de875_0_0,
    (
      ~sig(:exe_prefix_2byte, width: 1)
    )
  assign :e_shift_ROR,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(1, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :e_shift_RCL,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(2, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :e_shift_RCR,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(3, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :e_shift_SHL,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            (
                lit(4, width: 3, base: "h", signed: false) ==
                sig(:e_shift_cmd, width: 3)
            ) |
            (
                lit(6, width: 3, base: "h", signed: false) ==
                sig(:e_shift_cmd, width: 3)
            )
        )
    )
  assign :e_shift_SHR,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(5, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :e_shift_SAR,
    (
        sig(:__VdfgRegularize_h435de875_0_0, width: 1) &
        (
            lit(7, width: 3, base: "h", signed: false) ==
            sig(:e_shift_cmd, width: 3)
        )
    )
  assign :e_shift_SHLD,
    (
        (
          ~sig(:exe_cmd, width: 7)[0]
        ) &
        sig(:exe_prefix_2byte, width: 1)
    )
  assign :e_shift_SHRD,
    (
        sig(:exe_prefix_2byte, width: 1) &
        sig(:exe_cmd, width: 7)[0]
    )
  assign :e_shift_left_input,
    mux(
      sig(:e_shift_SHL, width: 1),
      sig(:e_shift_dst_wire, width: 32).concat(
        lit(0, width: 32, base: "h", signed: false)
      ),
      mux(
        sig(:e_shift_ROL, width: 1),
        sig(:__VdfgRegularize_h435de875_0_1, width: 64),
        mux(
          sig(:__VdfgRegularize_h435de875_0_2, width: 1),
          sig(:dst, width: 32)[7..0].concat(
            sig(:cflag, width: 1).concat(
              sig(:dst, width: 32)[7..0].concat(
                sig(:cflag, width: 1).concat(
                  sig(:dst, width: 32)[7..2].concat(
                    sig(:dst, width: 32)[7..0]
                  )
                )
              ).concat(
                sig(:cflag, width: 1).concat(
                  sig(:dst, width: 32)[7..0].concat(
                    sig(:cflag, width: 1).concat(
                      sig(:dst, width: 32)[7..0].concat(
                        sig(:cflag, width: 1).concat(
                          sig(:dst, width: 32)[7..0].concat(
                            sig(:cflag, width: 1).concat(
                              sig(:dst, width: 32)[7..4]
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
          mux(
            (
                sig(:e_shift_RCL, width: 1) &
                sig(:exe_operand_16bit, width: 1)
            ),
            sig(:e_shift_dst_wire, width: 32).concat(
              sig(:cflag, width: 1).concat(
                sig(:dst, width: 32)[15..0].concat(
                  sig(:cflag, width: 1).concat(
                    sig(:dst, width: 32)[15..2]
                  )
                )
              )
            ),
            mux(
              (
                  sig(:e_shift_RCL, width: 1) &
                  sig(:exe_operand_32bit, width: 1)
              ),
              sig(:e_shift_dst_wire, width: 32).concat(
                sig(:cflag, width: 1).concat(
                  sig(:dst, width: 32)[31..1]
                )
              ),
              mux(
                sig(:__VdfgRegularize_h435de875_0_3, width: 1),
                sig(:__VdfgRegularize_h435de875_0_4, width: 64),
                sig(:e_shift_dst_wire, width: 32).concat(
                  sig(:src, width: 32)
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h435de875_0_1,
    sig(:e_shift_dst_wire, width: 32).replicate(
      lit(2, width: 32, base: "h", signed: false)
    )
  assign :__VdfgRegularize_h435de875_0_2,
    (
        sig(:e_shift_RCL, width: 1) &
        sig(:exe_is_8bit, width: 1)
    )
  assign :__VdfgRegularize_h435de875_0_3,
    (
        sig(:e_shift_SHLD, width: 1) &
        sig(:exe_operand_16bit, width: 1)
    )
  assign :__VdfgRegularize_h435de875_0_4,
    sig(:e_shift_dst_wire, width: 32).concat(
      sig(:src, width: 32)[15..0].concat(
        sig(:dst, width: 32)[15..0]
      )
    )
  assign :e_shift_right_input,
    mux(
      (
          sig(:e_shift_SAR, width: 1) &
          sig(:exe_is_8bit, width: 1)
      ),
      sig(:dst, width: 32)[7].replicate(
        lit(56, width: 32, base: "h", signed: true)
      ).concat(
        sig(:dst, width: 32)[7..0]
      ),
      mux(
        (
            sig(:e_shift_SAR, width: 1) &
            sig(:exe_operand_16bit, width: 1)
        ),
        sig(:dst, width: 32)[15].replicate(
          lit(48, width: 32, base: "h", signed: true)
        ).concat(
          sig(:dst, width: 32)[15..0]
        ),
        mux(
          (
              sig(:e_shift_SAR, width: 1) &
              sig(:exe_operand_32bit, width: 1)
          ),
          sig(:dst, width: 32)[31].replicate(
            lit(32, width: 32, base: "h", signed: true)
          ).concat(
            sig(:dst, width: 32)
          ),
          mux(
            (
                sig(:e_shift_SHR, width: 1) &
                sig(:exe_is_8bit, width: 1)
            ),
            lit(0, width: 56, base: "d", signed: false).concat(
              sig(:dst, width: 32)[7..0]
            ),
            mux(
              (
                  sig(:e_shift_SHR, width: 1) &
                  sig(:exe_operand_16bit, width: 1)
              ),
              lit(0, width: 48, base: "d", signed: false).concat(
                sig(:dst, width: 32)[15..0]
              ),
              mux(
                (
                    sig(:e_shift_SHR, width: 1) &
                    sig(:exe_operand_32bit, width: 1)
                ),
                lit(0, width: 32, base: "d", signed: false).concat(
                  sig(:dst, width: 32)
                ),
                mux(
                  sig(:e_shift_ROR, width: 1),
                  sig(:__VdfgRegularize_h435de875_0_1, width: 64),
                  mux(
                    (
                        sig(:e_shift_RCR, width: 1) &
                        sig(:exe_is_8bit, width: 1)
                    ),
                    sig(:dst, width: 32)[0].concat(
                      sig(:cflag, width: 1).concat(
                        sig(:dst, width: 32)[7..0].concat(
                          sig(:cflag, width: 1).concat(
                            sig(:dst, width: 32)[7..0].concat(
                              sig(:cflag, width: 1).concat(
                                sig(:dst, width: 32)[7..0].concat(
                                  sig(:cflag, width: 1).concat(
                                    sig(:dst, width: 32)[7..0].concat(
                                      sig(:cflag, width: 1).concat(
                                        sig(:dst, width: 32)[7..0].concat(
                                          sig(:cflag, width: 1).concat(
                                            sig(:dst, width: 32)[7..0].concat(
                                              sig(:cflag, width: 1).concat(
                                                sig(:dst, width: 32)[7..0]
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
                    mux(
                      (
                          sig(:e_shift_RCR, width: 1) &
                          sig(:exe_operand_16bit, width: 1)
                      ),
                      sig(:dst, width: 32)[12..0].concat(
                        sig(:cflag, width: 1).concat(
                          sig(:dst, width: 32)[15..0].concat(
                            sig(:cflag, width: 1).concat(
                              sig(:dst, width: 32)[15..0].concat(
                                sig(:cflag, width: 1).concat(
                                  sig(:dst, width: 32)[15..0]
                                )
                              )
                            )
                          )
                        )
                      ),
                      mux(
                        (
                            sig(:e_shift_RCR, width: 1) &
                            sig(:exe_operand_32bit, width: 1)
                        ),
                        sig(:dst, width: 32)[30..0].concat(
                          sig(:cflag, width: 1)
                        ).concat(
                          sig(:dst, width: 32)
                        ),
                        mux(
                          sig(:__VdfgRegularize_h435de875_0_5, width: 1),
                          sig(:__VdfgRegularize_h435de875_0_4, width: 64),
                          sig(:src, width: 32).concat(
                            sig(:dst, width: 32)
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
  assign :__VdfgRegularize_h435de875_0_5,
    (
        sig(:e_shift_SHRD, width: 1) &
        sig(:exe_operand_16bit, width: 1)
    )
  assign :e_shift_cflag,
    mux(
      sig(:__VdfgRegularize_h435de875_0_28, width: 1),
      (
          (
            ~(
                sig(:e_shift_SHL, width: 1) &
                (
                    sig(:exe_is_8bit, width: 1) &
                    (
                        lit(9, width: 5, base: "h", signed: false) <=
                        sig(:e_shift_count, width: 5)
                    )
                )
            )
          ) &
          (
              (
                ~(
                    sig(:__VdfgRegularize_h435de875_0_6, width: 1) &
                    (
                        sig(:e_shift_SHL, width: 1) &
                        (
                            sig(:exe_operand_16bit, width: 1) &
                            sig(:__VdfgRegularize_h435de875_0_7, width: 1)
                        )
                    )
                )
              ) &
              mux(
                (
                    sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                    sig(:__VdfgRegularize_h435de875_0_8, width: 1)
                ),
                sig(:dst, width: 32)[1],
                mux(
                  (
                      sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                      sig(:__VdfgRegularize_h435de875_0_9, width: 1)
                  ),
                  sig(:dst, width: 32)[0],
                  mux(
                    (
                        sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                        sig(:__VdfgRegularize_h435de875_0_10, width: 1)
                    ),
                    sig(:cflag, width: 1),
                    mux(
                      (
                          sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                          sig(:__VdfgRegularize_h435de875_0_11, width: 1)
                      ),
                      sig(:dst, width: 32)[7],
                      mux(
                        (
                            sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                            sig(:__VdfgRegularize_h435de875_0_12, width: 1)
                        ),
                        sig(:dst, width: 32)[6],
                        mux(
                          (
                              sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                              sig(:__VdfgRegularize_h435de875_0_13, width: 1)
                          ),
                          sig(:dst, width: 32)[5],
                          mux(
                            (
                                sig(:__VdfgRegularize_h435de875_0_2, width: 1) &
                                sig(:__VdfgRegularize_h435de875_0_14, width: 1)
                            ),
                            sig(:dst, width: 32)[4],
                            mux(
                              (
                                  sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                  sig(:__VdfgRegularize_h435de875_0_15, width: 1)
                              ),
                              sig(:cflag, width: 1),
                              mux(
                                (
                                    sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                    sig(:__VdfgRegularize_h435de875_0_16, width: 1)
                                ),
                                sig(:dst, width: 32)[15],
                                mux(
                                  (
                                      sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                      sig(:__VdfgRegularize_h435de875_0_17, width: 1)
                                  ),
                                  sig(:dst, width: 32)[14],
                                  mux(
                                    (
                                        sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                        sig(:__VdfgRegularize_h435de875_0_18, width: 1)
                                    ),
                                    sig(:dst, width: 32)[13],
                                    mux(
                                      (
                                          sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                          sig(:__VdfgRegularize_h435de875_0_19, width: 1)
                                      ),
                                      sig(:dst, width: 32)[12],
                                      mux(
                                        (
                                            sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                            sig(:__VdfgRegularize_h435de875_0_20, width: 1)
                                        ),
                                        sig(:dst, width: 32)[11],
                                        mux(
                                          (
                                              sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                              sig(:__VdfgRegularize_h435de875_0_21, width: 1)
                                          ),
                                          sig(:dst, width: 32)[10],
                                          mux(
                                            (
                                                sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                sig(:__VdfgRegularize_h435de875_0_22, width: 1)
                                            ),
                                            sig(:dst, width: 32)[9],
                                            mux(
                                              (
                                                  sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                  sig(:__VdfgRegularize_h435de875_0_8, width: 1)
                                              ),
                                              sig(:dst, width: 32)[8],
                                              mux(
                                                (
                                                    sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                    sig(:__VdfgRegularize_h435de875_0_9, width: 1)
                                                ),
                                                sig(:dst, width: 32)[7],
                                                mux(
                                                  (
                                                      sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                      sig(:__VdfgRegularize_h435de875_0_10, width: 1)
                                                  ),
                                                  sig(:dst, width: 32)[6],
                                                  mux(
                                                    (
                                                        sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                        sig(:__VdfgRegularize_h435de875_0_11, width: 1)
                                                    ),
                                                    sig(:dst, width: 32)[5],
                                                    mux(
                                                      (
                                                          sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                          sig(:__VdfgRegularize_h435de875_0_12, width: 1)
                                                      ),
                                                      sig(:dst, width: 32)[4],
                                                      mux(
                                                        (
                                                            sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                            sig(:__VdfgRegularize_h435de875_0_13, width: 1)
                                                        ),
                                                        sig(:dst, width: 32)[3],
                                                        mux(
                                                          (
                                                              sig(:__VdfgRegularize_h435de875_0_29, width: 1) &
                                                              sig(:__VdfgRegularize_h435de875_0_14, width: 1)
                                                          ),
                                                          sig(:dst, width: 32)[2],
                                                          mux(
                                                            (
                                                                sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                sig(:__VdfgRegularize_h435de875_0_15, width: 1)
                                                            ),
                                                            sig(:src, width: 32)[15],
                                                            mux(
                                                              (
                                                                  sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                  sig(:__VdfgRegularize_h435de875_0_16, width: 1)
                                                              ),
                                                              sig(:src, width: 32)[14],
                                                              mux(
                                                                (
                                                                    sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                    sig(:__VdfgRegularize_h435de875_0_17, width: 1)
                                                                ),
                                                                sig(:src, width: 32)[13],
                                                                mux(
                                                                  (
                                                                      sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                      sig(:__VdfgRegularize_h435de875_0_18, width: 1)
                                                                  ),
                                                                  sig(:src, width: 32)[12],
                                                                  mux(
                                                                    (
                                                                        sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                        sig(:__VdfgRegularize_h435de875_0_19, width: 1)
                                                                    ),
                                                                    sig(:src, width: 32)[11],
                                                                    mux(
                                                                      (
                                                                          sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                          sig(:__VdfgRegularize_h435de875_0_20, width: 1)
                                                                      ),
                                                                      sig(:src, width: 32)[10],
                                                                      mux(
                                                                        (
                                                                            sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                            sig(:__VdfgRegularize_h435de875_0_21, width: 1)
                                                                        ),
                                                                        sig(:src, width: 32)[9],
                                                                        mux(
                                                                          (
                                                                              sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                              sig(:__VdfgRegularize_h435de875_0_22, width: 1)
                                                                          ),
                                                                          sig(:src, width: 32)[8],
                                                                          mux(
                                                                            (
                                                                                sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                sig(:__VdfgRegularize_h435de875_0_8, width: 1)
                                                                            ),
                                                                            sig(:src, width: 32)[7],
                                                                            mux(
                                                                              (
                                                                                  sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                  sig(:__VdfgRegularize_h435de875_0_9, width: 1)
                                                                              ),
                                                                              sig(:src, width: 32)[6],
                                                                              mux(
                                                                                (
                                                                                    sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                    sig(:__VdfgRegularize_h435de875_0_10, width: 1)
                                                                                ),
                                                                                sig(:src, width: 32)[5],
                                                                                mux(
                                                                                  (
                                                                                      sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                      sig(:__VdfgRegularize_h435de875_0_11, width: 1)
                                                                                  ),
                                                                                  sig(:src, width: 32)[4],
                                                                                  mux(
                                                                                    (
                                                                                        sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                        sig(:__VdfgRegularize_h435de875_0_12, width: 1)
                                                                                    ),
                                                                                    sig(:src, width: 32)[3],
                                                                                    mux(
                                                                                      (
                                                                                          sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                          sig(:__VdfgRegularize_h435de875_0_13, width: 1)
                                                                                      ),
                                                                                      sig(:src, width: 32)[2],
                                                                                      mux(
                                                                                        (
                                                                                            sig(:__VdfgRegularize_h435de875_0_3, width: 1) &
                                                                                            sig(:__VdfgRegularize_h435de875_0_14, width: 1)
                                                                                        ),
                                                                                        sig(:src, width: 32)[1],
                                                                                        sig(:e_shift_left_result, width: 33)[32]
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
      (
          (
            ~(
                sig(:__VdfgRegularize_h435de875_0_5, width: 1) &
                sig(:__VdfgRegularize_h435de875_0_7, width: 1)
            )
          ) &
          sig(:e_shift_right_result, width: 33)[0]
      )
    )
  assign :__VdfgRegularize_h435de875_0_28,
    (
        sig(:e_shift_SHL, width: 1) |
        (
            sig(:e_shift_ROL, width: 1) |
            (
                sig(:e_shift_RCL, width: 1) |
                sig(:e_shift_SHLD, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h435de875_0_6,
    (
      ~sig(:exe_is_8bit, width: 1)
    )
  assign :__VdfgRegularize_h435de875_0_7,
    (
        lit(17, width: 5, base: "h", signed: false) <=
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_8,
    (
        lit(25, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_9,
    (
        lit(26, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_10,
    (
        lit(27, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_11,
    (
        lit(28, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_12,
    (
        lit(29, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_13,
    (
        lit(30, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_14,
    (
        lit(31, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_29,
    (
        sig(:e_shift_RCL, width: 1) &
        sig(:__VdfgRegularize_h435de875_0_24, width: 1)
    )
  assign :__VdfgRegularize_h435de875_0_15,
    (
        lit(17, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_16,
    (
        lit(18, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_17,
    (
        lit(19, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_18,
    (
        lit(20, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_19,
    (
        lit(21, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_20,
    (
        lit(22, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_21,
    (
        lit(23, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgRegularize_h435de875_0_22,
    (
        lit(24, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :e_shift_oflag,
    mux(
      sig(:e_shift_ROL, width: 1),
      (
          sig(:e_shift_result, width: 32)[31] ^
          sig(:e_shift_result, width: 32)[0]
      ),
      mux(
        (
            sig(:e_shift_ROR, width: 1) |
            (
                sig(:e_shift_RCR, width: 1) |
                (
                    sig(:e_shift_SHR, width: 1) |
                    sig(:e_shift_SHRD, width: 1)
                )
            )
        ),
        (
            sig(:e_shift_result, width: 32)[31] ^
            sig(:e_shift_result, width: 32)[30]
        ),
        (
            (
                sig(:e_shift_RCL, width: 1) |
                (
                    sig(:e_shift_SHL, width: 1) |
                    sig(:e_shift_SHLD, width: 1)
                )
            ) &
            (
                sig(:e_shift_result, width: 32)[31] ^
                sig(:e_shift_cflag, width: 1)
            )
        )
      )
    )
  assign :e_shift_result,
    mux(
      (
          sig(:__VdfgRegularize_h435de875_0_28, width: 1) &
          sig(:exe_is_8bit, width: 1)
      ),
      sig(:e_shift_left_result, width: 33)[7].replicate(
        lit(24, width: 32, base: "h", signed: true)
      ).concat(
        sig(:e_shift_left_result, width: 33)[7..0]
      ),
      mux(
        (
            sig(:__VdfgRegularize_h435de875_0_28, width: 1) &
            sig(:exe_operand_16bit, width: 1)
        ),
        sig(:e_shift_left_result, width: 33)[15].replicate(
          lit(16, width: 32, base: "h", signed: true)
        ).concat(
          sig(:e_shift_left_result, width: 33)[15..0]
        ),
        mux(
          (
              sig(:__VdfgRegularize_h435de875_0_28, width: 1) &
              sig(:exe_operand_32bit, width: 1)
          ),
          sig(:e_shift_left_result, width: 33)[31..0],
          mux(
            sig(:exe_is_8bit, width: 1),
            sig(:e_shift_right_result, width: 33)[8].concat(
              sig(:e_shift_right_result, width: 33)[7].replicate(
                lit(23, width: 32, base: "h", signed: true)
              ).concat(
                sig(:e_shift_right_result, width: 33)[8..1]
              )
            ),
            mux(
              sig(:exe_operand_16bit, width: 1),
              sig(:e_shift_right_result, width: 33)[16].concat(
                sig(:e_shift_right_result, width: 33)[15].replicate(
                  lit(15, width: 32, base: "h", signed: true)
                ).concat(
                  sig(:e_shift_right_result, width: 33)[16..1]
                )
              ),
              sig(:e_shift_right_result, width: 33)[32..1]
            )
          )
        )
      )
    )
  assign :e_shift_cf_of_rotate_carry_8bit,
    (
        sig(:__VdfgRegularize_h435de875_0_23, width: 1) &
        (
            (
                lit(9, width: 5, base: "h", signed: false) !=
                sig(:e_shift_count, width: 5)
            ) &
            (
                (
                    lit(18, width: 5, base: "h", signed: false) !=
                    sig(:e_shift_count, width: 5)
                ) &
                (
                    lit(27, width: 5, base: "h", signed: false) !=
                    sig(:e_shift_count, width: 5)
                )
            )
        )
    )
  assign :__VdfgRegularize_h435de875_0_23,
    (
        lit(0, width: 5, base: "h", signed: false) !=
        sig(:e_shift_count, width: 5)
    )
  assign :e_shift_cf_of_rotate_carry_16bit,
    (
        sig(:__VdfgRegularize_h435de875_0_23, width: 1) &
        (
            lit(17, width: 5, base: "h", signed: false) !=
            sig(:e_shift_count, width: 5)
        )
    )
  assign :e_shift_cmd_carry,
    (
        sig(:e_shift_RCL, width: 1) |
        sig(:e_shift_RCR, width: 1)
    )
  assign :e_shift_cmd_shift,
    (
        sig(:e_shift_SHL, width: 1) |
        (
            sig(:e_shift_SHR, width: 1) |
            (
                sig(:e_shift_SAR, width: 1) |
                (
                    sig(:e_shift_SHLD, width: 1) |
                    sig(:e_shift_SHRD, width: 1)
                )
            )
        )
    )
  assign :e_shift_cmd_rot,
    (
        sig(:e_shift_ROL, width: 1) |
        sig(:e_shift_ROR, width: 1)
    )
  assign :e_shift_cf_of_update,
    (
        (
            sig(:__VdfgRegularize_h435de875_0_23, width: 1) &
            (
                sig(:e_shift_cmd_rot, width: 1) |
                sig(:e_shift_cmd_shift, width: 1)
            )
        ) |
        (
            (
                sig(:exe_is_8bit, width: 1) &
                (
                    sig(:e_shift_cf_of_rotate_carry_8bit, width: 1) &
                    sig(:e_shift_cmd_carry, width: 1)
                )
            ) |
            (
                (
                    sig(:__VdfgRegularize_h435de875_0_24, width: 1) &
                    (
                        sig(:e_shift_cf_of_rotate_carry_16bit, width: 1) &
                        sig(:e_shift_cmd_carry, width: 1)
                    )
                ) |
                (
                    sig(:__VdfgRegularize_h435de875_0_25, width: 1) &
                    (
                        sig(:__VdfgRegularize_h435de875_0_23, width: 1) &
                        sig(:e_shift_cmd_carry, width: 1)
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h435de875_0_24,
    (
        sig(:__VdfgRegularize_h435de875_0_6, width: 1) &
        sig(:exe_operand_16bit, width: 1)
    )
  assign :__VdfgRegularize_h435de875_0_25,
    (
        sig(:__VdfgRegularize_h435de875_0_6, width: 1) &
        sig(:exe_operand_32bit, width: 1)
    )
  assign :e_shift_oszapc_update,
    (
        sig(:e_shift_cf_of_update, width: 1) &
        sig(:e_shift_cmd_shift, width: 1)
    )
  assign :e_shift_no_write,
    (
        (
            sig(:e_shift_cmd_shift, width: 1) &
            sig(:__VdfgRegularize_h435de875_0_26, width: 1)
        ) |
        (
            (
                sig(:exe_is_8bit, width: 1) &
                (
                    sig(:e_shift_cmd_rot, width: 1) &
                    (
                        lit(0, width: 3, base: "h", signed: false) ==
                        sig(:e_shift_count, width: 5)[2..0]
                    )
                )
            ) |
            (
                (
                    sig(:__VdfgRegularize_h435de875_0_24, width: 1) &
                    (
                        sig(:e_shift_cmd_rot, width: 1) &
                        (
                            lit(0, width: 4, base: "h", signed: false) ==
                            sig(:e_shift_count, width: 5)[3..0]
                        )
                    )
                ) |
                (
                    (
                        sig(:exe_is_8bit, width: 1) &
                        (
                            (
                              ~sig(:e_shift_cf_of_rotate_carry_8bit, width: 1)
                            ) &
                            sig(:e_shift_cmd_carry, width: 1)
                        )
                    ) |
                    (
                        (
                            sig(:__VdfgRegularize_h435de875_0_24, width: 1) &
                            (
                                (
                                  ~sig(:e_shift_cf_of_rotate_carry_16bit, width: 1)
                                ) &
                                sig(:e_shift_cmd_carry, width: 1)
                            )
                        ) |
                        (
                            sig(:__VdfgRegularize_h435de875_0_25, width: 1) &
                            sig(:__VdfgRegularize_h435de875_0_26, width: 1)
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_h435de875_0_26,
    (
        lit(0, width: 5, base: "h", signed: false) ==
        sig(:e_shift_count, width: 5)
    )
  assign :__VdfgExtracted_h9393973f__0,
    sig(:e_shift_left_input, width: 64)[63..31]
  assign :__VdfgExtracted_h9393947e__0,
    sig(:e_shift_left_input, width: 64)[62..30]
  assign :__VdfgExtracted_h939397d8__0,
    sig(:e_shift_left_input, width: 64)[61..29]
  assign :__VdfgExtracted_h93938b59__0,
    sig(:e_shift_left_input, width: 64)[60..28]
  assign :__VdfgExtracted_h93938a56__0,
    sig(:e_shift_left_input, width: 64)[59..27]
  assign :__VdfgExtracted_h93938b97__0,
    sig(:e_shift_left_input, width: 64)[58..26]
  assign :__VdfgExtracted_h93938acf__0,
    sig(:e_shift_left_input, width: 64)[57..25]
  assign :__VdfgExtracted_h93938a0e__0,
    sig(:e_shift_left_input, width: 64)[56..24]
  assign :__VdfgExtracted_h93938d51__0,
    sig(:e_shift_left_input, width: 64)[55..23]
  assign :__VdfgExtracted_h93938a90__0,
    sig(:e_shift_left_input, width: 64)[54..22]
  assign :__VdfgExtracted_h93939de6__0,
    sig(:e_shift_left_input, width: 64)[53..21]
  assign :__VdfgExtracted_h9393a127__0,
    sig(:e_shift_left_input, width: 64)[52..20]
  assign :__VdfgExtracted_h9393a068__0,
    sig(:e_shift_left_input, width: 64)[51..19]
  assign :__VdfgExtracted_h9393a1a9__0,
    sig(:e_shift_left_input, width: 64)[50..18]
  assign :__VdfgExtracted_h939398d5__0,
    sig(:e_shift_left_input, width: 64)[49..17]
  assign :__VdfgExtracted_h93939814__0,
    sig(:e_shift_left_input, width: 64)[48..16]
  assign :__VdfgExtracted_h93938b53__0,
    sig(:e_shift_left_input, width: 64)[47..15]
  assign :__VdfgExtracted_h93939892__0,
    sig(:e_shift_left_input, width: 64)[46..14]
  assign :__VdfgExtracted_h93953f14__0,
    sig(:e_shift_left_input, width: 64)[45..13]
  assign :__VdfgExtracted_h93953f55__0,
    sig(:e_shift_left_input, width: 64)[44..12]
  assign :__VdfgExtracted_h93953f92__0,
    sig(:e_shift_left_input, width: 64)[43..11]
  assign :__VdfgExtracted_h93953bd3__0,
    sig(:e_shift_left_input, width: 64)[42..10]
  assign :__VdfgExtracted_h93939ee3__0,
    sig(:e_shift_left_input, width: 64)[41..9]
  assign :__VdfgExtracted_h93939e22__0,
    sig(:e_shift_left_input, width: 64)[40..8]
  assign :__VdfgExtracted_h9393a165__0,
    sig(:e_shift_left_input, width: 64)[39..7]
  assign :__VdfgExtracted_h93939ea4__0,
    sig(:e_shift_left_input, width: 64)[38..6]
  assign :__VdfgExtracted_h939391f2__0,
    sig(:e_shift_left_input, width: 64)[37..5]
  assign :__VdfgExtracted_h93939533__0,
    sig(:e_shift_left_input, width: 64)[36..4]
  assign :__VdfgExtracted_h93939474__0,
    sig(:e_shift_left_input, width: 64)[35..3]
  assign :__VdfgExtracted_h939395b5__0,
    sig(:e_shift_left_input, width: 64)[34..2]
  assign :__VdfgExtracted_h93953c59__0,
    sig(:e_shift_left_input, width: 64)[33..1]
  assign :__VdfgExtracted_h60a66432__0,
    sig(:e_shift_right_input, width: 64)[32..0]
  assign :__VdfgExtracted_h60a66573__0,
    sig(:e_shift_right_input, width: 64)[33..1]
  assign :__VdfgExtracted_h60a40aff__0,
    sig(:e_shift_right_input, width: 64)[34..2]
  assign :__VdfgExtracted_h60a40d3e__0,
    sig(:e_shift_right_input, width: 64)[35..3]
  assign :__VdfgExtracted_h60a40c7d__0,
    sig(:e_shift_right_input, width: 64)[36..4]
  assign :__VdfgExtracted_h60a40abc__0,
    sig(:e_shift_right_input, width: 64)[37..5]
  assign :__VdfgExtracted_h60a4062e__0,
    sig(:e_shift_right_input, width: 64)[38..6]
  assign :__VdfgExtracted_h60a4086f__0,
    sig(:e_shift_right_input, width: 64)[39..7]
  assign :__VdfgExtracted_h60a407ac__0,
    sig(:e_shift_right_input, width: 64)[40..8]
  assign :__VdfgExtracted_h60a405ed__0,
    sig(:e_shift_right_input, width: 64)[41..9]
  assign :__VdfgExtracted_h60a6659d__0,
    sig(:e_shift_right_input, width: 64)[42..10]
  assign :__VdfgExtracted_h60a664dc__0,
    sig(:e_shift_right_input, width: 64)[43..11]
  assign :__VdfgExtracted_h60a6651f__0,
    sig(:e_shift_right_input, width: 64)[44..12]
  assign :__VdfgExtracted_h60a6665e__0,
    sig(:e_shift_right_input, width: 64)[45..13]
  assign :__VdfgExtracted_h60a40fdc__0,
    sig(:e_shift_right_input, width: 64)[46..14]
  assign :__VdfgExtracted_h60a4111d__0,
    sig(:e_shift_right_input, width: 64)[47..15]
  assign :__VdfgExtracted_h60a4115e__0,
    sig(:e_shift_right_input, width: 64)[48..16]
  assign :__VdfgExtracted_h60a4109f__0,
    sig(:e_shift_right_input, width: 64)[49..17]
  assign :__VdfgExtracted_h60a40703__0,
    sig(:e_shift_right_input, width: 64)[50..18]
  assign :__VdfgExtracted_h60a40942__0,
    sig(:e_shift_right_input, width: 64)[51..19]
  assign :__VdfgExtracted_h60a40881__0,
    sig(:e_shift_right_input, width: 64)[52..20]
  assign :__VdfgExtracted_h60a406f0__0,
    sig(:e_shift_right_input, width: 64)[53..21]
  assign :__VdfgExtracted_h60a411da__0,
    sig(:e_shift_right_input, width: 64)[54..22]
  assign :__VdfgExtracted_h60a4131b__0,
    sig(:e_shift_right_input, width: 64)[55..23]
  assign :__VdfgExtracted_h60a41368__0,
    sig(:e_shift_right_input, width: 64)[56..24]
  assign :__VdfgExtracted_h60a41299__0,
    sig(:e_shift_right_input, width: 64)[57..25]
  assign :__VdfgExtracted_h60a410f1__0,
    sig(:e_shift_right_input, width: 64)[58..26]
  assign :__VdfgExtracted_h60a41220__0,
    sig(:e_shift_right_input, width: 64)[59..27]
  assign :__VdfgExtracted_h60a41273__0,
    sig(:e_shift_right_input, width: 64)[60..28]
  assign :__VdfgExtracted_h60a411b2__0,
    sig(:e_shift_right_input, width: 64)[61..29]
  assign :__VdfgExtracted_h60a40c18__0,
    sig(:e_shift_right_input, width: 64)[62..30]

  # Processes

  process :combinational_logic_0,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    case_stmt(sig(:e_shift_count, width: 5)) do
      when_value(lit(0, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:cflag, width: 1).concat(
            sig(:e_shift_left_input, width: 64)[63..32]
          ),
          kind: :blocking
        )
      end
      when_value(lit(1, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393973f__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(2, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393947e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(3, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h939397d8__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(4, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938b59__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(5, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938a56__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(6, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938b97__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(7, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938acf__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(8, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938a0e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(9, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938d51__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(10, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938a90__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(11, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939de6__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(12, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393a127__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(13, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393a068__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(14, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393a1a9__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(15, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h939398d5__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(16, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939814__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(17, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93938b53__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(18, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939892__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(19, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93953f14__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(20, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93953f55__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(21, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93953f92__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(22, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93953bd3__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(23, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939ee3__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(24, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939e22__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(25, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h9393a165__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(26, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939ea4__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(27, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h939391f2__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(28, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939533__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(29, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93939474__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(30, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h939395b5__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(31, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_left_result,
          sig(:__VdfgExtracted_h93953c59__0, width: 33),
          kind: :blocking
        )
      end
    end
  end

  process :combinational_logic_1,
    sensitivity: [
    ],
    clocked: false,
    initial: false do
    case_stmt(sig(:e_shift_count, width: 5)) do
      when_value(lit(0, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:e_shift_right_input, width: 64)[31..0].concat(
            sig(:cflag, width: 1)
          ),
          kind: :blocking
        )
      end
      when_value(lit(1, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a66432__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(2, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a66573__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(3, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40aff__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(4, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40d3e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(5, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40c7d__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(6, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40abc__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(7, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4062e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(8, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4086f__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(9, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a407ac__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(10, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a405ed__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(11, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a6659d__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(12, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a664dc__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(13, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a6651f__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(14, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a6665e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(15, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40fdc__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(16, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4111d__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(17, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4115e__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(18, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4109f__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(19, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40703__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(20, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40942__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(21, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40881__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(22, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a406f0__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(23, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a411da__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(24, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a4131b__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(25, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a41368__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(26, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a41299__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(27, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a410f1__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(28, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a41220__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(29, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a41273__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(30, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a411b2__0, width: 33),
          kind: :blocking
        )
      end
      when_value(lit(31, width: 5, base: "h", signed: false)) do
        assign(
          :e_shift_right_result,
          sig(:__VdfgExtracted_h60a40c18__0, width: 33),
          kind: :blocking
        )
      end
    end
  end

  process :initial_block_2,
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
