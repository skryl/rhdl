# frozen_string_literal: true

class DecodePrefix < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: decode_prefix

  def self._import_decl_kinds
    {
      CRx_DRx_condition: :wire,
      __VdfgRegularize_h6656821c_0_0: :logic,
      __VdfgRegularize_h6656821c_0_1: :logic,
      __VdfgRegularize_h6656821c_0_10: :logic,
      __VdfgRegularize_h6656821c_0_11: :logic,
      __VdfgRegularize_h6656821c_0_12: :logic,
      __VdfgRegularize_h6656821c_0_13: :logic,
      __VdfgRegularize_h6656821c_0_14: :logic,
      __VdfgRegularize_h6656821c_0_15: :logic,
      __VdfgRegularize_h6656821c_0_16: :logic,
      __VdfgRegularize_h6656821c_0_2: :logic,
      __VdfgRegularize_h6656821c_0_3: :logic,
      __VdfgRegularize_h6656821c_0_4: :logic,
      __VdfgRegularize_h6656821c_0_5: :logic,
      __VdfgRegularize_h6656821c_0_6: :logic,
      __VdfgRegularize_h6656821c_0_7: :logic,
      __VdfgRegularize_h6656821c_0_8: :logic,
      __VdfgRegularize_h6656821c_0_9: :logic,
      _unused_ok: :wire,
      dec_address_16bit: :wire,
      prefix_group_2: :reg,
      prefix_group_3: :reg,
      prefix_group_4: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :cs_cache, width: 64
  input :dec_is_modregrm
  input :decoder, width: 96
  input :instr_prefix
  input :instr_finished
  output :dec_operand_32bit
  output :dec_address_32bit
  output :dec_prefix_group_1_rep, width: 2
  output :dec_prefix_group_1_lock
  output :dec_prefix_group_2_seg, width: 3
  output :dec_prefix_2byte
  output :dec_modregrm_len, width: 3
  output :prefix_count, width: 4
  output :is_prefix
  output :prefix_group_1_lock

  # Signals

  signal :CRx_DRx_condition
  signal :__VdfgRegularize_h6656821c_0_0
  signal :__VdfgRegularize_h6656821c_0_1
  signal :__VdfgRegularize_h6656821c_0_10
  signal :__VdfgRegularize_h6656821c_0_11
  signal :__VdfgRegularize_h6656821c_0_12
  signal :__VdfgRegularize_h6656821c_0_13
  signal :__VdfgRegularize_h6656821c_0_14
  signal :__VdfgRegularize_h6656821c_0_15
  signal :__VdfgRegularize_h6656821c_0_16
  signal :__VdfgRegularize_h6656821c_0_2
  signal :__VdfgRegularize_h6656821c_0_3
  signal :__VdfgRegularize_h6656821c_0_4
  signal :__VdfgRegularize_h6656821c_0_5
  signal :__VdfgRegularize_h6656821c_0_6
  signal :__VdfgRegularize_h6656821c_0_7
  signal :__VdfgRegularize_h6656821c_0_8
  signal :__VdfgRegularize_h6656821c_0_9
  signal :_unused_ok
  signal :dec_address_16bit
  signal :prefix_group_2, width: 3
  signal :prefix_group_3
  signal :prefix_group_4

  # Assignments

  assign :dec_operand_32bit,
    (
        sig(:cs_cache, width: 64)[54] ^
        sig(:prefix_group_3, width: 1)
    )
  assign :dec_address_32bit,
    (
        sig(:cs_cache, width: 64)[54] ^
        sig(:prefix_group_4, width: 1)
    )
  assign :dec_address_16bit,
    (
      ~sig(:dec_address_32bit, width: 1)
    )
  assign :dec_modregrm_len,
    mux(
      sig(:CRx_DRx_condition, width: 1),
      lit(2, width: 3, base: "h", signed: false),
      mux(
        (
            sig(:__VdfgRegularize_h6656821c_0_1, width: 1) &
            sig(:__VdfgRegularize_h6656821c_0_2, width: 1)
        ),
        lit(4, width: 3, base: "h", signed: false),
        mux(
          (
              sig(:dec_address_16bit, width: 1) &
              sig(:__VdfgRegularize_h6656821c_0_3, width: 1)
          ),
          lit(3, width: 3, base: "h", signed: false),
          mux(
            (
                sig(:dec_address_16bit, width: 1) &
                sig(:__VdfgRegularize_h6656821c_0_4, width: 1)
            ),
            lit(4, width: 3, base: "h", signed: false),
            mux(
              sig(:dec_address_32bit, width: 1),
              mux(
                (
                    sig(:__VdfgRegularize_h6656821c_0_5, width: 1) &
                    sig(:__VdfgRegularize_h6656821c_0_6, width: 1)
                ),
                lit(6, width: 3, base: "h", signed: false),
                mux(
                  (
                      sig(:__VdfgRegularize_h6656821c_0_8, width: 1) &
                      sig(:__VdfgRegularize_h6656821c_0_9, width: 1)
                  ),
                  lit(7, width: 3, base: "h", signed: false),
                  mux(
                    sig(:__VdfgRegularize_h6656821c_0_8, width: 1),
                    lit(3, width: 3, base: "h", signed: false),
                    mux(
                      (
                          sig(:__VdfgRegularize_h6656821c_0_10, width: 1) &
                          sig(:__VdfgRegularize_h6656821c_0_7, width: 1)
                      ),
                      lit(4, width: 3, base: "h", signed: false),
                      mux(
                        sig(:__VdfgRegularize_h6656821c_0_10, width: 1),
                        lit(3, width: 3, base: "h", signed: false),
                        mux(
                          (
                              sig(:__VdfgRegularize_h6656821c_0_11, width: 1) &
                              sig(:__VdfgRegularize_h6656821c_0_7, width: 1)
                          ),
                          lit(7, width: 3, base: "h", signed: false),
                          mux(
                            sig(:__VdfgRegularize_h6656821c_0_11, width: 1),
                            lit(6, width: 3, base: "h", signed: false),
                            lit(2, width: 3, base: "h", signed: false)
                          )
                        )
                      )
                    )
                  )
                )
              ),
              lit(2, width: 3, base: "h", signed: false)
            )
          )
        )
      )
    )
  assign :CRx_DRx_condition,
    (
        sig(:dec_prefix_2byte, width: 1) &
        (
            lit(8, width: 6, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..2]
        )
    )
  assign :__VdfgRegularize_h6656821c_0_1,
    (
        sig(:dec_address_16bit, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_0, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_2,
    (
        lit(6, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[10..8]
    )
  assign :__VdfgRegularize_h6656821c_0_3,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[15..14]
    )
  assign :__VdfgRegularize_h6656821c_0_4,
    (
        lit(2, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[15..14]
    )
  assign :__VdfgRegularize_h6656821c_0_5,
    (
        sig(:dec_address_32bit, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_0, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_6,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[10..8]
    )
  assign :__VdfgRegularize_h6656821c_0_8,
    (
        sig(:__VdfgRegularize_h6656821c_0_5, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_7, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_9,
    (
        lit(5, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[18..16]
    )
  assign :__VdfgRegularize_h6656821c_0_10,
    (
        sig(:dec_address_32bit, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_3, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_7,
    (
        lit(4, width: 3, base: "h", signed: false) ==
        sig(:decoder, width: 96)[10..8]
    )
  assign :__VdfgRegularize_h6656821c_0_11,
    (
        sig(:dec_address_32bit, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_4, width: 1)
    )
  assign :is_prefix,
    (
        (
            lit(242, width: 8, base: "h", signed: false) ==
            sig(:decoder, width: 96)[7..0]
        ) |
        (
            (
                lit(243, width: 8, base: "h", signed: false) ==
                sig(:decoder, width: 96)[7..0]
            ) |
            (
                (
                    lit(240, width: 8, base: "h", signed: false) ==
                    sig(:decoder, width: 96)[7..0]
                ) |
                (
                    (
                        lit(38, width: 8, base: "h", signed: false) ==
                        sig(:decoder, width: 96)[7..0]
                    ) |
                    (
                        (
                            lit(46, width: 8, base: "h", signed: false) ==
                            sig(:decoder, width: 96)[7..0]
                        ) |
                        (
                            (
                                lit(54, width: 8, base: "h", signed: false) ==
                                sig(:decoder, width: 96)[7..0]
                            ) |
                            (
                                (
                                    lit(62, width: 8, base: "h", signed: false) ==
                                    sig(:decoder, width: 96)[7..0]
                                ) |
                                (
                                    (
                                        lit(100, width: 8, base: "h", signed: false) ==
                                        sig(:decoder, width: 96)[7..0]
                                    ) |
                                    (
                                        (
                                            lit(101, width: 8, base: "h", signed: false) ==
                                            sig(:decoder, width: 96)[7..0]
                                        ) |
                                        (
                                            (
                                                lit(102, width: 8, base: "h", signed: false) ==
                                                sig(:decoder, width: 96)[7..0]
                                            ) |
                                            (
                                                (
                                                    lit(103, width: 8, base: "h", signed: false) ==
                                                    sig(:decoder, width: 96)[7..0]
                                                ) |
                                                (
                                                    lit(15, width: 8, base: "h", signed: false) ==
                                                    sig(:decoder, width: 96)[7..0]
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
  assign :dec_prefix_group_1_lock,
    (
        sig(:prefix_group_1_lock, width: 1) |
        (
            (
              ~sig(:dec_prefix_2byte, width: 1)
            ) &
            (
                (
                    lit(67, width: 7, base: "h", signed: false) ==
                    sig(:decoder, width: 96)[7..1]
                ) &
                sig(:__VdfgRegularize_h6656821c_0_12, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h6656821c_0_12,
    (
        lit(3, width: 2, base: "h", signed: false) !=
        sig(:decoder, width: 96)[15..14]
    )
  assign :dec_prefix_group_2_seg,
    mux(
      (
          sig(:__VdfgRegularize_h6656821c_0_16, width: 1) &
          (
              sig(:dec_is_modregrm, width: 1) &
              (
                  (
                    ~sig(:CRx_DRx_condition, width: 1)
                  ) &
                  (
                      (
                          sig(:__VdfgRegularize_h6656821c_0_14, width: 1) &
                          sig(:__VdfgRegularize_h6656821c_0_6, width: 1)
                      ) |
                      (
                          (
                              sig(:dec_address_32bit, width: 1) &
                              (
                                  sig(:__VdfgRegularize_h6656821c_0_12, width: 1) &
                                  (
                                      sig(:__VdfgRegularize_h6656821c_0_7, width: 1) &
                                      (
                                          lit(4, width: 3, base: "h", signed: false) ==
                                          sig(:decoder, width: 96)[18..16]
                                      )
                                  )
                              )
                          ) |
                          (
                              (
                                  sig(:__VdfgRegularize_h6656821c_0_14, width: 1) &
                                  (
                                      sig(:__VdfgRegularize_h6656821c_0_7, width: 1) &
                                      sig(:__VdfgRegularize_h6656821c_0_9, width: 1)
                                  )
                              ) |
                              (
                                  (
                                      sig(:__VdfgRegularize_h6656821c_0_1, width: 1) &
                                      sig(:__VdfgRegularize_h6656821c_0_15, width: 1)
                                  ) |
                                  (
                                      sig(:dec_address_16bit, width: 1) &
                                      (
                                          sig(:__VdfgRegularize_h6656821c_0_13, width: 1) &
                                          (
                                              sig(:__VdfgRegularize_h6656821c_0_15, width: 1) |
                                              sig(:__VdfgRegularize_h6656821c_0_2, width: 1)
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
      lit(2, width: 3, base: "h", signed: false),
      mux(
        sig(:__VdfgRegularize_h6656821c_0_16, width: 1),
        lit(3, width: 3, base: "h", signed: false),
        sig(:prefix_group_2, width: 3)
      )
    )
  assign :__VdfgRegularize_h6656821c_0_16,
    (
        lit(7, width: 3, base: "h", signed: false) ==
        sig(:prefix_group_2, width: 3)
    )
  assign :__VdfgRegularize_h6656821c_0_14,
    (
        sig(:dec_address_32bit, width: 1) &
        sig(:__VdfgRegularize_h6656821c_0_13, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_15,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[10..9]
    )
  assign :__VdfgRegularize_h6656821c_0_13,
    (
        sig(:__VdfgRegularize_h6656821c_0_3, width: 1) |
        sig(:__VdfgRegularize_h6656821c_0_4, width: 1)
    )
  assign :__VdfgRegularize_h6656821c_0_0,
    (
        lit(0, width: 2, base: "h", signed: false) ==
        sig(:decoder, width: 96)[15..14]
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :dec_prefix_group_1_rep,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(242, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :dec_prefix_group_1_rep,
              lit(1, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:instr_prefix, width: 1) & (lit(243, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                assign(
                  :dec_prefix_group_1_rep,
                  lit(2, width: 2, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :dec_prefix_group_1_rep,
          lit(0, width: 2, base: "h", signed: false),
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
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :prefix_group_1_lock,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(240, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :prefix_group_1_lock,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :prefix_group_1_lock,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :prefix_group_2,
          lit(7, width: 3, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(38, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :prefix_group_2,
              lit(0, width: 3, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:instr_prefix, width: 1) & (lit(46, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                assign(
                  :prefix_group_2,
                  lit(1, width: 3, base: "h", signed: false),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt((sig(:instr_prefix, width: 1) & (lit(54, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                    assign(
                      :prefix_group_2,
                      lit(2, width: 3, base: "h", signed: false),
                      kind: :nonblocking
                    )
                    else_block do
                      if_stmt((sig(:instr_prefix, width: 1) & (lit(62, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                        assign(
                          :prefix_group_2,
                          lit(3, width: 3, base: "h", signed: false),
                          kind: :nonblocking
                        )
                        else_block do
                          if_stmt((sig(:instr_prefix, width: 1) & (lit(100, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                            assign(
                              :prefix_group_2,
                              lit(4, width: 3, base: "h", signed: false),
                              kind: :nonblocking
                            )
                            else_block do
                              if_stmt((sig(:instr_prefix, width: 1) & (lit(101, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
                                assign(
                                  :prefix_group_2,
                                  lit(5, width: 3, base: "h", signed: false),
                                  kind: :nonblocking
                                )
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
      else_block do
        assign(
          :prefix_group_2,
          lit(7, width: 3, base: "h", signed: false),
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
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :prefix_group_3,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(102, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :prefix_group_3,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :prefix_group_3,
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
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :prefix_group_4,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(103, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :prefix_group_4,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :prefix_group_4,
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :dec_prefix_2byte,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:instr_prefix, width: 1) & (lit(15, width: 8, base: "h", signed: false) == sig(:decoder, width: 96)[7..0]))) do
            assign(
              :dec_prefix_2byte,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :dec_prefix_2byte,
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
      if_stmt(sig(:instr_finished, width: 1)) do
        assign(
          :prefix_count,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:instr_prefix, width: 1)) do
            assign(
              :prefix_count,
              (
                  lit(1, width: 4, base: "h", signed: false) +
                  sig(:prefix_count, width: 4)
              ),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :prefix_count,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_7,
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
