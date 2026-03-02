# frozen_string_literal: true

class ExecuteDivide < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute_divide

  def self._import_decl_kinds
    {
      __VdfgRegularize_hd2385e0e_0_0: :logic,
      __VdfgRegularize_hd2385e0e_0_1: :logic,
      __VdfgRegularize_hd2385e0e_0_2: :logic,
      __VdfgRegularize_hd2385e0e_0_3: :logic,
      __VdfgRegularize_hd2385e0e_0_4: :logic,
      __VdfgRegularize_hd2385e0e_0_5: :logic,
      __VdfgRegularize_hd2385e0e_0_7: :logic,
      __VdfgRegularize_hd2385e0e_0_8: :logic,
      _unused_ok: :wire,
      div_counter: :reg,
      div_denom: :wire,
      div_denom_neg: :wire,
      div_diff: :wire,
      div_dividend: :reg,
      div_divisor: :reg,
      div_numer: :wire,
      div_one_time: :reg,
      div_overflow: :wire,
      div_overflow_waiting: :reg,
      div_quotient: :reg,
      div_quotient_neg: :wire,
      div_remainder_neg: :wire,
      div_start: :wire,
      div_working: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :exe_reset
  input :exe_ready
  input :exe_is_8bit
  input :exe_operand_16bit
  input :exe_operand_32bit
  input :exe_cmd, width: 7
  input :eax, width: 32
  input :edx, width: 32
  input :src, width: 32
  output :div_busy
  output :exe_div_exception
  output :div_result_quotient, width: 32
  output :div_result_remainder, width: 32

  # Signals

  signal :__VdfgRegularize_hd2385e0e_0_0
  signal :__VdfgRegularize_hd2385e0e_0_1
  signal :__VdfgRegularize_hd2385e0e_0_2
  signal :__VdfgRegularize_hd2385e0e_0_3
  signal :__VdfgRegularize_hd2385e0e_0_4
  signal :__VdfgRegularize_hd2385e0e_0_5
  signal :__VdfgRegularize_hd2385e0e_0_7
  signal :__VdfgRegularize_hd2385e0e_0_8
  signal :_unused_ok
  signal :div_counter, width: 6
  signal :div_denom, width: 33
  signal :div_denom_neg, width: 33
  signal :div_diff, width: 65
  signal :div_dividend, width: 64
  signal :div_divisor, width: 64
  signal :div_numer, width: 65
  signal :div_one_time
  signal :div_overflow
  signal :div_overflow_waiting
  signal :div_quotient, width: 33
  signal :div_quotient_neg
  signal :div_remainder_neg
  signal :div_start
  signal :div_working

  # Assignments

  assign :exe_div_exception,
    (
        (
            sig(:__VdfgRegularize_hd2385e0e_0_1, width: 1) &
            (
                sig(:__VdfgRegularize_hd2385e0e_0_5, width: 1) &
                (
                    (
                        sig(:exe_is_8bit, width: 1) &
                        (
                            lit(0, width: 8, base: "h", signed: false) ==
                            sig(:src, width: 32)[7..0]
                        )
                    ) |
                    (
                        (
                            sig(:exe_operand_16bit, width: 1) &
                            (
                                lit(0, width: 16, base: "h", signed: false) ==
                                sig(:src, width: 32)[15..0]
                            )
                        ) |
                        (
                            sig(:exe_operand_32bit, width: 1) &
                            (
                                lit(0, width: 32, base: "h", signed: false) ==
                                sig(:src, width: 32)
                            )
                        )
                    )
                )
            )
        ) |
        (
            (
                sig(:__VdfgRegularize_hd2385e0e_0_1, width: 1) &
                (
                    sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
                    (
                        (
                            sig(:exe_is_8bit, width: 1) &
                            (
                                lit(32768, width: 16, base: "h", signed: false) ==
                                sig(:eax, width: 32)[15..0]
                            )
                        ) |
                        (
                            (
                              ~sig(:exe_is_8bit, width: 1)
                            ) &
                            (
                                (
                                    sig(:exe_operand_16bit, width: 1) &
                                    (
                                        (
                                            lit(32768, width: 16, base: "h", signed: false) ==
                                            sig(:edx, width: 32)[15..0]
                                        ) &
                                        (
                                            lit(0, width: 16, base: "h", signed: false) ==
                                            sig(:eax, width: 32)[15..0]
                                        )
                                    )
                                ) |
                                (
                                    sig(:exe_operand_32bit, width: 1) &
                                    (
                                        (
                                            lit(2147483648, width: 32, base: "h", signed: false) ==
                                            sig(:edx, width: 32)
                                        ) &
                                        (
                                            lit(0, width: 32, base: "h", signed: false) ==
                                            sig(:eax, width: 32)
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            ) |
            sig(:div_overflow_waiting, width: 1)
        )
    )
  assign :__VdfgRegularize_hd2385e0e_0_1,
    (
        lit(0, width: 6, base: "h", signed: false) ==
        sig(:div_counter, width: 6)
    )
  assign :__VdfgRegularize_hd2385e0e_0_5,
    (
        sig(:__VdfgRegularize_hd2385e0e_0_3, width: 1) |
        sig(:__VdfgRegularize_hd2385e0e_0_4, width: 1)
    )
  assign :__VdfgRegularize_hd2385e0e_0_2,
    (
        lit(43, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :div_start,
    (
        (
          ~sig(:exe_div_exception, width: 1)
        ) &
        (
            sig(:__VdfgRegularize_hd2385e0e_0_0, width: 1) &
            (
                sig(:__VdfgRegularize_hd2385e0e_0_1, width: 1) &
                sig(:__VdfgRegularize_hd2385e0e_0_5, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_hd2385e0e_0_0,
    (
      ~sig(:div_one_time, width: 1)
    )
  assign :div_working,
    (
        lit(1, width: 6, base: "h", signed: false) <
        sig(:div_counter, width: 6)
    )
  assign :div_busy,
    (
        sig(:__VdfgRegularize_hd2385e0e_0_0, width: 1) |
        (
            lit(0, width: 6, base: "h", signed: false) !=
            sig(:div_counter, width: 6)
        )
    )
  assign :div_numer,
    mux(
      sig(:__VdfgRegularize_hd2385e0e_0_4, width: 1),
      lit(0, width: 57, base: "d", signed: false).concat(
        sig(:eax, width: 32)[7..0]
      ),
      mux(
        sig(:exe_is_8bit, width: 1),
        (
            sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
            sig(:eax, width: 32)[15]
        ).replicate(
          lit(49, width: 32, base: "h", signed: true)
        ).concat(
          sig(:eax, width: 32)[15..0]
        ),
        mux(
          sig(:exe_operand_16bit, width: 1),
          (
              sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
              sig(:edx, width: 32)[15]
          ).replicate(
            lit(33, width: 32, base: "h", signed: true)
          ).concat(
            sig(:edx, width: 32)[15..0].concat(
              sig(:eax, width: 32)[15..0]
            )
          ),
          (
              sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
              sig(:edx, width: 32)[31]
          ).concat(
            sig(:edx, width: 32).concat(
              sig(:eax, width: 32)
            )
          )
        )
      )
    )
  assign :__VdfgRegularize_hd2385e0e_0_4,
    (
        lit(32, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :div_denom,
    mux(
      sig(:exe_is_8bit, width: 1),
      (
          sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
          sig(:src, width: 32)[7]
      ).replicate(
        lit(25, width: 32, base: "h", signed: true)
      ).concat(
        sig(:src, width: 32)[7..0]
      ),
      mux(
        sig(:exe_operand_16bit, width: 1),
        (
            sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
            sig(:src, width: 32)[15]
        ).replicate(
          lit(17, width: 32, base: "h", signed: true)
        ).concat(
          sig(:src, width: 32)[15..0]
        ),
        (
            sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
            sig(:src, width: 32)[31]
        ).concat(
          sig(:src, width: 32)
        )
      )
    )
  assign :div_denom_neg,
    (
      -sig(:div_denom, width: 33)
    )
  assign :div_diff,
    (
        lit(0, width: 1, base: "d", signed: false).concat(
          sig(:div_dividend, width: 64)
        ) -
        lit(0, width: 1, base: "d", signed: false).concat(
        sig(:div_divisor, width: 64)
      )
    )
  assign :div_quotient_neg,
    (
        sig(:div_remainder_neg, width: 1) ^
        sig(:div_denom, width: 33)[32]
    )
  assign :div_remainder_neg,
    sig(:div_numer, width: 65)[64]
  assign :div_overflow,
    (
        sig(:__VdfgRegularize_hd2385e0e_0_3, width: 1) &
        (
            (
                sig(:exe_is_8bit, width: 1) &
                (
                    (
                        sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
                        (
                            (
                                sig(:__VdfgRegularize_hd2385e0e_0_7, width: 1) &
                                (
                                    lit(0, width: 2, base: "h", signed: false) !=
                                    sig(:div_quotient, width: 33)[8..7]
                                )
                            ) |
                            (
                                sig(:div_quotient_neg, width: 1) &
                                (
                                    lit(128, width: 9, base: "h", signed: false) <
                                    sig(:div_quotient, width: 33)[8..0]
                                )
                            )
                        )
                    ) |
                    (
                        sig(:__VdfgRegularize_hd2385e0e_0_8, width: 1) &
                        sig(:div_quotient, width: 33)[8]
                    )
                )
            ) |
            (
                (
                    sig(:exe_operand_16bit, width: 1) &
                    (
                        (
                            sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
                            (
                                (
                                    sig(:__VdfgRegularize_hd2385e0e_0_7, width: 1) &
                                    (
                                        lit(0, width: 2, base: "h", signed: false) !=
                                        sig(:div_quotient, width: 33)[16..15]
                                    )
                                ) |
                                (
                                    sig(:div_quotient_neg, width: 1) &
                                    (
                                        lit(32768, width: 17, base: "h", signed: false) <
                                        sig(:div_quotient, width: 33)[16..0]
                                    )
                                )
                            )
                        ) |
                        (
                            sig(:__VdfgRegularize_hd2385e0e_0_8, width: 1) &
                            sig(:div_quotient, width: 33)[16]
                        )
                    )
                ) |
                (
                    sig(:exe_operand_32bit, width: 1) &
                    (
                        (
                            sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) &
                            (
                                (
                                    sig(:__VdfgRegularize_hd2385e0e_0_7, width: 1) &
                                    (
                                        lit(0, width: 2, base: "h", signed: false) !=
                                        sig(:div_quotient, width: 33)[32..31]
                                    )
                                ) |
                                (
                                    sig(:div_quotient_neg, width: 1) &
                                    (
                                        lit(2147483648, width: 33, base: "h", signed: false) <
                                        sig(:div_quotient, width: 33)
                                    )
                                )
                            )
                        ) |
                        (
                            sig(:__VdfgRegularize_hd2385e0e_0_8, width: 1) &
                            sig(:div_quotient, width: 33)[32]
                        )
                    )
                )
            )
        )
    )
  assign :__VdfgRegularize_hd2385e0e_0_3,
    (
        sig(:__VdfgRegularize_hd2385e0e_0_2, width: 1) |
        (
            lit(42, width: 7, base: "h", signed: false) ==
            sig(:exe_cmd, width: 7)
        )
    )
  assign :__VdfgRegularize_hd2385e0e_0_7,
    (
      ~sig(:div_quotient_neg, width: 1)
    )
  assign :__VdfgRegularize_hd2385e0e_0_8,
    (
        lit(43, width: 7, base: "h", signed: false) !=
        sig(:exe_cmd, width: 7)
    )
  assign :div_result_quotient,
    mux(
      sig(:div_quotient_neg, width: 1),
      (
        -sig(:div_quotient, width: 33)[31..0]
      ),
      sig(:div_quotient, width: 33)[31..0]
    )
  assign :div_result_remainder,
    mux(
      sig(:div_remainder_neg, width: 1),
      (
        -sig(:div_dividend, width: 64)[31..0]
      ),
      sig(:div_dividend, width: 64)[31..0]
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :div_one_time,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:exe_ready, width: 1)) do
            assign(
              :div_one_time,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((lit(1, width: 6, base: "h", signed: false) < sig(:div_counter, width: 6))) do
                assign(
                  :div_one_time,
                  lit(1, width: 1, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :div_one_time,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :div_overflow_waiting,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(((lit(1, width: 6, base: "h", signed: false) == sig(:div_counter, width: 6)) & sig(:div_overflow, width: 1))) do
            assign(
              :div_overflow_waiting,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :div_overflow_waiting,
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
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :div_counter,
          lit(0, width: 6, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:div_start, width: 1) & sig(:exe_is_8bit, width: 1))) do
            assign(
              :div_counter,
              lit(10, width: 6, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:div_start, width: 1) & sig(:exe_operand_16bit, width: 1))) do
                assign(
                  :div_counter,
                  lit(18, width: 6, base: "h", signed: false),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt((sig(:div_start, width: 1) & sig(:exe_operand_32bit, width: 1))) do
                    assign(
                      :div_counter,
                      lit(34, width: 6, base: "h", signed: false),
                      kind: :nonblocking
                    )
                    else_block do
                      if_stmt((lit(0, width: 6, base: "h", signed: false) != sig(:div_counter, width: 6))) do
                        assign(
                          :div_counter,
                          (
                              sig(:div_counter, width: 6) -
                              lit(1, width: 6, base: "h", signed: false)
                          ),
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
      else_block do
        assign(
          :div_counter,
          lit(0, width: 6, base: "h", signed: false),
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
      if_stmt((sig(:div_start, width: 1) & (~sig(:div_numer, width: 65)[64]))) do
        assign(
          :div_dividend,
          sig(:div_numer, width: 65)[63..0],
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:div_start, width: 1) & sig(:div_numer, width: 65)[64])) do
            assign(
              :div_dividend,
              (
                -sig(:div_numer, width: 65)[63..0]
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:div_working, width: 1) & (~sig(:div_diff, width: 65)[64]))) do
                assign(
                  :div_dividend,
                  sig(:div_diff, width: 65)[63..0],
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :div_dividend,
          lit(0, width: 64, base: "h", signed: false),
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
      if_stmt(((sig(:div_start, width: 1) & (~sig(:div_denom, width: 33)[32])) & sig(:exe_is_8bit, width: 1))) do
        assign(
          :div_divisor,
          lit(0, width: 48, base: "d", signed: false).concat(
            sig(:div_denom, width: 33)[7..0]
          ).concat(
            lit(0, width: 8, base: "h", signed: false)
          ),
          kind: :nonblocking
        )
        else_block do
          if_stmt(((sig(:div_start, width: 1) & sig(:div_denom, width: 33)[32]) & sig(:exe_is_8bit, width: 1))) do
            assign(
              :div_divisor,
              lit(0, width: 48, base: "d", signed: false).concat(
                sig(:div_denom_neg, width: 33)[7..0]
              ).concat(
                lit(0, width: 8, base: "h", signed: false)
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt(((sig(:div_start, width: 1) & (~sig(:div_denom, width: 33)[32])) & sig(:exe_operand_16bit, width: 1))) do
                assign(
                  :div_divisor,
                  lit(0, width: 32, base: "d", signed: false).concat(
                    sig(:div_denom, width: 33)[15..0]
                  ).concat(
                    lit(0, width: 16, base: "h", signed: false)
                  ),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt(((sig(:div_start, width: 1) & sig(:div_denom, width: 33)[32]) & sig(:exe_operand_16bit, width: 1))) do
                    assign(
                      :div_divisor,
                      lit(0, width: 32, base: "d", signed: false).concat(
                        sig(:div_denom_neg, width: 33)[15..0]
                      ).concat(
                        lit(0, width: 16, base: "h", signed: false)
                      ),
                      kind: :nonblocking
                    )
                    else_block do
                      if_stmt(((sig(:div_start, width: 1) & (~sig(:div_denom, width: 33)[32])) & sig(:exe_operand_32bit, width: 1))) do
                        assign(
                          :div_divisor,
                          sig(:div_denom, width: 33)[31..0].concat(
                            lit(0, width: 32, base: "h", signed: false)
                          ),
                          kind: :nonblocking
                        )
                        else_block do
                          if_stmt(((sig(:div_start, width: 1) & sig(:div_denom, width: 33)[32]) & sig(:exe_operand_32bit, width: 1))) do
                            assign(
                              :div_divisor,
                              sig(:div_denom_neg, width: 33)[31..0].concat(
                                lit(0, width: 32, base: "h", signed: false)
                              ),
                              kind: :nonblocking
                            )
                            else_block do
                              if_stmt(sig(:div_working, width: 1)) do
                                assign(
                                  :div_divisor,
                                  lit(0, width: 1, base: "d", signed: false).concat(
                                    sig(:div_divisor, width: 64)[63..1]
                                  ),
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
          :div_divisor,
          lit(0, width: 64, base: "h", signed: false),
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
      if_stmt(sig(:div_start, width: 1)) do
        assign(
          :div_quotient,
          lit(0, width: 33, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:div_working, width: 1) & (~sig(:div_diff, width: 65)[64]))) do
            assign(
              :div_quotient,
              sig(:div_quotient, width: 33)[31..0].concat(
                lit(1, width: 1, base: "h", signed: false)
              ),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:div_working, width: 1) & sig(:div_diff, width: 65)[64])) do
                assign(
                  :div_quotient,
                  sig(:div_quotient, width: 33)[31..0].concat(
                    lit(0, width: 1, base: "h", signed: false)
                  ),
                  kind: :nonblocking
                )
              end
            end
          end
        end
      end
      else_block do
        assign(
          :div_quotient,
          lit(0, width: 33, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
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
