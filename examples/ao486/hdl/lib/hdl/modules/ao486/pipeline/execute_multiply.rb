# frozen_string_literal: true

class ExecuteMultiply < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: execute_multiply

  def self._import_decl_kinds
    {
      __VdfgRegularize_h38aeeee1_0_0: :logic,
      __VdfgRegularize_h38aeeee1_0_1: :logic,
      mult_a: :wire,
      mult_b: :wire,
      mult_counter: :reg,
      mult_start: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :exe_reset
  input :exe_cmd, width: 7
  input :exe_is_8bit
  input :exe_operand_16bit
  input :exe_operand_32bit
  input :src, width: 32
  input :dst, width: 32
  output :mult_result, width: 66
  output :mult_busy
  output :exe_mult_overflow

  # Signals

  signal :__VdfgRegularize_h38aeeee1_0_0
  signal :__VdfgRegularize_h38aeeee1_0_1
  signal :mult_a, width: 33
  signal :mult_b, width: 33
  signal :mult_counter, width: 2
  signal :mult_start

  # Assignments

  assign :mult_start,
    (
        (
            lit(0, width: 2, base: "h", signed: false) ==
            sig(:mult_counter, width: 2)
        ) &
        (
            sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) |
            (
                (
                    lit(59, width: 7, base: "h", signed: false) ==
                    sig(:exe_cmd, width: 7)
                ) |
                sig(:__VdfgRegularize_h38aeeee1_0_1, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h38aeeee1_0_0,
    (
        lit(54, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :__VdfgRegularize_h38aeeee1_0_1,
    (
        lit(31, width: 7, base: "h", signed: false) ==
        sig(:exe_cmd, width: 7)
    )
  assign :mult_busy,
    (
        lit(1, width: 2, base: "h", signed: false) !=
        sig(:mult_counter, width: 2)
    )
  assign :mult_a,
    mux(
      sig(:exe_is_8bit, width: 1),
      (
          sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
          sig(:src, width: 32)[7]
      ).replicate(
        lit(25, width: 32, base: "h", signed: true)
      ).concat(
        sig(:src, width: 32)[7..0]
      ),
      mux(
        sig(:exe_operand_16bit, width: 1),
        (
            sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
            sig(:src, width: 32)[15]
        ).replicate(
          lit(17, width: 32, base: "h", signed: true)
        ).concat(
          sig(:src, width: 32)[15..0]
        ),
        (
            sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
            sig(:src, width: 32)[31]
        ).concat(
          sig(:src, width: 32)
        )
      )
    )
  assign :mult_b,
    mux(
      sig(:__VdfgRegularize_h38aeeee1_0_1, width: 1),
      lit(0, width: 25, base: "d", signed: false).concat(
        sig(:dst, width: 32)[15..8]
      ),
      mux(
        sig(:exe_is_8bit, width: 1),
        (
            sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
            sig(:dst, width: 32)[7]
        ).replicate(
          lit(25, width: 32, base: "h", signed: true)
        ).concat(
          sig(:dst, width: 32)[7..0]
        ),
        mux(
          sig(:exe_operand_16bit, width: 1),
          (
              sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
              sig(:dst, width: 32)[15]
          ).replicate(
            lit(17, width: 32, base: "h", signed: true)
          ).concat(
            sig(:dst, width: 32)[15..0]
          ),
          (
              sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
              sig(:dst, width: 32)[31]
          ).concat(
            sig(:dst, width: 32)
          )
        )
      )
    )
  assign :exe_mult_overflow,
    (
        (
            sig(:exe_is_8bit, width: 1) &
            (
                sig(:mult_result, width: 66)[65..8] !=
                (
                    sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
                    sig(:mult_result, width: 66)[7]
                ).replicate(
                lit(58, width: 32, base: "h", signed: true)
              )
            )
        ) |
        (
            (
                sig(:exe_operand_16bit, width: 1) &
                (
                    sig(:mult_result, width: 66)[65..16] !=
                    (
                        sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
                        sig(:mult_result, width: 66)[15]
                    ).replicate(
                    lit(50, width: 32, base: "h", signed: true)
                  )
                )
            ) |
            (
                sig(:exe_operand_32bit, width: 1) &
                (
                    sig(:mult_result, width: 66)[65..32] !=
                    (
                        sig(:__VdfgRegularize_h38aeeee1_0_0, width: 1) &
                        sig(:mult_result, width: 66)[31]
                    ).replicate(
                    lit(34, width: 32, base: "h", signed: true)
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
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:exe_reset, width: 1)) do
        assign(
          :mult_counter,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:mult_start, width: 1)) do
            assign(
              :mult_counter,
              lit(2, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt((lit(0, width: 2, base: "h", signed: false) != sig(:mult_counter, width: 2))) do
                assign(
                  :mult_counter,
                  (
                      sig(:mult_counter, width: 2) -
                      lit(1, width: 2, base: "h", signed: false)
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
          :mult_counter,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

  # Instances

  instance :mult_inst, "simple_mult__W21_WB21_WC42",
    ports: {
      a: :mult_a,
      b: :mult_b,
      out: :mult_result
    }

end
