# frozen_string_literal: true

class WriteDebug < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: write_debug

  def self._import_decl_kinds
    {
      __VdfgRegularize_h55f3f69c_0_0: :logic,
      __VdfgRegularize_h55f3f69c_0_1: :logic,
      __VdfgRegularize_h55f3f69c_0_2: :logic,
      __VdfgRegularize_h55f3f69c_0_3: :logic,
      _unused_ok: :wire,
      wr_code_linear: :wire,
      wr_debug_b0_code_trigger: :wire,
      wr_debug_b0_write_trigger: :reg,
      wr_debug_b1_code_trigger: :wire,
      wr_debug_b1_write_trigger: :reg,
      wr_debug_b2_code_trigger: :wire,
      wr_debug_b2_write_trigger: :reg,
      wr_debug_b3_code_trigger: :wire,
      wr_debug_b3_write_trigger: :reg,
      wr_debug_breakpoints_disabled: :wire,
      wr_debug_code: :wire,
      wr_debug_code_active: :wire,
      wr_debug_code_trigger: :wire,
      wr_debug_linear_last: :wire,
      wr_debug_linear_last_reg: :reg,
      wr_debug_read_current: :wire,
      wr_debug_step: :reg,
      wr_debug_write: :wire,
      write_address_last: :reg
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :dr0, width: 32
  input :dr1, width: 32
  input :dr2, width: 32
  input :dr3, width: 32
  input :dr7, width: 32
  input :debug_len0, width: 3
  input :debug_len1, width: 3
  input :debug_len2, width: 3
  input :debug_len3, width: 3
  input :rflag_to_reg
  input :tflag_to_reg
  input :wr_eip, width: 32
  input :cs_base, width: 32
  input :cs_limit, width: 32
  input :write_address, width: 32
  input :write_length, width: 3
  input :write_for_wr_ready
  input :w_load
  input :wr_finished
  input :wr_inhibit_interrupts_and_debug
  input :wr_debug_task_trigger
  input :wr_debug_trap_clear
  input :wr_string_in_progress
  input :exe_debug_read, width: 4
  output :wr_debug_prepare
  output :wr_debug_code_reg, width: 4
  output :wr_debug_write_reg, width: 4
  output :wr_debug_read_reg, width: 4
  output :wr_debug_step_reg
  output :wr_debug_task_reg

  # Signals

  signal :__VdfgRegularize_h55f3f69c_0_0
  signal :__VdfgRegularize_h55f3f69c_0_1
  signal :__VdfgRegularize_h55f3f69c_0_2
  signal :__VdfgRegularize_h55f3f69c_0_3
  signal :_unused_ok
  signal :wr_code_linear, width: 32
  signal :wr_debug_b0_code_trigger
  signal :wr_debug_b0_write_trigger
  signal :wr_debug_b1_code_trigger
  signal :wr_debug_b1_write_trigger
  signal :wr_debug_b2_code_trigger
  signal :wr_debug_b2_write_trigger
  signal :wr_debug_b3_code_trigger
  signal :wr_debug_b3_write_trigger
  signal :wr_debug_breakpoints_disabled
  signal :wr_debug_code, width: 4
  signal :wr_debug_code_active
  signal :wr_debug_code_trigger
  signal :wr_debug_linear_last, width: 32
  signal :wr_debug_linear_last_reg, width: 32
  signal :wr_debug_read_current, width: 4
  signal :wr_debug_step
  signal :wr_debug_write, width: 4
  signal :write_address_last, width: 32

  # Assignments

  assign :wr_debug_breakpoints_disabled,
    (
        lit(0, width: 8, base: "h", signed: false) ==
        sig(:dr7, width: 32)[7..0]
    )
  assign :wr_debug_read_current,
    mux(
      sig(:wr_debug_breakpoints_disabled, width: 1),
      lit(0, width: 4, base: "h", signed: false),
      sig(:exe_debug_read, width: 4)
    )
  assign :wr_debug_write,
    (
        mux(
          sig(:wr_debug_breakpoints_disabled, width: 1),
          lit(0, width: 4, base: "h", signed: false),
          sig(:wr_debug_b3_write_trigger, width: 1).concat(
            sig(:wr_debug_b2_write_trigger, width: 1).concat(
              sig(:wr_debug_b1_write_trigger, width: 1).concat(
                sig(:wr_debug_b0_write_trigger, width: 1)
              )
            )
          )
        ) |
        sig(:wr_debug_write_reg, width: 4)
    )
  assign :wr_code_linear,
    (
        sig(:cs_base, width: 32) +
        sig(:wr_eip, width: 32)
    )
  assign :wr_debug_code_trigger,
    (
        sig(:wr_finished, width: 1) &
        (
            (
              ~(
                  sig(:wr_debug_breakpoints_disabled, width: 1) |
                  sig(:wr_string_in_progress, width: 1)
              )
            ) &
            (
                (
                  ~sig(:rflag_to_reg, width: 1)
                ) &
                (
                    sig(:wr_eip, width: 32) <=
                    sig(:cs_limit, width: 32)
                )
            )
        )
    )
  assign :wr_debug_b0_code_trigger,
    (
        sig(:wr_debug_code_trigger, width: 1) &
        (
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[17..16]
            ) &
            (
                sig(:dr0, width: 32)[31..3].concat(
                  (
                      sig(:dr0, width: 32)[2..0] &
                      sig(:debug_len0, width: 3)
                  )
                ) ==
                sig(:wr_code_linear, width: 32)[31..3].concat(
                (
                    sig(:wr_code_linear, width: 32)[2..0] &
                    sig(:debug_len0, width: 3)
                )
              )
            )
        )
    )
  assign :wr_debug_b1_code_trigger,
    (
        sig(:wr_debug_code_trigger, width: 1) &
        (
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[21..20]
            ) &
            (
                sig(:dr1, width: 32)[31..3].concat(
                  (
                      sig(:dr1, width: 32)[2..0] &
                      sig(:debug_len1, width: 3)
                  )
                ) ==
                sig(:wr_code_linear, width: 32)[31..3].concat(
                (
                    sig(:wr_code_linear, width: 32)[2..0] &
                    sig(:debug_len1, width: 3)
                )
              )
            )
        )
    )
  assign :wr_debug_b2_code_trigger,
    (
        sig(:wr_debug_code_trigger, width: 1) &
        (
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[25..24]
            ) &
            (
                sig(:dr2, width: 32)[31..3].concat(
                  (
                      sig(:dr2, width: 32)[2..0] &
                      sig(:debug_len2, width: 3)
                  )
                ) ==
                sig(:wr_code_linear, width: 32)[31..3].concat(
                (
                    sig(:wr_code_linear, width: 32)[2..0] &
                    sig(:debug_len2, width: 3)
                )
              )
            )
        )
    )
  assign :wr_debug_b3_code_trigger,
    (
        sig(:wr_debug_code_trigger, width: 1) &
        (
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[29..28]
            ) &
            (
                sig(:dr3, width: 32)[31..3].concat(
                  (
                      sig(:dr3, width: 32)[2..0] &
                      sig(:debug_len3, width: 3)
                  )
                ) ==
                sig(:wr_code_linear, width: 32)[31..3].concat(
                (
                    sig(:wr_code_linear, width: 32)[2..0] &
                    sig(:debug_len3, width: 3)
                )
              )
            )
        )
    )
  assign :wr_debug_code_active,
    (
        (
            sig(:wr_debug_b3_code_trigger, width: 1) &
            sig(:__VdfgRegularize_h55f3f69c_0_0, width: 1)
        ) |
        (
            (
                sig(:wr_debug_b2_code_trigger, width: 1) &
                sig(:__VdfgRegularize_h55f3f69c_0_1, width: 1)
            ) |
            (
                (
                    sig(:wr_debug_b1_code_trigger, width: 1) &
                    sig(:__VdfgRegularize_h55f3f69c_0_2, width: 1)
                ) |
                (
                    sig(:wr_debug_b0_code_trigger, width: 1) &
                    sig(:__VdfgRegularize_h55f3f69c_0_3, width: 1)
                )
            )
        )
    )
  assign :__VdfgRegularize_h55f3f69c_0_0,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:dr7, width: 32)[7..6]
    )
  assign :__VdfgRegularize_h55f3f69c_0_1,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:dr7, width: 32)[5..4]
    )
  assign :__VdfgRegularize_h55f3f69c_0_2,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:dr7, width: 32)[3..2]
    )
  assign :__VdfgRegularize_h55f3f69c_0_3,
    (
        lit(0, width: 2, base: "h", signed: false) !=
        sig(:dr7, width: 32)[1..0]
    )
  assign :wr_debug_code,
    mux(
      sig(:wr_debug_code_active, width: 1),
      sig(:wr_debug_b3_code_trigger, width: 1).concat(
        sig(:wr_debug_b2_code_trigger, width: 1).concat(
          sig(:wr_debug_b1_code_trigger, width: 1).concat(
            sig(:wr_debug_b0_code_trigger, width: 1)
          )
        )
      ),
      lit(0, width: 4, base: "h", signed: false)
    )
  assign :wr_debug_prepare,
    (
        sig(:wr_finished, width: 1) &
        (
            (
              ~sig(:wr_inhibit_interrupts_and_debug, width: 1)
            ) &
            (
                sig(:wr_debug_task_trigger, width: 1) |
                (
                    sig(:wr_debug_step, width: 1) |
                    (
                        sig(:wr_debug_code_active, width: 1) |
                        (
                            (
                                (
                                    sig(:wr_debug_read_reg, width: 4)[3] &
                                    sig(:__VdfgRegularize_h55f3f69c_0_0, width: 1)
                                ) |
                                (
                                    sig(:wr_debug_read_reg, width: 4)[2] &
                                    sig(:__VdfgRegularize_h55f3f69c_0_1, width: 1)
                                )
                            ) |
                            (
                                (
                                    (
                                        sig(:wr_debug_read_reg, width: 4)[1] &
                                        sig(:__VdfgRegularize_h55f3f69c_0_2, width: 1)
                                    ) |
                                    (
                                        sig(:wr_debug_read_reg, width: 4)[0] &
                                        sig(:__VdfgRegularize_h55f3f69c_0_3, width: 1)
                                    )
                                ) |
                                (
                                    (
                                        sig(:wr_debug_write, width: 4)[3] &
                                        sig(:__VdfgRegularize_h55f3f69c_0_0, width: 1)
                                    ) |
                                    (
                                        (
                                            sig(:wr_debug_write, width: 4)[2] &
                                            sig(:__VdfgRegularize_h55f3f69c_0_1, width: 1)
                                        ) |
                                        (
                                            (
                                                sig(:wr_debug_write, width: 4)[1] &
                                                sig(:__VdfgRegularize_h55f3f69c_0_2, width: 1)
                                            ) |
                                            (
                                                sig(:wr_debug_write, width: 4)[0] &
                                                sig(:__VdfgRegularize_h55f3f69c_0_3, width: 1)
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
  assign :wr_debug_linear_last,
    (
        (
            sig(:write_address, width: 32) +
            lit(0, width: 29, base: "d", signed: false).concat(
            sig(:write_length, width: 3)
          )
        ) -
        lit(1, width: 32, base: "h", signed: false)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:wr_inhibit_interrupts_and_debug, width: 1) | sig(:wr_debug_prepare, width: 1))) do
        assign(
          :wr_debug_read_reg,
          sig(:wr_debug_read_reg, width: 4),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:wr_debug_trap_clear, width: 1)) do
            assign(
              :wr_debug_read_reg,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:wr_finished, width: 1) & sig(:w_load, width: 1))) do
                assign(
                  :wr_debug_read_reg,
                  sig(:wr_debug_read_current, width: 4),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt((sig(:wr_finished, width: 1) & (~sig(:w_load, width: 1)))) do
                    assign(
                      :wr_debug_read_reg,
                      lit(0, width: 4, base: "h", signed: false),
                      kind: :nonblocking
                    )
                    else_block do
                      if_stmt(sig(:w_load, width: 1)) do
                        assign(
                          :wr_debug_read_reg,
                          (
                              sig(:wr_debug_read_reg, width: 4) |
                              sig(:wr_debug_read_current, width: 4)
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
          :wr_debug_read_reg,
          lit(0, width: 4, base: "h", signed: false),
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
    assign(
      :wr_debug_linear_last_reg,
      mux(
        sig(:rst_n, width: 1),
        sig(:wr_debug_linear_last, width: 32),
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
      :write_address_last,
      mux(
        sig(:rst_n, width: 1),
        sig(:write_address, width: 32),
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
      :wr_debug_b0_write_trigger,
      (
          sig(:rst_n, width: 1) &
          (
              (
                  (
                      sig(:write_for_wr_ready, width: 1) &
                      sig(:dr7, width: 32)[16]
                  ) &
                  (
                      sig(:write_address_last, width: 32) <=
                      sig(:dr0, width: 32)[31..3].concat(
                      (
                          sig(:dr0, width: 32)[2..0] |
                          (
                            ~sig(:debug_len0, width: 3)
                          )
                      )
                    )
                  )
              ) &
              (
                  sig(:wr_debug_linear_last_reg, width: 32) >=
                  sig(:dr0, width: 32)[31..3].concat(
                  (
                      sig(:dr0, width: 32)[2..0] &
                      sig(:debug_len0, width: 3)
                  )
                )
              )
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
      :wr_debug_b1_write_trigger,
      (
          sig(:rst_n, width: 1) &
          (
              (
                  (
                      sig(:write_for_wr_ready, width: 1) &
                      sig(:dr7, width: 32)[20]
                  ) &
                  (
                      sig(:write_address_last, width: 32) <=
                      sig(:dr1, width: 32)[31..3].concat(
                      (
                          sig(:dr1, width: 32)[2..0] |
                          (
                            ~sig(:debug_len1, width: 3)
                          )
                      )
                    )
                  )
              ) &
              (
                  sig(:wr_debug_linear_last_reg, width: 32) >=
                  sig(:dr1, width: 32)[31..3].concat(
                  (
                      sig(:dr1, width: 32)[2..0] &
                      sig(:debug_len1, width: 3)
                  )
                )
              )
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
      :wr_debug_b2_write_trigger,
      (
          sig(:rst_n, width: 1) &
          (
              (
                  (
                      sig(:write_for_wr_ready, width: 1) &
                      sig(:dr7, width: 32)[24]
                  ) &
                  (
                      sig(:write_address_last, width: 32) <=
                      sig(:dr2, width: 32)[31..3].concat(
                      (
                          sig(:dr2, width: 32)[2..0] |
                          (
                            ~sig(:debug_len2, width: 3)
                          )
                      )
                    )
                  )
              ) &
              (
                  sig(:wr_debug_linear_last_reg, width: 32) >=
                  sig(:dr2, width: 32)[31..3].concat(
                  (
                      sig(:dr2, width: 32)[2..0] &
                      sig(:debug_len2, width: 3)
                  )
                )
              )
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
      :wr_debug_b3_write_trigger,
      (
          sig(:rst_n, width: 1) &
          (
              (
                  (
                      sig(:write_for_wr_ready, width: 1) &
                      sig(:dr7, width: 32)[28]
                  ) &
                  (
                      sig(:write_address_last, width: 32) <=
                      sig(:dr3, width: 32)[31..3].concat(
                      (
                          sig(:dr3, width: 32)[2..0] |
                          (
                            ~sig(:debug_len3, width: 3)
                          )
                      )
                    )
                  )
              ) &
              (
                  sig(:wr_debug_linear_last_reg, width: 32) >=
                  sig(:dr3, width: 32)[31..3].concat(
                  (
                      sig(:dr3, width: 32)[2..0] &
                      sig(:debug_len3, width: 3)
                  )
                )
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:wr_inhibit_interrupts_and_debug, width: 1)) do
        assign(
          :wr_debug_write_reg,
          sig(:wr_debug_write_reg, width: 4),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:wr_debug_trap_clear, width: 1)) do
            assign(
              :wr_debug_write_reg,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((sig(:write_for_wr_ready, width: 1) | sig(:wr_debug_prepare, width: 1))) do
                assign(
                  :wr_debug_write_reg,
                  sig(:wr_debug_write, width: 4),
                  kind: :nonblocking
                )
                else_block do
                  if_stmt(sig(:wr_finished, width: 1)) do
                    assign(
                      :wr_debug_write_reg,
                      lit(0, width: 4, base: "h", signed: false),
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
          :wr_debug_write_reg,
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
      if_stmt(sig(:wr_debug_prepare, width: 1)) do
        assign(
          :wr_debug_code_reg,
          sig(:wr_debug_code, width: 4),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_debug_code_reg,
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
      if_stmt(sig(:wr_debug_prepare, width: 1)) do
        assign(
          :wr_debug_step_reg,
          sig(:wr_debug_step, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_debug_step_reg,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:wr_debug_trap_clear, width: 1)) do
        assign(
          :wr_debug_step,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:wr_finished, width: 1)) do
            assign(
              :wr_debug_step,
              sig(:tflag_to_reg, width: 1),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :wr_debug_step,
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
      if_stmt(sig(:wr_debug_prepare, width: 1)) do
        assign(
          :wr_debug_task_reg,
          sig(:wr_debug_task_trigger, width: 1),
          kind: :nonblocking
        )
      end
      else_block do
        assign(
          :wr_debug_task_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  process :initial_block_12,
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
