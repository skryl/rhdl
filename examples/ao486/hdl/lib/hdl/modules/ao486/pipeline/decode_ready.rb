# frozen_string_literal: true

class DecodeReady < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: decode_ready

  def self._import_decl_kinds
    {
      __VdfgRegularize_h088ae185_0_0: :logic,
      __VdfgRegularize_h088ae185_0_1: :logic,
      __VdfgRegularize_h088ae185_0_10: :logic,
      __VdfgRegularize_h088ae185_0_2: :logic,
      __VdfgRegularize_h088ae185_0_3: :logic,
      __VdfgRegularize_h088ae185_0_4: :logic,
      __VdfgRegularize_h088ae185_0_5: :logic,
      __VdfgRegularize_h088ae185_0_6: :logic,
      __VdfgRegularize_h088ae185_0_7: :logic,
      __VdfgRegularize_h088ae185_0_8: :logic,
      __VdfgRegularize_h088ae185_0_9: :logic,
      _unused_ok: :wire,
      modregrm_imm_len: :wire
    }
  end

  # Ports

  input :enable
  input :is_prefix
  input :decoder_count, width: 4
  input :decoder, width: 96
  input :dec_operand_32bit
  input :dec_address_32bit
  input :dec_prefix_2byte
  input :dec_modregrm_len, width: 3
  output :dec_ready_one
  output :dec_ready_one_one
  output :dec_ready_one_two
  output :dec_ready_one_three
  output :dec_ready_2byte_one
  output :dec_ready_modregrm_one
  output :dec_ready_2byte_modregrm
  output :dec_ready_call_jmp_imm
  output :dec_ready_one_imm
  output :dec_ready_2byte_imm
  output :dec_ready_mem_offset
  output :dec_ready_modregrm_imm
  output :dec_ready_2byte_modregrm_imm
  input :consume_one
  input :consume_one_one
  input :consume_one_two
  input :consume_one_three
  input :consume_call_jmp_imm
  input :consume_modregrm_one
  input :consume_one_imm
  input :consume_modregrm_imm
  input :consume_mem_offset
  output :consume_count_local, width: 4
  output :dec_is_modregrm

  # Signals

  signal :__VdfgRegularize_h088ae185_0_0
  signal :__VdfgRegularize_h088ae185_0_1
  signal :__VdfgRegularize_h088ae185_0_10, width: 4
  signal :__VdfgRegularize_h088ae185_0_2
  signal :__VdfgRegularize_h088ae185_0_3
  signal :__VdfgRegularize_h088ae185_0_4
  signal :__VdfgRegularize_h088ae185_0_5
  signal :__VdfgRegularize_h088ae185_0_6
  signal :__VdfgRegularize_h088ae185_0_7, width: 4
  signal :__VdfgRegularize_h088ae185_0_8, width: 4
  signal :__VdfgRegularize_h088ae185_0_9, width: 4
  signal :_unused_ok
  signal :modregrm_imm_len, width: 4

  # Assignments

  assign :dec_is_modregrm,
    (
        sig(:consume_modregrm_imm, width: 1) |
        sig(:consume_modregrm_one, width: 1)
    )
  assign :modregrm_imm_len,
    (
        sig(:__VdfgRegularize_h088ae185_0_10, width: 4) +
        lit(0, width: 1, base: "d", signed: false).concat(
        (
            (
                mux(
                  (
                      sig(:dec_prefix_2byte, width: 1) |
                      (
                          (
                              lit(96, width: 7, base: "h", signed: false) ==
                              sig(:decoder, width: 96)[7..1]
                          ) |
                          (
                              (
                                  lit(0, width: 2, base: "h", signed: false) ==
                                  sig(:decoder, width: 96)[1..0]
                              ) |
                              (
                                  (
                                      lit(2, width: 2, base: "h", signed: false) ==
                                      sig(:decoder, width: 96)[1..0]
                                  ) |
                                  (
                                      lit(3, width: 3, base: "h", signed: false) ==
                                      sig(:decoder, width: 96)[2..0]
                                  )
                              )
                          )
                      )
                  ),
                  lit(1, width: 3, base: "h", signed: false),
                  mux(
                    sig(:dec_operand_32bit, width: 1),
                    lit(4, width: 3, base: "h", signed: false),
                    lit(2, width: 3, base: "h", signed: false)
                  )
                ) >>
                lit(0, width: nil, base: "d", signed: false)
            ) &
            (
                (
                    lit(1, width: 32, base: "d") <<
                    (
                          (
                            lit(2, width: nil, base: "d", signed: false)
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
      )
    )
  assign :__VdfgRegularize_h088ae185_0_10,
    lit(0, width: 1, base: "d", signed: false).concat(
      sig(:dec_modregrm_len, width: 3)
    )
  assign :consume_count_local,
    mux(
      sig(:consume_one, width: 1),
      lit(1, width: 4, base: "h", signed: false),
      mux(
        sig(:consume_one_one, width: 1),
        lit(2, width: 4, base: "h", signed: false),
        mux(
          sig(:consume_one_two, width: 1),
          lit(3, width: 4, base: "h", signed: false),
          mux(
            sig(:consume_one_three, width: 1),
            lit(4, width: 4, base: "h", signed: false),
            mux(
              sig(:consume_call_jmp_imm, width: 1),
              sig(:__VdfgRegularize_h088ae185_0_9, width: 4),
              mux(
                sig(:consume_modregrm_one, width: 1),
                sig(:__VdfgRegularize_h088ae185_0_10, width: 4),
                mux(
                  sig(:consume_one_imm, width: 1),
                  sig(:__VdfgRegularize_h088ae185_0_8, width: 4),
                  mux(
                    sig(:consume_modregrm_imm, width: 1),
                    sig(:modregrm_imm_len, width: 4),
                    mux(
                      sig(:consume_mem_offset, width: 1),
                      sig(:__VdfgRegularize_h088ae185_0_7, width: 4),
                      lit(0, width: 4, base: "h", signed: false)
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_h088ae185_0_9,
    lit(0, width: 1, base: "d", signed: false).concat(
      (
          (
              mux(
                (
                    lit(3, width: 2, base: "h", signed: false) ==
                    sig(:decoder, width: 96)[1..0]
                ),
                lit(2, width: 3, base: "h", signed: false),
                mux(
                  (
                      sig(:decoder, width: 96)[1] &
                      sig(:dec_operand_32bit, width: 1)
                  ),
                  lit(7, width: 3, base: "h", signed: false),
                  mux(
                    (
                        sig(:decoder, width: 96)[1] |
                        sig(:dec_operand_32bit, width: 1)
                    ),
                    lit(5, width: 3, base: "h", signed: false),
                    lit(3, width: 3, base: "h", signed: false)
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
                          lit(2, width: nil, base: "d", signed: false)
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
    )
  assign :__VdfgRegularize_h088ae185_0_8,
    lit(0, width: 1, base: "d", signed: false).concat(
      (
          (
              mux(
                (
                    sig(:__VdfgRegularize_h088ae185_0_0, width: 1) &
                    (
                        (
                            lit(22, width: 5, base: "h", signed: false) ==
                            sig(:decoder, width: 96)[7..3]
                        ) |
                        (
                            (
                                lit(168, width: 8, base: "h", signed: false) ==
                                sig(:decoder, width: 96)[7..0]
                            ) |
                            (
                                (
                                    lit(106, width: 8, base: "h", signed: false) ==
                                    sig(:decoder, width: 96)[7..0]
                                ) |
                                (
                                    lit(0, width: 3, base: "h", signed: false) ==
                                    sig(:decoder, width: 96)[7..6].concat(
                                    sig(:decoder, width: 96)[0]
                                  )
                                )
                            )
                        )
                    )
                ),
                lit(2, width: 3, base: "h", signed: false),
                mux(
                  sig(:dec_operand_32bit, width: 1),
                  lit(5, width: 3, base: "h", signed: false),
                  lit(3, width: 3, base: "h", signed: false)
                )
              ) >>
              lit(0, width: nil, base: "d", signed: false)
          ) &
          (
              (
                  lit(1, width: 32, base: "d") <<
                  (
                        (
                          lit(2, width: nil, base: "d", signed: false)
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
    )
  assign :__VdfgRegularize_h088ae185_0_7,
    lit(0, width: 1, base: "d", signed: false).concat(
      (
          (
              mux(
                sig(:dec_address_32bit, width: 1),
                lit(5, width: 3, base: "h", signed: false),
                lit(3, width: 3, base: "h", signed: false)
              ) >>
              lit(0, width: nil, base: "d", signed: false)
          ) &
          (
              (
                  lit(1, width: 32, base: "d") <<
                  (
                        (
                          lit(2, width: nil, base: "d", signed: false)
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
    )
  assign :dec_ready_one,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_1, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_6,
    (
        sig(:enable, width: 1) &
        (
            (
              ~sig(:is_prefix, width: 1)
            ) &
            sig(:__VdfgRegularize_h088ae185_0_0, width: 1)
        )
    )
  assign :__VdfgRegularize_h088ae185_0_1,
    (
        lit(1, width: 4, base: "h", signed: false) <=
        sig(:decoder_count, width: 4)
    )
  assign :dec_ready_one_one,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        (
            lit(2, width: 4, base: "h", signed: false) <=
            sig(:decoder_count, width: 4)
        )
    )
  assign :dec_ready_one_two,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        (
            lit(3, width: 4, base: "h", signed: false) <=
            sig(:decoder_count, width: 4)
        )
    )
  assign :dec_ready_one_three,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        (
            lit(4, width: 4, base: "h", signed: false) <=
            sig(:decoder_count, width: 4)
        )
    )
  assign :dec_ready_2byte_one,
    (
        sig(:__VdfgRegularize_h088ae185_0_5, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_1, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_5,
    (
        sig(:dec_prefix_2byte, width: 1) &
        sig(:enable, width: 1)
    )
  assign :dec_ready_modregrm_one,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_2, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_2,
    (
        sig(:decoder_count, width: 4) >=
        sig(:__VdfgRegularize_h088ae185_0_10, width: 4)
    )
  assign :dec_ready_2byte_modregrm,
    (
        sig(:__VdfgRegularize_h088ae185_0_5, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_2, width: 1)
    )
  assign :dec_ready_call_jmp_imm,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        (
            sig(:decoder_count, width: 4) >=
            sig(:__VdfgRegularize_h088ae185_0_9, width: 4)
        )
    )
  assign :dec_ready_one_imm,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_3, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_3,
    (
        sig(:decoder_count, width: 4) >=
        sig(:__VdfgRegularize_h088ae185_0_8, width: 4)
    )
  assign :dec_ready_2byte_imm,
    (
        sig(:__VdfgRegularize_h088ae185_0_5, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_3, width: 1)
    )
  assign :dec_ready_mem_offset,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        (
            sig(:decoder_count, width: 4) >=
            sig(:__VdfgRegularize_h088ae185_0_7, width: 4)
        )
    )
  assign :dec_ready_modregrm_imm,
    (
        sig(:__VdfgRegularize_h088ae185_0_6, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_4, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_4,
    (
        sig(:decoder_count, width: 4) >=
        sig(:modregrm_imm_len, width: 4)
    )
  assign :dec_ready_2byte_modregrm_imm,
    (
        sig(:__VdfgRegularize_h088ae185_0_5, width: 1) &
        sig(:__VdfgRegularize_h088ae185_0_4, width: 1)
    )
  assign :__VdfgRegularize_h088ae185_0_0,
    (
      ~sig(:dec_prefix_2byte, width: 1)
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
