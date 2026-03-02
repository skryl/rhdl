# frozen_string_literal: true

class ReadDebug < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: read_debug

  def self._import_decl_kinds
    {
      _unused_ok: :wire,
      rd_debug_b0_reg: :reg,
      rd_debug_b0_trigger: :wire,
      rd_debug_b1_reg: :reg,
      rd_debug_b1_trigger: :wire,
      rd_debug_b2_reg: :reg,
      rd_debug_b2_trigger: :wire,
      rd_debug_b3_reg: :reg,
      rd_debug_b3_trigger: :wire,
      rd_debug_length: :reg,
      rd_debug_linear: :reg,
      rd_debug_linear_last: :wire,
      rd_debug_trigger: :reg
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
  input :rd_ready
  input :read_do
  input :read_address, width: 32
  input :read_length, width: 4
  output :rd_debug_read, width: 4

  # Signals

  signal :_unused_ok
  signal :rd_debug_b0_reg
  signal :rd_debug_b0_trigger
  signal :rd_debug_b1_reg
  signal :rd_debug_b1_trigger
  signal :rd_debug_b2_reg
  signal :rd_debug_b2_trigger
  signal :rd_debug_b3_reg
  signal :rd_debug_b3_trigger
  signal :rd_debug_length, width: 4
  signal :rd_debug_linear, width: 32
  signal :rd_debug_linear_last, width: 32
  signal :rd_debug_trigger

  # Assignments

  assign :rd_debug_linear_last,
    (
        (
            sig(:rd_debug_linear, width: 32) +
            lit(0, width: 28, base: "d", signed: false).concat(
            sig(:rd_debug_length, width: 4)
          )
        ) -
        lit(1, width: 32, base: "h", signed: false)
    )
  assign :rd_debug_read,
    (
        sig(:rd_debug_b3_trigger, width: 1) |
        sig(:rd_debug_b3_reg, width: 1)
    ).concat(
      (
          sig(:rd_debug_b2_trigger, width: 1) |
          sig(:rd_debug_b2_reg, width: 1)
      ).concat(
        (
            sig(:rd_debug_b1_trigger, width: 1) |
            sig(:rd_debug_b1_reg, width: 1)
        ).concat(
          (
              sig(:rd_debug_b0_trigger, width: 1) |
              sig(:rd_debug_b0_reg, width: 1)
          )
        )
      )
    )
  assign :rd_debug_b3_trigger,
    (
        sig(:rd_debug_trigger, width: 1) &
        (
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[29..28]
            ) &
            (
                (
                    sig(:rd_debug_linear, width: 32) <=
                    sig(:dr3, width: 32)[31..3].concat(
                    (
                        (
                          ~sig(:debug_len3, width: 3)
                        ) |
                        sig(:dr3, width: 32)[2..0]
                    )
                  )
                ) &
                (
                    sig(:rd_debug_linear_last, width: 32) >=
                    sig(:dr3, width: 32)[31..3].concat(
                    (
                        sig(:dr3, width: 32)[2..0] &
                        sig(:debug_len3, width: 3)
                    )
                  )
                )
            )
        )
    )
  assign :rd_debug_b2_trigger,
    (
        sig(:rd_debug_trigger, width: 1) &
        (
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[25..24]
            ) &
            (
                (
                    sig(:rd_debug_linear, width: 32) <=
                    sig(:dr2, width: 32)[31..3].concat(
                    (
                        (
                          ~sig(:debug_len2, width: 3)
                        ) |
                        sig(:dr2, width: 32)[2..0]
                    )
                  )
                ) &
                (
                    sig(:rd_debug_linear_last, width: 32) >=
                    sig(:dr2, width: 32)[31..3].concat(
                    (
                        sig(:dr2, width: 32)[2..0] &
                        sig(:debug_len2, width: 3)
                    )
                  )
                )
            )
        )
    )
  assign :rd_debug_b1_trigger,
    (
        sig(:rd_debug_trigger, width: 1) &
        (
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[21..20]
            ) &
            (
                (
                    sig(:rd_debug_linear, width: 32) <=
                    sig(:dr1, width: 32)[31..3].concat(
                    (
                        (
                          ~sig(:debug_len1, width: 3)
                        ) |
                        sig(:dr1, width: 32)[2..0]
                    )
                  )
                ) &
                (
                    sig(:rd_debug_linear_last, width: 32) >=
                    sig(:dr1, width: 32)[31..3].concat(
                    (
                        sig(:dr1, width: 32)[2..0] &
                        sig(:debug_len1, width: 3)
                    )
                  )
                )
            )
        )
    )
  assign :rd_debug_b0_trigger,
    (
        sig(:rd_debug_trigger, width: 1) &
        (
            (
                lit(3, width: 2, base: "h", signed: false) ==
                sig(:dr7, width: 32)[17..16]
            ) &
            (
                (
                    sig(:rd_debug_linear, width: 32) <=
                    sig(:dr0, width: 32)[31..3].concat(
                    (
                        (
                          ~sig(:debug_len0, width: 3)
                        ) |
                        sig(:dr0, width: 32)[2..0]
                    )
                  )
                ) &
                (
                    sig(:rd_debug_linear_last, width: 32) >=
                    sig(:dr0, width: 32)[31..3].concat(
                    (
                        sig(:dr0, width: 32)[2..0] &
                        sig(:debug_len0, width: 3)
                    )
                  )
                )
            )
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
      :rd_debug_trigger,
      sig(:read_do, width: 1),
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
      :rd_debug_linear,
      sig(:read_address, width: 32),
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
      :rd_debug_length,
      sig(:read_length, width: 4),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_4,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :rd_debug_b0_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_debug_b0_trigger, width: 1)) do
            assign(
              :rd_debug_b0_reg,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_debug_b0_reg,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :rd_debug_b1_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_debug_b1_trigger, width: 1)) do
            assign(
              :rd_debug_b1_reg,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_debug_b1_reg,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :rd_debug_b2_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_debug_b2_trigger, width: 1)) do
            assign(
              :rd_debug_b2_reg,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_debug_b2_reg,
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
      if_stmt(sig(:rd_ready, width: 1)) do
        assign(
          :rd_debug_b3_reg,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:rd_debug_b3_trigger, width: 1)) do
            assign(
              :rd_debug_b3_reg,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :rd_debug_b3_reg,
          lit(0, width: 1, base: "h", signed: false),
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
