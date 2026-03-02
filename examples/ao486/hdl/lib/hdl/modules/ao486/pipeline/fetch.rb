# frozen_string_literal: true

class Fetch < RHDL::Component
  self._ports = []
  self._signals = []
  self._constants = []
  self._processes = []
  self._assignments = []
  self._instances = []
  self._generics = []

  # source_module: fetch

  def self._import_decl_kinds
    {
      __VdfgRegularize_h7b9f36a4_0_0: :logic,
      __VdfgRegularize_h7b9f36a4_0_1: :logic,
      fetch_count: :reg,
      partial: :wire
    }
  end

  # Ports

  input :clk
  input :rst_n
  input :pr_reset
  input :wr_eip, width: 32
  output :prefetch_eip, width: 32
  output :prefetchfifo_accept_do
  input :prefetchfifo_accept_data, width: 68
  input :prefetchfifo_accept_empty
  output :fetch_valid, width: 4
  output :fetch, width: 64
  output :fetch_limit
  output :fetch_page_fault
  input :dec_acceptable, width: 4

  # Signals

  signal :__VdfgRegularize_h7b9f36a4_0_0
  signal :__VdfgRegularize_h7b9f36a4_0_1
  signal :fetch_count, width: 4
  signal :partial

  # Assignments

  assign :prefetch_eip,
    sig(:wr_eip, width: 32)
  assign :fetch_valid,
    mux(
      (
          sig(:prefetchfifo_accept_empty, width: 1) |
          (
              lit(9, width: 4, base: "h", signed: false) <=
              sig(:prefetchfifo_accept_data, width: 68)[67..64]
          )
      ),
      lit(0, width: 4, base: "h", signed: false),
      (
          sig(:prefetchfifo_accept_data, width: 68)[67..64] -
          sig(:fetch_count, width: 4)
      )
    )
  assign :fetch_limit,
    (
        sig(:__VdfgRegularize_h7b9f36a4_0_0, width: 1) &
        (
            lit(15, width: 4, base: "h", signed: false) ==
            sig(:prefetchfifo_accept_data, width: 68)[67..64]
        )
    )
  assign :__VdfgRegularize_h7b9f36a4_0_0,
    (
      ~sig(:prefetchfifo_accept_empty, width: 1)
    )
  assign :fetch_page_fault,
    (
        sig(:__VdfgRegularize_h7b9f36a4_0_0, width: 1) &
        (
            lit(14, width: 4, base: "h", signed: false) ==
            sig(:prefetchfifo_accept_data, width: 68)[67..64]
        )
    )
  assign :fetch,
    mux(
      sig(:prefetchfifo_accept_empty, width: 1),
      lit(0, width: 64, base: "h", signed: false),
      case_select(
        sig(:fetch_count, width: 4),
        cases: {
          0 => sig(:prefetchfifo_accept_data, width: 68)[63..0],
          1 => lit(0, width: 8, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..8]),
          2 => lit(0, width: 16, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..16]),
          3 => lit(0, width: 24, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..24]),
          4 => lit(0, width: 32, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..32]),
          5 => lit(0, width: 40, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..40]),
          6 => lit(0, width: 48, base: "d", signed: false).concat(sig(:prefetchfifo_accept_data, width: 68)[63..48])
        },
        default: lit(0, width: 56, base: "d", signed: false).concat(
          sig(:prefetchfifo_accept_data, width: 68)[63..56]
        )
      )
    )
  assign :prefetchfifo_accept_do,
    (
        (
            sig(:dec_acceptable, width: 4) >=
            sig(:fetch_valid, width: 4)
        ) &
        sig(:__VdfgRegularize_h7b9f36a4_0_1, width: 1)
    )
  assign :__VdfgRegularize_h7b9f36a4_0_1,
    (
        sig(:__VdfgRegularize_h7b9f36a4_0_0, width: 1) &
        (
            lit(9, width: 4, base: "h", signed: false) >
            sig(:prefetchfifo_accept_data, width: 68)[67..64]
        )
    )
  assign :partial,
    (
        (
            sig(:dec_acceptable, width: 4) <
            sig(:fetch_valid, width: 4)
        ) &
        sig(:__VdfgRegularize_h7b9f36a4_0_1, width: 1)
    )

  # Processes

  process :sequential_posedge_clk,
    sensitivity: [
      { edge: "posedge", signal: sig(:clk, width: 1) }
    ],
    clocked: true,
    initial: false do
    if_stmt(sig(:rst_n, width: 1)) do
      if_stmt(sig(:pr_reset, width: 1)) do
        assign(
          :fetch_count,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
        else_block do
          if_stmt(sig(:prefetchfifo_accept_do, width: 1)) do
            assign(
              :fetch_count,
              lit(0, width: 4, base: "h", signed: false),
              kind: :nonblocking
            )
            else_block do
              if_stmt(sig(:partial, width: 1)) do
                assign(
                  :fetch_count,
                  (
                      sig(:fetch_count, width: 4) +
                      sig(:dec_acceptable, width: 4)
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
          :fetch_count,
          lit(0, width: 4, base: "h", signed: false),
          kind: :nonblocking
        )
      end
    end
  end

end
