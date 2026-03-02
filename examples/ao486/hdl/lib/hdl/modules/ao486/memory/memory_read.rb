# frozen_string_literal: true

class MemoryRead < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: memory_read

  def self._import_decl_kinds
    {
      __VdfgRegularize_h894b88fd_0_0: :logic,
      __VdfgRegularize_h894b88fd_0_1: :logic,
      __VdfgRegularize_h894b88fd_0_2: :logic,
      address_2: :wire,
      address_2_reg: :reg,
      buffer: :reg,
      left_in_line: :wire,
      length_1: :wire,
      length_1_save: :reg,
      length_2: :wire,
      length_2_reg: :reg,
      merged: :wire,
      read_data_next: :reg,
      read_done_next: :reg,
      reset_waiting: :reg,
      state: :reg
    }
  end

  # Parameters

  generic :STATE_IDLE, default: "2'h0"
  generic :STATE_WAIT, default: "2'h1"
  generic :STATE_FIRST, default: "2'h2"
  generic :STATE_SECOND, default: "2'h3"

  # Ports

  input :clk
  input :rst_n
  input :rd_reset
  input :read_do
  output :read_done
  output :read_page_fault
  output :read_ac_fault
  input :read_cpl, width: 2
  input :read_address, width: 32
  input :read_length, width: 4
  input :read_lock
  input :read_rmw
  output :read_data, width: 64
  output :tlbread_do
  input :tlbread_done
  input :tlbread_page_fault
  input :tlbread_ac_fault
  input :tlbread_retry
  output :tlbread_cpl, width: 2
  output :tlbread_address, width: 32
  output :tlbread_length, width: 4
  output :tlbread_length_full, width: 4
  output :tlbread_lock
  output :tlbread_rmw
  input :tlbread_data, width: 64

  # Signals

  signal :__VdfgRegularize_h894b88fd_0_0
  signal :__VdfgRegularize_h894b88fd_0_1
  signal :__VdfgRegularize_h894b88fd_0_2
  signal :address_2, width: 32
  signal :address_2_reg, width: 32
  signal :buffer, width: 56
  signal :left_in_line, width: 5
  signal :length_1, width: 4
  signal :length_1_save, width: 4
  signal :length_2, width: 4
  signal :length_2_reg, width: 4
  signal :merged, width: 64
  signal :read_data_next, width: 64
  signal :read_done_next
  signal :reset_waiting
  signal :state, width: 2

  # Assignments

  assign :left_in_line,
    (
        lit(16, width: 5, base: "h", signed: false) -
        lit(0, width: 1, base: "d", signed: false).concat(
        sig(:read_address, width: 32)[3..0]
      )
    )
  assign :length_1,
    mux(
      (
          sig(:left_in_line, width: 5) >=
          lit(0, width: 1, base: "d", signed: false).concat(
          sig(:read_length, width: 4)
        )
      ),
      sig(:read_length, width: 4),
      sig(:left_in_line, width: 5)[3..0]
    )
  assign :length_2,
    (
        sig(:read_length, width: 4) -
        sig(:length_1, width: 4)
    )
  assign :address_2,
    (
        lit(16, width: 32, base: "h", signed: false) +
        sig(:read_address, width: 32)[31..4].concat(
        lit(0, width: 4, base: "h", signed: false)
      )
    )
  assign :tlbread_length_full,
    sig(:read_length, width: 4)
  assign :merged,
    case_select(
      sig(:length_1_save, width: 4),
      cases: {
        1 => sig(:tlbread_data, width: 64)[55..0].concat(sig(:buffer, width: 56)[7..0]),
        2 => sig(:tlbread_data, width: 64)[47..0].concat(sig(:buffer, width: 56)[15..0]),
        3 => sig(:tlbread_data, width: 64)[39..0].concat(sig(:buffer, width: 56)[23..0]),
        4 => sig(:tlbread_data, width: 64)[31..0].concat(sig(:buffer, width: 56)[31..0]),
        5 => sig(:tlbread_data, width: 64)[23..0].concat(sig(:buffer, width: 56)[39..0]),
        6 => sig(:tlbread_data, width: 64)[15..0].concat(sig(:buffer, width: 56)[47..0])
      },
      default: sig(:tlbread_data, width: 64)[7..0].concat(
        sig(:buffer, width: 56)
      )
    )
  assign :tlbread_address,
    mux(
      sig(:__VdfgRegularize_h894b88fd_0_0, width: 1),
      sig(:address_2_reg, width: 32),
      sig(:read_address, width: 32)
    )
  assign :__VdfgRegularize_h894b88fd_0_0,
    (
        lit(3, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :tlbread_length,
    mux(
      sig(:__VdfgRegularize_h894b88fd_0_0, width: 1),
      sig(:length_2_reg, width: 4),
      sig(:length_1, width: 4)
    )
  assign :tlbread_do,
    (
        (
            (
                lit(0, width: 2, base: "h", signed: false) ==
                sig(:state, width: 2)
            ) &
            (
                sig(:read_do, width: 1) &
                (
                    (
                      ~(
                          sig(:read_ac_fault, width: 1) |
                          sig(:read_page_fault, width: 1)
                      )
                    ) &
                    (
                        (
                          ~sig(:read_done_next, width: 1)
                        ) &
                        sig(:__VdfgRegularize_h894b88fd_0_1, width: 1)
                    )
                )
            )
        ) |
        (
            sig(:__VdfgRegularize_h894b88fd_0_2, width: 1) |
            (
                (
                    lit(2, width: 2, base: "h", signed: false) ==
                    sig(:state, width: 2)
                ) |
                sig(:__VdfgRegularize_h894b88fd_0_0, width: 1)
            )
        )
    )
  assign :__VdfgRegularize_h894b88fd_0_1,
    (
      ~sig(:rd_reset, width: 1)
    )
  assign :__VdfgRegularize_h894b88fd_0_2,
    (
        lit(1, width: 2, base: "h", signed: false) ==
        sig(:state, width: 2)
    )
  assign :read_done,
    (
        (
            sig(:__VdfgRegularize_h894b88fd_0_2, width: 1) &
            (
                (
                  ~(
                      sig(:tlbread_page_fault, width: 1) |
                      (
                          sig(:tlbread_ac_fault, width: 1) |
                          (
                              sig(:reset_waiting, width: 1) &
                              sig(:tlbread_retry, width: 1)
                          )
                      )
                  )
                ) &
                (
                    sig(:tlbread_done, width: 1) &
                    (
                        sig(:__VdfgRegularize_h894b88fd_0_1, width: 1) &
                        (
                          ~sig(:reset_waiting, width: 1)
                        )
                    )
                )
            )
        ) |
        sig(:read_done_next, width: 1)
    )
  assign :read_data,
    mux(
      sig(:__VdfgRegularize_h894b88fd_0_2, width: 1),
      sig(:tlbread_data, width: 64),
      sig(:read_data_next, width: 64)
    )
  assign :tlbread_cpl,
    sig(:read_cpl, width: 2)
  assign :tlbread_lock,
    sig(:read_lock, width: 1)
  assign :tlbread_rmw,
    sig(:read_rmw, width: 1)

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    assign(
      :length_1_save,
      sig(:length_1, width: 4),
      kind: :nonblocking
    )
  end

  process :sequential_posedge_clk_2,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt((sig(:rd_reset, width: 1) & (lit(0, width: 2, base: "h", signed: false) != sig(:state, width: 2)))) do
        assign(
          :reset_waiting,
          lit(1, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((lit(0, width: 2, base: "h", signed: false) == sig(:state, width: 2))) do
            assign(
              :reset_waiting,
              lit(0, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :reset_waiting,
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
      if_stmt(sig(:rd_reset, width: 1)) do
        assign(
          :read_page_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:tlbread_page_fault, width: 1) & (~sig(:reset_waiting, width: 1)))) do
            assign(
              :read_page_fault,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :read_page_fault,
          lit(0, width: 1, base: "h", signed: false),
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
      if_stmt(sig(:rd_reset, width: 1)) do
        assign(
          :read_ac_fault,
          lit(0, width: 1, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt((sig(:tlbread_ac_fault, width: 1) & (~sig(:reset_waiting, width: 1)))) do
            assign(
              :read_ac_fault,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :read_ac_fault,
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
      assign(
        :read_done_next,
        lit(0, width: 1, base: "h", signed: false),
        kind: :nonblocking
      )
      case_stmt(sig(:state, width: 2)) do
        when_value(lit(0, width: 2, base: "h", signed: false)) do
          assign(
            :length_2_reg,
            sig(:length_2, width: 4),
            kind: :nonblocking
          )
          assign(
            :address_2_reg,
            sig(:address_2, width: 32)[31..4].concat(
              lit(0, width: 4, base: "h", signed: false)
            ),
            kind: :nonblocking
          )
          if_stmt(((((sig(:read_do, width: 1) & (~sig(:read_done_next, width: 1))) & (~sig(:rd_reset, width: 1))) & (~sig(:read_page_fault, width: 1))) & (~sig(:read_ac_fault, width: 1)))) do
            if_stmt((lit(0, width: 4, base: "h", signed: false) == sig(:length_2, width: 4))) do
              assign(
                :state,
                lit(1, width: 2, base: "h", signed: false),
                kind: :nonblocking
              )
              else_block do
                assign(
                  :state,
                  lit(2, width: 2, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
        when_value(lit(1, width: 2, base: "h", signed: false)) do
          if_stmt(((sig(:tlbread_page_fault, width: 1) | sig(:tlbread_ac_fault, width: 1)) | (sig(:tlbread_retry, width: 1) & sig(:reset_waiting, width: 1)))) do
            assign(
              :state,
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:tlbread_done, width: 1)) do
                assign(
                  :state,
                  lit(0, width: 2, base: "h", signed: false),
                  kind: :nonblocking
                )
                assign(
                  :read_data_next,
                  sig(:tlbread_data, width: 64),
                  kind: :nonblocking
                )
              end
            end
          end
        end
        when_value(lit(2, width: 2, base: "h", signed: false)) do
          if_stmt(((sig(:tlbread_page_fault, width: 1) | sig(:tlbread_ac_fault, width: 1)) | (sig(:tlbread_retry, width: 1) & sig(:reset_waiting, width: 1)))) do
            assign(
              :state,
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:tlbread_done, width: 1)) do
                assign(
                  :buffer,
                  sig(:tlbread_data, width: 64)[55..0],
                  kind: :nonblocking
                )
                assign(
                  :state,
                  lit(3, width: 2, base: "h", signed: false),
                  kind: :nonblocking
                )
              end
            end
          end
        end
        when_value(lit(3, width: 2, base: "h", signed: false)) do
          if_stmt((((sig(:tlbread_page_fault, width: 1) | sig(:tlbread_ac_fault, width: 1)) | sig(:tlbread_done, width: 1)) | (sig(:tlbread_retry, width: 1) & sig(:reset_waiting, width: 1)))) do
            assign(
              :state,
              lit(0, width: 2, base: "h", signed: false),
              kind: :nonblocking
            )
          end
          if_stmt(((sig(:tlbread_done, width: 1) & (~sig(:rd_reset, width: 1))) & (~sig(:reset_waiting, width: 1)))) do
            assign(
              :read_done_next,
              lit(1, width: 1, base: "h", signed: false),
              kind: :nonblocking
            )
            assign(
              :read_data_next,
              sig(:merged, width: 64),
              kind: :nonblocking
            )
          end
        end
      end
      else_block do
        assign(
          :state,
          lit(0, width: 2, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

end
